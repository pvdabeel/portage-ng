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

  - Domain hook sampling: measures cost of domain literal hook processing
  - ?{Context} list union sampling: measures cost of context list operations
  - Hook performance counters: count-based metrics for domain literal hook
    (done-hits, hook-fired, extra/fresh literals)
  - Timeout diagnostics: best-effort trace capture and literal simplification
    for diagnosing prover timeouts and failures
  - Runtime callsite stats: sampled stack-walk tracking of residual
    query:search/2 calls that survive goal-expansion

Key interfaces:

  - sampler:fact/1   — unified dynamic fact store (compound-term dispatch)
  - sampler:record/1 — unified recording (compound-term dispatch)
  - sampler:inc/1    — unified counting (compound-term dispatch)
*/

:- module(sampler, []).

% =============================================================================
%  SAMPLER declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Compile-time instrumentation gating
% -----------------------------------------------------------------------------
%
% Unless the application is started with -Dinstrumentation=true (e.g. via
% --profile), all hot-path instrumentation calls are compiled to `true`
% by goal_expansion, leaving zero overhead in the prover loop.

:- multifile user:goal_expansion/2.

user:goal_expansion(rule_call, true) :-
  \+ current_prolog_flag(instrumentation, true).

user:goal_expansion(hook_done_hit, true) :-
  \+ current_prolog_flag(instrumentation, true).

user:goal_expansion(hook_fired(_), true) :-
  \+ current_prolog_flag(instrumentation, true).

user:goal_expansion(hook_fresh(_), true) :-
  \+ current_prolog_flag(instrumentation, true).

user:goal_expansion(hook_counter_reset, true) :-
  \+ current_prolog_flag(instrumentation, true).

user:goal_expansion(hook_counter_report, true) :-
  \+ current_prolog_flag(instrumentation, true).

user:goal_expansion(hook_perf_reset, true) :-
  \+ current_prolog_flag(instrumentation, true).

user:goal_expansion(hook_perf_report, true) :-
  \+ current_prolog_flag(instrumentation, true).

user:goal_expansion(maybe_timeout_trace(_), true) :-
  \+ current_prolog_flag(instrumentation, true).

user:goal_expansion(phase_walltime(_), true) :-
  \+ current_prolog_flag(instrumentation, true).

user:goal_expansion(phase_record(_, _, _, _), true) :-
  \+ current_prolog_flag(instrumentation, true).

user:goal_expansion(phase_perf_reset, true) :-
  \+ current_prolog_flag(instrumentation, true).

user:goal_expansion(phase_perf_report, true) :-
  \+ current_prolog_flag(instrumentation, true).


% -----------------------------------------------------------------------------
%  Domain hook instrumentation
% -----------------------------------------------------------------------------
%
% Measures cost of domain literal hook processing (PDEPEND hooks). Includes
% periodic sampling with rate control and count-based counters.

%! sampler:hook_perf_reset is det.
%
% Zero all hook sampling counters (calls, has/no extra, sample count,
% accumulated sample time).

sampler:hook_perf_reset :-
  flag(po_calls, _, 0),
  flag(po_has_extra, _, 0),
  flag(po_no_extra, _, 0),
  flag(po_sample_n, _, 0),
  flag(po_sample_ms_sum, _, 0),
  !.


%! sampler:hook_perf_report is det.
%
% Print a one-line summary of hook sampling statistics.

sampler:hook_perf_report :-
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
  message:scroll_notice(['hook perf: calls=',Calls,
                         ' has_extra=',HasP,
                         ' no_extra=',NoP,
                         ' sample_n=',SN,
                         ' sample_ms_sum=',SMs,
                         ' avg_ms=',AvgMs,
                         ' est_total_ms=',EstTotalMs]),
  nl,
  !.


%! sampler:hook_sample_rate(-N) is det.
%
% The sampling rate: measure timing on every Nth call. Set to 1 for
% full profiling (expensive) or a large value for low-overhead sampling.

sampler:hook_sample_rate(1000).


%! sampler:hook_maybe_sample(:Goal) is semidet.
%
% Execute Goal, optionally wrapping it in wall-clock timing if this call
% hits the 1-in-N sampling window. Increments the call counter on every
% invocation; only the sampled calls pay the timing overhead.

sampler:hook_maybe_sample(Goal) :-
  flag(po_calls, C0, C0+1),
  sampler:hook_sample_rate(N),
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


%! sampler:hook_counter_reset is det.
%
% Reset all hook performance counters.

sampler:hook_counter_reset :-
  flag(obligation_done_hits, _, 0),
  flag(obligation_fired, _, 0),
  flag(obligation_extra_lits, _, 0),
  flag(obligation_fresh_lits, _, 0),
  sampler:hook_perf_reset,
  !.


%! sampler:hook_done_hit is det.
%
% Increment the "hook already done" hit counter.

sampler:hook_done_hit :-
  flag(obligation_done_hits, X, X+1),
  !.


%! sampler:hook_fired(+ExtraLits) is det.
%
% Increment hook-fired counter and add |ExtraLits| to total extra literals.

sampler:hook_fired(ExtraLits) :-
  length(ExtraLits, ExtraN),
  flag(obligation_fired, X, X+1),
  flag(obligation_extra_lits, Y, Y+ExtraN),
  !.


%! sampler:hook_fresh(+FreshLits) is det.
%
% Add |FreshLits| to the count of fresh (not-yet-proven) literals enqueued.

sampler:hook_fresh(FreshLits) :-
  length(FreshLits, FreshN),
  flag(obligation_fresh_lits, X, X+FreshN),
  !.


%! sampler:hook_counter_report is det.
%
% Print accumulated hook performance counters.

sampler:hook_counter_report :-
  flag(obligation_fired, Fired, Fired),
  flag(obligation_extra_lits, Extra, Extra),
  flag(obligation_fresh_lits, Fresh, Fresh),
  flag(obligation_done_hits, DoneHits, DoneHits),
  nl,
  message:scroll_notice(['Hook perf: fired=',Fired,
                         ' extra_lits=',Extra,
                         ' fresh_lits=',Fresh,
                         ' done_hits=',DoneHits]),
  nl,
  sampler:hook_perf_report,
  !.


