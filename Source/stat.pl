/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2021, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> STAT
This class is used for measuring progress and statistics
*/

:- module(stat, []).

% *****************
% STAT declarations
% *****************

:- class.

% public interface

:- dpublic('stat'/0).
:- dpublic('~stat'/0).

:- dpublic('init'/2).
:- dpublic('increase'/0).

:- dpublic('percentage'/1).
:- dpublic('runningtime'/2).

% private interface

:- dprivate('count'/1).
:- dprivate('total'/1).
:- dprivate('timestamp'/1).


%! Constructor
%
% Public predicate

'stat' ::-
  true.


%! Destructor
%
% Public predicate

'~stat' ::-
  true.


%! stat:init(+Count,+Total)
%
% Public predicate
%
% Sets the count and total to a given number

init(Count,Total) ::-
  get_time(T),
  <=count(Count),
  <=total(Total),
  <=timestamp(T).


%! stat:increase
%
% Public predicate
%
% Increases the count

increase ::-
  ::count(CurrentCount),
  NewCount is CurrentCount + 1,
  <=count(NewCount).

%! stat:percentage(-Percentage)
%
% Public predicate
%
% Retrieves the Percentage as count / total

percentage(Percentage) ::-
  ::count(Count),
  ::total(Total),
  P is Count/Total * 100,
  format(atom(Percentage),'~t~2f~w~7|',[P,'%']).

%! stat:runningtime(-Min,-Sec)
%
% Public predicate
%
% Retrieves the runningtime

runningtime(Min,Sec) ::-
  ::timestamp(T1),
  get_time(T2),
  Seconds is integer(T2-T1),
  Sec is Seconds mod 60,
  Min is Seconds div 60.

%! stat:total
%
% Private predicate
%
% The total

total(Total) ::-
  number(Total).


%! stat:count
%
% Private predicate
%
% The count

count(Count) ::-
  number(Count).


%!counter:timestamp
%
% Private predicate
%
% The timestamp

timestamp(Timestamp) ::-
  number(Timestamp).
