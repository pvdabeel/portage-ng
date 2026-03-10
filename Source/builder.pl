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
:- dynamic builder:resume_done/2.

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
  ( builder:ask_confirmation
  -> true
  ;  message:inform('Aborted.'),
     !,
     fail
  ),
  builder:maybe_create_snapshot(Plan),
  retractall(builder:resume_done(_, _)),
  builder:save_resume_state(Goals, Plan),
  plan:collect_plan_pre_actions(ProofAVL, PreActions),
  builder:count_actions(Plan, 0, PlanActions),
  length(PreActions, PreCount),
  ( PreCount > 0 -> PreSteps = 1 ; PreSteps = 0 ),
  TotalActions is PlanActions + PreCount,
  builder:count_nonempty_steps(Plan, 0, PlanSteps),
  NumSteps is PlanSteps + PreSteps,
  build:header(NumSteps, TotalActions),
  builder:print_pre_action_step(PreActions, PreSteps),
  StartStep is PreSteps + 1,
  builder:num_workers(NumWorkers),
  jobserver:init(NumWorkers, builder:execute_build_job),
  builder:execute_plan(Plan, StartStep, NumSteps, 0, 0, 0, Completed, Failed, Stubs),
  jobserver:shutdown(NumWorkers),
  snapshot:finalize,
  ( Failed =:= 0
  -> builder:clear_resume_state
  ;  true
  ),
  build:summary(Completed, Failed, Stubs),
  builder:alert.


%! builder:build_resume is det.
%
% Resumes a previously interrupted build. Loads the saved plan from
% Knowledge/resume.pl, filters out completed packages, and re-executes
% the remainder. Skips the clean phase so ebuild can pick up from the
% preserved work directory.

builder:build_resume :-
  ( builder:load_resume_state(_Goals, Plan, DoneList)
  -> true
  ;  message:failure('No saved build state found. Run --build first.'),
     !,
     fail
  ),
  builder:collect_skip_entries(Plan, SkipDone),
  append(DoneList, SkipDone, AllDone),
  builder:filter_completed_plan(Plan, AllDone, FilteredPlan),
  builder:count_actions(FilteredPlan, 0, RemainingActions),
  ( RemainingActions =:= 0
  -> message:inform('Nothing to resume — all packages completed successfully.'),
     builder:clear_resume_state
  ;  length(DoneList, CompletedCount),
     format(atom(ResumeMsg), '>>> Resuming: ~d completed, ~d remaining', [CompletedCount, RemainingActions]),
     message:color(green),
     message:print(ResumeMsg),
     message:reset,
     nl, nl,
     assertz(ebuild_exec:resuming),
     retractall(builder:resume_done(_, _)),
     builder:count_nonempty_steps(FilteredPlan, 0, NumSteps),
     build:header(NumSteps, RemainingActions),
     builder:num_workers(NumWorkers),
     jobserver:init(NumWorkers, builder:execute_build_job),
     builder:execute_plan(FilteredPlan, 1, NumSteps, 0, 0, 0, Completed, Failed, Stubs),
     jobserver:shutdown(NumWorkers),
     ( Failed =:= 0
     -> builder:clear_resume_state
     ;  true
     ),
     build:summary(Completed, Failed, Stubs),
     builder:alert,
     retractall(ebuild_exec:resuming)
  ).


%! builder:alert is det.
%
% When --alert is active, rings the terminal bell to attract attention.

builder:alert :-
  ( preference:flag(alert)
  -> message:bell
  ;  true
  ).


%! builder:ask_confirmation is semidet.
%
% When --ask is active, prompts the user to confirm before proceeding.
% Succeeds immediately if --ask is not set. Fails if the user declines.

builder:ask_confirmation :-
  ( preference:flag(ask)
  -> ( preference:flag(readnews)
     -> catch(news:check, _, true), nl
     ;  true
     ),
     builder:alert,
     nl,
     message:print('Would you like to merge these packages? [Yes/No] '),
     flush_output,
     read_line_to_string(current_input, Answer),
     ( member(Answer, ["Yes", "yes", "Y", "y", ""])
     -> true
     ;  false
     )
  ;  true
  ).


