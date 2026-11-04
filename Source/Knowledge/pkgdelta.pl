/*
 Author:   Pieter Van den Abeele
 E-mail:   pvdabeel@mac.com
 Copyright (c) 2005-2026, Pieter Van den Abeele

 Distributed under the terms of the LICENSE file in the root directory of this
 project.
*/


/** <module> PKGDELTA
Incremental installed-package facts.

A build writes a handful of directories under the VDB. Pretend answers
"what is installed?" from the pkg facts loaded at startup, so those
directories have to land in the cache before the next plan. Rewalking
every installed package, and saving the whole knowledge base, is out of
proportion to that change.

`Knowledge/pkgdelta.pl` records only the entries a build replaced.
Startup loads `kb.qlf` and then applies the file: each recorded entry
is reread from the VDB, and each replaced entry is dropped. A later
`--sync` that includes `pkg` rebuilds the facts from the directory and
deletes the file, because the saved knowledge base then already
matches the VDB.

emerge can change the same VDB between invocations. After the delta
is applied, the package directories are listed and compared with the
loaded facts. A difference is reported; the facts are not rewritten.
*/

:- module(pkgdelta, []).

% =============================================================================
% PKGDELTA declarations
% =============================================================================


% -----------------------------------------------------------------------------
% Record and apply
% -----------------------------------------------------------------------------

%! pkgdelta:apply is det.
%
% Applies Knowledge/pkgdelta.pl onto the loaded pkg facts. Missing file
% and a VDB that is not registered are both quiet no-ops. One bad entry
% does not discard the rest.

pkgdelta:apply :-
  ( pkgdelta:state_file(Path),
    exists_file(Path),
    knowledgebase:vdb_repository(Repo)
  -> pkgdelta:read_ops(Path, Ops),
     pkgdelta:normalize(Ops, Removes, Refreshes),
     pkgdelta:apply_lists(Repo, Removes, Refreshes)
  ;  true
  ).


%! pkgdelta:record(+Ops) is det.
%
% Merges Ops (`remove(Entry)` / `refresh(Entry)`) into the delta file
% and makes the loaded pkg facts match the result. Entry is the VDB id
% `category/pf`.

pkgdelta:record(Ops) :-
  pkgdelta:state_file(Path),
  pkgdelta:read_ops(Path, Old),
  append(Old, Ops, All),
  pkgdelta:normalize(All, Removes, Refreshes),
  ( knowledgebase:vdb_repository(Repo)
  -> pkgdelta:apply_lists(Repo, Removes, Refreshes)
  ;  true
  ),
  pkgdelta:write_ops(Path, Removes, Refreshes).


%! pkgdelta:clear is det.
%
% Deletes the delta file. Called after a pkg sync has been saved, when
% `kb.qlf` already contains the directory walk.

pkgdelta:clear :-
  ( pkgdelta:state_file(Path),
    exists_file(Path)
  -> delete_file(Path)
  ;  true
  ).


% -----------------------------------------------------------------------------
% Change normalisation
% -----------------------------------------------------------------------------

%! pkgdelta:normalize(+Ops, -Removes, -Refreshes) is det.
%
% Last operation for an entry wins. `refresh(E)` drops a pending
% `remove(E)`, and the other way around.

pkgdelta:normalize(Ops, Removes, Refreshes) :-
  pkgdelta:normalize(Ops, [], [], Removes, Refreshes).


%! pkgdelta:normalize(+Ops, +Removes0, +Refreshes0, -Removes, -Refreshes) is det.
%
% Tail of normalize/3.

pkgdelta:normalize([], Removes, Refreshes, Removes, Refreshes).
pkgdelta:normalize([remove(Entry)|Rest], Removes0, Refreshes0, Removes, Refreshes) :-
  !,
  delete(Refreshes0, Entry, Refreshes1),
  ( memberchk(Entry, Removes0) -> Removes1 = Removes0 ; Removes1 = [Entry|Removes0] ),
  pkgdelta:normalize(Rest, Removes1, Refreshes1, Removes, Refreshes).
pkgdelta:normalize([refresh(Entry)|Rest], Removes0, Refreshes0, Removes, Refreshes) :-
  !,
  delete(Removes0, Entry, Removes1),
  ( memberchk(Entry, Refreshes0) -> Refreshes1 = Refreshes0 ; Refreshes1 = [Entry|Refreshes0] ),
  pkgdelta:normalize(Rest, Removes1, Refreshes1, Removes, Refreshes).
