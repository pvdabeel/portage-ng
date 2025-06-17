/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2025, Pieter Van den Abeele

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

:- dpublic(find_category/1).
:- dpublic(find_metadata/5).
:- dpublic(find_manifest/4).
:- dpublic(find_ebuild/5).

:- dpublic(read_time/1).
:- dpublic(read_metadata/3).
:- dpublic(read_manifest/5).
:- dpublic(read_ebuild/2).
:- dpublic(read_ebuild/3).

:- dpublic(graph/0).
:- dpublic(prepare_directory/1).


% private interface

:- dpublic(update_metadata/2).
:- dpublic(update_cache/0).

% protected interface

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
% with remote repository (e.g. git / rsync / http tarball / ...)

sync(repository) ::-
  ::location(Local),
  ::remote(Remote),
  ::protocol(Protocol),
  script:exec(sync,[Protocol,Remote,Local],[],Stream),
  copy_stream_data(Stream,current_output),
  !.


%! repository:sync(+Metadata)
%
% Public predicate
%
% Regenerates cache metadata on disk for all ebuilds files inside the local repository
% by invoking a script. This is an exensive operation. Portage repositories typically
% ship with a prebuilt cache. Use config:trust_metadata to change behaviour. Trusting
% the vendor shipped cache is faster, as only changed ebuilds or ebuilds missing a
% cache entry will have their cache entry on disk regenerated.
%
% For non-eapi repositories, generates on-disk metadata cache by calling a script
% For a git repository, this for example creates a metadata entry for each release.

sync(metadata) ::-
  ::type('eapi'),!,
  %config:number_of_cpus(Cpus),
  message:hc,
  ( config:trust_metadata(false)
    -> (:update_cache,
        concurrent_forall(:find_ebuild(E,_,_,_,_),
                (:read_ebuild(E,Cd,_),
                 :update_metadata(E,Cd),
                  with_mutex(mutex,message:scroll(['Ebuild (local): ',E])))))
    ; true ),
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
% Regenerates prolog facts from the local repository cache

