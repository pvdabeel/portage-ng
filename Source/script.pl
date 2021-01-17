/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2021, Pieter Van den Abeele

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


script:exec(S,[]) :-
  !,
  atomic_list_concat(['Source/Scripts/',S],Script),
  shell(Script),!.

script:exec(S,Args) :-
  is_list(Args),
  atomic_list_concat(['Source/Scripts/',S],Script),
  atomic_list_concat(Args,'\' \'',QuotedArgs),
  atomic_list_concat([Script,' \'',QuotedArgs,'\''],'',Cmd),
  shell(Cmd),!.
