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


%! build:header is det.
%
% Print a header line between the plan output and the progress area,
% matching the style of the plan header.

build:header :-
  message:color(green),
  message:print('Progress merging the packages:'),
  message:color(normal),
  nl, nl.


% =============================================================================
%  Slot-based display
% =============================================================================

%! build:print_job_slots(+SlottedJobs, +TotalSteps) is det.
%
% Print one line per job in the step, all initially in "pending" state.
% After printing, the cursor parks on a blank line below all slots.
% SlottedJobs is a list of slotted(Slot, NumSlots, StepN, TotalSteps, Rule) terms.

build:print_job_slots([], _TotalSteps) :- !.

build:print_job_slots([slotted(_Slot, _NumSlots, StepN, TotalSteps, rule(_Repo://Entry:Action?{_Ctx}, _Body))|Rest], _) :-
  format(atom(Counter), '[~d/~d]', [StepN, TotalSteps]),
  message:color(darkgray),
  format(' ~w  ~~ ~w', [Counter, Action]),
  message:column(30, Entry),
  message:color(normal),
  nl,
  build:print_job_slots(Rest, TotalSteps).

build:print_job_slots([_|Rest], TotalSteps) :-
  build:print_job_slots(Rest, TotalSteps).


%! build:update_slot(+Slot, +NumSlots, +Status, +StepN, +TotalSteps, +Action, +Entry) is det.
%
% Update a specific slot line in-place using ANSI cursor movement.
% Must be called inside with_mutex(build_display, ...).
%
% Cursor protocol:
%   cursor up (NumSlots - Slot) lines
%   move to column 1
%   print new content + erase to EOL
%   cursor down (NumSlots - Slot) lines

build:update_slot(Slot, NumSlots, Status, StepN, TotalSteps, Action, Entry) :-
  LinesUp is NumSlots - Slot,
  format("\e[~dA\e[1G", [LinesUp]),
  build:render_slot(Status, StepN, TotalSteps, Action, Entry),
  message:el,
  format("\e[~dB\e[1G", [LinesUp]),
  flush_output.


%! build:render_slot(+Status, +StepN, +TotalSteps, +Action, +Entry) is det.
%
% Render the content of a slot line based on its status.

build:render_slot(pending, StepN, TotalSteps, Action, Entry) :-
  format(atom(Counter), '[~d/~d]', [StepN, TotalSteps]),
  message:color(darkgray),
  format(' ~w  ~~ ~w', [Counter, Action]),
  message:column(30, Entry),
  message:color(normal).

build:render_slot(active, StepN, TotalSteps, Action, Entry) :-
  format(atom(Counter), '[~d/~d]', [StepN, TotalSteps]),
  message:color(cyan),
  format(' ~w  > ~w', [Counter, Action]),
  message:column(30, Entry),
  message:color(normal).

build:render_slot(done, StepN, TotalSteps, Action, Entry) :-
  format(atom(Counter), '[~d/~d]', [StepN, TotalSteps]),
  message:color(green),
  format(' ~w  * ~w', [Counter, Action]),
  message:column(30, Entry),
  message:color(normal).

build:render_slot(failed(Reason), StepN, TotalSteps, Action, Entry) :-
  format(atom(Counter), '[~d/~d]', [StepN, TotalSteps]),
  message:color(red),
  format(' ~w  ! ~w', [Counter, Action]),
  message:column(30, Entry),
  format(' (~w)', [Reason]),
  message:color(normal).

build:render_slot(failed, StepN, TotalSteps, Action, Entry) :-
  build:render_slot(failed('error'), StepN, TotalSteps, Action, Entry).

build:render_slot(stub, StepN, TotalSteps, Action, Entry) :-
  format(atom(Counter), '[~d/~d]', [StepN, TotalSteps]),
  message:color(darkgray),
  format(' ~w    ~w', [Counter, Action]),
  message:column(30, Entry),
  message:print(' (stub)'),
  message:color(normal).


% =============================================================================
%  Summary
% =============================================================================

%! build:summary(+Completed, +Failed, +Stubs) is det.
%
% Print a summary line at the end of the build.

build:summary(Completed, Failed, Stubs) :-
  nl,
  message:color(green),
  format(' Completed: ~d', [Completed]),
  message:color(normal),
  ( Failed > 0
  -> format('  '),
     message:color(red),
     format('Failed: ~d', [Failed]),
     message:color(normal)
  ;  true
  ),
  ( Stubs > 0
  -> format('  '),
     message:color(darkgray),
     format('Stubs: ~d', [Stubs]),
     message:color(normal)
  ;  true
  ),
  nl.
