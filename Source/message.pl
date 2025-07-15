/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005‑2025, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of
  this project.
*/

/** <module> MESSAGE
This file contains the predicates used for pretty printing messages.
*/

:- module(message, [clear/0]).

% =============================================================================
%  MESSAGE declarations
% =============================================================================


% -----------------------------------------------------------------------------
%  Declarations
% -----------------------------------------------------------------------------

% The following predicates can be called, but depend on goal expansion
% to expand them into low level output predicates directly manipulating
% the output stream

:- multifile user:goal_expansion/2.

message:color(_).
message:style(_).
message:el.
message:hc.
message:sc.
message:bl.
message:cl.
message:clean.
message:title_reset.
message:title(_).
message:print(_).
message:column(_,_).
message:level(_).
message:msg(_,_,_).
message:msg(_,_).
message:scroll_msg(_,_).
message:failure(_).
message:warning(_).
message:success(_).
message:inform(_).
message:notice(_).
message:debug(_).
message:log(_).
message:scroll(_).
message:scroll_failure(_).
message:scroll_warning(_).
message:scroll_success(_).
message:scroll_inform(_).
message:scroll_notice(_).
message:scroll_debug(_).
message:scroll_log(_).


% -----------------------------------------------------------------------------
%  Goal expansion: Color
% -----------------------------------------------------------------------------

user:goal_expansion(color(red),            format("\e[31m",[])).
user:goal_expansion(color(green),          format("\e[32m",[])).
user:goal_expansion(color(orange),         format("\e[33m",[])).
user:goal_expansion(color(blue),           format("\e[34m",[])).
user:goal_expansion(color(magenta),        format("\e[35m",[])).
user:goal_expansion(color(cyan),           format("\e[36m",[])).
user:goal_expansion(color(lightgray),      format("\e[37m",[])).
user:goal_expansion(color(darkgray),       format("\e[90m",[])).
user:goal_expansion(color(lightred),       format("\e[91m",[])).
user:goal_expansion(color(lightgreen),     format("\e[92m",[])).
user:goal_expansion(color(lightorange),    format("\e[93m",[])).
user:goal_expansion(color(lightblue),      format("\e[94m",[])).
user:goal_expansion(color(lightmagenta),   format("\e[95m",[])).
user:goal_expansion(color(lightcyan),      format("\e[96m",[])).
user:goal_expansion(color(normal),         format("\e[00m",[])).


% -----------------------------------------------------------------------------
%  Goal expansion: Style
% -----------------------------------------------------------------------------

user:goal_expansion(style(normal),         format("\e[00m",[])).
user:goal_expansion(style(bold),           format("\e[01m",[])).
user:goal_expansion(style(dim),            format("\e[02m",[])).
user:goal_expansion(style(italic),         format("\e[03m",[])).
user:goal_expansion(style(underline),      format("\e[04m",[])).
user:goal_expansion(style(blink),          format("\e[05m",[])).


% -----------------------------------------------------------------------------
%  Goal expansion: Cursor
% -----------------------------------------------------------------------------

user:goal_expansion(el,                    format("\e[K",[])).
user:goal_expansion(hc,                    format("\e[?25l",[])).
user:goal_expansion(sc,                    format("\e[?25h",[])).
user:goal_expansion(bl,                    format("\e[1G",[])).
user:goal_expansion(cl,                    format("\e[2J\e[H",[])).
user:goal_expansion(clean,                 format("\e[K",[])).


% -----------------------------------------------------------------------------
%  Goal expansion: Label
% -----------------------------------------------------------------------------

user:goal_expansion(label(success),
  ( style(bold),
    color(green),
    format('[SUCCESS] ',[]) )) :- !.

user:goal_expansion(label(warning),
  ( style(bold),
    color(orange),
    format('[WARNING] ',[]) )) :- !.

user:goal_expansion(label(failure),
  ( style(bold),
    format('[FAILURE] ',[]) )) :- !.

user:goal_expansion(label(inform),
  ( format('% ',[]) )) :- !.

user:goal_expansion(label(notice),
  ( color(darkgray),
    format('% ',[]) )) :- !.

user:goal_expansion(label(debug),
  ( color(magenta),
    format('[DEBUG]   ',[]) )) :- !.

user:goal_expansion(label(log),
  ( color(darkgray),
    format('% ',[]) )) :- !.

user:goal_expansion(label(_),
  ( true )).


