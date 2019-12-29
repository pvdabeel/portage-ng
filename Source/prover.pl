/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2020, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> PROVER
The prover computes a proof and a model for a given input
*/

:- module(prover, []).

:- dynamic prover:broken/1.

% *******************
% PROVER declarations
% *******************


%! prover:proof(+Target,+OldProof,-NewProof,+OldModel,-NewModel,+OldConstraints,+NewConstraints)
%
% prove a given Target starting from OldProof and OldModel, producing NewProof
% and NewModel

% ------------------------------------------
% CASE 1: A list of literals to prove, empty
% ------------------------------------------

prover:prove([],Proof,Proof,Model,Model,Constraints,Constraints) :- !.


% ----------------------------------------------
% CASE 2: A list of literals to prove, not empty
% ----------------------------------------------

prover:prove([Literal|OtherLiterals],Proof,NewProof,Model,NewModel,Constraints,NewConstraints) :-
  !,
  prover:prove(Literal,Proof,TempProof,Model,TempModel,Constraints,TempConstraints),
  prover:prove(OtherLiterals,TempProof,NewProof,TempModel,NewModel,TempConstraints,NewConstraints).


% -------------------------------------------------
% CASE 3: A single literal to prove, already proven
% -------------------------------------------------

prover:prove(Literal,Proof,Proof,Model,Model,Constraints,Constraints) :-
  not(is_list(Literal)),
  not(prover:is_constraint(Literal)),
  prover:proven(Literal,Model),!.

prover:prove(Literal,Proof,Proof,Model,Model,Constraints,Constraints) :-
  not(is_list(Literal)),
  not(prover:is_constraint(Literal)),
  prover:assumed_proven(Literal,Model),!.


% ------------------------------------------------------------------------------------------------
% CASE 4a: A single literal to prove, not proven, not conflicting, body is empty
% ------------------------------------------------------------------------------------------------

prover:prove(Literal,Proof,[rule(Literal,[])|Proof],Model,[Literal|Model],Constraints,Constraints) :-
  not(is_list(Literal)),
  not(prover:is_constraint(Literal)),
  not(prover:proven(Literal,Model)),
  not(prover:conflicts(Literal,Model)),
  not(prover:conflictrule(rule(Literal,[]),Proof)),
  rule(Literal,[]).


% -------------------------------------------------------------------------------
% CASE 4a: A single literal to prove, not proven, not conflicting, assumed proven
% -------------------------------------------------------------------------------

prover:prove(Literal,Proof,[rule(Literal,assumed(Literal))|Proof],Model,Model,Constraints,Constraints) :-
  not(is_list(Literal)),
  not(prover:is_constraint(Literal)),
  not(prover:proven(Literal,Model)),
  not(prover:conflicts(Literal,Model)),
  not(prover:conflictrule(rule(Literal,[]),Proof)),
  prover:assumed_proven(Literal,Model).


% -----------------------------------------------------------------------------
% CASE 5: A single literal to prove, not proven, not proving, body is not empty
% -----------------------------------------------------------------------------

prover:prove(Literal,Proof,NewProof,Model,[Literal|NewModel],Constraints,NewConstraints) :-
  not(is_list(Literal)),
  not(prover:is_constraint(Literal)),
  not(prover:proven(Literal,Model)),
  not(prover:conflicts(Literal,Model)),
  not(prover:conflictrule(rule(Literal,[]),Proof)),
  rule(Literal,Body),
  not(prover:fact(rule(Literal,Body))),
  not(prover:proving(rule(Literal,Body),Proof)),
  prover:prove(Body,[rule(Literal,Body)|Proof],NewProof,Model,NewModel,Constraints,NewConstraints).


% -------------------------------------------------------------------------
% CASE 6: A single literal to prove, not proven, proving, body is not empty
% -------------------------------------------------------------------------

prover:prove(Literal,Proof,NewProof,Model,NewModel,Constraints,NewConstraints) :-
  not(is_list(Literal)),
  not(prover:is_constraint(Literal)),
  not(prover:proven(Literal,Model)),
  not(prover:conflicts(Literal,Model)),
  not(prover:conflictrule(rule(Literal,[]),Proof)),
  rule(Literal,Body),
  not(prover:fact(rule(Literal,Body))),
  prover:proving(rule(Literal,Body),Proof),
  not(prover:assumed_proving(Literal,Proof)),
  prover:prove([],[assumed(rule(Literal,[]))|Proof],NewProof,[assumed(Literal)|Model],NewModel,Constraints,NewConstraints).


% -----------------------------
% CASE 7: A constraint to prove
% -----------------------------

prover:prove(Literal,Proof,Proof,Model,Model,Constraints,NewConstraints) :-
  not(is_list(Literal)),
  prover:is_constraint(Literal),
  prover:unify_constraints(Literal,Constraints,NewConstraints).


