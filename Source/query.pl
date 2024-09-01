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

% EAPI qualifiedtarget generates a query and filter of the form:
%
% query(Operator,Repository,Category,Package,Version,Filter)
%   where is Filter = a list of Slot , Usedep , Manifest , ...


% Command line qualified target

% query - Qualified target EAPI spec via command line interface

qualified_target(query(none,R,C,P,['','','',''],F),R://I) :-
   !,
   cache:ordered_entry(R,I,C,P,_),
   apply_filters(R://I,F).

qualified_target(query(none,R,C,P,V,F),R://I) :-
   !,
   cache:ordered_entry(R,I,C,P,V),
   apply_filters(R://I,F).

qualified_target(query(O,R,C,P,V,F),R://I) :-
   !,
   cache:ordered_entry(R,I,C,P,PV),
   apply_version_filter(O,PV,V),
   apply_filters(R://I,F).


% filter - Qualified target EAPI spec version filter

apply_version_filter(greater,ProposedVersion,Version) :-
  !,
  compare(>,ProposedVersion,Version).

apply_version_filter(greaterequal,ProposedVersion,Version) :-
  !,
  compare(=,ProposedVersion,Version);
  compare(>,ProposedVersion,Version).

apply_version_filter(smaller,ProposedVersion,Version) :-
  !,
  compare(<,ProposedVersion,Version).

apply_version_filter(smallerequal,ProposedVersion,Version) :-
  !,
  compare(=,ProposedVersion,Version);
  compare(<,ProposedVersion,Version).

apply_version_filter(notequal,Version,Version) :-
  fail.

apply_version_filter(equal,Version,Version) :-
  !.

apply_version_filter(tilde,[Version,_,_,_],[Version,_,_,_]) :-
  !.


% other filters - Slot & usedep to be implemented for command line interface

apply_filters(_R://_I,[]) :- !.

apply_filters(R://I,[H|T]) :-
  !,
  apply_filter(R://I,H),
  apply_filters(R://I,T).

apply_filter(_R://_I,[]) :- !.



% Searching via command line


%! query:search(Query)
%
% Executes a query

search([],_://_) :- !.

search([Literal|Rest],R://I) :-
  !,
  search(Literal,R://I),
  search(Rest,R://I).



% search - Searching via command line

search(repository(notequal(R)),R://I) :-
  !,
  \+ cache:ordered_entry(R,I,_,_,_).

search(repository(equal(R)),R://I) :-
  !,
  cache:ordered_entry(R,I,_,_,_).

search(category(notequal(C)),R://I) :-
  !,
  \+ cache:ordered_entry(R,I,C,_,_).

search(category(equal(C)),R://I) :-
  !,
  cache:ordered_entry(R,I,C,_,_).

search(name(notequal(N)),R://I) :-
  !,
  \+ cache:ordered_entry(R,I,_,N,_).

search(name(equal(N)),R://I) :-
  !,
  cache:ordered_entry(R,I,_,N,_).

search(version(V),R://I) :-
  !,
  V =.. [Comparator,RequestedVersion],
  cache:ordered_entry(R,I,_,_,ProposedVersion),
  apply_version_filter(Comparator,ProposedVersion,RequestedVersion).

search(Q,R://I) :-
  !,
  Q =.. [Key,Value],
  Value =.. [equal,PureValue],
  cache:entry_metadata(R,I,Key,PureValue).




%execute(Prolog) :-
%  Prolog.
