/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> SETS
Computed package sets derived from the installed-package database (VDB) and
the portage tree.

These mirror the dynamically computed sets that traditional emerge exposes
through its built-in set classes.  Unlike the file-backed named sets handled
by `preference:set/2`, the members of these sets are computed on demand by
comparing the installed packages against the highest visible ebuild in the
tree:

  - installed        all installed packages, as `cat/name:slot` atoms
                     (mirrors portage.sets.dbapi.EverythingSet)
  - live-rebuild     installed packages carrying the `live` PROPERTY
                     (mirrors a PROPERTIES=live VariableSet)
  - changed-subslot  installed packages where the highest visible ebuild has
                     a different subslot than the installed version
                     (mirrors portage.sets.dbapi.SubslotChangedSet)
  - downgrade        installed packages where the highest visible ebuild
                     version is lower than the installed version
                     (mirrors portage.sets.dbapi.DowngradeSet)
  - unavailable      installed packages for which no visible ebuild exists
                     for the same category/name:slot
                     (mirrors portage.sets.dbapi.UnavailableSet)
  - rebuilt-binaries binary packages whose BUILD_TIME differs from the
                     installed package of the exact same version, as
                     `=cat/name-version` atoms
                     (mirrors portage.sets.dbapi.RebuiltBinaries)
  - unavailable-binaries
                     installed packages for which no binary package of the
                     exact same version is available, as `cat/name:slot`
                     atoms (mirrors portage.sets.dbapi.UnavailableBinaries)
  - security         packages needing upgrade for an unapplied GLSA that
                     currently affects the system (`=cat/name-version`
                     atoms; mirrors portage.sets.security.NewAffectedSet,
                     the Portage default for @security)
  - affected         same, including already-applied GLSAs
                     (mirrors AffectedSet)
  - new-affected     alias of security (explicit NewAffectedSet name)
  - new-glsa         remediation atoms from unapplied GLSAs
                     (mirrors NewGlsaSet)
  - preserved-rebuild
                     installed packages that consume a library kept only by
                     FEATURES=preserve-libs (`cat/name:slot` atoms; mirrors
                     portage.sets.libs.PreservedLibraryConsumerSet)
  - changed-deps     installed packages whose VDB RDEPEND/PDEPEND no longer
                     match the same-version tree ebuild after use-reduce and
                     slot-operator stripping (`=cat/name-version` atoms;
                     mirrors portage.sets.dbapi.ChangedDepsSet, with libc
                     inject stripping as in emerge's --changed-deps path)

The expansion entry point is `sets:expand/2`; `eapi:substitute_sets/2`
recognises the names enumerated by `sets:is_computed_set/1` and replaces an
`@<name>` reference with the resolved target atoms. File-backed and world
members that are themselves `@name` references are expanded recursively
(cycle or unknown name reached from inside a set is a hard error).
*/

:- module(sets, []).

:- use_module(library(http/json)).

% =============================================================================
%  SETS declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Computed set registry
% -----------------------------------------------------------------------------

%! sets:is_computed_set(?Name) is nondet.
%
% True for each computed set name recognised by sets:expand/2.

sets:is_computed_set(installed).
sets:is_computed_set('live-rebuild').
sets:is_computed_set('changed-subslot').
sets:is_computed_set(downgrade).
sets:is_computed_set(unavailable).
sets:is_computed_set('rebuilt-binaries').
sets:is_computed_set('unavailable-binaries').
sets:is_computed_set(security).
sets:is_computed_set(affected).
sets:is_computed_set('new-affected').
sets:is_computed_set('new-glsa').
sets:is_computed_set('preserved-rebuild').
sets:is_computed_set('changed-deps').


%! sets:expand(+Name, -Targets) is det.
%
% Resolves a computed set name to a sorted list of target atoms
% (`cat/name:slot` or `=cat/name-version` for security / changed-deps sets).
% Yields [] for unknown names.

sets:expand(installed, Targets) :-
  !,
  sets:installed_set(Targets).

sets:expand('live-rebuild', Targets) :-
  !,
  sets:live_rebuild_set(Targets).

sets:expand('changed-subslot', Targets) :-
  !,
  sets:changed_subslot_set(Targets).

sets:expand(downgrade, Targets) :-
  !,
  sets:downgrade_set(Targets).

sets:expand(unavailable, Targets) :-
  !,
  sets:unavailable_set(Targets).

sets:expand('rebuilt-binaries', Targets) :-
  !,
  sets:rebuilt_binaries_set(Targets).

sets:expand('unavailable-binaries', Targets) :-
  !,
  sets:unavailable_binaries_set(Targets).

sets:expand(security, Targets) :-
  !,
  glsa:security_atoms(new_affected, Targets).

sets:expand(affected, Targets) :-
  !,
  glsa:security_atoms(affected, Targets).

sets:expand('new-affected', Targets) :-
  !,
  glsa:security_atoms(new_affected, Targets).

sets:expand('new-glsa', Targets) :-
  !,
  glsa:security_atoms(new_glsa, Targets).

sets:expand('preserved-rebuild', Targets) :-
  !,
  sets:preserved_rebuild_set(Targets).

sets:expand('changed-deps', Targets) :-
  !,
  sets:changed_deps_set(Targets).

sets:expand(_, []).


% -----------------------------------------------------------------------------
%  installed set
% -----------------------------------------------------------------------------

%! sets:installed_set(-Targets) is det.
%
% All installed packages as sorted `cat/name:slot` atoms.

sets:installed_set(Targets) :-
  findall(Atom,
          ( knowledgebase:vdb_repository(VdbRepo),
            query:search([category(C),name(N)], VdbRepo://Entry),
            sets:slot_atom(VdbRepo://Entry, C, N, Atom)
          ),
          Targets0),
  sort(Targets0, Targets).


% -----------------------------------------------------------------------------
%  live-rebuild set
% -----------------------------------------------------------------------------

%! sets:live_rebuild_set(-Targets) is det.
%
% Installed packages that carry the `live` PROPERTY.

sets:live_rebuild_set(Targets) :-
  findall(Atom,
          ( knowledgebase:vdb_repository(VdbRepo),
            query:search([category(C),name(N)], VdbRepo://Entry),
            sets:installed_is_live(VdbRepo://Entry),
            sets:slot_atom(VdbRepo://Entry, C, N, Atom)
          ),
          Targets0),
  sort(Targets0, Targets).


%! sets:installed_is_live(+Repo://+Entry) is semidet.
%
% True when the installed package carries the `live` PROPERTY.  Prefers the
% PROPERTIES recorded in the VDB cache (authoritative for what is actually
% installed, rather than the possibly-diverged tree ebuild).  When PROPERTIES
% has not been loaded into the cache for any installed entry -- e.g. before
% the next `--sync` repopulates kb.qlf -- it falls back to reading the
% on-disk VDB PROPERTIES file.

sets:installed_is_live(VdbRepo://Entry) :-
  query:search(properties(live), VdbRepo://Entry),
  !.

sets:installed_is_live(VdbRepo://Entry) :-
  \+ cache:entry_metadata(VdbRepo, Entry, properties, _),
  vdb:read_metadata_file(Entry, 'PROPERTIES', Properties),
  sets:properties_has_live(Properties).


%! sets:properties_has_live(+Properties) is semidet.
%
% True when a whitespace-separated PROPERTIES value contains the `live` token.

sets:properties_has_live(Properties) :-
  split_string(Properties, " ", "", Tokens),
  memberchk("live", Tokens).


% -----------------------------------------------------------------------------
%  changed-subslot set
% -----------------------------------------------------------------------------

%! sets:changed_subslot_set(-Targets) is det.
%
% Installed packages where the highest visible ebuild in the same slot has a
% different subslot than the installed version.

sets:changed_subslot_set(Targets) :-
  findall(Atom,
          ( knowledgebase:vdb_repository(VdbRepo),
            query:search([category(C),name(N)], VdbRepo://Entry),
            slotmeta:entry_slot_default(VdbRepo, Entry, Slot),
            sets:entry_subslot(VdbRepo://Entry, InstalledSub),
            once(( sets:tree_cn(C, N, TC, TN),
                   sets:highest_visible_in_slot(TC, TN, Slot, BestEntry, _) )),
            sets:entry_subslot(BestEntry, TreeSub),
            InstalledSub \== TreeSub,
            sets:cn_slot_atom(C, N, Slot, Atom)
          ),
          Targets0),
  sort(Targets0, Targets).


% -----------------------------------------------------------------------------
%  downgrade set
% -----------------------------------------------------------------------------

%! sets:downgrade_set(-Targets) is det.
%
% Installed packages where the highest visible ebuild version in the same slot
% is lower than the installed version.

sets:downgrade_set(Targets) :-
  findall(Atom,
          ( knowledgebase:vdb_repository(VdbRepo),
            query:search([category(C),name(N),version(InstalledVer)], VdbRepo://Entry),
            InstalledVer \== version_none,
            slotmeta:entry_slot_default(VdbRepo, Entry, Slot),
            once(( sets:tree_cn(C, N, TC, TN),
                   sets:highest_visible_in_slot(TC, TN, Slot, _, BestVer) )),
            eapi:version_compare(<, BestVer, InstalledVer),
            sets:cn_slot_atom(C, N, Slot, Atom)
          ),
          Targets0),
  sort(Targets0, Targets).


% -----------------------------------------------------------------------------
%  unavailable set
% -----------------------------------------------------------------------------

%! sets:unavailable_set(-Targets) is det.
%
% Installed packages for which no visible ebuild exists in the tree for the
% same category/name:slot.

sets:unavailable_set(Targets) :-
  findall(Atom,
          ( knowledgebase:vdb_repository(VdbRepo),
            query:search([category(C),name(N)], VdbRepo://Entry),
            slotmeta:entry_slot_default(VdbRepo, Entry, Slot),
            \+ ( sets:tree_cn(C, N, TC, TN),
                 sets:highest_visible_in_slot(TC, TN, Slot, _, _) ),
            sets:cn_slot_atom(C, N, Slot, Atom)
          ),
          Targets0),
  sort(Targets0, Targets).


% -----------------------------------------------------------------------------
%  rebuilt-binaries set
% -----------------------------------------------------------------------------

%! sets:rebuilt_binaries_set(-Targets) is det.
%
% Binary packages whose BUILD_TIME differs from the currently installed
% package of the exact same category/name/version, as `=cat/name-version`
% atoms.  Yields [] when no binpkg repository is registered.

sets:rebuilt_binaries_set(Targets) :-
  ( sets:binpkg_available ->
      knowledgebase:vdb_repository(VdbRepo),
      findall(Atom,
              ( cache:ordered_entry(binpkg, _, C, N, V),
                cache:ordered_entry(VdbRepo, InstalledEntry, C, N, V),
                sets:rebuilt_binary_for(VdbRepo://InstalledEntry, C, N, V),
                atom_concat('=', InstalledEntry, Atom)
              ),
              Targets0),
      sort(Targets0, Targets)
  ; Targets = []
  ).


%! sets:entry_has_rebuilt_binary(+VdbEntry) is semidet.
%
% A binary package of the installed entry's exact version exists whose
% BUILD_TIME differs from the installed copy's. Used by
% `--rebuilt-binaries` (candidate.pl) to replace the installed copy.

sets:entry_has_rebuilt_binary(VdbRepo://Entry) :-
  cache:ordered_entry(VdbRepo, Entry, C, N, V),
  sets:binpkg_available,
  sets:rebuilt_binary_for(VdbRepo://Entry, C, N, V).


%! sets:rebuilt_binary_for(+VdbEntry, +C, +N, +V) is semidet.

sets:rebuilt_binary_for(VdbRepo://Entry, C, N, V) :-
  sets:installed_build_time(VdbRepo://Entry, InstalledBuildTime),
  cache:ordered_entry(binpkg, BinEntry, C, N, V),
  cache:entry_metadata(binpkg, BinEntry, build_time, BinBuildTime),
  \+ sets:same_build_time(BinBuildTime, InstalledBuildTime),
  !.


%! sets:installed_build_time(+Repo://+Entry, -BuildTime) is semidet.
%
% Returns the installed package BUILD_TIME, preferring the VDB cache and
% falling back to the on-disk VDB BUILD_TIME file (authoritative even before
% the next `--sync` loads BUILD_TIME into the cache).

sets:installed_build_time(VdbRepo://Entry, BuildTime) :-
  ( query:search(build_time(BuildTime0), VdbRepo://Entry)
    -> BuildTime = BuildTime0
    ;  vdb:read_metadata_file(Entry, 'BUILD_TIME', BuildTime)
  ).


%! sets:binpkg_available is semidet.
%
% True when binpkg consumption is enabled (binpkg_exec:consumption_enabled/0:
% the config default or a --usepkg family flag; the config alone where
% binpkg_exec is not loaded) and a binpkg repository is registered.
% Refreshes the on-disk index first so externally produced binpkgs are
% visible.

sets:binpkg_available :-
  ( current_predicate(binpkg_exec:consumption_enabled/0)
    -> binpkg_exec:consumption_enabled
    ;  config:use_binpkg(true)
  ),
  ( current_predicate(binpkg_exec:ensure_index_fresh/0)
    -> catch(binpkg_exec:ensure_index_fresh, _, true)
    ;  true
  ),
  cache:repository(binpkg).


%! sets:same_build_time(+A, +B) is semidet.
%
% True when two BUILD_TIME values are equal.  Compares numerically when both
% parse as integers, falling back to atom equality otherwise.

sets:same_build_time(A, B) :-
  ( sets:build_time_number(A, NA),
    sets:build_time_number(B, NB)
    -> NA =:= NB
    ;  A == B
  ).


%! sets:build_time_number(+Value, -Number) is semidet.
%
% Coerces a BUILD_TIME atom/number to an integer.  Fails for non-numeric
% values.

sets:build_time_number(Value, Number) :-
  ( number(Value)
    -> Number = Value
    ;  atom_number(Value, Number)
  ).


% -----------------------------------------------------------------------------
%  unavailable-binaries set
% -----------------------------------------------------------------------------

%! sets:unavailable_binaries_set(-Targets) is det.
%
% Installed packages for which no binary package of the exact same
% category/name/version is available, as sorted `cat/name:slot` atoms.
% When no binpkg repository is registered, every installed package is
% considered to have no available binary.

sets:unavailable_binaries_set(Targets) :-
  ignore(sets:binpkg_available),
  knowledgebase:vdb_repository(VdbRepo),
  findall(Atom,
          ( cache:ordered_entry(VdbRepo, Entry, C, N, V),
            \+ cache:ordered_entry(binpkg, _, C, N, V),
            sets:slot_atom(VdbRepo://Entry, C, N, Atom)
          ),
          Targets0),
  sort(Targets0, Targets).


% -----------------------------------------------------------------------------
%  preserved-rebuild set
% -----------------------------------------------------------------------------

%! sets:preserved_rebuild_set(-Targets) is det.
%
% Installed packages that consume a library retained only by
% FEATURES=preserve-libs, as sorted `cat/name:slot` atoms.  Reads Portage's
% `preserved_libs_registry` JSON (see `config:preserved_libs_registry/1`) and
% matches consumers via VDB `NEEDED.ELF.2` soname fields.  Yields [] when the
% registry is missing or empty (preserve-libs inactive / nothing preserved).

sets:preserved_rebuild_set(Targets) :-
  ( sets:preserved_lib_paths(Paths),
    Paths \== []
  -> findall(Soname, (member(Path, Paths), sets:path_sonames(Path, Sonames), member(Soname, Sonames)), Sonames0),
     sort(Sonames0, Sonames),
     findall(OwnerAtom, (member(Path, Paths), sets:path_owner_atom(Path, OwnerAtom)), OwnerAtoms0),
     sort(OwnerAtoms0, OwnerAtoms),
     findall(Atom,
             ( knowledgebase:vdb_repository(VdbRepo),
               query:search([category(C), name(N)], VdbRepo://Entry),
               findall(Tok, query:search(needed_elf2(Tok), VdbRepo://Entry), Needed),
               Needed \== [],
               sets:needed_mentions_soname(Needed, Sonames),
               sets:slot_atom(VdbRepo://Entry, C, N, Atom),
               \+ memberchk(Atom, OwnerAtoms)
             ),
             Targets0),
     sort(Targets0, Targets)
  ; Targets = []
  ).


%! sets:preserved_lib_paths(-Paths) is det.
%
% Sorted absolute paths of libraries listed in the preserve-libs registry.

sets:preserved_lib_paths(Paths) :-
  ( sets:read_preserved_libs_registry(Dict) ->
      findall(Path,
              ( get_dict(_Key, Dict, Value),
                sets:registry_entry_paths(Value, EntryPaths),
                member(Path, EntryPaths)
              ),
              Paths0),
      sort(Paths0, Paths)
  ; Paths = []
  ).


%! sets:read_preserved_libs_registry(-Dict) is semidet.
%
% Loads the Portage preserved_libs_registry JSON object. Fails when the file
% is missing, empty, or unreadable.

sets:read_preserved_libs_registry(Dict) :-
  current_predicate(config:preserved_libs_registry/1),
  config:preserved_libs_registry(File),
  exists_file(File),
  catch(
    setup_call_cleanup(
      open(File, read, In, [encoding(utf8)]),
      json_read_dict(In, Dict, [default_tag(json)]),
      close(In)
    ),
    _,
    fail
  ),
  is_dict(Dict).


%! sets:registry_entry_paths(+Value, -Paths) is det.
%
% Extracts the path list from a registry value. Portage stores
% `[Cpv, Counter, Paths]` (JSON array); tolerate a bare path list.

sets:registry_entry_paths(Value, Paths) :-
  is_list(Value),
  Value = [_, _, Paths0],
  is_list(Paths0),
  !,
  Paths = Paths0.
sets:registry_entry_paths(Value, Paths) :-
  is_list(Value),
  !,
  Paths = Value.
sets:registry_entry_paths(_, []).


%! sets:path_sonames(+Path, -Sonames) is det.
%
% Candidate sonames derived from a preserved library path: the basename and
% successive `.N` truncations down to the `.so` stem (best-effort stand-in for
% Portage LinkageMap ELF soname lookup).

sets:path_sonames(Path, Sonames) :-
  file_base_name(Path, Base),
  sets:soname_truncations(Base, Sonames0),
  sort(Sonames0, Sonames).


%! sets:soname_truncations(+Name, -Names) is det.
%
% `[libfoo.so.1.2.3, libfoo.so.1.2, libfoo.so.1, libfoo.so]` style chain.
% Strips a trailing `.` + digits component repeatedly (from the right).

sets:soname_truncations(Name, [Name|Rest]) :-
  ( atomic_list_concat(Parts, '.', Name),
    Parts = [_, _|_],
    append(StemParts, [Last], Parts),
    StemParts \== [],
    atom_codes(Last, Codes),
    Codes \== [],
    maplist(between(0'0, 0'9), Codes)
  -> atomic_list_concat(StemParts, '.', Stem),
     sets:soname_truncations(Stem, Rest)
  ;  Rest = []
  ).


%! sets:needed_mentions_soname(+NeededTokens, +Sonames) is semidet.
%
% True when any NEEDED.ELF.2 token lists one of Sonames in its needed field.

sets:needed_mentions_soname(NeededTokens, Sonames) :-
  member(Tok, NeededTokens),
  sets:needed_token_libs(Tok, Libs),
  member(Lib, Libs),
  memberchk(Lib, Sonames),
  !.


%! sets:needed_token_libs(+Token, -Libs) is det.
%
% Parses `arch;object;soname;rpath;needed;multilib` and returns the comma-
% separated needed sonames (empty when the token is malformed).

sets:needed_token_libs(Token, Libs) :-
  atomic_list_concat(Fields, ';', Token),
  ( nth1(5, Fields, NeededField),
    NeededField \== ''
  -> atomic_list_concat(Libs0, ',', NeededField),
     exclude(=( ''), Libs0, Libs)
  ;  Libs = []
  ).


%! sets:path_owner_atom(+Path, -Atom) is nondet.
%
% Yields `cat/name:slot` atoms for installed packages that own Path.

sets:path_owner_atom(Path, Atom) :-
  vdb:find_owner(Path, Owners),
  member(Entry-_OwnedPath, Owners),
  knowledgebase:vdb_repository(VdbRepo),
  query:search([category(C), name(N)], VdbRepo://Entry),
  sets:slot_atom(VdbRepo://Entry, C, N, Atom).


% -----------------------------------------------------------------------------
%  changed-deps set
% -----------------------------------------------------------------------------

%! sets:changed_deps_set(-Targets) is det.
%
% Installed packages whose on-disk VDB RDEPEND/PDEPEND differ from the
% same-version tree ebuild after use-reduce (installed USE), slot-operator
% stripping (`:=`), and libc-inject stripping, as sorted `=cat/name-version`
% atoms.

sets:changed_deps_set(Targets) :-
  findall(Atom,
          ( knowledgebase:vdb_repository(VdbRepo),
            cache:ordered_entry(VdbRepo, Entry, C, N, Ver),
            Ver \== version_none,
            sets:tree_same_version(C, N, Ver, TreeRepo, TreeEntry),
            sets:entry_deps_outdated(VdbRepo://Entry, TreeRepo://TreeEntry),
            atom_concat('=', Entry, Atom)
          ),
          Targets0),
  sort(Targets0, Targets).


%! sets:entry_deps_outdated(+VdbEntry) is semidet.
%
% True when the installed entry has a same-version tree ebuild and the
% runtime dependency sets diverge. Used by `@changed-deps` and `--changed-deps`.

sets:entry_deps_outdated(VdbRepo://Entry) :-
  query:search([category(C), name(N), version(Ver)], VdbRepo://Entry),
  Ver \== version_none,
  sets:tree_same_version(C, N, Ver, TreeRepo, TreeEntry),
  sets:entry_deps_outdated(VdbRepo://Entry, TreeRepo://TreeEntry).


%! sets:entry_deps_outdated(+VdbEntry, +TreeEntry) is semidet.
%
% Compares use-reduced RDEPEND+PDEPEND of an installed entry against the
% matching tree ebuild.

sets:entry_deps_outdated(VdbRepo://Entry, TreeRepo://TreeEntry) :-
  findall(U, query:search(use(U), VdbRepo://Entry), Use),
  sets:vdb_runtime_deps(Entry, VdbDeps0),
  sets:runtime_deps_differ(VdbDeps0, Use, TreeRepo://TreeEntry).


%! sets:entry_slot_changed(+VdbEntry) is semidet.
%
% True when the installed entry has a same-version tree ebuild whose
% SLOT or sub-slot differs from the installed copy's. Used by
% `--changed-slot` (candidate.pl).

sets:entry_slot_changed(VdbRepo://Entry) :-
  query:search([category(C), name(N), version(Ver)], VdbRepo://Entry),
  Ver \== version_none,
  sets:tree_same_version(C, N, Ver, TreeRepo, TreeEntry),
  slotmeta:entry_slot_default(VdbRepo, Entry, InstalledSlot),
  slotmeta:entry_slot_default(TreeRepo, TreeEntry, TreeSlot),
  sets:entry_subslot(VdbRepo://Entry, InstalledSub),
  sets:entry_subslot(TreeRepo://TreeEntry, TreeSub),
  InstalledSlot/InstalledSub \== TreeSlot/TreeSub.


%! sets:runtime_deps_differ(+RecordedDeps, +Use, +TreeEntry) is semidet.
%
% True when a built package's recorded RDEPEND+PDEPEND (parsed EAPI
% dependency terms, from the VDB or a binpkg index record), use-reduced
% under the USE it was built with, no longer match the tree ebuild's
% RDEPEND+PDEPEND under the same USE. Shared by `@changed-deps`,
% `--changed-deps` and binpkg_exec's `--binpkg-changed-deps` filter.

sets:runtime_deps_differ(RecordedDeps0, Use, TreeRepo://TreeEntry) :-
  sets:use_reduce_deps(RecordedDeps0, Use, RecordedDeps1),
  sets:canonicalize_deps(RecordedDeps1, RecordedDeps),
  findall(D, cache:entry_metadata(TreeRepo, TreeEntry, rdepend, D), TreeRd),
  findall(D, cache:entry_metadata(TreeRepo, TreeEntry, pdepend, D), TreePd),
  append(TreeRd, TreePd, TreeDeps0),
  sets:use_reduce_deps(TreeDeps0, Use, TreeDeps1),
  sets:canonicalize_deps(TreeDeps1, TreeDeps),
  RecordedDeps \== TreeDeps.


%! sets:tree_same_version(+C, +N, +Ver, -TreeRepo, -TreeEntry) is semidet.
%
% Finds a non-VDB tree/overlay entry with the exact installed version,
% following package moves when the installed name is gone from the tree.

sets:tree_same_version(C, N, Ver, TreeRepo, TreeEntry) :-
  sets:tree_cn(C, N, TC, TN),
  cache:ordered_entry(TreeRepo, TreeEntry, TC, TN, Ver),
  \+ knowledgebase:is_vdb_repository(TreeRepo),
  !.


%! sets:vdb_runtime_deps(+Entry, -Deps) is det.
%
% Parses on-disk VDB RDEPEND and PDEPEND (not loaded into kb cache) via the
% EAPI rdepend grammar.

sets:vdb_runtime_deps(Entry, Deps) :-
  ( vdb:read_metadata_file(Entry, 'RDEPEND', RdStr) -> true ; RdStr = '' ),
  ( vdb:read_metadata_file(Entry, 'PDEPEND', PdStr) -> true ; PdStr = '' ),
  sets:parse_rdepend_string(RdStr, Rd),
  sets:parse_rdepend_string(PdStr, Pd),
  append(Rd, Pd, Deps).


%! sets:parse_rdepend_string(+StringOrAtom, -Deps) is det.
%
% Parses a DEPEND-family string into a list of EAPI dependency terms.
% Empty / unparseable input yields [].

sets:parse_rdepend_string('', []) :- !.
sets:parse_rdepend_string(Str, Deps) :-
  ( atom(Str) -> atom_codes(Str, Codes)
  ; string(Str) -> string_codes(Str, Codes)
  ; Codes = []
  ),
  ( Codes == [] -> Deps = []
  ; catch(phrase(eapi:rdepend(_://_, Deps), Codes), _, Deps = [])
  ).


%! sets:use_reduce_deps(+Deps, +Use, -Reduced) is det.
%
% Evaluates use-conditional groups against the installed USE list and
% flattens `all_of_group`. Other group constructors are retained (with
% reduced children) so structure stays comparable to Portage use_reduce.

sets:use_reduce_deps([], _, []) :- !.
sets:use_reduce_deps([use_conditional_group(positive, U, _, Inner)|T], Use, Out) :-
  !,
  ( memberchk(U, Use)
  -> sets:use_reduce_deps(Inner, Use, R),
     sets:use_reduce_deps(T, Use, Rest),
     append(R, Rest, Out)
  ;  sets:use_reduce_deps(T, Use, Out)
  ).
sets:use_reduce_deps([use_conditional_group(negative, U, _, Inner)|T], Use, Out) :-
  !,
  ( memberchk(U, Use)
  -> sets:use_reduce_deps(T, Use, Out)
  ;  sets:use_reduce_deps(Inner, Use, R),
     sets:use_reduce_deps(T, Use, Rest),
     append(R, Rest, Out)
  ).
sets:use_reduce_deps([all_of_group(Inner)|T], Use, Out) :-
  !,
  sets:use_reduce_deps(Inner, Use, R),
  sets:use_reduce_deps(T, Use, Rest),
  append(R, Rest, Out).
sets:use_reduce_deps([any_of_group(Inner)|T], Use, [any_of_group(R)|Rest]) :-
  !,
  sets:use_reduce_deps(Inner, Use, R),
  sets:use_reduce_deps(T, Use, Rest).
sets:use_reduce_deps([exactly_one_of_group(Inner)|T], Use, [exactly_one_of_group(R)|Rest]) :-
  !,
  sets:use_reduce_deps(Inner, Use, R),
  sets:use_reduce_deps(T, Use, Rest).
sets:use_reduce_deps([at_most_one_of_group(Inner)|T], Use, [at_most_one_of_group(R)|Rest]) :-
  !,
  sets:use_reduce_deps(Inner, Use, R),
  sets:use_reduce_deps(T, Use, Rest).
sets:use_reduce_deps([H|T], Use, Out) :-
  ( sets:is_libc_dep(H)
  -> sets:use_reduce_deps(T, Use, Out)
  ;  sets:use_reduce_deps(T, Use, Rest),
     Out = [H|Rest]
  ).


%! sets:is_libc_dep(+Dep) is semidet.
%
% True for package deps on known libc providers. Mirrors emerge's
% `strip_libc_deps` so VDB libc injects do not flood `@changed-deps`.

sets:is_libc_dep(package_dependency(_, _, C, N, _, _, _, _)) :-
  sets:libc_package(C, N).


%! sets:libc_package(?Category, ?Name) is nondet.
%
% Known libc provider C/N pairs stripped during changed-deps comparison.

sets:libc_package('sys-libs', glibc).
sets:libc_package('sys-libs', musl).
sets:libc_package('sys-libs', uclibc).
sets:libc_package('sys-libs', 'uclibc-ng').


%! sets:canonicalize_deps(+Deps, -Canon) is det.
%
% Sorts a dependency list after stripping `:=` slot/subslot pins and ignoring
% USE-dep / phase noise on package atoms (Portage `strip_slots` plus a stable
% comparison key).

sets:canonicalize_deps(Deps, Canon) :-
  maplist(sets:canonicalize_dep, Deps, Canon0),
  sort(Canon0, Canon).


%! sets:canonicalize_dep(+Dep, -Canon) is det.
%
% Per-node canonical form for changed-deps comparison.

sets:canonicalize_dep(package_dependency(_Ph, B, C, N, O, V, S, _U),
                      dep(B, C, N, O, V, S2)) :-
  !,
  ( ( memberchk(equal, S) ; memberchk(any_same_slot, S) )
  -> S2 = equal
  ;  S2 = S
  ).
sets:canonicalize_dep(any_of_group(D), any_of_group(C)) :-
  !,
  sets:canonicalize_deps(D, C).
sets:canonicalize_dep(exactly_one_of_group(D), exactly_one_of_group(C)) :-
  !,
  sets:canonicalize_deps(D, C).
sets:canonicalize_dep(at_most_one_of_group(D), at_most_one_of_group(C)) :-
  !,
  sets:canonicalize_deps(D, C).
sets:canonicalize_dep(D, D).


% -----------------------------------------------------------------------------
%  Shared helpers
% -----------------------------------------------------------------------------

%! sets:tree_cn(+C0, +N0, -C, -N) is nondet.
%
% Yields the category/name to use for tree lookups of an installed
% package: first the installed name itself, then (when the pkgmoves
% module is available) the current name after profiles/updates package
% moves. Callers wrap this in once/1 with the tree lookup so a moved
% package resolves against its new name.

sets:tree_cn(C, N, C, N).
sets:tree_cn(C0, N0, C, N) :-
  current_predicate(pkgmoves:moved/4),
  catch(pkgmoves:moved(C0, N0, C, N), _, fail).


%! sets:slot_atom(+Repo://+Entry, +Category, +Name, -Atom) is det.
%
% Builds a `cat/name:slot` atom from an entry's canonical slot.

sets:slot_atom(Repo://Entry, C, N, Atom) :-
  slotmeta:entry_slot_default(Repo, Entry, Slot),
  sets:cn_slot_atom(C, N, Slot, Atom).


%! sets:cn_slot_atom(+Category, +Name, +Slot, -Atom) is det.
%
% Builds a `cat/name:slot` atom from explicit components.

sets:cn_slot_atom(C, N, Slot, Atom) :-
  atomic_list_concat([C, '/', N, ':', Slot], Atom).


%! sets:entry_subslot(+Repo://+Entry, -Subslot) is det.
%
% Returns the canonical subslot of an entry, defaulting to the main slot when
% no explicit subslot is recorded (matching PMS subslot defaulting).

sets:entry_subslot(Repo://Entry, Subslot) :-
  ( query:search(subslot(Sub0), Repo://Entry)
    -> slotmeta:canon_slot(Sub0, Subslot)
    ;  slotmeta:entry_slot_default(Repo, Entry, Subslot)
  ).


%! sets:entry_visible(+Repo://+Entry) is semidet.
%
% True when an entry is visible: keyword-accepted, not masked, and not
% license-masked.

sets:entry_visible(Repo://Entry) :-
  acceptance:entry_has_accepted_keyword(Repo://Entry),
  \+ query:search(masked(true), Repo://Entry),
  \+ acceptance:license_masked(Repo://Entry).


%! sets:highest_visible_in_slot(+Category, +Name, +Slot, -BestEntry, -BestVersion) is semidet.
%
% Finds the highest-versioned visible tree ebuild for Category/Name in the
% given canonical Slot.  Fails when no visible candidate exists.

sets:highest_visible_in_slot(C, N, Slot, BestEntry, BestVersion) :-
  findall(Version-(Repo://Entry),
          ( query:search([select(repository,notequal,pkg),category(C),name(N),version(Version)],
                         Repo://Entry),
            \+ knowledgebase:is_vdb_repository(Repo),
            slotmeta:entry_slot_default(Repo, Entry, Slot),
            sets:entry_visible(Repo://Entry)
          ),
          Pairs),
  Pairs \== [],
  sets:max_version_pair(Pairs, BestVersion-BestEntry).


%! sets:max_version_pair(+Pairs, -Max) is det.
%
% Selects the `Version-Entry` pair with the highest version from a non-empty
% list, using the EAPI version comparator.

sets:max_version_pair([First|Rest], Max) :-
  foldl(sets:keep_higher_version, Rest, First, Max).


%! sets:keep_higher_version(+Candidate, +Acc, -Best) is det.
%
% Folding step that retains the higher-versioned of two `Version-Entry` pairs.

sets:keep_higher_version(Version-Entry, AccVersion-AccEntry, Best) :-
  ( eapi:version_compare(>, Version, AccVersion)
    -> Best = Version-Entry
    ;  Best = AccVersion-AccEntry
  ).
