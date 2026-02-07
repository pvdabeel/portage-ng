/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> SCHEDULER
The Scheduler is a post-planning step that can deal with cyclic remainders.

Conceptually:
- The prover builds a proof (and triggers graph).
- The planner builds a wave plan for the acyclic portion of the graph.
- If the planner cannot schedule everything (e.g. due to cyclic rule bodies),
  it returns a remainder.

This scheduler computes strongly connected components (SCCs) on the remainder
subgraph (Kosaraju) and can "act" only on SCCs that are safe to merge as a set.

Policy:
- SCCs consisting purely of *mergeable* literals are schedulable as merge sets.
  Mergeable literals are:
  - :run (historical behavior)
  - :install/:update/:reinstall (merge actions)
- Any SCC containing other literal kinds is treated as unschedulable; all rules
  that (transitively) depend on such SCCs remain in the remainder.

The scheduler does not mutate the prover's TriggersAVL; it derives SCC metadata
and a condensed schedule for the remainder only.
*/

:- module(scheduler, []).


%! scheduler:schedule(+ProofAVL,+TriggersAVL,+PlanIn,+RemainderIn,-PlanOut,-RemainderOut)
%
% If RemainderIn is empty, passes PlanIn through unchanged (O(1)).
% Otherwise schedules the schedulable portion of the remainder by collapsing
% :run SCCs (merge sets) and returns a new remainder for the unschedulable part.
%
schedule(_ProofAVL, _TriggersAVL, PlanIn, RemainderIn, PlanOut, []) :-
  RemainderIn == [],
  !,
  scheduler:perf_add(0, 0, 0, 0, 0, 0, 0, 0),
  scheduler:enforce_order_after_constraints(PlanIn, PlanOut).
schedule(_ProofAVL, _TriggersAVL, PlanIn, RemainderIn, PlanOut, RemainderOut) :-
  % Only schedule from the planner-provided remainder. Do not remove items from
  % the existing plan here: removing + re-adding must be proven correct, and we
  % currently want a safe scheduler that never drops actions.
  scheduler:remainder_heads(RemainderIn, Heads),
  length(Heads, HeadsN),
  % Performance: avoid repeated ProofAVL lookups by building a head->rule map from
  % the planner-provided remainder rules, and extract the remainder subgraph from it.
  scheduler:remainder_head_rule_map(RemainderIn, HeadRuleMap),
  scheduler:build_forward_reverse_from_rules(Heads, HeadRuleMap, Forward, Reverse),
  scheduler:kosaraju_scc(Heads, Forward, Reverse, SCCs),
  length(SCCs, SCCsN),
  scheduler:build_components(SCCs, Forward, CompMap, Comps),
  length(Comps, CompsN),
  scheduler:blocked_components(Comps, Forward, CompMap, BlockedCompIds),
  length(BlockedCompIds, BlockedN),
  scheduler:schedulable_component_waves(Comps, Forward, CompMap, BlockedCompIds, WavesCompIds),
  length(WavesCompIds, WavesN),
  scheduler:count_wave_components(WavesCompIds, WavesCompTotalN),
  scheduler:expand_component_waves_from_map(WavesCompIds, Comps, HeadRuleMap, WavesRules),
  scheduler:count_rules_in_plan(WavesRules, AddedRulesN),
  append(PlanIn, WavesRules, PlanOut0),
  scheduler:remainder_from_blocked_from_map(BlockedCompIds, Comps, HeadRuleMap, RemainderOut),
  scheduler:perf_add(HeadsN, SCCsN, CompsN, BlockedN, WavesN, WavesCompTotalN, AddedRulesN, 1),
  scheduler:enforce_order_after_constraints(PlanOut0, PlanOut).

% -----------------------------------------------------------------------------
%  Enforce ordering-only constraints (after_only)
% -----------------------------------------------------------------------------
%
% `rules:ctx_add_after_condition/4` represents after_only/1 as:
%   constraint(order_after(Anchor):{[]})
%
% The wave planner ignores constraints, so we enforce them here by reordering the
% final plan so that any rule carrying such a constraint appears after Anchor.

scheduler:enforce_order_after_constraints(PlanIn, PlanOut) :-
  append(PlanIn, Flat0),
  ( scheduler:flat_has_order_after_constraints(Flat0) ->
      scheduler:plan_step_lengths(PlanIn, Lens),
      scheduler:flat_order_after_constraints(Flat0, Flat),
      scheduler:rechunk_by_lengths(Flat, Lens, PlanOut)
  ; PlanOut = PlanIn
  ),
  !.

scheduler:flat_has_order_after_constraints(Rules) :-
  member(Rule, Rules),
  scheduler:rule_order_after_anchor(Rule, _Anchor),
  !.

scheduler:plan_step_lengths(Plan, Lens) :-
  findall(N, (member(Step, Plan), length(Step, N)), Lens),
  !.

