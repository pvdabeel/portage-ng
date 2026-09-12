/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> PROVER
Inductive proof search engine for portage-ng.

The prover is a generic inference facility: it knows nothing about
resolving, ordering, or any other pipeline phase.  Callers hand it a
rule module together with the goals (`prover:prove(Rules, ...)`), and
every rule expansion during that pass resolves against `Rules:rule/2`.
The pipeline stages own the pairing: the resolver proves with the
`resolving` rule set (pass 1: what — versions, USE, slots), the orderer
proves with the `ordering` rule set (pass 2: when — waves).  Callers
that sit outside any pass (e.g. query-side model construction) fall
back to `config:default_rules/1`.

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
  delegates to the domain hook `heuristic:handle_reprove(Info, Added)`
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
  the boundary of each top-level `prover:prove/10` invocation.

- Cycle detection and cycle-break assumptions: during depth-first
  proof search, a per-proof *cycle stack* tracks literals currently
  being proved.  When a literal is encountered that is already on
  the stack, the prover consults the domain hook `heuristic:cycle_benign/2`
  (if defined) before deciding how to handle the cycle:

  * *Benign cycle* (`heuristic:cycle_benign(Lit, CyclePath)` succeeds): the literal
    is already being resolved by an ancestor on the proof stack and
    the domain considers the cycle harmless.  The prover treats it as
    already proven -- it adds `Lit` to the Model and continues without
    recording any assumption.  No `assumed(rule(Lit))` key is stored.
    This matches the behaviour of resolvers like Portage that silently
    handle dependency-level self-referential cycles.

  * *Structural cycle* (hook absent or fails): the prover records a
    cycle-break assumption.  In Proof, cycle-breaks appear under the
    key `assumed(rule(Lit))` (as opposed to `rule(Lit)` for normally
    proven literals).  In Model, they appear as `assumed(Lit)`.

  Both are distinct from *domain-level* assumptions introduced by the
  rule layer via `rule(assumed(X), [])`.

- Triggers form a reverse-dependency index: for each body literal B
  that appears in a proven rule `rule(H, [..., B, ...])`, Triggers
  maps B to the list of head literals H that depend on it.  This
  allows downstream consumers (the orderer) to answer "which
  heads are affected if B changes?" in O(1).  Triggers are maintained
  incrementally during the proof: each proven rule adds its body
  literals to Triggers as it is recorded.

- A lightweight =prove_model= variant skips Proof and Triggers
  bookkeeping for internal query-side model construction.

- Proof obligations (`heuristic:proof_obligation/4`): after a literal is
  proven, the prover queries the domain for additional proof
  obligations -- extra literals to be appended to the remaining proof
  queue.  This lets the domain inject derived proof obligations
  (e.g. post-dependencies discovered only after a literal is
  resolved) without the prover itself understanding or encoding
  any domain-specific semantics.


*/

:- module(prover, []).

:- use_module(library(assoc), [empty_assoc/1, get_assoc/3, put_assoc/4]).

user:goal_expansion(debug_hook(_, _, _, _), true) :-
  \+ current_prolog_flag(instrumentation, true).

user:goal_expansion(maybe_debug_hook(_, _, _, _), true) :-
  \+ current_prolog_flag(instrumentation, true).


% =============================================================================
%  PROVER declarations
% =============================================================================

% ----------------------------------------------------------------------------- 
% Rule set parameterization
% -----------------------------------------------------------------------------
%
% The prover never names a rule module itself: the module to prove
% against is an argument of the public entry points, scoped to the pass
% via a thread-local global (save/restore, so nested passes are safe).
% Outside any pass the accessor falls back to `config:default_rules/1`,
% which keeps query-side model construction (`prove_model/5` inlined by
% Source/Knowledge/query.pl) working from the printer, builder, and
% interactive sessions without explicit scoping.


%! prover:rule_module(-Rules)
%
% The rule module of the pass currently running on this thread, or the
% configured default when no pass is active.

prover:rule_module(Rules) :-
  ( nb_current(prover_rule_module, R), R \== [] ->
      Rules = R
  ; config:default_rules(Rules)
  ).


%! prover:with_rule_module(+Rules, :Goal)
%
% Run Goal with Rules as the active rule module (save/restore).

prover:with_rule_module(Rules, Goal) :-
  ( nb_current(prover_rule_module, Saved) -> true ; Saved = [] ),
  setup_call_cleanup(
    nb_setval(prover_rule_module, Rules),
    Goal,
    nb_setval(prover_rule_module, Saved)).


%! prover:rule_call(+Full, -Body)
%
% Expand a literal against the active rule module.  The single seam
% through which the proof engines below consult domain knowledge.

prover:rule_call(Full, Body) :-
  prover:rule_module(Rules),
  Rules:rule(Full, Body).


% ----------------------------------------------------------------------------- 
% Top-Level Entry Point
% -----------------------------------------------------------------------------


%! prover:prove(+Rules, +Target, +InProof, -OutProof, +InModel, -OutModel, +InCons, -OutCons, +InTriggers, -OutTriggers)
%
% Main entry point for the prover: prove Target against the Rules
% module (its `rule/2` supplies the domain knowledge for this pass).
% Orchestrates the proving process and the configurable trigger-building strategy.
%
% In addition, we support bounded "reprove with scoped rejects" retries for
% domain conflicts emitted via `prover_reprove(Info)` exceptions.

prover:prove(Rules, Target, InProof, OutProof, InModel, OutModel, InCons, OutCons, InTriggers, OutTriggers) :-
  prover:reprove_max_retries(MaxRetries),
  prover:with_rule_module(Rules,
    prover:with_root_goals(Target,
      prover:with_reprove_state(
        prover:prove_with_retries(
          Target, InProof, OutProof, InModel, OutModel, InCons, OutCons, InTriggers, OutTriggers, 0, MaxRetries
        )
      )
    )
  ).


%! prover:with_root_goals(+Target, :Goal) is det
%
% Run Goal with Target published as the root goal list of the current
% prove (see prover:root_goal/1).  Saved and restored around Goal so a
% nested prove does not clobber the outer one's roots.

prover:with_root_goals(Target, Goal) :-
  ( nb_current(prover_root_goals, Saved) -> true ; Saved = '$absent' ),
  ( is_list(Target) -> Goals = Target ; Goals = [Target] ),
  nb_setval(prover_root_goals, Goals),
  setup_call_cleanup(true,
                     Goal,
                     ( Saved == '$absent' -> nb_delete(prover_root_goals)
                     ; nb_setval(prover_root_goals, Saved)
                     )).


%! prover:root_goal(?Goal) is nondet
%
% Goal is one of the literals the current prove was asked to prove (the
% Target list handed to prover:prove/10), as opposed to a literal derived
% while proving.  Rule sets use it to recognise a root target where a
% learning step aimed at "choose a different version of this entry" is
% pointless: the root is not chosen, it is the request.

prover:root_goal(Goal) :-
  nb_current(prover_root_goals, Goals),
  member(Goal, Goals).


