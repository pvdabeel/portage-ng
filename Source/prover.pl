/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2025, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> PROVER
    The prover computes a proof and a model for a given input.

    ASSOC version with AVL trees for proof, model and constraints.
*/

:- module(prover, []).
:- dynamic prover:flag/1.

% =============================================================================
% PROVER declarations
% =============================================================================

prover:prove_lists(Target,[],Proof,[],Model,[],Constraints) :-
  prover:prove(Target,t,AvlProof,t,AvlModel,t,AvlConstraints),
  proof_to_list(AvlProof,Proof),
  model_to_list(AvlModel,Model),
  constraints_to_list(AvlConstraints,Constraints).

% -----------------------------------------------------------------------------
% CASE 1: A list of literals to prove
% -----------------------------------------------------------------------------

prover:prove([],Proof,Proof,Model,Model,Constraints,Constraints) :- !.

prover:prove([Literal|Rest],Proof,NewProof,Model,NewModel,Cons,NewCons) :-
  !,
  prover:prove(Literal, Proof,MidProof,    Model,MidModel,    Cons,MidCons),
  prover:prove(Rest,    MidProof,NewProof, MidModel,NewModel, MidCons,NewCons).


% -----------------------------------------------------------------------------
% CASE 2: A single literal (plain or context‑annotated)
% -----------------------------------------------------------------------------

prover:prove(Full, Proof,       NewProof,
                   Model,       NewModel,
                   Constraints, NewConstraints) :-

  canon_literal(Full, Lit, Ctx),

  (   %-------------------------------------------------------------
      % Constraint goals unify directly with a global constraint set
      %-------------------------------------------------------------
      prover:is_constraint(Lit) ->
      !,
      Proof  = NewProof,
      Model  = NewModel,
      prover:unify_constraints(Lit, Constraints, NewConstraints)

  ;   %-------------------------------------------------------------
      % Already proven (fact or derived)
      %-------------------------------------------------------------
      prover:proven(Lit, Model) ->
      Proof = NewProof,
      Model = NewModel,
      Constraints = NewConstraints

  ;   %-------------------------------------------------------------
      % Already assumed proven
      %-------------------------------------------------------------
      prover:assumed_proven(Lit, Model) ->
      Proof = NewProof,
      Model = NewModel,
      Constraints = NewConstraints

  ;   %-------------------------------------------------------------
      % NAF conflict with current model → fail immediately
      %-------------------------------------------------------------
      prover:conflicts(Lit, Model) ->
      fail

  ;   %-------------------------------------------------------------
      % In‑proof NAF conflict for rule(Lit,[]) → fail
      %-------------------------------------------------------------
      prover:conflictrule(rule(Lit,[]), Proof) ->
      fail

  ;   %-------------------------------------------------------------
      % Two branches:
      %   (A) we are already proving rule(Lit,_) ⇒ assume Lit
      %   (B) pick a rule/2 with head Lit and apply it
      %-------------------------------------------------------------
      (   prover:proving(rule(Lit,_), Proof),
          \+ prover:assumed_proving(Lit, Proof)

      ->  !,
          % (A) Cycle → assume once and for all
          put_assoc(assumed(rule(Lit)),Proof,[]?Ctx,NewProof),
          put_assoc(assumed(Lit),Model,Ctx,NewModel),
          NewConstraints = Constraints

      ;   % (B) Select rule/2 from program
          rule(Full, Body),
          (   Body = []

          ->  !,
              % fact – commit to first fact found
              put_assoc(rule(Lit),Proof,[]?Ctx,NewProof),
              put_assoc(Lit,Model,Ctx,NewModel),
              NewConstraints = Constraints

          ;   % non‑empty body – prove sequentially
              put_assoc(rule(Lit),Proof,Body?Ctx,Proof1),
              prover:prove(Body,
                           Proof1,
                           NewProof,
                           Model,
                           BodyModel,
                           Constraints,
                           BodyConstraints),
              put_assoc(Lit,BodyModel,Ctx,NewModel),
              NewConstraints = BodyConstraints
          )
      )
  ).


