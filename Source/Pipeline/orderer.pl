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
:- use_module(library(ordsets)).

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
% The AVL is published by reference (`nb_linkval/2`): `nb_setval/2` would
% deep-copy the tree. The rule set itself needs no dispatch flag: pass 2
% expands `ordering:rule/2` through `orderer:prove_scheduled/2`.

with_ordering_pass(Pass1Proof, Goal) :-
  setup_call_cleanup(
    ( nb_linkval(portage_ordering_proof, Pass1Proof),
      ordering:prepare_pass
    ),
    Goal,
    ( nb_linkval(portage_ordering_proof, t),
      ordering:release_pass
    )).


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
    ( orderer:prove_scheduled(Goals, OrdProof),
      orderer:preference_edges(Steps, Prefs)
    )),
  orderer:step_graph_from_proof(Steps, OrdProof, Graph, Cells),
  orderer:assign_waves(Cells),
  orderer:honor_preferences(Prefs, Graph),
  orderer:merge_unreachable(OrdProof, Pass1Proof, ProofOut),
  orderer:project_plan(Pass1Proof, TriggersAVL, Graph, Plan).


%! orderer:prove_scheduled(+Goals, -OrdProof)
%
% Ordering-only proof kernel: expand `ordering:rule/2` for the
% scheduled/1 goals (and the available/1 / assumed(unreachable/2)
% literals they demand) without the generic prover's model-union,
% constraint, trigger, obligation or reprove machinery. Pass 2 is
% deterministic and never needs those. The prover cycle stack is still
% installed so `ordering:rule(available(_,_), _)` can consult
% `prover:currently_proving/1`.

prove_scheduled(Goals, OrdProof) :-
  prover:with_cycle_stack(
    orderer:prove_lits(Goals, t, OrdProof, t, _Model)).


prove_lits([], Proof, Proof, Model, Model) :- !.
prove_lits([Literal|Rest], Proof0, Proof, Model0, Model) :-
  !,
  orderer:prove_lits(Literal, Proof0, Proof1, Model0, Model1),
  orderer:prove_lits(Rest, Proof1, Proof, Model1, Model).
