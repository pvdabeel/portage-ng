/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> DEPENDENCY
Package dependency context management for the rules engine.

This module provides predicates that annotate dependency literals with
provenance information (self-references), manage slot context propagation
across dependency edges, and handle build-with-use state threading.

The rule/2 clauses in rules.pl call into this module when they need to:

  1. Tag dependency literals with `self(Repo://Entry)` so downstream rules
     can distinguish self-dependencies from external ones.

  2. Propagate slot locks into the dependency context so that `:=`
     (rebuild-on-slot-change) semantics work correctly.

  3. Thread `build_with_use` state from bracketed USE constraints
     (e.g. `dev-libs/foo[bar]`) into the child dependency context.

  4. Collect USE requirements from dependency edges into the format
     expected by the prover's assumption mechanism.

== Key design constraints ==

  * Self-context (`self/1`): at most one `self/1` term is kept in any
    context to prevent context growth along deep dependency chains (which
    would defeat memoization).

  * Build-with-use: per-package state.  A child's build_with_use must NOT
    inherit the parent's; only the directives from the current dependency
    edge are applied.  This prevents parent USE state from leaking into
    dependencies and causing Portage-divergent rebuilds.
*/

:- module(dependency, []).


% =============================================================================
%  Dependency context management
% =============================================================================

%! dependency:add_self_to_dep_contexts(+Self, +Deps0, -Deps)
%
% Annotates every dependency literal in Deps0 with `self(Self)` so that
% downstream rules can identify the parent ebuild. Keeps at most one
% `self/1` term per context to prevent growth along chains.

add_self_to_dep_contexts(_Self, [], []) :- !.
add_self_to_dep_contexts(Self, [D0|Rest0], [D|Rest]) :-
  ( D0 = Term:Action?{Ctx} ->
      ctx_set_self(Ctx, Self, Ctx1),
      D = Term:Action?{Ctx1}
  ; D = D0
  ),
  add_self_to_dep_contexts(Self, Rest0, Rest).

%! dependency:ctx_set_self(+Ctx0, +Self, -Ctx)
%
% Replaces or inserts a `self(Self)` term in context Ctx0.
% If Ctx0 already contains a self/1 term it is replaced (not stacked).

ctx_set_self(Ctx0, Self, Ctx) :-
  ( is_list(Ctx0) ->
      ( selectchk(self(_), Ctx0, Ctx1) -> true ; Ctx1 = Ctx0 ),
      Ctx = [self(Self)|Ctx1]
  ; Ctx = [self(Self)]
  ),
  !.


% =============================================================================
%  USE requirement collection for dependency edges
% =============================================================================

%! dependency:collect_use_requirements(+UseDeps, -Requirements)
%
% Converts a list of `use(Directive, Default)` terms into the prover's
% assumption format: `required(Use)` for enable directives,
% `naf(required(Use))` for disable directives.

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

%! dependency:process_use(+ParentContext, +UseDirective, +Acc, -AccOut)
%
% Fold helper: processes a single USE dependency directive and accumulates
% assumption terms for the dependency context.
%
% CRITICAL: this predicate must be deterministic. Non-determinism here
% causes massive backtracking explosions when build-with-use context is
% propagated through dependency cycles.

process_use(ParentContext, use(Directive, Default), Acc, AccOut) :-
    !,
    use:use_dep_requirement(ParentContext, Directive, Default, Requirement),
    ( Requirement = requirement(enable, Use, _Default) ->
        AccOut = [required(Use), assumed(Use)|Acc]
    ; Requirement = requirement(disable, Use, _Default) ->
        AccOut = [naf(required(Use)), assumed(minus(Use))|Acc]
    ; AccOut = Acc
    ).

process_use(_ParentContext, _Other, Acc, Acc) :- !.


% =============================================================================
%  Slot context propagation
% =============================================================================

%! dependency:process_slot(+SlotReq, +SlotMeta, +C, +N, +RepoEntry, +Ctx0, -Ctx)
%
% Propagates a slot lock into the dependency context after a candidate has
% been selected. Explicit slot requirements (`[slot(_)|_]`) and
% `any_different_slot` are not locked: explicit slots allow multi-slot
% coexistence (e.g. Ruby :3.2 + :3.3) and `any_different_slot` is by
% definition not lockable.

