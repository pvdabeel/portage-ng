/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> SAMPLER
Lightweight performance sampling, instrumentation, and diagnostics.

Provides periodic sampling with rate control and statistical extrapolation
for measuring hot-path performance without adding significant overhead.

Subsystems:

  - Literal hook sampling: measures cost of PDEPEND hook processing (rules)
  - Context union sampling: measures cost of context list operations (prover)
  - Hook performance counters: count-based metrics for domain literal hook
    (done-hits, hook-fired, extra/fresh literals)
  - Timeout diagnostics: best-effort trace capture and literal simplification
    for diagnosing prover timeouts and failures
*/

:- module(sampler, []).


% =============================================================================
%  Compile-time instrumentation gating
% =============================================================================
%
% Unless the application is started with -Dinstrumentation=true (e.g. via
% --profile), all hot-path instrumentation calls are compiled to `true`
% by goal_expansion, leaving zero overhead in the prover loop.

:- multifile user:goal_expansion/2.

user:goal_expansion(test_stats_rule_call, true) :-
  \+ current_prolog_flag(instrumentation, true).

user:goal_expansion(obligation_counter_done_hit, true) :-
  \+ current_prolog_flag(instrumentation, true).

user:goal_expansion(obligation_counter_fired(_), true) :-
  \+ current_prolog_flag(instrumentation, true).

user:goal_expansion(obligation_counter_fresh(_), true) :-
  \+ current_prolog_flag(instrumentation, true).

user:goal_expansion(obligation_counter_reset, true) :-
  \+ current_prolog_flag(instrumentation, true).

user:goal_expansion(obligation_counter_report, true) :-
  \+ current_prolog_flag(instrumentation, true).

user:goal_expansion(obligation_perf_reset, true) :-
  \+ current_prolog_flag(instrumentation, true).

user:goal_expansion(obligation_perf_report, true) :-
  \+ current_prolog_flag(instrumentation, true).

user:goal_expansion(maybe_timeout_trace(_), true) :-
  \+ current_prolog_flag(instrumentation, true).


% =============================================================================
%  Proof obligation performance sampling
% =============================================================================
%
% Samples 1 in N calls to measure proof-obligation (domain hook) cost
% without adding noticeable overhead to every prove step.

%! sampler:obligation_perf_reset is det.
%
% Zero all proof-obligation sampling counters (calls, has/no extra
% obligations, sample count, and accumulated sample time).

sampler:obligation_perf_reset :-
  flag(po_calls, _, 0),
  flag(po_has_extra, _, 0),
  flag(po_no_extra, _, 0),
  flag(po_sample_n, _, 0),
  flag(po_sample_ms_sum, _, 0),
  !.


%! sampler:obligation_perf_report is det.
%
% Print a one-line summary of proof-obligation sampling statistics:
% total calls, extra/no-extra counts, sample count, total sampled time,
% average per-call time, and estimated total time across all calls.

sampler:obligation_perf_report :-
  flag(po_calls, Calls, Calls),
  flag(po_has_extra, HasP, HasP),
  flag(po_no_extra, NoP, NoP),
  flag(po_sample_n, SN, SN),
  flag(po_sample_ms_sum, SMs, SMs),
  ( SN =:= 0 ->
      AvgMs = 0,
      EstTotalMs = 0
  ; AvgMs is SMs / SN,
    EstTotalMs is AvgMs * Calls
  ),
  message:scroll_notice(['proof_obligation perf: calls=',Calls,
                         ' has_extra=',HasP,
                         ' no_extra=',NoP,
                         ' sample_n=',SN,
                         ' sample_ms_sum=',SMs,
                         ' avg_ms=',AvgMs,
                         ' est_total_ms=',EstTotalMs]),
  nl,
  !.


%! sampler:obligation_sample_rate(-N) is det.
%
% The sampling rate: measure timing on every Nth call. Set to 1 for
% full profiling (expensive) or a large value for low-overhead sampling.

sampler:obligation_sample_rate(1000).


%! sampler:obligation_maybe_sample(:Goal) is semidet.
%
% Execute Goal, optionally wrapping it in wall-clock timing if this call
% hits the 1-in-N sampling window. Increments the call counter on every
% invocation; only the sampled calls pay the timing overhead.

