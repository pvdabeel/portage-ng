/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2025, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> MESSAGE
This file contains the predicates used for pretty printing messages.
*/

:- module(message, []).

% ********************
% MESSAGE declarations
% ********************


%! message:title(+Message)
%
% Sets the terminal title.

message:title(MessageList) :-
  system:write('\033]0;'),
  atomic_list_concat(MessageList,Message),
  system:write(Message),
  system:write('\a'),!.

message:title_reset :-
  config:name(Name),
  message:title([Name]),!.


%! message:color(+Color)
%
% Sets the message color. Uses ANSI escape codes.

message:color(red) :-
  system:write('\033[31m').

message:color(green) :-
  system:write('\033[32m').

message:color(orange) :-
  system:write('\033[33m').

message:color(blue) :-
  system:write('\033[34m').

message:color(magenta) :-
  system:write('\033[35m').

message:color(cyan) :-
  system:write('\033[36m').


message:color(lightgray) :-
  system:write('\033[37m').

message:color(darkgray) :-
  system:write('\033[90m').

message:color(lightred) :-
  system:write('\033[91m').

message:color(lightgreen) :-
  system:write('\033[92m').

message:color(lightorange) :-
  system:write('\033[93m').

message:color(lightblue) :-
  system:write('\033[94m').

message:color(lightmagenta) :-
  system:write('\033[95m').

message:color(lightcyan) :-
  system:write('\033[96m').

message:color(normal) :-
  system:write('\033[00m').


%! message:el
%
% Clears all characters from the cursor position to the end of line

message:el :-
  system:write('\033[K').


%! message:hc
%
% Hides cursor

message:hc :-
  system:write('\033[?25l').


%! message:sc
%
% Show cursor

message:sc :-
  system:write('\033[?25h').


%! message:style(+Style)
%
% Sets the message style. Uses ANSI escape codes.

message:style(bold) :-
  system:write('\033[01m').

message:style(blink) :-
  system:write('\033[05m').

message:style(underline) :-
  system:write('\033[04m').

message:style(italic) :-
  system:write('\033[03m').

message:style(dim) :-
  system:write('\033[02m').

message:style(normal) :-
  system:write('\033[00m').



%! message:eend(+Message)
%
% Append at the end of the line

message:eend(Message) :-
  tty_size(_,Y),
  NewY is Y - 2,
  format('~t~a~*|',[Message,NewY]),!.


%! message:column(+Number,+Message)
%
% Writes a message in a given colum

message:column(Number,Message) :-
  format('~*| ~w',[Number,Message]),!.


%! message:hl(C)
%
% Writes a horizontal line with a given char

message:hl(C) :-
  tty_size(_,Y),
  forall(between(1,Y,_),write(C)).

%! message:hl
%
% Write a horizontal line

message:hl :-
  message:hl('-').


%! message:print(+Message)
%
% Write a list or simple message

message:print(Message) :-
  is_list(Message),!,
  forall(lists:member(M,Message),
    system:write(M)).

message:print(Message) :-
  system:write(Message).


%! message:print(+Message,-Len)
%
% Write a list message and return its length

message:print(Message,Len) :-
  message:print(Message),
  atomic_list_concat(Message,Concat),
  system:write_length(Concat,Len,[]).


%! message:failure(+Message)
%
% Informs the user about a failure and fails.

message:failure(Message) :-
  %message:prefix(failure),
  message:color(red),
  message:style(bold),
  system:write('[FAILURE] '),
  message:style(normal),
  message:color(normal),
  message:print(Message),
  nl,
  fail.


%! message:warning(+Message)
%
% Informs the user about a warning and continues.

message:warning(Message) :-
  %message:prefix(warning),
  message:color(orange),
  message:style(bold),
  system:write('[WARNING] '),
  message:color(normal),
  message:print(Message),
  nl.


%! message:success(+Message)
%
% Informs the user about something that went OK and continues.

message:success(Message) :-
  %message:prefix(good),
  message:color(green),
  message:style(bold),
  system:write('[SUCCESS] '),
  message:color(normal),
  message:print(Message),
  nl.


%! message:inform(+Message)
%
% Informs the user about something
% Message is a list.

message:inform(Message) :-
  system:write('% '),
  message:print(Message),
  nl.


%! message:notice(+Message)
%
% Informs the user about something
% Message is a list.

message:notice(Message) :-
  message:style(italic),
  message:color(darkgray),
  system:write('% '),
  message:print(Message),
  message:color(normal),
  message:style(normal),
  nl.


%! message:scroll(+Message)
%
% Informs the user about something - scroll style
% Message is a list.

