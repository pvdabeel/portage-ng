/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2024, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> QUERY
An implementation of a query language for the knowledge base
*/

:- module(query,[]).


% ******************
% QUERY declarations
% ******************

%! query:execute(+List)
%
% Executes a query

execute([]) :- !.

execute([Literal|Rest]) :-
  !,
  execute(Literal),
  execute(Rest).

execute(repository(R)) :-
  !,
  cache:repository(R).

execute(category(R,C)) :-
  !,
  cache:category(R,C).

execute(package(C,N,R://Id)) :-
  !,
  cache:package(R,C,N),
  cache:ordered_entry(R,Id,C,N,_).

execute(version(R://Id,Ver)) :-
  !,
  cache:ordered_entry(R,Id,_,_,[_,_,_,Ver]).

execute(entry(R://Id,Cat,Name,Ver)) :-
  !,
  cache:ordered_entry(R,Id,_,Cat,Name,[_,_,_,Ver]).

execute(metadata(R://Id,Key,Value)) :-
  !,
  cache:entry_metadata(R,Id,Key,Value).

execute(installed(R://Id)) :-
  !,
  cache:entry_metadata(R,Id,installed,true).

execute(not(Literal)) :-
  !,
  not(execute(Literal)).

execute(Prolog) :-
  Prolog.