/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005‑2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of
  this project.
*/


/** <module> MESSAGE
Pretty-printing infrastructure for portage-ng. All high-level output
predicates (color, style, label, msg, header, etc.) are declared as
thin stubs here and compiled away by goal_expansion/2 into direct
ANSI escape sequences at load time. This gives zero-overhead messaging
in production while keeping call sites readable.

Debug messaging (debug_msg/1..3, debug_write/1, debug_writeln/1) is
conditionally compiled via the SWI-Prolog `-Ddebug` flag: when debug
is disabled, calls expand to `true` (no overhead).
*/

:- module(message, [clear/0]).

% =============================================================================
%  MESSAGE declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Goal expansion declarations
% -----------------------------------------------------------------------------
%
% The following predicates are declared as stubs so they can be called by
% other modules. At load time, goal_expansion/2 replaces each call with
% the corresponding low-level ANSI escape or output predicate, so no
% runtime dispatch occurs.

:- multifile user:goal_expansion/2.

% - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
%  Debug messaging (compile-time conditional via -Ddebug)
% - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

user:goal_expansion(debug_msg(Msg), Expanded) :-
    current_prolog_flag(debug, true) ->
        Expanded = (message:label(debug), format(Msg, []), nl)
    ;
        Expanded = true.

user:goal_expansion(debug_msg(Fmt, Args), Expanded) :-
    current_prolog_flag(debug, true) ->
        Expanded = (message:label(debug), format(Fmt, Args), nl)
    ;
        Expanded = true.

user:goal_expansion(debug_write(Term), Expanded) :-
    current_prolog_flag(debug, true) ->
        Expanded = (message:label(debug), write(Term))
    ;
        Expanded = true.

user:goal_expansion(debug_writeln(Term), Expanded) :-
    current_prolog_flag(debug, true) ->
        Expanded = (message:label(debug), write(Term), nl)
    ;
        Expanded = true.

user:goal_expansion(debug_msg(Label, Msg), Expanded) :-
    current_prolog_flag(debug, true) ->
        Expanded = (message:label(debug), format('~s: ', [Label]), format(Msg, []), nl)
    ;
        Expanded = true.

user:goal_expansion(debug_msg(Label, Fmt, Args), Expanded) :-
    current_prolog_flag(debug, true) ->
        Expanded = (message:label(debug), format('~s: ', [Label]), format(Fmt, Args), nl)
    ;
        Expanded = true.

% - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
%  Stub declarations (expanded away at load time by goal_expansion/2)
% - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

message:color(_).
message:bgcolor(_).
message:bubble(_,_).
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
%  Goal expansion: Foreground color
% -----------------------------------------------------------------------------

user:goal_expansion(color(red),            ansi_term:keep_line_pos(current_output,format("\e[31m",[]))).
user:goal_expansion(color(green),          ansi_term:keep_line_pos(current_output,format("\e[32m",[]))).
user:goal_expansion(color(orange),         ansi_term:keep_line_pos(current_output,format("\e[33m",[]))).
user:goal_expansion(color(blue),           ansi_term:keep_line_pos(current_output,format("\e[34m",[]))).
user:goal_expansion(color(magenta),        ansi_term:keep_line_pos(current_output,format("\e[35m",[]))).
user:goal_expansion(color(cyan),           ansi_term:keep_line_pos(current_output,format("\e[36m",[]))).
user:goal_expansion(color(lightgray),      ansi_term:keep_line_pos(current_output,format("\e[37m",[]))).
user:goal_expansion(color(darkgray),       ansi_term:keep_line_pos(current_output,format("\e[90m",[]))).
user:goal_expansion(color(lightred),       ansi_term:keep_line_pos(current_output,format("\e[91m",[]))).
user:goal_expansion(color(lightgreen),     ansi_term:keep_line_pos(current_output,format("\e[92m",[]))).
user:goal_expansion(color(lightorange),    ansi_term:keep_line_pos(current_output,format("\e[93m",[]))).
user:goal_expansion(color(lightblue),      ansi_term:keep_line_pos(current_output,format("\e[94m",[]))).
user:goal_expansion(color(lightmagenta),   ansi_term:keep_line_pos(current_output,format("\e[95m",[]))).
user:goal_expansion(color(lightcyan),      ansi_term:keep_line_pos(current_output,format("\e[96m",[]))).
user:goal_expansion(color(normal),         ansi_term:keep_line_pos(current_output,format("\e[00m",[]))).


% -----------------------------------------------------------------------------
%  Goal expansion: Background color
% -----------------------------------------------------------------------------

