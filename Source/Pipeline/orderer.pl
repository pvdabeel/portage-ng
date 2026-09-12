/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> ORDERER
Order stage (pass 2): when to build — plans as proofs.

Thin pipeline stage that runs the generic prover a second time, handing
it the `ordering` rule set (Source/Domain/Gentoo/Rules/ordering.pl: planning
laws + Gentoo bindings) to construct a provably correct ordering of the
pass-1 solution, then projects the availability proofs onto the
wave-list Plan.  The counterpart stage is the resolver
(Source/Pipeline/resolver.pl), which hands the same prover the
`resolving` rule set.  See Documentation/Handbook/13-doc-planning.md for
the design.

Pass-2 literal language (all ground, built over pass-1 proof keys):

  - scheduled(H)        : step H can be placed (its proof is H's placement
                          justification)
  - available(H, D)     : hard requirement D of step H is satisfiable in
                          time — by an earlier plan step, by the installed
                          world, or (exceptionally) assumed unreachable
  - assumed(unreachable(H, D)) : negative domain assumption — no step and
                          no installed package can provide D for H (the
                          genuine bootstrap case)

The consumer H is part of the availability literal on purpose: whether a
requirement is bridged by the world depends on the consumer's position in
the derivation (cycle membership) and on the consumer's own constraints,
so availability proofs must not be shared across consumers. scheduled/1
proofs are position-independent and memoize globally through the prover's
proven fast path.

Preferences (runtime deps, PDEPEND ordering hints) never appear as
scheduled/1 conditions: a preference is not a promise, so it cannot be
allowed to force a world bridge or an unreachable assumption somewhere
down a cyclic chain. The wave projection honors preferences after the
hard structure is fixed — each is accepted exactly when it closes no
cycle against the hard edges and the previously accepted preferences
(Handbook chapter 12, "Preferences: honored exactly when safe").

The wave-list Plan is a projection over the pass-2 proofs: an evaluator,
not a decider (Handbook chapter 12, "Wave projection and plan output").
Its output contract is the one the printer and builder have always
consumed: a list of waves of full-format pass-1 rule terms.
*/

:- module(orderer, []).

:- use_module(library(assoc)).

% =============================================================================
%  ORDERER declarations
% =============================================================================

% -----------------------------------------------------------------------------
% Pass state
% -----------------------------------------------------------------------------

%! orderer:with_ordering_pass(+Pass1Proof, :Goal)
%
% Run Goal with the pass-1 proof published for the ordering rule set's
% bindings (ordering:step/1 and friends) and the per-pass indexes reset.
% The rule set itself needs no dispatch flag: the pass-2 prove names the
% `ordering` module explicitly (prover:prove_once(ordering, ...)).

with_ordering_pass(Pass1Proof, Goal) :-
  setup_call_cleanup(
    ( nb_setval(portage_ordering_proof, Pass1Proof),
      ordering:prepare_pass
    ),
    Goal,
    nb_setval(portage_ordering_proof, t)).


% -----------------------------------------------------------------------------
% Pass-2 driver
% -----------------------------------------------------------------------------

%! orderer:order(+Pass1Proof, +TriggersAVL, -ProofOut, -Plan)
%
% The pass-2 entry point, called from the pipeline after the pass-1
% prove.
%
% Proves scheduled(H) for every pass-1 proof step, projects the
% availability proofs to the wave-list Plan structure, and merges
% any unreachable/2 assumptions into ProofOut so the printer's assumption
% machinery (which reads the proof) reports them.

