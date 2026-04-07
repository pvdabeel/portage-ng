/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> TARGET
Target-level query resolution and candidate-level action resolution helpers.

Target resolution (target: prefix) turns a user query into a concrete candidate:

  - `resolve_candidate/2`           — query → visible candidate (with fallback)
  - `resolve_installed_candidate/2`  — query → installed candidate (pkg)

Candidate resolution (candidate: prefix) resolves proof conditions for a
concrete candidate.  The rule/2 clauses in rules.pl delegate here:

  - `candidate:resolve(R://E:fetchonly?{Ctx}, Conds)`
  - `candidate:resolve(R://E:install?{Ctx}, Conds)`
  - `candidate:resolve(R://E:run?{Ctx}, Conds)`
  - `candidate:resolve(R://E:update?{Ctx}, Conds)`
  - `candidate:resolve(weak_blocker(C,N,PackageDeps)?{Ctx}, Conds)`
  - `candidate:resolve(strong_blocker(C,N,PackageDeps)?{Ctx}, Conds)`
  - `candidate:resolve(grouped_dep(C,N,PackageDeps):Action?{Ctx}, Conds)`

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
      ( query:search(Q, Repository://Ebuild),
        candidate:entry_has_accepted_keyword(Repository://Ebuild),
        \+ query:search(masked(true), Repository://Ebuild),
        \+ candidate:license_masked(Repository://Ebuild)
      ; query:search(Q, Repository://Ebuild)
      )
  ; query:search(Q, Repository://Ebuild)
  ).


%! target:resolve_installed_candidate(+Q, -Repository://Ebuild) is nondet.
%
% Resolves a candidate from the installed packages repository (pkg).

target:resolve_installed_candidate(Q, pkg://Ebuild) :-
  query:search(Q, pkg://Ebuild).


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

target:deep_update_goals(Self, MergedDeps, DeepUpdates) :-
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

target:dep_cn(grouped_package_dependency(_,C,N,_):_Action?{_Ctx}, C, N) :- !.
target:dep_cn(grouped_package_dependency(C,N,_):_Action?{_Ctx}, C, N) :- !.
target:dep_cn(Repo://Entry:_Action?{_Ctx}, C, N) :-
  query:search([category(C),name(N)], Repo://Entry),
  !.
target:dep_cn(Repo://Entry:_Action, C, N) :-
  query:search([category(C),name(N)], Repo://Entry),
  !.


% =============================================================================
%  USE conditional resolution
% =============================================================================

%! candidate:resolve(use_conditional(+Deps):+Action?{+Context}, -Conditions)
%
% Produces the dependency sub-goals for an active USE conditional group,
% annotated with the current action and context.

candidate:resolve(use_conditional(Deps):Action?{Context}, Conditions) :-
  findall(D:Action?{Context}, member(D, Deps), Conditions0),
  sort(Conditions0, Conditions).


% =============================================================================
%  REQUIRED_USE validation
% =============================================================================

%! candidate:resolve(required_use(+GroupType, +Deps):validate?{+Context}, -Conditions)
%
% Validates a REQUIRED_USE choice constraint against effective USE.
% Returns [] when satisfied, or an assumed(conflict(...)) when violated.

candidate:resolve(required_use(exactly_one_of, Deps):validate?{Ctx}, []) :-
  findall(1, (member(D, Deps), use:required_use_term_satisfied(Ctx, D)), Ones),
  length(Ones, 1),
  !.
candidate:resolve(required_use(exactly_one_of, Deps):validate?{_},
                  [assumed(conflict(required_use, exactly_one_of_group(Deps)))]).

candidate:resolve(required_use(at_most_one_of, Deps):validate?{Ctx}, []) :-
  findall(1, (member(D, Deps), use:required_use_term_satisfied(Ctx, D)), Ones),
  length(Ones, N),
  N =< 1,
  !.
candidate:resolve(required_use(at_most_one_of, Deps):validate?{_},
                  [assumed(conflict(required_use, at_most_one_of_group(Deps)))]).

candidate:resolve(required_use(any_of, Deps):validate?{Ctx}, []) :-
  member(D, Deps),
  use:required_use_term_satisfied(Ctx, D),
  !.
candidate:resolve(required_use(any_of, Deps):validate?{_},
                  [assumed(conflict(required_use, any_of_group(Deps)))]).


% =============================================================================
%  Choice group resolution
% =============================================================================

%! candidate:resolve(choice_group(+Deps):+Action?{+Context}, -Conditions)
%
% Resolve phase: pick the best alternative, prove it via rule/2, and
% reject choices that degrade into domain assumptions.

candidate:resolve(choice_group(Deps):Action?{Context}, Conditions) :-
  candidate:prioritize_deps_keep_all(Deps, Context, SortedDeps),
  member(D0, SortedDeps),
  candidate:group_choice_dep(D0, D),
  rules:rule(D:Action?{Context}, Conditions0),
  ( candidate:any_of_reject_assumed_choice(D, Conditions0) ->
      fail
  ; Conditions = Conditions0
  ).


% =============================================================================
%  Blocker resolution
% =============================================================================

%! candidate:resolve(weak_blocker(+C, +N, +PackageDeps)?{+Context}, -Conditions)
%
% Resolves a weak blocker group: builds provenance constraints and
% blocker assumptions from the package_dependency terms in PackageDeps.

candidate:resolve(weak_blocker(C,N,PackageDeps)?{Context}, Conditions) :-
  candidate:make_blocker_constraint(C, N, PackageDeps, Context, ConstraintConds),
  candidate:make_blocker_assumption(Context, PackageDeps, C, N, AssumptionConds),
  append(ConstraintConds, AssumptionConds, Conditions).


%! candidate:resolve(strong_blocker(+C, +N, +PackageDeps)?{+Context}, -Conditions)
%
% Resolves a strong blocker group: partitions PackageDeps into
% unconditional (U == [], enforceable as hard constraints) and
% USE-conditional (U \== [], recorded as assumptions). When
% assume_blockers is active, all are assumed.

candidate:resolve(strong_blocker(C,N,PackageDeps)?{Context}, Conditions) :-
  ( candidate:assume_blockers ->
      candidate:resolve(weak_blocker(C,N,PackageDeps)?{Context}, Conditions)
  ;
    partition(candidate:is_unconditional_dep, PackageDeps, Unconditional, Conditional),
    candidate:make_blocker_assumption(Context, Conditional, C, N, AssumptionConds),
    ( Unconditional == [] ->
        Conditions = AssumptionConds
    ; candidate:make_blocker_constraint(C, N, Unconditional, Context, ConstraintConds),
      candidate:make_enforced_specs(Unconditional, EnforcedSpecs),
      append([constraint(blocked_cn(C,N):{ordset(EnforcedSpecs)})|ConstraintConds], AssumptionConds, Conditions)
    )
  ).


% =============================================================================
%  Grouped-dependency resolution
% =============================================================================

%! candidate:resolve(grouped_dep(+C,+N,+PackageDeps):+Action?{+Context}, -Conditions)
%
% Multi-clause orchestrator for regular (non-blocker) grouped
% dependencies. Resolution paths, tried in order:
%   1. Self-satisfied (runtime self-dependency)
%   2. Keep-installed (existing VDB entry satisfies all constraints)
%   3. Candidate resolution (select, verify, assemble proof conditions)
%   4. Learning / reprove (narrow parent domain or request reprove)
%   5. Assumption fallback (mark as assumed with diagnostics)

candidate:resolve(grouped_dep(C,N,_PackageDeps):run?{Context}, []) :-
  memberchk(self(SelfRepo://SelfEntry), Context),
  query:search([category(C),name(N)], SelfRepo://SelfEntry),
  !.

candidate:resolve(grouped_dep(C,N,PackageDeps):Action?{Context}, []) :-
  \+ preference:flag(emptytree),
  candidate:augment_package_deps_with_self_rdepend(Action, C, N, Context, PackageDeps, PackageDeps1),
  candidate:grouped_dep_keep_installed(Action, C, N, PackageDeps1, Context),
  !.

candidate:resolve(grouped_dep(C,N,PackageDeps):Action?{Context}, Conditions) :-
  candidate:augment_package_deps_with_self_rdepend(Action, C, N, Context, PackageDeps, PackageDeps1),
  candidate:grouped_dep_select_and_build(Action, C, N, PackageDeps1, Context, Conditions).

candidate:resolve(grouped_dep(C,N,PackageDeps):_Action?{Context}, _) :-
  candidate:augment_package_deps_with_self_rdepend(_, C, N, Context, PackageDeps, PackageDeps1),
  \+ memo:requse_violation_(C, N, _),
  candidate:maybe_learn_parent_narrowing(C, N, PackageDeps1, Context),
  fail.
candidate:resolve(grouped_dep(C,N,PackageDeps):Action?{Context}, _) :-
  candidate:augment_package_deps_with_self_rdepend(Action, C, N, Context, PackageDeps, PackageDeps1),
  \+ memo:requse_violation_(C, N, _),
  candidate:maybe_request_grouped_dep_reprove(Action, C, N, PackageDeps1, Context),
  fail.

candidate:resolve(grouped_dep(C,N,PackageDeps):Action?{Context}, Conditions) :-
  candidate:augment_package_deps_with_self_rdepend(Action, C, N, Context, PackageDeps, PackageDeps1),
  candidate:grouped_dep_build_assumption(Action, C, N, PackageDeps1, PackageDeps, Context, Conditions).


% =============================================================================
%  Depclean resolution
% =============================================================================

%! candidate:resolve(grouped_dep(+C,+N,+PackageDeps):depclean?{+Ctx}, -Conditions)
%
% Follows the depclean closure through installed packages only. Finds an
% installed entry satisfying the version/slot constraints and maps it
% back to a repository entry for continued traversal. Produces [] when
% nothing installed matches.

candidate:resolve(grouped_dep(C,N,PackageDeps):depclean?{_}, Conditions) :-
  candidate:merge_slot_restriction(run, C, N, PackageDeps, SlotReq),
  ( query:search([name(N),category(C),installed(true)], pkg://Installed),
    candidate:query_search_slot_constraint(SlotReq, pkg://Installed, _),
    candidate:installed_entry_satisfies_package_deps(run, C, N, PackageDeps, pkg://Installed),
    query:search(version(V), pkg://Installed),
    preference:accept_keywords(K),
    query:search([select(repository,notequal,pkg),category(C),name(N),keywords(K),version(V)],
                 Repo://Installed)
  ->
    Conditions = [Repo://Installed:depclean?{[]}]
  ;
    Conditions = []
  ).


%! candidate:resolve(+R://+E:depclean?{+Context}, -Conditions)
%
% Computes the runtime dependency model for an installed ebuild and
% rewrites all dependency literals as :depclean sub-goals. Falls back
% to [] when the model cannot be computed.

candidate:resolve(Repository://Ebuild:depclean?{Context}, Conditions) :-
  ( query:search(model(Model,required_use(_),build_with_use(_)), Repository://Ebuild),
    query:memoized_search(model(dependency(MergedDeps0,run)):config?{Model}, Repository://Ebuild),
    dependency:add_self_to_dep_contexts(Repository://Ebuild, MergedDeps0, MergedDeps),
    target:depclean_rewrite_deps(MergedDeps, Context, Conditions)
  -> true
  ;  Conditions = []
  ).


% =============================================================================
%  Update resolution
% =============================================================================

%! candidate:resolve(+Literal, -Conditions)
%
% Multi-clause resolution for :update actions:
%
% 1. Installed entry without replaces: find a newer version in the same slot
%    and schedule a transactional update on the replacement.
% 2. Not-installed entry without replaces: try same-slot replacement of an
%    older installed version, otherwise fall back to plain install.
% 3. Already-installed entry with no newer version: no-op.
% 4. Transactional update (replaces in context): resolve dependencies and
%    assemble the full condition set (USE + slot + download + deps).

candidate:resolve(Repository://Ebuild:update?{Context}, Conditions) :-
  \+ memberchk(replaces(_), Context),
  \+ preference:flag(emptytree),
  preference:accept_keywords(K),
  query:search([category(Category),name(Name),version(VersionInstalled),installed(true)],
               Repository://Ebuild),
  ( query:search(slot(SlotInstalled), Repository://Ebuild)
    -> query:search(latest([name(Name),category(Category),keywords(K),slot(SlotInstalled),
                            select(version,greater,VersionInstalled)]),
                    LatestRepo://LatestEbuild)
    ;  query:search(latest([name(Name),category(Category),keywords(K),
                            select(version,greater,VersionInstalled)]),
                    LatestRepo://LatestEbuild)
  ),
  !,
  feature_unification:unify([replaces(Repository://Ebuild)], Context, Ctx1),
  Conditions = [LatestRepo://LatestEbuild:update?{Ctx1}].

candidate:resolve(Repository://Ebuild:update?{Context}, Conditions) :-
  \+ memberchk(replaces(_), Context),
  \+ preference:flag(emptytree),
  query:search([category(Category),name(Name)], Repository://Ebuild),
  \+ candidate:installed(Repository://Ebuild),
  ( candidate:entry_slot_default(Repository, Ebuild, SlotNew),
    candidate:installed_entry_cn(Category, Name, OldRepo, OldEbuild),
    ( query:search(slot(SlotOld0), OldRepo://OldEbuild)
      -> candidate:canon_slot(SlotOld0, SlotOld)
      ;  SlotOld = SlotNew
    ),
    SlotOld == SlotNew
  -> feature_unification:unify([replaces(OldRepo://OldEbuild)], Context, UpdCtx),
     candidate:resolve(Repository://Ebuild:update?{UpdCtx}, Conditions)
  ;  Conditions = [Repository://Ebuild:install?{Context}]
  ),
  !.

candidate:resolve(Repository://Ebuild:update?{_Context}, []) :-
  candidate:installed(Repository://Ebuild),
  !.

candidate:resolve(Repository://Ebuild:update?{Context}, Conditions) :-
  memberchk(replaces(_), Context),
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
%  Downgrade resolution
% =============================================================================

%! candidate:resolve(+Literal, -Conditions)
%
% Multi-clause resolution for :downgrade actions:
%
% 1. With replaces in context: delegates to the transactional update resolver.
% 2. Already-installed version: no-op.
% 3. Without replaces: falls back to plain install.

candidate:resolve(Repository://Ebuild:downgrade?{Context}, Conditions) :-
  memberchk(replaces(_), Context),
  !,
  candidate:resolve(Repository://Ebuild:update?{Context}, Conditions).

candidate:resolve(Repository://Ebuild:downgrade?{_Context}, []) :-
  candidate:installed(Repository://Ebuild),
  !.

candidate:resolve(Repository://Ebuild:downgrade?{Context}, Conditions) :-
  !,
  Conditions = [Repository://Ebuild:install?{Context}].


% =============================================================================
%  Upgrade resolution (cross-slot)
% =============================================================================

%! candidate:resolve(+Literal, -Conditions)
%
% Multi-clause resolution for :upgrade actions (cross-slot transitions):
%
% 1. Installed entry without replaces: find a newer entry in a different
%    (higher) slot and schedule a transactional upgrade on the replacement.
% 2. Not-installed entry without replaces: locate the installed entry in
%    a different slot and set up the cross-slot replacement, or fall back
%    to plain install if nothing is installed.
% 3. Already-installed entry with no higher slot available: no-op.
% 4. Transactional upgrade (replaces in context): delegates to the update
%    resolver for dependency assembly.

candidate:resolve(Repository://Ebuild:upgrade?{Context}, Conditions) :-
  \+ memberchk(replaces(_), Context),
  \+ preference:flag(emptytree),
  preference:accept_keywords(K),
  query:search([category(Category),name(Name),installed(true)],
               Repository://Ebuild),
  candidate:entry_slot_default(Repository, Ebuild, SlotInstalled),
  query:search(latest([name(Name),category(Category),keywords(K),
                       select(slot,greater,SlotInstalled)]),
               LatestRepo://LatestEbuild),
  !,
  feature_unification:unify([replaces(Repository://Ebuild)], Context, Ctx1),
  Conditions = [LatestRepo://LatestEbuild:upgrade?{Ctx1}].

candidate:resolve(Repository://Ebuild:upgrade?{Context}, Conditions) :-
  \+ memberchk(replaces(_), Context),
  \+ preference:flag(emptytree),
  query:search([category(Category),name(Name)], Repository://Ebuild),
  \+ candidate:installed(Repository://Ebuild),
  candidate:entry_slot_default(Repository, Ebuild, SlotNew),
  ( candidate:installed_entry_cn(Category, Name, OldRepo, OldEbuild),
    candidate:entry_slot_default(OldRepo, OldEbuild, SlotOld),
    SlotOld \== SlotNew
  -> feature_unification:unify([replaces(OldRepo://OldEbuild)], Context, UpdCtx),
     candidate:resolve(Repository://Ebuild:upgrade?{UpdCtx}, Conditions)
  ;  Conditions = [Repository://Ebuild:install?{Context}]
  ),
  !.

candidate:resolve(Repository://Ebuild:upgrade?{_Context}, []) :-
  candidate:installed(Repository://Ebuild),
  !.

candidate:resolve(Repository://Ebuild:upgrade?{Context}, Conditions) :-
  memberchk(replaces(_), Context),
  !,
  candidate:resolve(Repository://Ebuild:update?{Context}, Conditions).


% -----------------------------------------------------------------------------
%  Download resolution
% -----------------------------------------------------------------------------

%! candidate:resolve(+Literal, -Conditions) is nondet.
%
% Resolves the :download action.  Goal-expanded at compile time to
% featureterm:get(after, Context, Conditions).

candidate:resolve(_Repository://_Ebuild:download?{Context}, Conditions) :-
  featureterm:get(after, Context, Conditions).


% -----------------------------------------------------------------------------
%  Fetchonly resolution
% -----------------------------------------------------------------------------

%! candidate:resolve(+Literal, -Conditions) is nondet.
%
% Resolves the :fetchonly action for a candidate ebuild: computes
% REQUIRED_USE model, dependency closure (fetchonly phase), and
% assembles proof conditions.  Virtual/acct packages skip the download.

candidate:resolve(Repository://Ebuild:fetchonly?{Context}, Conditions) :-
  query:search([category(C),name(N),select(slot,constraint([]),S)], Repository://Ebuild),
  use:context_build_with_use_state(Context, B),
  ( memberchk(required_use:R, Context) -> true ; true ),
  query:search(model(Model, required_use(R), build_with_use(B)), Repository://Ebuild),
  ( query:memoized_search(model(dependency(MergedDeps0, fetchonly)):config?{Model}, Repository://Ebuild) ->
      dependency:add_self_to_dep_contexts(Repository://Ebuild, MergedDeps0, MergedDeps),
      ( memberchk(C, ['virtual','acct-group','acct-user']) ->
          Conditions = [constraint(use(Repository://Ebuild):{R}),
                        constraint(slot(C,N,S):{Ebuild})
                        |MergedDeps]
      ;   Conditions = [constraint(use(Repository://Ebuild):{R}),
                        constraint(slot(C,N,S):{Ebuild}),
                        Repository://Ebuild:download?{R}
                        |MergedDeps]
      )
  ; feature_unification:unify([issue_with_model(explanation)], Context, Ctx1),
    Conditions = [assumed(Repository://Ebuild:install?{Ctx1})]
  ).


% -----------------------------------------------------------------------------
%  Install resolution
% -----------------------------------------------------------------------------

%! candidate:resolve(+Literal, -Conditions) is nondet.
%
% Resolves the :install action for a candidate ebuild: computes
% REQUIRED_USE model, dependency closure, and assembles proof conditions.

candidate:resolve(Repository://Ebuild:install?{Context}, Conditions) :-
  featureterm:get_after_with_mode(Context, After, AfterForDeps, Context1),
  query:search([category(C),name(N),select(slot,constraint([]),S)], Repository://Ebuild),
  query:search(version(Ver), Repository://Ebuild),
  Selected = constraint(selected_cn(C,N):{ordset([selected(Repository,Ebuild,install,Ver,S)])}),
  candidate:resolve_required_use(install, C, N, Repository://Ebuild, Context1, R, BResolved, Model),
  ( candidate:install_dep_model(Repository://Ebuild, Model, AfterForDeps, install,
                             Selected, C, N, S, R, BResolved, After, Conditions)
  ; feature_unification:unify([issue_with_model(explanation)], Context1, Ctx1),
    Conditions = [assumed(Repository://Ebuild:install?{Ctx1})]
  ).


% -----------------------------------------------------------------------------
%  Run resolution
% -----------------------------------------------------------------------------

%! candidate:resolve(+Literal, -Conditions) is nondet.
%
% Resolves the :run action for a candidate ebuild: computes REQUIRED_USE
% model, determines update/install action, tags suggestions, and assembles
% proof conditions.

candidate:resolve(Repository://Ebuild:run?{Context}, Conditions) :-
  featureterm:get_after_with_mode(Context, After, AfterForDeps, Context1),
  query:search([category(C),name(N),select(slot,constraint([]),S)], Repository://Ebuild),
  query:search(version(Ver), Repository://Ebuild),
  Selected = constraint(selected_cn(C,N):{ordset([selected(Repository,Ebuild,run,Ver,S)])}),
  candidate:resolve_required_use(run, C, N, Repository://Ebuild, Context1, R, BResolved, Model),
  ( candidate:run_dep_model(Repository://Ebuild, Model, AfterForDeps, run,
                         Selected, C, N, S, R, BResolved, After, Context1, Conditions)
  ; feature_unification:unify([issue_with_model(explanation)], Context1, Ctx1),
    Conditions = [assumed(Repository://Ebuild:run?{Ctx1})]
  ).


% -----------------------------------------------------------------------------
%  Install: dependency model helper
% -----------------------------------------------------------------------------

%! candidate:install_dep_model(+Entry, +Model, +AfterForDeps, +Phase, +Selected, +C, +N, +S, +R, +BResolved, +After, -Conditions) is semidet.
%
% Computes and assembles the dependency model for the :install proof.
% The model-fallback assumption in resolve_install only wraps this step.

candidate:install_dep_model(Repository://Ebuild, Model, AfterForDeps, install,
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
  featureterm:add_after_condition(After, AfterForDeps, Conditions0, Conditions).


% -----------------------------------------------------------------------------
%  Run: dependency model helper
% -----------------------------------------------------------------------------

%! candidate:run_dep_model(+Entry, +Model, +AfterForDeps, +Phase, +Selected, +C, +N, +S, +R, +BResolved, +After, +Context, -Conditions) is semidet.
%
% Computes and assembles the dependency model for the :run proof.
% The model-fallback assumption in resolve_run only wraps this step.

candidate:run_dep_model(Repository://Ebuild, Model, AfterForDeps, run,
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
  featureterm:add_after_condition(After, AfterForDeps, Conditions0, Conditions).


% -----------------------------------------------------------------------------
%  Shared: REQUIRED_USE resolution
% -----------------------------------------------------------------------------

%! candidate:resolve_required_use(+Phase, +C, +N, +Entry, +Context, -R, -BResolved, -Model) is semidet.
%
% Computes the REQUIRED_USE stable model, verifies BWU cross-dep conflicts,
% and resolves build_with_use against REQUIRED_USE. Fails (recording the
% violation) when REQUIRED_USE cannot be satisfied.

candidate:resolve_required_use(_Phase, C, N, Repository://Ebuild, Context1, R, BResolved, Model) :-
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