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


% =============================================================================
%  Hook performance counters (domain literal hook / PDEPEND)
% =============================================================================
%
% Count-based counters for whole-repo runs via prover:test/*, to help answer:
% is the slowdown due to hook work itself, or due to proving many more
% literals?

%! sampler:hook_perf_reset is det
%
% Reset all domain-hook performance counters.

sampler:hook_perf_reset :-
  flag(hook_perf_done_hits, _, 0),
  flag(hook_perf_hook_fired, _, 0),
  flag(hook_perf_extra_lits, _, 0),
  flag(hook_perf_fresh_lits, _, 0),
  sampler:literal_hook_perf_reset,
  !.


%! sampler:hook_perf_done_hit is det
%
% Increment the "hook already done" hit counter.

sampler:hook_perf_done_hit :-
  flag(hook_perf_done_hits, X, X+1),
  !.


%! sampler:hook_perf_hook_fired(+ExtraN) is det
%
% Increment hook-fired counter and add ExtraN to total extra literals.

sampler:hook_perf_hook_fired(ExtraN) :-
  flag(hook_perf_hook_fired, X, X+1),
  flag(hook_perf_extra_lits, Y, Y+ExtraN),
  !.


%! sampler:hook_perf_fresh_selected(+FreshN) is det
%
% Add FreshN to the count of fresh (not-yet-proven) literals enqueued.

sampler:hook_perf_fresh_selected(FreshN) :-
  flag(hook_perf_fresh_lits, X, X+FreshN),
  !.


%! sampler:hook_perf_report is det
%
% Print accumulated domain-hook performance counters.

sampler:hook_perf_report :-
  flag(hook_perf_hook_fired, Fired, Fired),
  flag(hook_perf_extra_lits, Extra, Extra),
  flag(hook_perf_fresh_lits, Fresh, Fresh),
  flag(hook_perf_done_hits, DoneHits, DoneHits),
  nl,
  message:scroll_notice(['Hook perf: fired=',Fired,
                         ' extra_lits=',Extra,
                         ' fresh_lits=',Fresh,
                         ' done_hits=',DoneHits]),
  nl,
  sampler:literal_hook_perf_report,
  !.


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
