/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> BUILDER
Build execution orchestrator.

Takes the same pipeline output as printer (Plan, Proof, Model, Triggers)
and executes each step in parallel via the jobserver. Downloads are real
(via download:fetch_distfiles/4), all other phases are stubbed.

The full plan is printed first (normal colors, via printer:print/5), then
a progress area below shows slot-based live updates as workers execute
jobs. Within each plan step, all executable rules run in parallel; steps
are sequential (the next step starts only after the previous completes).
*/

:- module(builder, []).

:- dynamic builder:slot_info/5.
:- dynamic builder:slot_outcome/2.

% =============================================================================
%  BUILDER declarations
% =============================================================================


%! builder:build(+Goals) is det.
%
% Top-level entry point. Proves goals, prints the plan, then executes
% each step in parallel via the jobserver with live progress.

builder:build(Goals) :-
  pipeline:prove_plan_with_fallback(Goals, ProofAVL, ModelAVL, Plan, TriggersAVL),
  printer:print(Goals, ModelAVL, ProofAVL, Plan, TriggersAVL),
  nl,
  build:header,
  builder:num_workers(NumWorkers),
  jobserver:init(NumWorkers, builder:execute_build_job),
  builder:count_steps(Plan, 0, TotalSteps),
  builder:execute_plan(Plan, 1, TotalSteps, 0, 0, 0, Completed, Failed, Stubs),
  jobserver:shutdown(NumWorkers),
  build:summary(Completed, Failed, Stubs).


%! builder:num_workers(-N) is det.
%
% Compute the number of worker threads: min(cpu_count, available_display_lines).

builder:num_workers(N) :-
  config:number_of_cpus(Cpus),
  config:printing_tty_size(H, _W),
  ReservedLines = 6,
  MaxDisplay is max(1, H - ReservedLines),
  N is min(Cpus, MaxDisplay).


% =============================================================================
%  Step counting
% =============================================================================

%! builder:count_steps(+Plan, +Acc, -Total) is det.

builder:count_steps([], Total, Total).

builder:count_steps([Step|Rest], Acc, Total) :-
  builder:count_executable_in_step(Step, N),
  Acc1 is Acc + N,
  builder:count_steps(Rest, Acc1, Total).

builder:count_executable_in_step(Rules, N) :-
  include(builder:is_executable_rule, Rules, Executable),
  length(Executable, N).


%! builder:is_executable_rule(+Rule) is semidet.

