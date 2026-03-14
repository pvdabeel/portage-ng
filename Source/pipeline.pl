/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> PIPELINE
The Pipeline orchestrates the three core resolution stages — prover,
planner, and scheduler — into a single entry point.

Architecture context:

  reader/parser  →  prover  →  planner  →  scheduler  →  printer
                    └──────── pipeline ────────┘

The pipeline sits between the parsing layer (reader + eapi grammar) and
the output layer (printer + writer).  It takes a list of proof goals and
returns a completed proof, model, scheduled plan, and triggers AVL:

  prove_plan(+Goals, -ProofAVL, -ModelAVL, -Plan, -TriggersAVL)

Callers:
- interface.pl  — interactive CLI proving  (--pretend / --merge)
- writer.pl     — batch file generation    (--graph)
- prover.pl     — test-target validation   (prover:test/1)

Pipeline stages:
1. prover:prove/9   — inductive proof search, builds ProofAVL + ModelAVL
2. planner:plan/5   — wave planning for acyclic portion, yields Plan + Remainder
3. scheduler:schedule/6 — SCC / merge-set scheduling for Remainder

Each stage is timed via sampler:perf_walltime and recorded via
sampler:perf_record for performance analysis.

PDEPEND handling:
Post-dependencies are normally resolved single-pass inside the prover
(see rules:literal_hook/4).  The prove_plan_with_pdepend/5 variant
provides an alternative multi-pass approach that delegates PDEPEND goal
extraction to dependency:pdepend_goals_from_plan/2 and re-runs the
pipeline with the extended goal set.  It is retained for experimentation
but not currently used in the default path.
*/

:- module(pipeline, []).


% =============================================================================
%  Core pipeline: prove + plan + schedule
% =============================================================================

%! pipeline:prove_plan(+Goals, -ProofAVL, -ModelAVL, -Plan, -TriggersAVL)
%
% Standard entry point.  Proves Goals, plans the proof, and schedules
% the remainder into a fully ordered Plan.

pipeline:prove_plan(Goals, ProofAVL, ModelAVL, Plan, TriggersAVL) :-
  pipeline:prove_plan_basic(Goals, ProofAVL, ModelAVL, Plan, TriggersAVL).


%! pipeline:prove_plan_with_fallback(+Goals, -ProofAVL, -ModelAVL, -Plan, -TriggersAVL)
%
% Proves with progressive relaxation: strict first, then keyword_acceptance,
% blockers, unmask, and finally both keyword_acceptance + unmask.  Used by
% both standalone and client paths so the fallback chain is consistent.

pipeline:prove_plan_with_fallback(Goals, ProofAVL, ModelAVL, Plan, TriggersAVL) :-
  pipeline:prove_plan_with_fallback(Goals, ProofAVL, ModelAVL, Plan, TriggersAVL, _).

%! pipeline:prove_plan_with_fallback(+Goals, -Proof, -Model, -Plan, -Triggers, -FallbackUsed)
%
% Same as prove_plan_with_fallback/5 but returns which relaxation tier
% was needed: false (strict), keyword_acceptance, blockers, unmask,
% keyword_unmask, or none (all tiers failed → deterministic failure).

pipeline:prove_plan_with_fallback(Goals, ProofAVL, ModelAVL, Plan, TriggersAVL, FallbackUsed) :-
  ( pipeline:prove_plan(Goals, ProofAVL, ModelAVL, Plan, TriggersAVL) ->
      FallbackUsed = false
  ; prover:assuming(keyword_acceptance,
      pipeline:prove_plan(Goals, ProofAVL, ModelAVL, Plan, TriggersAVL)) ->
      FallbackUsed = keyword_acceptance
  ; prover:assuming(blockers,
      pipeline:prove_plan(Goals, ProofAVL, ModelAVL, Plan, TriggersAVL)) ->
      FallbackUsed = blockers
  ; prover:assuming(unmask,
      pipeline:prove_plan(Goals, ProofAVL, ModelAVL, Plan, TriggersAVL)) ->
      FallbackUsed = unmask
  ; prover:assuming(keyword_acceptance,
      prover:assuming(unmask,
        pipeline:prove_plan(Goals, ProofAVL, ModelAVL, Plan, TriggersAVL))) ->
      FallbackUsed = keyword_unmask
  ; fail
  ).