scheduler:flat_order_after_constraints(Rules0, Rules) :-
  % Build a set of heads present in the plan.
  findall(H, (member(R, Rules0), scheduler:rule_head(R, H)), Heads0),
  sort(Heads0, Heads),
  empty_assoc(Empty),
  foldl(scheduler:assoc_set_put, Heads, Empty, HeadSet),
  % One-pass stable reordering using a waiting bucket per anchor.
  empty_assoc(W0),
  scheduler:order_after_loop(Rules0, HeadSet, W0, W, [], RevOut),
  % If some rules are mutually constrained (cycle), they may remain in Waiting.
  % Do NOT drop them (that would make schedule/6 fail). Instead append them in a
  % deterministic order as a best-effort fallback.
  scheduler:waiting_leftovers(W, Left0),
  reverse(Left0, RevLeft),
  append(RevLeft, RevOut, RevAll),
  reverse(RevAll, Rules).

scheduler:waiting_leftovers(Waiting, Leftovers) :-
  assoc:assoc_to_list(Waiting, Pairs),
  findall(R,
          ( member(_Anchor-Rs, Pairs),
            member(R, Rs)
          ),
          Leftovers).

scheduler:assoc_set_put(K, A0, A) :-
  ( get_assoc(K, A0, _) -> A = A0 ; put_assoc(K, A0, true, A) ).

scheduler:order_after_loop([], _HeadSet, Waiting, Waiting, Acc, Acc) :- !.
scheduler:order_after_loop([Rule|Rest], HeadSet, Waiting0, Waiting, Acc0, Acc) :-
  scheduler:rule_head(Rule, H),
  ( scheduler:rule_order_after_anchor(Rule, Anchor),
    get_assoc(Anchor, HeadSet, true)
  ->
    % Anchor exists in plan: delay until anchor is emitted.
    ( get_assoc(Anchor, Waiting0, L0) -> true ; L0 = [] ),
    append(L0, [Rule], L1),
    put_assoc(Anchor, Waiting0, L1, Waiting1),
    scheduler:order_after_loop(Rest, HeadSet, Waiting1, Waiting, Acc0, Acc)
  ; % Emit now, then flush dependents waiting on this head.
    scheduler:flush_waiting(H, HeadSet, Waiting0, Waiting1, [Rule|Acc0], Acc1),
    scheduler:order_after_loop(Rest, HeadSet, Waiting1, Waiting, Acc1, Acc)
  ).

scheduler:flush_waiting(H, HeadSet, Waiting0, Waiting, Acc0, Acc) :-
  ( get_assoc(H, Waiting0, L), L \== [] ->
      del_assoc(H, Waiting0, _Old, Waiting1),
      scheduler:flush_waiting_list(L, HeadSet, Waiting1, Waiting, Acc0, Acc)
  ; Waiting = Waiting0,
    Acc = Acc0
  ).

scheduler:flush_waiting_list([], _HeadSet, Waiting, Waiting, Acc, Acc) :- !.
scheduler:flush_waiting_list([R|Rs], HeadSet, Waiting0, Waiting, Acc0, Acc) :-
  scheduler:rule_head(R, H),
  scheduler:flush_waiting(H, HeadSet, Waiting0, Waiting1, [R|Acc0], Acc1),
  scheduler:flush_waiting_list(Rs, HeadSet, Waiting1, Waiting, Acc1, Acc).

scheduler:rule_order_after_anchor(Rule, Anchor) :-
  ( Rule = rule(_HeadWithCtx, Body)
  ; Rule = assumed(rule(_HeadWithCtx, Body))
  ; Rule = rule(assumed(_HeadWithCtx), Body)
  ),
  member(constraint(order_after(Anchor):{_}), Body),
  !.

scheduler:rechunk_by_lengths(Flat, Lens, Plan) :-
  scheduler:rechunk_by_lengths_(Flat, Lens, Plan).

scheduler:rechunk_by_lengths_([], [], []) :- !.
scheduler:rechunk_by_lengths_(Rules, [N|Ns], [Step|Rest]) :-
  length(Step, N),
  append(Step, Tail, Rules),
  scheduler:rechunk_by_lengths_(Tail, Ns, Rest).

