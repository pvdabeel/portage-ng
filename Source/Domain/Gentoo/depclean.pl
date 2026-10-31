/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> DEPCLEAN
Proof-based depclean: approximates Gentoo's graph-based depclean using the
prover's proof/model instead of scanning ELF binaries. Two proving passes:
the runtime closure from @world roots over installed packages (resolving
rule set, depclean mode) identifies removable packages not required by the
closure; the uninstall order is then proved over the unmerging rule set
(Source/Domain/Gentoo/Rules/unmerging.pl) — consumers unmerge before their
dependencies, cyclic claims surface as retained-claim assumptions.
*/

:- module(depclean, []).

% =============================================================================
%  DEPCLEAN declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Entry point
% -----------------------------------------------------------------------------

%! depclean:run(+ArgsSets)
%
% Entry point. Resolves @world (or the given set arguments) to installed
% root entries, proves the runtime closure, and prints removable packages.

depclean:run(ArgsSets) :-
  ( ArgsSets == [] ->
      eapi:substitute_sets([world], Args)
  ; eapi:substitute_sets(ArgsSets, Args)
  ),
  depclean:roots_from_args(Args, RootRepoEntries),
  sort(RootRepoEntries, Roots),
  ( Roots == [] ->
      message:warning('depclean: no roots found (empty @world?)'),
      nl
  ; depclean:prove_required(Roots, RequiredInstalled),
    removal:print_removals(RequiredInstalled)
  ).


% -----------------------------------------------------------------------------
%  Root resolution (argument -> installed repo entry)
% -----------------------------------------------------------------------------

%! depclean:roots_from_args(+Args, -Roots)
%
% Convert a list of target atoms into repo://Entry terms by resolving
% each argument against the installed package database.

depclean:roots_from_args([], []).
depclean:roots_from_args([Arg|Rest], Roots) :-
  depclean:roots_from_args(Rest, RootsRest),
  ( depclean:arg_installed_repo_entry(Arg, RepoEntry) ->
      Roots = [RepoEntry|RootsRest]
  ; Roots = RootsRest
  ).


%! depclean:arg_installed_repo_entry(+Arg, -RepoEntry)
%
% Resolve an argument atom to a repo entry for the currently installed version.
% Parses the atom as a qualified target, finds the installed VDB entry, then
% maps it to a non-pkg repo entry with the same category/name/version.

