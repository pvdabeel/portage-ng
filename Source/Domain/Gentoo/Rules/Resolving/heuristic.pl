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

  * heuristic:ctx_equivalent/2
    Decides when two literal contexts are equivalent
    (used by prover:proven/3 and the union early-out).

  * heuristic:should_union_ctx/1
    Decides which literals participate in cross-sibling
    Ctx union when re-requested with a different context
    (used by the context-changed branch of prove_recursive).

  * heuristic:cycle_benign/2
    Classifies dependency cycles as benign or structural.

  * heuristic:proof_obligation_key/3,4
    Computes hook keys for PDEPEND / ABI rebuild expansion.

  * heuristic:proof_obligation/4
    Produces extra PDEPEND goals and sub-slot ABI rebuild
    obligations (abirebuild:obligations/3) after proving a literal.

== Partial restart hooks (non-chronological backtracking) ==

  * heuristic:begin_pass/1
    Per-pass state clearing, scoped to fresh vs resumed passes.

  * heuristic:restart_seed/2
    Marks the model literals a deferred conflict invalidates.

  * heuristic:restart_obligation_head/2
    Maps an obligation-done key to its anchor literal.

  * heuristic:restart_constraint_scope/3
    Derives the constraint-pruning scope from the affected set.

  * heuristic:restart_drop_constraint/2
    Classifies which accumulated constraints to drop on restart.

*/

:- module(heuristic, [obligation_candidate/1,
                      handle_reprove/2,
                      reprove_exhausted/0,
                      init_state/0,
                      cleanup_state/0]).

:- use_module(library(assoc), [empty_assoc/1]).

% =============================================================================
%  HEURISTIC declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Obligation candidate filtering (domain hook for prover)
% -----------------------------------------------------------------------------

%! heuristic:merge_action(+Action) is semidet.
%
% First-argument-indexed facts enumerating the actions that represent a
% merge transaction and therefore participate in proof obligations
% (PDEPEND expansion). Action must be bound.

heuristic:merge_action(install).
heuristic:merge_action(update).
heuristic:merge_action(downgrade).
heuristic:merge_action(reinstall).


