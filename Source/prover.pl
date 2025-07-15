/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2025, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> PROVER
    The prover computes a proof, model, constraints, and triggers for a given input.

    This version is enhanced to be configurable:
    - If preference:flag(deep) is set, it performs a from-scratch build,
      optimizing for backtracking by building the Triggers tree at the end.
    - Otherwise, it performs an incremental build, updating the Triggers
      tree as it proves, which is efficient for small additions.
*/

:- module(prover, [canon_rule/3]).

% =============================================================================
%  PROVER declarations
% =============================================================================


% =============================================================================
% Top-Level Entry Point
% =============================================================================

%! prover:prove(+Target, +InProof, -OutProof, +InModel, -OutModel, +InCons, -OutCons, +InTriggers, -OutTriggers)
%
% Main entry point for the prover.
% Orchestrates the proving process and the configurable trigger-building strategy.

prover:prove(Target, InProof, OutProof, InModel, OutModel, InCons, OutCons, InTriggers, OutTriggers) :-

  % Call the core recursive engine.
  prover:prove_recursive(Target, InProof, OutProof, InModel, OutModel, InCons, OutCons, InTriggers, MidTriggers),

  % Check the flag to determine the final trigger-building action.
  (   current_predicate(preference:flag/1), preference:flag(deep) ->
      % From-Scratch Mode: Build the real Triggers tree from the final proof.
      build_triggers_from_proof(OutProof, OutTriggers)
  ;
      % Incremental Mode: The 'MidTriggers' tree is already complete.
      OutTriggers = MidTriggers
  ).


% =============================================================================
% Core Recursive Prover
% =============================================================================

% -----------------------------------------------------------------------------
% CASE 1: A list of literals to prove (Recursive Step)
% -----------------------------------------------------------------------------

prover:prove_recursive([],Proof,Proof,Model,Model,Constraints,Constraints,Triggers,Triggers) :- !.
prover:prove_recursive([Literal|Rest],Proof,NewProof,Model,NewModel,Cons,NewCons,Trig,NewTrig) :-
  !,
  prover:prove_recursive(Literal, Proof,MidProof,    Model,MidModel,    Cons,MidCons,    Trig,MidTrig),
  prover:prove_recursive(Rest,    MidProof,NewProof, MidModel,NewModel, MidCons,NewCons, MidTrig,NewTrig).


% -----------------------------------------------------------------------------
% CASE 2: A single literal to prove (Recursive Step)
% -----------------------------------------------------------------------------

prover:prove_recursive(Full, Proof, NewProof, Model, NewModel, Constraints, NewConstraints, Triggers, NewTriggers) :-
  canon_literal(Full, Lit, Ctx),
  (   prover:is_constraint(Lit) ->
      !,
      Proof  = NewProof,
      Model  = NewModel,
      Triggers = NewTriggers,
      prover:unify_constraints(Lit, Constraints, NewConstraints)

  ;   prover:proven(Lit, Model) ->
      Proof = NewProof,
      Model = NewModel,
      Triggers = NewTriggers,
      Constraints = NewConstraints

  ;   prover:assumed_proven(Lit, Model) ->
      Proof = NewProof,
      Model = NewModel,
      Triggers = NewTriggers,
      Constraints = NewConstraints

  ;   prover:conflicts(Lit, Model) ->
      fail

  ;   prover:conflictrule(rule(Lit,[]), Proof) ->
      fail

  ;   (   prover:proving(rule(Lit,_), Proof),
          \+ prover:assumed_proving(Lit, Proof) ->
          put_assoc(assumed(rule(Lit)), Proof, dep(0, [])?Ctx, NewProof),
          put_assoc(assumed(Lit), Model, Ctx, NewModel),
          NewConstraints = Constraints,
          NewTriggers = Triggers
      ;
          rule(Full, Body),
          length(Body, DepCount),
          put_assoc(rule(Lit), Proof, dep(DepCount, Body)?Ctx, Proof1),
          (   current_predicate(preference:flag/1), preference:flag(deep) ->
              Triggers1 = Triggers
          ;
              prover:add_triggers(Full, Body, Triggers, Triggers1)
          ),
          prover:prove_recursive(Body, Proof1, NewProof, Model, BodyModel, Constraints, BodyConstraints, Triggers1, NewTriggers),
          put_assoc(Lit, BodyModel, Ctx, NewModel),
          NewConstraints = BodyConstraints
      )
  ).


% =============================================================================
% Triggers Helpers
% =============================================================================

build_triggers_from_proof(ProofAVL, TriggersAVL) :-
    empty_assoc(EmptyTriggers),
    assoc_to_list(ProofAVL, RulesAsList),
    foldl(add_rule_triggers, RulesAsList, EmptyTriggers, TriggersAVL).

add_rule_triggers(HeadKey-Value, InTriggers, OutTriggers) :-
    ( prover:canon_rule(rule(Head, Body), HeadKey, Value) ; prover:canon_rule(assumed(rule(Head, Body)), HeadKey, Value) ),
    !,
    ( Value = dep(_, _)?Ctx -> prover:canon_literal(FullHead, Head, Ctx) ; FullHead = Head ),
    prover:add_triggers(FullHead, Body, InTriggers, OutTriggers).
