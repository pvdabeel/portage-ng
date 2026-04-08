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

== Additional prover hooks ==

  * heuristic:constraint_unify_hook/4
    Domain-specific constraint merge for cn_domain keys.

  * heuristic:constraint_guard/2
    Consistency guard called after each constraint merge.

  * heuristic:cycle_benign/2
    Classifies dependency cycles as benign or structural.

  * heuristic:proof_obligation_key/3,4
    Computes hook keys for PDEPEND expansion.

  * heuristic:proof_obligation/4
    Produces extra PDEPEND goals after proving a literal.

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

heuristic:obligation_candidate(_Repo://_Entry:Action?{_Ctx}) :-
  ( Action == install ; Action == update ; Action == downgrade ; Action == reinstall ),
  !.
heuristic:obligation_candidate(_Repo://_Entry:Action) :-
  ( Action == install ; Action == update ; Action == downgrade ; Action == reinstall ),
  !.


% =============================================================================
%  Reprove hooks
% =============================================================================

%! heuristic:handle_reprove(+Info, -Added)
%
% Process a reprove conflict. Delegates domain conflict processing
% to candidate:add_cn_domain_rejects/5 and candidate:add_cn_domain_origin_rejects/2.

heuristic:handle_reprove(cn_domain(C, N, Domain, Candidates, Reasons), Added) :-
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
heuristic:handle_reprove(_, false).


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


% =============================================================================
%  Constraint unification hook (domain hook called by prover)
% =============================================================================

%! heuristic:constraint_unify_hook(+Key, +Value, +Constraints, -NewConstraints)
%
% Domain-specific constraint merge for `cn_domain(C,N,Slot)` keys:
% normalises the incoming version domain and intersects it with any
% existing domain via `version_domain:domain_meet/3`.  Per-slot keys
% prevent cross-slot domain collisions for multi-slot packages.

heuristic:constraint_unify_hook(cn_domain(C,N,Slot), DomainDelta0, Constraints, NewConstraints) :-
  !,
  version_domain:domain_normalize(DomainDelta0, DomainDelta),
  ( get_assoc(cn_domain(C,N,Slot), Constraints, CurrentDomain, Constraints1, CurrentDomain) ->
      ( version_domain:domain_meet(CurrentDomain, DomainDelta, MergedDomain) ->
          put_assoc(cn_domain(C,N,Slot), Constraints1, MergedDomain, NewConstraints)
      ; ( \+ memo:slot_conflict_(C, N, _) ->
            assertz(memo:slot_conflict_(C, N,
                        domain_conflict(CurrentDomain, DomainDelta)))
        ; true
        ),
        fail
      )
  ; put_assoc(cn_domain(C,N,Slot), Constraints, DomainDelta, NewConstraints)
  ).


% =============================================================================
%  Constraint guard (domain hook called by prover)
% =============================================================================

%! heuristic:constraint_guard(+ConstraintLit, +Constraints)
%
% Called by the prover after merging any constraint literal. Must succeed
% for consistent constraint stores, fail to force backtracking.

heuristic:constraint_guard(constraint(cn_domain(C,N,Slot):{Domain0}), Constraints) :-
  !,
  ( get_assoc(cn_domain(C,N,Slot), Constraints, Domain) -> true ; Domain = Domain0 ),
  ( version_domain:domain_inconsistent(Domain) ->
      get_assoc(selected_cn_allow_multislot(C,N), Constraints, _AllowMultiSlot)
  ; ( get_assoc(selected_cn(C,N), Constraints, ordset(Selected)) ->
      filter_selected_by_slot(Slot, Selected, SlotSelected),
      ( SlotSelected == [] -> true
      ; candidate:selected_cn_domain_compatible_or_reprove(C, N, Domain, SlotSelected, Constraints)
      )
  ; true
    )
  ).
heuristic:constraint_guard(constraint(blocked_cn(C,N):{ordset(Specs)}), Constraints) :-
  !,
  ( get_assoc(selected_cn(C,N), Constraints, ordset(Selected)) ->
      candidate:selected_cn_not_blocked_or_reprove(C, N, Specs, Selected, Constraints)
  ; true
  ).
heuristic:constraint_guard(constraint(blocked_cn_source(C,N):{ordset(Sources)}), _Constraints) :-
  !,
  candidate:record_blocked_cn_source_snapshot(C, N, Sources).
heuristic:constraint_guard(constraint(selected_cn_allow_multislot(_C,_N):{_}), _Constraints) :-
  !.
heuristic:constraint_guard(constraint(selected_cn(C,N):{ordset(_SelectedNew)}), Constraints) :-
  !,
  get_assoc(selected_cn(C,N), Constraints, ordset(SelectedMerged)),
  candidate:record_selected_cn_snapshot(C, N, SelectedMerged),
  ( candidate:cn_domain_for_slot(C, N, any, Constraints, Domain) ->
      candidate:selected_cn_domain_compatible_or_reprove(C, N, Domain, SelectedMerged, Constraints)
  ; true
  ),
  candidate:selected_cn_unique_or_reprove(C, N, SelectedMerged, Constraints),
  ( get_assoc(blocked_cn(C,N), Constraints, ordset(Specs)) ->
      candidate:selected_cn_not_blocked_or_reprove(C, N, Specs, SelectedMerged, Constraints)
  ; true
  ).
heuristic:constraint_guard(_Other, _Constraints).


% -----------------------------------------------------------------------------
%  Slot filtering for per-slot domain checks
% -----------------------------------------------------------------------------

%! heuristic:filter_selected_by_slot(+Slot, +Selected, -Filtered)
%
% When Slot is `any`, returns all Selected unchanged.  Otherwise keeps
% only entries whose slot metadata matches Slot.

heuristic:filter_selected_by_slot(any, Selected, Selected) :- !.
heuristic:filter_selected_by_slot(Slot, Selected, Filtered) :-
  include(selected_on_slot_(Slot), Selected, Filtered).

heuristic:selected_on_slot_(Slot, selected(_Repo, _Entry, _Act, _Ver, SlotMeta)) :-
  candidate:selected_cn_slot_key_(SlotMeta, Slot).


% =============================================================================
%  Benign cycle classification (domain hook called by prover)
% =============================================================================

%! heuristic:cycle_benign(+Lit, +CyclePath)
%
% Succeeds if the cycle at Lit is benign.  Dependency-level literals
% are always benign.  Cross-package cycles are benign when any step
% in the CyclePath is a :run entry (RDEPEND-mediated).

heuristic:cycle_benign(Lit, _CyclePath) :-
    ( Lit = grouped_package_dependency(_,_,_,_):_
    ; Lit = grouped_package_dependency(_,_,_):_
    ; Lit = package_dependency(_,_,_,_,_,_,_,_):_
    ), !.

heuristic:cycle_benign(_Lit, CyclePath) :-
    member(Entry, CyclePath),
    Entry = _:run,
    !.


% =============================================================================
%  Proof obligations: PDEPEND expansion (domain hook called by prover)
% =============================================================================

%! heuristic:proof_obligation_key(+Literal, +Model, -HookKey) is semidet.
%
% Fast path: compute HookKey without dependency-model work.

heuristic:proof_obligation_key(Repo://Entry:Action?{_Ctx}, Model, HookKey) :-
  ( Action == install ; Action == update ; Action == downgrade ; Action == reinstall ),
  !,
  AnchorCore = (Repo://Entry:Action),
  ( cache:entry_metadata(Repo, Entry, pdepend, _) ->
      ( get_assoc(AnchorCore, Model, AnchorCtx) -> true ; AnchorCtx = [] ),
      use:context_build_with_use_state(AnchorCtx, B),
      HookKey = pdepend(AnchorCore, B)
  ; HookKey = pdepend_none(AnchorCore)
  ).
heuristic:proof_obligation_key(Repo://Entry:Action, Model, HookKey) :-
  ( Action == install ; Action == update ; Action == downgrade ; Action == reinstall ),
  !,
  AnchorCore = (Repo://Entry:Action),
  ( cache:entry_metadata(Repo, Entry, pdepend, _) ->
      ( get_assoc(AnchorCore, Model, AnchorCtx) -> true ; AnchorCtx = [] ),
      use:context_build_with_use_state(AnchorCtx, B),
      HookKey = pdepend(AnchorCore, B)
  ; HookKey = pdepend_none(AnchorCore)
  ).


%! heuristic:proof_obligation_key(+Literal, +Model, -HookKey, -NeedsFullHook) is semidet.
%
% Extended fast path: also reports whether the full hook can produce
% any extra literals at all.

heuristic:proof_obligation_key(Repo://Entry:Action?{_Ctx}, Model, HookKey, NeedsFullHook) :-
  ( Action == install ; Action == update ; Action == downgrade ; Action == reinstall ),
  !,
  AnchorCore = (Repo://Entry:Action),
  ( heuristic:proof_obligation_applicable(Repo://Entry:Action) ->
      ( cache:entry_metadata(Repo, Entry, pdepend, _) ->
          NeedsFullHook = true,
          ( get_assoc(AnchorCore, Model, AnchorCtx) -> true ; AnchorCtx = [] ),
          use:context_build_with_use_state(AnchorCtx, B),
          HookKey = pdepend(AnchorCore, B)
      ; NeedsFullHook = false,
        HookKey = pdepend_none(AnchorCore)
      )
  ; NeedsFullHook = false,
    HookKey = pdepend_none(AnchorCore)
  ).
heuristic:proof_obligation_key(Repo://Entry:Action, Model, HookKey, NeedsFullHook) :-
  ( Action == install ; Action == update ; Action == downgrade ; Action == reinstall ),
  !,
  AnchorCore = (Repo://Entry:Action),
  ( heuristic:proof_obligation_applicable(Repo://Entry:Action) ->
      ( cache:entry_metadata(Repo, Entry, pdepend, _) ->
          NeedsFullHook = true,
          ( get_assoc(AnchorCore, Model, AnchorCtx) -> true ; AnchorCtx = [] ),
          use:context_build_with_use_state(AnchorCtx, B),
          HookKey = pdepend(AnchorCore, B)
      ; NeedsFullHook = false,
        HookKey = pdepend_none(AnchorCore)
      )
  ; NeedsFullHook = false,
    HookKey = pdepend_none(AnchorCore)
  ).


%! heuristic:proof_obligation_applicable(+ActionLiteral) is semidet.
%
% True if the action represents an actual merge transaction.

heuristic:proof_obligation_applicable(_Repo://_Entry:reinstall) :- !, true.
heuristic:proof_obligation_applicable(_Repo://_Entry:update) :- !, true.
heuristic:proof_obligation_applicable(_Repo://_Entry:downgrade) :- !, true.
heuristic:proof_obligation_applicable(Repo://Entry:install) :-
  ( preference:flag(emptytree) ->
      true
  ; \+ query:search(installed(true), Repo://Entry) ->
      true
  ; false
  ),
  !.


%! heuristic:proof_obligation(+Literal, +Model, -HookKey, -ExtraLits)
%
% Produces extra PDEPEND goals after proving a literal.

heuristic:proof_obligation(Repo://Entry:Action?{_Ctx}, Model, HookKey, ExtraLits) :-
  ( Action == install ; Action == update ; Action == downgrade ; Action == reinstall ),
  !,
  sampler:hook_maybe_sample(
    ( AnchorCore = (Repo://Entry:Action),
      ( cache:entry_metadata(Repo, Entry, pdepend, _) ->
          flag(po_has_extra, HP0, HP0+1),
          ( get_assoc(AnchorCore, Model, AnchorCtx) -> true ; AnchorCtx = [] ),
          use:context_build_with_use_state(AnchorCtx, B),
          HookKey = pdepend(AnchorCore, B),
          ModelKey = [build_with_use:B],
          query:memoized_search(model(dependency(Pdeps0, pdepend)):config?{ModelKey}, Repo://Entry),
          dependency:add_self_to_dep_contexts(Repo://Entry, Pdeps0, Pdeps1),
          featureterm:drop_build_with_use_from_dep_contexts(Pdeps1, Pdeps2),
          featureterm:add_after_only_to_dep_contexts(AnchorCore, Pdeps2, ExtraLits)
      ; flag(po_no_extra, NP0, NP0+1),
        HookKey = pdepend_none(AnchorCore),
        ExtraLits = []
      )
    )
  ).
heuristic:proof_obligation(Repo://Entry:Action, Model, HookKey, ExtraLits) :-
  ( Action == install ; Action == update ; Action == downgrade ; Action == reinstall ),
  !,
  sampler:hook_maybe_sample(
    ( AnchorCore = (Repo://Entry:Action),
      ( cache:entry_metadata(Repo, Entry, pdepend, _) ->
          flag(po_has_extra, HP0, HP0+1),
          ( get_assoc(AnchorCore, Model, AnchorCtx) -> true ; AnchorCtx = [] ),
          use:context_build_with_use_state(AnchorCtx, B),
          HookKey = pdepend(AnchorCore, B),
          ModelKey = [build_with_use:B],
          query:memoized_search(model(dependency(Pdeps0, pdepend)):config?{ModelKey}, Repo://Entry),
          dependency:add_self_to_dep_contexts(Repo://Entry, Pdeps0, Pdeps1),
          featureterm:drop_build_with_use_from_dep_contexts(Pdeps1, Pdeps2),
          featureterm:add_after_only_to_dep_contexts(AnchorCore, Pdeps2, ExtraLits)
      ; flag(po_no_extra, NP0, NP0+1),
        HookKey = pdepend_none(AnchorCore),
        ExtraLits = []
      )
    )
  ).


% =============================================================================
%  Debugging helpers
% =============================================================================

%! heuristic:profile_run_entry(+RepoEntry, +Context, -Report)
%
% Times major sub-steps of the :run rule for one package.

heuristic:profile_run_entry(RepoEntry, Context, report(RepoEntry, Steps)) :-
  heuristic:step_time(mask_check,
                  ( query:search(masked(true), RepoEntry) -> true ; true ),
                  S1),
  heuristic:step_time(required_use_model,
                  ( findall(Item,(member(build_with_use:Inner, Context), member(Item,Inner)), B),
                    ( memberchk(required_use:R, Context) -> true ; true ),
                    query:search(model(_Model,required_use(R),build_with_use(B)), RepoEntry)
                  ),
                  S2),
  heuristic:step_time(dep_model_run_config,
                  ( query:memoized_search(model(dependency(_MergedDeps0,run)):config?{[]}, RepoEntry) ),
                  S3),
  Steps = [S1,S2,S3].


heuristic:step_time(Label, Goal, step(Label, ms(TimeMs), inferences(Inf), result(Result))) :-
  statistics(walltime, [T0,_]),
  statistics(inferences, I0),
  ( catch(call_with_time_limit(10, (Goal -> Result = ok ; Result = fail)),
          time_limit_exceeded,
          Result = timeout)
  ),
  statistics(walltime, [T1,_]),
  statistics(inferences, I1),
  TimeMs is T1 - T0,
  Inf is I1 - I0.