/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> SCRIPTS
This file declares a predicate to execute a script inside the scripts directory
*/

:- module(script,[]).

% =============================================================================
%  SCRIPT declarations
% =============================================================================


%! script:exec(+Name,+Args,+Env,-Out)
%
% Call script with arguments, Env can be used to set environment variables using
% [environment([key=value|...])]. Stream is a stream to which stdout is piped.
%
% Caller needs to close stream, to avoid getting leaking open_files

script:exec(S,Args,Env,Stream) :-
  !,
  atomic_list_concat(['Source/Scripts/',S],Script),
  process_set_method(vfork),
  process_create(portage(Script),Args,[stdout(pipe(Stream)),stderr(null)|Env]),
  !.


%! script:exec_streaming(+Name,+Args,+Env)
%
% Call script with arguments, streaming stdout line-by-line to current_output
% with flush_output after each line. Properly waits for the child process and
% closes the pipe stream. Suitable for long-running operations where real-time
% output is desired (e.g. repository sync).

script:exec_streaming(S,Args,Env) :-
  !,
  atomic_list_concat(['Source/Scripts/',S],Script),
  process_set_method(vfork),
  process_create(portage(Script),Args,[stdout(pipe(Stream)),process(Pid)|Env]),
  set_stream(Stream,buffer(false)),
  call_cleanup(
    script:stream_prefix_chars(Stream,true),
    ( close(Stream), process_wait(Pid,_) )
  ),
  !.

script:stream_prefix_chars(Stream,BOL) :-
  get_char(Stream,Char),
  ( Char == end_of_file ->
    ( BOL == false -> nl, flush_output ; true )
  ; Char == '\n' ->
    nl, flush_output,
    script:stream_prefix_chars(Stream,true)
  ; Char == '\r' ->
    put_char('\r'), flush_output,
    script:stream_prefix_chars(Stream,true)
  ;
    ( BOL == true -> write('% ') ; true ),
    put_char(Char),
    script:stream_prefix_chars(Stream,false)
  ).


%! script:exec(+Name,+Args,+Env)
%
% Same as previous, but outputs to stdout and stderr

script:exec(S,Args,Env) :-
  !,
  atomic_list_concat(['Source/Scripts/',S],Script),
  process_set_method(vfork),
  process_create(portage(Script),Args,[stdout(std),stderr(std)|Env]),
  !.


%! script:exec(+Name,+Args)
%
% Same as previous, simple version

script:exec(S,Args) :-
  is_list(Args),!,
  script:exec(S,Args,[]).


%! script:exec(+Name,+Var)
%
% Same as previous, output to var

script:exec(S,Var) :-
  \+ is_list(Var),!,
  atomic_list_concat(['Source/Scripts/',S],Script),
  process_set_method(vfork),
  process_create(portage(Script),[],[stdout(pipe(Out)),stderr(std)]),
  read_string(Out,"\n","\r",_,Var),
  close(Out),
  !.
