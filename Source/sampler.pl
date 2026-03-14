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

user:goal_expansion(perf_walltime(_), true) :-
  \+ current_prolog_flag(instrumentation, true).

user:goal_expansion(perf_record(_, _, _, _), true) :-
  \+ current_prolog_flag(instrumentation, true).

user:goal_expansion(prove_plan_perf_reset, true) :-
  \+ current_prolog_flag(instrumentation, true).

user:goal_expansion(prove_plan_perf_report, true) :-
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
%  Test statistics: cross-test summary (recording)
% =============================================================================
%
% Dynamic facts and recording predicates for whole-repo test runs.
% Printing predicates remain in printer.pl and access these via sampler:*.

:- dynamic sampler:test_stats_stat/2.
:- dynamic sampler:test_stats_type/3.
:- dynamic sampler:test_stats_cycle_mention/3.
:- dynamic sampler:test_stats_entry_had_cycle/1.
:- dynamic sampler:test_stats_other_head/2.
:- dynamic sampler:test_stats_pkg/3.
:- dynamic sampler:test_stats_type_entry_mention/3.
:- dynamic sampler:test_stats_entry_time/2.
:- dynamic sampler:test_stats_pkg_time/5.
:- dynamic sampler:test_stats_entry_cost/4.      % RepoEntry, TimeMs, Inferences, RuleCalls
:- dynamic sampler:test_stats_pkg_cost/6.        % C, N, SumMs, SumInf, SumRuleCalls, Cnt
:- dynamic sampler:test_stats_entry_ctx/5.       % RepoEntry, UnionCalls, UnionCost, MaxCtxLen, UnionMsEst
:- dynamic sampler:test_stats_pkg_ctx/6.         % C, N, SumUnionCost, MaxCtxLen, SumUnionMsEst, Cnt
:- dynamic sampler:test_stats_ctx_len_bin/2.     % CtxLen, Count (sampled)
:- dynamic sampler:test_stats_ctx_cost_model/3.  % SumMul, SumAdd, Samples (sampled)
:- dynamic sampler:test_stats_failed_entry/2.    % RepoEntry, Reason
:- dynamic sampler:test_stats_blocker_sp/3.      % Strength, Phase, Count
:- dynamic sampler:test_stats_blocker_cn/3.      % C, N, Count
:- dynamic sampler:test_stats_blocker_example/1. % Example term that failed to parse for breakdown
:- dynamic sampler:test_stats_blocker_reason/2.  % Reason, Count
:- dynamic sampler:test_stats_blocker_rp/3.      % Reason, Phase, Count
:- dynamic sampler:test_stats_emerge_time/2.     % Entry (atom, e.g. 'dev-python/foo-1.2'), EmergeMs

%! sampler:test_stats_reset(+Label, +ExpectedTotal)
%
% Reset all test_stats dynamic facts and initialise counters for a new
% whole-repo test run identified by Label with ExpectedTotal entries.

sampler:test_stats_reset(Label, ExpectedTotal) :-
  with_mutex(test_stats,
    ( retractall(sampler:test_stats_stat(_,_)),
      retractall(sampler:test_stats_type(_,_,_)),
      retractall(sampler:test_stats_cycle_mention(_,_,_)),
      retractall(sampler:test_stats_entry_had_cycle(_)),
      retractall(sampler:test_stats_entry_time(_,_)),
      retractall(sampler:test_stats_pkg_time(_,_,_,_,_)),
      retractall(sampler:test_stats_entry_cost(_,_,_,_)),
      retractall(sampler:test_stats_pkg_cost(_,_,_,_,_,_)),
      retractall(sampler:test_stats_entry_ctx(_,_,_,_,_)),
      retractall(sampler:test_stats_pkg_ctx(_,_,_,_,_,_)),
      retractall(sampler:test_stats_ctx_len_bin(_,_)),
      retractall(sampler:test_stats_ctx_cost_model(_,_,_)),
      retractall(sampler:test_stats_failed_entry(_,_)),
      retractall(sampler:test_stats_blocker_sp(_,_,_)),
      retractall(sampler:test_stats_blocker_cn(_,_,_)),
      retractall(sampler:test_stats_blocker_example(_)),
      retractall(sampler:test_stats_blocker_reason(_,_)),
      retractall(sampler:test_stats_blocker_rp(_,_,_)),
      retractall(sampler:test_stats_other_head(_,_)),
      retractall(sampler:test_stats_pkg(_,_,_)),
      retractall(sampler:test_stats_type_entry_mention(_,_,_)),
      assertz(sampler:test_stats_stat(label, Label)),
      ( Label == 'Proving'   -> Stage = prover
      ; Label == 'Planning'  -> Stage = planner
      ; Label == 'Scheduling'-> Stage = scheduler
      ; Label == 'Printing'  -> Stage = printer
      ; Label == 'Pipeline'  -> Stage = printer
      ; Stage = printer
      ),
      assertz(sampler:test_stats_stat(stage, Stage)),
      assertz(sampler:test_stats_stat(expected_total, ExpectedTotal)),
      assertz(sampler:test_stats_stat(expected_unique_packages, 0)),
      assertz(sampler:test_stats_stat(processed, 0)),
      assertz(sampler:test_stats_stat(entries_failed, 0)),
      assertz(sampler:test_stats_stat(entries_failed_blocker, 0)),
      assertz(sampler:test_stats_stat(entries_failed_timeout, 0)),
      assertz(sampler:test_stats_stat(entries_failed_other, 0)),
      assertz(sampler:test_stats_stat(entries_with_assumptions, 0)),
      assertz(sampler:test_stats_stat(entries_with_package_assumptions, 0)),
      assertz(sampler:test_stats_stat(entries_with_cycles, 0)),
      assertz(sampler:test_stats_stat(cycles_found, 0))
    )).

