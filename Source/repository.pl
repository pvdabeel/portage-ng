/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2019, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> REPOSITORY
The Repository is a collection of metadata which can be synced, queried, etc.
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
:- dpublic(ebuild/5).

:- dpublic(query/2).

:- dpublic(get_location/1).
:- dpublic(get_cache/1).
:- dpublic(get_remote/1).
:- dpublic(get_type/1).
:- dpublic(get_protocol/1).
:- dpublic(get_size/1).
:- dpublic(get_ebuild/2).


:- dpublic(read_entry/5).
:- dpublic(read_time/1).


% protected interface

:- dprotected(read_metadata/3).

:- dprotected(location/1).
:- dprotected(cache/1).
:- dprotected(remote/1).
:- dprotected(type/1).
:- dprotected(protocol/1).


%! Constructor
%
% public predicate

'repository' ::-
  true.


%! Destructor
%
% public predicate

'~repository' ::-
  true.


%! repository:init(+Location,+Cache,+Remote,+Protocol,+Type)
%
% public predicate
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
% public predicate
%
% Full sync of repository, metadata and rules

sync ::-
  :this(Context),
  message:wrap(Context:sync(repository)),
  message:wrap(Context:sync(metadata)),
  message:wrap(Context:sync(kb)),!.


%! repository:sync(+Repository)
%
% public predicate
%
% Updates files in local repository by invoking script to sync with remote

sync(repository) ::-
  ::location(Local),
  ::remote(Remote),
  ::protocol(Protocol),
  script:exec(sync,[Protocol,Remote,Local]),!.


%! repository:sync(+Metadata)
%
% public predicate
%
% Regenerates metadata from local repository files by invoking script

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
  :this(Context),
  script:exec(cache,[Type,Context,Remote,Local,Cache]),
  message:inform(['Updated metadata']).



% repository:sync(kb)
%
% public predicate
%
% Regenerates knowledgebase facts from local repository metadata

sync(kb) ::-
  :this(Context),
  forall(:read_entry(E,L,C,N,V),
         (:read_metadata(E,L,M),
          retractall(cache:entry(Context,E,_,_,_,_,_)),
          assert(cache:entry(Context,E,L,C,N,V,M)),
          message:scroll([E]))),
  message:inform(['Updated prolog knowledgebase']).



% repository:read_entry(+Entry, -Timestamp, -Category, -Name, -Version)
%
% public predicate
%
% Retrieves metadata cache entry, and the last modified date
% of the cache entry, its category, name and version
% Disk access required

read_entry(Entry,Timestamp,Category,Name,Version) ::-
  ::cache(Cache),!,
  os:directory_content(Cache,Category),
  os:compose_path(Cache,Category,CategoryDir),
  os:directory_content(CategoryDir,Package),
  eapi:packageversion(Package,Name,Version),       % BUG
  os:compose_path(Category,Package,Entry),
  os:compose_path(Cache,Entry,File),
  system:time_file(File,Timestamp).

% read_metadata(Entry,Timestamp,Metadata).


% repository:read_metadata(+Entry, -Timestamp, -Metadata)
%
% public predicate
%
% Reads the metadata for a given entry from disk if
% it is new of has been modifed

read_metadata(Entry,Timestamp,Metadata) ::-
  :this(Context),
  cache:entry(Context,Entry,Timestamp,_,_,_,Metadata),!.

read_metadata(Entry,_,Metadata) ::-
  ::cache(Cache),
  message:scroll([Entry]),
  reader:invoke(Cache,Entry,Contents),
  parser:invoke(Contents,Metadata),!.

read_metadata(Entry,_,[]) ::-
  message:failure(['Failed to parse ',Entry,' metadata cache!']),!.


% repository:read_time(-Time)
%
% public predicate
%
% Time is a float, representing the time last synced

read_time(Time) ::-
  ::location(Location),
  os:compose_path(Location,'metadata/timestamp.x',File),
  reader:read_timestamp(File,Time).


% repository:entry(?Entry)
%
% public predicate
%
% Retrieves metadata cache entry
% No disk access - initial sync required

entry(Entry) ::-
  :this(Context),
  cache:entry(Context,Entry,_,_,_,_,_).


% repository:entry(?Entry, ?Time)
%
% public predicate
%
% Retrieves metadata cache entry, and the last modified date
% of the cache entry
% No disk access - initial sync required

entry(Entry,Time) ::-
  :this(Context),
  cache:entry(Context,Entry,Time,_,_,_,_).


% repository:category(?Category)
%
% public predicate
%
% Retrieves metadata cache category
% No disk access - initial sync required

category(Category) ::-
  :this(Context),
  findall(C,cache:entry(Context,_,_,C,_,_,_),Cs),
  sort(Cs,Ss),!,
  member(Category,Ss).


% repository:package(?Category, ?Package)
%
% public predicate
%
% Retrieves metadata cache package
% No disk access - initial sync required