add_rule_triggers(_, InTriggers, InTriggers).

prover:add_triggers(_, [], Triggers, Triggers) :- !.
prover:add_triggers(Head, Body, InTriggers, OutTriggers) :-
    foldl(add_trigger(Head), Body, InTriggers, OutTriggers).

add_trigger(Head, Dep, InTriggers, OutTriggers) :-
    (   prover:is_constraint(Dep)
    ->  OutTriggers = InTriggers
    ;
        canon_literal(Dep, DepLit, _),
        (get_assoc(DepLit, InTriggers, Dependents) -> true ; Dependents = []),
        (memberchk(Head, Dependents) -> NewDependents = Dependents ; NewDependents = [Head | Dependents]),
        put_assoc(DepLit, InTriggers, NewDependents, OutTriggers)
    ).


% =============================================================================
% Proof helper predicates & Canonicalisation
% =============================================================================

prover:proving(rule(Lit, Body), Proof) :- get_assoc(rule(Lit),Proof,dep(_, Body)?_).
prover:assumed_proving(Lit, Proof) :- get_assoc(assumed(rule(Lit)),Proof,dep(0, [])?_).
prover:proven(Lit, Model) :- get_assoc(Lit,Model,_).
prover:assumed_proven(Lit, Model) :- get_assoc(assumed(Lit), Model, _).

prover:conflicts(Lit, Model) :-
  ( Lit = naf(Inner) -> (prover:proven(Inner, Model) ; prover:assumed_proven(Inner, Model))
  ; prover:proven(naf(Lit), Model)
  ), !.

prover:conflictrule(rule(Lit,_), Proof) :-
  ( Lit = naf(Inner) -> (prover:proving(rule(Inner,_), Proof) ; prover:assumed_proving(Inner, Proof))
  ; prover:proving(rule(naf(Lit),_), Proof)
  ), !.


% =============================================================================
% CONSTRAINT
% =============================================================================

prover:is_constraint(constraint(_)).


prover:unify_constraints(constraint(Key:{Value}),Constraints,NewConstraints) :-
  get_assoc(Key,Constraints,CurrentValue,NewConstraints,NewValue),!,
  prover:unify_constraint(Value,CurrentValue,NewValue).

prover:unify_constraints(constraint(Key:{Value}),Constraints,NewConstraints) :-
  prover:unify_constraint(Value,{},NewValue),
  put_assoc(Key,Constraints,NewValue,NewConstraints).

prover:unify_constraint([],{},Assoc) :-
  empty_assoc(Assoc),!.

prover:unify_constraint(Atom,{},Atom) :-
  is_of_type(atom,Atom),!.

prover:unify_constraint(List,{},Assoc) :-
  is_list(List),!, prover:list_to_assoc(List,Assoc).

prover:unify_constraint([],Assoc,Assoc) :-
  is_assoc(Assoc),!.

prover:unify_constraint(Atom,Atom,Atom) :-
  is_of_type(atom,Atom),!.

prover:unify_constraint(List,E,Assoc) :-
  is_list(List), empty_assoc(E),!,
  prover:list_to_assoc(List,Assoc).

prover:unify_constraint(List,M,Assoc) :-
  is_of_type(list,List), is_assoc(M),!,
  prover:prove_recursive(List,t,_,M,Assoc,t,_,t,_).


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

canon_rule(assumed(rule(R://L,B)),       assumed(rule(R://L)), dep(_,B)?{})   :- !.
canon_rule(assumed(rule(R://L?{Ctx},B)), assumed(rule(R://L)), dep(_,B)?Ctx)  :- !.
canon_rule(rule(R://L,B),                rule(R://L),          dep(_,B)?{})   :- !.
canon_rule(rule(R://L?{Ctx},B),          rule(R://L),          dep(_,B)?Ctx)  :- !.
canon_rule(assumed(rule(L,B)),           assumed(rule(L)),     dep(_,B)?{})   :- !.
canon_rule(assumed(rule(L?{Ctx},B)),     assumed(rule(L)),     dep(_,B)?Ctx)  :- !.
canon_rule(rule(L,B),                    rule(L),              dep(_,B)?{})   :- !.
canon_rule(rule(L?{Ctx},B),              rule(L),              dep(_,B)?Ctx)  :- !.


% =============================================================================
% Compatibility Layer for list-based I/O
% =============================================================================

prover:prove_lists(Target,[],ProofList,[],ModelList,[],ConstraintList,[],TriggersList) :-
  empty_assoc(InProof), empty_assoc(InModel), empty_assoc(InCons), empty_assoc(InTriggers),
  prover:prove(Target, InProof, OutProof, InModel, OutModel, InCons, OutCons, InTriggers, OutTriggers),
  proof_to_list(OutProof,ProofList),
  model_to_list(OutModel,ModelList),
  constraints_to_list(OutCons,ConstraintList),
  assoc_to_list(OutTriggers, TriggersList).


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
              ( with_q(prover:prove(Repository://Entry:Action?{[]},t,_,t,_,t,_,t,_)) )).

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
              ( with_q(prover:prove(Repository://Entry:Action?{[]},t,_,t,_,t,_,t,_)) )).
