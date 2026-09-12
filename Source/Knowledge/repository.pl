/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> REPOSITORY
The Repository is a class enabling its instances to manipulate repositories
and the metadata associated with those repositories.

Examples of repositories: Gentoo Portage, Github repositories, ...
*/

:- module(repository,[]).

% =============================================================================
%  REPOSITORY declarations
% =============================================================================

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
:- dpublic(find_metadata_xml/4).
:- dpublic(find_ebuild/5).

:- dpublic(read_time/1).
:- dpublic(read_metadata/3).
:- dpublic(read_manifest/5).
:- dpublic(read_metadata_xml/5).
:- dpublic(read_ebuild/2).
:- dpublic(read_ebuild/3).

:- dpublic(graph/0).
:- dpublic(graph_emerge/0).
:- dpublic(prepare_directory/1).


% private interface

:- dpublic(update_metadata/2).
:- dpublic(update_cache/0).

% VDB helpers (private to repository instances)
%
% These must be declared so they are available in the instance context
% (e.g. `pkg:find_vdb_entry/4`) when called via `:find_vdb_entry(...)`.
% keep public for performance, like the eapi slots  ...
:- dpublic(find_vdb_entry/4).

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
  % Network step, subject to the optional per-repository daily cap
  % (config:repository_sync_limit/2). When the cap is exhausted the
  % remote fetch is skipped with a notice; metadata and kb still rebuild
  % from what is on disk.
  ( repository:network_sync_allowed(Repository)
  -> ( message:wrap(Repository:sync(repository))
     -> repository:record_network_sync(Repository)
     ; format('% sync(repository) failed for ~w~n', [Repository]), flush_output, fail )
  ;  repository:sync_limit_notice(Repository) ),
  ( message:wrap(Repository:sync(metadata))
  -> true
  ; format('% sync(metadata) failed for ~w~n', [Repository]), flush_output, fail ),
  ( message:wrap(Repository:sync(kb))
  -> true
  ; format('% sync(kb) failed for ~w~n', [Repository]), flush_output, fail ),
  nl,!.


%! repository:sync(+Repository)
%
% Public predicate
%
% Updates files in local repository by invoking script to sync local repository
% with remote repository (e.g. git / rsync / http tarball / ...)

% Bugzilla sync(repository): paginated REST crawl into JSON pages under
% the repository location (see bugs:sync_pages/2). No external script;
% the protocol slot ('rest') documents the transport. Must precede the
% generic script-driven clause below (clause order is dispatch order in
% the OO context system).
sync(repository) ::-
  ::type('bugzilla'),!,
  ::location(Local),
  ::remote(Remote),
  message:hc,
  os:ensure_directory_path(Local),
  bugs:sync_pages(Local, Remote),
  message:sc,
  !.

sync(repository) ::-
  ::location(Local),
  ::remote(Remote),
  ::protocol(Protocol),
  message:hc,
  script:exec_streaming(sync,[Protocol,Remote,Local],[]),
  message:sc,
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
  :this(Repository),
  ::cache(Cache),
  % System-wide lock: multiple portage-ng instances must not update the same
  % on-disk metadata cache in parallel.
  lock:with_system_lock(repository_metadata_cache(Repository, Cache),
    ( message:hc,
      ( config:trust_metadata(false)
        -> (:update_cache,
            concurrent_forall(:find_ebuild(E,_,_,_,_),
                    (:read_ebuild(E,Cd,_),
                     :update_metadata(E,Cd),
                     with_mutex(mutex,message:scroll(['Ebuild (local): ',E])))))
        ; true
      ),
      message:sc,
      message:scroll(['Updated metadata.']),nl
    )).


% Binpkg sync(metadata): no-op. Portage's $PKGDIR/Packages file IS the
% metadata for a binpkg repository -- there is no per-entry metadata
% directory to regenerate. The on-disk Packages index is maintained
% incrementally by `emerge` (or whatever produced the binpkgs) via
% bintree.inject(). Must precede the generic ::type(Type) clause below,
% which would otherwise match 'binpkg' and cut (clause order is dispatch
% order in the OO context system).
sync(metadata) ::-
  ::type('binpkg'),!.


