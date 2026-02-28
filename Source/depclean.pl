/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> DEPCLEAN
Proof-based depclean: approximates Gentoo's graph-based depclean using the
prover's proof/model instead of scanning ELF binaries. Computes the runtime
closure from @world roots over installed packages and identifies removable
packages that are not required by the closure.
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
    printer:print_removals(RequiredInstalled)
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
  % Find installed entry in VDB repo.
  query:search([installed(true)|Q], pkg://InstalledEntry),
  depclean:installed_to_repo_entry(pkg://InstalledEntry, RepoEntry),
  !.


%! depclean:installed_to_repo_entry(+InstalledRef, -RepoEntry)
%
% Map an installed pkg://Entry to the corresponding entry in the active
% repository set (excluding VDB repo `pkg`). Falls back to any matching
% repo if keywords or overlay differ.

depclean:installed_to_repo_entry(pkg://InstalledEntry, RepoEntry) :-
  query:search([category(C),name(N),version(V)], pkg://InstalledEntry),
  preference:accept_keywords(K),
  ( query:search([select(repository,notequal,pkg),category(C),name(N),keywords(K),version(V)],
                 Repo//InstalledEntry)
  -> RepoEntry = Repo//InstalledEntry
  ; % Fallback: if keywords/overlay differ, allow any repo except pkg.
    query:search([select(repository,notequal,pkg),category(C),name(N),version(V)],
                 Repo2//InstalledEntry),
    RepoEntry = Repo2//InstalledEntry
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
  findall(Root:depclean?{[]}, member(Root, Roots), Proposal),
  prover:prove(Proposal, t, _ProofAVL, t, ModelAVL, t, _Constraints, t, _Triggers),
  prover:model_to_list(ModelAVL, ModelList),
  depclean:model_required_installed(ModelList, RequiredInstalled0),
  sort(RequiredInstalled0, RequiredInstalled).


%! depclean:model_required_installed(+ModelList, -RequiredInstalled)
%
% Filter the model list to pkg://Entry terms for entries that are both
% in the proof model and installed in the VDB.

depclean:model_required_installed([], []).
depclean:model_required_installed([X|Xs], Out) :-
  model_required_installed(Xs, Rest),
  ( depclean:model_item_repo_entry(X, Repo://Entry) ->
      ( query:search([category(C),name(N),version(V)], Repo://Entry),
        query:search([name(N),category(C),version(V),installed(true)], pkg://InstalledEntry) ->
          Out = [pkg://InstalledEntry|Rest]
      ; Out = Rest
      )
  ; Out = Rest
  ).


%! depclean:model_item_repo_entry(+ModelItem, -RepoEntry)
%
% Extract a Repo://Entry from a depclean model literal. Fails for
% non-depclean items.

depclean:model_item_repo_entry(Repo://Entry:depclean, Repo://Entry) :- !.
depclean:model_item_repo_entry(Repo://Entry:depclean?{_}, Repo://Entry) :- !.
depclean:model_item_repo_entry(_Other, _RepoEntry) :- fail.


% -----------------------------------------------------------------------------
%  Uninstall ordering (reverse-dependency topological sort)
% -----------------------------------------------------------------------------


%! depclean:uninstall_order(+Removable, -Order, -Cyclic)
%
% Compute the uninstall order via Kahn's topological sort on the
% dependency graph restricted to the removable set. Cyclic is `true`
% if a cycle was detected (remaining nodes appended to the order).

depclean:uninstall_order(Removable, Order, Cyclic) :-
  sort(Removable, Nodes),
  list_to_ord_set(Nodes, NodeSet),
  depclean:build_edges(NodeSet, Nodes, EdgesAssoc),
  kahn:toposort(Nodes, EdgesAssoc, Order, Cyclic).


%! depclean:build_edges(+NodeSet, +Nodes, -EdgesAssoc)
%
% Build adjacency list A -> [B...] where A depends on B, restricted to
% the removable node set.

depclean:build_edges(_NodeSet, [], Assoc) :-
  empty_assoc(Assoc).
depclean:build_edges(NodeSet, [pkg://E|Es], Out) :-
  depclean:build_edges(NodeSet, Es, In),
  ( depclean:direct_deps_installed(pkg://E, DirectDeps),
    include({NodeSet}/[X]>>ord_memberchk(X, NodeSet), DirectDeps, DirectDepsInSet),
    list_to_ord_set(DirectDepsInSet, DepsSet),
    put_assoc(pkg://E, In, DepsSet, Out)
  ; put_assoc(pkg://E, In, [], Out)
  ).


% -----------------------------------------------------------------------------
%  Installed dependency resolution
% ----------------------------------------------------------------------------

%! depclean:direct_deps_installed(+InstalledRef, -DepsInstalled)
%
% Sorted list of direct installed runtime dependencies of a pkg://Entry,
% computed via the repo metadata's dependency model.

depclean:direct_deps_installed(pkg://InstalledEntry, DepsInstalled) :-
  depclean:installed_to_repo_entry(pkg://InstalledEntry, RepoEntry),
  depclean:direct_deps_from_repo_entry(RepoEntry, DepsInstalled),
  !.


%! depclean:direct_deps_from_repo_entry(+RepoEntry, -DepsInstalled)
%
% Compute the effective runtime dependency model for a repo entry and
% resolve each dependency literal to an installed pkg://Entry.

depclean:direct_deps_from_repo_entry(Repo://Entry, DepsInstalled) :-
  query:search(model(Model,required_use(_),build_with_use(_)), Repo://Entry),
  query:memoized_search(model(dependency(MergedDeps0,run)):config?{Model}, Repo://Entry),
  add_self_to_dep_contexts(Repo://Entry, MergedDeps0, MergedDeps),
  findall(pkg://DepInstalled,
          depclean:dep_literal_installed_dep(MergedDeps, DepInstalled),
          Deps0),
  sort(Deps0, DepsInstalled).


%! depclean:dep_literal_installed_dep(+MergedDeps, -DepInstalled)
%
% Non-deterministically unify DepInstalled with an installed pkg://Entry
% that satisfies one of the merged dependency literals.

depclean:dep_literal_installed_dep(MergedDeps, DepInstalled) :-
  member(D0, MergedDeps),
  depclean:dep_term_cn_deps(D0, Action, C, N, PackageDeps),
  rules:merge_slot_restriction(Action, C, N, PackageDeps, SlotReq),
  query:search([name(N),category(C),installed(true)], pkg://DepInstalled),
  rules:query_search_slot_constraint(SlotReq, pkg://DepInstalled, _),
  rules:installed_entry_satisfies_package_deps(Action, C, N, PackageDeps, pkg://DepInstalled).


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

depclean:provides_acc(pkg://E, In, Out) :-
  ( query:search(provides_elf2(Provides0), pkg://E) -> true ; Provides0 = [] ),
  foldl(depclean:provides_tok_put(pkg://E), Provides0, In, Out).


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
  findall(broken(pkg://E, Tok, RemovedProviders),
          ( member(pkg://E, Kept),
            ( query:search(needed_elf2(Needed0), pkg://E) -> true ; Needed0 = [] ),
            member(Tok, Needed0),
            get_assoc(Tok, ProvidesMap, ProvidersAll),
            ord_intersection(ProvidersAll, RemovableSet, RemovedProviders),
            RemovedProviders \== [],
            ord_intersection(ProvidersAll, KeptSet, RemainingProviders),
            RemainingProviders == []
          ),
          Broken0),
  sort(Broken0, BrokenPairs).