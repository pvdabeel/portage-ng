/*                                                                              
  Author:   Pieter Van den Abeele                                               
  E-mail:   pvdabeel@mac.com                                                    
  Copyright (c) 2005-2019, Pieter Van den Abeele                                
                                                                                
  Distributed under the terms of the LICENSE file in the root directory of this 
  project.                                                                      
*/                                                                              
                                                                                
                                                                                
/** <module> PROVER                                                            
The prover computes a proof and a model for a given input
*/     

:- module(prover, []).

% *******************
% PROVER declarations
% *******************


% ------------------------------------------
% CASE 1: A list of literals to prove, empty
% ------------------------------------------

prover:prove([],Proof,Proof,Model,Model) :- !.


% ----------------------------------------------
% CASE 2: A list of literals to prove, not empty
% ----------------------------------------------

prover:prove([Literal|OtherLiterals],Proof,NewProof,Model,NewModel) :-
  !,
  prover:prove(Literal,Proof,TempProof,Model,TempModel),
  prover:prove(OtherLiterals,TempProof,NewProof,TempModel,NewModel).


% -------------------------------------------------
% CASE 3: A single literal to prove, already proven
% -------------------------------------------------

prover:prove(Literal,Proof,Proof,Model,Model) :-
  not(is_list(Literal)),
  prover:proven(Literal,Model),!.


% ----------------------------------------------------------------------------------------
% CASE 4: A contextual single literal to prove, not proven, not conflicting, body is empty
% ----------------------------------------------------------------------------------------

prover:prove(Literal,Proof,[rule(Literal,[])|Proof],Model,[Literal|Model]) :-
  not(is_list(Literal)),
  not(prover:proven(Literal,Model)),
  not(prover:conflicts(Literal,Model)),
  not(prover:conflictrule(rule(Literal,[]),Proof)),
  rule(Literal,[]).


% ---------------------------------------------------------------------------
% CASE 5: A single contextual literal to prove, not proven, body is not empty
% ---------------------------------------------------------------------------

prover:prove(Literal,Proof,NewProof,Model,[Literal|NewModel]) :-
  not(is_list(Literal)),
  not(prover:proven(Literal,Model)),
  not(prover:conflicts(Literal,Model)), 
  not(prover:conflictrule(rule(Literal,[]),Proof)),
  rule(Literal,Body),
  not(prover:fact(rule(Literal,Body))),
  not(prover:proving(rule(Literal,Body),Proof)),
  prover:prove(Body,[rule(Literal,Body)|Proof],NewProof,Model,NewModel).


% -----------------------------------------
% FACT: A fact is a rule with an empty body
% -----------------------------------------

prover:fact(rule(_,[])) :- !.


% ----------------------------------------------------------
% PROVEN: A literal is proven if it is part of a given model
% ----------------------------------------------------------

prover:proven(Literal, Model) :- member(Literal,Model), !.

% --------------------------------------------------------------
% PROVING: A rule is being proven if it is part of a given proof
% --------------------------------------------------------------

prover:proving(Rule, Proof) :- member(Rule, Proof), !.


% Negation as failure is implemented as a relation between literals in a given model
% For pruning rules in choicepoints, we also implement conflicts in proof

prover:conflicts(naf(Literal), Model) :- !, prover:proven(Literal,Model).
prover:conflicts(Literal, Model) :- prover:proven(naf(Literal),Model).

prover:conflictrule(rule(naf(Literal),_), Proof) :- !, prover:proving(rule(Literal,_),Proof).
prover:conflictrule(rule(Literal,_), Proof) :- !, prover:proving(rule(naf(Literal),_),Proof).


%! prover:test(+Repository)
%
% Prove all entries in a given Repository

prover:test(Repository) :-
  system:time(
              system:forall(Repository:entry(E),
 	                    ((message:success(E),
                              call_with_time_limit(10,prover:prove(Repository://E:install,[],_,[],_)));
			     (message:failure(E)))
                           )
             ),
  Repository:get_size(S),
  message:inform(['proved ',S,' ',Repository,' entries.']).


%! prover:testparallel(+Repository)
%
% Prove all entries in a given Repository, but do it concurrently

prover:testparallel(Repository) :-
  findall(call_with_time_limit(10,prover:prove(Repository://E:install,[],_,[],_)),Repository:entry(E),Calls), 
  config:number_of_cpus(Cpus),                                          
  time(concurrent(Cpus,Calls,[])),                                              
  Repository:get_size(S),                                                       
  message:inform(['proved ',S,' ',Repository,' entries.']).   
