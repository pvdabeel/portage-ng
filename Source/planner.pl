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


%! planner:notpart(+List,+List,-Element)
%
% Given two lists returns element in the first list but not the second list

planner:notpart(ListA,ListB,El) :-
	member(El,ListA),
	not(member(El,ListB)).

%! planner:zeroweight(+List,+List)
%
% Given two lists, return all elements in the first list but not the second list.

planner:zeroweight(ListA,ListB) :-
	findall(El,planner:notpart(ListA,ListB,El),[]).


%! planner:zerorules(+List,-List,+List,+List,-List)
%
% Iteratively filter out the rules in a list with zero weight

planner:zerorules([],Weights,Weights,[],[]) :- !.
planner:zerorules([rule(Head,Body)|Rest],ZeroWeights,[Head|TempZeroWeights],[rule(Head,Body)|ZeroRules],NonZeroRules) :-
	planner:zeroweight(Body,ZeroWeights),!,
	planner:zerorules(Rest,ZeroWeights,TempZeroWeights,ZeroRules,NonZeroRules).
planner:zerorules([rule(Head,Body)|Rest],ZeroWeights,TempZeroWeights,ZeroRules,[rule(Head,Body)|NonZeroRules]) :-
	planner:zerorules(Rest,ZeroWeights,TempZeroWeights,ZeroRules,NonZeroRules).


%! planner:plan(+Rules,+Weights,+OldPlan,+NewPlan)
%
% Creates a plan by weighting rules

planner:plan([],_,OldPlan,OldPlan) :- !.

planner:plan(Rules,InitialWeights,OldPlan,[ZeroRules|TempPlan]) :-
	planner:zerorules(Rules,InitialWeights,NewWeights,ZeroRules,NonZeroRules),
	planner:plan(NonZeroRules,NewWeights,OldPlan,TempPlan).


%! planner:test(+Repository)
%
% Creates a plan for every entry in a repository

planner:test(Repository) :-
  system:time(
              system:forall(Repository:entry(E),
 	                    ((message:success(E),
                              call_with_time_limit(10,(prover:prove(Repository://E:install,[],Proof,[],_),planner:plan(Proof,[],[],_))));
			     (message:failure(E)))
                           )
             ),
  Repository:get_size(S),
  message:inform(['created plan for ',S,' ',Repository,' entries.']).


%! planner:testparallel(+Repository)
%
% Creates a plan for every entry in a repository, concurrently

planner:testparallel(Repository) :-
  findall(call_with_time_limit(10,(prover:prove(Repository://E:install,[],Proof,[],_),planner:plan(Proof,[],[],_))),Repository:entry(E),Calls),
  config:number_of_cpus(Cpus),
  time(concurrent(Cpus,Calls,[])),
  Repository:get_size(S),
  message:inform(['created plan for ',S,' ',Repository,' entries.']).
