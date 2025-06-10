/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2025, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> PROVER
    The prover computes a proof and a model for a given input.

    ASSOC version with AVL trees.
*/

:- module(prover, []).
:- dynamic prover:flag/1.

% =============================================================================
%  PROVER declarations
% =============================================================================

prover:prove_assoc(Target,[],Proof,[],Model,[],Constraints) :-
  empty_assoc(InitialProof),
  empty_assoc(InitialModel),
  prover:prove(Target,InitialProof,ProofAssoc,InitialModel,ModelAssoc,[],Constraints),
  proof_to_list(ProofAssoc,Proof),
  model_to_list(ModelAssoc,Model).

% -----------------------------------------------------------------------------
% CASE 1: A list of literals to prove
% -----------------------------------------------------------------------------

prover:prove([],Proof,Proof,Model,Model,Constraints,Constraints) :- !.

prover:prove([Literal|Rest],Proof0,Proof,Model0,Model,Cons0,Cons) :-
    !,
    prover:prove(Literal,Proof0,MidProof,Model0,MidModel,Cons0,MidCons),
    prover:prove(Rest,   MidProof,Proof,   MidModel,Model,   MidCons,Cons).


% -----------------------------------------------------------------------------
% CASE 2: A single literal (plain or context‑annotated)
% -----------------------------------------------------------------------------

prover:prove(Full, Proof, NewProof,
                  Model, NewModel,
                  Constraints, NewConstraints) :-
    canon_literal(Full, Lit, Ctx),
    (   %-------------------------------------------------------------
        % Constraint goals unify directly with the global constraint set
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
%  Helper predicates – now single‑clause versions
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
%  Miscellaneous utilities
% =============================================================================

% A constraint literal recogniser
prover:is_constraint(constraint(_)).

% Constraint unification delegates to feature_unification/3.
prover:unify_constraints(constraint(Constraint),Constraints,NewConstraints) :-
    feature_unification:unify([Constraint],Constraints,NewConstraints).

% Facts are rules with an empty body.
prover:fact(rule(_,[])).

% Quick test to recognise context‑annotated literals.
% prover:test_compound(_?_) :- !.

% Build a model by proving a list of literals from scratch.
prover:model(Literals,Model) :-
    prover:prove_assoc(Literals,[],_,[],Model,[],_).
    %forall(member(I,Proof),writeln(I)).

% =============================================================================
%  Helper: canonicalise literals
% =============================================================================

%% canon_literal(+Full, -Core, -Ctx)
%%   Full  – full format
%%   Core  – part *before* the context annotation.
%%   Ctx   – the context ({} for the “no‑context” case).

canon_literal(R://L:A?{Ctx}, R://L:A,  Ctx) :- !.
canon_literal(R://L:A,       R://L:A,  {})  :- !.
canon_literal(R://L?{Ctx},   R://L,    Ctx) :- !.
canon_literal(R://L,         R://L,    {})  :- !.
canon_literal(L:A?{Ctx},     L:A,      Ctx) :- !.
canon_literal(L:A,           L:A,      {})  :- !.
canon_literal(L?{Ctx},       L,        Ctx) :- !.
canon_literal(L,             L,        {})  :- !.

%% list_to_assoc_set(+List, -Assoc)
% Convert a list to an assoc with elements as keys and true as values.
list_to_assoc_set(List, Assoc) :-
    empty_assoc(Empty),
    foldl(put_assoc_key, List, Empty, Assoc).

put_assoc_key(Key, Assoc0, Assoc) :-
    put_assoc(Key, Assoc0, true, Assoc).

%% assoc_to_list_set(+Assoc, -List)
% Convert an assoc to a list of keys.
proof_to_list(Assoc, List) :-
  assoc_to_list(Assoc, Pairs),
  maplist(fst, Pairs, List).

% To enable fast lookup, we store things differently in an assoc.
% We need to be able to recompose to original format

fst(assumed(rule(R://L:A))-(B?Ctx), assumed(rule(R://L:A?{Ctx},B))) :- !.
fst(rule(R://L:A)-(B?Ctx), rule(R://L:A?{Ctx},B)) :- !.
fst(rule(L:A)-(B?Ctx), rule(L:A?{Ctx},B)) :- !.
fst(rule(L)-(B?_), rule(L,B)) :- !.
fst(A-B,unknown([A,B])).

model_to_list(Assoc, List) :-
  assoc_to_list(Assoc, Pairs),
  maplist(snd, Pairs, List).

snd(assumed(R://L:A)-Ctx,assumed(R://L:A?{Ctx})) :- !.
snd((R://L:A)-[],R://L:A?{[]}) :- !.
snd((L:A)-[],L:A?{[]}) :- !.
snd(R://L:A-Ctx,R://L:A?{Ctx}) :- !.
snd(L:A-Ctx,L:A?{Ctx}) :- !.
snd(A-_,A).



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
                (Repository:entry(Entry)),
                ( empty_assoc(EmptyProof),
                  empty_assoc(EmptyModel),
                  with_q(prover:prove(Repository://Entry:Action?{[]},
                                       EmptyProof,_,EmptyModel,_,[],_)))).

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
                (Repository:package(C,N),once(Repository:ebuild(Entry,C,N,_))),
                ( empty_assoc(EmptyProof),
                  empty_assoc(EmptyModel),
                  with_q(prover:prove(Repository://Entry:Action?{[]},
                                       EmptyProof,_,EmptyModel,_,[],_)))).

