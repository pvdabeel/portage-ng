/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2020, Pieter Van den Abeele

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
:- dpublic(manifest/4).

:- dpublic(query/2).

:- dpublic(get_location/1).
:- dpublic(get_cache/1).
:- dpublic(get_remote/1).
:- dpublic(get_type/1).
:- dpublic(get_protocol/1).
:- dpublic(get_size/1).
:- dpublic(get_ebuild/2).


:- dpublic(find_metadata/5).
:- dpublic(find_manifest/3).

:- dpublic(read_time/1).
:- dpublic(read_time/1).


% protected interface

:- dprotected(read_metadata/3).
:- dpublic(read_manifest/5).

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
  message:wrap(Repository:sync(kb)),!.


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
% Regenerates cache metadata inside the local repository files by invoking a
% script

sync(metadata) ::-
  ::type('eapi'),!,
  forall((:entry(Id,Time),
           :get_ebuild(Id,Ebuild),
           system:time_file(Ebuild,Modified),
           Modified > Time),
          (message:scroll([Id]))),
           % script:exec(cache,[Ebuild]),!)).
  message:inform(['Updated metadata']).


sync(metadata) ::-
  ::type(Type),!,
  ::location(Local),
  ::remote(Remote),
  ::cache(Cache),
  :this(Repository),
  script:exec(cache,[Type,Repository,Remote,Local,Cache]),
  message:inform(['Updated metadata']).


%! repository:sync(kb)
%
% Public predicate
%
% Regenerates prolog facts from the local repository cache metadata

sync(kb) ::-
  :this(Repository),
  forall(:find_metadata(E,T,C,N,V),
         (:read_metadata(E,T,M),
          retractall(cache:entry(Repository,E,_,_,_,_)),
          retractall(cache:entry_metadata(Repository,E,_,_)),
          asserta(cache:entry(Repository,E,T,C,N,V)),
          forall(member(L,M),
                 (L=..[Key,Value],
                  forall(member(I,Value),
                         assertz(cache:entry_metadata(Repository,E,Key,I))))),
          message:scroll([E]))),
  forall(:find_manifest(P,C,N),
         (:read_manifest(P,T,C,N,M),
          retractall(cache:manifest(Repository,P,_,_,_,_)),
          assertz(cache:manifest(Repository,P,T,C,N,M)),
          message:scroll([P]))),!,
  message:inform(['Updated prolog knowledgebase']).


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
  system:time_file(File,Timestamp).


%! repository:find_manifest(?Manifest, -Category, -Name)
%
% Public predicate
%
% Retrieves manifest infofmration
% Disk access required

find_manifest(Entry,Category,Name) ::-
  ::location(Location),
  ::cache(Cache),
  catch((
   os:directory_content(Cache,Category),
   os:compose_path(Location,Category,CategoryDir),
   os:directory_content(CategoryDir,Name),
   os:compose_path(CategoryDir,Name,PackageDir),
   exists_directory(PackageDir),
   os:compose_path(PackageDir,'Manifest',Entry)),_,
  fail).


%! repository:read_metadata(+Entry, -Timestamp, -Metadata)
%
% Public predicate
%
% Reads the metadata for a given entry from disk if
% it is new of has been modifed

%read_metadata(Entry,Timestamp,Metadata) ::-
%  :this(Repository),
%  cache:entry(Repository,Entry,Timestamp,_,_,_,Metadata),!.

read_metadata(Entry,_,Metadata) ::-
  ::cache(Cache),
  message:scroll([Entry]),
  reader:invoke(Cache,Entry,Contents),
  parser:invoke(metadata,Contents,Metadata),!.

read_metadata(Entry,_,[]) ::-
  message:failure(['Failed to parse ',Entry,' metadata cache!']),!.


%! repository:read_manifest(+Path, +Category, +Name, -Manifest)
%
% Public predicate
%
% Reads the manifest for a given path from disk if
% it is new of has been modifed

read_manifest(Path,Timestamp,Category,Name,Manifest) ::-
  :this(Repository),
  cache:manifest(Repository,Path,Timestamp,Category,Name,Manifest),!.

read_manifest(Path,_,_,_,Manifest) ::-
  message:scroll([Path]),
  reader:invoke(Path,Contents),
  parser:invoke(manifest,Contents,Manifest),!.

read_manifest(Entry,_,_,_,[]) ::-
  message:failure(['Failed to parse ',Entry,' metadata cache!']),!.


%! repository:read_time(-Time)
%
% Public predicate
%
% Time is a float, representing the time last synced

read_time(Time) ::-
  ::location(Location),
  os:compose_path(Location,'metadata/timestamp.x',File),
  reader:read_timestamp(File,Time).


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
  findall(C,cache:entry(Repository,_,_,C,_,_),Cs),
  sort(Cs,Ss),!,
  member(Category,Ss).


%! repository:package(?Category, ?Package)
%
% Public predicate
%
% Retrieves metadata cache package
% No disk access - initial sync required

package(Category,Package) ::-
  :this(Repository),
  cache:entry(Repository,_,_,Category,Name,Version),
  atomic_list_concat([Name,'-',Version],Package).


%! repository:ebuild(?Category, ?Name, ?Version)
%
% Public predicate
%
% Retrieves metadata cache ebuild
% No disk access - initial sync required

ebuild(Category,Name,Version) ::-
  :this(Repository),
  cache:entry(Repository,_,_,Category,Name,Version).


%! repository:ebuild(?Id, ?Category, ?Name, ?Version)
%
% Public predicate
%
% Retrieves metadata cache ebuild
% No disk access - initial sync required

ebuild(Id,Category,Name,Version) ::-
  :this(Repository),
  cache:entry(Repository,Id,_,Category,Name,Version).


%! repository:ebuild(?Id, ?Category, ?Name, ?Version, ?Key, ?Value)
%
% Public predicate
%
% Retrieves metadata cache ebuild
% No disk access - initial sync required

ebuild(Id,Category,Name,Version,Key,Value) ::-
  :this(Repository),
  cache:entry(Repository,Id,_,Category,Name,Version),
  cache:entry_metadata(Repository,Id,Key,Value).


%! repository:manifest(?Id, ?Type, ?Filename, ?Size, ?Hash)
%
% Public predicate
%
% Retrieves manifest data
% No disk access - initial sync required

manifest(Id,Category,Name,Manifest) ::-
  :this(Repository),
  cache:manifest(Repository,Id,_,Category,Name,Manifest).


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
% to a portage tree installed on your local system.

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


%! repository:get_type(?Type)
%
% Public predicate
%
% Type is an atom, representing the type of data represented
% in the repository being processed.

get_size(Size) ::-
  :this(Repository),
  findall(E,Repository:entry(E),L),
  length(L,Size).


%! repository:get_ebuild(+Entry,-Ebuild)
%
% Public predicate
%
% For a given entry, retrieves the full path to the corresponding ebuild

get_ebuild(Entry,Ebuild) ::-
  ::location(Location),
  :ebuild(Entry,Category,Name,Version),
  atomic_list_concat([Location,'/',Category,'/',Name,'/',Name,'-',Version,'.ebuild'],Ebuild),
  exists_file(Ebuild).


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
