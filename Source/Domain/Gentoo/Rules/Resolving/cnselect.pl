/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> CNSELECT
CN-consistency and learned-domain bookkeeping for the portage-ng
resolver.

Split out of candidate.pl (issue #64). Ensures that for a given
(Category, Name) pair only compatible candidates are selected across
the proof:

  * selected_cn reuse (selected_cn_candidate/5 and friends)
  * CN-domain reject map (bounded reprove retries)
  * selected_cn uniqueness / constraint enforcement, including the
    learned constraint refinement entry points
    (maybe_learn_parent_narrowing/4, maybe_learn_wildcard_domain/4)
  * cn_domain constraint construction (cn_domain_constraints/7,
    wildcard_cn_domain_constraints/2) and dep constraint inspectors
*/

:- module(cnselect, []).

% =============================================================================
%  CNSELECT declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Installed entry satisfaction
% -----------------------------------------------------------------------------

%! cnselect:installed_entry_satisfies_package_deps(+Action, +C, +N, +PackageDeps, +Installed)
%
% True if the installed entry satisfies all version constraints in
% PackageDeps for (C,N). Used as a fast-path guard in the grouped
% dependency rule to skip candidate selection when an installed package
% already satisfies the dependency.

cnselect:installed_entry_satisfies_package_deps(_Action, _C, _N, [], _Installed) :- !.
cnselect:installed_entry_satisfies_package_deps(_Action, C, N, PackageDeps, Repo://Id) :-
  cache:ordered_entry(Repo, Id, _, _, InstalledVer),
  forall(member(package_dependency(_,no,C,N,O,V,_,_), PackageDeps),
         preference:version_match(O, InstalledVer, V)).

%! cnselect:installed_entry_cn(+C, +N, -Repo, -Entry)
%
% Looks up an installed entry for (C,N) in the active VDB repository
% (knowledgebase:vdb_repository/1).

cnselect:installed_entry_cn(C, N, VdbRepo, Entry) :-
  knowledgebase:vdb_repository(VdbRepo),
  query:search([name(N),category(C),installed(true)], VdbRepo://Entry),
  !.


% -----------------------------------------------------------------------------
%  CN-consistency: pick already-selected entry when possible
% -----------------------------------------------------------------------------

%! cnselect:selected_cn_candidate(+Action, +C, +N, +Context, -RepoEntry)
%
% Enumerates previously-selected candidates for (C,N) from the context's
% `selected_cn` constraint. Filters by action compatibility and slot
% lock. Used to prefer reusing an existing choice over fresh enumeration.

cnselect:selected_cn_candidate(Action, C, N, Context, FoundRepo://Candidate) :-
  memberchk(constraint(selected_cn(C,N):{ordset(SelectedSet)}), Context),
  member(selected(FoundRepo, Candidate, ActSel, _CandVer, SelSlotMeta), SelectedSet),
  ( (Action == install ; Action == run),
    (ActSel == install ; ActSel == run)
  -> true
  ; ActSel == Action
  ),
  ( memberchk(slot(C,N,SsLock0):{_}, Context) ->
      slotmeta:canon_any_same_slot_meta(SsLock0, SsLock),
      slotmeta:canon_any_same_slot_meta(SelSlotMeta, SsSel),
      SsSel == SsLock
  ; true
  ),
  cache:ordered_entry(FoundRepo, Candidate, C, N, _),
  \+ preference:masked(FoundRepo://Candidate).

%! cnselect:selected_cn_candidate_compatible(+Action, +C, +N, +SlotReq, +PackageDeps, +Context, -RepoEntry)
%
% Like selected_cn_candidate/5 but also verifies slot and version constraints.

cnselect:selected_cn_candidate_compatible(Action, C, N, SlotReq, PackageDeps, Context, FoundRepo://Candidate) :-
  selected_cn_candidate(Action, C, N, Context, FoundRepo://Candidate),
  slotmeta:query_search_slot_constraint(SlotReq, FoundRepo://Candidate, _),
  grouped_dep_candidate_satisfies_constraints(Action, C, N, PackageDeps, Context, FoundRepo://Candidate).

%! cnselect:selected_cn_rejected_candidates(+Action, +C, +N, +SlotReq, +PackageDeps, +Context, -Rejected)
%
% Collects previously-selected candidates for (C,N) that do NOT satisfy
% the current dependency's constraints. Used to exclude them from fresh
% enumeration.

cnselect:selected_cn_rejected_candidates(Action, C, N, SlotReq, PackageDeps, Context, Rejected) :-
  grouped_dep_effective_domain_precomputed(Action, C, N, PackageDeps, Context, EffDom, RejectDom),
  findall(Repo://Entry,
          ( selected_cn_candidate(Action, C, N, Context, Repo://Entry),
            slotmeta:query_search_slot_constraint(SlotReq, Repo://Entry, _),
            \+ grouped_dep_candidate_satisfies_constraints_precomputed(
                    C, N, PackageDeps, EffDom, RejectDom, Repo://Entry)
          ),
          Rejected0),
  sort(Rejected0, Rejected),
  !.

%! cnselect:grouped_dep_candidate_satisfies_constraints(+Action, +C, +N, +PackageDeps, +Context, +RepoEntry)
%
% True if RepoEntry satisfies all version constraints and the effective
% domain for (C,N) in the given context.

cnselect:grouped_dep_candidate_satisfies_constraints(Action, C, N, PackageDeps, Context, Repo://Entry) :-
  forall(member(package_dependency(_Phase,no,C,N,O,V,_SlotReq,_Use), PackageDeps),
         query:search(select(version, O, V), Repo://Entry)),
  grouped_dep_candidate_satisfies_effective_domain(Action, C, N, PackageDeps, Context, Repo://Entry),
  !.

%! cnselect:grouped_dep_candidate_satisfies_constraints_precomputed(+C, +N, +PackageDeps, +EffDom, +RejectDom, +RepoEntry)
%
% Like grouped_dep_candidate_satisfies_constraints/6 but uses precomputed
% effective and reject domains to avoid redundant domain intersection.

cnselect:grouped_dep_candidate_satisfies_constraints_precomputed(C, N, PackageDeps, EffDom, RejectDom, Repo://Entry) :-
  forall(member(package_dependency(_Phase,no,C,N,O,V,_SlotReq,_Use), PackageDeps),
         query:search(select(version, O, V), Repo://Entry)),
  grouped_dep_candidate_satisfies_effective_domain_precomputed(EffDom, RejectDom, C, N, Repo://Entry),
  !.

%! cnselect:grouped_dep_effective_domain_precomputed(+Action, +C, +N, +PackageDeps, +Context, -EffDom, -RejectDom)
%
% Precomputes both the effective version domain and the scoped reject
% domain for a grouped dependency. Avoids recomputing these per-candidate.

cnselect:grouped_dep_effective_domain_precomputed(Action, C, N, PackageDeps, Context, EffectiveDomain, RejectDomain) :-
  grouped_dep_effective_domain(Action, C, N, PackageDeps, Context, EffectiveDomain),
  context_cn_reject_scope(C, N, Context, EffectiveDomain, RejectScope),
  cn_reject_scoped_domain(RejectScope, EffectiveDomain, RejectDomain),
  !.

cnselect:grouped_dep_candidate_satisfies_effective_domain(Action, C, N, PackageDeps, Context, RepoEntry) :-
  grouped_dep_effective_domain_precomputed(Action, C, N, PackageDeps, Context, EffectiveDomain, RejectDomain),
  grouped_dep_candidate_satisfies_effective_domain_precomputed(EffectiveDomain, RejectDomain, C, N, RepoEntry),
  !.

cnselect:grouped_dep_candidate_satisfies_effective_domain_precomputed(EffectiveDomain, RejectDomain, C, N, RepoEntry) :-
  \+ version_domain:domain_inconsistent(EffectiveDomain),
  \+ cn_domain_candidate_rejected(C, N, RejectDomain, RepoEntry),
  \+ feedback:version_excluded(C, N, RepoEntry),
  \+ ghcabi:version_incompatible_with_selected_ghc(C, N, RepoEntry),
  version_domain:domain_allows_candidate(EffectiveDomain, RepoEntry),
  !.

%! cnselect:grouped_dep_effective_domain(+Action, +C, +N, +PackageDeps, +Context, -EffDom)
%
% Computes the effective version domain for a grouped dependency by
% intersecting the dep's own constraints, the context's CN domain,
% and any learned domain from prior reprove iterations.

cnselect:grouped_dep_effective_domain(Action, C, N, PackageDeps, Context, EffectiveDomain) :-
  version_domain:domain_from_packagedeps(Action, C, N, PackageDeps, DepDomain0),
  ( context_cn_domain_constraint(C, N, Context, CtxDomain0) ->
      ( version_domain:domain_meet(CtxDomain0, DepDomain0, D1) -> true
      ; D1 = version_domain(slots([]), [])
      )
  ; D1 = DepDomain0
  ),
  apply_learned_domain(C, N, PackageDeps, D1, EffectiveDomain),
  !.

%! cnselect:apply_learned_domain(+C, +N, +PackageDeps, +D0, -D)
%
% Intersects domain D0 with any learned domain constraints for (C,N)
% from the prover's learned constraint store. Learned domains come
% from prior reprove iterations (conflict-driven domain narrowing).

cnselect:apply_learned_domain(C, N, PackageDeps, D0, D) :-
  dep_slot_key(PackageDeps, Slot),
  ( Slot \== any, prover:learned(cn_domain(C,N,Slot), L1) -> true ; L1 = none ),
  ( prover:learned(cn_domain(C,N,any), L2) -> true ; L2 = none ),
  ( L1 \== none, L2 \== none ->
      version_domain:domain_meet(L1, L2, Learned),
      ( version_domain:domain_meet(D0, Learned, D) -> true ; D = D0 )
  ; L1 \== none ->
      ( version_domain:domain_meet(D0, L1, D) -> true ; D = D0 )
  ; L2 \== none ->
      ( version_domain:domain_meet(D0, L2, D) -> true ; D = D0 )
  ; D = D0
  ), !.

%! cnselect:dep_slot_key(+PackageDeps, -Slot)
%
% Extracts a canonical slot key from the first slotted dep in PackageDeps,
% or returns `any` if none carries a slot requirement.

cnselect:dep_slot_key(PackageDeps, Slot) :-
  member(package_dependency(_, _, _, _, _, _, SlotReq, _), PackageDeps),
  SlotReq = [slot(S)|_], slotmeta:canon_slot(S, Slot), !.
cnselect:dep_slot_key(_, any).

%! cnselect:context_cn_domain_constraint(+C, +N, +Context, -Domain)
%
% Extracts the cn_domain constraint for (C,N) from the ?{Context} list.

cnselect:context_cn_domain_constraint(C, N, Context, Domain) :-
  is_list(Context),
  ( memberchk(constraint(cn_domain(C,N,_):{Domain}), Context) -> true
  ; memberchk(constraint(cn_domain(C,N):{Domain}), Context)
  ),
  !.

%! cnselect:context_cn_domain_reason(+C, +N, +Context, -Reasons)
%
% Extracts domain reason tags for (C,N) from the ?{Context} list.

cnselect:context_cn_domain_reason(C, N, Context, Reasons) :-
  is_list(Context),
  ( memberchk(constraint(cn_domain_reason(C,N):{ordset(Reasons0)}), Context) ->
      Reasons = Reasons0
  ; memberchk(domain_reason(cn_domain(C,N,Reasons0)), Context) ->
      Reasons = Reasons0
  ; Reasons = []
  ),
  !.

%! cnselect:cn_domain_for_slot(+C, +N, +Slot, +Constraints, -Domain) is semidet.
%
% Looks up the effective cn_domain for a (C,N,Slot) triple. Tries the
% slot-specific entry first, then falls back to the `any` entry.

cnselect:cn_domain_for_slot(C, N, Slot, Constraints, Domain) :-
  ( Slot \== any, get_assoc(cn_domain(C,N,Slot), Constraints, Domain) -> true
  ; get_assoc(cn_domain(C,N,any), Constraints, Domain)
  ).


%! cnselect:selected_cn_check_slot_domains(+C, +N, +SelectedMerged, +Constraints)
%
% For each slot represented in SelectedMerged, looks up the
% slot-specific and `any` cn_domains, meets them, and checks
% compatibility.  Called by the selected_cn constraint guard.

cnselect:selected_cn_check_slot_domains(C, N, SelectedMerged, Constraints) :-
  findall(Slot,
          ( member(selected(_,_,_,_,SM), SelectedMerged),
            ( cnselect:selected_cn_slot_key_(SM, Slot0) -> true ; Slot0 = any ),
            Slot = Slot0
          ),
          Slots0),
  sort(Slots0, Slots),
  forall(member(Slot, Slots),
         selected_cn_check_one_slot_domain(C, N, Slot, SelectedMerged, Constraints)),
  !.

cnselect:selected_cn_check_one_slot_domain(C, N, Slot, SelectedMerged, Constraints) :-
  ( Slot \== any, get_assoc(cn_domain(C,N,Slot), Constraints, DSlot) -> true ; DSlot = none ),
  ( get_assoc(cn_domain(C,N,any), Constraints, DAny0) -> true ; DAny0 = none ),
  ( DAny0 \== none, version_domain:domain_inconsistent(DAny0) -> DAny = none ; DAny = DAny0 ),
  ( DSlot \== none, DAny \== none ->
      ( version_domain:domain_meet(DSlot, DAny, Domain) -> true ; Domain = DSlot )
  ; DSlot \== none -> Domain = DSlot
  ; DAny \== none -> Domain = DAny
  ; true
  ),
  ( var(Domain) -> true
  ; heuristic:filter_selected_by_slot(Slot, SelectedMerged, SlotSelected),
    ( SlotSelected == [] -> true
    ; cnselect:selected_cn_domain_compatible_or_reprove(C, N, Domain, SlotSelected, Constraints)
    )
  ),
  !.


%! cnselect:context_selected_cn_candidates(+C, +N, +Context, -Candidates)
%
% Extracts the list of previously-selected candidates for (C,N) from
% the constraint store in Context.

cnselect:context_selected_cn_candidates(C, N, Context, Candidates) :-
  is_list(Context),
  memberchk(constraint(selected_cn(C,N):{ordset(SelectedSet)}), Context),
  findall(Repo://Entry,
          member(selected(Repo,Entry,_Act,_SelVer,_SelSlotMeta), SelectedSet),
          Candidates0),
  sort(Candidates0, Candidates),
  Candidates \== [],
  !.

%! cnselect:context_cn_reject_scope(+C, +N, +Context, +Domain, -Scope)
%
% Determines the reject scope for (C,N): either a specific slot from
% the context or derived from the domain.

cnselect:context_cn_reject_scope(C, N, Context, Domain, Scope) :-
  ( context_slot_scope(C, N, Context, Scope0) ->
      Scope = Scope0
  ; domain_slot_scope(Domain, Scope)
  ),
  !.

cnselect:context_slot_scope(C, N, Context, slot(Slot)) :-
  is_list(Context),
  memberchk(slot(C,N,Ss0):{_}, Context),
  slotmeta:canon_any_same_slot_meta(Ss0, [slot(Slot)]),
  !.

cnselect:domain_slot_scope(version_domain(slots([S0]), _Bounds), slot(S)) :-
  slotmeta:canon_slot(S0, S),
  !.
cnselect:domain_slot_scope(_Domain, any) :-
  !.

cnselect:cn_reject_scope_canon(slot(S0), slot(S)) :-
  slotmeta:canon_slot(S0, S),
  !.
cnselect:cn_reject_scope_canon(any, any) :-
  !.
cnselect:cn_reject_scope_canon(_Other, any) :-
  !.

cnselect:cn_reject_scoped_domain(any, Domain, Domain) :-
  !.
cnselect:cn_reject_scoped_domain(Scope0, Domain, scoped(Scope, Domain)) :-
  cn_reject_scope_canon(Scope0, Scope),
  !.

%! cnselect:snapshot_selected_cn_candidates(+C, +N, -Candidates)
%
% Retrieves the memoized snapshot of selected candidates for (C,N).

cnselect:snapshot_selected_cn_candidates(C, N, Candidates) :-
  nb_current(memo_selected_cn_snap, AVL),
  get_assoc(C-N, AVL, Candidates),
  Candidates \== [],
  !.

%! cnselect:record_selected_cn_snapshot(+C, +N, +SelectedSet)
%
% Records a snapshot of the current selected candidates for (C,N) into
% the memoization store, replacing any previous snapshot.

cnselect:record_selected_cn_snapshot(C, N, SelectedSet) :-
  findall(Repo://Entry,
          member(selected(Repo,Entry,_Act,_SelVer,_SelSlotMeta), SelectedSet),
          Candidates0),
  sort(Candidates0, Candidates),
  ( nb_current(memo_selected_cn_snap, AVL0) -> true ; empty_assoc(AVL0) ),
  put_assoc(C-N, AVL0, Candidates, AVL1),
  nb_setval(memo_selected_cn_snap, AVL1),
  !.

%! cnselect:snapshot_blocked_cn_sources(+C, +N, -Sources)
%
% Retrieves the memoized blocker source snapshot for (C,N).

cnselect:snapshot_blocked_cn_sources(C, N, Sources) :-
  nb_current(memo_blocked_cn_source_snap, AVL),
  get_assoc(C-N, AVL, Sources),
  Sources \== [],
  !.

%! cnselect:record_blocked_cn_source_snapshot(+C, +N, +Sources)
%
% Records blocker source entries for (C,N), merging with any existing
% snapshot via ord_union.

cnselect:record_blocked_cn_source_snapshot(C, N, Sources0) :-
  sort(Sources0, Sources),
  Sources \== [],
  ( nb_current(memo_blocked_cn_source_snap, AVL0) -> true ; empty_assoc(AVL0) ),
  ( get_assoc(C-N, AVL0, OldSources) -> true ; OldSources = [] ),
  ord_union(OldSources, Sources, MergedSources),
  put_assoc(C-N, AVL0, MergedSources, AVL1),
  nb_setval(memo_blocked_cn_source_snap, AVL1),
  !.
cnselect:record_blocked_cn_source_snapshot(_C, _N, _Sources) :-
  !.

%! cnselect:reason_linked_selected_reprove_target(+Reasons, -SourceC, -SourceN, -SourceCandidates)
%
% Follows introduced_by reason chains to find the originally-selected
% candidate that should be rejected in a cross-package reprove.

cnselect:reason_linked_selected_reprove_target(Reasons, SourceC, SourceN, [SourceRepo://SourceEntry]) :-
  is_list(Reasons),
  member(introduced_by(OriginRepo://OriginEntry, _ReasonAction, _ReasonWhat), Reasons),
  query:search([category(OriginC),name(OriginN)], OriginRepo://OriginEntry),
  snapshot_blocked_cn_sources(OriginC, OriginN, Sources),
  member(source(SourceRepo,SourceEntry,_Phase,_O,_V,_SlotReq), Sources),
  query:search([category(SourceC),name(SourceN)], SourceRepo://SourceEntry),
  snapshot_selected_cn_candidates(SourceC, SourceN, SelectedSourceCandidates),
  memberchk(SourceRepo://SourceEntry, SelectedSourceCandidates),
  !.

%! cnselect:domain_conflicting_candidates(+Domain, +Candidates, -Conflicting)
%
% Filters Candidates to those not allowed by Domain.

cnselect:domain_conflicting_candidates(_Domain, [], []) :-
  !.
cnselect:domain_conflicting_candidates(Domain, Candidates, Conflicting) :-
  findall(RepoEntry,
          ( member(RepoEntry, Candidates),
            \+ version_domain:domain_allows_candidate(Domain, RepoEntry)
          ),
          Conflicting0),
  sort(Conflicting0, Conflicting),
  !.

%! cnselect:constraint_conflicting_candidates(+Action, +C, +N, +PackageDeps, +Context, +Candidates, -Conflicting)
%
% Filters Candidates to those not satisfying the grouped dependency constraints.

cnselect:constraint_conflicting_candidates(_Action, _C, _N, _PackageDeps, _Context, [], []) :-
  !.
cnselect:constraint_conflicting_candidates(Action, C, N, PackageDeps, Context, Candidates, Conflicting) :-
  findall(RepoEntry,
          ( member(RepoEntry, Candidates),
            \+ grouped_dep_candidate_satisfies_constraints(Action, C, N, PackageDeps, Context, RepoEntry)
          ),
          Conflicting0),
  sort(Conflicting0, Conflicting),
  !.

%! cnselect:maybe_request_grouped_dep_reprove(+Action, +C, +N, +PackageDeps, +Context)
%
% When CN-domain reprove is enabled and the effective domain conflicts
% with already-selected candidates, throws a `prover_reprove/1` exception
% requesting the prover to retry with the conflicting candidates rejected.
% This is the main conflict-driven learning entry point for grouped deps.
%
% Visibility-only failures are exempt, like in parent narrowing above:
% when the dep on (C,N) fails only because every candidate is masked /
% keyword-filtered, rejecting the introducing origin (line "SourceC/
% SourceN" below) permanently poisons it for the rest of the proof even
% though a later pass may not need the hidden dep at all (portage-ng#91
% sub-mechanism A: accountsservice[systemd]'s dep on profile-masked
% systemd:0= origin-rejected accountsservice itself; the final elogind-
% seeded pass then found accountsservice reject-listed and the whole
% Cinnamon stack collapsed to phantoms). Falling through instead lets
% grouped_dep_concretize_hidden plan the masked provider with a
% POSITIVE unmask suggestion.

cnselect:maybe_request_grouped_dep_reprove(Action, C, N, PackageDeps, Context) :-
  cn_domain_reprove_enabled,
  \+ dep_failure_is_visibility_only(C, N, PackageDeps, Context),
  ( context_selected_cn_candidates(C, N, Context, SelectedCandidatesRaw) ->
      true
  ; snapshot_selected_cn_candidates(C, N, SelectedCandidates0) ->
      SelectedCandidatesRaw = SelectedCandidates0
  ; SelectedCandidatesRaw = []
  ),
  grouped_dep_effective_domain(Action, C, N, PackageDeps, Context, EffectiveDomain),
  context_cn_reject_scope(C, N, Context, EffectiveDomain, RejectScope),
  cn_reject_scoped_domain(RejectScope, EffectiveDomain, RejectDomain),
  domain_conflicting_candidates(EffectiveDomain, SelectedCandidatesRaw, DomainConflicting),
  constraint_conflicting_candidates(Action, C, N, PackageDeps, Context, SelectedCandidatesRaw, ConstraintConflicting),
  ord_union(DomainConflicting, ConstraintConflicting, SelectedCandidates),
  version_domain:domain_reason_terms(Action, C, N, PackageDeps, Context, Reasons),
  ( SelectedCandidates \== []
  ; Reasons \== []
  ),
  ( version_domain:domain_inconsistent(EffectiveDomain)
  ; SelectedCandidates \== []
  ; dep_has_version_constraint(C, N, PackageDeps)
  ; dep_has_explicit_slot_constraint(C, N, PackageDeps)
  ),
  ( SelectedCandidates == [],
    reason_linked_selected_reprove_target(Reasons, SourceC, SourceN, SourceCandidates)
  ->
    throw(prover_reprove(cn_domain(SourceC, SourceN, none, SourceCandidates, Reasons)))
  ; throw(prover_reprove(cn_domain(C, N, RejectDomain, SelectedCandidates, Reasons)))
  ).
cnselect:maybe_request_grouped_dep_reprove(_Action, _C, _N, _PackageDeps, _Context) :-
  fail.


% -----------------------------------------------------------------------------
%  CN-domain reject map (bounded reprove retries)
% -----------------------------------------------------------------------------

%! cnselect:cn_domain_reject_key(+C, +N, +Domain, -Key)
%
% Computes a canonical reject-map key from (C,N) and a domain term.
% Keys are normalised to `key(C,N,Scope,Domain)` where Scope is
% either `slot(S)` or `any`, enabling both slot-specific and global
% reject tracking.

cnselect:cn_domain_reject_key(C, N, scoped(Scope0, Domain0), key(C,N,Scope,Domain)) :-
  cn_reject_scope_canon(Scope0, Scope),
  version_domain:domain_normalize(Domain0, Domain),
  !.
cnselect:cn_domain_reject_key(C, N, Domain0, key(C,N,Scope,Domain)) :-
  version_domain:domain_normalize(Domain0, Domain),
  domain_slot_scope(Domain, Scope),
  !.

%! cnselect:cn_domain_candidate_rejected(+C, +N, +Domain, +RepoEntry)
%
% True if RepoEntry has been rejected for (C,N) under Domain in a prior
% reprove iteration. Checks slot-scoped, domain-scoped, and global
% reject sets.

cnselect:cn_domain_candidate_rejected(C, N, Domain0, RepoEntry) :-
  cn_domain_reject_key(C, N, Domain0, key(C,N,Scope,Domain)),
  ( memo:cn_domain_reject_(key(C,N,Scope,Domain), Set),
    memberchk(RepoEntry, Set)
  ; memo:cn_domain_reject_(key(C,N,Scope,none), ScopeGlobalSet),
    memberchk(RepoEntry, ScopeGlobalSet)
  ; Scope \== any,
    memo:cn_domain_reject_(key(C,N,any,Domain), AnyDomainSet),
    memberchk(RepoEntry, AnyDomainSet)
  ; memo:cn_domain_reject_(key(C,N,any,none), GlobalSet),
    memberchk(RepoEntry, GlobalSet)
  ),
  !.

%! cnselect:add_cn_domain_rejects(+C, +N, +Domain, +Candidates, -Added)
%
% Records Candidates as rejected for (C,N) under Domain. Added is
% `true` if any new entries were added, `false` otherwise. Called by
% heuristic:handle_reprove/2 when a reprove conflict is processed.

cnselect:add_cn_domain_rejects(C, N, Domain0, Candidates0, Added) :-
  cn_domain_reject_key(C, N, Domain0, Key),
  sort(Candidates0, Candidates),
  ( memo:cn_domain_reject_(Key, OldSet) -> true ; OldSet = [] ),
  ord_union(OldSet, Candidates, NewSet),
  ( NewSet == OldSet ->
      Added = false
  ; ( retract(memo:cn_domain_reject_(Key, _)) -> true ; true ),
    assertz(memo:cn_domain_reject_(Key, NewSet)),
    Added = true
  ),
  !.

%! cnselect:add_cn_domain_origin_rejects(+Reasons, -Added)
%
% For each `introduced_by` reason, rejects the origin candidate globally.
% This enables cross-package conflict learning.

cnselect:add_cn_domain_origin_rejects(Reasons, Added) :-
  is_list(Reasons),
  findall(C0-N0-Repo://Entry,
          ( member(introduced_by(Repo://Entry, _Action, _Why), Reasons),
            query:search([category(C0),name(N0)], Repo://Entry)
          ),
          Origins0),
  sort(Origins0, Origins),
  add_cn_domain_origin_rejects_(Origins, false, Added),
  !.
cnselect:add_cn_domain_origin_rejects(_Reasons, false) :-
  !.

cnselect:add_cn_domain_origin_rejects_([], Added, Added) :-
  !.
cnselect:add_cn_domain_origin_rejects_([C-N-Repo://Entry|Rest], Added0, Added) :-
  add_cn_domain_rejects(C, N, none, [Repo://Entry], Added1),
  ( Added0 == true ->
      Added2 = true
  ; Added1 == true ->
      Added2 = true
  ; Added2 = false
  ),
  add_cn_domain_origin_rejects_(Rest, Added2, Added).

%! cnselect:cn_domain_reprove_enabled
%
% Guard predicate: succeeds when the prover's reprove mechanism is active.

cnselect:cn_domain_reprove_enabled :-
  prover:reprove_enabled,
  !.

%! cnselect:maybe_request_cn_domain_reprove(+C, +N, +Domain, +Selected)
%
% Throws prover_reprove/1 if reprove is enabled and Selected is non-empty.

cnselect:maybe_request_cn_domain_reprove(C, N, Domain, Selected) :-
  maybe_request_cn_domain_reprove(C, N, Domain, Selected, []).

%! cnselect:maybe_request_cn_domain_reprove(+C, +N, +Domain, +Selected, +Reasons)
%
% Extended variant that includes reason tags in the reprove exception.

cnselect:maybe_request_cn_domain_reprove(C, N, Domain, Selected, Reasons) :-
  cn_domain_reprove_enabled,
  findall(Repo://Entry,
          member(selected(Repo,Entry,_Act,_SelVer,_SelSlotMeta), Selected),
          Candidates0),
  sort(Candidates0, Candidates),
  Candidates \== [],
  throw(prover_reprove(cn_domain(C, N, Domain, Candidates, Reasons))).
cnselect:maybe_request_cn_domain_reprove(_C, _N, _Domain, _Selected, _Reasons) :-
  true.


% -----------------------------------------------------------------------------
%  Selected CN uniqueness / constraint enforcement
% -----------------------------------------------------------------------------

%! cnselect:selected_cn_unique_or_reprove(+C, +N, +SelectedMerged, +Constraints)
%
% Enforces that at most one concrete entry is selected per (C,N) (or per
% slot when multislot is allowed). If uniqueness is violated and reprove
% is enabled, learns the conflict and throws prover_reprove/1.
% Called by constraint_guard for selected_cn constraints.

cnselect:selected_cn_unique_or_reprove(C, N, SelectedMerged, Constraints) :-
  selected_cn_unique(C, N, SelectedMerged, Constraints),
  !.
cnselect:selected_cn_unique_or_reprove(C, N, SelectedMerged, Constraints) :-
  cn_domain_reprove_enabled,
  cn_domain_for_slot(C, N, any, Constraints, Domain),
  \+ selected_cn_requires_same_slot_multiversion(C, N, Constraints),
  selected_cn_partition_by_domain(Domain, SelectedMerged, Allowed, Conflicting),
  Allowed \== [],
  Conflicting \== [],
  ( Conflicting = [selected(_,_,_,_,SM0)|_],
    selected_cn_slot_key_(SM0, Slot) -> true ; Slot = any ),
  prover:learn(cn_domain(C,N,Slot), Domain, _),
  ( Slot \== any -> prover:learn(cn_domain(C,N,any), Domain, _) ; true ),
  maybe_request_cn_domain_reprove(C, N, none, Conflicting, [unique_conflict_with_domain]),
  fail.
cnselect:selected_cn_unique_or_reprove(C, N, _SelectedMerged, Constraints) :-
  cn_domain_reprove_enabled,
  cn_domain_for_slot(C, N, any, Constraints, _Domain),
  selected_cn_requires_same_slot_multiversion(C, N, Constraints),
  ( get_assoc(cn_domain_reason(C,N), Constraints, ordset(Reasons)) -> true ; Reasons = [] ),
  Reasons \== [],
  find_adjustable_origin(Reasons, OriginC, OriginN, OriginRepo://OriginEntry),
  query:search(version(OriginVer), OriginRepo://OriginEntry),
  ExcludeDomain = version_domain(any, [bound(smaller, OriginVer)]),
  prover:learn(cn_domain(OriginC, OriginN, any), ExcludeDomain, Added),
  Added == true,
  maybe_request_cn_domain_reprove(OriginC, OriginN, none, [OriginRepo://OriginEntry], [inconsistency_driven]),
  fail.
cnselect:selected_cn_unique_or_reprove(_C, _N, _SelectedMerged, _Constraints) :-
  fail.

%! cnselect:record_slot_conflict_if_multiple(+C, +N, +Selected)
%
% Records a slot conflict memo when the domain is inconsistent and
% multiple entries are selected for (C,N).  Persists across reprove
% attempts so the assumption clause can include slot conflict details.

cnselect:record_slot_conflict_if_multiple(C, N, Selected) :-
  ( Selected = [_,_|_],
    \+ memo:slot_conflict_(C, N, _) ->
      findall(slot_entry(Repo, Entry, Ver, SlotKey),
              ( member(selected(Repo, Entry, _Act, Ver, SlotMeta), Selected),
                ( selected_cn_slot_key_(SlotMeta, SlotKey) -> true ; SlotKey = unknown )
              ),
              Entries),
      assertz(memo:slot_conflict_(C, N, Entries))
  ; true
  ).


%! cnselect:find_adjustable_origin(+Reasons, -OriginC, -OriginN, -RepoEntry)
%
% Finds an origin candidate from introduced_by reasons that has already
% been narrowed in this proof, making it a candidate for version
% exclusion during reprove.

cnselect:find_adjustable_origin(Reasons, OriginC, OriginN, Repo://Entry) :-
  member(introduced_by(Repo://Entry, _Action, _Why), Reasons),
  cache:ordered_entry(Repo, Entry, OriginC, OriginN, _),
  cn_previously_narrowed(OriginC, OriginN), !.


%! cnselect:cn_previously_narrowed(+C, +N) is semidet.
%
% True when an earlier reprove iteration of this proof already narrowed
% (C,N): either a learned cn_domain exists (conflict / wildcard learning)
% or a globally rejected candidate exists (parent narrowing, which
% rejects the exact parent entry rather than learning a version cut).

cnselect:cn_previously_narrowed(C, N) :-
  ( prover:learned(cn_domain(C, N, _), _) -> true
  ; memo:cn_domain_reject_(key(C, N, any, none), Set),
    Set \== []
  ),
  !.

%! cnselect:maybe_learn_wildcard_domain(+C, +N, +PackageDeps, +Context) is semidet.
%
% When resolution of a wildcard dep on (C,N) fails, learns an
% upper-bound cn_domain from the wildcard constraint and reproves.
% Fires when the parent has already been narrowed by a prior
% parent_narrowing attempt, OR when the parent has only one version
% (where parent_narrowing would be futile). This ensures
% parent_narrowing gets priority for multi-version parents, correctly
% handling cross-package wildcard conflicts, while single-version
% parents get immediate wildcard domain learning.

cnselect:maybe_learn_wildcard_domain(C, N, PackageDeps, Context) :-
  cn_domain_reprove_enabled,
  is_list(Context),
  memberchk(self(ParentRepo://ParentEntry), Context),
  cache:ordered_entry(ParentRepo, ParentEntry, ParentC, ParentN, _),
  ( cn_previously_narrowed(ParentC, ParentN)
  ; parent_is_single_version(ParentC, ParentN)
  ),
  wildcard_upper_bound_domain(C, N, PackageDeps, Domain),
  dep_slot_key(PackageDeps, Slot),
  prover:learn(cn_domain(C, N, Slot), Domain, Added),
  Added == true,
  throw(prover_reprove(cn_domain(C, N, none, [], [wildcard_domain_learning]))).
cnselect:maybe_learn_wildcard_domain(_, _, _, _) :- fail.


%! cnselect:parent_is_single_version(+C, +N) is semidet.
%
% True if there is exactly one cache entry for (C,N). When the parent
% has only one version, parent_narrowing would make it unavailable, so
% wildcard domain learning should be preferred.

cnselect:parent_is_single_version(C, N) :-
  once(cache:ordered_entry(_, E1, C, N, _)),
  \+ (cache:ordered_entry(_, E2, C, N, _), E2 \== E1).


%! cnselect:dep_target_selected_conflict(+C, +N, +PackageDeps, +Context) is semidet.
%
% True when the dependency *target* (C,N) is already pinned in the
% selected_cn store at a candidate that violates this dep's own version
% constraints. In that case the conflict lives at the child level
% (e.g. dev-ruby/regexp_parser needs =dev-util/ragel-6*, but a sibling
% pinned dev-util/ragel-7), so the correct repair is to re-select the
% child (handled by maybe_request_grouped_dep_reprove/5, which rejects
% the conflicting candidate and lets ragel-6.10 be chosen), exactly as
% emerge backtracks the build-dep version. Narrowing the *parent* here
% is futile: every parent version shares the same child constraint, so
% parent_narrowing would churn through all parent versions and then emit
% a spurious assumption. This guard makes parent_narrowing yield to the
% child-level reprove in that situation.
%
% The yield is conditional on the child-level repair being *possible*:
% some non-rejected candidate of (C,N) must satisfy this dep's own
% constraints inside the effective domain (child_reselection_possible/4).
% When none does, re-selecting the child cannot help and the conflict
% lives at the parent level after all. Without this condition the
% child-level reprove rejects the selected child, the consumer's other
% deps select the next child version, the same dep rejects that one
% too, and so on through every version of the child; the last request
% repeats an existing reject, heuristic:handle_reprove/2 reports no
% progress and the prover drops the whole reject map for the final
% pass (dev-ada/gnatformat-25.0.0-r3: libadalang-26.0.0's ~gpr-26.0.0
% after gpr-26.0.0 had been rejected for gnatformat's own <gpr-26 walked
% through gpr-25.0.0-r4, 24.2.0-r1 and 24.0.0-r3 instead of narrowing
% libadalang to 25.0.0-r1, which is the consistent plan).

cnselect:dep_target_selected_conflict(C, N, PackageDeps, Context) :-
  ( context_selected_cn_candidates(C, N, Context, Selected)
  ; snapshot_selected_cn_candidates(C, N, Selected)
  ),
  Selected \== [],
  member(SelRepo://SelEntry, Selected),
  \+ forall( member(package_dependency(_Phase,no,C,N,O,V,_Slot,_Use), PackageDeps),
             query:search(select(version, O, V), SelRepo://SelEntry) ),
  child_reselection_possible(C, N, PackageDeps, Context),
  !.


%! cnselect:child_reselection_possible(+C, +N, +PackageDeps, +Context) is semidet.
%
% True when at least one candidate of (C,N) satisfies every version
% constraint of PackageDeps, lies inside the effective (dep + proof
% context + learned) domain, and is not in the reject map for that
% domain: the candidate a child-level reprove could switch to.

cnselect:child_reselection_possible(C, N, PackageDeps, Context) :-
  ( member(package_dependency(Phase, no, C, N, _, _, _, _), PackageDeps),
    Phase \== pdepend
  -> Action = Phase
  ;  Action = run
  ),
  grouped_dep_effective_domain_precomputed(Action, C, N, PackageDeps, Context, EffDom, RejectDom),
  cache:ordered_entry(Repo, Entry, C, N, _),
  grouped_dep_candidate_satisfies_constraints_precomputed(C, N, PackageDeps, EffDom, RejectDom, Repo://Entry),
  !.


%! cnselect:dep_failure_is_visibility_only(+C, +N, +PackageDeps, +Context) is semidet.
%
% True when the failed dependency on (C,N) is unsatisfiable purely
% because every candidate is hidden by a visibility filter (profile
% mask or ACCEPT_KEYWORDS). Uses the same cached diagnosis as the
% assumption fallback (explanation:assumption_reason_for_grouped_dep/6),
% so the classification here always agrees with what the concretization
% clause (grouped_dep_concretize_hidden/7) will accept.

cnselect:dep_failure_is_visibility_only(C, N, PackageDeps, Context) :-
  ( member(package_dependency(Phase, no, C, N, _, _, _, _), PackageDeps),
    Phase \== pdepend
  -> Action = Phase
  ;  Action = run
  ),
  explanation:assumption_reason_for_grouped_dep(Action, C, N, PackageDeps, Context, Reason),
  memberchk(Reason, [masked, keyword_filtered]),
  !.


%! cnselect:maybe_learn_parent_narrowing(+C, +N, +PackageDeps, +Context)
%
% When a dependency on (C,N) is unsatisfiable, excludes the parent
% version that introduced the dependency. This is the "wrong-level
% fix": the parent introduced a dep that cannot be satisfied, so
% exclude the parent version and reprove.
%
% The exclusion is the exact parent entry, recorded in the reject map
% by heuristic:handle_reprove/2 when the thrown prover_reprove/1 is
% processed. It is deliberately NOT a learned `< ParentVer` version
% cut: a cut also discards every newer parent version that was still
% eligible — newer versions are visited after older ones whenever they
% are keyword-filtered or ranked lower, and a version is "newer" for
% every consumer while the failure was proven for one dependency path.
% Tree-wide A/B (33k ebuilds): the cut lost still-eligible newer
% versions in 194 targets and the exact reject removed a net ~540
% NEGATIVE unsatisfied_constraints assumptions at identical inference
% cost. Like every other reject, it is dropped by
% heuristic:reprove_exhausted/0 before the final reprove-disabled pass;
% keeping it alive across exhaustion was measured to cost +168 CN-level
% assumptions tree-wide (3 targets better, 48 worse, 75 mixed).
%
% Skipped when dep_target_selected_conflict/4 holds: a conflicting
% pin on the child (C,N) is repaired by re-selecting the child via
% maybe_request_grouped_dep_reprove/5, not by narrowing the parent.
%
% Also skipped when the dep's failure is purely a visibility filter
% (masked / keyword_filtered): narrowing the parent cannot lift a
% profile mask, and the learned exclusion poisons every other consumer
% of the parent for the rest of the proof (portage-ng#91 sub-mechanism
% A: sys-apps/systemd is profile-masked on a headless baseline, so each
% systemd-USE consumer that reached this clause — dbus, at-spi2-core,
% gtk+, gnome-settings-daemon, ... — got version-excluded in turn and
% every edge onto it collapsed to a NEGATIVE `unsatisfied_constraints`
% phantom). Yielding here lets resolution fall through to the
% visibility-relaxed concretization (grouped_dep_concretize_hidden,
% portage-ng#14), which plans the hidden dep concretely and surfaces a
% single POSITIVE unmask / accept-keyword assumption instead.
%
% Also skipped when the parent is a root target of the current prove
% (prover:root_goal/1): the root is the request, not a choice, so its
% :install/:run literal is proven regardless of the reject map. The
% reject would only cost a full-restart retry and, should another
% package in the plan depend on the target's CN, steer that consumer
% onto a *different* version of it (a self-inflicted slot conflict).

cnselect:maybe_learn_parent_narrowing(C, N, PackageDeps, Context) :-
  \+ is_pdepend_failure(PackageDeps, Context),
  \+ is_multislot_miss(C, N, PackageDeps, Context),
  \+ dep_target_selected_conflict(C, N, PackageDeps, Context),
  \+ dep_failure_is_visibility_only(C, N, PackageDeps, Context),
  is_list(Context),
  memberchk(self(ParentRepo://ParentEntry), Context),
  \+ entry_is_root_target(ParentRepo://ParentEntry),
  cache:ordered_entry(ParentRepo, ParentEntry, ParentC, ParentN, _),
  % Progress guard: only throw when this exact entry is not yet rejected,
  % so the bounded reprove loop cannot spin on the same parent.
  \+ cn_domain_candidate_rejected(ParentC, ParentN, none, ParentRepo://ParentEntry),
  cn_domain_reprove_enabled,
  throw(prover_reprove(cn_domain(ParentC, ParentN, none, [ParentRepo://ParentEntry], [parent_narrowing]))).


%! cnselect:entry_is_root_target(+RepoEntry) is semidet.
%
% True when RepoEntry is the entry of one of the literals the current
% prove was asked to prove (prover:root_goal/1), whatever its action or
% proof context.

cnselect:entry_is_root_target(Repo://Entry) :-
  prover:root_goal(Goal),
  ( Goal = (Repo://Entry:_?{_}) -> true
  ; Goal = (Repo://Entry:_)
  ),
  !.

%! cnselect:is_pdepend_failure(+PackageDeps, +Context)
%
% True if the dependency set involves PDEPEND or after_only context,
% where parent narrowing should not be applied.

cnselect:is_pdepend_failure(PackageDeps, _Context) :-
  member(package_dependency(pdepend, _, _, _, _, _, _, _), PackageDeps),
  !.
cnselect:is_pdepend_failure(_, Context) :-
  is_list(Context),
  memberchk(after_only(_), Context),
  !.

%! cnselect:is_multislot_miss(+C, +N, +PackageDeps, +Context)
%
% True if the dep targets a slot not yet represented in the selected set,
% where parent narrowing would be counterproductive.

cnselect:is_multislot_miss(C, N, PackageDeps, Context) :-
  member(package_dependency(_, _, C, N, _, _, [slot(DepSlot0)|_], _), PackageDeps),
  slotmeta:canon_slot(DepSlot0, DepSlot),
  is_list(Context),
  memberchk(constraint(selected_cn(C,N):{ordset(Selected)}), Context),
  \+ ( member(selected(_, _, _, _, SlotMeta), Selected),
       selected_cn_slot_key_(SlotMeta, DepSlot) ),
  !.

%! cnselect:selected_cn_partition_by_domain(+Domain, +Selected, -Allowed, -Conflicting)
%
% Partitions selected entries into those allowed by Domain and those
% that conflict with it.

cnselect:selected_cn_partition_by_domain(_Domain, [], [], []) :-
  !.
cnselect:selected_cn_partition_by_domain(Domain, [Sel|Rest], [Sel|AllowedRest], ConflictingRest) :-
  Sel = selected(Repo,Entry,_Act,_SelVer,_SelSlotMeta),
  version_domain:domain_allows_candidate(Domain, Repo://Entry),
  !,
  selected_cn_partition_by_domain(Domain, Rest, AllowedRest, ConflictingRest).
cnselect:selected_cn_partition_by_domain(Domain, [Sel|Rest], AllowedRest, [Sel|ConflictingRest]) :-
  selected_cn_partition_by_domain(Domain, Rest, AllowedRest, ConflictingRest).

%! cnselect:selected_cn_not_blocked_or_reprove(+C, +N, +Specs, +Selected, +Constraints)
%
% Enforces strong blocker constraints: if any Spec in Specs violates an
% already-selected entry, attempts reprove by rejecting the blocker source.
% Called by constraint_guard for blocked_cn constraints.

cnselect:selected_cn_not_blocked_or_reprove(_C, _N, Specs, Selected, _Constraints) :-
  \+ candidate:specs_violate_selected(Specs, Selected),
  !.
cnselect:selected_cn_not_blocked_or_reprove(C, N, _Specs, _Selected, Constraints) :-
  cn_domain_reprove_enabled,
  blocked_cn_source_reprove_target(C, N, Constraints, SourceC, SourceN, Candidates),
  Candidates \== [],
  throw(prover_reprove(cn_domain(SourceC, SourceN, none, Candidates, []))).
cnselect:selected_cn_not_blocked_or_reprove(_C, _N, _Specs, _Selected, _Constraints) :-
  fail.

%! cnselect:blocked_cn_source_reprove_target(+C, +N, +Constraints, -SourceC, -SourceN, -Candidates)
%
% Finds the source candidate that introduced a blocker on (C,N) for
% targeted reprove rejection.

cnselect:blocked_cn_source_reprove_target(C, N, Constraints, SourceC, SourceN, [Repo://Entry]) :-
  get_assoc(blocked_cn_source(C,N), Constraints, ordset(Sources)),
  member(source(Repo,Entry,_Phase,_O,_V,_SlotReq), Sources),
  query:search([category(SourceC),name(SourceN)], Repo://Entry),
  !.

%! cnselect:selected_cn_domain_compatible_or_reprove(+C, +N, +Domain, +Selected, +Constraints)
%
% Checks that at least one entry in Selected is allowed by Domain.
% If not, learns the domain and requests reprove. Called by
% constraint_guard for cn_domain and selected_cn constraints.

cnselect:selected_cn_domain_compatible_or_reprove(C, N, Domain, Selected, Constraints) :-
  ( once(( member(selected(Repo, Entry, _Act, _SelVer, _SelSlotMeta), Selected),
           version_domain:domain_allows_candidate(Domain, Repo://Entry)
         )) ->
      true
  ; ( \+ version_domain:domain_inconsistent(Domain) ->
        ( ( Selected = [selected(_,_,_,_,SM0)|_],
            selected_cn_slot_key_(SM0, SelSlot) -> true ; SelSlot = any ),
          prover:learn(cn_domain(C,N,SelSlot), Domain, _),
          ( SelSlot \== any -> prover:learn(cn_domain(C,N,any), Domain, _) ; true )
        -> true ; true )
    ; record_slot_conflict_if_multiple(C, N, Selected),
      ( get_assoc(cn_domain_reason(C,N), Constraints, ordset(Reasons0)) -> true ; Reasons0 = [] ),
      ( Reasons0 \== [],
        find_adjustable_origin(Reasons0, OriginC, OriginN, OriginRepo://OriginEntry),
        query:search(version(OriginVer), OriginRepo://OriginEntry),
        ExcludeDomain = version_domain(any, [bound(smaller, OriginVer)]),
        prover:learn(cn_domain(OriginC, OriginN, any), ExcludeDomain, OriginAdded),
        OriginAdded == true
      ->
        maybe_request_cn_domain_reprove(OriginC, OriginN, none, [OriginRepo://OriginEntry], [inconsistency_driven]),
        fail
      ; true )
    ),
    ( get_assoc(cn_domain_reason(C,N), Constraints, ordset(Reasons)) -> true ; Reasons = [] ),
    ( prefer_global_selected_reject_from_domain(C, N, Domain, Selected, Constraints) ->
        DomainForReprove = none
    ; DomainForReprove = Domain
    ),
    maybe_request_cn_domain_reprove(C, N, DomainForReprove, Selected, Reasons),
    fail
  ),
  !.

%! cnselect:prefer_global_selected_reject_from_domain(+C, +N, +Domain, +Selected, +Constraints)
%
% Heuristic: when there are already selected candidates and the domain
% has an equal bound, prefer a global (domain=none) reject to keep the
% reprove search space manageable.

cnselect:prefer_global_selected_reject_from_domain(C, N, Domain, Selected, Constraints) :-
  Selected \== [],
  domain_has_equal_bound(Domain),
  \+ selected_cn_requires_same_slot_multiversion(C, N, Constraints),
  !.

%! cnselect:domain_has_equal_bound(+Domain)
%
% True if Domain has an `equal` bound.

cnselect:domain_has_equal_bound(version_domain(_Slots, Bounds)) :-
  member(bound(equal, _Req), Bounds),
  !.

%! cnselect:selected_cn_allow_multislot_constraints(+C, +N, +SlotReq, +PackageDeps, -Constraints)
%
% Generates an `allow_multislot` constraint when the dependency carries
% a slot or version restriction that justifies multi-slot selection.

cnselect:selected_cn_allow_multislot_constraints(C, N, SlotReq, PackageDeps, [constraint(selected_cn_allow_multislot(C,N):{true})]) :-
  ( SlotReq = [slot(_)|_]
  ; SlotReq == [any_same_slot]
  ; SlotReq == [any_different_slot]
  ; slotmeta:all_deps_exactish_versioned(PackageDeps)
  ; dep_has_version_constraint(C, N, PackageDeps)
  ),
  !.
cnselect:selected_cn_allow_multislot_constraints(_C, _N, _SlotReq, _PackageDeps, []).

%! cnselect:selected_cn_unique(+C, +N, +SelectedMerged, +Constraints)
%
% Dispatches to strict, per-slot, or per-slot+subslot uniqueness check
% based on whether multislot is allowed and multiversion is required.

cnselect:selected_cn_unique(C, N, SelectedMerged, Constraints) :-
  ( get_assoc(selected_cn_allow_multislot(C,N), Constraints, _AllowFlag) ->
      ( selected_cn_requires_same_slot_multiversion(C, N, Constraints) ->
          selected_cn_unique_per_slot_or_subslot(SelectedMerged)
      ; selected_cn_unique_per_slot(SelectedMerged)
      )
  ; selected_cn_unique_strict(SelectedMerged)
  ).

cnselect:selected_cn_unique_strict([]) :- !.
cnselect:selected_cn_unique_strict([selected(Repo,Entry,_Act,_Ver,_SlotMeta)|Rest]) :-
  forall(member(selected(Repo2,Entry2,_A2,_V2,_SlotMeta2), Rest),
         ( Repo2 == Repo,
           Entry2 == Entry
         )),
  selected_cn_unique_strict(Rest).

cnselect:selected_cn_unique_per_slot([]) :- !.
cnselect:selected_cn_unique_per_slot([selected(Repo,Entry,_Act,_Ver,SlotMeta)|Rest]) :-
  selected_cn_slot_key_(SlotMeta, Slot),
  forall(member(selected(Repo2,Entry2,_A2,_V2,SlotMeta2), Rest),
         ( selected_cn_slot_key_(SlotMeta2, Slot2),
           ( Slot2 \== Slot -> true
           ; Repo2 == Repo, Entry2 == Entry
           )
         )),
  selected_cn_unique_per_slot(Rest).

cnselect:selected_cn_unique_per_slot_or_subslot([]) :- !.
cnselect:selected_cn_unique_per_slot_or_subslot([selected(Repo,Entry,_Act,_Ver,SlotMeta)|Rest]) :-
  selected_cn_slot_subslot_key_(Repo, Entry, SlotMeta, SlotSubslot),
  forall(member(selected(Repo2,Entry2,_A2,_Ver2,SlotMeta2), Rest),
         ( selected_cn_slot_subslot_key_(Repo2, Entry2, SlotMeta2, SlotSubslot2),
           ( SlotSubslot2 \== SlotSubslot ->
               true
           ; Repo2 == Repo,
             Entry2 == Entry
           )
         )),
  selected_cn_unique_per_slot_or_subslot(Rest).

%! cnselect:selected_cn_requires_same_slot_multiversion(+C, +N, +Constraints)
%
% True if the CN domain is inconsistent, indicating that multiple
% versions in the same slot are required (subslot-level uniqueness).

cnselect:selected_cn_requires_same_slot_multiversion(C, N, Constraints) :-
  cn_domain_for_slot(C, N, any, Constraints, Domain),
  version_domain:domain_inconsistent(Domain),
  !.

cnselect:selected_cn_slot_subslot_key_(Repo, Entry, SlotMeta0, slot_subslot(Slot, SubSlot)) :-
  slotmeta:canon_any_same_slot_meta(SlotMeta0, [slot(S0)]),
  slotmeta:canon_slot(S0, Slot),
  ( is_list(SlotMeta0),
    memberchk(subslot(Ss0), SlotMeta0) ->
      slotmeta:canon_slot(Ss0, SubSlot)
  ; query:search(subslot(Ss1), Repo://Entry) ->
      slotmeta:canon_slot(Ss1, SubSlot)
  ; SubSlot = none
  ),
  !.

cnselect:selected_cn_slot_key_(SlotMeta0, Slot) :-
  slotmeta:canon_any_same_slot_meta(SlotMeta0, [slot(S0)]),
  slotmeta:canon_slot(S0, Slot),
  !.


% -----------------------------------------------------------------------------
%  Dep constraint helpers
% -----------------------------------------------------------------------------

%! cnselect:cn_domain_constraints(+Action, +C, +N, +PackageDeps, +Context, -DomainCons, -DomainReasonTags)
%
% Builds CN-domain constraints and reason tags from a grouped dependency's
% package_dependency terms. The domain is computed by version_domain and
% then turned into `constraint(cn_domain(...))` terms for the prover's
% constraint store.

cnselect:cn_domain_constraints(Action, C, N, PackageDeps, Context, DomainCons, DomainReasonTags) :-
  version_domain:domain_from_packagedeps(Action, C, N, PackageDeps, Domain),
  version_domain:domain_reason_terms(Action, C, N, PackageDeps, Context, DomainReasonTags),
  ( DomainReasonTags == [] ->
      ReasonCons = []
  ; ReasonCons = [constraint(cn_domain_reason(C,N):{ordset(DomainReasonTags)})]
  ),
  ( Domain == none ->
      DomainCons = ReasonCons
  ; dep_slot_key(PackageDeps, Slot),
    DomainCons = [constraint(cn_domain(C,N,Slot):{Domain})|ReasonCons]
  ),
  !.

%! cnselect:domain_constraints_for_any_different_slot(+SlotReq, +DomainCons0, -DomainCons)
%
% Suppresses domain constraints for any_different_slot deps since they
% deliberately seek a different slot from the existing selection.

cnselect:domain_constraints_for_any_different_slot([any_different_slot], _DomainCons0, []) :-
  !.
cnselect:domain_constraints_for_any_different_slot(_SlotReq, DomainCons, DomainCons) :-
  !.

%! cnselect:add_domain_reason_context(+C, +N, +ReasonTags, +Ctx0, -Ctx)
%
% Merges domain reason tags into the proof context via feature unification.

cnselect:add_domain_reason_context(_C, _N, [], Ctx, Ctx) :-
  !.
cnselect:add_domain_reason_context(C, N, ReasonTags, Ctx0, Ctx) :-
  feature_unification:unify([domain_reason(cn_domain(C,N,ReasonTags))], Ctx0, Ctx),
  !.

%! cnselect:dep_has_upper_version_bound(+C, +N, +PackageDeps)
%
% True if PackageDeps contains a `smaller` or `smallerorequal` constraint on (C,N).

cnselect:dep_has_upper_version_bound(C, N, PackageDeps) :-
  member(package_dependency(_Phase, no, C, N, Op, _V, _S, _U), PackageDeps),
  ( Op == smaller
  ; Op == smallerorequal
  ),
  !.

%! cnselect:dep_has_version_constraint(+C, +N, +PackageDeps)
%
% True if any dep on (C,N) carries a non-trivial version operator.

cnselect:dep_has_version_constraint(C, N, PackageDeps) :-
  member(package_dependency(_Phase, no, C, N, Op, _V, _S, _U), PackageDeps),
  nonvar(Op),
  Op \== none,
  !.

%! cnselect:dep_has_explicit_slot_constraint(+C, +N, +PackageDeps)
%
% True if any dep on (C,N) carries an explicit slot requirement.

cnselect:dep_has_explicit_slot_constraint(C, N, PackageDeps) :-
  member(package_dependency(_Phase, no, C, N, _Op, _V, SlotReq, _U), PackageDeps),
  slotmeta:slot_req_explicit_slot_key(SlotReq, _S),
  !.

cnselect:dep_has_tilde_constraint(C, N, PackageDeps) :-
  member(package_dependency(_Phase, no, C, N, tilde, _, _S, _U), PackageDeps),
  !.

cnselect:dep_has_equal_wildcard_constraint(C, N, PackageDeps) :-
  member(package_dependency(_Phase, no, C, N, Op, V0, _S, _U), PackageDeps),
  ( Op == wildcard -> true ; Op == equal, version_term_has_wildcard_(V0) ),
  !.

cnselect:version_term_has_wildcard_(V0) :-
  ( atom(V0) ->
      A = V0
  ; V0 = [_Nums,_Letter,_Rev,A],
    atom(A)
  ),
  sub_atom(A, _Start, _Len, _After, '*'),
  !.


%! cnselect:wildcard_cn_domain_constraints(+MergedDeps, -Constraints) is det.
%
% Scans a list of grouped dependencies for wildcard version constraints
% and emits cn_domain constraint terms for each unique (C,N). These
% constraints are added to the parent's condition list BEFORE the deps,
% so they flow through the constraint store and enable
% selected_cn_unique_or_reprove to resolve sibling conflicts.

cnselect:wildcard_cn_domain_constraints(MergedDeps, Constraints) :-
  findall(C-N-PackageDeps,
          ( member(grouped_package_dependency(_T, C, N, PackageDeps):_?{_}, MergedDeps),
            member(package_dependency(_, no, C, N, Op, _, _, _), PackageDeps),
            ( Op == wildcard ; Op == equal )
          ),
          CNPairs0),
  sort(1, @<, CNPairs0, CNPairs),
  wildcard_cn_domain_constraints_(CNPairs, Constraints).

cnselect:wildcard_cn_domain_constraints_([], []).
cnselect:wildcard_cn_domain_constraints_([C-N-PackageDeps|Rest], Cons) :-
  ( wildcard_upper_bound_domain(C, N, PackageDeps, Domain) ->
      dep_slot_key(PackageDeps, Slot),
      Cons = [constraint(cn_domain(C,N,Slot):{Domain})|Cons1]
  ; Cons = Cons1
  ),
  wildcard_cn_domain_constraints_(Rest, Cons1).


%! cnselect:wildcard_upper_bound_domain(+C, +N, +PackageDeps, -Domain) is semidet.
%
% Derives an upper-bound version_domain from wildcard deps on (C,N).
% For =pkg-0.6* the upper bound is <0.7 (last component incremented).
% Only upper bounds are produced to avoid cross-package conflicts from
% lower bounds. The domain is used by cn_domain_constraints to populate
% the constraint store, enabling selected_cn_unique_or_reprove to
% resolve conflicts when a sibling's transitive dep selects a version
% outside the wildcard range. Bound derivation is delegated to
% version_domain:wildcard_upper_bound/2 (bare wildcards yield no bound).

cnselect:wildcard_upper_bound_domain(C, N, PackageDeps, version_domain(any, Bounds)) :-
  findall(bound(smaller, UpperVer),
          ( member(package_dependency(_, no, C, N, Op, V0, _, _), PackageDeps),
            ( Op == wildcard -> true ; Op == equal, version_term_has_wildcard_(V0) ),
            version_domain:wildcard_upper_bound(V0, UpperVer)
          ),
          Bounds0),
  Bounds0 \== [],
  sort(Bounds0, Bounds).
