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

:- dynamic build:spinner_tick/2.

% -----------------------------------------------------------------------------
%  Header
% -----------------------------------------------------------------------------

%! build:header(+NumSteps, +TotalActions) is det.
%
% Print the progress header, matching the plan's footer style.

build:header(NumSteps, TotalActions) :-
  message:color(green),
  message:print('These are the packages being merged, in order:'),
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
  ;  SubInfo = phases(_ExecLine, _ExecLineCount, _LogsLine, PhaseList, LogPath)
  -> nl,
     build:print_exec_and_logs(Action, PhaseList, LogPath),
     build:print_build_config(Repo://Entry:Action?{Ctx}),
     nl
  ;  nl
  ),
  build:print_job_slots(Rest, NumSteps).

build:print_job_slots([slotted(_LineOff, _TotalLines, PlanStep, NumSteps, ActionIdx, rule(world(Atom):Action?{_Ctx}, _Body), _SubInfo)|Rest], _) :-
  !,
  build:render_slot(pending, PlanStep, NumSteps, ActionIdx, Action, Atom),
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
  ( SubInfo = phases(_ExecLine, _ExecLineCount, _LogsLine, PhaseList, LogPath)
  -> nl,
     build:print_skipped_exec_and_logs(Action, PhaseList, LogPath),
     build:print_skipped_conf(Repo://Entry:Action?{Ctx}),
     nl
  ;  nl
  ),
  build:print_skipped_slots(Rest, NumSteps).

build:print_skipped_slots([slotted(_LineOff, _TotalLines, PlanStep, NumSteps, ActionIdx, rule(world(Atom):Action?{_Ctx}, _Body), _SubInfo)|Rest], _) :-
  !,
  build:render_slot(skipped, PlanStep, NumSteps, ActionIdx, Action, Atom),
  nl,
  build:print_skipped_slots(Rest, NumSteps).

build:print_skipped_slots([_|Rest], NumSteps) :-
  build:print_skipped_slots(Rest, NumSteps).


%! build:print_build_config(+RuleHead) is det.
%
% Print config (USE flags etc.) in build context. In column mode the pretend
% plan places the first config item at column 104 on the step-header line,
% but the build plan has exec/logs lines in between, so the column-104 jump
% would land on the wrong line. We prepend a continuation line so that the
% first print_config_prefix('conf') column-104 alignment lands correctly.

build:print_build_config(RuleHead) :-
  console:printing_style('column'), !,
  with_output_to(string(S), catch(useflags:print_config(RuleHead), _, true)),
  ( S \== ""
  -> nl, write('             │ '),
     catch(useflags:print_config(RuleHead), _, true)
  ;  true
  ).

build:print_build_config(RuleHead) :-
  catch(useflags:print_config(RuleHead), _, true).


%! build:print_skipped_conf(+RuleHead) is det.
%
% Print the config lines for skipped steps.

build:print_skipped_conf(RuleHead) :-
  build:print_build_config(RuleHead), !.
build:print_skipped_conf(_).


%! build:print_skipped_exec_and_logs(+Action, +PhaseList, +LogPath) is det.
%
% Print exec and logs lines in darkgray for skipped steps.

build:print_skipped_exec_and_logs(_Action, PhaseList, LogPath) :-
  build:exec_prefix,
  message:bubble(darkgray, 'ACTION'),
  message:print(' = '),
  message:color(darkgray),
  maplist([P, P-pending]>>true, PhaseList, PhaseStates),
  build:render_phases_wrapped(PhaseStates),
  message:color(normal),
  nl,
  build:exec_continuation_prefix,
  message:bubble(darkgray, 'LOG'),
  message:print(' = '),
  message:color(darkgray),
  message:print(LogPath),
  message:color(normal).


% -----------------------------------------------------------------------------
%  In-place slot update
% -----------------------------------------------------------------------------

%! build:update_slot(+Slot, +NumSlots, +Status, +PlanStep, +NumSteps, +ActionIdx, +Action, +RepoEntry) is det.
%
% Update a specific slot line in-place using ANSI cursor movement.
% Must be called inside with_mutex(build_display, ...).
% When stdout is not a TTY, prints a log line instead.

build:update_slot(_Slot, _NumSlots, Status, PlanStep, NumSteps, ActionIdx, Action, RepoEntry) :-
  \+ console:output_tty,
  !,
  build:log_slot(Status, PlanStep, NumSteps, ActionIdx, Action, RepoEntry).

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
  build:print_slot_label(pending, Action, RepoEntry).

build:render_slot(active, PlanStep, _NumSteps, ActionIdx, Action, RepoEntry) :-
  build:print_slot_prefix(PlanStep, ActionIdx),
  build:print_slot_label(active, Action, RepoEntry),
  build:next_spinner_tick(PlanStep-ActionIdx, Tick),
  message:right_edge_spinner(Tick).

build:render_slot(done, PlanStep, _NumSteps, ActionIdx, Action, RepoEntry) :-
  build:print_slot_prefix(PlanStep, ActionIdx),
  build:print_slot_label(done, Action, RepoEntry),
  message:right_edge_ok.

build:render_slot(failed(_Reason), PlanStep, _NumSteps, ActionIdx, Action, RepoEntry) :-
  build:print_slot_prefix(PlanStep, ActionIdx),
  build:print_slot_label(failed, Action, RepoEntry),
  message:right_edge_fail.

build:render_slot(failed, PlanStep, NumSteps, ActionIdx, Action, RepoEntry) :-
  build:render_slot(failed('error'), PlanStep, NumSteps, ActionIdx, Action, RepoEntry).

build:render_slot(skipped, PlanStep, _NumSteps, ActionIdx, Action, RepoEntry) :-
  build:print_slot_prefix(PlanStep, ActionIdx),
  build:print_slot_label(skipped, Action, RepoEntry).

build:render_slot(stub, PlanStep, _NumSteps, ActionIdx, Action, RepoEntry) :-
  build:print_slot_prefix(PlanStep, ActionIdx),
  build:print_slot_label(stub, Action, RepoEntry),
  message:color(darkgray),
  message:print(' (stub)'),
  message:color(normal).


%! build:print_slot_label(+Status, +Action, +RepoEntry) is det.
%
% Action name and package column. The plan target (`run`) is a green
% bubble with a bold green package. Every other action is cyan with a
% green package, the same colours the pretend plan uses.

build:print_slot_label(Status, Action, RepoEntry) :-
  build:print_slot_action(Status, Action, RepoEntry),
  build:print_slot_entry(Status, Action, RepoEntry).


%! build:print_slot_action(+Status, +Action, +RepoEntry) is det.
%
% The plan target is a green bubble. Every other action, including a
% `run` that is only a dependency, is cyan once it runs. Pending and
% skipped stay dark gray. The colour atom is written literally:
% message:color/1 only emits ANSI for a compile-time atom.

build:print_slot_action(Status, Action, RepoEntry) :-
  build:slot_is_target(RepoEntry, Action),
  !,
  ( memberchk(Status, [pending, skipped])
  -> message:bubble(darkgray, Action)
  ;  message:bubble(green, Action)
  ).
build:print_slot_action(pending, Action, _) :-
  !,
  message:color(darkgray),
  message:print(Action).
build:print_slot_action(skipped, Action, _) :-
  !,
  message:color(darkgray),
  message:print(Action).
build:print_slot_action(_, Action, _) :-
  message:color(cyan),
  message:print(Action).


%! build:slot_is_target(+RepoEntry, +Action) is semidet.
%
% True when this slot is one of the packages the user asked to build.
% Registered by the builder from the resolved print target. A dependency
% whose action happens to be `run` is not a target.

build:slot_is_target(Repo://Entry, Action) :-
  current_predicate(builder:plan_target/3),
  builder:plan_target(Repo, Entry, Action),
  !.


%! build:print_slot_entry(+Status, +Action, +RepoEntry) is det.
%
% Package column. The plan target is bold green. Every other running
% action is green. Pending and skipped stay dark gray.

build:print_slot_entry(pending, _, RepoEntry) :-
  !,
  message:color(darkgray),
  message:column(24, RepoEntry),
  message:color(normal).
build:print_slot_entry(skipped, _, RepoEntry) :-
  !,
  message:color(darkgray),
  message:column(24, RepoEntry),
  message:color(normal).
build:print_slot_entry(_, Action, RepoEntry) :-
  build:slot_is_target(RepoEntry, Action),
  !,
  message:style(bold),
  message:color(green),
  message:column(24, RepoEntry),
  message:style(normal),
  message:color(normal).
build:print_slot_entry(_, _, RepoEntry) :-
  message:color(green),
  message:column(24, RepoEntry),
  message:color(normal).


%! build:next_spinner_tick(+Key, -Tick) is det.
%
% Next braille frame for this header. The first draw is frame 0.

build:next_spinner_tick(Key, Tick) :-
  ( retract(build:spinner_tick(Key, Prev))
  -> Tick is Prev + 1
  ;  Tick = 0
  ),
  assertz(build:spinner_tick(Key, Tick)).


%! build:clear_spinner_ticks is det.
%
% Drop header spinner frames at the end of a step.

build:clear_spinner_ticks :-
  retractall(build:spinner_tick(_, _)).


% -----------------------------------------------------------------------------
%  Log-style slot output (non-TTY)
% -----------------------------------------------------------------------------

%! build:log_slot(+Status, +PlanStep, +NumSteps, +ActionIdx, +Action, +RepoEntry) is det.
%
% Prints a single log line for a status transition. Only logs
% final states (done, failed, skipped, stub) to avoid flooding.
% Active/pending transitions are suppressed in pipe mode.

build:log_slot(active, _, _, _, _, _) :- !.
build:log_slot(pending, _, _, _, _, _) :- !.

build:log_slot(Status, PlanStep, _NumSteps, _ActionIdx, Action, RepoEntry) :-
  build:status_label(Status, Label),
  message:color(normal),
  format('[step ~0f] ', [PlanStep]),
  message:print(Label),
  message:print(' '),
  message:print(Action),
  message:print(' '),
  message:print(RepoEntry),
  nl,
  flush_output.


%! build:status_label(+Status, -Label) is det.
%
% Maps a slot status to a human-readable label for log output.

build:status_label(done,            'OK  ').
build:status_label(failed(Reason),  Label) :-
  format(atom(Label), 'FAIL (~w)', [Reason]).
build:status_label(failed,          'FAIL').
build:status_label(skipped,         'SKIP').
build:status_label(stub,            'STUB').
build:status_label(Other,           Label) :-
  format(atom(Label), '~w', [Other]).


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

build:print_file_subslots_([dist(Filename, Size, Pairs)|Rest], 0, Distdir) :-
  build:file_prefix_first,
  build:initial_file_status(Distdir, Filename, Size, Pairs, Status),
  build:render_file_content(Status, Filename, Size, Distdir),
  nl,
  build:print_file_subslots_(Rest, 1, Distdir).

build:print_file_subslots_([dist(Filename, Size, Pairs)|Rest], N, Distdir) :-
  N > 0,
  build:file_prefix_rest,
  build:initial_file_status(Distdir, Filename, Size, Pairs, Status),
  build:render_file_content(Status, Filename, Size, Distdir),
  nl,
  N1 is N + 1,
  build:print_file_subslots_(Rest, N1, Distdir).


%! build:initial_file_status(+Distdir, +Filename, +Size, +Pairs, -Status) is det.

build:initial_file_status(Distdir, Filename, Size, Pairs, Status) :-
  ( catch(download:distfile_destination(Distdir, Filename, Path), _, fail),
    download:verified_distfile(Path, Size, Pairs)
  -> Status = cached
  ;  Status = pending
  ).


% -----------------------------------------------------------------------------
%  File tree prefixes (style-aware, matching plan style)
% -----------------------------------------------------------------------------

%! build:file_prefix_first is det.
%
% Tree prefix for the first file line. Style-aware.

build:file_prefix_first :-
  console:printing_style('fancy'), !,
  write('             \u2502           '),
  message:color(darkgray),
  message:print('\u2514\u2500 file \u2500\u2524 '),
  message:color(normal).

build:file_prefix_first :-
  console:printing_style('column'), !,
  write('             \u2502 '),
  message:column(104, ' ').

build:file_prefix_first :-
  write('             \u2502           ').


%! build:file_prefix_rest is det.
%
% Tree prefix for subsequent file lines. Style-aware.

build:file_prefix_rest :-
  console:printing_style('fancy'), !,
  write('             \u2502          '),
  message:color(darkgray),
  message:print('          \u2502 '),
  message:color(normal).

build:file_prefix_rest :-
  console:printing_style('column'), !,
  write('             \u2502 '),
  message:column(104, ' ').

build:file_prefix_rest :-
  write('             \u2502           ').


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

build:update_file_subslot(_FileIdx, _FileStartLine, _TotalLines, Status, Filename, Size, Distdir) :-
  \+ console:output_tty,
  !,
  ( Status == done
  -> format('  file OK   ~w (~w)~n', [Filename, Size])
  ; Status = failed(_)
  -> format('  file FAIL ~w (~w)~n', [Filename, Size])
  ; true
  ),
  ignore(Distdir = _).

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

build:render_file_content(cached, Filename, Size, _Distdir) :-
  message:color(magenta),
  message:print_bytes(Size),
  message:color(normal),
  message:print(' '),
  message:print(Filename),
  message:right_edge_ok.

build:render_file_content(pending, Filename, Size, _Distdir) :-
  message:color(darkgray),
  message:print_bytes(Size),
  message:color(darkgray),
  message:print(' '),
  message:print(Filename),
  message:color(normal).

build:render_file_content(progress(Pct, Speed), Filename, Size, _Distdir) :-
  message:color(magenta),
  message:print_bytes(Size),
  message:color(normal),
  message:print(' '),
  message:print(Filename),
  build:right_edge_download(Pct, Speed).

build:render_file_content(progress(Pct), Filename, Size, Distdir) :-
  build:render_file_content(progress(Pct, 0), Filename, Size, Distdir).

build:render_file_content(done, Filename, Size, _Distdir) :-
  message:color(magenta),
  message:print_bytes(Size),
  message:color(normal),
  message:print(' '),
  message:print(Filename),
  message:right_edge_ok.

build:render_file_content(failed, Filename, Size, _Distdir) :-
  message:color(magenta),
  message:print_bytes(Size),
  message:color(normal),
  message:print(' '),
  message:print(Filename),
  message:right_edge_fail.

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
  message:print_bytes('live'),
  message:print(' '),
  message:print('git repository'),
  message:color(normal),
  nl.


%! build:live_prefix is det.
%
% Tree prefix for live source sub-slot. Style-aware.

build:live_prefix :-
  console:printing_style('fancy'), !,
  write('             \u2502           '),
  message:color(darkgray),
  message:print('\u2514\u2500 live \u2500\u2524 '),
  message:color(normal).

build:live_prefix :-
  console:printing_style('column'), !,
  write('             \u2502 '),
  message:column(104, ' ').

build:live_prefix :-
  write('             \u2502           ').


%! build:update_live_subslot(+Idx, +LiveStartLine, +TotalLines, +Status) is det.
%
% Update the live source sub-line in-place.
% Must be called inside with_mutex(build_display, ...).

build:update_live_subslot(_Idx, _LiveStartLine, _TotalLines, Status) :-
  \+ console:output_tty,
  !,
  ( Status == done
  -> format('  live OK~n')
  ; Status == failed
  -> format('  live FAIL~n')
  ; true
  ).

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
  message:print_bytes('live'),
  message:print(' '),
  message:print('git repository'),
  message:color(normal).

build:render_live_content(progress(Pct)) :-
  message:color(magenta),
  message:print_bytes('live'),
  message:color(normal),
  message:print(' '),
  message:print('git repository'),
  message:color(cyan),
  format('  ~d%', [Pct]),
  message:color(normal).

build:render_live_content(done) :-
  message:color(magenta),
  message:print_bytes('live'),
  message:color(normal),
  message:print(' '),
  message:print('git repository'),
  message:right_edge_ok.

build:render_live_content(failed) :-
  message:color(magenta),
  message:print_bytes('live'),
  message:color(normal),
  message:print(' '),
  message:print('git repository'),
  message:right_edge_fail.


% =============================================================================
%  Inline phase display (exec line + logs line)
% =============================================================================

% -----------------------------------------------------------------------------
%  Initial printing
% -----------------------------------------------------------------------------

%! build:print_exec_and_logs(+Action, +PhaseList, +LogPath) is det.
%
% Print lines below the action header. In fancy mode:
%   └─ exec ─┤ [ACTION] = phase1 → phase2 → ...
%                    │ [LOG] = logfile.log
% In column/short mode, omits tree connectors and wraps long phase
% lists across multiple lines.

build:print_exec_and_logs(_Action, PhaseList, LogPath) :-
  maplist([P, P-pending]>>true, PhaseList, PhaseStates),
  build:exec_prefix,
  message:bubble(darkgray, 'ACTION'),
  message:print(' = '),
  build:render_inline_phases_wrapped(PhaseStates),
  nl,
  build:exec_continuation_prefix,
  message:bubble(darkgray, 'LOG'),
  message:print(' = '),
  build:render_log_name(LogPath, pending).


% -----------------------------------------------------------------------------
%  Tree prefixes (style-aware)
% -----------------------------------------------------------------------------

build:exec_prefix :-
  console:printing_style('fancy'), !,
  write('             \u2502           '),
  message:color(darkgray),
  message:print('\u2514\u2500 exec \u2500\u2524 '),
  message:color(normal).

build:exec_prefix :-
  console:printing_style('column'), !,
  write('             \u2502 '),
  message:column(104, ' ').

build:exec_prefix :-
  write('             \u2502           ').


build:exec_continuation_prefix :-
  console:printing_style('fancy'), !,
  write('             \u2502                    '),
  message:color(darkgray),
  message:print('\u2502 '),
  message:color(normal).

build:exec_continuation_prefix :-
  console:printing_style('column'), !,
  write('             \u2502 '),
  message:column(104, ' ').

build:exec_continuation_prefix :-
  write('             \u2502           ').


% -----------------------------------------------------------------------------
%  In-place updates
% -----------------------------------------------------------------------------

%! build:update_exec_line(+ExecLine, +TotalLines, +Action, +PhaseStates) is det.
%
% Re-render the inline exec line at ExecLine with current phase states.
% Must be called inside with_mutex(build_display, ...).

build:update_exec_line(ExecLine, TotalLines, Action, PhaseStates) :-
  build:update_exec_line(ExecLine, TotalLines, Action, PhaseStates, none).


%! build:update_exec_line(+ExecLine, +TotalLines, +Action, +PhaseStates, +Entry) is det.
%
% Re-render the inline exec line. Entry is the ebuild being built, or
% `none` when the caller has no package to forecast. A known Entry
% weights the right-edge percentage by phase_stats durations and
% appends the remaining time.

build:update_exec_line(_ExecLine, _TotalLines, _Action, _PhaseStates, _Entry) :-
  \+ console:output_tty, !.

build:update_exec_line(ExecLine, TotalLines, _Action, PhaseStates, Entry) :-
  LinesUp is TotalLines - ExecLine,
  format("\e[~dA\r", [LinesUp]),
  build:exec_prefix,
  message:bubble(darkgray, 'ACTION'),
  message:print(' = '),
  build:render_inline_phases(PhaseStates, Entry),
  message:el,
  format("\e[~dB\r", [LinesUp]),
  flush_output.


%! build:update_logs_line(+LogsLine, +TotalLines, +LogPath, +OverallStatus) is det.
%
% Re-render the LOG continuation line. Shows log filename in red if any
% phase failed. Must be called inside with_mutex(build_display, ...).

build:update_logs_line(_LogsLine, _TotalLines, _LogPath, _OverallStatus) :-
  \+ console:output_tty, !.

build:update_logs_line(LogsLine, TotalLines, LogPath, OverallStatus) :-
  LinesUp is TotalLines - LogsLine,
  format("\e[~dA\r", [LinesUp]),
  build:exec_continuation_prefix,
  message:bubble(darkgray, 'LOG'),
  message:print(' = '),
  build:render_log_name(LogPath, OverallStatus),
  message:el,
  format("\e[~dB\r", [LinesUp]),
  flush_output.


% -----------------------------------------------------------------------------
%  Inline phase rendering
% -----------------------------------------------------------------------------

%! build:render_inline_phases(+PhaseStates) is det.
%
% Renders phases inline on a single line (used for in-place ANSI updates).

build:render_inline_phases(PhaseStates) :-
  build:render_inline_phases(PhaseStates, none).


%! build:render_inline_phases(+PhaseStates, +Entry) is det.
%
% render_inline_phases/1 with a package Entry for the duration forecast.
% Entry `none` keeps the equal-weight phase counter.

build:render_inline_phases(PhaseStates, Entry) :-
  build:render_phases_with_arrows(PhaseStates),
  message:el,
  build:render_overall_indicator(PhaseStates, Entry).


%! build:render_inline_phases_wrapped(+PhaseStates) is det.
%
% Renders phases with line wrapping when the content exceeds terminal width.
% Used for initial printing. Falls back to single-line for in-place updates.

build:render_inline_phases_wrapped(PhaseStates) :-
  build:render_phases_wrapped(PhaseStates),
  build:render_overall_indicator(PhaseStates).


%! build:render_phases_wrapped(+PhaseStates) is det.
%
% Renders phase names separated by arrows, wrapping to a new continuation
% line when the terminal width would be exceeded.

build:render_phases_wrapped(PhaseStates) :-
  console:printing_style('short'), !,
  catch(
    ( console:printing_tty_size(_, TermWidth),
      build:exec_content_start_col(StartCol),
      build:render_phases_wrap_(PhaseStates, StartCol, TermWidth, StartCol)
    ),
    _,
    build:render_phases_with_arrows(PhaseStates)
  ).

build:render_phases_wrapped(PhaseStates) :-
  build:render_phases_with_arrows(PhaseStates).

build:render_phases_wrap_([], _, _, _).

build:render_phases_wrap_([Phase-Status], _StartCol, _TermWidth, _Col) :-
  !,
  build:render_phase_word(Phase, Status).

build:render_phases_wrap_([Phase-Status|Rest], StartCol, TermWidth, Col) :-
  atom_length(Phase, PLen),
  Need is PLen + 4,
  ( Col + Need > TermWidth - 12 ->
    build:exec_wrap_newline(StartCol),
    build:render_phase_word(Phase, Status),
    NewCol is StartCol + PLen
  ; build:render_phase_word(Phase, Status),
    NewCol is Col + PLen
  ),
  message:color(darkgray),
  message:print(' \u2192 '),
  message:color(normal),
  NewCol2 is NewCol + 4,
  build:render_phases_wrap_(Rest, StartCol, TermWidth, NewCol2).


%! build:exec_wrap_newline(+StartCol) is det.
%
% Prints a newline and continuation prefix for wrapped exec phases.

build:exec_wrap_newline(StartCol) :-
  nl,
  build:exec_continuation_prefix,
  line_position(current_output, CurCol),
  Spaces is max(0, StartCol - CurCol),
  forall(between(1, Spaces, _), write(' ')).


%! build:render_phases_with_arrows(+PhaseStates) is det.
%
% Render phase names separated by arrows, each colored by status (single line).

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
  message:print(Phase),
  message:color(normal).

build:render_phase_word(Phase, failed(_)) :-
  message:color(lightred),
  message:print(Phase),
  message:color(normal).

build:render_phase_word(Phase, failed(_, _)) :-
  message:color(lightred),
  message:print(Phase),
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
  build:render_overall_indicator(PhaseStates, none).


%! build:render_overall_indicator(+PhaseStates, +Entry) is det.
%
% render_overall_indicator/1. When Entry names a package with phase
% stats, the running edge is a duration-weighted percentage plus ETA.

build:render_overall_indicator(_, _) :-
  console:printing_style('column'), !.

build:render_overall_indicator(PhaseStates, Entry) :-
  ( member(_-Status, PhaseStates),
    build:is_failed_status(Status)
  -> message:right_edge_fail
  ;  ( \+ member(_-pending, PhaseStates),
       \+ member(_-active, PhaseStates),
       \+ member(_-progress(_), PhaseStates)
     -> message:right_edge_ok
     ;  build:forecast_progress(PhaseStates, Entry, AccPct, Current, LiveTotal, Remain),
        build:right_edge_progress(AccPct, Current, LiveTotal, Remain)
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



%! build:forecast_progress(+PhaseStates, +Entry, -AccPct, -Current, -LiveTotal, -Remain) is det.
%
% AccPct and Current/LiveTotal describe the live phases. Remain is
% `seconds(Left)` when phase stats give a duration for at least one
% live phase, and `none` otherwise. With stats, AccPct is the share of
% expected seconds already spent and Left is the expected remainder.
% A phase with no measurement takes the median of the measured ones.
% Without stats every live phase weighs the same and Remain is `none`.

build:forecast_progress(PhaseStates, Entry, AccPct, Current, LiveTotal, Remain) :-
  build:phase_progress(PhaseStates, CountPct, Current, LiveTotal),
  ( build:timed_progress(PhaseStates, Entry, TimedPct, Left)
  -> AccPct = TimedPct,
     Remain = seconds(Left)
  ;  AccPct = CountPct,
     Remain = none
  ).


%! build:timed_progress(+PhaseStates, +Entry, -AccPct, -Left) is semidet.
%
% Duration-weighted percentage and remaining seconds. Fails when Entry
% is `none`, phase stats are unavailable, or no live phase has a duration.

build:timed_progress(PhaseStates, Entry, AccPct, Left) :-
  Entry \== none,
  current_predicate(phasestats:expected_seconds/3),
  include(build:is_live_phase, PhaseStates, Live),
  Live \== [],
  build:phase_durations(Live, Entry, Durations),
  sum_list(Durations, Total),
  Total > 0,
  build:accumulate_duration(Live, Durations, 0, Done, 0, Left),
  Raw is round((100 * Done) / Total),
  AccPct is min(99, max(0, Raw)).


%! build:phase_durations(+LiveStates, +Entry, -Durations) is semidet.
%
% One positive duration per live phase. Measured phases use their
% forecast. An unmeasured phase uses the median of the measured ones.
% Fails when nothing was measured.

build:phase_durations(Live, Entry, Durations) :-
  maplist(build:raw_seconds(Entry), Live, Raw),
  include(build:positive_seconds, Raw, Measured),
  Measured \== [],
  build:median_seconds(Measured, Fill),
  maplist(build:fill_seconds(Fill), Raw, Durations).


%! build:raw_seconds(+Entry, +PhaseState, -Seconds) is det.
%
% Forecast seconds for the phase, or 0 when phase stats have none.

build:raw_seconds(Entry, Phase-_, Seconds) :-
  ( phasestats:expected_seconds(Entry, Phase, Seconds) -> true ; Seconds = 0 ).


%! build:positive_seconds(+Seconds) is semidet.
%
% True when Seconds is a positive duration.

build:positive_seconds(Seconds) :-
  Seconds > 0.


%! build:fill_seconds(+Fill, +Raw, -Seconds) is det.
%
% Replace a zero raw duration with Fill.

build:fill_seconds(Fill, 0, Fill) :- !.
build:fill_seconds(_, Seconds, Seconds).


%! build:median_seconds(+List, -Median) is det.
%
% Median of a non-empty list of durations. An even count uses the mean
% of the two central values.

build:median_seconds(List, Median) :-
  msort(List, Sorted),
  length(Sorted, N),
  Mid is N // 2,
  ( N mod 2 =:= 1
  -> nth0(Mid, Sorted, Median)
  ;  Mid1 is Mid - 1,
     nth0(Mid1, Sorted, Lo),
     nth0(Mid, Sorted, Hi),
     Median is (Lo + Hi) / 2
  ).


%! build:accumulate_duration(+Live, +Durations, +Done0, -Done, +Left0, -Left) is det.
%
% Add each phase's duration to the spent total or the remainder.
% `done` is fully spent. `progress(P)` spends P percent of the duration.
% Any other live status (active, pending) is still ahead.

build:accumulate_duration([], [], Done, Done, Left, Left).
build:accumulate_duration([_-done|Ps], [W|Ws], D0, Done, L0, Left) :-
  !,
  D1 is D0 + W,
  build:accumulate_duration(Ps, Ws, D1, Done, L0, Left).
build:accumulate_duration([_-progress(P)|Ps], [W|Ws], D0, Done, L0, Left) :-
  !,
  Frac is max(0, min(100, P)) / 100,
  D1 is D0 + W * Frac,
  L1 is L0 + W * (1 - Frac),
  build:accumulate_duration(Ps, Ws, D1, Done, L1, Left).
build:accumulate_duration([_|Ps], [W|Ws], D0, Done, L0, Left) :-
  L1 is L0 + W,
  build:accumulate_duration(Ps, Ws, D0, Done, L1, Left).


%! build:right_edge_download(+Pct, +Speed) is det.
%
% Download percentage at the right edge, the same place an install
% shows its phase percentage. Speed is bytes per second, or 0.

build:right_edge_download(Pct, Speed) :-
  ( Speed > 0
  -> message:convert_bytes(Speed, SpeedStr),
     format(atom(Label), '(~d%)  ~w/s', [Pct, SpeedStr])
  ;  format(atom(Label), '(~d%)', [Pct])
  ),
  atom_length(Label, Len),
  message:at_right_edge(Len,
    ( message:color(cyan),
      message:print(Label),
      message:color(normal) )).


%! build:right_edge_progress(+AccPct, +Current, +LiveTotal, +Remain) is det.
%
% Print "(AccPct%) Current/LiveTotal" at the right edge of the terminal.
% Remain `seconds(N)` appends "ETA <duration>". Remain `none` does not.

build:right_edge_progress(AccPct, Current, LiveTotal, Remain) :-
  build:eta_label(AccPct, Current, LiveTotal, Remain, Label),
  atom_length(Label, Len),
  message:at_right_edge(Len,
    ( message:color(cyan),
      message:print(Label),
      message:color(normal) )).


%! build:eta_label(+AccPct, +Current, +LiveTotal, +Remain, -Label) is det.
%
% Right-edge text. Remain is `none` or `seconds(N)`.

build:eta_label(AccPct, Current, LiveTotal, none, Label) :-
  !,
  format(atom(Label), '(~d%) ~d/~d', [AccPct, Current, LiveTotal]).
build:eta_label(AccPct, Current, LiveTotal, seconds(Secs), Label) :-
  build:format_eta(Secs, Eta),
  format(atom(Label), '(~d%) ~d/~d  ETA ~w', [AccPct, Current, LiveTotal, Eta]).



%! build:format_eta(+Seconds, -Formatted) is det.
%
% Format a remaining time as "12s", "4m 12s", or "1h 5m".

build:format_eta(Seconds, Formatted) :-
  S is max(0, round(Seconds)),
  ( S >= 3600
  -> Hours is S // 3600,
     Rem is S mod 3600,
     Mins is Rem // 60,
     format(atom(Formatted), '~wh ~wm', [Hours, Mins])
  ;  S >= 60
  -> Mins is S // 60,
     Secs is S mod 60,
     format(atom(Formatted), '~wm ~ws', [Mins, Secs])
  ;  format(atom(Formatted), '~ws', [S])
  ).


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
%  Exec phase line count (for slot layout computation)
% =============================================================================

%! build:exec_phase_line_count(+PhaseList, -NumLines) is det.
%
% Computes how many display lines the exec phase list will occupy.
% Wrapping is only used for short style; fancy and column always render
% phases on a single line (required for ANSI in-place updates).

build:exec_phase_line_count(_, 1) :-
  \+ console:printing_style('short'), !.

build:exec_phase_line_count(PhaseList, NumLines) :-
  catch(
    ( console:printing_tty_size(_, TermWidth),
      build:exec_content_start_col(StartCol),
      build:count_phase_lines(PhaseList, StartCol, TermWidth, StartCol, 1, NumLines)
    ),
    _,
    NumLines = 1
  ).

build:exec_content_start_col(Col) :-
  ( console:printing_style('fancy') ->
    Col = 48
  ; console:printing_style('column') ->
    Col = 117
  ; Col = 37
  ).

build:count_phase_lines([], _, _, _, N, N).

build:count_phase_lines([Phase|Rest], StartCol, TermWidth, Col, Acc, N) :-
  atom_length(Phase, PLen),
  Need is PLen + 4,
  ( Col + Need > TermWidth - 12, Col > StartCol ->
    Acc1 is Acc + 1,
    NewCol is StartCol + PLen + 4
  ; Acc1 = Acc,
    NewCol is Col + PLen + 4
  ),
  build:count_phase_lines(Rest, StartCol, TermWidth, NewCol, Acc1, N).


% =============================================================================
%  Summary
% =============================================================================

%! build:print_emerging(+Header) is det.
%
% The same `>>> Emerging` line the pretend plan prints, above the live
% display.

build:print_emerging(Header) :-
  is_list(Header),
  Header \== [],
  !,
  nl,
  message:header('Emerging ', Header).
build:print_emerging(Header) :-
  nl,
  message:header('Emerging ', [Header]).


%! build:summary(+Plan, +PreActions, +Failed, +Stubs) is det.
%
% Closing lines in the pretend footer's shape. Counts are the actions
% the plan footer counts (a world register is not one of them). Bytes
% are what this run fetched.

build:summary(Plan, PreActions, Failed, Stubs) :-
  nl,
  plan:footer_stats_from_plan(Plan, S0),
  plan:footer_add_pre_actions(PreActions, S0, S),
  plan:pluralize(S.actions, action, actions, ActionWord),
  build:counted_steps(Plan, PlanSteps),
  ( PreActions == [] -> Steps = PlanSteps ; Steps is PlanSteps + 1 ),
  plan:pluralize(Steps, step, steps, StepWord),
  plan:footer_action_breakdown(S, Breakdown),
  format('Total: Executed ~d ~w (~w), grouped into ~d ~w.',
         [S.actions, ActionWord, Breakdown, Steps, StepWord]),
  ( Failed > 0
  -> format(' ~d failed.', [Failed])
  ;  true
  ),
  ( Stubs > 0
  -> format(' ~d stubbed.', [Stubs])
  ;  true
  ),
  nl,
  build:summary_download_line(S),
  nl,
  build:print_fixup_summary,
  ( catch(warning:print_discovered_bugreport_drafts, _, true) -> true ; true ),
  flush_output.



%! build:summary_download_line(+Stats) is det.
%
% Second summary line. Stats is the pretend footer dict.

build:summary_download_line(S) :-
  AlreadyDl = S.already_dl,
  RemainingDl is S.total_dl - AlreadyDl,
  ( AlreadyDl > 0
  -> message:convert_bytes(RemainingDl, RemStr),
     message:convert_bytes(AlreadyDl, AlrStr),
     format('~7|~w downloaded, ~w already downloaded.~n', [RemStr, AlrStr])
  ;  message:convert_bytes(S.total_dl, BytesStr),
     format('~7|~w downloaded.~n', [BytesStr])
  ).



%! build:counted_steps(+Plan, -N) is det.
%
% Steps that contain an action the pretend footer counts.

build:counted_steps(Plan, N) :-
  include(build:step_has_counted_action, Plan, Steps),
  length(Steps, N).



%! build:step_has_counted_action(+Step) is semidet.
%
% True when Step contributes to the pretend action total.

build:step_has_counted_action(Step) :-
  member(Rule, Step),
  S0 = stats{actions:0, downloads:0, runs:0, installs:0, updates:0,
             downgrades:0, reinstalls:0, total_dl:0, already_dl:0},
  plan:footer_stats_from_rule(Rule, S0, S),
  S.actions > 0,
  !.



%! build:print_fixup_summary is det.
%
% After the build summary, report the domain exception fixups that were
% applied during this build -- build-time workarounds for problems that
% should really be fixed at the ebuild/metadata level (e.g. the #90
% collision-protect deconfliction or the #93 GHC ABI repair). The printer
% is generic: it iterates the mechanisms registered with the fixup
% registry (Source/Domain/Gentoo/Exceptions/fixup.pl) and renders each
% mechanism's own note (fixup:mechanism_note/3) above the affected
% packages, so new exception mechanisms surface here without printer
% changes.

build:print_fixup_summary :-
  ( current_predicate(fixup:mechanism/1)
  -> forall(fixup:mechanism(Mechanism),
            build:print_fixup_mechanism(Mechanism))
  ;  true
  ).


%! build:print_fixup_mechanism(+Mechanism) is det.
%
% Prints one mechanism's applied-fixup block; silent when the mechanism
% applied nothing during this build.

build:print_fixup_mechanism(Mechanism) :-
  findall(Id, fixup:applied(Mechanism, Id, _), Ids0),
  sort(Ids0, Ids),
  ( Ids == []
  -> true
  ;  length(Ids, N),
     ( fixup:mechanism_note(Mechanism, N, Lines)
     -> true
     ;  format(atom(Fallback), 'Fixup ~w applied to ~d package(s):', [Mechanism, N]),
        Lines = [Fallback]
     ),
     message:color(yellow),
     forall(member(Line, Lines), format('~w~n', [Line])),
     message:color(darkgray),
     forall(member(Id, Ids), format('  - ~w~n', [Id])),
     message:color(normal),
     nl
  ).