% Bugzilla sync(metadata): no-op. The JSON pages written by
% sync(repository) are already the metadata; sync(kb) folds them.
sync(metadata) ::-
  ::type('bugzilla'),!.


sync(metadata) ::-
  ::type(Type),!,
  ::location(Local),
  ::remote(Remote),
  ::cache(Cache),
  :this(Repository),
  % System-wide lock: multiple portage-ng instances must not update the same
  % on-disk metadata cache in parallel.
  lock:with_system_lock(repository_metadata_cache(Repository, Cache),
    ( script:exec(cache,[Type,Repository,Remote,Local,Cache]),
      message:scroll(['Updated metadata.']),nl
    )).


%! repository:sync(kb)
%
% Public predicate
%
% Regenerates prolog facts from the local repository cache

% Binpkg sync(kb): build cache facts directly from a $PKGDIR/Packages
% RFC822 index. One cache:ordered_entry per BUILD_ID variant; metadata
% fields stored verbatim as cache:entry_metadata. Multiple variants of the
% same CPV share the same Version key but get unique EntryIds (`cat/pn-pv-N`)
% so they coexist in ordered_entry without dedup. The binpkg matcher
% (binpkg_exec) sorts candidates by `build_id` at query time -- we don't
% rely on ordered_entry's natural Version ordering for retrieval.
%
% The repository's `cache` slot points at the `Packages` file itself, not
% a directory (this is type-specific; for eapi it's the md5-cache dir).
%
% Atomicity (portage-ng#80): the index is parsed and projected to
% ready-to-assert rows BEFORE anything is retracted, and the actual
% retract+assert swap runs under `binpkg_index_lock`. Together this
% guarantees there is never a window in which a concurrent consumer sees
% an empty/partial binpkg index -- a slow or failed parse leaves the
% previously-loaded cache fully intact, and the swap itself is mutually
% exclusive with the reader/refresh path in binpkg_exec.
sync(kb) ::-
  ::type('binpkg'),!,
  :this(Repository),
  ::cache(IndexFile),
  message:hc,

  % Step 1: parse the on-disk `Packages` index FIRST, before mutating any
  % in-memory cache. A missing file or a parse error must never wipe a
  % previously-loaded binpkg index: there must be no window in which a
  % consumer (binpkg_exec:available_for/4) sees an empty index just
  % because a concurrent re-sync is mid-flight (portage-ng#80, item D).
  % We only swap the cache once a full, fresh record set is in hand.
  ( exists_file(IndexFile)
  -> binpkg_index:parse_file(IndexFile, _Header, Records),
     length(Records, NRec)
  ;  message:scroll(['No Packages index at ', IndexFile, ' -- registering empty binpkg repository.']),
     Records = [], NRec = 0
  ),

  % Step 2: project the parsed records into ready-to-assert rows and
  % derive the category / package sets in a single pass over the parsed
  % data -- no findall over the live database (portage-ng#80, item C).
  binpkg_index:project_records(Records, Rows, Categories, Packages),

  % Step 3 (optional, verbose only): per-variant trace. Default builds and
  % `--ci` runs stay quiet -- 32k `Binpkg:` lines previously dominated the
  % build log for trivial targets (portage-ng#80, item B). Emitted here,
  % outside the swap critical section, so it never extends the window in
  % which the cache is being mutated.
  ( config:verbose(true)
  -> forall(member(binpkg_row(EntryId, _, _, _, _), Rows),
            message:scroll(['Binpkg: ', EntryId]))
  ;  true
  ),

  % Step 4: atomically swap the in-memory cache. The retract+assert is the
  % ONLY mutation and is held under `binpkg_index_lock` so it can never
  % interleave with a concurrent reader/refresh that takes the same lock
  % (binpkg_exec:available_for/4, binpkg_exec:ensure_index_fresh/0). With
  % the parse + projection already done, this window is a tight in-memory
  % swap rather than the multi-second parse it used to straddle.
  with_mutex(binpkg_index_lock,
    ( retractall(cache:repository(Repository)),
      retractall(cache:category(Repository,_)),
      retractall(cache:entry(Repository,_,_,_,_)),
      retractall(cache:package(Repository,_,_)),
      retractall(cache:ordered_entry(Repository,_,_,_,_)),
      retractall(cache:entry_metadata(Repository,_,_,_)),
      retractall(cache:manifest(Repository,_,_,_,_)),
      retractall(cache:manifest_metadata(Repository,_,_,_,_,_)),
      forall(member(binpkg_row(EntryId, Cat, Name, Version, Meta), Rows),
             ( assertz(cache:ordered_entry(Repository, EntryId, Cat, Name, Version)),
               forall(member(Key-Value, Meta),
                      assertz(cache:entry_metadata(Repository, EntryId, Key, Value)))
             )),
      forall(member(Ca, Categories), assertz(cache:category(Repository, Ca))),
      forall(member(Ca-Pa, Packages), assertz(cache:package(Repository, Ca, Pa))),
      assertz(cache:repository(Repository))
    )),

  message:sc,
  message:scroll(['Updated prolog knowledgebase. Binpkg variants: ', NRec]), nl,
  message:clean,
  !.


% Bugzilla sync(kb): fold the pending JSON pages onto the bug store and
% serialise it to the qcompiled file named by the cache slot
% (Knowledge/bugs.qlf). Bugs are not tree entries: no cache:ordered_entry
% or cache:entry_metadata rows are produced, only cache:repository/1 so the
% repository shows up as registered. The store lives outside kb.qlf and
% is loaded lazily by its consumers (bugs:ensure_loaded/0).
sync(kb) ::-
  ::type('bugzilla'),!,
  :this(Repository),
  ::location(Local),
  ::cache(Qlf),
  message:hc,
  bugs:build_cache(Local, Qlf, Count),
  retractall(cache:repository(Repository)),
  assertz(cache:repository(Repository)),
  message:sc,
  message:scroll(['Updated bug tracker knowledgebase. Bugs: ', Count]), nl,
  message:clean,
  !.


% VDB sync: build cache facts directly from a /var/db/pkg-style directory tree.
sync(kb) ::-
  ::type('vdb'),!,
  :this(Repository),
  message:hc,

  % Step 1: clean prolog cache for this repository
  retractall(cache:repository(Repository)),
  retractall(cache:category(Repository,_)),
  retractall(cache:entry(Repository,_,_,_,_)),
  retractall(cache:package(Repository,_,_)),
  retractall(cache:ordered_entry(Repository,_,_,_,_)),
  retractall(cache:entry_metadata(Repository,_,_,_)),
  retractall(cache:manifest(Repository,_,_,_,_)),
  retractall(cache:manifest_metadata(Repository,_,_,_,_,_)),

  % Step 2: read installed entries and their metadata
  concurrent_forall(
    :find_vdb_entry(E,C,N,V),
    ( with_mutex(mutex,message:scroll(['VDB: ',E])),
      assertz(cache:entry(Repository,E,C,N,V)),
      :read_metadata(E,_T,M),
      forall(member(L,M),
             ( L =.. [Key,Value],
               forall(member(I,Value),
                      ( eapi:normalize_entry_metadata(Key, I, I1),
                        assertz(cache:entry_metadata(Repository,E,Key,I1))
                      ))
             ))
    )
  ),

  % Step 4/5/6/7: reuse standard ordering + repository finalization logic
  findall(Ca,cache:entry(Repository,_,Ca,_,_),Cu),
  sort(Cu,Cs),
  forall(member(Ca,Cs),
         assertz(cache:category(Repository,Ca))),

  findall([Ca,Pa],cache:entry(Repository,_,Ca,Pa,_),Pu),
  sort(Pu,Ps),
  forall(member([Ca,Pa],Ps),
         (findall([Ver,Id],
                  cache:entry(Repository,Id,Ca,Pa,Ver),
                  Vu),
          predsort(eapi:compare_ordered_entry_version_desc, Vu, Vs0),
          ( assertz(cache:package(Repository,Ca,Pa)),
            forall(member([OVer,OrderedId],Vs0),
                   assertz(cache:ordered_entry(Repository,OrderedId,Ca,Pa,OVer))
                 )))),

  retractall(cache:entry(Repository,_,_,_,_)),
  assertz(cache:repository(Repository)),

  message:sc,
  message:scroll(['Updated prolog knowledgebase.']),nl,
  message:clean,
  !.

sync(kb) ::-
  :this(Repository),
  message:hc,

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
                          ( eapi:normalize_entry_metadata(Key, I, I1),
                            assertz(cache:entry_metadata(Repository,E,Key,I1))
                          )))))),

  % Step 2.b: read ebuilds without repository cache

  (config:write_metadata(true) -> :update_cache ; true),

  concurrent_forall((:find_ebuild(E,T,C,N,V),\+(cache:entry_metadata(Repository,E,_,_))),
          (catch(:read_ebuild(E,Cd,M), _, fail)
           -> (with_mutex(mutex,message:scroll(['Ebuild (local): ',E])),
               assertz(cache:entry(Repository,E,C,N,V)),
               assertz(cache:entry_metadata(Repository,E,timestamp,T)),
               assertz(cache:entry_metadata(Repository,E,local,true)),
               forall(member(L,M),
                      (L=..[Key,Value],
                       forall(member(I,Value),
                              ( eapi:normalize_entry_metadata(Key, I, I1),
                                assertz(cache:entry_metadata(Repository,E,Key,I1))
                              )))),
               (config:write_metadata(true) -> :update_metadata(E,Cd) ; true))
           ; with_mutex(mutex,message:scroll(['Ebuild (local, skip): ',E])))),


  % Step 2.c: read ebuilds with outdated repository cache

  concurrent_forall((:find_ebuild(E,TE,C,N,V),cache:entry_metadata(Repository,E,timestamp,TC), TE > TC + 60), % time writing to disk
          (catch(:read_ebuild(E,Cd,M), _, fail)
           -> (with_mutex(mutex,message:scroll(['Ebuild (changed): ',E])),
               retractall(cache:entry(Repository,E,_,_,_)),
               retractall(cache:entry_metadata(Repository,E,_,_)),
               assertz(cache:entry(Repository,E,C,N,V)),
               assertz(cache:entry_metadata(Repository,E,timestamp,TE)),
               assertz(cache:entry_metadata(Repository,E,changed,true)),
               forall(member(L,M),
                      (L=..[Key,Value],
                       forall(member(I,Value),
                              ( eapi:normalize_entry_metadata(Key, I, I1),
                                assertz(cache:entry_metadata(Repository,E,Key,I1))
                              )))),
               (config:write_metadata(true) -> :update_metadata(E,Cd) ; true))
           ; with_mutex(mutex,message:scroll(['Ebuild (changed, skip): ',E])))),


  % Step 3: update prolog cache:manifest facts for manifests in the repository

  concurrent_forall(:find_manifest(P,T,C,N),
          (:read_manifest(P,T,C,N,M),
           with_mutex(mutex,message:scroll(['Manifest: ',P])),
           assertz(cache:manifest(Repository,P,T,C,N)),
           forall(member(manifest(Filetype,Filename,Filesize,Checksums),M),
                 assertz(cache:manifest_metadata(Repository,P,Filetype,Filename,Filesize,Checksums))))),

  % Step 3.5: load metadata.xml maintainers and assert cache:entry_metadata(maintainer)
  % Skip on parse error or empty maintainers; one bad metadata.xml must not abort sync.
  concurrent_forall(:find_metadata_xml(Path,T,C,N),
          ( catch((:read_metadata_xml(Path,T,C,N,Maintainers),
                  Maintainers \== [],
                  with_mutex(mutex,message:scroll(['Metadata.xml: ',C,'/',N])),
                  forall(cache:entry(Repository,Entry,C,N,_),
                         assertz(cache:entry_metadata(Repository,Entry,maintainer,Maintainers)))),
                _Error,
                true)
          ; true )),


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
         (findall([Ver,Id],
                  cache:entry(Repository,Id,Ca,Pa,Ver),
                  Vu),
          predsort(eapi:compare_ordered_entry_version_desc, Vu, Vs),
          ( assertz(cache:package(Repository,Ca,Pa)),
            forall(member([OVer,OrderedId],Vs),
                   assertz(cache:ordered_entry(Repository,OrderedId,Ca,Pa,OVer))
                 )))),

  % Step 6 : We retract the original unordered prolog cache entries.

  retractall(cache:entry(Repository,_,_,_,_)),

  % Step 7: We end by creating a prolog cache:repository

  assertz(cache:repository(Repository)),

  message:sc,
  message:scroll(['Updated prolog knowledgebase.']),nl,
  message:clean.


