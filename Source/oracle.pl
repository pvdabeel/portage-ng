/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2025, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> ORACLE
The oracle is essentially a mechanism to store answers to complex questions.
*/

:- module(oracle, [with_q/1]).

% *******************
% ORACLE declarations
% *******************

with_q(Predicate) :-
  q:knows(Predicate);
  Predicate,
  assert(q:knows(Predicate)),!.

vanish_q :-
  retractall(q:knows(_)),!.
