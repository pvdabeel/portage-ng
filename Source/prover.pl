/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> PROVER
Inductive proof search engine for portage-ng.

Given a list of target literals the prover constructs four artefacts
(all implemented as AVL trees / `library(assoc)`):

- Proof       -- maps `rule(Lit)` / `assumed(rule(Lit))` to
                 `dep(DepCount, Body)?Ctx`, recording which rule was
                 applied for each literal and its dependency body.
- Model       -- maps `Lit` to `Ctx`, recording every proven literal
                 and the context under which it was proven.
- Constraints -- accumulated constraint terms (`constraint(Key:{Val})`),
                 threaded through proof steps and unified incrementally.
- Triggers    -- reverse-dependency index: for each proven body literal,
                 lists the head literals that depend on it.

Key design points:

- Reprove (iterative constraint refinement): after a complete proof
  attempt, accumulated constraints may reveal conflicts that were
  invisible during depth-first search (e.g. two dependency edges
  imposing incompatible version bounds on the same package).  When
  the domain detects such a conflict, it throws a
  `prover_reprove(Info)` exception.  The prover catches it,
  delegates to the domain hook `rules:handle_reprove(Info, Added)`
  which records *no-goods* (rejected candidates) to avoid repeating
  the same choice, and then restarts the proof from scratch.  This
  bounded learn-and-restart loop runs up to `reprove_max_retries`
  times.  If retries are exhausted, a final attempt runs with
  reprove disabled so the proof can complete (possibly with
  assumptions).

- Learned constraints: a key-value store (`prover:learn/3`,
  `prover:learned/2`) persists constraint information *across*
  reprove attempts within the same top-level prove call.  The domain
  uses this to carry narrowed version domains, exclusion sets, or
  other refinements from one attempt to the next, guiding candidate
  selection towards a conflict-free proof.  The store is reset at
  the boundary of each top-level `prover:prove/9` invocation.

- Cycle detection and cycle-break assumptions: during depth-first
  proof search, a per-proof *cycle stack* tracks literals currently
  being proved.  When a literal is encountered that is already on
  the stack, the prover records a cycle-break assumption instead of
  diverging.  In Proof, cycle-breaks appear under the key
  `assumed(rule(Lit))` (as opposed to `rule(Lit)` for normally
  proven literals).  In Model, they appear as `assumed(Lit)`.
  This is distinct from *domain-level* assumptions introduced by the
  rule layer via `rule(assumed(X), [])`.

- Triggers form a reverse-dependency index: for each body literal B
  that appears in a proven rule `rule(H, [..., B, ...])`, Triggers
  maps B to the list of head literals H that depend on it.  This
  allows downstream consumers (planner, scheduler) to answer "which
  heads are affected if B changes?" in O(1).  Triggers are maintained
  incrementally during the proof: each proven rule adds its body
  literals to Triggers as it is recorded.

- A lightweight =prove_model= variant skips Proof and Triggers
  bookkeeping for internal query-side model construction.

- Proof obligations (`rules:proof_obligation/4`): after a literal is
  proven, the prover queries the domain for additional proof
  obligations -- extra literals to be appended to the remaining proof
  queue.  This lets the domain inject derived proof obligations
  (e.g. post-dependencies discovered only after a literal is
  resolved) without the prover itself understanding or encoding
  any domain-specific semantics.


*/

:- module(prover, []).

:- thread_local prover:learned_constraint_/2.

user:goal_expansion(debug_hook(_, _, _, _), true) :-
  \+ current_prolog_flag(instrumentation, true).

user:goal_expansion(maybe_debug_hook(_, _, _, _), true) :-
  \+ current_prolog_flag(instrumentation, true).


% =============================================================================
%  PROVER declarations
% =============================================================================

% ----------------------------------------------------------------------------- 
% Top-Level Entry Point
% -----------------------------------------------------------------------------


%! prover:prove(+Target, +InProof, -OutProof, +InModel, -OutModel, +InCons, -OutCons, +InTriggers, -OutTriggers)
%
% Main entry point for the prover.
% Orchestrates the proving process and the configurable trigger-building strategy.
%
% In addition, we support bounded "reprove with scoped rejects" retries for
% domain conflicts emitted via `prover_reprove(Info)` exceptions.

prover:prove(Target, InProof, OutProof, InModel, OutModel, InCons, OutCons, InTriggers, OutTriggers) :-
  prover:reprove_max_retries(MaxRetries),
  prover:with_reprove_state(
    prover:prove_with_retries(
      Target, InProof, OutProof, InModel, OutModel, InCons, OutCons, InTriggers, OutTriggers, 0, MaxRetries
    )
  ).


%! prover:prove_with_retries(+Target, +InProof, -OutProof, +InModel, -OutModel, +InCons, -OutCons, +InTriggers, -OutTriggers, +Attempt, +MaxRetries) is det
%
% Inner retry loop for domain conflict resolution.  Catches
% `prover_reprove(Info)` exceptions and delegates to the domain
% hook `rules:handle_reprove/2` to process the conflict.  Retries
% with expanded reject sets up to MaxRetries.

prover:prove_with_retries(Target, InProof, OutProof, InModel, OutModel, InCons, OutCons, InTriggers, OutTriggers, Attempt, MaxRetries) :-
  catch(
    prover:prove_once(Target, InProof, OutProof, InModel, OutModel, InCons, OutCons, InTriggers, OutTriggers),
    prover_reprove(Info),
    prover:handle_reprove(
      Target, InProof, OutProof, InModel, OutModel, InCons, OutCons, InTriggers, OutTriggers,
      Attempt, MaxRetries, Info
    )
  ).


%! prover:handle_reprove(+Target, +InProof, -OutProof, +InModel, -OutModel, +InCons, -OutCons, +InTriggers, -OutTriggers, +Attempt, +MaxRetries, +Info) is det
%
% Handle a reprove exception: delegate to the domain hook
% `rules:handle_reprove(Info, Added)` to process the conflict
% (e.g. add rejects), then retry or fall back to a final prove
% with reprove disabled.

