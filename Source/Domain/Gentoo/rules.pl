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
This file contains only rule/2 clauses (the "what"); all implementation
logic (the "how") lives in Rules/ submodules.

== Submodules ==

| Module        | Responsibility                                          |
|---------------|---------------------------------------------------------|
| candidate.pl  | Candidate selection, slot merging, CN-consistency,      |
|               | blocker matching, keyword helpers, any_of validation    |
| featureterm.pl| Proof-context list helpers (module: featureterm)        |
| dependency.pl | Self-entry injection, USE-requirement collection,       |
|               | slot/build-with-use propagation in ?{Context} lists     |
| heuristic.pl  | Prover hooks: constraint guard, cycle classification,   |
|               | proof obligations (PDEPEND), reprove state, debugging   |
| memo.pl       | Thread-local caching declarations, clear_caches/0       |
| target.pl     | Target resolution, update/downgrade transactions,       |
|               | depclean rewriting, --exclude / --rebuild-if-* helpers  |
| use.pl        | USE flag evaluation, conditionals, build_with_use,      |
|               | newuse, REQUIRED_USE, BWU cross-dep conflict detection  |

== Rule sections ==

  1. *Ebuild targets* -- target resolution, download, fetchonly,
     install, run, reinstall, uninstall, update, downgrade.
  2. *Dependency resolution* -- package_dependency/8 (weak/strong
     blockers), grouped_package_dependency/4, depclean traversal.
  3. *USE conditionals* -- use_conditional_group/4 (positive/negative).
  4. *Choice groups* -- exactly_one_of, at_most_one_of, any_of, all_of.
  5. *Required USE / blocking / prover primitives* -- naf, conflict, assumed.
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
  target:resolve_candidate(Q, Repository://Ebuild),
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
%
% For CN targets (no version), visible candidates are tried first so the
% prover prefers installable versions before resorting to relaxation.
% For CNV targets (explicit version), all candidates are tried in standard
% order since the user explicitly requested that version.
%
% --nodeps: resolve target without proving dependencies.
% --onlydeps: prove deps only, exclude the target from the plan.
% --exclude: skip atoms matching config:excluded_atom/1.

rule(target(Q, Arg):run?{Context}, Conditions) :-
  !,
  target:resolve_candidate(Q, Repository://Ebuild),
  ( target:is_excluded(Repository://Ebuild)
  -> Conditions = []
  ; preference:flag(onlydeps)
  -> Conditions = [Repository://Ebuild:run?{[onlydeps_target|Context]}]
  ; Conditions0 = [Repository://Ebuild:run?{Context}],
    ( preference:flag(oneshot) ->
        Conditions = Conditions0
    ; Conditions = [Repository://Ebuild:run?{Context},
                    world_action(register, Arg):world?{[after(Repository://Ebuild:run)]}]
    )
  ).


% -----------------------------------------------------------------------------
%  Rule: Download target
% -----------------------------------------------------------------------------
% Any ebuild can be downloaded.

rule(Repository://Ebuild:download?{Context},Conditions) :-
  !,
  featureterm:ctx_take_after(Context, After, _CtxNoAfter),
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
  featureterm:ctx_take_after(Context, After, _CtxNoAfter),
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
  ( query:search(masked(true),   Repository://Ebuild),
    \+ prover:assuming(unmask) ->
      fail
  ; \+ candidate:entry_has_accepted_keyword(Repository://Ebuild),
    \+ prover:assuming(keyword_acceptance) ->
      fail
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
  ( query:search(masked(true), Repository://Ebuild),
    \+ prover:assuming(unmask) ->
      fail
  ; \+ candidate:entry_has_accepted_keyword(Repository://Ebuild),
    \+ prover:assuming(keyword_acceptance) ->
      fail
  ; query:search(installed(true),Repository://Ebuild),
    \+ preference:flag(emptytree) ->
      Conditions = []
  ; target:resolve_install(Repository://Ebuild, Context, Conditions)
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
% Accepted in the ?{Context} list:
%
% - build_with_use(B)

rule(Repository://Ebuild:run?{Context},Conditions) :-
  !,
  ( query:search(masked(true), Repository://Ebuild),
    \+ prover:assuming(unmask) ->
      fail
  ; \+ candidate:entry_has_accepted_keyword(Repository://Ebuild),
    \+ prover:assuming(keyword_acceptance) ->
      fail
  ; query:search(installed(true),Repository://Ebuild), \+ preference:flag(emptytree) ->
    ( config:avoid_reinstall(true) ->
        Conditions = []
    ; featureterm:ctx_take_after_with_mode(Context, After0, AfterForDeps0, Context10),
      Cond0 = [Repository://Ebuild:reinstall?{Context10}],
      featureterm:ctx_add_after_condition(After0, AfterForDeps0, Cond0, Conditions)
    )
  ; target:resolve_run(Repository://Ebuild, Context, Conditions)
  ).


% -----------------------------------------------------------------------------
%  Rule: Reinstall target
% -----------------------------------------------------------------------------
% An ebuild can be reinstalled, when:
%
% - it is reportedly installed, and the emptytree flag is not set.

rule(Repository://Ebuild:reinstall?{_},[]) :-
  \+(preference:flag(emptytree)),
  query:search(installed(true),Repository://Ebuild),!. % todo: retrieve installed entry's ?{Context} list


% -----------------------------------------------------------------------------
%  Rule: Uninstall target
% -----------------------------------------------------------------------------
% An ebuild can be uninstalled, when:
%
% - it is reportedly installed, and we are not proving emptytree

rule(Repository://Ebuild:uninstall?{_},[]) :-
  \+(preference:flag(emptytree)),
  query:search(installed(true),Repository://Ebuild),!.


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
  ( candidate:assume_blockers ->
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
                 _://Candidate),
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
  ( candidate:assume_blockers ->
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
  candidate:resolve_grouped_dep(Action, C, N, PackageDeps1, PackageDeps, Context, Conditions).



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
    target:depclean_rewrite_deps(MergedDeps, Context, Conditions)
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
                 Repo://InstalledEntry)
  ->
    Conditions = [Repo://InstalledEntry:depclean?{[]}]
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
  preference:global_use(Use),
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
  preference:global_use(minus(Use)),
  \+ ( query:search(iuse(Value), R://E),
       eapi:strip_use_default(Value, Use) ),
  !,
  findall(D:Action?{Context}, member(D,Deps), Conditions0),
  sort(Conditions0, Conditions).

% 1c. Default-off globally (not set), but not an IUSE flag.
rule(use_conditional_group(negative,Use,R://E,Deps):Action?{Context},Conditions) :-
  \+ preference:global_use(Use),
  \+ preference:global_use(minus(Use)),
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
  preference:global_use(Use),!,
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
  preference:global_use(minus(Use)),!,
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

% Config phase: record chosen dep in model (same pattern as any_of_group).
rule(exactly_one_of_group(Deps):config?{Context}, [D:config?{Context}]) :-
  candidate:prioritize_deps_keep_all(Deps, Context, SortedDeps),
  member(D0, SortedDeps),
  candidate:any_of_config_dep_ok(Context, D0),
  D = D0,
  !.

% Runtime: select one, reject domain-assumption-only choices.
rule(exactly_one_of_group(Deps):Action?{Context}, Conditions) :-
  candidate:prioritize_deps_keep_all(Deps, Context, SortedDeps),
  member(D0, SortedDeps),
  candidate:group_choice_dep(D0, D),
  rule(D:Action?{Context}, Conditions0),
  ( candidate:any_of_reject_assumed_choice(D, Conditions0) ->
      fail
  ; Conditions = Conditions0
  ),
  !.

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

% Config phase: record chosen dep in model (same pattern as any_of_group).
rule(at_most_one_of_group(Deps):config?{Context}, [D:config?{Context}]) :-
  candidate:prioritize_deps_keep_all(Deps, Context, SortedDeps),
  member(D0, SortedDeps),
  candidate:any_of_config_dep_ok(Context, D0),
  D = D0,
  !.

% Config phase: choosing none is valid for ?? groups.
rule(at_most_one_of_group(_Deps):config?{_Context}, []) :- !.

% Runtime: select one, reject domain-assumption-only choices.
rule(at_most_one_of_group(Deps):Action?{Context}, Conditions) :-
  candidate:prioritize_deps_keep_all(Deps, Context, SortedDeps),
  member(D0, SortedDeps),
  candidate:group_choice_dep(D0, D),
  rule(D:Action?{Context}, Conditions0),
  ( candidate:any_of_reject_assumed_choice(D, Conditions0) ->
      fail
  ; Conditions = Conditions0
  ),
  !.

% Runtime: choosing none (all negated) is valid for ?? groups.
rule(at_most_one_of_group(Deps):_Action?{_Context}, NafDeps) :-
  findall(naf(N),(member(N,Deps)),NafDeps).

rule(at_most_one_of_group(Deps),[D|NafDeps]) :-
  candidate:prioritize_deps(Deps, SortedDeps),
  member(D, SortedDeps),
  findall(naf(N),(member(N,Deps), \+(D = N)),NafDeps).

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
  candidate:any_of_config_dep_ok(Context, D0),
  % In config phase we must prove the *package_dependency/8* term so it is
  % recorded in the model (AvlModel) and later extracted by query:model/2.
  D = D0,
  !.

rule(any_of_group(Deps):Action?{Context}, Conditions) :-
  candidate:prioritize_deps_keep_all(Deps, Context, SortedDeps),
  member(D0, SortedDeps),
  candidate:group_choice_dep(D0, D),
  rule(D:Action?{Context}, Conditions0),
  % IMPORTANT (Portage-like || semantics):
  % If a choice "succeeds" only by degrading into a domain assumption, treat it
  % as an unsatisfied option and try the next alternative.
  %
  % Example: || ( sys-devel/gcc[objc] llvm-core/clang )
  % If gcc[objc] cannot be satisfied under the effective USE configuration, we
  % must fall back to clang rather than assuming gcc.
  ( candidate:any_of_reject_assumed_choice(D, Conditions0) ->
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
  preference:global_use(minus(Use)),!.

rule(required(Use),[Use]) :-
  \+Use =.. [minus,_],
  preference:global_use(Use),!.

rule(required(Use),[assumed(conflict(required,Use))]) :-
  \+Use =.. [minus,_],
  preference:global_use(minus(Use)),!.

rule(required(minus(Use)),[assumed(conflict(required,minus(Use)))]) :-
  \+Use =.. [minus,_],
  preference:global_use(Use),!.

rule(required(minus(Use)),[assumed(minus(Use))]) :-
  \+Use =.. [minus,_],
  \+preference:global_use(Use),
  \+preference:global_use(minus(Use)),!.

rule(required(Use),[assumed(Use)]) :-
  \+Use =.. [minus,_],
  \+preference:global_use(Use),
  \+preference:global_use(minus(Use)),!.


% -----------------------------------------------------------------------------
%  Rule: Blocking use
% -----------------------------------------------------------------------------

rule(blocking(minus(Use)),[Use]) :-
  \+Use =.. [minus,_],
  preference:global_use(Use),!.

rule(blocking(Use),[minus(Use)]) :-
  \+Use =.. [minus,_],
  preference:global_use(minus(Use)),!.

rule(blocking(Use),[assumed(conflict(blocking,Use))]) :-
  \+Use =.. [minus,_],
  preference:global_use(Use),!.

rule(blocking(minus(Use)),[assumed(conflict(blocking,minus(Use)))]) :- % test needed
  \+Use =.. [minus,_],
  preference:global_use(minus(Use)),!.

rule(blocking(minus(Use)),[assumed(minus(Use)),naf(required(Use))]) :- % this doesnet make sense I think)
  \+Use =.. [minus,_],
  \+preference:global_use(Use),
  \+preference:global_use(minus(Use)),!.

rule(blocking(Use),[assumed(minus(Use)),naf(required(Use))]) :-
  \+Use =.. [minus,_],
  \+preference:global_use(Use),
  \+preference:global_use(minus(Use)),!.



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
  ( preference:global_use(Use) -> C = [conflict(Use,naf(required(Use)))] ; C = []).

rule(naf(Statement),C) :-
  Statement =.. [blocking,Use],!,
  ( preference:global_use(minus(Use)) -> C = [conflict(Use,naf(blocking(Use)))] ; C = [] ).

% Conflicts:

rule(conflict(A,B),[assumed(conflict(A,B))]) :-
  candidate:assume_conflicts,
  !.
rule(conflict(_,_),[]) :- !,
  fail.

% The default rule, prover takes care of negation

rule(naf(_),[]) :- !.

% Atoms

rule(Literal,[]) :-
  atom(Literal),!.


% NOTE: Constraint hooks, proof obligations, context helpers, BWU checks,
% blocker/conflict assumptions, any_of config plumbing, keyword helpers,
% depclean rewriting, CLI flag helpers, and debugging helpers have been
% extracted to their respective Rules/ submodules. See the module header
% for the submodule table.