builder:is_executable_rule(rule(_Repository://_Entry:_Action?{_Context}, _Body)) :- !.
builder:is_executable_rule(_) :- fail.


% =============================================================================
%  Plan execution (step-at-a-time via jobserver)
% =============================================================================

%! builder:execute_plan(+Plan, +StepN, +TotalSteps, +C0, +F0, +S0, -C, -F, -S) is det.

builder:execute_plan([], _StepN, _TotalSteps, C, F, S, C, F, S).

builder:execute_plan([Step|Rest], StepN, TotalSteps, C0, F0, S0, C, F, S) :-
  builder:execute_step(Step, StepN, TotalSteps, C0, F0, S0, C1, F1, S1, StepN1),
  builder:execute_plan(Rest, StepN1, TotalSteps, C1, F1, S1, C, F, S).


%! builder:execute_step(+Step, +StepN, +TotalSteps, +C0, +F0, +S0, -C, -F, -S, -NextStepN) is det.
%
% Execute all jobs in a step in parallel:
%   1. Extract executable rules and assign display slots
%   2. Register slot info for result handler lookups
%   3. Print all slots as pending
%   4. Submit all jobs to the jobserver
%   5. Collect results, updating slots in-place
%   6. Tally outcomes, clean up

builder:execute_step(Step, StepN, TotalSteps, C0, F0, S0, C, F, S, NextStepN) :-
  plan:stable_sort_by_weight(Step, Sorted),
  include(builder:is_executable_rule, Sorted, Executable),
  length(Executable, NumJobs),
  ( NumJobs > 0
  -> builder:assign_slots(Executable, StepN, TotalSteps, NumJobs, 0, SlottedJobs),
     builder:register_slot_info(SlottedJobs),
     build:print_job_slots(SlottedJobs, TotalSteps),
     jobserver:submit(SlottedJobs),
     jobserver:collect(NumJobs, builder:handle_result(NumJobs)),
     builder:tally_outcomes(C0, F0, S0, C, F, S),
     builder:clear_slot_info,
     NextStepN is StepN + NumJobs
  ;  C = C0, F = F0, S = S0,
     NextStepN = StepN
  ).


%! builder:assign_slots(+Rules, +StepN, +TotalSteps, +NumSlots, +Idx, -SlottedJobs) is det.
%
% Wrap each rule with its slot index, step numbers, and total slot count.

builder:assign_slots([], _StepN, _TotalSteps, _NumSlots, _Idx, []).

builder:assign_slots([Rule|Rest], StepN, TotalSteps, NumSlots, Idx, [Slotted|More]) :-
  Slotted = slotted(Idx, NumSlots, StepN, TotalSteps, Rule),
  Idx1 is Idx + 1,
  StepN1 is StepN + 1,
  builder:assign_slots(Rest, StepN1, TotalSteps, NumSlots, Idx1, More).


% =============================================================================
%  Slot info registry
% =============================================================================

%! builder:register_slot_info(+SlottedJobs) is det.
%
% Store slot metadata so the result handler can look up step/action/entry
% for display without needing the original job term.

builder:register_slot_info([]).

builder:register_slot_info([slotted(Slot, _NumSlots, StepN, TotalSteps, rule(_Repo://Entry:Action?{_Ctx}, _Body))|Rest]) :-
  builder:extract_entry_name(Entry, Name),
  assertz(builder:slot_info(Slot, StepN, TotalSteps, Action, Name)),
  builder:register_slot_info(Rest).

builder:register_slot_info([_|Rest]) :-
  builder:register_slot_info(Rest).


%! builder:clear_slot_info is det.

builder:clear_slot_info :-
  retractall(builder:slot_info(_, _, _, _, _)),
  retractall(builder:slot_outcome(_, _)).


%! builder:get_slot_info(+Slot, -StepN, -TotalSteps, -Action, -Entry) is det.

builder:get_slot_info(Slot, StepN, TotalSteps, Action, Entry) :-
  builder:slot_info(Slot, StepN, TotalSteps, Action, Entry), !.

builder:get_slot_info(_Slot, 0, 0, unknown, unknown).


%! builder:extract_entry_name(+Entry, -Name) is det.

builder:extract_entry_name(Entry, Entry) :- atom(Entry), !.
builder:extract_entry_name(Entry, Name) :- term_to_atom(Entry, Name).


% =============================================================================
%  Job execution (called by worker threads)
% =============================================================================

%! builder:execute_build_job(+SlottedJob, +WorkerSlot, -Result) is det.
%
% Execute a single build job. Called by jobserver worker threads.
% Updates the display slot to "active" on entry, then performs the work.
% Returns result(Slot, Outcome) so the collector can route the display update.

builder:execute_build_job(
    slotted(Slot, NumSlots, StepN, TotalSteps, rule(Repo://Entry:Action?{Ctx}, _Body)),
    _WorkerSlot, result(Slot, Outcome)) :-
  !,
  builder:extract_entry_name(Entry, Name),
  with_mutex(build_display,
    build:update_slot(Slot, NumSlots, active, StepN, TotalSteps, Action, Name)),
  builder:run_action(Action, Repo, Entry, Ctx, Outcome).

builder:execute_build_job(_, _WorkerSlot, result(0, stub)).


%! builder:run_action(+Action, +Repo, +Entry, +Ctx, -Outcome) is det.

builder:run_action(download, Repo, Entry, Ctx, Outcome) :-
  !, builder:run_download(Repo, Entry, Ctx, Outcome).

builder:run_action(fetchonly, Repo, Entry, Ctx, Outcome) :-
  !, builder:run_download(Repo, Entry, Ctx, Outcome).

builder:run_action(_Action, _Repo, _Entry, _Ctx, stub).


%! builder:run_download(+Repo, +Entry, +Ctx, -Outcome) is det.

builder:run_download(Repo, Entry, Ctx, Outcome) :-
  ( download:fetch_distfiles(Repo, Entry, Ctx, Failures),
    Failures == []
  -> Outcome = done
  ;  Outcome = failed('download errors')
  ).


% =============================================================================
%  Result handling (main thread, display callback)
% =============================================================================

%! builder:handle_result(+NumSlots, +Slot, +Outcome) is det.
%
% Called by jobserver:collect for each completed job. Updates the
% display slot and records the outcome for tallying.

builder:handle_result(NumSlots, _Slot, result(DisplaySlot, Outcome)) :-
  !,
  builder:handle_result(NumSlots, DisplaySlot, Outcome).

builder:handle_result(NumSlots, Slot, Outcome) :-
  assertz(builder:slot_outcome(Slot, Outcome)),
  builder:get_slot_info(Slot, StepN, TotalSteps, Action, Entry),
  builder:outcome_to_status(Outcome, Status),
  with_mutex(build_display,
    build:update_slot(Slot, NumSlots, Status, StepN, TotalSteps, Action, Entry)).


%! builder:outcome_to_status(+Outcome, -Status) is det.

builder:outcome_to_status(done, done) :- !.
builder:outcome_to_status(stub, stub) :- !.
builder:outcome_to_status(failed(Reason), failed(Reason)) :- !.
builder:outcome_to_status(failed, failed('error')) :- !.
builder:outcome_to_status(error(E), failed(E)) :- !.
builder:outcome_to_status(_, failed('unknown')).


% =============================================================================
%  Tally
% =============================================================================

%! builder:tally_outcomes(+C0, +F0, +S0, -C, -F, -S) is det.
%
% Count recorded outcomes from the last step.

builder:tally_outcomes(C0, F0, S0, C, F, S) :-
  aggregate_all(count, builder:slot_outcome(_, done), DC),
  aggregate_all(count, builder:slot_outcome(_, stub), SC),
  aggregate_all(count, (builder:slot_outcome(_, O),
                         O \= done, O \= stub), FC),
  C is C0 + DC,
  F is F0 + FC,
  S is S0 + SC.