order(Pass1Proof, TriggersAVL, ProofOut, Plan) :-
  orderer:steps_of_proof(Pass1Proof, Steps),
  findall(scheduled(H), member(H, Steps), Goals),
  orderer:with_ordering_pass(Pass1Proof,
    ( once(prover:prove_once(ordering, Goals, t, OrdProof, t, _OrdModel, t, _OrdCons, t, _OrdTrig)),
      orderer:preference_edges(Steps, Prefs)
    )),
  orderer:provider_edges(OrdProof, Edges),
  orderer:assign_waves(Steps, Edges, WaveAVL0),
  orderer:honor_preferences(Prefs, Edges, WaveAVL0, WaveAVL),
  orderer:project_plan(Pass1Proof, WaveAVL, Plan0),
  orderer:merge_unreachable(OrdProof, Pass1Proof, ProofOut),
  orderer:merge_order_bias(ProofOut, TriggersAVL, Plan0, Plan).


%! orderer:steps_of_proof(+ProofAVL, -Steps)
%
% Collect the canonical heads of every pass-1 proof rule: keys rule(L)
% and assumed(rule(L)). Skips the non-rule key families (cycle_path/1
% diagnostics, obligation_done/1 and obligation_pending/1 bookkeeping).
% Result is sorted (deterministic driver order) and duplicate-free.

steps_of_proof(ProofAVL, Steps) :-
  findall(H,
          ( assoc:gen_assoc(Key, ProofAVL, _),
            ( Key = rule(H) -> true
            ; Key = assumed(rule(H))
            )
          ),
          Heads),
  sort(Heads, Steps).


%! orderer:preference_edges(+Steps, -Prefs)
%
% Sorted list of H-D preference pairs ("H would like D placed earlier"),
% read from the pass-1 proof by the domain view. Enumerated inside the
% ordering pass (the view reads the published proof).

preference_edges(Steps, Prefs) :-
  findall(H-D,
          ( member(H, Steps),
            ordering:prefers(H, D)
          ),
          Prefs0),
  sort(Prefs0, Prefs).


% -----------------------------------------------------------------------------
% Projection: waves read off the availability proofs
% -----------------------------------------------------------------------------
%
% An evaluator, not a decider: a step's wave is one more than the latest
% wave among the providers its availability proofs cite; steps whose
% requirements were all world-provided land in wave 1. The provider edge
% set is acyclic by construction — the guard makes a cyclic
% step-availability derivation fail into the world clause, so no
% availability proof can cite an ancestor.

%! orderer:provider_edges(+OrdProof, -EdgesAVL)
%
% EdgesAVL maps each consumer H to the list of providers D whose
% scheduled/1 proofs H's availability proofs cite.

provider_edges(OrdProof, Edges) :-
  findall(H-D,
          ( assoc:gen_assoc(rule(available(H, D)), OrdProof, Value),
            Value = dep(_, [scheduled(D)])?_
          ),
          Pairs),
  keysort(Pairs, Sorted),
  orderer:group_pairs(Sorted, Grouped),
  ord_list_to_assoc(Grouped, Edges).

group_pairs([], []) :- !.
group_pairs([H-D|Rest], [H-[D|Ds]|Groups]) :-
  orderer:group_pairs_same(Rest, H, Ds, Tail),
  orderer:group_pairs(Tail, Groups).

group_pairs_same([H-D|Rest], H, [D|Ds], Tail) :-
  !,
  orderer:group_pairs_same(Rest, H, Ds, Tail).
group_pairs_same(Rest, _, [], Rest).


%! orderer:assign_waves(+Steps, +EdgesAVL, -WaveAVL)
%
% Least-wave assignment: memoized depth-first evaluation of
% wave(H) = 1 + max(wave(D) for providers D), 1 when H has none.

assign_waves(Steps, Edges, WaveAVL) :-
  empty_assoc(W0),
  foldl(orderer:assign_wave(Edges), Steps, W0, WaveAVL).

assign_wave(Edges, H, WIn, WOut) :-
  orderer:wave_of(H, Edges, WIn, WOut, _Wave).