% -----------------------------------------------------------------------------
%  Phase performance counters
% -----------------------------------------------------------------------------
%
% Timing accumulators for prove / plan / schedule phases and PDEPEND processing.

%! sampler:phase_walltime(-T) is det.
%
% Capture the current wall-clock time in milliseconds.

sampler:phase_walltime(T) :-
  statistics(walltime, [T, _]).


%! sampler:phase_record(+T0, +T1, +T2, +T3) is det.
%
% Record phase timings from four wall-clock snapshots.

sampler:phase_record(T0, T1, T2, T3) :-
  ProveMs is T1 - T0,
  PlanMs is T2 - T1,
  SchedMs is T3 - T2,
  sampler:phase_perf_add(ProveMs, PlanMs, SchedMs).


%! sampler:phase_perf_reset is det.
%
% Reset prove/plan/schedule timing accumulators.

sampler:phase_perf_reset :-
  flag(pp_perf_entries, _, 0),
  flag(pp_perf_prove_ms, _, 0),
  flag(pp_perf_plan_ms, _, 0),
  flag(pp_perf_sched_ms, _, 0),
  !.


%! sampler:phase_perf_add(+ProveMs, +PlanMs, +SchedMs) is det.
%
% Accumulate phase timing for one entry.

sampler:phase_perf_add(ProveMs, PlanMs, SchedMs) :-
  flag(pp_perf_entries, E0, E0+1),
  flag(pp_perf_prove_ms, P0, P0+ProveMs),
  flag(pp_perf_plan_ms, Pl0, Pl0+PlanMs),
  flag(pp_perf_sched_ms, S0, S0+SchedMs),
  !.


%! sampler:phase_perf_report is det.
%
% Print phase timing summary.

sampler:phase_perf_report :-
  flag(pp_perf_entries, E, E),
  ( E =:= 0 ->
      true
  ; flag(pp_perf_prove_ms, P, P),
    flag(pp_perf_plan_ms, Pl, Pl),
    flag(pp_perf_sched_ms, S, S),
    AvgP is P / E,
    AvgPl is Pl / E,
    AvgS is S / E,
    message:scroll_notice(['phase perf: entries=',E,
                           ' prove_ms_sum=',P,' avg=',AvgP,
                           ' plan_ms_sum=',Pl,' avg=',AvgPl,
                           ' sched_ms_sum=',S,' avg=',AvgS])
  ),
  nl,
  !.


%! sampler:pdepend_perf_reset is det.
%
% Reset PDEPEND timing accumulators.

sampler:pdepend_perf_reset :-
  flag(pdepend_perf_entries, _, 0),
  flag(pdepend_perf_pass1_ms, _, 0),
  flag(pdepend_perf_extract_ms, _, 0),
  flag(pdepend_perf_pass2_ms, _, 0),
  flag(pdepend_perf_second_pass_entries, _, 0),
  flag(pdepend_perf_new_goals, _, 0),
  !.


%! sampler:pdepend_perf_add(+Pass1Ms, +ExtractMs, +Pass2Ms, +DidSecondPass, +NewGoalsCount) is det.
%
% Accumulate PDEPEND timing for one entry.

sampler:pdepend_perf_add(Pass1Ms, ExtractMs, Pass2Ms, DidSecondPass, NewGoalsCount) :-
  flag(pdepend_perf_entries, E0, E0+1),
  flag(pdepend_perf_pass1_ms, P10, P10+Pass1Ms),
  flag(pdepend_perf_extract_ms, Ex0, Ex0+ExtractMs),
  flag(pdepend_perf_pass2_ms, P20, P20+Pass2Ms),
  flag(pdepend_perf_second_pass_entries, S0, S0+DidSecondPass),
  flag(pdepend_perf_new_goals, Ng0, Ng0+NewGoalsCount),
  !.


%! sampler:pdepend_perf_report is det.
%
% Print PDEPEND timing summary.

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


% -----------------------------------------------------------------------------
%  Dynamic fact store
% -----------------------------------------------------------------------------
%
% All test-run statistics are stored as sampler:fact/1 with compound-term
% discrimination. SWI's first-argument indexing dispatches on the functor.
%
%   kv(Key, Value)                             — run metadata (label, stage)
%   type(Type, Metric, Count)                  — assumption type counts
%   cycle_mention(Action, Entry, Count)        — per-entry cycle mention counts
%   entry_had_cycle(Entry)                     — entry had at least one cycle
%   other_head(Key, Count)                     — non-blocker assumption heads
%   pkg(Bucket, C, N)                          — per-bucket package membership
%   type_entry_mention(Type, Entry, Count)     — type x entry mention counts
%   entry_time(Entry, Ms)                      — per-entry wall-clock time
%   pkg_time(C, N, Sum, Max, Cnt)              — per-package time aggregates
%   entry_cost(Entry, Ms, Inf, Rules)          — per-entry cost metrics
%   pkg_cost(C, N, SumMs, SumInf, SumR, Cnt)  — per-package cost aggregates
%   entry_ctx(Entry, Calls, Cost, MaxLen, Ms)  — per-entry ?{Context} metrics
%   pkg_ctx(C, N, SumCost, MaxLen, SumMs, Cnt) — per-package ?{Context} aggregates
%   ctx_len_bin(Len, Count)                    — context length histogram
%   ctx_cost_model(SumMul, SumAdd, Samples)    — quadratic cost model
%   failed_entry(Entry, Reason)                — failed entries
%   blocker_sp(Strength, Phase, Count)         — blocker strength x phase
%   blocker_cn(C, N, Count)                    — blocker category x name
%   blocker_example(Term)                      — first unparseable blocker
%   blocker_reason(Reason, Count)              — blocker reason counts
%   blocker_rp(Reason, Phase, Count)           — blocker reason x phase
%   emerge_time(Atom, Ms)                      — emerge timing reference

:- dynamic sampler:fact/1.


% -----------------------------------------------------------------------------
%  Statistics: rule call counter
% -----------------------------------------------------------------------------
%
% Counts rule/2 applications during test runs. Designed as a true no-op
% when test runs are not active (counter does not exist).

%! sampler:reset_counters is det.
%
% Initialize all global counters to zero (rule calls, context-union
% calls/cost/max-length, length histogram, cost breakdown, and timing
% sample accumulators).