% -----------------------------------------------------------------------------
%  Goal expansion: Core messaging
% -----------------------------------------------------------------------------

user:goal_expansion(msg(Scroll,Level,Msg),
  ( message:label(Level),
    Output,
    Post,
    Continue )) :-
  ( ( is_list(Msg)
      -> Output = (atomic_list_concat(Msg,String),format(String,[]))
      ;  Output = (format(Msg,[])) ),
    ( Scroll == true
      -> Post = (message:el,message:bl,flush_output)
      ;  Post = nl ),
    ( Level == failure
      -> Continue = fail
      ;  Continue = true ) ).

user:goal_expansion(msg(Level,Msg),        msg(false,Level,Msg)).
user:goal_expansion(scroll_msg(Level,Msg), msg(true,Level,Msg)).


% -----------------------------------------------------------------------------
%  Goal expansion: Shortcuts
% -----------------------------------------------------------------------------

user:goal_expansion(failure(T),            msg(failure, T)).
user:goal_expansion(warning(T),            msg(warning, T)).
user:goal_expansion(success(T),            msg(success, T)).
user:goal_expansion(inform(T),             msg(inform,  T)).
user:goal_expansion(notice(T),             msg(notice,  T)).
user:goal_expansion(debug(T),              msg(debug,   T)).

user:goal_expansion(scroll(T),             scroll_msg(inform,  T)).
user:goal_expansion(scroll_failure(T),     scroll_msg(failure, T)).
user:goal_expansion(scroll_warning(T),     scroll_msg(warning, T)).
user:goal_expansion(scroll_success(T),     scroll_msg(success, T)).
user:goal_expansion(scroll_inform(T),      scroll_msg(inform,  T)).
user:goal_expansion(scroll_notice(T),      scroll_msg(notice,  T)).
user:goal_expansion(scroll_debug(T),       scroll_msg(debug,   T)).

user:goal_expansion(log(T),                Expanded) :-
  ( config:verbose(true)
    -> Expanded = msg(log,T)
    ;  Expanded = true ).

user:goal_expansion(scroll_log(T),         Expanded) :-
  ( config:verbose(true)
    -> Expanded = scroll_msg(log,T)
    ;  Expanded = true ).


% -----------------------------------------------------------------------------
%  Goal expansion: Title
% -----------------------------------------------------------------------------

user:goal_expansion(title_reset,           format(Expanded,[])) :-
  config:name(String),
  format(string(Expanded),'\e]0;~s\a',
         [String]).

user:goal_expansion(title(List),           Expanded) :-
  is_list(List),!,
  Expanded = (atomic_list_concat(List,String),
              format('\e]0;~s\a',[String])).

user:goal_expansion(title(String),         format(Expanded,[])) :-
  format(string(Expanded),'\e]0;~s\a',
         [String]).


% -----------------------------------------------------------------------------
%  Goal expansion: Printing
% -----------------------------------------------------------------------------

user:goal_expansion(print(Term),           Expanded) :-
  ( atomic(Term)
    ->  Expanded = format(Term,[])
    ;   Expanded = write(Term) ).


user:goal_expansion(column(N, Msg),        format('~*| ~w', [N, Msg])).

% -----------------------------------------------------------------------------
%  Runtime: Gradients
% -----------------------------------------------------------------------------

% --- Color definitions ---

message:gradient_start_color(R, G, B) :- R = 120,  G = 255,  B = 255.
message:gradient_end_color(R, G, B)   :- R = 60,   G = 255,  B = 40.


% --- Predicate to print a string with a gradient ---

message:print_gradient(Text) :-
  string_chars(Text, Chars),
  length(Chars, Length),
  (  Length > 0
  -> message:gradient_print_chars(Chars, 0, Length)
  ;  true
  ).


% --- Helper predicate to iterate through characters ---

message:gradient_print_chars([], _, _).
message:gradient_print_chars([Char|Chars], Index, Length) :-

  % Calculate interpolated RGB color
  message:gradient_interpolate_color(Index, Length, R, G, B),

  % Convert RGB to the nearest 8-bit color code
  message:gradient_rgb_to_8bit(R, G, B, ColorCode),

  % Print the character with the 8-bit color
  ansi_format([fg8(ColorCode)], '~s', [Char]),

  % Process the rest of the string
  NextIndex is Index + 1,
  message:gradient_print_chars(Chars, NextIndex, Length).