% -----------------------------------------------------------------------------
%  Perf counters (whole-repo runs)
% -----------------------------------------------------------------------------
%
% Aggregates SCC/remainder characteristics over many schedule/6 calls.
% Reset/report is triggered by prover:test/*.

scheduler:perf_reset :-
  flag(sch_perf_entries, _OldE, 0),
  flag(sch_perf_nontrivial, _OldNT, 0),
  flag(sch_perf_heads_sum, _OldH, 0),
  flag(sch_perf_scc_sum, _OldS, 0),
  flag(sch_perf_comps_sum, _OldC, 0),
  flag(sch_perf_blocked_sum, _OldB, 0),
  flag(sch_perf_waves_sum, _OldW, 0),
  flag(sch_perf_wave_comps_sum, _OldWC, 0),
  flag(sch_perf_added_rules_sum, _OldAR, 0),
  !.

scheduler:perf_add(HeadsN, SCCsN, CompsN, BlockedN, WavesN, WavesCompN, AddedRulesN, Nontrivial) :-
  flag(sch_perf_entries, E0, E0+1),
  flag(sch_perf_nontrivial, NT0, NT0+Nontrivial),
  flag(sch_perf_heads_sum, H0, H0+HeadsN),
  flag(sch_perf_scc_sum, S0, S0+SCCsN),
  flag(sch_perf_comps_sum, C0, C0+CompsN),
  flag(sch_perf_blocked_sum, B0, B0+BlockedN),
  flag(sch_perf_waves_sum, W0, W0+WavesN),
  flag(sch_perf_wave_comps_sum, WC0, WC0+WavesCompN),
  flag(sch_perf_added_rules_sum, AR0, AR0+AddedRulesN),
  !.

scheduler:perf_report :-
  flag(sch_perf_entries, E, E),
  ( E =:= 0 ->
      true
  ; flag(sch_perf_nontrivial, NT, NT),
    flag(sch_perf_heads_sum, H, H),
    flag(sch_perf_scc_sum, S, S),
    flag(sch_perf_comps_sum, C, C),
    flag(sch_perf_blocked_sum, B, B),
    flag(sch_perf_waves_sum, W, W),
    flag(sch_perf_wave_comps_sum, WC, WC),
    flag(sch_perf_added_rules_sum, AR, AR),
    AvgH is H / E,
    AvgS is S / E,
    AvgC is C / E,
    AvgB is B / E,
    AvgW is W / E,
    AvgWC is WC / E,
    AvgAR is AR / E,
    message:scroll_notice(['scheduler perf: entries=',E,
                           ' nontrivial=',NT,
                           ' heads_sum=',H,' avg=',AvgH,
                           ' scc_sum=',S,' avg=',AvgS,
                           ' comps_sum=',C,' avg=',AvgC,
                           ' blocked_sum=',B,' avg=',AvgB,
                           ' waves_sum=',W,' avg=',AvgW,
                           ' wave_comps_sum=',WC,' avg=',AvgWC,
                           ' added_rules_sum=',AR,' avg=',AvgAR])
  ),
  nl,
  !.

scheduler:count_wave_components(Waves, Total) :-
  findall(N, (member(W, Waves), length(W, N)), Ns),
  sum_list(Ns, Total),
  !.

scheduler:count_rules_in_plan(Plan, Count) :-
  findall(N, (member(Step, Plan), length(Step, N)), Ns),
  sum_list(Ns, Count),
  !.


% -----------------------------------------------------------------------------
%  Plan / closure helpers
% -----------------------------------------------------------------------------

% Collect all heads present in a plan.
scheduler:plan_heads(Plan, Heads) :-
  findall(H,
          ( member(Step, Plan),
            member(Rule, Step),
            scheduler:rule_head(Rule, H)
          ),
          Hs0),
  sort(Hs0, Heads).

% Compute the dependency closure starting from SeedHeads, but only:
% - include :run heads
% - include heads that are already present in the plan (to keep this bounded)
scheduler:run_closure_in_plan(SeedHeads, PlanHeads, ProofAVL, ClosureHeads) :-
  empty_assoc(V0),
  include(scheduler:is_run_head, SeedHeads, SeedsRun0),
  sort(SeedsRun0, SeedsRun),
  scheduler:closure_queue(SeedsRun, PlanHeads, ProofAVL, V0, _V, [], Closure0),
  sort(Closure0, ClosureHeads).

scheduler:is_run_head(Head) :-
  compound(Head),
  Head =.. [':', _Target, run].

scheduler:closure_queue([], _PlanHeads, _ProofAVL, V, V, Acc, Acc).
scheduler:closure_queue([H|Hs], PlanHeads, ProofAVL, V0, V, Acc0, Acc) :-
  ( get_assoc(H, V0, true) ->
      scheduler:closure_queue(Hs, PlanHeads, ProofAVL, V0, V, Acc0, Acc)
  ; put_assoc(H, V0, true, V1),
    scheduler:deps_in_plan_run(H, PlanHeads, ProofAVL, Deps),
    append(Deps, Hs, Q1),
    scheduler:closure_queue(Q1, PlanHeads, ProofAVL, V1, V, [H|Acc0], Acc)
  ).

scheduler:deps_in_plan_run(Head, PlanHeads, ProofAVL, Deps) :-
  ( scheduler:get_full_rule_from_proof(Head, ProofAVL, Rule) ->
      ( Rule = rule(_HeadWithCtx, Body)
      ; Rule = assumed(rule(_HeadWithCtx, Body))
      ; Rule = rule(assumed(_HeadWithCtx), Body)
      ),
      findall(DepHead0,
              ( member(Dep, Body),
                \+ prover:is_constraint(Dep),
                prover:canon_literal(Dep, DepHead0, _),
                scheduler:is_run_head(DepHead0),
                memberchk(DepHead0, PlanHeads)
              ),
              Deps0),
      sort(Deps0, Deps)
  ; Deps = []
  ).

% Remove rules whose heads are in RemoveHeads from a plan.
scheduler:remove_heads_from_plan(RemoveHeads, PlanIn, PlanOut) :-
  maplist(scheduler:remove_heads_from_step(RemoveHeads), PlanIn, Plan1),
  exclude(==( [] ), Plan1, PlanOut).

scheduler:remove_heads_from_step(RemoveHeads, StepIn, StepOut) :-
  findall(Rule,
          ( member(Rule, StepIn),
            scheduler:rule_head(Rule, H),
            \+ memberchk(H, RemoveHeads)
          ),
          StepOut).


% -----------------------------------------------------------------------------
%  Test helpers (mirror planner.pl)
% -----------------------------------------------------------------------------

%! scheduler:test(+Repository)
%
% Tests the scheduler (prove -> plan -> schedule).
%
scheduler:test(Repository) :-
  config:test_style(Style),
  scheduler:test(Repository, Style).

%! scheduler:test(+Repository,+Style)
scheduler:test(Repository, Style) :-
  config:proving_target(Action0),
  prover:test_action(Action0, Action),
  tester:test(Style, 'Scheduling', Repository://Entry, (Repository:entry(Entry)),
    ( prover:prove(Repository://Entry:Action?{[]},t,ProofAVL,t,_ModelAVL,t,_Constraint,t,TriggersAVL),
      planner:plan(ProofAVL,TriggersAVL,t,Plan0,Remainder0),
      scheduler:schedule(ProofAVL,TriggersAVL,Plan0,Remainder0,_Plan,_Remainder)
    )).

%! scheduler:test_latest(+Repository)
%
% Same as scheduler:test(+Repository), but only tests highest version of every package.
%
scheduler:test_latest(Repository) :-
  config:test_style(Style),
  scheduler:test_latest(Repository, Style).

%! scheduler:test_latest(+Repository,+Style)
scheduler:test_latest(Repository, Style) :-
  config:proving_target(Action0),
  prover:test_action(Action0, Action),
  tester:test(Style, 'Scheduling latest', Repository://Entry,
              (Repository:package(C,N),once(Repository:ebuild(Entry,C,N,_))),
              ( prover:prove(Repository://Entry:Action?{[]},t,ProofAVL,t,_ModelAVL,t,_Constraint,t,TriggersAVL),
                planner:plan(ProofAVL,TriggersAVL,t,Plan0,Remainder0),
                scheduler:schedule(ProofAVL,TriggersAVL,Plan0,Remainder0,_Plan,_Remainder)
              )).

% -----------------------------------------------------------------------------
%  Testing + statistics (mirror planner.pl)
% -----------------------------------------------------------------------------

%! scheduler:test_stats(+Repository)
scheduler:test_stats(Repository) :-
  config:test_style(Style),
  scheduler:test_stats(Repository, Style).

%! scheduler:test_stats(+Repository,+Style)
scheduler:test_stats(Repository, Style) :-
  config:proving_target(Action0),
  prover:test_action(Action0, Action),
  aggregate_all(count, (Repository:entry(_E)), ExpectedTotal),
  printer:test_stats_reset('Scheduling', ExpectedTotal),
  aggregate_all(count, (Repository:package(_C,_N)), ExpectedPkgs),
  printer:test_stats_set_expected_unique_packages(ExpectedPkgs),
  tester:test(Style,
              'Scheduling',
              Repository://Entry,
              (Repository:entry(Entry)),
              ( prover:prove(Repository://Entry:Action?{[]},t,ProofAVL,t,ModelAVL,t,_Constraint,t,TriggersAVL),
                planner:plan(ProofAVL,TriggersAVL,t,Plan0,Remainder0),
                scheduler:schedule(ProofAVL,TriggersAVL,Plan0,Remainder0,_Plan,_Remainder),
                printer:test_stats_record_entry(Repository://Entry, ModelAVL, ProofAVL, TriggersAVL, true)
              )),
  printer:test_stats_print.


% -----------------------------------------------------------------------------
%  Remainder extraction
% -----------------------------------------------------------------------------

scheduler:remainder_heads(RemainderRules, Heads) :-
  findall(Head,
          ( member(Rule, RemainderRules),
            scheduler:rule_head(Rule, Head)
          ),
          Heads0),
  sort(Heads0, Heads).

scheduler:rule_head(Rule, Head) :-
  ( Rule = rule(HeadWithCtx, _Body)
  ; Rule = assumed(rule(HeadWithCtx, _Body))
  ; Rule = rule(assumed(HeadWithCtx), _Body)
  ),
  prover:canon_literal(HeadWithCtx, Head, _).


% -----------------------------------------------------------------------------
%  Graph extraction (remainder-induced)
% -----------------------------------------------------------------------------

scheduler:build_forward_reverse(Heads, ProofAVL, Forward, Reverse) :-
  empty_assoc(EmptyF),
  foldl(scheduler:forward_put(Heads, ProofAVL), Heads, EmptyF, Forward0),
  scheduler:invert_graph(Heads, Forward0, Reverse0),
  Forward = Forward0,
  Reverse = Reverse0.

scheduler:forward_put(Heads, ProofAVL, Head, In, Out) :-
  scheduler:get_full_rule_from_proof(Head, ProofAVL, Rule),
  ( Rule = rule(_HeadWithCtx, Body)
  ; Rule = assumed(rule(_HeadWithCtx, Body))
  ; Rule = rule(assumed(_HeadWithCtx), Body)
  ),
  findall(DepHead,
          ( member(Dep, Body),
            \+ prover:is_constraint(Dep),
            prover:canon_literal(Dep, DepHead, _),
            memberchk(DepHead, Heads)
          ),
          Deps0),
  sort(Deps0, Deps),
  put_assoc(Head, In, Deps, Out).

% Build a head->rule assoc from the remainder rules list (planner already fetched
% full rules from the proof).
scheduler:remainder_head_rule_map(RemainderRules, Map) :-
  empty_assoc(M0),
  foldl(scheduler:remainder_head_rule_put, RemainderRules, M0, Map),
  !.

scheduler:remainder_head_rule_put(Rule, In, Out) :-
  scheduler:rule_head(Rule, Head),
  % If duplicates exist, keep the first encountered rule (stable).
  ( get_assoc(Head, In, _) ->
      Out = In
  ; put_assoc(Head, In, Rule, Out)
  ).

% Faster graph extraction using the remainder head->rule map and a heads set.
scheduler:build_forward_reverse_from_rules(Heads, HeadRuleMap, Forward, Reverse) :-
  scheduler:heads_set_assoc(Heads, HeadSet),
  empty_assoc(EmptyF),
  foldl(scheduler:forward_put_from_map(HeadRuleMap, HeadSet), Heads, EmptyF, Forward0),
  scheduler:invert_graph(Heads, Forward0, Reverse0),
  Forward = Forward0,
  Reverse = Reverse0.

scheduler:heads_set_assoc(Heads, Set) :-
  empty_assoc(S0),
  foldl(scheduler:assoc_set_put, Heads, S0, Set),
  !.

scheduler:forward_put_from_map(HeadRuleMap, HeadSet, Head, In, Out) :-
  ( get_assoc(Head, HeadRuleMap, Rule) ->
      scheduler:rule_body(Rule, Body),
      findall(DepHead,
              ( member(Dep, Body),
                \+ prover:is_constraint(Dep),
                prover:canon_literal(Dep, DepHead, _),
                get_assoc(DepHead, HeadSet, true)
              ),
              Deps0),
      sort(Deps0, Deps),
      put_assoc(Head, In, Deps, Out)
  ; % Should not happen, but keep scheduler total.
    put_assoc(Head, In, [], Out)
  ).

scheduler:rule_body(Rule, Body) :-
  ( Rule = rule(_HeadWithCtx, Body)
  ; Rule = assumed(rule(_HeadWithCtx, Body))
  ; Rule = rule(assumed(_HeadWithCtx), Body)
  ),
  !.

scheduler:invert_graph(Heads, Forward, Reverse) :-
  empty_assoc(Empty),
  foldl(scheduler:init_empty_neighbors, Heads, Empty, R0),
  assoc:assoc_to_list(Forward, Pairs),
  foldl(scheduler:invert_edges, Pairs, R0, Reverse).

scheduler:init_empty_neighbors(Node, In, Out) :-
  ( get_assoc(Node, In, _) -> Out = In ; put_assoc(Node, In, [], Out) ).

scheduler:invert_edges(Node-Neighbors, In, Out) :-
  foldl(scheduler:invert_edge(Node), Neighbors, In, Out).

scheduler:invert_edge(From, To, In, Out) :-
  ( get_assoc(To, In, Ns0) -> true ; Ns0 = [] ),
  ( memberchk(From, Ns0) -> Ns = Ns0 ; Ns = [From|Ns0] ),
  put_assoc(To, In, Ns, Out).


% -----------------------------------------------------------------------------
%  Kosaraju SCC
% -----------------------------------------------------------------------------

scheduler:kosaraju_scc(Nodes, Forward, Reverse, SCCs) :-
  empty_assoc(V0),
  scheduler:finish_order(Nodes, Forward, V0, _V1, [], Order0),
  empty_assoc(V2),
  scheduler:collect_sccs(Order0, Reverse, V2, _V3, [], SCCs0),
  reverse(SCCs0, SCCs).

scheduler:finish_order([], _Forward, V, V, Order, Order).
scheduler:finish_order([N|Ns], Forward, V0, V, Order0, Order) :-
  ( get_assoc(N, V0, true) ->
      scheduler:finish_order(Ns, Forward, V0, V, Order0, Order)
  ; put_assoc(N, V0, true, V1),
    scheduler:dfs_finish(N, Forward, V1, V2, Order0, Order1),
    scheduler:finish_order(Ns, Forward, V2, V, Order1, Order)
  ).

scheduler:dfs_finish(N, Forward, V0, V, Order0, Order) :-
  ( get_assoc(N, Forward, Neigh) -> true ; Neigh = [] ),
  scheduler:finish_order(Neigh, Forward, V0, V1, Order0, Order1),
  Order = [N|Order1],
  V = V1.

scheduler:collect_sccs([], _Reverse, V, V, SCCs, SCCs).
scheduler:collect_sccs([N|Ns], Reverse, V0, V, SCCs0, SCCs) :-
  ( get_assoc(N, V0, true) ->
      scheduler:collect_sccs(Ns, Reverse, V0, V, SCCs0, SCCs)
  ; put_assoc(N, V0, true, V1),
    scheduler:dfs_collect(N, Reverse, V1, V2, [], Members0),
    sort(Members0, Members),
    scheduler:collect_sccs(Ns, Reverse, V2, V, [Members|SCCs0], SCCs)
  ).

scheduler:dfs_collect(N, Reverse, V0, V, Acc0, Acc) :-
  Acc1 = [N|Acc0],
  ( get_assoc(N, Reverse, Neigh) -> true ; Neigh = [] ),
  scheduler:dfs_collect_list(Neigh, Reverse, V0, V, Acc1, Acc).

scheduler:dfs_collect_list([], _Reverse, V, V, Acc, Acc).
scheduler:dfs_collect_list([M|Ms], Reverse, V0, V, Acc0, Acc) :-
  ( get_assoc(M, V0, true) ->
      scheduler:dfs_collect_list(Ms, Reverse, V0, V, Acc0, Acc)
  ; put_assoc(M, V0, true, V1),
    scheduler:dfs_collect(M, Reverse, V1, V2, Acc0, Acc1),
    scheduler:dfs_collect_list(Ms, Reverse, V2, V, Acc1, Acc)
  ).


% -----------------------------------------------------------------------------
%  Components and scheduling
% -----------------------------------------------------------------------------

scheduler:build_components(SCCs, Forward, CompMap, Comps) :-
  empty_assoc(M0),
  scheduler:build_components_(SCCs, Forward, 1, M0, CompMap, [], CompsRev),
  reverse(CompsRev, Comps).

scheduler:build_components_([], _Forward, _I, M, M, Comps, Comps).
scheduler:build_components_([Members|Rest], Forward, I, M0, M, Comps0, Comps) :-
  scheduler:component_kind(Members, Forward, Kind),
  foldl(scheduler:compmap_put(I), Members, M0, M1),
  Comps1 = [comp(I, Kind, Members)|Comps0],
  I1 is I + 1,
  scheduler:build_components_(Rest, Forward, I1, M1, M, Comps1, Comps).

scheduler:compmap_put(Id, Node, In, Out) :-
  put_assoc(Node, In, Id, Out).

% Component kind:
% - merge_set: cyclic SCC of mergeable literals (:run or merge actions)
% - bad: cyclic SCC containing any other literal kind
% - single: singleton SCC with no self-loop
scheduler:component_kind(Members, Forward, Kind) :-
  ( Members = [Only] ->
      ( scheduler:self_loop(Only, Forward) ->
          ( scheduler:all_mergeable(Members) -> Kind = merge_set ; Kind = bad )
      ; Kind = single
      )
  ; % size > 1
    ( scheduler:all_mergeable(Members) -> Kind = merge_set ; Kind = bad )
  ).

scheduler:self_loop(Node, Forward) :-
  get_assoc(Node, Forward, Ns),
  memberchk(Node, Ns).

scheduler:all_mergeable([]).
scheduler:all_mergeable([H|T]) :-
  scheduler:is_mergeable_literal(H),
  scheduler:all_mergeable(T).

scheduler:is_run_literal(_Repo://_Ebuild:run) :- !.
scheduler:is_run_literal(_Something:run) :- !.

% Merge actions that can be part of a merge set SCC.
scheduler:is_merge_action_literal(_Repo://_Ebuild:install) :- !.
scheduler:is_merge_action_literal(_Repo://_Ebuild:update) :- !.
scheduler:is_merge_action_literal(_Repo://_Ebuild:reinstall) :- !.
scheduler:is_merge_action_literal(_Something:install) :- !.
scheduler:is_merge_action_literal(_Something:update) :- !.
scheduler:is_merge_action_literal(_Something:reinstall) :- !.

scheduler:is_mergeable_literal(H) :-
  ( scheduler:is_run_literal(H)
  ; scheduler:is_merge_action_literal(H)
  ),
  !.

% Compute the set of components that are blocked (unschedulable):
% - all 'bad' cyclic components
% - all components that (transitively) depend on a bad component
scheduler:blocked_components(Comps, Forward, CompMap, BlockedIds) :-
  findall(Id, member(comp(Id, bad, _), Comps), BadIds0),
  sort(BadIds0, BadIds),
  scheduler:comp_edges(Forward, CompMap, Edges),
  scheduler:reverse_comp_edges(Edges, RevEdges),
  scheduler:closure_from(BadIds, RevEdges, BadClosure),
  sort(BadClosure, BlockedIds).

scheduler:comp_edges(Forward, CompMap, Edges) :-
  assoc:assoc_to_list(Forward, Pairs),
  findall(edge(CU, CV),
          ( member(U-Ns, Pairs),
            get_assoc(U, CompMap, CU),
            member(V, Ns),
            get_assoc(V, CompMap, CV),
            CU \= CV
          ),
          Edges0),
  sort(Edges0, Edges).

scheduler:reverse_comp_edges(Edges, RevEdges) :-
  findall(edge(To, From), member(edge(From, To), Edges), Rev0),
  sort(Rev0, RevEdges).

scheduler:closure_from(Seeds, RevEdges, Closure) :-
  empty_assoc(V0),
  scheduler:closure_queue(Seeds, RevEdges, V0, _V, [], Closure).

scheduler:closure_queue([], _RevEdges, V, V, Acc, Acc).
scheduler:closure_queue([X|Xs], RevEdges, V0, V, Acc0, Acc) :-
  ( get_assoc(X, V0, true) ->
      scheduler:closure_queue(Xs, RevEdges, V0, V, Acc0, Acc)
  ; put_assoc(X, V0, true, V1),
    findall(N, member(edge(X, N), RevEdges), Ns),
    append(Ns, Xs, Q1),
    scheduler:closure_queue(Q1, RevEdges, V1, V, [X|Acc0], Acc)
  ).

scheduler:schedulable_component_waves(Comps, Forward, CompMap, BlockedIds, Waves) :-
  scheduler:comp_edges(Forward, CompMap, Edges),
  findall(Id, (member(comp(Id, Kind, _), Comps), Kind \= bad, \+ memberchk(Id, BlockedIds)), Sched0),
  sort(Sched0, Sched),
  scheduler:kahn_waves(Sched, Edges, Waves).

scheduler:kahn_waves(Sched, Edges, Waves) :-
  % Performance: implement Kahn using a reverse adjacency map so we only touch
  % nodes whose indegree changes, rather than scanning all nodes/edges per wave.
  scheduler:indegrees(Sched, Edges, Indeg0),
  scheduler:rev_adj_map(Sched, Edges, RevAdj),
  scheduler:assoc_set_from_list(Sched, RemSet0),
  scheduler:ready_nodes(Sched, Indeg0, Ready0),
  scheduler:kahn_loop_fast(Ready0, RemSet0, RevAdj, Indeg0, [], WavesRev),
  reverse(WavesRev, Waves).

scheduler:indegrees(Nodes, Edges, Indeg) :-
  empty_assoc(E),
  foldl(scheduler:init_zero, Nodes, E, I0),
  foldl(scheduler:add_edge_indegree(Nodes), Edges, I0, Indeg).

scheduler:init_zero(N, In, Out) :- put_assoc(N, In, 0, Out).

scheduler:add_edge_indegree(Nodes, edge(From, To), In, Out) :-
  ( memberchk(From, Nodes), memberchk(To, Nodes) ->
      get_assoc(From, In, D0),
      D is D0 + 1,
      put_assoc(From, In, D, Out)
  ; Out = In
  ).

scheduler:ready_nodes(Nodes, Indeg, Ready) :-
  findall(N, (member(N, Nodes), get_assoc(N, Indeg, 0)), Ready).

scheduler:kahn_loop([], _Nodes, _Edges, _Indeg, Waves, Waves).
scheduler:kahn_loop(Ready, Nodes, Edges, Indeg0, Waves0, Waves) :-
  Ready \= [],
  Wave = Ready,
  scheduler:remove_wave(Wave, Nodes, Nodes1),
  scheduler:decrement_dependents(Wave, Edges, Indeg0, Indeg1, Nodes1, Ready1),
  scheduler:kahn_loop(Ready1, Nodes1, Edges, Indeg1, [Wave|Waves0], Waves).

scheduler:remove_wave(Wave, Nodes, Nodes1) :-
  subtract(Nodes, Wave, Nodes1).

scheduler:decrement_dependents(Wave, Edges, Indeg0, Indeg, RemainingNodes, NextReady) :-
  foldl(scheduler:dec_for_node(Wave, Edges), RemainingNodes, Indeg0, Indeg),
  scheduler:ready_nodes(RemainingNodes, Indeg, NextReady).

% If N depends on any node in Wave, decrement its indegree.
scheduler:dec_for_node(Wave, Edges, N, In, Out) :-
  findall(Dep, (member(edge(N, Dep), Edges), memberchk(Dep, Wave)), Deps),
  length(Deps, K),
  ( K =:= 0 ->
      Out = In
  ; get_assoc(N, In, D0),
    D is max(0, D0 - K),
    put_assoc(N, In, D, Out)
  ).

% -----------------------------------------------------------------------------
%  Faster Kahn implementation
% -----------------------------------------------------------------------------

% Build a reverse adjacency map Dep -> [From...], restricted to nodes in Sched.
scheduler:rev_adj_map(Nodes, Edges, RevAdj) :-
  empty_assoc(M0),
  foldl(scheduler:rev_adj_put(Nodes), Edges, M0, RevAdj),
  !.

scheduler:rev_adj_put(Nodes, edge(From, To), In, Out) :-
  ( memberchk(From, Nodes), memberchk(To, Nodes) ->
      ( get_assoc(To, In, L0) -> true ; L0 = [] ),
      ( memberchk(From, L0) -> L1 = L0 ; L1 = [From|L0] ),
      put_assoc(To, In, L1, Out)
  ; Out = In
  ).

scheduler:assoc_set_from_list(List, Set) :-
  empty_assoc(S0),
  foldl(scheduler:assoc_set_put, List, S0, Set),
  !.

scheduler:kahn_loop_fast([], _RemSet, _RevAdj, _Indeg, Waves, Waves) :- !.
scheduler:kahn_loop_fast(Ready0, RemSet0, RevAdj, Indeg0, Waves0, Waves) :-
  % Current wave is the current ready set.
  Wave = Ready0,
  % Remove wave nodes from remaining set.
  scheduler:assoc_set_remove_all(Wave, RemSet0, RemSet1),
  % Decrement dependents and compute next ready set.
  scheduler:dec_dependents_for_wave(Wave, RemSet1, RevAdj, Indeg0, Indeg, NextReady),
  scheduler:kahn_loop_fast(NextReady, RemSet1, RevAdj, Indeg, [Wave|Waves0], Waves).

scheduler:assoc_set_remove_all([], Set, Set) :- !.
scheduler:assoc_set_remove_all([K|Ks], Set0, Set) :-
  ( del_assoc(K, Set0, _V, Set1) -> true ; Set1 = Set0 ),
  scheduler:assoc_set_remove_all(Ks, Set1, Set).

scheduler:dec_dependents_for_wave(Wave, RemSet, RevAdj, Indeg0, Indeg, NextReady) :-
  empty_assoc(R0),
  scheduler:dec_dependents_for_wave_(Wave, RemSet, RevAdj, Indeg0, Indeg, R0, R),
  assoc:assoc_to_keys(R, NextReady).

scheduler:dec_dependents_for_wave_([], _RemSet, _RevAdj, Indeg, Indeg, R, R) :- !.
scheduler:dec_dependents_for_wave_([Dep|Deps], RemSet, RevAdj, Indeg0, Indeg, R0, R) :-
  ( get_assoc(Dep, RevAdj, Froms0) -> true ; Froms0 = [] ),
  scheduler:dec_dependents_list(Froms0, RemSet, Indeg0, Indeg1, R0, R1),
  scheduler:dec_dependents_for_wave_(Deps, RemSet, RevAdj, Indeg1, Indeg, R1, R).

scheduler:dec_dependents_list([], _RemSet, Indeg, Indeg, R, R) :- !.
scheduler:dec_dependents_list([N|Ns], RemSet, Indeg0, Indeg, R0, R) :-
  ( get_assoc(N, RemSet, true) ->
      ( get_assoc(N, Indeg0, D0) -> true ; D0 = 0 ),
      D1 is max(0, D0 - 1),
      put_assoc(N, Indeg0, D1, Indeg1),
      ( D1 =:= 0 ->
          put_assoc(N, R0, true, R1)
      ; R1 = R0
      )
  ; Indeg1 = Indeg0,
    R1 = R0
  ),
  scheduler:dec_dependents_list(Ns, RemSet, Indeg1, Indeg, R1, R).

scheduler:expand_component_waves_from_map([], _Comps, _HeadRuleMap, []).
scheduler:expand_component_waves_from_map([WaveIds|Rest], Comps, HeadRuleMap, [WaveRules|Out]) :-
  findall(Rule,
          ( member(Id, WaveIds),
            member(comp(Id, _Kind, Members), Comps),
            member(H, Members),
            get_assoc(H, HeadRuleMap, Rule)
          ),
          WaveRules0),
  reverse(WaveRules0, WaveRules),
  scheduler:expand_component_waves_from_map(Rest, Comps, HeadRuleMap, Out).

scheduler:remainder_from_blocked_from_map([], _Comps, _HeadRuleMap, []).
scheduler:remainder_from_blocked_from_map(BlockedIds, Comps, HeadRuleMap, RemainderOut) :-
  findall(Rule,
          ( member(comp(Id, _Kind, Members), Comps),
            memberchk(Id, BlockedIds),
            member(H, Members),
            get_assoc(H, HeadRuleMap, Rule)
          ),
          RemainderOut0),
  sort(RemainderOut0, RemainderOut).


% -----------------------------------------------------------------------------
%  Proof access (same logic as planner:get_full_rule_from_proof/3)
% -----------------------------------------------------------------------------

scheduler:get_full_rule_from_proof(Literal, ProofAVL, FullRule) :-
  (   ProofKey = rule(Literal),
      get_assoc(ProofKey, ProofAVL, ProofValue)
  ;   ProofKey = assumed(rule(Literal)),
      get_assoc(ProofKey, ProofAVL, ProofValue)
  ;   ProofKey = rule(assumed(Literal)),
      get_assoc(ProofKey, ProofAVL, ProofValue)
  ),
  !,
  prover:canon_rule(FullRule, ProofKey, ProofValue).