sampler:reset_counters :-
  nb_setval(s_rule_calls, 0),
  nb_setval(s_ctx_calls, 0),
  nb_setval(s_ctx_cost, 0),
  nb_setval(s_ctx_max_len, 0),
  empty_assoc(EmptyHist),
  nb_setval(s_ctx_hist, EmptyHist),
  nb_setval(s_ctx_cost_mul, 0),
  nb_setval(s_ctx_cost_add, 0),
  nb_setval(s_ctx_time_rate, 64),
  nb_setval(s_ctx_time_samples, 0),
  nb_setval(s_ctx_time_ms, 0).


%! sampler:rule_call is det.
%
% Increment the rule-call counter if a test run is active.
% No-op when the counter does not exist.

sampler:rule_call :-
  ( nb_current(s_rule_calls, N0) ->
      N is N0 + 1,
      nb_setval(s_rule_calls, N)
  ; true
  ).


%! sampler:counters(-RuleCalls) is det.
%
% Retrieve the current rule-call count as `rule_calls(N)`.

sampler:counters(rule_calls(RuleCalls)) :-
  ( nb_current(s_rule_calls, RuleCalls) -> true ; RuleCalls = 0 ).


%! sampler:ctx_counters(-Calls, -CostEst, -MaxLen, -MsEst) is det.
%
% Retrieve context-union instrumentation counters. Values are returned as
% wrapped terms. Cost and time are extrapolated from sampled data to the
% full call count.

sampler:ctx_counters(ctx_union_calls(Calls),
                     ctx_union_cost(CostEst),
                     ctx_max_len(MaxLen),
                     ctx_union_ms_est(MsEst)) :-
  ( nb_current(s_ctx_calls, Calls) -> true ; Calls = 0 ),
  ( nb_current(s_ctx_cost, CostSampled) -> true ; CostSampled = 0 ),
  ( nb_current(s_ctx_max_len, MaxLen) -> true ; MaxLen = 0 ),
  ( nb_current(s_ctx_time_samples, Samples) -> true ; Samples = 0 ),
  ( nb_current(s_ctx_time_ms, MsSampled) -> true ; MsSampled = 0 ),
  ( Samples =:= 0 ->
      MsEst = 0,
      CostEst = 0
  ; MsEst0 is MsSampled * Calls / Samples,
    MsEst is round(MsEst0),
    CostEst0 is CostSampled * Calls / Samples,
    CostEst is round(CostEst0)
  ).


%! sampler:ctx_distribution(-HistPairs, -SumMul, -SumAdd, -Samples) is det.
%
% Retrieve context-union distribution data: output-length histogram,
% quadratic and linear cost sums, and total samples taken.

sampler:ctx_distribution(ctx_len_hist(HistPairs),
                         ctx_cost_mul(SumMul),
                         ctx_cost_add(SumAdd),
                         ctx_len_samples(Samples)) :-
  ( nb_current(s_ctx_hist, HistAssoc) -> true ; empty_assoc(HistAssoc) ),
  assoc_to_list(HistAssoc, HistPairs),
  ( nb_current(s_ctx_cost_mul, SumMul) -> true ; SumMul = 0 ),
  ( nb_current(s_ctx_cost_add, SumAdd) -> true ; SumAdd = 0 ),
  ( nb_current(s_ctx_time_samples, Samples) -> true ; Samples = 0 ).


% -----------------------------------------------------------------------------
%  Statistics: reset and helpers
% -----------------------------------------------------------------------------

%! sampler:reset(+Label, +ExpectedTotal) is det.
%
% Reset all dynamic facts and initialise counters for a new whole-repo
% test run identified by Label with ExpectedTotal entries.

sampler:reset(Label, ExpectedTotal) :-
  with_mutex(test_stats,
    ( retractall(sampler:fact(_)),
      assertz(sampler:fact(kv(label, Label))),
      ( Label == 'Proving'   -> Stage = prover
      ; Label == 'Planning'  -> Stage = planner
      ; Label == 'Scheduling'-> Stage = scheduler
      ; Label == 'Printing'  -> Stage = printer
      ; Label == 'Pipeline'  -> Stage = printer
      ; Stage = printer
      ),
      assertz(sampler:fact(kv(stage, Stage)))
    )),
  flag(expected_total, _, ExpectedTotal),
  flag(expected_unique_packages, _, 0),
  flag(processed, _, 0),
  flag(entries_failed, _, 0),
  flag(entries_failed_blocker, _, 0),
  flag(entries_failed_timeout, _, 0),
  flag(entries_failed_other, _, 0),
  flag(entries_with_assumptions, _, 0),
  flag(entries_with_package_assumptions, _, 0),
  flag(entries_with_cycles, _, 0),
  flag(cycles_found, _, 0).


%! sampler:set_expected_pkgs(+N) is det.
%
% Set the expected unique package count for progress reporting.

sampler:set_expected_pkgs(N) :-
  flag(expected_unique_packages, _, N).


%! sampler:add_pkg(+Bucket, +Repo, +Entry) is det.
%
% Register a package in the given bucket (processed, with_assumptions, etc.).

sampler:add_pkg(Bucket, Repo, Entry) :-
  ( cache:ordered_entry(Repo, Entry, C, N, _) ->
      with_mutex(test_stats,
        ( sampler:fact(pkg(Bucket, C, N)) -> true
        ; assertz(sampler:fact(pkg(Bucket, C, N)))
        ))
  ; true
  ).


%! sampler:pkg_count(+Bucket, -Count) is det.
%
% Count unique packages in a bucket.

sampler:pkg_count(Bucket, Count) :-
  findall(C-N, sampler:fact(pkg(Bucket, C, N)), Pairs0),
  sort(Pairs0, Pairs),
  length(Pairs, Count).


%! sampler:set_current_entry(+RepositoryEntry) is det.
%
% Set the current entry being processed (for cycle detection).

sampler:set_current_entry(RepositoryEntry) :-
  nb_setval(s_current_entry, RepositoryEntry).


%! sampler:clear_current_entry is det.
%
% Clear the current entry marker.

sampler:clear_current_entry :-
  ( nb_current(s_current_entry, _) ->
      nb_delete(s_current_entry)
  ; true
  ).


