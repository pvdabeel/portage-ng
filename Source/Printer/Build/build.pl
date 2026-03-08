/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> BUILD
Build execution progress rendering.

Displays live progress during plan execution using a slot-based display.
Each job in a step gets a display slot (a terminal line). Workers and
the controller update slots in-place via ANSI cursor movement, all
guarded by with_mutex(build_display, ...) for thread safety.

Architecture mirror of Source/Printer/Plan/plan.pl — this module handles
the display side of builder execution, while builder.pl handles orchestration.
*/

:- module(build, []).

% =============================================================================
%  Right-edge indicator helpers
% =============================================================================

%! build:right_edge_ok is det.
%
% Print a green checkmark at the right edge of the terminal (1 space in).

build:right_edge_ok :-
  config:printing_tty_size(_, W),
  Col is W - 1,
  format("\e[~dG", [Col]),
  message:color(green),
  message:print('\u2713'),
  message:color(normal).


%! build:right_edge_fail is det.
%
% Print a red bold exclamation at the right edge of the terminal.

build:right_edge_fail :-
  config:printing_tty_size(_, W),
  Col is W - 1,
  format("\e[~dG", [Col]),
  message:color(red),
  message:style(bold),
  message:print('!'),
  message:style(normal),
  message:color(normal).


%! build:right_edge_spinner(+Tick) is det.
%
% Print a gray spinner at the right edge using the quarter-circle style.

build:right_edge_spinner(Tick) :-
  config:printing_tty_size(_, W),
  Col is W - 1,
  format("\e[~dG", [Col]),
  message:spinner_frame(braille, Tick, Frame),
  message:color(darkgray),
  message:print(Frame),
  message:color(normal).


% =============================================================================
%  BUILD declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Header
% -----------------------------------------------------------------------------

%! build:header(+NumSteps, +TotalActions) is det.
%
% Print the progress header, matching the plan's footer style.

build:header(NumSteps, TotalActions) :-
  message:color(green),
  message:print('Progress merging the packages:'),
  message:color(normal),
  nl, nl,
  ( TotalActions =:= 1 -> AWord = action ; AWord = actions ),
  ( NumSteps =:= 1 -> SWord = step ; SWord = steps ),
  format('Executing ~d ~w, grouped into ~d ~w...', [TotalActions, AWord, NumSteps, SWord]),
  nl, nl.


% =============================================================================
%  Slot-based display
% =============================================================================

% -----------------------------------------------------------------------------
%  Initial slot printing
% -----------------------------------------------------------------------------

%! build:print_job_slots(+SlottedJobs, +TotalSteps) is det.
%
% Print one line per job in the step, all initially in "pending" state.
% For download actions with file metadata, also prints file sub-lines
% inline below the header. Cursor parks on a blank line below all slots.

build:print_job_slots([], _NumSteps) :- !.

