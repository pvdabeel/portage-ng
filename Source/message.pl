% ********************
% MESSAGE declarations
% ********************

% This file contains the predicates used for pretty printing messages. Write and
% writeln cannot be used in this project except in this file.

% [ <warn>foo</warn> ]


% message:color(+Color)
%
% Sets the message color. Uses ANSI escape codes.

message:color(green) :-
  system:write('\033[01;32m').

message:color(red) :-
  system:write('\033[01;31m').

message:color(blue) :-
  system:write('\033[01;34m').

message:color(orange) :-
  system:write('\033[01;33m').

message:color(pink) :-
  system:write('').

message:color(normal) :-
  system:write('\033[00m').


message:eend :-
  tty_size(X,Y),
  NewY is Y - 10,
  tty_goto(NewY,X).


% message:failure(+Message)
%
% Informs the user about a failure and fails.

message:failure(Message) :-
  message:prefix(failure),
  message:color(red),
  system:write('[FAILURE] '),
  message:color(normal),
  system:writeln(Message),
  fail.


% message:warning(+Message)
%
% Informs the user about a warning and continues.

message:warning(Message) :-
  message:prefix(warning),
  message:color(orange),
  system:write('[WARNING] '),
  message:color(normal),
  system:writeln(Message).


% message:success(+Message)
%
% Informs the user about something that went OK and continues.

message:success(Message) :-
  message:prefix(good),
  message:color(green),
  system:write('[SUCCESS] '),
  message:color(normal),
  system:writeln(Message).


% message:inform(+Message)
%
% Informs the user about something
% Message is a list.

message:inform(Message) :-
  system:write('% '),
  forall(member(M,Message),
    system:write(M)),
  nl.


% message:scroll(+Message)
%
% Informs the user about something - scroll style
% Message is a list.

message:scroll(Message) :-
  system:write('% '),
  forall(member(M,Message),
    system:write(M)),
  tty:tty_action(back(100)),
  tty:tty_action(ce).



% message:header(+Message)
%
% Informs the user about something - header style
% Message is a list.

message:header(Message) :-
  system:write('%%% '),
  message:color(orange),
  forall(member(M,Message),
    system:write(M)),
  message:color(normal),
  nl.



% message:prefix(failure)
%
% Message prefix

message:prefix(_) :-
  system:write('>>> ').


% message:wrap(rule)
%
% Informs and executes

message:wrap(Rule) :-
  message:color(green),
  system:write('--- Executing '),
  message:color(normal),
  system:write(Rule),nl,
  Rule,
  nl.