%! sampler:note_cycle_for_entry is det.
%
% Mark the current entry as having had a cycle.

sampler:note_cycle_for_entry :-
  ( nb_current(s_current_entry, RepoEntry) ->
      with_mutex(test_stats,
        ( sampler:fact(entry_had_cycle(RepoEntry)) ->
            true
        ; assertz(sampler:fact(entry_had_cycle(RepoEntry))),
          flag(entries_with_cycles, Nc, Nc+1)
        ))
      ,
      ( RepoEntry = Repo://Entry -> sampler:add_pkg(with_cycles, Repo, Entry) ; true )
  ; true
  ).


%! sampler:value(+Key, -Value) is det.
%
% Retrieve a statistics value by key (from kv facts or global flags).

sampler:value(Key, Value) :-
  ( sampler:fact(kv(Key, Value)) -> true
  ; flag(Key, Value, Value)
  ).


%! sampler:stage_at_least(+MinStage) is semidet.
%
% Succeeds when the current stage is at least MinStage.
% Stage order: prover < planner < scheduler < printer.

sampler:stage_at_least(MinStage) :-
  ( sampler:fact(kv(stage, Stage)) -> true ; Stage = printer ),
  sampler:stage_rank(MinStage, MinRank),
  sampler:stage_rank(Stage, Rank),
  Rank >= MinRank.

sampler:stage_rank(prover, 1).
sampler:stage_rank(planner, 2).
sampler:stage_rank(scheduler, 3).
sampler:stage_rank(printer, 4).


%! sampler:percent(+Part, +Total, -Percent) is det.
%
% Compute percentage, returning 0.0 when Total is zero.

sampler:percent(_, 0, 0.0) :- !.
sampler:percent(Part, Total, Percent) :-
  Percent is (100.0 * Part) / Total.


% -----------------------------------------------------------------------------
%  Statistics: unified inc/1
% -----------------------------------------------------------------------------
%
% All counting operations dispatch on the compound term's functor.
% Atom keys use simple flag increments; compound keys use retract/assert.

%! sampler:inc(+What) is det.
%
% Increment a counter. Atom keys increment global flags; compound keys
% update dynamic facts with retract/assert under mutex.

sampler:inc(type(Type, Metric, Delta)) :-
  with_mutex(test_stats,
    ( ( retract(sampler:fact(type(Type, Metric, N0))) -> true ; N0 = 0 ),
      N is N0 + Delta,
      assertz(sampler:fact(type(Type, Metric, N)))
    )).
sampler:inc(cycle_mention(Action, RepoEntry)) :-
  with_mutex(test_stats,
    ( ( retract(sampler:fact(cycle_mention(Action, RepoEntry, N0))) -> true ; N0 = 0 ),
      N is N0 + 1,
      assertz(sampler:fact(cycle_mention(Action, RepoEntry, N)))
    )).
sampler:inc(type_entry_mention(Type, RepoEntry)) :-
  with_mutex(test_stats,
    ( ( retract(sampler:fact(type_entry_mention(Type, RepoEntry, N0))) -> true ; N0 = 0 ),
      N is N0 + 1,
      assertz(sampler:fact(type_entry_mention(Type, RepoEntry, N)))
    )).
sampler:inc(other_head(Content)) :-
  ( Content = domain(X)      -> C1 = X
  ; Content = cycle_break(X) -> C1 = X
  ; C1 = Content
  ),
  assumption:assumption_head_key(C1, Key),
  with_mutex(test_stats,
    ( ( retract(sampler:fact(other_head(Key, N0))) -> true ; N0 = 0 ),
      N is N0 + 1,
      assertz(sampler:fact(other_head(Key, N)))
    )).
sampler:inc(blocker_reason(Reason, Phase)) :-
  with_mutex(test_stats,
    ( ( retract(sampler:fact(blocker_reason(Reason, N0))) -> true ; N0 = 0 ),
      N is N0 + 1,
      assertz(sampler:fact(blocker_reason(Reason, N))),
      ( retract(sampler:fact(blocker_rp(Reason, Phase, M0))) -> true ; M0 = 0 ),
      M is M0 + 1,
      assertz(sampler:fact(blocker_rp(Reason, Phase, M)))
    )).
sampler:inc(Key) :-
  flag(Key, N, N + 1).


% -----------------------------------------------------------------------------
%  Statistics: unified record/1
% -----------------------------------------------------------------------------
%
% All recording operations dispatch on the compound term's functor.
% SWI's first-argument indexing makes this zero-overhead.

%! sampler:record(+What) is det.
%
% Record a statistic. Compound-term dispatch on the functor determines
% what is being recorded.

sampler:record(failed(Reason)) :-
  sampler:inc(entries_failed),
  ( Reason == blocker ->
      sampler:inc(entries_failed_blocker)
  ; Reason == timeout ->
      sampler:inc(entries_failed_timeout)
  ; sampler:inc(entries_failed_other)
  ).

sampler:record(failed_entry(RepoEntry, Reason)) :-
  with_mutex(test_stats,
    assertz(sampler:fact(failed_entry(RepoEntry, Reason)))).

sampler:record(time(RepoEntry, TimeMs)) :-
  integer(TimeMs),
  TimeMs >= 0,
  ( RepoEntry = Repo0://Entry0,
    cache:ordered_entry(Repo0, Entry0, C, N, _)
  -> true
  ; C = _, N = _
  ),
  with_mutex(test_stats,
    ( ( retract(sampler:fact(entry_time(RepoEntry, OldMs))) ->
          EntryMaxMs is max(OldMs, TimeMs)
      ;   EntryMaxMs = TimeMs
      ),
      assertz(sampler:fact(entry_time(RepoEntry, EntryMaxMs))),
      ( nonvar(C), nonvar(N) ->
          ( retract(sampler:fact(pkg_time(C, N, Sum0, Max0, Cnt0))) ->
              true
          ;   Sum0 = 0, Max0 = 0, Cnt0 = 0
          ),
          Sum is Sum0 + TimeMs,
          Max is max(Max0, TimeMs),
          Cnt is Cnt0 + 1,
          assertz(sampler:fact(pkg_time(C, N, Sum, Max, Cnt)))
      ; true
      )
    )).

sampler:record(costs(RepoEntry, TimeMs, Inferences, RuleCalls)) :-
  sampler:record(time(RepoEntry, TimeMs)),
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
    ( ( retract(sampler:fact(entry_cost(RepoEntry, OldMs, OldInf, OldRule))) ->
          KeepMs is max(OldMs, TimeMs),
          KeepInf is max(OldInf, Inferences),
          KeepRule is max(OldRule, RuleCalls)
      ;   KeepMs = TimeMs,
          KeepInf = Inferences,
          KeepRule = RuleCalls
      ),
      assertz(sampler:fact(entry_cost(RepoEntry, KeepMs, KeepInf, KeepRule))),
      ( nonvar(C), nonvar(N) ->
          ( retract(sampler:fact(pkg_cost(C, N, Ms0, Inf0, Rule0, Cnt0))) ->
              true
          ;   Ms0 = 0, Inf0 = 0, Rule0 = 0, Cnt0 = 0
          ),
          Ms1 is Ms0 + TimeMs,
          Inf1 is Inf0 + Inferences,
          Rule1 is Rule0 + RuleCalls,
          Cnt1 is Cnt0 + 1,
          assertz(sampler:fact(pkg_cost(C, N, Ms1, Inf1, Rule1, Cnt1)))
      ; true
      )
    )).

