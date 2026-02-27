/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> PLANNER
The Planner creates a plan based on a Proof.

Two-phase planner aligned with PMS/Portage/Paludis dependency semantics:

  Phase 1 – Normal wave planning (Kahn's algorithm).
            All non-constraint deps are hard ordering constraints.

  Phase 2 – Relaxation pass.
            For rules left in the remainder, recalculate dep counts ignoring
            :run deps (RDEPEND / PDEPEND).  Build relaxed triggers and run
            another wave-planning loop.  This mirrors Portage's progressive
            cycle-breaking (ignore runtime_post, then runtime edges) and
            Paludis's insight that runtime-only cycles are not ordering-
            significant.

The net effect: build-time deps (DEPEND/BDEPEND) remain hard ordering edges
that are never relaxed.  Runtime deps (RDEPEND/PDEPEND) are honoured when
acyclic but relaxed when they cause cycles, matching PMS semantics.
*/

:- module(planner, []).

% =============================================================================
%  PLANNER declarations
% =============================================================================

%! planner:plan(+ProofAVL, +TriggersAVL, +PlannedHeadsIn, -EnrichedPlan)
%
% Creates a plan based on a Proof.

planner:plan(ProofAVL, TriggersAVL, PlannedHeadsIn, EnrichedPlan) :-
    planner:plan(ProofAVL, TriggersAVL, PlannedHeadsIn, EnrichedPlan, _RemainderRules).


%! planner:plan(+ProofAVL, +TriggersAVL, +PlannedHeadsIn, -EnrichedPlan, -RemainderRules)
%
% Like `planner:plan/4`, but also returns `RemainderRules`: rules whose heads
% could not be scheduled by the wave planner (typically due to cycles).
%
% Uses two-phase planning: normal planning followed by a relaxation pass
% that ignores :run deps as ordering constraints (matching Portage/Paludis
% semantics for runtime dependency cycles).
%
planner:plan(ProofAVL, TriggersAVL, PlannedHeadsIn, EnrichedPlan, RemainderRules) :-
    % Phase 1: Normal planning (all deps are ordering constraints)
    plan_init_from_proof(ProofAVL, PlannedHeadsIn, DepCounts0, ReadyQueue0),
    (   ReadyQueue0 \= [] ->
        update_planned_set(ReadyQueue0, PlannedHeadsIn, PlannedHeadsInit),
        plan_loop([ReadyQueue0], DepCounts0, TriggersAVL, ProofAVL, PlannedHeadsInit,
                  [], RevPlan1, DepCounts1, PlannedHeads1),
        reverse(RevPlan1, Plan1)
    ;   Plan1 = [],
        DepCounts1 = DepCounts0,
        PlannedHeads1 = PlannedHeadsIn
    ),
    % Phase 2: Relaxation (ignore :run deps as ordering constraints)
    plan_relaxation(ProofAVL, PlannedHeads1, RelaxedPlan, PlannedHeads2),
    append(Plan1, RelaxedPlan, EnrichedPlan),
    planner:collect_remainder(DepCounts1, PlannedHeads2, ProofAVL, RemainderRules).


%! planner:update_planned_set(+Rules, +SetIn, -SetOut)
%
% Updates the planned set with the given rules.

planner:update_planned_set(Rules, SetIn, SetOut) :-
    foldl(add_rule_head_to_set, Rules, SetIn, SetOut).


%! planner:add_rule_head_to_set(+Rule, +SetIn, -SetOut)
%
% Adds the head of a rule to the set.

planner:add_rule_head_to_set(Rule, SetIn, SetOut) :-
    ( Rule = rule(HeadWithCtx, _) ; Rule = assumed(rule(HeadWithCtx, _)) ; Rule = rule(assumed(HeadWithCtx), _) ),
    prover:canon_literal(HeadWithCtx, Head, _),
    put_assoc(Head, SetIn, true, SetOut).


%! planner:plan_init_from_proof(+ProofAVL, +PlannedHeadsAVL, -DepCounts, -ReadyQueue)
%
% Traverses ProofAVL using gen_assoc to initialize dependency counts and ready queue.

planner:plan_init_from_proof(ProofAVL, PlannedHeadsAVL, DepCounts, ReadyQueue) :-
    findall(
        CanonicalRule,
        (   assoc:gen_assoc(Key, ProofAVL, Value),
            prover:canon_rule(CanonicalRule, Key, Value)
        ),
        AllRules
    ),
    empty_assoc(EmptyCounts),
    build_depcounts_and_ready(AllRules, PlannedHeadsAVL, ProofAVL, EmptyCounts, DepCounts, [], ReadyQueue).


%! planner:build_depcounts_and_ready(+Rules, +PlannedHeads, +ProofAVL, +InCounts, -OutCounts, +InReady, -OutReady)
%
% Builds dependency counts and ready queue.

planner:build_depcounts_and_ready([], _, _ProofAVL, DepCounts, DepCounts, ReadyQueue, ReadyQueue).
planner:build_depcounts_and_ready([Rule|Rest], PlannedHeads, ProofAVL, InCounts, OutCounts, InReady, OutReady) :-
    ( Rule = rule(HeadWithCtx, Body)
    ; Rule = assumed(rule(HeadWithCtx, Body))
    ; Rule = rule(assumed(HeadWithCtx), Body)
    ),
    prover:canon_literal(HeadWithCtx, Head, _),
    % If the prover inserted a cycle-break marker for this Head, we must treat
    % the head as blocked in the planner (otherwise assoc traversal order can
    % overwrite the "blocked" count and accidentally enqueue it).
    (   get_assoc(assumed(rule(Head)), ProofAVL, _)
    ->  Count = 1
    ;   Rule = assumed(rule(_, _))
    ->  % Prover-level cycle-break: never make this immediately ready.
        % We still keep its body (stored in the proof) for downstream SCC logic.
        Count = 1
    ;   calculate_action_dependencies(Body, Count)
    ),
    put_assoc(Head, InCounts, Count, MidCounts),
    (   Count =:= 0,
        \+ get_assoc(Head, PlannedHeads, _),
        \+ get_assoc(assumed(rule(Head)), ProofAVL, _)
    ->  MidReady = [Rule | InReady]
    ;   MidReady = InReady
    ),
    build_depcounts_and_ready(Rest, PlannedHeads, ProofAVL, MidCounts, OutCounts, MidReady, OutReady).


%! planner:calculate_action_dependencies(+Body, -Count)
%
% Calculates the number of action dependencies in a body.

planner:calculate_action_dependencies([], 0).
planner:calculate_action_dependencies([Dep|Rest], Count) :-
    calculate_action_dependencies(Rest, RestCount),
    (   prover:is_constraint(Dep) -> Count = RestCount ; Count is RestCount + 1 ).


%! planner:plan_loop(+Queues, +Counts, +Triggers, +ProofAVL, +Planned, +Plan,
%!                   -FinalPlan, -FinalCounts, -FinalPlanned)
%
% Main planning loop.

planner:plan_loop([], Counts, _Triggers, _ProofAVL, Planned, FinalPlan, FinalPlan, Counts, Planned) :- !.
planner:plan_loop([[]|RestQueues], C, T, Proof, P, Cur, Fin, FinalCounts, FinalPlanned) :-
    !,
    planner:plan_loop(RestQueues, C, T, Proof, P, Cur, Fin, FinalCounts, FinalPlanned).
planner:plan_loop([ReadyQueue|RestQueues], InCounts, Triggers, ProofAVL, InPlanned, InPlan, FinalPlan, FinalCounts, FinalPlanned) :-
    OutPlan = [ReadyQueue | InPlan],
    process_wave(ReadyQueue, InCounts, Triggers, ProofAVL, InPlanned, OutPlanned, OutCounts, NextReadyQueue),
    plan_loop([NextReadyQueue|RestQueues], OutCounts, Triggers, ProofAVL, OutPlanned, OutPlan, FinalPlan, FinalCounts, FinalPlanned).


%! planner:collect_remainder(+DepCounts, +PlannedHeads, +ProofAVL, -RemainderRules)
%
% Collect all rules whose dependency count never reached zero.
%
planner:collect_remainder(DepCounts, PlannedHeads, ProofAVL, RemainderRules) :-
    findall(Head,
            ( assoc:gen_assoc(Head, DepCounts, Count),
              Count > 0,
              \+ get_assoc(Head, PlannedHeads, _)
            ),
            Heads0),
    sort(Heads0, Heads),
    findall(Rule,
            ( member(H, Heads),
              planner:get_full_rule_from_proof(H, ProofAVL, Rule)
            ),
            RemainderRules).


% =============================================================================
%  Phase 2: Relaxation pass (ignore :run deps as ordering constraints)
% =============================================================================

%! planner:is_runtime_dep(+Dep)
%
% True if Dep is a :run action literal (RDEPEND/PDEPEND ordering edge).
% These are the deps that can be relaxed when they cause cycles.

planner:is_runtime_dep(Dep) :-
    prover:canon_literal(Dep, Canon, _),
    scheduler:is_run_literal(Canon), !.


%! planner:plan_relaxation(+ProofAVL, +PlannedHeadsIn, -RelaxedPlan, -PlannedHeadsOut)
%
% For all rules not yet planned, recalculate dependency counts ignoring :run
% deps.  Rules whose non-runtime deps are all satisfied become immediately
% schedulable.  A secondary wave-planning loop cascades the freed rules.

planner:plan_relaxation(ProofAVL, PlannedHeadsIn, RelaxedPlan, PlannedHeadsOut) :-
    findall(Head-Rule,
            (   assoc:gen_assoc(Key, ProofAVL, Value),
                prover:canon_rule(Rule, Key, Value),
                Rule = rule(HeadWithCtx, _),
                HeadWithCtx \= assumed(_),
                prover:canon_literal(HeadWithCtx, Head, _),
                \+ get_assoc(Head, PlannedHeadsIn, _),
                \+ get_assoc(assumed(rule(Head)), ProofAVL, _)
            ),
            Remaining),
    (   Remaining = [] ->
        RelaxedPlan = [],
        PlannedHeadsOut = PlannedHeadsIn
    ;
        build_relaxed_counts(Remaining, PlannedHeadsIn, RelaxedCounts, ReadyQueue0),
        build_relaxed_triggers(Remaining, PlannedHeadsIn, RelaxedTriggers),
        (   ReadyQueue0 \= [] ->
            update_planned_set(ReadyQueue0, PlannedHeadsIn, PlannedHeads1),
            plan_loop([ReadyQueue0], RelaxedCounts, RelaxedTriggers, ProofAVL, PlannedHeads1,
                      [], RevRelaxedPlan, _FinalCounts, PlannedHeadsOut),
            reverse(RevRelaxedPlan, RelaxedPlan)
        ;   RelaxedPlan = [],
            PlannedHeadsOut = PlannedHeadsIn
        )
    ).


%! planner:build_relaxed_counts(+HeadRulePairs, +PlannedHeads, -Counts, -ReadyQueue)
%
% For each remaining rule, count non-constraint, non-:run, non-planned deps.

planner:build_relaxed_counts(Pairs, PlannedHeads, Counts, ReadyQueue) :-
    empty_assoc(EmptyCounts),
    build_relaxed_counts_(Pairs, PlannedHeads, EmptyCounts, Counts, [], ReadyQueue).

build_relaxed_counts_([], _, Counts, Counts, Ready, Ready).
build_relaxed_counts_([Head-Rule|Rest], PlannedHeads, InCounts, OutCounts, InReady, OutReady) :-
    Rule = rule(_, Body),
    calculate_relaxed_deps(Body, PlannedHeads, Count),
    put_assoc(Head, InCounts, Count, MidCounts),
    (   Count =:= 0 ->
        MidReady = [Rule | InReady]
    ;   MidReady = InReady
    ),
    build_relaxed_counts_(Rest, PlannedHeads, MidCounts, OutCounts, MidReady, OutReady).


%! planner:calculate_relaxed_deps(+Body, +PlannedHeads, -Count)
%
% Count body elements that are non-constraint, non-:run, and not yet planned.

planner:calculate_relaxed_deps([], _, 0).
planner:calculate_relaxed_deps([Dep|Rest], PlannedHeads, Count) :-
    calculate_relaxed_deps(Rest, PlannedHeads, RestCount),
    (   prover:is_constraint(Dep) -> Count = RestCount
    ;   is_runtime_dep(Dep) -> Count = RestCount
    ;   prover:canon_literal(Dep, DepHead, _),
        get_assoc(DepHead, PlannedHeads, _) -> Count = RestCount
    ;   Count is RestCount + 1
    ).


%! planner:build_relaxed_triggers(+HeadRulePairs, +PlannedHeads, -Triggers)
%
% Build a trigger map for the relaxation pass: dep_canonical -> [head_literal, ...].
% Only non-constraint, non-:run, non-planned deps generate trigger entries.

planner:build_relaxed_triggers(Remaining, PlannedHeads, Triggers) :-
    findall(DepCanon-HeadLiteral,
            (   member(_Head-Rule, Remaining),
                Rule = rule(HeadLiteral, Body),
                member(Dep, Body),
                \+ prover:is_constraint(Dep),
                \+ is_runtime_dep(Dep),
                prover:canon_literal(Dep, DepCanon, _),
                \+ get_assoc(DepCanon, PlannedHeads, _)
            ),
            Pairs0),
    (   Pairs0 = [] ->
        empty_assoc(Triggers)
    ;
        keysort(Pairs0, Pairs1),
        group_pairs_by_key(Pairs1, Grouped),
        list_to_assoc(Grouped, Triggers)
    ).


% =============================================================================
%  Wave planning loop
% =============================================================================

%! planner:process_wave(+ReadyQueue, +InCounts, +Triggers, +ProofAVL, +InPlanned, -OutPlanned, -OutCounts, -NextReadyQueue)
%
% Processes a wave of rules.

process_wave(ReadyQueue, InCounts, Triggers, ProofAVL, InPlanned, OutPlanned, OutCounts, NextReadyQueue) :-
    InitialState = state(InCounts, [], InPlanned),
    foldl(process_proven_rule(Triggers, ProofAVL), ReadyQueue, InitialState, FinalState),
    FinalState = state(OutCounts, NextReadyQueue, OutPlanned).


%! planner:process_proven_rule(+Triggers, +ProofAVL, +ProvenRule, +InState, -OutState)
%
% Processes a proven rule.

planner:process_proven_rule(Triggers, ProofAVL, ProvenRule, InState, OutState) :-
    (   ProvenRule = rule(HeadWithCtx, _) ; ProvenRule = assumed(rule(HeadWithCtx, _)) ),
    prover:canon_literal(HeadWithCtx, Head, _),
    (   get_assoc(Head, Triggers, Dependents)
    ->  foldl(decrement_and_enqueue(ProofAVL), Dependents, InState, OutState)
    ;   OutState = InState
    ).


%! planner:decrement_and_enqueue(+ProofAVL, +DependentLiteral, +InState, -OutState)
%
% Decrements the count of a dependent literal and enqueues it.

planner:decrement_and_enqueue(ProofAVL, DependentLiteral, InState, OutState) :-
    InState = state(InCounts, InNextReady, InPlanned),
    prover:canon_literal(DependentLiteral, NormalizedLiteral, _),
    % If the prover inserted a cycle-break marker for this head, we keep it in
    % the remainder for the scheduler: do NOT decrement to 0 and do NOT enqueue.
    (   get_assoc(assumed(rule(NormalizedLiteral)), ProofAVL, _)
    ->  OutState = InState
    ;
    (   get_assoc(NormalizedLiteral, InCounts, OldCount), OldCount > 0 ->
        NewCount is OldCount - 1,
        put_assoc(NormalizedLiteral, InCounts, NewCount, OutCounts),
        (   NewCount =:= 0, \+ get_assoc(NormalizedLiteral, InPlanned, _) ->
            (   get_full_rule_from_proof(NormalizedLiteral, ProofAVL, FullDependentRule)
            ->  OutNextReady = [FullDependentRule | InNextReady],
                put_assoc(NormalizedLiteral, InPlanned, true, OutPlanned)
            ;
                OutNextReady = InNextReady,
                OutPlanned = InPlanned
            )
        ;   OutNextReady = InNextReady,
            OutPlanned = InPlanned
        )
    ;
        OutCounts = InCounts,
        OutNextReady = InNextReady,
        OutPlanned = InPlanned
    ),
        OutState = state(OutCounts, OutNextReady, OutPlanned)
    ).


%! planner:get_full_rule_from_proof(+Literal, +ProofAVL, -FullRule)
%
% Gets the full rule from the proof.

planner:get_full_rule_from_proof(Literal, ProofAVL, FullRule) :-
    (   ProofKey = rule(Literal),
        get_assoc(ProofKey, ProofAVL, ProofValue)
    ;   ProofKey = assumed(rule(Literal)),
        get_assoc(ProofKey, ProofAVL, ProofValue)
    ;   ProofKey = rule(assumed(Literal)),
        get_assoc(ProofKey, ProofAVL, ProofValue)
    ),
    !,
    prover:canon_rule(FullRule, ProofKey, ProofValue).



%! planner:test(+Repository)
%
% Tests the planner.

planner:test(Repository) :- config:test_style(Style), planner:test(Repository,Style).
planner:test(Repository,Style) :-
  config:proving_target(Action0),
  prover:test_action(Action0, Action),
  tester:test(Style, 'Planning', Repository://Entry, (Repository:entry(Entry)),
    ( prover:prove(Repository://Entry:Action?{[]},t,Proof,t,_Model,t,_Constraint,t,Triggers),
      planner:plan(Proof,Triggers,t,_Plan,_Remainder)
    )).
planner:test_latest(Repository) :- config:test_style(Style), planner:test_latest(Repository,Style).
planner:test_latest(Repository,Style) :-
  config:proving_target(Action0),
  prover:test_action(Action0, Action),
  tester:test(Style, 'Planning latest', Repository://Entry,
              (Repository:package(C,N),once(Repository:ebuild(Entry,C,N,_))),
              ( prover:prove(Repository://Entry:Action?{[]},t,Proof,t,_Model,t,_Constraint,t,Triggers),
                planner:plan(Proof,Triggers,t,_Plan,_Remainder)
              )).

% -----------------------------------------------------------------------------
%  Testing + statistics
% -----------------------------------------------------------------------------

%! planner:test_stats(+Repository)
planner:test_stats(Repository) :-
  config:test_style(Style),
  planner:test_stats(Repository, Style).

%! planner:test_stats(+Repository,+Style)
planner:test_stats(Repository, Style) :-
  config:proving_target(Action0),
  prover:test_action(Action0, Action),
  aggregate_all(count, (Repository:entry(_E)), ExpectedTotal),
  printer:test_stats_reset('Planning', ExpectedTotal),
  aggregate_all(count, (Repository:package(_C,_N)), ExpectedPkgs),
  printer:test_stats_set_expected_unique_packages(ExpectedPkgs),
  tester:test(Style,
              'Planning',
              Repository://Entry,
              (Repository:entry(Entry)),
              ( prover:prove(Repository://Entry:Action?{[]},t,ProofAVL,t,ModelAVL,t,_Constraint,t,Triggers),
                planner:plan(ProofAVL,Triggers,t,_Plan,_Remainder),
                printer:test_stats_record_entry(Repository://Entry, ModelAVL, ProofAVL, Triggers, true)
              )),
  printer:test_stats_print.