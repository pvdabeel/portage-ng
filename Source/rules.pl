/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> RULES
Declarative hub containing all rule/2 clauses for the portage-ng resolver.

The prover calls rules:rule/2 to expand literals into proof conditions.
This file contains all rule/2 clauses (the "what"), while implementation
logic (the "how") is delegated to submodules in Source/Rules/.
Submodules are loaded by portage-ng.pl (see load_standalone_modules,
load_worker_modules).

== Submodules ==

| Module       | Responsibility                                           |
|--------------|----------------------------------------------------------|
| candidate.pl | Candidate selection, slot merging, version handling,     |
|              | CN-consistency, blocker matching, dependency ordering    |
| dependency.pl| Self-context injection, USE-requirement collection,      |
|              | slot/build-with-use context propagation                  |
| heuristic.pl | Domain-specific prover hooks (reprove, snapshots)        |
| memo.pl      | Thread-local caching declarations, clear_caches/0        |
| target.pl    | Transactional update/downgrade condition building        |
| use.pl       | USE flag evaluation, conditionals, build_with_use,       |
|              | newuse, REQUIRED_USE satisfaction                        |

== Rule sections ==

  1. *Ebuild targets* -- target/2 resolution, download, fetchonly,
     install, run, reinstall, uninstall, update, downgrade, upgrade.
  2. *Dependency resolution* -- package_dependency/8 (weak/strong
     blockers), grouped_package_dependency/4, depclean traversal.
  3. *USE conditionals* -- use_conditional_group/4 (positive/negative,
     context-aware and contextless variants).
  4. *Choice groups* -- exactly_one_of_group, at_most_one_of_group,
     any_of_group, all_of_group.
  5. *Required USE* -- required/1, blocking/1, naf/1, conflict/2.
  6. *Prover contract* -- constraint_unify_hook/4, constraint_guard/2,
     proof_obligation/4, proof_obligation_key/3,4.

== Context helpers ==

This file also contains lightweight context manipulation predicates
(ctx_take_after, ctx_add_after, ctx_drop_build_with_use, etc.) that
are used by rule/2 bodies for planning-marker threading.  These remain
here because they are tightly coupled to the rule clause structure and
have no reuse outside rule/2 bodies.

== Prover-level overrides ==

The `assume_blockers`, `assume_conflicts` predicates and their `with_*`
scoped variants delegate to `prover:assuming/1,2`.
*/

:- module(rules, [rule/2]).


% =============================================================================
%  Rule declarations
% =============================================================================
%
%  Each rule/2 clause maps a literal to a list of proof conditions.
%  The prover calls rules:rule(+Literal, -Conditions) to expand the proof
%  tree.  Conditions may include sub-goals (proved recursively),
%  constraint/1 terms (merged into the constraint store), and assumed/1
%  terms (domain assumptions recorded in the proof).


% =============================================================================
%  Ruleset: Ebuild targets
% =============================================================================

