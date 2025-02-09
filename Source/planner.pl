/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2024, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> PLANNER
The Builder takes a plan from the Planner and executes it.

Given a proof, consider it as graph, apply the following algorithm,
based on topological sort:

1. For each rule, determine weight
2. Filter out rules with zero weight
3. Continue weighting until there are no more edges in the graph
*/

:- module(planner, []).

% ********************
% PLANNER declarations
% ********************


%! planner:zerorules(+List,-List,+List,+List,-List)
%
% Iteratively filter out the rules in a list with zero weight

planner:zerorules([],Weights,Weights,[],[]) :- !.

planner:zerorules([constraint(_)|Rest],ZeroWeights,TempZeroWeights,ZeroRules,NonZeroRules) :-
  !,
  planner:zerorules(Rest,ZeroWeights,TempZeroWeights,ZeroRules,NonZeroRules).

planner:zerorules([assumed(rule(Head,Body))|Rest],ZeroWeights,[Head|TempZeroWeights],[assumed(rule(Head,Body))|ZeroRules],NonZeroRules) :-
  planner:is_zero(Body,ZeroWeights),!,
  planner:zerorules(Rest,ZeroWeights,TempZeroWeights,ZeroRules,NonZeroRules).

planner:zerorules([rule(Head,Body)|Rest],ZeroWeights,[Head|TempZeroWeights],[rule(Head,Body)|ZeroRules],NonZeroRules) :-
  planner:is_zero(Body,ZeroWeights),!,
  planner:zerorules(Rest,ZeroWeights,TempZeroWeights,ZeroRules,NonZeroRules).

planner:zerorules([Rule|Rest],ZeroWeights,TempZeroWeights,ZeroRules,[Rule|NonZeroRules]) :-
  !,
  planner:zerorules(Rest,ZeroWeights,TempZeroWeights,ZeroRules,NonZeroRules).


%! planner:is_zero(+Body,+Weights)
%
% Check whether a body has zero weight

planner:is_zero([],_) :- !.

% planner:is_zero([constraint(_)|R],W) :- !, planner:is_zero(R,W).

planner:is_zero([E|R],W) :- memberchk(E,[constraint(_)|W]),!, planner:is_zero(R,W).


%! planner:plan(+Rules,+Weights,+OldPlan,+NewPlan)
%
% Creates a plan by weighting rules

planner:plan([],_,OldPlan,OldPlan) :- !.

planner:plan(Rules,InitialWeights,OldPlan,[ZeroRules|TempPlan]) :-
  planner:zerorules(Rules,InitialWeights,NewWeights,ZeroRules,NonZeroRules),
  ZeroRules \= [],!,
  planner:plan(NonZeroRules,NewWeights,OldPlan,TempPlan).


%! planner:test(+Repository)
%
% Creates a plan for every entry in a repository, reports on progress in default style

planner:test(Repository) :-
  config:test_style(Style),
  planner:test(Repository,Style).


%! planner:test(+Repository,+Style)
%
% Creates a plan for every entry in a repository, reports on progress in given style

planner:test(Repository,Style) :-
  config:proving_target(Action),
  tester:test(Style,
              'Planning',
              Repository://Entry,
              (Repository:entry(Entry)),
              (with_q(prover:prove(Repository://Entry:Action,[],Proof,[],_Model,[],_Constraint)),
               with_q(planner:plan(Proof,[],[],_Plan)))).


%! planner:test_latest(+Repository,+Style)
%
% Same as planner:test(+Repository,+Style), but only tests highest version
% of every package.

planner:test_latest(Repository,Style) :-
  config:proving_target(Action),
  tester:test(Style,
              'Planning latest',
              Repository://Entry,
              (Repository:package(C,N),once(Repository:ebuild(Entry,C,N,_))),
              (with_q(prover:prove(Repository://Entry:Action,[],Proof,[],_Model,[],_Constraint)),
	       with_q(planner:plan(Proof,[],[],_Plan)))).
