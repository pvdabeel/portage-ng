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


%! depclean:run(+ArgsSets)
%
% Entry point. Resolves @world (or the given set arguments) to installed
% root entries, proves the runtime closure, and prints removable packages.

run(ArgsSets) :-
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
    depclean:print_removals(RequiredInstalled)
  ).


%! depclean:roots_from_args(+Args, -Roots)
%
% Convert a list of target atoms into repo://Entry terms by resolving
% each argument against the installed package database.

roots_from_args([], []).
roots_from_args([Arg|Rest], Roots) :-
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

arg_installed_repo_entry(Arg, RepoEntry) :-
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

installed_to_repo_entry(pkg://InstalledEntry, RepoEntry) :-
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

%! depclean:prove_required(+Roots, -RequiredInstalled)
%
% Prove the runtime closure in depclean mode and return the sorted set of
% installed pkg://Entry terms that are required by the proof.

prove_required(Roots, RequiredInstalled) :-
  setup_call_cleanup(
    asserta(preference:local_flag(depclean)),
    depclean:prove_required_(Roots, RequiredInstalled),
    retractall(preference:local_flag(depclean))
  ).


%! depclean:prove_required_(+Roots, -RequiredInstalled)
%
% Internal: run the prover with delayed triggers and extract required
% installed entries from the resulting model.

prove_required_(Roots, RequiredInstalled) :-
  findall(Root:depclean?{[]}, member(Root, Roots), Proposal),
  prover:with_delay_triggers(
    prover:prove(Proposal, t, _ProofAVL, t, ModelAVL, t, _Constraints, t, _Triggers)
  ),
  prover:model_to_list(ModelAVL, ModelList),
  depclean:model_required_installed(ModelList, RequiredInstalled0),
  sort(RequiredInstalled0, RequiredInstalled).


%! depclean:model_required_installed(+ModelList, -RequiredInstalled)
%
% Filter the model list to pkg://Entry terms for entries that are both
% in the proof model and installed in the VDB.

model_required_installed([], []).
model_required_installed([X|Xs], Out) :-
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

model_item_repo_entry(Repo://Entry:depclean, Repo://Entry) :- !.
model_item_repo_entry(Repo://Entry:depclean?{_}, Repo://Entry) :- !.
model_item_repo_entry(_Other, _RepoEntry) :- fail.


%! depclean:print_removals(+RequiredInstalled)
%
% Compute the set of removable packages (installed minus required) and
% print the removal list, uninstall order, and linkage risk report.

print_removals(RequiredInstalled) :-
  findall(pkg://E,
          query:search([installed(true)], pkg://E),
          Installed0),
  sort(Installed0, Installed),
  subtract(Installed, RequiredInstalled, Removable),
  nl,
  message:header('Depclean (proposed removals)'),
  nl,
  ( Removable == [] ->
      writeln('  (none)')
  ; forall(member(pkg://E, Removable),
           ( query:search([category(C),name(N),version(V)], pkg://E),
             format('  ~w/~w-~w~n', [C, N, V])
           ))
  ),
  depclean:print_uninstall_order(Removable),
  depclean:print_linkage_risks(Installed, Removable),
  nl.


% -----------------------------------------------------------------------------
%  Uninstall ordering (installed-only reverse-dependency sort)
% -----------------------------------------------------------------------------


%! depclean:print_uninstall_order(+Removable)
%
% Compute and print a topologically sorted uninstall order for the
% removable packages. Warns when cycles are detected.

print_uninstall_order([]) :- !.
print_uninstall_order(Removable) :-
  depclean:uninstall_order(Removable, Order, Cyclic),
  nl,
  message:header('Depclean (uninstall order)'),
  nl,
  ( Cyclic == true ->
      message:warning('cycle detected in uninstall graph; order is best-effort')
  ; true
  ),
  depclean:print_pkg_list_numbered(1, Order),
  nl.


%! depclean:print_pkg_list_numbered(+Index, +Packages)
%
% Print a numbered list of pkg://Entry terms with category/name-version.

print_pkg_list_numbered(_, []) :- !.
print_pkg_list_numbered(I, [pkg://E|Es]) :-
  ( query:search([category(C),name(N),version(V)], pkg://E) ->
      format('  ~d. ~w/~w-~w~n', [I, C, N, V])
  ; format('  ~d. ~w~n', [I, pkg://E])
  ),
  I2 is I + 1,
  depclean:print_pkg_list_numbered(I2, Es).


%! depclean:uninstall_order(+Removable, -Order, -Cyclic)
%
% Compute the uninstall order via Kahn's topological sort on the
% dependency graph restricted to the removable set. Cyclic is `true`
% if a cycle was detected (remaining nodes appended to the order).

uninstall_order(Removable, Order, Cyclic) :-
  sort(Removable, Nodes),
  list_to_ord_set(Nodes, NodeSet),
  depclean:build_edges(NodeSet, Nodes, EdgesAssoc),
  depclean:toposort(Nodes, EdgesAssoc, Order, Cyclic).


%! depclean:build_edges(+NodeSet, +Nodes, -EdgesAssoc)
%
% Build adjacency list A -> [B...] where A depends on B, restricted to
% the removable node set.

build_edges(_NodeSet, [], Assoc) :-
  empty_assoc(Assoc).
build_edges(NodeSet, [pkg://E|Es], Out) :-
  depclean:build_edges(NodeSet, Es, In),
  ( depclean:direct_deps_installed(pkg://E, DirectDeps),
    include({NodeSet}/[X]>>ord_memberchk(X, NodeSet), DirectDeps, DirectDepsInSet),
    list_to_ord_set(DirectDepsInSet, DepsSet),
    put_assoc(pkg://E, In, DepsSet, Out)
  ; put_assoc(pkg://E, In, [], Out)
  ).


%! depclean:direct_deps_installed(+InstalledRef, -DepsInstalled)
%
% Sorted list of direct installed runtime dependencies of a pkg://Entry,
% computed via the repo metadata's dependency model.

direct_deps_installed(pkg://InstalledEntry, DepsInstalled) :-
  depclean:installed_to_repo_entry(pkg://InstalledEntry, RepoEntry),
  depclean:direct_deps_from_repo_entry(RepoEntry, DepsInstalled),
  !.


%! depclean:direct_deps_from_repo_entry(+RepoEntry, -DepsInstalled)
%
% Compute the effective runtime dependency model for a repo entry and
% resolve each dependency literal to an installed pkg://Entry.

direct_deps_from_repo_entry(Repo://Entry, DepsInstalled) :-
  query:search(model(Model,required_use(_R),build_with_use(_B)), Repo://Entry),
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

dep_literal_installed_dep(MergedDeps, DepInstalled) :-
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

dep_term_cn_deps(grouped_package_dependency(_Strength,C,N,PackageDeps):Action?{_}, Action, C, N, PackageDeps) :- !.
dep_term_cn_deps(grouped_package_dependency(_Strength,C,N,PackageDeps):Action,    Action, C, N, PackageDeps) :- !.
dep_term_cn_deps(grouped_package_dependency(_Strength,C,N,PackageDeps),           run,    C, N, PackageDeps) :- !.


%! depclean:toposort(+Nodes, +Edges, -Order, -Cyclic)
%
% Kahn's topological sort on adjacency list A -> Bs (A depends on B).
% Returns Cyclic = true if a cycle prevents full ordering.

toposort(Nodes, Edges, Order, Cyclic) :-
  depclean:indegrees(Nodes, Edges, InDeg0),
  findall(N, (member(N, Nodes), get_assoc(N, InDeg0, 0)), Q0),
  depclean:kahn(Q0, Nodes, Edges, InDeg0, [], Order0, Remaining),
  ( Remaining == [] ->
      Cyclic = false,
      Order = Order0
  ; Cyclic = true,
    append(Order0, Remaining, Order)
  ).


%! depclean:indegrees(+Nodes, +Edges, -InDeg)
%
% Build the initial in-degree map for all nodes.

indegrees(Nodes, Edges, InDeg) :-
  empty_assoc(Empty0),
  foldl([N,In,Out]>>put_assoc(N, In, 0, Out), Nodes, Empty0, Empty1),
  foldl(depclean:indegree_acc(Edges), Nodes, Empty1, InDeg).


%! depclean:indegree_acc(+Edges, +Node, +InDegIn, -InDegOut)
%
% Accumulate in-degrees contributed by Node's successors.

indegree_acc(Edges, A, In, Out) :-
  ( get_assoc(A, Edges, Bs) -> true ; Bs = [] ),
  foldl(depclean:inc_indeg, Bs, In, Out).


%! depclean:inc_indeg(+Node, +InDegIn, -InDegOut)
%
% Increment the in-degree counter for Node by one.

inc_indeg(B, In, Out) :-
  ( get_assoc(B, In, V0) -> V1 is V0 + 1, put_assoc(B, In, V1, Out)
  ; put_assoc(B, In, 1, Out)
  ).


%! depclean:kahn(+Queue, +Nodes, +Edges, +InDeg, +Acc, -Order, -Remaining)
%
% Kahn's algorithm work loop. Processes zero-in-degree nodes, decrements
% neighbors, and collects the topological order. Remaining holds any
% nodes still unprocessed (cycle members).

kahn([], Nodes, _Edges, InDeg, Acc, Order, Remaining) :-
  reverse(Acc, Order),
  findall(N, (member(N, Nodes), get_assoc(N, InDeg, V), V > 0), Remaining).
kahn([N|Q], Nodes, Edges, InDeg0, Acc, Order, Remaining) :-
  ( get_assoc(N, Edges, Bs) -> true ; Bs = [] ),
  put_assoc(N, InDeg0, -1, InDeg1), % mark processed
  depclean:dec_neighbors(Bs, InDeg1, InDeg2, NewZeros),
  append(Q, NewZeros, Q2),
  depclean:kahn(Q2, Nodes, Edges, InDeg2, [N|Acc], Order, Remaining).


%! depclean:dec_neighbors(+Neighbors, +InDegIn, -InDegOut, -NewZeros)
%
% Decrement in-degree for each neighbor; collect those that reach zero.

dec_neighbors([], InDeg, InDeg, []).
dec_neighbors([B|Bs], InDeg0, InDeg, NewZeros) :-
  ( get_assoc(B, InDeg0, V0),
    V0 >= 0 ->
      V1 is V0 - 1,
      put_assoc(B, InDeg0, V1, InDeg1),
      ( V1 =:= 0 -> NewZeros = [B|RestZeros] ; NewZeros = RestZeros ),
      depclean:dec_neighbors(Bs, InDeg1, InDeg, RestZeros)
  ; depclean:dec_neighbors(Bs, InDeg0, InDeg, NewZeros)
  ).


% -----------------------------------------------------------------------------
%  Linkage risk report (preserved-libs approximation)
% -----------------------------------------------------------------------------

%! depclean:print_linkage_risks(+Installed, +Removable)
%
% Best-effort approximation of Portage preserved-libs behavior. Uses VDB
% metadata (NEEDED.ELF.2 / PROVIDES.ELF.2) to identify kept packages
% whose ELF dependencies would lose all providers if the removable set
% is unmerged.

print_linkage_risks(_Installed, Removable) :-
  Removable == [],
  !.
print_linkage_risks(Installed, Removable) :-
  sort(Removable, RemovableSorted),
  list_to_ord_set(RemovableSorted, RemovableSet),
  subtract(Installed, RemovableSorted, Kept),
  list_to_ord_set(Kept, KeptSet),
  depclean:build_provides_map(Installed, ProvidesMap),
  depclean:collect_broken_needed(Kept, KeptSet, RemovableSet, ProvidesMap, BrokenPairs),
  nl,
  message:header('Depclean (linkage risks, VDB ELF metadata)'),
  nl,
  ( BrokenPairs == [] ->
      writeln('  (none detected)')
  ; forall(member(broken(Consumer, NeededTok, RemovedProviders), BrokenPairs),
           depclean:print_broken_needed(Consumer, NeededTok, RemovedProviders))
  ),
  nl.


%! depclean:build_provides_map(+Installed, -Map)
%
% Build an assoc mapping each ELF token to the ordered set of pkg://Entry
% terms that provide it.

build_provides_map(Installed, Map) :-
  empty_assoc(Empty),
  foldl(depclean:provides_acc, Installed, Empty, Map).


%! depclean:provides_acc(+PkgEntry, +MapIn, -MapOut)
%
% Accumulate ELF provides tokens from a single installed package.

provides_acc(pkg://E, In, Out) :-
  ( query:search(provides_elf2(Provides0), pkg://E) -> true ; Provides0 = [] ),
  foldl(depclean:provides_tok_put(pkg://E), Provides0, In, Out).


%! depclean:provides_tok_put(+Pkg, +Token, +MapIn, -MapOut)
%
% Add Pkg to the provider set for Token in the provides map.

provides_tok_put(Pkg, Tok, In, Out) :-
  ( get_assoc(Tok, In, Providers0) ->
      ord_add_element(Providers0, Pkg, Providers),
      put_assoc(Tok, In, Providers, Out)
  ; put_assoc(Tok, In, [Pkg], Out)
  ).


%! depclean:collect_broken_needed(+Kept, +KeptSet, +RemovableSet, +ProvidesMap, -BrokenPairs)
%
% Find kept packages whose NEEDED.ELF.2 tokens would lose all providers
% if the removable set is unmerged (no remaining provider in the kept set).

collect_broken_needed(Kept, KeptSet, RemovableSet, ProvidesMap, BrokenPairs) :-
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


%! depclean:print_broken_needed(+Consumer, +Token, +RemovedProviders)
%
% Print a single broken-linkage warning: the consumer package, the ELF
% token it needs, and the removable packages that were its only providers.

print_broken_needed(pkg://E, Tok, RemovedProviders) :-
  ( query:search([category(C),name(N),version(V)], pkg://E) ->
      format('  ~w/~w-~w needs ~w~n', [C, N, V, Tok])
  ; format('  ~w needs ~w~n', [pkg://E, Tok])
  ),
  forall(member(pkg://P, RemovedProviders),
         ( ( query:search([category(CP),name(NP),version(VP)], pkg://P) ->
               format('    - would lose provider: ~w/~w-~w~n', [CP, NP, VP])
           ; format('    - would lose provider: ~w~n', [pkg://P])
           )
         )).