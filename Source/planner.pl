/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2020, Pieter Van den Abeele

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
% Creates a plan for every entry in a repository, reports on progress in default style

planner:test(Repository) :-
  config:test_style(Style),
  planner:test(Repository,Style).


%! planner:test(+Repository,+Style)
%
% Creates a plan for every entry in a repository, reports on progress in given style

planner:test(Repository,single_verbose) :-
  Repository:get_size(S),
  count:newinstance(counter),
  count:init(0,S),
  config:time_limit(T),
  config:proving_target(Action),
  time(forall(Repository:entry(E),
 	      (catch(call_with_time_limit(T,(count:increase,
                                             count:percentage(P),
                                             message:title(['Planning (Single thread): ',P,' complete']),
                                             prover:prove(Repository://E:Action,[],Proof,[],_,[],_),
                                             planner:plan(Proof,[],[],_),
                                             message:success([P,' - ',E:Action]))),
                     time_limit_exceeded,
                     assert(prover:broken(Repository://E)));
               message:failure(E)))),!,
  message:inform(['created plan for ',S,' ',Repository,' entries.']).


planner:test(Repository,parallel_verbose) :-
  Repository:get_size(S),
  count:newinstance(counter),
  count:init(0,S),
  config:time_limit(T),
  config:proving_target(Action),
  config:number_of_cpus(Cpus),
  findall((catch(call_with_time_limit(T,(prover:prove(Repository://E:Action,[],Proof,[],_,[],_),!,
                                         planner:plan(Proof,[],[],_),
                                         with_mutex(mutex,(count:increase,
                                                           count:percentage(P),
                                                           message:title(['Planning (',Cpus,' threads): ',P,' complete']),
                                                           message:success([P,' - ',E:Action]))))),
                  time_limit_exceeded,
                  assert(prover:broken(Repository://E)))),
          Repository:entry(E),
          Calls),
  time(concurrent(Cpus,Calls,[])),!,
  message:inform(['created plan for ',S,' ',Repository,' entries.']).


planner:test(Repository,parallel_fast) :-
  Repository:get_size(S),
  config:proving_target(Action),
  config:number_of_cpus(Cpus),
  findall((prover:prove(Repository://E:Action,[],Proof,[],_,[],_),
           planner:plan(Proof,[],[],_),!),
          Repository:entry(E),
          Calls),
  time(concurrent(Cpus,Calls,[])),!,
  message:inform(['created plan for ',S,' ',Repository,' entries.']).