user:goal_expansion(bgcolor(red),          ansi_term:keep_line_pos(current_output,format("\e[41m",[]))).
user:goal_expansion(bgcolor(green),        ansi_term:keep_line_pos(current_output,format("\e[42m",[]))).
user:goal_expansion(bgcolor(orange),       ansi_term:keep_line_pos(current_output,format("\e[43m",[]))).
user:goal_expansion(bgcolor(blue),         ansi_term:keep_line_pos(current_output,format("\e[44m",[]))).
user:goal_expansion(bgcolor(magenta),      ansi_term:keep_line_pos(current_output,format("\e[45m",[]))).
user:goal_expansion(bgcolor(cyan),         ansi_term:keep_line_pos(current_output,format("\e[46m",[]))).
user:goal_expansion(bgcolor(lightgray),    ansi_term:keep_line_pos(current_output,format("\e[47m",[]))).
user:goal_expansion(bgcolor(darkgray),     ansi_term:keep_line_pos(current_output,format("\e[100m",[]))).
user:goal_expansion(bgcolor(lightred),     ansi_term:keep_line_pos(current_output,format("\e[101m",[]))).
user:goal_expansion(bgcolor(lightgreen),   ansi_term:keep_line_pos(current_output,format("\e[102m",[]))).
user:goal_expansion(bgcolor(lightorange),  ansi_term:keep_line_pos(current_output,format("\e[103m",[]))).
user:goal_expansion(bgcolor(lightblue),    ansi_term:keep_line_pos(current_output,format("\e[104m",[]))).
user:goal_expansion(bgcolor(lightmagenta), ansi_term:keep_line_pos(current_output,format("\e[105m",[]))).
user:goal_expansion(bgcolor(lightcyan),    ansi_term:keep_line_pos(current_output,format("\e[106m",[]))).
user:goal_expansion(bgcolor(normal),       ansi_term:keep_line_pos(current_output,format("\e[00m",[]))).


% -----------------------------------------------------------------------------
%  Goal expansion: Style
% -----------------------------------------------------------------------------

user:goal_expansion(style(normal),         ansi_term:keep_line_pos(current_output,format("\e[00m",[]))).
user:goal_expansion(style(bold),           ansi_term:keep_line_pos(current_output,format("\e[01m",[]))).
user:goal_expansion(style(dim),            ansi_term:keep_line_pos(current_output,format("\e[02m",[]))).
user:goal_expansion(style(italic),         ansi_term:keep_line_pos(current_output,format("\e[03m",[]))).
user:goal_expansion(style(underline),      ansi_term:keep_line_pos(current_output,format("\e[04m",[]))).
user:goal_expansion(style(blink),          ansi_term:keep_line_pos(current_output,format("\e[05m",[]))).


% -----------------------------------------------------------------------------
%  Goal expansion: Cursor
% -----------------------------------------------------------------------------

user:goal_expansion(el,                    format("\e[K",[])).
user:goal_expansion(hc,                    ansi_term:keep_line_pos(current_output,format("\e[?25l",[]))).
user:goal_expansion(sc,                    ansi_term:keep_line_pos(current_output,format("\e[?25h",[]))).
user:goal_expansion(bl,                    format("\e[1G",[])).
user:goal_expansion(cl,                    format("\e[2J\e[H",[])).
user:goal_expansion(clean,                 format("\e[K",[])).


% -----------------------------------------------------------------------------
%  Goal expansion: Label
% -----------------------------------------------------------------------------

user:goal_expansion(bubble(Color,Text),
  ( color(Color),
    format(''),
    color(normal),
    bgcolor(Color),
    format(Text),
    bgcolor(normal),
    color(Color),
    format(''),
    color(normal))) :- !.

user:goal_expansion(label(success),
  ( bubble(green,success),
    format(' ') )) :-!.
    %style(bold),
    %color(green),
    %format('[SUCCESS] ',[]) )) :- !.

user:goal_expansion(label(warning),
  ( bubble(orange,warning),
    format(' ') )) :- !.
    %style(bold),
    %color(orange),
    %format('[WARNING] ',[]) )) :- !.

user:goal_expansion(label(failure),
  ( bubble(red,failure),
    format(' ') )) :- !.
    %style(bold),
    %format('[FAILURE] ',[]) )) :- !.

user:goal_expansion(label(inform),
  ( format('% ',[]) )) :- !.

user:goal_expansion(label(notice),
  ( color(darkgray),
    format('% ',[]) )) :- !.


