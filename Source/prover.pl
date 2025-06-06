/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2025, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> PROVER
    The prover computes a proof and a model for a given input.

    This version removes the code duplication that was necessary to handle two
    syntactic variants of literals (plain vs. context‑annotated).  A small
    helper, canon_literal/4, turns every literal into a *canonical* form; all
    other predicates are now written once and work for both variants.
*/

:- module(prover, []).
:- dynamic prover:flag/1.


% =============================================================================
%  Helper: canonicalise literals
% =============================================================================

%% canon_literal(+Raw, -Full, -Core, -Ctx)
%%   Raw   – literal as it appears in the caller.
%%   Full  – identical to Raw; kept because we still need the *full* term when
%%            checking membership in the model or proof.
%%   Core  – part *before* the context annotation.
%%   Ctx   – the context ({} for the “no‑context” case).

canon_literal(L?{Ctx}, L?{Ctx}, L,  Ctx) :- !.
canon_literal(L,       L,       L,  {}).


% =============================================================================
%  PROVER declarations
% =============================================================================

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

prover:prove(Raw, Proof, NewProof,
                    Model, NewModel,
                    Constraints, NewConstraints) :-
    canon_literal(Raw, Lit, _Core, _Ctx),
    (   %-------------------------------------------------------------
        % Constraint goals unify directly with the global constraint set
        %-------------------------------------------------------------
        prover:is_constraint(Lit) ->
        !,
        prover:unify_constraints(Lit, Constraints, NewConstraints),
        Proof  = NewProof,
        Model  = NewModel

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
        ->  !,   % (A) Cycle → assume once and for all
            NewProof       = [ assumed(rule(Lit,[])) | Proof ],
            NewModel       = [ assumed(Lit)           | Model ],
            NewConstraints = Constraints
        ;   % (B) Select rule/2 from program
            rule(Lit, Body),
            (   Body = []
            ->  !,  % fact – commit to first fact found
                NewProof       = [ rule(Lit,[]) | Proof ],
                NewModel       = [ Lit         | Model ],
                NewConstraints = Constraints
            ;   % non‑empty body – prove sequentially
                prover:prove(Body,
                             [ rule(Lit,Body) | Proof ],
                             NewProof,
                             Model,
                             BodyModel,
                             Constraints,
                             BodyConstraints),
                NewModel       = [ Lit | BodyModel ],
                NewConstraints = BodyConstraints
            )
        )
    ).


% =============================================================================
%  Helper predicates – now single‑clause versions
% =============================================================================

% A literal is proven if it (exact) appears in the model.
prover:proven(Raw, Model) :-
    canon_literal(Raw, Lit, _Core, _),
    memberchk(Lit, Model).

% Ditto for assumed literals.
prover:assumed_proven(Raw, Model) :-
    canon_literal(Raw, Lit, _Core, _),
    memberchk(assumed(Lit), Model).

% A rule is "being proven" if it appears in the current proof.
prover:proving(rule(Raw,Body), Proof) :-
    canon_literal(Raw, Lit, _Core, _),
    memberchk(rule(Lit,Body), Proof).

% Likewise for assumed rules.
prover:assumed_proving(Raw, Proof) :-
    canon_literal(Raw, Lit, _Core, _),
    memberchk(assumed(rule(Lit,[])), Proof).

% Negation‑as‑failure conflicts.
prover:conflicts(Raw, Model) :-
    canon_literal(Raw, Lit, _Core, _),
    (   Lit = naf(Inner) ->
        (   prover:proven(Inner, Model)
        ;   prover:assumed_proven(Inner, Model)
        )
    ;   prover:proven(naf(Lit), Model)
    ), !.

% Conflict *during* proving (rule vs. naf(rule))
prover:conflictrule(rule(Raw,_), Proof) :-
    canon_literal(Raw, Lit, _Core, _),
    (   Lit = naf(Inner) ->
        (   prover:proving(rule(Inner,_), Proof)
        ;   prover:assumed_proving(Inner, Proof)
        )
    ;   prover:proving(rule(naf(Lit),_), Proof)
    ), !.


% =============================================================================
%  Miscellaneous utilities (unchanged)
% =============================================================================

% A constraint literal recogniser
a:- op(200, xfx, ?).      % ensure the ?{}/2 syntax exists – adjust as needed
prover:is_constraint(constraint(_)).

% Constraint unification delegates to feature_unification/3.
prover:unify_constraints(constraint(Constraint),Constraints,NewConstraints) :-
    feature_unification:unify([Constraint],Constraints,NewConstraints).

% Facts are rules with an empty body.
prover:fact(rule(_,[])).

% Quick test to recognise context‑annotated literals.
prover:test_compound(_?_) :- !.

% Build a model by proving a list of literals from scratch.
prover:model(Literals,Model) :-
    prover:prove(Literals,[],_,[],Model,[],_).


% =============================================================================
%  Automated testing helpers (forwarded untouched)
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
                ( with_q(prover:prove(Repository://Entry:Action?{[]},
                                       [],_,[],_,[],_)))).

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
                ( with_q(prover:prove(Repository://Entry:Action?{[]},
                                       [],_,[],_,[],_)))).