prover:handle_reprove(Target, InProof, OutProof, InModel, OutModel, InCons, OutCons, InTriggers, OutTriggers,
                      Attempt, MaxRetries, Info) :-
  ( Attempt < MaxRetries,
    current_predicate(rules:handle_reprove/2),
    rules:handle_reprove(Info, Added),
    Added == true
  ->
    Attempt1 is Attempt + 1,
    prover:prove_with_retries(
      Target, InProof, OutProof, InModel, OutModel, InCons, OutCons, InTriggers, OutTriggers, Attempt1, MaxRetries
    )
  ; ( current_predicate(rules:reprove_exhausted/0) -> rules:reprove_exhausted ; true ),
    prover:with_reprove_disabled(
      prover:prove_once(Target, InProof, OutProof, InModel, OutModel, InCons, OutCons, InTriggers, OutTriggers)
    )
  ).


%! prover:prove_once(+Target, +InProof, -OutProof, +InModel, -OutModel, +InCons, -OutCons, +InTriggers, -OutTriggers) is det
%
% Single-attempt prove: runs the core recursive engine with cycle-stack
% bookkeeping.  Triggers are maintained incrementally during the proof.

prover:prove_once(Target, InProof, OutProof, InModel, OutModel, InCons, OutCons, InTriggers, OutTriggers) :-
  prover:debug_hook(Target, InProof, InModel, InCons),
  prover:with_cycle_stack(
    prover:prove_recursive(Target, InProof, OutProof, InModel, OutModel, InCons, OutCons, InTriggers, OutTriggers)
  ).


%! prover:reprove_max_retries(-Max) is det
%
% Maximum number of reprove retries (default 3).

prover:reprove_max_retries(Max) :-
  ( current_predicate(config:reprove_max_retries/1),
    config:reprove_max_retries(Max0),
    integer(Max0),
    Max0 >= 0
  ->
    Max = Max0
  ; Max = 3
  ).


%! prover:with_reprove_state(:Goal) is det
%
% Run Goal inside a fresh reprove environment.  Manages the prover-owned
% learned-constraint store and delegates domain-specific state lifecycle
% to `rules:reprove_init_state/0` and `rules:reprove_cleanup_state/0`.

prover:with_reprove_state(Goal) :-
  findall(L-C, prover:learned_constraint_(L, C), SavedLC),
  retractall(prover:learned_constraint_(_, _)),
  ( current_predicate(rules:reprove_init_state/0) -> rules:reprove_init_state ; true ),
  setup_call_cleanup(true,
                     Goal,
                     ( ( current_predicate(rules:reprove_cleanup_state/0) -> rules:reprove_cleanup_state ; true ),
                       retractall(prover:learned_constraint_(_, _)),
                       forall(member(L-C, SavedLC), assertz(prover:learned_constraint_(L, C)))
                     )).


%! prover:with_reprove_disabled(:Goal) is det
%
% Run Goal with reprove disabled (final-attempt clean prove).
% Delegates to `rules:reprove_disable/0` and `rules:reprove_enable/0`.

prover:with_reprove_disabled(Goal) :-
  ( current_predicate(rules:reprove_disable/0) -> rules:reprove_disable ; true ),
  setup_call_cleanup(true,
                     Goal,
                     ( current_predicate(rules:reprove_enable/0) -> rules:reprove_enable ; true )).


% -----------------------------------------------------------------------------
% Core Recursive Prover
% -----------------------------------------------------------------------------

% CASE 1: A list of literals to prove (Recursive Step)

%! prover:prove_recursive(+Target, +InProof, -OutProof, +InModel, -OutModel, +InCons, -OutCons, +InTrig, -OutTrig) is nondet
%
% Core recursive proof engine.  Handles lists of literals (CASE 1),
% single literals with constraint/proven/context-change/cycle-break/
% conflict/regular-proof dispatch (CASE 2).

prover:prove_recursive([],Proof,Proof,Model,Model,Constraints,Constraints,Triggers,Triggers) :-
  !.

prover:prove_recursive([Literal|Rest],Proof,NewProof,Model,NewModel,Cons,NewCons,Trig,NewTrig) :-
  !,
  prover:maybe_debug_hook([Literal|Rest], Proof, Model, Cons),
  prover:prove_recursive(Literal, Proof,MidProof,    Model,MidModel,    Cons,MidCons,    Trig,MidTrig),
  prover:collect_proof_obligations(Literal, MidProof, MidProof1, MidModel, Rest, Rest1),
  prover:prove_recursive(Rest1,    MidProof1,NewProof, MidModel,NewModel, MidCons,NewCons, MidTrig,NewTrig).


% CASE 2: A single literal to prove (Recursive Step)