% =============================================================================
% Proof helper predicates
% =============================================================================

% A literal is proven if it appears in the model.
prover:proven(Lit, Model) :-
  get_assoc(Lit,Model,_).

% Ditto for assumed literals.
prover:assumed_proven(Lit, Model) :-
  get_assoc(assumed(Lit), Model, _).

% A rule is "being proven" if it appears in the current proof.
prover:proving(rule(Lit, Body), Proof) :-
  get_assoc(rule(Lit),Proof,Body?_).

% Likewise for assumed rules.
prover:assumed_proving(Lit, Proof) :-
  get_assoc(assumed(rule(Lit)),Proof,[]?_).

% Negation‑as‑failure conflicts.
prover:conflicts(Lit, Model) :-
  (   Lit = naf(Inner) ->
      (   prover:proven(Inner, Model)
      ;   prover:assumed_proven(Inner, Model)
      )
  ;   prover:proven(naf(Lit), Model)
  ), !.

% Conflict *during* proving (rule vs. naf(rule))
prover:conflictrule(rule(Lit,_), Proof) :-
  (   Lit = naf(Inner) ->
      (   prover:proving(rule(Inner,_), Proof)
      ;   prover:assumed_proving(Inner, Proof)
      )
  ;   prover:proving(rule(naf(Lit),_), Proof)
  ), !.


% =============================================================================
% CONSTRAINT
% =============================================================================

% A constraint literal recogniser
prover:is_constraint(constraint(_)).


% -----------------------------------------------------------------------------
% Constraints unification
% -----------------------------------------------------------------------------

% Case: Key exists → update or fail
prover:unify_constraints(constraint(Key:{Value}),Constraints,NewConstraints) :-
  get_assoc(Key,Constraints,CurrentValue,NewConstraints,NewValue),!,
  prover:unify_constraint(Value,CurrentValue,NewValue).

% Case: Key doesn't exist → insert
prover:unify_constraints(constraint(Key:{Value}),Constraints,NewConstraints) :-
  prover:unify_constraint(Value,{},NewValue),
  put_assoc(Key,Constraints,NewValue,NewConstraints).


% Case: empty input, no existing constraints
prover:unify_constraint([],{},Assoc) :-		% []    + {}     → t
  empty_assoc(Assoc),!.

% Case: atom input, no existing constraints
prover:unify_constraint(Atom,{},Atom) :-        % atom  + {}     → atom
  is_of_type(atom,Atom),!.

% Case: atom input, no existing constraints
prover:unify_constraint(List,{},Assoc) :-       % list  + {}     → t{..}
  is_list(List),!,
  prover:list_to_assoc(List,Assoc).

% Case: empty input, existing constraints
prover:unify_constraint([],Assoc,Assoc) :-	% []    + t{..}  → t{..}
  is_assoc(Assoc),!.

% Case: atom input, existing constraints
prover:unify_constraint(Atom,Atom,Atom) :-	% atom  + atom   → atom
  is_of_type(atom,Atom),!.

% Case: list input, empty constraints
prover:unify_constraint(List,E,Assoc) :-	% list  + t      → t{..}
  is_list(List),
  empty_assoc(E),!,
  prover:list_to_assoc(List,Assoc).

% Case list input, existing constraints
prover:unify_constraint(List,M,Assoc) :-	% list  + t{..}  → t{..} (proven)
  is_of_type(list,List),
  is_assoc(M),!,
  prover:prove(List,t,_,M,Assoc,t,_).


% =============================================================================
% Helper: canonicalise literals and rules
% =============================================================================

% canon_literal(?Full, ?Core, ?Ctx)
%
%   Full  – full format
%   Core  – part *before* the context annotation.
%   Ctx   – the context ({} for the “no‑context” case).
%
% Convert between full format and key-value pair used
% for the AVL model tree

