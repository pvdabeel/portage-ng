/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2025, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> PROVER
The prover computes a proof and a model for a given input.
*/

:- module(prover, []).

:- dynamic prover:flag/1.


% *******************
% PROVER declarations
% *******************

% -----------------------------------
% CASE 1: A list of literals to prove
% -----------------------------------

prover:prove([],Proof,Proof,Model,Model,Constraints,Constraints) :- !.

prover:prove([Literal|OtherLiterals],Proof,NewProof,Model,NewModel,Constraints,NewConstraints) :-
  !,
  prover:prove(Literal,Proof,TempProof,Model,TempModel,Constraints,TempConstraints),
  prover:prove(OtherLiterals,TempProof,NewProof,TempModel,NewModel,TempConstraints,NewConstraints).


% ---------------------------------
% CASE 2: A single literal to prove
% ---------------------------------

% CASE 2a: Literal is a constraint

prover:prove(constraint(Literal),Proof,Proof,Model,Model,Constraints,NewConstraints) :-
  % \+(is_list(Literal)),				% green cut
  !,
  prover:unify_constraints(constraint(Literal),Constraints,NewConstraints).
  % todo: revalidate model against constraints


% CASE 2b: already proven

prover:prove(Literal,Proof,Proof,Model,Model,Constraints,Constraints) :-
  % \+(is_list(Literal)),				% green cut
  % \+(prover:is_constraint(Literal)),			% green cut
  prover:proven(Literal,Model),!.


% CASE 2c: assumed proven

prover:prove(Literal,Proof,Proof,Model,Model,Constraints,Constraints) :-
  % \+(is_list(Literal)),				% green cut
  % \+(prover:is_constraint(Literal)),			% green cut
  prover:assumed_proven(Literal,Model),!.


% CASE 2d: not proven, rule with empty body

prover:prove(Literal,Proof,[rule(Literal,[])|Proof],Model,[Literal|Model],Constraints,Constraints) :-
  % \+(is_list(Literal)),				% green cut
  % \+(prover:is_constraint(Literal)),			% green cut
  % \+(prover:proven(Literal,Model)),			% green cut
  rule(Literal,[]),!,
  \+(prover:conflicts(Literal,Model)),
  \+(prover:conflictrule(rule(Literal,[]),Proof)).


% CASE 2e: not proven, no rule, make assumption

%prover:prove(Literal,Proof,[rule(assumed(rule(Literal,[])))|Proof],Model,[assumed(Literal)|Model],Constraints,Constraints) :-
%   \+(is_list(Literal)),				% green cut
%   \+(prover:is_constraint(Literal)),			% green cut
%   \+(prover:proven(Literal,Model)),			% green cut
%   \+(prover:conflicts(Literal,Model)),
%   \+(prover:conflictrule(rule(Literal,[]),Proof)),
%   \+(rule(Literal,_)),!.


% CASE 2f: not proven, proving, make assumption

prover:prove(Literal,Proof,NewProof,Model,NewModel,Constraints,NewConstraints) :-
  % \+(is_list(Literal)),				% green cut
  % \+(prover:is_constraint(Literal)),			% green cut
  % \+(prover:proven(Literal,Model)),			% green cut
  % rule(Literal,Body),
  % \+(prover:fact(rule(Literal,Body))),		% green cut
  prover:proving(rule(Literal,_),Proof),
  \+(prover:assumed_proving(Literal,Proof)),!,
  \+(prover:conflicts(Literal,Model)),
  \+(prover:conflictrule(rule(Literal,[]),Proof)),
  prover:prove([],[assumed(rule(Literal,[]))|Proof],NewProof,[assumed(Literal)|Model],NewModel,Constraints,NewConstraints).


% CASE 2g: not proven, not proving, check if oracle knows otherwise prove body

prover:prove(Literal,Proof,NewProof,Model,[Literal|NewModel],Constraints,NewConstraints) :-
  % \+(is_list(Literal)),				% green cut
  % \+(prover:is_constraint(Literal)),			% green cut
  % \+(prover:proven(Literal,Model)),			% green cut
  \+(prover:conflicts(Literal,Model)),
  \+(prover:conflictrule(rule(Literal,[]),Proof)),
  rule(Literal,Body),
  % \+(prover:fact(rule(Literal,Body))),		% green cut
  % \+(prover:proving(rule(Literal,Body),Proof)),	% green cut
  % prover:prove(Body,[rule(Literal,Body)|Proof],NewProof,Model,NewModel,Constraints,NewConstraints).
  prover:prove(Body,[rule(Literal,Body)|Proof],NewProof,Model,NewModel,Constraints,NewConstraints).


