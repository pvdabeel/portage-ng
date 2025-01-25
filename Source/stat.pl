/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2024, Pieter Van den Abeele

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

:- dpublic('init'/3).
:- dpublic('increase'/1).
:- dpublic('decrease'/1).

:- dpublic('release'/1).

:- dpublic('percentage'/2).
:- dpublic('runningtime'/3).

:- dpublic('times'/2).

% private interface

:- dprivate('count'/2).
:- dprivate('total'/2).
:- dprivate('timestamp'/2).


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


%! stat:init(+Count,+Generator,-Id)
%
% Public predicate
%
% Sets the count and total to a given number

init(Count,Total,Id) ::-
  gensym(stat,Id),
  get_time(T),
  <=count(Id,Count),
  <=total(Id,Total),
  <=timestamp(Id,T).


%! stat:increase(+Id)
%
% Public predicate
%
% Increases the count

increase(Id) ::-
  ::count(Id,CurrentCount),
  NewCount is CurrentCount + 1,
  <=count(Id,NewCount).


%! stat:decrease(+Id)
%
% Public predicate
%
% Decreases the count

decrease(Id) ::-
  ::count(Id,CurrentCount),
  NewCount is CurrentCount - 1,
  <=count(Id,NewCount).


%! stat:release(+Id)
%
% Public predicate
%
% Releases all statistics related to a given Id

release(Id) ::-
  <-total(Id,_),
  <-count(Id,_),
  <-timestamp(Id,_).


%! stat:percentage(+Id,-Percentage)
%
% Public predicate
%
% Retrieves the Percentage as count / total

percentage(Id,Percentage) ::-
  ::count(Id,Count),
  ::total(Id,Total),
  P is Count/Total * 100,
  format(atom(Percentage),'~t~2f~w~7|',[P,'%']).


%! stat:runningtime(+Id,-Min,-Sec)
%
% Public predicate
%
% Retrieves the runningtime

runningtime(Id,Min,Sec) ::-
  ::timestamp(Id,T1),
  get_time(T2),
  Seconds is integer(T2-T1),
  Sec is Seconds mod 60,
  Min is Seconds div 60,!.


%! stat:times(+Generator,?Count)
%
% Public predicate
%
% Counts how many times Generator predicate is true

times(Generator,Count) ::-
  findall(1,Generator,List),
  length(List,Count).


%! stat:total
%
% Private predicate
%
% The total

total(Id,Total) ::-
  atom(Id),
  number(Total).


%! stat:count
%
% Private predicate
%
% The count

count(Id,Count) ::-
  atom(Id),
  number(Count).


%!counter:timestamp
%
% Private predicate
%
% The timestamp

timestamp(Id,Timestamp) ::-
  atom(Id),
  number(Timestamp).