build:print_job_slots([slotted(_LineOff, _TotalLines, PlanStep, NumSteps, ActionIdx, rule(Repo://Entry:Action?{Ctx}, _Body), SubInfo)|Rest], _) :-
  !,
  build:render_slot(pending, PlanStep, NumSteps, ActionIdx, Action, Repo://Entry),
  ( SubInfo = live_source(_LiveStart)
  -> nl,
     build:print_live_subslot
  ;  SubInfo = files(_FileStart, _NumFiles, DistFiles, Distdir)
  -> nl,
     build:print_file_subslots(DistFiles, Distdir)
  ;  SubInfo = phases(_ExecLine, _LogsLine, PhaseList, LogPath)
  -> nl,
     build:print_exec_and_logs(PhaseList, LogPath),
     plan:print_config(Repo://Entry:Action?{Ctx}),
     nl
  ;  nl
  ),
  build:print_job_slots(Rest, NumSteps).

build:print_job_slots([slotted(_LineOff, _TotalLines, PlanStep, NumSteps, ActionIdx, rule(world_action(Op, Arg):world?{_Ctx}, _Body), _SubInfo)|Rest], _) :-
  !,
  build:render_slot(pending, PlanStep, NumSteps, ActionIdx, Op, Arg),
  nl,
  build:print_job_slots(Rest, NumSteps).

build:print_job_slots([_|Rest], NumSteps) :-
  build:print_job_slots(Rest, NumSteps).


% -----------------------------------------------------------------------------
%  Skipped slot printing (all gray, no color)
% -----------------------------------------------------------------------------

%! build:print_skipped_slots(+SlottedJobs, +NumSteps) is det.
%
% Print slots for steps that are being skipped due to earlier failures.
% Everything is rendered in darkgray — no colored USE flags or phase names.

build:print_skipped_slots([], _) :- !.

build:print_skipped_slots([slotted(_LineOff, _TotalLines, PlanStep, NumSteps, ActionIdx, rule(Repo://Entry:Action?{Ctx}, _Body), SubInfo)|Rest], _) :-
  !,
  build:render_slot(skipped, PlanStep, NumSteps, ActionIdx, Action, Repo://Entry),
  ( SubInfo = phases(_ExecLine, _LogsLine, PhaseList, LogPath)
  -> nl,
     build:print_skipped_exec_and_logs(PhaseList, LogPath),
     build:print_skipped_conf(Repo://Entry:Action?{Ctx}),
     nl
  ;  nl
  ),
  build:print_skipped_slots(Rest, NumSteps).

build:print_skipped_slots([slotted(_LineOff, _TotalLines, PlanStep, NumSteps, ActionIdx, rule(world_action(Op, Arg):world?{_Ctx}, _Body), _SubInfo)|Rest], _) :-
  !,
  build:render_slot(skipped, PlanStep, NumSteps, ActionIdx, Op, Arg),
  nl,
  build:print_skipped_slots(Rest, NumSteps).

build:print_skipped_slots([_|Rest], NumSteps) :-
  build:print_skipped_slots(Rest, NumSteps).


%! build:print_skipped_conf(+RuleHead) is det.
%
% Print the config lines for skipped steps.
% Calls plan:print_config directly to ensure output is produced.

build:print_skipped_conf(RuleHead) :-
  catch(plan:print_config(RuleHead), _, true),
  !.
build:print_skipped_conf(_).


%! build:print_skipped_exec_and_logs(+PhaseList, +LogPath) is det.
%
% Print exec and logs lines in darkgray for skipped steps.

build:print_skipped_exec_and_logs(PhaseList, LogPath) :-
  build:exec_prefix,
  message:color(darkgray),
  build:print_skipped_phases(PhaseList),
  message:color(normal),
  ( catch(config:show_build_logs(true), _, fail)
  -> nl,
     build:logs_prefix,
     message:color(darkgray),
     message:print(LogPath),
     message:color(normal)
  ;  true
  ).

build:print_skipped_phases([]).
build:print_skipped_phases([Phase]) :-
  !,
  message:print(Phase).
build:print_skipped_phases([Phase|Rest]) :-
  message:print(Phase),
  message:color(darkgray),
  message:print(' \u2192 '),
  build:print_skipped_phases(Rest).


% -----------------------------------------------------------------------------
%  In-place slot update
% -----------------------------------------------------------------------------

%! build:update_slot(+Slot, +NumSlots, +Status, +PlanStep, +NumSteps, +ActionIdx, +Action, +RepoEntry) is det.
%
% Update a specific slot line in-place using ANSI cursor movement.
% Must be called inside with_mutex(build_display, ...).

build:update_slot(Slot, NumSlots, Status, PlanStep, NumSteps, ActionIdx, Action, RepoEntry) :-
  LinesUp is NumSlots - Slot,
  format("\e[~dA\r", [LinesUp]),
  build:render_slot(Status, PlanStep, NumSteps, ActionIdx, Action, RepoEntry),
  message:el,
  format("\e[~dB\r", [LinesUp]),
  flush_output.


% -----------------------------------------------------------------------------
%  Slot rendering
% -----------------------------------------------------------------------------

%! build:render_slot(+Status, +PlanStep, +NumSteps, +ActionIdx, +Action, +RepoEntry) is det.
%
% Render the content of a slot line based on its status. Uses the same
% step bubble and action/target colors as the plan display.
% ActionIdx=0 gets a step bubble; subsequent actions get a continuation prefix.

build:render_slot(pending, PlanStep, _NumSteps, ActionIdx, Action, RepoEntry) :-
  build:print_slot_prefix(PlanStep, ActionIdx),
  message:color(darkgray),
  message:print(Action),
  message:color(darkgray),
  message:column(24, RepoEntry),
  message:color(normal).

build:render_slot(active, PlanStep, _NumSteps, ActionIdx, Action, RepoEntry) :-
  build:print_slot_prefix(PlanStep, ActionIdx),
  message:color(cyan),
  message:print(Action),
  message:color(green),
  message:column(24, RepoEntry),
  message:color(normal),
  build:right_edge_spinner(0).

build:render_slot(done, PlanStep, _NumSteps, ActionIdx, Action, RepoEntry) :-
  build:print_slot_prefix(PlanStep, ActionIdx),
  message:color(cyan),
  message:print(Action),
  message:color(green),
  message:column(24, RepoEntry),
  message:color(normal),
  build:right_edge_ok.

build:render_slot(failed(_Reason), PlanStep, _NumSteps, ActionIdx, Action, RepoEntry) :-
  build:print_slot_prefix(PlanStep, ActionIdx),
  message:color(cyan),
  message:print(Action),
  message:color(green),
  message:column(24, RepoEntry),
  message:color(normal),
  build:right_edge_fail.

build:render_slot(failed, PlanStep, NumSteps, ActionIdx, Action, RepoEntry) :-
  build:render_slot(failed('error'), PlanStep, NumSteps, ActionIdx, Action, RepoEntry).

build:render_slot(skipped, PlanStep, _NumSteps, ActionIdx, Action, RepoEntry) :-
  build:print_slot_prefix(PlanStep, ActionIdx),
  message:color(darkgray),
  message:print(Action),
  message:color(darkgray),
  message:column(24, RepoEntry),
  message:color(normal).

build:render_slot(stub, PlanStep, _NumSteps, ActionIdx, Action, RepoEntry) :-
  build:print_slot_prefix(PlanStep, ActionIdx),
  message:color(cyan),
  message:print(Action),
  message:color(green),
  message:column(24, RepoEntry),
  message:color(darkgray),
  message:print(' (stub)'),
  message:color(normal).


% -----------------------------------------------------------------------------
%  Step bubble helper
% -----------------------------------------------------------------------------

%! build:print_slot_prefix(+PlanStep, +ActionIdx) is det.
%
% Print the slot prefix. First action in a step (ActionIdx=0) gets a
% step bubble matching the plan's format: " └─[step  N]─┤"
% Subsequent actions (ActionIdx>0) get a continuation line: "             │ "

build:print_slot_prefix(PlanStep, 0) :-
  !,
  format(atom(AtomStepN), '~t~0f~2|', [PlanStep]),
  format(atom(StepLabel), 'step ~a', [AtomStepN]),
  write(' \u2514\u2500'),
  message:bubble(darkgray, StepLabel),
  write('\u2500\u2524 ').

build:print_slot_prefix(_PlanStep, _ActionIdx) :-
  write('             \u2502 ').


% =============================================================================
%  File sub-slot display (per-file download progress)
% =============================================================================

% -----------------------------------------------------------------------------
%  Initial file sub-slot printing
% -----------------------------------------------------------------------------

%! build:print_file_subslots(+DistFiles, +Distdir) is det.
%
% Print one line per distfile below the download header slot, matching
% the plan's tree-drawing style. Already-present files show a green
% checkmark; others show as pending in darkgray.

build:print_file_subslots(DistFiles, Distdir) :-
  build:print_file_subslots_(DistFiles, 0, Distdir).

build:print_file_subslots_([], _, _).

build:print_file_subslots_([dist(Filename, Size, _)|Rest], 0, Distdir) :-
  build:file_prefix_first,
  build:render_file_content(pending, Filename, Size, Distdir),
  nl,
  build:print_file_subslots_(Rest, 1, Distdir).

build:print_file_subslots_([dist(Filename, Size, _)|Rest], N, Distdir) :-
  N > 0,
  build:file_prefix_rest,
  build:render_file_content(pending, Filename, Size, Distdir),
  nl,
  N1 is N + 1,
  build:print_file_subslots_(Rest, N1, Distdir).


% -----------------------------------------------------------------------------
%  File tree prefixes (matching plan style)
% -----------------------------------------------------------------------------

%! build:file_prefix_first is det.
%
% Tree prefix for the first file: │  └─ file ─┤

build:file_prefix_first :-
  write('             \u2502           '),
  message:color(darkgray),
  message:print('\u2514\u2500 file \u2500\u2524 '),
  message:color(normal).


%! build:file_prefix_rest is det.
%
% Tree prefix for subsequent files: │           │

build:file_prefix_rest :-
  write('             \u2502          '),
  message:color(darkgray),
  message:print('          \u2502 '),
  message:color(normal).


% -----------------------------------------------------------------------------
%  In-place file sub-slot update
% -----------------------------------------------------------------------------

%! build:update_file_subslot(+FileIdx, +FileStartLine, +TotalLines, +Status, +Filename, +Size, +Distdir) is det.
%
% Update a file sub-line in-place using ANSI cursor movement.
% Must be called inside with_mutex(build_display, ...).
% FileIdx is 0-based within this download's files.
% FileStartLine is the absolute line of the first file in the display.
% TotalLines is the total display lines for the step.

build:update_file_subslot(FileIdx, FileStartLine, TotalLines, Status, Filename, Size, Distdir) :-
  AbsLine is FileStartLine + FileIdx,
  LinesUp is TotalLines - AbsLine,
  format("\e[~dA\r", [LinesUp]),
  ( FileIdx =:= 0
  -> build:file_prefix_first
  ;  build:file_prefix_rest
  ),
  build:render_file_content(Status, Filename, Size, Distdir),
  message:el,
  format("\e[~dB\r", [LinesUp]),
  flush_output.


% -----------------------------------------------------------------------------
%  File content rendering
% -----------------------------------------------------------------------------

%! build:render_file_content(+Status, +Filename, +Size, +Distdir) is det.
%
% Render file content for a sub-slot. Matches the plan's layout:
% size (magenta) then filename, followed by status indicator.

build:render_file_content(pending, Filename, Size, Distdir) :-
  ( mirror:flat_present(Distdir, Filename)
  -> message:color(magenta),
     message:print_bytes(Size),
     message:color(normal),
     message:print(' '),
     message:print(Filename),
     build:right_edge_ok
  ;  message:color(darkgray),
     message:print_bytes(Size),
     message:color(darkgray),
     message:print(' '),
     message:print(Filename),
     message:color(normal)
  ).

build:render_file_content(progress(Pct, Speed), Filename, Size, _Distdir) :-
  message:color(magenta),
  message:print_bytes(Size),
  message:color(normal),
  message:print(' '),
  message:print(Filename),
  message:color(cyan),
  format('  ~d%%', [Pct]),
  ( Speed > 0
  -> message:color(darkgray),
     message:convert_bytes(Speed, SpeedStr),
     format('  ~w/s', [SpeedStr])
  ;  true
  ),
  message:color(normal).

build:render_file_content(progress(Pct), Filename, Size, Distdir) :-
  build:render_file_content(progress(Pct, 0), Filename, Size, Distdir).

build:render_file_content(done, Filename, Size, _Distdir) :-
  message:color(magenta),
  message:print_bytes(Size),
  message:color(normal),
  message:print(' '),
  message:print(Filename),
  build:right_edge_ok.

build:render_file_content(failed, Filename, Size, _Distdir) :-
  message:color(magenta),
  message:print_bytes(Size),
  message:color(normal),
  message:print(' '),
  message:print(Filename),
  build:right_edge_fail.

build:render_file_content(restricted, Filename, Size, _Distdir) :-
  message:color(magenta),
  message:print_bytes(Size),
  message:color(normal),
  message:print(' '),
  message:print(Filename),
  message:color(yellow),
  message:print(' (manual fetch required)'),
  message:color(normal).


% =============================================================================
%  Live source sub-slot display
% =============================================================================

%! build:print_live_subslot is det.
%
% Print a single sub-line for live ebuilds: "└─ live ─┤ git repository"

build:print_live_subslot :-
  build:live_prefix,
  message:color(darkgray),
  message:print('git repository'),
  message:color(normal),
  nl.


%! build:live_prefix is det.

build:live_prefix :-
  write('             \u2502           '),
  message:color(darkgray),
  message:print('\u2514\u2500 live \u2500\u2524 '),
  message:color(normal).


%! build:update_live_subslot(+Idx, +LiveStartLine, +TotalLines, +Status) is det.
%
% Update the live source sub-line in-place.
% Must be called inside with_mutex(build_display, ...).

build:update_live_subslot(_Idx, LiveStartLine, TotalLines, Status) :-
  LinesUp is TotalLines - LiveStartLine,
  format("\e[~dA\r", [LinesUp]),
  build:live_prefix,
  build:render_live_content(Status),
  message:el,
  format("\e[~dB\r", [LinesUp]),
  flush_output.


%! build:render_live_content(+Status) is det.

build:render_live_content(pending) :-
  message:color(darkgray),
  message:print('git repository'),
  message:color(normal).

build:render_live_content(done) :-
  message:color(normal),
  message:print('git repository'),
  build:right_edge_ok.

build:render_live_content(failed) :-
  message:color(normal),
  message:print('git repository'),
  build:right_edge_fail.


% =============================================================================
%  Inline phase display (exec line + logs line)
% =============================================================================

% -----------------------------------------------------------------------------
%  Initial printing
% -----------------------------------------------------------------------------

%! build:print_exec_and_logs(+PhaseList, +LogPath) is det.
%
% Print two lines below the action header:
%   └─ exec ─┤ [ phase1 → phase2 → ... ]
%   └─ logs ─┤ logfile.log

build:print_exec_and_logs(PhaseList, LogPath) :-
  maplist([P, P-pending]>>true, PhaseList, PhaseStates),
  build:exec_prefix,
  build:render_inline_phases(PhaseStates),
  ( catch(config:show_build_logs(true), _, fail)
  -> nl,
     build:logs_prefix,
     build:render_log_name(LogPath, pending)
  ;  true
  ).


% -----------------------------------------------------------------------------
%  Tree prefixes
% -----------------------------------------------------------------------------

build:exec_prefix :-
  write('             \u2502           '),
  message:color(darkgray),
  message:print('\u2514\u2500 exec \u2500\u2524 '),
  message:color(normal).

build:logs_prefix :-
  write('             \u2502           '),
  message:color(darkgray),
  message:print('\u2514\u2500 logs \u2500\u2524 '),
  message:color(normal).


% -----------------------------------------------------------------------------
%  In-place updates
% -----------------------------------------------------------------------------

%! build:update_exec_line(+ExecLine, +TotalLines, +PhaseStates) is det.
%
% Re-render the inline exec line at ExecLine with current phase states.
% Must be called inside with_mutex(build_display, ...).

build:update_exec_line(ExecLine, TotalLines, PhaseStates) :-
  LinesUp is TotalLines - ExecLine,
  format("\e[~dA\r", [LinesUp]),
  build:exec_prefix,
  build:render_inline_phases(PhaseStates),
  message:el,
  format("\e[~dB\r", [LinesUp]),
  flush_output.


%! build:update_logs_line(+LogsLine, +TotalLines, +LogPath, +OverallStatus) is det.
%
% Re-render the logs line. Shows log filename in red if any phase failed.
% Must be called inside with_mutex(build_display, ...).

build:update_logs_line(LogsLine, TotalLines, LogPath, OverallStatus) :-
  LinesUp is TotalLines - LogsLine,
  format("\e[~dA\r", [LinesUp]),
  build:logs_prefix,
  build:render_log_name(LogPath, OverallStatus),
  message:el,
  format("\e[~dB\r", [LinesUp]),
  flush_output.


% -----------------------------------------------------------------------------
%  Inline phase rendering
% -----------------------------------------------------------------------------

%! build:render_inline_phases(+PhaseStates) is det.
%
% Renders phases inline: [ phase1 → phase2 → ... ] with per-phase coloring.
% Appends a green checkmark if all done, red ! if any failed.

build:render_inline_phases(PhaseStates) :-
  build:render_phases_with_arrows(PhaseStates),
  message:el,
  build:render_overall_indicator(PhaseStates).


%! build:render_phases_with_arrows(+PhaseStates) is det.
%
% Render phase names separated by arrows, each colored by status.

build:render_phases_with_arrows([]).

build:render_phases_with_arrows([Phase-Status]) :-
  !,
  build:render_phase_word(Phase, Status).

build:render_phases_with_arrows([Phase-Status|Rest]) :-
  build:render_phase_word(Phase, Status),
  message:color(darkgray),
  message:print(' \u2192 '),
  message:color(normal),
  build:render_phases_with_arrows(Rest).


%! build:render_phase_word(+Phase, +Status) is det.
%
% Render a single phase word with status-appropriate color.

build:render_phase_word(Phase, pending) :-
  message:color(darkgray),
  message:print(Phase),
  message:color(normal).

build:render_phase_word(Phase, active) :-
  message:color(cyan),
  message:print(Phase),
  message:color(normal).

build:render_phase_word(Phase, progress(_)) :-
  message:color(cyan),
  message:print(Phase),
  message:color(normal).

build:render_phase_word(Phase, done) :-
  message:color(cyan),
  message:print(Phase),
  message:color(normal).

build:render_phase_word(Phase, failed) :-
  message:color(lightred),
  message:style(bold),
  message:print(Phase),
  message:style(normal),
  message:color(normal).

build:render_phase_word(Phase, failed(_)) :-
  message:color(lightred),
  message:style(bold),
  message:print(Phase),
  message:style(normal),
  message:color(normal).

build:render_phase_word(Phase, failed(_, _)) :-
  message:color(lightred),
  message:style(bold),
  message:print(Phase),
  message:style(normal),
  message:color(normal).

build:render_phase_word(Phase, skipped) :-
  message:color(darkgray),
  message:print(Phase),
  message:color(normal).

build:render_phase_word(Phase, stub) :-
  message:color(darkgray),
  message:print(Phase),
  message:color(normal).


%! build:render_overall_indicator(+PhaseStates) is det.
%
% Appends a green checkmark if all phases are done/stub,
% a red bold ! if any phase failed, or a phase fraction N/M if running.

build:render_overall_indicator(PhaseStates) :-
  ( member(_-Status, PhaseStates),
    build:is_failed_status(Status)
  -> build:right_edge_fail
  ;  ( \+ member(_-pending, PhaseStates),
       \+ member(_-active, PhaseStates),
       \+ member(_-progress(_), PhaseStates)
     -> build:right_edge_ok
     ;  build:phase_progress(PhaseStates, AccPct, Current, LiveTotal),
        build:right_edge_progress(AccPct, Current, LiveTotal)
     )
  ).


%! build:phase_progress(+PhaseStates, -AccPct, -Current, -LiveTotal) is det.
%
% Computes accumulated progress across all live (non-stub) phases.
% AccPct = (done_count * 100 + current_phase_pct) / live_total.
% Current is the 1-based index of the active phase within live phases.
% LiveTotal excludes stub phases.

build:phase_progress(PhaseStates, AccPct, Current, LiveTotal) :-
  include(build:is_live_phase, PhaseStates, LiveStates),
  length(LiveStates, LiveTotal),
  ( LiveTotal > 0
  -> aggregate_all(count, member(_-done, LiveStates), DoneCount),
     ( member(_-progress(P), LiveStates), P > 0 -> CurPct = P ; CurPct = 0 ),
     AccPct is (DoneCount * 100 + CurPct) // LiveTotal,
     build:current_phase_index(LiveStates, 1, Current)
  ;  AccPct = 0, Current = 0
  ).

build:is_live_phase(_-stub) :- !, fail.
build:is_live_phase(_).

build:current_phase_index([], _, 1).
build:current_phase_index([_-active|_], N, N) :- !.
build:current_phase_index([_-progress(_)|_], N, N) :- !.
build:current_phase_index([_|Rest], N, Current) :-
  N1 is N + 1,
  build:current_phase_index(Rest, N1, Current).


%! build:right_edge_progress(+AccPct, +Current, +LiveTotal) is det.
%
% Print "(AccPct%) Current/LiveTotal" at the right edge of the terminal.

build:right_edge_progress(AccPct, Current, LiveTotal) :-
  config:printing_tty_size(_, W),
  format(atom(Label), '(~d%) ~d/~d', [AccPct, Current, LiveTotal]),
  atom_length(Label, Len),
  Col is W - Len,
  format("\e[~dG", [Col]),
  message:color(darkgray),
  message:print(Label),
  message:color(normal).

build:is_failed_status(failed).
build:is_failed_status(failed(_)).
build:is_failed_status(failed(_, _)).


% -----------------------------------------------------------------------------
%  Log name rendering
% -----------------------------------------------------------------------------

%! build:render_log_name(+LogPath, +OverallStatus) is det.
%
% Render the log filename. Red if failed, darkgray otherwise.

build:render_log_name(LogPath, OverallStatus) :-
  ( LogPath == '' -> DisplayPath = '(no log)' ; DisplayPath = LogPath ),
  ( build:is_failed_status(OverallStatus)
  -> message:color(red),
     message:print(DisplayPath),
     message:color(normal)
  ;  message:color(darkgray),
     message:print(DisplayPath),
     message:color(normal)
  ).


% =============================================================================
%  Summary
% =============================================================================

%! build:summary(+Completed, +Failed, +Stubs) is det.
%
% Print a summary line at the end of the build.

build:summary(Completed, Failed, Stubs) :-
  nl,
  format('Total: ', []),
  build:summary_collect(Completed, Failed, Stubs, Parts),
  build:print_summary_parts(Parts),
  format('.~n~n', []),
  flush_output.

build:summary_collect(Completed, Failed, Stubs, Parts) :-
  ( Completed > 0 -> CP = [completed-Completed] ; CP = [] ),
  ( Failed > 0    -> FP = [failed-Failed]       ; FP = [] ),
  ( Stubs > 0     -> SP = [stubs-Stubs]         ; SP = [] ),
  append([CP, FP, SP], Parts).

build:print_summary_parts([]).

build:print_summary_parts([Label-Count]) :-
  build:print_summary_one(Label, Count).

build:print_summary_parts([Label-Count, Last]) :-
  build:print_summary_one(Label, Count),
  format(' and ', []),
  build:print_summary_parts([Last]).

build:print_summary_parts([Label-Count, B, C | Rest]) :-
  build:print_summary_one(Label, Count),
  format(', ', []),
  build:print_summary_parts([B, C | Rest]).

build:print_summary_one(completed, N) :-
  message:color(green), format('~d', [N]), message:color(normal),
  format(' completed', []).

build:print_summary_one(failed, N) :-
  message:color(red), format('~d', [N]), message:color(normal),
  format(' failed', []).

build:print_summary_one(stubs, N) :-
  message:color(darkgray), format('~d', [N]), message:color(normal),
  format(' stubs', []).