wave_of(H, Edges, WIn, WOut, Wave) :-
  ( get_assoc(H, WIn, Wave) ->
      WOut = WIn
  ; get_assoc(H, Edges, Providers) ->
      orderer:waves_of(Providers, Edges, WIn, WMid, 0, Deepest),
      Wave is Deepest + 1,
      put_assoc(H, WMid, Wave, WOut)
  ; Wave = 1,
    put_assoc(H, WIn, Wave, WOut)
  ).

waves_of([], _, W, W, Max, Max) :- !.
waves_of([D|Ds], Edges, WIn, WOut, MaxIn, MaxOut) :-
  orderer:wave_of(D, Edges, WIn, WMid, WD),
  MaxMid is max(MaxIn, WD),
  orderer:waves_of(Ds, Edges, WMid, WOut, MaxMid, MaxOut).


% -----------------------------------------------------------------------------
% Preference honoring (soft requirements)
% -----------------------------------------------------------------------------
%
% A preference H-D ("D earlier than H") is accepted exactly when it closes
% no cycle against the hard edges and the previously accepted preferences;
% accepted preferences delay H (and, transitively, H's consumers) — they
% can never pull D earlier, so hard availability is preserved by
% construction.
%
% Which preferences reach this fold is the ordering strategy's business
% (ordering:prefers/2, `--optimize`). Under the default `parallelism`
% strategy the bindings already withhold every preference that lies on a
% cycle, so the set handed in is acyclic and the fold is a pure
% evaluator: the cycle branch below is never taken. Under
% `soft-requirements` the raw preferences arrive, conflicts (the cyclic
% case) are resolved here in processing order, and the ones processed
% later are simply not honored — silently and safely, matching the
% retired scheduler's :run relaxation but without SCC machinery.
%
% Cycle test: accepting H-D is unsafe iff H is reachable from D over the
% accepted edge set (consumer -> provider direction). Preferences whose
% provider already sits in an earlier wave are recorded without any
% reachability walk (the wave invariant proves acyclicity), so the walk
% only runs for the contested minority.

%! orderer:honor_preferences(+Prefs, +HardEdges, +WaveIn, -WaveOut)
%
% Fold the sorted preference list over the wave assignment.

honor_preferences(Prefs, HardEdges, WaveIn, WaveOut) :-
  orderer:reverse_edges(HardEdges, Consumers),
  foldl(orderer:honor_preference,
        Prefs,
        state(HardEdges, Consumers, WaveIn),
        state(_, _, WaveOut)).

honor_preference(H-D,
                 state(Edges, Consumers, Waves),
                 state(EdgesOut, ConsumersOut, WavesOut)) :-
  ( get_assoc(H, Waves, WH),
    get_assoc(D, Waves, WD)
  ->
    ( WD < WH ->
        % Already satisfied: record the edge so later preferences cannot
        % contradict this one, no waves move.
        orderer:add_edge(H, D, Edges, Consumers, EdgesOut, ConsumersOut),
        WavesOut = Waves
    ; orderer:reachable(D, H, Edges) ->
        % Honoring would close a cycle: skip.
        EdgesOut = Edges, ConsumersOut = Consumers, WavesOut = Waves
    ; % Accept: delay H after D and cascade the delay to H's consumers.
      orderer:add_edge(H, D, Edges, Consumers, EdgesOut, ConsumersOut),
      W1 is WD + 1,
      orderer:raise_wave(H, W1, ConsumersOut, Waves, WavesOut)
    )
  ; % One side is not a step (defensive): nothing to order.
    EdgesOut = Edges, ConsumersOut = Consumers, WavesOut = Waves
  ).

add_edge(H, D, Edges, Consumers, EdgesOut, ConsumersOut) :-
  ( get_assoc(H, Edges, Ds) -> true ; Ds = [] ),
  put_assoc(H, Edges, [D|Ds], EdgesOut),
  ( get_assoc(D, Consumers, Hs) -> true ; Hs = [] ),
  put_assoc(D, Consumers, [H|Hs], ConsumersOut).

reverse_edges(Edges, Consumers) :-
  findall(D-H,
          ( assoc:gen_assoc(H, Edges, Ds),
            member(D, Ds)
          ),
          Pairs),
  keysort(Pairs, Sorted),
  orderer:group_pairs(Sorted, Grouped),
  ord_list_to_assoc(Grouped, Consumers).


%! orderer:reachable(+From, +To, +EdgesAVL)
%
% To is reachable from From over consumer -> provider edges
% (visited-set depth-first walk).

reachable(From, To, _Edges) :-
  From == To,
  !.
reachable(From, To, Edges) :-
  empty_assoc(Visited),
  orderer:reachable_walk([From], To, Edges, Visited).

reachable_walk([Node|_], To, _Edges, _Visited) :-
  Node == To,
  !.
reachable_walk([Node|Rest], To, Edges, Visited) :-
  ( get_assoc(Node, Visited, _) ->
      orderer:reachable_walk(Rest, To, Edges, Visited)
  ; put_assoc(Node, Visited, true, V1),
    ( get_assoc(Node, Edges, Providers) -> true ; Providers = [] ),
    append(Providers, Rest, Queue),
    orderer:reachable_walk(Queue, To, Edges, V1)
  ).


%! orderer:raise_wave(+H, +MinWave, +ConsumersAVL, +WavesIn, -WavesOut)
%
% Ensure wave(H) >= MinWave and cascade to H's consumers (each must stay
% strictly after its providers). Waves only ever increase, so the cascade
% terminates.