% -----------------------------------------
% FACT: A fact is a rule with an empty body
% -----------------------------------------

prover:fact(rule(_,[])) :- !.


% ----------------------------------------------------------
% PROVEN: A literal is proven if it is part of a given model
% ----------------------------------------------------------

prover:proven(Literal, Model) :- memberchk(Literal,Model), !.


% -----------------------------------------------------------------------------
% ASSUMED PROVEN: A literal is proven if its assumption is part of a given model
% -----------------------------------------------------------------------------

prover:assumed_proven(Literal, Model) :- memberchk(assumed(Literal),Model), !.


% --------------------------------------------------------------
% PROVING: A rule is being proven if it is part of a given proof
% --------------------------------------------------------------

prover:proving(Rule, Proof) :- memberchk(Rule, Proof), !.


% ----------------------------------------------------------------------------------
% ASSUMED PROVING: A rule is being proven if its assumption is part of a given proof
% ----------------------------------------------------------------------------------

prover:assumed_proving(rule(Literal,_), Proof) :- memberchk(assumed(rule(Literal,[])), Proof) , !.


% ---------------------------------------------------------------------------------------------
% CONFLICTS: Negation as failure is implemented as a relation between literals in a given model
% ---------------------------------------------------------------------------------------------

prover:conflicts(naf(Literal), Model) :- prover:proven(Literal,Model),!.
prover:conflicts(naf(Literal), Model) :- prover:assumed_proven(Literal,Model),!.

prover:conflicts(Literal, Model) :- prover:proven(naf(Literal),Model),!.


% ------------------------------------------------------------------
% CONFLICT RULE: Negation as failure can be triggered during proving
% ------------------------------------------------------------------

prover:conflictrule(rule(naf(Literal),_), Proof) :- prover:proving(rule(Literal,_),Proof),!.
prover:conflictrule(rule(naf(Literal),_), Proof) :- prover:assumed_proving(rule(Literal,_),Proof),!.

prover:conflictrule(rule(Literal,_), Proof) :- !, prover:proving(rule(naf(Literal),_),Proof).


% ---------------------------------------------------------------------------------------
% CONSTRAINT: A constraint is a literal subject to unification with the other constraints
% ---------------------------------------------------------------------------------------

prover:is_constraint(constraint(_)) :- !.


% -----------------------------------------
% UNIFY CONSTRAINTS: constraint unification
% -----------------------------------------

prover:unify_constraints(constraint(Constraint),Constraints,NewConstraints) :-
  feature_unifation:unify([Constraint],Constraints,NewConstraints).


%! prover:test(+Repository)
%
% Prove all entries in a given Repository, using the default style

prover:test(Repository) :-
  config:test_style(Style),
  prover:test(Repository,Style).


%! prover:test(+Repository,+Style)
%
% Prove all entries in a given Repository, according to given style (single threaded, concurrent, verbose)

prover:test(Repository,single_verbose) :-
  Repository:get_size(S),
  count:newinstance(counter),
  count:init(0,S),
  config:time_limit(T),
  config:proving_target(Action),
  time(forall(Repository:entry(E),
 	      (catch(call_with_time_limit(T,(count:increase,
                                             count:percentage(P),
                                             prover:prove(Repository://E:Action,[],_,[],_,[],_),
                                             message:success([P,' - ',E:Action]))),
                     time_limit_exceeded,
                     assert(prover:broken(Repository://E)));
               message:failure(E)))),!,
  message:inform(['proved ',S,' ',Repository,' entries.']).


prover:test(Repository,parallel_verbose) :-
  Repository:get_size(S),
  count:newinstance(counter),
  count:init(0,S),
  config:time_limit(T),
  config:proving_target(Action),
  config:number_of_cpus(Cpus),
  findall((catch(call_with_time_limit(T,(prover:prove(Repository://E:Action,[],_,[],_,[],_),!,
                                         with_mutex(mutex,(count:increase,
                                                           count:percentage(P),
                                                           message:success([P,' - ',E:Action]))))),
                 time_limit_exceeded,
                 assert(prover:broken(Repository://E)))),
          Repository:entry(E),
          Calls),!,
  time(concurrent(Cpus,Calls,[])),!,
  message:inform(['proved ',S,' ',Repository,' entries.']).


prover:test(Repository,parallel_fast) :-
  Repository:get_size(S),
  config:proving_target(Action),
  config:number_of_cpus(Cpus),
  findall((prover:prove(Repository://E:Action,[],_,[],_,[],_),!),
          Repository:entry(E),
          Calls),
  time(concurrent(Cpus,Calls,[])),!,
  message:inform(['proved ',S,' ',Repository,' entries.']).
