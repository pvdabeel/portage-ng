/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026w, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> PROVER
    The prover computes a proof, model, constraints, and triggers for a given input.

    This version is enhanced to be configurable:
    - If preference:flag(delay_triggers) is set, it performs a from-scratch build,
      optimizing for backtracking by building the Triggers tree at the end.
    - Otherwise, it performs an incremental build, updating the Triggers
      tree as it proves, which is efficient for small additions.
*/

:- module(prover, [test_action/2]).

:- use_module(unify). % feature_unification:unify/3 for context merging

% =============================================================================
%  PROVER declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Internal override: delay trigger construction
% -----------------------------------------------------------------------------
%
% `preference:flag(delay_triggers)` is a user-level knob, but for certain internal
% computations (notably query-side model construction) we can safely suppress
% trigger maintenance to reduce overhead. We do this in a thread-local way using
% nb_* so it is safe under multi-threading.

prover:delay_triggers :-
  ( nb_current(prover_delay_triggers, true) ->
      true
  ; current_predicate(preference:flag/1),
    preference:flag(delay_triggers)
  ).

prover:with_delay_triggers(Goal) :-
  ( nb_current(prover_delay_triggers, Old) -> true ; Old = unset ),
  nb_setval(prover_delay_triggers, true),
  setup_call_cleanup(true,
                     Goal,
                     ( Old == unset -> nb_delete(prover_delay_triggers)
                     ; nb_setval(prover_delay_triggers, Old)
                     )).

% -----------------------------------------------------------------------------
%  Internal: cycle stack (for printing cycle-break paths)
% -----------------------------------------------------------------------------
%
% Cycle-break detection should be based on "Lit currently on the proof stack".
% The triggers graph is sometimes insufficient to reconstruct a human-readable
% cycle quickly (especially when triggers are delayed or pruned). We therefore
% maintain a lightweight per-proof stack of literals currently being proven,
% and store a compact cycle witness in the proof under `cycle_path(Lit)`.

prover:with_cycle_stack(Goal) :-
  ( nb_current(prover_cycle_stack, Old) -> true ; Old = unset ),
  nb_setval(prover_cycle_stack, []),
  setup_call_cleanup(true,
                     Goal,
                     ( Old == unset -> nb_delete(prover_cycle_stack)
                     ; nb_setval(prover_cycle_stack, Old)
                     )).

prover:cycle_stack_push(Lit) :-
  ( nb_current(prover_cycle_stack, S0) -> true ; S0 = [] ),
  nb_setval(prover_cycle_stack, [Lit|S0]).

prover:cycle_stack_pop(Lit) :-
  ( nb_current(prover_cycle_stack, [Lit|Rest]) ->
      nb_setval(prover_cycle_stack, Rest)
  ; true
  ).

prover:take_until([Stop|_], Stop, [Stop]) :- !.
prover:take_until([X|Xs], Stop, [X|Out]) :-
  prover:take_until(Xs, Stop, Out).

prover:cycle_path_for(Lit, CyclePath) :-
  ( nb_current(prover_cycle_stack, Stack),
    prover:take_until(Stack, Lit, PrefixRev) ->
      reverse(PrefixRev, Prefix),
      append(Prefix, [Lit], CyclePath)
  ; CyclePath = [Lit, Lit]
  ).

prover:currently_proving(Lit) :-
  nb_current(prover_cycle_stack, Stack),
  memberchk(Lit, Stack),
  !.

% -----------------------------------------------------------------------------
%  Lightweight model construction (skip Proof + Triggers bookkeeping)
% -----------------------------------------------------------------------------
%
% For some internal computations (notably query-side model construction), we only
% need the resulting Model/Constraints, not the Proof tree nor Triggers. Using the
% full prover in those cases creates substantial overhead (assoc updates for Proof,
% trigger maintenance, cycle bookkeeping keyed by Proof, ...).
%
% `prove_model/*` keeps the same semantics for constraints and for "already proven"
% context refinement, but uses a dedicated in-progress set for cycle detection.

prover:prove_model(Target, InModel, OutModel, InCons, OutCons) :-
  prover:prove_model(Target, InModel, OutModel, InCons, OutCons, t).

prover:prove_model([], Model, Model, Cons, Cons, _InProg) :-
  !.
prover:prove_model([Literal|Rest], Model0, Model, Cons0, Cons, InProg0) :-
  !,
  prover:prove_model(Literal, Model0, Model1, Cons0, Cons1, InProg0),
  prover:prove_model(Rest,    Model1, Model,  Cons1, Cons,  InProg0).

prover:prove_model(Full, Model0, Model, Constraints0, Constraints, InProg0) :-
  canon_literal(Full, Lit, Ctx),

  (   % Case: a constraint
      prover:is_constraint(Lit) ->
      !,
      Model = Model0,
      prover:unify_constraints(Lit, Constraints0, Constraints)

  ;   % Case: Lit already proven with given context
      prover:proven(Lit, Model0, Ctx) ->
      !,
      Model = Model0,
      Constraints = Constraints0

  ;   % Case: Lit already proven, but context has changed
      prover:proven(Lit, Model0, OldCtx) ->
      !,
      prover:ctx_union(OldCtx, Ctx, NewCtx),
      ( NewCtx == OldCtx ->
          Model = Model0,
          Constraints = Constraints0
      ; canon_literal(NewFull, Lit, NewCtx),
        prover:test_stats_rule_call,
        rule(NewFull, NewBody),
        prover:prove_model(NewBody, Model0, BodyModel, Constraints0, BodyConstraints, InProg0),
        put_assoc(Lit, BodyModel, NewCtx, Model),
        Constraints = BodyConstraints
      )

  ;   % Case: circular model proof (cycle-break)
      get_assoc(Lit, InProg0, true) ->
      !,
      % Keep the same taxonomy as the full prover's cycle-breaks: store assumed(Lit)
      % in the model (note: dependency-model extraction ignores assumed/1 keys).
      put_assoc(assumed(Lit), Model0, Ctx, Model),
      Constraints = Constraints0

  ;   % Case: regular proof (model-only)
      put_assoc(Lit, InProg0, true, InProg1),
      prover:test_stats_rule_call,
      rule(Full, Body),
      prover:prove_model(Body, Model0, BodyModel, Constraints0, BodyConstraints, InProg1),
      del_assoc(Lit, InProg1, _Old, InProg2),
      ( InProg2 = _ -> true ), % keep var used (avoid singleton warnings)
      put_assoc(Lit, BodyModel, Ctx, Model),
      Constraints = BodyConstraints
  ).

