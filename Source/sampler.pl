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
  - Runtime callsite stats: sampled stack-walk tracking of residual
    query:search/2 calls that survive goal-expansion
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


% =============================================================================
%  Runtime callsite stats (debugging)
% =============================================================================
%
% Goal-expansion should remove most `query:search/2` calls at compile time.
% Remaining runtime calls can happen when:
% - the call was constructed dynamically (e.g. via call/1)
% - goal-expansion didn't run due to load order / compilation context
% - a query form falls back to the runtime `search/2` clauses
%
% Additionally, SWI-Prolog's profiler often attributes work of meta-calls (call/1)
% to the caller, so `query:search/2` can appear hot even when executing compiled
% cache-level goals. These callsite stats help answer: "who is still calling
% query:search/2 at runtime?"

:- dynamic sampler:search_callsite_stats_enabled/0.
:- dynamic sampler:search_callsite/4.      % File, Line, PI, Count
:- dynamic sampler:search_callsite_sig/5.  % File, Line, PI, Sig, Count
:- dynamic sampler:search_callsite_sample_rate/1.

sampler:search_callsite_sample_rate(4096).


%! sampler:enable_search_callsite_stats is det.
%
% Enable runtime callsite tracking for query:search/2.

sampler:enable_search_callsite_stats :-
  ( sampler:search_callsite_stats_enabled -> true
  ; assertz(sampler:search_callsite_stats_enabled)
  ).


%! sampler:disable_search_callsite_stats is det.
%
% Disable runtime callsite tracking for query:search/2.

sampler:disable_search_callsite_stats :-
  retractall(sampler:search_callsite_stats_enabled).


%! sampler:reset_search_callsites is det.
%
% Clear all accumulated callsite data and reset the sampling counter.

sampler:reset_search_callsites :-
  retractall(sampler:search_callsite(_,_,_,_)),
  retractall(sampler:search_callsite_sig(_,_,_,_,_)),
  nb_setval(query_search_callsite_counter, 0).


%! sampler:set_search_callsite_sample_rate(+Rate) is det.
%
% Set the sampling rate for callsite recording. Only every Nth call is
% recorded to keep overhead low on large runs.

sampler:set_search_callsite_sample_rate(Rate) :-
  integer(Rate),
  Rate > 0,
  retractall(sampler:search_callsite_sample_rate(_)),
  assertz(sampler:search_callsite_sample_rate(Rate)).


%! sampler:report_search_callsites(+TopN) is det.
%
% Print the top N runtime callsites for query:search/2, sorted by count
% (descending).

sampler:report_search_callsites(TopN) :-
  ( integer(TopN), TopN > 0 -> true ; TopN = 50 ),
  findall(Count-File-Line-PI,
          sampler:search_callsite(File, Line, PI, Count),
          Rows0),
  keysort(Rows0, RowsAsc),
  reverse(RowsAsc, Rows),
  format('~n>>> query:search/2 runtime callsites (Top ~d)~n~n', [TopN]),
  format('  ~` t~d~8|  ~` t~s~8|  ~` t~s~s~n', [8, 'Count', 'Line', 'Callsite']),
  format('  ~`-t~80|~n', []),
  sampler:print_search_callsite_rows(Rows, TopN, 1).


%! sampler:report_search_callsites_sig(+TopN) is det.
%
% Print the top N runtime callsites with per-signature breakdown.

sampler:report_search_callsites_sig(TopN) :-
  ( integer(TopN), TopN > 0 -> true ; TopN = 50 ),
  findall(Count-File-Line-PI-Sig,
          sampler:search_callsite_sig(File, Line, PI, Sig, Count),
          Rows0),
  keysort(Rows0, RowsAsc),
  reverse(RowsAsc, Rows),
  format('~n>>> query:search/2 runtime callsites (signature breakdown, Top ~d)~n~n', [TopN]),
  format('  ~` t~d~8|  ~` t~s~8|  ~` t~s~s~n', [8, 'Count', 'Line', 'Callsite / Signature']),
  format('  ~`-t~80|~n', []),
  sampler:print_search_callsite_sig_rows(Rows, TopN, 1).


%! sampler:print_search_callsite_sig_rows(+Rows, +TopN, +I) is det.
%
% Print helper for signature-breakdown callsite rows.

sampler:print_search_callsite_sig_rows([], _, _) :- !.
sampler:print_search_callsite_sig_rows(_, TopN, I) :- I > TopN, !.
sampler:print_search_callsite_sig_rows([Count-File-Line-PI-Sig|Rest], TopN, I) :-
  format('  ~` t~d~8|  ~w:~w~n      ~w~n      ~w~n', [Count, File, Line, PI, Sig]),
  I2 is I + 1,
  sampler:print_search_callsite_sig_rows(Rest, TopN, I2).


