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

message:bubble/2 is the exception: it dispatches at runtime so cap
style can follow TERM (Powerline glyphs vs foreground-only <...> on
TERM=linux).

Debug messaging (debug_msg/1..3, debug_write/1, debug_writeln/1) is
conditionally compiled via the SWI-Prolog `-Ddebug` flag: when debug
is disabled, calls expand to `true` (no overhead).
*/

:- module(message, [clear/0]).

% =============================================================================
%  MESSAGE declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Line-position preserving ANSI emit
% -----------------------------------------------------------------------------
%
% Older SWI-Prolog builds count ANSI escapes as output columns, so escape
% writes must save/restore line_position or column stops (~t / ~|) drift.
% swipl-devel 3575a02c makes the stream layer ignore escapes and drops
% library(ansi_term)'s private keep_line_pos/2. Version numbers cannot tell
% the two apart (both report 10.1.12), so detect the behaviour at load time:
% wrap_ansi/2 embeds the save/restore wrapper only on old builds; on modern
% builds goal expansion inlines the bare emit goal.

%! message:ansi_escapes_affect_line_pos is semidet.
%
% Succeeds when writing an ANSI escape advances the stream column.

message:ansi_escapes_affect_line_pos :-
  with_output_to(string(_),
      ( format('\e[0m', []),
        line_position(current_output, N),
        N > 0 )).


:- if(message:ansi_escapes_affect_line_pos).

:- meta_predicate message:keep_line_pos(+, 0).

%! message:keep_line_pos(+Stream, :Goal) is det.
%
% Run Goal without changing Stream's line_position (reimplements the
% helper dropped from library(ansi_term)).

message:keep_line_pos(S, G) :-
  stream_property(S, position(Pos)),
  !,
  setup_call_cleanup(
      stream_position_data(line_position, Pos, LPos),
      G,
      set_stream(S, line_position(LPos))).
message:keep_line_pos(_, G) :-
  call(G).


%! message:wrap_ansi(+Goal, -Wrapped) is det.
%
% Embed Goal (a term, not meta-called) in a keep_line_pos/2 wrapper.

message:wrap_ansi(G, message:keep_line_pos(current_output, G)).

:- else.

%! message:wrap_ansi(+Goal, -Wrapped) is det.
%
% Identity: this stream layer ignores ANSI escapes for column tracking.

message:wrap_ansi(G, G).

:- endif.


%! message:emit_ansi(+Code) is det.
%
% Write an ANSI escape Code chosen at runtime (bubble renderer).

message:emit_ansi(Code) :-
  message:wrap_ansi(format(Code, []), Goal),
  call(Goal).


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
message:style(_).
message:bell.
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
%  Goal expansion: Color, background color and style
% -----------------------------------------------------------------------------
%
% One escape table drives the color/1, bgcolor/1 and style/1 expansions and
% the runtime bubble renderer below. A single rule expands any stub found in
% the table, guarded by the runtime colour switch.

%! message:ansi_code(?Stub, ?Code) is nondet.
%
% ANSI escape Code emitted for a color/1, bgcolor/1 or style/1 stub.

message:ansi_code(color(red),            "\e[31m").
message:ansi_code(color(green),          "\e[32m").
message:ansi_code(color(orange),         "\e[33m").
message:ansi_code(color(blue),           "\e[34m").
message:ansi_code(color(magenta),        "\e[35m").
message:ansi_code(color(cyan),           "\e[36m").
message:ansi_code(color(lightgray),      "\e[37m").
message:ansi_code(color(darkgray),       "\e[90m").
message:ansi_code(color(lightred),       "\e[91m").
message:ansi_code(color(lightgreen),     "\e[92m").
message:ansi_code(color(yellow),         "\e[93m").
message:ansi_code(color(lightorange),    "\e[93m").
message:ansi_code(color(lightblue),      "\e[94m").
message:ansi_code(color(lightmagenta),   "\e[95m").
message:ansi_code(color(lightcyan),      "\e[96m").
message:ansi_code(color(normal),         "\e[00m").
message:ansi_code(bgcolor(red),          "\e[41m").
message:ansi_code(bgcolor(green),        "\e[42m").
message:ansi_code(bgcolor(orange),       "\e[43m").
message:ansi_code(bgcolor(blue),         "\e[44m").
message:ansi_code(bgcolor(magenta),      "\e[45m").
message:ansi_code(bgcolor(cyan),         "\e[46m").
message:ansi_code(bgcolor(lightgray),    "\e[47m").
message:ansi_code(bgcolor(darkgray),     "\e[100m").
message:ansi_code(bgcolor(lightred),     "\e[101m").
message:ansi_code(bgcolor(lightgreen),   "\e[102m").
message:ansi_code(bgcolor(yellow),       "\e[103m").
message:ansi_code(bgcolor(lightorange),  "\e[103m").
message:ansi_code(bgcolor(lightblue),    "\e[104m").
message:ansi_code(bgcolor(lightmagenta), "\e[105m").
message:ansi_code(bgcolor(lightcyan),    "\e[106m").
message:ansi_code(bgcolor(normal),       "\e[00m").
message:ansi_code(style(normal),         "\e[00m").
message:ansi_code(style(bold),           "\e[01m").
message:ansi_code(style(dim),            "\e[02m").
message:ansi_code(style(italic),         "\e[03m").
message:ansi_code(style(underline),      "\e[04m").
message:ansi_code(style(blink),          "\e[05m").