% -----------------------------------------------------------------------------
%  VDB helpers
% -----------------------------------------------------------------------------

%! repository:find_vdb_entry(-Entry,-Category,-Name,-Version)
%
% Enumerate installed entries from a /var/db/pkg-style directory tree.
% Entry is the canonical cache id (e.g. 'www-client/links-2.30').
find_vdb_entry(Entry, Category, Name, Version) ::-
  ::location(Root),
  os:directory_content(Root, Category),
  os:compose_path(Root, Category, CategoryDir),
  exists_directory(CategoryDir),
  os:directory_content(CategoryDir, PF),
  os:compose_path(CategoryDir, PF, EntryDir),
  exists_directory(EntryDir),
  atomic_list_concat([Category,PF], '/', Entry),
  eapi:packageversion(PF, Name, Version).


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


%! repository:find_metadata_xml(?Path, -Timestamp, -Category, -Name)
%
% Public predicate
%
% Finds metadata.xml files in the repository (GLEP 68).
% Disk access required.

find_metadata_xml(Path,Timestamp,Category,Name) ::-
  ::location(Location),
  ::cache(Cache),
  os:directory_content(Cache,Category),
  os:compose_path(Location,Category,CategoryDir),
  exists_directory(CategoryDir),
  os:directory_content(CategoryDir,Name),
  os:compose_path(CategoryDir,Name,PackageDir),
  exists_directory(PackageDir),
  os:compose_path(PackageDir,'metadata.xml',Path),
  exists_file(Path),
  system:time_file(Path,Timestamp).


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