depclean:arg_installed_repo_entry(Arg, RepoEntry) :-
  atom(Arg),
  atom_codes(Arg, Codes),
  phrase(eapi:qualified_target(Q), Codes),
  % Find installed entry in the active VDB repository.
  knowledgebase:vdb_repository(VdbRepo),
  query:search([installed(true)|Q], VdbRepo://InstalledEntry),
  depclean:installed_to_repo_entry(VdbRepo://InstalledEntry, RepoEntry),
  !.


%! depclean:installed_to_repo_entry(+InstalledRef, -RepoEntry)
%
% Map an installed VDB entry to the corresponding entry in the active
% repository set (excluding VDB repositories). Falls back to any
% matching non-VDB repo if keywords or overlay differ.

depclean:installed_to_repo_entry(VdbRepo://InstalledEntry, RepoEntry) :-
  query:search([category(C),name(N),version(V)], VdbRepo://InstalledEntry),
  preference:accept_keywords(K),
  ( query:search([select(repository,notequal,pkg),category(C),name(N),keywords(K),version(V)],
                 Repo://InstalledEntry),
    \+ knowledgebase:is_vdb_repository(Repo)
  -> RepoEntry = Repo://InstalledEntry
  ; % Fallback: if keywords/overlay differ, allow any non-VDB repo.
    query:search([select(repository,notequal,pkg),category(C),name(N),version(V)],
                 Repo2://InstalledEntry),
    \+ knowledgebase:is_vdb_repository(Repo2),
    RepoEntry = Repo2://InstalledEntry
  ).


% -----------------------------------------------------------------------------
%  Proof-based closure
% -----------------------------------------------------------------------------

%! depclean:prove_required(+Roots, -RequiredInstalled)
%
% Prove the runtime closure in depclean mode and return the sorted set of
% installed pkg://Entry terms that are required by the proof.

depclean:prove_required(Roots, RequiredInstalled) :-
  setup_call_cleanup(
    asserta(preference:local_flag(depclean)),
    depclean:prove_required_(Roots, RequiredInstalled),
    retractall(preference:local_flag(depclean))
  ).


%! depclean:prove_required_(+Roots, -RequiredInstalled)
%
% Internal: run the prover and extract required installed entries from
% the resulting model.

depclean:prove_required_(Roots, RequiredInstalled) :-
  findall(Repo://Entry:depclean?{[]}, member(Repo://Entry, Roots), Proposal),
  resolver:resolve(Proposal, t, _ProofAVL, t, ModelAVL, t, _Constraints, t, _Triggers),
  prover:model_to_list(ModelAVL, ModelList),
  depclean:model_required_installed(ModelList, RequiredInstalled0),
  sort(RequiredInstalled0, RequiredInstalled).


%! depclean:model_required_installed(+ModelList, -RequiredInstalled)
%
% Filter the model list to pkg://Entry terms for entries that are both
% in the proof model and installed in the VDB.

depclean:model_required_installed(ModelList, RequiredInstalled) :-
  convlist(depclean:model_item_installed, ModelList, RequiredInstalled).


%! depclean:model_item_installed(+ModelItem, -InstalledEntry) is semidet.
%
% Maps a depclean model literal to its installed VDB entry, succeeding only
% when the item resolves to a Repo://Entry that is both in the proof model and
% installed in the VDB. Fails (so convlist/3 drops the item) otherwise.

depclean:model_item_installed(X, VdbRepo://InstalledEntry) :-
  depclean:model_item_repo_entry(X, Repo://Entry),
  query:search([category(C),name(N),version(V)], Repo://Entry),
  knowledgebase:vdb_repository(VdbRepo),
  query:search([name(N),category(C),version(V),installed(true)], VdbRepo://InstalledEntry).


%! depclean:model_item_repo_entry(+ModelItem, -RepoEntry)
%
% Extract a Repo://Entry from a depclean model literal. Fails for
% non-depclean items.

depclean:model_item_repo_entry(Repo://Entry:depclean, Repo://Entry) :- !.
depclean:model_item_repo_entry(Repo://Entry:depclean?{_}, Repo://Entry) :- !.
depclean:model_item_repo_entry(_Other, _RepoEntry) :- fail.


% -----------------------------------------------------------------------------
%  Uninstall ordering (proof-based unmerge pass)
% -----------------------------------------------------------------------------


%! depclean:uninstall_order(+Removable, -Order, -Retained)
%
% Order the removable set by proving `scheduled(Node:unmerge)` for every
% node with the generic prover over the unmerging rule set
% (Source/Domain/Gentoo/Rules/unmerging.pl): a package can be unmerged
% once every claim on it is released, i.e. every removable consumer is
% unmerged first. The availability proofs are projected onto waves by
% the orderer's evaluator and flattened wave-major into Order.
%
% Retained is the sorted list of retained-claim assumptions
% `retained(Claimant, Dependency)` — dependency cycles where the
% claimant could not be ordered before the package it depends on, so
% the dependency unmerges while the claimant is still installed. Empty
% when the claim graph is acyclic.

depclean:uninstall_order([], [], []) :- !.
depclean:uninstall_order(Removable, Order, Retained) :-
  sort(Removable, Nodes),
  findall(N:unmerge, member(N, Nodes), Steps),
  findall(scheduled(S), member(S, Steps), Goals),
  unmerging:with_unmerge_pass(Nodes,
    once(prover:prove_once(unmerging, Goals, t, OrdProof, t, _Model, t, _Cons, t, _Triggers))),
  orderer:provider_edges(OrdProof, Edges),
  orderer:assign_waves(Steps, Edges, WaveAVL),
  depclean:waves_to_order(WaveAVL, Order),
  depclean:retained_claims(OrdProof, Retained).


%! depclean:waves_to_order(+WaveAVL, -Order)
%
% Flatten the wave assignment (Node:unmerge -> Wave) into the uninstall
% order: wave-major, standard order of terms within a wave (keysort is
% stable over the key-ordered assoc list).

depclean:waves_to_order(WaveAVL, Order) :-
  assoc_to_list(WaveAVL, Pairs),
  findall(W-N, member((N:unmerge)-W, Pairs), WavePairs),
  keysort(WavePairs, SortedPairs),
  findall(N, member(_-N, SortedPairs), Order).


%! depclean:retained_claims(+OrdProof, -Retained)
%
% Extract the retained-claim assumptions from the unmerge-pass proof:
% `assumed(unreachable(R:unmerge, C:unmerge))` records that claimant C
% could not be unmerged before its dependency R.

depclean:retained_claims(OrdProof, Retained) :-
  findall(retained(C, R),
          gen_assoc(rule(assumed(unreachable(R:unmerge, C:unmerge))), OrdProof, _),
          Retained0),
  sort(Retained0, Retained).


% -----------------------------------------------------------------------------
%  Installed dependency resolution
% ----------------------------------------------------------------------------

%! depclean:direct_deps_installed(+InstalledRef, -DepsInstalled)
%
% Sorted list of direct installed runtime dependencies of a VDB entry.
% Computed from the same-version tree ebuild's dependency model (Portage's
% dynamic deps, the default), or -- under `--dynamic-deps=n` -- from the
% RDEPEND/PDEPEND/IDEPEND the VDB recorded when the package was built.

depclean:direct_deps_installed(VdbRepo://InstalledEntry, DepsInstalled) :-
  preference:flag(nodynamicdeps),
  !,
  depclean:direct_deps_from_vdb_record(VdbRepo://InstalledEntry, DepsInstalled).
depclean:direct_deps_installed(VdbRepo://InstalledEntry, DepsInstalled) :-
  depclean:installed_to_repo_entry(VdbRepo://InstalledEntry, RepoEntry),
  depclean:direct_deps_from_repo_entry(RepoEntry, DepsInstalled),
  !.


%! depclean:direct_deps_from_vdb_record(+InstalledRef, -DepsInstalled)
%
% The installed packages satisfying the runtime dependencies the VDB
% recorded for the entry: the on-disk RDEPEND, PDEPEND and IDEPEND
% strings, use-reduced under the recorded USE. Every alternative of an
% any-of group counts (a conservative claim: an installed alternative is
% never removed from under a consumer that may be using it); blockers
% claim nothing.

depclean:direct_deps_from_vdb_record(VdbRepo://Entry, DepsInstalled) :-
  findall(U, query:search(use(U), VdbRepo://Entry), Use),
  findall(D,
          ( member(Key, ['RDEPEND', 'PDEPEND', 'IDEPEND']),
            vdb:read_metadata_file(Entry, Key, Str),
            sets:parse_rdepend_string(Str, Ds),
            member(D, Ds)
          ),
          Recorded0),
  sets:use_reduce_deps(Recorded0, Use, Recorded),
  depclean:recorded_dep_leaves(Recorded, Leaves),
  findall(VdbRepo://DepInstalled,
          ( member(package_dependency(Phase, no, C, N, O, V, S, Us), Leaves),
            Grouped = grouped_package_dependency(no, C, N,
                        [package_dependency(Phase, no, C, N, O, V, S, Us)]):run,
            depclean:dep_literal_installed_dep(VdbRepo, [Grouped], DepInstalled)
          ),
          Deps0),
  sort(Deps0, DepsInstalled).


%! depclean:recorded_dep_leaves(+Deps, -Leaves)
%
% The package_dependency/8 leaves of a use-reduced dependency list,
% flattening the remaining group constructors.

depclean:recorded_dep_leaves([], []) :- !.
depclean:recorded_dep_leaves([D|Ds], Leaves) :-
  ( D = package_dependency(_, _, _, _, _, _, _, _)
  -> Leaves = [D|Rest]
  ;  D =.. [_Group, Inner],
     is_list(Inner)
  -> depclean:recorded_dep_leaves(Inner, InnerLeaves),
     append(InnerLeaves, Rest, Leaves)
  ;  Leaves = Rest
  ),
  depclean:recorded_dep_leaves(Ds, Rest).


%! depclean:direct_deps_from_repo_entry(+RepoEntry, -DepsInstalled)
%
% Compute the effective runtime dependency model for a repo entry and
% resolve each dependency literal to an installed pkg://Entry.

depclean:direct_deps_from_repo_entry(Repo://Entry, DepsInstalled) :-
  query:search(model(Model,required_use(_),build_with_use(_)), Repo://Entry),
  query:search(model(dependency(MergedDeps0,run)):config?{Model}, Repo://Entry),
  dependency:add_self_to_dep_contexts(Repo://Entry, MergedDeps0, MergedDeps),
  knowledgebase:vdb_repository(VdbRepo),
  findall(VdbRepo://DepInstalled,
          depclean:dep_literal_installed_dep(VdbRepo, MergedDeps, DepInstalled),
          Deps0),
  sort(Deps0, DepsInstalled).


%! depclean:dep_literal_installed_dep(+VdbRepo, +MergedDeps, -DepInstalled)
%
% Non-deterministically unify DepInstalled with an installed VDB entry
% that satisfies one of the merged dependency literals.

depclean:dep_literal_installed_dep(VdbRepo, MergedDeps, DepInstalled) :-
  member(D0, MergedDeps),
  depclean:dep_term_cn_deps(D0, Action, C, N, PackageDeps),
  slotmeta:merge_slot_restriction(Action, C, N, PackageDeps, SlotReq),
  query:search([name(N),category(C),installed(true)], VdbRepo://DepInstalled),
  slotmeta:query_search_slot_constraint(SlotReq, VdbRepo://DepInstalled, _),
  cnselect:installed_entry_satisfies_package_deps(Action, C, N, PackageDeps, VdbRepo://DepInstalled).


%! depclean:dep_term_cn_deps(+DepTerm, -Action, -C, -N, -PackageDeps)
%
% Extract action, category, name, and package dependency list from a
% merged dependency literal.

depclean:dep_term_cn_deps(grouped_package_dependency(_Strength,C,N,PackageDeps):Action?{_}, Action, C, N, PackageDeps) :- !.
depclean:dep_term_cn_deps(grouped_package_dependency(_Strength,C,N,PackageDeps):Action,    Action, C, N, PackageDeps) :- !.
depclean:dep_term_cn_deps(grouped_package_dependency(_Strength,C,N,PackageDeps),           run,    C, N, PackageDeps) :- !.



% -----------------------------------------------------------------------------
%  Linkage risk data (preserved-libs approximation)
% -----------------------------------------------------------------------------


%! depclean:build_provides_map(+Installed, -Map)
%
% Build an assoc mapping each ELF token to the ordered set of pkg://Entry
% terms that provide it.

depclean:build_provides_map(Installed, Map) :-
  empty_assoc(Empty),
  foldl(depclean:provides_acc, Installed, Empty, Map).


%! depclean:provides_acc(+PkgEntry, +MapIn, -MapOut)
%
% Accumulate ELF provides tokens from a single installed package.

depclean:provides_acc(VdbRepo://E, In, Out) :-
  ( query:search(provides_elf2(Provides0), VdbRepo://E) -> true ; Provides0 = [] ),
  foldl(depclean:provides_tok_put(VdbRepo://E), Provides0, In, Out).


%! depclean:provides_tok_put(+Pkg, +Token, +MapIn, -MapOut)
%
% Add Pkg to the provider set for Token in the provides map.

depclean:provides_tok_put(Pkg, Tok, In, Out) :-
  ( get_assoc(Tok, In, Providers0) ->
      ord_add_element(Providers0, Pkg, Providers),
      put_assoc(Tok, In, Providers, Out)
  ; put_assoc(Tok, In, [Pkg], Out)
  ).


%! depclean:collect_broken_needed(+Kept, +KeptSet, +RemovableSet, +ProvidesMap, -BrokenPairs)
%
% Find kept packages whose NEEDED.ELF.2 tokens would lose all providers
% if the removable set is unmerged (no remaining provider in the kept set).

depclean:collect_broken_needed(Kept, KeptSet, RemovableSet, ProvidesMap, BrokenPairs) :-
  findall(broken(VdbRepo://E, Tok, RemovedProviders),
          ( member(VdbRepo://E, Kept),
            ( query:search(needed_elf2(Needed0), VdbRepo://E) -> true ; Needed0 = [] ),
            member(Tok, Needed0),
            get_assoc(Tok, ProvidesMap, ProvidersAll),
            ord_intersection(ProvidersAll, RemovableSet, RemovedProviders),
            RemovedProviders \== [],
            ord_intersection(ProvidersAll, KeptSet, RemainingProviders),
            RemainingProviders == []
          ),
          Broken0),
  sort(Broken0, BrokenPairs).