sampler:obligation_maybe_sample(Goal) :-
  flag(po_calls, C0, C0+1),
  sampler:obligation_sample_rate(N),
  ( N =< 1 ->
      statistics(walltime, [T0,_]),
      ( Goal -> Ok = true ; Ok = false ),
      statistics(walltime, [T1,_]),
      Dt is T1 - T0,
      flag(po_sample_n, SN0, SN0+1),
      flag(po_sample_ms_sum, SM0, SM0+Dt),
      Ok == true
  ; C1 is C0 + 1,
    ( 0 is C1 mod N ->
        statistics(walltime, [T0,_]),
        ( Goal -> Ok = true ; Ok = false ),
        statistics(walltime, [T1,_]),
        Dt is T1 - T0,
        flag(po_sample_n, SN0, SN0+1),
        flag(po_sample_ms_sum, SM0, SM0+Dt),
        Ok == true
    ; Goal
    )
  ).


% =============================================================================
%  Test stats: rule call counter
% =============================================================================
%
% Counts rule/2 applications during test_stats runs. Designed as a true no-op
% when test_stats is not active (counter does not exist).

%! sampler:test_stats_reset_counters is det.
%
% Initialize all test-stats global counters to zero (rule calls,
% context-union calls/cost/max-length, length histogram, cost
% breakdown, and timing sample accumulators).

sampler:test_stats_reset_counters :-
  nb_setval(prover_test_stats_rule_calls, 0),
  nb_setval(prover_test_stats_ctx_union_calls, 0),
  nb_setval(prover_test_stats_ctx_union_cost, 0),
  nb_setval(prover_test_stats_ctx_max_len, 0),
  empty_assoc(EmptyHist),
  nb_setval(prover_test_stats_ctx_len_hist, EmptyHist),
  nb_setval(prover_test_stats_ctx_cost_mul, 0),
  nb_setval(prover_test_stats_ctx_cost_add, 0),
  nb_setval(prover_test_stats_ctx_union_time_sample_rate, 64),
  nb_setval(prover_test_stats_ctx_union_time_samples, 0),
  nb_setval(prover_test_stats_ctx_union_time_ms_sampled, 0).


%! sampler:test_stats_rule_call is det.
%
% Increment the rule-call counter if a test_stats run is active.
% No-op when the counter does not exist.

sampler:test_stats_rule_call :-
  ( nb_current(prover_test_stats_rule_calls, N0) ->
      N is N0 + 1,
      nb_setval(prover_test_stats_rule_calls, N)
  ; true
  ).


%! sampler:test_stats_get_counters(-RuleCalls) is det.
%
% Retrieve the current rule-call count as `rule_calls(N)`.

sampler:test_stats_get_counters(rule_calls(RuleCalls)) :-
  ( nb_current(prover_test_stats_rule_calls, RuleCalls) -> true ; RuleCalls = 0 ).


%! sampler:test_stats_get_ctx_counters(-Calls, -CostEst, -MaxLen, -MsEst) is det.
%
% Retrieve context-union instrumentation counters. Values are returned as
% wrapped terms: `ctx_union_calls(N)`, `ctx_union_cost(N)`,
% `ctx_max_len(N)`, `ctx_union_ms_est(N)`. Cost and time are
% extrapolated from sampled data to the full call count.

sampler:test_stats_get_ctx_counters(ctx_union_calls(Calls),
                                    ctx_union_cost(CostEst),
                                    ctx_max_len(MaxLen),
                                    ctx_union_ms_est(MsEst)) :-
  ( nb_current(prover_test_stats_ctx_union_calls, Calls) -> true ; Calls = 0 ),
  ( nb_current(prover_test_stats_ctx_union_cost, CostSampled) -> true ; CostSampled = 0 ),
  ( nb_current(prover_test_stats_ctx_max_len, MaxLen) -> true ; MaxLen = 0 ),
  ( nb_current(prover_test_stats_ctx_union_time_samples, Samples) -> true ; Samples = 0 ),
  ( nb_current(prover_test_stats_ctx_union_time_ms_sampled, MsSampled) -> true ; MsSampled = 0 ),
  ( Samples =:= 0 ->
      MsEst = 0,
      CostEst = 0
  ; MsEst0 is MsSampled * Calls / Samples,
    MsEst is round(MsEst0),
    CostEst0 is CostSampled * Calls / Samples,
    CostEst is round(CostEst0)
  ).


%! sampler:test_stats_get_ctx_distribution(-HistPairs, -SumMul, -SumAdd, -Samples) is det.
%
% Retrieve context-union distribution data: output-length histogram
% (`ctx_len_hist(Pairs)`), quadratic cost sum (`ctx_cost_mul(N)`),
% linear cost sum (`ctx_cost_add(N)`), and total samples taken.