user:goal_expansion(label(debug),
  ( bubble(magenta,debug),
    format(' ') )) :-!.
    %color(magenta),
    %format('[DEBUG]   ',[]) )) :- !.

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
      % IMPORTANT: `Msg` pieces are data, not a format string.
      % Using `format(String, [])` will interpret any `~` in the message and can
      % crash (e.g. diagnostics containing '~amd64' or similar). Print literally.
      -> Output = (atomic_list_concat(Msg,String),format('~a', [String]))
      ;  Output = (format(Msg,[])) ),
    ( Scroll == true
      -> Post = (message:el,message:bl,flush_output)
      ;  Post = (message:color(normal),nl) ),
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

user:goal_expansion(title_reset,           Expanded) :-
  config:name(String),
  Expanded = (ansi_term:keep_line_pos(current_output,
                                     format('\e]0;~s\a',[String]))).

user:goal_expansion(title(List),           Expanded) :-
  is_list(List),!,
  Expanded = (atomic_list_concat(List,String),
              ansi_term:keep_line_pos(current_output,
                                      format('\e]0;~s\a',[String]))).

user:goal_expansion(title(String),         Expanded) :-
  Expanded = (ansi_term:keep_line_pos(current_output,
                                      format('\e]0;~s\a',[String]))).


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

%! message:gradient_start_color(-R, -G, -B) is det.
%
% Starting RGB color for the gradient used by message:logo/1,2.

message:gradient_start_color(R, G, B) :- R = 120,  G = 255,  B = 255.

%! message:gradient_end_color(-R, -G, -B) is det.
%
% Ending RGB color for the gradient used by message:logo/1,2.

message:gradient_end_color(R, G, B)   :- R = 60,   G = 255,  B = 40.


%! message:print_gradient(+Text) is det.
%
% Prints Text character by character with a smooth color gradient
% interpolated between gradient_start_color and gradient_end_color.

message:print_gradient(Text) :-
  string_chars(Text, Chars),
  length(Chars, Length),
  (  Length > 0
  -> message:gradient_print_chars(Chars, 0, Length)
  ;  true
  ).


%! message:gradient_print_chars(+Chars, +Index, +Length) is det.
%
% Recursively prints each character with its interpolated gradient color.

message:gradient_print_chars([], _, _).
message:gradient_print_chars([Char|Chars], Index, Length) :-
  message:gradient_interpolate_color(Index, Length, R, G, B),
  message:gradient_rgb_to_8bit(R, G, B, ColorCode),
  ansi_format([fg8(ColorCode)], '~s', [Char]),
  NextIndex is Index + 1,
  message:gradient_print_chars(Chars, NextIndex, Length).


%! message:gradient_interpolate_color(+Index, +Length, -R, -G, -B) is det.
%
% Linearly interpolates between gradient_start_color and gradient_end_color
% based on the character position Index within a string of Length characters.

message:gradient_interpolate_color(Index, Length, R, G, B) :-
    message:gradient_start_color(R1, G1, B1),
    message:gradient_end_color(R2, G2, B2),
    Ratio is Index / max(1, Length - 1),
    R is round(R1 + (R2 - R1) * Ratio),
    G is round(G1 + (G2 - G1) * Ratio),
    B is round(B1 + (B2 - B1) * Ratio).


%! message:gradient_rgb_to_8bit(+R, +G, +B, -Code) is det.
%
% Converts 0-255 RGB values to the nearest 8-bit (256-color) ANSI code
% within the 6x6x6 color cube (codes 16-231).

message:gradient_rgb_to_8bit(R, G, B, Code) :-
  R_scaled is round(R / 255 * 5),
  G_scaled is round(G / 255 * 5),
  B_scaled is round(B / 255 * 5),
  Code is 16 + (36 * R_scaled) + (6 * G_scaled) + B_scaled.


%! message:logo(+List) is det.
%
% Prints the portage-ng logo by concatenating List into a string and
% rendering it with a gradient.

message:logo(List) :-
  atomic_list_concat(List,String),
  message:print_gradient(String),nl.

%! message:logo(+List, +Mode) is det.
%
% Prints the portage-ng logo with the current Mode label appended
% as a dark-gray bubble.

message:logo(List,Mode) :-
  atomic_list_concat(List,String),
  message:print_gradient(String),
  message:print(' '),
  message:bubble(darkgray,Mode),nl.


% -----------------------------------------------------------------------------
%  Runtime: Lines and columns
% -----------------------------------------------------------------------------

%! message:eend(+Msg) is det.
%
% Prints Msg right-aligned near the end of the terminal line (column W-2).

eend(Msg) :-
  config:printing_tty_size(_,W),
  Col is W - 2,
  format('~t~a~*|', [Msg, Col]).

%! message:hl(+Title) is det.
%
% Prints a horizontal rule line with an embedded Title, padded with dashes
% to the full terminal width.