sync(kb) ::-
  :this(Repository),
  message:hc,

  % We sync in parallel

  % config:number_of_cpus(Cpus),

  % Step 1: clean prolog cache

  retractall(cache:repository(Repository)),
  retractall(cache:category(Repository,_)),
  retractall(cache:entry(Repository,_,_,_,_)),
  retractall(cache:package(Repository,_,_)),
  retractall(cache:ordered_entry(Repository,_,_,_,_)),
  retractall(cache:entry_metadata(Repository,_,_,_)),
  retractall(cache:manifest(Repository,_,_,_,_)),
  retractall(cache:manifest_metadata(Repository,_,_,_,_,_)),

  % Step 2: update prolog cache:entry and cache:entry_metadata facts

  % Step 2.a: read repository cache

  concurrent_forall(:find_metadata(E,T,C,N,V),
          (:read_metadata(E,T,M),
           with_mutex(mutex,message:scroll(['Ebuild: ',E])),
           assertz(cache:entry(Repository,E,C,N,V)),
           assertz(cache:entry_metadata(Repository,E,timestamp,T)),
           forall(member(L,M),
                  (L=..[Key,Value],
                   forall(member(I,Value),
                          assertz(cache:entry_metadata(Repository,E,Key,I))))))),

  % Step 2.b: read ebuilds without repository cache

  (config:write_metadata(true) -> :update_cache ; true),

  concurrent_forall((:find_ebuild(E,T,C,N,V),\+(cache:entry_metadata(Repository,E,_,_))),
          (:read_ebuild(E,Cd,M),
           with_mutex(mutex,message:scroll(['Ebuild (local): ',E])),
           assertz(cache:entry(Repository,E,C,N,V)),
           assertz(cache:entry_metadata(Repository,E,timestamp,T)),
           assertz(cache:entry_metadata(Repository,E,local,true)),
           forall(member(L,M),
                  (L=..[Key,Value],
                   forall(member(I,Value),
                          assertz(cache:entry_metadata(Repository,E,Key,I))))),
           (config:write_metadata(true) -> :update_metadata(E,Cd) ; true))),


  % Step 2.c: read ebuilds with outdated repository cache

  concurrent_forall((:find_ebuild(E,TE,C,N,V),cache:entry_metadata(Repository,E,timestamp,TC), TE > TC + 60), % time writing to disk
          (:read_ebuild(E,Cd,M),
           with_mutex(mutex,message:scroll(['Ebuild (changed): ',E])),
           assertz(cache:entry(Repository,E,C,N,V)),
           assertz(cache:entry_metadata(Repository,E,timestamp,T)),
           assertz(cache:entry_metadata(Repository,E,changed,true)),
           forall(member(L,M),
                  (L=..[Key,Value],
                   forall(member(I,Value),
                          assertz(cache:entry_metadata(Repository,E,Key,I))))),
           (config:write_metadata(true) -> :update_metadata(E,Cd) ; true))),


  % Step 3: update prolog cache:manifest facts for manifests in the repository

  concurrent_forall(:find_manifest(P,T,C,N),
          (:read_manifest(P,T,C,N,M),
           with_mutex(mutex,message:scroll(['Manifest: ',P])),
           assertz(cache:manifest(Repository,P,T,C,N)),
           forall(member(manifest(Filetype,Filename,Filesize,Checksums),M),
                 assertz(cache:manifest_metadata(Repository,P,Filetype,Filename,Filesize,Checksums))))),


  % Step 4: Ordered prolog cache:category creation

  findall(Ca,cache:entry(Repository,_,Ca,_,_),Cu),
  sort(Cu,Cs),
  forall(member(Ca,Cs),
         assertz(cache:category(Repository,Ca))),


  % Step 5:
  %
  % We create a unique prolog cache:package and create cache:ordered_entry.
  % The cache package allows us to retrieve individual package names efficiently.
  % (without duplicates). We impose an ordering on cache:entry using
  % the versions of a given package.
  %
  % By default we prefer newer versions over older versions. We sort category, and
  % package alphabetically, then order versions using EAPI version sorting specs.
  % The ordered entries are stored in the cache, from which facts will later be
  % retrieved in the right order, avoiding costly sorting or list traversals.

  findall([Ca,Pa],cache:entry(Repository,_,Ca,Pa,_),Pu),
  sort(Pu,Ps),
  forall(member([Ca,Pa],Ps),
         (findall([Vn,Va,Vs,Vf,Id],
                  (cache:entry(Repository,Id,Ca,Pa,[Vn,Va,Vs,Vf])),
                   % eapi:version2numberlist(Vn,Vl)),
                  Vu),
          sort(0,@>=,Vu,Vs),
          ( assertz(cache:package(Repository,Ca,Pa)),
            forall(member([OVn,OVa,OVs,OVf,OrderedId],Vs),
                 assertz(cache:ordered_entry(Repository,OrderedId,Ca,Pa,[OVn,OVa,OVs,OVf])))))),

  % Step 6 : We retract the original unordered prolog cache entries.

  retractall(cache:entry(Repository,_,_,_,_)),

  % Step 7: We end by creating a prolog cache:repository

  assertz(cache:repository(Repository)),

  message:sc,
  message:scroll(['Updated prolog knowledgebase.']),nl,
  message:clean.


%! repository:find_category(?Category)
%
% Public predicate
%
% Retrieves category, directly from the on-disk repository

find_category(Category) ::-
  ::location(Location),
  os:directory_content(Location,Category),
  os:compose_path(Location,Category,Path),
  os:contains('metadata.xml',Path).


%! repository:find_metadata(?Entry, -Timestamp, -Category, -Name, -Version)
%
% Public predicate
%
% Retrieves metadata cache entry, and the last modified date
% of the cache entry, its category, name and version.
% Disk access required.

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
% Retrieves manifest information.
% Disk access required.

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


%! repository:find_ebuild(?Entry, -Timestamp, -Category, -Name, -Version)
%
% Public predicate
%
% Find ebuild file in repository.
% Disk access required.

find_ebuild(Entry,Timestamp,Category,Name,Version) ::-
  ::location(Location),
  os:directory_content(Location,Category),
  os:compose_path(Location,Category,CategoryDir),
  os:directory_content(CategoryDir,Name),
  os:compose_path(CategoryDir,Name,NameDir),
  os:directory_content(NameDir,Ebuild),
  system:file_name_extension(Package,'ebuild',Ebuild),
  os:compose_path(Category,Package,Entry),
  eapi:packageversion(Package,Name,Version),
  os:compose_path(NameDir,Ebuild,EbuildFile),
  system:time_file(EbuildFile,Timestamp).


%! repository:read_metadata(+Entry, -Timestamp, -Metadata)
%
% Public predicate
%
% Reads the metadata for a given entry from the metadata cache
% inside the repository on and update it if it is new of has
% been modifed.
% Disk access required.

read_metadata(Entry,Timestamp,[]) ::-
  :this(Repository),
  cache:ordered_entry(Repository,Entry,_,_,_),
  cache:entry_metadata(Repository,Entry,timestamp,Timestamp),!,
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
% it is new of has been modifed.
% Disk access required.

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