%! sampler:print_search_callsite_rows(+Rows, +TopN, +I) is det.
%
% Print helper for basic callsite rows.

sampler:print_search_callsite_rows([], _, _) :- !.
sampler:print_search_callsite_rows(_, TopN, I) :- I > TopN, !.
sampler:print_search_callsite_rows([Count-File-Line-PI|Rest], TopN, I) :-
  format('  ~` t~d~8|  ~w:~w~n      ~w~n', [Count, File, Line, PI]),
  I2 is I + 1,
  sampler:print_search_callsite_rows(Rest, TopN, I2).


%! sampler:maybe_record_search_callsite(+Q, +RepoEntry) is det.
%
% Conditionally record a query:search/2 callsite if stats are enabled.

sampler:maybe_record_search_callsite(Q, RepoEntry) :-
  ( sampler:search_callsite_stats_enabled ->
      sampler:maybe_record_search_callsite_sampled(Q, RepoEntry)
  ; true
  ).


%! sampler:maybe_record_search_callsite_sampled(+Q, +RepoEntry) is det.
%
% Sampled callsite recorder: only records every Nth call to keep overhead
% low even on huge runs.

sampler:maybe_record_search_callsite_sampled(Q, RepoEntry) :-
  ( sampler:search_callsite_sample_rate(Rate) -> true ; Rate = 4096 ),
  ( nb_current(query_search_callsite_counter, C0) -> true ; C0 = 0 ),
  C is C0 + 1,
  nb_setval(query_search_callsite_counter, C),
  ( 0 is C mod Rate ->
      nb_setval(query_search_callsite_last_q, Q),
      nb_setval(query_search_callsite_last_entry, RepoEntry),
      sampler:record_search_callsite
  ; true
  ).


%! sampler:record_search_callsite is det.
%
% Walk the Prolog call stack to identify the external caller of
% query:search/2 and record it in the callsite database.

sampler:record_search_callsite :-
  ( prolog_current_frame(F),
    prolog_frame_attribute(F, parent, Parent0),
    sampler:find_non_trivial_caller_frame(Parent0, CallerFrame0),
    sampler:find_external_callsite_frame(CallerFrame0, CallerFrame),
    sampler:frame_callsite(CallerFrame, File, Line, PI),
    ( nb_current(query_search_callsite_last_q, Q) -> true ; Q = unknown ),
    ( nb_current(query_search_callsite_last_entry, E) -> true ; E = unknown ),
    sampler:search_call_signature(Q, E, Sig)
  -> with_mutex(query_search_callsite,
       ( ( retract(sampler:search_callsite(File, Line, PI, N0)) -> true ; N0 = 0 ),
         N is N0 + 1,
         assertz(sampler:search_callsite(File, Line, PI, N)),
         ( ( retract(sampler:search_callsite_sig(File, Line, PI, Sig, S0)) -> true ; S0 = 0 ),
           S is S0 + 1,
           assertz(sampler:search_callsite_sig(File, Line, PI, Sig, S))
         )
       ))
  ; true
  ).


%! sampler:search_call_signature(+Q, +RepoEntry, -Sig) is det.
%
% Compute a cheap signature for sampled calls to help identify which query
% forms are still reaching runtime query:search/2.

sampler:search_call_signature(Q, RepoEntry, sig(Kind, Head, Flags, EntryKind)) :-
  ( is_list(Q) ->
      Kind = list,
      length(Q, Len),
      Head = list(Len),
      sampler:search_sig_flags(Q, Flags0),
      sort(Flags0, Flags)
  ; compound(Q) ->
      Kind = compound,
      ( Q = select(Key, Op, _Value) ->
          sampler:select_sig_op(Op, OpTag),
          Head = select(Key, OpTag)
      ; functor(Q, F, A),
        Head = F/A
      ),
      Flags = []
  ; Kind = other,
    Head = other,
    Flags = []
  ),
  ( RepoEntry = _Repo://_Id -> EntryKind = op_slash_colon2
  ; EntryKind = other
  ).


%! sampler:select_sig_op(+Op, -OpTag) is det.
%
% Classify a query select operator for signature grouping.

