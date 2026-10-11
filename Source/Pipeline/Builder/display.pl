/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> DISPLAY
Build display layout math and slot registry.

Pre-allocates the live progress area shown below the printed plan:
assigns each executable rule its display line offset (slotted/7 terms),
determines per-rule sub-line counts (distfile sub-slots, exec phase
lines, configuration lines), and keeps the slot-info registry that the
builder's result handler uses to map a completed job back to its
step/action/entry for rendering.

Actual line rendering lives in the build printer
(Source/Pipeline/Printer/Build/build.pl); this module only computes
layout and bookkeeping.
*/

:- module(display, []).

% =============================================================================
%  DISPLAY declarations
% =============================================================================

:- dynamic display:slot_info/6.

% -----------------------------------------------------------------------------
%  Pre-action steps (keyword/unmask/use_change)
% -----------------------------------------------------------------------------

%! display:print_pre_action_step(+PreActions, +PreSteps) is det.
%
% Renders pre-actions (keyword acceptance, unmask, use flag changes) as
% a completed step in the build display, matching the plan printer's
% format. These are informational — the prover already assumed them.

display:print_pre_action_step([], _) :- !.

display:print_pre_action_step(PreActions, _PreSteps) :-
  format(atom(AtomStepNum), '~t~0f~2|', [1]),
  format(atom(StepLabel), 'step ~a', [AtomStepNum]),
  write(' \u2514\u2500'),
  message:bubble(darkgray, StepLabel),
  write('\u2500\u2524 '),
  display:print_pre_actions(PreActions),
  nl, nl.


%! display:print_pre_actions(+PreActions) is det.

display:print_pre_actions([Action]) :-
  !,
  display:print_pre_action(Action),
  message:right_edge_ok.

display:print_pre_actions([Action|Rest]) :-
  display:print_pre_action(Action),
  message:right_edge_ok,
  forall(member(A, Rest),
         ( nl,
           write('             \u2502 '),
           display:print_pre_action(A),
           message:right_edge_ok
         )).


%! display:print_pre_action(+PreAction) is det.
%
% Delegates to the shared plan:print_pre_action_core/2 with ShowUseFlags
% false, so use_change flags are not wrapped inline (the build display has
% a fixed right-edge layout).

display:print_pre_action(Action) :-
  plan:print_pre_action_core(Action, false).


% -----------------------------------------------------------------------------
%  Slot layout
% -----------------------------------------------------------------------------

%! display:assign_slots(+Rules, +PlanStep, +NumSteps, -SlottedJobs, -TotalLines) is det.
%
% Pre-allocate the display layout. For download/fetchonly rules, queries
% distfile specs to determine file sub-line count. Each slotted/7 term
% carries its absolute LineOffset, plan step number, within-step action
% index (0-based), and a shared TotalLines variable (bound when the
% last rule is processed).

display:assign_slots(Rules, PlanStep, NumSteps, SlottedJobs, TotalLines) :-
  distfiles:get_location(Distdir),
  display:assign_slots_(Rules, PlanStep, NumSteps, Distdir, 0, 0, TotalLines, SlottedJobs).

display:assign_slots_([], _PlanStep, _NumSteps, _Distdir, LineOff, _ActionIdx, LineOff, []).

display:assign_slots_([Rule|Rest], PlanStep, NumSteps, Distdir, LineOff, ActionIdx, TotalLines, [Slotted|More]) :-
  display:rule_file_info(Rule, Distdir, LineOff, FileInfo, LinesForRule),
  NextLineOff is LineOff + LinesForRule,
  Slotted = slotted(LineOff, TotalLines, PlanStep, NumSteps, ActionIdx, Rule, FileInfo),
  ActionIdx1 is ActionIdx + 1,
  display:assign_slots_(Rest, PlanStep, NumSteps, Distdir, NextLineOff, ActionIdx1, TotalLines, More).


%! display:rule_file_info(+Rule, +Distdir, +LineOff, -FileInfo, -Lines) is det.
%
% Determine file metadata for a rule. Downloads with distfiles get
% files(FileStartLine, NumFiles, DistFiles, Distdir); others get no_files.