hl(Title) :-
  config:printing_tty_size(_,W),
  atom_chars('-', [C]),
  atomic_list_concat(['--- ',Title,' ~`', C, 't~*|\n'], Fmt),
  write('\r'),
  format(Fmt, [W]).

%! message:hl is det.
%
% Prints a full-width horizontal rule line of dashes.

hl :-
  config:printing_tty_size(_,W),
  atom_chars('-', [C]),
  atomic_list_concat(['~`', C, 't~*|\n'], Fmt),
  write('\r'),
  format(Fmt, [W]).


% -----------------------------------------------------------------------------
%  Runtime: Headers
% -----------------------------------------------------------------------------

%! message:enable_debug is det.
%
% Enables debug mode by setting the SWI-Prolog `debug` flag to true.

message:enable_debug :-
    set_prolog_flag(debug, true).

%! message:disable_debug is det.
%
% Disables debug mode by setting the SWI-Prolog `debug` flag to false.

message:disable_debug :-
    set_prolog_flag(debug, false).

%! message:is_debug_enabled is semidet.
%
% Succeeds if debug mode is currently enabled.

message:is_debug_enabled :-
    current_prolog_flag(debug, true).

%! message:topheader(+Message) is det.
%
% Prints a top-level section header in cyan bold (### prefix).
% Message can be an atom, string, or list of atoms.

topheader(Message) :-
  color(cyan),
  style(bold),
  msg_atom(Message, Atom),
  format('### ~s', [Atom]),
  color(normal),
  nl, nl.

%! message:header(+Message) is det.
%
% Prints a section header in light-orange bold (>>> prefix).
% Message can be an atom, string, or list of atoms.

header(Message) :-
  color(lightorange),
  style(bold),
  msg_atom(Message, Atom),
  format('>>> ~s', [Atom]),
  color(normal),
  nl.

%! message:header(+Header, +Items) is det.
%
% Prints a multi-line header: the first item on the same line as Header,
% subsequent items indented below.

header(Header, [First | Rest]) :-
  color(lightorange),
  color(bold),
  format('>>> ~w: ~w', [Header, First]),
  nl,
  forall(member(Item, Rest),
         ( msg_atom(Item,String), format('               ~w~n', [String]) )),
  color(normal),
  nl.


% -----------------------------------------------------------------------------
%  Header helpers
% -----------------------------------------------------------------------------

%! message:msg_atom(+Term, -Atom) is det.
%
% Converts an arbitrary term to an atom suitable for formatted output.
% Handles lists (concatenated), atoms, unbound variables, and compound
% terms (via write_term).

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
  with_output_to(string(Atom),write_term(Compound, [quoted(false)])).


% -----------------------------------------------------------------------------
%  Convertor: Byte
% -----------------------------------------------------------------------------

%! message:convert_bytes(+Bytes, -String) is det.
%
% Converts a byte count to a human-readable string with the appropriate
% unit (Kb, Mb, or Gb) and two decimal places.

convert_bytes(Bytes, String) :-
  (   Bytes >= 1 << 30
  ->  Unit = 'Gb', Value is Bytes / (1 << 30)
  ;   Bytes >= 1 << 20
  ->  Unit = 'Mb', Value is Bytes / (1 << 20)
  ;   Unit = 'Kb',  Value is Bytes / (1 << 10)
  ),
  format(string(String), '~2f ~w', [Value, Unit]).

%! message:print_bytes(+BytesOrLive) is det.
%
% Prints a tab-aligned byte size. The atom `live` prints "live" instead
% of a numeric value.

print_bytes(live) :-
  format('live   \t', []).

print_bytes(Bytes) :-
    convert_bytes(Bytes, Atom),
    format('~w  \t', [Atom]).


% -----------------------------------------------------------------------------
%  Convertor: Date/time
% -----------------------------------------------------------------------------

%! message:datetime(-Datetime) is det.
%
% Unifies Datetime with the current local date/time formatted as
% e.g. "Sat 21 Feb 2026 14:30:00".

datetime(Datetime) :-
  get_time(Stamp),
  stamp_date_time(Stamp, DT, 'local'),
  format_time(atom(Datetime), '%a %d %b %Y %T', DT).


% -----------------------------------------------------------------------------
%  Misc helpers
% -----------------------------------------------------------------------------

%! message:clear is det.
%
% Clears the terminal screen.

clear :- cl.

%! message:wrap(+Goal) is det.
%
% Executes Goal while printing a green "--- Executing <Goal>" banner
% before and a newline after. Useful for visually demarcating steps.

wrap(Goal) :-
  color(green),
  format('--- Executing ',[]),
  color(normal),
  write(Goal),
  nl,
  call(Goal),
  nl.