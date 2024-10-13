/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2024, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> SCRIPTS
This file declares a predicate to execute a script inside the scripts directory
*/

:- module(script,[]).

% *******************
% SCRIPT declarations
% *******************


%! script:exec(+Name,+Args,+Env,-Out)
%
% Call script with arguments, Env can be used to set environment variables using
% [environment([key=value|...])]. Stream is a stream to which stdout is piped.
%
% Caller needs to close stream, to avoid getting leaking open_files

script:exec(S,Args,Env,Stream) :-
  !,
  atomic_list_concat(['Source/Scripts/',S],Script),
    process_create(portage(Script),Args,[stdout(pipe(Stream)),stderr(null)|Env]),
    !.


%! script:exec(+Name,+Args,+Env)
%
% Same as previous, but outputs to stdout and stderr

script:exec(S,Args,Env) :-
  !,
  atomic_list_concat(['Source/Scripts/',S],Script),
    process_create(portage(Script),Args,[stdout(std),stderr(std)|Env]),
    !.

%! script:exec(+Name,+Args)
%
% Same as previous, simple version

script:exec(S,Args) :-
  script:exec(S,Args,[]).