display:rule_file_info(rule(Repo://Entry:Action?{_Ctx}, _Body), _Distdir, LineOff, FileInfo, Lines) :-
  memberchk(Action, [download, fetchonly]),
  Repo:get_type(eapi),
  predicate_property(ebuild:is_live(_), defined),
  ebuild:is_live(Repo://Entry),
  !,
  LiveStartLine is LineOff + 1,
  FileInfo = live_source(LiveStartLine),
  Lines = 2.

display:rule_file_info(rule(Repo://Entry:Action?{_Ctx}, _Body), Distdir, LineOff, FileInfo, Lines) :-
  memberchk(Action, [download, fetchonly]),
  Repo:get_type(eapi),
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

display:rule_file_info(rule(Repo://Entry:Action?{Ctx}, _Body), _Distdir, LineOff, SubInfo, Lines) :-
  \+ memberchk(Action, [download, fetchonly]),
  Repo:get_type(eapi),
  predicate_property(ebuild_exec:display_phases(_,_,_,_,_), defined),
  catch(ebuild_exec:display_phases(Action, Repo, Entry, Ctx, PhaseList), _, fail),
  PhaseList \= [],
  !,
  ExecLine is LineOff + 1,
  build:exec_phase_line_count(PhaseList, ExecLineCount),
  display:count_conf_lines(Repo, Entry, Action, Ctx, ConfCount),
  ( predicate_property(ebuild_exec:build_log_path(_,_), defined)
  -> catch(ebuild_exec:build_log_path(Entry, LogPath), _, LogPath = '')
  ;  LogPath = ''
  ),
  ( catch(config:show_build_logs(true), _, fail)
  -> LogsLine is ExecLine + ExecLineCount,
     SubInfo = phases(ExecLine, ExecLineCount, LogsLine, PhaseList, LogPath),
     Lines is 1 + ConfCount + ExecLineCount + 1
  ;  SubInfo = phases(ExecLine, ExecLineCount, -1, PhaseList, LogPath),
     Lines is 1 + ConfCount + ExecLineCount
  ).

display:rule_file_info(_, _, _, no_files, 1).


%! display:count_conf_lines(+Repo, +Entry, +Action, +Ctx, -Count) is det.
%
% Count how many display lines useflags:print_config would produce for
% this rule (USE flags, USE_EXPAND variables, slot info). Captures
% the output and counts newlines to stay consistent with the plan printer.

display:count_conf_lines(Repo, Entry, Action, Ctx, Count) :-
  memberchk(Action, [install, update, downgrade, reinstall]),
  !,
  display:count_conf_lines_as_short(Repo, Entry, Action, Ctx, Count).
display:count_conf_lines(_, _, _, _, 0).


%! display:count_conf_lines_as_short(+Repo, +Entry, +Action, +Ctx, -Count) is det.
%
% Count config lines as if printing style were 'short'. In 'column' mode
% the probe renders with an explicit 'short' style argument
% (useflags:print_config/2) instead of flipping the process-global
% config:interface_printing_style, so jobserver worker threads rendering
% slots concurrently are unaffected.

display:count_conf_lines_as_short(Repo, Entry, Action, Ctx, Count) :-
  ( console:printing_style('column')
  -> Style = 'short'
  ;  console:printing_style(Style)
  ),
  with_output_to(string(S),
    catch(useflags:print_config(Style, Repo://Entry:Action?{Ctx}), _, true)),
  split_string(S, "\n", "", Parts),
  length(Parts, N),
  Count is max(0, N - 1).


% -----------------------------------------------------------------------------
%  Slot info registry
% -----------------------------------------------------------------------------

%! display:register_slot_info(+SlottedJobs) is det.
%
% Store slot metadata so the result handler can look up step/action/entry
% for display without needing the original job term.

display:register_slot_info([]).

display:register_slot_info([slotted(LineOff, _TotalLines, PlanStep, NumSteps, ActionIdx, rule(Repo://Entry:Action?{_Ctx}, _Body), _FileInfo)|Rest]) :-
  !,
  assertz(display:slot_info(LineOff, PlanStep, NumSteps, ActionIdx, Action, Repo://Entry)),
  display:register_slot_info(Rest).

display:register_slot_info([slotted(LineOff, _TotalLines, PlanStep, NumSteps, ActionIdx, rule(world(Atom):Action?{_Ctx}, _Body), _FileInfo)|Rest]) :-
  !,
  assertz(display:slot_info(LineOff, PlanStep, NumSteps, ActionIdx, Action, Atom)),
  display:register_slot_info(Rest).

display:register_slot_info([_|Rest]) :-
  display:register_slot_info(Rest).


%! display:clear_slot_info is det.

display:clear_slot_info :-
  retractall(display:slot_info(_, _, _, _, _, _)).


%! display:get_slot_info(+Slot, -PlanStep, -NumSteps, -ActionIdx, -Action, -Entry) is det.

display:get_slot_info(Slot, PlanStep, NumSteps, ActionIdx, Action, Entry) :-
  display:slot_info(Slot, PlanStep, NumSteps, ActionIdx, Action, Entry), !.

display:get_slot_info(_Slot, 0, 0, 0, unknown, unknown).


% -----------------------------------------------------------------------------
%  Skipped step rendering
% -----------------------------------------------------------------------------

%! display:mark_skipped(+SlottedJobs, +TotalLines) is det.
%
% Mark all slots in a skipped step as failed (dependency not met).

display:mark_skipped([], _).

display:mark_skipped([slotted(LineOff, TotalLines, PlanStep, NumSteps, ActionIdx, rule(Repo://Entry:Action?{_Ctx}, _Body), _FileInfo)|Rest], _) :-
  !,
  with_mutex(build_display,
    build:update_slot(LineOff, TotalLines, skipped, PlanStep, NumSteps, ActionIdx, Action, Repo://Entry)),
  display:mark_skipped(Rest, TotalLines).

display:mark_skipped([slotted(LineOff, TotalLines, PlanStep, NumSteps, ActionIdx, rule(world(Atom):Action?{_Ctx}, _Body), _FileInfo)|Rest], _) :-
  !,
  with_mutex(build_display,
    build:update_slot(LineOff, TotalLines, skipped, PlanStep, NumSteps, ActionIdx, Action, Atom)),
  display:mark_skipped(Rest, TotalLines).

display:mark_skipped([_|Rest], TotalLines) :-
  display:mark_skipped(Rest, TotalLines).