%! prover:prove_with_retries(+Target, +InProof, -OutProof, +InModel, -OutModel, +InCons, -OutCons, +InTriggers, -OutTriggers, +Attempt, +MaxRetries) is det
%
% Inner retry loop for domain conflict resolution.  Catches
% `prover_reprove(Info)` exceptions and delegates to the domain
% hook `heuristic:handle_reprove/2` to process the conflict.  Retries
% with expanded reject sets up to MaxRetries.
%
% After a pass COMPLETES, the domain is additionally consulted for
% *deferred* conflicts (`heuristic:reprove_pending/1`): conflicts the
% domain chose to learn mid-pass without aborting, batching them into a
% single retry (e.g. shared-dep USE forces, portage-ng#94). Because the
% pass completed, its Proof/Model/Constraints/Triggers are intact and
% the retry can be a *partial restart* (non-chronological backtracking):
% only the literals affected by the conflict are pruned and re-derived,
% everything else is resumed as-is (see "Conflict-driven partial
% restart" below). When the retry budget is exhausted the completed
% proof is accepted as-is (it is exactly what the final
% reprove-disabled pass would recompute).

prover:prove_with_retries(Target, InProof, OutProof, InModel, OutModel, InCons, OutCons, InTriggers, OutTriggers, Attempt, MaxRetries) :-
  catch(
    ( prover:prove_once(Target, InProof, Proof1, InModel, Model1, InCons, Cons1, InTriggers, Trig1),
      Outcome = completed
    ),
    prover_reprove(ThrownInfo),
    Outcome = thrown(ThrownInfo)
  ),
  ( Outcome == completed ->
      ( prover:deferred_reprove_pending(Attempt, MaxRetries, Info) ->
          prover:reprove_from_completed(
            Target, InProof, OutProof, InModel, OutModel, InCons, OutCons, InTriggers, OutTriggers,
            Attempt, MaxRetries, Info, Proof1, Model1, Cons1, Trig1
          )
      ; OutProof = Proof1, OutModel = Model1, OutCons = Cons1, OutTriggers = Trig1
      )
  ; Outcome = thrown(Info0),
    prover:handle_reprove(
      Target, InProof, OutProof, InModel, OutModel, InCons, OutCons, InTriggers, OutTriggers,
      Attempt, MaxRetries, Info0
    )
  ).


%! prover:deferred_reprove_pending(+Attempt, +MaxRetries, -Info) is semidet
%
% Consult the domain for conflicts deferred during the pass that just
% completed. Succeeds with the domain's Info term when a deferred
% conflict is pending and retry budget remains; fails otherwise,
% accepting the completed proof.

prover:deferred_reprove_pending(Attempt, MaxRetries, Info) :-
  Attempt < MaxRetries,
  current_predicate(heuristic:reprove_pending/1),
  heuristic:reprove_pending(Info).


%! prover:reprove_from_completed(+Target, +InProof, -OutProof, +InModel, -OutModel, +InCons, -OutCons, +InTriggers, -OutTriggers, +Attempt, +MaxRetries, +Info, +Proof1, +Model1, +Cons1, +Trig1) is det
%
% Retry after a COMPLETED pass reported a deferred conflict.  The
% completed pass artifacts (Proof1/Model1/Cons1/Trig1) are available, so
% after the domain confirms progress (`heuristic:handle_reprove/2`) the
% retry prefers a partial restart from the pruned artifacts over a full
% restart from the original inputs.  A resumed pass that itself throws a
% mid-pass conflict falls back to the classical full-restart path from
% the ORIGINAL inputs, so thrown conflicts keep their existing
% semantics regardless of how the previous pass was restarted.

prover:reprove_from_completed(Target, InProof, OutProof, InModel, OutModel, InCons, OutCons, InTriggers, OutTriggers,
                              Attempt, MaxRetries, Info, Proof1, Model1, Cons1, Trig1) :-
  ( current_predicate(heuristic:handle_reprove/2),
    heuristic:handle_reprove(Info, Added),
    Added == true
  ->
    Attempt1 is Attempt + 1,
    ( prover:partial_restart_state(Info, Proof1, Model1, Cons1, Trig1, RProof, RModel, RCons, RTrig) ->
        flag(prover_partial_restarts, PR, PR + 1),
        catch(
          ( prover:mark_resume_pass,
            prover:prove_once(Target, RProof, Proof2, RModel, Model2, RCons, Cons2, RTrig, Trig2),
            Resumed = completed
          ),
          prover_reprove(ThrownInfo),
          Resumed = thrown(ThrownInfo)
        ),
        ( Resumed == completed ->
            ( prover:deferred_reprove_pending(Attempt1, MaxRetries, Info2) ->
                prover:reprove_from_completed(
                  Target, InProof, OutProof, InModel, OutModel, InCons, OutCons, InTriggers, OutTriggers,
                  Attempt1, MaxRetries, Info2, Proof2, Model2, Cons2, Trig2
                )
            ; OutProof = Proof2, OutModel = Model2, OutCons = Cons2, OutTriggers = Trig2
            )
        ; Resumed = thrown(Info3),
          prover:handle_reprove(
            Target, InProof, OutProof, InModel, OutModel, InCons, OutCons, InTriggers, OutTriggers,
            Attempt1, MaxRetries, Info3
          )
        )
    ; flag(prover_full_restarts, FR, FR + 1),
      prover:prove_with_retries(
        Target, InProof, OutProof, InModel, OutModel, InCons, OutCons, InTriggers, OutTriggers, Attempt1, MaxRetries
      )
    )
  ; % The domain recorded no progress for the deferred conflict: accept
    % the completed pass (re-proving would recompute the same result).
    OutProof = Proof1, OutModel = Model1, OutCons = Cons1, OutTriggers = Trig1
  ).


%! prover:handle_reprove(+Target, +InProof, -OutProof, +InModel, -OutModel, +InCons, -OutCons, +InTriggers, -OutTriggers, +Attempt, +MaxRetries, +Info) is det
%
% Handle a reprove exception: delegate to the domain hook
% `heuristic:handle_reprove(Info, Added)` to process the conflict
% (e.g. add rejects), then retry or fall back to a final prove
% with reprove disabled.

prover:handle_reprove(Target, InProof, OutProof, InModel, OutModel, InCons, OutCons, InTriggers, OutTriggers,
                      Attempt, MaxRetries, Info) :-
  ( Attempt < MaxRetries,
    current_predicate(heuristic:handle_reprove/2),
    heuristic:handle_reprove(Info, Added),
    Added == true
  ->
    Attempt1 is Attempt + 1,
    prover:prove_with_retries(
      Target, InProof, OutProof, InModel, OutModel, InCons, OutCons, InTriggers, OutTriggers, Attempt1, MaxRetries
    )
  ; ( current_predicate(heuristic:reprove_exhausted/0) -> heuristic:reprove_exhausted ; true ),
    prover:with_reprove_disabled(
      prover:prove_once(Target, InProof, OutProof, InModel, OutModel, InCons, OutCons, InTriggers, OutTriggers)
    )
  ).


%! prover:prove_once(+Rules, +Target, +InProof, -OutProof, +InModel, -OutModel, +InCons, -OutCons, +InTriggers, -OutTriggers) is det
%
% Single-attempt prove against the Rules module: no reprove harness, no
% learned-constraint lifecycle.  This is the entry point for passes that
% need exactly one deterministic attempt (the orderer's pass 2).

prover:prove_once(Rules, Target, InProof, OutProof, InModel, OutModel, InCons, OutCons, InTriggers, OutTriggers) :-
  prover:with_rule_module(Rules,
    prover:prove_once(Target, InProof, OutProof, InModel, OutModel, InCons, OutCons, InTriggers, OutTriggers)
  ).


%! prover:prove_once(+Target, +InProof, -OutProof, +InModel, -OutModel, +InCons, -OutCons, +InTriggers, -OutTriggers) is det
%
% Single-attempt prove: runs the core recursive engine with cycle-stack
% bookkeeping.  Triggers are maintained incrementally during the proof;
% dependent lists are deduplicated once here, after the proof completes
% (see `prover:add_trigger/4` / issue #53).  Internal: runs under the
% rule module already scoped by prove/10 or prove_once/10.

prover:prove_once(Target, InProof, OutProof, InModel, OutModel, InCons, OutCons, InTriggers, OutTriggers) :-
  prover:debug_hook(Target, InProof, InModel, InCons),
  prover:begin_pass,
  prover:with_cycle_stack(
    prover:prove_recursive(Target, InProof, OutProof, InModel, OutModel, InCons, OutCons, InTriggers, RawTriggers)
  ),
  prover:dedup_triggers(RawTriggers, OutTriggers).


%! prover:begin_pass is det
%
% Per-pass initialization dispatch.  Determines whether the pass about
% to run is a `fresh` pass (full restart or first attempt) or a `resume`
% pass (partial restart from pruned artifacts, see
% `prover:partial_restart_state/9`) and notifies the domain through the
% `heuristic:begin_pass/1` hook so it can scope its per-pass state
% clearing accordingly.  Falls back to the legacy
% `use:clear_bwu_cross_dep_memos/0` call for a fresh pass when the hook
% is not installed.

prover:begin_pass :-
  ( nb_current(prover_resume_pass, true) ->
      nb_setval(prover_resume_pass, false),
      Kind = resume
  ; Kind = fresh,
    % A fresh pass has no pre-restart witness pass; drop any
    % prior-proven set left over from an earlier partial restart.
    ( nb_current(prover_restart_prior_proven, _) ->
        nb_delete(prover_restart_prior_proven)
    ; true
    )
  ),
  ( current_predicate(heuristic:begin_pass/1) ->
      heuristic:begin_pass(Kind)
  ; Kind == fresh,
    current_predicate(use:clear_bwu_cross_dep_memos/0) ->
      use:clear_bwu_cross_dep_memos
  ; true
  ).


%! prover:mark_resume_pass is det
%
% Mark the next `prove_once/9` pass as a resumed (partial restart) pass.
% Consumed (reset) by `prover:begin_pass/0`.

prover:mark_resume_pass :-
  nb_setval(prover_resume_pass, true).


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
% to `heuristic:init_state/0` and `heuristic:cleanup_state/0`.

prover:with_reprove_state(Goal) :-
  ( nb_current(prover_learned_constraints, SavedAVL) -> true ; empty_assoc(SavedAVL) ),
  empty_assoc(EmptyAVL),
  nb_setval(prover_learned_constraints, EmptyAVL),
  ( current_predicate(heuristic:init_state/0) -> heuristic:init_state ; true ),
  setup_call_cleanup(true,
                     Goal,
                     ( ( current_predicate(heuristic:cleanup_state/0) -> heuristic:cleanup_state ; true ),
                       nb_setval(prover_learned_constraints, SavedAVL)
                     )).


%! prover:with_reprove_disabled(:Goal) is det
%
% Run Goal with reprove disabled (final-attempt clean prove).

prover:with_reprove_disabled(Goal) :-
  prover:reprove_disable,
  setup_call_cleanup(true,
                     Goal,
                     prover:reprove_enable).


%! prover:reprove_disable is det.
%
% Disable reprove (used for final-attempt clean prove).
% Saves the current reprove-enabled flag and sets it to false.

prover:reprove_disable :-
  ( nb_current(prover_reprove_enabled, Old) -> true ; Old = '$absent' ),
  nb_setval(prover_reprove_disable_saved, Old),
  nb_setval(prover_reprove_enabled, false),
  !.


%! prover:reprove_enable is det.
%
% Restore reprove state after a reprove_disable/0 call.

prover:reprove_enable :-
  ( nb_current(prover_reprove_disable_saved, Old) ->
      ( Old == '$absent' -> nb_delete(prover_reprove_enabled)
      ; nb_setval(prover_reprove_enabled, Old)
      ),
      nb_delete(prover_reprove_disable_saved)
  ; true
  ),
  !.


%! prover:reprove_enabled is semidet.
%
% Succeeds when the reprove retry mechanism is currently enabled.

prover:reprove_enabled :-
  nb_current(prover_reprove_enabled, true),
  !.


%! prover:assuming(+Literal, :Goal) is det.
%
% Run Goal with Literal-class proof failures treated as assumptions.
% Domain modules check prover:assuming(Literal) to decide behavior.
%
% Example usage:
%   prover:assuming(blockers, Goal)   — treat blockers as assumptions
%   prover:assuming(conflicts, Goal)  — treat conflicts as assumptions

prover:assuming(Literal, Goal) :-
  atom_concat('prover_assuming_', Literal, Key),
  ( nb_current(Key, Old) -> true ; Old = unset ),
  nb_setval(Key, true),
  setup_call_cleanup(true,
                     Goal,
                     ( Old == unset -> nb_delete(Key)
                     ; nb_setval(Key, Old)
                     )).


%! prover:assuming(+Literal) is semidet.
%
% Succeeds when Literal-class proof failures are currently being assumed.

prover:assuming(Literal) :-
  atom_concat('prover_assuming_', Literal, Key),
  nb_current(Key, true).


% -----------------------------------------------------------------------------
% Conflict-driven partial restart (non-chronological backtracking)
% -----------------------------------------------------------------------------

% When a completed pass reports a deferred conflict, a classical retry
% throws away the whole pass and re-proves from the original inputs,
% even though the conflict typically invalidates only a small region of
% the proof.  The partial restart instead:
%
%   1. asks the domain which model literals the conflict invalidates
%      (`heuristic:restart_seed/2` — e.g. every action literal of a
%      provider whose USE flags were force-changed),
%   2. computes the AFFECTED SET: the transitive dependents-closure of
%      the seeds over the Triggers index (every literal whose derivation
%      could observe the invalidated ones — by construction this
%      includes the proof targets, so the resumed pass re-reaches every
%      pruned literal that is still needed),
%   3. prunes the affected literals from Proof/Model/Triggers and asks
%      the domain which accumulated constraints belong to the affected
%      region (`heuristic:restart_constraint_scope/3` +
%      `heuristic:restart_drop_constraint/2`),
%   4. resumes proving from the pruned artifacts: unaffected literals
%      hit the `proven` fast path, affected ones re-derive with the
%      conflict resolution (e.g. learned USE forces) applied.
%
% The mechanism is fully generic: what constitutes a seed, an affected
% constraint, or per-pass domain state to preserve on resume is decided
% by the heuristic hooks.  Without those hooks (or with
% config:reprove_partial_restart(false)) the prover falls back to the
% classical full restart.


%! prover:partial_restart_state(+Info, +Proof, +Model, +Cons, +Trig, -RProof, -RModel, -RCons, -RTrig) is semidet
%
% Compute pruned artifacts for a partial restart after a deferred
% conflict Info.  Fails (falling back to a full restart) when partial
% restart is disabled, the domain does not provide the seed hook, or no
% seed literal is found in the Model.

prover:partial_restart_state(Info, Proof, Model, Cons, Trig, RProof, RModel, RCons, RTrig) :-
  prover:partial_restart_enabled,
  current_predicate(heuristic:restart_seed/2),
  prover:restart_seeds(Info, Model, Seeds),
  Seeds \== [],
  prover:triggers_closure(Seeds, Trig, Affected),
  prover:prune_model(Model, Affected, RModel),
  prover:prune_proof(Proof, Affected, Info, RProof),
  prover:prune_triggers(Trig, Affected, RTrig),
  prover:prune_constraints(Cons, Affected, Info, RCons),
  prover:restart_note_prior_proven(Model, Affected),
  !.


%! prover:restart_note_prior_proven(+Model, +Affected) is det
%
% Record which pruned literals the pre-restart pass proved WITHOUT a
% cycle-break.  A literal qualifies when the prior Model holds its
% plain key and NO `assumed(Core)` marker: a cycle-break records
% `assumed(Core)` first and the plain key is still added when the
% literal's outer derivation completes, so the plain key alone is not
% a cycle-free witness.  The resumed pass consults this set when it
% detects a cycle: the previous completed pass is a witness that the
% literal is provable cycle-free, so a cycle re-detected on it during
% the resume is an artifact of the altered traversal order (kept
% literals short-circuit through the `proven` fast path, changing
% which literals sit on the cycle stack) rather than a new structural
% cycle, and is treated as benign.  Consumed via
% `prover:restart_prior_proven/1`; reset on fresh passes by
% `prover:begin_pass/0`.

prover:restart_note_prior_proven(Model, Affected) :-
  assoc_to_keys(Affected, Cores),
  findall(Core-true,
          ( member(Core, Cores),
            get_assoc(Core, Model, _),
            \+ get_assoc(assumed(Core), Model, _)
          ),
          Pairs),
  ord_list_to_assoc(Pairs, PriorProven),
  nb_setval(prover_restart_prior_proven, PriorProven).


%! prover:restart_prior_proven(+Lit) is semidet
%
% True when Lit was proven without a cycle-break by the completed pass
% that preceded the current partial restart (see
% `prover:restart_note_prior_proven/2`).

prover:restart_prior_proven(Lit) :-
  nb_current(prover_restart_prior_proven, PriorProven),
  get_assoc(Lit, PriorProven, _).


%! prover:partial_restart_enabled is semidet
%
% Partial restart is enabled unless config:reprove_partial_restart(false).

prover:partial_restart_enabled :-
  ( current_predicate(config:reprove_partial_restart/1),
    config:reprove_partial_restart(Enabled)
  ->
    Enabled == true
  ; true
  ).


%! prover:restart_seeds(+Info, +Model, -Seeds) is det
%
% Collect the model keys the domain marks as invalidated by the
% deferred conflict Info (`heuristic:restart_seed/2`).  The domain
% classifies the unwrapped core (assumed/naf wrappers stripped), but
% the seed is the EXACT model key: the Triggers index is keyed by the
% canonical body-literal core, which for a failed dependency edge is
% the `assumed(...)`-wrapped literal itself, so the closure must start
% from the exact key to reach the consumers of that edge.

prover:restart_seeds(Info, Model, Seeds) :-
  findall(Key,
          ( gen_assoc(Key, Model, _),
            prover:restart_core(Key, Core),
            heuristic:restart_seed(Info, Core)
          ),
          Seeds0),
  sort(Seeds0, Seeds).


%! prover:restart_core(+Key, -Core) is det
%
% Strip `assumed/1` and `naf/1` wrappers from a Proof/Model key,
% yielding the underlying literal core used in the Triggers index.

prover:restart_core(assumed(Key0), Core) :- !, prover:restart_core(Key0, Core).
prover:restart_core(naf(Key0), Core)     :- !, prover:restart_core(Key0, Core).
prover:restart_core(Core, Core).


%! prover:triggers_closure(+Seeds, +Triggers, -Affected) is det
%
% Transitive dependents-closure of Seeds over the Triggers index
% (literal core -> list of dependent head cores).  Affected is an AVL
% mapping every reached core (seeds included) to `true`.

prover:triggers_closure(Seeds, Triggers, Affected) :-
  empty_assoc(Empty),
  prover:closure_add(Seeds, Empty, Visited0, _Fresh),
  prover:triggers_closure_(Seeds, Triggers, Visited0, Affected).

prover:triggers_closure_([], _Triggers, Affected, Affected) :- !.
prover:triggers_closure_([Core|Worklist], Triggers, Visited0, Affected) :-
  ( get_assoc(Core, Triggers, Dependents) -> true ; Dependents = [] ),
  prover:closure_add(Dependents, Visited0, Visited1, Fresh),
  append(Fresh, Worklist, Worklist1),
  prover:triggers_closure_(Worklist1, Triggers, Visited1, Affected).


%! prover:closure_add(+Cores, +Visited0, -Visited, -Fresh) is det
%
% Add unvisited cores to the visited set, returning the newly added ones.

prover:closure_add([], Visited, Visited, []) :- !.
prover:closure_add([Core|Cores], Visited0, Visited, Fresh) :-
  ( get_assoc(Core, Visited0, _) ->
      Visited1 = Visited0,
      Fresh = Fresh1
  ; put_assoc(Core, Visited0, true, Visited1),
    Fresh = [Core|Fresh1]
  ),
  prover:closure_add(Cores, Visited1, Visited, Fresh1).


%! prover:restart_affected(+Affected, +Key) is semidet
%
% True when a Proof/Model/Triggers key is in the affected set, either
% as the exact key or through its unwrapped core (`assumed/1`, `naf/1`
% stripped).  The exact-key check matches seeds that ARE wrapped model
% keys (e.g. assumed dependency literals with embedded context); the
% core check matches bookkeeping keys (cycle-break `assumed(Lit)`
% markers, `naf(Lit)`) that wrap a closure member.

prover:restart_affected(Affected, Key) :-
  ( get_assoc(Key, Affected, _) ->
      true
  ; prover:restart_core(Key, Core),
    Core \== Key,
    get_assoc(Core, Affected, _)
  ).


%! prover:prune_model(+Model, +Affected, -RModel) is det
%
% Remove affected literals (plain, `assumed/1` and `naf/1` keys) from
% the Model AVL.

prover:prune_model(Model, Affected, RModel) :-
  assoc_to_list(Model, Pairs),
  exclude(prover:model_pair_affected(Affected), Pairs, Kept),
  ord_list_to_assoc(Kept, RModel).

prover:model_pair_affected(Affected, Key-_Value) :-
  prover:restart_affected(Affected, Key).


%! prover:prune_proof(+Proof, +Affected, +Info, -RProof) is det
%
% Remove affected entries from the Proof AVL: `rule/1` (and
% `assumed(rule/1)`) entries, `cycle_path/1` witnesses and
% `obligation_pending/1` markers whose core is affected, plus
% `obligation_done/1` markers whose anchor literal (resolved through the
% domain hook `heuristic:restart_obligation_head/2`) is affected, so
% obligations re-fire when their anchor re-proves.

prover:prune_proof(Proof, Affected, Info, RProof) :-
  assoc_to_list(Proof, Pairs),
  exclude(prover:proof_pair_affected(Affected, Info), Pairs, Kept),
  ord_list_to_assoc(Kept, RProof).

prover:proof_pair_affected(Affected, _Info, Key-_Value) :-
  ( Key = rule(Inner)               -> prover:restart_affected(Affected, Inner)
  ; Key = assumed(rule(Inner))      -> prover:restart_affected(Affected, Inner)
  ; Key = cycle_path(Inner)         -> prover:restart_affected(Affected, Inner)
  ; Key = obligation_pending(Inner) -> prover:restart_affected(Affected, Inner)
  ; Key = obligation_done(OKey)     ->
      current_predicate(heuristic:restart_obligation_head/2),
      heuristic:restart_obligation_head(OKey, Inner),
      prover:restart_affected(Affected, Inner)
  ; fail
  ).


%! prover:prune_triggers(+Triggers, +Affected, -RTriggers) is det
%
% Remove affected keys from the Triggers index and filter affected
% heads out of the dependent lists of the kept keys.  The resumed pass
% re-adds the real edges as affected rules re-derive.

prover:prune_triggers(Triggers, Affected, RTriggers) :-
  assoc_to_list(Triggers, Pairs),
  prover:prune_trigger_pairs(Pairs, Affected, Kept),
  ord_list_to_assoc(Kept, RTriggers).

prover:prune_trigger_pairs([], _Affected, []) :- !.
prover:prune_trigger_pairs([Core-Dependents|Pairs], Affected, Kept) :-
  ( get_assoc(Core, Affected, _) ->
      Kept = Kept1
  ; exclude(prover:restart_affected(Affected), Dependents, Dependents1),
    Kept = [Core-Dependents1|Kept1]
  ),
  prover:prune_trigger_pairs(Pairs, Affected, Kept1).


%! prover:prune_constraints(+Cons, +Affected, +Info, -RCons) is det
%
% Drop accumulated constraints belonging to the affected region.  Which
% constraint keys those are is domain knowledge: the domain first
% derives an opaque scope term from the affected set
% (`heuristic:restart_constraint_scope/3`), then classifies each key
% (`heuristic:restart_drop_constraint/2`).  Without the hooks all
% constraints are kept.

prover:prune_constraints(Cons, Affected, Info, RCons) :-
  ( current_predicate(heuristic:restart_constraint_scope/3),
    current_predicate(heuristic:restart_drop_constraint/2),
    heuristic:restart_constraint_scope(Info, Affected, Scope)
  ->
    assoc_to_list(Cons, Pairs),
    exclude(prover:constraint_pair_dropped(Scope), Pairs, Kept),
    ord_list_to_assoc(Kept, RCons)
  ; RCons = Cons
  ).

prover:constraint_pair_dropped(Scope, Key-_Value) :-
  heuristic:restart_drop_constraint(Scope, Key).


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
      Proof       = NewProof,
      Model       = NewModel,
      Triggers    = NewTriggers,
      constraint:unify_constraints(Lit, Constraints, Constraints1),
      % Domain hook (keeps prover generic): if the domain provides a constraint
      % guard, it can reject inconsistent states by failing here.
      ( current_predicate(heuristic:constraint_guard/2) ->
          ( heuristic:constraint_guard(Lit, Constraints1) ->
              NewConstraints = Constraints1
          ; fail
          )
      ; NewConstraints = Constraints1
      )


  ;   % Case: Lit already proven with given proof context

      prover:proven(Lit, Model, Ctx) ->
      !,
      Proof       = NewProof,
      Model       = NewModel,
      Triggers    = NewTriggers,
      Constraints = NewConstraints


  ;   % Case: Lit already proven, but the requested proof context differs.
      %
      % The prover offers two ways of resolving such a re-request:
      %
      %   (a) `should_union_ctx/1` succeeds for Lit
      %       => union the stored Ctx with the incoming Ctx and
      %          re-derive the rule body under the unioned proof context.
      %          Subsequent obligations are computed from the diff
      %          (NewBody \ OldBody).
      %
      %   (b) `should_union_ctx/1` fails (default for any literal)
      %       => fall through to the `regular proof` branch below,
      %          which overwrites the stored Ctx with the incoming
      %          proof context and re-walks the body.
      %
      % (a) is needed when the rule body depends on Ctx in a way that
      % requires merging across multiple call sites (e.g. accumulating
      % per-package constraints from siblings). (b) is the classical
      % proof behaviour and is correct for literals whose Ctx is
      % per-edge plumbing rather than per-package state.
      %
      % The decision between (a) and (b) is domain-specific. The
      % prover stays domain-agnostic: it asks `should_union_ctx/1`
      % (which delegates to `heuristic:should_union_ctx/1` when the
      % domain installs that hook) and acts accordingly.
      %
      % `prove_model/6` (the lighter-weight model-only path) has the
      % same shape and the same domain hook below.

      prover:should_union_ctx(Lit),
      get_assoc(Lit, Model, ModelCtx) ->
      !,
      sampler:ctx_union(ModelCtx, Ctx, NewCtx),
      ( prover:ctx_equivalent(NewCtx, ModelCtx) ->
          % The union introduced nothing semantically new (only
          % non-equivalence-relevant Ctx items differ); the body
          % would re-derive identically, so keep the existing
          % Proof/Model/Triggers entries.
          Proof       = NewProof,
          Model       = NewModel,
          Triggers    = NewTriggers,
          Constraints = NewConstraints
      ; % The Proof AVL holds exactly one value per key, so a single
        % lookup suffices to retrieve the previously derived body.
        get_assoc(rule(Lit),Proof,dep(_OldCount,OldBody)?_OldProofCtx),

        prover:canon_literal(NewFull, Lit, NewCtx),

        sampler:rule_call,
        sampler:maybe_timeout_trace(Lit),
        prover:rule_call(NewFull,NewBody),

        % ==-based diff (NOT subtract/3): body literals may contain
        % unbound variables (e.g. constraints with fresh slot vars),
        % and unification-based membership would spuriously match and
        % silently drop a re-derived obligation.
        prover:body_diff(NewBody,OldBody,DiffBody),
        length(NewBody,NewCount),
        put_assoc(rule(Lit), Proof, dep(NewCount, NewBody)?NewCtx,Proof1),
        prover:add_triggers(NewFull, NewBody, Triggers, Triggers1),

        setup_call_cleanup(prover:cycle_stack_push(Lit),
                           prover:prove_recursive(DiffBody, Proof1, NewProof, Model, BodyModel, Constraints, BodyConstraints, Triggers1, NewTriggers),
                           prover:cycle_stack_pop(Lit)),

        put_assoc(Lit, BodyModel, NewCtx, NewModel),
        NewConstraints = BodyConstraints
      )


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

          prover:cycle_path_for(Lit, CyclePath),
          ( ( current_predicate(heuristic:cycle_benign/2),
              heuristic:cycle_benign(Lit, CyclePath)
            ; % Partial-restart witness: the completed pass that preceded
              % this resume proved Lit without a cycle-break, so this cycle
              % is an artifact of the resumed traversal order (kept
              % literals short-circuit via the `proven` fast path, changing
              % the cycle-stack contents), not a new structural cycle.
              prover:restart_prior_proven(Lit)
            ) ->

              % Benign cycle: the domain classifies this cycle as harmless
              % based on the cycle path (e.g. RDEPEND-mediated cycles that
              % Portage/Paludis handle as ordering issues, not resolution
              % failures).  Treat as proven without creating a cycle-break
              % assumption.
              put_assoc(Lit, Model, Ctx, NewModel),
              NewProof = Proof,
              NewConstraints = Constraints,
              NewTriggers = Triggers
          ;
              % Structural cycle: cycle-break assumption.
              % - In the Proof: record a special key `assumed(rule(Lit))`
              % - In the Model: record `assumed(Lit)`
              %
              % This is distinct from domain-level assumptions introduced by
              % rules via `rule(assumed(X), [])`.
              % Store the *current* body of the in-progress rule so downstream
              % planning logic can still see the cycle edges.  Mark the
              % depcount as -1 to indicate "deferred / cyclic".
              ( get_assoc(rule(Lit), Proof, dep(_OldCount, OldBody)?_OldCtx)
                -> BodyForPlanning = OldBody
                ;  BodyForPlanning = []
              ),
              put_assoc(assumed(rule(Lit)), Proof, dep(-1, BodyForPlanning)?Ctx, Proof1),
              put_assoc(cycle_path(Lit), Proof1, CyclePath, NewProof),
              put_assoc(assumed(Lit), Model, Ctx, NewModel),
              NewConstraints = Constraints,
              NewTriggers = Triggers
          )
      ;

      % Case: regular proof

          %message:color(orange),
          %writeln('PROVER: regular proof'),
          %message:color(normal),

          sampler:rule_call,
          sampler:maybe_timeout_trace(Lit),
          prover:rule_call(Full, Body),

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

  ;   % Case: Lit already proven with given proof context
      prover:proven(Lit, Model0, Ctx) ->
      !,
      Model = Model0,
      Constraints = Constraints0

  ;   % Case: Lit already proven, but the requested proof context differs.
      % Same domain-agnostic dispatch as prove_recursive/9: ask the
      % domain whether to union and re-derive (a) or to fall through
      % to the regular_proof branch (b). See the comment block in
      % prove_recursive/9 for the rationale.
      prover:should_union_ctx(Lit),
      get_assoc(Lit, Model0, OldCtx) ->
      !,
      sampler:ctx_union(OldCtx, Ctx, NewCtx),
      ( prover:ctx_equivalent(NewCtx, OldCtx) ->
          Model = Model0,
          Constraints = Constraints0
      ; prover:canon_literal(NewFull, Lit, NewCtx),
        sampler:rule_call,
        prover:rule_call(NewFull, NewBody),
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
      sampler:rule_call,
      prover:rule_call(Full, Body),
      prover:prove_model(Body, Model0, BodyModel, Constraints0, BodyConstraints, InProg1),
      put_assoc(Lit, BodyModel, Ctx, Model),
      Constraints = BodyConstraints
  ).


% -----------------------------------------------------------------------------
%  Proof obligations (domain-injected)
% -----------------------------------------------------------------------------

% The prover stays domain-agnostic.  After proving a literal, it consults
% an optional domain predicate to discover additional proof obligations:
%
%   heuristic:proof_obligation(+Literal, +Model, -Key, -ExtraLits)
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
  \+ current_predicate(heuristic:proof_obligation/4),
  !.
prover:collect_proof_obligations(Literal, Proof0, Proof, Model, Rest0, Rest) :-
  % Cheap skip: when the domain can compute the obligation key without
  % dependency-model work, an obligation already marked done -- or one the
  % domain says cannot yield extra literals -- never reaches the full hook.
  ( prover:obligation_key(Literal, Model, Key, NeedsFull) ->
      ( get_assoc(obligation_done(Key), Proof0, true) ->
          sampler:hook_done_hit,
          Proof = Proof0,
          Rest = Rest0
      ; NeedsFull == false ->
          put_assoc(obligation_done(Key), Proof0, true, Proof),
          Rest = Rest0
      ; prover:run_proof_obligation(Literal, Proof0, Proof, Model, Rest0, Rest)
      )
  ; prover:run_proof_obligation(Literal, Proof0, Proof, Model, Rest0, Rest)
  ).


%! prover:obligation_key(+Literal, +Model, -Key, -NeedsFull) is semidet
%
% The domain's cheap obligation key for Literal: heuristic:proof_obligation_key/4
% when defined, otherwise /3 (which cannot tell whether the full hook is
% needed, so NeedsFull is true). Fails when the domain defines neither or
% has no key for Literal.

prover:obligation_key(Literal, Model, Key, NeedsFull) :-
  ( current_predicate(heuristic:proof_obligation_key/4) ->
      once(heuristic:proof_obligation_key(Literal, Model, Key, NeedsFull))
  ; current_predicate(heuristic:proof_obligation_key/3) ->
      once(heuristic:proof_obligation_key(Literal, Model, Key)),
      NeedsFull = true
  ).


%! prover:run_proof_obligation(+Literal, +Proof0, -Proof, +Model, +Rest0, -Rest) is det
%
% Call the full domain hook. It is expected to be deterministic (0 or 1
% result), so the single result is processed directly instead of through
% findall/3.

prover:run_proof_obligation(Literal, Proof0, Proof, Model, Rest0, Rest) :-
  ( once(heuristic:proof_obligation(Literal, Model, Key, ExtraLits)) ->
      prover:collect_proof_obligations_list([obligation(Key, ExtraLits)],
                                            Proof0, Proof, Model, Rest0, Rest)
  ; Proof = Proof0,
    Rest = Rest0
  ).


%! prover:obligation_candidate(+Literal) is semidet
%
% Succeeds when Literal is a merge-action literal eligible for
% proof obligations. Delegates to heuristic:obligation_candidate/1
% for domain-specific action filtering.

prover:obligation_candidate(Literal) :-
  heuristic:obligation_candidate(Literal).


%! prover:collect_proof_obligations_list(+Obligations, +Proof0, -Proof, +Model, +Rest0, -Rest) is det
%
% Process a list of obligation(Key, ExtraLits) results: mark each key
% done in the proof, filter already-proven/pending literals, and append
% fresh ones to the remaining literal queue.

prover:collect_proof_obligations_list([], Proof, Proof, _Model, Rest, Rest) :- !.
prover:collect_proof_obligations_list([obligation(Key, ExtraLits)|Hs], Proof0, Proof, Model, Rest0, Rest) :-
  ( get_assoc(obligation_done(Key), Proof0, true) ->
      sampler:hook_done_hit,
      Proof1 = Proof0,
      Rest1 = Rest0
  ; put_assoc(obligation_done(Key), Proof0, true, Proof1),
    sampler:hook_fired(ExtraLits),
    prover:select_new_literals_to_enqueue(ExtraLits, Model, Proof1, Proof2, FreshLits),
    sampler:hook_fresh(FreshLits),
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
  nb_current(prover_learned_constraints, AVL),
  get_assoc(Literal, AVL, Constraint).


%! prover:learn(+Literal, +Constraint, -Added)
%
%  Store a learned constraint. If one already exists for Literal,
%  merge via feature_unification:val_hook. Added is true if the
%  store changed, false if Constraint was already subsumed.

prover:learn(Literal, Constraint, Added) :-
  ( nb_current(prover_learned_constraints, AVL0) -> true ; empty_assoc(AVL0) ),
  ( get_assoc(Literal, AVL0, Old) ->
      ( Old == Constraint ->
          Added = false
      ; feature_unification:val_hook(Old, Constraint, Merged) ->
          ( Merged == Old ->
              Added = false
          ; put_assoc(Literal, AVL0, Merged, AVL1),
            nb_setval(prover_learned_constraints, AVL1),
            Added = true
          )
      ; put_assoc(Literal, AVL0, Constraint, AVL1),
        nb_setval(prover_learned_constraints, AVL1),
        Added = true
      )
  ; put_assoc(Literal, AVL0, Constraint, AVL1),
    nb_setval(prover_learned_constraints, AVL1),
    Added = true
  ),
  ( Added == true ->
      choicelog:clog_emit(learn, recorded, learn(Literal, Constraint, true))
  ; true
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
% Calls of this predicate are compiled to `true` by the user:goal_expansion
% clause at the top of this file unless the `instrumentation` flag is set.

:- thread_local prover:debug_hook_handler/1.


%! prover:with_debug_hook(+Handler, :Goal)
%
% Install a per-thread debug hook handler during Goal. Handler must be a
% callable closure that can be called as call(Handler, Target, Proof, Model, Constraints).
% Example: prover:with_debug_hook(state:display_state, prover:prove(...)).
prover:with_debug_hook(Handler, Goal) :-
  setup_call_cleanup(
    asserta(prover:debug_hook_handler(Handler)),
    Goal,
    retractall(prover:debug_hook_handler(Handler))
  ).


%! prover:maybe_debug_hook(+Target, +Proof, +Model, +Constraints) is det
%
% Guarded debug hook for the hot path.  Compiled to `true` when the
% `instrumentation` flag is off (user:goal_expansion at the top of this file).

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
        % CRITICAL: dependents are keyed by CANONICAL head (no proof context).
        %
        % The proof AVL keys rules by their canonical head (no `?{Ctx}`
        % suffix), and trigger consumers (the orderer's refcount-based
        % merge-order bias) look up heads by the canonical literal.  If we
        % store the full head with context here, the same canonical head can
        % end up multiple times in a single trigger's dependent list (once
        % per distinct context the rule was proved/re-proved with),
        % over-counting that head's dependents.
        %
        % Concrete historical symptom (wave-planner era): with
        % `app-misc/mc`, libICE:install (depcount=7) was scheduled in the
        % same wave as xorg-proto:install because non-canonical dedup let
        % elt-patches/pkgconfig/libICE triggers decrement libICE multiple
        % times in wave 1.
        %
        % PERFORMANCE (issue #53): insertion is a plain cons — duplicates
        % are allowed here and removed once per completed proof by
        % `prover:dedup_triggers/2` (end of `prove_once/9`).  An inline
        % `memberchk/2` dedup would make each insertion O(D) and the total
        % cost per popular dependency literal (glibc-style, hundreds of
        % dependents) O(D²) on the proving hot path.
        prover:canon_literal(Dep, DepLit, _),
        prover:canon_literal(Head, HeadCanon, _),
        (get_assoc(DepLit, InTriggers, Dependents) -> true ; Dependents = []),
        put_assoc(DepLit, InTriggers, [HeadCanon|Dependents], OutTriggers)
    ).


%! prover:dedup_triggers(+InTriggers, -OutTriggers)
%
% Remove duplicate dependents from every trigger key in one pass.
%
% `add_trigger/4` conses dependents without deduplication (see issue #53);
% this runs once per completed proof.  The dedup is order-preserving and
% reproduces exactly the list `memberchk/2`-based insertion used to build:
% reverse insertion order of first occurrences.  Membership is tracked in
% an assoc, so a list with I insertions and U unique dependents costs
% O(I log U) instead of the O(I·U) of an inline scan.

prover:dedup_triggers(InTriggers, OutTriggers) :-
    map_assoc(prover:dedup_dependents, InTriggers, OutTriggers).


%! prover:dedup_dependents(+Dependents, -Deduped)
%
% Dedup a single dependent list, keeping the first-inserted occurrence of
% each head.  The input list is in reverse insertion order (newest first),
% so we walk it reversed (insertion order) and cons unseen heads, yielding
% reverse insertion order of first occurrences.

prover:dedup_dependents(Dependents, Deduped) :-
    reverse(Dependents, InsertionOrder),
    empty_assoc(Seen),
    prover:dedup_dependents_(InsertionOrder, Seen, [], Deduped).

prover:dedup_dependents_([], _, Acc, Acc).
prover:dedup_dependents_([Head|Rest], Seen, Acc, Deduped) :-
    (   get_assoc(Head, Seen, _)
    ->  prover:dedup_dependents_(Rest, Seen, Acc, Deduped)
    ;   put_assoc(Head, Seen, true, NewSeen),
        prover:dedup_dependents_(Rest, NewSeen, [Head|Acc], Deduped)
    ).


% -----------------------------------------------------------------------------
% Proof helper predicates & Canonicalisation
% -----------------------------------------------------------------------------


%! prover:proving(+RuleTerm, +Proof) is semidet
%
% Succeeds when the Proof AVL has a `rule(Lit)` entry, i.e. Lit has been
% proven (or is being proven) in this proof; Body is the stored body.

prover:proving(rule(Lit, Body), Proof) :- get_assoc(rule(Lit),Proof,dep(_, Body)?_).


%! prover:body_diff(+NewBody, +OldBody, -DiffBody) is det
%
% DiffBody contains the literals of NewBody (original order preserved)
% that are not ==-identical to any literal of OldBody.
%
% Used by the ctx-union re-derive branch of prove_recursive/9 instead
% of subtract/3: subtract/3 tests membership by unification, so a body
% literal containing an unbound variable could spuriously match an old
% literal and be dropped, silently skipping a re-derived obligation.
% OldBody is msort-ed once so membership is checked with ord_memberchk/2
% (compare/3-based, i.e. == semantics, with early termination) rather
% than a unifying memberchk/2 over the unsorted list.

prover:body_diff(NewBody, OldBody, DiffBody) :-
  msort(OldBody, OldSorted),
  prover:body_diff_(NewBody, OldSorted, DiffBody).

prover:body_diff_([], _, []).
prover:body_diff_([Lit|Lits], OldSorted, Diff) :-
  ( ord_memberchk(Lit, OldSorted)
  -> Diff = Rest
  ;  Diff = [Lit|Rest]
  ),
  prover:body_diff_(Lits, OldSorted, Rest).


%! prover:assumed_proving(+Lit, +Proof) is semidet
%
% Succeeds when Lit has a prover-level cycle-break marker in Proof
% (`assumed(rule(Lit))`).

prover:assumed_proving(Lit, Proof) :- get_assoc(assumed(rule(Lit)),Proof,dep(_Count, _Body)?_).


%! prover:proven(+Lit, +Model, +Ctx) is semidet
%
% Succeeds when Lit is in Model under a context that the domain
% considers equivalent to Ctx. Equivalence is delegated to
% `prover:ctx_equivalent/2`, which falls back to structural
% identity when no domain hook is installed.

prover:proven(Lit, Model, Ctx) :-
  get_assoc(Lit, Model, StoredCtx),
  prover:ctx_equivalent(StoredCtx, Ctx).


%! prover:assumed_proven(+Lit, +Model) is semidet
%
% Succeeds when Lit has a cycle-break assumption in the Model.

prover:assumed_proven(Lit, Model) :- get_assoc(assumed(Lit), Model, _).


% -----------------------------------------------------------------------------
% Domain hooks consumed by prove_recursive/9 and prove_model/6
% -----------------------------------------------------------------------------
%
% The prover engine is intentionally domain-agnostic: it knows only
% how to dispatch on `Lit ∈ Model` / `Lit ∉ Model`, on cycles, on
% conflicts, and on rule expansion. Anything that needs to know
% what a literal *means* — including how two literal contexts
% compare for equivalence and whether two requests for the same
% literal under different contexts should be merged — is delegated
% to the domain via the `heuristic:` hook namespace.
%
% Both hooks default to safe behaviour when the domain does not
% install them:
%
%  * `ctx_equivalent/2` defaults to structural identity (`==`).
%  * `should_union_ctx/1` defaults to false (the prover then falls
%     through to the regular_proof branch, i.e. the classical
%     "overwrite stored Ctx" behaviour).


%! prover:ctx_equivalent(+Ctx1, +Ctx2) is semidet.
%
% Two literal contexts are equivalent iff they are structurally
% identical OR the domain (`heuristic:ctx_equivalent/2`) declares
% them equivalent. Used by `proven/3` and by the post-union
% short-circuit in the context-changed branch.

prover:ctx_equivalent(C, C) :- !.
prover:ctx_equivalent(C1, C2) :-
  current_predicate(heuristic:ctx_equivalent/2),
  heuristic:ctx_equivalent(C1, C2).


%! prover:should_union_ctx(+Lit) is semidet.
%
% Domain hook: succeeds when the prover should *merge* multiple
% per-call-site Ctx values for Lit (rather than overwriting the
% stored one). Only literals whose rule body genuinely depends on
% an accumulated Ctx need this — for the rest, the classical
% regular_proof branch is both correct and cheaper.
%
% Falls back to false when the domain does not install
% `heuristic:should_union_ctx/1`, in which case the prover behaves
% like a plain SLD resolver with last-write-wins on stored Ctx.

prover:should_union_ctx(Lit) :-
  current_predicate(heuristic:should_union_ctx/1),
  heuristic:should_union_ctx(Lit).


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
%   Core  – part *before* the `?{Context}` proof-context annotation.
%   Ctx   – the proof-context list ({} for the “no proof-context” case).
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


%! prover:rule_parts(+Rule, -HeadWithCtx, -Body, -Kind) is det
%
% Deterministically destructure a full-format proof rule into its raw
% (proof-context-retaining) head, its body, and its kind. Single source of
% truth for the three rule shapes (issue #61): use this instead of
% open-coding the ( Rule = rule(H,B) ; Rule = assumed(rule(H,B)) ;
% Rule = rule(assumed(H),B) ) disjunction. Clauses are ordered
% most-specific first and committed with a cut, so a rule never yields two
% different destructurings on backtracking (issue #36).
%
% Kinds (see the assumption taxonomy in the project rules):
%   - cycle_break:       assumed(rule(X, Body))  (prover cycle-break)
%   - domain_assumption: rule(assumed(X), Body)  (domain assumption)
%   - regular:           rule(X, Body)           (regular rule)

prover:rule_parts(assumed(rule(HeadWithCtx, Body)), HeadWithCtx, Body, cycle_break) :- !.
prover:rule_parts(rule(assumed(HeadWithCtx), Body), HeadWithCtx, Body, domain_assumption) :- !.
prover:rule_parts(rule(HeadWithCtx, Body), HeadWithCtx, Body, regular).


%! prover:rule_head(+Rule, -Head) is det
%
% Extract the canonical head from a full-format proof rule (deterministic,
% via prover:rule_parts/4).
%
% Canonical head forms:
%   - assumed(rule(X, Body))  (prover cycle-break)  -> ctx-stripped X
%   - rule(assumed(X), Body)  (domain assumption)   -> the whole assumed(X)
%     term, inner ?{Ctx} retained. This is deliberate: it must match both
%     the proof key rule(assumed(X)) and the trigger key assumed(X), which
%     both retain the inner proof context.
%   - rule(X, Body)           (regular rule)        -> ctx-stripped X

prover:rule_head(Rule, Head) :-
  prover:rule_parts(Rule, HeadWithCtx, _Body, Kind),
  (   Kind == domain_assumption
  ->  Head = assumed(HeadWithCtx)
  ;   prover:canon_literal(HeadWithCtx, Head, _)
  ).


%! prover:rule_body(+Rule, -Body) is det
%
% Extract the body from a full-format proof rule. Deterministic companion
% to prover:rule_head/2 (via prover:rule_parts/4).

prover:rule_body(Rule, Body) :-
  prover:rule_parts(Rule, _HeadWithCtx, Body, _Kind).


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