raise_wave(H, MinWave, Consumers, WavesIn, WavesOut) :-
  ( get_assoc(H, WavesIn, W), W >= MinWave ->
      WavesOut = WavesIn
  ; put_assoc(H, WavesIn, MinWave, W1),
    ( get_assoc(H, Consumers, Cs) -> true ; Cs = [] ),
    W2 is MinWave + 1,
    foldl(orderer:raise_consumer(Consumers, W2), Cs, W1, WavesOut)
  ).

raise_consumer(Consumers, MinWave, C, WavesIn, WavesOut) :-
  orderer:raise_wave(C, MinWave, Consumers, WavesIn, WavesOut).


% -----------------------------------------------------------------------------
% Plan emission
% -----------------------------------------------------------------------------

%! orderer:project_plan(+Pass1Proof, +WaveAVL, -Plan)
%
% Emit the wave-list Plan: for every pass-1 proof rule, the
% full-format rule term (prover:canon_rule/3 — heads keep their ?{Ctx},
% bodies come along) placed in its head's wave. When a head has both a
% rule(L) and an assumed(rule(L)) entry (pass-1 cycle break), only the
% complete rule(L) term is emitted — one plan item per action
% (membership invariant).

project_plan(Pass1Proof, WaveAVL, Plan) :-
  findall(Wave-Full,
          ( assoc:gen_assoc(Key, Pass1Proof, Value),
            ( Key = rule(H)
            ; Key = assumed(rule(H)),
              \+ get_assoc(rule(H), Pass1Proof, _)
            ),
            prover:canon_rule(Full, Key, Value),
            ( get_assoc(H, WaveAVL, Wave) -> true ; Wave = 1 )
          ),
          Pairs),
  keysort(Pairs, Sorted),
  ( Sorted == [] ->
      Plan = []
  ; last(Sorted, MaxWave-_),
    orderer:buckets(1, MaxWave, Sorted, Plan)
  ).

buckets(W, MaxWave, _, []) :-
  W > MaxWave,
  !.
buckets(W, MaxWave, Pairs, [Wave|Waves]) :-
  orderer:take_wave(Pairs, W, Wave, Rest),
  W1 is W + 1,
  orderer:buckets(W1, MaxWave, Rest, Waves).

take_wave([W-Full|Rest], W, [Full|Fs], Tail) :-
  !,
  orderer:take_wave(Rest, W, Fs, Tail).
take_wave(Rest, _, [], Rest).


