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


%! script:exec(+Name,+Args)
%
% Call script with arguments


%script:exec(S,[]) :-
%  !,
%  atomic_list_concat(['Source/Scripts/',S],Script),
%  shell(Script),!.

script:exec(S,Args,Env) :-
  !,
  atomic_list_concat(['Source/Scripts/',S],Script),
    process_create(portage(Script),Args,[stdout(pipe(Out)),stderr(pipe(Out))|Env]),
    copy_stream_data(Out, current_output),
    !.

script:exec(S,Args) :-
  script:exec(S,Args,[]).


%script:exec(S,Args) :-
%  is_list(Args),
%  atomic_list_concat(['Source/Scripts/',S],Script),
%  atomic_list_concat(Args,'\' \'',QuotedArgs),
%  atomic_list_concat([Script,' \'',QuotedArgs,'\''],'',Cmd),
	%  shell(Cmd),!.
