/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2024, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> REPOSITORY
The Repository is a class enabling its instances to manipulate repositories
and the metadata associated with those repositories.

Examples of repositories: Gentoo Portage, Github repositories, ...
*/

:- module(repository,[]).

% ***********************
% REPOSITORY declarations
% ***********************


:- class.

% public interface

:- dpublic('repository'/0).
:- dpublic('~repository'/0).


:- dpublic(init/5).
:- dpublic(sync/0).
:- dpublic(sync/1).


:- dpublic(entry/1).
:- dpublic(entry/2).
:- dpublic(category/1).
:- dpublic(package/2).
:- dpublic(ebuild/3).
:- dpublic(ebuild/4).
:- dpublic(ebuild/6).
:- dpublic(manifest/7).

:- dpublic(query/2).

:- dpublic(get_location/1).
:- dpublic(get_cache/1).
:- dpublic(get_remote/1).
:- dpublic(get_type/1).
:- dpublic(get_protocol/1).
:- dpublic(get_size/1).

:- dpublic(get_ebuild_file/2).
:- dpublic(get_cache_file/2).

% protected interface

:- dprotected(find_metadata/5).
:- dpublic(find_manifest/4).

:- dprotected(read_time/1).
:- dprotected(read_metadata/3).
:- dprotected(read_manifest/5).

:- dprotected(location/1).
:- dprotected(cache/1).
:- dprotected(remote/1).
:- dprotected(type/1).
:- dprotected(protocol/1).


%! Constructor
%
% Public predicate

'repository' ::-
  true.


%! Destructor
%
% Public predicate

'~repository' ::-
  true.


%! repository:init(+Location,+Cache,+Remote,+Protocol,+Type)
%
% Public predicate
%
% Initializes the repository instance with a location,
% remote and type

init(Location,Cache,Remote,Protocol,Type) ::-
  <=location(Location),
  <=cache(Cache),
  <=remote(Remote),
  <=protocol(Protocol),
  <=type(Type),!.


%! repository:sync
%
% Public predicate
%
% Full sync of repository, metadata and rules

sync ::-
  :this(Repository),
  message:wrap(Repository:sync(repository)),
  message:wrap(Repository:sync(metadata)),
  message:wrap(Repository:sync(kb)),nl,!.


%! repository:sync(+Repository)
%
% Public predicate
%
% Updates files in local repository by invoking script to sync local repository
% with remote repository

sync(repository) ::-
  ::location(Local),
  ::remote(Remote),
  ::protocol(Protocol),
  script:exec(sync,[Protocol,Remote,Local]),!.


%! repository:sync(+Metadata)
%
% Public predicate
%
% Regenerates cache metadata for changed files inside the local repository files 
% by invoking a script

sync(metadata) ::-
  ::type('eapi'),!,
  message:hc,
  forall((:entry(Id,Time),
           :get_ebuild_file(Id,Ebuild),
           system:time_file(Ebuild,Modified),
           Modified > Time),
          (message:scroll([Id]))),
           % script:exec(cache,[Ebuild]),!)).
  message:sc,
  message:scroll(['Updated metadata.']),nl.


sync(metadata) ::-
  ::type(Type),!,
  ::location(Local),
  ::remote(Remote),
  ::cache(Cache),
  :this(Repository),
  script:exec(cache,[Type,Repository,Remote,Local,Cache]),
  message:scroll(['Updated metadata.']),nl.


%! repository:sync(kb)
%
% Public predicate
%
% Regenerates prolog facts from the local repository cache metadata

sync(kb) ::-
  :this(Repository),
  message:hc,

  % Step 1: update cache:entry and cache:entry_metadata facts

  forall((:find_metadata(E,T,C,N,V),
          :read_metadata(E,T,M)),
          (message:scroll(['Ebuild: ',E]),
           retractall(cache:entry(Repository,E,_,_,_,_)),
           retractall(cache:entry_metadata(Repository,E,_,_)),
           assert(cache:entry(Repository,E,T,C,N,V)),
           forall(member(L,M),
                  (L=..[Key,Value],
                   forall(member(I,Value),
                   assert(cache:entry_metadata(Repository,E,Key,I))))))),

  % Step 2: update cache:manifest facts for manifests in the repository

  forall((:find_manifest(P,T,C,N),
          :read_manifest(P,T,C,N,M)),
         (message:scroll(['Manifest: ',P]),
          retractall(cache:manifest(Repository,P,_,_,_)),
          assert(cache:manifest(Repository,P,T,C,N)),
          forall(member(manifest(Filetype,Filename,Filesize,Checksums),M),
                 assert(cache:manifest_metadata(Repository,P,Filetype,Filename,Filesize,Checksums))))),

  % re-create cache:repository, cache:category and cache:package facts
  % for the repository. These facts are used by the knowledgebase query
  % mechanism for fast retrieval of metadata, avoidance of sorting versions,
  % etc.

  retractall(cache:repository(Repository)),
  retractall(cache:category(Repository,_)),
  retractall(cache:package(Repository,_,_,_)),

  % Step3: cache:category creation

  findall(Ca,cache:entry(Repository,_,_,Ca,_,_),Cu),
  sort(Cu,Cs),
  forall(member(Ca,Cs),
         assert(cache:category(Repository,Ca))),

  % Step 4: cache:package creation. Here we create an ordering on the versions
  % of a given package. By default we prefer newer versions over older
  % versions. This ordering is stored in the cache, from which facts
  % will be retrieved

  findall([Ca,Pa],cache:entry(Repository,_,_,Ca,Pa,_),Pu),
  sort(Pu,Ps),
  forall(member([Ca,Pa],Ps),
         (findall([Vl,Va,Vs,Vf,Id],
                  (cache:entry(Repository,Id,_,Ca,Pa,[Vn,Va,Vs,Vf]),
                   eapi:version2numberlist(Vn,Vl)),
                  Vu),
          sort(0,@>=,Vu,Vs),
          assert(cache:package(Repository,Ca,Pa,Vs)))),

  % Step 5: cache:repository creation for each repository in the knowledge base

  assert(cache:repository(Repository)),
  message:sc,
  message:scroll(['Updated prolog knowledgebase.']),nl.