% -----------------------------------------------------------------------------
% Unreachable assumptions: merge into the proof handed downstream
% -----------------------------------------------------------------------------

%! orderer:merge_unreachable(+OrdProof, +Pass1Proof, -ProofOut)
%
% Copy the pass-2 rule(assumed(unreachable(H,D))) entries into the proof
% handed to the printer/builder, so unreachable requirements surface
% through the existing domain-assumption reporting (they classify as a
% negative assumption; see assumption:assumption_type/2).

merge_unreachable(OrdProof, Pass1Proof, ProofOut) :-
  findall(Key-Value,
          ( assoc:gen_assoc(Key, OrdProof, Value),
            Key = rule(assumed(unreachable(_, _)))
          ),
          Pairs),
  foldl(orderer:put_pair, Pairs, Pass1Proof, ProofOut).

put_pair(Key-Value, In, Out) :-
  put_assoc(Key, In, Value, Out).


% -----------------------------------------------------------------------------
%  Test helpers (mirror prover.pl / printer.pl)
% -----------------------------------------------------------------------------

%! orderer:test(+Repository)
%
% Tests the ordering engine (prove -> order) over every repository
% entry.

test(Repository) :-
  config:test_style(Style),
  orderer:test(Repository, Style).

%! orderer:test(+Repository,+Style)
test(Repository, Style) :-
  config:proving_target(Action0),
  tester:test_action(Action0, Action),
  tester:test(Style, 'Ordering', Repository://Entry, (Repository:entry(Entry)),
    ( pipeline:prove_with_fallback([Repository://Entry:Action?{[]}],ProofAVL,_ModelAVL,TriggersAVL),
      orderer:order(ProofAVL,TriggersAVL,_ProofOut,_Plan)
    )),
  nl.


%! orderer:test_latest(+Repository)
%
% Same as orderer:test(+Repository), but only tests highest version of every package.

test_latest(Repository) :-
  config:test_style(Style),
  orderer:test_latest(Repository, Style).

%! orderer:test_latest(+Repository,+Style)
test_latest(Repository, Style) :-
  config:proving_target(Action0),
  tester:test_action(Action0, Action),
  tester:test(Style, 'Ordering latest', Repository://Entry,
              (Repository:package(C,N),once(Repository:ebuild(Entry,C,N,_))),
              ( pipeline:prove_with_fallback([Repository://Entry:Action?{[]}],ProofAVL,_ModelAVL,TriggersAVL),
                orderer:order(ProofAVL,TriggersAVL,_ProofOut,_Plan)
              )),
  nl.


%! orderer:test_stats(+Repository)
%
% Whole-repository run with proving statistics.

test_stats(Repository) :-
  config:test_style(Style),
  orderer:test_stats(Repository, Style).

%! orderer:test_stats(+Repository,+Style)
test_stats(Repository, Style) :-
  config:proving_target(Action0),
  tester:test_action(Action0, Action),
  aggregate_all(count, (Repository:entry(_E)), ExpectedTotal),
  sampler:reset('Ordering', ExpectedTotal),
  aggregate_all(count, (Repository:package(_C,_N)), ExpectedPkgs),
  sampler:set_expected_pkgs(ExpectedPkgs),
  tester:test(Style,
              'Ordering',
              Repository://Entry,
              (Repository:entry(Entry)),
              ( pipeline:prove_with_fallback([Repository://Entry:Action?{[]}],ProofAVL,ModelAVL,TriggersAVL),
                orderer:order(ProofAVL,TriggersAVL,_ProofOut,_Plan),
                sampler:record(entry(Repository://Entry, ModelAVL, ProofAVL, TriggersAVL, true))
              )),
  stats:test_stats_print.


% -----------------------------------------------------------------------------
%  Merge-order bias: within-wave reordering by reference count
% -----------------------------------------------------------------------------
%
% Portage's _merge_order_bias() sorts nodes by descending reference count
% (number of parent/dependent nodes in the graph).  Packages depended on by
% more things are installed first, since they satisfy the most constraints
% earliest.  This matches Portage's leaf-node selection order.
%
% Engine-agnostic presentation pass (Plan + Triggers in, Plan out),
% inherited from the retired classic scheduler: it orders rules inside a
% wave and never moves anything across waves, so it cannot violate an
% availability proof.

%! orderer:merge_order_bias(+ProofAVL, +TriggersAVL, +PlanIn, -PlanOut)
%
% Reorder rules within each wave of PlanIn by descending reference count.

merge_order_bias(_ProofAVL, TriggersAVL, PlanIn, PlanOut) :-
  append(PlanIn, AllRules),
  ( AllRules == [] -> PlanOut = PlanIn
  ;
    orderer:build_refcount_map(AllRules, TriggersAVL, RefCountMap),
    orderer:reorder_waves_by_refcount(PlanIn, RefCountMap, PlanOut)
  ).


%! orderer:build_refcount_map(+AllRules, +TriggersAVL, -RefCountMap)
%
% For each rule head in the plan, count how many OTHER planned heads trigger
% on it (= reference count / number of dependents in the full graph).

build_refcount_map(AllRules, TriggersAVL, RefCountMap) :-
  empty_assoc(HeadSet0),
  foldl(orderer:add_rule_to_head_set_, AllRules, HeadSet0, HeadSet),
  assoc_to_keys(HeadSet, AllHeads),
  empty_assoc(M0),
  foldl(orderer:compute_refcount(TriggersAVL, HeadSet), AllHeads, M0, RefCountMap).

add_rule_to_head_set_(Rule, In, Out) :-
  ( prover:rule_head(Rule, Head) ->
      put_assoc(Head, In, true, Out)
  ; Out = In
  ).

compute_refcount(TriggersAVL, HeadSet, Head, In, Out) :-
  % The rule set decides which heads count as references to Head (for
  % Gentoo: a merge step and its :run head, ordering:reference_heads/2).
  ordering:reference_heads(Head, TriggerKeys),
  % Assoc-set uniqueness avoids findall + sort over the dependents bag.
  empty_assoc(U0),
  foldl(orderer:refcount_add_key(TriggersAVL, HeadSet, Head),
        TriggerKeys, U0, Unique),
  assoc_to_keys(Unique, UniqueDepHeads),
  length(UniqueDepHeads, Count),
  put_assoc(Head, In, Count, Out).

refcount_add_key(TriggersAVL, HeadSet, Head, TK, In, Out) :-
  ( get_assoc(TK, TriggersAVL, Dependents) ->
      foldl(orderer:refcount_add_dep(HeadSet, Head), Dependents, In, Out)
  ; Out = In
  ).

refcount_add_dep(HeadSet, Head, D0, In, Out) :-
  prover:canon_literal(D0, DepHead, _),
  DepHead \= Head,
  get_assoc(DepHead, HeadSet, _),
  !,
  put_assoc(DepHead, In, true, Out).
refcount_add_dep(_HeadSet, _Head, _D0, In, In).


%! orderer:reorder_waves_by_refcount(+PlanIn, +RefCountMap, -PlanOut)
%
% Sort each wave by descending reference count (stable for equal counts).

reorder_waves_by_refcount([], _, []) :- !.
reorder_waves_by_refcount([Wave|Ws], RefCountMap, [Sorted|Rs]) :-
  findall(NegCount-Rule,
          ( member(Rule, Wave),
            ( prover:rule_head(Rule, Head),
              get_assoc(Head, RefCountMap, Count)
            -> NegCount is -Count
            ; NegCount = 0
            )
          ),
          Pairs),
  keysort(Pairs, SortedPairs),
  findall(Rule, member(_-Rule, SortedPairs), Sorted),
  orderer:reorder_waves_by_refcount(Ws, RefCountMap, Rs).
