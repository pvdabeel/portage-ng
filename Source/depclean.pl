/*
  Depclean (proof-based)

  Goal: provide a Portage-like depclean workflow without scanning ELF binaries.
  We approximate Gentoo's graph-based depclean using our proof/model.

  This first implementation:
  - Computes the set of "roots" from @world (and optional extra args)
  - Proves the runtime closure in a special "depclean traversal" mode that only
    follows *installed* packages
  - Prints the list of installed packages that are removable (not required)

  Future:
  - Order uninstall operations (reverse dependency order)
  - Use VDB NEEDED.ELF.2 / PROVIDES.ELF.2 to emulate preserved-libs rebuild sets
*/

:- module(depclean, [run/1]).

:- use_module(library(assoc)).
:- use_module(library(ordsets)).
:- use_module(library(apply)).
:- use_module(library(lists)).

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

roots_from_args([], []).
roots_from_args([Arg|Rest], Roots) :-
  depclean:roots_from_args(Rest, RootsRest),
  ( depclean:arg_installed_repo_entry(Arg, RepoEntry) ->
      Roots = [RepoEntry|RootsRest]
  ; Roots = RootsRest
  ).

% Resolve an argument (atom) to a *repo* entry for the currently installed version.
% We prefer using the exact installed version (pkg://Entry), then map it to a
% non-pkg repo entry with the same category/name/version.
arg_installed_repo_entry(Arg, RepoEntry) :-
  atom(Arg),
  atom_codes(Arg, Codes),
  phrase(eapi:qualified_target(Q), Codes),
  % Find installed entry in VDB repo.
  query:search([repository(pkg),installed(true)|Q], pkg://InstalledEntry),
  depclean:installed_to_repo_entry(pkg://InstalledEntry, RepoEntry),
  !.

installed_to_repo_entry(pkg://InstalledEntry, RepoEntry) :-
  % Locate the same version in the active repo set (excluding VDB repo `pkg`).
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

% Prove closure in depclean mode and return the set of installed pkg:// entries
% that are required by the proof.
prove_required(Roots, RequiredInstalled) :-
  setup_call_cleanup(
    asserta(preference:local_flag(depclean)),
    depclean:prove_required_(Roots, RequiredInstalled),
    retractall(preference:local_flag(depclean))
  ).

prove_required_(Roots, RequiredInstalled) :-
  findall(Root:depclean?{[]}, member(Root, Roots), Proposal),
  prover:with_delay_triggers(
    prover:prove(Proposal, t, _ProofAVL, t, ModelAVL, t, _Constraints, t, _Triggers)
  ),
  prover:model_to_list(ModelAVL, ModelList),
  depclean:model_required_installed(ModelList, RequiredInstalled0),
  sort(RequiredInstalled0, RequiredInstalled).

model_required_installed([], []).
model_required_installed([X|Xs], Out) :-
  model_required_installed(Xs, Rest),
  ( depclean:model_item_repo_entry(X, Repo://Entry) ->
      ( query:search([category(C),name(N),version(V)], Repo://Entry),
        query:search([repository(pkg),category(C),name(N),version(V),installed(true)], pkg://InstalledEntry) ->
          Out = [pkg://InstalledEntry|Rest]
      ; Out = Rest
      )
  ; Out = Rest
  ).

model_item_repo_entry(Repo://Entry:depclean, Repo://Entry) :- !.
model_item_repo_entry(Repo://Entry:depclean?{_}, Repo://Entry) :- !.
model_item_repo_entry(_Other, _RepoEntry) :- fail.

print_removals(RequiredInstalled) :-
  findall(pkg://E,
          query:search([repository(pkg),installed(true)], pkg://E),
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

print_pkg_list_numbered(_, []) :- !.
print_pkg_list_numbered(I, [pkg://E|Es]) :-
  ( query:search([category(C),name(N),version(V)], pkg://E) ->
      format('  ~d. ~w/~w-~w~n', [I, C, N, V])
  ; format('  ~d. ~w~n', [I, pkg://E])
  ),
  I2 is I + 1,
  depclean:print_pkg_list_numbered(I2, Es).

uninstall_order(Removable, Order, Cyclic) :-
  sort(Removable, Nodes),
  list_to_ord_set(Nodes, NodeSet),
  depclean:build_edges(NodeSet, Nodes, EdgesAssoc),
  depclean:toposort(Nodes, EdgesAssoc, Order, Cyclic).

% Build adjacency list A -> [B...] (A depends on B), restricted to removable nodes.
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

% Direct installed runtime deps of an installed pkg:// entry, computed via repo metadata.
direct_deps_installed(pkg://InstalledEntry, DepsInstalled) :-
  depclean:installed_to_repo_entry(pkg://InstalledEntry, RepoEntry),
  depclean:direct_deps_from_repo_entry(RepoEntry, DepsInstalled),
  !.

direct_deps_from_repo_entry(Repo://Entry, DepsInstalled) :-
  % Compute effective dependency model for run-time deps of the repo entry.
  query:search(model(Model,required_use(_R),build_with_use(_B)), Repo://Entry),
  query:memoized_search(model(dependency(MergedDeps0,run)):config?{Model}, Repo://Entry),
  add_self_to_dep_contexts(Repo://Entry, MergedDeps0, MergedDeps),
  findall(pkg://DepInstalled,
          depclean:dep_literal_installed_dep(MergedDeps, DepInstalled),
          Deps0),
  sort(Deps0, DepsInstalled).

dep_literal_installed_dep(MergedDeps, DepInstalled) :-
  member(D0, MergedDeps),
  depclean:dep_term_cn_deps(D0, Action, C, N, PackageDeps),
  rules:merge_slot_restriction(Action, C, N, PackageDeps, SlotReq),
  query:search([repository(pkg),category(C),name(N),installed(true)], pkg://DepInstalled),
  rules:query_search_slot_constraint(SlotReq, pkg://DepInstalled, _),
  rules:installed_entry_satisfies_package_deps(Action, C, N, PackageDeps, pkg://DepInstalled).

% Extract (Action,C,N,Deps) from a merged dependency literal.
dep_term_cn_deps(grouped_package_dependency(_Strength,C,N,PackageDeps):Action?{_}, Action, C, N, PackageDeps) :- !.
dep_term_cn_deps(grouped_package_dependency(_Strength,C,N,PackageDeps):Action,    Action, C, N, PackageDeps) :- !.
dep_term_cn_deps(grouped_package_dependency(_Strength,C,N,PackageDeps),           run,    C, N, PackageDeps) :- !.

% Kahn toposort on adjacency list A -> Bs (A depends on B).
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

indegrees(Nodes, Edges, InDeg) :-
  empty_assoc(Empty0),
  foldl([N,In,Out]>>put_assoc(N, In, 0, Out), Nodes, Empty0, Empty1),
  foldl(depclean:indegree_acc(Edges), Nodes, Empty1, InDeg).

indegree_acc(Edges, A, In, Out) :-
  ( get_assoc(A, Edges, Bs) -> true ; Bs = [] ),
  foldl(depclean:inc_indeg, Bs, In, Out).

inc_indeg(B, In, Out) :-
  ( get_assoc(B, In, V0) -> V1 is V0 + 1, put_assoc(B, In, V1, Out)
  ; put_assoc(B, In, 1, Out)
  ).

kahn([], Nodes, _Edges, InDeg, Acc, Order, Remaining) :-
  reverse(Acc, Order),
  findall(N, (member(N, Nodes), get_assoc(N, InDeg, V), V > 0), Remaining).
kahn([N|Q], Nodes, Edges, InDeg0, Acc, Order, Remaining) :-
  ( get_assoc(N, Edges, Bs) -> true ; Bs = [] ),
  put_assoc(N, InDeg0, -1, InDeg1), % mark processed
  depclean:dec_neighbors(Bs, InDeg1, InDeg2, NewZeros),
  append(Q, NewZeros, Q2),
  depclean:kahn(Q2, Nodes, Edges, InDeg2, [N|Acc], Order, Remaining).

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
%
% Uses VDB metadata:
% - needed_elf2/1 from NEEDED.ELF.2
% - provides_elf2/1 from PROVIDES.ELF.2
%
% This is a best-effort approximation of Portage preserved-libs behavior.

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

build_provides_map(Installed, Map) :-
  empty_assoc(Empty),
  foldl(depclean:provides_acc, Installed, Empty, Map).

provides_acc(pkg://E, In, Out) :-
  ( query:search(provides_elf2(Provides0), pkg://E) -> true ; Provides0 = [] ),
  foldl(depclean:provides_tok_put(pkg://E), Provides0, In, Out).

provides_tok_put(Pkg, Tok, In, Out) :-
  ( get_assoc(Tok, In, Providers0) ->
      ord_add_element(Providers0, Pkg, Providers),
      put_assoc(Tok, In, Providers, Out)
  ; put_assoc(Tok, In, [Pkg], Out)
  ).

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