% -----------------------------------------
% FACT: A fact is a rule with an empty body
% -----------------------------------------

prover:fact(rule(_,[])) :- !.


% ----------------------------------------------------------
% PROVEN: A literal is proven if it is part of a given model
% ----------------------------------------------------------

prover:proven(Literal?_, Model) :- !, memberchk(Literal?_,Model).
prover:proven(Literal, Model) :- !, memberchk(Literal,Model).


% -----------------------------------------------------------------------------
% ASSUMED PROVEN: A literal is proven if its assumption is part of a given model
% -----------------------------------------------------------------------------

prover:assumed_proven(Literal?_, Model) :- !, memberchk(assumed(Literal?_),Model).
prover:assumed_proven(Literal, Model) :- !, memberchk(assumed(Literal),Model).


% --------------------------------------------------------------
% PROVING: A rule is being proven if it is part of a given proof
% --------------------------------------------------------------

prover:proving(rule(Head?_,Body), Proof) :- !, memberchk(rule(Head?_,Body), Proof).
prover:proving(Rule, Proof) :- !, memberchk(Rule, Proof).


% ----------------------------------------------------------------------------------
% ASSUMED PROVING: A rule is being proven if its assumption is part of a given proof
% ----------------------------------------------------------------------------------

prover:assumed_proving(rule(Literal?_,_), Proof) :- !, memberchk(assumed(rule(Literal?_,[])), Proof).
prover:assumed_proving(rule(Literal,_), Proof) :- !, memberchk(assumed(rule(Literal,[])), Proof).


% ---------------------------------------------------------------------------------------------
% CONFLICTS: Negation as failure is implemented as a relation between literals in a given model
% ---------------------------------------------------------------------------------------------

prover:conflicts(naf(Literal?_), Model) :- prover:proven(Literal?_,Model),!.
prover:conflicts(naf(Literal?_), Model) :- prover:assumed_proven(Literal?_,Model),!.
prover:conflicts(Literal?_, Model) :- !, prover:proven(naf(Literal?_),Model),!. % reformulate as constraint

prover:conflicts(naf(Literal), Model) :- prover:proven(Literal,Model),!.
prover:conflicts(naf(Literal), Model) :- prover:assumed_proven(Literal,Model),!.
prover:conflicts(Literal, Model) :- !, prover:proven(naf(Literal),Model),!. % reformulate as constraint


% ------------------------------------------------------------------
% CONFLICT RULE: Negation as failure can be triggered during proving
% ------------------------------------------------------------------

prover:conflictrule(rule(naf(Literal?_),_), Proof) :- prover:proving(rule(Literal?_,_),Proof),!.
prover:conflictrule(rule(naf(Literal?_),_), Proof) :- prover:assumed_proving(rule(Literal?_,_),Proof),!.
prover:conflictrule(rule(Literal?_,_), Proof) :- !, prover:proving(rule(naf(Literal?_),_),Proof).

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
  feature_unification:unify([Constraint],Constraints,NewConstraints).


% -----
% MODEL
% -----

prover:model(Literals,Model) :-
  prover:prove(Literals,[],_,[],Model,[],_).


% ----
% TEST
% ----

%! prover:test(+Repository)
%
% Prove all entries in a given Repository
%
% Repository: The repository instance from which to parse all entries.
%
% Proves a repository using the default reporting style.

prover:test(Repository) :-
  config:test_style(Style),
  prover:test(Repository,Style).


%! prover:test(+Repository,+Style)
%
% Same as prover:test(+Repository), but uses a specified reporting style
% 'single_verbose', 'parallel_verbose' or 'parallel_fast'.

prover:test(Repository,Style) :-
  config:proving_target(Action),
  tester:test(Style,
              'Proving',
              Repository://Entry,
              (Repository:entry(Entry)),
              (with_q(prover:prove(Repository://Entry:Action?{[]},[],_Proof,[],_Model,[],_Constraint)))).


%! prover:test_latest(+Repository,+Style)
%
% Same as prover:test(+Repository,+Style), but only tests highest version
% of every package.

prover:test_latest(Repository,Style) :-
  config:proving_target(Action),
  tester:test(Style,
              'Proving',
              Repository://Entry,
              (Repository:package(C,N),once(Repository:ebuild(Entry,C,N,_))),
              (with_q(prover:prove(Repository://Entry:Action?{[]},[],_Proof,[],_Model,[],_Constraint)))).