%! repository:find_metadata(?Entry, -Timestamp, -Category, -Name, -Version)
%
% Public predicate
%
% Retrieves metadata cache entry, and the last modified date
% of the cache entry, its category, name and version
% Disk access required

find_metadata(Entry,Timestamp,Category,Name,Version) ::-
  ::cache(Cache),!,
  os:directory_content(Cache,Category),
  os:compose_path(Cache,Category,CategoryDir),
  os:directory_content(CategoryDir,Package),
  eapi:packageversion(Package,Name,Version),
  os:compose_path(Category,Package,Entry),
  os:compose_path(Cache,Entry,File),
  exists_file(File),
  system:time_file(File,Timestamp).


%! repository:find_manifest(?Manifest,-Timestamp, -Category, -Name)
%
% Public predicate
%
% Retrieves manifest information
% Disk access required

find_manifest(Entry,Timestamp,Category,Name) ::-
  ::location(Location),
  ::cache(Cache),
  os:directory_content(Cache,Category),
  os:compose_path(Location,Category,CategoryDir),
  exists_directory(CategoryDir),
  os:directory_content(CategoryDir,Name),
  os:compose_path(CategoryDir,Name,PackageDir),
  exists_directory(PackageDir),
  os:compose_path(PackageDir,'Manifest',Entry),
  exists_file(Entry),
  system:time_file(Entry,Timestamp).


%! repository:read_metadata(+Entry, -Timestamp, -Metadata)
%
% Public predicate
%
% Reads the metadata for a given entry from disk if
% it is new of has been modifed

read_metadata(Entry,Timestamp,[]) ::-
  :this(Repository),
  cache:entry(Repository,Entry,Timestamp,_,_,_),!,
  fail.

