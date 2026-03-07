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


%! pipeline:prove_plan_basic(+Goals, -ProofAVL, -ModelAVL, -Plan, -TriggersAVL)
%
% Single-pass pipeline with per-stage wall-time instrumentation.

pipeline:prove_plan_basic(Goals, ProofAVL, ModelAVL, Plan, TriggersAVL) :-
  sampler:perf_walltime(T0),
  prover:prove(Goals, t, ProofAVL, t, ModelAVL, t, _Constraints, t, TriggersAVL),
  sampler:perf_walltime(T1),
  planner:plan(ProofAVL, TriggersAVL, t, Plan0, Remainder0),
  sampler:perf_walltime(T2),
  scheduler:schedule(ProofAVL, TriggersAVL, Plan0, Remainder0, Plan, _Remainder),
  sampler:perf_walltime(T3),
  sampler:perf_record(T0, T1, T2, T3).


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