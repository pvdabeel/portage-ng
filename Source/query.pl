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


%! query:execute(Query)
%
% Executes a query

%execute([]) :- !.

%execute([Literal|Rest]) :-
%  !,
%  execute(Literal),
%  execute(Rest).


% query

execute(query(none,R,C,P,['','','',''],F),R://I) :-
   !,
   cache:ordered_entry(R,I,C,P,_),
   apply_filters(R://I,F).

execute(query(none,R,C,P,V,F),R://I) :-
   !,
   cache:ordered_entry(R,I,C,P,V),
   apply_filters(R://I,F).

execute(query(O,R,C,P,V,F),R://I) :-
   !,
   cache:ordered_entry(R,I,C,P,PV),
   apply_version_filter(O,PV,V),
   apply_filters(R://I,F).


% version filter

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

apply_version_filter(equal,Version,Version) :-
  !.

apply_version_filter(tilde,[Version,_,_,_],[Version,_,_,_]) :-
  !.



apply_filters(_R://_I,[]) :- !.

apply_filters(R://I,[H|T]) :-
  !,
  apply_filter(R://I,H),
  apply_filters(R://I,T).

apply_filter(_R://_I,[]) :- !.




%execute(repository(R)) :-
%  !,
%  cache:repository(R).

%execute(category(R,C)) :-
%  !,
%  cache:category(R,C).

%execute(package(C,N,R://Id)) :-
%  !,
%  cache:package(R,C,N),
%  cache:ordered_entry(R,Id,C,N,_).

%execute(version(R://Id,Ver)) :-
%  !,
%  cache:ordered_entry(R,Id,_,_,[_,_,_,Ver]).

%execute(entry(R://Id,Cat,Name,Ver)) :-
%  !,
%  cache:ordered_entry(R,Id,_,Cat,Name,[_,_,_,Ver]).

%execute(metadata(R://Id,Key,Value)) :-
%  !,
%  cache:entry_metadata(R,Id,Key,Value).

%execute(installed(R://Id)) :-
%  !,
%  cache:entry_metadata(R,Id,installed,true).

%execute(not(Literal)) :-
%  !,
%  not(execute(Literal)).

%execute(Prolog) :-
%  Prolog.
