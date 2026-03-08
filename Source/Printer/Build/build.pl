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

build:print_job_slots([], _TotalSteps) :- !.

build:print_job_slots([slotted(_LineOff, _TotalLines, StepN, TotalSteps, rule(Repo://Entry:Action?{_Ctx}, _Body), FileInfo)|Rest], _) :-
  build:render_slot(pending, StepN, TotalSteps, Action, Repo://Entry),
  nl,
  ( FileInfo = files(_FileStart, _NumFiles, DistFiles, Distdir)
  -> build:print_file_subslots(DistFiles, Distdir)
  ;  true
  ),
  build:print_job_slots(Rest, TotalSteps).

build:print_job_slots([_|Rest], TotalSteps) :-
  build:print_job_slots(Rest, TotalSteps).


% -----------------------------------------------------------------------------
%  In-place slot update
% -----------------------------------------------------------------------------

%! build:update_slot(+Slot, +NumSlots, +Status, +StepN, +TotalSteps, +Action, +RepoEntry) is det.
%
% Update a specific slot line in-place using ANSI cursor movement.
% Must be called inside with_mutex(build_display, ...).

build:update_slot(Slot, NumSlots, Status, StepN, TotalSteps, Action, RepoEntry) :-
  LinesUp is NumSlots - Slot,
  format("\e[~dA\r", [LinesUp]),
  build:render_slot(Status, StepN, TotalSteps, Action, RepoEntry),
  message:el,
  format("\e[~dB\r", [LinesUp]),
  flush_output.


% -----------------------------------------------------------------------------
%  Slot rendering
% -----------------------------------------------------------------------------

%! build:render_slot(+Status, +StepN, +TotalSteps, +Action, +RepoEntry) is det.
%
% Render the content of a slot line based on its status. Uses the same
% step bubble and action/target colors as the plan display.

build:render_slot(pending, StepN, _TotalSteps, Action, RepoEntry) :-
  build:print_step_bubble(StepN),
  message:color(darkgray),
  message:print(Action),
  message:color(darkgray),
  message:column(24, RepoEntry),
  message:color(normal).

build:render_slot(active, StepN, _TotalSteps, Action, RepoEntry) :-
  build:print_step_bubble(StepN),
  message:color(cyan),
  message:print(Action),
  message:color(green),
  message:column(24, RepoEntry),
  message:color(normal).

build:render_slot(done, StepN, _TotalSteps, Action, RepoEntry) :-
  build:print_step_bubble(StepN),
  message:color(cyan),
  message:print(Action),
  message:color(green),
  message:column(24, RepoEntry),
  message:color(green),
  message:print(' \u2713'),
  message:color(normal).

build:render_slot(failed(Reason), StepN, _TotalSteps, Action, RepoEntry) :-
  build:print_step_bubble(StepN),
  message:color(cyan),
  message:print(Action),
  message:color(green),
  message:column(24, RepoEntry),
  message:color(red),
  message:style(bold),
  message:print(' !'),
  format(' (~w)', [Reason]),
  message:style(normal),
  message:color(normal).

build:render_slot(failed, StepN, TotalSteps, Action, RepoEntry) :-
  build:render_slot(failed('error'), StepN, TotalSteps, Action, RepoEntry).

build:render_slot(stub, StepN, _TotalSteps, Action, RepoEntry) :-
  build:print_step_bubble(StepN),
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

%! build:print_step_bubble(+StepN) is det.
%
% Print a step bubble matching the plan's format: " └─[step  N]─┤"
% Uses the same message:bubble/2 as the plan printer.

build:print_step_bubble(StepN) :-
  format(atom(AtomStepN), '~t~0f~2|', [StepN]),
  format(atom(StepLabel), 'step ~a', [AtomStepN]),
  write(' \u2514\u2500'),
  message:bubble(darkgray, StepLabel),
  write('\u2500\u2524 ').


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
     message:color(green),
     message:print(' \u2713'),
     message:color(normal)
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
  message:color(green),
  message:print(' \u2713'),
  message:color(normal).

build:render_file_content(failed, Filename, Size, _Distdir) :-
  message:color(magenta),
  message:print_bytes(Size),
  message:color(normal),
  message:print(' '),
  message:print(Filename),
  message:color(red),
  message:style(bold),
  message:print(' !'),
  message:style(normal),
  message:color(normal).


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