process_slot([any_different_slot], _, _, _, _, Context, Context) :- !.
process_slot([slot(_)|_], _SlotMeta, _C, _N, _Repository://_Candidate, Context, Context) :- !.
process_slot(_, Slot, C, N, _Repository://Candidate, Context0, Context) :-
  feature_unification:unify([slot(C, N, Slot):{Candidate}], Context0, Context).


% =============================================================================
%  Build-with-use context propagation
% =============================================================================

%! dependency:process_build_with_use(+Directives, +Ctx0, -Ctx, -Conditions, +Candidate)
%
% Threads bracketed USE constraints from a dependency edge into the child
% context. Strips any inherited build_with_use from the parent context
% and builds fresh per-package USE state from the current directives only.
%
% IMPORTANT (correctness): build_with_use is per-package state. The child
% must not inherit the parent's build_with_use: otherwise parent USE state
% (e.g. gui/widgets, abi_x86_*) leaks into the dependency and causes
% Portage-divergent rebuilds.
%
% IMPORTANT (performance): at most one build_with_use term is kept in the
% context to prevent growth that defeats cycle detection/memoization.

process_build_with_use(Directives, Context0, Context, Conditions, Candidate) :-
    ( select(build_with_use:_, Context0, Context1) -> true ; Context1 = Context0 ),
    use:empty_use_state(PrevState),
    foldl(use:process_bwu_directive(Context0), Directives, PrevState, State0),
    use:normalize_build_with_use(State0, State),
    ( State = use_state([], []) ->
        Context = Context1
    ; feature_unification:unify([build_with_use:State], Context1, Context)
    ),
    build_with_use_constraints(Directives, Conditions, Candidate).

%! dependency:build_with_use_constraints(+Directives, -Conditions, +Candidate)
%
% Generates global constraint literals from build-with-use directives.
% Currently a no-op (returns []) because Portage-style USE deps are
% per-package constraints modelled via context, not global constraints.

build_with_use_constraints(_, [], _) :- !.


% =============================================================================
%  PDEPEND goal collection from a completed plan
% =============================================================================

%! dependency:pdepend_goals_from_plan(+Plan, -Goals)
%
% Walk the plan's merge anchors, look up each entry's PDEPEND metadata,
% build dependency goals from it, and filter out goals already satisfied
% by the current merge set.

pdepend_goals_from_plan(Plan, Goals) :-
  plan_merged_cn_sets(Plan, MergedCNSet, MergedCNSlotSet),
  findall(Gs,
          ( planner:plan_merge_anchor(Plan, Repo://Entry, AnchorCore, ActionCtx),
            use:context_build_with_use_state(ActionCtx, B),
            ModelKey = [build_with_use:B],
            ( cache:entry_metadata(Repo, Entry, pdepend, _) ->
                query:memoized_search(model(dependency(Pdeps0, pdepend)):config?{ModelKey}, Repo://Entry),
                dependency:add_self_to_dep_contexts(Repo://Entry, Pdeps0, Pdeps1),
                rules:add_after_only_to_dep_contexts(AnchorCore, Pdeps1, Pdeps),
                filter_redundant_pdepend_goals(MergedCNSet, MergedCNSlotSet, Pdeps, Gs)
            ; Gs = []
            )
          ),
          Nested),
  append(Nested, Flat0),
  sort(Flat0, Goals).


%! dependency:plan_merged_cn_sets(+Plan, -CNSet, -CNSlotSet)
%
% Build fast assoc-based lookup sets for category/name pairs (and
% category/name/slot triples) already being merged in the plan.

plan_merged_cn_sets(Plan, CNSet, CNSlotSet) :-
  findall(key(C,N),
          ( planner:plan_merge_anchor(Plan, Repo://Entry, _AnchorCore, _Ctx),
            query:search([category(C),name(N)], Repo://Entry)
          ),
          CNKeys0),
  sort(CNKeys0, CNKeys),
  scheduler:assoc_set_from_list(CNKeys, CNSet),
  findall(key(C,N,Slot),
          ( planner:plan_merge_anchor(Plan, Repo://Entry, _AnchorCore2, _Ctx2),
            query:search([category(C),name(N)], Repo://Entry),
            candidate:entry_slot_default(Repo, Entry, Slot)
          ),
          CNSlotKeys0),
  sort(CNSlotKeys0, CNSlotKeys),
  scheduler:assoc_set_from_list(CNSlotKeys, CNSlotSet).


%! dependency:filter_redundant_pdepend_goals(+CNSet, +CNSlotSet, +Goals0, -Goals)
%
% Drop PDEPEND goals whose category/name (or category/name/slot) is
% already present in the current plan's merge set.

filter_redundant_pdepend_goals(_CNSet, _CNSlotSet, [], []) :- !.

filter_redundant_pdepend_goals(CNSet, CNSlotSet, Goals0, Goals) :-
  ( is_list(Goals0) ->
      include(dependency:pdepend_goal_needed(CNSet, CNSlotSet), Goals0, Goals)
  ; Goals = Goals0
  ),
  !.


%! dependency:pdepend_goal_needed(+CNSet, +CNSlotSet, +Goal)
%
% Succeeds when Goal is not already covered by the plan's merge set.

pdepend_goal_needed(CNSet, CNSlotSet, Goal) :-
  ( target:dep_cn(Goal, C, N) ->
      ( goal_specific_slot(Goal, Slot) ->
          \+ get_assoc(key(C,N,Slot), CNSlotSet, _)
      ; \+ get_assoc(key(C,N), CNSet, _)
      )
  ; true
  ).


%! dependency:goal_specific_slot(+Goal, -Slot)
%
% Extract an explicit slot requirement from a grouped dependency goal.
% A goal is only dropped if the plan already merges the same (C,N,Slot).

goal_specific_slot(grouped_package_dependency(_,C,N,PackageDeps):_Action?{_Ctx}, Slot) :-
  member(package_dependency(_Phase,_Strength,C,N,_O,_V,SlotReq,_U), PackageDeps),
  is_list(SlotReq),
  member(slot(S0), SlotReq),
  candidate:canon_slot(S0, Slot),
  !.

goal_specific_slot(grouped_package_dependency(C,N,PackageDeps):_Action?{_Ctx}, Slot) :-
  member(package_dependency(_Phase,_Strength,C,N,_O,_V,SlotReq,_U), PackageDeps),
  is_list(SlotReq),
  member(slot(S0), SlotReq),
  candidate:canon_slot(S0, Slot),
  !.
