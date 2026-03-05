/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> HEURISTIC
Prover hooks (domain side), reprove domain state management, constraint
guards, proof obligations, and snapshot/rollback for the rules engine.

This module implements the domain-specific side of the prover's hook
interface. The prover is kept domain-agnostic; it calls into heuristic:
predicates for reprove state, constraint guards, and proof obligations.

== Prover Hook Interface ==

The following predicates are called by the prover:

  * heuristic:handle_reprove(+Info, -Added)
    Called when a prover_reprove(Info) exception is caught.
    Processes domain-specific conflict information and returns
    whether new rejects were added.

  * heuristic:reprove_exhausted/0
    Called when reprove retries are exhausted. Clears the reject
    map for the final clean prove attempt.

  * heuristic:init_state/0
    Save domain state at the start of a reprove-enabled proof.

  * heuristic:cleanup_state/0
    Restore domain state saved by init_state/0.

  * heuristic:obligation_candidate(+Literal)
    Domain hook for obligation filtering: succeeds when Literal
    is eligible for proof obligations.

  * heuristic:constraint_unify_hook(+Key, +Value, +Constraints, -NewConstraints)
    Domain-specific constraint merge for cn_domain keys.

  * heuristic:constraint_guard(+Constraint, +Constraints)
    Called after merging a constraint; must succeed for consistent stores.

  * heuristic:proof_obligation(+Literal, +Model, -HookKey, -ExtraLits)
    Compute extra literals to enqueue after proving a literal.

  * heuristic:proof_obligation_key(+Literal, +Model, -HookKey)
    Fast-path: compute only the obligation key.

*/

:- module(heuristic, [obligation_candidate/1,
                      handle_reprove/2,
                      reprove_exhausted/0,
                      init_state/0,
                      cleanup_state/0]).


% =============================================================================
%  Obligation candidate filtering (domain hook for prover)
% =============================================================================

%! heuristic:obligation_candidate(+Literal)
%
% Domain hook: succeeds when Literal is eligible for proof obligations.
% Only install, update, downgrade, and reinstall actions generate
% obligations; constraints, downloads, and other action types do not.

obligation_candidate(_Repo://_Entry:Action?{_Ctx}) :-
  ( Action == install ; Action == update ; Action == downgrade ; Action == reinstall ),
  !.
obligation_candidate(_Repo://_Entry:Action) :-
  ( Action == install ; Action == update ; Action == downgrade ; Action == reinstall ),
  !.


% =============================================================================
%  Reprove hooks
% =============================================================================

%! heuristic:handle_reprove(+Info, -Added)
%
% Process a reprove conflict. Delegates domain conflict processing
% to candidate:add_cn_domain_rejects/5 and candidate:add_cn_domain_origin_rejects/2.

handle_reprove(cn_domain(C, N, Domain, Candidates, Reasons), Added) :-
  candidate:add_cn_domain_rejects(C, N, Domain, Candidates, AddedDomain),
  ( Candidates == [] ->
      candidate:add_cn_domain_origin_rejects(Reasons, AddedOrigins)
  ; AddedOrigins = false
  ),
  ( AddedDomain == true -> Added = true
  ; AddedOrigins == true -> Added = true
  ; Added = false
  ),
  !.
handle_reprove(_, false).


%! heuristic:reprove_exhausted
%
% Called when reprove retries are exhausted. Clears the reject
% map so the final prove runs clean.

reprove_exhausted :-
  retractall(memo:cn_domain_reject_(_, _)),
  !.


%! heuristic:init_state
%
% Save domain state at the start of a reprove-enabled proof.
% Saves current state and installs fresh empty globals.

init_state :-
  ( nb_current(prover_reprove_enabled, OldEnabled) -> true ; OldEnabled = '$absent' ),
  findall(C-N-V, memo:selected_cn_snap_(C, N, V), SavedSnap),
  findall(C-N-V, memo:blocked_cn_source_snap_(C, N, V), SavedBlocked),
  findall(K-V, memo:cn_domain_reject_(K, V), SavedRejects),
  nb_setval(rules_reprove_saved_state, state(OldEnabled, SavedSnap, SavedRejects, SavedBlocked)),
  nb_setval(prover_reprove_enabled, true),
  retractall(memo:cn_domain_reject_(_, _)),
  retractall(memo:selected_cn_snap_(_, _, _)),
  retractall(memo:blocked_cn_source_snap_(_, _, _)),
  !.


%! heuristic:cleanup_state
%
% Restore domain state saved by init_state/0.

cleanup_state :-
  ( nb_current(rules_reprove_saved_state, state(OldEnabled, SavedSnap, SavedRejects, SavedBlocked)) ->
      ( OldEnabled == '$absent' -> nb_delete(prover_reprove_enabled) ; nb_setval(prover_reprove_enabled, OldEnabled) ),
      retractall(memo:cn_domain_reject_(_, _)),
      retractall(memo:selected_cn_snap_(_, _, _)),
      retractall(memo:blocked_cn_source_snap_(_, _, _)),
      forall(member(C-N-V, SavedSnap), assertz(memo:selected_cn_snap_(C, N, V))),
      forall(member(C-N-V, SavedBlocked), assertz(memo:blocked_cn_source_snap_(C, N, V))),
      forall(member(K-V, SavedRejects), assertz(memo:cn_domain_reject_(K, V))),
      nb_delete(rules_reprove_saved_state)
  ; true
  ),
  !.
