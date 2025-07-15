/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2025, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> ORACLE
The oracle is a caching mechanism for proofs and plans.
Allows to cache complex proofs and plans when debugging printer or builder.
*/

:- module(oracle, [with_q/1]).

:- dynamic(q:knows/1).


% -----------------------------------------------------------------------------
%  ORACLE declarations
% -----------------------------------------------------------------------------

with_q(Predicate) :-
  Predicate.

%with_q(Predicate) :-
%  q:knows(Predicate);
%  Predicate,
%  assertz(q:knows(Predicate)),!.

vanish_q :-
  retractall(q:knows(_)),!.