sampler:record(ctx_costs(RepoEntry, UnionCalls, UnionCost, MaxCtxLen)) :-
  sampler:record(ctx_costs(RepoEntry, UnionCalls, UnionCost, MaxCtxLen, 0)).

sampler:record(ctx_costs(RepoEntry, UnionCalls, UnionCost, MaxCtxLen, UnionMsEst)) :-
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
    ( ( retract(sampler:fact(entry_ctx(RepoEntry, OldCalls, OldCost, OldMax, OldMs))) ->
          Calls1 is max(OldCalls, UnionCalls),
          Cost1 is max(OldCost, UnionCost),
          Max1 is max(OldMax, MaxCtxLen),
          Ms1 is max(OldMs, UnionMsEst)
      ;   Calls1 = UnionCalls,
          Cost1 = UnionCost,
          Max1 = MaxCtxLen,
          Ms1 = UnionMsEst
      ),
      assertz(sampler:fact(entry_ctx(RepoEntry, Calls1, Cost1, Max1, Ms1))),
      ( nonvar(C), nonvar(N) ->
          ( retract(sampler:fact(pkg_ctx(C, N, Sum0, Max0, SumMs0, Cnt0))) -> true
          ; Sum0 = 0, Max0 = 0, SumMs0 = 0, Cnt0 = 0
          ),
          Sum1 is Sum0 + UnionCost,
          Max2 is max(Max0, MaxCtxLen),
          SumMs1 is SumMs0 + UnionMsEst,
          Cnt1 is Cnt0 + 1,
          assertz(sampler:fact(pkg_ctx(C, N, Sum1, Max2, SumMs1, Cnt1)))
      ; true
      )
    )).

sampler:record(ctx_dist(HistPairs, SumMul, SumAdd, Samples)) :-
  with_mutex(test_stats,
    ( forall(member(Len-Cnt, HistPairs),
             ( integer(Len), Len >= 0,
               integer(Cnt), Cnt >= 0,
               ( retract(sampler:fact(ctx_len_bin(Len, Old))) ->
                   New is Old + Cnt
               ; New is Cnt
               ),
               assertz(sampler:fact(ctx_len_bin(Len, New)))
             )),
      ( integer(SumMul), SumMul >= 0,
        integer(SumAdd), SumAdd >= 0,
        integer(Samples), Samples >= 0 ->
          ( retract(sampler:fact(ctx_cost_model(M0, A0, S0))) ->
              true
          ; M0 = 0, A0 = 0, S0 = 0
          ),
          M1 is M0 + SumMul,
          A1 is A0 + SumAdd,
          S1 is S0 + Samples,
          assertz(sampler:fact(ctx_cost_model(M1, A1, S1)))
      ; true
      )
    )).

sampler:record(blocker(Content)) :-
  ( Content = domain(X)      -> Content1 = X
  ; Content = cycle_break(X) -> Content1 = X
  ; Content1 = Content
  ),
  assumption:collect_ctx_tags(Content1, Tags),
  assumption:unwrap_ctx_wrappers(Content1, Core),
  ( Core = blocker(Strength, Phase, C, N, _O2, _V2, _SlotReq2) ->
      ( sampler:record(blocker_breakdown(Strength, Phase, C, N)),
        ( memberchk(assumption_reason(Reason), Tags) -> true ; Reason = unknown ),
        sampler:inc(blocker_reason(Reason, Phase))
      )
  ; with_mutex(test_stats,
      ( sampler:fact(blocker_example(_)) ->
          true
      ; assertz(sampler:fact(blocker_example(Content1)))
      ))
  ).

sampler:record(blocker_breakdown(Strength, Phase, C, N)) :-
  with_mutex(test_stats,
    ( ( retract(sampler:fact(blocker_sp(Strength, Phase, Nsp0))) -> true ; Nsp0 = 0 ),
      Nsp is Nsp0 + 1,
      assertz(sampler:fact(blocker_sp(Strength, Phase, Nsp))),
      ( retract(sampler:fact(blocker_cn(C, N, Ncn0))) -> true ; Ncn0 = 0 ),
      Ncn is Ncn0 + 1,
      assertz(sampler:fact(blocker_cn(C, N, Ncn)))
    )).

