/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> HEURISTIC
Reprove state management, obligation candidate filtering, and
snapshot/rollback for the domain-specific side of the prover.

This module implements the reprove hooks that the prover calls
when conflict-driven learning triggers a retry. The prover is
domain-agnostic; it delegates to heuristic: for reprove handling
and obligation filtering.

== Predicates defined here ==

  * heuristic:handle_reprove(+Info, -Added)
    Called when a prover_reprove(Info) exception is caught.

  * heuristic:reprove_exhausted/0
    Called when reprove retries are exhausted.

  * heuristic:init_state/0
    Save domain state at the start of a reprove-enabled proof.

  * heuristic:cleanup_state/0
    Restore domain state saved by init_state/0.

  * heuristic:obligation_candidate(+Literal)
    Succeeds when Literal is eligible for proof obligations.

== Predicates defined in rules.pl ==

The prover also calls the following hooks, which are implemented
in rules.pl rather than here:

  * rules:constraint_unify_hook/4
  * rules:constraint_guard/2
  * rules:proof_obligation/4
  * rules:proof_obligation_key/3

*/

:- module(heuristic, [obligation_candidate/1,
                      handle_reprove/2,
                      reprove_exhausted/0,
                      init_state/0,
                      cleanup_state/0]).

:- use_module(library(assoc), [empty_assoc/1]).

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
  ( nb_current(memo_selected_cn_snap, SavedSnapAVL) -> true ; empty_assoc(SavedSnapAVL) ),
  ( nb_current(memo_blocked_cn_source_snap, SavedBlockedAVL) -> true ; empty_assoc(SavedBlockedAVL) ),
  findall(K-V, memo:cn_domain_reject_(K, V), SavedRejects),
  nb_setval(rules_reprove_saved_state, state(OldEnabled, SavedSnapAVL, SavedRejects, SavedBlockedAVL)),
  nb_setval(prover_reprove_enabled, true),
  retractall(memo:cn_domain_reject_(_, _)),
  empty_assoc(EmptyAVL),
  nb_setval(memo_selected_cn_snap, EmptyAVL),
  nb_setval(memo_blocked_cn_source_snap, EmptyAVL),
  !.


%! heuristic:cleanup_state
%
% Restore domain state saved by init_state/0.

cleanup_state :-
  ( nb_current(rules_reprove_saved_state, state(OldEnabled, SavedSnapAVL, SavedRejects, SavedBlockedAVL)) ->
      ( OldEnabled == '$absent' -> nb_delete(prover_reprove_enabled) ; nb_setval(prover_reprove_enabled, OldEnabled) ),
      retractall(memo:cn_domain_reject_(_, _)),
      nb_setval(memo_selected_cn_snap, SavedSnapAVL),
      nb_setval(memo_blocked_cn_source_snap, SavedBlockedAVL),
      forall(member(K-V, SavedRejects), assertz(memo:cn_domain_reject_(K, V))),
      nb_delete(rules_reprove_saved_state)
  ; true
  ),
  !.