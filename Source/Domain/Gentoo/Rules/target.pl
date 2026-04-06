/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> TARGET
Action-level resolution helpers for :install, :run, :update, and :downgrade.

The rule/2 clauses in rules.pl delegate the body of each action here:

  - `resolve_install/3`   — :install proof body
  - `resolve_run/3`       — :run proof body (includes update-vs-install)
  - `update_txn_conditions/3` — :update / :downgrade proof body

All actions share a common pattern:

  1. Compute the REQUIRED_USE model and build_with_use state
     (`resolve_required_use/8`).
  2. Compute and memoize the grouped dependency model.
  3. Optionally generate deep-update goals (when `--deep` is active).
  4. Assemble proof conditions: USE constraints, slot constraint, download
     goal (unless virtual/acct-*), and the dependency closure.

== Deep updates ==

When `preference:flag(deep)` is set, `deep_update_goals/3` scans the
dependency model for installed packages that have a newer version
available in the same slot, and schedules transactional update goals
for them.

== Dependency CN extraction ==

`dep_cn/3` extracts the category/name pair from various dependency
literal formats.  It is used by deep_update_goals/3 and by the printer
module for PDEPEND goal filtering.
*/

:- module(target, []).

% =============================================================================
%  Target candidate resolution (CN vs CNV)
% =============================================================================

%! target:is_cn_target(+Q) is semidet.
%
% True when Q is a category/name-only target (no version constraint).

target:is_cn_target(qualified_target(none, _, _, _, version_none, _)).
target:is_cn_target(qualified_target(none, _, _, _, [[],'','','',''], _)).


