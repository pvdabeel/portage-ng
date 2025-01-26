/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2024, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> ORACLE
The oracle is essentially a mechanism to store answers to complex questions.
Proof caching mechanism.
*/

:- module(oracle, []).

% *******************
% ORACLE declarations
% *******************

:- class.

% public interface

:- dpublic('oracle'/0).
:- dpublic('~oracle'/0).

:- dpublic('tell'/2).
:- dpublic('question'/2).
:- dpublic('forget'/1).

% private interface

:- dprivate('knows'/2).


%! Constructor
%
% Public predicate

'oracle' ::-
  true.


%! Destructor
%
% Public predicate

'~oracle' ::-
  true.


%! oracle:tell(+Answer,+Question)
%
% Public predicate
%
% Tell the oracle Answer is the answer to a Question

tell(Answer,Question) ::-
  <=knows(Question,Answer).


%! oracle:question(+Question,+Answer)
%
% Public predicate
%
% Ask the oracle a question and get the Answer

question(Question,Answer) ::-
  ::knows(Question,Answer).


%! oracle:forget(+Question)
%
% Public predicate
%
% Forget all answers to a given Question

forget(Question) ::-
  <-count(Question,_).


%! oracle:knows(+Question,-Answer)
%
% Private predicate
%
% The Questions to which the oracle knows the Answer

knows(_Question,_Answer) ::-
  true.