sampler:test_stats_get_ctx_distribution(ctx_len_hist(HistPairs),
                                        ctx_cost_mul(SumMul),
                                        ctx_cost_add(SumAdd),
                                        ctx_len_samples(Samples)) :-
  ( nb_current(prover_test_stats_ctx_len_hist, HistAssoc) -> true ; empty_assoc(HistAssoc) ),
  assoc_to_list(HistAssoc, HistPairs),
  ( nb_current(prover_test_stats_ctx_cost_mul, SumMul) -> true ; SumMul = 0 ),
  ( nb_current(prover_test_stats_ctx_cost_add, SumAdd) -> true ; SumAdd = 0 ),
  ( nb_current(prover_test_stats_ctx_union_time_samples, Samples) -> true ; Samples = 0 ).


% =============================================================================
%  Context union: raw implementation + self/1 helpers
% =============================================================================

%! sampler:ctx_union_raw(+OldCtx, +Ctx, -NewCtx) is det.
%
% Raw context union that strips `self/1` provenance before merging
% to prevent unbounded accumulation through repeated refinements.

sampler:ctx_union_raw(OldCtx, Ctx, NewCtx) :-
  sampler:ctx_strip_self(OldCtx, OldNoSelf),
  sampler:ctx_strip_self_keep_one(Ctx, SelfTerm, CtxNoSelf),
  feature_unification:unify(OldNoSelf, CtxNoSelf, Merged),
  sampler:ctx_prepend_self(SelfTerm, Merged, NewCtx),
  !.


%! sampler:ctx_strip_self(+Ctx0, -Ctx) is det.
%
% Remove all `self/1` terms from a context list.

sampler:ctx_strip_self(Ctx0, Ctx) :-
  ( is_list(Ctx0) ->
      exclude(sampler:is_self_term, Ctx0, Ctx)
  ; Ctx = Ctx0
  ),
  !.

sampler:is_self_term(self(_)).


%! sampler:ctx_strip_self_keep_one(+Ctx0, -SelfTerm, -Ctx) is det.
%
% Extract the first `self/1` term from Ctx0 and remove all others.

sampler:ctx_strip_self_keep_one(Ctx0, SelfTerm, Ctx) :-
  ( is_list(Ctx0) ->
      sampler:ctx_extract_self(Ctx0, SelfTerm, Ctx)
  ; SelfTerm = none,
    Ctx = Ctx0
  ),
  !.


%! sampler:ctx_extract_self(+Ctx0, -Self, -Ctx) is det.
%
% Extract the first `self(S)` from Ctx0 into Self, removing all others.

sampler:ctx_extract_self([], none, []).
sampler:ctx_extract_self([self(S)|T], self(S), Rest) :-
  !, exclude(sampler:is_self_term, T, Rest).
sampler:ctx_extract_self([H|T], Self, [H|Rest]) :-
  sampler:ctx_extract_self(T, Self, Rest).


%! sampler:ctx_prepend_self(+SelfTerm, +Ctx0, -Ctx) is det.
%
% Prepend a previously extracted `self/1` term back onto a context list.

sampler:ctx_prepend_self(none, Ctx, Ctx) :- !.
sampler:ctx_prepend_self(self(S), Ctx0, Ctx) :-
  ( is_list(Ctx0) ->
      Ctx = [self(S)|Ctx0]
  ; Ctx = Ctx0
  ),
  !.


% =============================================================================
%  Context union instrumentation (sampled)
% =============================================================================
%
% Wraps sampler:ctx_union_raw/3 with periodic sampling of input/output lengths,
% timing, and cost metrics. Only active during test_stats runs.

%! sampler:ctx_union(+OldCtx, +Ctx, -NewCtx) is det.
%
% Instrumented wrapper around `sampler:ctx_union_raw/3`. When a test_stats
% run is active, periodically samples input/output list lengths, wall-clock
% timing, and cost metrics (every 64th call after the first 16). Outside
% a test_stats run, delegates directly to ctx_union_raw.

