/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2025, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> PLANNER
The Planner creates a plan based on a Proof.

This version is synchronized with the corrected prover. It initializes by
traversing the ProofAVL directly and fetches rule details from the ProofAVL
"just-in-time" within the main planning loop.
*/

:- module(planner, []).

% =============================================================================
%  PLANNER declarations
% =============================================================================

%! planner:plan(+ProofAVL, +TriggersAVL, +PlannedHeadsIn, -EnrichedPlan)
%
% Creates a plan based on a Proof.

planner:plan(ProofAVL, TriggersAVL, PlannedHeadsIn, EnrichedPlan) :-
    plan_init_from_proof(ProofAVL, PlannedHeadsIn, DepCounts, ReadyQueue),
    (   ReadyQueue \= [] ->
        update_planned_set(ReadyQueue, PlannedHeadsIn, PlannedHeadsInit),
        plan_loop([ReadyQueue], DepCounts, TriggersAVL, ProofAVL, PlannedHeadsInit, [], RevEnrichedPlan),
        reverse(RevEnrichedPlan, EnrichedPlan)
    ;   EnrichedPlan = []
    ).


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
    build_depcounts_and_ready(AllRules, PlannedHeadsAVL, EmptyCounts, DepCounts, [], ReadyQueue).


%! planner:build_depcounts_and_ready(+Rules, +PlannedHeads, +InCounts, -OutCounts, +InReady, -OutReady)
%
% Builds dependency counts and ready queue.

planner:build_depcounts_and_ready([], _, DepCounts, DepCounts, ReadyQueue, ReadyQueue).
planner:build_depcounts_and_ready([Rule|Rest], PlannedHeads, InCounts, OutCounts, InReady, OutReady) :-
    ( Rule = rule(HeadWithCtx, Body) ; Rule = assumed(rule(HeadWithCtx, Body)) ; Rule = rule(assumed(HeadWithCtx), Body) ),
    prover:canon_literal(HeadWithCtx, Head, _),
    calculate_action_dependencies(Body, Count),
    put_assoc(Head, InCounts, Count, MidCounts),
    (   Count =:= 0, \+ get_assoc(Head, PlannedHeads, _)
    ->  MidReady = [Rule | InReady]
    ;   MidReady = InReady
    ),
    build_depcounts_and_ready(Rest, PlannedHeads, MidCounts, OutCounts, MidReady, OutReady).


%! planner:calculate_action_dependencies(+Body, -Count)
%
% Calculates the number of action dependencies in a body.

planner:calculate_action_dependencies([], 0).
planner:calculate_action_dependencies([Dep|Rest], Count) :-
    calculate_action_dependencies(Rest, RestCount),
    (   prover:is_constraint(Dep) -> Count = RestCount ; Count is RestCount + 1 ).


%! planner:plan_loop(+Queues, +Counts, +Triggers, +ProofAVL, +Planned, +Plan, -FinalPlan)
%
% Main planning loop.

planner:plan_loop([], _, _, _, _, FinalPlan, FinalPlan) :- !.
planner:plan_loop([[]|RestQueues], C, T, Proof, P, Cur, Fin) :- !, planner:plan_loop(RestQueues, C, T, Proof, P, Cur, Fin).
planner:plan_loop([ReadyQueue|RestQueues], InCounts, Triggers, ProofAVL, InPlanned, InPlan, FinalPlan) :-
    OutPlan = [ReadyQueue | InPlan],
    process_wave(ReadyQueue, InCounts, Triggers, ProofAVL, InPlanned, OutPlanned, OutCounts, NextReadyQueue),
    plan_loop([NextReadyQueue|RestQueues], OutCounts, Triggers, ProofAVL, OutPlanned, OutPlan, FinalPlan).


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
    OutState = state(OutCounts, OutNextReady, OutPlanned).


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
  config:proving_target(Action),
  tester:test(Style, 'Planning', Repository://Entry, (Repository:entry(Entry)),
    ( with_q(prover:prove(Repository://Entry:Action?{[]},t,Proof,t,_Model,t,_Constraint,t,Triggers)),
      with_q(planner:plan(Proof,Triggers,t,_Plan))
    )).
planner:test_latest(Repository) :- config:test_style(Style), planner:test_latest(Repository,Style).
planner:test_latest(Repository,Style) :-
  config:proving_target(Action),
  tester:test(Style, 'Planning latest', Repository://Entry,
              (Repository:package(C,N),once(Repository:ebuild(Entry,C,N,_))),
              ( with_q(prover:prove(Repository://Entry:Action?{[]},t,Proof,t,_Model,t,_Constraint,t,Triggers)),
                    with_q(planner:plan(Proof,Triggers,t,_Plan))
              )).

