/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2021, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> QUERY
An implementation of a query language for the knowledge base
*/


% ******************
% QUERY declarations
% ******************

perform_query([]) :- !.

perform_query([Literal|Rest]) :-
  query_literal(Literal),
  perform_query(Rest).


query_literal(repository(R)) :-
  !,
  cache:repository(R).

query_literal(category(R,C)) :-
  !,
  cache:category(R,C).

query_literal(package(C,N,R://Id)) :-
  !,
  cache:package(R,C,N,V),
  member([_,_,_,_,Id],V).

query_literal(version(R://Id,Ver)) :-
  !,
  cache:entry(R,Id,_,_,_,[_,_,_,Ver]).

query_literal(entry(R://Id,Cat,Name,Ver)) :-
  !,
  cache:entry(R,Id,_,Cat,Name,[_,_,_,Ver]).

query_literal(metadata(R://Id,Key,Value)) :-
  !,
  cache:entry_metadata(R,Id,Key,Value).

query_literal(not(Literal)) :-
  !,
  not(query_literal(Literal)).

query_literal(Prolog) :-
  Prolog.