sampler:select_sig_op(Op, OpTag) :-
  ( var(Op) ->
      OpTag = var
  ; atomic(Op) ->
      OpTag = Op
  ; compound(Op) ->
      functor(Op, F, A),
      ( Op = constraint(Inner, _Out) ->
          sampler:constraint_inner_tag(Inner, InnerTag),
          OpTag = constraint(InnerTag)
      ; OpTag = F/A
      )
  ; OpTag = other
  ).


%! sampler:constraint_inner_tag(+Inner, -Tag) is det.
%
% Classify constraint internals for signature grouping.

sampler:constraint_inner_tag(Inner, Tag) :-
  ( var(Inner) -> Tag = var
  ; Inner == [] -> Tag = empty
  ; is_list(Inner) ->
      length(Inner, L),
      Tag = list(L)
  ; Tag = other
  ).


%! sampler:search_sig_flags(+Terms, -Flags) is det.
%
% Extract functor/arity flags from a query term list for signature grouping.

sampler:search_sig_flags([], []) :- !.
sampler:search_sig_flags([H|T], [Flag|Rest]) :-
  ( compound(H) ->
      functor(H, F, A),
      Flag = F/A
  ; Flag = atom
  ),
  sampler:search_sig_flags(T, Rest).


%! sampler:find_non_trivial_caller_frame(+Frame0, -Frame) is det.
%
% Walk up the call stack, skipping trivial wrapper frames (query:search,
% system:call, etc.) until a meaningful caller is found.

sampler:find_non_trivial_caller_frame(Frame0, Frame) :-
  ( var(Frame0) ; Frame0 == 0 ), !,
  Frame = 0.
sampler:find_non_trivial_caller_frame(Frame0, Frame) :-
  ( sampler:frame_predicate_indicator(Frame0, PI),
    sampler:skip_callsite_pi(PI)
  -> ( prolog_frame_attribute(Frame0, parent, Parent),
       sampler:find_non_trivial_caller_frame(Parent, Frame)
     )
  ; Frame = Frame0
  ).


%! sampler:skip_callsite_pi(?PI) is nondet.
%
% Predicate indicators to skip when walking the call stack to find the
% real external caller of query:search/2.

sampler:skip_callsite_pi(query:search/2).
sampler:skip_callsite_pi(query:memoized_search/2).
sampler:skip_callsite_pi(search/2).
sampler:skip_callsite_pi(system:call/1).
sampler:skip_callsite_pi(system:once/1).
sampler:skip_callsite_pi(apply:call_/2).
sampler:skip_callsite_pi(apply:maplist_/3).
sampler:skip_callsite_pi(apply:include_/3).
sampler:skip_callsite_pi(apply:exclude_/3).


%! sampler:frame_predicate_indicator(+Frame, -PI) is det.
%
% Retrieve the predicate indicator for a stack frame, or unknown/0 on
% failure.

sampler:frame_predicate_indicator(Frame, PI) :-
  prolog_frame_attribute(Frame, predicate_indicator, PI),
  !.
sampler:frame_predicate_indicator(_Frame, unknown/0).


%! sampler:frame_callsite(+Frame, -File, -Line, -PI) is det.
%
% Extract file, line number, and predicate indicator from a stack frame.

sampler:frame_callsite(Frame, File, Line, PI) :-
  sampler:frame_predicate_indicator(Frame, PI),
  ( prolog_frame_attribute(Frame, clause, ClauseRef),
    clause_property(ClauseRef, file(File0))
  -> File = File0
  ; File = '<unknown>'
  ),
  ( prolog_frame_attribute(Frame, clause, ClauseRef2),
    ( clause_property(ClauseRef2, line(Line0))
    ; clause_property(ClauseRef2, line_count(Line0))
    )
  -> Line = Line0
  ; Line = '?'
  ).


%! sampler:find_external_callsite_frame(+Frame0, -Frame) is det.
%
% Walk up the call stack until a frame outside query.pl is found, so the
% report points at the actual caller rather than query internals.

sampler:find_external_callsite_frame(Frame0, Frame) :-
  ( var(Frame0) ; Frame0 == 0 ), !,
  Frame = Frame0.
sampler:find_external_callsite_frame(Frame0, Frame) :-
  sampler:frame_callsite(Frame0, File, _Line, PI),
  ( File == '/Users/pvdabeel/Desktop/Prolog/Source/query.pl'
    ; sampler:skip_callsite_pi(PI)
  ),
  !,
  ( prolog_frame_attribute(Frame0, parent, Parent) ->
      sampler:find_external_callsite_frame(Parent, Frame)
  ; Frame = Frame0
  ).
sampler:find_external_callsite_frame(Frame0, Frame0).