% -----------------------------------------------------------------------------
%  Rule: Target candidate (defer selection to prover)
% -----------------------------------------------------------------------------
%
% The CLI used to resolve a concrete candidate (Repo://Ebuild) up-front and then
% prove `Repo://Ebuild:run?{[]}`.
%
% For richer proof/plan integration (notably rule-driven "world" side effects),
% we also allow proving *unresolved* targets
% of the form:
%
%   target(Q, Arg):Action?{Ctx}
%
% where:
% - Q   is a parsed `qualified_target/6` term (see `eapi:qualified_target//1`)
% - Arg is the original CLI atom (used for world registration)
%
% Candidate selection happens inside the proof via `kb:query/2`, so it can
% backtrack under conflicts/constraints.
%

rule(target(Q, _Arg):fetchonly?{Context}, Conditions) :-
  !,
  kb:query(Q, Repository://Ebuild),
  Conditions = [Repository://Ebuild:fetchonly?{Context}].

rule(target(Q, Arg):uninstall?{Context}, Conditions) :-
  !,
  kb:query(Q, Repository://Ebuild),
  kb:query(installed(true), Repository://Ebuild),
  ( preference:flag(oneshot) ->
      WorldConds = []
  ; WorldConds = [world_action(unregister, Arg):world?{[after(Repository://Ebuild:uninstall)]}]
  ),
  Conditions = [Repository://Ebuild:uninstall?{Context}|WorldConds].

% Portage-style merge semantics for a requested target:
% - prove the merge (run)
% - then register the original atom in @world (unless --oneshot)
rule(target(Q, Arg):run?{Context}, Conditions) :-
  !,
  kb:query(Q, Repository://Ebuild),
  Conditions0 = [Repository://Ebuild:run?{Context}],
  ( preference:flag(oneshot) ->
      Conditions = Conditions0
  ; Conditions = [Repository://Ebuild:run?{Context},
                  world_action(register, Arg):world?{[after(Repository://Ebuild:run)]}]
  ).


% -----------------------------------------------------------------------------
%  Rule: Download target
% -----------------------------------------------------------------------------
% Any ebuild can be downloaded.

rule(Repository://Ebuild:download?{Context},Conditions) :-
  !,
  rules:ctx_take_after(Context, After, _CtxNoAfter),
  query:search(ebuild(Ebuild),Repository://Ebuild),
  ( After == none -> Conditions = [] ; Conditions = [After] ).


% -----------------------------------------------------------------------------
%  Rule: World action (side-effectful, executed by interface/builder)
% -----------------------------------------------------------------------------
%
% We encode @world modifications as proof/plan actions so they can be scheduled
% relative to other actions (e.g. after a merge).
%
% Execution is performed outside the prover (currently by interface code), but
% the *decision* to perform a world action is now rule-driven.
%

rule(world_action(_Op,_Arg):world?{Context}, Conditions) :-
  !,
  rules:ctx_take_after(Context, After, _CtxNoAfter),
  ( After == none -> Conditions = [] ; Conditions = [After] ).


% -----------------------------------------------------------------------------
%  Rule: Fetchonly target
% -----------------------------------------------------------------------------
% Fetchonly downloads the ebuild and its dependency tree.
%
% The dependency tree is computed by passing the use model onto the dependencies
% to calculate the corresponding dependency model.
%
% 1. Don't perform downloads for already installed packages, unless the emptytree
%    flag is specified.
%
% 2. When a package is not installed, consider its dependencies, taking into
%    account slot and use restrictions. We consider both runtime as well as
%    compile time dependencies at the same time, since downloading doesn't impose
%    a specific order on handling the dependencies.
%
% We don't trigger downloads for virtual, acct-group or acct-user, since they
% don't have any downloads.

rule(Repository://Ebuild:fetchonly?{Context},Conditions) :-
  !,
  ( query:search(masked(true),   Repository://Ebuild) ->
      Conditions = []
  ; query:search(installed(true),Repository://Ebuild),
    \+preference:flag(emptytree) ->
      Conditions = []
  ; % Normal fetchonly proof — guard: model computation must succeed.
    ( query:search([category(C),name(N),select(slot,constraint([]),S)], Repository://Ebuild),
  use:context_build_with_use_state(Context, B),
  (memberchk(required_use:R,Context) -> true ; true),
  query:search(model(Model,required_use(R),build_with_use(B)),Repository://Ebuild),
      query:memoized_search(model(dependency(MergedDeps0,fetchonly)):config?{Model},Repository://Ebuild)
    ->
  dependency:add_self_to_dep_contexts(Repository://Ebuild, MergedDeps0, MergedDeps),
  ( memberchk(C,['virtual','acct-group','acct-user'])
    -> Conditions = [constraint(use(Repository://Ebuild):{R}),
                     constraint(slot(C,N,S):{Ebuild})
                     |MergedDeps]
    ;  Conditions = [constraint(use(Repository://Ebuild):{R}),
                     constraint(slot(C,N,S):{Ebuild}),
                     Repository://Ebuild:download?{R}
                         |MergedDeps]
      )
    ; % Model-computation fallback (see :install rule comment).
     feature_unification:unify([issue_with_model(explanation)], Context, Ctx1),
      Conditions = [assumed(Repository://Ebuild:install?{Ctx1})]
    )
  ).


% -----------------------------------------------------------------------------
%  Rule: Install target
% -----------------------------------------------------------------------------
% An ebuild is installed, when either:
%
% - Metadata indicates it is installed, and the emptytree flag is not set
%
% or, if the following conditions are satisfied:
%
% - Its require_use dependencies are satisfied,
% - It is downloaded (Only when it is not a virtual, a group or a user),
% - Its compile-time dependencies are satisfied,
% - it can occupy an installation slot.
%
% We don't trigger downloads for virtual, acct-group or acct-user.

rule(Repository://Ebuild:install?{Context},Conditions) :-
  !,
  ( query:search(masked(true),   Repository://Ebuild) ->
      Conditions = []
  ; query:search(installed(true),Repository://Ebuild),
    \+ preference:flag(emptytree) ->
      Conditions = []  % todo check new build_with_use requirements
  ; rules:ctx_take_after_with_mode(Context, After, AfterForDeps, Context1),

    % 1. Get some metadata we need further down

    ( % Normal install proof
      query:search([category(C),name(N),select(slot,constraint([]),S)], Repository://Ebuild),
      query:search(version(Ver), Repository://Ebuild),
      Selected = constraint(selected_cn(C,N):{ordset([selected(Repository,Ebuild,install,Ver,S)])}),

      % 2. Compute required_use stable model, if not already passed on by run.
      %    Thread per-package USE constraints from build_with_use.
      use:context_build_with_use_state(Context1, B),
      ( memberchk(required_use:R,Context1) -> true ; true ),
      query:search(model(Model,required_use(R),build_with_use(B)),Repository://Ebuild),

      % 3. Pass use model onto dependencies to calculate corresponding dependency model,
      %    We pass using config action to avoid package_dependency from generating choices.
      %    The config action triggers use_conditional, any_of_group, exactly_one_of_group,
      %    all_of_group ... choice point generation

      % 4. Compute + memoize dependency model, already grouped by package Category & Name.
      query:memoized_search(model(dependency(MergedDeps0,install)):config?{Model},Repository://Ebuild),
      dependency:add_self_to_dep_contexts(Repository://Ebuild, MergedDeps0, MergedDeps),
      rules:add_after_to_dep_contexts(AfterForDeps, MergedDeps, MergedDepsAfter),
      % Heuristic (parity): prove explicit slot/subslot deps early.
      % Some stacks (notably OCaml Jane Street) rely on a "release series" encoded
      % in SUBSLOT. If we first satisfy a loose dependency (e.g. := / any_same_slot),
      % we can lock selected_cn(C,N) to the newest series and later degrade an
      % explicit :0/0.16 requirement into a bogus "non-existent assumed".
      %
      % Ordering explicit slot/subslot requirements first avoids this class of
      % conflict without changing solver semantics.
      candidate:order_deps_for_proof(install, MergedDepsAfter, MergedDepsOrdered),

      % 5. Pass on relevant package dependencies and constraints to prover
      ( memberchk(C,['virtual','acct-group','acct-user']) ->
          Prefix0 = [ Selected,
                      constraint(use(Repository://Ebuild):{R}),
                      constraint(slot(C,N,S):{Ebuild})
                    ],
          append(Prefix0, MergedDepsOrdered, Conditions0)
      ; ( AfterForDeps == none ->
            DownloadCtx0 = [required_use:R,build_with_use:B]
        ; DownloadCtx0 = [after(AfterForDeps),required_use:R,build_with_use:B]
        ),
        Prefix0 = [ Selected,
                    constraint(use(Repository://Ebuild):{R}),
                    constraint(slot(C,N,S):{Ebuild}),
                    Repository://Ebuild:download?{DownloadCtx0}
                  ],
        append(Prefix0, MergedDepsOrdered, Conditions0)
      ),
      rules:ctx_add_after_condition(After, AfterForDeps, Conditions0, Conditions)
    ; % Model-computation fallback: the dependency model could not be built
      % (e.g. all branches of an any_of_group are keyword-filtered). Produce
      % an assumption so the prover can continue rather than failing silently.
      feature_unification:unify([issue_with_model(explanation)], Context1, Ctx1),
      Conditions = [assumed(Repository://Ebuild:install?{Ctx1})]
    )
  ).


% -----------------------------------------------------------------------------
%  Rule: Run target
% -----------------------------------------------------------------------------
% An ebuild can be run, either:
%
% - it is reportedly installed, and the emptytree flag is not set,
%
% or:
%
% - if it is installed and if its runtime dependencies are satisfied
%
% Accepted in context:
%
% - build_with_use(B)

rule(Repository://Ebuild:run?{Context},Conditions) :-
  !,
  ( % 0. Check if the ebuild is masked or installed
    query:search(masked(true),   Repository://Ebuild) ->
      Conditions = []
  ; query:search(installed(true),Repository://Ebuild), \+preference:flag(emptytree) ->
    ( config:avoid_reinstall(true) ->
        Conditions = []
    ; rules:ctx_take_after_with_mode(Context, After0, AfterForDeps0, Context10),
      Cond0 = [Repository://Ebuild:reinstall?{Context10}],
      rules:ctx_add_after_condition(After0, AfterForDeps0, Cond0, Conditions)
    )
  ; rules:ctx_take_after_with_mode(Context, After, AfterForDeps, Context1),

    ( % Normal run proof
  % 1. Get some metadata we need further down
  query:search([category(C),name(N),select(slot,constraint([]),S)], Repository://Ebuild),
  query:search(version(Ver), Repository://Ebuild),
  Selected = constraint(selected_cn(C,N):{ordset([selected(Repository,Ebuild,run,Ver,S)])}),

  % 2. Compute required_use stable model, extend with build_with_use requirements.
  use:context_build_with_use_state(Context1, B),
  query:search(model(Model,required_use(R),build_with_use(B)),Repository://Ebuild),

      % 3-4. Compute + memoize dependency model, already grouped by package Category & Name.
  query:memoized_search(model(dependency(MergedDeps0,run)):config?{Model},Repository://Ebuild),
  dependency:add_self_to_dep_contexts(Repository://Ebuild, MergedDeps0, MergedDeps),
  rules:add_after_to_dep_contexts(AfterForDeps, MergedDeps, MergedDepsAfter),
  candidate:order_deps_for_proof(run, MergedDepsAfter, MergedDepsOrdered),

  % 5. Pass on relevant package dependencies and constraints to prover
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
        InstallOrUpdate = Repository://Ebuild:UpdateOrDowngrade?{[replaces(OldRepo://OldEbuild),required_use:R,build_with_use:B]}
  ; InstallOrUpdate = Repository://Ebuild:install?{[required_use:R,build_with_use:B]}
  ),
  Prefix0 = [Selected,
             constraint(use(Repository://Ebuild):{R}),
             constraint(slot(C,N,S):{Ebuild}),
             InstallOrUpdate],
  append(Prefix0, MergedDepsOrdered, Conditions0),
      rules:ctx_add_after_condition(After, AfterForDeps, Conditions0, Conditions)
    ; % Model-computation fallback (see :install rule comment).
      feature_unification:unify([issue_with_model(explanation)], Context1, Ctx1),
      Conditions = [assumed(Repository://Ebuild:run?{Ctx1})]
    )
  ).


% -----------------------------------------------------------------------------
%  Rule: Reinstall target
% -----------------------------------------------------------------------------
% An ebuild can be reinstalled, when:
%
% - it is reportedly installed, and the emptytree flag is not set.

rule(Repository://Ebuild:reinstall?{_},[]) :-
  \+(preference:flag(emptytree)),
  query:search(installed(true),Repository://Ebuild),!. % todo: retrieve installation context


% -----------------------------------------------------------------------------
%  Rule: Uninstall target
% -----------------------------------------------------------------------------
% An ebuild can be uninstalled, when:
%
% - it is reportedly installed, and we are not proving emptytree

rule(Repository://Ebuild:uninstall?{_},[]) :-
  \+(preference:flag(emptytree)),
  query:search(installed(true),Repository://Ebuild),!.

% Note: this may leave the Model and Proof for the other packages incomplete - todo: implement depclean.


% -----------------------------------------------------------------------------
%  Rule: Update target
% -----------------------------------------------------------------------------
% An ebuild can be updated, when:
%
% - it is reportedly installed, and the emptytree flag is not set,
% - a higher version is available,
% - the accept_keywords filter is satisfied.

% Wrapper: updating an *installed* entry selects a replacement version (same slot)
% and schedules the actual transactional update on that replacement version.
rule(Repository://Ebuild:update?{Context},Conditions) :-
  \+ memberchk(replaces(_), Context),
  \+(preference:flag(emptytree)),
  preference:accept_keywords(K),
  % Determine the installed version + identity (C/N) from the concrete entry.
  query:search([category(Category),name(Name),version(VersionInstalled),installed(true)],
              Repository://Ebuild),
  % Find the latest acceptable version for this C/N in the repo set.
  % Update semantics stay within the same slot (upgrade semantics cross slots and
  % will be introduced later).
  ( query:search(slot(SlotInstalled), Repository://Ebuild)
    -> query:search(latest([name(Name),category(Category),keywords(K),slot(SlotInstalled),
                            select(version,greater,VersionInstalled)]),
                    LatestRepo://LatestEbuild)
    ;  query:search(latest([name(Name),category(Category),keywords(K),
                            select(version,greater,VersionInstalled)]),
                    LatestRepo://LatestEbuild)
  ),
  !,
  % IMPORTANT: represent the update as a single transactional action on the
  % *new* version, annotated with the old version it replaces.
  feature_unification:unify([replaces(Repository://Ebuild)], Context, Ctx1),
  Conditions = [LatestRepo://LatestEbuild:update?{Ctx1}].

% If the user targets a specific version with :update and it is not installed,
% treat it as a transactional same-slot replacement when an older version is
% installed, otherwise fall back to a plain install.
rule(Repository://Ebuild:update?{Context},Conditions) :-
  \+ memberchk(replaces(_), Context),
  \+(preference:flag(emptytree)),
  query:search([category(Category),name(Name)], Repository://Ebuild),
  \+ query:search(installed(true), Repository://Ebuild),
  % Try same-slot replacement first (if slot is known).
  ( candidate:entry_slot_default(Repository, Ebuild, SlotNew),
    candidate:installed_entry_cn(Category, Name, OldRepo, OldEbuild),
    ( query:search(slot(SlotOld0), OldRepo://OldEbuild)
      -> candidate:canon_slot(SlotOld0, SlotOld)
      ;  SlotOld = SlotNew
    ),
    SlotOld == SlotNew
  -> feature_unification:unify([replaces(OldRepo://OldEbuild)], Context, UpdCtx),
     target:update_txn_conditions(Repository://Ebuild, UpdCtx, Conditions)
  ;  Conditions = [Repository://Ebuild:install?{Context}]
  ),
  !.

% Otherwise, updating an already-installed version is a no-op (already current or
% no acceptable newer version).
rule(Repository://Ebuild:update?{_Context},[]) :-
  query:search(installed(true), Repository://Ebuild),
  !.

% Actual transactional update on a chosen replacement entry. This action is
% responsible for the "remove old + merge new" atomicity inside the same slot.
rule(Repository://Ebuild:update?{Context},Conditions) :-
  memberchk(replaces(_OldRepo://_OldEbuild), Context),
  !,
  target:update_txn_conditions(Repository://Ebuild, Context, Conditions).


% -----------------------------------------------------------------------------
%  Rule: Downgrade target
% -----------------------------------------------------------------------------
% A downgrade is semantically identical to an update (transactional same-slot
% replacement) but with a lower version replacing a higher one. The version
% direction is already captured in the action name; the proof mechanics are
% the same as for update.

% Transactional downgrade with replaces in context (produced by the target rule
% or grouped dependency rule when the candidate version < installed version).
rule(Repository://Ebuild:downgrade?{Context},Conditions) :-
  memberchk(replaces(_OldRepo://_OldEbuild), Context),
  !,
  target:update_txn_conditions(Repository://Ebuild, Context, Conditions).

% Downgrading an already-installed version is a no-op.
rule(Repository://Ebuild:downgrade?{_Context},[]) :-
  query:search(installed(true), Repository://Ebuild),
  !.

% Fallback: downgrade without replaces context — treat as install.
rule(Repository://Ebuild:downgrade?{Context},Conditions) :-
  \+ memberchk(replaces(_), Context),
  !,
  Conditions = [Repository://Ebuild:install?{Context}].


% -----------------------------------------------------------------------------
%  Rule: Upgrade target
% -----------------------------------------------------------------------------
% An ebuild can be upgraded, when:
%
% - it is reportedly installed, and the emptytree flag is not set,
% - a higher version is available,
% - the accept_keywords filter is satisfied.

% Upgrade logic will be introduced later (world/set upgrades + --deep).

% todo: deep


% =============================================================================
%  Ruleset: Dependency resolution
% =============================================================================
%
% Ebuilds use package dependencies to express relations (conflicts or requirements)
% on other ebuilds.
%
% Ebuilds use package dependencies to express relations (conflicts or requirements) on
% other ebuilds.


% -----------------------------------------------------------------------------
%  Rule: Conflicting package
% -----------------------------------------------------------------------------
% EAPI 8.2.6.2: a weak block can be ignored by the package manager
%
% Efficient semantics: record the blocker as a global side-condition (constraint).
% Enforcement is done in the prover (so it can backtrack to alternative candidates)
% and can consider both "future" (later selections) and "past" (already selected).
rule(package_dependency(Phase,weak,C,N,O,V,S,_U):_Action?{Context},
     Conditions) :-
  % Weak blockers are extremely common (esp. in system sets like systemd/udev),
  % and enforcing them as hard constraints during proving can cause massive
  % backtracking explosions. We record them as domain assumptions so the plan
  % can still be computed, while the printer can warn the user.
  BlockedSpecs = [blocked(weak,Phase,O,V,S)],
  candidate:blocker_source_constraints(C, N, BlockedSpecs, Context, SourceConds),
  candidate:blocker_assumption_ctx(Context, AssCtx),
  append(SourceConds,
         [assumed(blocker(weak, Phase, C, N, O, V, S)?{AssCtx})],
         Conditions),
  !.


% -----------------------------------------------------------------------------
%  Rule: Conflicting package
% -----------------------------------------------------------------------------
% EAPI 8.2.6.2: a strong block is satisfied when no suitable candidate is satisfied
%
% In portage-ng we implement strong blockers as "remove if installed" (harder
% semantics like "forbid co-installation in the same plan" can be layered in
% the planner/printer using the planned package set).
rule(package_dependency(Phase,strong,C,N,O,V,S,U):_Action?{Context},
     Conditions) :-
  ( rules:assume_blockers ->
      candidate:blocker_assumption_ctx(Context, AssCtx),
      Conditions = [assumed(blocker(strong, Phase, C, N, O, V, S)?{AssCtx})]
  ; % IMPORTANT (Portage-like blockers with USE deps):
    % Many strong blockers are conditional on bracketed USE requirements, e.g.
    %   !!x11-drivers/nvidia-drivers[-libglvnd]
    %
    % Our blocker constraint store (`blocked_cn/2`) currently tracks only C/N, Op, Ver, SlotReq
    % and does NOT record the dependency USE condition. Enforcing such blockers as hard
    % constraints therefore over-approximates (treats them as unconditional) and can
    % cause massive backtracking / false conflicts (e.g. primus wants nvidia-drivers[libglvnd]).
    %
    % To keep proving correct and performant, we enforce ONLY unconditional strong blockers
    % (those without bracketed USE constraints). Conditional strong blockers are recorded
    % as domain assumptions in strict mode.
    ( U == [] ->
        BlockedSpecs = [blocked(strong,Phase,O,V,S)],
        candidate:blocker_source_constraints(C, N, BlockedSpecs, Context, SourceConds),
        Conditions = [constraint(blocked_cn(C,N):{ordset(BlockedSpecs)})|SourceConds]
    ; candidate:blocker_assumption_ctx(Context, AssCtx),
      Conditions = [assumed(blocker(strong, Phase, C, N, O, V, S)?{AssCtx})]
    )
  ),
  !.


% -----------------------------------------------------------------------------
%  Rule: Dependencies on the system profile / core packages
% -----------------------------------------------------------------------------

% In emptytree mode, we treat a small set of "core" packages as provided by the
% system profile / baseline and *do not* force model construction to resolve them.
% This keeps emptytree proofs from exploding into "build the whole OS" graphs.
%
% Note: core package handling during actual dependency *resolution* happens in
% the grouped dependency rule below (`grouped_package_dependency/4`), not here.
rule(package_dependency(_Phase,no,C,N,_O,_V,_S,_U):config?{_Context}, []) :-
    preference:flag(emptytree),
    profile:core_pkg(C,N), !.


% -----------------------------------------------------------------------------
%  Rule: Package dependencies
% -----------------------------------------------------------------------------
% A package dependency is satisfied when a suitable candidate is satisfied,
% a package dependency that has no suitable candidates is "assumed" satisfied
%
% Portage-ng will identify these assumptions in its proof and show them to the
% user prior to continuing to the next stage (i.e. executing the plan).

% Preference: prefer installed packages over new packages, unless 'emptytree' flag
% is used


% package dependency rules for dependency model creation

% In config-phase dependency model construction, package deps normally do not
% generate further conditions. However, for self-hosting dependencies (a package
% depending on itself to build/install), we must ensure the dependency is actually
% satisfiable *without* selecting the current ebuild (unless already installed).
% This allows any_of_group to backtrack to bootstrap alternatives (e.g. go vs
% go-bootstrap) during model construction, before the model is memoized.
rule(package_dependency(Phase,no,C,N,O,V,S,_U):config?{Context},[]) :-
  ( memberchk(self(SelfRepo://SelfEntry), Context),
    query:search([category(C),name(N)], SelfRepo://SelfEntry),
    Phase \== run,
    \+ preference:flag(emptytree)
  ->
    preference:accept_keywords(K),
    ( memberchk(slot(C,N,Ss):{_}, Context) -> true ; Ss = _ ),
    query:search([name(N),category(C),keyword(K),installed(true),
                  select(version,O,V),select(slot,constraint(S),Ss)],
                 _FoundRepo//Candidate),
    Candidate = Candidate
  ; true
  ),
  !.
rule(package_dependency(_,_,_,_,_,_,_,_):config?{_},[]) :- !.
rule(package_dependency(_,no,_,_,_,_,_,_),[]) :- !.


% -----------------------------------------------------------------------------
%  Rule: Conflicting package
% -----------------------------------------------------------------------------
% EAPI 8.2.6.2: a weak block can be ignored by the package manager

rule(grouped_package_dependency(weak,C,N,PackageDeps):Action?{Context},
     Conditions) :-
  !,
  candidate:grouped_blocker_specs(weak, Action, C, N, PackageDeps, Specs),
  candidate:blocker_source_constraints(C, N, Specs, Context, SourceConds),
  candidate:blocker_assumption_ctx(Context, AssCtx),
  findall(assumed(blocker(Strength, Phase, C, N, O, V, SlotReq)?{AssCtx}),
          member(blocked(Strength, Phase, O, V, SlotReq), Specs),
          AssumeConds),
  append(SourceConds, AssumeConds, Conditions).


% -----------------------------------------------------------------------------
%  Rule: Conflicting package
% -----------------------------------------------------------------------------
% EAPI 8.2.6.2: a strong block is satisfied when no suitable candidate is satisfied

rule(grouped_package_dependency(strong,C,N,PackageDeps):Action?{Context},
     Conditions) :-
  !,
  candidate:grouped_blocker_specs_partition(strong, Action, C, N, PackageDeps, EnforceSpecs, AssumeSpecs),
  ( rules:assume_blockers ->
      append(EnforceSpecs, AssumeSpecs, AllSpecs),
      candidate:blocker_source_constraints(C, N, AllSpecs, Context, SourceConds),
      candidate:blocker_assumption_ctx(Context, AssCtx),
      findall(assumed(blocker(Strength, Phase, C, N, O, V, SlotReq)?{AssCtx}),
              ( member(blocked(Strength, Phase, O, V, SlotReq), EnforceSpecs)
              ; member(blocked(Strength, Phase, O, V, SlotReq), AssumeSpecs)
              ),
              AssumeConds),
      append(SourceConds, AssumeConds, Conditions)
  ;
    candidate:blocker_assumption_ctx(Context, AssCtx),
    findall(assumed(blocker(Strength, Phase, C, N, O, V, SlotReq)?{AssCtx}),
            member(blocked(Strength, Phase, O, V, SlotReq), AssumeSpecs),
            AssumeConds),
    ( EnforceSpecs == [] ->
        Conditions = AssumeConds
    ; candidate:blocker_source_constraints(C, N, EnforceSpecs, Context, SourceConds),
      append([constraint(blocked_cn(C,N):{ordset(EnforceSpecs)})|SourceConds], AssumeConds, Conditions)
    )
  ).


% =============================================================================
%  Rule: Package dependencies
% =============================================================================

% IMPORTANT (Portage-like multi-slot deps):
%
% Some packages depend on *multiple* versions of the same cat/pkg simultaneously.
% Portage can satisfy this when the package is multi-slot (versions live in
% different SLOTs), e.g. `dev-dotnet/dotnet-runtime-nugets` where dotnet SDK
% depends on several ~cat/pkg-ver constraints at once.
%
% Our dependency model groups deps by (C,N) which would otherwise attempt to pick
% a *single* candidate satisfying all version constraints. When those constraints
% are meant to be satisfied side-by-side (multi-slot), that is impossible and
% degrades into "non-existent, assumed running".
%
% Split such grouped deps into independent requirements.
rule(grouped_package_dependency(no,C,N,PackageDeps):Action?{Context},Conditions) :-
  candidate:should_split_grouped_dep(PackageDeps),
  !,
  findall(grouped_package_dependency(no, C, N, [D]):Action?{Context},
          member(D, PackageDeps),
          Conditions0),
  sort([constraint(selected_cn_allow_multislot(C,N):{true})|Conditions0], Conditions).

rule(grouped_package_dependency(no,C,N,PackageDeps):Action?{Context},Conditions) :-
  !,
  candidate:augment_package_deps_with_self_rdepend(Action, C, N, Context, PackageDeps, PackageDeps1),
  % Self-dependency at runtime is trivially satisfied: once the package is built,
  % it provides itself. Treat this generically to avoid hard failures on packages
  % that (redundantly) list themselves in RDEPEND.
  ( Action == run,
    memberchk(self(SelfRepo://SelfEntry), Context),
    query:search([category(C),name(N)], SelfRepo://SelfEntry)
  ->
    Conditions = []
  ; preference:flag(emptytree),
    profile:core_pkg(C,N)
  ->
    Conditions = []
  ; \+ preference:flag(emptytree),
    \+ preference:flag(deep),
    candidate:merge_slot_restriction(Action, C, N, PackageDeps1, SlotReq),
    % If an installed instance exists in the same slot, and it satisfies all
    % version constraints, treat the grouped dependency as satisfied.
    %
    % Performance note:
    % Avoid `select(version,O,V)` with variable Op, and `select(slot,constraint(SlotReq),_)`
    % with variable SlotReq, because those prevent compile-time query macro expansion.
    query:search([name(N),category(C),installed(true)],
                 pkg://InstalledEntry),
    candidate:query_search_slot_constraint(SlotReq, pkg://InstalledEntry, _),
    candidate:installed_entry_satisfies_package_deps(Action, C, N, PackageDeps1, pkg://InstalledEntry),
    % IMPORTANT (Portage-like rebuilds):
    % The "keep installed" fast-path must also respect bracketed USE requirements
    % expressed by this dependency (e.g. xmlto[text], glib[introspection]).
    % These are carried as per-package `build_with_use` constraints, so we must
    % derive them from this grouped dep's PackageDeps before deciding the installed
    % instance satisfies the dependency.
    findall(U0, member(package_dependency(_P0,no,C,N,_O,_V,_,U0),PackageDeps1), MergedUse0),
    append(MergedUse0, MergedUse),
    dependency:process_build_with_use(MergedUse, Context, ContextWU, _BWUCons, pkg://InstalledEntry),
    % Portage does not rebuild virtuals based on USE deps: virtuals are satisfied
    % by their provider packages; rebuilding the virtual itself is a no-op.
    ( C == 'virtual'
    -> true
    ; use:installed_entry_satisfies_build_with_use(pkg://InstalledEntry, ContextWU)
    ),
    % --newuse: do not "keep installed" if USE/IUSE has changed since the installed
    % package was built (Portage-like -N behavior).
    ( preference:flag(newuse) ->
        \+ use:newuse_mismatch(pkg://InstalledEntry)
    ; true
    ),
    !   % commit to the first installed entry that satisfies constraints
  ->
    Conditions = []
  ;
    ( candidate:merge_slot_restriction(Action, C, N, PackageDeps1, SlotReq),

      % Candidate selection (portage / overlays)
      %
      % CN-consistency: reuse an already-selected concrete entry when possible.
      %
      % IMPORTANT (:= / any_same_slot correctness):
      % The Context may contain multiple `slot(C,N,...)` facts (multi-slot).
      % If we bind Ss *before* choosing Candidate, we might bind to an unrelated
      % slot constraint and incorrectly render the dependency "unsatisfiable".
      %
      % Therefore:
      % - first choose Candidate (prefer reusing selected_cn when present),
      % - then (optionally) bind Ss from the matching slot(C,N,...) entry for that
      %   exact Candidate, and only use Ss as a lock when enumerating further.
      % If the context already carries a slot lock for this (C,N) (typically via :=),
      % reuse it to restrict candidate choice. This is how we enforce Portage-like
      % `:=` behavior (same slot/subslot as the previously chosen instance).
      %
      % IMPORTANT: do NOT apply this to explicit slot deps [slot(_)] — those are
      % validated via query_search_slot_constraint/3 and must allow multi-slot.
      ( SlotReq == [any_same_slot],
        memberchk(slot(C,N,SsLock0):{_}, Context),
        candidate:canon_any_same_slot_meta(SsLock0, SsLock)
      ->
        true
      ; SsLock = _Unbound
      ),

      % Candidate selection must respect slot constraints.
      %
      % IMPORTANT:
      % - For explicit slot/subslot deps (cat/pkg:0/0.16, :=0/0.16, etc.), we must NOT
      %   blindly reuse an existing selected_cn(C,N) choice that may point at a
      %   different slot/subslot (otherwise the dep degrades into a bogus
      %   "non-existent, assumed ..." domain assumption).
      % - We therefore only reuse selected_cn when it satisfies SlotReq.
      % - Also, only reuse when it is compatible with the effective domain for
      %   this dependency; otherwise, fall back to fresh candidate enumeration.
      ( SlotReq = [slot(_)|_] ->
          candidate:accepted_keyword_candidate(Action, C, N, SlotReq, _Ss0, Context, FoundRepo://Candidate),
          CandPreVerified = false
      ; candidate:selected_cn_candidate_compatible(Action, C, N, SlotReq, PackageDeps1, Context, FoundRepo://Candidate) ->
          CandPreVerified = true
      ; candidate:selected_cn_rejected_candidates(Action, C, N, SlotReq, PackageDeps1, Context, RejectedSelected),
        candidate:accepted_keyword_candidate(Action, C, N, SlotReq, SsLock, Context, FoundRepo://Candidate),
        \+ memberchk(FoundRepo://Candidate, RejectedSelected),
        CandPreVerified = false
      ),

      % Avoid resolving a dep to self unless candidate is already installed
      ( ( memberchk(self(_SelfRepo://SelfEntry1), Context)
        ; memberchk(slot(C,N,_SelfSlot):{SelfEntry1}, Context)
        ),
        Candidate == SelfEntry1
      ->
        \+ preference:flag(emptytree),
        query:search(installed(true), FoundRepo://Candidate)
      ; true
      ),

      ( CandPreVerified == true ->
          true
      ; forall(member(package_dependency(_P1,no,C,N,O,V,_,_), PackageDeps1),
             candidate:query_search_version_select(O, V, FoundRepo://Candidate)),
        candidate:grouped_dep_candidate_satisfies_effective_domain(Action, C, N, PackageDeps1, Context, FoundRepo://Candidate)
      ),
      candidate:candidate_reverse_deps_compatible_with_parent(Context, FoundRepo://Candidate),

      % For PDEPEND edges, we treat the dependency as runtime-soft (cycle-breakable),
      % but we should not propagate or enforce `build_with_use` from the parent.
      % Otherwise large USE_EXPAND sets (llvm_targets_*, python_targets_*) explode
      % the dependency context and can prevent resolution (and cause mismatches).
      % PDEPEND edges also must not inherit the parent's `build_with_use` context.
      ( member(package_dependency(pdepend,_,C,N,_,_,_,_), PackageDeps1) ->
          MergedUse = [],
          rules:ctx_drop_build_with_use_and_assumption_reason(Context, ContextDep)
      ; findall(U0, member(package_dependency(_P2,no,C,N,_O,_V,_,U0),PackageDeps1), MergedUse0),
        append(MergedUse0, MergedUse),
        ContextDep = Context
      ),
      % Enforce bracketed USE constraints (e.g. sys-devel/gcc[objc], python[xml(+)], foo[bar?]).
      use:candidate_satisfies_use_deps(ContextDep, FoundRepo://Candidate, MergedUse),
      dependency:process_build_with_use(MergedUse,ContextDep,NewContext,Constraints,FoundRepo://Candidate),
      candidate:query_search_slot_constraint(SlotReq, FoundRepo://Candidate, SlotMeta),
      dependency:process_slot(SlotReq, SlotMeta, C, N, FoundRepo://Candidate, NewContext, NewerContext),

      % Prefer expressing as update when a pkg-installed entry exists in the same
      % slot and the chosen candidate has a different version (upgrade OR downgrade).
      ( \+ preference:flag(emptytree),
        % Update/reinstall semantics must be per-slot: only treat this as an update
        % when there is an installed instance of (C,N) in the SAME SLOT as the
        % chosen candidate. Otherwise we'd incorrectly "update" one slot while
        % actually installing another (Portage would call that a new-slot install).
        candidate:selected_cn_slot_key_(SlotMeta, SlotChosen),
        query:search([name(N),category(C),installed(true)],
                     pkg://InstalledEntry2),
        ( query:search(slot(SlotInstalled0), pkg://InstalledEntry2)
          -> candidate:canon_slot(SlotInstalled0, SlotInstalled)
          ;  SlotInstalled = SlotChosen
        ),
        SlotInstalled == SlotChosen,
        !,
        ( % Standard transactional version change in same slot:
          % candidate differs from installed (upgrade or downgrade).
          InstalledEntry2 \== Candidate,
          query:search(version(OldVer), pkg://InstalledEntry2),
          query:search(version(CandVer0), FoundRepo://Candidate),
          OldVer \== CandVer0 ->
            feature_unification:unify([replaces(pkg://InstalledEntry2)], NewerContext, UpdateCtx),
            ( eapi:version_compare(<, CandVer0, OldVer)
            -> DepUpdateAction = downgrade
            ;  DepUpdateAction = update
            )
        ; % Incoming bracketed USE constraints require a rebuild of the installed instance.
          ( current_predicate(config:avoid_reinstall/1),
            config:avoid_reinstall(true) ->
              fail
          ; C \== 'virtual',
            \+ use:installed_entry_satisfies_build_with_use(pkg://InstalledEntry2, NewerContext)
          ) ->
            feature_unification:unify([replaces(pkg://InstalledEntry2),rebuild_reason(build_with_use)], NewerContext, UpdateCtx),
            DepUpdateAction = update
        ; % --newuse: force a transactional rebuild even if version is the same,
          % when USE/IUSE differs.
          preference:flag(newuse),
          use:newuse_mismatch(pkg://InstalledEntry2, FoundRepo://Candidate) ->
            feature_unification:unify([replaces(pkg://InstalledEntry2),rebuild_reason(newuse)], NewerContext, UpdateCtx),
            DepUpdateAction = update
        )
      ->
        ActionGoal = FoundRepo://Candidate:DepUpdateAction?{UpdateCtx}
      ; DepAction = Action,
        ActionGoal = FoundRepo://Candidate:DepAction?{NewerContext}
      ),
      % IMPORTANT for performance + correctness:
      % Record the concrete choice as a selection constraint *before* proving
      % ActionGoal, so the blocker guard can prune blocked candidates early
      % and backtrack within `query:search/2` enumeration (instead of exploring
      % deep proof paths for an invalid choice).
      ( ActionGoal = _://_:ActSel?{_} -> true
      ; ActionGoal = _://_:ActSel     -> true
      ; ActSel = Action
      ),
      query:search(version(CandVer), FoundRepo://Candidate),
      Selected = constraint(selected_cn(C,N):{ordset([selected(FoundRepo,Candidate,ActSel,CandVer,SlotMeta)])}),
      candidate:selected_cn_allow_multislot_constraints(C, N, SlotReq, PackageDeps1, AllowMultiSlotCons),
      candidate:cn_domain_constraints(Action, C, N, PackageDeps1, Context, DomainCons0, _DomainReasonTags),
      candidate:domain_constraints_for_any_different_slot(SlotReq, DomainCons0, DomainCons),
      append(Constraints, [ActionGoal], ConstraintsTail),
      append(AllowMultiSlotCons, [Selected|ConstraintsTail], Suffix),
      append(DomainCons, Suffix, Conditions)
    ; % In --deep mode we *prefer* upgrades, but we should not create domain
      % assumptions when the dependency is already installed in the vdb (`pkg`)
      % and satisfies constraints. Instead, fall back to "keep installed".
      ( preference:flag(deep),
        candidate:merge_slot_restriction(Action, C, N, PackageDeps, SlotReq2),
        query:search([name(N),category(C),installed(true)],
                     pkg://InstalledEntryFallback),
        candidate:query_search_slot_constraint(SlotReq2, pkg://InstalledEntryFallback, _),
        !,
        candidate:installed_entry_satisfies_package_deps(Action, C, N, PackageDeps, pkg://InstalledEntryFallback)
      ->
        Conditions = []
      ; % Before reprove, check if the parent should be narrowed — the parent
        % introduced a dep that made (C,N) unsatisfiable (wrong-level fix).
        % Skip for fetchonly: transitive dep failures (e.g. USE-flag mismatches)
        % should not narrow the parent — fetchonly only needs to download sources.
        Action \== fetchonly,
        candidate:maybe_learn_parent_narrowing(C, N, PackageDeps1, Context),
        fail
      ; Action \== fetchonly,
        candidate:maybe_request_grouped_dep_reprove(Action, C, N, PackageDeps1, Context),
        fail
      ; explanation:assumption_reason_for_grouped_dep(Action, C, N, PackageDeps, Context, Reason),
        version_domain:domain_reason_terms(Action, C, N, PackageDeps1, Context, DomainReasonTags),
        candidate:add_domain_reason_context(C, N, DomainReasonTags, Context, Ctx2),
        feature_unification:unify([assumption_reason(Reason)], Ctx2, Ctx3),
        Conditions = [assumed(grouped_package_dependency(C,N,PackageDeps1):Action?{Ctx3})]
      )
    )
  ).



% -----------------------------------------------------------------------------
%  Depclean traversal rules
% -----------------------------------------------------------------------------
%
% These are used by depclean:run/1 to compute a "kept" closure over *installed*
% packages only, using repository metadata for dependency structure.

rule(Repository://Ebuild:depclean?{Context}, Conditions) :-
  % Use current preference/profile to evaluate USE conditionals.
  ( query:search(model(Model,required_use(_),build_with_use(_)), Repository://Ebuild),
    % Compute runtime dependency model in config phase (no candidate choices here).
    query:memoized_search(model(dependency(MergedDeps0,run)):config?{Model}, Repository://Ebuild),
    dependency:add_self_to_dep_contexts(Repository://Ebuild, MergedDeps0, MergedDeps),
    % Rewrite all dependency literals to the depclean action.
    rules:depclean_rewrite_deps(MergedDeps, Context, Conditions)
  -> true
  ; Conditions = []
  ).


% Depclean: grouped package dependency – follow only installed packages.
rule(grouped_package_dependency(no,C,N,PackageDeps):depclean?{_Context}, Conditions) :-
  !,
  candidate:merge_slot_restriction(run, C, N, PackageDeps, SlotReq),
  ( query:search([name(N),category(C),installed(true)], pkg://InstalledEntry),
    candidate:query_search_slot_constraint(SlotReq, pkg://InstalledEntry, _),
    candidate:installed_entry_satisfies_package_deps(run, C, N, PackageDeps, pkg://InstalledEntry),
    % Find same-version repo entry (exclude pkg).
    query:search(version(V), pkg://InstalledEntry),
    preference:accept_keywords(K),
    query:search([select(repository,notequal,pkg),category(C),name(N),keywords(K),version(V)],
                 Repo//InstalledEntry)
  ->
    Conditions = [Repo//InstalledEntry:depclean?{[]}]
  ; Conditions = []
  ).

% Depclean: ignore blockers (they do not decide whether something is "needed").
rule(grouped_package_dependency(_Strength,_C,_N,_PackageDeps):depclean?{_Context}, []) :-
  !.



% -----------------------------------------------------------------------------
%  Rule: Positive use conditional dependencies
% -----------------------------------------------------------------------------
% The dependencies in a positive use conditional group need to be satisfied when
% the use flag is positive through required use constraint, preference or ebuild
% default

% 1. The USE is enabled in the context (dependency induced, or required_use)

rule(use_conditional_group(positive,Use,_R://_E,Deps):Action?{Context},Conditions) :-
  use:ctx_assumed(Context, Use),
  !,
  findall(D:Action?{Context},member(D,Deps),Conditions0),
  sort(Conditions0, Conditions).

% 1b. The USE is enabled globally (profile/env), but it is *not* an IUSE flag of
% this ebuild (e.g. kernel_linux, elibc_glibc, userland_GNU). Gentoo allows such
% conditionals; they are profile-driven, not package-driven.
rule(use_conditional_group(positive,Use,R://E,Deps):Action?{Context},Conditions) :-
  \+ Use =.. [minus,_],
  preference:use(Use),
  \+ ( query:search(iuse(Value), R://E),
       eapi:strip_use_default(Value, Use) ),
  !,
  findall(D:Action?{Context}, member(D,Deps), Conditions0),
  sort(Conditions0, Conditions).

% 2. The USE is explicitely enabled, either by preference or ebuild -> process deps

rule(use_conditional_group(positive,Use,R://E,Deps):Action?{Context},Conditions) :-
  % Fast check: avoid scanning all IUSE entries (clang/llvm has huge IUSE lists).
  use:effective_use_for_entry(R://E, Use, positive),
  !,
  findall(D:Action?{Context}, member(D, Deps), Result0),
  sort(Result0, Conditions).

% 3. The USE is not enabled -> no deps

rule(use_conditional_group(positive,_Use,_R://_E,_):_?{_},[]) :-
  !.


% -----------------------------------------------------------------------------
%  Rule: Negative use conditional dependencies
% -----------------------------------------------------------------------------
% The dependencies in a negative use conditional group need to be satisfied when
% the use flag is not positive through required use constraint, preference or
% ebuild default

% 1. The USE is disabled in the context (dependency induced, or required_use)

rule(use_conditional_group(negative,Use,_R://_E,Deps):Action?{Context},Conditions) :-
  % Context propagation uses per-package USE state under build_with_use.
  use:ctx_assumed_minus(Context, Use),
  !,
  findall(D:Action?{Context},member(D,Deps),Conditions0),
  sort(Conditions0, Conditions).

% 1b. Explicitly disabled globally (profile/env), but not an IUSE flag.
rule(use_conditional_group(negative,Use,R://E,Deps):Action?{Context},Conditions) :-
  preference:use(minus(Use)),
  \+ ( query:search(iuse(Value), R://E),
       eapi:strip_use_default(Value, Use) ),
  !,
  findall(D:Action?{Context}, member(D,Deps), Conditions0),
  sort(Conditions0, Conditions).

% 1c. Default-off globally (not set), but not an IUSE flag.
rule(use_conditional_group(negative,Use,R://E,Deps):Action?{Context},Conditions) :-
  \+ preference:use(Use),
  \+ preference:use(minus(Use)),
  \+ ( query:search(iuse(Value), R://E),
       eapi:strip_use_default(Value, Use) ),
  !,
  findall(D:Action?{Context}, member(D,Deps), Conditions0),
  sort(Conditions0, Conditions).

% 2. The USE is explicitely enabled, either by preference or ebuild -> process deps

rule(use_conditional_group(negative,Use,R://E,Deps):Action?{Context},Conditions) :-
  % Fast check: avoid scanning all IUSE entries (clang/llvm has huge IUSE lists).
  use:effective_use_for_entry(R://E, Use, negative),
  !,
  findall(D:Action?{Context}, member(D, Deps), Result0),
  sort(Result0, Conditions).

% 3. The USE is not enabled -> no deps

rule(use_conditional_group(negative,_Use,_R://_E,_):_?{_},[]) :-
  !.


% -----------------------------------------------------------------------------
%  Rule: Contextless use conditionals
% -----------------------------------------------------------------------------
% Contextless use conditionals are found in for example required_use constraints.

% In REQUIRED_USE evaluation, interpret conditionals against the current ebuild's
% *effective USE* (IUSE defaults + profile/env/package.use), not just global USE.
rule(use_conditional_group(positive,Use,Self,_Deps),[]) :-
  nb_current(query_required_use_self, Self),
  \+ Use =.. [minus,_],
  \+ use:effective_use_in_context([], Use, positive),
  !.
rule(use_conditional_group(positive,Use,Self,Deps),Conditions) :-
  nb_current(query_required_use_self, Self),
  \+ Use =.. [minus,_],
  use:effective_use_in_context([], Use, positive),
  !,
  findall(D, member(D,Deps), Conditions0),
  sort(Conditions0, Conditions).

rule(use_conditional_group(positive,Use,_://_,Deps),Conditions) :-
  preference:use(Use),!,
  findall(D,member(D,Deps),Conditions0),
  sort(Conditions0, Conditions).

rule(use_conditional_group(positive,_,_://_,_),[]) :- !.

rule(use_conditional_group(negative,Use,Self,_Deps),[]) :-
  nb_current(query_required_use_self, Self),
  \+ Use =.. [minus,_],
  \+ use:effective_use_in_context([], Use, negative),
  !.
rule(use_conditional_group(negative,Use,Self,Deps),Conditions) :-
  nb_current(query_required_use_self, Self),
  \+ Use =.. [minus,_],
  use:effective_use_in_context([], Use, negative),
  !,
  findall(D, member(D,Deps), Conditions0),
  sort(Conditions0, Conditions).

rule(use_conditional_group(negative,Use,_://_,Deps),Conditions) :-
  preference:use(minus(Use)),!,
  findall(D,member(D,Deps),Conditions0),
  sort(Conditions0, Conditions).

rule(use_conditional_group(negative,_,_://_,_),[]) :- !.


% -----------------------------------------------------------------------------
%  Rule: Exactly one of group
% -----------------------------------------------------------------------------
% Exactly one of the dependencies in an exactly-one-of-group should be satisfied

% REQUIRED_USE evaluation: check, don't search.
rule(exactly_one_of_group(Deps),[]) :-
  nb_current(query_required_use_self, _Self),
  findall(1, (member(D, Deps), use:required_use_term_satisfied(D)), Ones),
  length(Ones, 1),
  !.
rule(exactly_one_of_group(Deps),[assumed(conflict(required_use,exactly_one_of_group(Deps)))]) :-
  nb_current(query_required_use_self, _Self),
  !.

rule(exactly_one_of_group(Deps):Action?{Context},[D:Action?{Context}|NafDeps]) :-
  candidate:prioritize_deps(Deps, Context, SortedDeps),
  member(D0, SortedDeps),
  rules:group_choice_dep(D0, D),
  findall(naf(N),(member(N,Deps), \+(D = N)),NafDeps).

rule(exactly_one_of_group(Deps),[D|NafDeps]) :-
  candidate:prioritize_deps(Deps, SortedDeps),
  member(D, SortedDeps),
  findall(naf(N),(member(N,Deps), \+(D = N)),NafDeps).


% -----------------------------------------------------------------------------
%  Rule: At most one of group
% -----------------------------------------------------------------------------
% At most one of the dependencies in an at-most-one-of-group should be satisfied

% REQUIRED_USE evaluation: check, don't search.
rule(at_most_one_of_group(Deps),[]) :-
  nb_current(query_required_use_self, _Self),
  findall(1, (member(D, Deps), use:required_use_term_satisfied(D)), Ones),
  length(Ones, N),
  N =< 1,
  !.
rule(at_most_one_of_group(Deps),[assumed(conflict(required_use,at_most_one_of_group(Deps)))]) :-
  nb_current(query_required_use_self, _Self),
  !.

rule(at_most_one_of_group(Deps):Action?{Context},[D:Action?{Context}|NafDeps]) :-
  candidate:prioritize_deps(Deps, Context, SortedDeps),
  member(D0, SortedDeps),
  rules:group_choice_dep(D0, D),
  findall(naf(N),(member(N,Deps), \+(D = N)),NafDeps).

% Allow choosing none (all negated) — Portage REQUIRED_USE '?? ( ... )' does NOT
% require any of the flags to be enabled. Put this *after* the choice clause so
% we first try to satisfy already-enabled / preferred flags before negating all.
rule(at_most_one_of_group(Deps):_Action?{_Context}, NafDeps) :-
  findall(naf(N),(member(N,Deps)),NafDeps).

% Contextless variant: allow choosing none.
rule(at_most_one_of_group(Deps),[D|NafDeps]) :-
  candidate:prioritize_deps(Deps, SortedDeps),
  member(D, SortedDeps),
  findall(naf(N),(member(N,Deps), \+(D = N)),NafDeps).

% Contextless variant: allow choosing none (after attempting a choice).
rule(at_most_one_of_group(Deps), NafDeps) :-
  findall(naf(N),(member(N,Deps)),NafDeps).


% -----------------------------------------------------------------------------
%  Rule: Any of group
% -----------------------------------------------------------------------------
% One dependency of an any_of_group should be satisfied

% REQUIRED_USE evaluation: check, don't search.
rule(any_of_group(Deps),[]) :-
  nb_current(query_required_use_self, _Self),
  member(D, Deps),
  use:required_use_term_satisfied(D),
  !.
rule(any_of_group(Deps),[assumed(conflict(required_use,any_of_group(Deps)))]) :-
  nb_current(query_required_use_self, _Self),
  !.


% During model construction (`config` phase), we must *prove* the chosen literal
% so it becomes part of the memoized model. Calling `rule/2` directly (as in the
% runtime clause below) does not record the chosen package_dependency/8 in the
% model, which makes || ( ... ) disappear from dependency models.
rule(any_of_group(Deps):config?{Context}, [D:config?{Context}]) :-
  candidate:prioritize_deps_keep_all(Deps, Context, SortedDeps),
  member(D0, SortedDeps),
  rules:any_of_config_dep_ok(Context, D0),
  % In config phase we must prove the *package_dependency/8* term so it is
  % recorded in the model (AvlModel) and later extracted by query:model/2.
  D = D0,
  !.

rule(any_of_group(Deps):Action?{Context}, Conditions) :-
  candidate:prioritize_deps_keep_all(Deps, Context, SortedDeps),
  member(D0, SortedDeps),
  rules:group_choice_dep(D0, D),
  rule(D:Action?{Context}, Conditions0),
  % IMPORTANT (Portage-like || semantics):
  % If a choice "succeeds" only by degrading into a domain assumption, treat it
  % as an unsatisfied option and try the next alternative.
  %
  % Example: || ( sys-devel/gcc[objc] llvm-core/clang )
  % If gcc[objc] cannot be satisfied under the effective USE configuration, we
  % must fall back to clang rather than assuming gcc.
  ( rules:any_of_reject_assumed_choice(D, Conditions0) ->
      fail
  ; Conditions = Conditions0
  ),
  !.

rule(any_of_group(Deps), Conditions) :-
  candidate:prioritize_deps_keep_all(Deps, [], SortedDeps),
  member(D, SortedDeps),
  rule(D, Conditions),
  !.



% -----------------------------------------------------------------------------
%  Rule: All of group
% -----------------------------------------------------------------------------
% All dependencies in an all_of_group should be satisfied

rule(all_of_group(Deps):Action?{Context},Result) :-
  findall(D:Action?{Context},member(D,Deps),Result),!.

rule(all_of_group(Deps),Result) :-
  findall(D,member(D,Deps),Result),!.


% -----------------------------------------------------------------------------
%  Rule: Uri
% -----------------------------------------------------------------------------
% It is possible to put uri's in the proof, and verify at proof time whether
% downloads exists, are valid, etc. This makes the proofs unnecessarily large.
% In practice it is better to verify downloadability of a uri at proof execution
% time.

rule(uri(_,_,_):_,[]) :- !.
rule(uri(_):_,[]) :- !.


% -----------------------------------------------------------------------------
%  Rule: Required use
% -----------------------------------------------------------------------------

% Context-aware REQUIRED_USE evaluation:
% When the "current ebuild" is available via self(...) in the context (passed
% from query:model(required_use(...))), treat requirements that are already
% satisfied by effective USE (IUSE defaults + profile/env/package.use) as
% non-assumptions. This prevents any_of_group/^^ groups from arbitrarily
% enabling the first alternative.
rule(required(Use):_?{Context},[]) :-
  \+Use =.. [minus,_],
  use:effective_use_in_context(Context, Use, positive),
  !.
rule(required(minus(Use)):_?{Context},[]) :-
  \+Use =.. [minus,_],
  use:effective_use_in_context(Context, Use, negative),
  !.

rule(required(minus(Use)),[minus(Use)]) :-
  \+Use =.. [minus,_],
  preference:use(minus(Use)),!.

rule(required(Use),[Use]) :-
  \+Use =.. [minus,_],
  preference:use(Use),!.

rule(required(Use),[assumed(conflict(required,Use))]) :-
  \+Use =.. [minus,_],
  preference:use(minus(Use)),!.

rule(required(minus(Use)),[assumed(conflict(required,minus(Use)))]) :-
  \+Use =.. [minus,_],
  preference:use(Use),!.

rule(required(minus(Use)),[assumed(minus(Use))]) :-
  \+Use =.. [minus,_],
  \+preference:use(Use),
  \+preference:use(minus(Use)),!.

rule(required(Use),[assumed(Use)]) :-
  \+Use =.. [minus,_],
  \+preference:use(Use),
  \+preference:use(minus(Use)),!.


% -----------------------------------------------------------------------------
%  Rule: Blocking use
% -----------------------------------------------------------------------------

rule(blocking(minus(Use)),[Use]) :-
  \+Use =.. [minus,_],
  preference:use(Use),!.

rule(blocking(Use),[minus(Use)]) :-
  \+Use =.. [minus,_],
  preference:use(minus(Use)),!.

rule(blocking(Use),[assumed(conflict(blocking,Use))]) :-
  \+Use =.. [minus,_],
  preference:use(Use),!.

rule(blocking(minus(Use)),[assumed(conflict(blocking,minus(Use)))]) :- % test needed
  \+Use =.. [minus,_],
  preference:use(minus(Use)),!.

rule(blocking(minus(Use)),[assumed(minus(Use)),naf(required(Use))]) :- % this doesnet make sense I think)
  \+Use =.. [minus,_],
  \+preference:use(Use),
  \+preference:use(minus(Use)),!.

rule(blocking(Use),[assumed(minus(Use)),naf(required(Use))]) :-
  \+Use =.. [minus,_],
  \+preference:use(Use),
  \+preference:use(minus(Use)),!.



% -----------------------------------------------------------------------------
%  Rules needed by prover
% -----------------------------------------------------------------------------

% Assumptions:

% Domain-level assumption: rules can emit `assumed(X)` in a body to represent an
% unprovable domain fact (e.g. missing dependency or conflict resolution).
% The prover will prove such literals via this rule, and store them in the proof
% as `rule(assumed(X))` (distinct from prover cycle-break keys `assumed(rule(X))`).
rule(assumed(_),[]) :- !.


% Negation as failure:

rule(naf(Statement),C) :-
  Statement =.. [required,Use],!,
  ( preference:use(Use) -> C = [conflict(Use,naf(required(Use)))] ; C = []).

rule(naf(Statement),C) :-
  Statement =.. [blocking,Use],!,
  ( preference:use(minus(Use)) -> C = [conflict(Use,naf(blocking(Use)))] ; C = [] ).

% Conflicts:

rule(conflict(A,B),[assumed(conflict(A,B))]) :-
  rules:assume_conflicts,
  !.
rule(conflict(_,_),[]) :- !,
  fail.

% The default rule, prover takes care of negation

rule(naf(_),[]) :- !.

% Atoms

rule(Literal,[]) :-
  atom(Literal),!.

% =============================================================================
%  Debugging helpers
% =============================================================================

% -----------------------------------------------------------------------------
%  profile_run_entry/3: Time major sub-steps of the :run rule
% -----------------------------------------------------------------------------
%
% This is meant for answering: "where do those 300s go?" on a single package.
% It times the major sub-steps of the `:run` rule without needing full tracing.
%
% Usage example:
%   ?- rules:profile_run_entry(portage://'dev-python/qtpy-2.4.3-r1', [], Report),
%      writeln(Report).
%
rules:profile_run_entry(RepoEntry, Context, report(RepoEntry, Steps)) :-
  rules:step_time(mask_check,
                  ( query:search(masked(true), RepoEntry) -> true ; true ),
                  S1),
  rules:step_time(required_use_model,
                  ( findall(Item,(member(build_with_use:Inner, Context), member(Item,Inner)), B),
                    ( memberchk(required_use:R, Context) -> true ; true ),
                    query:search(model(_Model,required_use(R),build_with_use(B)), RepoEntry)
                  ),
                  S2),
  rules:step_time(dep_model_run_config,
                  ( query:memoized_search(model(dependency(_MergedDeps0,run)):config?{[]}, RepoEntry) ),
                  S3),
  Steps = [S1,S2,S3].

rules:step_time(Label, Goal, step(Label, ms(TimeMs), inferences(Inf), result(Result))) :-
  statistics(walltime, [T0,_]),
  statistics(inferences, I0),
  ( catch(call_with_time_limit(10, (Goal -> Result = ok ; Result = fail)),
          time_limit_exceeded,
          Result = timeout)
  ),
  statistics(walltime, [T1,_]),
  statistics(inferences, I1),
  TimeMs is T1 - T0,
  Inf is I1 - I0.



% -----------------------------------------------------------------------------
%  Constraint unification hook (domain hook called by prover)
% -----------------------------------------------------------------------------
%
% Called by the prover before generic constraint merging for domain-specific
% merge semantics.  If it succeeds, the prover uses the resulting constraints.

%! rules:constraint_unify_hook(+Key, +Value, +Constraints, -NewConstraints)
%
% Domain-specific constraint merge for `cn_domain(C,N)` keys: normalises
% the incoming version domain and intersects it with any existing domain
% via `version_domain:domain_meet/3`.

rules:constraint_unify_hook(cn_domain(C,N), DomainDelta0, Constraints, NewConstraints) :-
  !,
  version_domain:domain_normalize(DomainDelta0, DomainDelta),
  ( get_assoc(cn_domain(C,N), Constraints, CurrentDomain, Constraints1, CurrentDomain) ->
      version_domain:domain_meet(CurrentDomain, DomainDelta, MergedDomain),
      put_assoc(cn_domain(C,N), Constraints1, MergedDomain, NewConstraints)
  ; put_assoc(cn_domain(C,N), Constraints, DomainDelta, NewConstraints)
  ).


% -----------------------------------------------------------------------------
%  Constraint guard (domain hook called by prover)
% -----------------------------------------------------------------------------
%
% This predicate is called by the prover after merging any constraint literal.
% It must succeed for consistent constraint stores and fail to force backtracking
% when constraints become inconsistent.
%
% We use it for enforcing strong blockers against already-selected candidates,
% while keeping the prover itself domain-agnostic.
%
rules:constraint_guard(constraint(cn_domain(C,N):{Domain0}), Constraints) :-
  !,
  ( get_assoc(cn_domain(C,N), Constraints, Domain) -> true ; Domain = Domain0 ),
  ( version_domain:domain_inconsistent(Domain) ->
      % Multi-slot mode can intentionally accumulate disjoint slot domains
      % (e.g. ruby:3.2 and ruby:3.3). In that case the merged intersection is
      % globally inconsistent by construction, but each slot-constrained edge is
      % still validated locally during candidate selection.
      get_assoc(selected_cn_allow_multislot(C,N), Constraints, _AllowMultiSlot)
  ; ( get_assoc(selected_cn(C,N), Constraints, ordset(Selected)) ->
      candidate:selected_cn_domain_compatible_or_reprove(C, N, Domain, Selected, Constraints)
  ; true
    )
  ).
rules:constraint_guard(constraint(blocked_cn(C,N):{ordset(Specs)}), Constraints) :-
  !,
  ( get_assoc(selected_cn(C,N), Constraints, ordset(Selected)) ->
      candidate:selected_cn_not_blocked_or_reprove(C, N, Specs, Selected, Constraints)
  ; true
  ).
rules:constraint_guard(constraint(blocked_cn_source(C,N):{ordset(Sources)}), _Constraints) :-
  !,
  candidate:record_blocked_cn_source_snapshot(C, N, Sources).
rules:constraint_guard(constraint(selected_cn_allow_multislot(_C,_N):{_}), _Constraints) :-
  !.
rules:constraint_guard(constraint(selected_cn(C,N):{ordset(_SelectedNew)}), Constraints) :-
  !,
  % Enforce CN-consistency:
  % - default: one concrete entry per (C,N),
  % - opt-in: allow one concrete entry per SLOT when multislot was explicitly
  %   requested (slot-qualified deps or split grouped deps).
  get_assoc(selected_cn(C,N), Constraints, ordset(SelectedMerged)),
  candidate:record_selected_cn_snapshot(C, N, SelectedMerged),
  ( get_assoc(cn_domain(C,N), Constraints, Domain) ->
      candidate:selected_cn_domain_compatible_or_reprove(C, N, Domain, SelectedMerged, Constraints)
  ; true
  ),
  candidate:selected_cn_unique_or_reprove(C, N, SelectedMerged, Constraints),
  ( get_assoc(blocked_cn(C,N), Constraints, ordset(Specs)) ->
      candidate:selected_cn_not_blocked_or_reprove(C, N, Specs, SelectedMerged, Constraints)
  ; true
  ).
rules:constraint_guard(_Other, _Constraints).
% -----------------------------------------------------------------------------
%  Prover hook: domain-driven goal enqueueing (single-pass extensions)
% -----------------------------------------------------------------------------
%
% The prover is kept domain-agnostic. It may call this hook after proving a
% literal to request additional goals to enqueue in the same prover run.
%
% Hook contract (called by prover):
%   rules:proof_obligation(+Literal, +Model, -HookKey, -ExtraLits)
%
% This implementation provides Portage-like PDEPEND behavior:
% - PDEPEND deps are included in the transaction (proved in the same run),
% - but are NOT prerequisites of the parent merge action (anchored via after_only/1).
%
% IMPORTANT:
% - Must be monotonic and backtracking-safe (no global side effects).
% - Must not depend on Proof structure; HookKey is an opaque term.

% Fast path for the prover: compute HookKey only (no dependency-model work).
% This lets the prover skip calling proof_obligation/4 entirely when that key is
% already marked done in the evolving Proof.
%
% Extended fast path:
% `rules:proof_obligation_key/4` also tells the prover whether the full hook can
% produce any extra literals at all (`NeedsFullHook=false`).
rules:proof_obligation_key(Repo://Entry:Action?{_Ctx}, Model, HookKey) :-
  ( Action == install ; Action == update ; Action == downgrade ; Action == reinstall ),
  !,
  AnchorCore = (Repo://Entry:Action),
  % Fast path: most entries have no PDEPEND; avoid inspecting build_with_use.
  ( cache:entry_metadata(Repo, Entry, pdepend, _) ->
      ( get_assoc(AnchorCore, Model, AnchorCtx) -> true ; AnchorCtx = [] ),
      use:context_build_with_use_state(AnchorCtx, B),
      HookKey = pdepend(AnchorCore, B)
  ; HookKey = pdepend_none(AnchorCore)
  ).
rules:proof_obligation_key(Repo://Entry:Action, Model, HookKey) :-
  ( Action == install ; Action == update ; Action == downgrade ; Action == reinstall ),
  !,
  AnchorCore = (Repo://Entry:Action),
  ( cache:entry_metadata(Repo, Entry, pdepend, _) ->
      ( get_assoc(AnchorCore, Model, AnchorCtx) -> true ; AnchorCtx = [] ),
      use:context_build_with_use_state(AnchorCtx, B),
      HookKey = pdepend(AnchorCore, B)
  ; HookKey = pdepend_none(AnchorCore)
  ).

rules:proof_obligation_key(Repo://Entry:Action?{_Ctx}, Model, HookKey, NeedsFullHook) :-
  ( Action == install ; Action == update ; Action == downgrade ; Action == reinstall ),
  !,
  AnchorCore = (Repo://Entry:Action),
  % If this action will not result in a merge transaction, do not expand PDEPEND.
  % (E.g. `:install` can be satisfied by already-installed packages when not emptytree.)
  ( rules:proof_obligation_applicable(Repo://Entry:Action) ->
      ( cache:entry_metadata(Repo, Entry, pdepend, _) ->
          NeedsFullHook = true,
          ( get_assoc(AnchorCore, Model, AnchorCtx) -> true ; AnchorCtx = [] ),
          use:context_build_with_use_state(AnchorCtx, B),
          HookKey = pdepend(AnchorCore, B)
      ; NeedsFullHook = false,
        HookKey = pdepend_none(AnchorCore)
      )
  ; NeedsFullHook = false,
    HookKey = pdepend_none(AnchorCore)
  ).
rules:proof_obligation_key(Repo://Entry:Action, Model, HookKey, NeedsFullHook) :-
  ( Action == install ; Action == update ; Action == downgrade ; Action == reinstall ),
  !,
  AnchorCore = (Repo://Entry:Action),
  ( rules:proof_obligation_applicable(Repo://Entry:Action) ->
      ( cache:entry_metadata(Repo, Entry, pdepend, _) ->
          NeedsFullHook = true,
          ( get_assoc(AnchorCore, Model, AnchorCtx) -> true ; AnchorCtx = [] ),
          use:context_build_with_use_state(AnchorCtx, B),
          HookKey = pdepend(AnchorCore, B)
      ; NeedsFullHook = false,
        HookKey = pdepend_none(AnchorCore)
      )
  ; NeedsFullHook = false,
    HookKey = pdepend_none(AnchorCore)
  ).

% Decide whether an action literal represents an actual merge transaction.
% For install actions, already-installed entries (when not emptytree) are no-ops.
rules:proof_obligation_applicable(_Repo://_Entry:reinstall) :- !, true.
rules:proof_obligation_applicable(_Repo://_Entry:update) :- !, true.
rules:proof_obligation_applicable(_Repo://_Entry:downgrade) :- !, true.
rules:proof_obligation_applicable(Repo://Entry:install) :-
  ( preference:flag(emptytree) ->
      true
  ; \+ query:search(installed(true), Repo://Entry) ->
      true
  ; false
  ),
  !.

rules:proof_obligation(Repo://Entry:Action?{_Ctx}, Model, HookKey, ExtraLits) :-
  ( Action == install ; Action == update ; Action == downgrade ; Action == reinstall ),
  !,
  sampler:obligation_maybe_sample(
    ( AnchorCore = (Repo://Entry:Action),
      ( cache:entry_metadata(Repo, Entry, pdepend, _) ->
          flag(po_has_extra, HP0, HP0+1),
          % Determine current build_with_use state from the anchor's model context.
          ( get_assoc(AnchorCore, Model, AnchorCtx) -> true ; AnchorCtx = [] ),
          use:context_build_with_use_state(AnchorCtx, B),
          HookKey = pdepend(AnchorCore, B),
          ModelKey = [build_with_use:B],
          query:memoized_search(model(dependency(Pdeps0, pdepend)):config?{ModelKey}, Repo://Entry),
          dependency:add_self_to_dep_contexts(Repo://Entry, Pdeps0, Pdeps1),
          rules:drop_build_with_use_from_dep_contexts(Pdeps1, Pdeps2),
          rules:add_after_only_to_dep_contexts(AnchorCore, Pdeps2, ExtraLits)
      ; flag(po_no_extra, NP0, NP0+1),
        HookKey = pdepend_none(AnchorCore),
        ExtraLits = []
      )
    )
  ).
rules:proof_obligation(Repo://Entry:Action, Model, HookKey, ExtraLits) :-
  ( Action == install ; Action == update ; Action == downgrade ; Action == reinstall ),
  !,
  sampler:obligation_maybe_sample(
    ( AnchorCore = (Repo://Entry:Action),
      ( cache:entry_metadata(Repo, Entry, pdepend, _) ->
          flag(po_has_extra, HP0, HP0+1),
          ( get_assoc(AnchorCore, Model, AnchorCtx) -> true ; AnchorCtx = [] ),
          use:context_build_with_use_state(AnchorCtx, B),
          HookKey = pdepend(AnchorCore, B),
          ModelKey = [build_with_use:B],
          query:memoized_search(model(dependency(Pdeps0, pdepend)):config?{ModelKey}, Repo://Entry),
          dependency:add_self_to_dep_contexts(Repo://Entry, Pdeps0, Pdeps1),
          rules:drop_build_with_use_from_dep_contexts(Pdeps1, Pdeps2),
          rules:add_after_only_to_dep_contexts(AnchorCore, Pdeps2, ExtraLits)
      ; flag(po_no_extra, NP0, NP0+1),
        HookKey = pdepend_none(AnchorCore),
        ExtraLits = []
      )
    )
  ).


% -----------------------------------------------------------------------------
%  Context helpers: planning-only ordering markers
% -----------------------------------------------------------------------------
%
%  The planner uses `after/1` and `after_only/1` markers in dependency
%  contexts to express ordering constraints between actions.  The
%  predicates below thread, extract, and strip these markers.

%! rules:ctx_take_after(+Context0, -After, -Context)
%
% Extracts the first `after(Literal)` marker from Context0.
% Unifies After with `none` if no marker is present.

rules:ctx_take_after(Context0, After, Context) :-
  ( is_list(Context0),
    select(after(After1), Context0, Context1) ->
      After = After1,
      Context = Context1
  ; After = none,
    Context = Context0
  ),
  !.

%! rules:ctx_take_after_with_mode(+Context0, -After, -AfterForDeps, -Context)
%
% Like ctx_take_after/3 but distinguishes `after/1` (propagates to deps)
% from `after_only/1` (does not propagate -- AfterForDeps = none).

rules:ctx_take_after_with_mode(Context0, After, AfterForDeps, Context) :-
  ( is_list(Context0),
    select(after_only(After1), Context0, Ctx1) ->
      After = After1,
      AfterForDeps = none,
      ( select(after(_), Ctx1, Context) -> true ; Context = Ctx1 )
  ; is_list(Context0),
    select(after(After1), Context0, Ctx1) ->
      After = After1,
      AfterForDeps = After1,
      ( select(after_only(_), Ctx1, Context) -> true ; Context = Ctx1 )
  ; After = none,
    AfterForDeps = none,
    Context = Context0
  ),
  !.

%! rules:ctx_add_after_condition(+After, +AfterForDeps, +Conds0, -Conds)
%
% Prepends an ordering constraint to Conds0 based on the extracted markers.
% `after/1` becomes a real dependency; `after_only/1` becomes a
% `constraint(order_after(...))` that the planner uses for ordering only.

rules:ctx_add_after_condition(none, _AfterForDeps, Conditions, Conditions) :- !.
rules:ctx_add_after_condition(After, none, Conditions0, [constraint(order_after(After):{[]} )|Conditions0]) :-
  After \== none,
  !.
rules:ctx_add_after_condition(After, _AfterForDeps, Conditions0, [After|Conditions0]) :-
  !.

%! rules:ctx_strip_planning(+Context0, -Context)
%
% Removes planning-only markers (after/1, world_atom/1) from a context
% so they do not affect dependency-model memoization keys.

rules:ctx_strip_planning(Context0, Context) :-
  ( is_list(Context0) ->
      findall(X,
              ( member(X, Context0),
                \+ X = after(_),
                \+ X = world_atom(_)
              ),
              Context)
  ; Context = Context0
  ),
  !.

%! rules:add_after_to_dep_contexts(+After, +Deps0, -Deps)
%
% Injects an `after/1` marker into each dependency literal's context.

rules:add_after_to_dep_contexts(none, Deps, Deps) :- !.
rules:add_after_to_dep_contexts(After, Deps0, Deps) :-
  is_list(Deps0),
  !,
  findall(D,
          ( member(D0, Deps0),
            ( D0 = Term:Action?{Ctx0} ->
                rules:ctx_add_after(Ctx0, After, Ctx),
                D = Term:Action?{Ctx}
            ; D = D0
            )
          ),
          Deps).
rules:add_after_to_dep_contexts(_After, Deps, Deps).

rules:ctx_add_after(Ctx0, After, Ctx) :-
  ( is_list(Ctx0) ->
      ( select(after(_), Ctx0, Ctx1) -> true ; Ctx1 = Ctx0 ),
      Ctx = [after(After)|Ctx1]
  ; Ctx = [after(After)]
  ),
  !.

%! rules:add_after_only_to_dep_contexts(+After, +Deps0, -Deps)
%
% Injects an `after_only/1` marker into each dependency literal's context.
% Unlike after/1, after_only/1 does not propagate into the dependency's
% own closure (ordering applies only to the direct goal).

rules:add_after_only_to_dep_contexts(_After, [], []) :- !.
rules:add_after_only_to_dep_contexts(After, Deps0, Deps) :-
  is_list(Deps0),
  !,
  findall(D,
          ( member(D0, Deps0),
            ( D0 = Term:Action?{Ctx0} ->
                rules:ctx_add_after_only(Ctx0, After, Ctx),
                D = Term:Action?{Ctx}
            ; D = D0
            )
          ),
          Deps).
rules:add_after_only_to_dep_contexts(_After, Deps, Deps).

%! rules:drop_build_with_use_from_dep_contexts(+Deps0, -Deps)
%
% Strips `build_with_use` terms from each dependency context.
% Used during PDEPEND expansion where build_with_use serves only as a
% memoization key, not a semantic constraint on the targets.

rules:drop_build_with_use_from_dep_contexts([], []) :- !.
rules:drop_build_with_use_from_dep_contexts([D0|Rest0], [D|Rest]) :-
  !,
  rules:drop_build_with_use_from_dep_context(D0, D),
  rules:drop_build_with_use_from_dep_contexts(Rest0, Rest).
rules:drop_build_with_use_from_dep_contexts(Deps, Deps).

rules:drop_build_with_use_from_dep_context(Dep0:Act?{Ctx0}, Dep:Act?{Ctx}) :-
  !,
  Dep = Dep0,
  rules:ctx_drop_build_with_use(Ctx0, Ctx).
rules:drop_build_with_use_from_dep_context(Other, Other).

rules:ctx_add_after_only(Ctx0, After, Ctx) :-
  ( is_list(Ctx0) ->
      ( select(after(_), Ctx0, Ctx1) -> true ; Ctx1 = Ctx0 ),
      ( select(after_only(_), Ctx1, Ctx2) -> true ; Ctx2 = Ctx1 ),
      Ctx = [after_only(After)|Ctx2]
  ; Ctx = [after_only(After)]
  ),
  !.


% -----------------------------------------------------------------------------
%  Context helpers: drop diagnostic / per-package USE constraints
% -----------------------------------------------------------------------------

%! rules:ctx_drop_build_with_use(+Ctx0, -Ctx)
%
% Removes all `build_with_use:_` terms from a context.

rules:ctx_drop_build_with_use(Ctx0, Ctx) :-
  ( is_list(Ctx0) ->
      exclude(rules:ctx_is_build_with_use_term, Ctx0, Ctx)
  ; Ctx = Ctx0
  ),
  !.

rules:ctx_is_build_with_use_term(build_with_use:_) :- !.

%! rules:ctx_drop_assumption_reason(+Ctx0, -Ctx)
%
% Removes all `assumption_reason(_)` terms from a context.

rules:ctx_drop_assumption_reason(Ctx0, Ctx) :-
  ( is_list(Ctx0) ->
      exclude(rules:ctx_is_assumption_reason_term, Ctx0, Ctx)
  ; Ctx = Ctx0
  ),
  !.

rules:ctx_is_assumption_reason_term(assumption_reason(_)) :- !.

%! rules:ctx_drop_build_with_use_and_assumption_reason(+Ctx0, -Ctx)
%
% Removes both `build_with_use:_` and `assumption_reason(_)` from a context.
% Used for PDEPEND edges where neither should propagate.

rules:ctx_drop_build_with_use_and_assumption_reason(Ctx0, Ctx) :-
  ( is_list(Ctx0) ->
      exclude(rules:ctx_is_bwu_or_assumption_reason, Ctx0, Ctx)
  ; Ctx = Ctx0
  ),
  !.

rules:ctx_is_bwu_or_assumption_reason(build_with_use:_) :- !.
rules:ctx_is_bwu_or_assumption_reason(assumption_reason(_)) :- !.

% -----------------------------------------------------------------------------
%  Internal override: assume blockers
% -----------------------------------------------------------------------------
%
% Used for developer UX: when a plan cannot be proven due to blockers, we can
% re-run in a mode that turns blockers into domain assumptions, so the printer
% can show "this would be the plan if you verify/override these blockers".

%! rules:assume_blockers
%
% True when blocker constraints should be treated as domain assumptions.

rules:assume_blockers :-
  prover:assuming(blockers).

%! rules:with_assume_blockers(:Goal)
%
% Runs Goal in a scope where blockers are treated as domain assumptions.

rules:with_assume_blockers(Goal) :-
  prover:assuming(blockers, Goal).

% -----------------------------------------------------------------------------
%  Internal override: assume conflicts
% -----------------------------------------------------------------------------

%! rules:assume_conflicts
%
% True when USE/REQUIRED_USE conflicts should be treated as domain
% assumptions rather than hard failures.

rules:assume_conflicts :-
  prover:assuming(conflicts).

%! rules:with_assume_conflicts(:Goal)
%
% Runs Goal in a scope where conflicts are treated as domain assumptions.

rules:with_assume_conflicts(Goal) :-
  prover:assuming(conflicts, Goal).


%! rules:any_of_reject_assumed_choice(+Dep, +Conditions)
%
% True if the chosen any_of alternative resolved only via a domain
% assumption (i.e. the dependency is not concretely satisfiable).
% Forces backtracking to the next alternative.

rules:any_of_reject_assumed_choice(grouped_package_dependency(_Strength, C, N, _PackageDeps),
                                   [assumed(grouped_package_dependency(C, N, _Deps):_Act?{_Ctx})]) :-
  !.

% Config-phase guard: avoid locking in an unsatisfiable bracketed-USE option as the
% chosen member of a || group, because that discards the other alternatives from
% the memoized dependency model.
%
% We still keep this reasonably narrow for performance, but we must avoid
% locking in an any-of branch that has no concrete candidate at all
% (e.g. virtual/perl-* branches with stale ~perl-core versions).
%
% IMPORTANT:
% During config phase, any_of members can be composite terms (all_of_group,
% use_conditional_group, nested any_of_group). Treating those as automatically
% satisfiable will lock unsatisfiable branches into the memoized model and drop
% valid alternatives. We must recurse and validate leaves.
rules:any_of_config_dep_ok(Context, all_of_group(Deps)) :-
  !,
  rules:any_of_config_deps_all_ok(Context, Deps).
rules:any_of_config_dep_ok(Context, any_of_group(Deps)) :-
  !,
  rules:any_of_config_deps_any_ok(Context, Deps).
rules:any_of_config_dep_ok(Context, use_conditional_group(Pol, Use, RepoEntry, Deps)) :-
  !,
  % Reuse established USE-conditional activation semantics from rule/2. If this
  % branch is inactive, it must not satisfy an enclosing any_of_group.
  rule(use_conditional_group(Pol, Use, RepoEntry, Deps):config?{Context}, Conditions),
  Conditions \== [],
  rules:any_of_config_conditions_all_ok(Context, Conditions).

rules:any_of_config_dep_ok(Context, package_dependency(Phase, _Strength, C, N, O, V, SlotReq, U)) :-
  % Test USE-dep satisfiability against concrete candidates that match the
  % dependency's own version/slot constraints. Using a single arbitrary
  % representative entry can produce false negatives and make model
  % construction fail at the root `entry(...:run)` literal.
  findall(Repo://Id,
          ( candidate:accepted_keyword_candidate(Phase, C, N, SlotReq, _Ss, Context, Repo://Id),
            candidate:query_search_version_select(O, V, Repo://Id)
          ),
          Candidates0),
  sort(Candidates0, Candidates),
  Candidates \== [],
  ( U == []
  -> true
  ; member(Candidate, Candidates),
    use:candidate_satisfies_use_deps(Context, Candidate, U)
  ),
  !.
% If the USE-deps are not satisfiable, reject this option.
rules:any_of_config_dep_ok(_Context, package_dependency(_Phase, _Strength, _C, _N, _O, _V, _S, _U)) :-
  rules:assume_conflicts,
  !.
rules:any_of_config_dep_ok(_Context, package_dependency(_Phase, _Strength, _C, _N, _O, _V, _S, _U)) :-
  !,
  fail.
rules:any_of_config_dep_ok(_Context, _Other) :-
  true.

rules:any_of_config_deps_all_ok(_Context, []) :- !.
rules:any_of_config_deps_all_ok(Context, [Dep|Rest]) :-
  rules:any_of_config_dep_ok(Context, Dep),
  rules:any_of_config_deps_all_ok(Context, Rest).

rules:any_of_config_deps_any_ok(Context, Deps) :-
  member(Dep, Deps),
  rules:any_of_config_dep_ok(Context, Dep),
  !.

rules:any_of_config_conditions_all_ok(_Context, []) :- !.
rules:any_of_config_conditions_all_ok(Context, [Cond|Rest]) :-
  rules:any_of_config_condition_dep(Cond, Dep),
  rules:any_of_config_dep_ok(Context, Dep),
  rules:any_of_config_conditions_all_ok(Context, Rest).

rules:any_of_config_condition_dep(Dep:config?{_Ctx}, Dep) :- !.
rules:any_of_config_condition_dep(Dep, Dep).



%! rules:group_choice_dep(+Dep0, -Dep)
%
% Lifts a plain package_dependency/8 into a grouped_package_dependency/4
% wrapper so it can be resolved by the grouped dependency rule.

rules:group_choice_dep(package_dependency(Phase,Strength,C,N,O,V,S,U),
                       grouped_package_dependency(Strength,C,N,
                           [package_dependency(Phase,Strength,C,N,O,V,S,U)])) :- !.
rules:group_choice_dep(D, D).



%! rules:depclean_rewrite_deps(+Deps0, +ParentCtx, -Deps)
%
% Rewrites all dependency literals to the `:depclean` action for
% depclean closure traversal.

rules:depclean_rewrite_deps([], _ParentCtx, []) :- !.
rules:depclean_rewrite_deps([D0|Rest0], ParentCtx, [D|Rest]) :-
  rules:depclean_rewrite_dep(D0, ParentCtx, D),
  rules:depclean_rewrite_deps(Rest0, ParentCtx, Rest).

rules:depclean_rewrite_dep(Term:Action?{Ctx0}, _ParentCtx, Term:depclean?{Ctx0}) :-
  nonvar(Action),
  !.
rules:depclean_rewrite_dep(Term:Action, _ParentCtx, Term:depclean?{[]}) :-
  nonvar(Action),
  !.
rules:depclean_rewrite_dep(Term, _ParentCtx, Term:depclean?{[]}) :-
  !.