canon_literal(R://L:A,       R://L:A,  {})  :- !.
canon_literal(R://L:A?{Ctx}, R://L:A,  Ctx) :- !.
canon_literal(R://L,         R://L,    {})  :- !.
canon_literal(R://L?{Ctx},   R://L,    Ctx) :- !.
canon_literal(L:A,           L:A,      {})  :- !.
canon_literal(L:A?{Ctx},     L:A,      Ctx) :- !.
canon_literal(L,             L,        {})  :- !.
canon_literal(L?{Ctx},       L,        Ctx) :- !.

% canon_rule(?Full, ?Key, ?Value
%
% Convert between full format and key-value pair used
% for the AVL proof tree

canon_rule(assumed(rule(L,B)),     assumed(rule(L)), B?{})   :- !.
canon_rule(assumed(rule(L?Ctx,B)), assumed(rule(L)), B?Ctx)  :- !.
canon_rule(rule(L,B),              rule(L),          B?{})   :- !.
canon_rule(rule(L?Ctx,B),          rule(L),          B?Ctx)  :- !.


% =============================================================================
%  Helper: AVL assoc convertors
% =============================================================================

% AVL proof to List proof
proof_to_list(Assoc, List) :-
  findall(Full,
          (gen_assoc(Key,Assoc,Value),
           canon_rule(Full,Key,Value)),
          List).


% AVL model to List model
model_to_list(Assoc, List) :-
  findall(Full,
          (gen_assoc(Key,Assoc,Value),
           canon_literal(Full,Key,Value)),
          List).


% AVL constraints to List model
constraints_to_list(Assoc, List) :-
  findall(Full,
          (gen_assoc(Key,Assoc,Value),
           canon_literal(Full,Key,Value)),
          List).


% List proof to AVL proof
list_to_proof(List, Assoc) :-
  empty_assoc(Empty),
  foldl(add_to_proof, List, Empty, Assoc).

add_to_proof(Full, InAssoc, OutAssoc) :-
  canon_rule(Full, Key, Value),
  put_assoc(Key, InAssoc, Value, OutAssoc).


% List model to AVL model
list_to_model(List, Assoc) :-
  empty_assoc(Empty),
  foldl(add_to_model, List, Empty, Assoc).

add_to_model(Full, InAssoc, OutAssoc) :-
  canon_literal(Full, Key, Value),
  put_assoc(Key, InAssoc, Value, OutAssoc).


% List constraints to AVL constraints
list_to_constraints(List, Assoc) :-
  empty_assoc(Empty),
  foldl(add_to_constraints, List, Empty, Assoc).

add_to_constraints(Full, InAssoc, OutAssoc) :-
  canon_literal(Full, Key, Value),
  put_assoc(Key, InAssoc, Value, OutAssoc).


% Generic list to Generic Assoc, with {} as value
list_to_assoc(List, Assoc) :-
  empty_assoc(Empty),
  foldl(add_to_assoc, List, Empty, Assoc).

add_to_assoc(Key,InAssoc,OutAssoc) :-
  put_assoc(Key,InAssoc,{},OutAssoc).


% =============================================================================
%  Automated testing helpers
% =============================================================================

%! prover:test(+Repository)
prover:test(Repository) :-
  config:test_style(Style),
  prover:test(Repository,Style).

%! prover:test(+Repository,+Style)
prover:test(Repository,Style) :-
  config:proving_target(Action),
  tester:test(Style,
              'Proving',
              Repository://Entry,
              Repository:entry(Entry),
              ( with_q(prover:prove(Repository://Entry:Action?{[]},t,_,t,_,t,_)) )).

%! prover:test_latest(+Repository)
prover:test_latest(Repository) :-
  config:test_style(Style),
  prover:test_latest(Repository,Style).

%! prover:test_latest(+Repository,+Style)
prover:test_latest(Repository,Style) :-
  config:proving_target(Action),
  tester:test(Style,
              'Proving',
              Repository://Entry,
              ( Repository:package(C,N),once(Repository:ebuild(Entry,C,N,_)) ),
              ( with_q(prover:prove(Repository://Entry:Action?{[]},t,_,t,_,t,_)) )).