prover:prove_recursive(Full, Proof, NewProof, Model, NewModel, Constraints, NewConstraints, Triggers, NewTriggers) :-

  prover:maybe_debug_hook(Full, Proof, Model, Constraints),

  canon_literal(Full, Lit, Ctx),

  (   % Case: a constraint

      constraint:is_constraint(Lit) ->
      !,
      %message:color(orange),
      %writeln('PROVER: is constraint'),
      %message:color(normal),

      Proof       = NewProof,
      Model       = NewModel,
      Triggers    = NewTriggers,
      constraint:unify_constraints(Lit, Constraints, Constraints1),
      % Domain hook (keeps prover generic): if the domain provides a constraint
      % guard, it can reject inconsistent states by failing here.
      ( current_predicate(rules:constraint_guard/2) ->
          ( rules:constraint_guard(Lit, Constraints1) ->
              NewConstraints = Constraints1
          ; fail
          )
      ; NewConstraints = Constraints1
      )


  ;   % Case: Lit already proven with given context

      prover:proven(Lit, Model, Ctx) ->
      !,
      Proof       = NewProof,
      Model       = NewModel,
      Triggers    = NewTriggers,
      Constraints = NewConstraints


  ;   % Case: Lit already proven, but context has changed

      prover:proven(Lit, Model, ModelCtx) ->
      !,
      ( get_assoc(rule(Lit),Proof,dep(_OldCount,OldBody)?ModelCtx) ->
          true
      ; get_assoc(rule(Lit),Proof,dep(_OldCount,OldBody)?_OldProofCtx)
      ),

      sampler:ctx_union(ModelCtx, Ctx, NewCtx),
      prover:canon_literal(NewFull, Lit, NewCtx),

      sampler:test_stats_rule_call,
      sampler:maybe_timeout_trace(Lit),
      rule(NewFull,NewBody),

      subtract(NewBody,OldBody,DiffBody),
      length(NewBody,NewCount),
      put_assoc(rule(Lit), Proof, dep(NewCount, NewBody)?NewCtx,Proof1),
      prover:add_triggers(NewFull, NewBody, Triggers, Triggers1),

      setup_call_cleanup(prover:cycle_stack_push(Lit),
                         prover:prove_recursive(DiffBody, Proof1, NewProof, Model, BodyModel, Constraints, BodyConstraints, Triggers1, NewTriggers),
                         prover:cycle_stack_pop(Lit)),

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

      (   prover:currently_proving(Lit),
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
          put_assoc(assumed(rule(Lit)), Proof, dep(-1, BodyForPlanning)?Ctx, Proof1),
          ( prover:cycle_path_for(Lit, CyclePath) ->
              put_assoc(cycle_path(Lit), Proof1, CyclePath, NewProof)
          ; NewProof = Proof1
          ),
          put_assoc(assumed(Lit), Model, Ctx, NewModel),
          NewConstraints = Constraints,
          NewTriggers = Triggers
      ;

      % Case: regular proof

          %message:color(orange),
          %writeln('PROVER: regular proof'),
          %message:color(normal),

          sampler:test_stats_rule_call,
          sampler:maybe_timeout_trace(Lit),
          rule(Full, Body),

          length(Body, DepCount),
          put_assoc(rule(Lit), Proof, dep(DepCount, Body)?Ctx, Proof1),
          prover:add_triggers(Full, Body, Triggers, Triggers1),
          setup_call_cleanup(prover:cycle_stack_push(Lit),
                             prover:prove_recursive(Body, Proof1, NewProof, Model, BodyModel, Constraints, BodyConstraints, Triggers1, NewTriggers),
                             prover:cycle_stack_pop(Lit)),
          put_assoc(Lit, BodyModel, Ctx, NewModel),
          NewConstraints = BodyConstraints
      )
  ).


% -----------------------------------------------------------------------------
%  Lightweight model construction (skip Proof + Triggers bookkeeping)
% -----------------------------------------------------------------------------

% For some internal computations (notably query-side model construction), we only
% need the resulting Model/Constraints, not the Proof tree nor Triggers. Using the
% full prover in those cases creates substantial overhead (assoc updates for Proof,
% trigger maintenance, cycle bookkeeping keyed by Proof, ...).
%
% `prove_model/*` keeps the same semantics for constraints and for "already proven"
% context refinement, but uses a dedicated in-progress set for cycle detection.


%! prover:prove_model(+Target, +InModel, -OutModel, +InCons, -OutCons) is det
%
% Lightweight model construction: proves Target into OutModel/OutCons
% without maintaining Proof or Triggers bookkeeping.

prover:prove_model(Target, InModel, OutModel, InCons, OutCons) :-
  prover:prove_model(Target, InModel, OutModel, InCons, OutCons, t).

prover:prove_model([], Model, Model, Cons, Cons, _InProg) :-
  !.
prover:prove_model([Literal|Rest], Model0, Model, Cons0, Cons, InProg0) :-
  !,
  prover:prove_model(Literal, Model0, Model1, Cons0, Cons1, InProg0),
  prover:prove_model(Rest,    Model1, Model,  Cons1, Cons,  InProg0).

prover:prove_model(Full, Model0, Model, Constraints0, Constraints, InProg0) :-
  canon_literal(Full, Lit, Ctx),

  (   % Case: a constraint
      constraint:is_constraint(Lit) ->
      !,
      Model = Model0,
      constraint:unify_constraints(Lit, Constraints0, Constraints)

  ;   % Case: Lit already proven with given context
      prover:proven(Lit, Model0, Ctx) ->
      !,
      Model = Model0,
      Constraints = Constraints0

  ;   % Case: Lit already proven, but context has changed
      prover:proven(Lit, Model0, OldCtx) ->
      !,
      sampler:ctx_union(OldCtx, Ctx, NewCtx),
      ( NewCtx == OldCtx ->
          Model = Model0,
          Constraints = Constraints0
      ; prover:canon_literal(NewFull, Lit, NewCtx),
        sampler:test_stats_rule_call,
        rule(NewFull, NewBody),
        prover:prove_model(NewBody, Model0, BodyModel, Constraints0, BodyConstraints, InProg0),
        put_assoc(Lit, BodyModel, NewCtx, Model),
        Constraints = BodyConstraints
      )

  ;   % Case: circular model proof (cycle-break)
      get_assoc(Lit, InProg0, true) ->
      !,
      % Keep the same taxonomy as the full prover's cycle-breaks: store assumed(Lit)
      % in the model (note: dependency-model extraction ignores assumed/1 keys).
      put_assoc(assumed(Lit), Model0, Ctx, Model),
      Constraints = Constraints0

  ;   % Case: regular proof (model-only)
      put_assoc(Lit, InProg0, true, InProg1),
      sampler:test_stats_rule_call,
      rule(Full, Body),
      prover:prove_model(Body, Model0, BodyModel, Constraints0, BodyConstraints, InProg1),
      del_assoc(Lit, InProg1, _Old, InProg2),
      ( InProg2 = _ -> true ), % keep var used (avoid singleton warnings)
      put_assoc(Lit, BodyModel, Ctx, Model),
      Constraints = BodyConstraints
  ).


% -----------------------------------------------------------------------------
%  Proof obligations (domain-injected)
% -----------------------------------------------------------------------------

% The prover stays domain-agnostic.  After proving a literal, it consults
% an optional domain predicate to discover additional proof obligations:
%
%   rules:proof_obligation(+Literal, +Model, -Key, -ExtraLits)
%
% - Key is an arbitrary term identifying this obligation.  The prover stores
%   `obligation_done(Key)` in the ProofAVL to ensure each obligation is
%   processed at most once (even if the literal is later refined due to
%   context changes).
% - ExtraLits is a list of additional literals to append to the proof queue.
%
% The domain must keep the predicate monotonic and backtracking-safe (no
% global side effects).  The prover only records the obligation_done marker.