pkgdelta:normalize([_|Rest], Removes0, Refreshes0, Removes, Refreshes) :-
  pkgdelta:normalize(Rest, Removes0, Refreshes0, Removes, Refreshes).


% -----------------------------------------------------------------------------
% Cache update
% -----------------------------------------------------------------------------

%! pkgdelta:apply_lists(+Repo, +Removes, +Refreshes) is det.
%
% Drops Removes, then rereads Refreshes from the VDB into Repo's cache.

pkgdelta:apply_lists(Repo, Removes, Refreshes) :-
  forall(member(Entry, Removes),
         pkgdelta:forget_entry(Repo, Entry)),
  forall(member(Entry, Refreshes),
         pkgdelta:refresh_entry(Repo, Entry)),
  append(Removes, Refreshes, Touched),
  pkgdelta:drop_missing_packages(Repo, Touched).


%! pkgdelta:drop_missing_packages(+Repo, +Entries) is det.
%
% Forgets every cached version of a package touched by Entries whose
% VDB directory is gone. A merge removes the version it replaced
% inside the ebuild, which the plan's `replaces` marker can miss.

pkgdelta:drop_missing_packages(Repo, Entries) :-
  findall(C-N, pkgdelta:entry_cn(Entries, C, N), Pairs0),
  sort(Pairs0, Pairs),
  forall(member(C-N, Pairs),
         pkgdelta:drop_missing_versions(Repo, C, N)).


%! pkgdelta:entry_cn(+Entries, -Category, -Name) is nondet.
%
% Category and Name of one entry id in Entries.

pkgdelta:entry_cn(Entries, C, N) :-
  member(Entry, Entries),
  atomic_list_concat([C, PF], '/', Entry),
  eapi:packageversion(PF, N, _).


%! pkgdelta:drop_missing_versions(+Repo, +Category, +Name) is det.
%
% Forgets cached versions of Category/Name that are not on disk.
% The directory check is collected before any retraction.

pkgdelta:drop_missing_versions(Repo, C, N) :-
  findall(Entry,
          ( cache:ordered_entry(Repo, Entry, C, N, _),
            \+ pkgdelta:entry_on_disk(Repo, Entry)
          ),
          Gone),
  forall(member(Entry, Gone),
         pkgdelta:forget_entry(Repo, Entry)).


%! pkgdelta:forget_entry(+Repo, +Entry) is det.
%
% Retracts Entry and, when it was the last version of its package or
% the last package of its category, the package and category facts.

pkgdelta:forget_entry(Repo, Entry) :-
  ( cache:ordered_entry(Repo, Entry, Cat, Name, _) ->
      true
  ;  Cat = none,
     Name = none
  ),
  retractall(cache:ordered_entry(Repo, Entry, _, _, _)),
  retractall(cache:entry_metadata(Repo, Entry, _, _)),
  retractall(cache:entry(Repo, Entry, _, _, _)),
  ( Cat == none ->
      true
  ; cache:ordered_entry(Repo, _, Cat, Name, _) ->
      true
  ; retractall(cache:package(Repo, Cat, Name)),
    ( cache:ordered_entry(Repo, _, Cat, _, _) ->
        true
    ; retractall(cache:category(Repo, Cat))
    )
  ).


%! pkgdelta:refresh_entry(+Repo, +Entry) is det.
%
% Rereads Entry from the VDB. A directory that is no longer there is
% forgotten, which is what a downgrade does to the version it replaced
% when that id was recorded as a refresh.

pkgdelta:refresh_entry(Repo, Entry) :-
  ( pkgdelta:entry_on_disk(Repo, Entry),
    atomic_list_concat([Cat, PF], '/', Entry),
    eapi:packageversion(PF, Name, Ver),
    catch(Repo:read_metadata(Entry, _, Metadata), _, fail)
  -> pkgdelta:forget_entry(Repo, Entry),
     pkgdelta:assert_metadata(Repo, Entry, Metadata),
     pkgdelta:place_version(Repo, Cat, Name, Entry, Ver)
  ;  pkgdelta:forget_entry(Repo, Entry)
  ).


%! pkgdelta:entry_on_disk(+Repo, +Entry) is semidet.
%
% True when Repo's VDB root contains Entry as a directory.