message:scroll(Message) :-
  system:write('% '),
  message:print(Message,Len),
  message:el,
  flush_output,
  Prefixed_Len is Len + 2,% + 3,
  tty:tty_action(back(Prefixed_Len)).


%! message:scroll(+Message)
%
% Informs the user about a success - scroll style
% Message is a list.

message:scroll_success(Message) :-
  %system:write('% '),
  message:color(green),
  message:style(bold),
  message:print(['[SUCCESS] '],LenA),
  message:color(normal),
  message:print(Message,LenB),
  message:el,
  flush_output,
  Prefixed_Len is LenA + LenB,
  tty:tty_action(back(Prefixed_Len)).

message:scroll_failure(Message) :-
  %system:write('% '),
  message:color(red),
  message:style(bold),
  message:print(['[FAILURE] '],LenA),
  message:color(normal),
  message:print(Message,LenB),
  message:el,
  flush_output,
  Prefixed_Len is LenA + LenB,
  tty:tty_action(back(Prefixed_Len)).

message:scroll_warning(Message) :-
  %system:write('% '),
  message:color(orange),
  message:style(bold),
  message:print(['[WARNING] '],LenA),
  message:color(normal),
  message:print(Message,LenB),
  message:el,
  flush_output,
  Prefixed_Len is LenA + LenB,
  tty:tty_action(back(Prefixed_Len)).

message:scroll_inform(Message) :-
  system:write('% '),
  message:print(Message,Len),
  message:el,
  flush_output,
  Prefixed_Len is Len + 2,
  tty:tty_action(back(Prefixed_Len)).

message:scroll_notice(Message) :-
  message:style(italic),
  message:color(darkgray),
  system:write('% '),
  message:print(Message,Len),
  message:color(normal),
  message:style(normal),
  message:el,
  flush_output,
  Prefixed_Len is Len + 2,
  tty:tty_action(back(Prefixed_Len)).


%! message:clean
%
% Cleans the current line without moving the cursor

message:clean :-
  message:el.
  %Len is 3,
  %tty:tty_action(back(Len)).


%! message:topheader(+Message)
%
% Informs the user about something - header style
% Message is a list.

message:topheader(Message) :-
  message:color(cyan),
  message:style(bold),
  system:write('### '),
  forall(lists:member(M,Message),
    system:write(M)),
  message:color(normal),
  message:style(normal),
  nl,nl.


%! message:header(+Message)
%
% Informs the user about something - header style
% Message is a list.

message:header(Message) :-
  message:color(orange),
  message:style(bold),
  system:write('>>> '),
  forall(lists:member(M,Message),
    system:write(M)),
  message:color(normal),
  message:style(normal),
  nl.

message:header(Header,[E|R]) :-
  message:color(orange),
  message:style(bold),
  system:write('>>> '),
  system:write(Header),
  system:write(': '),
  system:write(E),nl,
  forall(member(M,R),
   (message:write('               '),
    message:write(M),
    nl)),
  message:color(normal),
  message:style(normal),
  nl.




%! message:convert_bytes(+Bytes,-Output,-Unit)
%
% Converts a number of bytes into a gigabyte, megabyte or kilobyte

message:convert_bytes(Bytes,Output) :-
  Bytes >= 1024 * 1024 * 1024,!,
  Gigabytes is Bytes / 1024 / 1024 / 1024,
  format(atom(Output),'~2f Gb~10|',[Gigabytes]).


message:convert_bytes(Bytes,Output) :-
  Bytes < 1024 * 1024 * 1024,
  Bytes >= 1024 * 1024, !,
  Megabytes is Bytes / 1024 / 1024,
  format(atom(Output),'~2f Mb~10|',[Megabytes]).

message:convert_bytes(Bytes,Output) :-
  Bytes < 1024 * 1024, !,
  Kilobytes is Bytes / 1024,
  format(atom(Output),'~2f Kb~10|',[Kilobytes]).


%! message:format_bytes(+Bytes)
%
% Formats a given number of bytes

message:print_bytes('live') :-
  !,
  format('~tlive      ~10|',[]).

message:print_bytes(Bytes) :-
  message:convert_bytes(Bytes,Output),
  format('~t~w~10|',[Output]).


%! message:prefix(+Message)
%
% Message prefix

message:prefix(_Message) :-
  system:write('>>> ').


%! message:wrap(+Rule)
%
% Informs and executes

message:wrap(Rule) :-
  message:color(green),
  system:write('--- Executing '),
  message:color(normal),
  system:write(Rule),nl,
  Rule,
  nl.