read_metadata(Entry,Timestamp,Metadata) ::-
  ::type('vdb'),
  :this(Repository),
  ::location(Root),
  os:compose_path(Root, Entry, Dir),
  exists_directory(Dir),
  % Use directory mtime as a cheap timestamp for incremental logic if needed.
  ( system:time_file(Dir, Timestamp) -> true ; Timestamp = 0 ),
  parser:invoke(vdb, Repository://Entry, Dir, Metadata),
  !.

read_metadata(Entry,_Timestamp,[]) ::-
  ::type('vdb'),
  message:failure(['Failed to parse ',Entry,' vdb metadata!']),
  fail.

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


%! repository:read_metadata_xml(+Path, +Timestamp, +Category, +Name, -Maintainers)
%
% Public predicate
%
% Reads metadata.xml at Path and extracts maintainer email addresses.
% Maintainers is a list of atoms. Disk access required.

read_metadata_xml(Path,_Timestamp,_Category,_Name,Maintainers) ::-
  eapi:metadata_maintainers(Path, Maintainers).


%! repository:read_ebuild(?Entry, -Contents, -Metadata))
%
% Public predicate
%
% Reads metadata for a given entry directly from the ebuild file
% bypassing the metadata cache inside the repository.
% Disk access required.

read_ebuild(Entry,Metadata) ::-
  read_ebuild(Entry,_,Metadata).