pkgdelta:entry_on_disk(Repo, Entry) :-
  catch(Repo:get_location(Root), _, fail),
  os:compose_path(Root, Entry, Dir),
  exists_directory(Dir).


%! pkgdelta:assert_metadata(+Repo, +Entry, +Metadata) is det.
%
% Stores parsed VDB metadata under the same normalisation the full
% pkg sync uses.

pkgdelta:assert_metadata(Repo, Entry, Metadata) :-
  forall(member(Field, Metadata),
         ( Field =.. [Key, Value],
           forall(member(Item, Value),
                  ( eapi:normalize_entry_metadata(Key, Item, Item1),
                    assertz(cache:entry_metadata(Repo, Entry, Key, Item1))
                  ))
         )).


%! pkgdelta:place_version(+Repo, +Cat, +Name, +Entry, +Ver) is det.
%
% Inserts Entry into the package's ordered_entry facts in descending
% version order, preserving every other installed version of Cat/Name.

pkgdelta:place_version(Repo, Cat, Name, Entry, Ver) :-
  findall([OtherVer, OtherId],
          ( cache:ordered_entry(Repo, OtherId, Cat, Name, OtherVer),
            OtherId \== Entry
          ),
          Others),
  predsort(eapi:compare_ordered_entry_version_desc, [[Ver, Entry]|Others], Sorted),
  retractall(cache:ordered_entry(Repo, _, Cat, Name, _)),
  forall(member([SortedVer, SortedId], Sorted),
         assertz(cache:ordered_entry(Repo, SortedId, Cat, Name, SortedVer))),
  ( cache:category(Repo, Cat) -> true ; assertz(cache:category(Repo, Cat)) ),
  ( cache:package(Repo, Cat, Name) -> true ; assertz(cache:package(Repo, Cat, Name)) ).


% -----------------------------------------------------------------------------
% Delta file
% -----------------------------------------------------------------------------

%! pkgdelta:state_file(-Path) is det.
%
% Path of the incremental installed-package file.

pkgdelta:state_file(Path) :-
  config:state_dir(Dir),
  os:compose_path([Dir, 'Knowledge', 'pkgdelta.pl'], Path).


%! pkgdelta:read_ops(+Path, -Ops) is det.
%
% Ops is the list of terms in Path, or [] when Path is absent.

pkgdelta:read_ops(Path, Ops) :-
  ( exists_file(Path) ->
      setup_call_cleanup(
        open(Path, read, Stream),
        pkgdelta:read_terms(Stream, Ops),
        close(Stream))
  ;  Ops = []
  ).


%! pkgdelta:read_terms(+Stream, -Terms) is det.
%
% Reads every term from Stream.

pkgdelta:read_terms(Stream, Terms) :-
  read_term(Stream, Term, []),
  ( Term == end_of_file ->
      Terms = []
  ; Terms = [Term|Rest],
    pkgdelta:read_terms(Stream, Rest)
  ).


%! pkgdelta:write_ops(+Path, +Removes, +Refreshes) is det.
%
% Rewrites Path. Removes are written first so a later refresh of a
% different version cannot be undone by the remove of the one it
% replaced. An empty delta deletes Path.

pkgdelta:write_ops(Path, [], []) :-
  !,
  ( exists_file(Path) -> delete_file(Path) ; true ).
pkgdelta:write_ops(Path, Removes, Refreshes) :-
  file_directory_name(Path, Dir),
  ( exists_directory(Dir) -> true ; make_directory_path(Dir) ),
  atomic_list_concat([Path, '.tmp'], Temp),
  setup_call_cleanup(
    open(Temp, write, Stream),
    ( forall(member(Entry, Removes),
             ( write_canonical(Stream, remove(Entry)),
               format(Stream, '.~n', []) )),
      forall(member(Entry, Refreshes),
             ( write_canonical(Stream, refresh(Entry)),
               format(Stream, '.~n', []) ))
    ),
    close(Stream)),
  ( exists_file(Path) -> delete_file(Path) ; true ),
  rename_file(Temp, Path).


% -----------------------------------------------------------------------------
% External VDB changes
% -----------------------------------------------------------------------------

%! pkgdelta:warn_external_changes is det.
%
% Warns when the on-disk VDB and the loaded pkg facts name different
% packages. portage-ng's own builds are already in the facts via the
% delta file. What remains was written by another tool. A missing VDB
% is silent. `--sync` is silent too: that command is what reloads the
% facts, so the warning would only tell the user to run the command
% they are already running.

