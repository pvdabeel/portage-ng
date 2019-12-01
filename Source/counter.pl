/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2019, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> COUNTER
This class is used for outputting parallel process progress
*/

:- module(counter, []).

% *******************
% EBUILD declarations
% *******************

:- class.

% public interface

:- dpublic('counter'/0).
:- dpublic('~counter'/0).

:- dpublic('init'/2).
:- dpublic('increase'/0).

:- dpublic('percentage'/1).

% private interface

:- dprivate('count'/1).
:- dprivate('total'/1).


%! Constructor
%
% Public predicate

'counter' ::-
  true.


%! Destructor
%
% Public predicate

'~knowledgebase' ::-
  true.


%! counter:init(+Count,+Total)
%
% Public predicate
%
% Sets the count and total to a given number

init(Count,Total) ::-
  <=count(Count),
  <=total(Total).


%! counter:increase
%
% Public predicate
%
% Increases the count

increase ::-
  ::count(CurrentCount),
  NewCount is CurrentCount + 1,
  <=count(NewCount).

%! counter:percentage(-Percentage)
%
% Public predicate
%
% Retrieves the Percentage as count / total

percentage(Percentage) ::-
  ::count(Count),
  ::total(Total),
  P is Count/Total * 100,
  format(atom(Percentage),'~t~2f~w~7|',[P,'%']).


%!counter:total
%
% Private predicate
%
% The total

total(Total) ::-
  number(Total).


%!counter:count
%
% Private predicate
%
% The count

count(Count) ::-
  number(Count).