%! prover:collect_proof_obligations(+Literal, +Proof0, -Proof, +Model, +Rest0, -Rest) is det
%
% After proving Literal, consult the domain for additional proof obligations.
% Only fires for merge-action candidates.

prover:collect_proof_obligations(Literal, Proof, Proof, _Model, Rest, Rest) :-
  \+ prover:obligation_candidate(Literal),
  !.
prover:collect_proof_obligations(_Literal, Proof, Proof, _Model, Rest, Rest) :-
  \+ current_predicate(rules:proof_obligation/4),
  !.
prover:collect_proof_obligations(Literal, Proof0, Proof, Model, Rest0, Rest) :-
  % Cheap skip: if the domain can compute the key without doing expensive work,
  % avoid calling the full obligation when that key is already marked done.
  ( current_predicate(rules:proof_obligation_key/4),
    once(rules:proof_obligation_key(Literal, Model, Key0, NeedsFull)),
    ( get_assoc(obligation_done(Key0), Proof0, true) ->
        sampler:obligation_counter_done_hit,
        Proof = Proof0,
        Rest = Rest0
    ; NeedsFull == false ->
        put_assoc(obligation_done(Key0), Proof0, true, Proof),
        Rest = Rest0
    ; fail
    )
  ; current_predicate(rules:proof_obligation_key/3),
    once(rules:proof_obligation_key(Literal, Model, Key1)),
    get_assoc(obligation_done(Key1), Proof0, true) ->
      sampler:obligation_counter_done_hit,
      Proof = Proof0,
      Rest = Rest0
  ;
  % The domain obligation predicate is expected to be deterministic (0 or 1
  % result). Keep this fast: avoid `findall/3` for the common case where
  % there is no result.
  ( once(rules:proof_obligation(Literal, Model, Key, ExtraLits)) ->
      Obligations = [obligation(Key, ExtraLits)]
  ; Obligations = []
  ),
  prover:collect_proof_obligations_list(Obligations, Proof0, Proof, Model, Rest0, Rest),
  true
  ),
  !.
prover:collect_proof_obligations(_Literal, Proof, Proof, _Model, Rest, Rest).


%! prover:obligation_candidate(+Literal) is semidet
%
% Succeeds when Literal is a merge-action literal eligible for
% proof obligations (install/update/downgrade/reinstall).

