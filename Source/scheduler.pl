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
- SCCs consisting purely of :run literals are schedulable as merge sets.
- Any SCC containing non-:run literals is treated as unschedulable; all rules
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
  PlanOut = PlanIn.
schedule(ProofAVL, _TriggersAVL, PlanIn, RemainderIn, PlanOut, RemainderOut) :-
  % Only schedule from the planner-provided remainder. Do not remove items from
  % the existing plan here: removing + re-adding must be proven correct, and we
  % currently want a safe scheduler that never drops actions.
  scheduler:remainder_heads(RemainderIn, Heads),
  scheduler:build_forward_reverse(Heads, ProofAVL, Forward, Reverse),
  scheduler:kosaraju_scc(Heads, Forward, Reverse, SCCs),
  scheduler:build_components(SCCs, Forward, CompMap, Comps),
  scheduler:blocked_components(Comps, Forward, CompMap, BlockedCompIds),
  scheduler:schedulable_component_waves(Comps, Forward, CompMap, BlockedCompIds, WavesCompIds),
  scheduler:expand_component_waves(WavesCompIds, Comps, ProofAVL, WavesRules),
  append(PlanIn, WavesRules, PlanOut),
  scheduler:remainder_from_blocked(BlockedCompIds, Comps, ProofAVL, RemainderOut).


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
  config:proving_target(Action),
  tester:test(Style, 'Scheduling', Repository://Entry, (Repository:entry(Entry)),
    ( with_q(prover:prove(Repository://Entry:Action?{[]},t,ProofAVL,t,_ModelAVL,t,_Constraint,t,TriggersAVL)),
      with_q(planner:plan(ProofAVL,TriggersAVL,t,Plan0,Remainder0)),
      with_q(scheduler:schedule(ProofAVL,TriggersAVL,Plan0,Remainder0,_Plan,_Remainder))
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
  config:proving_target(Action),
  tester:test(Style, 'Scheduling latest', Repository://Entry,
              (Repository:package(C,N),once(Repository:ebuild(Entry,C,N,_))),
              ( with_q(prover:prove(Repository://Entry:Action?{[]},t,ProofAVL,t,_ModelAVL,t,_Constraint,t,TriggersAVL)),
                with_q(planner:plan(ProofAVL,TriggersAVL,t,Plan0,Remainder0)),
                with_q(scheduler:schedule(ProofAVL,TriggersAVL,Plan0,Remainder0,_Plan,_Remainder))
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
  config:proving_target(Action),
  aggregate_all(count, (Repository:entry(_E)), ExpectedTotal),
  printer:test_stats_reset('Scheduling', ExpectedTotal),
  aggregate_all(count, (Repository:package(_C,_N)), ExpectedPkgs),
  printer:test_stats_set_expected_unique_packages(ExpectedPkgs),
  tester:test(Style,
              'Scheduling',
              Repository://Entry,
              (Repository:entry(Entry)),
              ( with_q(prover:prove(Repository://Entry:Action?{[]},t,ProofAVL,t,ModelAVL,t,_Constraint,t,TriggersAVL)),
                with_q(planner:plan(ProofAVL,TriggersAVL,t,Plan0,Remainder0)),
                with_q(scheduler:schedule(ProofAVL,TriggersAVL,Plan0,Remainder0,_Plan,_Remainder)),
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
% - merge_set: cyclic SCC of pure :run literals
% - bad: cyclic SCC containing any non-:run literal
% - single: singleton SCC with no self-loop
scheduler:component_kind(Members, Forward, Kind) :-
  ( Members = [Only] ->
      ( scheduler:self_loop(Only, Forward) ->
          ( scheduler:all_run(Members) -> Kind = merge_set ; Kind = bad )
      ; Kind = single
      )
  ; % size > 1
    ( scheduler:all_run(Members) -> Kind = merge_set ; Kind = bad )
  ).

scheduler:self_loop(Node, Forward) :-
  get_assoc(Node, Forward, Ns),
  memberchk(Node, Ns).

scheduler:all_run([]).
scheduler:all_run([H|T]) :-
  scheduler:is_run_literal(H),
  scheduler:all_run(T).

scheduler:is_run_literal(_Repo://_Ebuild:run) :- !.
scheduler:is_run_literal(_Something:run) :- !.

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
  scheduler:indegrees(Sched, Edges, Indeg),
  scheduler:ready_nodes(Sched, Indeg, Ready0),
  scheduler:kahn_loop(Ready0, Sched, Edges, Indeg, [], WavesRev),
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

scheduler:expand_component_waves([], _Comps, _ProofAVL, []).
scheduler:expand_component_waves([WaveIds|Rest], Comps, ProofAVL, [WaveRules|Out]) :-
  findall(Rule,
          ( member(Id, WaveIds),
            member(comp(Id, _Kind, Members), Comps),
            member(H, Members),
            scheduler:get_full_rule_from_proof(H, ProofAVL, Rule)
          ),
          WaveRules0),
  reverse(WaveRules0, WaveRules),
  scheduler:expand_component_waves(Rest, Comps, ProofAVL, Out).

scheduler:remainder_from_blocked([], _Comps, _ProofAVL, []).
scheduler:remainder_from_blocked(BlockedIds, Comps, ProofAVL, RemainderOut) :-
  findall(Rule,
          ( member(comp(Id, _Kind, Members), Comps),
            memberchk(Id, BlockedIds),
            member(H, Members),
            scheduler:get_full_rule_from_proof(H, ProofAVL, Rule)
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