user:goal_expansion(Goal, (config:color_output -> Emit ; true)) :-
  compound(Goal),
  arg(1, Goal, Arg),
  atom(Arg),
  message:ansi_code(Goal, Code),
  message:wrap_ansi(format(Code, []), Emit).


% -----------------------------------------------------------------------------
%  Goal expansion: Cursor
% -----------------------------------------------------------------------------

user:goal_expansion(bell,                  (format("\a",[]),flush_output)).
user:goal_expansion(el,                    (console:output_tty -> format("\e[K",[]) ; true)).
user:goal_expansion(hc,                    (console:output_tty -> Emit ; true)) :-
  message:wrap_ansi(format("\e[?25l",[]), Emit).
user:goal_expansion(sc,                    (console:output_tty -> Emit ; true)) :-
  message:wrap_ansi(format("\e[?25h",[]), Emit).
user:goal_expansion(bl,                    (console:output_tty -> format("\e[1G",[]) ; true)).
user:goal_expansion(cl,                    (console:output_tty -> format("\e[2J\e[H",[]) ; true)).
user:goal_expansion(clean,                 (console:output_tty -> format("\e[K",[]) ; true)).


% -----------------------------------------------------------------------------
%  Goal expansion: Label
% -----------------------------------------------------------------------------

user:goal_expansion(bubble(Color,Text),
                    message:bubble(Color, Text)) :- !.

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
%  Runtime: Bubbles
% -----------------------------------------------------------------------------
%
% bubble/2 is expanded at call sites to message:bubble/2 so the cap style
% can follow TERM at runtime (Powerline vs <...> on TERM=linux).

%! message:bubble(+Color, +Text) is det.
%
% Render a coloured label badge. Uses Powerline caps on UTF-8 terminals
% and <...> angle brackets on the Linux console (TERM=linux). Angle
% bubbles omit background colour; step labels render as <step N> in
% darkgray foreground (brackets included).

message:bubble(Color, Text) :-
  ( console:powerline_bubbles
  -> message:bubble_powerline(Color, Text)
  ;  message:bubble_angle(Color, Text)
  ).


message:bubble_powerline(Color, Text) :-
  ( config:color_output
  -> message:bubble_colored(Color, Text, '\uE0B6', '\uE0B4')
  ;  message:bubble_write(Text)
  ).


message:bubble_angle(Color, Text) :-
  ( config:color_output
  -> message:bubble_angle_fg(Color, Text, Fg),
     message:bubble_angle_colored(Fg, Text, Color)
  ;  message:bubble_plain_angle(Text)
  ).


message:bubble_angle_fg(_Color, Text, darkgray) :-
  message:bubble_is_step_label(Text),
  !.

message:bubble_angle_fg(Color, _Text, Color).


%! message:bubble_is_step_label(+Text) is semidet.
%
% True when Text is a plan step label ("step  N").

message:bubble_is_step_label(Text) :-
  atom(Text),
  sub_atom(Text, 0, 5, _, 'step ').


message:bubble_angle_colored(FgColor, Text, BubbleColor) :-
  message:bubble_emit_fg(FgColor),
  ( message:bubble_angle_bold(BubbleColor)
  -> message:bubble_emit_bold
  ;  true
  ),
  format('<'),
  message:bubble_write(Text),
  format('>'),
  ( message:bubble_angle_bold(BubbleColor)
  -> message:bubble_emit_bold_off
  ;  true
  ),
  message:bubble_emit_fg(normal).


message:bubble_angle_bold(green).


message:bubble_colored(Color, Text, Left, Right) :-
  message:bubble_emit_fg(Color),
  format('~w', [Left]),
  message:bubble_emit_fg(normal),
  message:bubble_emit_bg(Color),
  message:bubble_write(Text),
  message:bubble_emit_bg(normal),
  message:bubble_emit_fg(Color),
  format('~w', [Right]),
  message:bubble_emit_fg(normal).


message:bubble_plain_angle(Text) :-
  format('<'),
  message:bubble_write(Text),
  format('>').


message:bubble_write(Text) :-
  ( atom(Text)
  -> write(Text)
  ;  string(Text)
  -> write(Text)
  ;  format(Text)
  ).


message:bubble_emit_fg(Color) :-
  ( config:color_output,
    message:ansi_code(color(Color), Code)
  -> message:emit_ansi(Code)
  ;  true
  ).


message:bubble_emit_bg(Color) :-
  ( config:color_output,
    message:ansi_code(bgcolor(Color), Code)
  -> message:emit_ansi(Code)
  ;  true
  ).