% --- Color interpolation logic ---

message:gradient_interpolate_color(Index, Length, R, G, B) :-
    message:gradient_start_color(R1, G1, B1),
    message:gradient_end_color(R2, G2, B2),
    Ratio is Index / max(1, Length - 1),
    R is round(R1 + (R2 - R1) * Ratio),
    G is round(G1 + (G2 - G1) * Ratio),
    B is round(B1 + (B2 - B1) * Ratio).


% --- RGB to 8-bit (256 color) conversion ---

message:gradient_rgb_to_8bit(R, G, B, Code) :-

  % Scale RGB values from 0-255 to 0-5
  R_scaled is round(R / 255 * 5),
  G_scaled is round(G / 255 * 5),
  B_scaled is round(B / 255 * 5),

  % Calculate the color code in the 6x6x6 cube
  Code is 16 + (36 * R_scaled) + (6 * G_scaled) + B_scaled.


% --- Main entry point for execution ---

message:logo(List) :-
  atomic_list_concat(List,String),
  message:print_gradient(String),nl.


% -----------------------------------------------------------------------------
%  Runtime: Lines and colums
% -----------------------------------------------------------------------------

eend(Msg) :-
  tty_size(_,W),
  Col is W - 2,
  format('~t~a~*|', [Msg, Col]).

hl(Title) :-
  tty_size(_,W),
  atom_chars('-', [C]),
  atomic_list_concat(['--- ',Title,' ~`', C, 't~*|\n'], Fmt),
  write('\r'),
  format(Fmt, [W]).

hl :-
  tty_size(_,W),
  atom_chars('-', [C]),
  atomic_list_concat(['~`', C, 't~*|\n'], Fmt),
  write('\r'),
  format(Fmt, [W]).


% -----------------------------------------------------------------------------
%  Runtime: Headers
% -----------------------------------------------------------------------------

topheader(Message) :-
  color(cyan),
  style(bold),
  msg_atom(Message, Atom),
  format('### ~s', [Atom]),
  color(normal),
  nl, nl.

header(Message) :-
  color(lightorange),
  style(bold),
  msg_atom(Message, Atom),
  format('>>> ~s', [Atom]),
  color(normal),
  nl.

header(Header, [First | Rest]) :-
  color(lightorange),
  color(bold),
  format('>>> ~w: ~w', [Header, First]),
  nl,
  forall(member(Item, Rest),
         ( msg_atom(Item,String), format('               ~s~n', [String]) )),
  color(normal),
  nl.


% -----------------------------------------------------------------------------
%  Header helpers
% -----------------------------------------------------------------------------

msg_atom(List, Atom) :-
  is_list(List),
  !,
  maplist(msg_atom,List,Atoms),
  atomic_list_concat(Atoms,Atom).

msg_atom(Atomic, Atomic) :-
  atomic(Atomic),
  !.

msg_atom(Var, Atom) :-
  var(Var),
  !,
  term_to_atom(Var, Atom).

msg_atom(Compound, Atom) :-
  term_to_atom(Compound, Atom).


% -----------------------------------------------------------------------------
%  Convertor: Byte
% -----------------------------------------------------------------------------

convert_bytes(Bytes, String) :-
  (   Bytes >= 1 << 30
  ->  Unit = 'Gb', Value is Bytes / (1 << 30)
  ;   Bytes >= 1 << 20
  ->  Unit = 'Mb', Value is Bytes / (1 << 20)
  ;   Unit = 'Kb',  Value is Bytes / (1 << 10)
  ),
  format(string(String), '~2f ~w', [Value, Unit]).

print_bytes(live) :-
  format('live\t', []).

print_bytes(Bytes) :-
  convert_bytes(Bytes, Atom),
  format('~w\t', [Atom]).


% -----------------------------------------------------------------------------
%  Convertor: Date/time
% -----------------------------------------------------------------------------

datetime(Datetime) :-
  get_time(Stamp),
  stamp_date_time(Stamp, DT, 'local'),
  format_time(atom(Datetime), '%a %d %b %Y %T', DT).


% -----------------------------------------------------------------------------
%  Misc helpers
% -----------------------------------------------------------------------------

clear :- cl.

wrap(Goal) :-
  color(green),
  format('--- Executing ',[]),
  color(normal),
  write(Goal),
  nl,
  call(Goal),
  nl.