prover:obligation_candidate(_Repo://_Entry:Action?{_Ctx}) :-
  ( Action == install ; Action == update ; Action == downgrade ; Action == reinstall ),
  !.
prover:obligation_candidate(_Repo://_Entry:Action) :-
  ( Action == install ; Action == update ; Action == downgrade ; Action == reinstall ),
  !.


%! prover:collect_proof_obligations_list(+Obligations, +Proof0, -Proof, +Model, +Rest0, -Rest) is det
%
% Process a list of obligation(Key, ExtraLits) results: mark each key
% done in the proof, filter already-proven/pending literals, and append
% fresh ones to the remaining literal queue.

prover:collect_proof_obligations_list([], Proof, Proof, _Model, Rest, Rest) :- !.
prover:collect_proof_obligations_list([obligation(Key, ExtraLits)|Hs], Proof0, Proof, Model, Rest0, Rest) :-
  ( get_assoc(obligation_done(Key), Proof0, true) ->
      sampler:obligation_counter_done_hit,
      Proof1 = Proof0,
      Rest1 = Rest0
  ; put_assoc(obligation_done(Key), Proof0, true, Proof1),
    sampler:obligation_counter_fired(ExtraLits),
    prover:select_new_literals_to_enqueue(ExtraLits, Model, Proof1, Proof2, FreshLits),
    sampler:obligation_counter_fresh(FreshLits),
    ( FreshLits == [] ->
        Rest1 = Rest0
    ; append(FreshLits, Rest0, Rest1)
    )
  ),
  ( var(Proof2) -> ProofNext = Proof1 ; ProofNext = Proof2 ),
  prover:collect_proof_obligations_list(Hs, ProofNext, Proof, Model, Rest1, Rest).


%! prover:select_new_literals_to_enqueue(+Lits0, +Model, +Proof0, -Proof, -Lits) is det
%
% Deterministically select only those ExtraLits that are not already proven
% (present in Model) and not already pending (tracked via obligation_pending/1
% keys in the Proof AVL).

prover:select_new_literals_to_enqueue(Lits0, Model, Proof0, Proof, Lits) :-
  ( is_list(Lits0) ->
      prover:select_new_literals_to_enqueue_(Lits0, Model, Proof0, Proof, [], Rev),
      reverse(Rev, Lits)
  ; Proof = Proof0,
    Lits = []
  ),
  !.

prover:select_new_literals_to_enqueue_([], _Model, Proof, Proof, Acc, Acc) :- !.
prover:select_new_literals_to_enqueue_([L0|Ls], Model, Proof0, Proof, Acc0, Acc) :-
  prover:canon_literal(L0, Core, _),
  ( get_assoc(Core, Model, _) ->
      Proof1 = Proof0,
      Acc1 = Acc0
  ; get_assoc(obligation_pending(Core), Proof0, true) ->
      Proof1 = Proof0,
      Acc1 = Acc0
  ; put_assoc(obligation_pending(Core), Proof0, true, Proof1),
    Acc1 = [L0|Acc0]
  ),
  prover:select_new_literals_to_enqueue_(Ls, Model, Proof1, Proof, Acc1, Acc).


% -----------------------------------------------------------------------------
%  Learned constraint store
% -----------------------------------------------------------------------------

%  A generic key-value store for constraints learned across proof attempts.
%  Rules can learn constraints (e.g., version domain narrowing) and consult
%  them during candidate selection. The prover manages the store lifecycle.
%  Merge semantics are defined by feature_unification:val_hook.


%! prover:learned(+Literal, -Constraint)
%
%  Look up a learned constraint. Fails if none exists.

prover:learned(Literal, Constraint) :-
  prover:learned_constraint_(Literal, Constraint).


%! prover:learn(+Literal, +Constraint, -Added)
%
%  Store a learned constraint. If one already exists for Literal,
%  merge via feature_unification:val_hook. Added is true if the
%  store changed, false if Constraint was already subsumed.

prover:learn(Literal, Constraint, Added) :-
  ( prover:learned_constraint_(Literal, Old) ->
      ( Old == Constraint ->
          Added = false
      ; feature_unification:val_hook(Old, Constraint, Merged) ->
          ( Merged == Old ->
              Added = false
          ; retract(prover:learned_constraint_(Literal, _)),
            assertz(prover:learned_constraint_(Literal, Merged)),
            Added = true
          )
      ; retract(prover:learned_constraint_(Literal, _)),
        assertz(prover:learned_constraint_(Literal, Constraint)),
        Added = true
      )
  ; assertz(prover:learned_constraint_(Literal, Constraint)),
    Added = true
  ),
  !.


% -----------------------------------------------------------------------------
%  Cycle stack (for cycle-break paths)
% -----------------------------------------------------------------------------
%
% Cycle-break detection should be based on "Lit currently on the proof stack".
% The triggers graph is sometimes insufficient to reconstruct a human-readable
% cycle quickly (especially when triggers are delayed or pruned). We therefore
% maintain a lightweight per-proof stack of literals currently being proven,
% and store a compact cycle witness in the proof under `cycle_path(Lit)`.
%
%! prover:with_cycle_stack(:Goal) is det
%
% Run Goal with a fresh per-proof cycle stack.  Literals are pushed/popped
% as they enter/leave the recursive prover, enabling cycle-path extraction
% when a cycle-break assumption is made.

prover:with_cycle_stack(Goal) :-
  ( nb_current(prover_cycle_stack, Old) -> true ; Old = unset ),
  nb_setval(prover_cycle_stack, []),
  setup_call_cleanup(true,
                     Goal,
                     ( Old == unset -> nb_delete(prover_cycle_stack)
                     ; nb_setval(prover_cycle_stack, Old)
                     )).


%! prover:cycle_stack_push(+Lit) is det
%
% Push Lit onto the thread-local cycle stack.
% Uses b_setval (backtrackable, O(1) reference store) instead of
% nb_setval (non-backtrackable, O(N) deep copy) to avoid GC pressure
% from copying the entire stack on every push.

prover:cycle_stack_push(Lit) :-
  nb_getval(prover_cycle_stack, S0),
  b_setval(prover_cycle_stack, [Lit|S0]).


%! prover:cycle_stack_pop(+Lit) is det
%
% Pop the top element from the thread-local cycle stack.
% Uses b_setval for O(1) store (see cycle_stack_push/1).

prover:cycle_stack_pop(_) :-
  nb_getval(prover_cycle_stack, [_|Rest]),
  b_setval(prover_cycle_stack, Rest).


%! prover:take_until(+List, +Stop, -Prefix) is semidet
%
% Return the prefix of List up to and including Stop.

prover:take_until([Stop|_], Stop, [Stop]) :- !.
prover:take_until([X|Xs], Stop, [X|Out]) :-
  prover:take_until(Xs, Stop, Out).


%! prover:cycle_path_for(+Lit, -CyclePath) is det
%
% Extract a cycle witness from the current cycle stack for Lit.
% Returns the portion of the stack from Lit back to its first
% occurrence, forming a closed cycle path.

prover:cycle_path_for(Lit, CyclePath) :-
  ( nb_current(prover_cycle_stack, Stack),
    prover:take_until(Stack, Lit, PrefixRev) ->
      reverse(PrefixRev, Prefix),
      append(Prefix, [Lit], CyclePath)
  ; CyclePath = [Lit, Lit]
  ).


%! prover:currently_proving(+Lit) is semidet
%
% Succeeds when Lit is currently on the proof cycle stack (i.e. an
% ancestor in the current proof derivation).

prover:currently_proving(Lit) :-
  nb_getval(prover_cycle_stack, Stack),
  memberchk(Lit, Stack),
  !.


% -----------------------------------------------------------------------------
% Debug Hook
% -----------------------------------------------------------------------------


%! prover:debug_hook(+Target, +Proof, +Model, +Constraints)
%
% This predicate is expanded by user:goal_expansion

:- thread_local prover:debug_hook_handler/1.


%! prover:with_debug_hook(+Handler, :Goal)
%
% Install a per-thread debug hook handler during Goal. Handler must be a
% callable closure that can be called as call(Handler, Target, Proof, Model, Constraints).
% Example: prover:with_debug_hook(printer:display_state, prover:prove(...)).
prover:with_debug_hook(Handler, Goal) :-
  setup_call_cleanup(
    asserta(prover:debug_hook_handler(Handler)),
    Goal,
    retractall(prover:debug_hook_handler(Handler))
  ).


%! prover:maybe_debug_hook(+Target, +Proof, +Model, +Constraints) is det
%
% Guarded debug hook for the hot path.  Compiled to `true` when
% instrumentation is off (via goal_expansion in sampler.pl).

prover:maybe_debug_hook(Target, Proof, Model, Constraints) :-
  ( prover:debug_hook_handler(Handler) ->
      catch(call(Handler, Target, Proof, Model, Constraints),
            E,
            print_message(error, E))
  ; true
  ),
  !.


%! prover:debug_hook(+Target, +Proof, +Model, +Constraints) is det
%
% Invoke the installed debug-hook handler (if any).  Best-effort:
% errors in the handler are caught and printed, never propagated.
% Used at the top-level entry point (called once per prove).

prover:debug_hook(Target, Proof, Model, Constraints) :-
  ( prover:debug_hook_handler(Handler) ->
      catch(call(Handler, Target, Proof, Model, Constraints),
            E,
            print_message(error, E))
  ; true
  ),
  !.


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
    ( Value = dep(_, _)?Ctx ->
        % `rule_parts/3` may already return a context-annotated Head (Head?{Ctx}).
        % Avoid wrapping a second time, which creates nested context terms like:
        %   portage://(dev-ml/foo-1.0:run?{Ctx})?{Ctx}
        ( Head = _?{_} -> FullHead = Head
        ; prover:canon_literal(FullHead, Head, Ctx)
        )
    ; FullHead = Head
    ),
    prover:add_triggers(FullHead, Body, InTriggers, OutTriggers).

prover:add_rule_triggers(_, InTriggers, InTriggers).


%! prover:add_triggers(+Head, +Body, +InTriggers, -OutTriggers)
%
% Add the triggers for a rule to the Triggers tree.

prover:add_triggers(_, [], Triggers, Triggers) :- !.

prover:add_triggers(Head, Body, InTriggers, OutTriggers) :-
    foldl(prover:add_trigger(Head), Body, InTriggers, OutTriggers).

prover:add_trigger(Head, Dep, InTriggers, OutTriggers) :-
    (   constraint:is_constraint(Dep)
    ->  OutTriggers = InTriggers
    ;
        prover:canon_literal(Dep, DepLit, _),
        (get_assoc(DepLit, InTriggers, Dependents) -> true ; Dependents = []),
        (memberchk(Head, Dependents) -> NewDependents = Dependents ; NewDependents = [Head | Dependents]),
        put_assoc(DepLit, InTriggers, NewDependents, OutTriggers)
    ).


% -----------------------------------------------------------------------------
% Proof helper predicates & Canonicalisation
% -----------------------------------------------------------------------------


%! prover:proving(+RuleTerm, +Proof) is semidet
%
% Succeeds when `rule(Lit)` is in the Proof AVL (currently being proven).

prover:proving(rule(Lit, Body), Proof) :- get_assoc(rule(Lit),Proof,dep(_, Body)?_).


%! prover:assumed_proving(+Lit, +Proof) is semidet
%
% Succeeds when Lit has a prover-level cycle-break marker in Proof
% (`assumed(rule(Lit))`).

prover:assumed_proving(Lit, Proof) :- get_assoc(assumed(rule(Lit)),Proof,dep(_Count, _Body)?_).


%! prover:proven(+Lit, +Model, +Ctx) is semidet
%
% Succeeds when Lit is in Model under a semantically equivalent context
% (prevents needless re-proving when only provenance differs).

prover:proven(Lit, Model, Ctx) :-
  get_assoc(Lit, Model, StoredCtx),
  ( StoredCtx == Ctx ->
      true
  ; prover:ctx_sem_key(StoredCtx, K1),
    prover:ctx_sem_key(Ctx,       K2),
    K1 == K2
  ).


%! prover:assumed_proven(+Lit, +Model) is semidet
%
% Succeeds when Lit has a cycle-break assumption in the Model.

prover:assumed_proven(Lit, Model) :- get_assoc(assumed(Lit), Model, _).


%! prover:ctx_sem_key(+Ctx, -Key) is det
%
% Extract a semantic key from a context for equivalence comparison.
% Two contexts with the same semantic key are considered equivalent
% by proven/3 (ignoring provenance like `self/1`).

prover:ctx_sem_key({}, key([], none)) :- !.
prover:ctx_sem_key(Ctx, key(RU, BWU)) :-
  is_list(Ctx),
  !,
  ( memberchk(required_use:RU0, Ctx) -> RU = RU0 ; RU = [] ),
  ( memberchk(build_with_use:BWU0, Ctx) -> BWU = BWU0 ; BWU = none ).
prover:ctx_sem_key(_Other, key([], none)) :-
  !.


%! prover:conflicts(+Lit, +Model) is semidet
%
% Succeeds when Lit conflicts with the current Model (a positive
% literal conflicts with a proven `naf/1` and vice versa).

prover:conflicts(Lit, Model) :-
  ( Lit = naf(Inner) -> (prover:proven(Inner, Model, _) ; prover:assumed_proven(Inner, Model))
  ; prover:proven(naf(Lit), Model, _)
  ), !.


%! prover:conflictrule(+RuleTerm, +Proof) is semidet
%
% Succeeds when a rule for Lit conflicts with rules already in the Proof.

prover:conflictrule(rule(Lit,_), Proof) :-
  ( Lit = naf(Inner) -> (prover:proving(rule(Inner,_), Proof) ; prover:assumed_proving(Inner, Proof))
  ; prover:proving(rule(naf(Lit),_), Proof)
  ), !.


% -----------------------------------------------------------------------------
% Helper: compose and decompose literals and rules
% -----------------------------------------------------------------------------

%! prover:canon_literal(?Full, ?Core, ?Ctx)
%
%   Full  – full format
%   Core  – part *before* the context annotation.
%   Ctx   – the context ({} for the “no‑context” case).
%
% Convert between full format and key-value pair used
% for the AVL model tree

prover:canon_literal(R://(L:A),               R://L:A, {})  :- !.
prover:canon_literal(R://(L:A?{Ctx1}),        R://L:A, Ctx1) :- !.
prover:canon_literal(R://(L:A)?{Ctx2},        R://L:A, Ctx2) :- !.
prover:canon_literal(R://(L:A?{Ctx1})?{Ctx2}, R://L:A, Ctx) :-
  !,
  sampler:ctx_union(Ctx1, Ctx2, Ctx).

prover:canon_literal(R://(L),                 R://L,   {})  :- !.
prover:canon_literal(R://(L?{Ctx1}),          R://L,   Ctx1) :- !.
prover:canon_literal(R://(L)?{Ctx2},          R://L,   Ctx2) :- !.
prover:canon_literal(R://(L?{Ctx1})?{Ctx2},   R://L,   Ctx) :-
  !,
  sampler:ctx_union(Ctx1, Ctx2, Ctx).

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


% -----------------------------------------------------------------------------
%  Helper: AVL assoc convertors
% -----------------------------------------------------------------------------


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


%! prover:list_to_proof(+List, -Assoc)
%
% Convert a list to an AVL proof tree.

prover:list_to_proof(List, Assoc) :-
  empty_assoc(Empty),
  foldl(prover:add_to_proof, List, Empty, Assoc).


%! prover:add_to_proof(+Full, +InAssoc, -OutAssoc) is det

prover:add_to_proof(Full, InAssoc, OutAssoc) :-
  prover:canon_rule(Full, Key, Value),
  put_assoc(Key, InAssoc, Value, OutAssoc).


%! prover:list_to_model(+List, -Assoc)
%
% Convert a list to an AVL model tree.

prover:list_to_model(List, Assoc) :-
  empty_assoc(Empty),
  foldl(prover:add_to_model, List, Empty, Assoc).


%! prover:add_to_model(+Full, +InAssoc, -OutAssoc) is det

prover:add_to_model(Full, InAssoc, OutAssoc) :-
  prover:canon_literal(Full, Key, Value),
  put_assoc(Key, InAssoc, Value, OutAssoc).


%! prover:list_to_assoc(+List, -Assoc)
%
% Convert a list to an AVL tree.

prover:list_to_assoc(List, Assoc) :-
  empty_assoc(Empty),
  foldl(prover:add_to_assoc, List, Empty, Assoc).


%! prover:add_to_assoc(+Key, +InAssoc, -OutAssoc) is det

prover:add_to_assoc(Key,InAssoc,OutAssoc) :-
  put_assoc(Key,InAssoc,{},OutAssoc).


% -----------------------------------------------------------------------------
%  Automated testing helpers
% -----------------------------------------------------------------------------

% -----------------------------------------------------------------------------
%  Test action mapping
% -----------------------------------------------------------------------------
%
%! prover:test_action(+Action0, -Action) is det
%
% Map a configured target action to the action used by test harnesses.
% Identity mapping (historically run was mapped to merge).

prover:test_action(Action, Action).


%! prover:test_target_success(+Target)
%
% Test harness fallback chain:
%  1) strict prove/plan
%  2) allow blocker assumptions
%  3) allow conflict assumptions
%
% This keeps whole-repo test runs robust for known blocker/conflict-heavy
% packages while preserving strict behavior as first choice.
prover:test_target_success(Target) :-
  printer:prove_plan([Target], _ProofAVL, _ModelAVL, _Plan, _TriggersAVL),
  !.
prover:test_target_success(Target) :-
  current_predicate(rules:with_assume_blockers/1),
  rules:with_assume_blockers(
    printer:prove_plan([Target], _ProofAVL2, _ModelAVL2, _Plan2, _TriggersAVL2)
  ),
  !.
prover:test_target_success(Target) :-
  current_predicate(rules:with_assume_conflicts/1),
  rules:with_assume_conflicts(
    printer:prove_plan([Target], _ProofAVL3, _ModelAVL3, _Plan3, _TriggersAVL3)
  ).


%! prover:test(+Repository) is det
%
% Run a whole-repo prove test using the default test style.

prover:test(Repository) :-
  config:test_style(Style),
  prover:test(Repository,Style).


%! prover:test(+Repository, +Style) is det
%
% Run a whole-repo prove test with the given Style (sequential/parallel).

prover:test(Repository,Style) :-
  config:proving_target(Action0),
  prover:test_action(Action0, Action),
  ( current_predicate(printer:prove_plan_perf_reset/0) ->
      printer:prove_plan_perf_reset
  ; true
  ),
  ( current_predicate(scheduler:perf_reset/0) ->
      scheduler:perf_reset
  ; true
  ),
  sampler:obligation_counter_reset,
  tester:test(Style,
              'Proving',
              Repository://Entry,
              Repository:entry(Entry),
              ( Target = (Repository://Entry:Action?{[]}),
                prover:test_target_success(Target)
              )),
  sampler:obligation_counter_report,
  ( current_predicate(printer:prove_plan_perf_report/0) ->
      printer:prove_plan_perf_report
  ; true
  ),
  ( current_predicate(scheduler:perf_report/0) ->
      scheduler:perf_report
  ; true
  ).


%! prover:test_latest(+Repository) is det
%
% Run a prove test over only the latest ebuild per package.

prover:test_latest(Repository) :-
  config:test_style(Style),
  prover:test_latest(Repository,Style).


%! prover:test_latest(+Repository, +Style) is det
%
% Run a latest-ebuild prove test with the given Style.

prover:test_latest(Repository,Style) :-
  config:proving_target(Action0),
  prover:test_action(Action0, Action),
  tester:test(Style,
              'Proving',
              Repository://Entry,
              ( Repository:package(C,N),once(Repository:ebuild(Entry,C,N,_)) ),
              ( Target = (Repository://Entry:Action?{[]}),
                prover:test_target_success(Target)
              )).


% -----------------------------------------------------------------------------
%  Testing + statistics
% -----------------------------------------------------------------------------

%! prover:test_stats(+Repository) is det
%
% Run a whole-repo prove test with detailed statistics recording
% and top-N reporting.

prover:test_stats(Repository) :-
  config:test_style(Style),
  prover:test_stats(Repository, Style).


%! prover:test_stats(+Repository, +TopN) is det
%
% Like test_stats/1, but allows choosing the Top-N limit in the output.

prover:test_stats(Repository, TopN) :-
  integer(TopN),
  !,
  config:test_style(Style),
  prover:test_stats(Repository, Style, TopN).


%! prover:test_stats(+Repository, +Style) is det
%
% Run test_stats with the given Style and default TopN.

prover:test_stats(Repository, Style) :-
  ( config:test_stats_top_n(TopN) -> true ; TopN = 25 ),
  prover:test_stats(Repository, Style, TopN).


%! prover:test_stats(+Repository, +Style, +TopN) is det
%
% Core test_stats loop: proves each entry, records timing / inference /
% rule-call / context-union costs, classifies failures, and prints the
% TopN report at the end.

prover:test_stats(Repository, Style, TopN) :-
  config:proving_target(Action0),
  prover:test_action(Action0, Action),
  aggregate_all(count, (Repository:entry(_E)), ExpectedTotal),
  printer:test_stats_reset('Proving', ExpectedTotal),
  aggregate_all(count, (Repository:package(_C,_N)), ExpectedPkgs),
  printer:test_stats_set_expected_unique_packages(ExpectedPkgs),
  tester:test(Style,
              'Proving',
              Repository://Entry,
              Repository:entry(Entry),
              ( sampler:test_stats_reset_counters,
                statistics(inferences, I0),
                statistics(walltime, [T0,_]),
                ( printer:prove_plan([Repository://Entry:Action?{[]}], ProofAVL, ModelAVL, _Plan, Triggers) ->
                    Proved = true
                ; Proved = false
                ),
                statistics(walltime, [T1,_]),
                statistics(inferences, I1),
                TimeMs is T1 - T0,
                Inferences is I1 - I0,
                ( Proved == true ->
                    sampler:test_stats_get_counters(rule_calls(RuleCalls)),
                    sampler:test_stats_get_ctx_counters(ctx_union_calls(CtxUC), ctx_union_cost(CtxCost), ctx_max_len(CtxMax), ctx_union_ms_est(CtxMsEst)),
                    sampler:test_stats_get_ctx_distribution(ctx_len_hist(CtxHistPairs),
                                                          ctx_cost_mul(CtxMul),
                                                          ctx_cost_add(CtxAdd),
                                                          ctx_len_samples(CtxLenSamples)),
                    printer:test_stats_record_costs(Repository://Entry, TimeMs, Inferences, RuleCalls),
                    printer:test_stats_record_context_costs(Repository://Entry, CtxUC, CtxCost, CtxMax, CtxMsEst),
                    printer:test_stats_record_ctx_len_distribution(CtxHistPairs, CtxMul, CtxAdd, CtxLenSamples),
                    printer:test_stats_record_entry(Repository://Entry, ModelAVL, ProofAVL, Triggers, true)
                ; % strict failure: classify blocker vs conflict vs other (best-effort)
                  % Time-budget: skip re-prove attempts if original prove already
                  % consumed more than 1/3 of the time limit to avoid timeouts.
                  config:time_limit(TLimit),
                  TimeBudgetMs is TLimit * 333,
                  ( TimeMs > TimeBudgetMs ->
                      printer:test_stats_record_failed(other)
                  ; ( current_predicate(rules:with_assume_blockers/1),
                      rules:with_assume_blockers(
                        printer:prove_plan([Repository://Entry:Action?{[]}], _ProofAVL3, _ModelAVL3, _Plan3, _TriggersAVL3)
                      ) ->
                        printer:test_stats_record_failed(blocker)
                    ; current_predicate(rules:with_assume_conflicts/1),
                      rules:with_assume_conflicts(
                        prover:prove(Repository://Entry:Action?{[]},t,_,t,_,t,_,t,_)
                      ) ->
                        printer:test_stats_record_failed(conflict)
                    ; printer:test_stats_record_failed(other)
                    )
                  )
                )
              )),
  printer:test_stats_print(TopN).


% -----------------------------------------------------------------------------
%  Focused stats: run prover:test_stats for a specific list of Category/Name pairs
% -----------------------------------------------------------------------------


%! prover:test_stats_pkgs(+Repository, +Pkgs)
%
% Run test_stats for a specific list of packages, where Pkgs is a list of C-N pairs.
% This is intended for fast iteration on the slowest packages reported by test_stats/1.
prover:test_stats_pkgs(Repository, Pkgs) :-
  config:test_style(Style),
  ( config:test_stats_top_n(TopN) -> true ; TopN = 25 ),
  prover:test_stats_pkgs(Repository, Style, TopN, Pkgs).


%! prover:test_stats_pkgs(+Repository, +Style, +TopN, +Pkgs) is det
%
% Inner loop for focused test_stats over a specific list of packages.

prover:test_stats_pkgs(Repository, Style, TopN, Pkgs) :-
  is_list(Pkgs),
  config:proving_target(Action),
  length(Pkgs, ExpectedTotal),
  printer:test_stats_reset('Proving', ExpectedTotal),
  printer:test_stats_set_expected_unique_packages(ExpectedTotal),
  tester:test(Style,
              'Proving',
              Repository://Entry,
              ( member(C-N, Pkgs),
                once(Repository:ebuild(Entry, C, N, _))
              ),
              ( sampler:test_stats_reset_counters,
                statistics(inferences, I0),
                statistics(walltime, [T0,_]),
                ( prover:prove(Repository://Entry:Action?{[]},t,ProofAVL,t,ModelAVL,t,_Constraint,t,Triggers) ->
                    Proved = true
                ; Proved = false
                ),
                statistics(walltime, [T1,_]),
                statistics(inferences, I1),
                TimeMs is T1 - T0,
                Inferences is I1 - I0,
                ( Proved == true ->
                    sampler:test_stats_get_counters(rule_calls(RuleCalls)),
                    sampler:test_stats_get_ctx_counters(ctx_union_calls(CtxUC), ctx_union_cost(CtxCost), ctx_max_len(CtxMax), ctx_union_ms_est(CtxMsEst)),
                    sampler:test_stats_get_ctx_distribution(ctx_len_hist(CtxHistPairs),
                                                          ctx_cost_mul(CtxMul),
                                                          ctx_cost_add(CtxAdd),
                                                          ctx_len_samples(CtxLenSamples)),
                    printer:test_stats_record_costs(Repository://Entry, TimeMs, Inferences, RuleCalls),
                    printer:test_stats_record_context_costs(Repository://Entry, CtxUC, CtxCost, CtxMax, CtxMsEst),
                    printer:test_stats_record_ctx_len_distribution(CtxHistPairs, CtxMul, CtxAdd, CtxLenSamples),
                    printer:test_stats_record_entry(Repository://Entry, ModelAVL, ProofAVL, Triggers, true)
                ; % strict failure: classify blocker vs conflict vs other (best-effort)
                  ( current_predicate(rules:with_assume_blockers/1),
                    rules:with_assume_blockers(
                      prover:prove(Repository://Entry:Action?{[]},t,_,t,_,t,_,t,_)
                    ) ->
                      printer:test_stats_record_failed(blocker)
                  ; current_predicate(rules:with_assume_conflicts/1),
                    rules:with_assume_conflicts(
                      prover:prove(Repository://Entry:Action?{[]},t,_,t,_,t,_,t,_)
                    ) ->
                      printer:test_stats_record_failed(conflict)
                  ; printer:test_stats_record_failed(other)
                  )
                )
              )),
  printer:test_stats_print(TopN).