sampler:ctx_union(OldCtx, Ctx, NewCtx) :-
  ( nb_current(prover_test_stats_ctx_union_calls, C0) ->
      C is C0 + 1,
      nb_setval(prover_test_stats_ctx_union_calls, C),
      ( ( C =< 16 ; 0 is C /\ 63 ) ->
          ( is_list(OldCtx) -> length(OldCtx, L0) ; L0 = 0 ),
          ( is_list(Ctx)    -> length(Ctx, L1)    ; L1 = 0 ),
          statistics(walltime, [T0,_]),
          sampler:ctx_union_raw(OldCtx, Ctx, NewCtx),
          statistics(walltime, [T1,_]),
          Dt is T1 - T0,
          ( is_list(NewCtx) -> length(NewCtx, L2) ; L2 = 0 ),
          ( nb_current(prover_test_stats_ctx_union_time_samples, S0) -> true ; S0 = 0 ),
          ( nb_current(prover_test_stats_ctx_union_time_ms_sampled, M0s) -> true ; M0s = 0 ),
          S1 is S0 + 1, M1s is M0s + Dt,
          nb_setval(prover_test_stats_ctx_union_time_samples, S1),
          nb_setval(prover_test_stats_ctx_union_time_ms_sampled, M1s),
          ( nb_current(prover_test_stats_ctx_union_cost, K0) -> true ; K0 = 0 ),
          ( nb_current(prover_test_stats_ctx_max_len,    M0) -> true ; M0 = 0 ),
          K is K0 + L0 + L1,
          M is max(M0, max(L0, max(L1, L2))),
          nb_setval(prover_test_stats_ctx_union_cost, K),
          nb_setval(prover_test_stats_ctx_max_len,    M),
          sampler:ctx_union_sampled(L0, L1, L2)
      ;
          sampler:ctx_union_raw(OldCtx, Ctx, NewCtx)
      )
  ; sampler:ctx_union_raw(OldCtx, Ctx, NewCtx)
  ).


%! sampler:ctx_union_sampled(+L0, +L1, +L2) is det.
%
% Record a sampled context-union observation: update the output-length
% histogram and accumulate quadratic (`L0 * L1`) and linear (`L0 + L1`)
% cost components.

sampler:ctx_union_sampled(L0, L1, L2) :-
  ( nb_current(prover_test_stats_ctx_len_hist, Hist0) -> true ; empty_assoc(Hist0) ),
  ( get_assoc(L2, Hist0, C0) -> true ; C0 = 0 ),
  C1 is C0 + 1,
  put_assoc(L2, Hist0, C1, Hist1),
  nb_setval(prover_test_stats_ctx_len_hist, Hist1),
  ( nb_current(prover_test_stats_ctx_cost_mul, Mul0) -> true ; Mul0 = 0 ),
  ( nb_current(prover_test_stats_ctx_cost_add, Add0) -> true ; Add0 = 0 ),
  Mul1 is Mul0 + L0 * L1,
  Add1 is Add0 + L0 + L1,
  nb_setval(prover_test_stats_ctx_cost_mul, Mul1),
  nb_setval(prover_test_stats_ctx_cost_add, Add1).


