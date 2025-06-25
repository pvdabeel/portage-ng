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

% ********************
% MESSAGE declarations
% ********************

% ---------------------
% Colour & style tables
% ---------------------

color_code(red,          "31").
color_code(green,        "32").
color_code(orange,       "33").
color_code(blue,         "34").
color_code(magenta,      "35").
color_code(cyan,         "36").
color_code(lightgray,    "37").
color_code(darkgray,     "90").
color_code(lightred,     "91").
color_code(lightgreen,   "92").
color_code(lightorange,  "93").
color_code(lightblue,    "94").
color_code(lightmagenta, "95").
color_code(lightcyan,    "96").
color_code(normal,       "00").

style_code(normal,       "00").
style_code(bold,         "01").
style_code(dim,          "02").
style_code(italic,       "03").
style_code(underline,    "04").
style_code(blink,        "05").

color(Name) :-
  color_code(Name, Code),
  format('\e[~sm', [Code]).

style(Name) :-
  style_code(Name, Code),
  format('\e[~sm', [Code]).


% --------------
% Cursor helpers
% --------------

el :- write('\e[K').
hc :- write('\e[?25l').
sc :- write('\e[?25h').
bl :- write('\e[1G').
cl :- write('\e[2J\e[H').


% -------------
% Title helpers
% -------------

title(Parts) :-
  msg_atom(Parts, Atom),
  format('\e]0;~s\a', [Atom]).

title_reset :-
  catch(config:name(Name), _, fail),
  !,
  title([Name]).

title_reset.


% ----------------
% Printing helpers
% ----------------

print(Item) :-
  msg_atom(Item, Atom),
  write(Atom).

column(N, Msg) :-
  format('~*| ~w', [N, Msg]).

eend(Msg) :-
  tty_size(_,W),
  Col is W - 2,
  msg_atom(Msg, Atom),
  format('~t~a~*|', [Atom, Col]).



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


% ---------------
% Convertor: Byte
% ---------------

convert_bytes(Bytes, Atom) :-
  (   Bytes >= 1 << 30
  ->  Unit = 'Gb', Value is Bytes / (1 << 30)
  ;   Bytes >= 1 << 20
  ->  Unit = 'Mb', Value is Bytes / (1 << 20)
  ;   Unit = 'Kb',  Value is Bytes / (1 << 10)
  ),
  format(atom(Atom), '~2f ~w', [Value, Unit]).

print_bytes(live) :-
  format('live\t', []).

print_bytes(Bytes) :-
  convert_bytes(Bytes, Atom),
  format('~w\t', [Atom]).


% --------------------
% Convertor: Date/time
% --------------------

datetime(Datetime) :-
  get_time(Stamp),
  stamp_date_time(Stamp, DT, 'local'),
  format_time(atom(Datetime), '%a %d %b %Y %T', DT).


% -----------------
% Messaging backend
% -----------------

:- meta_predicate
        msg(+,+),
        msg_scroll(+,+).

msg(Level, Text) :-
  level_attrs(Level, Attrs, Prefix),
  msg_atom(Text, Atom),
  ansi_format(Attrs, '~s~s', [Prefix, Atom]),
  nl,
  ( Level == failure -> fail ; true ).

msg_scroll(Level, Text) :-
  level_attrs(Level, Attrs, Prefix),
  msg_atom(Text, Atom),
  ansi_format(Attrs, '~s~s', [Prefix, Atom]),
  el,
  bl,
  flush_output,
  ( Level == failure -> fail ; true ).


level_attrs(success, [bold, fg(green)],     '[SUCCESS] ').
level_attrs(warning, [bold, fg(yellow)],    '[WARNING] ').
level_attrs(failure, [bold, fg(red)],       '[FAILURE] ').
level_attrs(inform,  [],                    '% ').
level_attrs(notice,  [faint, fg(white)],    '% ').
level_attrs(debug,   [fg(magenta)],         '[DEBUG] ').
level_attrs(log,     [faint, fg(white)],    '% ').

failure(T)        :- msg(failure, T).
warning(T)        :- msg(warning, T).
success(T)        :- msg(success, T).
inform(T)         :- msg(inform,  T).
notice(T)         :- msg(notice,  T).
debug(T)          :- msg(debug,   T).
log(T)            :- ( config:verbose(true) -> msg(log,T) ; true ).

scroll_failure(T) :- msg_scroll(failure, T).
scroll_warning(T) :- msg_scroll(warning, T).
scroll_success(T) :- msg_scroll(success, T).
scroll_inform(T)  :- msg_scroll(inform,  T).
scroll_notice(T)  :- msg_scroll(notice,  T).
scroll_debug(T)   :- msg_scroll(debug,   T).
scroll(T)         :- msg_scroll(inform,  T).


% --------------
% Header helpers
% --------------

%! msg_atom(+Any, -Atom) is det.
%  Convert any printable term to a flat atom.
msg_atom(List, Atom) :-
  is_list(List),
  !,
  maplist(msg_atom, List, Atoms),
  atomic_list_concat(Atoms, Atom).

msg_atom(Atomic, Atomic) :-
  atomic(Atomic),
  !.

msg_atom(Var, Atom) :-
  var(Var),
  !,
  term_to_atom(Var, Atom).

msg_atom(Compound, Atom) :-
  term_to_atom(Compound, Atom).


topheader(Message) :-
  msg_atom(Message, Atom),
  ansi_format([bold, fg(cyan)], '### ~s', [Atom]),
  nl, nl.

header(Message) :-
  msg_atom(Message, Atom),
  ansi_format([bold, fg(yellow)], '>>> ~s', [Atom]),
  nl.

header(Header, [First | Rest]) :-
  ansi_format([bold, fg(yellow)], '>>> ~w: ~w', [Header, First]),
  nl,
  forall(member(Item, Rest),
         ( %msg_atom(Item, ItemAtom),
           ansi_format([bold, fg(yellow)], '               ~s~n', [Item]) )),
  nl.


% ------------
% Misc helpers
% ------------

clear :- cl.

clean :- el.

prefix(_) :- write('>>> ').

:- meta_predicate wrap(0).
wrap(Goal) :-
  color(green),
  write('--- Executing '),
  color(normal),
  write(Goal),
  nl,
  call(Goal),
  nl.
