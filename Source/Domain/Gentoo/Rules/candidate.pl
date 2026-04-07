/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> CANDIDATE
Candidate selection, slot management, version handling, and ranking for
the portage-ng resolver.

This is the largest implementation submodule of the rules engine.  It is
called by the grouped_package_dependency rule/2 clauses in rules.pl and
by the constraint_guard/2 prover hooks.

== Major sections ==

  1. *Slot primitives* -- canon_slot/2, canon_any_same_slot_meta/2,
     entry_slot_default/3: normalise slot atoms and retrieve defaults.

  2. *Slot restriction merging* -- merge_slot_restriction/5: combine
     slot requirements from multiple deps on the same (C,N).

  3. *Slot constraint queries* -- query_search_slot_constraint/3:
     bridge between slot constraints and the query engine. Version
     constraints are handled directly via query:search goal expansion.

  4. *Installed entry satisfaction* -- installed_entry_satisfies_package_deps/5,
     installed_entry_cn/4: fast-path checks for already-installed packages.

  5. *CN-consistency* -- selected_cn_candidate/5 and friends: ensure that
     for a given (Category, Name) pair only compatible candidates are
     selected across the proof.

  6. *CN-domain reject map* -- cn_domain_reject_key/4,
     cn_domain_candidate_rejected/4, add_cn_domain_rejects/5: bounded
     reprove retry mechanism that learns which candidates to exclude.

  8. *Selected CN uniqueness* -- selected_cn_unique_or_reprove/4,
     selected_cn_domain_compatible_or_reprove/5,
     selected_cn_not_blocked_or_reprove/5: constraint guards called by
     the prover after merging selected_cn/blocked_cn constraints.

  9. *Blocker matching* -- specs_violate_selected/2, blocker_spec_matches_selected/7:
     strong blocker enforcement against already-selected candidates.

 10. *Dependency ordering heuristic* -- order_deps_for_proof/3,
     prioritize_deps/2,3: sort dependency groups for deterministic proof
     search (tighter constraints first).

 11. *Reverse-dep pre-filter* -- candidate_reverse_deps_compatible_with_parent/2:
     avoid selecting a candidate whose RDEPEND would conflict with the parent.

 12. *Self-RDEPEND propagation* -- augment_package_deps_with_self_rdepend/6:
     propagate version bounds from a parent's RDEPEND to tighten child
     candidate selection.

 13. *License masking* -- license_masked/1, effective_license/2: filter out
     candidates whose license is not in ACCEPT_LICENSE.

 14. *Keyword-aware enumeration* -- accepted_keyword_candidate/7: enumerate
     candidates respecting ACCEPT_KEYWORDS ordering and slot locks.

 15. *Provider-reuse reordering* -- candidates_prefer_proven_providers/4:
     Portage-like heuristic to prefer virtual providers whose dependencies
     have already been proven.
*/

:- module(candidate, []).

% =============================================================================
%  Slot primitives
% =============================================================================

%! candidate:canon_slot(+S0, -S)
%
% Canonicalises a slot value to an atom. Integers and numbers are
% converted via atom_number/2; atoms pass through unchanged.

candidate:canon_slot(S0, S) :-
  ( atom(S0)   -> S = S0
  ; integer(S0) -> atom_number(S, S0)
  ; number(S0)  -> atom_number(S, S0)
  ; S = S0
  ),
  !.

%! candidate:canon_any_same_slot_meta(+Meta0, -Canonical)
%
% Extracts and canonicalises the slot from a slot metadata list.
% Succeeds with `[slot(S)]` if Meta0 contains a slot/1 element.

candidate:canon_any_same_slot_meta(Meta0, [slot(S)]) :-
  is_list(Meta0),
  member(slot(S0), Meta0),
  canon_slot(S0, S),
  !.

%! candidate:is_self_dep(+C, +N, +Phase, +Context)
%
% True when Context indicates a build/install self-dependency: the
% parent ebuild (self/1) has the same category and name as the dep.

