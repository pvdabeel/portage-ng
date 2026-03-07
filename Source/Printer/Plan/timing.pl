/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> TIMING
Plan timing output in emerge-compatible format.

Prints started/ended timestamps and wall-time duration lines used by
writer.pl when generating .merge files.
*/

:- module(timing, []).


%! timing:print_timing_header(+Label, +T0) is det
%
% Print a "% <Label> started: <epoch> (<human>)" line to current output.

timing:print_timing_header(Label, T0) :-
  Epoch is truncate(T0),
  format_time(string(Human), "%Y-%m-%d %H:%M:%S", T0),
  format("% ~w started: ~w (~w)~n", [Label, Epoch, Human]).


%! timing:print_timing_footer(+Label, +T0) is det
%
% Print ended + wall_time_ms lines matching the emerge format.

timing:print_timing_footer(Label, T0) :-
  get_time(T1),
  Epoch1 is truncate(T1),
  WallMs is truncate((T1 - T0) * 1000),
  format_time(string(Human1), "%Y-%m-%d %H:%M:%S", T1),
  format("% ~w ended: ~w (~w)~n", [Label, Epoch1, Human1]),
  format("% ~w wall_time_ms: ~w~n", [Label, WallMs]).