sampler:test_stats_record_failed(Reason) :-
  sampler:test_stats_inc(entries_failed),
  ( Reason == blocker ->
      sampler:test_stats_inc(entries_failed_blocker)
  ; Reason == timeout ->
      sampler:test_stats_inc(entries_failed_timeout)
  ; sampler:test_stats_inc(entries_failed_other)
  ).

sampler:test_stats_record_failed_entry(RepoEntry, Reason) :-
  with_mutex(test_stats,
    ( assertz(sampler:test_stats_failed_entry(RepoEntry, Reason))
    )).

sampler:test_stats_set_expected_unique_packages(N) :-
  with_mutex(test_stats,
    ( retractall(sampler:test_stats_stat(expected_unique_packages,_)),
      assertz(sampler:test_stats_stat(expected_unique_packages, N))
    )).

sampler:test_stats_add_pkg(Bucket, Repo, Entry) :-
  ( cache:ordered_entry(Repo, Entry, C, N, _) ->
      with_mutex(test_stats,
        ( sampler:test_stats_pkg(Bucket, C, N) -> true
        ; assertz(sampler:test_stats_pkg(Bucket, C, N))
        ))
  ; true
  ).

sampler:test_stats_unique_pkg_count(Bucket, Count) :-
  findall(C-N, sampler:test_stats_pkg(Bucket, C, N), Pairs0),
  sort(Pairs0, Pairs),
  length(Pairs, Count).

sampler:test_stats_set_current_entry(RepositoryEntry) :-
  nb_setval(test_stats_current_entry, RepositoryEntry).

sampler:test_stats_clear_current_entry :-
  ( nb_current(test_stats_current_entry, _) ->
      nb_delete(test_stats_current_entry)
  ; true
  ).

sampler:test_stats_inc(Key) :-
  with_mutex(test_stats,
    ( ( retract(sampler:test_stats_stat(Key, N0)) -> true ; N0 = 0 ),
      N is N0 + 1,
      assertz(sampler:test_stats_stat(Key, N))
    )).

sampler:test_stats_inc_type(Type, Metric, Delta) :-
  with_mutex(test_stats,
    ( ( retract(sampler:test_stats_type(Type, Metric, N0)) -> true ; N0 = 0 ),
      N is N0 + Delta,
      assertz(sampler:test_stats_type(Type, Metric, N))
    )).

sampler:test_stats_inc_cycle_mention(Action, RepoEntry) :-
  with_mutex(test_stats,
    ( ( retract(sampler:test_stats_cycle_mention(Action, RepoEntry, N0)) -> true ; N0 = 0 ),
      N is N0 + 1,
      assertz(sampler:test_stats_cycle_mention(Action, RepoEntry, N))
    )).