candidate:is_self_dep(C, N, Phase, Context) :-
  memberchk(self(SelfRepo://SelfEntry), Context),
  query:search([category(C),name(N)], SelfRepo://SelfEntry),
  Phase \== run,
  \+ preference:flag(emptytree).


%! candidate:self_dep_satisfiable(+C, +N, +O, +V, +S, +Context)
%
% True when an installed version of C/N satisfies the version and slot
% constraints. Fails otherwise, causing backtracking to bootstrap
% alternatives.

candidate:self_dep_satisfiable(C, N, O, V, S, Context) :-
  preference:accept_keywords(K),
  ( memberchk(slot(C,N,Ss):{_}, Context) -> true ; Ss = _ ),
  query:search([name(N),category(C),keyword(K),installed(true),
                select(version,O,V),select(slot,constraint(S),Ss)],
               _://_).


%! candidate:entry_slot_default(+Repo, +Entry, -Slot)
%
% Looks up the slot for an entry, defaulting to '0' if unset.

candidate:entry_slot_default(Repo, Entry, Slot) :-
  ( query:search(slot(Slot0), Repo://Entry)
    -> canon_slot(Slot0, Slot)
    ;  Slot = '0'
  ).


% =============================================================================
%  Slot restriction merging
% =============================================================================

%! candidate:merge_slot_restriction(+Action, +C, +N, +PackageDeps, -SlotReq)
%
% Combines slot requirements from all package_dependency/8 terms in
% PackageDeps that match (C,N). Returns `[]` if no slot requirement
% is present, or the merged slot restriction list (e.g. `[slot('3')]`).
% Fails if incompatible slot requirements cannot be merged.

candidate:merge_slot_restriction(Action, C, N, PackageDeps, SlotReq) :-
  merge_slot_restriction_(PackageDeps, Action, C, N, none, Slot0),
  ( Slot0 == none -> SlotReq = []
  ; SlotReq = Slot0
  ).

candidate:merge_slot_restriction_([], _Action, _C, _N, Acc, Acc) :- !.
candidate:merge_slot_restriction_([package_dependency(_Phase,no,C,N,_O,_V,S,_U)|Rest], Action, C, N, Acc0, Acc) :-
  !,
  ( S == []      -> Acc1 = Acc0
  ; Acc0 == none -> Acc1 = S
  ; Acc0 == S    -> Acc1 = Acc0
  ; merge_slot_restriction_pair(Acc0, S, Acc1) -> true
  ; fail
  ),
  merge_slot_restriction_(Rest, Action, C, N, Acc1, Acc).
candidate:merge_slot_restriction_([_|Rest], Action, C, N, Acc0, Acc) :-
  merge_slot_restriction_(Rest, Action, C, N, Acc0, Acc).

candidate:merge_slot_restriction_pair([slot(S0)], [slot(S1),equal], [slot(S),equal]) :-
  canon_slot(S0, S),
  canon_slot(S1, S),
  !.
candidate:merge_slot_restriction_pair([slot(S0),equal], [slot(S1)], [slot(S),equal]) :-
  canon_slot(S0, S),
  canon_slot(S1, S),
  !.
candidate:merge_slot_restriction_pair([slot(S0)], [slot(S1),subslot(Ss0)], [slot(S),subslot(Ss)]) :-
  canon_slot(S0, S),
  canon_slot(S1, S),
  canon_slot(Ss0, Ss),
  !.
candidate:merge_slot_restriction_pair([slot(S0),subslot(Ss0)], [slot(S1)], [slot(S),subslot(Ss)]) :-
  canon_slot(S0, S),
  canon_slot(S1, S),
  canon_slot(Ss0, Ss),
  !.
candidate:merge_slot_restriction_pair([slot(S0)], [slot(S1),subslot(Ss0),equal], [slot(S),subslot(Ss),equal]) :-
  canon_slot(S0, S),
  canon_slot(S1, S),
  canon_slot(Ss0, Ss),
  !.
candidate:merge_slot_restriction_pair([slot(S0),subslot(Ss0),equal], [slot(S1)], [slot(S),subslot(Ss),equal]) :-
  canon_slot(S0, S),
  canon_slot(S1, S),
  canon_slot(Ss0, Ss),
  !.
candidate:merge_slot_restriction_pair([slot(S0),equal], [slot(S1),subslot(Ss0)], [slot(S),subslot(Ss),equal]) :-
  canon_slot(S0, S),
  canon_slot(S1, S),
  canon_slot(Ss0, Ss),
  !.
candidate:merge_slot_restriction_pair([slot(S0),subslot(Ss0)], [slot(S1),equal], [slot(S),subslot(Ss),equal]) :-
  canon_slot(S0, S),
  canon_slot(S1, S),
  canon_slot(Ss0, Ss),
  !.
candidate:merge_slot_restriction_pair([slot(S0),equal], [slot(S1),subslot(Ss0),equal], [slot(S),subslot(Ss),equal]) :-
  canon_slot(S0, S),
  canon_slot(S1, S),
  canon_slot(Ss0, Ss),
  !.
candidate:merge_slot_restriction_pair([slot(S0),subslot(Ss0),equal], [slot(S1),equal], [slot(S),subslot(Ss),equal]) :-
  canon_slot(S0, S),
  canon_slot(S1, S),
  canon_slot(Ss0, Ss),
  !.


% =============================================================================
%  Slot constraint queries
% =============================================================================

%! candidate:query_search_slot_constraint(+SlotReq, +RepoEntry, -SlotMeta)
%
% Queries the knowledge base for entries matching a slot constraint.
% Bridges between the dependency's slot requirement format and the
% query engine's `select(slot, constraint(...), ...)` interface.
% Handles all slot requirement forms: `[]` (any), `[slot(S)]`,
% `[slot(S),subslot(Ss)]`, `[slot(S),equal]`, `[any_same_slot]`,
% `[any_different_slot]`, and combinations with `equal`.

candidate:query_search_slot_constraint(SlotReq, RepoEntry, SlotMeta) :-
  RepoEntry = Repo://Id,
  cached_slot_meta(Repo, Id, AllMeta),
  slot_constraint_match(SlotReq, Repo, Id, AllMeta, SlotMeta).


%! candidate:cached_slot_meta(+Repo, +Id, -AllMeta)
%
% Returns the full slot metadata list for Repo/Id, using
% memo_slot_meta_cache AVL to avoid redundant findall allocations.

candidate:cached_slot_meta(Repo, Id, AllMeta) :-
  ( nb_current(memo_slot_meta_cache, CacheAVL),
    get_assoc(Repo-Id, CacheAVL, Cached)
  ->
    AllMeta = Cached
  ;
    findall(R, cache:entry_metadata(Repo, Id, slot, R), AllMeta),
    ( nb_current(memo_slot_meta_cache, AVL0) -> true ; empty_assoc(AVL0) ),
    put_assoc(Repo-Id, AVL0, AllMeta, AVL1),
    nb_setval(memo_slot_meta_cache, AVL1)
  ).


%! candidate:slot_constraint_match(+SlotReq, +Repo, +Id, +AllMeta, -SlotMeta)
%
% Validates a slot constraint against the cached slot metadata and returns
% the appropriate metadata list. Preserves the semantics of the original
% query:search(select(slot,...)) dispatch.

candidate:slot_constraint_match(SlotReq, Repo, Id, AllMeta, SlotMeta) :-
  ( SlotReq == [] ->
      cache:ordered_entry(Repo, Id, _, _, _),
      SlotMeta = AllMeta
  ; SlotReq = [slot(S0)] ->
      canon_slot(S0, S),
      memberchk(slot(S), AllMeta),
      SlotMeta = AllMeta
  ; SlotReq = [slot(S0),subslot(Ss)] ->
      canon_slot(S0, S),
      ( memberchk(slot(S), AllMeta),
        memberchk(subslot(Ss), AllMeta)
      ->
        SlotMeta = AllMeta
      ; canon_slot(Ss, Ss1),
        Ss1 == S,
        \+ cache:entry_metadata(Repo, Id, subslot, _),
        memberchk(slot(S), AllMeta),
        SlotMeta = [slot(S),subslot(Ss1)]
      )
  ; SlotReq = [slot(S0),equal] ->
      canon_slot(S0, S),
      memberchk(slot(S), AllMeta),
      SlotMeta = AllMeta
  ; SlotReq = [slot(S0),subslot(Ss),equal] ->
      canon_slot(S0, S),
      ( memberchk(slot(S), AllMeta),
        memberchk(subslot(Ss), AllMeta)
      ->
        SlotMeta = AllMeta
      ; canon_slot(Ss, Ss1),
        Ss1 == S,
        \+ cache:entry_metadata(Repo, Id, subslot, _),
        memberchk(slot(S), AllMeta),
        SlotMeta = [slot(S),subslot(Ss1),equal]
      )
  ; SlotReq = [any_same_slot] ->
      cache:ordered_entry(Repo, Id, _, _, _),
      findall(slot(S), member(slot(S), AllMeta), SlotMeta0),
      canon_any_same_slot_meta(SlotMeta0, SlotMeta)
  ; SlotReq = [any_different_slot] ->
      cache:ordered_entry(Repo, Id, _, _, _),
      findall(slot(S), member(slot(S), AllMeta), SlotMeta)
  ; query:search(select(slot,constraint(SlotReq),SlotMeta), Repo://Id)
  ).


% =============================================================================
%  Installed entry satisfaction
% =============================================================================

%! candidate:installed_entry_satisfies_package_deps(+Action, +C, +N, +PackageDeps, +Installed)
%
% True if the installed entry satisfies all version constraints in
% PackageDeps for (C,N). Used as a fast-path guard in the grouped
% dependency rule to skip candidate selection when an installed package
% already satisfies the dependency.

candidate:installed_entry_satisfies_package_deps(_Action, _C, _N, [], _Installed) :- !.
candidate:installed_entry_satisfies_package_deps(_Action, C, N, PackageDeps, Repo://Id) :-
  cache:ordered_entry(Repo, Id, _, _, InstalledVer),
  forall(member(package_dependency(_,no,C,N,O,V,_,_), PackageDeps),
         preference:version_match(O, InstalledVer, V)).

%! candidate:installed_entry_cn(+C, +N, -Repo, -Entry)
%
% Looks up an installed entry for (C,N) in the VDB (pkg repo).

candidate:installed_entry_cn(C, N, pkg, Entry) :-
  query:search([name(N),category(C),installed(true)], pkg://Entry),
  !.


% =============================================================================
%  CN-consistency: pick already-selected entry when possible
% =============================================================================

%! candidate:selected_cn_candidate(+Action, +C, +N, +Context, -RepoEntry)
%
% Enumerates previously-selected candidates for (C,N) from the context's
% `selected_cn` constraint. Filters by action compatibility and slot
% lock. Used to prefer reusing an existing choice over fresh enumeration.

candidate:selected_cn_candidate(Action, C, N, Context, FoundRepo://Candidate) :-
  memberchk(constraint(selected_cn(C,N):{ordset(SelectedSet)}), Context),
  member(selected(FoundRepo, Candidate, ActSel, _CandVer, SelSlotMeta), SelectedSet),
  ( (Action == install ; Action == run),
    (ActSel == install ; ActSel == run)
  -> true
  ; ActSel == Action
  ),
  ( memberchk(slot(C,N,SsLock0):{_}, Context) ->
      canon_any_same_slot_meta(SsLock0, SsLock),
      canon_any_same_slot_meta(SelSlotMeta, SsSel),
      SsSel == SsLock
  ; true
  ),
  cache:ordered_entry(FoundRepo, Candidate, C, N, _),
  \+ preference:masked(FoundRepo://Candidate).

%! candidate:selected_cn_candidate_compatible(+Action, +C, +N, +SlotReq, +PackageDeps, +Context, -RepoEntry)
%
% Like selected_cn_candidate/5 but also verifies slot and version constraints.

candidate:selected_cn_candidate_compatible(Action, C, N, SlotReq, PackageDeps, Context, FoundRepo://Candidate) :-
  selected_cn_candidate(Action, C, N, Context, FoundRepo://Candidate),
  query_search_slot_constraint(SlotReq, FoundRepo://Candidate, _),
  grouped_dep_candidate_satisfies_constraints(Action, C, N, PackageDeps, Context, FoundRepo://Candidate).

%! candidate:selected_cn_rejected_candidates(+Action, +C, +N, +SlotReq, +PackageDeps, +Context, -Rejected)
%
% Collects previously-selected candidates for (C,N) that do NOT satisfy
% the current dependency's constraints. Used to exclude them from fresh
% enumeration.

candidate:selected_cn_rejected_candidates(Action, C, N, SlotReq, PackageDeps, Context, Rejected) :-
  grouped_dep_effective_domain_precomputed(Action, C, N, PackageDeps, Context, EffDom, RejectDom),
  findall(Repo://Entry,
          ( selected_cn_candidate(Action, C, N, Context, Repo://Entry),
            query_search_slot_constraint(SlotReq, Repo://Entry, _),
            \+ grouped_dep_candidate_satisfies_constraints_precomputed(
                    C, N, PackageDeps, EffDom, RejectDom, Repo://Entry)
          ),
          Rejected0),
  sort(Rejected0, Rejected),
  !.

%! candidate:grouped_dep_candidate_satisfies_constraints(+Action, +C, +N, +PackageDeps, +Context, +RepoEntry)
%
% True if RepoEntry satisfies all version constraints and the effective
% domain for (C,N) in the given context.

candidate:grouped_dep_candidate_satisfies_constraints(Action, C, N, PackageDeps, Context, Repo://Entry) :-
  forall(member(package_dependency(_Phase,no,C,N,O,V,_SlotReq,_Use), PackageDeps),
         query:search(select(version, O, V), Repo://Entry)),
  grouped_dep_candidate_satisfies_effective_domain(Action, C, N, PackageDeps, Context, Repo://Entry),
  !.

%! candidate:grouped_dep_candidate_satisfies_constraints_precomputed(+C, +N, +PackageDeps, +EffDom, +RejectDom, +RepoEntry)
%
% Like grouped_dep_candidate_satisfies_constraints/6 but uses precomputed
% effective and reject domains to avoid redundant domain intersection.

candidate:grouped_dep_candidate_satisfies_constraints_precomputed(C, N, PackageDeps, EffDom, RejectDom, Repo://Entry) :-
  forall(member(package_dependency(_Phase,no,C,N,O,V,_SlotReq,_Use), PackageDeps),
         query:search(select(version, O, V), Repo://Entry)),
  grouped_dep_candidate_satisfies_effective_domain_precomputed(EffDom, RejectDom, C, N, Repo://Entry),
  !.

%! candidate:grouped_dep_effective_domain_precomputed(+Action, +C, +N, +PackageDeps, +Context, -EffDom, -RejectDom)
%
% Precomputes both the effective version domain and the scoped reject
% domain for a grouped dependency. Avoids recomputing these per-candidate.

candidate:grouped_dep_effective_domain_precomputed(Action, C, N, PackageDeps, Context, EffectiveDomain, RejectDomain) :-
  grouped_dep_effective_domain(Action, C, N, PackageDeps, Context, EffectiveDomain),
  context_cn_reject_scope(C, N, Context, EffectiveDomain, RejectScope),
  cn_reject_scoped_domain(RejectScope, EffectiveDomain, RejectDomain),
  !.

candidate:grouped_dep_candidate_satisfies_effective_domain(Action, C, N, PackageDeps, Context, RepoEntry) :-
  grouped_dep_effective_domain_precomputed(Action, C, N, PackageDeps, Context, EffectiveDomain, RejectDomain),
  grouped_dep_candidate_satisfies_effective_domain_precomputed(EffectiveDomain, RejectDomain, C, N, RepoEntry),
  !.

candidate:grouped_dep_candidate_satisfies_effective_domain_precomputed(EffectiveDomain, RejectDomain, C, N, RepoEntry) :-
  \+ version_domain:domain_inconsistent(EffectiveDomain),
  \+ cn_domain_candidate_rejected(C, N, RejectDomain, RepoEntry),
  version_domain:domain_allows_candidate(EffectiveDomain, RepoEntry),
  !.

%! candidate:grouped_dep_effective_domain(+Action, +C, +N, +PackageDeps, +Context, -EffDom)
%
% Computes the effective version domain for a grouped dependency by
% intersecting the dep's own constraints, the context's CN domain,
% and any learned domain from prior reprove iterations.

candidate:grouped_dep_effective_domain(Action, C, N, PackageDeps, Context, EffectiveDomain) :-
  version_domain:domain_from_packagedeps(Action, C, N, PackageDeps, DepDomain0),
  ( context_cn_domain_constraint(C, N, Context, CtxDomain0) ->
      ( version_domain:domain_meet(CtxDomain0, DepDomain0, D1) -> true
      ; D1 = version_domain(slots([]), [])
      )
  ; D1 = DepDomain0
  ),
  apply_learned_domain(C, N, PackageDeps, D1, EffectiveDomain),
  !.

%! candidate:apply_learned_domain(+C, +N, +PackageDeps, +D0, -D)
%
% Intersects domain D0 with any learned domain constraints for (C,N)
% from the prover's learned constraint store. Learned domains come
% from prior reprove iterations (conflict-driven domain narrowing).

candidate:apply_learned_domain(C, N, PackageDeps, D0, D) :-
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

%! candidate:dep_slot_key(+PackageDeps, -Slot)
%
% Extracts a canonical slot key from the first slotted dep in PackageDeps,
% or returns `any` if none carries a slot requirement.

candidate:dep_slot_key(PackageDeps, Slot) :-
  member(package_dependency(_, _, _, _, _, _, SlotReq, _), PackageDeps),
  SlotReq = [slot(S)|_], canon_slot(S, Slot), !.
candidate:dep_slot_key(_, any).

%! candidate:context_cn_domain_constraint(+C, +N, +Context, -Domain)
%
% Extracts the cn_domain constraint for (C,N) from the ?{Context} list.

candidate:context_cn_domain_constraint(C, N, Context, Domain) :-
  is_list(Context),
  memberchk(constraint(cn_domain(C,N):{Domain}), Context),
  !.

%! candidate:context_cn_domain_reason(+C, +N, +Context, -Reasons)
%
% Extracts domain reason tags for (C,N) from the ?{Context} list.

candidate:context_cn_domain_reason(C, N, Context, Reasons) :-
  is_list(Context),
  ( memberchk(constraint(cn_domain_reason(C,N):{ordset(Reasons0)}), Context) ->
      Reasons = Reasons0
  ; memberchk(domain_reason(cn_domain(C,N,Reasons0)), Context) ->
      Reasons = Reasons0
  ; Reasons = []
  ),
  !.

%! candidate:context_selected_cn_candidates(+C, +N, +Context, -Candidates)
%
% Extracts the list of previously-selected candidates for (C,N) from
% the constraint store in Context.

candidate:context_selected_cn_candidates(C, N, Context, Candidates) :-
  is_list(Context),
  memberchk(constraint(selected_cn(C,N):{ordset(SelectedSet)}), Context),
  findall(Repo://Entry,
          member(selected(Repo,Entry,_Act,_SelVer,_SelSlotMeta), SelectedSet),
          Candidates0),
  sort(Candidates0, Candidates),
  Candidates \== [],
  !.

%! candidate:context_cn_reject_scope(+C, +N, +Context, +Domain, -Scope)
%
% Determines the reject scope for (C,N): either a specific slot from
% the context or derived from the domain.

candidate:context_cn_reject_scope(C, N, Context, Domain, Scope) :-
  ( context_slot_scope(C, N, Context, Scope0) ->
      Scope = Scope0
  ; domain_slot_scope(Domain, Scope)
  ),
  !.

candidate:context_slot_scope(C, N, Context, slot(Slot)) :-
  is_list(Context),
  memberchk(slot(C,N,Ss0):{_}, Context),
  canon_any_same_slot_meta(Ss0, [slot(Slot)]),
  !.

candidate:domain_slot_scope(version_domain(slots([S0]), _Bounds), slot(S)) :-
  canon_slot(S0, S),
  !.
candidate:domain_slot_scope(_Domain, any) :-
  !.

candidate:cn_reject_scope_canon(slot(S0), slot(S)) :-
  canon_slot(S0, S),
  !.
candidate:cn_reject_scope_canon(any, any) :-
  !.
candidate:cn_reject_scope_canon(_Other, any) :-
  !.

candidate:cn_reject_scoped_domain(any, Domain, Domain) :-
  !.
candidate:cn_reject_scoped_domain(Scope0, Domain, scoped(Scope, Domain)) :-
  cn_reject_scope_canon(Scope0, Scope),
  !.

%! candidate:snapshot_selected_cn_candidates(+C, +N, -Candidates)
%
% Retrieves the memoized snapshot of selected candidates for (C,N).

candidate:snapshot_selected_cn_candidates(C, N, Candidates) :-
  nb_current(memo_selected_cn_snap, AVL),
  get_assoc(C-N, AVL, Candidates),
  Candidates \== [],
  !.

%! candidate:record_selected_cn_snapshot(+C, +N, +SelectedSet)
%
% Records a snapshot of the current selected candidates for (C,N) into
% the memoization store, replacing any previous snapshot.

candidate:record_selected_cn_snapshot(C, N, SelectedSet) :-
  findall(Repo://Entry,
          member(selected(Repo,Entry,_Act,_SelVer,_SelSlotMeta), SelectedSet),
          Candidates0),
  sort(Candidates0, Candidates),
  ( nb_current(memo_selected_cn_snap, AVL0) -> true ; empty_assoc(AVL0) ),
  put_assoc(C-N, AVL0, Candidates, AVL1),
  nb_setval(memo_selected_cn_snap, AVL1),
  !.

%! candidate:snapshot_blocked_cn_sources(+C, +N, -Sources)
%
% Retrieves the memoized blocker source snapshot for (C,N).

candidate:snapshot_blocked_cn_sources(C, N, Sources) :-
  nb_current(memo_blocked_cn_source_snap, AVL),
  get_assoc(C-N, AVL, Sources),
  Sources \== [],
  !.

%! candidate:record_blocked_cn_source_snapshot(+C, +N, +Sources)
%
% Records blocker source entries for (C,N), merging with any existing
% snapshot via ord_union.

candidate:record_blocked_cn_source_snapshot(C, N, Sources0) :-
  sort(Sources0, Sources),
  Sources \== [],
  ( nb_current(memo_blocked_cn_source_snap, AVL0) -> true ; empty_assoc(AVL0) ),
  ( get_assoc(C-N, AVL0, OldSources) -> true ; OldSources = [] ),
  ord_union(OldSources, Sources, MergedSources),
  put_assoc(C-N, AVL0, MergedSources, AVL1),
  nb_setval(memo_blocked_cn_source_snap, AVL1),
  !.
candidate:record_blocked_cn_source_snapshot(_C, _N, _Sources) :-
  !.

%! candidate:reason_linked_selected_reprove_target(+Reasons, -SourceC, -SourceN, -SourceCandidates)
%
% Follows introduced_by reason chains to find the originally-selected
% candidate that should be rejected in a cross-package reprove.

candidate:reason_linked_selected_reprove_target(Reasons, SourceC, SourceN, [SourceRepo://SourceEntry]) :-
  is_list(Reasons),
  member(introduced_by(OriginRepo://OriginEntry, _ReasonAction, _ReasonWhat), Reasons),
  query:search([category(OriginC),name(OriginN)], OriginRepo://OriginEntry),
  snapshot_blocked_cn_sources(OriginC, OriginN, Sources),
  member(source(SourceRepo,SourceEntry,_Phase,_O,_V,_SlotReq), Sources),
  query:search([category(SourceC),name(SourceN)], SourceRepo://SourceEntry),
  snapshot_selected_cn_candidates(SourceC, SourceN, SelectedSourceCandidates),
  memberchk(SourceRepo://SourceEntry, SelectedSourceCandidates),
  !.

%! candidate:domain_conflicting_candidates(+Domain, +Candidates, -Conflicting)
%
% Filters Candidates to those not allowed by Domain.

candidate:domain_conflicting_candidates(_Domain, [], []) :-
  !.
candidate:domain_conflicting_candidates(Domain, Candidates, Conflicting) :-
  findall(RepoEntry,
          ( member(RepoEntry, Candidates),
            \+ version_domain:domain_allows_candidate(Domain, RepoEntry)
          ),
          Conflicting0),
  sort(Conflicting0, Conflicting),
  !.

%! candidate:constraint_conflicting_candidates(+Action, +C, +N, +PackageDeps, +Context, +Candidates, -Conflicting)
%
% Filters Candidates to those not satisfying the grouped dependency constraints.

candidate:constraint_conflicting_candidates(_Action, _C, _N, _PackageDeps, _Context, [], []) :-
  !.
candidate:constraint_conflicting_candidates(Action, C, N, PackageDeps, Context, Candidates, Conflicting) :-
  findall(RepoEntry,
          ( member(RepoEntry, Candidates),
            \+ grouped_dep_candidate_satisfies_constraints(Action, C, N, PackageDeps, Context, RepoEntry)
          ),
          Conflicting0),
  sort(Conflicting0, Conflicting),
  !.

%! candidate:maybe_request_grouped_dep_reprove(+Action, +C, +N, +PackageDeps, +Context)
%
% When CN-domain reprove is enabled and the effective domain conflicts
% with already-selected candidates, throws a `prover_reprove/1` exception
% requesting the prover to retry with the conflicting candidates rejected.
% This is the main conflict-driven learning entry point for grouped deps.

candidate:maybe_request_grouped_dep_reprove(Action, C, N, PackageDeps, Context) :-
  cn_domain_reprove_enabled,
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
candidate:maybe_request_grouped_dep_reprove(_Action, _C, _N, _PackageDeps, _Context) :-
  fail.


% =============================================================================
%  CN-domain reject map (bounded reprove retries)
% =============================================================================

%! candidate:cn_domain_reject_key(+C, +N, +Domain, -Key)
%
% Computes a canonical reject-map key from (C,N) and a domain term.
% Keys are normalised to `key(C,N,Scope,Domain)` where Scope is
% either `slot(S)` or `any`, enabling both slot-specific and global
% reject tracking.

candidate:cn_domain_reject_key(C, N, scoped(Scope0, Domain0), key(C,N,Scope,Domain)) :-
  cn_reject_scope_canon(Scope0, Scope),
  version_domain:domain_normalize(Domain0, Domain),
  !.
candidate:cn_domain_reject_key(C, N, Domain0, key(C,N,Scope,Domain)) :-
  version_domain:domain_normalize(Domain0, Domain),
  domain_slot_scope(Domain, Scope),
  !.

%! candidate:cn_domain_candidate_rejected(+C, +N, +Domain, +RepoEntry)
%
% True if RepoEntry has been rejected for (C,N) under Domain in a prior
% reprove iteration. Checks slot-scoped, domain-scoped, and global
% reject sets.

candidate:cn_domain_candidate_rejected(C, N, Domain0, RepoEntry) :-
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

%! candidate:add_cn_domain_rejects(+C, +N, +Domain, +Candidates, -Added)
%
% Records Candidates as rejected for (C,N) under Domain. Added is
% `true` if any new entries were added, `false` otherwise. Called by
% heuristic:handle_reprove/2 when a reprove conflict is processed.

candidate:add_cn_domain_rejects(C, N, Domain0, Candidates0, Added) :-
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

%! candidate:add_cn_domain_origin_rejects(+Reasons, -Added)
%
% For each `introduced_by` reason, rejects the origin candidate globally.
% This enables cross-package conflict learning.

candidate:add_cn_domain_origin_rejects(Reasons, Added) :-
  is_list(Reasons),
  findall(C0-N0-Repo://Entry,
          ( member(introduced_by(Repo://Entry, _Action, _Why), Reasons),
            query:search([category(C0),name(N0)], Repo://Entry)
          ),
          Origins0),
  sort(Origins0, Origins),
  add_cn_domain_origin_rejects_(Origins, false, Added),
  !.
candidate:add_cn_domain_origin_rejects(_Reasons, false) :-
  !.

candidate:add_cn_domain_origin_rejects_([], Added, Added) :-
  !.
candidate:add_cn_domain_origin_rejects_([C-N-Repo://Entry|Rest], Added0, Added) :-
  add_cn_domain_rejects(C, N, none, [Repo://Entry], Added1),
  ( Added0 == true ->
      Added2 = true
  ; Added1 == true ->
      Added2 = true
  ; Added2 = false
  ),
  add_cn_domain_origin_rejects_(Rest, Added2, Added).

%! candidate:cn_domain_reprove_enabled
%
% Guard predicate: succeeds when the prover's reprove mechanism is active.

candidate:cn_domain_reprove_enabled :-
  prover:reprove_enabled,
  !.

%! candidate:maybe_request_cn_domain_reprove(+C, +N, +Domain, +Selected)
%
% Throws prover_reprove/1 if reprove is enabled and Selected is non-empty.

candidate:maybe_request_cn_domain_reprove(C, N, Domain, Selected) :-
  maybe_request_cn_domain_reprove(C, N, Domain, Selected, []).

%! candidate:maybe_request_cn_domain_reprove(+C, +N, +Domain, +Selected, +Reasons)
%
% Extended variant that includes reason tags in the reprove exception.

candidate:maybe_request_cn_domain_reprove(C, N, Domain, Selected, Reasons) :-
  cn_domain_reprove_enabled,
  findall(Repo://Entry,
          member(selected(Repo,Entry,_Act,_SelVer,_SelSlotMeta), Selected),
          Candidates0),
  sort(Candidates0, Candidates),
  Candidates \== [],
  throw(prover_reprove(cn_domain(C, N, Domain, Candidates, Reasons))).
candidate:maybe_request_cn_domain_reprove(_C, _N, _Domain, _Selected, _Reasons) :-
  true.


% =============================================================================
%  Selected CN uniqueness / constraint enforcement
% =============================================================================

%! candidate:selected_cn_unique_or_reprove(+C, +N, +SelectedMerged, +Constraints)
%
% Enforces that at most one concrete entry is selected per (C,N) (or per
% slot when multislot is allowed). If uniqueness is violated and reprove
% is enabled, learns the conflict and throws prover_reprove/1.
% Called by constraint_guard for selected_cn constraints.

candidate:selected_cn_unique_or_reprove(C, N, SelectedMerged, Constraints) :-
  selected_cn_unique(C, N, SelectedMerged, Constraints),
  !.
candidate:selected_cn_unique_or_reprove(C, N, SelectedMerged, Constraints) :-
  cn_domain_reprove_enabled,
  get_assoc(cn_domain(C,N), Constraints, Domain),
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
candidate:selected_cn_unique_or_reprove(C, N, _SelectedMerged, Constraints) :-
  cn_domain_reprove_enabled,
  get_assoc(cn_domain(C,N), Constraints, _Domain),
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
candidate:selected_cn_unique_or_reprove(_C, _N, _SelectedMerged, _Constraints) :-
  fail.

%! candidate:record_slot_conflict_if_multiple(+C, +N, +Selected)
%
% Records a slot conflict memo when the domain is inconsistent and
% multiple entries are selected for (C,N).  Persists across reprove
% attempts so the assumption clause can include slot conflict details.

candidate:record_slot_conflict_if_multiple(C, N, Selected) :-
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


%! candidate:find_adjustable_origin(+Reasons, -OriginC, -OriginN, -RepoEntry)
%
% Finds an origin candidate from introduced_by reasons that has a learned
% domain, making it a candidate for version exclusion during reprove.

candidate:find_adjustable_origin(Reasons, OriginC, OriginN, Repo://Entry) :-
  member(introduced_by(Repo://Entry, _Action, _Why), Reasons),
  cache:ordered_entry(Repo, Entry, OriginC, OriginN, _),
  prover:learned(cn_domain(OriginC, OriginN, _), _), !.

%! candidate:maybe_learn_parent_narrowing(+C, +N, +PackageDeps, +Context)
%
% When a dependency on (C,N) is unsatisfiable, learns to exclude the
% parent version that introduced the dependency. This is the
% "wrong-level fix": the parent introduced a dep that cannot be
% satisfied, so exclude the parent version and reprove.

candidate:maybe_learn_parent_narrowing(C, N, PackageDeps, Context) :-
  \+ is_pdepend_failure(PackageDeps, Context),
  \+ is_multislot_miss(C, N, PackageDeps, Context),
  is_list(Context),
  memberchk(self(ParentRepo://ParentEntry), Context),
  cache:ordered_entry(ParentRepo, ParentEntry, ParentC, ParentN, _),
  query:search(version(ParentVer), ParentRepo://ParentEntry),
  ExcludeDomain = version_domain(any, [bound(smaller, ParentVer)]),
  prover:learn(cn_domain(ParentC, ParentN, any), ExcludeDomain, Added),
  Added == true,
  cn_domain_reprove_enabled,
  throw(prover_reprove(cn_domain(ParentC, ParentN, none, [ParentRepo://ParentEntry], [parent_narrowing]))).

%! candidate:is_pdepend_failure(+PackageDeps, +Context)
%
% True if the dependency set involves PDEPEND or after_only context,
% where parent narrowing should not be applied.

candidate:is_pdepend_failure(PackageDeps, _Context) :-
  member(package_dependency(pdepend, _, _, _, _, _, _, _), PackageDeps),
  !.
candidate:is_pdepend_failure(_, Context) :-
  is_list(Context),
  memberchk(after_only(_), Context),
  !.

%! candidate:is_multislot_miss(+C, +N, +PackageDeps, +Context)
%
% True if the dep targets a slot not yet represented in the selected set,
% where parent narrowing would be counterproductive.

candidate:is_multislot_miss(C, N, PackageDeps, Context) :-
  member(package_dependency(_, _, C, N, _, _, [slot(DepSlot0)|_], _), PackageDeps),
  canon_slot(DepSlot0, DepSlot),
  is_list(Context),
  memberchk(constraint(selected_cn(C,N):{ordset(Selected)}), Context),
  \+ ( member(selected(_, _, _, _, SlotMeta), Selected),
       selected_cn_slot_key_(SlotMeta, DepSlot) ),
  !.

%! candidate:selected_cn_partition_by_domain(+Domain, +Selected, -Allowed, -Conflicting)
%
% Partitions selected entries into those allowed by Domain and those
% that conflict with it.

candidate:selected_cn_partition_by_domain(_Domain, [], [], []) :-
  !.
candidate:selected_cn_partition_by_domain(Domain, [Sel|Rest], [Sel|AllowedRest], ConflictingRest) :-
  Sel = selected(Repo,Entry,_Act,_SelVer,_SelSlotMeta),
  version_domain:domain_allows_candidate(Domain, Repo://Entry),
  !,
  selected_cn_partition_by_domain(Domain, Rest, AllowedRest, ConflictingRest).
candidate:selected_cn_partition_by_domain(Domain, [Sel|Rest], AllowedRest, [Sel|ConflictingRest]) :-
  selected_cn_partition_by_domain(Domain, Rest, AllowedRest, ConflictingRest).

%! candidate:selected_cn_not_blocked_or_reprove(+C, +N, +Specs, +Selected, +Constraints)
%
% Enforces strong blocker constraints: if any Spec in Specs violates an
% already-selected entry, attempts reprove by rejecting the blocker source.
% Called by constraint_guard for blocked_cn constraints.

candidate:selected_cn_not_blocked_or_reprove(_C, _N, Specs, Selected, _Constraints) :-
  \+ specs_violate_selected(Specs, Selected),
  !.
candidate:selected_cn_not_blocked_or_reprove(C, N, _Specs, _Selected, Constraints) :-
  cn_domain_reprove_enabled,
  blocked_cn_source_reprove_target(C, N, Constraints, SourceC, SourceN, Candidates),
  Candidates \== [],
  throw(prover_reprove(cn_domain(SourceC, SourceN, none, Candidates, []))).
candidate:selected_cn_not_blocked_or_reprove(_C, _N, _Specs, _Selected, _Constraints) :-
  fail.

%! candidate:blocked_cn_source_reprove_target(+C, +N, +Constraints, -SourceC, -SourceN, -Candidates)
%
% Finds the source candidate that introduced a blocker on (C,N) for
% targeted reprove rejection.

candidate:blocked_cn_source_reprove_target(C, N, Constraints, SourceC, SourceN, [Repo://Entry]) :-
  get_assoc(blocked_cn_source(C,N), Constraints, ordset(Sources)),
  member(source(Repo,Entry,_Phase,_O,_V,_SlotReq), Sources),
  query:search([category(SourceC),name(SourceN)], Repo://Entry),
  !.

%! candidate:selected_cn_domain_compatible_or_reprove(+C, +N, +Domain, +Selected, +Constraints)
%
% Checks that at least one entry in Selected is allowed by Domain.
% If not, learns the domain and requests reprove. Called by
% constraint_guard for cn_domain and selected_cn constraints.

candidate:selected_cn_domain_compatible_or_reprove(C, N, Domain, Selected, Constraints) :-
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

%! candidate:prefer_global_selected_reject_from_domain(+C, +N, +Domain, +Selected, +Constraints)
%
% Heuristic: when there are already selected candidates and the domain
% has an equal bound, prefer a global (domain=none) reject to keep the
% reprove search space manageable.

candidate:prefer_global_selected_reject_from_domain(C, N, Domain, Selected, Constraints) :-
  Selected \== [],
  domain_has_equal_bound(Domain),
  \+ selected_cn_requires_same_slot_multiversion(C, N, Constraints),
  !.

%! candidate:domain_has_equal_bound(+Domain)
%
% True if Domain has an `equal` bound.

candidate:domain_has_equal_bound(version_domain(_Slots, Bounds)) :-
  member(bound(equal, _Req), Bounds),
  !.

%! candidate:selected_cn_allow_multislot_constraints(+C, +N, +SlotReq, +PackageDeps, -Constraints)
%
% Generates an `allow_multislot` constraint when the dependency carries
% a slot or version restriction that justifies multi-slot selection.

candidate:selected_cn_allow_multislot_constraints(C, N, SlotReq, PackageDeps, [constraint(selected_cn_allow_multislot(C,N):{true})]) :-
  ( SlotReq = [slot(_)|_]
  ; SlotReq == [any_same_slot]
  ; SlotReq == [any_different_slot]
  ; all_deps_exactish_versioned(PackageDeps)
  ; dep_has_version_constraint(C, N, PackageDeps)
  ),
  !.
candidate:selected_cn_allow_multislot_constraints(_C, _N, _SlotReq, _PackageDeps, []).

%! candidate:selected_cn_unique(+C, +N, +SelectedMerged, +Constraints)
%
% Dispatches to strict, per-slot, or per-slot+subslot uniqueness check
% based on whether multislot is allowed and multiversion is required.

candidate:selected_cn_unique(C, N, SelectedMerged, Constraints) :-
  ( get_assoc(selected_cn_allow_multislot(C,N), Constraints, _AllowFlag) ->
      ( selected_cn_requires_same_slot_multiversion(C, N, Constraints) ->
          selected_cn_unique_per_slot_or_subslot(SelectedMerged)
      ; selected_cn_unique_per_slot(SelectedMerged)
      )
  ; selected_cn_unique_strict(SelectedMerged)
  ).

candidate:selected_cn_unique_strict([]) :- !.
candidate:selected_cn_unique_strict([selected(Repo,Entry,_Act,_Ver,_SlotMeta)|Rest]) :-
  forall(member(selected(Repo2,Entry2,_A2,_V2,_SlotMeta2), Rest),
         ( Repo2 == Repo,
           Entry2 == Entry
         )),
  selected_cn_unique_strict(Rest).

candidate:selected_cn_unique_per_slot([]) :- !.
candidate:selected_cn_unique_per_slot([selected(Repo,Entry,_Act,_Ver,SlotMeta)|Rest]) :-
  selected_cn_slot_key_(SlotMeta, Slot),
  forall(member(selected(Repo2,Entry2,_A2,_V2,SlotMeta2), Rest),
         ( selected_cn_slot_key_(SlotMeta2, Slot2),
           ( Slot2 \== Slot -> true
           ; Repo2 == Repo, Entry2 == Entry
           )
         )),
  selected_cn_unique_per_slot(Rest).

candidate:selected_cn_unique_per_slot_or_subslot([]) :- !.
candidate:selected_cn_unique_per_slot_or_subslot([selected(Repo,Entry,_Act,_Ver,SlotMeta)|Rest]) :-
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

%! candidate:selected_cn_requires_same_slot_multiversion(+C, +N, +Constraints)
%
% True if the CN domain is inconsistent, indicating that multiple
% versions in the same slot are required (subslot-level uniqueness).

candidate:selected_cn_requires_same_slot_multiversion(C, N, Constraints) :-
  get_assoc(cn_domain(C,N), Constraints, Domain),
  version_domain:domain_inconsistent(Domain),
  !.

candidate:selected_cn_slot_subslot_key_(Repo, Entry, SlotMeta0, slot_subslot(Slot, SubSlot)) :-
  canon_any_same_slot_meta(SlotMeta0, [slot(S0)]),
  canon_slot(S0, Slot),
  ( is_list(SlotMeta0),
    memberchk(subslot(Ss0), SlotMeta0) ->
      canon_slot(Ss0, SubSlot)
  ; query:search(subslot(Ss1), Repo://Entry) ->
      canon_slot(Ss1, SubSlot)
  ; SubSlot = none
  ),
  !.

candidate:selected_cn_slot_key_(SlotMeta0, Slot) :-
  canon_any_same_slot_meta(SlotMeta0, [slot(S0)]),
  canon_slot(S0, Slot),
  !.


% =============================================================================
%  Blocker matching
% =============================================================================

%! candidate:specs_violate_selected(+Specs, +Selected)
%
% True if any strong blocker spec in Specs matches an entry in Selected.
% Used to check whether a newly-selected candidate conflicts with
% existing blocker constraints.

candidate:specs_violate_selected(Specs, Selected) :-
  member(blocked(Strength, Phase, O, V, SlotReq), Specs),
  Strength == strong,
  member(selected(Repo, Entry, Act, SelVer, SelSlotMeta), Selected),
  action_phase(Act, Phase),
  blocker_spec_matches_selected(SelVer, SelSlotMeta, Repo, Entry, O, V, SlotReq),
  !.

%! candidate:action_phase(+Action, -Phase)
%
% Maps a build action to its blocker-relevant phase.

candidate:action_phase(run, run) :- !.
candidate:action_phase(install, install) :- !.
candidate:action_phase(reinstall, install) :- !.
candidate:action_phase(update, install) :- !.
candidate:action_phase(download, install) :- !.
candidate:action_phase(_Other, run).

%! candidate:blocker_spec_matches_selected(+SelVer, +SelSlotMeta, +Repo, +Entry, +O, +V, +SlotReq)
%
% True if a blocker spec (O, V, SlotReq) matches a selected candidate.

candidate:blocker_spec_matches_selected(SelVer, SelSlotMeta, Repo, Entry, O, V, SlotReq) :-
  blocker_version_matches(O, V, SelVer, Repo, Entry),
  blocker_slot_matches(SlotReq, SelSlotMeta, Repo, Entry).

candidate:blocker_version_matches(none, _Req, _SelVer, _Repo, _Entry) :- !.
candidate:blocker_version_matches(equal, Req, SelVer, _Repo, _Entry) :- !, SelVer == Req.
candidate:blocker_version_matches(notequal, Req, SelVer, _Repo, _Entry) :- !, SelVer \== Req.
candidate:blocker_version_matches(smaller, Req, SelVer, _Repo, _Entry) :- !, system:compare(<, SelVer, Req).
candidate:blocker_version_matches(greater, Req, SelVer, _Repo, _Entry) :- !, system:compare(>, SelVer, Req).
candidate:blocker_version_matches(smallerequal, Req, SelVer, _Repo, _Entry) :- !,
  ( system:compare(<, SelVer, Req) ; system:compare(=, SelVer, Req) ).
candidate:blocker_version_matches(greaterequal, Req, SelVer, _Repo, _Entry) :- !,
  ( system:compare(>, SelVer, Req) ; system:compare(=, SelVer, Req) ).
candidate:blocker_version_matches(Op, Req, _SelVer, Repo, Entry) :-
  query:search(select(version,Op,Req), Repo://Entry).

candidate:blocker_slot_matches([], _SelSlotMeta, _Repo, _Entry) :- !.
candidate:blocker_slot_matches([slot(S)], SelSlotMeta, _Repo, _Entry) :- !,
  memberchk(slot(S), SelSlotMeta).
candidate:blocker_slot_matches([slot(S),subslot(Ss)], SelSlotMeta, _Repo, _Entry) :- !,
  memberchk(slot(S), SelSlotMeta),
  memberchk(subslot(Ss), SelSlotMeta).
candidate:blocker_slot_matches([slot(S),equal], SelSlotMeta, _Repo, _Entry) :- !,
  memberchk(slot(S), SelSlotMeta).
candidate:blocker_slot_matches([slot(S),subslot(Ss),equal], SelSlotMeta, _Repo, _Entry) :- !,
  memberchk(slot(S), SelSlotMeta),
  memberchk(subslot(Ss), SelSlotMeta).
candidate:blocker_slot_matches(SlotReq, _SelSlotMeta, Repo, Entry) :-
  query:search(select(slot,constraint(SlotReq), _), Repo://Entry).


% =============================================================================
%  Blocker helpers
% =============================================================================

%! candidate:is_unconditional_dep(+PackageDep) is semidet.
%
% True when a package_dependency has no USE condition (U == []).

candidate:is_unconditional_dep(package_dependency(_Phase, _Strength, _C, _N, _O, _V, _S, U)) :-
  U == [].


%! candidate:make_enforced_specs(+PackageDeps, -Specs)
%
% Extracts blocked(...) spec terms from package_dependency terms
% for use in the blocked_cn constraint store.

candidate:make_enforced_specs(PackageDeps, Specs) :-
  findall(blocked(Strength, Phase, O, V, SlotReq),
          member(package_dependency(Phase, Strength, _C, _N, O, V, SlotReq, _U), PackageDeps),
          Specs0),
  sort(Specs0, Specs).


%! candidate:make_blocker_assumption(+Context, +PackageDeps, +C, +N, -Assumptions)
%
% Builds a list of assumed(blocker(...)) terms from package_dependency
% terms, annotated with a minimal assumption context preserving the
% self/1 reference from the original context if present.

candidate:make_blocker_assumption(Ctx0, PackageDeps, C, N, Assumptions) :-
  ( is_list(Ctx0),
    memberchk(self(Repo://Entry), Ctx0) ->
      AssCtx = [suggestion(loosen_blocker), assumption_reason(blocker_conflict), self(Repo://Entry)]
  ; AssCtx = [suggestion(loosen_blocker), assumption_reason(blocker_conflict)]
  ),
  findall(assumed(blocker(Strength, Phase, C, N, O, V, SlotReq)?{AssCtx}),
          member(package_dependency(Phase, Strength, C, N, O, V, SlotReq, _U), PackageDeps),
          Assumptions).


%! candidate:make_blocker_constraint(+C, +N, +PackageDeps, +Context, -Constraints)
%
% Generates `blocked_cn_source` constraints that record which parent
% entry introduced the blocker. Used for reprove source tracking.

candidate:make_blocker_constraint(_C, _N, PackageDeps, _Context, []) :-
  PackageDeps == [],
  !.
candidate:make_blocker_constraint(C, N, PackageDeps, Context, [constraint(blocked_cn_source(C,N):{ordset(Sources)})]) :-
  is_list(Context),
  memberchk(self(SelfRepo://SelfEntry), Context),
  findall(source(SelfRepo,SelfEntry,Phase,O,V,SlotReq),
          member(package_dependency(Phase, _Strength, _C, _N, O, V, SlotReq, _U), PackageDeps),
          Sources0),
  sort(Sources0, Sources),
  Sources \== [],
  !.
candidate:make_blocker_constraint(_C, _N, _PackageDeps, _Context, []) :-
  !.


% =============================================================================
%  Dependency ordering heuristic
% =============================================================================

%! candidate:order_deps_for_proof(+Action, +Deps, -Ordered)
%
% Sorts dependency groups for deterministic proof search. Tighter
% constraints (fewer candidates, installed packages, blockers) are
% proved first, reducing the backtracking search space. Uses a
% numeric priority key computed by dep_priority/2.

candidate:order_deps_for_proof(_Action, Deps, Ordered) :-
  maplist(dep_priority_kv, Deps, KVs),
  keysort(KVs, Sorted),
  pairs_values(Sorted, Ordered),
  !.

candidate:dep_priority_kv(Dep, K-Dep) :-
  dep_priority(Dep, K),
  !.

%! candidate:dep_priority(+DepLiteral, -Key)
%
% Computes a priority key for a dependency literal. Lower keys are
% proved first. Key is `key(BaseK, TightUpper, C, N)` where BaseK
% accounts for upper-bound tightness, wildcard constraints, and slot
% specificity.

candidate:dep_priority(grouped_package_dependency(_T,C,N,PackageDeps):Action?{_Context}, K) :-
  !,
  ( merge_slot_restriction(Action, C, N, PackageDeps, SlotReq) ->
      ( dep_tightest_upper_bound(C, N, PackageDeps, TightUpper) ->
          UpperK0 = 1
      ; dep_has_equal_wildcard_constraint(C, N, PackageDeps) ->
          UpperK0 = 8,
          TightUpper = none
      ; UpperK0 = 999,
        TightUpper = none
      ),
      slotreq_priority(SlotReq, SlotK0),
      BaseK is min(UpperK0, SlotK0),
      K = key(BaseK, TightUpper, C, N)
  ; K = key(50, none, C, N)
  ).
candidate:dep_priority(_Other, key(90, none, zz, zz)) :- !.

candidate:slotreq_priority([slot(_),subslot(_)|_], 0) :- !.
candidate:slotreq_priority([slot(_)|_],             5) :- !.
candidate:slotreq_priority([any_same_slot],        10) :- !.
candidate:slotreq_priority([any_different_slot],   15) :- !.
candidate:slotreq_priority([],                     20) :- !.
candidate:slotreq_priority(_Other,                 30) :- !.

candidate:dep_tightest_upper_bound(C, N, PackageDeps, Tightest) :-
  member(package_dependency(_, no, C, N, Op0, _, _, _), PackageDeps),
  ( Op0 == smaller ; Op0 == smallerorequal ),
  !,
  findall(V,
          ( member(package_dependency(_Phase, no, C, N, Op, V, _S, _U), PackageDeps),
            ( Op == smaller ; Op == smallerorequal )
          ),
          [First|Rest]),
  foldl(min_version_bound_, Rest, First, Tightest).

candidate:min_version_bound_(V, Best0, Best) :-
  ( eapi:version_compare(<, V, Best0) ->
      Best = V
  ; Best = Best0
  ),
  !.


% =============================================================================
%  Dep constraint helpers
% =============================================================================

%! candidate:cn_domain_constraints(+Action, +C, +N, +PackageDeps, +Context, -DomainCons, -DomainReasonTags)
%
% Builds CN-domain constraints and reason tags from a grouped dependency's
% package_dependency terms. The domain is computed by version_domain and
% then turned into `constraint(cn_domain(...))` terms for the prover's
% constraint store.

candidate:cn_domain_constraints(Action, C, N, PackageDeps, Context, DomainCons, DomainReasonTags) :-
  version_domain:domain_from_packagedeps(Action, C, N, PackageDeps, Domain),
  version_domain:domain_reason_terms(Action, C, N, PackageDeps, Context, DomainReasonTags),
  ( DomainReasonTags == [] ->
      ReasonCons = []
  ; ReasonCons = [constraint(cn_domain_reason(C,N):{ordset(DomainReasonTags)})]
  ),
  ( Domain == none ->
      DomainCons = ReasonCons
  ; DomainCons = [constraint(cn_domain(C,N):{Domain})|ReasonCons]
  ),
  !.

%! candidate:domain_constraints_for_any_different_slot(+SlotReq, +DomainCons0, -DomainCons)
%
% Suppresses domain constraints for any_different_slot deps since they
% deliberately seek a different slot from the existing selection.

candidate:domain_constraints_for_any_different_slot([any_different_slot], _DomainCons0, []) :-
  !.
candidate:domain_constraints_for_any_different_slot(_SlotReq, DomainCons, DomainCons) :-
  !.

%! candidate:add_domain_reason_context(+C, +N, +ReasonTags, +Ctx0, -Ctx)
%
% Merges domain reason tags into the proof context via feature unification.

candidate:add_domain_reason_context(_C, _N, [], Ctx, Ctx) :-
  !.
candidate:add_domain_reason_context(C, N, ReasonTags, Ctx0, Ctx) :-
  feature_unification:unify([domain_reason(cn_domain(C,N,ReasonTags))], Ctx0, Ctx),
  !.

%! candidate:dep_has_upper_version_bound(+C, +N, +PackageDeps)
%
% True if PackageDeps contains a `smaller` or `smallerorequal` constraint on (C,N).

candidate:dep_has_upper_version_bound(C, N, PackageDeps) :-
  member(package_dependency(_Phase, no, C, N, Op, _V, _S, _U), PackageDeps),
  ( Op == smaller
  ; Op == smallerorequal
  ),
  !.

%! candidate:dep_has_version_constraint(+C, +N, +PackageDeps)
%
% True if any dep on (C,N) carries a non-trivial version operator.

candidate:dep_has_version_constraint(C, N, PackageDeps) :-
  member(package_dependency(_Phase, no, C, N, Op, _V, _S, _U), PackageDeps),
  nonvar(Op),
  Op \== none,
  !.

%! candidate:dep_has_explicit_slot_constraint(+C, +N, +PackageDeps)
%
% True if any dep on (C,N) carries an explicit slot requirement.

candidate:dep_has_explicit_slot_constraint(C, N, PackageDeps) :-
  member(package_dependency(_Phase, no, C, N, _Op, _V, SlotReq, _U), PackageDeps),
  slot_req_explicit_slot_key(SlotReq, _S),
  !.

candidate:dep_has_equal_wildcard_constraint(C, N, PackageDeps) :-
  member(package_dependency(_Phase, no, C, N, equal, V0, _S, _U), PackageDeps),
  version_term_has_wildcard_(V0),
  !.

candidate:version_term_has_wildcard_(V0) :-
  ( atom(V0) ->
      A = V0
  ; V0 = [_Nums,_Letter,_Rev,A],
    atom(A)
  ),
  sub_atom(A, _Start, _Len, _After, '*'),
  !.


% =============================================================================
%  Dependency ranking / prioritization
% =============================================================================

%! candidate:prioritize_deps(+Deps, -SortedDeps)
%
% Sorts dependency groups by priority class and sub-ranking (slot
% specificity, blocker status). Used at the rule level to present
% candidates in deterministic order.

candidate:prioritize_deps(Deps, SortedDeps) :-
  prioritize_deps(Deps, [], SortedDeps).

%! candidate:prioritize_deps(+Deps, +Context, -SortedDeps)
%
% Sorts dependency groups by rank using Context for installed/use checks.

candidate:prioritize_deps(Deps, Context, SortedDeps) :-
  predsort(candidate:compare_dep_rank(Context), Deps, SortedDeps).

%! candidate:prioritize_deps_keep_all(+Deps, +Context, -SortedDeps)
%
% Like prioritize_deps/3 but uses a multi-key ranking (license-ok,
% intrinsic rank, overlap count, snapshot status) to break ties.

candidate:prioritize_deps_keep_all(Deps, Context, SortedDeps) :-
  findall(NegLicOk-NegRank-NegOverlap-NegSnap-I-Dep,
          ( nth1(I, Deps, Dep),
            dep_rank(Context, Dep, Rank),
            dep_overlap_group_count(Context, Dep, OvRaw),
            ( OvRaw > 1 -> Overlap = OvRaw ; Overlap = 0 ),
            ( dep_snapshot_selected(Dep) -> Snap = 1 ; Snap = 0 ),
            ( dep_license_ok(Dep) -> LicOk = 1 ; LicOk = 0 ),
            NegLicOk is -LicOk,
            NegRank is -Rank,
            NegOverlap is -Overlap,
            NegSnap is -Snap
          ),
          Ranked),
  keysort(Ranked, RankedSorted),
  findall(Dep, member(_-_-_-_-_-Dep, RankedSorted), SortedDeps0),
  candidate:boost_variant_preferred(SortedDeps0, SortedDeps),
  !.


%! candidate:boost_variant_preferred(+Deps, -Reordered) is det.
%
% When a thread-local variant:branch_prefer/1 override is active,
% moves matching deps to the front so the any_of_group cut selects them.

candidate:boost_variant_preferred(Deps, Reordered) :-
  ( variant:branch_prefer(Pref),
    partition(candidate:dep_matches_prefer(Pref), Deps, Front, Rest),
    Front \== []
  -> append(Front, Rest, Reordered)
  ;  Reordered = Deps
  ).


%! candidate:dep_matches_prefer(+Preferred, +Dep) is semidet.

candidate:dep_matches_prefer(Pref, Dep) :-
  Pref = package_dependency(_, _, PC, PN, _, _, _, _),
  Dep  = package_dependency(_, _, PC, PN, _, _, _, _).

candidate:dep_snapshot_selected(package_dependency(_Phase,_Strength,C,N,_O,_V,_S,_U)) :-
  snapshot_selected_cn_candidates(C, N, _),
  !.
candidate:dep_snapshot_selected(_) :- fail.

candidate:dep_overlap_group_count(Context, package_dependency(_,_,C,N,_,_,_,_), Count) :-
  memberchk(self(Repo://Ebuild), Context),
  !,
  aggregate_all(count, (
    member(DepKey, [rdepend, depend, bdepend, pdepend, cdepend, idepend]),
    cache:entry_metadata(Repo, Ebuild, DepKey, DepEntry),
    dep_entry_active_any_of_with_cn(DepEntry, Repo://Ebuild, C, N)
  ), Count).
candidate:dep_overlap_group_count(_, _, 0).

candidate:dep_entry_active_any_of_with_cn(any_of_group(Deps), _, C, N) :-
  member(package_dependency(_, _, C, N, _, _, _, _), Deps), !.
candidate:dep_entry_active_any_of_with_cn(use_conditional_group(Pol, Use, RepoEntry, Deps), _, C, N) :-
  rdepend_self_use_conditional_active(Pol, Use, RepoEntry),
  member(D, Deps),
  dep_entry_active_any_of_with_cn(D, RepoEntry, C, N), !.
candidate:dep_entry_active_any_of_with_cn(all_of_group(Deps), RepoEntry, C, N) :-
  member(D, Deps),
  dep_entry_active_any_of_with_cn(D, RepoEntry, C, N), !.

candidate:compare_dep_rank(Context, Delta, A, B) :-
  dep_rank(Context, A, Ra),
  dep_rank(Context, B, Rb),
  compare(C, Rb, Ra),
  ( C == (<) -> Delta = (<)
  ; C == (>) -> Delta = (>)
  ; Delta = (=)
  ).

%! candidate:dep_rank(+Context, +Dep, -Rank)
%
% Computes a numeric rank for a dependency term. Higher rank = preferred.

candidate:dep_rank(Context, Dep, Rank) :-
  Dep \= package_dependency(_,_,_,_,_,_,_,_),
  ( is_preferred_dep(Context, Dep) -> Pref = 1 ; Pref = 0 ),
  dep_intrinsic_rank(Dep, Base),
  Rank is Pref*1000000000 + Base,
  !.

candidate:dep_rank(Context, package_dependency(Phase,Strength,C,N,O,V,S,U), Rank) :-
  ( self_cn(Context, C, N) -> Base0 = -100000000 ; Base0 = 0 ),
  installed_version_mismatch_penalty(package_dependency(Phase,Strength,C,N,O,V,S,U), BaseInst),
  ( is_preferred_dep(Context, package_dependency(Phase,Strength,C,N,O,V,S,U)) -> Pref = 1 ; Pref = 0 ),
  dep_intrinsic_rank(package_dependency(Phase,Strength,C,N,O,V,S,U), Base1),
  dep_favour_avoid_bonus(C, N, FavAvoid),
  Rank is Pref*1000000000 + Base0 + BaseInst + Base1 + FavAvoid,
  !.

candidate:self_cn(Context, C, N) :-
  memberchk(self(Repo://Id), Context),
  query:search([category(C),name(N)], Repo://Id),
  !.

candidate:dep_intrinsic_rank(required(Use), Rank) :-
  use_rank(Use, Rank),
  !.
candidate:dep_intrinsic_rank(required(minus(Use)), Rank) :-
  use_rank(Use, Rank),
  !.
candidate:dep_intrinsic_rank(package_dependency(_Phase,_Strength,_C,N,_O,_V,_S,_U), Rank) :-
  ( atom_concat(_, '-bootstrap', N) -> Rank = 50000
  ; Rank = 0
  ),
  !.
candidate:dep_intrinsic_rank(_, 0).


%! candidate:dep_favour_avoid_bonus(+Category, +Name, -Bonus) is det.
%
% Returns a large positive bonus for --favour'd packages and a large
% negative penalty for --avoid'd packages in || dep resolution.

candidate:dep_favour_avoid_bonus(C, N, Bonus) :-
  atomic_list_concat([C, '/', N], CN),
  ( config:dep_favour(CN) -> FavBonus = 500000000
  ; config:dep_favour(N)  -> FavBonus = 500000000
  ; FavBonus = 0
  ),
  ( config:dep_avoid(CN) -> AvoidPen = -500000000
  ; config:dep_avoid(N)  -> AvoidPen = -500000000
  ; AvoidPen = 0
  ),
  Bonus is FavBonus + AvoidPen.

candidate:use_rank(Use, Rank) :-
  atom(Use),
  ( llvm_slot_rank(Use, Rank)
  ; lua_single_target_rank(Use, Rank)
  ),
  !.
candidate:use_rank(_, 0).

candidate:llvm_slot_rank(Use, Rank) :-
  atom_concat('llvm_slot_', Suffix, Use),
  catch(atom_number(Suffix, N), _, fail),
  Rank is 100000 + N.

candidate:lua_single_target_rank(Use, Rank) :-
  atom_concat('lua_single_target_lua5-', Suffix, Use),
  catch(atom_number(Suffix, N), _, fail),
  Rank is 90000 + N.

%! candidate:is_preferred_dep(+Context, +Dep)
%
% True if a dependency is "preferred" based on USE flags, installed
% status, or all_of_group member satisfaction.

candidate:is_preferred_dep(_Context, use_conditional_group(positive, Use, RepoEntry, _Deps)) :-
  \+ Use =.. [minus,_],
  RepoEntry = _Repo://_Id,
  use:effective_use_for_entry(RepoEntry, Use, positive),
  !.
candidate:is_preferred_dep(_Context, use_conditional_group(negative, Use, RepoEntry, _Deps)) :-
  \+ Use =.. [minus,_],
  RepoEntry = _Repo://_Id,
  use:effective_use_for_entry(RepoEntry, Use, negative),
  !.

candidate:is_preferred_dep(Context, required(Use)) :-
  Use \= minus(_),
  ( preference:global_use(Use)
  ; use:effective_use_in_context(Context, Use, positive)
  ),
  !.
candidate:is_preferred_dep(Context, required(minus(Use))) :-
  ( preference:global_use(minus(Use))
  ; use:effective_use_in_context(Context, Use, negative)
  ),
  !.

candidate:is_preferred_dep(Context, all_of_group(Deps)) :-
  Deps \= [],
  forall(member(D, Deps), group_member_preferred(Context, D)),
  !.

candidate:is_preferred_dep(_Context, package_dependency(_Phase,_Strength,C,N,O,V,_S,_U)) :-
  query:search([name(N),category(C),installed(true)], pkg://Installed),
  ( O == none ; query:search(select(version, O, V), pkg://Installed) ),
  !.


% =============================================================================
%  any_of_group preference helpers (installed satisfaction)
% =============================================================================

%! candidate:group_member_preferred(+Context, +PackageDep)
%
% True if a package_dependency member is "preferred" -- i.e. already
% installed or previously selected in the proof. Used by any_of_group
% rules to try installed alternatives first.

candidate:group_member_preferred(Context, package_dependency(Phase,Strength,C,N,O,V,S,U)) :-
  installed_pkg_satisfies_dep(Context, package_dependency(Phase,Strength,C,N,O,V,S,U)),
  !.
candidate:group_member_preferred(Context, use_conditional_group(positive, Use, RepoEntry, Deps)) :-
  is_preferred_dep(Context, use_conditional_group(positive, Use, RepoEntry, Deps)),
  !.
candidate:group_member_preferred(Context, use_conditional_group(negative, Use, RepoEntry, Deps)) :-
  is_preferred_dep(Context, use_conditional_group(negative, Use, RepoEntry, Deps)),
  !.
candidate:group_member_preferred(Context, all_of_group(Deps)) :-
  Deps \= [],
  forall(member(D, Deps), group_member_preferred(Context, D)),
  !.
candidate:group_member_preferred(_Context, _Other) :-
  fail.

%! candidate:installed_pkg_satisfies_dep(+ParentContext, +PackageDep)
%
% True if an installed package satisfies the version and USE requirements
% of the given package_dependency term. ParentContext is the ?{Context}
% list of the parent literal.

candidate:installed_pkg_satisfies_dep(ParentContext,
                             package_dependency(_Phase,_Strength,C,N,O,V,_S,UseReqs)) :-
  query:search([name(N),category(C),installed(true)], pkg://InstalledId),
  ( O == none
  ; query:search(select(version, O, V), pkg://InstalledId)
  ),
  use:installed_pkg_satisfies_use_reqs(ParentContext, pkg://InstalledId, UseReqs),
  !.

%! candidate:installed_version_mismatch_penalty(+PackageDep, -Penalty)
%
% Returns a large negative penalty if a package is installed but the
% installed version does not match the constraint, indicating a forced upgrade.

candidate:installed_version_mismatch_penalty(package_dependency(_Phase,_Strength,C,N,O,V,_S,_U), Penalty) :-
  O \== none,
  query:search([name(N),category(C),installed(true)], pkg://_),
  \+ ( query:search([name(N),category(C),installed(true)], pkg://InstalledId),
       query:search(select(version, O, V), pkg://InstalledId)
     ),
  Penalty is -50000000,
  !.
candidate:installed_version_mismatch_penalty(_Dep, 0).


% =============================================================================
%  Reverse-dep candidate pre-filter (RDEPEND only)
% =============================================================================

%! candidate:candidate_reverse_deps_compatible_with_parent(+Context, +RepoEntry)
%
% Verifies that the candidate's RDEPEND does not conflict with the parent
% entry in the proof context. If the candidate's RDEPEND contains a
% version constraint on the parent (C,N) that is incompatible with the
% parent's version, the candidate is filtered out early. Only applied
% when a `self/1` term is present in the context (i.e. when the parent's
% identity is known).

candidate:candidate_reverse_deps_compatible_with_parent(Context, FoundRepo://Candidate) :-
  ( memberchk(self(SelfRepo://SelfEntry), Context),
    cache:ordered_entry(SelfRepo, SelfEntry, ParC, ParN, _)
  ->
    \+ candidate_has_incompatible_reverse_dep(FoundRepo, Candidate, ParC, ParN, SelfRepo://SelfEntry)
  ; true
  ).

candidate:candidate_has_incompatible_reverse_dep(FoundRepo, Candidate, ParC, ParN, SelfRepo://SelfEntry) :-
  cache:entry_metadata(FoundRepo, Candidate, rdepend, Dep),
  dep_contains_pkg_dep_on(Dep, ParC, ParN, Op, V, SlotReq),
  Op \== none,
  reverse_dep_slot_matches_parent(SlotReq, SelfRepo://SelfEntry),
  \+ query:search(select(version, Op, V), SelfRepo://SelfEntry).

candidate:reverse_dep_slot_matches_parent([], _) :- !.
candidate:reverse_dep_slot_matches_parent([slot(DepSlot)|_], SelfRepo://SelfEntry) :-
  !,
  query:search(slot(ParSlot), SelfRepo://SelfEntry),
  canon_slot(ParSlot, ParSlotC),
  canon_slot(DepSlot, DepSlotC),
  ParSlotC == DepSlotC.
candidate:reverse_dep_slot_matches_parent([any_same_slot|_], _) :- !.
candidate:reverse_dep_slot_matches_parent([any_different_slot|_], _) :- !, fail.
candidate:reverse_dep_slot_matches_parent(_, _).

candidate:dep_contains_pkg_dep_on(package_dependency(_, no, C, N, Op, V, SlotReq, _), C, N, Op, V, SlotReq).
candidate:dep_contains_pkg_dep_on(use_conditional_group(_, _, _, SubDeps), C, N, Op, V, SlotReq) :-
  member(D, SubDeps),
  dep_contains_pkg_dep_on(D, C, N, Op, V, SlotReq).
candidate:dep_contains_pkg_dep_on(all_of_group(SubDeps), C, N, Op, V, SlotReq) :-
  member(D, SubDeps),
  dep_contains_pkg_dep_on(D, C, N, Op, V, SlotReq).


% =============================================================================
%  Grouped dep slot helpers
% =============================================================================

%! candidate:all_deps_have_explicit_slot(+PackageDeps)
%
% True if every dep in PackageDeps carries a non-empty slot requirement.
% Used to decide whether the grouped dep can be resolved slot-by-slot.

candidate:all_deps_have_explicit_slot([]) :- !, fail.
candidate:all_deps_have_explicit_slot(Deps) :-
  forall(member(package_dependency(_P,_Strength,_C,_N,_O,_V,SlotReq,_U), Deps),
         slot_req_explicit_slot_key(SlotReq, _S)),
  !.

%! candidate:multiple_distinct_slots(+Deps)
%
% True if Deps contains package_dependency terms targeting more than one
% distinct slot.

candidate:multiple_distinct_slots(Deps) :-
  member(package_dependency(_,_,_,_,_,_,SR1,_), Deps),
  slot_req_explicit_slot_key(SR1, S1), !,
  member(package_dependency(_,_,_,_,_,_,SR2,_), Deps),
  slot_req_explicit_slot_key(SR2, S2),
  S2 \== S1, !.

%! candidate:slot_req_explicit_slot_key(+SlotReq, -Slot)
%
% Extracts and canonicalises the explicit slot from a slot requirement list.

candidate:slot_req_explicit_slot_key([slot(S0)], S) :-
  canon_slot(S0, S),
  !.
candidate:slot_req_explicit_slot_key([slot(S0),equal], S) :-
  canon_slot(S0, S),
  !.
candidate:slot_req_explicit_slot_key([slot(S0),subslot(_Ss)], S) :-
  canon_slot(S0, S),
  !.
candidate:slot_req_explicit_slot_key([slot(S0),subslot(_Ss),equal], S) :-
  canon_slot(S0, S),
  !.

%! candidate:all_deps_exactish_versioned(+Deps)
%
% True if every dep uses `tilde` or `equal` with a bound version and no slot.

candidate:all_deps_exactish_versioned([]) :- !, fail.
candidate:all_deps_exactish_versioned(Deps) :-
  forall(member(package_dependency(_P,_Strength,_C,_N,Op,Ver,SlotReq,_U), Deps),
         ( SlotReq == [],
           ( Op == tilde ; Op == equal ),
           nonvar(Ver)
         )),
  !.

candidate:multiple_distinct_exactish_versions(Deps) :-
  findall(Full,
          ( member(package_dependency(_P,_Strength,_C,_N,_Op,Ver,_SlotReq,_U), Deps),
            ( Ver = version(_,_,_,_,_,_,Full) -> true ; Full = Ver )
          ),
          Vs0),
  sort(Vs0, Vs),
  Vs = [_|Rest],
  Rest \== [],
  !.

%! candidate:should_split_grouped_dep(+PackageDeps)
%
% True if the grouped dependency should be split into per-slot or
% per-version sub-groups for independent resolution.

candidate:should_split_grouped_dep(PackageDeps) :-
  ( all_deps_have_explicit_slot(PackageDeps),
    multiple_distinct_slots(PackageDeps)
  ; all_deps_exactish_versioned(PackageDeps),
    multiple_distinct_exactish_versions(PackageDeps)
  ),
  !.


% =============================================================================
%  Self-RDEPEND version-bound propagation (timeout-safe)
% =============================================================================

%! candidate:augment_package_deps_with_self_rdepend(+Action, +C, +N, +Context, +Deps0, -Deps)
%
% When the parent ebuild has an RDEPEND on (C,N) with a version constraint,
% propagates that version bound into the child dependency's package_dependency
% list. This tightens candidate selection and avoids picking a version that
% would later conflict with the parent's RDEPEND. Only applies to `:install`
% actions, and only when the parent is known (via `self/1` in Context). The
% RDEPEND lookup result is memoized in `memo:rdepend_vbounds_cache_/5`.

candidate:augment_package_deps_with_self_rdepend(install, C, N, Context, PackageDeps0, PackageDeps) :-
  ( memberchk(self(RepoEntry0), Context) ->
      RepoEntry0 = Repo://SelfId
  ; fail
  ),
  ( dep_has_version_constraints(C, N, PackageDeps0) ->
      PackageDeps = PackageDeps0
  ; self_rdepend_vbounds_for_cn(Repo, SelfId, C, N, Extra0),
    ( merge_slot_restriction(install, C, N, PackageDeps0, BaseSlotReq) ->
        true
    ; BaseSlotReq = []
    ),
    findall(ExtraDep,
            ( member(ExtraDep, Extra0),
              self_rdepend_extra_slot_compatible(BaseSlotReq, ExtraDep)
            ),
            Extra),
    ( Extra == [] ->
        PackageDeps = PackageDeps0
    ; append(PackageDeps0, Extra, PackageDeps)
    )
  ),
  !.
candidate:augment_package_deps_with_self_rdepend(_OtherAction, _C, _N, _Context, PackageDeps, PackageDeps) :-
  !.

%! candidate:dep_has_version_constraints(+C, +N, +PackageDeps)
%
% True if PackageDeps already contains a non-trivial version operator
% for (C,N). Used to skip RDEPEND augmentation when bounds already exist.

candidate:dep_has_version_constraints(C, N, PackageDeps) :-
  member(package_dependency(_Phase, no, C, N, Op, _V, _S, _U), PackageDeps),
  Op \== none,
  !.

candidate:self_rdepend_extra_slot_compatible([], _ExtraDep) :-
  !.
candidate:self_rdepend_extra_slot_compatible([slot(S0)|_],
                                   package_dependency(_P,_Strength,_C,_N,_Op,_V,SlotReq,_U)) :-
  !,
  canon_slot(S0, S),
  ( SlotReq == []
  ; SlotReq = [slot(S1)|_],
    canon_slot(S1, S)
  ).
candidate:self_rdepend_extra_slot_compatible(_BaseSlotReq, _ExtraDep) :-
  !.

%! candidate:self_rdepend_vbounds_for_cn(+Repo, +SelfId, +C, +N, -Extra)
%
% Returns version-bound deps from the parent's RDEPEND on (C,N), with
% memoization via memo:rdepend_vbounds_cache_/5.

candidate:self_rdepend_vbounds_for_cn(Repo, SelfId, C, N, Extra) :-
  ( memo:rdepend_vbounds_cache_(Repo, SelfId, C, N, Extra0) ->
    Extra = Extra0
  ;
    build_self_rdepend_vbounds_for_cn(Repo, SelfId, C, N, Extra1),
    assertz(memo:rdepend_vbounds_cache_(Repo, SelfId, C, N, Extra1)),
    Extra = Extra1
  ),
  !.

candidate:build_self_rdepend_vbounds_for_cn(Repo, SelfId, C, N, Extra) :-
  SelfRepoEntry = Repo://SelfId,
  findall(Term, cache:entry_metadata(Repo, SelfId, rdepend, Term), Terms),
  findall(Dep,
          ( member(Term, Terms),
            rdepend_collect_vbounds_for_cn(Term, C, N, SelfRepoEntry, Deps0),
            member(Dep, Deps0)
          ),
          Extra0),
  sort(Extra0, Extra),
  !.

candidate:rdepend_collect_vbounds_for_cn(package_dependency(_P, no, C, N, Op, V, SlotReq, _UseDeps),
                                C, N, _SelfRepoEntry,
                                [package_dependency(run, no, C, N, Op, V, SlotReq, [])]) :-
  Op \== none,
  !.
candidate:rdepend_collect_vbounds_for_cn(package_dependency(_P, _Strength, _C, _N, _Op, _V, _SlotReq, _UseDeps),
                                _C0, _N0, _SelfRepoEntry, []) :-
  !.
candidate:rdepend_collect_vbounds_for_cn(use_conditional_group(Pol, Use, _Self, Deps0), C, N, SelfRepoEntry, Deps) :-
  !,
  ( rdepend_self_use_conditional_active(Pol, Use, SelfRepoEntry) ->
      rdepend_collect_vbounds_for_cn_list(Deps0, C, N, SelfRepoEntry, Deps)
  ; Deps = []
  ).
candidate:rdepend_collect_vbounds_for_cn(any_of_group(Deps0), C, N, SelfRepoEntry, Deps) :-
  !,
  rdepend_collect_vbounds_for_cn_choice_intersection(Deps0, C, N, SelfRepoEntry, Deps).
candidate:rdepend_collect_vbounds_for_cn(all_of_group(Deps0), C, N, SelfRepoEntry, Deps) :-
  !,
  rdepend_collect_vbounds_for_cn_list(Deps0, C, N, SelfRepoEntry, Deps).
candidate:rdepend_collect_vbounds_for_cn(exactly_one_of_group(Deps0), C, N, SelfRepoEntry, Deps) :-
  !,
  rdepend_collect_vbounds_for_cn_choice_intersection(Deps0, C, N, SelfRepoEntry, Deps).
candidate:rdepend_collect_vbounds_for_cn(at_most_one_of_group(Deps0), C, N, SelfRepoEntry, Deps) :-
  !,
  rdepend_collect_vbounds_for_cn_choice_intersection(Deps0, C, N, SelfRepoEntry, Deps).
candidate:rdepend_collect_vbounds_for_cn(_Other, _C, _N, _SelfRepoEntry, []) :-
  !.

candidate:rdepend_collect_vbounds_for_cn_list([], _C, _N, _SelfRepoEntry, []) :- !.
candidate:rdepend_collect_vbounds_for_cn_list([T|Ts], C, N, SelfRepoEntry, Deps) :-
  rdepend_collect_vbounds_for_cn(T, C, N, SelfRepoEntry, D0),
  rdepend_collect_vbounds_for_cn_list(Ts, C, N, SelfRepoEntry, D1),
  append(D0, D1, Deps),
  !.

%! candidate:rdepend_self_use_conditional_active(+Polarity, +Use, +SelfRepoEntry)
%
% True if a USE-conditional guard in the parent's RDEPEND is active
% based on the parent's effective USE flags.

candidate:rdepend_self_use_conditional_active(positive, Use, SelfRepoEntry) :-
  ( use:effective_use_for_entry(SelfRepoEntry, Use, positive) ->
      true
  ; \+ rdepend_self_entry_has_iuse_flag(SelfRepoEntry, Use),
    preference:global_use(Use)
  ),
  !.
candidate:rdepend_self_use_conditional_active(negative, Use, SelfRepoEntry) :-
  ( use:effective_use_for_entry(SelfRepoEntry, Use, negative) ->
      true
  ; \+ rdepend_self_entry_has_iuse_flag(SelfRepoEntry, Use),
    preference:global_use(minus(Use))
  ; \+ rdepend_self_entry_has_iuse_flag(SelfRepoEntry, Use),
    \+ preference:global_use(Use),
    \+ preference:global_use(minus(Use))
  ),
  !.
candidate:rdepend_self_use_conditional_active(_Pol, _Use, _SelfRepoEntry) :-
  fail.

candidate:rdepend_self_entry_has_iuse_flag(Repo://Entry, Use) :-
  use:entry_iuse_info(Repo://Entry, iuse_info(IuseSet, _PlusSet)),
  memberchk(Use, IuseSet),
  !.
candidate:rdepend_self_entry_has_iuse_flag(_RepoEntry, _Use) :-
  fail.

candidate:rdepend_collect_vbounds_for_cn_choice_intersection([], _C, _N, _SelfRepoEntry, []) :-
  !.
candidate:rdepend_collect_vbounds_for_cn_choice_intersection([Dep|Deps], C, N, SelfRepoEntry, Common) :-
  rdepend_collect_vbounds_for_cn(Dep, C, N, SelfRepoEntry, First0),
  sort(First0, First),
  rdepend_collect_vbounds_for_cn_choice_intersection_(Deps, C, N, SelfRepoEntry, First, Common),
  !.

candidate:rdepend_collect_vbounds_for_cn_choice_intersection_([], _C, _N, _SelfRepoEntry, Acc, Acc) :-
  !.
candidate:rdepend_collect_vbounds_for_cn_choice_intersection_([Dep|Deps], C, N, SelfRepoEntry, Acc0, Common) :-
  rdepend_collect_vbounds_for_cn(Dep, C, N, SelfRepoEntry, Next0),
  sort(Next0, Next),
  ord_intersection(Acc0, Next, Acc1),
  rdepend_collect_vbounds_for_cn_choice_intersection_(Deps, C, N, SelfRepoEntry, Acc1, Common),
  !.


% =============================================================================
%  License masking (ACCEPT_LICENSE)
% =============================================================================

%! candidate:license_masked(+RepoEntry)
%
% True if RepoEntry is masked due to an unaccepted license. Checks
% whether any license string from the entry's LICENSE metadata is
% rejected by `preference:accept_license/2`.

candidate:license_masked(Repo://Entry) :-
  effective_license(Repo://Entry, Lic),
  \+ preference:license_accepted(Lic),
  \+ candidate:package_license_accepted(Repo://Entry, Lic),
  !.


%! candidate:package_license_accepted(+RepoEntry, +License) is semidet.
%
% True if License is accepted for RepoEntry via a per-package override
% in /etc/portage/package.license (loaded into userconfig:package_license_entry/2).

candidate:package_license_accepted(Repo://Entry, Lic) :-
  current_predicate(userconfig:package_license_entry/2),
  query:search([category(C), name(N)], Repo://Entry),
  atomic_list_concat([C, N], '/', CatPkg),
  userconfig:package_license_entry(CatPkg, Lic).

%! candidate:effective_license(+RepoEntry, -License)
%
% Enumerates the effective license atoms for an entry, resolving
% USE-conditional license groups against the entry's effective USE.

candidate:effective_license(Repo://Entry, License) :-
  cache:entry_metadata(Repo, Entry, license, LicTerm),
  effective_license_term_(LicTerm, Repo://Entry, License).

candidate:effective_license_term_(use_conditional_group(Pol, Use, _Self, Deps), RepoEntry, License) :-
  !,
  rdepend_self_use_conditional_active(Pol, Use, RepoEntry),
  member(D, Deps),
  effective_license_term_(D, RepoEntry, License).
candidate:effective_license_term_(License, _RepoEntry, License) :-
  atom(License).

%! candidate:dep_license_ok(+Dep)
%
% True if at least one visible, license-accepted candidate exists for
% the dependency's (C,N).

candidate:dep_license_ok(package_dependency(_, _, C, N, _, _, _, _)) :- !,
  cache:ordered_entry(Repo, Entry, C, N, _),
  \+ preference:masked(Repo://Entry),
  \+ license_masked(Repo://Entry).
candidate:dep_license_ok(grouped_package_dependency(_, C, N, _)) :- !,
  cache:ordered_entry(Repo, Entry, C, N, _),
  \+ preference:masked(Repo://Entry),
  \+ license_masked(Repo://Entry).
candidate:dep_license_ok(_).


% =============================================================================
%  Keyword-aware candidate enumeration (Portage-like)
% =============================================================================

%! candidate:accepted_keyword_candidate(+Action, +C, +N, +SlotReq, +SlotSet, +Context, -RepoEntry)
%
% Enumerates candidates for (C,N) respecting ACCEPT_KEYWORDS, slot locks,
% license masking, and the CN-domain reject map. Candidates are returned
% in keyword-priority order (stable first, then testing, then masked).
% Results are memoized per (Action, C, N, SlotReq, LockKey) in
% memo:keyword_cache_/6 to avoid repeated query/sort overhead.

candidate:accepted_keyword_candidate(Action, C, N, SlotReq0, Ss0, Context, FoundRepo://Candidate) :-
  accepted_keyword_slot_lock_arg(C, N, SlotReq0, Ss0, Context, SlotReq, Ss, LockKey),
  ( preference:keyword_selection_mode(keyword_order) ->
      ( preference:accept_keywords(K)
      ; candidate:package_keyword_entry(C, N, K)
      ),
      query_keyword_candidate(Action, C, N, K, Context, FoundRepo://Candidate),
      query_search_slot_constraint(SlotReq, FoundRepo://Candidate, Ss)
  ; ( Action \== run,
      memberchk(self(SelfRepo0://SelfEntry0), Context),
      query:search([category(C),name(N)], SelfRepo0://SelfEntry0)
    ->
      findall(FoundRepo0://Candidate0,
              ( ( preference:accept_keywords(K0)
                ; candidate:package_keyword_entry(C, N, K0)
                ),
                query_keyword_candidate(Action, C, N, K0, Context, FoundRepo0://Candidate0),
                query_search_slot_constraint(SlotReq, FoundRepo0://Candidate0, Ss)
              ),
              Candidates0),
      Candidates0 \== [],
      sort(Candidates0, Candidates1),
      predsort(candidate:compare_candidate_version_desc, Candidates1, CandidatesSorted),
      member(FoundRepo://Candidate, CandidatesSorted)
    ;
      accepted_keyword_candidates_cached(Action, C, N, SlotReq, LockKey, CandidatesSorted0),
      candidates_prefer_proven_providers(C, N, SlotReq, CandidatesSorted0, CandidatesSorted),
      member(FoundRepo://Candidate, CandidatesSorted),
      query_search_slot_constraint(SlotReq, FoundRepo://Candidate, Ss)
    )
  ).

% Fallback: when keyword_acceptance is active, accept candidates with any
% keyword that are not masked. This produces a full resolution (download +
% install + run) rather than a "verify" stub.
candidate:accepted_keyword_candidate(Action, C, N, SlotReq0, Ss0, Context, FoundRepo://Candidate) :-
  prover:assuming(keyword_acceptance),
  accepted_keyword_slot_lock_arg(C, N, SlotReq0, Ss0, Context, SlotReq, Ss, _LockKey),
  findall(FoundRepo0://Candidate0,
          ( query_keyword_candidate_any(Action, C, N, Context, FoundRepo0://Candidate0),
            query_search_slot_constraint(SlotReq, FoundRepo0://Candidate0, Ss)
          ),
          Candidates0),
  Candidates0 \== [],
  sort(Candidates0, Candidates1),
  predsort(candidate:compare_candidate_version_desc, Candidates1, CandidatesSorted),
  member(FoundRepo://Candidate, CandidatesSorted).

% Fallback: when unmask is active, accept masked candidates with accepted
% keywords. Produces a full resolution with an unmask suggestion.
candidate:accepted_keyword_candidate(Action, C, N, SlotReq0, Ss0, Context, FoundRepo://Candidate) :-
  prover:assuming(unmask),
  accepted_keyword_slot_lock_arg(C, N, SlotReq0, Ss0, Context, SlotReq, Ss, _LockKey),
  findall(FoundRepo0://Candidate0,
          ( query_keyword_candidate_masked(Action, C, N, Context, FoundRepo0://Candidate0),
            query_search_slot_constraint(SlotReq, FoundRepo0://Candidate0, Ss)
          ),
          Candidates0),
  Candidates0 \== [],
  sort(Candidates0, Candidates1),
  predsort(candidate:compare_candidate_version_desc, Candidates1, CandidatesSorted),
  member(FoundRepo://Candidate, CandidatesSorted).

%! candidate:query_keyword_candidate_any(+Action, +C, +N, +Context, -RepoEntry)
%
% Like query_keyword_candidate but accepts any candidate regardless of
% keywords. Used when keyword_acceptance fallback is active.

candidate:query_keyword_candidate_any(Action, C, N, Context, FoundRepo://Candidate) :-
  ( Action \== run,
    memberchk(self(SelfRepo0://SelfEntry0), Context),
    query:search([category(C),name(N)], SelfRepo0://SelfEntry0)
  ->
    query:search([name(N),category(C)], FoundRepo://Candidate),
    \+ preference:masked(FoundRepo://Candidate),
    ( FoundRepo == SelfRepo0,
      Candidate == SelfEntry0
    ->
      \+ preference:flag(emptytree),
      query:search(installed(true), FoundRepo://Candidate)
    ; true
    )
  ; query:search([name(N),category(C)], FoundRepo://Candidate),
    \+ preference:masked(FoundRepo://Candidate)
  ).

%! candidate:query_keyword_candidate_masked(+Action, +C, +N, +Context, -RepoEntry)
%
% Accepts masked candidates with any keyword. Used when the unmask
% fallback is active to let masked packages through for full resolution.

candidate:query_keyword_candidate_masked(Action, C, N, Context, FoundRepo://Candidate) :-
  ( Action \== run,
    memberchk(self(SelfRepo0://SelfEntry0), Context),
    query:search([category(C),name(N)], SelfRepo0://SelfEntry0)
  ->
    query:search([name(N),category(C),keyword(_)], FoundRepo://Candidate),
    ( FoundRepo == SelfRepo0,
      Candidate == SelfEntry0
    ->
      \+ preference:flag(emptytree),
      query:search(installed(true), FoundRepo://Candidate)
    ; true
    )
  ; query:search([name(N),category(C),keyword(_)], FoundRepo://Candidate)
  ).

%! candidate:accepted_keyword_slot_lock_arg(+C, +N, +SlotReq0, +Ss0, +Context, -SlotReq, -Ss, -LockKey)
%
% Resolves slot lock arguments for keyword-aware candidate enumeration,
% incorporating context-level slot constraints.

candidate:accepted_keyword_slot_lock_arg(C, N, SlotReq0, Ss0, Context, SlotReq, Ss, LockKey) :-
  ( memberchk(slot(C,N,SsCtx0):{_}, Context) ->
      canon_any_same_slot_meta(SsCtx0, SsCtx)
  ; SsCtx = _NoCtxLock
  ),
  ( SlotReq0 == [],
    nonvar(SsCtx)
  ->
    SlotReq1 = [any_same_slot]
  ; SlotReq1 = SlotReq0
  ),
  ( SlotReq1 == [any_same_slot] ->
      ( nonvar(Ss0) ->
          canon_any_same_slot_meta(Ss0, Ss1)
      ; nonvar(SsCtx) ->
          Ss1 = SsCtx
      ; Ss1 = _NoSlotLock
      ),
      SlotReq = [any_same_slot],
      Ss = Ss1
  ; SlotReq = SlotReq1,
    Ss = Ss0
  ),
  accepted_keyword_slot_lock_key(SlotReq, Ss, LockKey),
  !.

candidate:accepted_keyword_slot_lock_key([any_same_slot], Ss, slot(S)) :-
  nonvar(Ss),
  canon_any_same_slot_meta(Ss, [slot(S)|_]),
  !.
candidate:accepted_keyword_slot_lock_key(_SlotReq, _Ss, any) :-
  !.

candidate:accepted_keyword_slot_lock_filter([any_same_slot], slot(S), [slot(S)]) :-
  !.
candidate:accepted_keyword_slot_lock_filter(_SlotReq, _LockKey, _SsFilter) :-
  !.

%! candidate:accepted_keyword_candidates_cached(+Action, +C, +N, +SlotReq, +LockKey, -CandidatesSorted)
%
% Returns memoized keyword-accepted candidates sorted by version descending.
% Builds and caches the result on first call for each (Action, C, N, SlotReq, LockKey).

candidate:accepted_keyword_candidates_cached(Action, C, N, SlotReq, LockKey, CandidatesSorted) :-
  ( memo:keyword_cache_(Action, C, N, SlotReq, LockKey, CandidatesSorted) ->
    true
  ;
    accepted_keyword_slot_lock_filter(SlotReq, LockKey, SsFilter),
    findall(FoundRepo0://Candidate0,
            ( ( preference:accept_keywords(K0)
              ; candidate:package_keyword_entry(C, N, K0)
              ),
              query_keyword_candidate(Action, C, N, K0, [], FoundRepo0://Candidate0),
              query_search_slot_constraint(SlotReq, FoundRepo0://Candidate0, SsFilter)
            ),
            Candidates0),
    Candidates0 \== [],
    sort(Candidates0, Candidates1),
    predsort(candidate:compare_candidate_version_desc, Candidates1, CandidatesSorted),
    assertz(memo:keyword_cache_(Action, C, N, SlotReq, LockKey, CandidatesSorted))
  ).


%! candidate:package_keyword_entry(+C, +N, -K) is nondet.
%
% Enumerate keyword terms accepted for C/N via per-package
% /etc/portage/package.accept_keywords overrides.

candidate:package_keyword_entry(C, N, K) :-
  current_predicate(userconfig:package_keyword/2),
  atomic_list_concat([C, N], '/', CatPkg),
  userconfig:package_keyword(CatPkg, RawKW),
  candidate:raw_kw_to_term_(RawKW, K).

candidate:raw_kw_to_term_(RawKW, K) :-
  atom_codes(RawKW, Codes),
  catch(phrase(eapi:keywords([K]), Codes), _, fail).

%! candidate:query_keyword_candidate(+Action, +C, +N, +Keyword, +Context, -RepoEntry)
%
% Enumerates unmasked candidates for (C,N) matching keyword K. Handles
% self-reference filtering when the parent is the same (C,N).

candidate:query_keyword_candidate(Action, C, N, K, Context, FoundRepo://Candidate) :-
  ( Action \== run,
    memberchk(self(SelfRepo0://SelfEntry0), Context),
    query:search([category(C),name(N)], SelfRepo0://SelfEntry0)
  ->
    query:search([name(N),category(C),keyword(K)], FoundRepo://Candidate),
    \+ preference:masked(FoundRepo://Candidate),
    ( FoundRepo == SelfRepo0,
      Candidate == SelfEntry0
    ->
      \+ preference:flag(emptytree),
      query:search(installed(true), FoundRepo://Candidate)
    ; true
    )
  ; query:search([name(N),category(C),keyword(K)], FoundRepo://Candidate),
    \+ preference:masked(FoundRepo://Candidate)
  ).

%! candidate:compare_candidate_version_desc(-Delta, +A, +B)
%
% Comparison predicate for predsort/3: orders candidates by version
% descending (newest first).

candidate:compare_candidate_version_desc(Delta, RepoA://IdA, RepoB://IdB) :-
  cache:ordered_entry(RepoA, IdA, _Ca, _Na, VerA),
  cache:ordered_entry(RepoB, IdB, _Cb, _Nb, VerB),
  ( eapi:version_compare(>, VerA, VerB) -> Delta = (<)
  ; eapi:version_compare(<, VerA, VerB) -> Delta = (>)
  ; Delta = (=)
  ).


%! candidate:candidate_non_accepted_keyword(+RepoEntry, -NonAccKw) is semidet.
%
% Returns the most relevant non-accepted keyword on RepoEntry. Prefers a
% keyword matching the user's architecture (e.g. ~amd64 when the user
% accepts amd64). Falls back to ** when the package has no keyword for
% the user's arch at all, or has no keywords whatsoever.

candidate:candidate_non_accepted_keyword(Repo://Entry, NonAccKw) :-
  findall(K, preference:accept_keywords(K), AcceptedKs0),
  sort(AcceptedKs0, AcceptedKs),
  findall(NK,
          ( cache:entry_metadata(Repo, Entry, keywords, NK),
            \+ memberchk(NK, AcceptedKs)
          ),
          NonAccKws0),
  sort(NonAccKws0, NonAccKws),
  candidate_best_keyword_suggestion(AcceptedKs, NonAccKws, NonAccKw),
  !.


%! candidate:candidate_best_keyword_suggestion(+AcceptedKs, +NonAccKws, -Best)
%
% Selects the most useful keyword suggestion. Prefers a keyword whose
% architecture matches the user's ACCEPT_KEYWORDS (e.g. unstable(amd64)
% for an amd64 user). Returns ** when no arch-relevant keyword exists.

candidate:candidate_best_keyword_suggestion(AcceptedKs, NonAccKws, Best) :-
  NonAccKws \== [],
  findall(Arch,
          ( member(K, AcceptedKs),
            keyword_arch(K, Arch)
          ),
          Archs0),
  sort(Archs0, Archs),
  ( member(NK, NonAccKws),
    keyword_arch(NK, A),
    memberchk(A, Archs)
  ->
    Best = NK
  ;
    Best = '**'
  ),
  !.
candidate:candidate_best_keyword_suggestion(_AcceptedKs, [], '**').


%! candidate:keyword_arch(+Keyword, -Arch)
%
% Extracts the architecture atom from a keyword term.

candidate:keyword_arch(stable(Arch), Arch).
candidate:keyword_arch(unstable(Arch), Arch).


% =============================================================================
%  Provider-reuse candidate reordering (Portage-like)
% =============================================================================

%! candidate:candidates_prefer_proven_providers(+C, +N, +SlotReq, +Candidates, -Reordered)
%
% For virtual packages: reorders candidates to prefer providers whose
% dependencies have already been proven in the current proof tree.
% Non-virtual packages pass through unchanged. This mirrors Portage's
% behaviour of preferring virtual providers that are already being
% installed as part of the dependency closure.

candidate:candidates_prefer_proven_providers(virtual, _N, SlotReq, Candidates, Reordered) :-
  SlotReq \= [slot(_)|_],
  include(candidate_has_proven_provider, Candidates, Preferred),
  Preferred \== [],
  !,
  subtract(Candidates, Preferred, Rest),
  append(Preferred, Rest, Reordered).
candidate:candidates_prefer_proven_providers(_C, _N, _SlotReq, Candidates, Candidates).

%! candidate:candidate_has_proven_provider(+RepoEntry)
%
% True if the candidate's RDEPEND references a (C,N) that has already
% been selected in the current proof.

candidate:candidate_has_proven_provider(Repo://Entry) :-
  cache:entry_metadata(Repo, Entry, rdepend, Dep),
  dep_references_selected_cn(Dep),
  !.

%! candidate:dep_references_selected_cn(+DepTerm)
%
% True if a dependency term references a (C,N) pair that has been
% selected in the current proof snapshot.

candidate:dep_references_selected_cn(package_dependency(_Phase,_Str,C,N,_O,_V,Ss,_U)) :-
  snapshot_selected_cn_candidates(C, N, SelCandidates),
  ( Ss = [slot(ReqSlot0)|_] ->
      canon_slot(ReqSlot0, ReqSlot),
      member(SelRepo://SelEntry, SelCandidates),
      query:search(slot(SelSlotRaw), SelRepo://SelEntry),
      canon_slot(SelSlotRaw, SelSlot),
      ReqSlot == SelSlot
  ; true
  ),
  !.
candidate:dep_references_selected_cn(any_of_group(Deps)) :-
  member(D, Deps),
  dep_references_selected_cn(D),
  !.


% =============================================================================
%  Candidate eligibility
% =============================================================================

%! candidate:eligible(+Literal) is semidet.
%
% Succeeds when the candidate is eligible for the given action.
% Goal-expanded at compile time per action:
%   - :download  — entry exists in the repository
%   - all others — not masked (unless assuming unmask) and keyword-accepted
%                   (unless assuming keyword_acceptance)

candidate:eligible(Repo://Entry:download?{_}) :-
  !,
  query:search(ebuild(Entry), Repo://Entry).

candidate:eligible(Repo://Entry:_Action?{_}) :-
  ( query:search(masked(true), Repo://Entry) ->
      prover:assuming(unmask)
  ; true
  ),
  ( candidate:entry_has_accepted_keyword(Repo://Entry) ->
      true
  ; prover:assuming(keyword_acceptance)
  ).


%! candidate:eligible(use_conditional(+Polarity, +Use, +R://+E):+Action?{+Context})
%
% Succeeds when a USE conditional is active. Checks in order:
%   1. Context-assumed (dependency-induced or required_use)
%   2. Global profile USE on a non-IUSE flag (e.g. kernel_linux)
%   3. Effective USE for the ebuild (IUSE defaults + profile/env/package.use)

candidate:eligible(use_conditional(positive, Use, _R://_E):_?{Context}) :-
  use:assumed(Context, Use), !.
candidate:eligible(use_conditional(positive, Use, R://E):_?{_}) :-
  \+ Use =.. [minus,_],
  preference:global_use(Use),
  \+ ( query:search(iuse(Value), R://E),
       eapi:strip_use_default(Value, Use) ), !.
candidate:eligible(use_conditional(positive, Use, R://E):_?{_}) :-
  use:effective_use_for_entry(R://E, Use, positive), !.

candidate:eligible(use_conditional(negative, Use, _R://_E):_?{Context}) :-
  use:assumed_minus(Context, Use), !.
candidate:eligible(use_conditional(negative, Use, R://E):_?{_}) :-
  preference:global_use(minus(Use)),
  \+ ( query:search(iuse(Value), R://E),
       eapi:strip_use_default(Value, Use) ), !.
candidate:eligible(use_conditional(negative, Use, R://E):_?{_}) :-
  \+ preference:global_use(Use),
  \+ preference:global_use(minus(Use)),
  \+ ( query:search(iuse(Value), R://E),
       eapi:strip_use_default(Value, Use) ), !.
candidate:eligible(use_conditional(negative, Use, R://E):_?{_}) :-
  use:effective_use_for_entry(R://E, Use, negative), !.




%! candidate:installed(+RepoEntry) is semidet.
%
% Succeeds when the entry is installed (exists in the pkg repository).
% Goal-expanded at compile time to cache:ordered_entry(pkg, Id, _, _, _).

candidate:installed(Repo://Entry) :-
  query:search(installed(true), Repo://Entry).


% =============================================================================
%  Keyword helpers
% =============================================================================

%! candidate:entry_has_keyword(+RepoEntry)
%
% True if the entry has any keyword metadata at all.

candidate:entry_has_keyword(Repo://Entry) :-
  query:search(keyword(_), Repo://Entry),
  !.


%! candidate:entry_has_accepted_keyword(+RepoEntry)
%
% True if the entry has at least one keyword in ACCEPT_KEYWORDS or
% is accepted via per-package /etc/portage/package.accept_keywords.

candidate:entry_has_accepted_keyword(Repo://Entry) :-
  preference:accept_keywords(K),
  query:search(keyword(K), Repo://Entry),
  !.

candidate:entry_has_accepted_keyword(Repo://Entry) :-
  query:search([category(C), name(N)], Repo://Entry),
  cache:entry_metadata(Repo, Entry, keywords, K),
  preference:package_keyword_accepted(C, N, K),
  !.


%! candidate:entry_is_keyword_filtered(+RepoEntry)
%
% True if the entry has keyword metadata but none match ACCEPT_KEYWORDS.

candidate:entry_is_keyword_filtered(Repo://Entry) :-
  candidate:entry_has_keyword(Repo://Entry),
  \+ candidate:entry_has_accepted_keyword(Repo://Entry).


%! candidate:entry_needs_keyword_acceptance(+RepoEntry)
%
% True if the entry should be rejected in strict mode.

candidate:entry_needs_keyword_acceptance(Repo://Entry) :-
  candidate:entry_is_keyword_filtered(Repo://Entry),
  !.
candidate:entry_needs_keyword_acceptance(Repo://Entry) :-
  \+ candidate:entry_has_keyword(Repo://Entry),
  \+ query:search(slot(_), Repo://Entry).


% =============================================================================
%  Blocker/conflict assumption overrides
% =============================================================================

%! candidate:assume_blockers
%
% True when blocker constraints should be treated as domain assumptions.

candidate:assume_blockers :-
  prover:assuming(blockers).


%! candidate:with_assume_blockers(:Goal)
%
% Runs Goal in a scope where blockers are treated as domain assumptions.

candidate:with_assume_blockers(Goal) :-
  prover:assuming(blockers, Goal).


%! candidate:assume_conflicts
%
% True when USE/REQUIRED_USE conflicts should be treated as domain
% assumptions rather than hard failures.

candidate:assume_conflicts :-
  prover:assuming(conflicts).


%! candidate:with_assume_conflicts(:Goal)
%
% Runs Goal in a scope where conflicts are treated as domain assumptions.

candidate:with_assume_conflicts(Goal) :-
  prover:assuming(conflicts, Goal).


% =============================================================================
%  any_of config-phase validation
% =============================================================================

%! candidate:any_of_reject_assumed_choice(+Dep, +Conditions)
%
% True if the chosen any_of alternative resolved only via a domain
% assumption.  Forces backtracking to the next alternative.

candidate:any_of_reject_assumed_choice(grouped_package_dependency(_Strength, C, N, _PackageDeps),
                                   [assumed(grouped_package_dependency(C, N, _Deps):_Act?{_Ctx})]) :-
  !.


candidate:any_of_config_dep_ok(Context, all_of_group(Deps)) :-
  !,
  candidate:any_of_config_deps_all_ok(Context, Deps).
candidate:any_of_config_dep_ok(Context, any_of_group(Deps)) :-
  !,
  candidate:any_of_config_deps_any_ok(Context, Deps).
candidate:any_of_config_dep_ok(Context, use_conditional_group(Pol, Use, RepoEntry, Deps)) :-
  !,
  rule(use_conditional_group(Pol, Use, RepoEntry, Deps):config?{Context}, Conditions),
  Conditions \== [],
  candidate:any_of_config_conditions_all_ok(Context, Conditions).

candidate:any_of_config_dep_ok(Context, package_dependency(Phase, _Strength, C, N, O, V, SlotReq, U)) :-
  findall(Repo://Id,
          ( candidate:accepted_keyword_candidate(Phase, C, N, SlotReq, _Ss, Context, Repo://Id),
            query:search(select(version, O, V), Repo://Id)
          ),
          Candidates0),
  sort(Candidates0, Candidates),
  Candidates \== [],
  ( U == []
  -> true
  ; member(Candidate, Candidates),
    use:candidate_satisfies_use_deps(Context, Candidate, U)
  ),
  !.
candidate:any_of_config_dep_ok(_Context, package_dependency(_Phase, _Strength, _C, _N, _O, _V, _S, _U)) :-
  candidate:assume_conflicts,
  !.
candidate:any_of_config_dep_ok(_Context, package_dependency(_Phase, _Strength, _C, _N, _O, _V, _S, _U)) :-
  !,
  fail.
candidate:any_of_config_dep_ok(_Context, _Other) :-
  true.


candidate:any_of_config_deps_all_ok(_Context, []) :- !.
candidate:any_of_config_deps_all_ok(Context, [Dep|Rest]) :-
  candidate:any_of_config_dep_ok(Context, Dep),
  candidate:any_of_config_deps_all_ok(Context, Rest).


candidate:any_of_config_deps_any_ok(Context, Deps) :-
  member(Dep, Deps),
  candidate:any_of_config_dep_ok(Context, Dep),
  !.


candidate:any_of_config_conditions_all_ok(_Context, []) :- !.
candidate:any_of_config_conditions_all_ok(Context, [Cond|Rest]) :-
  candidate:any_of_config_condition_dep(Cond, Dep),
  candidate:any_of_config_dep_ok(Context, Dep),
  candidate:any_of_config_conditions_all_ok(Context, Rest).


candidate:any_of_config_condition_dep(Dep:config?{_Ctx}, Dep) :- !.
candidate:any_of_config_condition_dep(Dep, Dep).


%! candidate:group_choice_dep(+Dep0, -Dep)
%
% Lifts a plain package_dependency/8 into a grouped_package_dependency/4
% wrapper so it can be resolved by the grouped dependency rule.

candidate:group_choice_dep(package_dependency(Phase,Strength,C,N,O,V,S,U),
                       grouped_package_dependency(Strength,C,N,
                           [package_dependency(Phase,Strength,C,N,O,V,S,U)])) :- !.
candidate:group_choice_dep(D, D).


% -----------------------------------------------------------------------------
%  Grouped-dependency resolution helpers
% -----------------------------------------------------------------------------


% -----------------------------------------------------------------------------
%  Phase 2: Keep-installed fast path
% -----------------------------------------------------------------------------

%! candidate:grouped_dep_keep_installed(+Action, +C, +N, +PackageDeps, +Context) is semidet.
%
% Succeeds when an installed VDB entry satisfies all version constraints,
% bracketed USE deps, and rebuild flags for this grouped dependency.

candidate:grouped_dep_keep_installed(Action, C, N, PackageDeps1, Context) :-
  candidate:merge_slot_restriction(Action, C, N, PackageDeps1, SlotReq),
  query:search([name(N),category(C),installed(true)], pkg://InstalledEntry),
  candidate:query_search_slot_constraint(SlotReq, pkg://InstalledEntry, _),
  candidate:installed_entry_satisfies_package_deps(Action, C, N, PackageDeps1, pkg://InstalledEntry),
  findall(U0, member(package_dependency(_P0,no,C,N,_O,_V,_,U0),PackageDeps1), MergedUse0),
  append(MergedUse0, MergedUse),
  dependency:process_build_with_use(MergedUse, Context, ContextWU, _BWUCons, pkg://InstalledEntry),
  ( C == 'virtual'
  -> true
  ; use:installed_entry_satisfies_build_with_use(pkg://InstalledEntry, ContextWU)
  ),
  ( preference:flag(newuse) ->
      \+ use:newuse_mismatch(pkg://InstalledEntry)
  ; preference:flag(changeduse) ->
      \+ use:changeduse_mismatch(pkg://InstalledEntry)
  ; true
  ),
  \+ target:rebuild_if_newer_available(pkg://InstalledEntry),
  \+ target:is_excluded_cn(C, N),
  !.


% -----------------------------------------------------------------------------
%  Phase 3: Candidate selection and constraint assembly
% -----------------------------------------------------------------------------

%! candidate:grouped_dep_select_and_build(+Action, +C, +N, +PackageDeps, +Context, -Conditions) is nondet.
%
% Selects a candidate from portage/overlays, verifies version/slot/USE
% constraints, tags suggestions, determines update-vs-install action,
% and assembles the final proof conditions list.

candidate:grouped_dep_select_and_build(Action, C, N, PackageDeps1, Context, Conditions) :-
  candidate:merge_slot_restriction(Action, C, N, PackageDeps1, SlotReq),
  candidate:grouped_dep_slot_lock(SlotReq, C, N, Context, SsLock),
  candidate:grouped_dep_find_candidate(Action, C, N, SlotReq, SsLock, PackageDeps1, Context,
                                       FoundRepo://Candidate, CandPreVerified),
  candidate:grouped_dep_avoid_self(C, N, Context, FoundRepo://Candidate),
  candidate:grouped_dep_verify_candidate(CandPreVerified, Action, C, N, PackageDeps1, Context,
                                         FoundRepo://Candidate),
  candidate:candidate_reverse_deps_compatible_with_parent(Context, FoundRepo://Candidate),
  candidate:grouped_dep_use_and_slot(Action, C, N, PackageDeps1, SlotReq, Context,
                                     FoundRepo://Candidate,
                                     Constraints, SlotMeta, NewerContext0),
  candidate:grouped_dep_tag_suggestions(FoundRepo://Candidate, NewerContext0, NewerContext),
  candidate:grouped_dep_determine_action(Action, C, N, FoundRepo://Candidate,
                                         SlotMeta, NewerContext, ActionGoal),
  candidate:grouped_dep_assemble_conditions(Action, C, N, PackageDeps1, SlotReq, Context,
                                            FoundRepo://Candidate, SlotMeta,
                                            Constraints, ActionGoal, Conditions).


%! candidate:grouped_dep_slot_lock(+SlotReq, +C, +N, +Context, -SsLock) is det.
%
% When the context carries a slot lock for (C,N) via :=, bind SsLock to
% restrict candidate enumeration. Otherwise SsLock is unbound.

candidate:grouped_dep_slot_lock([any_same_slot], C, N, Context, SsLock) :-
  memberchk(slot(C,N,SsLock0):{_}, Context),
  candidate:canon_any_same_slot_meta(SsLock0, SsLock),
  !.
candidate:grouped_dep_slot_lock(_, _, _, _, _).


%! candidate:grouped_dep_find_candidate(+Action, +C, +N, +SlotReq, +SsLock, +PackageDeps, +Context, -Entry, -PreVerified) is nondet.
%
% Enumerates candidate entries respecting slot constraints and CN-consistency.

candidate:grouped_dep_find_candidate(Action, C, N, [slot(_)|_] = SlotReq, _SsLock, _PackageDeps1, Context,
                                     FoundRepo://Candidate, false) :-
  !,
  candidate:accepted_keyword_candidate(Action, C, N, SlotReq, _Ss0, Context, FoundRepo://Candidate).
candidate:grouped_dep_find_candidate(Action, C, N, SlotReq, _SsLock, PackageDeps1, Context,
                                     FoundRepo://Candidate, true) :-
  candidate:selected_cn_candidate_compatible(Action, C, N, SlotReq, PackageDeps1, Context, FoundRepo://Candidate),
  !.
candidate:grouped_dep_find_candidate(Action, C, N, SlotReq, SsLock, PackageDeps1, Context,
                                     FoundRepo://Candidate, false) :-
  candidate:grouped_dep_effective_domain_precomputed(Action, C, N, PackageDeps1, Context, EffDom, RejectDom),
  candidate:accepted_keyword_candidate(Action, C, N, SlotReq, SsLock, Context, FoundRepo://Candidate),
  ( candidate:selected_cn_candidate(Action, C, N, Context, FoundRepo://Candidate),
    candidate:query_search_slot_constraint(SlotReq, FoundRepo://Candidate, _)
  ->
    candidate:grouped_dep_candidate_satisfies_constraints_precomputed(
        C, N, PackageDeps1, EffDom, RejectDom, FoundRepo://Candidate)
  ; true
  ).


%! candidate:grouped_dep_avoid_self(+C, +N, +Context, +Entry) is semidet.
%
% Prevents resolving a dependency to the parent package itself unless
% the candidate is already installed.

candidate:grouped_dep_avoid_self(C, N, Context, FoundRepo://Candidate) :-
  ( ( memberchk(self(_SelfRepo://SelfEntry1), Context)
    ; memberchk(slot(C,N,_SelfSlot):{SelfEntry1}, Context)
    ),
    Candidate == SelfEntry1
  ->
    \+ preference:flag(emptytree),
    query:search(installed(true), FoundRepo://Candidate)
  ; true
  ).


%! candidate:grouped_dep_verify_candidate(+PreVerified, +Action, +C, +N, +PackageDeps, +Context, +Entry) is semidet.
%
% When PreVerified is false, checks that the candidate satisfies all
% version constraints and the effective domain.

candidate:grouped_dep_verify_candidate(true, _, _, _, _, _, _) :- !.
candidate:grouped_dep_verify_candidate(false, Action, C, N, PackageDeps1, Context, FoundRepo://Candidate) :-
  cache:ordered_entry(FoundRepo, Candidate, _, _, CandVer),
  forall(member(package_dependency(_P1,no,C,N,O,V,_,_), PackageDeps1),
         preference:version_match(O, CandVer, V)),
  candidate:grouped_dep_candidate_satisfies_effective_domain(Action, C, N, PackageDeps1, Context, FoundRepo://Candidate).


%! candidate:grouped_dep_use_and_slot(+Action, +C, +N, +PackageDeps, +SlotReq, +Context, +Entry, -Constraints, -SlotMeta, -NewContext) is semidet.
%
% Processes USE deps (bracketed constraints, PDEPEND stripping, BWU conflict
% checks) and slot binding for the selected candidate.

candidate:grouped_dep_use_and_slot(_Action, C, N, PackageDeps1, SlotReq, Context,
                                   FoundRepo://Candidate,
                                   Constraints, SlotMeta, NewerContext0) :-
  ( member(package_dependency(pdepend,_,C,N,_,_,_,_), PackageDeps1) ->
      MergedUse = [],
      featureterm:drop_build_with_use_and_assumption_reason(Context, ContextDep)
  ; findall(U0, member(package_dependency(_P2,no,C,N,_O,_V,_,U0),PackageDeps1), MergedUse0),
    append(MergedUse0, MergedUse),
    ContextDep = Context
  ),
  use:candidate_satisfies_use_deps(ContextDep, FoundRepo://Candidate, MergedUse),
  dependency:process_build_with_use(MergedUse, ContextDep, NewContext, Constraints, FoundRepo://Candidate),
  use:check_bwu_ed_conflict(C, N, NewContext),
  candidate:query_search_slot_constraint(SlotReq, FoundRepo://Candidate, SlotMeta),
  dependency:process_slot(SlotReq, SlotMeta, C, N, FoundRepo://Candidate, NewContext, NewerContext0).


%! candidate:grouped_dep_tag_suggestions(+Entry, +Context0, -Context) is det.
%
% Tags the context with keyword-acceptance, unmask, license, and USE-change
% suggestions when applicable.

candidate:grouped_dep_tag_suggestions(FoundRepo://Candidate, Ctx0, Ctx) :-
  ( prover:assuming(keyword_acceptance),
    candidate:candidate_non_accepted_keyword(FoundRepo://Candidate, NonAccKw)
  ->
    feature_unification:unify([suggestion(accept_keyword, NonAccKw)], Ctx0, Ctx1)
  ; prover:assuming(unmask),
    preference:masked(FoundRepo://Candidate)
  ->
    feature_unification:unify([suggestion(unmask, FoundRepo://Candidate)], Ctx0, Ctx1)
  ; candidate:license_masked(FoundRepo://Candidate)
  ->
    feature_unification:unify([suggestion(unmask, FoundRepo://Candidate)], Ctx0, Ctx1)
  ; Ctx1 = Ctx0
  ),
  ( use:context_build_with_use_state(Ctx1, BWUState),
    use:build_with_use_changes(BWUState, FoundRepo://Candidate, UseChanges),
    UseChanges \== []
  ->
    feature_unification:unify([suggestion(use_change, FoundRepo://Candidate, UseChanges)], Ctx1, Ctx)
  ; Ctx = Ctx1
  ).


%! candidate:grouped_dep_determine_action(+Action, +C, +N, +Entry, +SlotMeta, +Context, -ActionGoal) is det.
%
% Determines whether the dep is a fresh install, update, downgrade, or
% rebuild based on the installed VDB state and CLI flags.

candidate:grouped_dep_determine_action(Action, C, N, FoundRepo://Candidate,
                                       SlotMeta, NewerContext, ActionGoal) :-
  ( \+ preference:flag(emptytree),
    candidate:selected_cn_slot_key_(SlotMeta, SlotChosen),
    query:search([name(N),category(C),installed(true)], pkg://InstalledEntry2),
    ( query:search(slot(SlotInstalled0), pkg://InstalledEntry2)
      -> candidate:canon_slot(SlotInstalled0, SlotInstalled)
      ;  SlotInstalled = SlotChosen
    ),
    SlotInstalled == SlotChosen,
    !,
    candidate:grouped_dep_update_reason(C, N, FoundRepo://Candidate,
                                        pkg://InstalledEntry2, NewerContext,
                                        DepUpdateAction, UpdateCtx)
  ->
    ActionGoal = FoundRepo://Candidate:DepUpdateAction?{UpdateCtx}
  ; ActionGoal = FoundRepo://Candidate:Action?{NewerContext}
  ).


%! candidate:grouped_dep_update_reason(+C, +N, +CandEntry, +InstalledEntry, +Context, -UpdateAction, -UpdateCtx) is semidet.
%
% Determines the specific update reason (version change, BWU rebuild,
% --newuse, --changed-use, --rebuild-if-new-*).

candidate:grouped_dep_update_reason(_C, _N, FoundRepo://Candidate,
                                    pkg://InstalledEntry2, NewerContext,
                                    DepUpdateAction, UpdateCtx) :-
  InstalledEntry2 \== Candidate,
  query:search(version(OldVer), pkg://InstalledEntry2),
  query:search(version(CandVer0), FoundRepo://Candidate),
  OldVer \== CandVer0,
  !,
  feature_unification:unify([replaces(pkg://InstalledEntry2)], NewerContext, UpdateCtx),
  ( eapi:version_compare(<, CandVer0, OldVer)
  -> DepUpdateAction = downgrade
  ;  DepUpdateAction = update
  ).
candidate:grouped_dep_update_reason(C, _N, _FoundRepo://_Candidate,
                                    pkg://InstalledEntry2, NewerContext,
                                    update, UpdateCtx) :-
  ( current_predicate(config:avoid_reinstall/1),
    config:avoid_reinstall(true) ->
      fail
  ; C \== 'virtual',
    \+ use:installed_entry_satisfies_build_with_use(pkg://InstalledEntry2, NewerContext)
  ),
  !,
  feature_unification:unify([replaces(pkg://InstalledEntry2),rebuild_reason(build_with_use)], NewerContext, UpdateCtx).
candidate:grouped_dep_update_reason(_C, _N, FoundRepo://Candidate,
                                    pkg://InstalledEntry2, NewerContext,
                                    update, UpdateCtx) :-
  preference:flag(newuse),
  use:newuse_mismatch(pkg://InstalledEntry2, FoundRepo://Candidate),
  !,
  feature_unification:unify([replaces(pkg://InstalledEntry2),rebuild_reason(newuse)], NewerContext, UpdateCtx).
candidate:grouped_dep_update_reason(_C, _N, FoundRepo://Candidate,
                                    pkg://InstalledEntry2, NewerContext,
                                    update, UpdateCtx) :-
  preference:flag(changeduse),
  use:changeduse_mismatch(pkg://InstalledEntry2, FoundRepo://Candidate),
  !,
  feature_unification:unify([replaces(pkg://InstalledEntry2),rebuild_reason(changeduse)], NewerContext, UpdateCtx).
candidate:grouped_dep_update_reason(_C, _N, _FoundRepo://_Candidate,
                                    pkg://InstalledEntry2, NewerContext,
                                    update, UpdateCtx) :-
  target:rebuild_if_newer_available(pkg://InstalledEntry2),
  feature_unification:unify([replaces(pkg://InstalledEntry2),rebuild_reason(rebuild)], NewerContext, UpdateCtx).


%! candidate:grouped_dep_assemble_conditions(+Action, +C, +N, +PackageDeps, +SlotReq, +Context, +Entry, +SlotMeta, +Constraints, +ActionGoal, -Conditions) is det.
%
% Assembles the final proof conditions list from the selected candidate,
% its constraints, domain constraints, and the action goal.

candidate:grouped_dep_assemble_conditions(Action, C, N, PackageDeps1, SlotReq, Context,
                                          FoundRepo://Candidate, SlotMeta,
                                          Constraints, ActionGoal, Conditions) :-
  ( ActionGoal = _://_:ActSel?{_} -> true
  ; ActionGoal = _://_:ActSel     -> true
  ; ActSel = Action
  ),
  query:search(version(CandVer), FoundRepo://Candidate),
  Selected = constraint(selected_cn(C,N):{ordset([selected(FoundRepo,Candidate,ActSel,CandVer,SlotMeta)])}),
  candidate:selected_cn_allow_multislot_constraints(C, N, SlotReq, PackageDeps1, AllowMultiSlotCons),
  candidate:cn_domain_constraints(Action, C, N, PackageDeps1, Context, DomainCons0, _DomainReasonTags),
  candidate:domain_constraints_for_any_different_slot(SlotReq, DomainCons0, DomainCons),
  append(Constraints, [ActionGoal], ConstraintsTail),
  append(AllowMultiSlotCons, [Selected|ConstraintsTail], Suffix),
  append(DomainCons, Suffix, Conditions).


% -----------------------------------------------------------------------------
%  Phase 5: Assumption fallback with diagnostics
% -----------------------------------------------------------------------------

%! candidate:grouped_dep_build_assumption(+Action, +C, +N, +PackageDeps, +PackageDepsOrig, +Context, -Conditions) is det.
%
% Builds an assumption condition when no candidate could satisfy the
% grouped dependency. Tags context with explanation reason and
% actionable suggestions (keyword, unmask, slot conflict, REQUIRED_USE).

candidate:grouped_dep_build_assumption(Action, C, N, PackageDeps1, PackageDepsOrig, Context, Conditions) :-
  explanation:assumption_reason_for_grouped_dep(Action, C, N, PackageDepsOrig, Context, Reason),
  version_domain:domain_reason_terms(Action, C, N, PackageDeps1, Context, DomainReasonTags),
  candidate:add_domain_reason_context(C, N, DomainReasonTags, Context, Ctx2),
  feature_unification:unify([assumption_reason(Reason)], Ctx2, Ctx3),
  candidate:grouped_dep_tag_assumption_suggestion(C, N, PackageDeps1, Reason, Ctx3, Ctx4),
  ( memo:requse_violation_(C, N, ViolDesc) ->
      retractall(memo:requse_violation_(C, N, _)),
      feature_unification:unify([required_use_violation(ViolDesc)], Ctx4, Ctx5)
  ; Ctx5 = Ctx4
  ),
  ( use:find_dep_slot_conflict(C, N, SlotConflictDesc) ->
      feature_unification:unify([slot_conflict(SlotConflictDesc)], Ctx5, Ctx6)
  ; Ctx6 = Ctx5
  ),
  Conditions = [assumed(grouped_package_dependency(C,N,PackageDeps1):Action?{Ctx6})].


%! candidate:grouped_dep_tag_assumption_suggestion(+C, +N, +PackageDeps, +Reason, +Ctx0, -Ctx) is det.
%
% For keyword-filtered or masked assumptions, tags the context with the
% best actionable suggestion (accept-keyword or unmask).

candidate:grouped_dep_tag_assumption_suggestion(C, N, PackageDeps1, keyword_filtered, Ctx0, Ctx) :-
  !,
  ( memo:keyword_suggestion_cache_(C, N, CachedKw) ->
      SuggestedKw = CachedKw
  ; findall(Repo4://Entry4,
            ( query:search([category(C), name(N)], Repo4://Entry4),
              \+ preference:masked(Repo4://Entry4),
              forall(member(package_dependency(_,no,C,N,O4,V4,_,_), PackageDeps1),
                     query:search(select(version, O4, V4), Repo4://Entry4))
            ),
            KwCands1),
    explanation:candidate_keywords(KwCands1, CandKws),
    ( CandKws \== [] ->
        findall(AK, preference:accept_keywords(AK), AKs0),
        sort(AKs0, AKs),
        candidate:candidate_best_keyword_suggestion(AKs, CandKws, SuggestedKw)
    ; SuggestedKw = none
    ),
    assertz(memo:keyword_suggestion_cache_(C, N, SuggestedKw))
  ),
  ( SuggestedKw \== none ->
      feature_unification:unify([suggestion(accept_keyword, SuggestedKw)], Ctx0, Ctx)
  ; Ctx = Ctx0
  ).
candidate:grouped_dep_tag_assumption_suggestion(_C, _N, _PackageDeps1, masked, Ctx0, Ctx) :-
  !,
  feature_unification:unify([suggestion(unmask)], Ctx0, Ctx).
candidate:grouped_dep_tag_assumption_suggestion(_C, _N, _PackageDeps1, _Reason, Ctx, Ctx).