%! builder:num_workers(-N) is det.
%
% Compute the number of worker threads: min(cpu_count, available_display_lines).
% When --jobs N is specified and N > 0, uses that value instead.

builder:num_workers(N) :-
  ( config:cli_jobs(J)
  -> N = J
  ;  config:number_of_cpus(Cpus),
     config:printing_tty_size(H, _W),
     ReservedLines = 6,
     MaxDisplay is max(1, H - ReservedLines),
     N is min(Cpus, MaxDisplay)
  ).


% =============================================================================
%  Pre-action steps (keyword/unmask/use_change)
% =============================================================================

%! builder:print_pre_action_step(+PreActions, +PreSteps) is det.
%
% Renders pre-actions (keyword acceptance, unmask, use flag changes) as
% a completed step in the build display, matching the plan printer's
% format. These are informational — the prover already assumed them.

builder:print_pre_action_step([], _) :- !.

builder:print_pre_action_step(PreActions, _PreSteps) :-
  format(atom(AtomStepNum), '~t~0f~2|', [1]),
  format(atom(StepLabel), 'step ~a', [AtomStepNum]),
  write(' \u2514\u2500'),
  message:bubble(darkgray, StepLabel),
  write('\u2500\u2524 '),
  builder:print_pre_actions(PreActions),
  nl, nl.


%! builder:print_pre_actions(+PreActions) is det.

builder:print_pre_actions([Action]) :-
  !,
  builder:print_pre_action(Action),
  build:right_edge_ok.

builder:print_pre_actions([Action|Rest]) :-
  builder:print_pre_action(Action),
  build:right_edge_ok,
  forall(member(A, Rest),
         ( nl,
           write('             \u2502 '),
           builder:print_pre_action(A),
           build:right_edge_ok
         )).


%! builder:print_pre_action(+PreAction) is det.