%! heuristic:strip_ctx(+Literal, -Core) is det.
%
% Normalize an action literal by dropping `?{Context}` proof-context
% annotations, yielding the bare core (e.g. `Repo://Entry:Action`).
% Thin wrapper over `prover:canon_literal/3` so the literal-shape table
% lives in one place. Context may attach to the action
% (`Repo://Entry:Action?{Ctx}`) rather than only at the top level
% (`Core?{Ctx}`); without this, PDEPEND proof obligations silently skip
% every context-carrying merge literal (portage-ng#100).
%
% Nested double-context forms can make `canon_literal/3` fail when
% `sampler:ctx_union/3` rejects a USE conflict; the fallback still peels
% Core so this predicate stays det for obligation filtering.

heuristic:strip_ctx(Literal, Core) :-
  prover:canon_literal(Literal, Core, _),
  !.
heuristic:strip_ctx(Literal, Core) :-
  heuristic:strip_ctx_nested_core_(Literal, Core),
  !.

% Only the nested double-`?{Context}` shapes where canon_literal may fail
% after matching (ctx_union conflict). All other shapes are covered by
% canon_literal/3 above.
heuristic:strip_ctx_nested_core_(R://(L:A?{_})?{_}, R://L:A) :- !.
heuristic:strip_ctx_nested_core_(R://(L?{_})?{_}, R://L) :- !.
heuristic:strip_ctx_nested_core_(Literal, Literal).


%! heuristic:obligation_candidate(+Literal)
%
% Domain hook: succeeds when Literal is eligible for proof obligations.
% Only install, update, downgrade, and reinstall actions generate
% obligations; constraints, downloads, and other action types do not.

heuristic:obligation_candidate(Literal) :-
  heuristic:strip_ctx(Literal, _Repo://_Entry:Action),
  heuristic:merge_action(Action),
  !.


% -----------------------------------------------------------------------------
%  Reprove hooks
% -----------------------------------------------------------------------------

%! heuristic:handle_reprove(+Info, -Added)
%
% Process a reprove conflict. Delegates domain conflict processing
% to cnselect:add_cn_domain_rejects/5 and cnselect:add_cn_domain_origin_rejects/2.

heuristic:handle_reprove(cn_domain(C, N, Domain, Candidates, Reasons), Added) :-
  cnselect:add_cn_domain_rejects(C, N, Domain, Candidates, AddedDomain),
  ( Candidates == [] ->
      cnselect:add_cn_domain_origin_rejects(Reasons, AddedOrigins)
  ; AddedOrigins = false
  ),
  ( AddedDomain == true -> Added = true
  ; AddedOrigins == true -> Added = true
  ; Added = false
  ),
  choicelog:clog_emit(reject, recorded, reject(C, N, Domain, Candidates, Reasons)),
  choicelog:clog_emit(reprove, recorded, reprove(cn_domain(C, N, Domain, Candidates, Reasons))),
  !.
heuristic:handle_reprove(bwu_force_flush(Pending), true) :-
  % portage-ng#91 sub-mechanism B / portage-ng#94 / portage-ng#121:
  % end-of-pass batched flush of the USE forces learned during the pass that
  % just completed (see heuristic:reprove_pending/1). The forces are already
  % in the learned constraint store (use:maybe_force_shared_dep_use/3,
  % use:maybe_follow_equality_overturns/4); confirming progress
  % makes the bounded reprove loop run one clean re-proof with all of them
  % applied from the start. Each flush corresponds to at least one
  % prover:learn with Added==true, so the loop terminates once a pass learns
  % nothing new.
  choicelog:clog_emit(reprove, recorded, reprove(bwu_force_flush(Pending))),
  !.
heuristic:handle_reprove(Info, false) :-
  choicelog:clog_emit(reprove, recorded, reprove(Info)),
  !.


%! heuristic:reprove_pending(-Info)
%
% Domain hook called by the prover after a proof pass COMPLETES
% (prover:deferred_reprove_pending/3). Succeeds when the pass deferred
% at least one conflict that warrants a re-proof; Info is passed to
% heuristic:handle_reprove/2 exactly like a thrown prover_reprove(Info).
%
% Two deferred conflict classes travel this channel, both recorded as
% pending USE forces instead of aborting the pass, and both flushed here
% as a single batched reprove: the shared-dep HARD-USE force on a
% provider (portage-ng#94, use:maybe_force_shared_dep_use/3) and the
% consumer-side equality follow (portage-ng#121,
% use:maybe_follow_equality_overturns/4).

heuristic:reprove_pending(bwu_force_flush(Pending)) :-
  use:deferred_use_pending(Pending).


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


% -----------------------------------------------------------------------------
%  Partial restart hooks (non-chronological backtracking, domain side)
% -----------------------------------------------------------------------------

%! heuristic:begin_pass(+Kind)
%
% Per-pass state clearing, called by prover:begin_pass/0 at the start of
% every prove_once/9 pass. Kind is `fresh` (first attempt or full
% restart) or `resume` (partial restart from pruned artifacts).
%
% Both kinds clear the same per-pass cross-dep memos. This is safe for
% a resumed pass because every contributor to a forced provider's
% candidate_bwu_ accumulation is a direct consumer of that provider,
% hence a trigger-dependent, hence in the affected set: all of them
% re-derive on the resumed pass and re-contribute their bracketed-USE
% state in the same relative order as a full restart. Keeping the
% completed pass's accumulation instead was tried and diverged in the
% genuinely-conflicted case (enable/disable USE conflicts surfaced as
% unsatisfied-constraint assumptions rather than the REQUIRED_USE
% violations a full restart converges to, because the provider saw the
% whole conflicting accumulation at once instead of progressively).

heuristic:begin_pass(fresh) :-
  use:clear_bwu_cross_dep_memos.
heuristic:begin_pass(resume) :-
  use:clear_bwu_cross_dep_memos.


%! heuristic:restart_seed(+Info, +Core) is semidet
%
% Marks the model literal cores invalidated by a deferred conflict.
% For the shared-dep USE-force flush every action literal (install,
% run, download, ...) of a forced (C,N) provider is a seed: its
% committed build_with_use state predates the force, so the literal
% (and, through the prover's dependents-closure, everything that could
% observe it) must re-derive with the force applied. Contexts are
% stripped first: an assumed action literal keeps its `?{Context}`
% inside the `assumed/1` wrapper (`assumed(Repo://E:install?{[...]})`),
% and matching the bare shape alone let those degraded literals survive
% the flush -- they then stayed in the final model as a stale
% "model unavailable" assumption for a package the re-proof planned
% properly.
%
% An equality follow (#121) seeds both ends of the edge: the consumer
% that has to change, and the provider whose dependency literal was
% resolved -- or assumed -- against the consumer's old value.
%
% Grouped-dependency literals naming a forced (C,N) are seeds as well.
% Proven ones are already reached through the provider's trigger edges,
% but ASSUMED ones (domain assumptions from a failed resolution) are
% not: their consumers depend on the `assumed(grouped_package_dependency
% (...))` literal, and no trigger edge links the provider's action
% literals to it. Those failed resolutions read the learned bwu_force
% store, so the flush invalidates them (and, through the closure, their
% consumers) even though the provider itself never proved.

heuristic:restart_seed(bwu_force_flush(Pending), Lit0) :-
  heuristic:strip_ctx(Lit0, Lit),
  ( Lit = Repo://Entry:_Action ->
      cache:ordered_entry(Repo, Entry, C, N, _)
  ; Lit = grouped_package_dependency(_Strength, C, N, _Deps):_Action1 ->
      true
  ; Lit = grouped_package_dependency(C, N, _Deps2):_Action2 ->
      true
  ; fail
  ),
  heuristic:pending_use_force_cn(Pending, C, N).


%! heuristic:pending_use_force_cn(+Pending, +C, +N) is semidet
%
% True when the flush carries a USE force involving (C,N): a shared-dep
% HARD force on it as a provider (#94), or an equality follow on it as
% the consumer that has to change, or on it as the provider whose
% dependency literal was resolved against the consumer's old value
% (#121). In every case its committed state predates the force.

heuristic:pending_use_force_cn(Pending, C, N) :-
  ( memberchk(bwu_force(C, N, _), Pending) -> true
  ; memberchk(eq_follow(C, N, _, _), Pending) -> true
  ; memberchk(eq_follow(_, _, _, provider(C, N)), Pending)
  ).


%! heuristic:restart_obligation_head(+ObligationKey, -Core) is semidet
%
% Maps an obligation_done key (see heuristic:proof_obligation/4) to the
% anchor literal that produced it, so the prover can invalidate the
% marker when the anchor is affected by a partial restart and PDEPEND
% expansion re-fires on the re-proof.

heuristic:restart_obligation_head(pdepend(AnchorCore, _B), AnchorCore).
heuristic:restart_obligation_head(pdepend_none(AnchorCore), AnchorCore).


%! heuristic:restart_constraint_scope(+Info, +Affected, -Scope)
%
% Derives the constraint-pruning scope from the affected-literal set of
% a partial restart: the set of affected Repo://Entry ids and their
% (C,N) pairs. Computed once per restart; consulted per constraint key
% by heuristic:restart_drop_constraint/2.

heuristic:restart_constraint_scope(_Info, Affected, scope(Entries, CNs)) :-
  assoc_to_keys(Affected, Keys),
  heuristic:restart_scope_pairs(Keys, Entries0, CNs0),
  sort(Entries0, Entries),
  sort(CNs0, CNs).


%! heuristic:restart_scope_pairs(+Keys, -Entries, -CNs)
%
% Collect Repo://Entry ids and C-N pairs from the affected keys that
% are action literals; other keys (grouped deps, constraints) add
% nothing. Keys are unwrapped first: cycle-break and domain-assumption
% keys wrap the action literal in assumed/1 (possibly with an embedded
% `?{Context}`), naf/1 wraps blocker literals.

heuristic:restart_scope_pairs([], [], []).
heuristic:restart_scope_pairs([Key0|Keys], Entries, CNs) :-
  heuristic:restart_scope_core(Key0, Key),
  ( Key = Repo://Entry:_Action ->
      Entries = [Repo://Entry|Entries1],
      ( cache:ordered_entry(Repo, Entry, C, N, _) ->
          CNs = [C-N|CNs1]
      ; CNs = CNs1
      )
  ; Entries = Entries1,
    CNs = CNs1
  ),
  heuristic:restart_scope_pairs(Keys, Entries1, CNs1).


%! heuristic:restart_scope_core(+Key, -Core) is det
%
% Recursively strip assumed/1, naf/1 and `?{Context}` wrappers from an
% affected-set key, yielding the bare literal core.

heuristic:restart_scope_core(assumed(Key0), Core) :- !, heuristic:restart_scope_core(Key0, Core).
heuristic:restart_scope_core(naf(Key0), Core)     :- !, heuristic:restart_scope_core(Key0, Core).
heuristic:restart_scope_core(Key0?{_Ctx}, Core)   :- !, heuristic:restart_scope_core(Key0, Core).
heuristic:restart_scope_core(Core, Core).


%! heuristic:restart_drop_constraint(+Scope, +ConstraintKey) is semidet
%
% Classifies which accumulated constraint keys belong to the affected
% region of a partial restart and must be dropped (they are re-emitted
% verbatim or re-derived when the affected literals re-prove):
%
%   - use(Repo://E): the REQUIRED_USE model of an affected entry; the
%     forced flags can change it, and stale entries would be unioned
%     with (and can contradict) the re-derived model.
%   - slot(C,N,S) / selected_cn(C,N): the version selection records of
%     an affected (C,N); re-established by the re-proof.
%
% Everything else is kept: cn_domain domains are monotone narrowings
% that stay valid, and blocker constraints are unrelated to USE forces.

heuristic:restart_drop_constraint(scope(Entries, _CNs), use(RepoEntry)) :-
  ord_memberchk(RepoEntry, Entries),
  !.
heuristic:restart_drop_constraint(scope(_Entries, CNs), slot(C, N, _S)) :-
  ord_memberchk(C-N, CNs),
  !.
heuristic:restart_drop_constraint(scope(_Entries, CNs), selected_cn(C, N)) :-
  ord_memberchk(C-N, CNs),
  !.


% -----------------------------------------------------------------------------
%  Constraint unification hook (domain hook called by prover)
% -----------------------------------------------------------------------------

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


% -----------------------------------------------------------------------------
%  Constraint guard (domain hook called by prover)
% -----------------------------------------------------------------------------

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
      ; cnselect:selected_cn_domain_compatible_or_reprove(C, N, Domain, SlotSelected, Constraints)
      )
  ; true
    )
  ).
heuristic:constraint_guard(constraint(blocked_cn(C,N):{ordset(Specs)}), Constraints) :-
  !,
  ( get_assoc(selected_cn(C,N), Constraints, ordset(Selected)) ->
      cnselect:selected_cn_not_blocked_or_reprove(C, N, Specs, Selected, Constraints)
  ; true
  ).
heuristic:constraint_guard(constraint(blocked_cn_source(C,N):{ordset(Sources)}), _Constraints) :-
  !,
  cnselect:record_blocked_cn_source_snapshot(C, N, Sources).
heuristic:constraint_guard(constraint(selected_cn_allow_multislot(_C,_N):{_}), _Constraints) :-
  !.
heuristic:constraint_guard(constraint(selected_cn(C,N):{ordset(_SelectedNew)}), Constraints) :-
  !,
  get_assoc(selected_cn(C,N), Constraints, ordset(SelectedMerged)),
  cnselect:record_selected_cn_snapshot(C, N, SelectedMerged),
  ( cnselect:cn_domain_for_slot(C, N, any, Constraints, Domain) ->
      cnselect:selected_cn_domain_compatible_or_reprove(C, N, Domain, SelectedMerged, Constraints)
  ; true
  ),
  cnselect:selected_cn_unique_or_reprove(C, N, SelectedMerged, Constraints),
  ( get_assoc(blocked_cn(C,N), Constraints, ordset(Specs)) ->
      cnselect:selected_cn_not_blocked_or_reprove(C, N, Specs, SelectedMerged, Constraints)
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
  cnselect:selected_cn_slot_key_(SlotMeta, Slot).


% -----------------------------------------------------------------------------
%  Proof-context equivalence and union-eligibility (domain hooks)
% -----------------------------------------------------------------------------
%
% The prover engine calls these hooks to decide:
%
%  * `heuristic:ctx_equivalent/2` — when may two `?{Context}` lists be
%    treated as the same? Used by `prover:proven/3` and by the
%    post-union short-circuit in the proof-context-changed branch of
%    `prove_recursive/9` and `prove_model/6`.
%
%  * `heuristic:should_union_ctx/1` — for which literals should the
%    prover *merge* (rather than overwrite) per-call-site proof contexts
%    when the same literal is re-requested under a different Ctx?
%    Used by the proof-context-changed branch.
%
% Both are pure predicates on Gentoo-specific literal / proof-context
% shape. The prover stays domain-agnostic and falls back to safe
% defaults when these hooks are absent.

%! heuristic:ctx_equivalent(+Ctx1, +Ctx2) is semidet.
%
% Two proof-context lists are equivalent iff they have the same
% semantic key, where the semantic key is the pair of
% required_use (RU) and build_with_use (BWU) values carried in
% the `?{Context}` list. Other proof-context items (provenance such as
% `self/1`, suggestion tags, domain reasons, etc.) are
% intentionally ignored: they describe how the literal was
% reached, not what is being proven.

heuristic:ctx_equivalent(C1, C2) :-
  heuristic:ctx_sem_key(C1, K),
  heuristic:ctx_sem_key(C2, K).

heuristic:ctx_sem_key({}, key([], none)) :- !.
heuristic:ctx_sem_key(Ctx, key(RU, BWU)) :-
  is_list(Ctx),
  !,
  ( memberchk(required_use:RU0, Ctx) -> RU = RU0 ; RU = [] ),
  ( memberchk(build_with_use:BWU0, Ctx) -> BWU = BWU0 ; BWU = none ).
heuristic:ctx_sem_key(_Other, key([], none)).


%! heuristic:should_union_ctx(+Lit) is semidet.
%
% Succeeds only for ebuild action literals — terms shaped as
% `Repo://Entry:Action` (and their `assumed/1` variant). The body
% of an ebuild action rule depends on the per-package
% build_with_use state, which must be the *union* of the demands
% from every parent that pulled this ebuild in (e.g. cairo's
% `freetype[png]` and pango's `freetype[harfbuzz]` together
% produce `freetype[png,harfbuzz]`).
%
% Intermediate literals (`grouped_package_dependency/4`,
% `use_conditional_group/4`, `package_dependency/8`, …) carry
% per-edge plumbing context that is meaningful only relative to
% one immediate parent. Unioning across siblings would
% accumulate unrelated grandparent flags into nodes that have no
% IUSE for them and explode the regular_proof count across the
% whole subtree (e.g. `pkgconfig:install` ending up with
% `[deprecated,flexiblas,lapacke]` from grandparents).
%
% For those literals we want the prover's classical
% "overwrite stored Ctx" behaviour, so this hook simply does not
% match them and the prover falls through to the regular_proof
% branch.

heuristic:should_union_ctx(_Repo://_Entry:_Action) :- !.
heuristic:should_union_ctx(assumed(_Repo://_Entry:_Action)) :- !.


% -----------------------------------------------------------------------------
%  Benign cycle classification (domain hook called by prover)
% -----------------------------------------------------------------------------

%! heuristic:cycle_benign(+Lit, +CyclePath)
%
% Succeeds if the cycle at Lit is benign.  Dependency-level literals
% are always benign.  Cross-package cycles are benign when any step
% in the CyclePath is a :run entry (RDEPEND-mediated) or a :fetchonly
% entry (distfiles are independent; a fetch-only cycle is not a
% bootstrap failure). The :run/:fetchonly match is on the *grouped*
% dep (`grouped_package_dependency(...):run`), which is what actually
% sits on a real-package cycle path — `Repo://Entry:run` does not
% unify with `_:run` because `://` binds looser than `:`.

heuristic:cycle_benign(Lit, _CyclePath) :-
    ( Lit = grouped_package_dependency(_,_,_,_):_
    ; Lit = grouped_package_dependency(_,_,_):_
    ; Lit = package_dependency(_,_,_,_,_,_,_,_):_
    ), !.

heuristic:cycle_benign(_Lit, CyclePath) :-
    member(Entry, CyclePath),
    ( Entry = _:run
    ; Entry = _:fetchonly
    ),
    !.


% -----------------------------------------------------------------------------
%  Proof obligations: PDEPEND + ABI rebuild expansion (domain hook for prover)
% -----------------------------------------------------------------------------

%! heuristic:proof_obligation_key(+Literal, +Model, -HookKey) is semidet.
%
% Fast path: compute HookKey without dependency-model work.
% Literal is normalized via strip_ctx/2 so bare and `?{Context}`-carrying
% action literals share a single clause.

heuristic:proof_obligation_key(Literal, Model, HookKey) :-
  heuristic:strip_ctx(Literal, Repo://Entry:Action),
  heuristic:merge_action(Action),
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
% any extra literals at all (PDEPEND expansion and/or sub-slot ABI
% rebuilds). Literal is normalized via strip_ctx/2.

heuristic:proof_obligation_key(Literal, Model, HookKey, NeedsFullHook) :-
  heuristic:strip_ctx(Literal, Repo://Entry:Action),
  heuristic:merge_action(Action),
  !,
  AnchorCore = (Repo://Entry:Action),
  ( heuristic:proof_obligation_applicable(AnchorCore) ->
      ( cache:entry_metadata(Repo, Entry, pdepend, _) ->
          NeedsFullHook = true,
          ( get_assoc(AnchorCore, Model, AnchorCtx) -> true ; AnchorCtx = [] ),
          use:context_build_with_use_state(AnchorCtx, B),
          HookKey = pdepend(AnchorCore, B)
      ; HookKey = pdepend_none(AnchorCore),
        ( abirebuild:enabled,
          abirebuild:provider_change(Repo, Entry, _C, _N, _Slot, _Old, _New)
        -> NeedsFullHook = true
        ;  NeedsFullHook = false
        )
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
% Produces extra goals after proving a literal: PDEPEND expansion plus
% sub-slot ABI rebuild obligations (abirebuild:obligations/3, the
% prove-side of portage-ng#89). Literal is normalized via strip_ctx/2 so
% bare and `?{Context}`-carrying action literals share a single clause.

heuristic:proof_obligation(Literal, Model, HookKey, ExtraLits) :-
  heuristic:strip_ctx(Literal, Repo://Entry:Action),
  heuristic:merge_action(Action),
  !,
  sampler:hook_maybe_sample(
    ( AnchorCore = (Repo://Entry:Action),
      ( cache:entry_metadata(Repo, Entry, pdepend, _) ->
          flag(po_has_extra, HP0, HP0+1),
          ( get_assoc(AnchorCore, Model, AnchorCtx) -> true ; AnchorCtx = [] ),
          use:context_build_with_use_state(AnchorCtx, B),
          HookKey = pdepend(AnchorCore, B),
          ModelKey = [build_with_use:B],
          query:search(model(dependency(Pdeps0, pdepend)):config?{ModelKey}, Repo://Entry),
          dependency:add_self_to_dep_contexts(Repo://Entry, Pdeps0, Pdeps1),
          featureterm:drop_build_with_use_from_dep_contexts(Pdeps1, Pdeps2),
          featureterm:add_after_only_to_dep_contexts(AnchorCore, Pdeps2, PdependLits)
      ; flag(po_no_extra, NP0, NP0+1),
        HookKey = pdepend_none(AnchorCore),
        PdependLits = []
      ),
      abirebuild:obligations(AnchorCore, Model, RebuildLits),
      ( RebuildLits == []
      -> ExtraLits = PdependLits
      ;  append(PdependLits, RebuildLits, ExtraLits)
      )
    )
  ).


% -----------------------------------------------------------------------------
%  Debugging helpers
% -----------------------------------------------------------------------------

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
                  ( query:search(model(dependency(_MergedDeps0,run)):config?{[]}, RepoEntry) ),
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
