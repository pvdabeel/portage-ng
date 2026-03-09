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
and executes each step in parallel via the jobserver. Downloads use
parallel curl with per-file progress; other build phases dispatch to
ebuild_exec (Portage's ebuild CLI) when config:build_live_phases is
non-empty, or return stub when fully stubbed.

The full plan is printed first (normal colors, via printer:print/5), then
a progress area below shows slot-based live updates as workers execute
jobs. Within each plan step, all executable rules run in parallel; steps
are sequential (the next step starts only after the previous completes).
*/

:- module(builder, []).

:- dynamic builder:slot_info/6.
:- dynamic builder:slot_outcome/2.
:- dynamic builder:exec_phase_state/3.

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
  builder:count_actions(Plan, 0, TotalActions),
  builder:count_nonempty_steps(Plan, 0, NumSteps),
  build:header(NumSteps, TotalActions),
  builder:num_workers(NumWorkers),
  jobserver:init(NumWorkers, builder:execute_build_job),
  builder:execute_plan(Plan, 1, NumSteps, 0, 0, 0, Completed, Failed, Stubs),
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

%! builder:count_actions(+Plan, +Acc, -Total) is det.

builder:count_actions([], Total, Total).

builder:count_actions([Step|Rest], Acc, Total) :-
  builder:count_executable_in_step(Step, N),
  Acc1 is Acc + N,
  builder:count_actions(Rest, Acc1, Total).

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
builder:is_executable_rule(rule(world_action(_Op, _Arg):world?{_Ctx}, _Body)) :- !.
builder:is_executable_rule(_) :- fail.


% =============================================================================
%  Plan execution (step-at-a-time via jobserver)
% =============================================================================

%! builder:execute_plan(+Plan, +PlanStep, +NumSteps, +C0, +F0, +S0, -C, -F, -S) is det.

builder:execute_plan([], _PlanStep, _NumSteps, C, F, S, C, F, S).

builder:execute_plan([Step|Rest], PlanStep, NumSteps, C0, F0, S0, C, F, S) :-
  builder:execute_step(Step, PlanStep, NumSteps, C0, F0, S0, C1, F1, S1, HasJobs),
  ( HasJobs == true -> PlanStep1 is PlanStep + 1 ; PlanStep1 = PlanStep ),
  ( F1 > F0
  -> builder:skip_remaining(Rest, PlanStep1, NumSteps, C1, F1, S1, C, F, S)
  ;  builder:execute_plan(Rest, PlanStep1, NumSteps, C1, F1, S1, C, F, S)
  ).


%! builder:skip_remaining(+Plan, +PlanStep, +NumSteps, +C0, +F0, +S0, -C, -F, -S) is det.
%
% When a step has failures, skip all remaining steps. Each remaining
% executable action is counted as failed since its dependencies weren't met.

builder:skip_remaining([], _PlanStep, _NumSteps, C, F, S, C, F, S).

builder:skip_remaining([Step|Rest], PlanStep, NumSteps, C0, F0, S0, C, F, S) :-
  include(builder:is_executable_rule, Step, Executable),
  length(Executable, NumJobs),
  ( NumJobs > 0
  -> builder:assign_slots(Executable, PlanStep, NumSteps, SlottedJobs, TotalLines),
     build:print_skipped_slots(SlottedJobs, NumSteps),
     builder:mark_skipped(SlottedJobs, TotalLines),
     nl,
     F1 is F0 + NumJobs,
     PlanStep1 is PlanStep + 1
  ;  F1 = F0,
     PlanStep1 = PlanStep
  ),
  builder:skip_remaining(Rest, PlanStep1, NumSteps, C0, F1, S0, C, F, S).


%! builder:mark_skipped(+SlottedJobs, +TotalLines) is det.
%
% Mark all slots in a skipped step as failed (dependency not met).

builder:mark_skipped([], _).

builder:mark_skipped([slotted(LineOff, TotalLines, PlanStep, NumSteps, ActionIdx, rule(Repo://Entry:Action?{_Ctx}, _Body), _FileInfo)|Rest], _) :-
  !,
  with_mutex(build_display,
    build:update_slot(LineOff, TotalLines, skipped, PlanStep, NumSteps, ActionIdx, Action, Repo://Entry)),
  builder:mark_skipped(Rest, TotalLines).

builder:mark_skipped([slotted(LineOff, TotalLines, PlanStep, NumSteps, ActionIdx, rule(world_action(Op, Arg):world?{_Ctx}, _Body), _FileInfo)|Rest], _) :-
  !,
  with_mutex(build_display,
    build:update_slot(LineOff, TotalLines, skipped, PlanStep, NumSteps, ActionIdx, Op, Arg)),
  builder:mark_skipped(Rest, TotalLines).

builder:mark_skipped([_|Rest], TotalLines) :-
  builder:mark_skipped(Rest, TotalLines).


%! builder:execute_step(+Step, +PlanStep, +NumSteps, +C0, +F0, +S0, -C, -F, -S, -HasJobs) is det.
%
% Execute all jobs in a step in parallel:
%   1. Extract executable rules and pre-allocate display layout
%   2. Register slot info for result handler lookups
%   3. Print all slots (with file sub-lines for downloads)
%   4. Submit all jobs to the jobserver
%   5. Collect results, updating slots in-place
%   6. Tally outcomes, clean up

builder:execute_step(Step, PlanStep, NumSteps, C0, F0, S0, C, F, S, HasJobs) :-
  plan:stable_sort_by_weight(Step, Sorted),
  include(builder:is_executable_rule, Sorted, Executable),
  length(Executable, NumJobs),
  ( NumJobs > 0
  -> HasJobs = true,
     builder:assign_slots(Executable, PlanStep, NumSteps, SlottedJobs, TotalLines),
     builder:register_slot_info(SlottedJobs),
     build:print_job_slots(SlottedJobs, NumSteps),
     jobserver:submit(SlottedJobs),
     jobserver:collect(NumJobs, builder:handle_result(TotalLines)),
     nl,
     builder:tally_outcomes(C0, F0, S0, C, F, S),
     builder:clear_slot_info
  ;  HasJobs = false,
     C = C0, F = F0, S = S0
  ).


%! builder:assign_slots(+Rules, +PlanStep, +NumSteps, -SlottedJobs, -TotalLines) is det.
%
% Pre-allocate the display layout. For download/fetchonly rules, queries
% distfile specs to determine file sub-line count. Each slotted/7 term
% carries its absolute LineOffset, plan step number, within-step action
% index (0-based), and a shared TotalLines variable (bound when the
% last rule is processed).

builder:assign_slots(Rules, PlanStep, NumSteps, SlottedJobs, TotalLines) :-
  distfiles:get_location(Distdir),
  builder:assign_slots_(Rules, PlanStep, NumSteps, Distdir, 0, 0, TotalLines, SlottedJobs).

builder:assign_slots_([], _PlanStep, _NumSteps, _Distdir, LineOff, _ActionIdx, LineOff, []).

builder:assign_slots_([Rule|Rest], PlanStep, NumSteps, Distdir, LineOff, ActionIdx, TotalLines, [Slotted|More]) :-
  builder:rule_file_info(Rule, Distdir, LineOff, FileInfo, LinesForRule),
  NextLineOff is LineOff + LinesForRule,
  Slotted = slotted(LineOff, TotalLines, PlanStep, NumSteps, ActionIdx, Rule, FileInfo),
  ActionIdx1 is ActionIdx + 1,
  builder:assign_slots_(Rest, PlanStep, NumSteps, Distdir, NextLineOff, ActionIdx1, TotalLines, More).


%! builder:rule_file_info(+Rule, +Distdir, +LineOff, -FileInfo, -Lines) is det.
%
% Determine file metadata for a rule. Downloads with distfiles get
% files(FileStartLine, NumFiles, DistFiles, Distdir); others get no_files.

builder:rule_file_info(rule(Repo://Entry:Action?{_Ctx}, _Body), _Distdir, LineOff, FileInfo, Lines) :-
  memberchk(Action, [download, fetchonly]),
  predicate_property(ebuild:is_live(_), defined),
  ebuild:is_live(Repo://Entry),
  !,
  LiveStartLine is LineOff + 1,
  FileInfo = live_source(LiveStartLine),
  Lines = 2.

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

builder:rule_file_info(rule(Repo://Entry:Action?{Ctx}, _Body), _Distdir, LineOff, SubInfo, Lines) :-
  \+ memberchk(Action, [download, fetchonly]),
  predicate_property(ebuild_exec:display_phases(_,_,_,_,_), defined),
  catch(ebuild_exec:display_phases(Action, Repo, Entry, Ctx, PhaseList), _, fail),
  PhaseList \= [],
  !,
  ExecLine is LineOff + 1,
  builder:count_conf_lines(Repo, Entry, Action, Ctx, ConfCount),
  ( predicate_property(ebuild_exec:build_log_path(_,_), defined)
  -> catch(ebuild_exec:build_log_path(Entry, LogPath), _, LogPath = '')
  ;  LogPath = ''
  ),
  ( catch(config:show_build_logs(true), _, fail)
  -> LogsLine is ExecLine + 1,
     SubInfo = phases(ExecLine, LogsLine, PhaseList, LogPath),
     Lines is 1 + ConfCount + 2
  ;  SubInfo = phases(ExecLine, -1, PhaseList, LogPath),
     Lines is 1 + ConfCount + 1
  ).

builder:rule_file_info(_, _, _, no_files, 1).


%! builder:count_conf_lines(+Repo, +Entry, +Action, +Ctx, -Count) is det.
%
% Count how many display lines plan:print_config would produce for
% this rule (USE flags, USE_EXPAND variables, slot info). Captures
% the output and counts newlines to stay consistent with the plan printer.

builder:count_conf_lines(Repo, Entry, Action, Ctx, Count) :-
  memberchk(Action, [install, update, downgrade, reinstall]),
  !,
  with_output_to(string(S),
    catch(plan:print_config(Repo://Entry:Action?{Ctx}), _, true)),
  split_string(S, "\n", "", Parts),
  length(Parts, N),
  Count is max(0, N - 1).

builder:count_conf_lines(_, _, _, _, 0).


% =============================================================================
%  Slot info registry
% =============================================================================

%! builder:register_slot_info(+SlottedJobs) is det.
%
% Store slot metadata so the result handler can look up step/action/entry
% for display without needing the original job term.

builder:register_slot_info([]).

builder:register_slot_info([slotted(LineOff, _TotalLines, PlanStep, NumSteps, ActionIdx, rule(Repo://Entry:Action?{_Ctx}, _Body), _FileInfo)|Rest]) :-
  !,
  assertz(builder:slot_info(LineOff, PlanStep, NumSteps, ActionIdx, Action, Repo://Entry)),
  builder:register_slot_info(Rest).

builder:register_slot_info([slotted(LineOff, _TotalLines, PlanStep, NumSteps, ActionIdx, rule(world_action(Op, Arg):world?{_Ctx}, _Body), _FileInfo)|Rest]) :-
  !,
  assertz(builder:slot_info(LineOff, PlanStep, NumSteps, ActionIdx, Op, Arg)),
  builder:register_slot_info(Rest).

builder:register_slot_info([_|Rest]) :-
  builder:register_slot_info(Rest).


%! builder:clear_slot_info is det.

builder:clear_slot_info :-
  retractall(builder:slot_info(_, _, _, _, _, _)),
  retractall(builder:slot_outcome(_, _)),
  retractall(builder:dl_prev_snapshot(_, _, _)),
  retractall(builder:exec_phase_state(_, _, _)).


%! builder:get_slot_info(+Slot, -PlanStep, -NumSteps, -ActionIdx, -Action, -Entry) is det.

builder:get_slot_info(Slot, PlanStep, NumSteps, ActionIdx, Action, Entry) :-
  builder:slot_info(Slot, PlanStep, NumSteps, ActionIdx, Action, Entry), !.

builder:get_slot_info(_Slot, 0, 0, 0, unknown, unknown).



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
    slotted(LineOff, TotalLines, PlanStep, NumSteps, ActionIdx, rule(Repo://Entry:Action?{Ctx}, _Body), FileInfo),
    _WorkerSlot, result(LineOff, ResultOutcome)) :-
  !,
  with_mutex(build_display,
    build:update_slot(LineOff, TotalLines, active, PlanStep, NumSteps, ActionIdx, Action, Repo://Entry)),
  ( FileInfo = live_source(LiveStartLine)
  -> with_mutex(build_display,
       build:update_live_subslot(0, LiveStartLine, TotalLines, done)),
     with_mutex(build_display,
       build:update_slot(LineOff, TotalLines, done, PlanStep, NumSteps, ActionIdx, Action, Repo://Entry)),
     ResultOutcome = display_handled(done)
  ;  FileInfo = files(FileStartLine, _NumFiles, DistFiles, Distdir)
  -> builder:run_download_parallel(Repo, Entry, Ctx, LineOff, TotalLines, PlanStep, NumSteps, ActionIdx, Action,
                                    FileStartLine, DistFiles, Distdir, Outcome),
     ResultOutcome = display_handled(Outcome)
  ;  memberchk(Action, [download, fetchonly])
  -> with_mutex(build_display,
       build:update_slot(LineOff, TotalLines, done, PlanStep, NumSteps, ActionIdx, Action, Repo://Entry)),
     ResultOutcome = display_handled(done)
  ;  FileInfo = phases(ExecLine, LogsLine, PhaseList, LogPath)
  -> builder:run_action_with_phases(Action, Repo, Entry, Ctx,
                                     TotalLines, ExecLine, LogsLine, PhaseList, LogPath,
                                     LineOff, PlanStep, NumSteps, ActionIdx, Outcome),
     ResultOutcome = display_handled(Outcome)
  ;  builder:run_action(Action, Repo, Entry, Ctx, Outcome),
     ResultOutcome = Outcome
  ),
  builder:dispatch_suggestions(Ctx).

builder:execute_build_job(
    slotted(LineOff, TotalLines, PlanStep, NumSteps, ActionIdx, rule(world_action(Op, Arg):world?{_Ctx}, _Body), _FileInfo),
    _WorkerSlot, result(LineOff, display_handled(done))) :-
  !,
  builder:execute_world_action(Op, Arg),
  with_mutex(build_display,
    build:update_slot(LineOff, TotalLines, done, PlanStep, NumSteps, ActionIdx, Op, Arg)).

builder:execute_build_job(_, _WorkerSlot, result(0, stub)).


%! builder:run_action(+Action, +Repo, +Entry, +Ctx, -Outcome) is det.
%
% Execute a non-download action. Downloads are handled by
% run_download_parallel via execute_build_job.
%
% Dispatches to ebuild_exec for real builds when config:build_live_phases
% is non-empty. Falls back to stub when fully stubbed or ebuild_exec
% is unavailable.

builder:run_action(Action, Repo, Entry, Ctx, Outcome) :-
  config:build_live_phases(LP), LP \= [],
  predicate_property(ebuild_exec:execute(_,_,_,_,_), defined),
  !,
  ebuild_exec:execute(Action, Repo, Entry, Ctx, Outcome).

builder:run_action(_Action, _Repo, _Entry, _Ctx, stub).


%! builder:run_action_with_phases(+Action, +Repo, +Entry, +Ctx, +TotalLines, +ExecLine, +LogsLine, +PhaseList, +LogPath, +LineOff, +PlanStep, +NumSteps, +ActionIdx, -Outcome) is det.
%
% Execute a build action with inline phase progress tracking.
% Uses a single exec line with arrow-separated phases and a logs line below.

builder:run_action_with_phases(Action, Repo, Entry, Ctx,
                                TotalLines, ExecLine, LogsLine, PhaseList, LogPath,
                                LineOff, PlanStep, NumSteps, ActionIdx, Outcome) :-
  config:build_live_phases(LP), LP \= [],
  predicate_property(ebuild_exec:execute_with_progress(_,_,_,_,_,_), defined),
  !,
  builder:init_exec_phase_state(ExecLine, PhaseList),
  Callback = builder:phase_callback(TotalLines, ExecLine, LogsLine, Action, PhaseList, LogPath),
  ebuild_exec:execute_with_progress(Action, Repo, Entry, Ctx, Callback, Outcome),
  builder:outcome_to_status(Outcome, FinalStatus),
  builder:clear_exec_phase_state(ExecLine),
  ( LogsLine >= 0
  -> with_mutex(build_display,
       build:update_logs_line(LogsLine, TotalLines, LogPath, FinalStatus))
  ;  true
  ),
  with_mutex(build_display,
    build:update_slot(LineOff, TotalLines, FinalStatus, PlanStep, NumSteps, ActionIdx, Action, Repo://Entry)).

builder:run_action_with_phases(Action, Repo, Entry, _Ctx,
                                TotalLines, ExecLine, LogsLine, PhaseList, LogPath,
                                LineOff, PlanStep, NumSteps, ActionIdx, stub) :-
  builder:stub_all_phases(Action, PhaseList, TotalLines, ExecLine, LogsLine, LogPath),
  with_mutex(build_display,
    build:update_slot(LineOff, TotalLines, stub, PlanStep, NumSteps, ActionIdx, Action, Repo://Entry)).


%! builder:phase_callback(+TotalLines, +ExecLine, +LogsLine, +Action, +PhaseList, +LogPath, +Phase, +Status) is det.
%
% Display callback invoked by ebuild_exec for each phase transition.
% Updates the exec_phase_state facts and re-renders the inline exec line.

builder:phase_callback(TotalLines, ExecLine, LogsLine, Action, PhaseList, LogPath, Phase, Status) :-
  memberchk(Phase, PhaseList),
  !,
  ( retract(builder:exec_phase_state(ExecLine, Phase, _)) -> true ; true ),
  assertz(builder:exec_phase_state(ExecLine, Phase, Status)),
  builder:collect_phase_states(ExecLine, PhaseList, PhaseStates),
  with_mutex(build_display,
    build:update_exec_line(ExecLine, TotalLines, Action, PhaseStates)),
  ( builder:is_failure_status(Status), LogsLine >= 0
  -> with_mutex(build_display,
       build:update_logs_line(LogsLine, TotalLines, LogPath, failed))
  ;  true
  ).

builder:phase_callback(_, _, _, _, _, _, _, _).


%! builder:collect_phase_states(+ExecLine, +PhaseList, -PhaseStates) is det.
%
% Build a list of Phase-Status pairs from the dynamic exec_phase_state facts.

builder:collect_phase_states(_, [], []).

builder:collect_phase_states(ExecLine, [Phase|Rest], [Phase-Status|States]) :-
  ( builder:exec_phase_state(ExecLine, Phase, Status)
  -> true
  ;  Status = pending
  ),
  builder:collect_phase_states(ExecLine, Rest, States).


%! builder:init_exec_phase_state(+ExecLine, +PhaseList) is det.
%
% Initialize all phases as pending for a given exec line.

builder:init_exec_phase_state(_, []).

builder:init_exec_phase_state(ExecLine, [Phase|Rest]) :-
  assertz(builder:exec_phase_state(ExecLine, Phase, pending)),
  builder:init_exec_phase_state(ExecLine, Rest).


%! builder:clear_exec_phase_state(+ExecLine) is det.
%
% Remove all phase state facts for a given exec line.

builder:clear_exec_phase_state(ExecLine) :-
  retractall(builder:exec_phase_state(ExecLine, _, _)).


builder:is_failure_status(failed).
builder:is_failure_status(failed(_)).
builder:is_failure_status(failed(_, _)).


%! builder:stub_all_phases(+Action, +PhaseList, +TotalLines, +ExecLine, +LogsLine, +LogPath) is det.
%
% Mark all phases as stub and render the inline display accordingly.

builder:stub_all_phases(Action, PhaseList, TotalLines, ExecLine, LogsLine, LogPath) :-
  maplist([P, P-stub]>>true, PhaseList, PhaseStates),
  with_mutex(build_display,
    build:update_exec_line(ExecLine, TotalLines, Action, PhaseStates)),
  ( LogsLine >= 0
  -> with_mutex(build_display,
       build:update_logs_line(LogsLine, TotalLines, LogPath, stub))
  ;  true
  ).


%! builder:run_download_parallel(+Repo, +Entry, +Ctx, +LineOff, +TotalLines, +PlanStep, +NumSteps, +ActionIdx, +Action, +FileStartLine, +DistFiles, +Distdir, -Outcome) is det.
%
% Parallel download with per-file progress using pre-allocated layout.
% File sub-lines are already printed by print_job_slots; this predicate
% only starts async curls, polls progress in-place, and updates the
% header slot on completion.

builder:run_download_parallel(Repo, Entry, _Ctx, LineOff, TotalLines, PlanStep, NumSteps, ActionIdx, Action,
                               FileStartLine, DistFiles, Distdir, Outcome) :-
  ( \+ exists_directory(Distdir) -> make_directory_path(Distdir) ; true ),
  ( download:is_fetch_restricted(Repo, Entry)
  -> builder:handle_restricted_files(DistFiles, 0, TotalLines, FileStartLine, Distdir, MissingCount),
     ( MissingCount =:= 0
     -> FinalStatus = done, Outcome = done
     ;  FinalStatus = failed('manual fetch required'), Outcome = failed('manual fetch required')
     )
  ;  config:mirror_url(MirrorUrl),
     download:mirror_layout(Layout),
     builder:prepare_download_jobs(MirrorUrl, Layout, Distdir, DistFiles, 0, Repo, Entry, DlJobs),
     get_time(T0),
     builder:init_speed_tracking(DlJobs, T0, FileStartLine),
     builder:poll_download_loop(DlJobs, TotalLines, FileStartLine, Distdir, FailCount),
     ( FailCount =:= 0
     -> FinalStatus = done, Outcome = done
     ;  FinalStatus = failed('download errors'), Outcome = failed('download errors')
     )
  ),
  with_mutex(build_display,
    build:update_slot(LineOff, TotalLines, FinalStatus, PlanStep, NumSteps, ActionIdx, Action, Repo://Entry)).


% =============================================================================
%  Parallel download helpers
% =============================================================================

%! builder:prepare_download_jobs(+MirrorUrl, +Layout, +Distdir, +DistFiles, +Idx, +Repo, +Entry, -DlJobs) is det.
%
% Start async curl processes for files not already present. Returns
% dl_job/8 terms for tracking. Already-present files are skipped
% (they already show checkmarks from print_file_subslots).

builder:prepare_download_jobs(_, _, _, [], _, _, _, []).

builder:prepare_download_jobs(MirrorUrl, Layout, Distdir, [dist(Filename, Size, Pairs)|Rest], Idx, Repo, Entry, Jobs) :-
  Idx1 is Idx + 1,
  ( mirror:flat_present(Distdir, Filename)
  -> builder:prepare_download_jobs(MirrorUrl, Layout, Distdir, Rest, Idx1, Repo, Entry, Jobs)
  ;  download:mirror_download_url(MirrorUrl, Layout, Filename, URL),
     atomic_list_concat([Distdir, '/', Filename], DestPath),
     download:start_curl_async(URL, DestPath, Pid),
     Jobs = [dl_job(Pid, Idx, Filename, Size, Pairs, DestPath, Repo, Entry)|MoreJobs],
     builder:prepare_download_jobs(MirrorUrl, Layout, Distdir, Rest, Idx1, Repo, Entry, MoreJobs)
  ).


% -----------------------------------------------------------------------------
%  Speed tracking (dynamic state for per-file speed calculation)
% -----------------------------------------------------------------------------

:- dynamic builder:dl_prev_snapshot/3.

%! builder:init_speed_tracking(+DlJobs, +T0, +FileStartLine) is det.

builder:init_speed_tracking([], _, _).

builder:init_speed_tracking([dl_job(_, Idx, _, _, _, _, _, _)|Rest], T0, FileStartLine) :-
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
  Job = dl_job(Pid, FileIdx, Filename, ExpSize, Pairs, DestPath, Repo, Entry),
  ( download:check_process_done(Pid, ExitCode)
  -> builder:finalize_download(ExitCode, FileIdx, Filename, ExpSize, Pairs, DestPath, Repo, Entry,
                                TotalLines, FileStartLine, Distdir, OK),
     builder:poll_all_jobs(Rest, TotalLines, FileStartLine, Distdir, StillActive, RestFails),
     ( OK == true -> Fails = RestFails ; Fails is RestFails + 1 )
  ;  builder:update_download_progress(FileIdx, Filename, ExpSize, DestPath,
                                       TotalLines, FileStartLine, Distdir),
     StillActive = [Job|MoreActive],
     builder:poll_all_jobs(Rest, TotalLines, FileStartLine, Distdir, MoreActive, Fails)
  ).


%! builder:finalize_download(+ExitCode, +FileIdx, +Filename, +ExpSize, +Pairs, +DestPath, +Repo, +Entry, +TotalLines, +FileStartLine, +Distdir, -OK) is det.
%
% Called when a curl process exits. Verifies size and hashes,
% updates the file sub-slot to done or failed. On mirror failure,
% attempts an upstream SRC_URI fallback before giving up.

builder:finalize_download(ExitCode, FileIdx, Filename, ExpSize, Pairs, DestPath, Repo, Entry,
                           TotalLines, FileStartLine, Distdir, OK) :-
  ( ExitCode =:= 0,
    download:verify_size(DestPath, ExpSize),
    download:verify_hashes(DestPath, Pairs)
  -> OK = true,
     with_mutex(build_display,
       build:update_file_subslot(FileIdx, FileStartLine, TotalLines, done, Filename, ExpSize, Distdir))
  ;  catch(delete_file(DestPath), _, true),
     builder:try_upstream_fallback(FileIdx, Filename, ExpSize, Pairs, DestPath, Repo, Entry,
                                    TotalLines, FileStartLine, Distdir, OK)
  ).


%! builder:try_upstream_fallback(+FileIdx, +Filename, +ExpSize, +Pairs, +DestPath, +Repo, +Entry, +TotalLines, +FileStartLine, +Distdir, -OK) is det.
%
% Attempts to download a distfile directly from its upstream SRC_URI
% when the mirror download has failed.

builder:try_upstream_fallback(FileIdx, Filename, ExpSize, Pairs, DestPath, Repo, Entry,
                               TotalLines, FileStartLine, Distdir, OK) :-
  ( download:upstream_url(Repo, Entry, Filename, UpstreamURL)
  -> with_mutex(build_display,
       build:update_file_subslot(FileIdx, FileStartLine, TotalLines, progress(0, 0), Filename, ExpSize, Distdir)),
     download:curl_download(UpstreamURL, DestPath, FallbackExit),
     ( FallbackExit =:= 0,
       download:verify_size(DestPath, ExpSize),
       download:verify_hashes(DestPath, Pairs)
     -> OK = true,
        with_mutex(build_display,
          build:update_file_subslot(FileIdx, FileStartLine, TotalLines, done, Filename, ExpSize, Distdir))
     ;  catch(delete_file(DestPath), _, true),
        OK = false,
        with_mutex(build_display,
          build:update_file_subslot(FileIdx, FileStartLine, TotalLines, failed, Filename, ExpSize, Distdir))
     )
  ;  OK = false,
     with_mutex(build_display,
       build:update_file_subslot(FileIdx, FileStartLine, TotalLines, failed, Filename, ExpSize, Distdir))
  ).


% -----------------------------------------------------------------------------
%  RESTRICT=fetch handling
% -----------------------------------------------------------------------------

%! builder:handle_restricted_files(+DistFiles, +Idx, +TotalLines, +FileStartLine, +Distdir, -MissingCount) is det.
%
% For fetch-restricted ebuilds, checks each distfile: present files get
% a green checkmark, missing files get a yellow "manual fetch required" marker.

builder:handle_restricted_files([], _, _, _, _, 0).

builder:handle_restricted_files([dist(Filename, Size, _)|Rest], Idx, TotalLines, FileStartLine, Distdir, MissingCount) :-
  Idx1 is Idx + 1,
  ( mirror:flat_present(Distdir, Filename)
  -> with_mutex(build_display,
       build:update_file_subslot(Idx, FileStartLine, TotalLines, done, Filename, Size, Distdir)),
     builder:handle_restricted_files(Rest, Idx1, TotalLines, FileStartLine, Distdir, MissingCount)
  ;  with_mutex(build_display,
       build:update_file_subslot(Idx, FileStartLine, TotalLines, restricted, Filename, Size, Distdir)),
     builder:handle_restricted_files(Rest, Idx1, TotalLines, FileStartLine, Distdir, RestMissing),
     MissingCount is RestMissing + 1
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
  builder:get_slot_info(LineOff, PlanStep, NumSteps, ActionIdx, Action, Entry),
  builder:outcome_to_status(Outcome, Status),
  with_mutex(build_display,
    build:update_slot(LineOff, TotalLines, Status, PlanStep, NumSteps, ActionIdx, Action, Entry)).


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


% =============================================================================
%  World action execution (stubs)
% =============================================================================

%! builder:execute_world_action(+Op, +Arg) is det.
%
% Stub for world set modifications. Currently a no-op; future
% implementation will call world:register/1 or world:unregister/1.

builder:execute_world_action(register, _Arg).
builder:execute_world_action(unregister, _Arg).


% =============================================================================
%  Suggestion dispatch (stubs)
% =============================================================================

%! builder:dispatch_suggestions(+Ctx) is det.
%
% Extracts suggestion tags from a rule's context and dispatches them
% to stub handlers. Currently no-ops; future implementation will
% write to /etc/portage/package.{unmask,accept_keywords,use}.

builder:dispatch_suggestions(Ctx) :-
  is_list(Ctx), !,
  ( memberchk(suggestion(unmask, Repo://Entry), Ctx)
  -> builder:execute_suggestion(unmask, Repo, Entry)
  ;  true
  ),
  ( memberchk(suggestion(accept_keyword, Kw), Ctx)
  -> builder:execute_suggestion(accept_keyword, Kw)
  ;  true
  ),
  ( memberchk(suggestion(use_change, Repo://Entry, Changes), Ctx)
  -> builder:execute_suggestion(use_change, Repo, Entry, Changes)
  ;  true
  ).

builder:dispatch_suggestions(_).


%! builder:execute_suggestion(+Type, ...) is det.
%
% Stub predicates for suggestion execution. Each will eventually
% write to the corresponding /etc/portage/package.* file.

builder:execute_suggestion(unmask, _Repo, _Entry).
builder:execute_suggestion(accept_keyword, _Kw).
builder:execute_suggestion(use_change, _Repo, _Entry, _Changes).


% =============================================================================
%  Builder test stats (whole-repo and targeted)
% =============================================================================

%! builder:test_stats(+Repository) is det.
%
% Run a builder test across the entire repository: for each entry,
% prove a plan, download distfiles, and run safe build phases.
% Uses tester:test for parallel iteration with progress.

builder:test_stats(Repository) :-
  config:test_style(Style),
  builder:test_stats(Repository, Style).


%! builder:test_stats(+Repository, +StyleOrTopN) is det.

builder:test_stats(Repository, TopN) :-
  integer(TopN), !,
  config:test_style(Style),
  builder:test_stats(Repository, Style, TopN).

builder:test_stats(Repository, Style) :-
  ( config:test_stats_top_n(TopN) -> true ; TopN = 25 ),
  builder:test_stats(Repository, Style, TopN).


%! builder:test_stats(+Repository, +Style, +TopN) is det.
%
% Core test loop: for each entry, prove plan, download distfiles,
% run safe phases. Failure at any stage is recorded via the sampler.

builder:test_stats(Repository, Style, TopN) :-
  aggregate_all(count, (Repository:entry(_E)), ExpectedTotal),
  sampler:test_stats_reset('Building', ExpectedTotal),
  aggregate_all(count, (Repository:package(_C,_N)), ExpectedPkgs),
  sampler:test_stats_set_expected_unique_packages(ExpectedPkgs),
  tester:test(Style,
              'Building',
              Repository://Entry,
              Repository:entry(Entry),
              builder:test_single(Repository, Entry)),
  stats:test_stats_print(TopN).


%! builder:test_stats_pkgs(+Repository, +Pkgs) is det.
%
% Run builder test for a specific list of packages (C-N pairs).

builder:test_stats_pkgs(Repository, Pkgs) :-
  config:test_style(Style),
  ( config:test_stats_top_n(TopN) -> true ; TopN = 25 ),
  builder:test_stats_pkgs(Repository, Style, TopN, Pkgs).


%! builder:test_stats_pkgs(+Repository, +Style, +TopN, +Pkgs) is det.

builder:test_stats_pkgs(Repository, Style, TopN, Pkgs) :-
  is_list(Pkgs),
  length(Pkgs, ExpectedTotal),
  sampler:test_stats_reset('Building', ExpectedTotal),
  sampler:test_stats_set_expected_unique_packages(ExpectedTotal),
  tester:test(Style,
              'Building',
              Repository://Entry,
              ( member(C-N, Pkgs),
                once(Repository:ebuild(Entry, C, N, _))
              ),
              builder:test_single(Repository, Entry)),
  stats:test_stats_print(TopN).


% =============================================================================
%  Per-entry test (prove + download + safe phases)
% =============================================================================

%! builder:test_single(+Repository, +Entry) is det.
%
% Test a single entry end-to-end without display:
%   1. Prove plan (with keyword/unmask fallback)
%   2. Download distfiles (skips already-present, verifies hashes)
%   3. Run safe build phases via ebuild_exec
%
% Succeeds if all steps complete, otherwise records failure via sampler
% and succeeds (tester:test handles outer error classification).

builder:test_single(Repository, Entry) :-
  sampler:test_stats_reset_counters,
  statistics(inferences, I0),
  statistics(walltime, [T0, _]),
  Goals = [Repository://Entry:run?{[]}],
  ( ( pipeline:prove_plan(Goals, _Proof, _Model, Plan, _Triggers)
    ; prover:assuming(keyword_acceptance,
        prover:assuming(unmask,
          pipeline:prove_plan(Goals, _Proof2, _Model2, Plan, _Triggers2)))
    )
  -> catch(builder:test_plan_downloads(Plan), DlErr,
       with_mutex(mutex,
         (term_to_atom(DlErr, DA), message:warning([Entry, ' download error: ', DA])))),
     catch(builder:test_plan_phases(Plan), PhErr,
       with_mutex(mutex,
         (term_to_atom(PhErr, PA), message:warning([Entry, ' build error: ', PA])))),
     statistics(walltime, [T1, _]),
     statistics(inferences, I1),
     TimeMs is T1 - T0,
     Inferences is I1 - I0,
     sampler:test_stats_get_counters(rule_calls(RuleCalls)),
     sampler:test_stats_record_costs(Repository://Entry, TimeMs, Inferences, RuleCalls)
  ;  ( current_predicate(sampler:test_stats_record_failed/1)
     -> sampler:test_stats_record_failed(other)
     ;  true
     )
  ).


%! builder:test_plan_downloads(+Plan) is det.
%
% Walk the plan and download distfiles for all download/fetchonly rules.
% Uses download:fetch_distfiles/4 which handles mirror URLs, fallback,
% hash verification, and skipping already-present files.

builder:test_plan_downloads([]).

builder:test_plan_downloads([Step|Rest]) :-
  builder:test_step_downloads(Step),
  builder:test_plan_downloads(Rest).


%! builder:test_step_downloads(+Step) is det.

builder:test_step_downloads([]).

builder:test_step_downloads([Rule|Rest]) :-
  ( Rule = rule(Head, _Body),
    prover:canon_literal(Head, Core, Ctx),
    Core = Repo://Entry:Action,
    memberchk(Action, [download, fetchonly]),
    \+ download:is_fetch_restricted(Repo, Entry),
    ( predicate_property(ebuild:is_live(_), defined) -> \+ ebuild:is_live(Repo://Entry) ; true )
  -> ( download:fetch_distfiles(Repo, Entry, Ctx, Failures),
       ( Failures == [] -> true
       ; term_to_atom(Failures, FA),
         with_mutex(mutex, message:warning([Entry, ' download failures: ', FA]))
       )
     ; true
     )
  ;  true
  ),
  builder:test_step_downloads(Rest).


%! builder:test_plan_phases(+Plan) is det.
%
% Walk the plan and execute safe build phases for all non-download rules.
% Uses ebuild_exec:execute/5 when config:build_live_phases is non-empty.

builder:test_plan_phases([]).

builder:test_plan_phases([Step|Rest]) :-
  builder:test_step_phases(Step),
  builder:test_plan_phases(Rest).


%! builder:test_step_phases(+Step) is det.

builder:test_step_phases([]).

builder:test_step_phases([Rule|Rest]) :-
  ( Rule = rule(Head, _Body),
    prover:canon_literal(Head, Core, Ctx),
    Core = Repo://Entry:Action,
    \+ memberchk(Action, [download, fetchonly])
  -> ( config:build_live_phases(LP), LP \= [],
       predicate_property(ebuild_exec:execute(_,_,_,_,_), defined)
     -> ( ebuild_exec:execute(Action, Repo, Entry, Ctx, Outcome),
          ( Outcome == done -> true
          ; term_to_atom(Outcome, OA),
            with_mutex(mutex, message:warning([Entry, ' build phase outcome: ', OA]))
          )
        ; true
        )
     ;  true
     )
  ;  true
  ),
  builder:test_step_phases(Rest).