%! pipeline:prove_plan_basic(+Goals, -ProofAVL, -ModelAVL, -Plan, -TriggersAVL)
%
% Single-pass pipeline with per-stage wall-time instrumentation.
% Pre-injects selected_cn_allow_multislot constraints when the goal
% list contains multiple targets for the same Category-Name (different
% versions/slots).

pipeline:prove_plan_basic(Goals, ProofAVL, ModelAVL, Plan, TriggersAVL) :-
  sampler:perf_walltime(T0),
  pipeline:multislot_initial_constraints(Goals, InitCons),
  prover:prove(Goals, t, ProofAVL, t, ModelAVL, InitCons, _Constraints, t, TriggersAVL),
  sampler:perf_walltime(T1),
  planner:plan(ProofAVL, TriggersAVL, t, Plan0, Remainder0),
  sampler:perf_walltime(T2),
  scheduler:schedule(ProofAVL, TriggersAVL, Plan0, Remainder0, Plan, _Remainder),
  sampler:perf_walltime(T3),
  sampler:perf_record(T0, T1, T2, T3).


% =============================================================================
%  Testing
% =============================================================================

%! pipeline:test(+Repository) is det
%
% Runs the full pipeline (prove + plan + schedule + print) for every entry
% in Repository. Same as printer:test/1.

pipeline:test(Repository) :-
  printer:test(Repository).


%! pipeline:test_stats(+Repository) is det
%
% Runs the full pipeline with statistics recording and Top-N report.
% Uses label 'Pipeline' for the stats output.

pipeline:test_stats(Repository) :-
  config:test_style(Style),
  pipeline:test_stats(Repository, Style).

%! pipeline:test_stats(+Repository, +Style) is det
%
% Same as pipeline:test_stats/1 with explicit Style.