% -----------------------------------------------------------------------------
%  Optional per-proof counters (used by prover:test_stats/*)
% -----------------------------------------------------------------------------

prover:test_stats_reset_counters :-
  nb_setval(prover_test_stats_rule_calls, 0),
  nb_setval(prover_test_stats_ctx_union_calls, 0),
  nb_setval(prover_test_stats_ctx_union_cost, 0),
  nb_setval(prover_test_stats_ctx_max_len, 0),
  % Sampled context length distribution + cost model inputs:
  % - ctx_len_hist: histogram of output context lengths (NewCtx) for sampled unions
  % - ctx_cost_mul: sum(L0*L1) across sampled unions (rough proxy for list union work)
  % - ctx_cost_add: sum(L0+L1) across sampled unions (rough proxy for ord_union work)
  empty_assoc(EmptyHist),
  nb_setval(prover_test_stats_ctx_len_hist, EmptyHist),
  nb_setval(prover_test_stats_ctx_cost_mul, 0),
  nb_setval(prover_test_stats_ctx_cost_add, 0),
  % Sampling for ctx_union timing:
  % - keep overhead low
  % - but ensure we usually get at least a few samples on small runs
  nb_setval(prover_test_stats_ctx_union_time_sample_rate, 64),
  nb_setval(prover_test_stats_ctx_union_time_samples, 0),
  nb_setval(prover_test_stats_ctx_union_time_ms_sampled, 0).

prover:test_stats_rule_call :-
  ( nb_current(prover_test_stats_rule_calls, N0) -> true ; N0 = 0 ),
  N is N0 + 1,
  nb_setval(prover_test_stats_rule_calls, N).

prover:test_stats_get_counters(rule_calls(RuleCalls)) :-
  ( nb_current(prover_test_stats_rule_calls, RuleCalls) -> true ; RuleCalls = 0 ).

prover:test_stats_get_ctx_counters(ctx_union_calls(Calls),
                                  ctx_union_cost(Cost),
                                  ctx_max_len(MaxLen),
                                  ctx_union_ms_est(MsEst)) :-
  ( nb_current(prover_test_stats_ctx_union_calls, Calls) -> true ; Calls = 0 ),
  ( nb_current(prover_test_stats_ctx_union_cost, Cost) -> true ; Cost = 0 ),
  ( nb_current(prover_test_stats_ctx_max_len, MaxLen) -> true ; MaxLen = 0 ),
  ( nb_current(prover_test_stats_ctx_union_time_samples, Samples) -> true ; Samples = 0 ),
  ( nb_current(prover_test_stats_ctx_union_time_ms_sampled, MsSampled) -> true ; MsSampled = 0 ),
  ( Samples =:= 0 ->
      MsEst = 0
  ; MsEst0 is MsSampled * Calls / Samples,
    % Round to integer milliseconds for reporting consistency.
    MsEst is round(MsEst0)
  ).

prover:test_stats_get_ctx_distribution(ctx_len_hist(HistPairs),
                                      ctx_cost_mul(SumMul),
                                      ctx_cost_add(SumAdd),
                                      ctx_len_samples(Samples)) :-
  ( nb_current(prover_test_stats_ctx_len_hist, HistAssoc) -> true ; empty_assoc(HistAssoc) ),
  assoc_to_list(HistAssoc, HistPairs),
  ( nb_current(prover_test_stats_ctx_cost_mul, SumMul) -> true ; SumMul = 0 ),
  ( nb_current(prover_test_stats_ctx_cost_add, SumAdd) -> true ; SumAdd = 0 ),
  ( nb_current(prover_test_stats_ctx_union_time_samples, Samples) -> true ; Samples = 0 ).

% -----------------------------------------------------------------------------
%  Context list instrumentation
% -----------------------------------------------------------------------------
%
% Contexts are currently represented as lists. To test whether context list
% processing is a performance bottleneck, we record:
% - how often we union contexts
% - an approximate "union cost" (sum of input lengths)
% - the max context length observed
%
% NOTE: This is intentionally cheap; it is used only in test_stats runs.

prover:ctx_union(OldCtx, Ctx, NewCtx) :-
  % Fast path: if test_stats is not active, do a plain union with no overhead.
  ( nb_current(prover_test_stats_ctx_union_calls, _) ->
      ( is_list(OldCtx) -> length(OldCtx, L0) ; L0 = 0 ),
      ( is_list(Ctx)    -> length(Ctx, L1)    ; L1 = 0 ),
      ( nb_current(prover_test_stats_ctx_union_calls, C0pre) -> true ; C0pre = 0 ),
      CallIndex is C0pre + 1,
      ( nb_current(prover_test_stats_ctx_union_time_sample_rate, Rate) -> true ; Rate = 1024 ),
      % Always sample the first few unions to avoid "0 samples => 0 ms" on small runs.
      ( ( CallIndex =< 16
        ; 0 is CallIndex mod Rate
        ) ->
          Sampled = true
        ; Sampled = false
      ),
      ( Sampled == true ->
          statistics(walltime, [T0,_]),
          prover:ctx_union_raw(OldCtx, Ctx, NewCtx),
          statistics(walltime, [T1,_]),
          Dt is T1 - T0,
          ( nb_current(prover_test_stats_ctx_union_time_samples, S0) -> true ; S0 = 0 ),
          ( nb_current(prover_test_stats_ctx_union_time_ms_sampled, M0s) -> true ; M0s = 0 ),
          S1 is S0 + 1,
          M1s is M0s + Dt,
          nb_setval(prover_test_stats_ctx_union_time_samples, S1),
          nb_setval(prover_test_stats_ctx_union_time_ms_sampled, M1s)
      ; prover:ctx_union_raw(OldCtx, Ctx, NewCtx)
      ),
      ( is_list(NewCtx) -> length(NewCtx, L2) ; L2 = 0 ),
      ( Sampled == true ->
          prover:test_stats_ctx_union_sampled(L0, L1, L2)
      ; true
      ),
      ( nb_current(prover_test_stats_ctx_union_calls, C0) -> true ; C0 = 0 ),
      ( nb_current(prover_test_stats_ctx_union_cost,  K0) -> true ; K0 = 0 ),
      ( nb_current(prover_test_stats_ctx_max_len,     M0) -> true ; M0 = 0 ),
      C is C0 + 1,
      K is K0 + L0 + L1,
      M is max(M0, max(L0, max(L1, L2))),
      nb_setval(prover_test_stats_ctx_union_calls, C),
      nb_setval(prover_test_stats_ctx_union_cost,  K),
      nb_setval(prover_test_stats_ctx_max_len,     M)
  ; prover:ctx_union_raw(OldCtx, Ctx, NewCtx)
  ).

% Keep context unions stable by preventing `self/1` provenance from accumulating.
% `self/1` is used for local dependency-resolution guards and printing, but it
% should not grow unboundedly through repeated ctx unions.
prover:ctx_union_raw(OldCtx, Ctx, NewCtx) :-
  prover:ctx_strip_self(OldCtx, OldNoSelf),
  prover:ctx_strip_self_keep_one(Ctx, SelfTerm, CtxNoSelf),
  feature_unification:unify(OldNoSelf, CtxNoSelf, Merged),
  prover:ctx_prepend_self(SelfTerm, Merged, NewCtx),
  !.

prover:ctx_strip_self(Ctx0, Ctx) :-
  ( is_list(Ctx0) ->
      findall(X, (member(X, Ctx0), \+ X = self(_)), Ctx)
  ; Ctx = Ctx0
  ),
  !.

prover:ctx_strip_self_keep_one(Ctx0, SelfTerm, Ctx) :-
  ( is_list(Ctx0) ->
      ( memberchk(self(S), Ctx0) -> SelfTerm = self(S) ; SelfTerm = none ),
      findall(X, (member(X, Ctx0), \+ X = self(_)), Ctx)
  ; SelfTerm = none,
    Ctx = Ctx0
  ),
  !.

prover:ctx_prepend_self(none, Ctx, Ctx) :- !.
prover:ctx_prepend_self(self(S), Ctx0, Ctx) :-
  ( is_list(Ctx0) ->
      Ctx = [self(S)|Ctx0]
  ; Ctx = Ctx0
  ),
  !.

prover:test_stats_ctx_union_sampled(L0, L1, L2) :-
  % Histogram of resulting context lengths.
  ( nb_current(prover_test_stats_ctx_len_hist, Hist0) -> true ; empty_assoc(Hist0) ),
  ( get_assoc(L2, Hist0, C0) -> true ; C0 = 0 ),
  C1 is C0 + 1,
  put_assoc(L2, Hist0, C1, Hist1),
  nb_setval(prover_test_stats_ctx_len_hist, Hist1),
  % Cost-model inputs.
  ( nb_current(prover_test_stats_ctx_cost_mul, Mul0) -> true ; Mul0 = 0 ),
  ( nb_current(prover_test_stats_ctx_cost_add, Add0) -> true ; Add0 = 0 ),
  Mul1 is Mul0 + L0 * L1,
  Add1 is Add0 + L0 + L1,
  nb_setval(prover_test_stats_ctx_cost_mul, Mul1),
  nb_setval(prover_test_stats_ctx_cost_add, Add1).


% =============================================================================
% Top-Level Entry Point
% =============================================================================

%! prover:prove(+Target, +InProof, -OutProof, +InModel, -OutModel, +InCons, -OutCons, +InTriggers, -OutTriggers)
%
% Main entry point for the prover.
% Orchestrates the proving process and the configurable trigger-building strategy.

prover:prove(Target, InProof, OutProof, InModel, OutModel, InCons, OutCons, InTriggers, OutTriggers) :-

  % Call the core recursive engine.
  prover:debug_hook(Target, InProof, InModel, InCons),
  prover:with_cycle_stack(
    prover:prove_recursive(Target, InProof, OutProof, InModel, OutModel, InCons, OutCons, InTriggers, MidTriggers)
  ),

  % Check the flag to determine the final trigger-building action.
  (   prover:delay_triggers ->
      % From-Scratch Mode: Build the real Triggers tree from the final proof.
      build_triggers_from_proof(OutProof, OutTriggers)
  ;
      % Incremental Mode: The 'MidTriggers' tree is already complete.
      OutTriggers = MidTriggers
  ).


% =============================================================================
% Core Recursive Prover
% =============================================================================

% -----------------------------------------------------------------------------
% CASE 1: A list of literals to prove (Recursive Step)
% -----------------------------------------------------------------------------

prover:prove_recursive([],Proof,Proof,Model,Model,Constraints,Constraints,Triggers,Triggers) :-
  !.

prover:prove_recursive([Literal|Rest],Proof,NewProof,Model,NewModel,Cons,NewCons,Trig,NewTrig) :-
  !,
  prover:debug_hook([Literal|Rest], Proof, Model, Cons),
  prover:prove_recursive(Literal, Proof,MidProof,    Model,MidModel,    Cons,MidCons,    Trig,MidTrig),
  prover:prove_recursive(Rest,    MidProof,NewProof, MidModel,NewModel, MidCons,NewCons, MidTrig,NewTrig).


% -----------------------------------------------------------------------------
% CASE 2: A single literal to prove (Recursive Step)
% -----------------------------------------------------------------------------

prover:prove_recursive(Full, Proof, NewProof, Model, NewModel, Constraints, NewConstraints, Triggers, NewTriggers) :-

  % Debug hook (enabled only when a handler is installed).
  ( prover:debug_hook_handler(_)
    -> prover:debug_hook(Full, Proof, Model, Constraints)
    ;  true
  ),

  canon_literal(Full, Lit, Ctx),

  (   % Case: a constraint

      prover:is_constraint(Lit) ->
      !,
      %message:color(orange),
      %writeln('PROVER: is constraint'),
      %message:color(normal),

      Proof       = NewProof,
      Model       = NewModel,
      Triggers    = NewTriggers,
      prover:unify_constraints(Lit, Constraints, Constraints1),
      % Domain hook (keeps prover generic): if the domain provides a constraint
      % guard, it can reject inconsistent states by failing here.
      ( current_predicate(rules:constraint_guard/2) ->
          ( rules:constraint_guard(Lit, Constraints1) ->
              NewConstraints = Constraints1
          ; fail
          )
      ; NewConstraints = Constraints1
      )


  ;   % Case: Lit already proven with given context

      prover:proven(Lit, Model, Ctx) ->
      !,
      %message:color(orange),
      %writeln('PROVER: lit is proven with same Ctx'),
      %message:color(normal),

      Proof       = NewProof,
      Model       = NewModel,
      Triggers    = NewTriggers,
      Constraints = NewConstraints


  ;   % Case: Lit already proven, but context has changed

      prover:proven(Lit, Model, OldCtx) ->
      !,
      %message:color(orange),
      %writeln('PROVER: lit is proven with different Ctx'),
      %writeln('PROVER: -- Get Old body and Old Dep Count'),

      % -- Get old body and old dep count
      get_assoc(rule(Lit),Proof,dep(_OldCount,OldBody)?OldCtx),
      %write('  - Lit      : '),writeln(Lit),
      %write('  - Ctx      : '),writeln(Ctx),
      %write('  - OldCtx   : '),writeln(OldCtx),
      %write('  - OldCount : '),writeln(OldCount),
      %write('  - OldBody  : '),writeln(OldBody),

      %writeln('PROVER: -- Union'),

      % -- Merge old & new context
      prover:ctx_union(OldCtx, Ctx, NewCtx),
      %write('  - NewCtx   : '),writeln(NewCtx),

      %writeln('PROVER: -- Create updated full literal'),
      % -- Put together updated full literal
      canon_literal(NewFull,Lit,NewCtx),
      %write('  - NewFull  : '),writeln(NewFull),

      %writeln('PROVER: -- Ready to apply rule for full literal'),
      % -- Apply rule
      prover:test_stats_rule_call,
      ( nb_current(prover_timeout_trace, _) ->
          prover:trace_simplify(Lit, SimpleRuleLit),
          prover:timeout_trace_push(rule_call(SimpleRuleLit))
      ; true
      ),
      rule(NewFull,NewBody),

      %message:hl('PROVER - returning from subcall'),
      %message:color(orange),


      % -- Only body difference should be proved further
      subtract(NewBody,OldBody,DiffBody),

      %write('PROVER: -- NewBody: '),writeln(NewBody),
      %write('PROVER: -- OldBody: '),writeln(OldBody),
      %write('PROVER: -- DifBody: '),writeln(DiffBody),
      %message:color(normal),

      % -- Prepare to refine proof
      length(NewBody,NewCount),

      % -- Amend existing proof, make it seem we are prescient
      put_assoc(rule(Lit), Proof, dep(NewCount, NewBody)?NewCtx,Proof1),

      %writeln('PROVER: -- Ammended rule in proof '),

      (   prover:delay_triggers ->
          Triggers1 = Triggers
      ;
          prover:add_triggers(NewFull, NewBody, Triggers, Triggers1)
      ),

      % -- Prove body difference
      % When we refine a rule due to context changes, we are effectively re-entering
      % the proof of Lit. Record Lit on the cycle stack as well, so if a cycle-break
      % happens during this refinement we can still extract a meaningful cycle path.
      setup_call_cleanup(prover:cycle_stack_push(Lit),
                         prover:prove_recursive(DiffBody, Proof1, NewProof, Model, BodyModel, Constraints, BodyConstraints, Triggers1, NewTriggers),
                         prover:cycle_stack_pop(Lit)),

      % -- Update model & Constraints
      put_assoc(Lit, BodyModel, NewCtx, NewModel),
      NewConstraints = BodyConstraints


  ;   % Case: Lit is assumed proven

      prover:assumed_proven(Lit, Model) ->

      %message:color(orange),
      %writeln('PROVER: lit is assumed proven'),
      %message:color(normal),

      Proof       = NewProof,
      Model       = NewModel,
      Triggers    = NewTriggers,
      Constraints = NewConstraints


      % Case: Conflicts:

  ;   prover:conflicts(Lit, Model) ->

      %message:color(orange),
      %writeln('PROVER: lit is conflicting with Model'),
      %message:color(normal),

      fail

  ;   prover:conflictrule(rule(Lit,[]), Proof) ->

      %message:color(orange),
      %writeln('PROVER: lit rule is conflicting with Proof'),
      %message:color(normal),

      fail

  ;   % Case: circular proof

      (   prover:currently_proving(Lit),
          \+ prover:assumed_proving(Lit, Proof) ->

	        %message:color(orange),
          %writeln('PROVER: circular proof, taking assumption'),
          %message:color(normal),

          % Cycle-break mechanism:
          % - In the Proof: record a special key `assumed(rule(Lit))`
          % - In the Model: record `assumed(Lit)`
          %
          % This is distinct from domain-level assumptions introduced by rules
          % via the literal `assumed(X)` (which are proven by `rule(assumed(_), [])`
          % and stored under `rule(assumed(X))` in the proof).
          % Store the *current* body of the in-progress rule so downstream
          % planning/SCC logic can still see the cycle edges. Mark the depcount
          % as -1 to indicate "deferred / cyclic".
          ( get_assoc(rule(Lit), Proof, dep(_OldCount, OldBody)?_OldCtx)
            -> BodyForPlanning = OldBody
            ;  BodyForPlanning = []
          ),
          put_assoc(assumed(rule(Lit)), Proof, dep(-1, BodyForPlanning)?Ctx, Proof1),
          ( prover:cycle_path_for(Lit, CyclePath) ->
              put_assoc(cycle_path(Lit), Proof1, CyclePath, NewProof)
          ; NewProof = Proof1
          ),
          put_assoc(assumed(Lit), Model, Ctx, NewModel),
          NewConstraints = Constraints,
          NewTriggers = Triggers
      ;

      % Case: regular proof

          %message:color(orange),
          %writeln('PROVER: regular proof'),
          %message:color(normal),

          prover:test_stats_rule_call,
          ( nb_current(prover_timeout_trace, _) ->
              prover:trace_simplify(Lit, SimpleRuleLit),
              prover:timeout_trace_push(rule_call(SimpleRuleLit))
          ; true
          ),
          rule(Full, Body),

          length(Body, DepCount),
          put_assoc(rule(Lit), Proof, dep(DepCount, Body)?Ctx, Proof1),
          (   prover:delay_triggers ->
              Triggers1 = Triggers
          ;
              prover:add_triggers(Full, Body, Triggers, Triggers1)
          ),
          setup_call_cleanup(prover:cycle_stack_push(Lit),
                             prover:prove_recursive(Body, Proof1, NewProof, Model, BodyModel, Constraints, BodyConstraints, Triggers1, NewTriggers),
                             prover:cycle_stack_pop(Lit)),
          put_assoc(Lit, BodyModel, Ctx, NewModel),
          NewConstraints = BodyConstraints
      )
  ).


% =============================================================================
% Debug Hook
% =============================================================================

%! prover:debug_hook(+Target, +Proof, +Model, +Constraints)
%
% This predicate is expanded by user:goal_expansion

:- thread_local prover:debug_hook_handler/1.

%! prover:with_debug_hook(+Handler, :Goal)
%
% Install a per-thread debug hook handler during Goal. Handler must be a
% callable closure that can be called as call(Handler, Target, Proof, Model, Constraints).
% Example: prover:with_debug_hook(printer:display_state, prover:prove(...)).
prover:with_debug_hook(Handler, Goal) :-
  setup_call_cleanup(
    asserta(prover:debug_hook_handler(Handler)),
    Goal,
    retractall(prover:debug_hook_handler(Handler))
  ).

% -----------------------------------------------------------------------------
%  Timeout diagnostics (best-effort)
% -----------------------------------------------------------------------------
%
% Used by tester on timeouts to capture a short "where were we" trace without
% enabling full tracing (which is too expensive at scale).

prover:trace_simplify(Item, Simple) :-
  % Keep timeout traces small + comparable (helps spot loops).
  ( var(Item) ->
      Simple = var
  ; Item = required(U) ->
      Simple = required(U)
  ; Item = assumed(U) ->
      Simple = assumed(U)
  ; Item = naf(G) ->
      ( G = required(U) -> Simple = naf_required(U)
      ; G = blocking(U) -> Simple = naf_blocking(U)
      ; Simple = naf
      )
  ; Item = conflict(A, _B) ->
      % Keep just the conflicting head; the second argument is usually derived.
      Simple = conflict(A)
  ; Item = Inner:Action,
    atom(Action) ->
      % Many of our literals are action-tagged, e.g.
      %   grouped_package_dependency(...):run
      %   use_conditional_group(...):install
      % If we don't handle this, the trace becomes `functor((:)/2)` noise.
      prover:trace_simplify(Inner, InnerS),
      Simple = act(Action, InnerS)
  ; Item = constraint(Key:{_}) ->
      Simple = constraint(Key)
  ; Item = use_conditional_group(Sign, Use, Repo://Entry, Deps) ->
      ( is_list(Deps) -> length(Deps, N) ; N = '?' ),
      Simple = use_cond(Sign, Use, Repo://Entry, N)
  ; Item = any_of_group(Deps) ->
      ( is_list(Deps) -> length(Deps, N) ; N = '?' ),
      Simple = any_of_group(N)
  ; Item = exactly_one_of_group(Deps) ->
      ( is_list(Deps) -> length(Deps, N) ; N = '?' ),
      Simple = exactly_one_of_group(N)
  ; Item = at_most_one_of_group(Deps) ->
      ( is_list(Deps) -> length(Deps, N) ; N = '?' ),
      Simple = at_most_one_of_group(N)
  ; Item = grouped_package_dependency(Strength, C, N, PackageDeps) ->
      ( PackageDeps = [package_dependency(Phase, _, _, _, _, _, SlotReq, _)|_] ->
          Simple = gpd(Strength, Phase, C, N, SlotReq)
      ; Simple = gpd(Strength, C, N)
      )
  ; Item = package_dependency(Phase, Strength, C, N, O, V, S, U) ->
      ( is_list(U) -> length(U, UL) ; UL = '?' ),
      Simple = pkgdep(Phase, Strength, C, N, O, V, S, usedeps(UL))
  ; Item = Repo://Entry:Action ->
      Simple = entry(Repo://Entry, Action)
  ; Item = Repo://Entry ->
      Simple = entry(Repo://Entry)
  ; is_list(Item) ->
      length(Item, N),
      Simple = list(N)
  ; compound(Item) ->
      functor(Item, F, A),
      Simple = functor(F/A)
  ; Simple = Item
  ).

prover:timeout_trace_reset :-
  nb_setval(prover_timeout_trace, []).

prover:timeout_trace_push(Item0) :-
  % Also update frequency counters (when enabled) so we can identify which
  % obligations dominate during long/looping runs.
  ( nb_current(prover_timeout_count_assoc, A0) ->
      ( get_assoc(Item0, A0, N0) -> true ; N0 = 0 ),
      N is N0 + 1,
      put_assoc(Item0, A0, N, A1),
      nb_setval(prover_timeout_count_assoc, A1)
  ; true
  ),
  ( nb_current(prover_timeout_trace, L0) -> true ; L0 = [] ),
  L1 = [Item0|L0],
  % Keep only the last N items (diagnostics; not performance-critical).
  ( nb_current(prover_timeout_trace_maxlen, MaxLen) -> true ; MaxLen = 200 ),
  length(L1, Len),
  ( Len =< MaxLen ->
      nb_setval(prover_timeout_trace, L1)
  ; length(Keep, MaxLen),
    append(Keep, _Drop, L1),
    nb_setval(prover_timeout_trace, Keep)
  ).

prover:timeout_trace_hook(Target, _Proof, _Model, _Constraints) :-
  % Prefer the canonical literal head, not the full annotated target.
  ( catch(canon_literal(Target, Lit0, _Ctx), _, fail) ->
      Lit = Lit0
  ; Lit = Target
  ),
  prover:trace_simplify(Lit, Simple),
  % Optional: count which literals dominate during a diagnosis run.
  ( nb_current(prover_timeout_count_assoc, A0) ->
      ( get_assoc(Simple, A0, N0) -> true ; N0 = 0 ),
      N is N0 + 1,
      put_assoc(Simple, A0, N, A1),
      nb_setval(prover_timeout_count_assoc, A1)
  ; true
  ),
  prover:timeout_trace_push(Simple).

% Run a short best-effort diagnosis for a target. Always succeeds.
prover:diagnose_timeout(Target, LimitSec, diagnosis(DeltaInferences, RuleCalls, Trace)) :-
  prover:timeout_trace_reset,
  prover:test_stats_reset_counters,
  statistics(inferences, I0),
  ( catch(
      prover:with_debug_hook(prover:timeout_trace_hook,
        call_with_time_limit(LimitSec,
          prover:prove(Target, t, _Proof, t, _Model, t, _Cons, t, _Triggers)
        )
      ),
      time_limit_exceeded,
      true
    )
  -> true
  ;  true
  ),
  statistics(inferences, I1),
  DeltaInferences is I1 - I0,
  prover:test_stats_get_counters(rule_calls(RuleCalls)),
  ( nb_current(prover_timeout_trace, TraceRev) -> reverse(TraceRev, Trace) ; Trace = [] ).

% Like diagnose_timeout/3, but also returns a TopCounts list of the most frequent
% simplified literals seen during the run.
prover:diagnose_timeout_counts(Target, LimitSec, Diagnosis, TopCounts) :-
  empty_assoc(A0),
  nb_setval(prover_timeout_count_assoc, A0),
  prover:diagnose_timeout(Target, LimitSec, Diagnosis),
  ( nb_current(prover_timeout_count_assoc, A1) -> true ; A1 = A0 ),
  nb_delete(prover_timeout_count_assoc),
  % Post-processing can dominate on huge runs; keep it bounded and best-effort.
  ( catch(
      call_with_time_limit(1.0,
        ( findall(N-S,
                  gen_assoc(S, A1, N),
                  Pairs0),
          keysort(Pairs0, PairsAsc),
          reverse(PairsAsc, Pairs),
          length(Pairs, Len),
          ( Len > 20 ->
              length(TopCounts, 20),
              append(TopCounts, _Rest, Pairs)
          ; TopCounts = Pairs
          )
        )),
      time_limit_exceeded,
      TopCounts = []
    )
  -> true
  ; TopCounts = []
  ).

prover:debug_hook(Target, Proof, Model, Constraints) :-
  ( prover:debug_hook_handler(Handler) ->
      % Best-effort: debugging must not crash the prover.
      catch(call(Handler, Target, Proof, Model, Constraints),
            E,
            print_message(error, E))
  ; true
  ),
  !.

%prover:debug_hook(Target, Proof, Model, Constraints) :-
%  printer:display_state(Target, Proof, Model, Constraints).



%! prover:debug
%
% Debug all predicates in the prover module.

prover:debug :-
  forall(current_predicate(prover:X),trace(prover:X)).


% =============================================================================
% Triggers Helpers
% =============================================================================

%! build_triggers_from_proof(+ProofAVL, -TriggersAVL)
%
% Build the Triggers tree from the Proof AVL tree.

prover:build_triggers_from_proof(ProofAVL, TriggersAVL) :-
    empty_assoc(EmptyTriggers),
    assoc_to_list(ProofAVL, RulesAsList),
    foldl(prover:add_rule_triggers, RulesAsList, EmptyTriggers, TriggersAVL).


%! prover:add_rule_triggers(+HeadKey-Value, +InTriggers, -OutTriggers)
%
% Add the triggers for a rule to the Triggers tree.

prover:add_rule_triggers(HeadKey-Value, InTriggers, OutTriggers) :-
    ( prover:canon_rule(rule(Head, Body), HeadKey, Value) ; prover:canon_rule(assumed(rule(Head, Body)), HeadKey, Value) ),
    !,
    ( Value = dep(_, _)?Ctx ->
        % `canon_rule/3` may already return a context-annotated Head (Head?{Ctx}).
        % Avoid wrapping a second time, which creates nested context terms like:
        %   portage://(dev-ml/foo-1.0:run?{Ctx})?{Ctx}
        ( Head = _?{_} -> FullHead = Head
        ; prover:canon_literal(FullHead, Head, Ctx)
        )
    ; FullHead = Head
    ),
    prover:add_triggers(FullHead, Body, InTriggers, OutTriggers).

prover:add_rule_triggers(_, InTriggers, InTriggers).


%! prover:add_triggers(+Head, +Body, +InTriggers, -OutTriggers)
%
% Add the triggers for a rule to the Triggers tree.

prover:add_triggers(_, [], Triggers, Triggers) :- !.

prover:add_triggers(Head, Body, InTriggers, OutTriggers) :-
    foldl(prover:add_trigger(Head), Body, InTriggers, OutTriggers).

prover:add_trigger(Head, Dep, InTriggers, OutTriggers) :-
    (   prover:is_constraint(Dep)
    ->  OutTriggers = InTriggers
    ;
        prover:canon_literal(Dep, DepLit, _),
        (get_assoc(DepLit, InTriggers, Dependents) -> true ; Dependents = []),
        (memberchk(Head, Dependents) -> NewDependents = Dependents ; NewDependents = [Head | Dependents]),
        put_assoc(DepLit, InTriggers, NewDependents, OutTriggers)
    ).


% =============================================================================
% Proof helper predicates & Canonicalisation
% =============================================================================

prover:proving(rule(Lit, Body), Proof) :- get_assoc(rule(Lit),Proof,dep(_, Body)?_).
% "Assumed proving" is our prover-level cycle-break marker. Historically this
% used dep(0,[]); we now use dep(-1,Body) but keep the predicate robust.
prover:assumed_proving(Lit, Proof) :- get_assoc(assumed(rule(Lit)),Proof,dep(_Count, _Body)?_).
% Consider a literal "proven" if we've proven it under an equivalent *semantic*
% context. This prevents needless re-proving when only provenance (e.g. self/1)
% differs across callers.
prover:proven(Lit, Model, Ctx) :-
  get_assoc(Lit, Model, StoredCtx),
  ( StoredCtx == Ctx
  ; prover:ctx_sem_key(StoredCtx, K1),
    prover:ctx_sem_key(Ctx,       K2),
    K1 == K2
  ).
prover:assumed_proven(Lit, Model) :- get_assoc(assumed(Lit), Model, _).

prover:ctx_sem_key({}, key([], none)) :- !.
prover:ctx_sem_key(Ctx, key(RU, BWU)) :-
  is_list(Ctx),
  !,
  ( memberchk(required_use:RU0, Ctx) -> RU = RU0 ; RU = [] ),
  ( memberchk(build_with_use:BWU0, Ctx) -> BWU = BWU0 ; BWU = none ).
prover:ctx_sem_key(_Other, key([], none)) :-
  !.

prover:conflicts(Lit, Model) :-
  ( Lit = naf(Inner) -> (prover:proven(Inner, Model, _) ; prover:assumed_proven(Inner, Model))
  ; prover:proven(naf(Lit), Model, _)
  ), !.

prover:conflictrule(rule(Lit,_), Proof) :-
  ( Lit = naf(Inner) -> (prover:proving(rule(Inner,_), Proof) ; prover:assumed_proving(Inner, Proof))
  ; prover:proving(rule(naf(Lit),_), Proof)
  ), !.


% =============================================================================
% CONSTRAINT
% =============================================================================

%! prover:is_constraint(+Literal)
%
% Check if a literal is a constraint.

prover:is_constraint(constraint(_)).



%! prover:unify_constraints(+Constraint, +Constraints, -NewConstraints)
%
% Unify a constraint with the current constraints.

prover:unify_constraints(constraint(Key:{Value}),Constraints,NewConstraints) :-
  % Generic fast path for set-like constraint values.
  % Domain code can wrap list values in ordset/1 to get cheap merges.
  Value = ordset(List),
  is_list(List),
  !,
  sort(List, NewSet),
  ( get_assoc(Key, Constraints, ordset(CurSet0), Constraints1, ordset(CurSet0)) ->
      ord_union(CurSet0, NewSet, CurSet),
      put_assoc(Key, Constraints1, ordset(CurSet), NewConstraints)
  ; put_assoc(Key, Constraints, ordset(NewSet), NewConstraints)
  ).

prover:unify_constraints(constraint(Key:{Value}),Constraints,NewConstraints) :-
  get_assoc(Key,Constraints,CurrentValue,NewConstraints,NewValue),!,
  prover:unify_constraint(Value,CurrentValue,NewValue).

prover:unify_constraints(constraint(Key:{Value}),Constraints,NewConstraints) :-
  prover:unify_constraint(Value,{},NewValue),
  put_assoc(Key,Constraints,NewValue,NewConstraints).

prover:unify_constraint([],{},Assoc) :-
  empty_assoc(Assoc),!.

prover:unify_constraint(Atom,{},Atom) :-
  is_of_type(atom,Atom),!.

prover:unify_constraint(List,{},Assoc) :-
  is_list(List),!, prover:list_to_assoc(List,Assoc).

prover:unify_constraint([],Assoc,Assoc) :-
  is_assoc(Assoc),!.

prover:unify_constraint(Atom,Atom,Atom) :-
  is_of_type(atom,Atom),!.

prover:unify_constraint(List,E,Assoc) :-
  is_list(List), empty_assoc(E),!,
  prover:list_to_assoc(List,Assoc).

prover:unify_constraint(List,M,Assoc) :-
  is_of_type(list,List), is_assoc(M),!,
  prover:prove_recursive(List,t,_,M,Assoc,t,_,t,_).


% =============================================================================
% Helper: canonicalise literals and rules
% =============================================================================


%! prover:canon_literal(?Full, ?Core, ?Ctx)
%
%   Full  – full format
%   Core  – part *before* the context annotation.
%   Ctx   – the context ({} for the “no‑context” case).
%
% Convert between full format and key-value pair used
% for the AVL model tree

% Robustness: occasionally a literal can be accidentally wrapped as
%   Repo://(Entry:Action?{Ctx})?{Ctx2}
% (repo applied to a whole action+context term). Canonicalize those to the
% intended shape Repo://Entry:Action?{MergedCtx}.

prover:canon_literal(R://(L:A),               R://L:A, {})  :- !.
prover:canon_literal(R://(L:A?{Ctx1}),        R://L:A, Ctx1) :- !.
prover:canon_literal(R://(L:A)?{Ctx2},        R://L:A, Ctx2) :- !.
prover:canon_literal(R://(L:A?{Ctx1})?{Ctx2}, R://L:A, Ctx) :-
  !,
  prover:ctx_union(Ctx1, Ctx2, Ctx).

prover:canon_literal(R://(L),                 R://L,   {})  :- !.
prover:canon_literal(R://(L?{Ctx1}),          R://L,   Ctx1) :- !.
prover:canon_literal(R://(L)?{Ctx2},          R://L,   Ctx2) :- !.
prover:canon_literal(R://(L?{Ctx1})?{Ctx2},   R://L,   Ctx) :-
  !,
  prover:ctx_union(Ctx1, Ctx2, Ctx).

prover:canon_literal(R://L:A,       R://L:A,  {})  :- !.
prover:canon_literal(R://L:A?{Ctx}, R://L:A,  Ctx) :- !.
prover:canon_literal(R://L,         R://L,    {})  :- !.
prover:canon_literal(R://L?{Ctx},   R://L,    Ctx) :- !.
prover:canon_literal(L:A,           L:A,      {})  :- !.
prover:canon_literal(L:A?{Ctx},     L:A,      Ctx) :- !.
prover:canon_literal(L,             L,        {})  :- !.
prover:canon_literal(L?{Ctx},       L,        Ctx) :- !.


%! prover:canon_rule(?Full, ?Key, ?Value)
%
% Convert between full format and key-value pair used
% for the AVL proof tree

prover:canon_rule(assumed(rule(R://L,B)),       assumed(rule(R://L)), dep(_,B)?{})   :- !.
prover:canon_rule(assumed(rule(R://L?{Ctx},B)), assumed(rule(R://L)), dep(_,B)?Ctx)  :- !.
prover:canon_rule(rule(R://L,B),                rule(R://L),          dep(_,B)?{})   :- !.
prover:canon_rule(rule(R://L?{Ctx},B),          rule(R://L),          dep(_,B)?Ctx)  :- !.
prover:canon_rule(assumed(rule(L,B)),           assumed(rule(L)),     dep(_,B)?{})   :- !.
prover:canon_rule(assumed(rule(L?{Ctx},B)),     assumed(rule(L)),     dep(_,B)?Ctx)  :- !.
prover:canon_rule(rule(L,B),                    rule(L),              dep(_,B)?{})   :- !.
prover:canon_rule(rule(L?{Ctx},B),              rule(L),              dep(_,B)?Ctx)  :- !.


% =============================================================================
%  Helper: AVL assoc convertors
% =============================================================================

%! prover:proof_to_list(+Assoc, -List)
%
% Convert an AVL proof tree to a list.

prover:proof_to_list(Assoc, List) :-
  findall(Full,
          (gen_assoc(Key,Assoc,Value),
           prover:canon_rule(Full,Key,Value)),
          List).


%! prover:model_to_list(+Assoc, -List)
%
% Convert an AVL model tree to a list.

prover:model_to_list(Assoc, List) :-
  findall(Full,
          (gen_assoc(Key,Assoc,Value),
           prover:canon_literal(Full,Key,Value)),
          List).


%! prover:constraints_to_list(+Assoc, -List)
%
% Convert an AVL constraints tree to a list.

prover:constraints_to_list(Assoc, List) :-
  findall(Full,
          (gen_assoc(Key,Assoc,Value),
           canon_literal(Full,Key,Value)),
          List).


%! prover:list_to_proof(+List, -Assoc)
%
% Convert a list to an AVL proof tree.

prover:list_to_proof(List, Assoc) :-
  empty_assoc(Empty),
  foldl(prover:add_to_proof, List, Empty, Assoc).

prover:add_to_proof(Full, InAssoc, OutAssoc) :-
  prover:canon_rule(Full, Key, Value),
  put_assoc(Key, InAssoc, Value, OutAssoc).


%! prover:list_to_model(+List, -Assoc)
%
% Convert a list to an AVL model tree.

prover:list_to_model(List, Assoc) :-
  empty_assoc(Empty),
  foldl(prover:add_to_model, List, Empty, Assoc).

prover:add_to_model(Full, InAssoc, OutAssoc) :-
  prover:canon_literal(Full, Key, Value),
  put_assoc(Key, InAssoc, Value, OutAssoc).


%! prover:list_to_constraints(+List, -Assoc)
%
% Convert a list to an AVL constraints tree.

prover:list_to_constraints(List, Assoc) :-
  empty_assoc(Empty),
  foldl(prover:add_to_constraints, List, Empty, Assoc).

prover:add_to_constraints(Full, InAssoc, OutAssoc) :-
  prover:canon_literal(Full, Key, Value),
  put_assoc(Key, InAssoc, Value, OutAssoc).


%! prover:list_to_assoc(+List, -Assoc)
%
% Convert a list to an AVL tree.

prover:list_to_assoc(List, Assoc) :-
  empty_assoc(Empty),
  foldl(prover:add_to_assoc, List, Empty, Assoc).

prover:add_to_assoc(Key,InAssoc,OutAssoc) :-
  put_assoc(Key,InAssoc,{},OutAssoc).


% =============================================================================
%  Automated testing helpers
% =============================================================================

% -----------------------------------------------------------------------------
%  Test action mapping
% -----------------------------------------------------------------------------
%
% In CLI mode we now treat "merge" as the Portage-like root action:
%   :merge = :run + :pdepend
%
% For automated tests/stats we therefore map proving_target(run) -> merge so
% PDEPEND is exercised as part of the proof.
%
% IMPORTANT: this does NOT introduce any world registrations, because those are
% only produced by rules for the wrapper target(Q,Arg):run. Repository://Entry
% tests never use that wrapper, so no world_action/2 goals are generated.

prover:test_action(run, merge) :- !.
prover:test_action(Action, Action).

%! prover:test(+Repository)
prover:test(Repository) :-
  config:test_style(Style),
  prover:test(Repository,Style).

%! prover:test(+Repository,+Style)
prover:test(Repository,Style) :-
  config:proving_target(Action0),
  prover:test_action(Action0, Action),
  tester:test(Style,
              'Proving',
              Repository://Entry,
              Repository:entry(Entry),
              ( prover:prove(Repository://Entry:Action?{[]},t,_,t,_,t,_,t,_) )).

%! prover:test_latest(+Repository)
prover:test_latest(Repository) :-
  config:test_style(Style),
  prover:test_latest(Repository,Style).

%! prover:test_latest(+Repository,+Style)
prover:test_latest(Repository,Style) :-
  config:proving_target(Action0),
  prover:test_action(Action0, Action),
  tester:test(Style,
              'Proving',
              Repository://Entry,
              ( Repository:package(C,N),once(Repository:ebuild(Entry,C,N,_)) ),
              ( prover:prove(Repository://Entry:Action?{[]},t,_,t,_,t,_,t,_) )).

% -----------------------------------------------------------------------------
%  Testing + statistics
% -----------------------------------------------------------------------------

%! prover:test_stats(+Repository)
prover:test_stats(Repository) :-
  config:test_style(Style),
  prover:test_stats(Repository, Style).

%! prover:test_stats(+Repository,+TopN)
%
% Like prover:test_stats/1, but allows choosing the Top-N limit in the output.
prover:test_stats(Repository, TopN) :-
  integer(TopN),
  !,
  config:test_style(Style),
  prover:test_stats(Repository, Style, TopN).

%! prover:test_stats(+Repository,+Style)
prover:test_stats(Repository, Style) :-
  ( config:test_stats_top_n(TopN) -> true ; TopN = 25 ),
  prover:test_stats(Repository, Style, TopN).

%! prover:test_stats(+Repository,+Style,+TopN)
prover:test_stats(Repository, Style, TopN) :-
  config:proving_target(Action0),
  prover:test_action(Action0, Action),
  aggregate_all(count, (Repository:entry(_E)), ExpectedTotal),
  printer:test_stats_reset('Proving', ExpectedTotal),
  aggregate_all(count, (Repository:package(_C,_N)), ExpectedPkgs),
  printer:test_stats_set_expected_unique_packages(ExpectedPkgs),
  tester:test(Style,
              'Proving',
              Repository://Entry,
              Repository:entry(Entry),
              ( prover:test_stats_reset_counters,
                statistics(inferences, I0),
                statistics(walltime, [T0,_]),
                ( prover:prove(Repository://Entry:Action?{[]},t,ProofAVL,t,ModelAVL,t,_Constraint,t,Triggers) ->
                    Proved = true
                ; Proved = false
                ),
                statistics(walltime, [T1,_]),
                statistics(inferences, I1),
                TimeMs is T1 - T0,
                Inferences is I1 - I0,
                ( Proved == true ->
                    prover:test_stats_get_counters(rule_calls(RuleCalls)),
                    prover:test_stats_get_ctx_counters(ctx_union_calls(CtxUC), ctx_union_cost(CtxCost), ctx_max_len(CtxMax), ctx_union_ms_est(CtxMsEst)),
                    prover:test_stats_get_ctx_distribution(ctx_len_hist(CtxHistPairs),
                                                          ctx_cost_mul(CtxMul),
                                                          ctx_cost_add(CtxAdd),
                                                          ctx_len_samples(CtxLenSamples)),
                    printer:test_stats_record_costs(Repository://Entry, TimeMs, Inferences, RuleCalls),
                    printer:test_stats_record_context_costs(Repository://Entry, CtxUC, CtxCost, CtxMax, CtxMsEst),
                    printer:test_stats_record_ctx_len_distribution(CtxHistPairs, CtxMul, CtxAdd, CtxLenSamples),
                    printer:test_stats_record_entry(Repository://Entry, ModelAVL, ProofAVL, Triggers, true)
                ; % strict failure: classify blocker vs conflict vs other (best-effort)
                  ( current_predicate(rules:with_assume_blockers/1),
                    rules:with_assume_blockers(
                      prover:prove(Repository://Entry:Action?{[]},t,_,t,_,t,_,t,_)
                    ) ->
                      printer:test_stats_record_failed(blocker)
                  ; current_predicate(rules:with_assume_conflicts/1),
                    rules:with_assume_conflicts(
                      prover:prove(Repository://Entry:Action?{[]},t,_,t,_,t,_,t,_)
                    ) ->
                      printer:test_stats_record_failed(conflict)
                  ; printer:test_stats_record_failed(other)
                  )
                )
              )),
  printer:test_stats_print(TopN).

% -----------------------------------------------------------------------------
%  Focused stats: run prover:test_stats for a specific list of Category/Name pairs
% -----------------------------------------------------------------------------

%! prover:test_stats_pkgs(+Repository, +Pkgs)
%
% Run test_stats for a specific list of packages, where Pkgs is a list of C-N pairs.
% This is intended for fast iteration on the slowest packages reported by test_stats/1.
prover:test_stats_pkgs(Repository, Pkgs) :-
  config:test_style(Style),
  ( config:test_stats_top_n(TopN) -> true ; TopN = 25 ),
  prover:test_stats_pkgs(Repository, Style, TopN, Pkgs).

prover:test_stats_pkgs(Repository, Style, TopN, Pkgs) :-
  is_list(Pkgs),
  config:proving_target(Action),
  length(Pkgs, ExpectedTotal),
  printer:test_stats_reset('Proving', ExpectedTotal),
  printer:test_stats_set_expected_unique_packages(ExpectedTotal),
  tester:test(Style,
              'Proving',
              Repository://Entry,
              ( member(C-N, Pkgs),
                once(Repository:ebuild(Entry, C, N, _))
              ),
              ( prover:test_stats_reset_counters,
                statistics(inferences, I0),
                statistics(walltime, [T0,_]),
                ( prover:prove(Repository://Entry:Action?{[]},t,ProofAVL,t,ModelAVL,t,_Constraint,t,Triggers) ->
                    Proved = true
                ; Proved = false
                ),
                statistics(walltime, [T1,_]),
                statistics(inferences, I1),
                TimeMs is T1 - T0,
                Inferences is I1 - I0,
                ( Proved == true ->
                    prover:test_stats_get_counters(rule_calls(RuleCalls)),
                    prover:test_stats_get_ctx_counters(ctx_union_calls(CtxUC), ctx_union_cost(CtxCost), ctx_max_len(CtxMax), ctx_union_ms_est(CtxMsEst)),
                    prover:test_stats_get_ctx_distribution(ctx_len_hist(CtxHistPairs),
                                                          ctx_cost_mul(CtxMul),
                                                          ctx_cost_add(CtxAdd),
                                                          ctx_len_samples(CtxLenSamples)),
                    printer:test_stats_record_costs(Repository://Entry, TimeMs, Inferences, RuleCalls),
                    printer:test_stats_record_context_costs(Repository://Entry, CtxUC, CtxCost, CtxMax, CtxMsEst),
                    printer:test_stats_record_ctx_len_distribution(CtxHistPairs, CtxMul, CtxAdd, CtxLenSamples),
                    printer:test_stats_record_entry(Repository://Entry, ModelAVL, ProofAVL, Triggers, true)
                ; % strict failure: classify blocker vs conflict vs other (best-effort)
                  ( current_predicate(rules:with_assume_blockers/1),
                    rules:with_assume_blockers(
                      prover:prove(Repository://Entry:Action?{[]},t,_,t,_,t,_,t,_)
                    ) ->
                      printer:test_stats_record_failed(blocker)
                  ; current_predicate(rules:with_assume_conflicts/1),
                    rules:with_assume_conflicts(
                      prover:prove(Repository://Entry:Action?{[]},t,_,t,_,t,_,t,_)
                    ) ->
                      printer:test_stats_record_failed(conflict)
                  ; printer:test_stats_record_failed(other)
                  )
                )
              )),
  printer:test_stats_print(TopN).