builder:print_pre_action(unmask(R, E, _C, _N)) :-
  message:bubble(orange, unmask),
  message:color(green),
  message:column(24, R://E),
  message:color(normal).

builder:print_pre_action(accept_keyword(R, E, _C, _N, K)) :-
  warning:keyword_atom(K, KAtom),
  message:bubble(orange, keyword),
  message:color(green),
  message:column(24, R://E),
  message:color(darkgray),
  format(atom(Msg), ' (~w)', [KAtom]),
  message:print(Msg),
  message:color(normal).

builder:print_pre_action(use_change(R, E, _C, _N, _Changes)) :-
  message:bubble(orange, useflag),
  message:color(green),
  message:column(24, R://E),
  message:color(normal).


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
  builder:flush_resume_done_to_disk,
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
  builder:maybe_quickpkg_old(Action, Ctx),
  ( FileInfo = live_source(LiveStartLine)
  -> builder:run_git_download(Repo, Entry, LiveStartLine, TotalLines,
                               LineOff, PlanStep, NumSteps, ActionIdx, Action, Outcome),
     ResultOutcome = display_handled(Outcome)
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


%! builder:run_git_download(+Repo, +Entry, +LiveStartLine, +TotalLines, +LineOff, +PlanStep, +NumSteps, +ActionIdx, +Action, -Outcome) is det.
%
% Clones or fetches a live ebuild's git repository with progress tracking.
% Extracts EGIT_REPO_URI from the ebuild, uses the distdir/git3-src cache
% (matching Portage's git-r3.eclass convention), and polls for progress.

builder:run_git_download(Repo, Entry, LiveStartLine, TotalLines,
                          LineOff, PlanStep, NumSteps, ActionIdx, Action, Outcome) :-
  ( download:extract_git_uri(Repo, Entry, URI)
  -> distfiles:get_location(Distdir),
     download:git_cache_dir(Distdir, GitCacheDir),
     ( \+ exists_directory(GitCacheDir) -> make_directory_path(GitCacheDir) ; true ),
     download:git_repo_cache_path(GitCacheDir, URI, RepoPath),
     ebuild_exec:build_log_path(Entry, LogPath),
     ebuild_exec:ensure_log_dir,
     Callback = builder:git_progress_callback(LiveStartLine, TotalLines),
     download:start_git_clone_async(URI, RepoPath, LogPath, Pid),
     download:poll_git_progress(Pid, LogPath, Callback, ExitCode),
     ( ExitCode =:= 0
     -> with_mutex(build_display,
          build:update_live_subslot(0, LiveStartLine, TotalLines, done)),
        with_mutex(build_display,
          build:update_slot(LineOff, TotalLines, done, PlanStep, NumSteps, ActionIdx, Action, Repo://Entry)),
        Outcome = done
     ;  with_mutex(build_display,
          build:update_live_subslot(0, LiveStartLine, TotalLines, failed)),
        with_mutex(build_display,
          build:update_slot(LineOff, TotalLines, failed(git), PlanStep, NumSteps, ActionIdx, Action, Repo://Entry)),
        Outcome = failed(git)
     )
  ;  with_mutex(build_display,
       build:update_live_subslot(0, LiveStartLine, TotalLines, done)),
     with_mutex(build_display,
       build:update_slot(LineOff, TotalLines, done, PlanStep, NumSteps, ActionIdx, Action, Repo://Entry)),
     Outcome = done
  ).


%! builder:git_progress_callback(+LiveStartLine, +TotalLines, +Phase, +Status) is det.
%
% Updates the live sub-slot display with git clone/fetch progress.

builder:git_progress_callback(LiveStartLine, TotalLines, _Phase, progress(Pct)) :-
  with_mutex(build_display,
    build:update_live_subslot(0, LiveStartLine, TotalLines, progress(Pct))).

builder:git_progress_callback(_, _, _, _).


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
  assertz(builder:slot_outcome(LineOff, Outcome)),
  builder:maybe_record_resume_done(LineOff, Outcome).

builder:handle_result(TotalLines, LineOff, Outcome) :-
  assertz(builder:slot_outcome(LineOff, Outcome)),
  builder:get_slot_info(LineOff, PlanStep, NumSteps, ActionIdx, Action, Entry),
  builder:outcome_to_status(Outcome, Status),
  with_mutex(build_display,
    build:update_slot(LineOff, TotalLines, Status, PlanStep, NumSteps, ActionIdx, Action, Entry)),
  builder:maybe_record_resume_done(LineOff, Outcome).


%! builder:maybe_record_resume_done(+LineOff, +Outcome) is det.
%
% Records a completed entry for resume tracking. Only records
% repository entries (Repo://Entry pattern) with done outcome.

builder:maybe_record_resume_done(LineOff, Outcome) :-
  ( Outcome == done,
    builder:slot_info(LineOff, _, _, _, Action, Entry),
    Entry = _://_
  -> assertz(builder:resume_done(Entry, Action))
  ;  true
  ).


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
%  Resume state management
% =============================================================================

%! builder:resume_state_file(-Path) is det.
%
% Returns the path to the resume state file (Knowledge/resume.pl).

builder:resume_state_file(Path) :-
  config:installation_dir(Dir),
  os:compose_path([Dir, 'Knowledge', 'resume.pl'], Path).


%! builder:save_resume_state(+Goals, +Plan) is det.
%
% Saves the build goals and plan to Knowledge/resume.pl. This is
% called at the start of a --build run so the plan can be loaded
% later by --resume.

builder:save_resume_state(Goals, Plan) :-
  builder:resume_state_file(Path),
  catch(
    setup_call_cleanup(
      open(Path, write, S),
      ( write_term(S, resume_goals(Goals), [quoted(true)]),
        format(S, '.~n', []),
        write_term(S, resume_plan(Plan), [quoted(true)]),
        format(S, '.~n', [])
      ),
      close(S)),
    _, true).


%! builder:flush_resume_done_to_disk is det.
%
% Appends any in-memory resume_done/2 facts to the resume state file,
% then retracts them. Called after each plan step for crash safety.

builder:flush_resume_done_to_disk :-
  builder:resume_state_file(Path),
  ( exists_file(Path)
  -> findall(E-A, builder:resume_done(E, A), Entries),
     ( Entries \= []
     -> catch(
          setup_call_cleanup(
            open(Path, append, S),
            forall(
              member(E-A, Entries),
              ( write_term(S, resume_done(E, A), [quoted(true)]),
                format(S, '.~n', [])
              )
            ),
            close(S)),
          _, true),
        retractall(builder:resume_done(_, _))
     ;  true
     )
  ;  true
  ).


%! builder:load_resume_state(-Goals, -Plan, -DoneList) is semidet.
%
% Loads the resume state from Knowledge/resume.pl. Returns the
% original goals, plan, and a list of done(Entry, Action) terms
% for entries that already completed. Fails if no resume file exists.

builder:load_resume_state(Goals, Plan, DoneList) :-
  builder:resume_state_file(Path),
  exists_file(Path),
  catch(
    setup_call_cleanup(
      open(Path, read, S),
      builder:read_all_resume_terms(S, Terms),
      close(S)),
    _, fail),
  ( memberchk(resume_goals(Goals), Terms) -> true ; Goals = [] ),
  ( memberchk(resume_plan(Plan), Terms) -> true ; Plan = [] ),
  findall(done(E, A), member(resume_done(E, A), Terms), DoneList).


%! builder:read_all_resume_terms(+Stream, -Terms) is det.
%
% Reads all Prolog terms from a stream until end_of_file.

builder:read_all_resume_terms(S, Terms) :-
  read_term(S, T, []),
  ( T == end_of_file
  -> Terms = []
  ;  Terms = [T|Rest],
     builder:read_all_resume_terms(S, Rest)
  ).


%! builder:clear_resume_state is det.
%
% Deletes the resume state file after a successful build.

builder:clear_resume_state :-
  builder:resume_state_file(Path),
  ( exists_file(Path) -> delete_file(Path) ; true ).


%! builder:filter_completed_plan(+Plan, +DoneList, -FilteredPlan) is det.
%
% Removes completed rules from each step in the plan. A rule is
% considered completed if its Entry and Action appear in DoneList.

builder:filter_completed_plan([], _, []).

builder:filter_completed_plan([Step|Rest], DoneList, [Filtered|FilteredRest]) :-
  exclude(builder:rule_is_done(DoneList), Step, Filtered),
  builder:filter_completed_plan(Rest, DoneList, FilteredRest).


%! builder:rule_is_done(+DoneList, +Rule) is semidet.
%
% True if the rule's package and action appear in the done list.

builder:rule_is_done(DoneList, rule(Repo://Entry:Action?{_Ctx}, _Body)) :-
  memberchk(done(Repo://Entry, Action), DoneList).


%! builder:collect_skip_entries(+Plan, -SkipDone) is det.
%
% Collects done/2 entries for rules whose Entry matches any
% config:skip_atom/1 fact. Matches by sub_atom so the user can
% specify a qualified name like dev-lang/python-3.12.0 and it
% will match the full Entry atom in the plan.

builder:collect_skip_entries(Plan, SkipDone) :-
  findall(done(Repo://Entry, Action),
    ( member(Step, Plan),
      member(rule(Repo://Entry:Action?{_Ctx}, _Body), Step),
      config:skip_atom(Skip),
      sub_atom(Entry, _, _, _, Skip)
    ),
    SkipDone).


% =============================================================================
%  Snapshot integration
% =============================================================================

%! builder:maybe_create_snapshot(+Plan) is det.
%
% If --snapshot is active (snapshot:active_id/1 has been asserted by
% interface dispatch), creates a snapshot before the build begins.

builder:maybe_create_snapshot(Plan) :-
  ( snapshot:active_id(Id)
  -> snapshot:create(Id, Plan)
  ;  true
  ).


%! builder:maybe_quickpkg_old(+Action, +Ctx) is det.
%
% When a snapshot is active and the action replaces an installed
% package, quickpkg the old version before the merge phase overwrites it.

builder:maybe_quickpkg_old(Action, Ctx) :-
  snapshot:active_id(_),
  memberchk(Action, [install, update, downgrade, reinstall]),
  memberchk(replaces(OldRepo://OldEntry), Ctx),
  !,
  snapshot:quickpkg_old(OldRepo, OldEntry).

builder:maybe_quickpkg_old(_, _).


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