message:bubble_emit_bold :-
  ( config:color_output
  -> message:emit_ansi("\e[01m")
  ;  true
  ).


message:bubble_emit_bold_off :-
  ( config:color_output
  -> message:emit_ansi("\e[22m")
  ;  true
  ).


% -----------------------------------------------------------------------------
%  Goal expansion: Core messaging
% -----------------------------------------------------------------------------

user:goal_expansion(msg(Scroll,Level,Msg),
  Expanded) :-
  ( ( is_list(Msg)
      -> Output = (atomic_list_concat(Msg,String),format('~a', [String]))
      ;  Output = (format(Msg,[])) ),
    ( Scroll == true
      -> Post = (( console:output_tty
                 -> message:el, message:bl, flush_output
                 ;  message:color(normal), nl ))
      ;  Post = (message:color(normal),nl) ),
    ( Level == failure
      -> Continue = fail
      ;  Continue = true ),
    Body = ( message:label(Level), Output, Post, Continue ),
    ( memberchk(Level, [failure, warning])
      -> Expanded = Body
      ;  Expanded = ( \+ preference:flag(quiet) -> Body ; Continue )
    ) ).

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
  message:wrap_ansi(format('\e]0;~s\a',[String]), Expanded).

user:goal_expansion(title(List),           Expanded) :-
  is_list(List),!,
  message:wrap_ansi(format('\e]0;~s\a',[String]), Emit),
  Expanded = (atomic_list_concat(List,String), Emit).

user:goal_expansion(title(String),         Expanded) :-
  message:wrap_ansi(format('\e]0;~s\a',[String]), Expanded).


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
  console:printing_tty_size(_,W),
  Col is W - 2,
  format('~t~a~*|', [Msg, Col]).

%! message:hl(+Title) is det.
%
% Prints a horizontal rule line with an embedded Title, padded with dashes
% to the full terminal width.

hl(Title) :-
  console:printing_tty_size(_,W),
  atom_chars('-', [C]),
  atomic_list_concat(['--- ',Title,' ~`', C, 't~*|\n'], Fmt),
  write('\r'),
  format(Fmt, [W]).

%! message:hl is det.
%
% Prints a full-width horizontal rule line of dashes.

hl :-
  console:printing_tty_size(_,W),
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
%  Spinners
% -----------------------------------------------------------------------------

%! message:spinner_frames(+Style, -Frames) is det.
%
% Returns the list of unicode frames for a given spinner style.
% Available styles: braille, block, quarter, line.

message:spinner_frames(braille,  ['\u2801','\u2802','\u2804','\u2840','\u2880','\u2820','\u2810','\u2808']).
message:spinner_frames(block,    ['\u2589','\u258A','\u258B','\u258C','\u258D','\u258E','\u258F','\u258E','\u258D','\u258C','\u258B','\u258A','\u2589']).
message:spinner_frames(quarter,  ['\u25F4','\u25F7','\u25F6','\u25F5']).
message:spinner_frames(line,     ['|','/','-','\\']).


%! message:spinner_frame(+Style, +Tick, -Frame) is det.
%
% Returns the frame for a given spinner style at a given tick count.
% Cycles through frames using modular arithmetic.

message:spinner_frame(Style, Tick, Frame) :-
  message:spinner_frames(Style, Frames),
  length(Frames, Len),
  Idx is Tick mod Len,
  nth0(Idx, Frames, Frame).


% -----------------------------------------------------------------------------
%  Right-edge indicators
% -----------------------------------------------------------------------------
%
% Status glyphs printed one column in from the right edge of the current
% line (plan printer: distfile present; build printer: phase outcome and
% in-progress spinner). All are no-ops when stdout is not a TTY.

%! message:at_right_edge(+Width, :Goal) is det.
%
% Clears the rest of the current line, moves the cursor so that Width
% columns of output end one column short of the right edge, and runs
% Goal there; does nothing without a TTY.

:- meta_predicate message:at_right_edge(+, 0).

message:at_right_edge(_Width, _Goal) :-
  \+ console:output_tty, !.
message:at_right_edge(Width, Goal) :-
  message:el,
  console:printing_tty_size(_, W),
  Col is W - Width,
  format("\e[~dG", [Col]),
  call(Goal).


%! message:right_edge_ok is det.
%
% Green checkmark at the right edge.

message:right_edge_ok :-
  message:at_right_edge(1,
    ( message:color(green),
      message:print('\u2713'),
      message:color(normal) )).


%! message:right_edge_fail is det.
%
% Red bold exclamation mark at the right edge.

message:right_edge_fail :-
  message:at_right_edge(1,
    ( message:color(red),
      message:style(bold),
      message:print('!'),
      message:style(normal),
      message:color(normal) )).


%! message:right_edge_spinner(+Tick) is det.
%
% Gray braille spinner frame for Tick at the right edge.

message:right_edge_spinner(Tick) :-
  message:spinner_frame(braille, Tick, Frame),
  message:at_right_edge(1,
    ( message:color(darkgray),
      message:print(Frame),
      message:color(normal) )).


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