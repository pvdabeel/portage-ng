/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2019, Pieter Van den Abeele

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

planner:zerorules([constraint(C)|Rest],ZeroWeights,[constraint(C)|TempZeroWeights],[constraint(C)|ZeroRules],NonZeroRules) :-
  !,
  planner:zerorules(Rest,ZeroWeights,TempZeroWeights,ZeroRules,NonZeroRules).

planner:zerorules([assumed(rule(Head,Body))|Rest],ZeroWeights,[Head|TempZeroWeights],[assumed(rule(Head,Body))|ZeroRules],NonZeroRules) :-
  exclude(prover:is_constraint,Body,TempBody),
  subtract(TempBody,ZeroWeights,[]),!,
  planner:zerorules(Rest,ZeroWeights,TempZeroWeights,ZeroRules,NonZeroRules).

planner:zerorules([rule(Head,Body)|Rest],ZeroWeights,[Head|TempZeroWeights],[rule(Head,Body)|ZeroRules],NonZeroRules) :-
  exclude(prover:is_constraint,Body,TempBody),
  subtract(TempBody,ZeroWeights,[]),!,
  planner:zerorules(Rest,ZeroWeights,TempZeroWeights,ZeroRules,NonZeroRules).

planner:zerorules([rule(Head,Body)|Rest],ZeroWeights,TempZeroWeights,ZeroRules,[rule(Head,Body)|NonZeroRules]) :-
  !,
  planner:zerorules(Rest,ZeroWeights,TempZeroWeights,ZeroRules,NonZeroRules).



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
% Creates a plan for every entry in a repository

planner:test(Repository) :-
  config:time_limit(T),
  preference:proving_target(Action),
  time(forall(Repository:entry(E),
 	      ((message:success(E),
                call_with_time_limit(T,(prover:prove(Repository://E:Action,[],Proof,[],_,[],_),planner:plan(Proof,[],[],_))));
               (message:failure(E))))
      ),
  Repository:get_size(S),
  message:inform(['created plan for ',S,' ',Repository,' entries.']).


%! planner:testparallel(+Repository)
%
% Creates a plan for every entry in a repository, concurrently

planner:testparallel(Repository) :-
  preference:proving_target(Action),
  findall((prover:prove(Repository://E:Action,[],Proof,[],_,[],_),planner:plan(Proof,[],[],_)),Repository:entry(E),Calls),
  config:number_of_cpus(Cpus),
  time(concurrent(Cpus,Calls,[])),
  Repository:get_size(S),
  message:inform(['created plan for ',S,' ',Repository,' entries.']).
