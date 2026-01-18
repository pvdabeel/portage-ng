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
      ( query:search([repository(pkg),category(C),name(N),version(V),installed(true)], pkg://InstalledEntry),
        query:search([category(C),name(N),version(V)], Repo://Entry) ->
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
  nl.