sampler:test_stats_record_time(RepoEntry, TimeMs) :-
  integer(TimeMs),
  TimeMs >= 0,
  ( RepoEntry = Repo0://Entry0,
    cache:ordered_entry(Repo0, Entry0, C, N, _)
  -> true
  ; C = _, N = _
  ),
  with_mutex(test_stats,
    ( ( retract(sampler:test_stats_entry_time(RepoEntry, OldMs)) ->
          EntryMaxMs is max(OldMs, TimeMs)
      ;   EntryMaxMs = TimeMs
      ),
      assertz(sampler:test_stats_entry_time(RepoEntry, EntryMaxMs)),
      ( nonvar(C), nonvar(N) ->
          ( retract(sampler:test_stats_pkg_time(C, N, Sum0, Max0, Cnt0)) ->
              true
          ;   Sum0 = 0, Max0 = 0, Cnt0 = 0
          ),
          Sum is Sum0 + TimeMs,
          Max is max(Max0, TimeMs),
          Cnt is Cnt0 + 1,
          assertz(sampler:test_stats_pkg_time(C, N, Sum, Max, Cnt))
      ; true
      )
    )).

sampler:test_stats_record_costs(RepoEntry, TimeMs, Inferences, RuleCalls) :-
  sampler:test_stats_record_time(RepoEntry, TimeMs),
  integer(Inferences),
  Inferences >= 0,
  integer(RuleCalls),
  RuleCalls >= 0,
  ( RepoEntry = Repo0://Entry0,
    cache:ordered_entry(Repo0, Entry0, C, N, _)
  -> true
  ; C = _, N = _
  ),
  with_mutex(test_stats,
    ( ( retract(sampler:test_stats_entry_cost(RepoEntry, OldMs, OldInf, OldRule)) ->
          KeepMs is max(OldMs, TimeMs),
          KeepInf is max(OldInf, Inferences),
          KeepRule is max(OldRule, RuleCalls)
      ;   KeepMs = TimeMs,
          KeepInf = Inferences,
          KeepRule = RuleCalls
      ),
      assertz(sampler:test_stats_entry_cost(RepoEntry, KeepMs, KeepInf, KeepRule)),
      ( nonvar(C), nonvar(N) ->
          ( retract(sampler:test_stats_pkg_cost(C, N, Ms0, Inf0, Rule0, Cnt0)) ->
              true
          ;   Ms0 = 0, Inf0 = 0, Rule0 = 0, Cnt0 = 0
          ),
          Ms1 is Ms0 + TimeMs,
          Inf1 is Inf0 + Inferences,
          Rule1 is Rule0 + RuleCalls,
          Cnt1 is Cnt0 + 1,
          assertz(sampler:test_stats_pkg_cost(C, N, Ms1, Inf1, Rule1, Cnt1))
      ; true
      )
    )).

sampler:test_stats_record_context_costs(RepoEntry, UnionCalls, UnionCost, MaxCtxLen) :-
  sampler:test_stats_record_context_costs(RepoEntry, UnionCalls, UnionCost, MaxCtxLen, 0).

sampler:test_stats_record_context_costs(RepoEntry, UnionCalls, UnionCost, MaxCtxLen, UnionMsEst) :-
  integer(UnionCalls),
  UnionCalls >= 0,
  integer(UnionCost),
  UnionCost >= 0,
  integer(MaxCtxLen),
  MaxCtxLen >= 0,
  integer(UnionMsEst),
  UnionMsEst >= 0,
  ( RepoEntry = Repo0://Entry0,
    cache:ordered_entry(Repo0, Entry0, C, N, _)
  -> true
  ; C = _, N = _
  ),
  with_mutex(test_stats,
    ( ( retract(sampler:test_stats_entry_ctx(RepoEntry, OldCalls, OldCost, OldMax, OldMs)) ->
          Calls1 is max(OldCalls, UnionCalls),
          Cost1 is max(OldCost, UnionCost),
          Max1 is max(OldMax, MaxCtxLen),
          Ms1 is max(OldMs, UnionMsEst)
      ;   Calls1 = UnionCalls,
          Cost1 = UnionCost,
          Max1 = MaxCtxLen,
          Ms1 = UnionMsEst
      ),
      assertz(sampler:test_stats_entry_ctx(RepoEntry, Calls1, Cost1, Max1, Ms1)),
      ( nonvar(C), nonvar(N) ->
          ( retract(sampler:test_stats_pkg_ctx(C, N, Sum0, Max0, SumMs0, Cnt0)) -> true
          ; Sum0 = 0, Max0 = 0, SumMs0 = 0, Cnt0 = 0
          ),
          Sum1 is Sum0 + UnionCost,
          Max2 is max(Max0, MaxCtxLen),
          SumMs1 is SumMs0 + UnionMsEst,
          Cnt1 is Cnt0 + 1,
          assertz(sampler:test_stats_pkg_ctx(C, N, Sum1, Max2, SumMs1, Cnt1))
      ; true
      )
    )).