% =============================================================================
%  Proof obligation counters
% =============================================================================
%
% Count-based counters for whole-repo runs via prover:test/*, to help answer:
% is the slowdown due to obligation work itself, or due to proving many more
% literals?

%! sampler:obligation_counter_reset is det
%
% Reset all proof-obligation performance counters.

sampler:obligation_counter_reset :-
  flag(obligation_done_hits, _, 0),
  flag(obligation_fired, _, 0),
  flag(obligation_extra_lits, _, 0),
  flag(obligation_fresh_lits, _, 0),
  sampler:obligation_perf_reset,
  !.


%! sampler:obligation_counter_done_hit is det
%
% Increment the "obligation already done" hit counter.

sampler:obligation_counter_done_hit :-
  flag(obligation_done_hits, X, X+1),
  !.


%! sampler:obligation_counter_fired(+ExtraLits) is det
%
% Increment obligation-fired counter and add |ExtraLits| to total extra literals.

sampler:obligation_counter_fired(ExtraLits) :-
  length(ExtraLits, ExtraN),
  flag(obligation_fired, X, X+1),
  flag(obligation_extra_lits, Y, Y+ExtraN),
  !.


%! sampler:obligation_counter_fresh(+FreshLits) is det
%
% Add |FreshLits| to the count of fresh (not-yet-proven) literals enqueued.

sampler:obligation_counter_fresh(FreshLits) :-
  length(FreshLits, FreshN),
  flag(obligation_fresh_lits, X, X+FreshN),
  !.


%! sampler:obligation_counter_report is det
%
% Print accumulated proof-obligation performance counters.

sampler:obligation_counter_report :-
  flag(obligation_fired, Fired, Fired),
  flag(obligation_extra_lits, Extra, Extra),
  flag(obligation_fresh_lits, Fresh, Fresh),
  flag(obligation_done_hits, DoneHits, DoneHits),
  nl,
  message:scroll_notice(['Proof obligation perf: fired=',Fired,
                         ' extra_lits=',Extra,
                         ' fresh_lits=',Fresh,
                         ' done_hits=',DoneHits]),
  nl,
  sampler:obligation_perf_report,
  !.


% =============================================================================
%  Timeout trace: prover hot-path wrapper
% =============================================================================


%! sampler:maybe_timeout_trace(+Lit) is det
%
% If a timeout trace is active, push a rule_call event.
% Compiled to `true` when instrumentation is off.

sampler:maybe_timeout_trace(Lit) :-
  ( nb_current(prover_timeout_trace, _) ->
      sampler:trace_simplify(Lit, Simple),
      sampler:timeout_trace_push(rule_call(Simple))
  ; true
  ).


% =============================================================================
%  Timeout diagnostics (best-effort)
% =============================================================================
%
% Used by tester on timeouts to capture a short "where were we" trace without
% enabling full tracing (which is too expensive at scale).

%! sampler:trace_simplify(+Item, -Simple) is det
%
% Reduce a literal to a compact, comparable representation for timeout
% diagnostics.  Strips large sub-terms (bodies, USE-dep lists) so traces
% stay small and loops become visible.

sampler:trace_simplify(Item, Simple) :-
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
      Simple = conflict(A)
  ; Item = Inner:Action,
    atom(Action) ->
      sampler:trace_simplify(Inner, InnerS),
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


%! sampler:timeout_trace_reset is det
%
% Clear the timeout trace buffer.

sampler:timeout_trace_reset :-
  nb_setval(prover_timeout_trace, []).


%! sampler:timeout_trace_push(+Item0) is det
%
% Push a simplified literal onto the timeout trace ring buffer,
% updating frequency counters when enabled.

sampler:timeout_trace_push(Item0) :-
  ( nb_current(prover_timeout_count_assoc, A0) ->
      ( get_assoc(Item0, A0, N0) -> true ; N0 = 0 ),
      N is N0 + 1,
      put_assoc(Item0, A0, N, A1),
      nb_setval(prover_timeout_count_assoc, A1)
  ; true
  ),
  ( nb_current(prover_timeout_trace, L0) -> true ; L0 = [] ),
  L1 = [Item0|L0],
  ( nb_current(prover_timeout_trace_maxlen, MaxLen) -> true ; MaxLen = 200 ),
  length(L1, Len),
  ( Len =< MaxLen ->
      nb_setval(prover_timeout_trace, L1)
  ; length(Keep, MaxLen),
    append(Keep, _Drop, L1),
    nb_setval(prover_timeout_trace, Keep)
  ).


%! sampler:timeout_trace_hook(+Target, +Proof, +Model, +Constraints) is det
%
% Debug-hook callback that records simplified literals into the
% timeout trace and frequency counters.

sampler:timeout_trace_hook(Target, _Proof, _Model, _Constraints) :-
  ( catch(prover:canon_literal(Target, Lit0, _Ctx), _, fail) ->
      Lit = Lit0
  ; Lit = Target
  ),
  sampler:trace_simplify(Lit, Simple),
  ( nb_current(prover_timeout_count_assoc, A0) ->
      ( get_assoc(Simple, A0, N0) -> true ; N0 = 0 ),
      N is N0 + 1,
      put_assoc(Simple, A0, N, A1),
      nb_setval(prover_timeout_count_assoc, A1)
  ; true
  ),
  sampler:timeout_trace_push(Simple).


%! sampler:diagnose_timeout(+Target, +LimitSec, -Diagnosis) is det
%
% Run a short best-effort diagnosis for Target with a time limit of
% LimitSec seconds.  Always succeeds; returns a
% `diagnosis(DeltaInferences, RuleCalls, Trace)` term.

sampler:diagnose_timeout(Target, LimitSec, diagnosis(DeltaInferences, RuleCalls, Trace)) :-
  sampler:timeout_trace_reset,
  sampler:test_stats_reset_counters,
  statistics(inferences, I0),
  ( catch(
      prover:with_debug_hook(sampler:timeout_trace_hook,
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
  sampler:test_stats_get_counters(rule_calls(RuleCalls)),
  ( nb_current(prover_timeout_trace, TraceRev) -> reverse(TraceRev, Trace) ; Trace = [] ).


%! sampler:diagnose_timeout_counts(+Target, +LimitSec, -Diagnosis, -TopCounts) is det
%
% Like diagnose_timeout/3, but also returns a TopCounts list
% (up to 20) of the most frequent simplified literals seen during
% the run.

sampler:diagnose_timeout_counts(Target, LimitSec, Diagnosis, TopCounts) :-
  empty_assoc(A0),
  nb_setval(prover_timeout_count_assoc, A0),
  sampler:diagnose_timeout(Target, LimitSec, Diagnosis),
  ( nb_current(prover_timeout_count_assoc, A1) -> true ; A1 = A0 ),
  nb_delete(prover_timeout_count_assoc),
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
