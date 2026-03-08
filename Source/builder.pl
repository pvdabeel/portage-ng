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
  builder:count_steps(Plan, 0, TotalActions),
  builder:count_nonempty_steps(Plan, 0, NumSteps),
  build:header(NumSteps, TotalActions),
  builder:num_workers(NumWorkers),
  jobserver:init(NumWorkers, builder:execute_build_job),
  builder:execute_plan(Plan, 1, TotalActions, 0, 0, 0, Completed, Failed, Stubs),
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


%! builder:count_nonempty_steps(+Plan, +Acc, -Total) is det.

builder:count_nonempty_steps([], Total, Total).

builder:count_nonempty_steps([Step|Rest], Acc, Total) :-
  builder:count_executable_in_step(Step, N),
  ( N > 0 -> Acc1 is Acc + 1 ; Acc1 = Acc ),
  builder:count_nonempty_steps(Rest, Acc1, Total).


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
%   1. Extract executable rules and pre-allocate display layout
%   2. Register slot info for result handler lookups
%   3. Print all slots (with file sub-lines for downloads)
%   4. Submit all jobs to the jobserver
%   5. Collect results, updating slots in-place
%   6. Tally outcomes, clean up

builder:execute_step(Step, StepN, TotalSteps, C0, F0, S0, C, F, S, NextStepN) :-
  plan:stable_sort_by_weight(Step, Sorted),
  include(builder:is_executable_rule, Sorted, Executable),
  length(Executable, NumJobs),
  ( NumJobs > 0
  -> builder:assign_slots(Executable, StepN, TotalSteps, SlottedJobs, TotalLines),
     builder:register_slot_info(SlottedJobs),
     build:print_job_slots(SlottedJobs, TotalSteps),
     jobserver:submit(SlottedJobs),
     jobserver:collect(NumJobs, builder:handle_result(TotalLines)),
     nl,
     builder:tally_outcomes(C0, F0, S0, C, F, S),
     builder:clear_slot_info,
     NextStepN is StepN + NumJobs
  ;  C = C0, F = F0, S = S0,
     NextStepN = StepN
  ).


%! builder:assign_slots(+Rules, +StepN, +TotalSteps, -SlottedJobs, -TotalLines) is det.
%
% Pre-allocate the display layout. For download/fetchonly rules, queries
% distfile specs to determine file sub-line count. Each slotted/6 term
% carries its absolute LineOffset and a shared TotalLines variable
% (bound when the last rule is processed).

builder:assign_slots(Rules, StepN, TotalSteps, SlottedJobs, TotalLines) :-
  distfiles:get_location(Distdir),
  builder:assign_slots_(Rules, StepN, TotalSteps, Distdir, 0, TotalLines, SlottedJobs).

builder:assign_slots_([], _StepN, _TotalSteps, _Distdir, LineOff, LineOff, []).

builder:assign_slots_([Rule|Rest], StepN, TotalSteps, Distdir, LineOff, TotalLines, [Slotted|More]) :-
  builder:rule_file_info(Rule, Distdir, LineOff, FileInfo, LinesForRule),
  NextLineOff is LineOff + LinesForRule,
  Slotted = slotted(LineOff, TotalLines, StepN, TotalSteps, Rule, FileInfo),
  StepN1 is StepN + 1,
  builder:assign_slots_(Rest, StepN1, TotalSteps, Distdir, NextLineOff, TotalLines, More).


%! builder:rule_file_info(+Rule, +Distdir, +LineOff, -FileInfo, -Lines) is det.
%
% Determine file metadata for a rule. Downloads with distfiles get
% files(FileStartLine, NumFiles, DistFiles, Distdir); others get no_files.