%! target:resolve_candidate(+Q, -Repository://Ebuild) is nondet.
%
% For CN targets: generates visible candidates first (not masked, keyword-
% accepted, not license-masked), then falls back to all candidates.  This
% ensures the prover picks a visible version before resorting to relaxation.
%
% For CNV targets: generates candidates in standard version-descending order
% without visibility bias, since the user explicitly requested a specific
% version and relaxation is the expected path if it's not visible.

target:resolve_candidate(Q, Repository://Ebuild) :-
  ( target:is_cn_target(Q) ->
      ( kb:query(Q, Repository://Ebuild),
        candidate:entry_has_accepted_keyword(Repository://Ebuild),
        \+ query:search(masked(true), Repository://Ebuild),
        \+ candidate:license_masked(Repository://Ebuild)
      ; kb:query(Q, Repository://Ebuild)
      )
  ; kb:query(Q, Repository://Ebuild)
  ).


% =============================================================================
%  Transactional update prerequisites
% =============================================================================

%! target:update_txn_conditions(+RepoEntry, +Context, -Conditions)
%
% Computes the proof conditions for a transactional update or downgrade.
% Context must contain `replaces(OldRepo://OldEntry)`.
%
% Steps: 1) resolve required_use model + build_with_use state; 2) compute
% grouped dependency model (memoized); 3) inject self-references into
% dependency contexts; 4) optionally generate deep-update goals; 5) assemble
% conditions (USE + slot + download + deps). For virtual/acct-group/acct-user
% packages the download goal is omitted.

update_txn_conditions(Repository://Ebuild, Context, Conditions) :-
  use:context_build_with_use_state(Context, B),
  (memberchk(required_use:R,Context) -> true ; R = []),
  query:search(model(Model,required_use(R),build_with_use(B)),Repository://Ebuild),

  query:memoized_search(model(dependency(MergedDeps0,install)):config?{Model},Repository://Ebuild),
  dependency:add_self_to_dep_contexts(Repository://Ebuild, MergedDeps0, MergedDeps),

  ( preference:flag(deep)
  -> deep_update_goals(Repository://Ebuild, MergedDeps, DeepUpdates)
  ;  DeepUpdates = []
  ),

  query:search([category(CNew),name(NNew),select(slot,constraint([]),SAll)], Repository://Ebuild),
  ( memberchk(CNew,['virtual','acct-group','acct-user'])
    -> Base0 = [ constraint(use(Repository://Ebuild):{R}),
                 constraint(slot(CNew,NNew,SAll):{Ebuild})
                 |DeepUpdates],
       append(Base0, MergedDeps, Conditions)
    ;  Base0 = [ constraint(use(Repository://Ebuild):{R}),
                 constraint(slot(CNew,NNew,SAll):{Ebuild}),
                 Repository://Ebuild:download?{[required_use:R,build_with_use:B]}
                 |DeepUpdates],
       append(Base0, MergedDeps, Conditions)
  ).


% =============================================================================
%  Deep-update goal generation
% =============================================================================

%! target:deep_update_goals(+Self, +MergedDeps, -DeepUpdates)
%
% When `--deep` is active, scans MergedDeps for dependency packages that are
% currently installed and have a newer version available in the same slot.
% For each such package, generates a transactional update goal annotated with
% `replaces(OldRepo://OldEntry)`. Only packages from the VDB (`pkg`) are
% considered. The parent entry (Self) is excluded to prevent self-update loops.

deep_update_goals(Self, MergedDeps, DeepUpdates) :-
  ( preference:accept_keywords(K)
    -> KeywordQ = [keywords(K)]
    ;  KeywordQ = []
  ),
  findall(C-N, (member(Dep, MergedDeps), dep_cn(Dep, C, N)), CN0),
  sort(CN0, CN),
  findall(NewRepo://NewEntry:update?{[replaces(OldRepo://OldEntry)]},
          ( member(C-N, CN),
            query:search([name(N),category(C),installed(true)], pkg://OldEntry),
            OldRepo = pkg,
            pkg://OldEntry \== Self,
            query:search(version(OldVer), pkg://OldEntry),
            query:search(slot(Slot0), pkg://OldEntry),
            candidate:canon_slot(Slot0, Slot),
            ( KeywordQ == []
              -> query:search(latest([select(repository,notequal,pkg),
                                      category(C),name(N),slot(Slot),
                                      select(version,greater,OldVer)]),
                              NewRepo://NewEntry)
              ;  query:search(latest([select(repository,notequal,pkg),
                                      category(C),name(N),slot(Slot),keywords(K),
                                      select(version,greater,OldVer)]),
                              NewRepo://NewEntry)
            )
          ),
          Updates0),
  sort(Updates0, DeepUpdates).


% =============================================================================
%  Dependency CN extraction
% =============================================================================

%! target:dep_cn(+DepLiteral, -C, -N)
%
% Extracts the category (C) and name (N) from a dependency literal. Handles
% grouped_package_dependency/4, grouped_package_dependency/3, and concrete
% Repo://Entry:Action literals.

dep_cn(grouped_package_dependency(_,C,N,_):_Action?{_Ctx}, C, N) :- !.
dep_cn(grouped_package_dependency(C,N,_):_Action?{_Ctx}, C, N) :- !.
dep_cn(Repo://Entry:_Action?{_Ctx}, C, N) :-
  query:search([category(C),name(N)], Repo://Entry),
  !.
dep_cn(Repo://Entry:_Action, C, N) :-
  query:search([category(C),name(N)], Repo://Entry),
  !.


% =============================================================================
%  Depclean rewriting
% =============================================================================

%! target:depclean_rewrite_deps(+Deps0, +ParentCtx, -Deps)
%
% Rewrites all dependency literals to the `:depclean` action for
% depclean closure traversal.

target:depclean_rewrite_deps([], _ParentCtx, []) :- !.
target:depclean_rewrite_deps([D0|Rest0], ParentCtx, [D|Rest]) :-
  target:depclean_rewrite_dep(D0, ParentCtx, D),
  target:depclean_rewrite_deps(Rest0, ParentCtx, Rest).


target:depclean_rewrite_dep(Term:Action?{Ctx0}, _ParentCtx, Term:depclean?{Ctx0}) :-
  nonvar(Action),
  !.
target:depclean_rewrite_dep(Term:Action, _ParentCtx, Term:depclean?{[]}) :-
  nonvar(Action),
  !.
target:depclean_rewrite_dep(Term, _ParentCtx, Term:depclean?{[]}) :-
  !.


% =============================================================================
%  CLI flag helpers
% =============================================================================

%! target:is_excluded(+RepoEntry) is semidet.
%
% True if the entry matches a config:excluded_atom/1 pattern.

target:is_excluded(Repository://Entry) :-
  config:excluded_atom(Pattern),
  query:search([category(C),name(N)], Repository://Entry),
  ( atom_concat(C, '/', CN0), atom_concat(CN0, N, CN),
    CN == Pattern
  ; N == Pattern
  ),
  !.


%! target:is_excluded_cn(+Category, +Name) is semidet.
%
% True if the C/N pair matches a config:excluded_atom/1 pattern.

target:is_excluded_cn(C, N) :-
  config:excluded_atom(Pattern),
  ( atom_concat(C, '/', CN0), atom_concat(CN0, N, CN),
    CN == Pattern
  ; N == Pattern
  ),
  !.


%! target:rebuild_if_newer_available(+InstalledEntry) is semidet.
%
% True if --rebuild-if-new-rev or --rebuild-if-new-ver is active and
% a newer revision or version of the installed package exists in the repo.

target:rebuild_if_newer_available(pkg://InstalledEntry) :-
  ( preference:flag(rebuildnewrev) ; preference:flag(rebuildnewver) ),
  query:search([category(C),name(N),version(VInstalled)], pkg://InstalledEntry),
  preference:accept_keywords(K),
  query:search([select(repository,notequal,pkg),category(C),name(N),keywords(K),version(VRepo)],
               _://_),
  ( preference:flag(rebuildnewver)
  -> VRepo @> VInstalled
  ;  VRepo @>= VInstalled
  ),
  !.


% -----------------------------------------------------------------------------
%  Install resolution
% -----------------------------------------------------------------------------

%! target:resolve_install(+Entry, +Context, -Conditions) is nondet.
%
% Resolves the :install action for a candidate ebuild: computes
% REQUIRED_USE model, dependency closure, and assembles proof conditions.

target:resolve_install(Repository://Ebuild, Context, Conditions) :-
  featureterm:ctx_take_after_with_mode(Context, After, AfterForDeps, Context1),
  query:search([category(C),name(N),select(slot,constraint([]),S)], Repository://Ebuild),
  query:search(version(Ver), Repository://Ebuild),
  Selected = constraint(selected_cn(C,N):{ordset([selected(Repository,Ebuild,install,Ver,S)])}),
  target:resolve_required_use(install, C, N, Repository://Ebuild, Context1, R, BResolved, Model),
  ( target:install_dep_model(Repository://Ebuild, Model, AfterForDeps, install,
                             Selected, C, N, S, R, BResolved, After, Conditions)
  ; feature_unification:unify([issue_with_model(explanation)], Context1, Ctx1),
    Conditions = [assumed(Repository://Ebuild:install?{Ctx1})]
  ).


%! target:install_dep_model(+Entry, +Model, +AfterForDeps, +Phase, +Selected, +C, +N, +S, +R, +BResolved, +After, -Conditions) is semidet.
%
% Computes and assembles the dependency model for the :install proof.
% The model-fallback assumption in resolve_install only wraps this step.

target:install_dep_model(Repository://Ebuild, Model, AfterForDeps, install,
                         Selected, C, N, S, R, BResolved, After, Conditions) :-
  query:memoized_search(model(dependency(MergedDeps0,install)):config?{Model}, Repository://Ebuild),
  dependency:add_self_to_dep_contexts(Repository://Ebuild, MergedDeps0, MergedDeps),
  featureterm:add_after_to_dep_contexts(AfterForDeps, MergedDeps, MergedDepsAfter),
  candidate:order_deps_for_proof(install, MergedDepsAfter, MergedDepsOrdered),
  ( memberchk(C, ['virtual','acct-group','acct-user']) ->
      Prefix0 = [ Selected,
                  constraint(use(Repository://Ebuild):{R}),
                  constraint(slot(C,N,S):{Ebuild})
                ],
      append(Prefix0, MergedDepsOrdered, Conditions0)
  ; ( AfterForDeps == none ->
        DownloadCtx0 = [required_use:R,build_with_use:BResolved]
    ; DownloadCtx0 = [after(AfterForDeps),required_use:R,build_with_use:BResolved]
    ),
    Prefix0 = [ Selected,
                constraint(use(Repository://Ebuild):{R}),
                constraint(slot(C,N,S):{Ebuild}),
                Repository://Ebuild:download?{DownloadCtx0}
              ],
    append(Prefix0, MergedDepsOrdered, Conditions0)
  ),
  featureterm:ctx_add_after_condition(After, AfterForDeps, Conditions0, Conditions).


% -----------------------------------------------------------------------------
%  Run resolution
% -----------------------------------------------------------------------------

%! target:resolve_run(+Entry, +Context, -Conditions) is nondet.
%
% Resolves the :run action for a candidate ebuild: computes REQUIRED_USE
% model, determines update/install action, tags suggestions, and assembles
% proof conditions.

target:resolve_run(Repository://Ebuild, Context, Conditions) :-
  featureterm:ctx_take_after_with_mode(Context, After, AfterForDeps, Context1),
  query:search([category(C),name(N),select(slot,constraint([]),S)], Repository://Ebuild),
  query:search(version(Ver), Repository://Ebuild),
  Selected = constraint(selected_cn(C,N):{ordset([selected(Repository,Ebuild,run,Ver,S)])}),
  target:resolve_required_use(run, C, N, Repository://Ebuild, Context1, R, BResolved, Model),
  ( target:run_dep_model(Repository://Ebuild, Model, AfterForDeps, run,
                         Selected, C, N, S, R, BResolved, After, Context1, Conditions)
  ; feature_unification:unify([issue_with_model(explanation)], Context1, Ctx1),
    Conditions = [assumed(Repository://Ebuild:run?{Ctx1})]
  ).


%! target:run_dep_model(+Entry, +Model, +AfterForDeps, +Phase, +Selected, +C, +N, +S, +R, +BResolved, +After, +Context, -Conditions) is semidet.
%
% Computes and assembles the dependency model for the :run proof.
% The model-fallback assumption in resolve_run only wraps this step.

target:run_dep_model(Repository://Ebuild, Model, AfterForDeps, run,
                     Selected, C, N, S, R, BResolved, After, _Context1, Conditions) :-
  query:memoized_search(model(dependency(MergedDeps0,run)):config?{Model}, Repository://Ebuild),
  dependency:add_self_to_dep_contexts(Repository://Ebuild, MergedDeps0, MergedDeps),
  featureterm:add_after_to_dep_contexts(AfterForDeps, MergedDeps, MergedDepsAfter),
  candidate:order_deps_for_proof(run, MergedDepsAfter, MergedDepsOrdered),
  target:run_install_action(Repository://Ebuild, C, N, R, BResolved, InstallAction, InstallCtx0),
  target:run_tag_suggestions(Repository://Ebuild, BResolved, R, InstallCtx0, InstallCtx),
  InstallOrUpdate = Repository://Ebuild:InstallAction?{InstallCtx},
  Prefix0 = [Selected,
             constraint(use(Repository://Ebuild):{R}),
             constraint(slot(C,N,S):{Ebuild}),
             InstallOrUpdate],
  append(Prefix0, MergedDepsOrdered, Conditions0),
  featureterm:ctx_add_after_condition(After, AfterForDeps, Conditions0, Conditions).


% -----------------------------------------------------------------------------
%  Shared: REQUIRED_USE resolution
% -----------------------------------------------------------------------------

%! target:resolve_required_use(+Phase, +C, +N, +Entry, +Context, -R, -BResolved, -Model) is semidet.
%
% Computes the REQUIRED_USE stable model, verifies BWU cross-dep conflicts,
% and resolves build_with_use against REQUIRED_USE. Fails (recording the
% violation) when REQUIRED_USE cannot be satisfied.

target:resolve_required_use(_Phase, C, N, Repository://Ebuild, Context1, R, BResolved, Model) :-
  use:context_build_with_use_state(Context1, B),
  ( memberchk(required_use:R, Context1) -> true ; true ),
  query:search(model(Model,required_use(R),build_with_use(B)), Repository://Ebuild),
  use:check_bwu_cross_dep(C, N, Repository://Ebuild, B),
  use:build_with_use_resolve_required_use(B, Repository://Ebuild, BResolved0),
  use:stabilize_required_use(Repository://Ebuild, BResolved0, BResolved),
  ( \+ use:verify_required_use_with_bwu(Repository://Ebuild, BResolved) ->
      use:describe_required_use_violation(Repository://Ebuild, BResolved, ViolDesc),
      ( \+ memo:requse_violation_(C, N, _) ->
          assertz(memo:requse_violation_(C, N, ViolDesc))
      ; true
      ),
      fail
  ; true
  ).


% -----------------------------------------------------------------------------
%  Run: update-vs-install decision
% -----------------------------------------------------------------------------

%! target:run_install_action(+Entry, +C, +N, +R, +BResolved, -Action, -Ctx) is det.
%
% Determines whether the :run proof should schedule an install, update,
% or downgrade based on the VDB state.

target:run_install_action(Repository://Ebuild, C, N, R, BResolved, InstallAction, InstallCtx0) :-
  ( \+ preference:flag(emptytree),
    candidate:entry_slot_default(Repository, Ebuild, SlotNew),
    query:search(package(C,N), pkg://_),
    candidate:installed_entry_cn(C, N, OldRepo, OldEbuild),
    OldEbuild \== Ebuild,
    ( query:search(slot(SlotOld0), OldRepo://OldEbuild)
      -> candidate:canon_slot(SlotOld0, SlotOld)
      ;  SlotOld = SlotNew
    ),
    SlotOld == SlotNew
  ->
    ( query:search(version(NewVer_), Repository://Ebuild),
      query:search(version(OldVer_), OldRepo://OldEbuild),
      eapi:version_compare(<, NewVer_, OldVer_)
    -> UpdateOrDowngrade = downgrade
    ;  UpdateOrDowngrade = update
    ),
    InstallCtx0 = [replaces(OldRepo://OldEbuild),required_use:R,build_with_use:BResolved],
    InstallAction = UpdateOrDowngrade
  ; InstallCtx0 = [required_use:R,build_with_use:BResolved],
    InstallAction = install
  ).


% -----------------------------------------------------------------------------
%  Run: suggestion tagging
% -----------------------------------------------------------------------------

%! target:run_tag_suggestions(+Entry, +BResolved, +R, +Ctx0, -Ctx) is det.
%
% Tags the install context with unmask, keyword-acceptance, and USE-change
% suggestions when applicable.

target:run_tag_suggestions(Repository://Ebuild, BResolved, R, Ctx0, Ctx) :-
  ( prover:assuming(unmask), query:search(masked(true), Repository://Ebuild) ->
      Ctx1 = [suggestion(unmask, Repository://Ebuild)|Ctx0]
  ; candidate:license_masked(Repository://Ebuild) ->
      Ctx1 = [suggestion(unmask, Repository://Ebuild)|Ctx0]
  ; Ctx1 = Ctx0
  ),
  ( prover:assuming(keyword_acceptance),
    candidate:candidate_non_accepted_keyword(Repository://Ebuild, NonAccKw) ->
      Ctx2 = [suggestion(accept_keyword, NonAccKw)|Ctx1]
  ; Ctx2 = Ctx1
  ),
  ( BResolved \== use_state([],[]),
    use:build_with_use_changes(BResolved, Repository://Ebuild, BWUChanges),
    BWUChanges \== []
  -> true
  ; BWUChanges = []
  ),
  ( use:model_required_use_changes(R, RUChanges),
    RUChanges \== []
  -> true
  ; RUChanges = []
  ),
  append(BWUChanges, RUChanges, AllUseChanges0),
  sort(AllUseChanges0, AllUseChanges),
  ( AllUseChanges \== [] ->
      Ctx = [suggestion(use_change, Repository://Ebuild, AllUseChanges)|Ctx2]
  ; Ctx = Ctx2
  ).