sampler:test_stats_record_ctx_len_distribution(HistPairs, SumMul, SumAdd, Samples) :-
  with_mutex(test_stats,
    ( forall(member(Len-Cnt, HistPairs),
             ( integer(Len), Len >= 0,
               integer(Cnt), Cnt >= 0,
               ( retract(sampler:test_stats_ctx_len_bin(Len, Old)) ->
                   New is Old + Cnt
               ; New is Cnt
               ),
               assertz(sampler:test_stats_ctx_len_bin(Len, New))
             )),
      ( integer(SumMul), SumMul >= 0,
        integer(SumAdd), SumAdd >= 0,
        integer(Samples), Samples >= 0 ->
          ( retract(sampler:test_stats_ctx_cost_model(M0, A0, S0)) ->
              true
          ; M0 = 0, A0 = 0, S0 = 0
          ),
          M1 is M0 + SumMul,
          A1 is A0 + SumAdd,
          S1 is S0 + Samples,
          assertz(sampler:test_stats_ctx_cost_model(M1, A1, S1))
      ; true
      )
    )).

sampler:test_stats_inc_type_entry_mention(Type, RepoEntry) :-
  with_mutex(test_stats,
    ( ( retract(sampler:test_stats_type_entry_mention(Type, RepoEntry, N0)) -> true ; N0 = 0 ),
      N is N0 + 1,
      assertz(sampler:test_stats_type_entry_mention(Type, RepoEntry, N))
    )).