builder:rule_file_info(rule(Repo://Entry:Action?{_Ctx}, _Body), Distdir, LineOff, FileInfo, Lines) :-
  memberchk(Action, [download, fetchonly]),
  !,
  download:collect_distfile_specs(Repo, Entry, DistFiles),
  length(DistFiles, NumFiles),
  ( NumFiles > 0
  -> FileStartLine is LineOff + 1,
     FileInfo = files(FileStartLine, NumFiles, DistFiles, Distdir),
     Lines is 1 + NumFiles
  ;  FileInfo = no_files,
     Lines = 1
  ).

builder:rule_file_info(_, _, _, no_files, 1).


% =============================================================================
%  Slot info registry
% =============================================================================

%! builder:register_slot_info(+SlottedJobs) is det.
%
% Store slot metadata so the result handler can look up step/action/entry
% for display without needing the original job term.

builder:register_slot_info([]).

builder:register_slot_info([slotted(LineOff, _TotalLines, StepN, TotalSteps, rule(Repo://Entry:Action?{_Ctx}, _Body), _FileInfo)|Rest]) :-
  assertz(builder:slot_info(LineOff, StepN, TotalSteps, Action, Repo://Entry)),
  builder:register_slot_info(Rest).

builder:register_slot_info([_|Rest]) :-
  builder:register_slot_info(Rest).


%! builder:clear_slot_info is det.

builder:clear_slot_info :-
  retractall(builder:slot_info(_, _, _, _, _)),
  retractall(builder:slot_outcome(_, _)),
  retractall(builder:dl_prev_snapshot(_, _, _)).


%! builder:get_slot_info(+Slot, -StepN, -TotalSteps, -Action, -Entry) is det.

builder:get_slot_info(Slot, StepN, TotalSteps, Action, Entry) :-
  builder:slot_info(Slot, StepN, TotalSteps, Action, Entry), !.

builder:get_slot_info(_Slot, 0, 0, unknown, unknown).



% =============================================================================
%  Job execution (called by worker threads)
% =============================================================================

%! builder:execute_build_job(+SlottedJob, +WorkerSlot, -Result) is det.
%
% Execute a single build job. Called by jobserver worker threads.
% Updates the display slot to "active" on entry, then performs the work.
% For download/fetchonly actions, the worker manages file sub-slot display
% itself and returns display_handled(Outcome) to skip redundant updates.

builder:execute_build_job(
    slotted(LineOff, TotalLines, StepN, TotalSteps, rule(Repo://Entry:Action?{Ctx}, _Body), FileInfo),
    _WorkerSlot, result(LineOff, ResultOutcome)) :-
  !,
  with_mutex(build_display,
    build:update_slot(LineOff, TotalLines, active, StepN, TotalSteps, Action, Repo://Entry)),
  ( FileInfo = files(FileStartLine, _NumFiles, DistFiles, Distdir)
  -> builder:run_download_parallel(Repo, Entry, Ctx, LineOff, TotalLines, StepN, TotalSteps, Action,
                                    FileStartLine, DistFiles, Distdir, Outcome),
     ResultOutcome = display_handled(Outcome)
  ;  memberchk(Action, [download, fetchonly])
  -> with_mutex(build_display,
       build:update_slot(LineOff, TotalLines, done, StepN, TotalSteps, Action, Repo://Entry)),
     ResultOutcome = display_handled(done)
  ;  builder:run_action(Action, Repo, Entry, Ctx, Outcome),
     ResultOutcome = Outcome
  ).

builder:execute_build_job(_, _WorkerSlot, result(0, stub)).


%! builder:run_action(+Action, +Repo, +Entry, +Ctx, -Outcome) is det.
%
% Execute a non-download action. Downloads are handled by
% run_download_parallel via execute_build_job.

builder:run_action(_Action, _Repo, _Entry, _Ctx, stub).


%! builder:run_download_parallel(+Repo, +Entry, +Ctx, +LineOff, +TotalLines, +StepN, +TotalSteps, +Action, +FileStartLine, +DistFiles, +Distdir, -Outcome) is det.
%
% Parallel download with per-file progress using pre-allocated layout.
% File sub-lines are already printed by print_job_slots; this predicate
% only starts async curls, polls progress in-place, and updates the
% header slot on completion.

builder:run_download_parallel(Repo, Entry, _Ctx, LineOff, TotalLines, StepN, TotalSteps, Action,
                               FileStartLine, DistFiles, Distdir, Outcome) :-
  ( \+ exists_directory(Distdir) -> make_directory_path(Distdir) ; true ),
  config:mirror_url(MirrorUrl),
  download:mirror_layout(Layout),
  builder:prepare_download_jobs(MirrorUrl, Layout, Distdir, DistFiles, 0, DlJobs),
  get_time(T0),
  builder:init_speed_tracking(DlJobs, T0, FileStartLine),
  builder:poll_download_loop(DlJobs, TotalLines, FileStartLine, Distdir, FailCount),
  ( FailCount =:= 0
  -> FinalStatus = done, Outcome = done
  ;  FinalStatus = failed('download errors'), Outcome = failed('download errors')
  ),
  with_mutex(build_display,
    build:update_slot(LineOff, TotalLines, FinalStatus, StepN, TotalSteps, Action, Repo://Entry)).


% =============================================================================
%  Parallel download helpers
% =============================================================================

%! builder:prepare_download_jobs(+MirrorUrl, +Layout, +Distdir, +DistFiles, +Idx, -DlJobs) is det.
%
% Start async curl processes for files not already present. Returns
% dl_job/6 terms for tracking. Already-present files are skipped
% (they already show checkmarks from print_file_subslots).

builder:prepare_download_jobs(_, _, _, [], _, []).

builder:prepare_download_jobs(MirrorUrl, Layout, Distdir, [dist(Filename, Size, Pairs)|Rest], Idx, Jobs) :-
  Idx1 is Idx + 1,
  ( mirror:flat_present(Distdir, Filename)
  -> builder:prepare_download_jobs(MirrorUrl, Layout, Distdir, Rest, Idx1, Jobs)
  ;  download:mirror_download_url(MirrorUrl, Layout, Filename, URL),
     atomic_list_concat([Distdir, '/', Filename], DestPath),
     download:start_curl_async(URL, DestPath, Pid),
     Jobs = [dl_job(Pid, Idx, Filename, Size, Pairs, DestPath)|MoreJobs],
     builder:prepare_download_jobs(MirrorUrl, Layout, Distdir, Rest, Idx1, MoreJobs)
  ).


% -----------------------------------------------------------------------------
%  Speed tracking (dynamic state for per-file speed calculation)
% -----------------------------------------------------------------------------

:- dynamic builder:dl_prev_snapshot/3.

%! builder:init_speed_tracking(+DlJobs, +T0, +FileStartLine) is det.

builder:init_speed_tracking([], _, _).

builder:init_speed_tracking([dl_job(_, Idx, _, _, _, _)|Rest], T0, FileStartLine) :-
  Key is FileStartLine + Idx,
  retractall(builder:dl_prev_snapshot(Key, _, _)),
  assertz(builder:dl_prev_snapshot(Key, 0, T0)),
  builder:init_speed_tracking(Rest, T0, FileStartLine).


%! builder:compute_speed(+Key, +CurrentSize, -Speed) is det.
%
% Compute download speed in bytes/sec using delta from last snapshot.
% Key is FileStartLine + FileIdx (unique across concurrent downloads).

builder:compute_speed(Key, CurrentSize, Speed) :-
  get_time(Now),
  ( builder:dl_prev_snapshot(Key, PrevSize, PrevTime)
  -> Delta is CurrentSize - PrevSize,
     Dt is Now - PrevTime,
     ( Dt > 0.1, Delta > 0
     -> Speed is round(Delta / Dt),
        retractall(builder:dl_prev_snapshot(Key, _, _)),
        assertz(builder:dl_prev_snapshot(Key, CurrentSize, Now))
     ;  Speed = 0
     )
  ;  Speed = 0,
     assertz(builder:dl_prev_snapshot(Key, CurrentSize, Now))
  ).


% -----------------------------------------------------------------------------
%  Poll loop
% -----------------------------------------------------------------------------

%! builder:poll_download_loop(+DlJobs, +TotalLines, +FileStartLine, +Distdir, -FailCount) is det.
%
% Poll all active downloads until none remain. Returns the total
% number of failed downloads. Updates file sub-slot display with
% percentage and speed on each iteration.

builder:poll_download_loop([], _, _, _, 0) :- !.

builder:poll_download_loop(ActiveJobs, TotalLines, FileStartLine, Distdir, TotalFails) :-
  builder:poll_all_jobs(ActiveJobs, TotalLines, FileStartLine, Distdir, StillActive, BatchFails),
  ( StillActive == []
  -> TotalFails = BatchFails
  ;  sleep(0.25),
     builder:poll_download_loop(StillActive, TotalLines, FileStartLine, Distdir, MoreFails),
     TotalFails is BatchFails + MoreFails
  ).


%! builder:poll_all_jobs(+Jobs, +TotalLines, +FileStartLine, +Distdir, -StillActive, -Fails) is det.

builder:poll_all_jobs([], _, _, _, [], 0).

builder:poll_all_jobs([Job|Rest], TotalLines, FileStartLine, Distdir, StillActive, Fails) :-
  Job = dl_job(Pid, FileIdx, Filename, ExpSize, Pairs, DestPath),
  ( download:check_process_done(Pid, ExitCode)
  -> builder:finalize_download(ExitCode, FileIdx, Filename, ExpSize, Pairs, DestPath,
                                TotalLines, FileStartLine, Distdir, OK),
     builder:poll_all_jobs(Rest, TotalLines, FileStartLine, Distdir, StillActive, RestFails),
     ( OK == true -> Fails = RestFails ; Fails is RestFails + 1 )
  ;  builder:update_download_progress(FileIdx, Filename, ExpSize, DestPath,
                                       TotalLines, FileStartLine, Distdir),
     StillActive = [Job|MoreActive],
     builder:poll_all_jobs(Rest, TotalLines, FileStartLine, Distdir, MoreActive, Fails)
  ).


%! builder:finalize_download(+ExitCode, +FileIdx, +Filename, +ExpSize, +Pairs, +DestPath, +TotalLines, +FileStartLine, +Distdir, -OK) is det.
%
% Called when a curl process exits. Verifies size and hashes,
% updates the file sub-slot to done or failed.

builder:finalize_download(ExitCode, FileIdx, Filename, ExpSize, Pairs, DestPath,
                           TotalLines, FileStartLine, Distdir, OK) :-
  ( ExitCode =:= 0,
    download:verify_size(DestPath, ExpSize),
    download:verify_hashes(DestPath, Pairs)
  -> OK = true,
     with_mutex(build_display,
       build:update_file_subslot(FileIdx, FileStartLine, TotalLines, done, Filename, ExpSize, Distdir))
  ;  catch(delete_file(DestPath), _, true),
     OK = false,
     with_mutex(build_display,
       build:update_file_subslot(FileIdx, FileStartLine, TotalLines, failed, Filename, ExpSize, Distdir))
  ).


%! builder:update_download_progress(+FileIdx, +Filename, +ExpSize, +DestPath, +TotalLines, +FileStartLine, +Distdir) is det.
%
% Update a file sub-slot with current download progress (percentage + speed).

builder:update_download_progress(FileIdx, Filename, ExpSize, DestPath,
                                  TotalLines, FileStartLine, Distdir) :-
  SpeedKey is FileStartLine + FileIdx,
  ( exists_file(DestPath)
  -> size_file(DestPath, CurrentSize),
     ( atom(ExpSize) -> atom_number(ExpSize, ES) ; ES = ExpSize ),
     ( ES > 0 -> Pct is min(99, (CurrentSize * 100) // ES) ; Pct = 0 ),
     builder:compute_speed(SpeedKey, CurrentSize, Speed)
  ;  Pct = 0, Speed = 0
  ),
  with_mutex(build_display,
    build:update_file_subslot(FileIdx, FileStartLine, TotalLines, progress(Pct, Speed), Filename, ExpSize, Distdir)).


% =============================================================================
%  Result handling (main thread, display callback)
% =============================================================================

%! builder:handle_result(+TotalLines, +LineOff, +Outcome) is det.
%
% Called by jobserver:collect for each completed job. Updates the
% display slot and records the outcome for tallying.
% display_handled(Outcome) means the worker already updated the display.

builder:handle_result(_TotalLines, LineOff, display_handled(Outcome)) :-
  !,
  assertz(builder:slot_outcome(LineOff, Outcome)).

builder:handle_result(TotalLines, LineOff, Outcome) :-
  assertz(builder:slot_outcome(LineOff, Outcome)),
  builder:get_slot_info(LineOff, StepN, TotalSteps, Action, Entry),
  builder:outcome_to_status(Outcome, Status),
  with_mutex(build_display,
    build:update_slot(LineOff, TotalLines, Status, StepN, TotalSteps, Action, Entry)).


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