package(Category,Package) ::-
  :this(Context),
  cache:entry(Context,_,_,Category,Name,Version,_),
  atomic_list_concat([Name,'-',Version],Package).


% repository:ebuild(?Category, ?Name, ?Version)
%
% public predicate
%
% Retrieves metadata cache ebuild
% No disk access - initial sync required

ebuild(Category,Name,Version) ::-
  :this(Context),
  cache:entry(Context,_,_,Category,Name,Version,_).


% repository:ebuild(?Id, ?Category, ?Name, ?Version)
%
% public predicate
%
% Retrieves metadata cache ebuild
% No disk access - initial sync required

ebuild(Id,Category,Name,Version) ::-
  :this(Context),
  cache:entry(Context,Id,_,Category,Name,Version,_).


% repository:ebuild(?Id, ?Category, ?Name, ?Version, ?Metadata)
%
% public predicate
%
% Retrieves metadata cache ebuild
% Disk access

ebuild(Id,Category,Name,Version,Metadata) ::-
  :this(Context),
  cache:entry(Context,Id,_,Category,Name,Version,Metadata).



% repository:query(+Query,-Result)
%
% public predicate
%
% Retrieves metadata cache ebuild that satisfies
% a given query

query([],Id) ::-
  :this(Repository),
  cache:entry(Repository,Id,_,_,_,_,_).

query([name(Name)|Rest],Id) ::-
  :this(Repository),
  cache:entry(Repository,Id,_,_,Name,_,_),
  Repository:query(Rest,Id).

query([category(Category)|Rest],Id) ::-
  :this(Repository),
  cache:entry(Repository,Id,_,Category,_,_,_),
  Repository:query(Rest,Id).

query([version(Version)|Rest],Id) ::-
  :this(Repository),
  cache:entry(Repository,Id,_,_,_,Version,_),
  % compare(C,Version,Providedversion),
  Repository:query(Rest,Id).

query([not(Statement)|Rest],Id) ::-
  :this(Repository),
  not(Repository:query([Statement],Id)),
  Repository:query(Rest,Id).

query([Statement|Rest],Id) ::-
  :this(Repository),
  cache:entry(Repository,Id,_,_,_,_,Metadata),
  Statement =.. [Key,Arg],
  eapi:elem(Key,Metadata,Setting),
  member(Arg,Setting),
  Repository:query(Rest,Id).


% repository:get_location(?Location).
%
% public predicate
%
% Location is an atom, representing a full absolute path
% to a portage tree installed on your local system.

get_location(Location) ::-
  ::location(Location).


% repository:get_cache(?Location).
%
% public predicate
%
% Location is an atom, representing a full absolute path
% to a portage tree cache installed on your local system.

get_cache(Location) ::-
  ::cache(Location).


% repository:get_remote(?Location).
%
% public predicate
%
% Location is an atom, representing an uri to a remote
% portage tree.

get_remote(Location) ::-
  ::remote(Location).


% repository:get_protocol(?Protocol).
%
% public predicate
%
% Protocol is an atom, representing a protocol to sync
% with the remote portage tree.

get_protocol(Protocol) ::-
  ::protocol(Protocol).


% repository:get_type(?Type)
%
% public predicate
%
% Type is an atom, representing the type of data represented
% in the repository being processed.

get_type(Type) ::-
  ::type(Type).


% repository:get_type(?Type)
%
% public predicate
%
% Type is an atom, representing the type of data represented
% in the repository being processed.

get_size(Size) ::-
  :this(Repository),
  findall(E,Repository:entry(E),L),
  length(L,Size).


% repository:get_ebuild(+Entry,-Ebuild)
%
% public predicate
%
% For a given entry, retrieves the full path to the corresponding ebuild

get_ebuild(Entry,Ebuild) ::-
  ::location(Location),
  :ebuild(Entry,Category,Name,Version),
  atomic_list_concat([Location,'/',Category,'/',Name,'/',Name,'-',Version,'.ebuild'],Ebuild),
  exists_file(Ebuild).


% repository:location(?Location)
%
% protected predicate
%
% location is an atom, representing a full absolute path
% to a portage tree installed on your local system

location(Location) ::-
  atom(Location).
  %is_absolute_file_name(Location).


% repository:cache(?Location)
%
% protected predicate
%
% location is an atom, representing a full absolute path
% to a portage tree cache installed on your local system

cache(Location) ::-
  atom(Location).
  %is_absolute_file_name(Location).


% repository:remote(?Location)
%
% protected predicate
%
% Location is an atom, representing an uri to a remote
% portage tree.

remote(Location) ::-
  atom(Location).
  % is_absolute_url(Location).


% repository:protocol(?Protocol)
%
% protected predicate
%
% Protocol is an atom, representing the protocol to
% sync with the remote portage tree.

protocol(Protocol) ::-
  atom(Protocol).
  % member(Protocol,['git','http','rsync']).


% repository:type(?Type)
%
% protected predicate
%
% Type is an atom, representing the type of data represented
% in the repository being processed

type(Type) ::-
  atom(Type).