pkgdelta:warn_external_changes :-
  pkgdelta:sync_requested,
  !.
pkgdelta:warn_external_changes :-
  catch(pkgdelta:report_external_changes, _, true).


%! pkgdelta:sync_requested is semidet.
%
% True when this process was started with `--sync`.

pkgdelta:sync_requested :-
  current_predicate(interface:argv/2),
  interface:argv(Options, _),
  memberchk(sync(true), Options),
  !.



%! pkgdelta:report_external_changes is det.
%
% Compares the VDB directory with cache:ordered_entry/5 for the
% installed-package repository.

pkgdelta:report_external_changes :-
  knowledgebase:vdb_repository(Repo),
  catch(Repo:get_location(Root), _, fail),
  exists_directory(Root),
  !,
  findall(Entry, pkgdelta:disk_entry(Root, Entry), Disk0),
  sort(Disk0, Disk),
  findall(Entry, cache:ordered_entry(Repo, Entry, _, _, _), Cached0),
  sort(Cached0, Cached),
  pkgdelta:vdb_drift(Disk, Cached, Gone, Added),
  ( Gone == [], Added == [] ->
      true
  ; pkgdelta:report_drift(Gone, Added)
  ).
pkgdelta:report_external_changes.


%! pkgdelta:disk_entry(+Root, -Entry) is nondet.
%
% Entry is one `category/pf` directory under Root whose name is a
% package version. Other directories are skipped without a parse error.

pkgdelta:disk_entry(Root, Entry) :-
  os:directory_content(Root, Category),
  os:compose_path(Root, Category, CategoryDir),
  exists_directory(CategoryDir),
  os:directory_content(CategoryDir, PF),
  os:compose_path(CategoryDir, PF, EntryDir),
  exists_directory(EntryDir),
  pkgdelta:pf_name(PF),
  atomic_list_concat([Category, PF], '/', Entry).


%! pkgdelta:pf_name(+PF) is semidet.
%
% True when PF is `name-version`.

pkgdelta:pf_name(PF) :-
  atom_codes(PF, Codes),
  phrase(eapi:package(_), Codes, Rest),
  phrase(eapi:version(_), Rest, []),
  !.


%! pkgdelta:vdb_drift(+Disk, +Cached, -Gone, -Added) is det.
%
% Gone are facts with no directory. Added are directories with no fact.
% Both input lists are sorted.

pkgdelta:vdb_drift(Disk, Cached, Gone, Added) :-
  ord_subtract(Cached, Disk, Gone),
  ord_subtract(Disk, Cached, Added).


%! pkgdelta:report_drift(+Gone, +Added) is det.
%
% Prints the drift warning and a short sample of each side.

pkgdelta:report_drift(Gone, Added) :-
  length(Gone, NG),
  length(Added, NA),
  N is NG + NA,
  format(atom(Count), '~d', [N]),
  message:warning(['Installed package database changed outside portage-ng (',
                   Count,
                   ' packages). Loaded facts are stale. Run --sync pkg.']),
  pkgdelta:report_drift_side('removed since last sync', Gone),
  pkgdelta:report_drift_side('installed since last sync', Added).


%! pkgdelta:report_drift_side(+Label, +Entries) is det.
%
% Prints up to eight entries. An empty side is skipped.

pkgdelta:report_drift_side(_, []) :- !.
pkgdelta:report_drift_side(Label, Entries) :-
  pkgdelta:sample_entries(Entries, 8, Sample, Rest),
  atomic_list_concat(Sample, ', ', Listed),
  ( Rest =:= 0 ->
      message:warning(['  ', Label, ': ', Listed])
  ; format(atom(More), ' and ~d more', [Rest]),
    message:warning(['  ', Label, ': ', Listed, More])
  ).


%! pkgdelta:sample_entries(+Entries, +Max, -Sample, -Rest) is det.
%
% Sample is the prefix of Entries of length at most Max. Rest is how
% many entries were left out.

pkgdelta:sample_entries(Entries, Max, Sample, Rest) :-
  length(Entries, N),
  ( N =< Max ->
      Sample = Entries,
      Rest = 0
  ; length(Sample, Max),
    append(Sample, _, Entries),
    Rest is N - Max
  ).
