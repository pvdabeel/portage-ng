/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> RULES
This file contains domain-specific rules
*/

:- module(rules, [rule/2]).

:- use_module(library(ordsets)).

:- discontiguous rules:rule/2.


% =============================================================================
%  RULES declarations
% =============================================================================

% =============================================================================
%  Ruleset: Ebuild targets
% =============================================================================

% -----------------------------------------------------------------------------
%  Rule: Download target
% -----------------------------------------------------------------------------
% Any ebuild can be downloaded.

rule(Repository://Ebuild:download?{_},[]) :-
  !,
  query:search(ebuild(Ebuild),Repository://Ebuild).


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

rule(Repository://Ebuild:fetchonly?{Context},Conditions) :- % todo: to update in line with new :install and :run rules
  !,
  query:search(masked(true),   Repository://Ebuild) -> Conditions = [] ;
  query:search(installed(true),Repository://Ebuild), \+preference:flag(emptytree) -> Conditions = [] ;

  % 1. Get some metadata we need further down

  query:search([category(C),name(N),select(slot,constraint([]),S)], Repository://Ebuild),

  % 2. Compute required_use stable model

  (findall(Item,
          (member(build_with_use(InnerList), Context),
           member(Item,InnerList)),
          B)),

  (memberchk(required_use(R),Context) -> true ; true),

  query:search(model(Model,required_use(R),build_with_use(B)),Repository://Ebuild),

  % 3. Pass use model onto dependencies to calculate corresponding dependency  model,
  %    We pass using config action to avoid package_dependency from generating choices.
  %    The config action triggers use_conditional, any_of_group, exactly_one_of_group,
  %    all_of_group ... choice point generation

  % 4. Compute + memoize dependency model, already grouped by package Category & Name.

  query:memoized_search(model(dependency(MergedDeps0,fetchonly)):config?{Model},Repository://Ebuild),
  add_self_to_dep_contexts(Repository://Ebuild, MergedDeps0, MergedDeps),

  % 5. Pass on relevant package dependencies and constraints to prover

  ( memberchk(C,['virtual','acct-group','acct-user'])
    -> Conditions = [constraint(use(Repository://Ebuild):{R}),
                     constraint(slot(C,N,S):{Ebuild})
                     |MergedDeps]
    ;  Conditions = [constraint(use(Repository://Ebuild):{R}),
                     constraint(slot(C,N,S):{Ebuild}),
                     Repository://Ebuild:download?{R}
                     |MergedDeps] )
   ; Conditions = [assumed(Repository://Ebuild:install?{[issue_with_model(explanation)|Context]})].


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
  query:search(masked(true),   Repository://Ebuild) -> Conditions = [] ;
  query:search(installed(true),Repository://Ebuild), \+preference:flag(emptytree) -> Conditions = [] ; % todo check new build_with_use requirements


  % 1. Get some metadata we need further down

  query:search([category(C),name(N),select(slot,constraint([]),S)], Repository://Ebuild),
  query:search(version(Ver), Repository://Ebuild),
  Selected = constraint(selected_cn(C,N):{ordset([selected(Repository,Ebuild,install,Ver,S)])}),

  % 2. Compute required_use stable model, if not already passed on by run
  %    Extend with build_with_use requirements

  (findall(Item,
          (member(build_with_use(InnerList), Context),
           member(Item,InnerList)),
          B)),

  % (memberchk(build_with_use(B),Context) -> true ; B = []),
  (memberchk(required_use(R),Context) -> true ; true),

  query:search(model(Model,required_use(R),build_with_use(B)),Repository://Ebuild),

  % 3. Pass use model onto dependencies to calculate corresponding dependency  model,
  %    We pass using config action to avoid package_dependency from generating choices.
  %    The config action triggers use_conditional, any_of_group, exactly_one_of_group,
  %    all_of_group ... choice point generation

  % 4. Compute + memoize dependency model, already grouped by package Category & Name.

  query:memoized_search(model(dependency(MergedDeps0,install)):config?{Model},Repository://Ebuild),
  add_self_to_dep_contexts(Repository://Ebuild, MergedDeps0, MergedDeps),

  % 5. Pass on relevant package dependencies and constraints to prover

  ( memberchk(C,['virtual','acct-group','acct-user'])
    -> Conditions = [ Selected,
                    constraint(use(Repository://Ebuild):{R}),
                    constraint(slot(C,N,S):{Ebuild})
                    |MergedDeps]
    ;  Conditions = [ Selected,
                    constraint(use(Repository://Ebuild):{R}),
                    constraint(slot(C,N,S):{Ebuild}),
                    Repository://Ebuild:download?{[required_use(R),build_with_use(B)]}
                    |MergedDeps] )
  ; Conditions = [assumed(Repository://Ebuild:install?{[issue_with_model(explanation)|Context]})].


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
  % 0. Check if the ebuild is masked or installed
  query:search(masked(true),   Repository://Ebuild) -> Conditions = [] ;
  query:search(installed(true),Repository://Ebuild), \+preference:flag(emptytree) -> (config:avoid_reinstall(true) -> Conditions = [] ; Conditions = [Repository://Ebuild:reinstall?{Context}]) ; % todo check new build_with_use requirements

  % 1. Get some metadata we need further down

  query:search([category(C),name(N),select(slot,constraint([]),S)], Repository://Ebuild),
  query:search(version(Ver), Repository://Ebuild),
  Selected = constraint(selected_cn(C,N):{ordset([selected(Repository,Ebuild,run,Ver,S)])}),

  % 2. Compute required_use stable model, extend with build_with_use requirements

  (findall(Item,
          (member(build_with_use(InnerList), Context),
           member(Item,InnerList)),
          B)),

  % (memberchk(build_with_use(B),Context) -> true ; B = []),

  query:search(model(Model,required_use(R),build_with_use(B)),Repository://Ebuild),

  % 3. Pass use model onto dependencies to calculate corresponding dependency  model,
  %    We pass using config action to avoid package_dependency from generating choices.
  %    The config action triggers use_conditional, any_of_group, exactly_one_of_group,
  %    all_of_group ... choice point generation

  % 4. Compute + memoize dependency model, already grouped by package Category & Name.

  query:memoized_search(model(dependency(MergedDeps0,run)):config?{Model},Repository://Ebuild),
  add_self_to_dep_contexts(Repository://Ebuild, MergedDeps0, MergedDeps),

  % 5. Pass on relevant package dependencies and constraints to prover

  % If another version is already installed in the same slot, then "merge" should
  % translate into a transactional same-slot replacement (Portage-style), i.e.
  % NewVersion:update (replaces OldVersion), rather than a plain NewVersion:install.
  ( \+ preference:flag(emptytree),
    rules:entry_slot_default(Repository, Ebuild, SlotNew),
    % Fast guard: if nothing for C/N is installed in the VDB repo, don't even
    % attempt update detection. This avoids lots of failing work when proving
    % arbitrary/uninstalled packages (e.g. in `test_latest/2`).
    query:search(package(C,N), pkg://_),
    rules:installed_entry_cn(C, N, OldRepo, OldEbuild),
    OldEbuild \== Ebuild,
    % If the installed entry is no longer in the repo set, we may not have its
    % slot metadata. In that case, assume it matches the slot of the replacement
    % entry (this mirrors Portage's ability to read slot from /var/db/pkg).
    ( query:search(slot(SlotOld0), OldRepo://OldEbuild)
      -> rules:canon_slot(SlotOld0, SlotOld)
      ;  SlotOld = SlotNew
    ),
    SlotOld == SlotNew
  ->
    % IMPORTANT: do NOT thread slot(C,N,...) through action contexts. Slot is a
    % prover-level constraint (see constraint(slot(...))) and should not influence
    % grouped dependency candidate selection (it would incorrectly constrain := deps).
    InstallOrUpdate = Repository://Ebuild:update?{[replaces(OldRepo://OldEbuild),required_use(R),build_with_use(B)]}
  ; InstallOrUpdate = Repository://Ebuild:install?{[required_use(R),build_with_use(B)]}
  ),
  Conditions = [Selected,
                constraint(use(Repository://Ebuild):{R}),
                constraint(slot(C,N,S):{Ebuild}),
                InstallOrUpdate
                |MergedDeps].


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
  Conditions = [LatestRepo://LatestEbuild:update?{[replaces(Repository://Ebuild)|Context]}].

% If the user targets a specific version with :update and it is not installed,
% treat it as a transactional same-slot replacement when an older version is
% installed, otherwise fall back to a plain install.
rule(Repository://Ebuild:update?{Context},Conditions) :-
  \+ memberchk(replaces(_), Context),
  \+(preference:flag(emptytree)),
  query:search([category(Category),name(Name)], Repository://Ebuild),
  \+ query:search(installed(true), Repository://Ebuild),
  % Try same-slot replacement first (if slot is known).
  ( rules:entry_slot_default(Repository, Ebuild, SlotNew),
    rules:installed_entry_cn(Category, Name, OldRepo, OldEbuild),
    ( query:search(slot(SlotOld0), OldRepo://OldEbuild)
      -> rules:canon_slot(SlotOld0, SlotOld)
      ;  SlotOld = SlotNew
    ),
    SlotOld == SlotNew
  -> rules:update_txn_conditions(Repository://Ebuild, [replaces(OldRepo://OldEbuild)|Context], Conditions)
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
  rules:update_txn_conditions(Repository://Ebuild, Context, Conditions).


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
  rules:blocker_assumption_ctx(Context, AssCtx),
  Conditions = [assumed(blocker(weak, Phase, C, N, O, V, S)?{AssCtx})],
  !.


% -----------------------------------------------------------------------------
%  Rule: Conflicting package
% -----------------------------------------------------------------------------
% EAPI 8.2.6.2: a strong block is satisfied when no suitable candidate is satisfied
%
% In portage-ng we implement strong blockers as "remove if installed" (harder
% semantics like "forbid co-installation in the same plan" can be layered in
% the planner/printer using the planned package set).
rule(package_dependency(Phase,strong,C,N,O,V,S,_U):_Action?{Context},
     Conditions) :-
  ( rules:assume_blockers ->
      rules:blocker_assumption_ctx(Context, AssCtx),
      Conditions = [assumed(blocker(strong, Phase, C, N, O, V, S)?{AssCtx})]
  ; Conditions = [constraint(blocked_cn(C,N):{ordset([blocked(strong,Phase,O,V,S)])})]
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
    core_pkg(C,N), !.


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
  rules:grouped_blocker_specs(weak, Action, C, N, PackageDeps, Specs),
  rules:blocker_assumption_ctx(Context, AssCtx),
  findall(assumed(blocker(Strength, Phase, C, N, O, V, SlotReq)?{AssCtx}),
          member(blocked(Strength, Phase, O, V, SlotReq), Specs),
          Conditions).


% -----------------------------------------------------------------------------
%  Rule: Conflicting package
% -----------------------------------------------------------------------------
% EAPI 8.2.6.2: a strong block is satisfied when no suitable candidate is satisfied

rule(grouped_package_dependency(strong,C,N,PackageDeps):Action?{Context},
     Conditions) :-
  !,
  rules:grouped_blocker_specs(strong, Action, C, N, PackageDeps, Specs),
  ( rules:assume_blockers ->
      rules:blocker_assumption_ctx(Context, AssCtx),
      findall(assumed(blocker(Strength, Phase, C, N, O, V, SlotReq)?{AssCtx}),
              member(blocked(Strength, Phase, O, V, SlotReq), Specs),
              Conditions)
  ; Conditions = [constraint(blocked_cn(C,N):{ordset(Specs)})]
  ).

% Context tags for blocker assumptions, so the printer can show provenance
% (who pulled in the blocker) and test_stats can classify them.
rules:blocker_assumption_ctx(Ctx0, AssCtx) :-
  ( is_list(Ctx0),
    memberchk(self(Repo://Entry), Ctx0) ->
      AssCtx = [assumption_reason(blocker_conflict), self(Repo://Entry)]
  ; AssCtx = [assumption_reason(blocker_conflict)]
  ).

% -----------------------------------------------------------------------------
%  Internal override: assume blockers
% -----------------------------------------------------------------------------
%
% Used for developer UX: when a plan cannot be proven due to blockers, we can
% re-run in a mode that turns blockers into domain assumptions, so the printer
% can show "this would be the plan if you verify/override these blockers".

rules:assume_blockers :-
  nb_current(rules_assume_blockers, true).

rules:with_assume_blockers(Goal) :-
  ( nb_current(rules_assume_blockers, Old) -> true ; Old = unset ),
  nb_setval(rules_assume_blockers, true),
  setup_call_cleanup(true,
                     Goal,
                     ( Old == unset -> nb_delete(rules_assume_blockers)
                     ; nb_setval(rules_assume_blockers, Old)
                     )).


% =============================================================================
%  Rule: Package dependencies
% =============================================================================

rule(grouped_package_dependency(no,C,N,PackageDeps):Action?{Context},Conditions) :-
  !,
  % Self-dependency at runtime is trivially satisfied: once the package is built,
  % it provides itself. Treat this generically to avoid hard failures on packages
  % that (redundantly) list themselves in RDEPEND.
  ( Action == run,
    memberchk(self(SelfRepo://SelfEntry), Context),
    query:search([category(C),name(N)], SelfRepo://SelfEntry)
  ->
    Conditions = []
  ; preference:flag(emptytree),
    core_pkg(C,N)
  ->
    Conditions = []
  ; \+ preference:flag(emptytree),
    \+ preference:flag(deep),
    merge_slot_restriction(Action, C, N, PackageDeps, SlotReq),
    % If an installed instance exists in the same slot, and it satisfies all
    % version constraints, treat the grouped dependency as satisfied.
    %
    % Performance note:
    % Avoid `select(version,O,V)` with variable Op, and `select(slot,constraint(SlotReq),_)`
    % with variable SlotReq, because those prevent compile-time query macro expansion.
    query:search([repository(pkg),category(C),name(N),installed(true)],
                 pkg://InstalledEntry),
    rules:query_search_slot_constraint(SlotReq, pkg://InstalledEntry, _),
    rules:installed_entry_satisfies_package_deps(Action, C, N, PackageDeps, pkg://InstalledEntry),
    % --newuse: do not "keep installed" if USE/IUSE has changed since the installed
    % package was built (Portage-like -N behavior).
    ( preference:flag(newuse) ->
        \+ rules:newuse_mismatch(pkg://InstalledEntry)
    ; true
    ),
    !   % commit to the first installed entry that satisfies constraints
  ->
    Conditions = []
  ;
    ( (memberchk(slot(C,N,Ss):{_}, Context) -> true ; true),
      merge_slot_restriction(Action, C, N, PackageDeps, SlotReq),

      % Candidate selection (portage / overlays)
      rules:accepted_keyword_candidate(Action, C, N, SlotReq, Ss, Context, FoundRepo://Candidate),

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

      forall(member(package_dependency(Action,no,C,N,O,V,_,_), PackageDeps),
             rules:query_search_version_select(O, V, FoundRepo://Candidate)),

      findall(U, member(package_dependency(Action,no,C,N,_O,_V,_,U),PackageDeps), MergedUse),
      process_build_with_use(MergedUse,Context,NewContext,Constraints,FoundRepo://Candidate),
      process_slot(SlotReq,Ss,C,N,FoundRepo://Candidate,NewContext,NewerContext),

      % Prefer expressing as update when a pkg-installed entry exists and the chosen
      % candidate is newer.
      ( \+ preference:flag(emptytree),
        query:search([repository(pkg),category(C),name(N),installed(true)],
                     pkg://InstalledEntry2),
        rules:query_search_slot_constraint(SlotReq, pkg://InstalledEntry2, _),
        !,
        ( % Standard update: candidate newer than installed
          InstalledEntry2 \== Candidate,
          query:search(version(OldVer), pkg://InstalledEntry2),
          query:search(select(version,greater,OldVer), FoundRepo://Candidate) ->
            UpdateCtx = [replaces(pkg://InstalledEntry2)|NewerContext]
        ; % --newuse: force a transactional rebuild even if version is the same,
          % when USE/IUSE differs.
          preference:flag(newuse),
          rules:newuse_mismatch(pkg://InstalledEntry2, FoundRepo://Candidate) ->
            UpdateCtx = [replaces(pkg://InstalledEntry2),rebuild_reason(newuse)|NewerContext]
        )
      ->
        ActionGoal = FoundRepo://Candidate:update?{UpdateCtx}
      ; ActionGoal = FoundRepo://Candidate:Action?{NewerContext}
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
      Selected = constraint(selected_cn(C,N):{ordset([selected(FoundRepo,Candidate,ActSel,CandVer,Ss)])}),
      append([Selected|Constraints], [ActionGoal], Conditions)
    ; % In --deep mode we *prefer* upgrades, but we should not create domain
      % assumptions when the dependency is already installed in the vdb (`pkg`)
      % and satisfies constraints. Instead, fall back to "keep installed".
      ( preference:flag(deep),
        merge_slot_restriction(Action, C, N, PackageDeps, SlotReq2),
        query:search([repository(pkg),category(C),name(N),installed(true)],
                     pkg://InstalledEntryFallback),
        rules:query_search_slot_constraint(SlotReq2, pkg://InstalledEntryFallback, _),
        !,
        rules:installed_entry_satisfies_package_deps(Action, C, N, PackageDeps, pkg://InstalledEntryFallback)
      ->
        Conditions = []
      ; explanation:assumption_reason_for_grouped_dep(Action, C, N, PackageDeps, Context, Reason),
        Conditions = [assumed(grouped_package_dependency(C,N,PackageDeps):Action?{[assumption_reason(Reason)|Context]})]
      )
    )
  ).


% -----------------------------------------------------------------------------
%  Keyword-aware candidate enumeration (Portage-like)
% -----------------------------------------------------------------------------
%
% Enumerate candidates that match any accepted keyword, in descending version
% order, so the solver tries the best versions first but can backtrack to
% older alternatives.

rules:accepted_keyword_candidate(Action, C, N, SlotReq, Ss, Context, FoundRepo://Candidate) :-
  ( preference:keyword_selection_mode(keyword_order) ->
      % Legacy behavior: accept_keywords enumeration order is a preference.
      preference:accept_keywords(K),
      rules:query_keyword_candidate(Action, C, N, K, Context, FoundRepo://Candidate),
      rules:query_search_slot_constraint(SlotReq, FoundRepo://Candidate, Ss)
  ; % Portage-like: union of accepted keywords, then choose max version first.
    findall(FoundRepo0://Candidate0,
            ( preference:accept_keywords(K0),
              rules:query_keyword_candidate(Action, C, N, K0, Context, FoundRepo0://Candidate0),
              rules:query_search_slot_constraint(SlotReq, FoundRepo0://Candidate0, Ss)
            ),
            Candidates0),
    Candidates0 \== [],
    sort(Candidates0, Candidates1),
    predsort(rules:compare_candidate_version_desc, Candidates1, CandidatesSorted),
    member(FoundRepo://Candidate, CandidatesSorted)
  ).

rules:query_keyword_candidate(Action, C, N, K, Context, FoundRepo://Candidate) :-
  ( Action \== run,
    memberchk(self(SelfRepo0://SelfEntry0), Context),
    query:search([category(C),name(N)], SelfRepo0://SelfEntry0)
  ->
    \+ preference:flag(emptytree),
    query:search([name(N),category(C),keyword(K),installed(true)], FoundRepo://Candidate),
    \+ preference:masked(FoundRepo://Candidate)
  ; query:search([name(N),category(C),keyword(K)], FoundRepo://Candidate),
    \+ preference:masked(FoundRepo://Candidate)
  ).

rules:compare_candidate_version_desc(Delta, RepoA://IdA, RepoB://IdB) :-
  cache:ordered_entry(RepoA, IdA, _Ca, _Na, VerA),
  cache:ordered_entry(RepoB, IdB, _Cb, _Nb, VerB),
  ( eapi:version_compare(>, VerA, VerB) -> Delta = (<)
  ; eapi:version_compare(<, VerA, VerB) -> Delta = (>)
  ; Delta = (=)
  ).


% -----------------------------------------------------------------------------
%  --newuse support (Portage-like -N)
% -----------------------------------------------------------------------------
%
% Minimal implementation:
% - Compare installed VDB USE (what the package was built with) against the
%   currently effective USE for the same version (when available in repo set).
% - Also compare installed VDB IUSE against current IUSE to detect added/removed
%   flags (if VDB provides IUSE; we parse it when present).
%
% If we cannot locate the same version in the current repo set, we conservatively
% do not force a rebuild.

rules:newuse_mismatch(pkg://InstalledEntry) :-
  % Find the same version in the active repo set (excluding VDB repo `pkg`).
  query:search([category(C),name(N),version(V)], pkg://InstalledEntry),
  preference:accept_keywords(K),
  ( query:search([select(repository,notequal,pkg),category(C),name(N),keywords(K),version(V)],
                 CurRepo//CurEntry)
  -> rules:newuse_mismatch(pkg://InstalledEntry, CurRepo//CurEntry)
  ;  fail
  ).

rules:newuse_mismatch(pkg://InstalledEntry, CurRepo//CurEntry) :-
  rules:vdb_enabled_use_set(pkg://InstalledEntry, BuiltUse),
  rules:entry_enabled_use_set(CurRepo//CurEntry, CurUse),
  ( rules:symmetric_diff_nonempty(BuiltUse, CurUse)
  ; rules:vdb_iuse_set(pkg://InstalledEntry, BuiltIuse),
    rules:entry_iuse_set(CurRepo//CurEntry, CurIuse),
    BuiltIuse \== [],
    CurIuse \== [],
    rules:symmetric_diff_nonempty(BuiltIuse, CurIuse)
  ),
  !.

rules:vdb_enabled_use_set(RepoEntry, UseSet) :-
  findall(U, query:search(use(U), RepoEntry), Us0),
  sort(Us0, UseSet).

rules:entry_iuse_set(RepoEntry, IuseSet) :-
  findall(U,
          ( query:search(iuse(Value), RepoEntry),
            eapi:strip_use_default(Value, U)
          ),
          Us0),
  sort(Us0, IuseSet).

rules:vdb_iuse_set(RepoEntry, IuseSet) :-
  rules:entry_iuse_set(RepoEntry, IuseSet).

% Current effective enabled USE set for an ebuild entry:
% gather IUSE flags that evaluate to positive under current preference/profile.
rules:entry_enabled_use_set(RepoEntry, UseSet) :-
  findall(U,
          ( query:search(iuse(Value), RepoEntry),
            eapi:categorize_use(Value, positive, _Reason),
            eapi:strip_use_default(Value, U)
          ),
          Us0),
  sort(Us0, UseSet).

rules:symmetric_diff_nonempty(A, B) :-
  ( member(X, A), \+ memberchk(X, B) -> true
  ; member(X, B), \+ memberchk(X, A) -> true
  ).


% -----------------------------------------------------------------------------
%  Depclean traversal rules
% -----------------------------------------------------------------------------
%
% These are used by depclean:run/1 to compute a "kept" closure over *installed*
% packages only, using repository metadata for dependency structure.

rule(Repository://Ebuild:depclean?{Context}, Conditions) :-
  % Use current preference/profile to evaluate USE conditionals.
  ( query:search(model(Model,required_use(_R),build_with_use(_B)), Repository://Ebuild),
    % Compute runtime dependency model in config phase (no candidate choices here).
    query:memoized_search(model(dependency(MergedDeps0,run)):config?{Model}, Repository://Ebuild),
    add_self_to_dep_contexts(Repository://Ebuild, MergedDeps0, MergedDeps),
    % Rewrite all dependency literals to the depclean action.
    rules:depclean_rewrite_deps(MergedDeps, Context, Conditions)
  -> true
  ; Conditions = []
  ).

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

% Depclean: grouped package dependency – follow only installed packages.
rule(grouped_package_dependency(no,C,N,PackageDeps):depclean?{_Context}, Conditions) :-
  !,
  merge_slot_restriction(run, C, N, PackageDeps, SlotReq),
  ( query:search([repository(pkg),category(C),name(N),installed(true)], pkg://InstalledEntry),
    rules:query_search_slot_constraint(SlotReq, pkg://InstalledEntry, _),
    rules:installed_entry_satisfies_package_deps(run, C, N, PackageDeps, pkg://InstalledEntry),
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
  memberchk(assumed(Use),Context),!,
  findall(D:Action?{Context},member(D,Deps),Conditions).

% 2. The USE is explicitely enabled, either by preference or ebuild -> process deps

rule(use_conditional_group(positive,Use,R://E,Deps):Action?{Context},Conditions) :-
  query:search(iuse(Value), R://E),
  eapi:categorize_use_for_entry(Value, R://E, positive, _Reason),
  eapi:strip_use_default(Value,Use),!,
  findall(D:Action?{Context},member(D,Deps),Result),
  Conditions = Result.

% 3. The USE is not enabled -> no deps

rule(use_conditional_group(positive,_Use,_R://_E,_):_?{_},[]) :-
  !.


% -----------------------------------------------------------------------------
%  Rule: Negative use conditional dependencies
% -----------------------------------------------------------------------------
% The dependencies in a negative use conditional group need to be satisfied when
% the use flag is not positive through required use constraint, preference or
% ebuild default

% 1. The USE is enabled in the context (dependency induced, or required_use)

rule(use_conditional_group(negative,Use,_R://_E,Deps):Action?{Context},Conditions) :-
  memberchk(naf(use(Use)),Context),!,
  findall(D:Action?{Context},member(D,Deps),Conditions).

% 2. The USE is explicitely enabled, either by preference or ebuild -> process deps

rule(use_conditional_group(negative,Use,R://E,Deps):Action?{Context},Conditions) :-
  query:search(iuse(Value), R://E),
  eapi:categorize_use_for_entry(Value, R://E, negative, _Reason),
  eapi:strip_use_default(Value,Use),!,
  findall(D:Action?{Context},member(D,Deps),Result),
  Conditions = Result.

% 3. The USE is not enabled -> no deps

rule(use_conditional_group(negative,_Use,_R://_E,_):_?{_},[]) :-
  !.


% -----------------------------------------------------------------------------
%  Rule: Contextless use conditionals
% -----------------------------------------------------------------------------
% Contextless use conditionals are found in for example required_use constraints.

rule(use_conditional_group(positive,Use,_://_,Deps),Conditions) :-
  preference:use(Use),!,
  findall(D,member(D,Deps),Conditions).

rule(use_conditional_group(positive,_,_://_,_),[]) :- !.

rule(use_conditional_group(negative,Use,_://_,Deps),Conditions) :-
  preference:use(minus(Use)),!,
  findall(D,member(D,Deps),Conditions).

rule(use_conditional_group(negative,_,_://_,_),[]) :- !.


% -----------------------------------------------------------------------------
%  Rule: Exactly one of group
% -----------------------------------------------------------------------------
% Exactly one of the dependencies in an exactly-one-of-group should be satisfied

rule(exactly_one_of_group(Deps):Action?{Context},[D:Action?{Context}|NafDeps]) :-
  prioritize_deps(Deps, Context, SortedDeps),
  member(D0, SortedDeps),
  rules:group_choice_dep(D0, D),
  findall(naf(N),(member(N,Deps), \+(D = N)),NafDeps).

rule(exactly_one_of_group(Deps),[D|NafDeps]) :-
  prioritize_deps(Deps, SortedDeps),
  member(D, SortedDeps),
  findall(naf(N),(member(N,Deps), \+(D = N)),NafDeps).


% -----------------------------------------------------------------------------
%  Rule: At most one of group
% -----------------------------------------------------------------------------
% At most one of the dependencies in an at-most-one-of-group should be satisfied

% Allow choosing none (all negated) — Portage REQUIRED_USE '?? ( ... )' does NOT
% require any of the flags to be enabled.
rule(at_most_one_of_group(Deps):_Action?{_Context}, NafDeps) :-
  findall(naf(N),(member(N,Deps)),NafDeps).

rule(at_most_one_of_group(Deps):Action?{Context},[D:Action?{Context}|NafDeps]) :-
  prioritize_deps(Deps, Context, SortedDeps),
  member(D0, SortedDeps),
  rules:group_choice_dep(D0, D),
  findall(naf(N),(member(N,Deps), \+(D = N)),NafDeps).

% Contextless variant: allow choosing none.
rule(at_most_one_of_group(Deps), NafDeps) :-
  findall(naf(N),(member(N,Deps)),NafDeps).

rule(at_most_one_of_group(Deps),[D|NafDeps]) :-
  prioritize_deps(Deps, SortedDeps),
  member(D, SortedDeps),
  findall(naf(N),(member(N,Deps), \+(D = N)),NafDeps).


% -----------------------------------------------------------------------------
%  Rule: Any of group
% -----------------------------------------------------------------------------
% One dependency of an any_of_group should be satisfied

% When resolving dependency groups at Action time, group choices that are plain
% package_dependency/8 terms must be lifted into grouped_package_dependency/4,
% because the actual resolution logic lives in grouped_package_dependency rules.
rules:group_choice_dep(package_dependency(Phase,Strength,C,N,O,V,S,U),
                       grouped_package_dependency(Strength,C,N,
                           [package_dependency(Phase,Strength,C,N,O,V,S,U)])) :- !.
rules:group_choice_dep(D, D).

% During model construction (`config` phase), we must *prove* the chosen literal
% so it becomes part of the memoized model. Calling `rule/2` directly (as in the
% runtime clause below) does not record the chosen package_dependency/8 in the
% model, which makes || ( ... ) disappear from dependency models.
rule(any_of_group(Deps):config?{Context}, [D:config?{Context}]) :-
  prioritize_deps(Deps, Context, SortedDeps),
  member(D0, SortedDeps),
  % In config phase we must prove the *package_dependency/8* term so it is
  % recorded in the model (AvlModel) and later extracted by query:model/2.
  D = D0,
  !.

rule(any_of_group(Deps):Action?{Context}, Conditions) :-
  prioritize_deps(Deps, Context, SortedDeps),
  member(D0, SortedDeps),
  rules:group_choice_dep(D0, D),
  rule(D:Action?{Context}, Conditions),
  !.

rule(any_of_group(Deps), Conditions) :-
  prioritize_deps(Deps, SortedDeps),
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
rule(required(Use):_?{Context},[Use]) :-
  \+Use =.. [minus,_],
  rules:effective_use_in_context(Context, Use, positive),
  !.
rule(required(minus(Use)):_?{Context},[minus(Use)]) :-
  \+Use =.. [minus,_],
  rules:effective_use_in_context(Context, Use, negative),
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

rule(conflict(_,_),[]) :- !,
  fail.

% The default rule, prover takes care of negation

rule(naf(_),[]) :- !.

% Atoms

rule(Literal,[]) :-
  atom(Literal),!.

% -----------------------------------------------------------------------------
%  Helper: merge_slot_restriction
% -----------------------------------------------------------------------------
% Derive the (single) slot restriction to apply when selecting a candidate for a
% grouped dependency. If no slot restriction is present, return [].
% If multiple distinct slot restrictions are present, fail (no candidate can satisfy all).

merge_slot_restriction(Action, C, N, PackageDeps, SlotReq) :-
  % Performance note: this predicate is called very frequently during proving.
  % Avoid findall/3 + sort/2 and instead scan once, ensuring all non-empty slot
  % restrictions are identical.
  merge_slot_restriction_(PackageDeps, Action, C, N, none, Slot0),
  ( Slot0 == none -> SlotReq = []
  ; SlotReq = Slot0
  ).

merge_slot_restriction_([], _Action, _C, _N, Acc, Acc) :- !.
merge_slot_restriction_([package_dependency(Action,no,C,N,_O,_V,S,_U)|Rest], Action, C, N, Acc0, Acc) :-
  !,
  ( S == []      -> Acc1 = Acc0
  ; Acc0 == none -> Acc1 = S
  ; Acc0 == S    -> Acc1 = Acc0
  ; fail
  ),
  merge_slot_restriction_(Rest, Action, C, N, Acc1, Acc).
merge_slot_restriction_([_|Rest], Action, C, N, Acc0, Acc) :-
  merge_slot_restriction_(Rest, Action, C, N, Acc0, Acc).

% -----------------------------------------------------------------------------
%  Helper: query_search_slot_constraint
% -----------------------------------------------------------------------------
% Execute a slot constraint query in a way that preserves compile-time query macro
% expansion (i.e. avoid passing a variable SlotReq into select(slot,constraint/2)).

query_search_slot_constraint(SlotReq, RepoEntry, SlotMeta) :-
  % IMPORTANT: keep the second argument of query:search/2 syntactically in the
  % form Repo://Id so goal-expansion does not bind a variable during compilation.
  RepoEntry = Repo://Id,
  ( SlotReq == [] ->
      query:search(select(slot,constraint([]),SlotMeta), Repo://Id)
  ; SlotReq = [slot(S)] ->
      query:search(select(slot,constraint([slot(S)]),SlotMeta), Repo://Id)
  ; SlotReq = [slot(S),subslot(Ss)] ->
      query:search(select(slot,constraint([slot(S),subslot(Ss)]),SlotMeta), Repo://Id)
  ; SlotReq = [slot(S),equal] ->
      query:search(select(slot,constraint([slot(S),equal]),SlotMeta), Repo://Id)
  ; SlotReq = [slot(S),subslot(Ss),equal] ->
      query:search(select(slot,constraint([slot(S),subslot(Ss),equal]),SlotMeta), Repo://Id)
  ; SlotReq = [any_same_slot] ->
      query:search(select(slot,constraint([any_same_slot]),SlotMeta), Repo://Id)
  ; SlotReq = [any_different_slot] ->
      query:search(select(slot,constraint([any_different_slot]),SlotMeta), Repo://Id)
  ; % Fallback (should be rare; may be slower due to missing macro)
    query:search(select(slot,constraint(SlotReq),SlotMeta), Repo://Id)
  ).

% -----------------------------------------------------------------------------
%  Helper: installed_entry_satisfies_package_deps
% -----------------------------------------------------------------------------
% Check that an installed entry satisfies all version constraints expressed in
% the grouped package dependency list, while preserving query macro expansion.

installed_entry_satisfies_package_deps(_Action, _C, _N, [], _Installed) :- !.
installed_entry_satisfies_package_deps(Action, C, N,
                                       [package_dependency(Action,no,C,N,O,V,_,_)|Rest],
                                       Installed) :-
  !,
  rules:query_search_version_select(O, V, Installed),
  rules:installed_entry_satisfies_package_deps(Action, C, N, Rest, Installed).
installed_entry_satisfies_package_deps(Action, C, N, [_|Rest], Installed) :-
  rules:installed_entry_satisfies_package_deps(Action, C, N, Rest, Installed).

% Map runtime operator to a compile-time-friendly `select(version,<op>,...)` goal.
query_search_version_select(equal, Ver, RepoEntry) :- !,
  RepoEntry = Repo://Id,
  query:search(select(version,equal,Ver), Repo://Id).
query_search_version_select(none, _Ver, _RepoEntry) :- !.
query_search_version_select(smaller, Ver, RepoEntry) :- !,
  RepoEntry = Repo://Id,
  query:search(select(version,smaller,Ver), Repo://Id).
query_search_version_select(greater, Ver, RepoEntry) :- !,
  RepoEntry = Repo://Id,
  query:search(select(version,greater,Ver), Repo://Id).
query_search_version_select(smallerequal, Ver, RepoEntry) :- !,
  RepoEntry = Repo://Id,
  query:search(select(version,smallerequal,Ver), Repo://Id).
query_search_version_select(greaterequal, Ver, RepoEntry) :- !,
  RepoEntry = Repo://Id,
  query:search(select(version,greaterequal,Ver), Repo://Id).
query_search_version_select(notequal, Ver, RepoEntry) :- !,
  RepoEntry = Repo://Id,
  query:search(select(version,notequal,Ver), Repo://Id).
query_search_version_select(wildcard, Ver, RepoEntry) :- !,
  RepoEntry = Repo://Id,
  query:search(select(version,wildcard,Ver), Repo://Id).
query_search_version_select(tilde, Ver, RepoEntry) :- !,
  RepoEntry = Repo://Id,
  query:search(select(version,tilde,Ver), Repo://Id).
query_search_version_select(Op, Ver, RepoEntry) :-
  % Fallback: keep semantics even if slower / not macro-expanded.
  RepoEntry = Repo://Id,
  query:search(select(version,Op,Ver), Repo://Id).


% =============================================================================
%  Ruleset: Dependency group helpers
% =============================================================================

% -----------------------------------------------------------------------------
%  Helper: prioritize_deps
% -----------------------------------------------------------------------------
% Sorts dependencies by prioritizing those that match user preferences, to
% reduce the number of assumptions in the proof.

prioritize_deps(Deps, SortedDeps) :-
  prioritize_deps(Deps, [], SortedDeps).

prioritize_deps(Deps, Context, SortedDeps) :-
  predsort(rules:compare_dep_rank(Context), Deps, SortedDeps).

% Rank dependencies for deterministic group choice.
% Primary signal: prefer deps that are already satisfied by effective USE /
% preferences / installed packages.
% Secondary signal: for selector-style flags, choose highest version/slot.
rules:compare_dep_rank(Context, Delta, A, B) :-
  rules:dep_rank(Context, A, Ra),
  rules:dep_rank(Context, B, Rb),
  compare(C, Rb, Ra), % descending
  ( C == (<) -> Delta = (<)
  ; C == (>) -> Delta = (>)
  ; Delta = (=)
  ).

rules:dep_rank(Context, Dep, Rank) :-
  ( is_preferred_dep(Context, Dep) -> Pref = 1 ; Pref = 0 ),
  rules:dep_intrinsic_rank(Dep, Base),
  Rank is Pref*1000000000 + Base.

rules:dep_intrinsic_rank(required(Use), Rank) :-
  rules:use_rank(Use, Rank),
  !.
rules:dep_intrinsic_rank(required(minus(Use)), Rank) :-
  rules:use_rank(Use, Rank),
  !.
rules:dep_intrinsic_rank(_, 0).

rules:use_rank(Use, Rank) :-
  atom(Use),
  ( rules:llvm_slot_rank(Use, Rank)
  ; rules:lua_single_target_rank(Use, Rank)
  ),
  !.
rules:use_rank(_, 0).

rules:llvm_slot_rank(Use, Rank) :-
  atom_concat('llvm_slot_', Suffix, Use),
  catch(atom_number(Suffix, N), _, fail),
  Rank is 100000 + N.

rules:lua_single_target_rank(Use, Rank) :-
  % lua-single flags show up as e.g. lua_single_target_lua5-4
  atom_concat('lua_single_target_lua5-', Suffix, Use),
  catch(atom_number(Suffix, N), _, fail),
  Rank is 90000 + N.

is_preferred_dep(Context, required(Use)) :-
  Use \= minus(_),
  ( preference:use(Use)
  ; rules:effective_use_in_context(Context, Use, positive)
  ),
  !.
is_preferred_dep(Context, required(minus(Use))) :-
  ( preference:use(minus(Use))
  ; rules:effective_use_in_context(Context, Use, negative)
  ),
  !.

% Prefer any-of alternatives that are already installed.
% This helps align Portage-like behavior for || groups that include a heavy
% build-time tool (e.g. dev-lang/vala) versus a lighter already-installed
% alternative (e.g. gobject-introspection).
is_preferred_dep(_Context, package_dependency(_Phase,_Strength,_C,N,_O,_V,_S,_U)) :-
  % Prefer *-bin alternatives in || groups to avoid pulling toolchains from source
  % when Portage would use a prebuilt binary (e.g. zig-bin).
  atom_concat(_, '-bin', N),
  !.
is_preferred_dep(_Context, package_dependency(_Phase,_Strength,C,N,O,V,_S,_U)) :-
  query:search([repository(pkg),category(C),name(N),installed(true)], pkg://Installed),
  ( O == none ; rules:query_search_version_select(O, V, pkg://Installed) ),
  !.

% Effective USE for the current ebuild (when we have `self(...)` in Context).
% Helps REQUIRED_USE group choice: prefer alternatives already satisfied by the
% current effective USE (profile/env/package.use), rather than forcing new flags.
rules:effective_use_in_context(Context, Use, State) :-
  ( memberchk(self(RepoEntry0), Context) ->
      ( RepoEntry0 = Repo://Id -> true
      ; RepoEntry0 = Repo//Id  -> true
      )
  ; nb_current(query_required_use_self, Repo://Id)
  ),
  query:search(iuse(RawIuse), Repo://Id),
  eapi:strip_use_default(RawIuse, Use),
  eapi:categorize_use_for_entry(RawIuse, Repo://Id, State, _Reason),
  !.

% -----------------------------------------------------------------------------
%  Helper: add_self_to_dep_contexts
% -----------------------------------------------------------------------------
% Annotate dependency literals with provenance of the "current ebuild" so that
% downstream dependency-resolution rules can make safe choices (e.g. avoid
% resolving a dependency to the current ebuild unless it is already installed),
% without polluting memoized model keys.

add_self_to_dep_contexts(_Self, [], []) :- !.
add_self_to_dep_contexts(Self, [D0|Rest0], [D|Rest]) :-
  ( D0 = Term:Action?{Ctx} ->
      ( memberchk(self(Self), Ctx) ->
          D = D0
      ; D = Term:Action?{[self(Self)|Ctx]}
      )
  ; D = D0
  ),
  add_self_to_dep_contexts(Self, Rest0, Rest).

% -----------------------------------------------------------------------------
%  Rule: Core packages
% -----------------------------------------------------------------------------
% Core packages are used to resolve dependencies on the system profile. This way
% we avoid unnecessary assumptions in the proof, since we know the system profile
% is always installed.

core_pkg('app-admin','eselect').
core_pkg('app-alternatives','awk').
core_pkg('app-alternatives','bzip2').
core_pkg('app-alternatives','gzip').
core_pkg('app-alternatives','sh').
core_pkg('app-alternatives','tar').
core_pkg('app-arch','bzip2').
core_pkg('app-arch','gzip').
core_pkg('app-arch','tar').
core_pkg('app-arch','xz-utils').
core_pkg('app-shells','bash').
core_pkg('dev-build','make').
core_pkg('net-mail','mailbase').
core_pkg('net-misc','iputils').
core_pkg('net-misc','rsync').
core_pkg('net-misc','wget').
core_pkg('sec-keys','openpgp-keys-gentoo-release').
core_pkg('sys-apps','baselayout').
core_pkg('sys-apps','coreutils').
core_pkg('sys-apps','diffutils').
core_pkg('sys-apps','file').
core_pkg('sys-apps','findutils').
core_pkg('sys-apps','gawk').
core_pkg('sys-apps','grep').
core_pkg('sys-apps','iproute2').
core_pkg('sys-apps','kbd').
core_pkg('sys-apps','kmod').
core_pkg('sys-apps','less').
core_pkg('sys-apps','man-pages').
core_pkg('sys-apps','net-tools').
core_pkg('sys-apps','sed').
core_pkg('sys-apps','shadow').
core_pkg('sys-apps','util-linux').
core_pkg('sys-apps','which').
core_pkg('sys-devel','binutils').
core_pkg('sys-devel','gcc').
core_pkg('sys-devel','gnuconfig').
core_pkg('sys-devel','patch').
core_pkg('sys-fs','e2fsprogs').
core_pkg('sys-process','procps').
core_pkg('sys-process','psmisc').
core_pkg('virtual','dev-manager').
core_pkg('virtual','editor').
core_pkg('virtual','libc').
core_pkg('virtual','man').
core_pkg('virtual','os-headers').
core_pkg('virtual','package-manager').
core_pkg('virtual','pager').
core_pkg('virtual','service-manager').
core_pkg('virtual','ssh').


% -----------------------------------------------------------------------------
%  Helper for process_slot
% -----------------------------------------------------------------------------

process_slot([any_different_slot], _, _, _, _, Context, Context) :- !.
% Do not "lock" explicit slot requirements into the shared context.
% Many ecosystems (notably Ruby) legitimately require multiple slots to coexist
% in the same plan (e.g. dev-lang/ruby:3.2 and dev-lang/ruby:3.3). If we store a
% single chosen slot in the context, later deps for a different explicit slot
% will fail to resolve and get misreported as "non-existent".
process_slot([slot(_)], _SlotMeta, _C, _N, _Repository://_Candidate, Context, Context) :- !.
process_slot(_, Slot, C, N, _Repository://Candidate, Context, [slot(C, N, Slot):{Candidate}|Context]).

%process_slot([any_same_slot],Slot,Context,[slot(Slot)|Context]) :- !.
%process_slot([slot(X),equal],[slot(X)],Context,[slot([slot(X)])|Context]) :- !.
%process_slot(_,_,Context,Context).



% -----------------------------------------------------------------------------
%  Helper for process_build_with_use
% -----------------------------------------------------------------------------
% When processing build with use directives, we are given the current context
% as well as the directives. We extend the current context with the directives
% prior to passing it on to the child dependencies. We also return build_with_use
% constraints that should be added to the global constraint list.

% Main predicate using foldl/4 to process USE directives.
process_build_with_use(Directives, Context, [build_with_use(Result)|Context], Conditions, Candidate) :-
    foldl(process_use(Context), Directives, [], Result),
    build_with_use_constraints(Directives, Conditions, Candidate).

% Helper predicate to generate build_with_use constraints
% Collects all USE requirements into a single list to avoid data duplication
%
% NOTE:
% Portage-style USE dependencies like `[foo]` or `[foo(+)]` are constraints on the
% *child package's* USE state, not on the global profile/make.conf USE.
%
% At the moment, `portage-ng` models these by pushing `assumed(foo)` /
% `naf(required(foo))` into the dependency context (see `process_use/4`) so that
% downstream `use_conditional_group/4` can resolve correctly.
%
% Emitting global `constraint(use(Candidate))` entries here incorrectly ties these
% requirements to `preference:use/1` (global USE), which causes false
% "unsatisfiable dependency" errors (e.g. xdg-utils -> xmlto[text(+)]), even when
% the child package has that flag enabled by default.
%
% Until we implement per-package USE evaluation, we keep these as context only.
build_with_use_constraints(_, [], _) :- !.

% Helper predicate to collect all USE requirements into a single list
collect_use_requirements([], []).
collect_use_requirements([use(enable(Use), _)|Rest], [required(Use)|RestRequirements]) :-
    !,
    collect_use_requirements(Rest, RestRequirements).
collect_use_requirements([use(disable(Use), _)|Rest], [naf(required(Use))|RestRequirements]) :-
    !,
    collect_use_requirements(Rest, RestRequirements).
collect_use_requirements([use(equal(Use), _)|Rest], [required(Use)|RestRequirements]) :-
    !,
    collect_use_requirements(Rest, RestRequirements).
collect_use_requirements([use(inverse(Use), _)|Rest], [naf(required(Use))|RestRequirements]) :-
    !,
    collect_use_requirements(Rest, RestRequirements).
collect_use_requirements([use(optenable(Use), _)|Rest], [required(Use)|RestRequirements]) :-
    !,
    collect_use_requirements(Rest, RestRequirements).
collect_use_requirements([use(optdisable(Use), _)|Rest], [naf(required(Use))|RestRequirements]) :-
    !,
    collect_use_requirements(Rest, RestRequirements).
collect_use_requirements([_|Rest], RestRequirements) :-
    !,
    collect_use_requirements(Rest, RestRequirements).


% Helper predicate for foldl/4.
% It processes a single USE directive.

% Handles [opt] - The flag must be enabled.
process_use(_Context, use(enable(Use), _), Acc, [required(Use), assumed(Use)|Acc]).

% Handles [-opt] - The flag must be disabled.
process_use(_Context, use(disable(Use), _), Acc, [naf(required(Use)), assumed(minus(Use))|Acc]).

% Handles [opt=] - The flag must be enabled if enabled in the parent, disabled otherwise.
process_use(Context, use(equal(Use), _), Acc, [required(Use), assumed(Use)|Acc]) :-
    memberchk(assumed(Use), Context), !.								% this is broken, there is parent use info (i think)?
process_use(Context, use(equal(Use), _), Acc, [naf(required(Use)), assumed(minus(Use))|Acc]) :-
    \+ memberchk(assumed(Use), Context).								% item

% Handles [!opt=] - The flag must be disabled if enabled in the parent, enabled otherwise.
process_use(Context, use(inverse(Use), _), Acc, [naf(required(Use)), assumed(minus(Use))|Acc]) :-
    memberchk(assumed(Use), Context), !.								% idem
process_use(Context, use(inverse(Use), _), Acc, [required(Use), assumed(Use)|Acc]) :-
    \+ memberchk(assumed(Use), Context).

% Handles [opt?] - The flag must be enabled if enabled in the parent.
process_use(Context, use(optenable(Use), _), Acc, [required(Use), assumed(Use)|Acc]) :-
    (memberchk(assumed(Use), Context); preference:use(Use)), !.						% idem
process_use(_Context, use(optenable(_Use), _), Acc, Acc).

% Handles [!opt?] - The flag must be disabled if disabled in the parent.
process_use(Context, use(optdisable(Use), _), Acc, [naf(required(Use)), assumed(minus(Use))|Acc]) :-
    (memberchk(assumed(minus(Use)), Context); preference:use(minus(Use))), !.				% idem
process_use(_Context, use(optdisable(_Use), _), Acc, Acc).

% 4-style USE dependency defaults
% These are consulted when the conditional dependency is on a flag not in the parent's context.

% todo: this seems duplicate?

% For [opt=](+) or [!opt=](+)
process_use(_Context, use(equal(Use), positive), Acc, [required(Use), assumed(Use)|Acc]).
process_use(_Context, use(inverse(Use), positive), Acc, [required(Use), assumed(Use)|Acc]).
process_use(_Context, use(optenable(Use), positive), Acc, [required(Use), assumed(Use)|Acc]).
process_use(_Context, use(optdisable(Use), positive), Acc, [required(Use), assumed(Use)|Acc]).


% For [opt=](-) or [!opt=](-)
process_use(_Context, use(equal(Use), negative), Acc, [naf(required(Use)), assumed(minus(Use))|Acc]).
process_use(_Context, use(inverse(Use), negative), Acc, [naf(required(Use)), assumed(minus(Use))|Acc]).
process_use(_Context, use(optenable(Use), negative), Acc, [naf(required(Use)), assumed(minus(Use))|Acc]).
process_use(_Context, use(optdisable(Use), negative), Acc, [naf(required(Use)), assumed(minus(Use))|Acc]).

% For [opt=](none) or no default specified
process_use(_Context, use(equal(_Use), none), Acc, Acc).
process_use(_Context, use(inverse(_Use), none), Acc, Acc).
process_use(_Context, use(optenable(_Use), none), Acc, Acc).
process_use(_Context, use(optdisable(_Use), none), Acc, Acc).


% Catch-all for any other directives
process_use(_Context, _, Acc, Acc).



% Shared implementation of transactional update prerequisites for Repository://Ebuild.
% Context MUST contain replaces(OldRepo://OldEbuild).
rules:update_txn_conditions(Repository://Ebuild, Context, Conditions) :-
  % 1. Compute required_use stable model for the *new* version, extend with build_with_use
  (findall(Item,
          (member(build_with_use(InnerList), Context),
           member(Item,InnerList)),
          B)),
  (memberchk(required_use(R),Context) -> true ; R = []),
  query:search(model(Model,required_use(R),build_with_use(B)),Repository://Ebuild),

  % 2. Compute + memoize dependency model (grouped), for the *new* version.
  query:memoized_search(model(dependency(MergedDeps0,install)):config?{Model},Repository://Ebuild),
  add_self_to_dep_contexts(Repository://Ebuild, MergedDeps0, MergedDeps),

  % Optional: deep update means "also update dependency packages".
  % We model this by scheduling update goals for any installed dependency package
  % that appears in the dependency model.
  ( preference:flag(deep)
  -> rules:deep_update_goals(Repository://Ebuild, MergedDeps, DeepUpdates)
  ;  DeepUpdates = []
  ),

  % 3. Pass on relevant package dependencies and constraints to prover.
  query:search([category(CNew),name(NNew),select(slot,constraint([]),SAll)], Repository://Ebuild),
  ( memberchk(CNew,['virtual','acct-group','acct-user'])
    -> Base = [ constraint(use(Repository://Ebuild):{R}),
                constraint(slot(CNew,NNew,SAll):{Ebuild})
                |DeepUpdates],
       append(Base, MergedDeps, Conditions)
    ;  Base = [ constraint(use(Repository://Ebuild):{R}),
                constraint(slot(CNew,NNew,SAll):{Ebuild}),
                Repository://Ebuild:download?{[required_use(R),build_with_use(B)]}
                |DeepUpdates],
       append(Base, MergedDeps, Conditions)
  ).

% Collect update goals for installed dependency packages from a grouped dependency model.
rules:deep_update_goals(Self, MergedDeps, DeepUpdates) :-
  ( preference:accept_keywords(K)
    -> KeywordQ = [keywords(K)]
    ;  KeywordQ = []
  ),
  findall(C-N, (member(Dep, MergedDeps), rules:dep_cn(Dep, C, N)), CN0),
  sort(CN0, CN),
  findall(NewRepo://NewEntry:update?{[replaces(OldRepo://OldEntry)]},
          ( member(C-N, CN),
            % For each dependency package, look at installed instances in the VDB repo (`pkg`)
            % (possibly multiple slots). Restricting to `pkg` avoids scanning all repos.
            query:search([repository(pkg),category(C),name(N),installed(true)], pkg://OldEntry),
            OldRepo = pkg,
            pkg://OldEntry \== Self,
            query:search(version(OldVer), pkg://OldEntry),
            % Only deep-update within the same slot if we can determine it.
            query:search(slot(Slot0), pkg://OldEntry),
            rules:canon_slot(Slot0, Slot),
            % Pick the newest acceptable candidate in that slot.
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

rules:dep_cn(grouped_package_dependency(_,C,N,_):_Action?{_Ctx}, C, N) :- !.
rules:dep_cn(grouped_package_dependency(C,N,_):_Action?{_Ctx}, C, N) :- !.
% Concrete dependency literals (already resolved to a specific entry):
%   Repo://Entry:install?{...}
%   Repo://Entry:run?{...}
%   Repo://Entry:config?{...}
% etc.
rules:dep_cn(Repo://Entry:_Action?{_Ctx}, C, N) :-
  query:search([category(C),name(N)], Repo://Entry),
  !.
rules:dep_cn(Repo://Entry:_Action, C, N) :-
  query:search([category(C),name(N)], Repo://Entry),
  !.


% Determine a package slot for planning decisions.
% If explicit slot metadata exists, use it; otherwise treat it as slot 0.
rules:entry_slot_default(Repo, Entry, Slot) :-
  ( query:search(slot(Slot0), Repo://Entry)
    -> rules:canon_slot(Slot0, Slot)
    ;  Slot = '0'
  ).

% Normalize slot values so comparisons work even when some facts use numbers and
% others use atoms.
rules:canon_slot(S0, S) :-
  ( atom(S0)   -> S = S0
  ; integer(S0) -> number_atom(S0, S)
  ; number(S0)  -> number_atom(S0, S)
  ; S = S0
  ),
  !.

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
rules:constraint_guard(constraint(blocked_cn(C,N):{ordset(Specs)}), Constraints) :-
  !,
  ( get_assoc(selected_cn(C,N), Constraints, ordset(Selected)) ->
      \+ rules:specs_violate_selected(Specs, Selected)
  ; true
  ).
rules:constraint_guard(constraint(selected_cn(C,N):{ordset(SelectedNew)}), Constraints) :-
  !,
  ( get_assoc(blocked_cn(C,N), Constraints, ordset(Specs)) ->
      \+ rules:specs_violate_selected(Specs, SelectedNew)
  ; true
  ).
rules:constraint_guard(_Other, _Constraints).

% True iff any blocker spec in Specs violates any selected instance.
%
% Current semantics:
% - strong (!!) blockers are enforced as hard conflicts (force backtracking)
% - weak (!) blockers are tracked as domain assumptions (warning), not enforced
%   during proving (to avoid search explosions).
rules:specs_violate_selected(Specs, Selected) :-
  member(blocked(Strength, Phase, O, V, SlotReq), Specs),
  Strength == strong,
  member(selected(Repo, Entry, Act, SelVer, SelSlotMeta), Selected),
  rules:action_phase(Act, Phase),
  rules:blocker_spec_matches_selected(SelVer, SelSlotMeta, Repo, Entry, O, V, SlotReq),
  !.

rules:action_phase(run, run) :- !.
rules:action_phase(install, install) :- !.
rules:action_phase(reinstall, install) :- !.
rules:action_phase(update, install) :- !.
rules:action_phase(download, install) :- !.
rules:action_phase(_Other, run).

rules:blocker_spec_matches_selected(SelVer, SelSlotMeta, Repo, Entry, O, V, SlotReq) :-
  rules:blocker_version_matches(O, V, SelVer, Repo, Entry),
  rules:blocker_slot_matches(SlotReq, SelSlotMeta, Repo, Entry).

rules:blocker_version_matches(none, _Req, _SelVer, _Repo, _Entry) :- !.
rules:blocker_version_matches(equal, Req, SelVer, _Repo, _Entry) :- !, SelVer == Req.
rules:blocker_version_matches(notequal, Req, SelVer, _Repo, _Entry) :- !, SelVer \== Req.
rules:blocker_version_matches(smaller, Req, SelVer, _Repo, _Entry) :- !, system:compare(<, SelVer, Req).
rules:blocker_version_matches(greater, Req, SelVer, _Repo, _Entry) :- !, system:compare(>, SelVer, Req).
rules:blocker_version_matches(smallerequal, Req, SelVer, _Repo, _Entry) :- !,
  ( system:compare(<, SelVer, Req) ; system:compare(=, SelVer, Req) ).
rules:blocker_version_matches(greaterequal, Req, SelVer, _Repo, _Entry) :- !,
  ( system:compare(>, SelVer, Req) ; system:compare(=, SelVer, Req) ).
rules:blocker_version_matches(Op, Req, _SelVer, Repo, Entry) :-
  % Fallback for wildcard/tilde/complex patterns: reuse query semantics.
  query:search(select(version,Op,Req), Repo://Entry).

rules:blocker_slot_matches([], _SelSlotMeta, _Repo, _Entry) :- !.
rules:blocker_slot_matches([slot(S)], SelSlotMeta, _Repo, _Entry) :- !,
  memberchk(slot(S), SelSlotMeta).
rules:blocker_slot_matches([slot(S),subslot(Ss)], SelSlotMeta, _Repo, _Entry) :- !,
  memberchk(slot(S), SelSlotMeta),
  memberchk(subslot(Ss), SelSlotMeta).
rules:blocker_slot_matches([slot(S),equal], SelSlotMeta, _Repo, _Entry) :- !,
  memberchk(slot(S), SelSlotMeta).
rules:blocker_slot_matches([slot(S),subslot(Ss),equal], SelSlotMeta, _Repo, _Entry) :- !,
  memberchk(slot(S), SelSlotMeta),
  memberchk(subslot(Ss), SelSlotMeta).
rules:blocker_slot_matches(SlotReq, _SelSlotMeta, Repo, Entry) :-
  % Fallback for any_same_slot/any_different_slot or future extensions.
  query:search(select(slot,constraint(SlotReq), _), Repo://Entry).

% -----------------------------------------------------------------------------
%  Helper: blocker uninstall goals
% -----------------------------------------------------------------------------
%
% Implement weak/strong blockers efficiently by querying the installed VDB repo
% (`pkg`) for matching instances and scheduling uninstall actions for them.
%
% Notes:
% - This enforces "not installed at end of transaction" for installed packages.
% - Co-installation prevention (strong blockers vs planned installs) can be
%   validated later using the planned package set without adding prover overhead.

% Extract blocker specs from a grouped dependency list.
% Specs is an ordset of blocked(Strength,Phase,O,V,SlotReq) terms.
rules:grouped_blocker_specs(Strength, Phase, C, N, PackageDeps, Specs) :-
  findall(blocked(Strength, Phase, O, V, SlotReq),
          ( member(package_dependency(Phase, Strength, C, N, O, V, SlotReq, _U), PackageDeps) ),
          Specs0),
  sort(Specs0, Specs).

% Find an installed entry for the given category/name, even if it isn't present
% as an ordered_entry (e.g. when the installed version no longer exists in the
% active repository set).
rules:installed_entry_cn(C, N, pkg, Entry) :-
  % The installed package database is represented by the VDB repository instance
  % named `pkg`. Prefer using its structured facts instead of parsing Entry IDs
  % with atom_concat/sub_atom (which is extremely expensive at scale).
  query:search([repository(pkg),category(C),name(N),installed(true)], pkg://Entry),
  !.