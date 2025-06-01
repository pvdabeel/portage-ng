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


% -------------------------------------------------------
% CASE 2a: “If it’s a constraint(L), unify it and return”
% -------------------------------------------------------

prover:prove(constraint(Lit),
             Proof, Proof,
             Model, Model,
             Constraints, NewConstraints) :-
  !,
  prover:unify_constraints(constraint(Lit), Constraints, NewConstraints).


% ------------------------------------------------------------
% CASE 2b: “If Literal is already in Model as proven, succeed”
% ------------------------------------------------------------
prover:prove(Literal,
             Proof, Proof,
             Model, Model,
             Constraints, Constraints) :-
  prover:proven(Literal, Model),
  !.


% -------------------------------------------------------------
% CASE 2c: “If Literal is already in Model as assumed, succeed”
% -------------------------------------------------------------
prover:prove(Literal,
             Proof, Proof,
             Model, Model,
             Constraints, Constraints) :-
  prover:assumed_proven(Literal, Model),
  !.


% ----------------------------------------------------------------
% COMBINED CASE (2d+2f+2g) for context‐annotated Literal?{Context}
% ----------------------------------------------------------------
prover:prove(Literal?{Context},
             Proof,
             NewProof,
             Model,
             NewModel,
             Constraints,
             NewConstraints) :-

    %— skip constraint goals —%
    \+ prover:is_constraint(Literal?{Context}),

    %— skip if already proven or already assumed —%
    \+ prover:proven(Literal?{Context}, Model),
    \+ prover:assumed_proven(Literal?{Context}, Model),

    %— skip if NAF conflict would arise —%
    \+ prover:conflicts(Literal?{Context}, Model),

    %— skip if there’s an in‐proof conflict for rule(Literal?{Context},[]) —%
    \+ prover:conflictrule(rule(Literal?{Context}, []), Proof),

    %— two branches: (A) cycle→assume, or (B) pick/apply a rule —%
    (
      % (A) We’re already in the middle of proving this same head → assume
      prover:proving(rule(Literal?{Context}, _), Proof),
      \+ prover:assumed_proving(Literal?{Context}, Proof)
    ->
      !,  % commit to assumption
      NewProof       = [ assumed(rule(Literal?{Context}, [])) | Proof ],
      NewModel       = [ assumed(Literal?{Context})           | Model ],
      NewConstraints = Constraints

    ; % (B) Not in a cycle: lookup any rule(Literal?{Context}, Body)
      rule(Literal?{Context}, Body),

      ( Body = []
      ->  % (B1) Fact case: add fact and cut
         !,
         NewProof       = [ rule(Literal?{Context}, [])  | Proof ],
         NewModel       = [ Literal?{Context}            | Model ],
         NewConstraints = Constraints

      ;  % (B2) Non‐empty body: prove each subgoal
         prover:prove(Body,
                      [ rule(Literal?{Context}, Body) | Proof ],
                      NewProof,
                      Model,
                      ModelAfterBody,
                      Constraints,
                      NewConstraints),
         NewModel = [ Literal?{Context} | ModelAfterBody ]
      )
    ).


% -----------------------------------------------------------
% COMBINED CASE (2d+2f+2g) for a plain (non‐compound) Literal
% -----------------------------------------------------------
prover:prove(Literal,
             Proof,
             NewProof,
             Model,
             NewModel,
             Constraints,
             NewConstraints) :-

    %— ensure this is not context‐annotated —%
    \+ prover:test_compound(Literal),

    %— skip constraint goals —%
    \+ prover:is_constraint(Literal),

    %— skip if already proven or assumed —%
    \+ prover:proven(Literal, Model),
    \+ prover:assumed_proven(Literal, Model),

    %— skip if NAF conflict would arise —%
    \+ prover:conflicts(Literal, Model),

    %— skip if in‐proof conflict for rule(Literal,[]) —%
    \+ prover:conflictrule(rule(Literal, []), Proof),

    %— two branches: (A) cycle→assume, or (B) pick/apply a rule —%
    (
      % (A) We’re already “proving rule(Literal,_)” → assume
      prover:proving(rule(Literal, _), Proof),
      \+ prover:assumed_proving(Literal, Proof)
    ->
      !,  % commit to assumption
      NewProof       = [ assumed(rule(Literal, [])) | Proof ],
      NewModel       = [ assumed(Literal)           | Model ],
      NewConstraints = Constraints

    ; % (B) Not in a cycle: lookup any rule(Literal, Body)
      rule(Literal, Body),

      ( Body = []
      ->  % (B1) Fact: add fact, then cut
         !,
         NewProof       = [ rule(Literal, []) | Proof ],
         NewModel       = [ Literal           | Model ],
         NewConstraints = Constraints

      ;  % (B2) Non‐empty body: prove each subgoal (no cut here)
         prover:prove(Body,
                      [ rule(Literal, Body) | Proof ],
                      NewProof,
                      Model,
                      ModelAfterBody,
                      Constraints,
                      NewConstraints),
         NewModel = [ Literal | ModelAfterBody ]
      )
    ).


% -----------------------------------------
% FACT: A fact is a rule with an empty body
% -----------------------------------------

prover:fact(rule(_,[])) :- !.


prover:test_compound(_?_) :- !.

% ----------------------------------------------------------
% PROVEN: A literal is proven if it is part of a given model
% ----------------------------------------------------------

prover:proven(Literal?_, Model) :- !, memberchk(Literal?_,Model).
prover:proven(Literal, Model) :- \+ prover:test_compound(Literal),!, memberchk(Literal,Model).


% -----------------------------------------------------------------------------
% ASSUMED PROVEN: A literal is proven if its assumption is part of a given model
% -----------------------------------------------------------------------------

prover:assumed_proven(Literal?_, Model) :- !, memberchk(assumed(Literal?_),Model).
prover:assumed_proven(Literal, Model) :- \+ prover:test_compound(Literal),!, memberchk(assumed(Literal),Model).


% --------------------------------------------------------------
% PROVING: A rule is being proven if it is part of a given proof
% --------------------------------------------------------------

prover:proving(rule(Head?_,Body), Proof) :- !, memberchk(rule(Head?_,Body), Proof).
prover:proving(rule(Head,Body), Proof) :- \+ prover:test_compound(Head),!, memberchk(rule(Head,Body), Proof).


% ----------------------------------------------------------------------------------
% ASSUMED PROVING: A rule is being proven if its assumption is part of a given proof
% ----------------------------------------------------------------------------------

prover:assumed_proving(rule(Literal?_,_), Proof) :- !, memberchk(assumed(rule(Literal?_,[])), Proof).
prover:assumed_proving(rule(Literal,_), Proof) :- \+ prover:test_compound(Literal),!, memberchk(assumed(rule(Literal,[])), Proof).


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


%! prover:test_latest(+Repository)
%
% Same as prover:test(+Repository), but only tests highest version
% of every package.

prover:test_latest(Repository) :-
  config:test_style(Style),
  prover:test_latest(Repository,Style).


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