sampler:record(entry(RepositoryEntry, _ModelAVL, ProofAVL, TriggersAVL, DoCycles)) :-
  flag(processed, Np, Np+1),
  ( RepositoryEntry = Repo://Entry -> sampler:add_pkg(processed, Repo, Entry) ; true ),
  findall(ContentN,
          ( assoc:gen_assoc(ProofKey, ProofAVL, _),
            explainer:assumption_content_from_proof_key(ProofKey, Content0),
            explainer:assumption_normalize(Content0, ContentN)
          ),
          Contents0),
  ( Contents0 == [] ->
      true
  ; flag(entries_with_assumptions, Na, Na+1),
    ( RepositoryEntry = Repo://Entry -> sampler:add_pkg(with_assumptions, Repo, Entry) ; true ),
    ( once((member(C0, Contents0), assumption:assumption_is_package_level(C0))) ->
        flag(entries_with_package_assumptions, Npa, Npa+1),
        ( RepositoryEntry = Repo://Entry -> sampler:add_pkg(with_package_assumptions, Repo, Entry) ; true )
    ; true
    ),
    findall(Type-Content,
            ( member(Content, Contents0),
              assumption:assumption_type(Content, Type)
            ),
            TypeContentPairs),
    pairs_keys(TypeContentPairs, TypesAll),
    sort(TypesAll, TypesUnique),
    with_mutex(test_stats,
      ( forall(member(Type-_TC, TypeContentPairs),
               ( ( retract(sampler:fact(type(Type, occurrences, N0))) -> true ; N0 = 0 ),
                 N is N0 + 1,
                 assertz(sampler:fact(type(Type, occurrences, N))),
                 ( retract(sampler:fact(type_entry_mention(Type, RepositoryEntry, M0))) -> true ; M0 = 0 ),
                 M is M0 + 1,
                 assertz(sampler:fact(type_entry_mention(Type, RepositoryEntry, M)))
               )),
        forall(member(T, TypesUnique),
               ( ( retract(sampler:fact(type(T, entries, TE0))) -> true ; TE0 = 0 ),
                 TE is TE0 + 1,
                 assertz(sampler:fact(type(T, entries, TE)))
               )),
        forall(member(blocker_assumption-BC, TypeContentPairs),
               sampler:record(blocker(BC))),
        forall((member(other-OC, TypeContentPairs)),
               sampler:inc(other_head(OC)))
      ))
  ),
  ( DoCycles == true ->
      sampler:set_current_entry(RepositoryEntry),
      statistics(walltime, [CycleBudgetT0, _]),
      CycleBudgetEnd is CycleBudgetT0 + 2000,
      forall(member(Content, Contents0),
             ( statistics(walltime, [CycleTNow, _]),
               CycleTNow < CycleBudgetEnd
             -> ( catch(call_with_time_limit(0.5,
                    assumption:cycle_for_assumption(Content, TriggersAVL, CyclePath0, CyclePath)),
                    time_limit_exceeded, fail)
                -> sampler:record(cycle(CyclePath0, CyclePath))
                ; true
                )
             ; true
             )),
      sampler:clear_current_entry
  ; true
  ).

sampler:record(cycle(_CyclePath0, CyclePath)) :-
  sampler:inc(cycles_found),
  sampler:note_cycle_for_entry,
  findall(Action-RepoEntry,
          ( member(Node, CyclePath),
            cycle:cycle_pkg_repo_entry(Node, RepoEntry, Action),
            ( Action == run ; Action == install )
          ),
          Mentions0),
  sort(Mentions0, Mentions),
  forall(member(Action-RepoEntry, Mentions),
         sampler:inc(cycle_mention(Action, RepoEntry))).


% -----------------------------------------------------------------------------
%  ?{Context} list union
% -----------------------------------------------------------------------------
%
% Raw context union that strips self/1 provenance before merging, plus
% instrumented wrapper with periodic sampling of input/output lengths,
% timing, and cost metrics.

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


%! sampler:ctx_union(+OldCtx, +Ctx, -NewCtx) is det.
%
% Instrumented wrapper around ctx_union_raw/3. When a test run is active,
% periodically samples input/output list lengths, wall-clock timing, and
% cost metrics. Outside a test run, delegates directly to ctx_union_raw.

sampler:ctx_union(OldCtx, Ctx, NewCtx) :-
  ( nb_current(s_ctx_calls, C0) ->
      C is C0 + 1,
      nb_setval(s_ctx_calls, C),
      ( ( C =< 16 ; 0 is C /\ 63 ) ->
          ( is_list(OldCtx) -> length(OldCtx, L0) ; L0 = 0 ),
          ( is_list(Ctx)    -> length(Ctx, L1)    ; L1 = 0 ),
          statistics(walltime, [T0,_]),
          sampler:ctx_union_raw(OldCtx, Ctx, NewCtx),
          statistics(walltime, [T1,_]),
          Dt is T1 - T0,
          ( is_list(NewCtx) -> length(NewCtx, L2) ; L2 = 0 ),
          ( nb_current(s_ctx_time_samples, S0) -> true ; S0 = 0 ),
          ( nb_current(s_ctx_time_ms, M0s) -> true ; M0s = 0 ),
          S1 is S0 + 1, M1s is M0s + Dt,
          nb_setval(s_ctx_time_samples, S1),
          nb_setval(s_ctx_time_ms, M1s),
          ( nb_current(s_ctx_cost, K0) -> true ; K0 = 0 ),
          ( nb_current(s_ctx_max_len, M0) -> true ; M0 = 0 ),
          K is K0 + L0 + L1,
          M is max(M0, max(L0, max(L1, L2))),
          nb_setval(s_ctx_cost, K),
          nb_setval(s_ctx_max_len, M),
          sampler:ctx_union_sampled(L0, L1, L2)
      ;
          sampler:ctx_union_raw(OldCtx, Ctx, NewCtx)
      )
  ; sampler:ctx_union_raw(OldCtx, Ctx, NewCtx)
  ).


%! sampler:ctx_union_sampled(+L0, +L1, +L2) is det.
%
% Record a sampled context-union observation: update the output-length
% histogram and accumulate quadratic and linear cost components.

sampler:ctx_union_sampled(L0, L1, L2) :-
  ( nb_current(s_ctx_hist, Hist0) -> true ; empty_assoc(Hist0) ),
  ( get_assoc(L2, Hist0, C0) -> true ; C0 = 0 ),
  C1 is C0 + 1,
  put_assoc(L2, Hist0, C1, Hist1),
  nb_setval(s_ctx_hist, Hist1),
  ( nb_current(s_ctx_cost_mul, Mul0) -> true ; Mul0 = 0 ),
  ( nb_current(s_ctx_cost_add, Add0) -> true ; Add0 = 0 ),
  Mul1 is Mul0 + L0 * L1,
  Add1 is Add0 + L0 + L1,
  nb_setval(s_ctx_cost_mul, Mul1),
  nb_setval(s_ctx_cost_add, Add1).


% -----------------------------------------------------------------------------
%  Timeout trace: prover hot-path wrapper
% -----------------------------------------------------------------------------

%! sampler:maybe_timeout_trace(+Lit) is det.
%
% If a timeout trace is active, push a rule_call event.
% Compiled to `true` when instrumentation is off.

sampler:maybe_timeout_trace(Lit) :-
  ( nb_current(prover_timeout_trace, _) ->
      sampler:trace_simplify(Lit, Simple),
      sampler:timeout_trace_push(rule_call(Simple))
  ; true
  ).


% -----------------------------------------------------------------------------
%  Timeout diagnostics
% -----------------------------------------------------------------------------
%
% Used by tester on timeouts to capture a short "where were we" trace without
% enabling full tracing (which is too expensive at scale).

%! sampler:trace_simplify(+Item, -Simple) is det.
%
% Reduce a literal to a compact, comparable representation for timeout
% diagnostics. Strips large sub-terms so traces stay small and loops
% become visible.

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


%! sampler:timeout_trace_reset is det.
%
% Clear the timeout trace buffer.

sampler:timeout_trace_reset :-
  nb_setval(prover_timeout_trace, []).


%! sampler:timeout_trace_push(+Item0) is det.
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


%! sampler:timeout_trace_hook(+Target, +Proof, +Model, +Constraints) is det.
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


%! sampler:diagnose_timeout(+Target, +LimitSec, -Diagnosis) is det.
%
% Run a short best-effort diagnosis for Target with a time limit of
% LimitSec seconds. Always succeeds; returns a
% `diagnosis(DeltaInferences, RuleCalls, Trace)` term.

sampler:diagnose_timeout(Target, LimitSec, diagnosis(DeltaInferences, RuleCalls, Trace)) :-
  sampler:timeout_trace_reset,
  sampler:reset_counters,
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
  sampler:counters(rule_calls(RuleCalls)),
  ( nb_current(prover_timeout_trace, TraceRev) -> reverse(TraceRev, Trace) ; Trace = [] ).


%! sampler:diagnose_timeout_counts(+Target, +LimitSec, -Diagnosis, -TopCounts) is det.
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


% -----------------------------------------------------------------------------
%  Runtime callsite tracking
% -----------------------------------------------------------------------------
%
% Sampled stack-walk tracking of residual query:search/2 calls that survive
% goal-expansion. Helps answer: "who is still calling query:search/2?"

:- dynamic sampler:callsite_enabled/0.
:- dynamic sampler:callsite/4.
:- dynamic sampler:callsite_sig/5.
:- dynamic sampler:callsite_rate/1.

sampler:callsite_rate(4096).


%! sampler:enable_callsite_stats is det.
%
% Enable runtime callsite tracking for query:search/2.

sampler:enable_callsite_stats :-
  ( sampler:callsite_enabled -> true
  ; assertz(sampler:callsite_enabled)
  ).


%! sampler:disable_callsite_stats is det.
%
% Disable runtime callsite tracking for query:search/2.

sampler:disable_callsite_stats :-
  retractall(sampler:callsite_enabled).


%! sampler:reset_callsites is det.
%
% Clear all accumulated callsite data and reset the sampling counter.

sampler:reset_callsites :-
  retractall(sampler:callsite(_,_,_,_)),
  retractall(sampler:callsite_sig(_,_,_,_,_)),
  nb_setval(s_callsite_counter, 0).


%! sampler:set_callsite_rate(+Rate) is det.
%
% Set the sampling rate for callsite recording. Only every Nth call is
% recorded to keep overhead low on large runs.

sampler:set_callsite_rate(Rate) :-
  integer(Rate),
  Rate > 0,
  retractall(sampler:callsite_rate(_)),
  assertz(sampler:callsite_rate(Rate)).


%! sampler:report_callsites(+TopN) is det.
%
% Print the top N runtime callsites for query:search/2, sorted by count.

sampler:report_callsites(TopN) :-
  ( integer(TopN), TopN > 0 -> true ; TopN = 50 ),
  findall(Count-File-Line-PI,
          sampler:callsite(File, Line, PI, Count),
          Rows0),
  keysort(Rows0, RowsAsc),
  reverse(RowsAsc, Rows),
  format('~n>>> query:search/2 runtime callsites (Top ~d)~n~n', [TopN]),
  format('  ~` t~d~8|  ~` t~s~8|  ~` t~s~s~n', [8, 'Count', 'Line', 'Callsite']),
  format('  ~`-t~80|~n', []),
  sampler:print_callsite_rows(Rows, TopN, 1).


%! sampler:report_callsites_sig(+TopN) is det.
%
% Print the top N runtime callsites with per-signature breakdown.

sampler:report_callsites_sig(TopN) :-
  ( integer(TopN), TopN > 0 -> true ; TopN = 50 ),
  findall(Count-File-Line-PI-Sig,
          sampler:callsite_sig(File, Line, PI, Sig, Count),
          Rows0),
  keysort(Rows0, RowsAsc),
  reverse(RowsAsc, Rows),
  format('~n>>> query:search/2 runtime callsites (signature breakdown, Top ~d)~n~n', [TopN]),
  format('  ~` t~d~8|  ~` t~s~8|  ~` t~s~s~n', [8, 'Count', 'Line', 'Callsite / Signature']),
  format('  ~`-t~80|~n', []),
  sampler:print_callsite_sig_rows(Rows, TopN, 1).


%! sampler:print_callsite_sig_rows(+Rows, +TopN, +I) is det.
%
% Print helper for signature-breakdown callsite rows.

sampler:print_callsite_sig_rows([], _, _) :- !.
sampler:print_callsite_sig_rows(_, TopN, I) :- I > TopN, !.
sampler:print_callsite_sig_rows([Count-File-Line-PI-Sig|Rest], TopN, I) :-
  format('  ~` t~d~8|  ~w:~w~n      ~w~n      ~w~n', [Count, File, Line, PI, Sig]),
  I2 is I + 1,
  sampler:print_callsite_sig_rows(Rest, TopN, I2).


%! sampler:print_callsite_rows(+Rows, +TopN, +I) is det.
%
% Print helper for basic callsite rows.

sampler:print_callsite_rows([], _, _) :- !.
sampler:print_callsite_rows(_, TopN, I) :- I > TopN, !.
sampler:print_callsite_rows([Count-File-Line-PI|Rest], TopN, I) :-
  format('  ~` t~d~8|  ~w:~w~n      ~w~n', [Count, File, Line, PI]),
  I2 is I + 1,
  sampler:print_callsite_rows(Rest, TopN, I2).


%! sampler:maybe_record_callsite(+Q, +RepoEntry) is det.
%
% Conditionally record a query:search/2 callsite if stats are enabled.

sampler:maybe_record_callsite(Q, RepoEntry) :-
  ( sampler:callsite_enabled ->
      sampler:maybe_record_callsite_sampled(Q, RepoEntry)
  ; true
  ).


%! sampler:maybe_record_callsite_sampled(+Q, +RepoEntry) is det.
%
% Sampled callsite recorder: only records every Nth call to keep overhead
% low even on huge runs.

sampler:maybe_record_callsite_sampled(Q, RepoEntry) :-
  ( sampler:callsite_rate(Rate) -> true ; Rate = 4096 ),
  ( nb_current(s_callsite_counter, C0) -> true ; C0 = 0 ),
  C is C0 + 1,
  nb_setval(s_callsite_counter, C),
  ( 0 is C mod Rate ->
      nb_setval(s_callsite_last_q, Q),
      nb_setval(s_callsite_last_entry, RepoEntry),
      sampler:record_callsite
  ; true
  ).


%! sampler:record_callsite is det.
%
% Walk the Prolog call stack to identify the external caller of
% query:search/2 and record it in the callsite database.

sampler:record_callsite :-
  ( prolog_current_frame(F),
    prolog_frame_attribute(F, parent, Parent0),
    sampler:skip_trivial_frames(Parent0, CallerFrame0),
    sampler:skip_query_frames(CallerFrame0, CallerFrame),
    sampler:frame_callsite(CallerFrame, File, Line, PI),
    ( nb_current(s_callsite_last_q, Q) -> true ; Q = unknown ),
    ( nb_current(s_callsite_last_entry, E) -> true ; E = unknown ),
    sampler:callsite_signature(Q, E, Sig)
  -> with_mutex(query_search_callsite,
       ( ( retract(sampler:callsite(File, Line, PI, N0)) -> true ; N0 = 0 ),
         N is N0 + 1,
         assertz(sampler:callsite(File, Line, PI, N)),
         ( ( retract(sampler:callsite_sig(File, Line, PI, Sig, S0)) -> true ; S0 = 0 ),
           S is S0 + 1,
           assertz(sampler:callsite_sig(File, Line, PI, Sig, S))
         )
       ))
  ; true
  ).


%! sampler:callsite_signature(+Q, +RepoEntry, -Sig) is det.
%
% Compute a cheap signature for sampled calls to help identify which query
% forms are still reaching runtime query:search/2.

sampler:callsite_signature(Q, RepoEntry, sig(Kind, Head, Flags, EntryKind)) :-
  ( is_list(Q) ->
      Kind = list,
      length(Q, Len),
      Head = list(Len),
      sampler:callsite_sig_flags(Q, Flags0),
      sort(Flags0, Flags)
  ; compound(Q) ->
      Kind = compound,
      ( Q = select(Key, Op, _Value) ->
          sampler:callsite_sig_op(Op, OpTag),
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


%! sampler:callsite_sig_op(+Op, -OpTag) is det.
%
% Classify a query select operator for signature grouping.

sampler:callsite_sig_op(Op, OpTag) :-
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


%! sampler:callsite_sig_flags(+Terms, -Flags) is det.
%
% Extract functor/arity flags from a query term list for signature grouping.

sampler:callsite_sig_flags([], []) :- !.
sampler:callsite_sig_flags([H|T], [Flag|Rest]) :-
  ( compound(H) ->
      functor(H, F, A),
      Flag = F/A
  ; Flag = atom
  ),
  sampler:callsite_sig_flags(T, Rest).


%! sampler:skip_trivial_frames(+Frame0, -Frame) is det.
%
% Walk up the call stack, skipping trivial wrapper frames (query:search,
% system:call, etc.) until a meaningful caller is found.

sampler:skip_trivial_frames(Frame0, Frame) :-
  ( var(Frame0) ; Frame0 == 0 ), !,
  Frame = 0.
sampler:skip_trivial_frames(Frame0, Frame) :-
  ( sampler:frame_predicate_indicator(Frame0, PI),
    sampler:skip_frame_pi(PI)
  -> ( prolog_frame_attribute(Frame0, parent, Parent),
       sampler:skip_trivial_frames(Parent, Frame)
     )
  ; Frame = Frame0
  ).


%! sampler:skip_frame_pi(?PI) is nondet.
%
% Predicate indicators to skip when walking the call stack.

sampler:skip_frame_pi(query:search/2).
sampler:skip_frame_pi(query:memoized_search/2).
sampler:skip_frame_pi(search/2).
sampler:skip_frame_pi(system:call/1).
sampler:skip_frame_pi(system:once/1).
sampler:skip_frame_pi(apply:call_/2).
sampler:skip_frame_pi(apply:maplist_/3).
sampler:skip_frame_pi(apply:include_/3).
sampler:skip_frame_pi(apply:exclude_/3).


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


%! sampler:skip_query_frames(+Frame0, -Frame) is det.
%
% Walk up the call stack until a frame outside query.pl is found, so the
% report points at the actual caller rather than query internals.

sampler:skip_query_frames(Frame0, Frame) :-
  ( var(Frame0) ; Frame0 == 0 ), !,
  Frame = Frame0.
sampler:skip_query_frames(Frame0, Frame) :-
  sampler:frame_callsite(Frame0, File, _Line, PI),
  ( source_file(query:_, QueryFile),
    File == QueryFile
    ; sampler:skip_frame_pi(PI)
  ),
  !,
  ( prolog_frame_attribute(Frame0, parent, Parent) ->
      sampler:skip_query_frames(Parent, Frame)
  ; Frame = Frame0
  ).
sampler:skip_query_frames(Frame0, Frame0).