prove_lits(Lit, Proof0, Proof, Model0, Model) :-
  ( get_assoc(Lit, Model0, _) ->
      Proof = Proof0,
      Model = Model0
  ; ordering:rule(Lit, Body),
    length(Body, Count),
    put_assoc(rule(Lit), Proof0, dep(Count, Body)?{}, Proof1),
    prover:prove_on_cycle_stack(Lit,
      orderer:prove_lits(Body, Proof1, Proof, Model0, BodyModel)),
    put_assoc(Lit, BodyModel, {}, Model)
  ).


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
% read from the per-pass relation index. PDEPEND `order_after` edges are
% placed ahead of competing soft preferences so the parent install
% precedes its post-dependency (portage-ng#124). Enumerated inside the
% ordering pass (the index is built from the published proof).

preference_edges(Steps, Prefs) :-
  ordering:relation_index(RelIdx),
  ( preference:local_flag(optimize_soft_requirements) ->
      SoftReq = true
  ; SoftReq = false
  ),
  orderer:collect_preference_edges(Steps, RelIdx, SoftReq, _CompIdx, OrderAfter, OtherPrefs),
  append(OrderAfter, OtherPrefs, Prefs).


collect_preference_edges([], _RelIdx, _SoftReq, _CompIdx, [], []).
collect_preference_edges([H|Hs], RelIdx, SoftReq, CompIdx, OAOut, OtherOut) :-
  ( get_assoc(H, RelIdx, relations(_, Prefers0, OA)) ->
      ( OA == [] ->
          OAOut = OATail,
          Other0 = Prefers0
      ; orderer:pref_pairs(OA, H, OAOut, OATail),
        ord_subtract(Prefers0, OA, Other0)
      ),
      ( Other0 == [] ->
          OtherOut = OtherTail
      ; SoftReq == true ->
          orderer:pref_pairs(Other0, H, OtherOut, OtherTail)
      ; ( var(CompIdx) -> ordering:component_index(CompIdx) ; true ),
        ( get_assoc(H, CompIdx, CH) ->
            orderer:filter_other_prefs(Other0, H, CH, CompIdx, OtherOut, OtherTail)
        ; orderer:pref_pairs(Other0, H, OtherOut, OtherTail)
        )
      )
  ; OAOut = OATail,
    OtherOut = OtherTail
  ),
  orderer:collect_preference_edges(Hs, RelIdx, SoftReq, CompIdx, OATail, OtherTail).


pref_pairs([], _H, Tail, Tail).
pref_pairs([D|Ds], H, [H-D|Out], Tail) :-
  orderer:pref_pairs(Ds, H, Out, Tail).


filter_other_prefs([], _H, _CH, _CompIdx, Tail, Tail).
filter_other_prefs([D|Ds], H, CH, CompIdx, Out, Tail) :-
  ( get_assoc(D, CompIdx, CD), CD == CH ->
      Out = Out1
  ; Out = [H-D|Out1]
  ),
  orderer:filter_other_prefs(Ds, H, CH, CompIdx, Out1, Tail).


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
% scheduled/1 proofs H's availability proofs cite. Kept for depclean
% (`wave_assignment/3`); the pass-2 driver links cells directly from
% the proof.

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


%! orderer:step_graph_from_proof(+Steps, +OrdProof, -Graph, -Cells)
%
% Graph maps every step to its cell(Id, Wave, ProviderCells,
% ConsumerCells, Stamp). Provider and consumer lists hold the cell
% terms themselves (pointer links), so wave assignment, preference
% honoring and the reachability walk do not look steps up. The AVL is
% built once from the sorted step list; the projection and the
% preference fold update cells in place (setarg/3). Both are
% deterministic, so no update is ever undone by backtracking before
% project_plan reads the waves out.

step_graph_from_proof(Steps, OrdProof, Graph, Cells) :-
  orderer:alloc_step_cells(Steps, 1, Pairs, Cells),
  ord_list_to_assoc(Pairs, Graph),
  orderer:populate_from_proof(OrdProof, Graph, none, none, _, _).


%! orderer:wave_assignment(+Steps, +EdgesAVL, -WaveAVL)
%
% The least-wave assignment as a plain AVL (step -> wave), for callers
% that project availability proofs without honoring preferences
% (depclean:uninstall_order/3, the unmerge pass).

wave_assignment(Steps, Edges, WaveAVL) :-
  orderer:alloc_step_cells(Steps, 1, Pairs, Cells),
  ord_list_to_assoc(Pairs, Graph),
  orderer:populate_from_edges(Edges, Graph),
  orderer:assign_waves(Cells),
  map_assoc(orderer:cell_wave, Graph, WaveAVL).

cell_wave(cell(_Id, Wave, _Providers, _Consumers, _Stamp), Wave).


alloc_step_cells([], _, [], []).
alloc_step_cells([H|Hs], Id0, [H-Cell|Pairs], [Cell|Cells]) :-
  Cell = cell(Id0, none, [], [], 0),
  Id1 is Id0 + 1,
  orderer:alloc_step_cells(Hs, Id1, Pairs, Cells).


populate_from_proof(t, _Graph, PrevH, PrevCell, PrevH, PrevCell) :- !.
populate_from_proof(t(Key, Val, _, L, R), Graph, PrevH0, PrevCell0, PrevH, PrevCell) :-
  orderer:populate_from_proof(L, Graph, PrevH0, PrevCell0, PrevH1, PrevCell1),
  ( Key = rule(available(H, D)),
    Val = dep(_, [scheduled(D)])?_ ->
      ( H == PrevH1 ->
          HCell = PrevCell1
      ; get_assoc(H, Graph, HCell) ->
          true
      ; HCell = none
      ),
      ( HCell \== none,
        get_assoc(D, Graph, DCell) ->
          orderer:add_edge_cells(HCell, DCell)
      ; true
      ),
      orderer:populate_from_proof(R, Graph, H, HCell, PrevH, PrevCell)
  ; orderer:populate_from_proof(R, Graph, PrevH1, PrevCell1, PrevH, PrevCell)
  ).


populate_from_edges(Edges, Graph) :-
  assoc_to_list(Edges, Pairs),
  orderer:add_edge_pairs(Pairs, Graph).

add_edge_pairs([], _).
add_edge_pairs([H-Ds|Rest], Graph) :-
  ( get_assoc(H, Graph, HCell) ->
      orderer:link_providers(Ds, HCell, Graph)
  ; true
  ),
  orderer:add_edge_pairs(Rest, Graph).

link_providers([], _, _).
link_providers([D|Ds], HCell, Graph) :-
  ( get_assoc(D, Graph, DCell) ->
      orderer:add_edge_cells(HCell, DCell)
  ; true
  ),
  orderer:link_providers(Ds, HCell, Graph).


add_edge_cells(HCell, DCell) :-
  arg(3, HCell, Ds),
  setarg(3, HCell, [DCell|Ds]),
  arg(4, DCell, Hs),
  setarg(4, DCell, [HCell|Hs]).


%! orderer:assign_waves(+Cells)
%
% Least-wave assignment: memoized depth-first evaluation of
% wave(H) = 1 + max(wave(D) for provider cells D), 1 when H has none.

assign_waves([]).
assign_waves([Cell|Cells]) :-
  orderer:wave_of_cell(Cell, _),
  orderer:assign_waves(Cells).


wave_of_cell(Cell, Wave) :-
  arg(2, Cell, Known),
  ( Known \== none ->
      Wave = Known
  ; arg(3, Cell, Providers),
    orderer:waves_of_cells(Providers, 0, Deepest),
    Wave is Deepest + 1,
    setarg(2, Cell, Wave)
  ).


waves_of_cells([], Max, Max).
waves_of_cells([DCell|Ds], MaxIn, MaxOut) :-
  orderer:wave_of_cell(DCell, WD),
  MaxMid is max(MaxIn, WD),
  orderer:waves_of_cells(Ds, MaxMid, MaxOut).


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
% strategy the bindings withhold runtime preferences that lie on a cycle
% while keeping explicit `order_after` PDEPEND anchors (portage-ng#124).
% Under `soft-requirements` all raw preferences arrive. In both modes any
% preference that would close a cycle against the hard edges or previously
% accepted preferences is skipped silently and safely here.
%
% Cycle test: accepting H-D is unsafe iff H is reachable from D over the
% accepted edge set (consumer -> provider direction). Preferences whose
% provider already sits in an earlier wave are recorded without any
% reachability walk (the wave invariant proves acyclicity), so the walk
% only runs for the contested minority.
%
% Wave invariant: every edge X -> Y in the accepted set has
% wave(Y) < wave(X). The least-wave assignment establishes it for the
% hard edges, and each accepted preference re-establishes it by raising
% the consumer (and, cascading, its consumers) above the provider. The
% reachability walk relies on it to prune: a node whose wave is at most
% wave(H) cannot reach H (every provider it leads to sits in a strictly
% earlier wave), so the walk only descends into nodes placed after H,
% and a provider in H's own wave cannot reach H at all.

%! orderer:honor_preferences(+Prefs, +Graph)
%
% Fold the sorted preference list over the step graph, updating waves
% and accepted edges in place.

honor_preferences(Prefs, Graph) :-
  Counter = counter(0),
  orderer:honor_preferences_loop(Prefs, Graph, Counter, none, none).

honor_preferences_loop([], _Graph, _Counter, _PrevH, _PrevHCell).
honor_preferences_loop([H-D|Prefs], Graph, Counter, PrevH, PrevHCell) :-
  ( H == PrevH ->
      HCell = PrevHCell
  ; get_assoc(H, Graph, HCell) ->
      true
  ; HCell = none
  ),
  ( HCell \== none,
    get_assoc(D, Graph, DCell),
    arg(2, HCell, WH),
    arg(2, DCell, WD)
  ->
    ( WD < WH ->
        % Already satisfied: record the edge so later preferences cannot
        % contradict this one, no waves move.
        orderer:add_edge_cells(HCell, DCell)
    ; WD > WH,
      orderer:reachable_cell(DCell, HCell, WH, Counter) ->
        % Honoring would close a cycle: skip. (A provider in H's own
        % wave cannot reach H, see the wave invariant above.)
        true
    ; % Accept: delay H after D and cascade the delay to H's consumers.
      orderer:add_edge_cells(HCell, DCell),
      W1 is WD + 1,
      orderer:raise_wave(HCell, W1)
    )
  ; true
  ),
  orderer:honor_preferences_loop(Prefs, Graph, Counter, H, HCell).


%! orderer:reachable_cell(+FromCell, +ToCell, +WaveTo, +Counter)
%
% ToCell is reachable from FromCell over consumer -> provider cell
% links. WaveTo is To's wave: by the wave invariant a provider placed
% in wave WaveTo or earlier cannot lead to To, so such providers are
% not descended (other than To itself). Counter is a stamp incremented
% per walk; cells record the stamp they were last visited with so the
% walk needs no AVL visited-set.

reachable_cell(FromCell, ToCell, _WaveTo, _Counter) :-
  arg(1, FromCell, IdF),
  arg(1, ToCell, IdT),
  IdF =:= IdT,
  !.
reachable_cell(FromCell, ToCell, WaveTo, Counter) :-
  arg(1, Counter, S0),
  S is S0 + 1,
  nb_setarg(1, Counter, S),
  nb_setarg(5, FromCell, S),
  arg(1, ToCell, IdTo),
  arg(3, FromCell, Providers),
  orderer:reachable_providers(Providers, IdTo, WaveTo, S).

reachable_providers([P|_], IdTo, _WaveTo, _S) :-
  arg(1, P, IdP),
  IdP =:= IdTo,
  !.
reachable_providers([P|Ps], IdTo, WaveTo, S) :-
  ( arg(2, P, WP),
    WP > WaveTo,
    arg(5, P, SP),
    SP < S ->
      nb_setarg(5, P, S),
      arg(3, P, PProviders),
      ( orderer:reachable_providers(PProviders, IdTo, WaveTo, S) ->
          true
      ; orderer:reachable_providers(Ps, IdTo, WaveTo, S)
      )
  ; orderer:reachable_providers(Ps, IdTo, WaveTo, S)
  ).


%! orderer:raise_wave(+Cell, +MinWave)
%
% Ensure the step of Cell sits in wave MinWave or later and cascade to
% its consumers (each must stay strictly after its providers). Waves
% only ever increase, so the cascade terminates.

raise_wave(Cell, MinWave) :-
  arg(2, Cell, W),
  ( W >= MinWave ->
      true
  ; setarg(2, Cell, MinWave),
    arg(4, Cell, Consumers),
    W2 is MinWave + 1,
    orderer:raise_consumers(Consumers, W2)
  ).

raise_consumers([], _MinWave).
raise_consumers([CCell|Cs], MinWave) :-
  orderer:raise_wave(CCell, MinWave),
  orderer:raise_consumers(Cs, MinWave).


% -----------------------------------------------------------------------------
% Plan emission
% -----------------------------------------------------------------------------

%! orderer:project_plan(+Pass1Proof, +Graph, -Plan)
%
% Emit the wave-list Plan: for every pass-1 proof rule, the
% full-format rule term (prover:canon_rule/3 — heads keep their ?{Ctx},
% bodies come along) placed in its head's wave. When a head has both a
% rule(L) and an assumed(rule(L)) entry (pass-1 cycle break), only the
% complete rule(L) term is emitted — one plan item per action
% (membership invariant). The 3-argument form does not apply
% merge-order bias; `order/4` uses the 4-argument form below.

project_plan(Pass1Proof, Graph, Plan) :-
  assoc_to_list(Pass1Proof, KVs),
  orderer:plan_pairs_unbiased(KVs, Pass1Proof, Graph, Pairs0),
  keysort(Pairs0, Sorted),
  orderer:bucket_plan(Sorted, Plan).


%! orderer:project_plan(+Pass1Proof, +TriggersAVL, +Graph, -Plan)
%
% Wave projection fused with merge-order bias: a single `keysort/2` on
% `w(Wave, NegCount)-Full` yields wave order and, within each wave,
% descending reference count. Graph doubles as the planned-head set
% the bias uses to count in-plan dependents.

project_plan(Pass1Proof, TriggersAVL, Graph, Plan) :-
  assoc_to_list(Pass1Proof, KVs),
  orderer:plan_pairs_biased(KVs, Pass1Proof, TriggersAVL, Graph, Pairs0),
  keysort(Pairs0, Sorted),
  orderer:bucket_plan_biased(Sorted, Plan).


plan_pairs_unbiased([], _Proof, _Graph, []).
plan_pairs_unbiased([Key-Value|KVs], Proof, Graph, Pairs) :-
  ( orderer:plan_head(Key, Proof, Value, H, Full) ->
      orderer:head_wave(H, Graph, Wave),
      Pairs = [Wave-Full|Rest]
  ; Pairs = Rest
  ),
  orderer:plan_pairs_unbiased(KVs, Proof, Graph, Rest).


plan_pairs_biased([], _Proof, _Triggers, _Graph, []).
plan_pairs_biased([Key-Value|KVs], Proof, TriggersAVL, Graph, Pairs) :-
  ( orderer:plan_head(Key, Proof, Value, H, Full) ->
      orderer:head_wave(H, Graph, Wave),
      orderer:compute_refcount(TriggersAVL, Graph, H, Count),
      NegCount is -Count,
      Pairs = [w(Wave, NegCount)-Full|Rest]
  ; Pairs = Rest
  ),
  orderer:plan_pairs_biased(KVs, Proof, TriggersAVL, Graph, Rest).


plan_head(rule(H), _Proof, Value, H, Full) :-
  !,
  prover:canon_rule(Full, rule(H), Value).
plan_head(assumed(rule(H)), Proof, Value, H, Full) :-
  \+ get_assoc(rule(H), Proof, _),
  prover:canon_rule(Full, assumed(rule(H)), Value).


head_wave(H, Graph, Wave) :-
  ( get_assoc(H, Graph, Cell),
    arg(2, Cell, Wave0),
    Wave0 \== none
  -> Wave = Wave0
  ;  Wave = 1
  ).


bucket_plan([], []) :- !.
bucket_plan(Sorted, Plan) :-
  last(Sorted, MaxWave-_),
  orderer:buckets(1, MaxWave, Sorted, Plan).


bucket_plan_biased([], []) :- !.
bucket_plan_biased(Sorted, Plan) :-
  last(Sorted, w(MaxWave, _)-_),
  orderer:buckets_biased(1, MaxWave, Sorted, Plan).


buckets_biased(W, MaxWave, _, []) :-
  W > MaxWave,
  !.
buckets_biased(W, MaxWave, Pairs, [Wave|Waves]) :-
  orderer:take_wave_biased(Pairs, W, Wave, Rest),
  W1 is W + 1,
  orderer:buckets_biased(W1, MaxWave, Rest, Waves).


take_wave_biased([w(W, _)-Full|Rest], W, [Full|Fs], Tail) :-
  !,
  orderer:take_wave_biased(Rest, W, Fs, Tail).
take_wave_biased(Rest, _, [], Rest).


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

merge_unreachable(t, Proof, Proof) :- !.
merge_unreachable(t(Key, Val, _, L, R), Proof0, Proof) :-
  % rule(assumed(_)) @< rule(available(_,_)) @< rule(scheduled(_)), so a
  % non-assumed node has no assumed keys in its right subtree.
  ( Key = rule(assumed(unreachable(_, _))) ->
      orderer:merge_unreachable(L, Proof0, Proof1),
      put_assoc(Key, Proof1, Val, Proof2),
      orderer:merge_unreachable(R, Proof2, Proof)
  ; orderer:merge_unreachable(L, Proof0, Proof)
  ).


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
  orderer:rule_heads(AllRules, Heads0),
  sort(Heads0, AllHeads),
  orderer:head_set_pairs(AllHeads, HeadPairs),
  ord_list_to_assoc(HeadPairs, HeadSet),
  orderer:refcount_pairs(AllHeads, TriggersAVL, HeadSet, CountPairs),
  ord_list_to_assoc(CountPairs, RefCountMap).

rule_heads([], []).
rule_heads([Rule|Rules], Heads) :-
  ( prover:rule_head(Rule, Head) ->
      Heads = [Head|Heads1]
  ; Heads = Heads1
  ),
  orderer:rule_heads(Rules, Heads1).

head_set_pairs([], []).
head_set_pairs([Head|Heads], [Head-true|Pairs]) :-
  orderer:head_set_pairs(Heads, Pairs).

refcount_pairs([], _TriggersAVL, _HeadSet, []).
refcount_pairs([Head|Heads], TriggersAVL, HeadSet, [Head-Count|Pairs]) :-
  orderer:compute_refcount(TriggersAVL, HeadSet, Head, Count),
  orderer:refcount_pairs(Heads, TriggersAVL, HeadSet, Pairs).

compute_refcount(TriggersAVL, HeadSet, Head, Count) :-
  % The rule set decides which heads count as references to Head (for
  % Gentoo: a merge step and its :run head, ordering:reference_heads/2).
  ordering:reference_heads(Head, TriggerKeys),
  % Collect the planned dependents of every reference head, then count
  % them once each (sort/2 removes duplicates).
  foldl(orderer:refcount_add_key(TriggersAVL, HeadSet, Head),
        TriggerKeys, [], DepHeads),
  ( DepHeads == [] ->
      Count = 0
  ; DepHeads = [_] ->
      Count = 1
  ; sort(DepHeads, UniqueDepHeads),
    length(UniqueDepHeads, Count)
  ).

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
  Out = [DepHead|In].
refcount_add_dep(_HeadSet, _Head, _D0, In, In).


%! orderer:reorder_waves_by_refcount(+PlanIn, +RefCountMap, -PlanOut)
%
% Sort each wave by descending reference count (stable for equal counts).

reorder_waves_by_refcount([], _, []).
reorder_waves_by_refcount([Wave|Ws], RefCountMap, [Sorted|Rs]) :-
  orderer:wave_refcount_pairs(Wave, RefCountMap, Pairs),
  keysort(Pairs, SortedPairs),
  orderer:pair_values(SortedPairs, Sorted),
  orderer:reorder_waves_by_refcount(Ws, RefCountMap, Rs).


wave_refcount_pairs([], _, []).
wave_refcount_pairs([Rule|Rules], RefCountMap, [NegCount-Rule|Pairs]) :-
  ( prover:rule_head(Rule, Head),
    get_assoc(Head, RefCountMap, Count)
  -> NegCount is -Count
  ; NegCount = 0
  ),
  orderer:wave_refcount_pairs(Rules, RefCountMap, Pairs).


pair_values([], []).
pair_values([_-V|Ps], [V|Vs]) :-
  orderer:pair_values(Ps, Vs).