sampler:test_stats_note_cycle_for_current_entry :-
  ( nb_current(test_stats_current_entry, RepoEntry) ->
      with_mutex(test_stats,
        ( sampler:test_stats_entry_had_cycle(RepoEntry) ->
            true
        ; assertz(sampler:test_stats_entry_had_cycle(RepoEntry)),
          ( retract(sampler:test_stats_stat(entries_with_cycles, N0)) -> true ; N0 = 0 ),
          N is N0 + 1,
          assertz(sampler:test_stats_stat(entries_with_cycles, N))
        ))
      ,
      ( RepoEntry = Repo://Entry -> sampler:test_stats_add_pkg(with_cycles, Repo, Entry) ; true )
  ; true
  ).

sampler:test_stats_inc_other_head(Content) :-
  ( Content = domain(X)      -> C1 = X
  ; Content = cycle_break(X) -> C1 = X
  ; C1 = Content
  ),
  assumption:assumption_head_key(C1, Key),
  with_mutex(test_stats,
    ( ( retract(sampler:test_stats_other_head(Key, N0)) -> true ; N0 = 0 ),
      N is N0 + 1,
      assertz(sampler:test_stats_other_head(Key, N))
    )).

sampler:test_stats_record_blocker_assumption(Content) :-
  ( Content = domain(X)      -> Content1 = X
  ; Content = cycle_break(X) -> Content1 = X
  ; Content1 = Content
  ),
  assumption:collect_ctx_tags(Content1, Tags),
  assumption:unwrap_ctx_wrappers(Content1, Core),
  ( Core = blocker(Strength, Phase, C, N, _O2, _V2, _SlotReq2) ->
      ( sampler:test_stats_record_blocker_breakdown(Strength, Phase, C, N),
        ( memberchk(assumption_reason(Reason), Tags) -> true ; Reason = unknown ),
        sampler:test_stats_inc_blocker_reason(Reason, Phase)
      )
  ; with_mutex(test_stats,
      ( sampler:test_stats_blocker_example(_) ->
          true
      ; assertz(sampler:test_stats_blocker_example(Content1))
      ))
  ).

sampler:test_stats_record_blocker_breakdown(Strength, Phase, C, N) :-
  with_mutex(test_stats,
    ( ( retract(sampler:test_stats_blocker_sp(Strength, Phase, Nsp0)) -> true ; Nsp0 = 0 ),
      Nsp is Nsp0 + 1,
      assertz(sampler:test_stats_blocker_sp(Strength, Phase, Nsp)),
      ( retract(sampler:test_stats_blocker_cn(C, N, Ncn0)) -> true ; Ncn0 = 0 ),
      Ncn is Ncn0 + 1,
      assertz(sampler:test_stats_blocker_cn(C, N, Ncn))
    )).

sampler:test_stats_inc_blocker_reason(Reason, Phase) :-
  with_mutex(test_stats,
    ( ( retract(sampler:test_stats_blocker_reason(Reason, N0)) -> true ; N0 = 0 ),
      N is N0 + 1,
      assertz(sampler:test_stats_blocker_reason(Reason, N)),
      ( retract(sampler:test_stats_blocker_rp(Reason, Phase, M0)) -> true ; M0 = 0 ),
      M is M0 + 1,
      assertz(sampler:test_stats_blocker_rp(Reason, Phase, M))
    )).

sampler:test_stats_record_entry(RepositoryEntry, _ModelAVL, ProofAVL, TriggersAVL, DoCycles) :-
  sampler:test_stats_inc(processed),
  ( RepositoryEntry = Repo://Entry -> sampler:test_stats_add_pkg(processed, Repo, Entry) ; true ),
  findall(ContentN,
          ( assoc:gen_assoc(ProofKey, ProofAVL, _),
            explainer:assumption_content_from_proof_key(ProofKey, Content0),
            explainer:assumption_normalize(Content0, ContentN)
          ),
          Contents0),
  ( Contents0 == [] ->
      true
  ; sampler:test_stats_inc(entries_with_assumptions),
    ( RepositoryEntry = Repo://Entry -> sampler:test_stats_add_pkg(with_assumptions, Repo, Entry) ; true ),
    ( once((member(C0, Contents0), assumption:assumption_is_package_level(C0))) ->
        sampler:test_stats_inc(entries_with_package_assumptions),
        ( RepositoryEntry = Repo://Entry -> sampler:test_stats_add_pkg(with_package_assumptions, Repo, Entry) ; true )
    ; true
    ),
    findall(Type,
            ( member(Content, Contents0),
              assumption:assumption_type(Content, Type),
              sampler:test_stats_inc_type(Type, occurrences, 1),
              sampler:test_stats_inc_type_entry_mention(Type, RepositoryEntry),
              ( Type == blocker_assumption ->
                  sampler:test_stats_record_blocker_assumption(Content)
              ; true
              )
            ),
            TypesAll),
    forall((member(Content, Contents0), assumption:assumption_type(Content, other)),
           sampler:test_stats_inc_other_head(Content)),
    sort(TypesAll, TypesUnique),
    forall(member(T, TypesUnique),
           sampler:test_stats_inc_type(T, entries, 1))
  ),
  ( DoCycles == true ->
      sampler:test_stats_set_current_entry(RepositoryEntry),
      forall(member(Content, Contents0),
             ( assumption:cycle_for_assumption(Content, TriggersAVL, CyclePath0, CyclePath) ->
                 sampler:test_stats_record_cycle(CyclePath0, CyclePath)
             ; true
             )),
      sampler:test_stats_clear_current_entry
  ; true
  ).

sampler:test_stats_record_cycle(_CyclePath0, CyclePath) :-
  sampler:test_stats_inc(cycles_found),
  sampler:test_stats_note_cycle_for_current_entry,
  findall(Action-RepoEntry,
          ( member(Node, CyclePath),
            cycle:cycle_pkg_repo_entry(Node, RepoEntry, Action),
            ( Action == run ; Action == install )
          ),
          Mentions0),
  sort(Mentions0, Mentions),
  forall(member(Action-RepoEntry, Mentions),
         sampler:test_stats_inc_cycle_mention(Action, RepoEntry)).

sampler:test_stats_value(Key, Value) :-
  ( sampler:test_stats_stat(Key, Value) -> true ; Value = 0 ).

%! sampler:test_stats_stage_at_least(+MinStage) is semidet
%
% Succeeds when the current test_stats stage is at least MinStage.
% Stage order: prover < planner < scheduler < printer.

sampler:test_stats_stage_at_least(MinStage) :-
  ( sampler:test_stats_stat(stage, Stage) -> true ; Stage = printer ),
  sampler:test_stats_stage_rank(MinStage, MinRank),
  sampler:test_stats_stage_rank(Stage, Rank),
  Rank >= MinRank.

sampler:test_stats_stage_rank(prover, 1).
sampler:test_stats_stage_rank(planner, 2).
sampler:test_stats_stage_rank(scheduler, 3).
sampler:test_stats_stage_rank(printer, 4).

sampler:test_stats_percent(_, 0, 0.0) :- !.
sampler:test_stats_percent(Part, Total, Percent) :-
  Percent is (100.0 * Part) / Total.


% =============================================================================
%  Prove/plan/schedule performance counters
% =============================================================================

sampler:perf_walltime(T) :-
  statistics(walltime, [T, _]).

sampler:perf_record(T0, T1, T2, T3) :-
  ProveMs is T1 - T0,
  PlanMs is T2 - T1,
  SchedMs is T3 - T2,
  sampler:prove_plan_perf_add(ProveMs, PlanMs, SchedMs).

sampler:prove_plan_perf_reset :-
  flag(pp_perf_entries, _OldE, 0),
  flag(pp_perf_prove_ms, _OldP, 0),
  flag(pp_perf_plan_ms, _OldPl, 0),
  flag(pp_perf_sched_ms, _OldS, 0),
  !.

sampler:prove_plan_perf_add(ProveMs, PlanMs, SchedMs) :-
  flag(pp_perf_entries, E0, E0+1),
  flag(pp_perf_prove_ms, P0, P0+ProveMs),
  flag(pp_perf_plan_ms, Pl0, Pl0+PlanMs),
  flag(pp_perf_sched_ms, S0, S0+SchedMs),
  !.

sampler:prove_plan_perf_report :-
  flag(pp_perf_entries, E, E),
  ( E =:= 0 ->
      true
  ; flag(pp_perf_prove_ms, P, P),
    flag(pp_perf_plan_ms, Pl, Pl),
    flag(pp_perf_sched_ms, S, S),
    AvgP is P / E,
    AvgPl is Pl / E,
    AvgS is S / E,
    message:scroll_notice(['prove_plan perf: entries=',E,
                           ' prove_ms_sum=',P,' avg=',AvgP,
                           ' plan_ms_sum=',Pl,' avg=',AvgPl,
                           ' sched_ms_sum=',S,' avg=',AvgS])
  ),
  nl,
  !.


% =============================================================================
%  PDEPEND perf counters
% =============================================================================

sampler:pdepend_perf_reset :-
  flag(pdepend_perf_entries, _OldE, 0),
  flag(pdepend_perf_pass1_ms, _OldP1, 0),
  flag(pdepend_perf_extract_ms, _OldEx, 0),
  flag(pdepend_perf_pass2_ms, _OldP2, 0),
  flag(pdepend_perf_second_pass_entries, _OldS, 0),
  flag(pdepend_perf_new_goals, _OldNg, 0),
  !.

sampler:pdepend_perf_add(Pass1Ms, ExtractMs, Pass2Ms, DidSecondPass, NewGoalsCount) :-
  flag(pdepend_perf_entries, E0, E0+1),
  flag(pdepend_perf_pass1_ms, P10, P10+Pass1Ms),
  flag(pdepend_perf_extract_ms, Ex0, Ex0+ExtractMs),
  flag(pdepend_perf_pass2_ms, P20, P20+Pass2Ms),
  flag(pdepend_perf_second_pass_entries, S0, S0+DidSecondPass),
  flag(pdepend_perf_new_goals, Ng0, Ng0+NewGoalsCount),
  !.

sampler:pdepend_perf_report :-
  flag(pdepend_perf_entries, E, E),
  ( E =:= 0 ->
      true
  ; flag(pdepend_perf_pass1_ms, P1, P1),
    flag(pdepend_perf_extract_ms, Ex, Ex),
    flag(pdepend_perf_pass2_ms, P2, P2),
    flag(pdepend_perf_second_pass_entries, S, S),
    flag(pdepend_perf_new_goals, Ng, Ng),
    AvgP1 is P1 / E,
    AvgEx is Ex / E,
    AvgP2 is P2 / E,
    AvgNg is Ng / E,
    message:scroll_notice(['PDEPEND perf: entries=',E,
                           ' pass1_ms_sum=',P1,' avg=',AvgP1,
                           ' extract_ms_sum=',Ex,' avg=',AvgEx,
                           ' pass2_ms_sum=',P2,' avg=',AvgP2,
                           ' pass2_entries=',S,
                           ' new_goals_sum=',Ng,' avg=',AvgNg])
  ),
  !.


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