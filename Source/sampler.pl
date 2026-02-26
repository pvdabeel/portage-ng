/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> SAMPLER
Lightweight performance sampling and instrumentation infrastructure.

Provides periodic sampling with rate control and statistical extrapolation
for measuring hot-path performance without adding significant overhead.

Two subsystems:
  - Literal hook sampling: measures cost of PDEPEND hook processing (rules)
  - Context union sampling: measures cost of context list operations (prover)
*/

:- module(sampler, []).


% =============================================================================
%  Literal hook performance sampling
% =============================================================================
%
% Samples 1 in N calls to measure PDEPEND hook cost without adding
% noticeable overhead to every prove step.

%! sampler:literal_hook_perf_reset is det.
%
% Zero all literal-hook sampling counters (calls, has/no PDEPEND hits,
% sample count, and accumulated sample time).

sampler:literal_hook_perf_reset :-
  flag(lit_hook_calls, _, 0),
  flag(lit_hook_has_pdepend, _, 0),
  flag(lit_hook_no_pdepend, _, 0),
  flag(lit_hook_sample_n, _, 0),
  flag(lit_hook_sample_ms_sum, _, 0),
  !.


%! sampler:literal_hook_perf_report is det.
%
% Print a one-line summary of literal-hook sampling statistics: total
% calls, PDEPEND hit/miss counts, sample count, total sampled time,
% average per-call time, and estimated total time across all calls.

sampler:literal_hook_perf_report :-
  flag(lit_hook_calls, Calls, Calls),
  flag(lit_hook_has_pdepend, HasP, HasP),
  flag(lit_hook_no_pdepend, NoP, NoP),
  flag(lit_hook_sample_n, SN, SN),
  flag(lit_hook_sample_ms_sum, SMs, SMs),
  ( SN =:= 0 ->
      AvgMs = 0,
      EstTotalMs = 0
  ; AvgMs is SMs / SN,
    EstTotalMs is AvgMs * Calls
  ),
  message:scroll_notice(['literal_hook perf: calls=',Calls,
                         ' has_pdepend=',HasP,
                         ' no_pdepend=',NoP,
                         ' sample_n=',SN,
                         ' sample_ms_sum=',SMs,
                         ' avg_ms=',AvgMs,
                         ' est_total_ms=',EstTotalMs]),
  nl,
  !.


%! sampler:lit_hook_sample_rate(-N) is det.
%
% The sampling rate: measure timing on every Nth call. Set to 1 for
% full profiling (expensive) or a large value for low-overhead sampling.

sampler:lit_hook_sample_rate(1000).


%! sampler:lit_hook_maybe_sample(:Goal) is semidet.
%
% Execute Goal, optionally wrapping it in wall-clock timing if this call
% hits the 1-in-N sampling window. Increments the call counter on every
% invocation; only the sampled calls pay the timing overhead.

sampler:lit_hook_maybe_sample(Goal) :-
  flag(lit_hook_calls, C0, C0+1),
  sampler:lit_hook_sample_rate(N),
  ( N =< 1 ->
      statistics(walltime, [T0,_]),
      ( Goal -> Ok = true ; Ok = false ),
      statistics(walltime, [T1,_]),
      Dt is T1 - T0,
      flag(lit_hook_sample_n, SN0, SN0+1),
      flag(lit_hook_sample_ms_sum, SM0, SM0+Dt),
      Ok == true
  ; C1 is C0 + 1,
    ( 0 is C1 mod N ->
        statistics(walltime, [T0,_]),
        ( Goal -> Ok = true ; Ok = false ),
        statistics(walltime, [T1,_]),
        Dt is T1 - T0,
        flag(lit_hook_sample_n, SN0, SN0+1),
        flag(lit_hook_sample_ms_sum, SM0, SM0+Dt),
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
%  Context union instrumentation (sampled)
% =============================================================================
%
% Wraps prover:ctx_union_raw/3 with periodic sampling of input/output lengths,
% timing, and cost metrics. Only active during test_stats runs.

%! sampler:ctx_union(+OldCtx, +Ctx, -NewCtx) is det.
%
% Instrumented wrapper around `prover:ctx_union_raw/3`. When a test_stats
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
          prover:ctx_union_raw(OldCtx, Ctx, NewCtx),
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
          prover:ctx_union_raw(OldCtx, Ctx, NewCtx)
      )
  ; prover:ctx_union_raw(OldCtx, Ctx, NewCtx)
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