read_ebuild(Entry,Contents,Metadata) ::-
  :this(Repository),
  ::location(Location),
  ebuild:invoke(cache,Location,Entry,Stream),
  reader:invoke(Stream,Contents),
  parser:invoke(metadata,Repository://Entry,Contents,Metadata),!.


%! repository:update_metadata(+Entry, +Contents)
%
% Private predicate
%
% Update the repository on-disk cache with codes
% read by the reader from the ebuild.sh stream.
% Note: category subdirectories inside metadata/md5-cache may not exist yet
% (e.g., when a new category is created in an overlay). Ensure the parent
% directory exists before writing.

update_metadata(Entry,Contents) ::-
  ::cache(Cache),
  os:compose_path(Cache,Entry,File),
  file_directory_name(File, Dir),
  os:ensure_directory_path(Dir),
  tell(File),
  forall(member(String,Contents),(writeln(String))),
  told.


%! repository:update_cache
%
% Private predicate
%
% Creates a category structure in the on-disk cache.

update_cache ::-
  ::cache(Cache),
  os:ensure_directory_path(Cache),
  forall(:find_category(Category),
         (os:compose_path(Cache,Category,Path),
          os:ensure_directory_path(Path))).


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
  current_predicate(config:graph_directory/1),
  config:graph_directory(G),
  os:compose_path(G,Repository,D),
  system:exists_directory(D),!,
  message:scroll_notice(['Directory already exists! Updating...']),
  vdb:create_repository_dirs(Repository,D),
  grapher:copy_graph_assets(D),
  sitefiles:write_site_files(D,Repository).

prepare_directory(D) ::-
  :this(Repository),
  current_predicate(config:graph_directory/1),
  config:graph_directory(G),
  os:ensure_directory_path(G),
  os:compose_path(G,Repository,D),
  \+(system:exists_directory(D)),!,
  message:scroll_notice(['Directory does not exist! Creating...']),
  vdb:make_repository_dirs(Repository,D),
  grapher:copy_graph_assets(D),
  sitefiles:write_site_files(D,Repository).


%! repository:graph
%
% Creates graph and proof files for the repository

graph ::-
  :this(Repository),
  atomic_concat(graph,Repository,Mutex),
  with_mutex(Mutex,
    (:prepare_directory(D),
     writer:write_graph_files(D,Repository),
     writer:write_proof_files(D,Repository),
     writer:write_index_files(D,Repository)
     )).


%! repository:graph_emerge
%
% Generates .emerge files for the repository by invoking the gentoo-prefix
% `emerge-vp` wrapper for every ebuild. Skips entries whose .emerge file
% is already newer than the source .ebuild unless force_emerge_regen is
% asserted. Intended to be driven by `--graph emerge` (see graph.pl).

graph_emerge ::-
  :this(Repository),
  atomic_concat(graph_emerge,Repository,Mutex),
  with_mutex(Mutex,
    (:prepare_directory(D),
     writer:write_emerge_files(D,Repository)
     )).


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
  cache:ordered_entry(Repository,_,Category,Name,Ver),
  eapi:version_full(Ver, Version).


%! repository:ebuild(?Id, ?Category, ?Name, ?Version)
%
% Public predicate
%
% Retrieves metadata cache ebuild
% No disk access - initial sync required

ebuild(Id,Category,Name,Version) ::-
  :this(Repository),
  cache:ordered_entry(Repository,Id,Category,Name,Ver),
  eapi:version_full(Ver, Version).


%! repository:ebuild(?Id, ?Category, ?Name, ?Version, ?Key, ?Value)
%
% Public predicate
%
% Retrieves metadata cache ebuild
% No disk access - initial sync required

ebuild(Id,Category,Name,Version,Key,Value) ::-
  :this(Repository),
  cache:ordered_entry(Repository,Id,Category,Name,Ver),
  eapi:version_full(Ver, Version),
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


%! repository:get_size(?Size)
%
% Public predicate
%
% Size is an integer, representing the number of entries in a repository

get_size(Size) ::-
  :this(Repository),
  aggregate_all(count,Repository:entry(_),Size).


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
  os:compose_path(Cache, Entry, File).


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


% -----------------------------------------------------------------------------
%  Per-repository network sync cap
% -----------------------------------------------------------------------------

% Plain module predicates (not instance methods): the cap is keyed by the
% repository name and its state is a stamp file, so no instance state is
% involved. `config:repository_sync_limit(Repo, PerDay)` declares the
% maximum number of network syncs (`sync(repository)`) in any rolling
% 24-hour window; repositories without a declaration are unlimited. The
% stamps live in `Knowledge/<Repo>.sync`, one POSIX time per line.

%! repository:sync_stamp_file(+Repository, -File) is det.
%
% Path of the network-sync stamp file for Repository.

repository:sync_stamp_file(Repository, File) :-
  config:working_dir(Dir),
  format(atom(Name), 'Knowledge/~w.sync', [Repository]),
  os:compose_path(Dir, Name, File).


%! repository:sync_limit(+Repository, -PerDay) is semidet.
%
% Declared daily cap for Repository, when any.

repository:sync_limit(Repository, PerDay) :-
  current_predicate(config:repository_sync_limit/2),
  config:repository_sync_limit(Repository, PerDay),
  integer(PerDay),
  PerDay >= 0,
  !.


%! repository:recent_sync_stamps(+Repository, -Stamps) is det.
%
% POSIX times of the network syncs of Repository within the last 24h.

repository:recent_sync_stamps(Repository, Stamps) :-
  repository:sync_stamp_file(Repository, File),
  ( exists_file(File)
  -> catch(read_file_to_terms(File, Terms, []), _, Terms = [])
  ;  Terms = [] ),
  get_time(Now),
  Cutoff is Now - 86400,
  findall(T, ( member(T, Terms), number(T), T > Cutoff ), Stamps).


%! repository:network_sync_allowed(+Repository) is semidet.
%
% True unless a daily cap is declared for Repository and already reached.

repository:network_sync_allowed(Repository) :-
  ( repository:sync_limit(Repository, PerDay)
  -> repository:recent_sync_stamps(Repository, Stamps),
     length(Stamps, Done),
     Done < PerDay
  ;  true ).


%! repository:record_network_sync(+Repository) is det.
%
% Append the current time to the stamp file (only when a cap is declared,
% so uncapped repositories never write stamps). Stale stamps are pruned
% on the way.

repository:record_network_sync(Repository) :-
  ( repository:sync_limit(Repository, _)
  -> repository:recent_sync_stamps(Repository, Stamps),
     get_time(Now),
     append(Stamps, [Now], All),
     repository:sync_stamp_file(Repository, File),
     file_directory_name(File, Dir),
     os:ensure_directory_path(Dir),
     setup_call_cleanup(
       open(File, write, Out),
       forall(member(T, All), format(Out, '~q.~n', [T])),
       close(Out))
  ;  true ).


%! repository:sync_limit_notice(+Repository) is det.
%
% Explain why the network step was skipped and when it becomes available.

repository:sync_limit_notice(Repository) :-
  repository:sync_limit(Repository, PerDay),
  repository:recent_sync_stamps(Repository, Stamps),
  ( Stamps = [Oldest|_]
  -> Next is Oldest + 86400,
     format_time(atom(When), '%F %T', Next)
  ;  When = 'later' ),
  message:scroll_notice(['Network sync of \"', Repository, '\" skipped: daily cap of ',
                         PerDay, ' reached; next allowed after ', When,
                         '. Rebuilding from local data.']),
  nl.