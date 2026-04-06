/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

% -----------------------------------------------------------------------------
%  Action: VDB queries (contents, owner, size, verify, executables)
% -----------------------------------------------------------------------------

%! action:process_vdb_query(+QueryType, +Args) is det.
%
% Dispatches VDB query commands. For --owner, Args are file paths;
% for all others, Args are package targets.

action:process_vdb_query(_, []) :-
  !, message:failure('No targets specified.').

action:process_vdb_query(owner, Args) :-
  !,
  forall(member(Arg, Args),
    ( message:header(['Packages owning ', Arg]),
      nl,
      vdb:print_owner(Arg)
    )).

action:process_vdb_query(QueryType, Args) :-
  forall(member(Arg, Args),
    ( vdb:resolve_vdb_entries(Arg, Entries),
      ( Entries == [] ->
        message:warning(['Not installed: ', Arg])
      ; forall(member(Entry, Entries),
          run_vdb_query(QueryType, Entry))
      )
    )).


%! action:run_vdb_query(+QueryType, +Entry) is det.

action:run_vdb_query(contents, Entry) :-
  message:header(['Contents of ', Entry]),
  nl,
  vdb:print_contents(Entry).

action:run_vdb_query(size, Entry) :-
  vdb:print_size(Entry).

action:run_vdb_query(verify, Entry) :-
  vdb:verify_package(Entry).

action:run_vdb_query(executables, Entry) :-
  message:header(['Executables from ', Entry]),
  nl,
  vdb:print_executables(Entry).


% -----------------------------------------------------------------------------
%  Action: FIX-LINKAGE
% -----------------------------------------------------------------------------

%! action:process_fix_linkage(+Args, +Options) is det.
%
% Scans installed packages for broken shared library linkage and
% outputs packages that need rebuilding.

action:process_fix_linkage(_Args, _Options) :-
  ( predicate_property(linkage:check(_), defined) ->
    linkage:check(Results),
    ( Results == [] ->
      message:inform('No broken linkage detected.')
    ; message:header(['Packages with broken linkage']),
      nl,
      forall(member(Entry-Libs, Results),
        ( format('  ~w~n', [Entry]),
          forall(member(Lib, Libs),
            format('    broken: ~w~n', [Lib]))
        )),
      nl,
      length(Results, N),
      format('~w package(s) need rebuilding.~n', [N])
    )
  ; message:warning('Linkage checking module not loaded.')
  ).


% -----------------------------------------------------------------------------
%  Action: REPORT
% -----------------------------------------------------------------------------

%! action:process_report(+Options) is det.
%
% Displays a summary of potential problems with installed packages.

action:process_report(_Options) :-
  ( predicate_property(report:check(_), defined) ->
    report:check(Results),
    report:print_results(Results)
  ; message:warning('Report module not loaded.')
  ).


% -----------------------------------------------------------------------------
%  Action: REVERSE DEPENDENCIES
% -----------------------------------------------------------------------------

%! action:process_rdeps(+Args) is det.
%
% Shows which packages depend on the given targets.

action:process_rdeps([]) :-
  !, message:failure('No targets specified.').

action:process_rdeps(Args) :-
  forall(member(Arg, Args),
    ( atom_codes(Arg, Codes),
      ( phrase(eapi:qualified_target(Q), Codes),
        once(kb:query(Q, _Repo://Entry))
      -> query:search([category(Cat), name(Name)], _://Entry),
         message:header(['Reverse dependencies of ', Cat, '/', Name]),
         nl,
         vdb:reverse_deps(Cat, Name, RevDeps),
         ( RevDeps == [] ->
           format('  (none found)~n')
         ; length(RevDeps, Count),
           forall(member(RD, RevDeps), format('  ~w~n', [RD])),
           nl,
           format('~w reverse dependency(ies) found.~n', [Count])
         )
      ; message:warning(['Package not found: ', Arg])
      )
    )).


% -----------------------------------------------------------------------------
%  Action: UNUSED DISTFILES
% -----------------------------------------------------------------------------

%! action:process_unused_distfiles(+Options) is det.
%
% Lists distfiles not referenced by any installed package.

action:process_unused_distfiles(_Options) :-
  ( predicate_property(distfiles:orphans(_,_), defined) ->
    distfiles:get_location(DistDir),
    message:header(['Unused distfiles in ', DistDir]),
    nl,
    distfiles:orphans(portage, Orphans),
    ( Orphans == [] ->
      message:inform('No unused distfiles found.')
    ; length(Orphans, Count),
      forall(member(F, Orphans), format('  ~w~n', [F])),
      nl,
      format('~w unused distfile(s).~n', [Count])
    )
  ; message:warning('Distfiles module not available.')
  ).


% -----------------------------------------------------------------------------
%  Action: IMPORT (track unpackaged software in VDB)
% -----------------------------------------------------------------------------

%! action:process_import(+Args, +Options) is det.
%
% Creates VDB entries for manually installed software so the package
% manager can track it. Accepts targets as Category/Name-Version or
% Category/Name (defaults to version 0).

action:process_import([], _Options) :-
  !,
  message:failure('Usage: portage-ng --import cat/name-version [cat/name-version ...]').

action:process_import(Args, Options) :-
  ( memberchk(pretend(true), Options) -> Pretend = true ; Pretend = false ),
  forall(member(Arg, Args),
    do_import_one(Arg, Pretend)
  ).


%! action:do_import_one(+Arg, +Pretend) is det.
%
% Imports a single package specification into the VDB.

action:do_import_one(Arg, Pretend) :-
  atom_string(Arg, ArgStr),
  ( split_string(ArgStr, "/", "", [CatStr, PVStr]) ->
    atom_string(Category, CatStr),
    vdb:split_pv(PVStr, Name, Version),
    ( Pretend == true ->
      format('Would import: ~w/~w-~w~n', [Category, Name, Version])
    ; vdb:import_package(Category, Name, Version),
      format('Imported: ~w/~w-~w~n', [Category, Name, Version])
    )
  ; message:warning(['Invalid import target (expected cat/name-version): ', Arg])
  ).


% -----------------------------------------------------------------------------
%  Action: UNMANAGED FILES
% -----------------------------------------------------------------------------

%! action:process_unmanaged_files(+Args) is det.
%
% Finds files on the filesystem not tracked by any installed package.
% Args are directories to scan; defaults to /usr if none given.

action:process_unmanaged_files(Args) :-
  ( Args == [] -> Dirs = ['/usr'] ; Dirs = Args ),
  message:header(['Building file ownership index...']),
  nl,
  vdb:build_contents_index(OwnedSet),
  rb_size(OwnedSet, IndexSize),
  format('  Indexed ~w files from installed packages.~n~n', [IndexSize]),
  forall(member(DirAtom, Dirs),
    ( atom_string(DirAtom, DirStr),
      ( exists_directory(DirStr) ->
        message:header(['Scanning ', DirAtom, ' for unmanaged files...']),
        nl,
        vdb:find_unmanaged(DirAtom, OwnedSet, Unmanaged),
        ( Unmanaged == [] ->
          format('  No unmanaged files found in ~w.~n', [DirAtom])
        ; length(Unmanaged, Count),
          forall(member(F, Unmanaged), format('  ~w~n', [F])),
          nl,
          format('~w unmanaged file(s) in ~w.~n', [Count, DirAtom])
        )
      ; message:warning(['Directory does not exist: ', DirAtom])
      )
    )).