read_metadata(Entry,_,Metadata) ::-
  :this(Repository),
  ::cache(Cache),
  os:compose_path(Cache,Entry,File),
  reader:invoke(File,Contents),
  parser:invoke(metadata,Repository://Entry,Contents,Metadata),!.

read_metadata(Entry,_,[]) ::-
  message:failure(['Failed to parse ',Entry,' metadata cache!']),
  fail.


%! repository:read_manifest(+Path, +Category, +Name, -Metadata)
%
% Public predicate
%
% Reads the manifest for a given path from disk if
% it is new of has been modifed

read_manifest(Path,Timestamp,Category,Name,[]) ::-
  :this(Repository),
  cache:manifest(Repository,Path,Timestamp,Category,Name),!,
  fail.

read_manifest(Path,_,_,_,Metadata) ::-
  reader:invoke(Path,Contents),
  parser:invoke(manifest,_,Contents,Metadata),!.

read_manifest(Path,_,_,_,[]) ::-
  message:failure(['Failed to parse ',Path,' metadata cache!']),
  fail.


%! repository:read_time(-Time)
%
% Public predicate
%
% Time is a float, representing the time last synced

read_time(Time) ::-
  ::location(Location),
  os:compose_path(Location,'metadata/timestamp.chk',File),
  system:time_file(File,Time).


%! repository:entry(?Entry)
%
% Public predicate
%
% Retrieves metadata cache entry
% No disk access - initial sync required

entry(Entry) ::-
  :this(Repository),
  cache:entry(Repository,Entry,_,_,_,_).


%! repository:entry(?Entry, ?Time)
%
% Public predicate
%
% Retrieves metadata cache entry, and the last modified date
% of the cache entry
% No disk access - initial sync required

entry(Entry,Time) ::-
  :this(Repository),
  cache:entry(Repository,Entry,Time,_,_,_).


%! repository:category(?Category)
%
% Public predicate
%
% Retrieves metadata cache category
% No disk access - initial sync required

category(Category) ::-
  :this(Repository),
  cache:category(Repository,Category).


%! repository:package(?Category,?Packname)
%
% Public predicate
%
% Retrieves package

package(Category,Package) ::-
  :this(Repository),
  cache:package(Repository,Category,Package,_).


%! repository:ebuild(?Category, ?Name, ?Version)
%
% Public predicate
%
% Retrieves metadata cache ebuild
% No disk access - initial sync required

ebuild(Category,Name,Version) ::-
  :this(Repository),
  cache:entry(Repository,_,_,Category,Name,[_,_,_,Version]).


%! repository:ebuild(?Id, ?Category, ?Name, ?Version)
%
% Public predicate
%
% Retrieves metadata cache ebuild
% No disk access - initial sync required

ebuild(Id,Category,Name,Version) ::-
  :this(Repository),
  cache:entry(Repository,Id,_,Category,Name,[_,_,_,Version]).


%! repository:ebuild(?Id, ?Category, ?Name, ?Version, ?Key, ?Value)
%
% Public predicate
%
% Retrieves metadata cache ebuild
% No disk access - initial sync required

ebuild(Id,Category,Name,Version,Key,Value) ::-
  :this(Repository),
  cache:entry(Repository,Id,_,Category,Name,[_,_,_,Version]),
  cache:entry_metadata(Repository,Id,Key,Value).


%! repository:manifest(?Id, ?Type, ?Filename, ?Size, ?Hash)
%
% Public predicate
%
% Retrieves manifest data
% No disk access - initial sync required

manifest(Id,Category,Name,Filetype,Filename,Filesize,Checksums) ::-
  :this(Repository),
  cache:manifest(Repository,Id,_,Category,Name),
  cache:manifest_metadata(Repository,Id,Filetype,Filename,Filesize,Checksums).


%! repository:query(+Query,-Result)
%
% Public predicate
%
% Retrieves metadata cache ebuild that satisfies
% a given query

query(Query,Result) ::-
  :this(Repository),
  knowledgebase:query(Query,Repository://Result).





%! repository:get_location(?Location).
%
% Public predicate
%
% Location is an atom, representing a full absolute path
% to a portage tree i%! repository:count(+Query,-Count)
% installed on your local system.

get_location(Location) ::-
  ::location(Location).


%! repository:get_cache(?Location).
%
% Public predicate
%
% Location is an atom, representing a full absolute path
% to a portage tree cache installed on your local system.

get_cache(Location) ::-
  ::cache(Location).


%! repository:get_remote(?Location).
%
% Public predicate
%
% Location is an atom, representing an uri to a remote
% portage tree.

get_remote(Location) ::-
  ::remote(Location).


%! repository:get_protocol(?Protocol).
%
% Public predicate
%
% Protocol is an atom, representing a protocol to sync
% with the remote portage tree.

get_protocol(Protocol) ::-
  ::protocol(Protocol).


%! repository:get_type(?Type)
%
% Public predicate
%
% Type is an atom, representing the type of data represented
% in the repository being processed.

get_type(Type) ::-
  ::type(Type).


%! repository:get_size(?Size)
%
% Public predicate
%
% Size is an integer, representing the number of entries in a repository

get_size(Size) ::-
  :this(Repository),
  findall(E,Repository:entry(E),L),
  length(L,Size).


%! repository:get_ebuild_file(+Entry,-Ebuild)
%
% Public predicate
%
% For a given entry, retrieves the full path to the corresponding ebuild

get_ebuild_file(Entry,File) ::-
  ::location(Location),
  :ebuild(Entry,Category,Name,Version),
  atomic_list_concat([Location,'/',Category,'/',Name,'/',Name,'-',Version,'.ebuild'],File).


%! repository:get_cache_file(+Entry,-Cache)
%
% Public predicate
%
% For a given entry, retrieves the full path to the corresponding cache file

get_cache_file(Entry,File) ::-
  ::cache(Cache),
  :entry(Entry),
  atomic_list_concat([Cache,'/',Entry],File).


%! repository:location(?Location)
%
% Protected predicate
%
% location is an atom, representing a full absolute path
% to a portage tree installed on your local system

location(Location) ::-
  atom(Location).
  %is_absolute_file_name(Location).


%! repository:cache(?Location)
%
% Protected predicate
%
% location is an atom, representing a full absolute path
% to a portage tree cache installed on your local system

cache(Location) ::-
  atom(Location).
  %is_absolute_file_name(Location).


%! repository:remote(?Location)
%
% Protected predicate
%
% Location is an atom, representing an uri to a remote
% portage tree.

remote(Location) ::-
  atom(Location).
  % is_absolute_url(Location).


%! repository:protocol(?Protocol)
%
% Protected predicate
%
% Protocol is an atom, representing the protocol to
% sync with the remote portage tree.

protocol(Protocol) ::-
  atom(Protocol).
  % member(Protocol,['git','http','rsync']).


%! repository:type(?Type)
%
% Protected predicate
%
% Type is an atom, representing the type of data represented
% in the repository being processed

type(Type) ::-
  atom(Type).
