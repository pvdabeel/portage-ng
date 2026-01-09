/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026w, Pieter Van den Abeele

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

:- module(prover, []).

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
  prover:debug_hook(Target, InProof, InModel, InCons),
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

prover:prove_recursive([],Proof,Proof,Model,Model,Constraints,Constraints,Triggers,Triggers) :-
  !.

prover:prove_recursive([Literal|Rest],Proof,NewProof,Model,NewModel,Cons,NewCons,Trig,NewTrig) :-
  !,
  prover:debug_hook([Literal|Rest], Proof, Model, Cons),
  prover:prove_recursive(Literal, Proof,MidProof,    Model,MidModel,    Cons,MidCons,    Trig,MidTrig),
  prover:prove_recursive(Rest,    MidProof,NewProof, MidModel,NewModel, MidCons,NewCons, MidTrig,NewTrig).


% -----------------------------------------------------------------------------
% CASE 2: A single literal to prove (Recursive Step)
% -----------------------------------------------------------------------------

prover:prove_recursive(Full, Proof, NewProof, Model, NewModel, Constraints, NewConstraints, Triggers, NewTriggers) :-

  %prover:debug_hook(Full, Proof, Model, Constraints),

  canon_literal(Full, Lit, Ctx),

  (   % Case: a constraint

      prover:is_constraint(Lit) ->
      !,
      %message:color(orange),
      %writeln('PROVER: is constraint'),
      %message:color(normal),

      Proof       = NewProof,
      Model       = NewModel,
      Triggers    = NewTriggers,
      prover:unify_constraints(Lit, Constraints, NewConstraints)


  ;   % Case: Lit already proven with given context

      prover:proven(Lit, Model, Ctx) ->
      !,
      %message:color(orange),
      %writeln('PROVER: lit is proven with same Ctx'),
      %message:color(normal),

      Proof       = NewProof,
      Model       = NewModel,
      Triggers    = NewTriggers,
      Constraints = NewConstraints


  ;   % Case: Lit already proven, but context has changed

      prover:proven(Lit, Model, OldCtx) ->
      !,
      %message:color(orange),
      %writeln('PROVER: lit is proven with different Ctx'),
      %writeln('PROVER: -- Get Old body and Old Dep Count'),

      % -- Get old body and old dep count
      get_assoc(rule(Lit),Proof,dep(_OldCount,OldBody)?OldCtx),
      %write('  - Lit      : '),writeln(Lit),
      %write('  - Ctx      : '),writeln(Ctx),
      %write('  - OldCtx   : '),writeln(OldCtx),
      %write('  - OldCount : '),writeln(OldCount),
      %write('  - OldBody  : '),writeln(OldBody),

      %writeln('PROVER: -- Union'),

      % -- Merge old & new context
      union(OldCtx,Ctx,NewCtx),
      %write('  - NewCtx   : '),writeln(NewCtx),

      %writeln('PROVER: -- Create updated full literal'),
      % -- Put together updated full literal
      canon_literal(NewFull,Lit,NewCtx),
      %write('  - NewFull  : '),writeln(NewFull),

      %writeln('PROVER: -- Ready to apply rule for full literal'),
      % -- Apply rule
      rule(NewFull,NewBody),

      %message:hl('PROVER - returning from subcall'),
      %message:color(orange),


      % -- Only body difference should be proved further
      subtract(NewBody,OldBody,DiffBody),

      %write('PROVER: -- NewBody: '),writeln(NewBody),
      %write('PROVER: -- OldBody: '),writeln(OldBody),
      %write('PROVER: -- DifBody: '),writeln(DiffBody),
      %message:color(normal),

      % -- Prepare to refine proof
      length(NewBody,NewCount),

      % -- Amend existing proof, make it seem we are prescient
      put_assoc(rule(Lit), Proof, dep(NewCount, NewBody)?NewCtx,Proof1),

      %writeln('PROVER: -- Ammended rule in proof '),

      (   current_predicate(preference:flag/1), preference:flag(deep) ->
          Triggers1 = Triggers
      ;
          prover:add_triggers(NewFull, NewBody, Triggers, Triggers1)
      ),

      % -- Prove body difference
      prover:prove_recursive(DiffBody, Proof1, NewProof, Model, BodyModel, Constraints, BodyConstraints, Triggers1, NewTriggers),

      % -- Update model & Constraints
      put_assoc(Lit, BodyModel, NewCtx, NewModel),
      NewConstraints = BodyConstraints


  ;   % Case: Lit is assumed proven

      prover:assumed_proven(Lit, Model) ->

      %message:color(orange),
      %writeln('PROVER: lit is assumed proven'),
      %message:color(normal),

      Proof       = NewProof,
      Model       = NewModel,
      Triggers    = NewTriggers,
      Constraints = NewConstraints


      % Case: Conflicts:

  ;   prover:conflicts(Lit, Model) ->

      %message:color(orange),
      %writeln('PROVER: lit is conflicting with Model'),
      %message:color(normal),

      fail

  ;   prover:conflictrule(rule(Lit,[]), Proof) ->

      %message:color(orange),
      %writeln('PROVER: lit rule is conflicting with Proof'),
      %message:color(normal),

      fail

  ;   % Case: circular proof

      (   prover:proving(rule(Lit,_), Proof),
          \+ prover:assumed_proving(Lit, Proof) ->

	        %message:color(orange),
          %writeln('PROVER: circular proof, taking assumption'),
          %message:color(normal),

          % Cycle-break mechanism:
          % - In the Proof: record a special key `assumed(rule(Lit))`
          % - In the Model: record `assumed(Lit)`
          %
          % This is distinct from domain-level assumptions introduced by rules
          % via the literal `assumed(X)` (which are proven by `rule(assumed(_), [])`
          % and stored under `rule(assumed(X))` in the proof).
          % Store the *current* body of the in-progress rule so downstream
          % planning/SCC logic can still see the cycle edges. Mark the depcount
          % as -1 to indicate "deferred / cyclic".
          ( get_assoc(rule(Lit), Proof, dep(_OldCount, OldBody)?_OldCtx)
            -> BodyForPlanning = OldBody
            ;  BodyForPlanning = []
          ),
          put_assoc(assumed(rule(Lit)), Proof, dep(-1, BodyForPlanning)?Ctx, NewProof),
          put_assoc(assumed(Lit), Model, Ctx, NewModel),
          NewConstraints = Constraints,
          NewTriggers = Triggers
      ;

      % Case: regular proof

          %message:color(orange),
          %writeln('PROVER: regular proof'),
          %message:color(normal),

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
% Debug Hook
% =============================================================================

%! prover:debug_hook(+Target, +Proof, +Model, +Constraints)
%
% This predicate is expanded by user:goal_expansion

prover:debug_hook(_Target, _Proof, _Model, _Constraints) :- !.

%prover:debug_hook(Target, Proof, Model, Constraints) :-
%  printer:display_state(Target, Proof, Model, Constraints).



%! prover:debug
%
% Debug all predicates in the prover module.

prover:debug :-
  forall(current_predicate(prover:X),trace(prover:X)).


% =============================================================================
% Triggers Helpers
% =============================================================================

%! build_triggers_from_proof(+ProofAVL, -TriggersAVL)
%
% Build the Triggers tree from the Proof AVL tree.

prover:build_triggers_from_proof(ProofAVL, TriggersAVL) :-
    empty_assoc(EmptyTriggers),
    assoc_to_list(ProofAVL, RulesAsList),
    foldl(prover:add_rule_triggers, RulesAsList, EmptyTriggers, TriggersAVL).


%! prover:add_rule_triggers(+HeadKey-Value, +InTriggers, -OutTriggers)
%
% Add the triggers for a rule to the Triggers tree.

prover:add_rule_triggers(HeadKey-Value, InTriggers, OutTriggers) :-
    ( prover:canon_rule(rule(Head, Body), HeadKey, Value) ; prover:canon_rule(assumed(rule(Head, Body)), HeadKey, Value) ),
    !,
    ( Value = dep(_, _)?Ctx -> prover:canon_literal(FullHead, Head, Ctx) ; FullHead = Head ),
    prover:add_triggers(FullHead, Body, InTriggers, OutTriggers).

prover:add_rule_triggers(_, InTriggers, InTriggers).


%! prover:add_triggers(+Head, +Body, +InTriggers, -OutTriggers)
%
% Add the triggers for a rule to the Triggers tree.

prover:add_triggers(_, [], Triggers, Triggers) :- !.

prover:add_triggers(Head, Body, InTriggers, OutTriggers) :-
    foldl(prover:add_trigger(Head), Body, InTriggers, OutTriggers).

prover:add_trigger(Head, Dep, InTriggers, OutTriggers) :-
    (   prover:is_constraint(Dep)
    ->  OutTriggers = InTriggers
    ;
        prover:canon_literal(Dep, DepLit, _),
        (get_assoc(DepLit, InTriggers, Dependents) -> true ; Dependents = []),
        (memberchk(Head, Dependents) -> NewDependents = Dependents ; NewDependents = [Head | Dependents]),
        put_assoc(DepLit, InTriggers, NewDependents, OutTriggers)
    ).


% =============================================================================
% Proof helper predicates & Canonicalisation
% =============================================================================

prover:proving(rule(Lit, Body), Proof) :- get_assoc(rule(Lit),Proof,dep(_, Body)?_).
% "Assumed proving" is our prover-level cycle-break marker. Historically this
% used dep(0,[]); we now use dep(-1,Body) but keep the predicate robust.
prover:assumed_proving(Lit, Proof) :- get_assoc(assumed(rule(Lit)),Proof,dep(_Count, _Body)?_).
prover:proven(Lit, Model, Ctx) :- get_assoc(Lit,Model,Ctx).
prover:assumed_proven(Lit, Model) :- get_assoc(assumed(Lit), Model, _).

prover:conflicts(Lit, Model) :-
  ( Lit = naf(Inner) -> (prover:proven(Inner, Model, _) ; prover:assumed_proven(Inner, Model))
  ; prover:proven(naf(Lit), Model, _)
  ), !.

prover:conflictrule(rule(Lit,_), Proof) :-
  ( Lit = naf(Inner) -> (prover:proving(rule(Inner,_), Proof) ; prover:assumed_proving(Inner, Proof))
  ; prover:proving(rule(naf(Lit),_), Proof)
  ), !.


% =============================================================================
% CONSTRAINT
% =============================================================================

%! prover:is_constraint(+Literal)
%
% Check if a literal is a constraint.

prover:is_constraint(constraint(_)).


%! prover:unify_constraints(+Constraint, +Constraints, -NewConstraints)
%
% Unify a constraint with the current constraints.

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


%! prover:canon_literal(?Full, ?Core, ?Ctx)
%
%   Full  – full format
%   Core  – part *before* the context annotation.
%   Ctx   – the context ({} for the “no‑context” case).
%
% Convert between full format and key-value pair used
% for the AVL model tree

prover:canon_literal(R://L:A,       R://L:A,  {})  :- !.
prover:canon_literal(R://L:A?{Ctx}, R://L:A,  Ctx) :- !.
prover:canon_literal(R://L,         R://L,    {})  :- !.
prover:canon_literal(R://L?{Ctx},   R://L,    Ctx) :- !.
prover:canon_literal(L:A,           L:A,      {})  :- !.
prover:canon_literal(L:A?{Ctx},     L:A,      Ctx) :- !.
prover:canon_literal(L,             L,        {})  :- !.
prover:canon_literal(L?{Ctx},       L,        Ctx) :- !.


%! prover:canon_rule(?Full, ?Key, ?Value)
%
% Convert between full format and key-value pair used
% for the AVL proof tree

prover:canon_rule(assumed(rule(R://L,B)),       assumed(rule(R://L)), dep(_,B)?{})   :- !.
prover:canon_rule(assumed(rule(R://L?{Ctx},B)), assumed(rule(R://L)), dep(_,B)?Ctx)  :- !.
prover:canon_rule(rule(R://L,B),                rule(R://L),          dep(_,B)?{})   :- !.
prover:canon_rule(rule(R://L?{Ctx},B),          rule(R://L),          dep(_,B)?Ctx)  :- !.
prover:canon_rule(assumed(rule(L,B)),           assumed(rule(L)),     dep(_,B)?{})   :- !.
prover:canon_rule(assumed(rule(L?{Ctx},B)),     assumed(rule(L)),     dep(_,B)?Ctx)  :- !.
prover:canon_rule(rule(L,B),                    rule(L),              dep(_,B)?{})   :- !.
prover:canon_rule(rule(L?{Ctx},B),              rule(L),              dep(_,B)?Ctx)  :- !.


% =============================================================================
%  Helper: AVL assoc convertors
% =============================================================================

%! prover:proof_to_list(+Assoc, -List)
%
% Convert an AVL proof tree to a list.

prover:proof_to_list(Assoc, List) :-
  findall(Full,
          (gen_assoc(Key,Assoc,Value),
           prover:canon_rule(Full,Key,Value)),
          List).


%! prover:model_to_list(+Assoc, -List)
%
% Convert an AVL model tree to a list.

prover:model_to_list(Assoc, List) :-
  findall(Full,
          (gen_assoc(Key,Assoc,Value),
           prover:canon_literal(Full,Key,Value)),
          List).


%! prover:constraints_to_list(+Assoc, -List)
%
% Convert an AVL constraints tree to a list.

prover:constraints_to_list(Assoc, List) :-
  findall(Full,
          (gen_assoc(Key,Assoc,Value),
           canon_literal(Full,Key,Value)),
          List).


%! prover:list_to_proof(+List, -Assoc)
%
% Convert a list to an AVL proof tree.

prover:list_to_proof(List, Assoc) :-
  empty_assoc(Empty),
  foldl(prover:add_to_proof, List, Empty, Assoc).

prover:add_to_proof(Full, InAssoc, OutAssoc) :-
  prover:canon_rule(Full, Key, Value),
  put_assoc(Key, InAssoc, Value, OutAssoc).


%! prover:list_to_model(+List, -Assoc)
%
% Convert a list to an AVL model tree.

prover:list_to_model(List, Assoc) :-
  empty_assoc(Empty),
  foldl(prover:add_to_model, List, Empty, Assoc).

prover:add_to_model(Full, InAssoc, OutAssoc) :-
  prover:canon_literal(Full, Key, Value),
  put_assoc(Key, InAssoc, Value, OutAssoc).


%! prover:list_to_constraints(+List, -Assoc)
%
% Convert a list to an AVL constraints tree.

prover:list_to_constraints(List, Assoc) :-
  empty_assoc(Empty),
  foldl(prover:add_to_constraints, List, Empty, Assoc).

prover:add_to_constraints(Full, InAssoc, OutAssoc) :-
  prover:canon_literal(Full, Key, Value),
  put_assoc(Key, InAssoc, Value, OutAssoc).


%! prover:list_to_assoc(+List, -Assoc)
%
% Convert a list to an AVL tree.

prover:list_to_assoc(List, Assoc) :-
  empty_assoc(Empty),
  foldl(prover:add_to_assoc, List, Empty, Assoc).

prover:add_to_assoc(Key,InAssoc,OutAssoc) :-
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

% -----------------------------------------------------------------------------
%  Testing + statistics
% -----------------------------------------------------------------------------

%! prover:test_stats(+Repository)
prover:test_stats(Repository) :-
  config:test_style(Style),
  prover:test_stats(Repository, Style).

%! prover:test_stats(+Repository,+TopN)
%
% Like prover:test_stats/1, but allows choosing the Top-N limit in the output.
prover:test_stats(Repository, TopN) :-
  integer(TopN),
  !,
  config:test_style(Style),
  prover:test_stats(Repository, Style, TopN).

%! prover:test_stats(+Repository,+Style)
prover:test_stats(Repository, Style) :-
  ( config:test_stats_top_n(TopN) -> true ; TopN = 25 ),
  prover:test_stats(Repository, Style, TopN).

%! prover:test_stats(+Repository,+Style,+TopN)
prover:test_stats(Repository, Style, TopN) :-
  config:proving_target(Action),
  aggregate_all(count, (Repository:entry(_E)), ExpectedTotal),
  printer:test_stats_reset('Proving', ExpectedTotal),
  aggregate_all(count, (Repository:package(_C,_N)), ExpectedPkgs),
  printer:test_stats_set_expected_unique_packages(ExpectedPkgs),
  tester:test(Style,
              'Proving',
              Repository://Entry,
              Repository:entry(Entry),
              ( with_q(prover:prove(Repository://Entry:Action?{[]},t,ProofAVL,t,ModelAVL,t,_Constraint,t,Triggers)),
                printer:test_stats_record_entry(Repository://Entry, ModelAVL, ProofAVL, Triggers, true)
              )),
  printer:test_stats_print(TopN).