pipeline:test_stats(Repository, Style) :-
  config:proving_target(Action),
  aggregate_all(count, (Repository:entry(_E)), ExpectedTotal),
  sampler:test_stats_reset('Pipeline', ExpectedTotal),
  aggregate_all(count, (Repository:package(_C,_N)), ExpectedPkgs),
  sampler:test_stats_set_expected_unique_packages(ExpectedPkgs),
  tester:test(Style,
              'Pipeline',
              Repository://Entry,
              (Repository:entry(Entry)),
              ( prover:prove(Repository://Entry:Action?{[]},t,ProofAVL,t,ModelAVL,t,_Constraint,t,Triggers),
                planner:plan(ProofAVL,Triggers,t,Plan0,Remainder0),
                scheduler:schedule(ProofAVL,Triggers,Plan0,Remainder0,Plan,_Remainder)
              ),
              ( sampler:test_stats_record_entry(Repository://Entry, ModelAVL, ProofAVL, Triggers, false),
                sampler:test_stats_set_current_entry(Repository://Entry),
                printer:print([Repository://Entry:Action?{[]}],ModelAVL,ProofAVL,Plan,Triggers),
                sampler:test_stats_clear_current_entry
              ),
              false),
  stats:test_stats_print.


% =============================================================================
%  Multi-slot initial constraints
% =============================================================================

%! pipeline:multislot_initial_constraints(+Goals, -Constraints) is det.
%
% Scans the goal list for duplicate (Category, Name) pairs (different
% versions of the same package). For each such pair, pre-populates the
% constraint AVL with selected_cn_allow_multislot(C,N) so the prover
% permits per-slot selection instead of enforcing single-selection.

pipeline:multislot_initial_constraints(Goals, Constraints) :-
  pipeline:extract_goal_cns(Goals, CNs),
  msort(CNs, Sorted),
  pipeline:collect_duplicate_cns(Sorted, DupCNs),
  pipeline:build_multislot_avl(DupCNs, t, Constraints).


%! pipeline:extract_goal_cns(+Goals, -CNPairs) is det.

pipeline:extract_goal_cns([], []).

pipeline:extract_goal_cns([target(Q, _):_?{_}|Rest], [C-N|More]) :-
  once(kb:query(Q, R://E)),
  query:search([category(C), name(N)], R://E),
  !,
  pipeline:extract_goal_cns(Rest, More).

pipeline:extract_goal_cns([_|Rest], More) :-
  pipeline:extract_goal_cns(Rest, More).


%! pipeline:collect_duplicate_cns(+Sorted, -Duplicates) is det.

pipeline:collect_duplicate_cns([], []).

pipeline:collect_duplicate_cns([CN, CN|Rest], [CN|More]) :-
  !,
  pipeline:skip_same_cn(CN, Rest, Rest1),
  pipeline:collect_duplicate_cns(Rest1, More).

pipeline:collect_duplicate_cns([_|Rest], More) :-
  pipeline:collect_duplicate_cns(Rest, More).


%! pipeline:skip_same_cn(+CN, +List, -Rest) is det.

pipeline:skip_same_cn(CN, [CN|Rest], Rest1) :-
  !,
  pipeline:skip_same_cn(CN, Rest, Rest1).

pipeline:skip_same_cn(_, Rest, Rest).


%! pipeline:build_multislot_avl(+DupCNs, +AVL0, -AVL) is det.

pipeline:build_multislot_avl([], AVL, AVL).

pipeline:build_multislot_avl([C-N|Rest], AVL0, AVL) :-
  put_assoc(selected_cn_allow_multislot(C,N), AVL0, true, AVL1),
  pipeline:build_multislot_avl(Rest, AVL1, AVL).


% =============================================================================
%  Extended pipeline with PDEPEND fixpoint
% =============================================================================

%! pipeline:prove_plan_with_pdepend(+Goals, -ProofAVL, -ModelAVL, -Plan, -TriggersAVL)
%
% Two-pass variant.  Runs the basic pipeline, extracts PDEPEND goals
% from merged entries in the resulting plan, and — if new goals were
% found — re-runs the pipeline with the extended goal set.
%
% Retained for experimentation; the default path uses prove_plan/5.

pipeline:prove_plan_with_pdepend(Goals0, ProofAVL, ModelAVL, Plan, TriggersAVL) :-
  statistics(walltime, [T0,_]),
  pipeline:prove_plan_basic(Goals0, Proof0, Model0, Plan0, Trig0),
  statistics(walltime, [T1,_]),
  Pass1Ms is T1 - T0,
  statistics(walltime, [T2,_]),
  dependency:pdepend_goals_from_plan(Plan0, PdependGoals),
  statistics(walltime, [T3,_]),
  ExtractMs is T3 - T2,
  ( PdependGoals == [] ->
      sampler:pdepend_perf_add(Pass1Ms, ExtractMs, 0, 0, 0),
      ProofAVL = Proof0, ModelAVL = Model0, Plan = Plan0, TriggersAVL = Trig0
  ; sort(Goals0, GoalsU),
    sort(PdependGoals, PdepU),
    subtract(PdepU, GoalsU, NewGoals),
    length(NewGoals, NewGoalsCount),
    ( NewGoals == [] ->
        sampler:pdepend_perf_add(Pass1Ms, ExtractMs, 0, 0, 0),
        ProofAVL = Proof0, ModelAVL = Model0, Plan = Plan0, TriggersAVL = Trig0
    ; append(Goals0, NewGoals, Goals1),
      statistics(walltime, [T4,_]),
      pipeline:prove_plan_basic(Goals1, ProofAVL, ModelAVL, Plan, TriggersAVL),
      statistics(walltime, [T5,_]),
      Pass2Ms is T5 - T4,
      sampler:pdepend_perf_add(Pass1Ms, ExtractMs, Pass2Ms, 1, NewGoalsCount)
    )
  ).


% =============================================================================
%  Multi-variant pipeline (parallel re-proving)
% =============================================================================

%! pipeline:prove_plan_variants(+Goals, +Targets, +VariantSpecs, -Baseline, -VariantResults) is det.
%
% Proves the baseline plan, then re-proves each variant specification
% in parallel using concurrent threads. Each thread gets its own
% thread-local variant overrides and memo caches.
%
% Baseline = baseline(ProofAVL, ModelAVL, Plan, TriggersAVL)
% VariantResults = list of variant_result(Spec, ProofAVL, ModelAVL, Plan, TriggersAVL)
%                  or variant_result(Spec, failed) on proof failure.

pipeline:prove_plan_variants(Goals, _Targets, VariantSpecs,
                             baseline(ProofAVL, ModelAVL, Plan, TriggersAVL),
                             VariantResults) :-
  pipeline:prove_plan_with_fallback(Goals, ProofAVL, ModelAVL, Plan, TriggersAVL),
  pipeline:prove_variants_parallel(Goals, VariantSpecs, VariantResults).


%! pipeline:prove_variants_parallel(+Goals, +Specs, -Results) is det.
%
% Proves each variant in a separate thread. Thread-local overrides
% ensure variants don't interfere with each other or the main thread.

pipeline:prove_variants_parallel(Goals, Specs, Results) :-
  length(Specs, N),
  ( N =:= 0
  -> Results = []
  ; length(Results, N),
    pipeline:prove_variants_threads(Goals, Specs, Results)
  ).


%! pipeline:prove_variants_threads(+Goals, +Specs, -Results) is det.
%
% Spawns a thread per variant using a shared message queue to
% collect results. Thread bindings do not propagate back via
% thread_join, so each thread posts its result to the queue.

pipeline:prove_variants_threads(Goals, Specs, Results) :-
  message_queue_create(Queue),
  length(Specs, N),
  findall(ThreadId,
    ( nth1(Idx, Specs, Spec),
      thread_create(
        pipeline:prove_single_variant(Goals, Spec, Idx, Queue),
        ThreadId, [])
    ),
    ThreadIds),
  maplist(pipeline:join_variant_thread, ThreadIds),
  pipeline:collect_queue_results(Queue, N, Unsorted),
  message_queue_destroy(Queue),
  msort(Unsorted, Sorted),
  pairs_values(Sorted, Results).


%! pipeline:join_variant_thread(+ThreadId) is det.

pipeline:join_variant_thread(ThreadId) :-
  thread_join(ThreadId, _Status).


%! pipeline:collect_queue_results(+Queue, +N, -Results) is det.

pipeline:collect_queue_results(_, 0, []) :- !.
pipeline:collect_queue_results(Queue, N, [Idx-Result|Rest]) :-
  thread_get_message(Queue, result(Idx, Result)),
  N1 is N - 1,
  pipeline:collect_queue_results(Queue, N1, Rest).


%! pipeline:prove_single_variant(+Goals, +Spec, +Idx, +Queue) is det.
%
% Runs inside a spawned thread. Applies the variant override,
% clears memo caches (thread-local), proves, and posts the result
% to the shared message queue.

pipeline:prove_single_variant(Goals, Spec, Idx, Queue) :-
  setup_call_cleanup(
    ( variant:apply(Spec),
      memo:clear_caches
    ),
    ( catch(
        ( pipeline:prove_plan_with_fallback(Goals, P, M, Pl, T)
        -> thread_send_message(Queue, result(Idx, variant_result(Spec, P, M, Pl, T)))
        ;  thread_send_message(Queue, result(Idx, variant_result(Spec, failed)))
        ),
        _Error,
        thread_send_message(Queue, result(Idx, variant_result(Spec, failed)))
      )
    ),
    ( variant:cleanup,
      memo:clear_caches
    )
  ).