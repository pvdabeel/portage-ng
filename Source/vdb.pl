/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> VDB
Tracks installed packages on the system by scanning the VDB (var/db/pkg)
directory tree. Provides predicates to synchronise the installed-package
metadata into the Prolog cache, to scaffold repository directory structures,
and to copy static graph assets.
*/

:- module(vdb, []).

% =============================================================================
%  VDB declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  VDB synchronisation
% -----------------------------------------------------------------------------

%! vdb:sync is det.
%
% Refreshes the in-memory installed-package metadata by scanning the VDB
% directory. Retracts all existing `installed` metadata for the portage
% repository and re-asserts a fact for every package found on disk.

vdb:sync :-
  retractall(cache:entry_metadata(portage,_,installed,_)),
  forall(vdb:find_installed_pkg(portage://Entry),
         (asserta(cache:entry_metadata(portage,Entry,installed,true)))).


%! vdb:find_installed_pkg(-RepoEntry) is nondet.
%
% Enumerates installed packages from the host-specific VDB directory
% (config:pkg_directory/2). On backtracking, unifies RepoEntry with
% each portage://Category/Package-Version found on disk.

vdb:find_installed_pkg(portage://Entry) :-
  config:hostname(Hostname),
  config:pkg_directory(Hostname,Directory),
  os:directory_content(Directory,Category),
  os:compose_path(Directory,Category,CategoryDir),
  os:directory_content(CategoryDir,Package),
  os:compose_path(Category,Package,Entry).


% -----------------------------------------------------------------------------
%  Repository directory scaffolding
% -----------------------------------------------------------------------------

%! vdb:create_repository_dirs(+Repository, +Directory) is det.
%
% Ensures that Directory contains a subdirectory for every category
% in Repository. Existing subdirectories are left untouched.

vdb:create_repository_dirs(Repository,Directory) :-
  forall(Repository:category(C),
    (os:compose_path(Directory,C,Subdir),
     (system:exists_directory(Subdir);
      system:make_directory(Subdir)))).


%! vdb:make_repository_dirs(+Repository, +Directory) is det.
%
% Creates Directory and a subdirectory for every category in Repository.
% Unlike create_repository_dirs/2, this assumes Directory does not yet
% exist.

vdb:make_repository_dirs(Repository,Directory) :-
  os:ensure_directory_path(Directory),
  forall(Repository:category(C),
    (os:compose_path(Directory,C,Subdir),
     os:make_directory(Subdir))).


% -----------------------------------------------------------------------------
%  Graph directory helpers
% -----------------------------------------------------------------------------

%! vdb:copy_graph_assets(+Directory) is det.
%
% Copies all static assets (.index.css, .proof.css, .meslo.ttf) into
% the repository graph Directory. Sources are resolved via
% config:graph_asset_source/2.

vdb:copy_graph_assets(Directory) :-
  vdb:copy_graph_asset(index_css, '.index.css', Directory),
  vdb:copy_graph_asset(proof_css, '.proof.css', Directory),
  vdb:copy_graph_asset(meslo_ttf, '.meslo.ttf', Directory),
  !.

%! vdb:copy_graph_asset(+Key, +TargetName, +Directory) is det.
%
% Copies the asset identified by Key to Directory/TargetName,
% overwriting any existing file. Warns on missing sources or copy
% failures.

vdb:copy_graph_asset(Key, TargetName, Directory) :-
  ( current_predicate(config:graph_asset_source/2),
    config:graph_asset_source(Key, Source),
    exists_file(Source)
  ->
    atomic_list_concat([Directory,'/',TargetName], Target),
    ( exists_file(Target) -> catch(delete_file(Target), _, true) ; true ),
    catch(copy_file(Source, Target), E,
          message:warning(['Failed to copy graph asset ', Source, ' -> ', Target, ' (', E, ')']))
  ; message:warning(['Missing graph asset source for ', Key, ' (or file not found)'])
  ).


% -----------------------------------------------------------------------------
%  VDB helpers (diagnostics)
% -----------------------------------------------------------------------------

%! vdb:outdated(+Category, +Name, -Installed, -Latest) is nondet.
%
% Succeeds when the VDB (pkg) repository contains Category/Name at an
% older version than the newest acceptable candidate in the portage
% repository. Useful as a diagnostic for validating --deep behaviour.
%
% Example:
%   ?- vdb:outdated('dev-libs', openssl, Installed, Latest).
%   Installed = pkg://'dev-libs/openssl-3.5.0',
%   Latest    = portage://'dev-libs/openssl-3.5.4'.

vdb:outdated(Category, Name, pkg://InstalledEntry, portage://LatestEntry) :-
  cache:ordered_entry(pkg, InstalledEntry, Category, Name, InstalledVer),
  preference:accept_keywords(K),
  once(query:search([repository(portage),category(Category),name(Name),keywords(K),version(LatestVer)],
                    portage://LatestEntry)),
  compare(>, LatestVer, InstalledVer).


% -----------------------------------------------------------------------------
%  VDB package contents
% -----------------------------------------------------------------------------

%! vdb:read_contents(+Entry, -Contents) is det.
%
% Reads and parses the CONTENTS file for the given VDB entry
% (Category/Name-Version). Contents is a list of terms:
% obj(Path, MD5, MTime), dir(Path), sym(Path, Target, MTime).

vdb:read_contents(Entry, Contents) :-
  config:hostname(Hostname),
  config:pkg_directory(Hostname, PkgDir),
  atomic_list_concat([PkgDir, '/', Entry, '/CONTENTS'], File),
  ( exists_file(File) ->
    read_file_to_string(File, Str, []),
    split_string(Str, "\n", "\n", Lines),
    findall(P, (member(L, Lines), L \== "", vdb:parse_contents_line(L, P)), Contents)
  ; Contents = []
  ).


%! vdb:parse_contents_line(+Line, -Parsed) is semidet.
%
% Parses a single CONTENTS line into a structured term.

vdb:parse_contents_line(Line, obj(Path, MD5, MTime)) :-
  string_concat("obj ", Rest, Line),
  split_string(Rest, " ", "", Parts),
  length(Parts, Len), Len >= 3,
  nth1(Len, Parts, MTimeS),
  N1 is Len - 1, nth1(N1, Parts, MD5S),
  N2 is Len - 2, length(PP, N2),
  append(PP, [MD5S, MTimeS], Parts),
  maplist([S,A]>>atom_string(A,S), PP, PPA),
  atomic_list_concat(PPA, ' ', Path),
  atom_string(MD5, MD5S),
  atom_string(MTime, MTimeS), !.

vdb:parse_contents_line(Line, dir(Path)) :-
  string_concat("dir ", PathS, Line),
  atom_string(Path, PathS), !.

vdb:parse_contents_line(Line, sym(Path, Target, MTime)) :-
  string_concat("sym ", Rest, Line),
  ( sub_string(Rest, Before, 4, _, " -> ") ->
    sub_string(Rest, 0, Before, _, PathS),
    After is Before + 4,
    sub_string(Rest, After, _, 0, TRest),
    split_string(TRest, " ", "", TParts),
    length(TParts, TLen),
    ( TLen >= 2 ->
      last(TParts, MTimeS),
      TLen1 is TLen - 1, length(TP, TLen1),
      append(TP, [MTimeS], TParts),
      maplist([S,A]>>atom_string(A,S), TP, TPA),
      atomic_list_concat(TPA, ' ', Target)
    ; TParts = [TS],
      atom_string(Target, TS),
      MTimeS = "0"
    ),
    atom_string(Path, PathS),
    atom_string(MTime, MTimeS)
  ; atom_string(Path, Rest),
    Target = '', MTime = '0'
  ), !.


%! vdb:print_contents(+Entry) is det.
%
% Prints the file listing for an installed package.

vdb:print_contents(Entry) :-
  vdb:read_contents(Entry, Contents),
  ( Contents == [] ->
    format('No CONTENTS found for ~w~n', [Entry])
  ; forall(member(Item, Contents),
      vdb:print_contents_item(Item))
  ).

vdb:print_contents_item(obj(Path, _MD5, _MTime)) :-
  format('~w~n', [Path]).
vdb:print_contents_item(dir(Path)) :-
  format('~w/~n', [Path]).
vdb:print_contents_item(sym(Path, Target, _MTime)) :-
  format('~w -> ~w~n', [Path, Target]).


% -----------------------------------------------------------------------------
%  VDB file ownership
% -----------------------------------------------------------------------------

%! vdb:find_owner(+Pattern, -Owners) is det.
%
% Finds installed packages owning files matching Pattern.
% Pattern starting with / is matched as a full path; otherwise
% matched as a basename.

vdb:find_owner(Pattern, Owners) :-
  atom_string(Pattern, PS),
  findall(Entry-Path,
    ( vdb:find_installed_pkg(portage://Entry),
      vdb:read_contents(Entry, Contents),
      member(Item, Contents),
      vdb:contents_item_path(Item, Path),
      vdb:path_matches(PS, Path)
    ),
    Owners).


%! vdb:contents_item_path(+Item, -Path) is det.
%
% Extracts the filesystem path from a CONTENTS item.

vdb:contents_item_path(obj(P,_,_), P).
vdb:contents_item_path(dir(P), P).
vdb:contents_item_path(sym(P,_,_), P).


%! vdb:path_matches(+PatternStr, +PathAtom) is semidet.
%
% True when the pattern matches the path. Full path if Pattern
% starts with /, basename match otherwise.

vdb:path_matches(PS, Path) :-
  atom_string(Path, PathS),
  ( sub_string(PS, 0, 1, _, "/") ->
    PathS == PS
  ; file_base_name(Path, Base),
    atom_string(Base, BaseS),
    BaseS == PS
  ).


%! vdb:print_owner(+Pattern) is det.
%
% Prints packages owning files matching Pattern.

vdb:print_owner(Pattern) :-
  vdb:find_owner(Pattern, Owners),
  ( Owners == [] ->
    format('No package owns ~w~n', [Pattern])
  ; forall(member(Entry-Path, Owners),
      format('~w (~w)~n', [Entry, Path]))
  ).


% -----------------------------------------------------------------------------
%  VDB installed package size
% -----------------------------------------------------------------------------

%! vdb:package_size(+Entry, -TotalSize) is det.
%
% Calculates total disk space used by an installed package's files.

vdb:package_size(Entry, TotalSize) :-
  vdb:read_contents(Entry, Contents),
  aggregate_all(sum(S),
    ( member(obj(Path,_,_), Contents),
      catch(size_file(Path, S), _, S = 0)
    ),
    TotalSize).


%! vdb:format_size(+Bytes, -Formatted) is det.
%
% Formats a byte count into a human-readable string (KiB, MiB, GiB).

vdb:format_size(Bytes, Formatted) :-
  ( Bytes >= 1073741824 ->
    V is Bytes / 1073741824,
    format(atom(Formatted), '~2f GiB', [V])
  ; Bytes >= 1048576 ->
    V is Bytes / 1048576,
    format(atom(Formatted), '~2f MiB', [V])
  ; Bytes >= 1024 ->
    V is Bytes / 1024,
    format(atom(Formatted), '~2f KiB', [V])
  ; format(atom(Formatted), '~w B', [Bytes])
  ).


%! vdb:print_size(+Entry) is det.
%
% Prints the total disk space used by an installed package.

vdb:print_size(Entry) :-
  vdb:package_size(Entry, TotalSize),
  vdb:format_size(TotalSize, Formatted),
  format('~w: ~w~n', [Entry, Formatted]).


% -----------------------------------------------------------------------------
%  VDB package verification
% -----------------------------------------------------------------------------

%! vdb:verify_package(+Entry) is det.
%
% Verifies installed files against CONTENTS checksums. Reports
% modified and missing files.

vdb:verify_package(Entry) :-
  vdb:read_contents(Entry, Contents),
  ( Contents == [] ->
    format('No CONTENTS found for ~w~n', [Entry])
  ; include([obj(_,_,_)]>>true, Contents, ObjFiles),
    length(ObjFiles, Total),
    format('Verifying ~w files for ~w...~n', [Total, Entry]),
    vdb:verify_files(ObjFiles, 0, 0, Modified, Missing),
    OK is Total - Modified - Missing,
    format('  ~w OK, ~w modified, ~w missing~n', [OK, Modified, Missing])
  ).


%! vdb:verify_files(+Files, +ModAcc, +MissAcc, -Modified, -Missing) is det.

vdb:verify_files([], M, Mi, M, Mi).

vdb:verify_files([obj(Path, MD5, _MTime)|Rest], MAcc, MiAcc, M, Mi) :-
  ( exists_file(Path) ->
    ( sanitize:not_symlink(Path) ->
      catch(
        ( size_file(Path, Size),
          ( Size > 1073741824 ->
            MAcc1 = MAcc, MiAcc1 = MiAcc
          ; crypto_file_hash(Path, Hash, [algorithm(md5), encoding(hex)]),
            ( Hash == MD5 ->
              MAcc1 = MAcc
            ; MAcc1 is MAcc + 1,
              format('  MOD ~w~n', [Path])
            ),
            MiAcc1 = MiAcc
          )
        ),
        _,
        ( MAcc1 = MAcc, MiAcc1 = MiAcc )
      )
    ; MAcc1 = MAcc, MiAcc1 = MiAcc
    )
  ; MiAcc1 is MiAcc + 1,
    MAcc1 = MAcc,
    format('  !!! ~w (missing)~n', [Path])
  ),
  vdb:verify_files(Rest, MAcc1, MiAcc1, M, Mi).


% -----------------------------------------------------------------------------
%  VDB package executables
% -----------------------------------------------------------------------------

%! vdb:package_executables(+Entry, -Executables) is det.
%
% Returns executable files (binaries in PATH directories) installed
% by a package.

vdb:package_executables(Entry, Executables) :-
  vdb:read_contents(Entry, Contents),
  include(vdb:is_executable_entry, Contents, Executables).


%! vdb:is_executable_entry(+Item) is semidet.
%
% True when Item is an obj or sym in a standard executable directory.

vdb:is_executable_entry(obj(Path, _, _)) :- vdb:is_bin_path(Path).
vdb:is_executable_entry(sym(Path, _, _)) :- vdb:is_bin_path(Path).


%! vdb:is_bin_path(+Path) is semidet.

vdb:is_bin_path(Path) :-
  atom_string(Path, PS),
  ( sub_string(PS, 0, _, _, "/usr/bin/")
  ; sub_string(PS, 0, _, _, "/usr/sbin/")
  ; sub_string(PS, 0, _, _, "/bin/")
  ; sub_string(PS, 0, _, _, "/sbin/")
  ; sub_string(PS, 0, _, _, "/usr/local/bin/")
  ; sub_string(PS, 0, _, _, "/usr/local/sbin/")
  ).


%! vdb:print_executables(+Entry) is det.
%
% Prints executables provided by an installed package.

vdb:print_executables(Entry) :-
  vdb:package_executables(Entry, Execs),
  ( Execs == [] ->
    format('No executables found for ~w~n', [Entry])
  ; forall(member(Item, Execs),
      ( vdb:contents_item_path(Item, Path),
        file_base_name(Path, Base),
        format('~w~n', [Base])
      ))
  ).


% -----------------------------------------------------------------------------
%  VDB target resolution
% -----------------------------------------------------------------------------

%! vdb:entry_matches(+Entry, +Query) is semidet.
%
% True when the VDB entry (Category/Name-Version) matches the user
% query (which may be Category/Name, just Name, or a full CPV).

vdb:entry_matches(Entry, Query) :-
  atom_string(Entry, ES),
  atom_string(Query, QS),
  ( ES == QS -> true
  ; string_concat(QS, Rest, ES),
    string_codes(Rest, [0'-|_])
  ; split_string(ES, "/", "", [_, PVS]),
    ( string_concat(QS, Rest2, PVS),
      ( Rest2 == "" ; string_codes(Rest2, [0'-|_]) )
    )
  ).


%! vdb:resolve_vdb_entries(+Query, -Entries) is det.
%
% Resolves a user query to matching installed VDB entries.

vdb:resolve_vdb_entries(Query, Entries) :-
  findall(Entry,
    ( vdb:find_installed_pkg(portage://Entry),
      vdb:entry_matches(Entry, Query)
    ),
    Entries).


% -----------------------------------------------------------------------------
%  VDB reverse dependencies
% -----------------------------------------------------------------------------

%! vdb:reverse_deps(+Category, +Name, -RevDeps) is det.
%
% Finds packages whose dependencies reference Category/Name.

vdb:reverse_deps(Category, Name, RevDeps) :-
  findall(Repo://Entry,
    ( member(DepKey, [rdepend, depend, bdepend, pdepend, idepend]),
      cache:entry_metadata(Repo, Entry, DepKey, DepTree),
      vdb:dep_tree_mentions(DepTree, Category, Name)
    ),
    RevDeps0),
  sort(RevDeps0, RevDeps).


%! vdb:dep_tree_mentions(+DepTree, +Category, +Name) is semidet.
%
% True when the dependency tree contains a reference to Category/Name.

vdb:dep_tree_mentions(package_dependency(_,_,C,N,_,_,_,_), C, N) :- !.
vdb:dep_tree_mentions(all_of_group(Deps), C, N) :-
  member(D, Deps), vdb:dep_tree_mentions(D, C, N), !.
vdb:dep_tree_mentions(any_of_group(Deps), C, N) :-
  member(D, Deps), vdb:dep_tree_mentions(D, C, N), !.
vdb:dep_tree_mentions(use_conditional_group(_,_,_,Deps), C, N) :-
  member(D, Deps), vdb:dep_tree_mentions(D, C, N), !.


% -----------------------------------------------------------------------------
%  VDB package import
% -----------------------------------------------------------------------------

%! vdb:import_package(+Category, +Name, +Version) is det.
%
% Creates a minimal VDB entry for manually installed software.
% Writes CATEGORY, PF, SLOT, EAPI, repository, and an empty
% CONTENTS file to the VDB pkg directory.

vdb:import_package(Category, Name, Version) :-
  ( sanitize:safe_portage_category(Category) -> true
  ; throw(error(permission_error(create, vdb_entry, Category),
                context(vdb:import_package/3, 'Invalid category name')))
  ),
  ( sanitize:safe_portage_name(Name) -> true
  ; throw(error(permission_error(create, vdb_entry, Name),
                context(vdb:import_package/3, 'Invalid package name')))
  ),
  ( sanitize:safe_path_component(Version) -> true
  ; throw(error(permission_error(create, vdb_entry, Version),
                context(vdb:import_package/3, 'Invalid version string')))
  ),
  config:hostname(Hostname),
  config:pkg_directory(Hostname, PkgDir),
  atomic_list_concat([Name, '-', Version], PV),
  atomic_list_concat([PkgDir, '/', Category], CatDir),
  atomic_list_concat([CatDir, '/', PV], EntryDir),
  ( \+ exists_directory(CatDir) -> make_directory_path(CatDir) ; true ),
  ( exists_directory(EntryDir) ->
    message:warning(['VDB entry already exists: ', Category, '/', PV]),
    format('  Overwriting metadata in ~w~n', [EntryDir])
  ; make_directory_path(EntryDir)
  ),
  vdb:write_vdb_file(EntryDir, 'CATEGORY', Category),
  vdb:write_vdb_file(EntryDir, 'PF', PV),
  vdb:write_vdb_file(EntryDir, 'SLOT', '0'),
  vdb:write_vdb_file(EntryDir, 'EAPI', '8'),
  vdb:write_vdb_file(EntryDir, 'repository', 'manual'),
  vdb:write_vdb_file(EntryDir, 'CONTENTS', ''),
  vdb:write_vdb_file(EntryDir, 'DESCRIPTION', 'Manually imported package'),
  atomic_list_concat([Category, '/', PV], FullEntry),
  asserta(cache:entry_metadata(portage, FullEntry, installed, true)).


%! vdb:write_vdb_file(+Dir, +FileName, +Content) is det.
%
% Writes a single VDB metadata file.

vdb:write_vdb_file(Dir, FileName, Content) :-
  atomic_list_concat([Dir, '/', FileName], Path),
  setup_call_cleanup(
    open(Path, write, Out),
    ( atom_string(Content, ContentStr),
      write(Out, ContentStr),
      ( ContentStr \== "" -> nl(Out) ; true )
    ),
    close(Out)
  ).


%! vdb:split_pv(+PVString, -Name, -Version) is det.
%
% Splits a package-version string like "foo-1.2.3" into Name and
% Version. Finds the last hyphen followed by a digit as the
% version boundary. Falls back to Name=PV, Version='0'.

vdb:split_pv(PVStr, Name, Version) :-
  string_codes(PVStr, Codes),
  ( vdb:find_version_boundary(Codes, 0, -1, BoundaryPos),
    BoundaryPos >= 0 ->
    sub_string(PVStr, 0, BoundaryPos, _, NameStr),
    BP1 is BoundaryPos + 1,
    sub_string(PVStr, BP1, _, 0, VerStr),
    atom_string(Name, NameStr),
    atom_string(Version, VerStr)
  ; atom_string(Name, PVStr),
    Version = '0'
  ).


%! vdb:find_version_boundary(+Codes, +Pos, +LastFound, -Boundary) is det.
%
% Walks code list finding the last position where a hyphen is
% followed by a digit (version boundary).

vdb:find_version_boundary([], _, Found, Found).

vdb:find_version_boundary([0'-,D|Rest], Pos, _, Boundary) :-
  D >= 0'0, D =< 0'9, !,
  Pos1 is Pos + 2,
  vdb:find_version_boundary(Rest, Pos1, Pos, Boundary).

vdb:find_version_boundary([_|Rest], Pos, Acc, Boundary) :-
  Pos1 is Pos + 1,
  vdb:find_version_boundary(Rest, Pos1, Acc, Boundary).


% -----------------------------------------------------------------------------
%  Unmanaged files detection
% -----------------------------------------------------------------------------

%! vdb:build_contents_index(-OwnedSet) is det.
%
% Builds a red-black tree index of all file paths tracked by
% installed packages. Efficient for O(log n) membership checks.

vdb:build_contents_index(OwnedSet) :-
  rb_empty(Empty),
  findall(Path,
    ( vdb:find_installed_pkg(portage://Entry),
      vdb:read_contents(Entry, Contents),
      member(Item, Contents),
      vdb:contents_item_path(Item, Path)
    ),
    AllPaths),
  foldl([P, TreeIn, TreeOut]>>(
    ( rb_lookup(P, _, TreeIn) ->
      TreeOut = TreeIn
    ; rb_insert(TreeIn, P, true, TreeOut)
    )
  ), AllPaths, Empty, OwnedSet).


%! vdb:find_unmanaged(+Dir, +OwnedSet, -Unmanaged) is det.
%
% Recursively scans Dir and returns files not present in OwnedSet.
% Limits recursion depth and skips symbolic links to directories
% to prevent symlink traversal attacks and unbounded recursion.

vdb:find_unmanaged(Dir, OwnedSet, Unmanaged) :-
  vdb:find_unmanaged(Dir, OwnedSet, 64, Unmanaged).


%! vdb:find_unmanaged(+Dir, +OwnedSet, +MaxDepth, -Unmanaged) is det.

vdb:find_unmanaged(_Dir, _OwnedSet, MaxDepth, []) :-
  MaxDepth =< 0, !.

vdb:find_unmanaged(Dir, OwnedSet, MaxDepth, Unmanaged) :-
  catch(
    directory_files(Dir, Entries0),
    _, Entries0 = []
  ),
  exclude(vdb:is_dot_entry, Entries0, Entries),
  Depth1 is MaxDepth - 1,
  foldl(vdb:check_unmanaged_entry(Dir, OwnedSet, Depth1), Entries, [], Unmanaged0),
  reverse(Unmanaged0, Unmanaged).


%! vdb:is_dot_entry(+Name) is semidet.

vdb:is_dot_entry('.').
vdb:is_dot_entry('..').


%! vdb:check_unmanaged_entry(+Dir, +OwnedSet, +MaxDepth, +Name, +Acc, -NewAcc) is det.

vdb:check_unmanaged_entry(Dir, OwnedSet, MaxDepth, Name, Acc, NewAcc) :-
  atomic_list_concat([Dir, '/', Name], FullPath),
  ( exists_directory(FullPath) ->
    ( sanitize:not_symlink(FullPath) ->
      vdb:find_unmanaged(FullPath, OwnedSet, MaxDepth, SubUnmanaged),
      append(SubUnmanaged, Acc, NewAcc)
    ; NewAcc = Acc
    )
  ; ( rb_lookup(FullPath, _, OwnedSet) ->
      NewAcc = Acc
    ; NewAcc = [FullPath|Acc]
    )
  ).