%! repository:read_ebuild(?Entry, -Contents, -Metadata))
%
% Public predicate
%
% Reads metadata for a given entry directly from the ebuild file
% bypassing the metadata cache inside the repository.
% Disk access required.

read_ebuild(Entry,Metadata) ::-
  read_ebuild(Entry,_,Metadata).

read_ebuild(Entry,Codes,Metadata) ::-
  :this(Repository),
  ::location(Location),
  ebuild:invoke(cache,Location,Entry,Stream),
  reader:invoke(Stream,Codes),
  parser:invoke(metadata,Repository://Entry,Codes,Metadata),!.


%! repository:update_metadata(+Entry, +Codes)
%
% Private predicate
%
% Update the repository on-disk cache with codes
% read by the reader from the ebuild.sh stream.
% Cache directory assumed to exist and prepopulated

update_metadata(Entry,Codes) ::-
  ::cache(Cache),
  os:compose_path(Cache,Entry,File),
  tell(File),
  forall(member(Line,Codes),(atom_codes(Atom,Line),writeln(Atom))),
  told.


%! repository:update_cace
%
% Private predicate
%
% Creates a category structure in the on-disk cache.

update_cache ::-
  ::cache(Cache),
  forall(:find_category(Category),
         (os:compose_path(Cache,Category,Path),
          os:make_directory(Path))).


%! repository:read_time(-Time)
%
% Public predicate
%
% Time is a float, representing the time last synced
% Disk access required.

read_time(Time) ::-
  ::location(Location),
  os:compose_path(Location,'metadata/timestamp.chk',File),
  system:time_file(File,Time).


%! repository:prepare_directory(D)
%
% Public predicate
%
% Creates or updates the repository directory structure

prepare_directory(D) ::-
  :this(Repository),
  config:hostname(H),
  config:graph_directory(H,G),
  os:compose_path(G,Repository,D),
  system:exists_directory(D),!,
  message:scroll_notice(['Directory already exists! Updating...']),
  pkg:create_repository_dirs(Repository,D).

prepare_directory(D) ::-
  :this(Repository),
  config:hostname(H),
  config:graph_directory(H,G),
  os:compose_path(G,Repository,D),
  \+(system:exists_directory(D)),!,
  message:scroll_notice(['Directory does not exist! Creating...']),
  pkg:make_repository_dirs(Repository,D).


%! repository:graph
%
% Creates graph and proof files for the repository

graph ::-
  :this(Repository),
  atomic_concat(graph,Repository,Mutex),
  with_mutex(Mutex,
    (:prepare_directory(D),
     grapher:write_graph_files(D,Repository),
     grapher:produce_svg(D),
     printer:write_proof_files(D,Repository),
     printer:produce_html(D))).


%! repository:entry(?Entry)
%
% Public predicate
%
% Retrieves metadata cache entry
% No disk access - initial sync required

entry(Entry) ::-
  :this(Repository),
  cache:ordered_entry(Repository,Entry,_,_,_).


%! repository:entry(?Entry, ?Time)
%
% Public predicate
%
% Retrieves metadata cache entry, and the last modified date
% of the cache entry
% No disk access - initial sync required

entry(Entry,Time) ::-
  :this(Repository),
  cache:ordered_entry(Repository,Entry,_,_,_),
  cache:entry_metadata(Repository,Entry,'timestamp',Time).


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
  cache:package(Repository,Category,Package).


%! repository:ebuild(?Category, ?Name, ?Version)
%
% Public predicate
%
% Retrieves metadata cache ebuild
% No disk access - initial sync required

ebuild(Category,Name,Version) ::-
  :this(Repository),
  cache:ordered_entry(Repository,_,Category,Name,[_,_,_,Version]).


%! repository:ebuild(?Id, ?Category, ?Name, ?Version)
%
% Public predicate
%
% Retrieves metadata cache ebuild
% No disk access - initial sync required

ebuild(Id,Category,Name,Version) ::-
  :this(Repository),
  cache:ordered_entry(Repository,Id,Category,Name,[_,_,_,Version]).


%! repository:ebuild(?Id, ?Category, ?Name, ?Version, ?Key, ?Value)
%
% Public predicate
%
% Retrieves metadata cache ebuild
% No disk access - initial sync required

ebuild(Id,Category,Name,Version,Key,Value) ::-
  :this(Repository),
  cache:ordered_entry(Repository,Id,Category,Name,[_,_,_,Version]),
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
  query:search(Query,Repository://Result).


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
