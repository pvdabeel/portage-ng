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

  2. *Version primitives* -- coerce_version_term/2: normalise version
     representations for comparison.

  3. *Slot restriction merging* -- merge_slot_restriction/5: combine
     slot requirements from multiple deps on the same (C,N).

  4. *Slot/version constraint queries* -- query_search_slot_constraint/3,
     query_search_version_select/3: bridge between dependency constraints
     and the query engine.

  5. *Installed entry satisfaction* -- installed_entry_satisfies_package_deps/5,
     installed_entry_cn/4: fast-path checks for already-installed packages.

  6. *CN-consistency* -- selected_cn_candidate/5 and friends: ensure that
     for a given (Category, Name) pair only compatible candidates are
     selected across the proof.

  7. *CN-domain reject map* -- cn_domain_reject_key/4,
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

canon_slot(S0, S) :-
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

canon_any_same_slot_meta(Meta0, [slot(S)]) :-
  is_list(Meta0),
  member(slot(S0), Meta0),
  canon_slot(S0, S),
  !.

%! candidate:entry_slot_default(+Repo, +Entry, -Slot)
%
% Looks up the slot for an entry, defaulting to '0' if unset.

entry_slot_default(Repo, Entry, Slot) :-
  ( query:search(slot(Slot0), Repo://Entry)
    -> canon_slot(Slot0, Slot)
    ;  Slot = '0'
  ).


% =============================================================================
%  Version primitives
% =============================================================================

%! candidate:coerce_version_term(+Ver0, -Ver)
%
% Normalises a version representation into the canonical version/7 compound
% used by the resolver. Handles version/7 terms, wildcard atoms (e.g.
% `'1.2.*'`), plain atoms parseable as version numbers, numeric values,
% and unbound variables (passed through).

coerce_version_term(Ver0, Ver) :-
  var(Ver0),
  !,
  Ver = Ver0.
coerce_version_term(version(_,_,_,_,_,_,_)=Ver, Ver) :- !.
coerce_version_term(Full, Ver) :-
  atom(Full),
  sub_atom(Full, _, 1, 0, '*'),
  !,
  Ver = version([0], '', 4, 0, '', 0, Full).
coerce_version_term(Full, version(Nums, '', 4, 0, '', 0, Full)) :-
  atom(Full),
  eapi:version2numberlist(Full, Nums),
  Nums \== [],
  !.
coerce_version_term(Num, Ver) :-
  number(Num),
  number_string(Num, S),
  atom_string(Full, S),
  !,
  coerce_version_term(Full, Ver).
coerce_version_term(Other, Other).


% =============================================================================
%  Slot restriction merging
% =============================================================================

%! candidate:merge_slot_restriction(+Action, +C, +N, +PackageDeps, -SlotReq)
%
% Combines slot requirements from all package_dependency/8 terms in
% PackageDeps that match (C,N). Returns `[]` if no slot requirement
% is present, or the merged slot restriction list (e.g. `[slot('3')]`).
% Fails if incompatible slot requirements cannot be merged.

merge_slot_restriction(Action, C, N, PackageDeps, SlotReq) :-
  merge_slot_restriction_(PackageDeps, Action, C, N, none, Slot0),
  ( Slot0 == none -> SlotReq = []
  ; SlotReq = Slot0
  ).

merge_slot_restriction_([], _Action, _C, _N, Acc, Acc) :- !.
merge_slot_restriction_([package_dependency(_Phase,no,C,N,_O,_V,S,_U)|Rest], Action, C, N, Acc0, Acc) :-
  !,
  ( S == []      -> Acc1 = Acc0
  ; Acc0 == none -> Acc1 = S
  ; Acc0 == S    -> Acc1 = Acc0
  ; merge_slot_restriction_pair(Acc0, S, Acc1) -> true
  ; fail
  ),
  merge_slot_restriction_(Rest, Action, C, N, Acc1, Acc).
merge_slot_restriction_([_|Rest], Action, C, N, Acc0, Acc) :-
  merge_slot_restriction_(Rest, Action, C, N, Acc0, Acc).

merge_slot_restriction_pair([slot(S0)], [slot(S1),equal], [slot(S),equal]) :-
  canon_slot(S0, S),
  canon_slot(S1, S),
  !.
merge_slot_restriction_pair([slot(S0),equal], [slot(S1)], [slot(S),equal]) :-
  canon_slot(S0, S),
  canon_slot(S1, S),
  !.
merge_slot_restriction_pair([slot(S0)], [slot(S1),subslot(Ss0)], [slot(S),subslot(Ss)]) :-
  canon_slot(S0, S),
  canon_slot(S1, S),
  canon_slot(Ss0, Ss),
  !.
merge_slot_restriction_pair([slot(S0),subslot(Ss0)], [slot(S1)], [slot(S),subslot(Ss)]) :-
  canon_slot(S0, S),
  canon_slot(S1, S),
  canon_slot(Ss0, Ss),
  !.
merge_slot_restriction_pair([slot(S0)], [slot(S1),subslot(Ss0),equal], [slot(S),subslot(Ss),equal]) :-
  canon_slot(S0, S),
  canon_slot(S1, S),
  canon_slot(Ss0, Ss),
  !.
merge_slot_restriction_pair([slot(S0),subslot(Ss0),equal], [slot(S1)], [slot(S),subslot(Ss),equal]) :-
  canon_slot(S0, S),
  canon_slot(S1, S),
  canon_slot(Ss0, Ss),
  !.
merge_slot_restriction_pair([slot(S0),equal], [slot(S1),subslot(Ss0)], [slot(S),subslot(Ss),equal]) :-
  canon_slot(S0, S),
  canon_slot(S1, S),
  canon_slot(Ss0, Ss),
  !.
merge_slot_restriction_pair([slot(S0),subslot(Ss0)], [slot(S1),equal], [slot(S),subslot(Ss),equal]) :-
  canon_slot(S0, S),
  canon_slot(S1, S),
  canon_slot(Ss0, Ss),
  !.
merge_slot_restriction_pair([slot(S0),equal], [slot(S1),subslot(Ss0),equal], [slot(S),subslot(Ss),equal]) :-
  canon_slot(S0, S),
  canon_slot(S1, S),
  canon_slot(Ss0, Ss),
  !.
merge_slot_restriction_pair([slot(S0),subslot(Ss0),equal], [slot(S1),equal], [slot(S),subslot(Ss),equal]) :-
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

query_search_slot_constraint(SlotReq, RepoEntry, SlotMeta) :-
  RepoEntry = Repo://Id,
  ( SlotReq == [] ->
      query:search(select(slot,constraint([]),SlotMeta), Repo://Id)
  ; SlotReq = [slot(S0)] ->
      canon_slot(S0, S),
      query:search(select(slot,constraint([slot(S)]),SlotMeta), Repo://Id)
  ; SlotReq = [slot(S0),subslot(Ss)] ->
      canon_slot(S0, S),
      ( query:search(select(slot,constraint([slot(S),subslot(Ss)]),SlotMeta), Repo://Id)
      -> true
      ; canon_slot(Ss, Ss1),
        Ss1 == S,
        \+ cache:entry_metadata(Repo, Id, subslot, _),
        query:search(select(slot,constraint([slot(S)]),_SlotMeta0), Repo://Id),
        SlotMeta = [slot(S),subslot(Ss1)]
      )
  ; SlotReq = [slot(S0),equal] ->
      canon_slot(S0, S),
      query:search(select(slot,constraint([slot(S),equal]),SlotMeta), Repo://Id)
  ; SlotReq = [slot(S0),subslot(Ss),equal] ->
      canon_slot(S0, S),
      ( query:search(select(slot,constraint([slot(S),subslot(Ss),equal]),SlotMeta), Repo://Id)
      -> true
      ; canon_slot(Ss, Ss1),
        Ss1 == S,
        \+ cache:entry_metadata(Repo, Id, subslot, _),
        query:search(select(slot,constraint([slot(S)]),_SlotMeta0), Repo://Id),
        SlotMeta = [slot(S),subslot(Ss1),equal]
      )
  ; SlotReq = [any_same_slot] ->
      query:search(select(slot,constraint([any_same_slot]),SlotMeta0), Repo://Id),
      canon_any_same_slot_meta(SlotMeta0, SlotMeta)
  ; SlotReq = [any_different_slot] ->
      query:search(select(slot,constraint([any_different_slot]),SlotMeta0), Repo://Id),
      SlotMeta = SlotMeta0
  ; query:search(select(slot,constraint(SlotReq),SlotMeta), Repo://Id)
  ).


% =============================================================================
%  Version select queries
% =============================================================================

%! candidate:query_search_version_select(+Op, +Ver, +RepoEntry)
%
% Queries the knowledge base for entries matching a version constraint.
% Op is a comparison operator (equal, smaller, greater, smallerequal,
% greaterequal, notequal, wildcard, tilde, none). Wildcard versions
% (ending in `*`) are matched via wildcard_match/2. The special operator
% `none` always succeeds (unconstrained).

query_search_version_select(equal, Ver0, RepoEntry) :-
  RepoEntry = Repo://Id,
  coerce_version_term(Ver0, Ver1),
  Ver1 = version(_,_,_,_,_,_,Pattern),
  atom(Pattern),
  sub_atom(Pattern, _, 1, 0, '*'),
  !,
  cache:ordered_entry(Repo, Id, _C, _N, version(_,_,_,_,_,_,ProposedVersion)),
  wildcard_match(Pattern, ProposedVersion).
query_search_version_select(equal, Ver, RepoEntry) :- !,
  RepoEntry = Repo://Id,
  coerce_version_term(Ver, Ver1),
  cache:ordered_entry(Repo, Id, _C, _N, Ver1).
query_search_version_select(none, _Ver, _RepoEntry) :- !.
query_search_version_select(smaller, Ver, RepoEntry) :- !,
  RepoEntry = Repo://Id,
  coerce_version_term(Ver, Ver1),
  query:search(select(version,smaller,Ver1), Repo://Id).
query_search_version_select(greater, Ver, RepoEntry) :- !,
  RepoEntry = Repo://Id,
  coerce_version_term(Ver, Ver1),
  query:search(select(version,greater,Ver1), Repo://Id).
query_search_version_select(smallerequal, Ver, RepoEntry) :- !,
  RepoEntry = Repo://Id,
  coerce_version_term(Ver, Ver1),
  query:search(select(version,smallerequal,Ver1), Repo://Id).
query_search_version_select(greaterequal, Ver, RepoEntry) :- !,
  RepoEntry = Repo://Id,
  coerce_version_term(Ver, Ver1),
  query:search(select(version,greaterequal,Ver1), Repo://Id).
query_search_version_select(notequal, Ver, RepoEntry) :- !,
  RepoEntry = Repo://Id,
  coerce_version_term(Ver, Ver1),
  query:search(select(version,notequal,Ver1), Repo://Id).
query_search_version_select(wildcard, Ver, RepoEntry) :- !,
  RepoEntry = Repo://Id,
  coerce_version_term(Ver, Ver1),
  query:search(select(version,wildcard,Ver1), Repo://Id).
query_search_version_select(tilde, Ver, RepoEntry) :- !,
  RepoEntry = Repo://Id,
  coerce_version_term(Ver, Ver1),
  query:search(select(version,tilde,Ver1), Repo://Id).
query_search_version_select(Op, Ver, RepoEntry) :-
  RepoEntry = Repo://Id,
  coerce_version_term(Ver, Ver1),
  query:search(select(version,Op,Ver1), Repo://Id).


% =============================================================================
%  Installed entry satisfaction
% =============================================================================

%! candidate:installed_entry_satisfies_package_deps(+Action, +C, +N, +PackageDeps, +Installed)
%
% True if the installed entry satisfies all version constraints in
% PackageDeps for (C,N). Used as a fast-path guard in the grouped
% dependency rule to skip candidate selection when an installed package
% already satisfies the dependency.

installed_entry_satisfies_package_deps(_Action, _C, _N, [], _Installed) :- !.
installed_entry_satisfies_package_deps(Action, C, N,
                                       [package_dependency(_Phase,no,C,N,O,V,_,_)|Rest],
                                       Installed) :-
  !,
  query_search_version_select(O, V, Installed),
  installed_entry_satisfies_package_deps(Action, C, N, Rest, Installed).
installed_entry_satisfies_package_deps(Action, C, N, [_|Rest], Installed) :-
  installed_entry_satisfies_package_deps(Action, C, N, Rest, Installed).

%! candidate:installed_entry_cn(+C, +N, -Repo, -Entry)
%
% Looks up an installed entry for (C,N) in the VDB (pkg repo).

installed_entry_cn(C, N, pkg, Entry) :-
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

selected_cn_candidate(Action, C, N, Context, FoundRepo://Candidate) :-
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

selected_cn_candidate_compatible(Action, C, N, SlotReq, PackageDeps, Context, FoundRepo://Candidate) :-
  selected_cn_candidate(Action, C, N, Context, FoundRepo://Candidate),
  query_search_slot_constraint(SlotReq, FoundRepo://Candidate, _),
  grouped_dep_candidate_satisfies_constraints(Action, C, N, PackageDeps, Context, FoundRepo://Candidate).

%! candidate:selected_cn_rejected_candidates(+Action, +C, +N, +SlotReq, +PackageDeps, +Context, -Rejected)
%
% Collects previously-selected candidates for (C,N) that do NOT satisfy
% the current dependency's constraints. Used to exclude them from fresh
% enumeration.

selected_cn_rejected_candidates(Action, C, N, SlotReq, PackageDeps, Context, Rejected) :-
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

grouped_dep_candidate_satisfies_constraints(Action, C, N, PackageDeps, Context, RepoEntry) :-
  forall(member(package_dependency(_Phase,no,C,N,O,V,_SlotReq,_Use), PackageDeps),
         query_search_version_select(O, V, RepoEntry)),
  grouped_dep_candidate_satisfies_effective_domain(Action, C, N, PackageDeps, Context, RepoEntry),
  !.

grouped_dep_candidate_satisfies_constraints_precomputed(C, N, PackageDeps, EffDom, RejectDom, RepoEntry) :-
  forall(member(package_dependency(_Phase,no,C,N,O,V,_SlotReq,_Use), PackageDeps),
         query_search_version_select(O, V, RepoEntry)),
  grouped_dep_candidate_satisfies_effective_domain_precomputed(EffDom, RejectDom, C, N, RepoEntry),
  !.

grouped_dep_effective_domain_precomputed(Action, C, N, PackageDeps, Context, EffectiveDomain, RejectDomain) :-
  grouped_dep_effective_domain(Action, C, N, PackageDeps, Context, EffectiveDomain),
  context_cn_reject_scope(C, N, Context, EffectiveDomain, RejectScope),
  cn_reject_scoped_domain(RejectScope, EffectiveDomain, RejectDomain),
  !.

grouped_dep_candidate_satisfies_effective_domain(Action, C, N, PackageDeps, Context, RepoEntry) :-
  grouped_dep_effective_domain_precomputed(Action, C, N, PackageDeps, Context, EffectiveDomain, RejectDomain),
  grouped_dep_candidate_satisfies_effective_domain_precomputed(EffectiveDomain, RejectDomain, C, N, RepoEntry),
  !.

grouped_dep_candidate_satisfies_effective_domain_precomputed(EffectiveDomain, RejectDomain, C, N, RepoEntry) :-
  \+ version_domain:domain_inconsistent(EffectiveDomain),
  \+ cn_domain_candidate_rejected(C, N, RejectDomain, RepoEntry),
  version_domain:domain_allows_candidate(EffectiveDomain, RepoEntry),
  !.

%! candidate:grouped_dep_effective_domain(+Action, +C, +N, +PackageDeps, +Context, -EffDom)
%
% Computes the effective version domain for a grouped dependency by
% intersecting the dep's own constraints, the context's CN domain,
% and any learned domain from prior reprove iterations.

grouped_dep_effective_domain(Action, C, N, PackageDeps, Context, EffectiveDomain) :-
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

apply_learned_domain(C, N, PackageDeps, D0, D) :-
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

dep_slot_key(PackageDeps, Slot) :-
  member(package_dependency(_, _, _, _, _, _, SlotReq, _), PackageDeps),
  SlotReq = [slot(S)|_], canon_slot(S, Slot), !.
dep_slot_key(_, any).

context_cn_domain_constraint(C, N, Context, Domain) :-
  is_list(Context),
  memberchk(constraint(cn_domain(C,N):{Domain}), Context),
  !.

context_cn_domain_reason(C, N, Context, Reasons) :-
  is_list(Context),
  ( memberchk(constraint(cn_domain_reason(C,N):{ordset(Reasons0)}), Context) ->
      Reasons = Reasons0
  ; memberchk(domain_reason(cn_domain(C,N,Reasons0)), Context) ->
      Reasons = Reasons0
  ; Reasons = []
  ),
  !.

context_selected_cn_candidates(C, N, Context, Candidates) :-
  is_list(Context),
  memberchk(constraint(selected_cn(C,N):{ordset(SelectedSet)}), Context),
  findall(Repo://Entry,
          member(selected(Repo,Entry,_Act,_SelVer,_SelSlotMeta), SelectedSet),
          Candidates0),
  sort(Candidates0, Candidates),
  Candidates \== [],
  !.

context_cn_reject_scope(C, N, Context, Domain, Scope) :-
  ( context_slot_scope(C, N, Context, Scope0) ->
      Scope = Scope0
  ; domain_slot_scope(Domain, Scope)
  ),
  !.

context_slot_scope(C, N, Context, slot(Slot)) :-
  is_list(Context),
  memberchk(slot(C,N,Ss0):{_}, Context),
  canon_any_same_slot_meta(Ss0, [slot(Slot)]),
  !.

domain_slot_scope(version_domain(slots([S0]), _Bounds), slot(S)) :-
  canon_slot(S0, S),
  !.
domain_slot_scope(_Domain, any) :-
  !.

cn_reject_scope_canon(slot(S0), slot(S)) :-
  canon_slot(S0, S),
  !.
cn_reject_scope_canon(any, any) :-
  !.
cn_reject_scope_canon(_Other, any) :-
  !.

cn_reject_scoped_domain(any, Domain, Domain) :-
  !.
cn_reject_scoped_domain(Scope0, Domain, scoped(Scope, Domain)) :-
  cn_reject_scope_canon(Scope0, Scope),
  !.

snapshot_selected_cn_candidates(C, N, Candidates) :-
  memo:selected_cn_snap_(C, N, Candidates),
  Candidates \== [],
  !.

record_selected_cn_snapshot(C, N, SelectedSet) :-
  findall(Repo://Entry,
          member(selected(Repo,Entry,_Act,_SelVer,_SelSlotMeta), SelectedSet),
          Candidates0),
  sort(Candidates0, Candidates),
  ( retract(memo:selected_cn_snap_(C, N, _)) -> true ; true ),
  assertz(memo:selected_cn_snap_(C, N, Candidates)),
  !.

snapshot_blocked_cn_sources(C, N, Sources) :-
  memo:blocked_cn_source_snap_(C, N, Sources),
  Sources \== [],
  !.

record_blocked_cn_source_snapshot(C, N, Sources0) :-
  sort(Sources0, Sources),
  Sources \== [],
  ( retract(memo:blocked_cn_source_snap_(C, N, OldSources)) -> true ; OldSources = [] ),
  ord_union(OldSources, Sources, MergedSources),
  assertz(memo:blocked_cn_source_snap_(C, N, MergedSources)),
  !.
record_blocked_cn_source_snapshot(_C, _N, _Sources) :-
  !.

reason_linked_selected_reprove_target(Reasons, SourceC, SourceN, [SourceRepo://SourceEntry]) :-
  is_list(Reasons),
  member(introduced_by(OriginRepo://OriginEntry, _ReasonAction, _ReasonWhat), Reasons),
  query:search([category(OriginC),name(OriginN)], OriginRepo://OriginEntry),
  snapshot_blocked_cn_sources(OriginC, OriginN, Sources),
  member(source(SourceRepo,SourceEntry,_Phase,_O,_V,_SlotReq), Sources),
  query:search([category(SourceC),name(SourceN)], SourceRepo://SourceEntry),
  snapshot_selected_cn_candidates(SourceC, SourceN, SelectedSourceCandidates),
  memberchk(SourceRepo://SourceEntry, SelectedSourceCandidates),
  !.

domain_conflicting_candidates(_Domain, [], []) :-
  !.
domain_conflicting_candidates(Domain, Candidates, Conflicting) :-
  findall(RepoEntry,
          ( member(RepoEntry, Candidates),
            \+ version_domain:domain_allows_candidate(Domain, RepoEntry)
          ),
          Conflicting0),
  sort(Conflicting0, Conflicting),
  !.

constraint_conflicting_candidates(_Action, _C, _N, _PackageDeps, _Context, [], []) :-
  !.
constraint_conflicting_candidates(Action, C, N, PackageDeps, Context, Candidates, Conflicting) :-
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

maybe_request_grouped_dep_reprove(Action, C, N, PackageDeps, Context) :-
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
maybe_request_grouped_dep_reprove(_Action, _C, _N, _PackageDeps, _Context) :-
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

cn_domain_reject_key(C, N, scoped(Scope0, Domain0), key(C,N,Scope,Domain)) :-
  cn_reject_scope_canon(Scope0, Scope),
  version_domain:domain_normalize(Domain0, Domain),
  !.
cn_domain_reject_key(C, N, Domain0, key(C,N,Scope,Domain)) :-
  version_domain:domain_normalize(Domain0, Domain),
  domain_slot_scope(Domain, Scope),
  !.

%! candidate:cn_domain_candidate_rejected(+C, +N, +Domain, +RepoEntry)
%
% True if RepoEntry has been rejected for (C,N) under Domain in a prior
% reprove iteration. Checks slot-scoped, domain-scoped, and global
% reject sets.

cn_domain_candidate_rejected(C, N, Domain0, RepoEntry) :-
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

add_cn_domain_rejects(C, N, Domain0, Candidates0, Added) :-
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

add_cn_domain_origin_rejects(Reasons, Added) :-
  is_list(Reasons),
  findall(C0-N0-Repo://Entry,
          ( member(introduced_by(Repo://Entry, _Action, _Why), Reasons),
            query:search([category(C0),name(N0)], Repo://Entry)
          ),
          Origins0),
  sort(Origins0, Origins),
  add_cn_domain_origin_rejects_(Origins, false, Added),
  !.
add_cn_domain_origin_rejects(_Reasons, false) :-
  !.

add_cn_domain_origin_rejects_([], Added, Added) :-
  !.
add_cn_domain_origin_rejects_([C-N-Repo://Entry|Rest], Added0, Added) :-
  add_cn_domain_rejects(C, N, none, [Repo://Entry], Added1),
  ( Added0 == true ->
      Added2 = true
  ; Added1 == true ->
      Added2 = true
  ; Added2 = false
  ),
  add_cn_domain_origin_rejects_(Rest, Added2, Added).

cn_domain_reprove_enabled :-
  prover:reprove_enabled,
  !.

maybe_request_cn_domain_reprove(C, N, Domain, Selected) :-
  maybe_request_cn_domain_reprove(C, N, Domain, Selected, []).

maybe_request_cn_domain_reprove(C, N, Domain, Selected, Reasons) :-
  cn_domain_reprove_enabled,
  findall(Repo://Entry,
          member(selected(Repo,Entry,_Act,_SelVer,_SelSlotMeta), Selected),
          Candidates0),
  sort(Candidates0, Candidates),
  Candidates \== [],
  throw(prover_reprove(cn_domain(C, N, Domain, Candidates, Reasons))).
maybe_request_cn_domain_reprove(_C, _N, _Domain, _Selected, _Reasons) :-
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

selected_cn_unique_or_reprove(C, N, SelectedMerged, Constraints) :-
  selected_cn_unique(C, N, SelectedMerged, Constraints),
  !.
selected_cn_unique_or_reprove(C, N, SelectedMerged, Constraints) :-
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
selected_cn_unique_or_reprove(C, N, _SelectedMerged, Constraints) :-
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
selected_cn_unique_or_reprove(_C, _N, _SelectedMerged, _Constraints) :-
  fail.

find_adjustable_origin(Reasons, OriginC, OriginN, Repo://Entry) :-
  member(introduced_by(Repo://Entry, _Action, _Why), Reasons),
  cache:ordered_entry(Repo, Entry, OriginC, OriginN, _),
  prover:learned(cn_domain(OriginC, OriginN, _), _), !.

%! candidate:maybe_learn_parent_narrowing(+C, +N, +PackageDeps, +Context)
%
% When a dependency on (C,N) is unsatisfiable, learns to exclude the
% parent version that introduced the dependency. This is the
% "wrong-level fix": the parent introduced a dep that cannot be
% satisfied, so exclude the parent version and reprove.

maybe_learn_parent_narrowing(C, N, PackageDeps, Context) :-
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

is_pdepend_failure(PackageDeps, _Context) :-
  member(package_dependency(pdepend, _, _, _, _, _, _, _), PackageDeps),
  !.
is_pdepend_failure(_, Context) :-
  is_list(Context),
  memberchk(after_only(_), Context),
  !.

is_multislot_miss(C, N, PackageDeps, Context) :-
  member(package_dependency(_, _, C, N, _, _, [slot(DepSlot0)|_], _), PackageDeps),
  canon_slot(DepSlot0, DepSlot),
  is_list(Context),
  memberchk(constraint(selected_cn(C,N):{ordset(Selected)}), Context),
  \+ ( member(selected(_, _, _, _, SlotMeta), Selected),
       selected_cn_slot_key_(SlotMeta, DepSlot) ),
  !.

selected_cn_partition_by_domain(_Domain, [], [], []) :-
  !.
selected_cn_partition_by_domain(Domain, [Sel|Rest], [Sel|AllowedRest], ConflictingRest) :-
  Sel = selected(Repo,Entry,_Act,_SelVer,_SelSlotMeta),
  version_domain:domain_allows_candidate(Domain, Repo://Entry),
  !,
  selected_cn_partition_by_domain(Domain, Rest, AllowedRest, ConflictingRest).
selected_cn_partition_by_domain(Domain, [Sel|Rest], AllowedRest, [Sel|ConflictingRest]) :-
  selected_cn_partition_by_domain(Domain, Rest, AllowedRest, ConflictingRest).

%! candidate:selected_cn_not_blocked_or_reprove(+C, +N, +Specs, +Selected, +Constraints)
%
% Enforces strong blocker constraints: if any Spec in Specs violates an
% already-selected entry, attempts reprove by rejecting the blocker source.
% Called by constraint_guard for blocked_cn constraints.

selected_cn_not_blocked_or_reprove(_C, _N, Specs, Selected, _Constraints) :-
  \+ specs_violate_selected(Specs, Selected),
  !.
selected_cn_not_blocked_or_reprove(C, N, _Specs, _Selected, Constraints) :-
  cn_domain_reprove_enabled,
  blocked_cn_source_reprove_target(C, N, Constraints, SourceC, SourceN, Candidates),
  Candidates \== [],
  throw(prover_reprove(cn_domain(SourceC, SourceN, none, Candidates, []))).
selected_cn_not_blocked_or_reprove(_C, _N, _Specs, _Selected, _Constraints) :-
  fail.

blocked_cn_source_reprove_target(C, N, Constraints, SourceC, SourceN, [Repo://Entry]) :-
  get_assoc(blocked_cn_source(C,N), Constraints, ordset(Sources)),
  member(source(Repo,Entry,_Phase,_O,_V,_SlotReq), Sources),
  query:search([category(SourceC),name(SourceN)], Repo://Entry),
  !.

%! candidate:selected_cn_domain_compatible_or_reprove(+C, +N, +Domain, +Selected, +Constraints)
%
% Checks that at least one entry in Selected is allowed by Domain.
% If not, learns the domain and requests reprove. Called by
% constraint_guard for cn_domain and selected_cn constraints.

selected_cn_domain_compatible_or_reprove(C, N, Domain, Selected, Constraints) :-
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
    ; ( get_assoc(cn_domain_reason(C,N), Constraints, ordset(Reasons0)) -> true ; Reasons0 = [] ),
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

prefer_global_selected_reject_from_domain(C, _N, Domain, Selected, _Constraints) :-
  C == 'dev-haskell',
  Selected \== [],
  domain_has_upper_bound(Domain),
  !.
prefer_global_selected_reject_from_domain(C, N, Domain, Selected, Constraints) :-
  C == 'dev-lang',
  N == ghc,
  Selected \== [],
  domain_has_upper_bound(Domain),
  \+ selected_cn_requires_same_slot_multiversion(C, N, Constraints),
  !.
prefer_global_selected_reject_from_domain(C, N, Domain, Selected, Constraints) :-
  C == 'dev-ml',
  N == cmdliner,
  Selected \== [],
  domain_has_upper_bound(Domain),
  \+ selected_cn_requires_same_slot_multiversion(C, N, Constraints),
  !.
prefer_global_selected_reject_from_domain(C, N, Domain, Selected, Constraints) :-
  Selected \== [],
  domain_has_equal_bound(Domain),
  \+ selected_cn_requires_same_slot_multiversion(C, N, Constraints),
  !.

domain_has_upper_bound(version_domain(_Slots, Bounds)) :-
  member(bound(Op, _Req), Bounds),
  ( Op == smaller
  ; Op == smallerequal
  ),
  !.

domain_has_equal_bound(version_domain(_Slots, Bounds)) :-
  member(bound(equal, _Req), Bounds),
  !.

selected_cn_allow_multislot_constraints(C, N, SlotReq, PackageDeps, [constraint(selected_cn_allow_multislot(C,N):{true})]) :-
  ( SlotReq = [slot(_)|_]
  ; SlotReq == [any_same_slot]
  ; SlotReq == [any_different_slot]
  ; all_deps_exactish_versioned(PackageDeps)
  ; dep_has_version_constraint(C, N, PackageDeps)
  ),
  !.
selected_cn_allow_multislot_constraints(_C, _N, _SlotReq, _PackageDeps, []).

selected_cn_unique(C, N, SelectedMerged, Constraints) :-
  ( get_assoc(selected_cn_allow_multislot(C,N), Constraints, _AllowFlag) ->
      ( selected_cn_requires_same_slot_multiversion(C, N, Constraints) ->
          selected_cn_unique_per_slot_or_subslot(SelectedMerged)
      ; selected_cn_unique_per_slot(SelectedMerged)
      )
  ; selected_cn_unique_strict(SelectedMerged)
  ).

selected_cn_unique_strict([]) :- !.
selected_cn_unique_strict([selected(Repo,Entry,_Act,_Ver,_SlotMeta)|Rest]) :-
  forall(member(selected(Repo2,Entry2,_A2,_V2,_SlotMeta2), Rest),
         ( Repo2 == Repo,
           Entry2 == Entry
         )),
  selected_cn_unique_strict(Rest).

selected_cn_unique_per_slot([]) :- !.
selected_cn_unique_per_slot([selected(Repo,Entry,_Act,_Ver,SlotMeta)|Rest]) :-
  selected_cn_slot_key_(SlotMeta, Slot),
  forall(member(selected(Repo2,Entry2,_A2,_V2,SlotMeta2), Rest),
         ( selected_cn_slot_key_(SlotMeta2, Slot2),
           ( Slot2 \== Slot -> true
           ; Repo2 == Repo, Entry2 == Entry
           )
         )),
  selected_cn_unique_per_slot(Rest).

selected_cn_unique_per_slot_or_subslot([]) :- !.
selected_cn_unique_per_slot_or_subslot([selected(Repo,Entry,_Act,_Ver,SlotMeta)|Rest]) :-
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

selected_cn_requires_same_slot_multiversion(C, N, Constraints) :-
  get_assoc(cn_domain(C,N), Constraints, Domain),
  version_domain:domain_inconsistent(Domain),
  !.

selected_cn_slot_subslot_key_(Repo, Entry, SlotMeta0, slot_subslot(Slot, SubSlot)) :-
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

selected_cn_slot_key_(SlotMeta0, Slot) :-
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

specs_violate_selected(Specs, Selected) :-
  member(blocked(Strength, Phase, O, V, SlotReq), Specs),
  Strength == strong,
  member(selected(Repo, Entry, Act, SelVer, SelSlotMeta), Selected),
  action_phase(Act, Phase),
  blocker_spec_matches_selected(SelVer, SelSlotMeta, Repo, Entry, O, V, SlotReq),
  !.

action_phase(run, run) :- !.
action_phase(install, install) :- !.
action_phase(reinstall, install) :- !.
action_phase(update, install) :- !.
action_phase(download, install) :- !.
action_phase(_Other, run).

blocker_spec_matches_selected(SelVer, SelSlotMeta, Repo, Entry, O, V, SlotReq) :-
  blocker_version_matches(O, V, SelVer, Repo, Entry),
  blocker_slot_matches(SlotReq, SelSlotMeta, Repo, Entry).

blocker_version_matches(none, _Req, _SelVer, _Repo, _Entry) :- !.
blocker_version_matches(equal, Req, SelVer, _Repo, _Entry) :- !, SelVer == Req.
blocker_version_matches(notequal, Req, SelVer, _Repo, _Entry) :- !, SelVer \== Req.
blocker_version_matches(smaller, Req, SelVer, _Repo, _Entry) :- !, system:compare(<, SelVer, Req).
blocker_version_matches(greater, Req, SelVer, _Repo, _Entry) :- !, system:compare(>, SelVer, Req).
blocker_version_matches(smallerequal, Req, SelVer, _Repo, _Entry) :- !,
  ( system:compare(<, SelVer, Req) ; system:compare(=, SelVer, Req) ).
blocker_version_matches(greaterequal, Req, SelVer, _Repo, _Entry) :- !,
  ( system:compare(>, SelVer, Req) ; system:compare(=, SelVer, Req) ).
blocker_version_matches(Op, Req, _SelVer, Repo, Entry) :-
  query:search(select(version,Op,Req), Repo://Entry).

blocker_slot_matches([], _SelSlotMeta, _Repo, _Entry) :- !.
blocker_slot_matches([slot(S)], SelSlotMeta, _Repo, _Entry) :- !,
  memberchk(slot(S), SelSlotMeta).
blocker_slot_matches([slot(S),subslot(Ss)], SelSlotMeta, _Repo, _Entry) :- !,
  memberchk(slot(S), SelSlotMeta),
  memberchk(subslot(Ss), SelSlotMeta).
blocker_slot_matches([slot(S),equal], SelSlotMeta, _Repo, _Entry) :- !,
  memberchk(slot(S), SelSlotMeta).
blocker_slot_matches([slot(S),subslot(Ss),equal], SelSlotMeta, _Repo, _Entry) :- !,
  memberchk(slot(S), SelSlotMeta),
  memberchk(subslot(Ss), SelSlotMeta).
blocker_slot_matches(SlotReq, _SelSlotMeta, Repo, Entry) :-
  query:search(select(slot,constraint(SlotReq), _), Repo://Entry).


% =============================================================================
%  Blocker helpers
% =============================================================================

%! candidate:grouped_blocker_specs(+Strength, +Phase, +C, +N, +PackageDeps, -Specs)
%
% Collects all blocker specs from PackageDeps matching (C,N) into a sorted list.

grouped_blocker_specs(Strength, Phase, C, N, PackageDeps, Specs) :-
  findall(blocked(Strength, Phase, O, V, SlotReq),
          ( member(package_dependency(Phase, Strength, C, N, O, V, SlotReq, _U), PackageDeps) ),
          Specs0),
  sort(Specs0, Specs).

%! candidate:grouped_blocker_specs_partition(+Strength, +Phase, +C, +N, +PackageDeps, -Enforce, -Assume)
%
% Partitions blocker specs into unconditional (enforceable) and
% USE-conditional (assumed). Unconditional blockers have empty USE
% requirements; conditional blockers are recorded as assumptions.

grouped_blocker_specs_partition(Strength, Phase, C, N, PackageDeps, EnforceSpecs, AssumeSpecs) :-
  findall(blocked(Strength, Phase, O, V, SlotReq),
          ( member(package_dependency(Phase, Strength, C, N, O, V, SlotReq, U), PackageDeps),
            U == []
          ),
          Enforce0),
  sort(Enforce0, EnforceSpecs),
  findall(blocked(Strength, Phase, O, V, SlotReq),
          ( member(package_dependency(Phase, Strength, C, N, O, V, SlotReq, U), PackageDeps),
            U \== []
          ),
          Assume0),
  sort(Assume0, AssumeSpecs),
  !.

%! candidate:blocker_assumption_ctx(+Ctx0, -AssCtx)
%
% Builds a minimal assumption context for blocker assumptions, preserving
% the self/1 reference from the original context if present.

blocker_assumption_ctx(Ctx0, AssCtx) :-
  ( is_list(Ctx0),
    memberchk(self(Repo://Entry), Ctx0) ->
      AssCtx = [suggestion(loosen_blocker), assumption_reason(blocker_conflict), self(Repo://Entry)]
  ; AssCtx = [suggestion(loosen_blocker), assumption_reason(blocker_conflict)]
  ).

%! candidate:blocker_source_constraints(+C, +N, +Specs, +Context, -Constraints)
%
% Generates `blocked_cn_source` constraints that record which parent
% entry introduced the blocker. Used for reprove source tracking.

blocker_source_constraints(_C, _N, Specs, _Context, []) :-
  Specs == [],
  !.
blocker_source_constraints(C, N, Specs, Context, [constraint(blocked_cn_source(C,N):{ordset(Sources)})]) :-
  is_list(Context),
  memberchk(self(SelfRepo://SelfEntry), Context),
  findall(source(SelfRepo,SelfEntry,Phase,O,V,SlotReq),
          member(blocked(_Strength,Phase,O,V,SlotReq), Specs),
          Sources0),
  sort(Sources0, Sources),
  Sources \== [],
  !.
blocker_source_constraints(_C, _N, _Specs, _Context, []) :-
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

order_deps_for_proof(_Action, Deps, Ordered) :-
  maplist(dep_priority_kv, Deps, KVs),
  keysort(KVs, Sorted),
  pairs_values(Sorted, Ordered),
  !.

dep_priority_kv(Dep, K-Dep) :-
  dep_priority(Dep, K),
  !.

%! candidate:dep_priority(+DepLiteral, -Key)
%
% Computes a priority key for a dependency literal. Lower keys are
% proved first. Key is `key(BaseK, TightUpper, C, N)` where BaseK
% accounts for upper-bound tightness, slot specificity, and special
% categories.

dep_priority(grouped_package_dependency(_T,C,N,PackageDeps):Action?{_Context}, K) :-
  !,
  ( merge_slot_restriction(Action, C, N, PackageDeps, SlotReq) ->
      ( dep_tightest_upper_bound(C, N, PackageDeps, TightUpper) ->
          UpperK0 = 1
      ; C == 'dev-ml',
        dep_has_equal_wildcard_constraint(C, N, PackageDeps) ->
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
dep_priority(_Other, key(90, none, zz, zz)) :- !.

slotreq_priority([slot(_),subslot(_)|_], 0) :- !.
slotreq_priority([slot(_)|_],             5) :- !.
slotreq_priority([any_same_slot],        10) :- !.
slotreq_priority([any_different_slot],   15) :- !.
slotreq_priority([],                     20) :- !.
slotreq_priority(_Other,                 30) :- !.

dep_tightest_upper_bound(C, N, PackageDeps, Tightest) :-
  member(package_dependency(_, no, C, N, Op0, _, _, _), PackageDeps),
  ( Op0 == smaller ; Op0 == smallerorequal ),
  !,
  findall(Vn,
          ( member(package_dependency(_Phase, no, C, N, Op, V0, _S, _U), PackageDeps),
            ( Op == smaller ; Op == smallerorequal ),
            coerce_version_term(V0, Vn)
          ),
          [First|Rest]),
  foldl(min_version_bound_, Rest, First, Tightest).

min_version_bound_(V, Best0, Best) :-
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

cn_domain_constraints(Action, C, N, PackageDeps, Context, DomainCons, DomainReasonTags) :-
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

domain_constraints_for_any_different_slot([any_different_slot], _DomainCons0, []) :-
  !.
domain_constraints_for_any_different_slot(_SlotReq, DomainCons, DomainCons) :-
  !.

add_domain_reason_context(_C, _N, [], Ctx, Ctx) :-
  !.
add_domain_reason_context(C, N, ReasonTags, Ctx0, Ctx) :-
  feature_unification:unify([domain_reason(cn_domain(C,N,ReasonTags))], Ctx0, Ctx),
  !.

dep_has_upper_version_bound(C, N, PackageDeps) :-
  member(package_dependency(_Phase, no, C, N, Op, _V, _S, _U), PackageDeps),
  ( Op == smaller
  ; Op == smallerorequal
  ),
  !.

dep_has_version_constraint(C, N, PackageDeps) :-
  member(package_dependency(_Phase, no, C, N, Op, _V, _S, _U), PackageDeps),
  nonvar(Op),
  Op \== none,
  !.

dep_has_explicit_slot_constraint(C, N, PackageDeps) :-
  member(package_dependency(_Phase, no, C, N, _Op, _V, SlotReq, _U), PackageDeps),
  slot_req_explicit_slot_key(SlotReq, _S),
  !.

dep_has_equal_wildcard_constraint(C, N, PackageDeps) :-
  member(package_dependency(_Phase, no, C, N, equal, V0, _S, _U), PackageDeps),
  version_term_has_wildcard_(V0),
  !.

version_term_has_wildcard_(V0) :-
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

prioritize_deps(Deps, SortedDeps) :-
  prioritize_deps(Deps, [], SortedDeps).

prioritize_deps(Deps, Context, SortedDeps) :-
  predsort(candidate:compare_dep_rank(Context), Deps, SortedDeps).

prioritize_deps_keep_all(Deps, Context, SortedDeps) :-
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
  findall(Dep, member(_-_-_-_-_-Dep, RankedSorted), SortedDeps),
  !.

dep_snapshot_selected(package_dependency(_Phase,_Strength,C,N,_O,_V,_S,_U)) :-
  snapshot_selected_cn_candidates(C, N, _),
  !.
dep_snapshot_selected(_) :- fail.

dep_overlap_group_count(Context, package_dependency(_,_,C,N,_,_,_,_), Count) :-
  memberchk(self(Repo://Ebuild), Context),
  !,
  aggregate_all(count, (
    member(DepKey, [rdepend, depend, bdepend, pdepend, cdepend, idepend]),
    cache:entry_metadata(Repo, Ebuild, DepKey, DepEntry),
    dep_entry_active_any_of_with_cn(DepEntry, Repo://Ebuild, C, N)
  ), Count).
dep_overlap_group_count(_, _, 0).

dep_entry_active_any_of_with_cn(any_of_group(Deps), _, C, N) :-
  member(package_dependency(_, _, C, N, _, _, _, _), Deps), !.
dep_entry_active_any_of_with_cn(use_conditional_group(Pol, Use, RepoEntry, Deps), _, C, N) :-
  rdepend_self_use_conditional_active(Pol, Use, RepoEntry),
  member(D, Deps),
  dep_entry_active_any_of_with_cn(D, RepoEntry, C, N), !.
dep_entry_active_any_of_with_cn(all_of_group(Deps), RepoEntry, C, N) :-
  member(D, Deps),
  dep_entry_active_any_of_with_cn(D, RepoEntry, C, N), !.

compare_dep_rank(Context, Delta, A, B) :-
  dep_rank(Context, A, Ra),
  dep_rank(Context, B, Rb),
  compare(C, Rb, Ra),
  ( C == (<) -> Delta = (<)
  ; C == (>) -> Delta = (>)
  ; Delta = (=)
  ).

dep_rank(Context, Dep, Rank) :-
  Dep \= package_dependency(_,_,_,_,_,_,_,_),
  ( is_preferred_dep(Context, Dep) -> Pref = 1 ; Pref = 0 ),
  dep_intrinsic_rank(Dep, Base),
  Rank is Pref*1000000000 + Base,
  !.

dep_rank(Context, package_dependency(Phase,Strength,C,N,O,V,S,U), Rank) :-
  ( self_cn(Context, C, N) -> Base0 = -100000000 ; Base0 = 0 ),
  installed_version_mismatch_penalty(package_dependency(Phase,Strength,C,N,O,V,S,U), BaseInst),
  ( is_preferred_dep(Context, package_dependency(Phase,Strength,C,N,O,V,S,U)) -> Pref = 1 ; Pref = 0 ),
  dep_intrinsic_rank(package_dependency(Phase,Strength,C,N,O,V,S,U), Base1),
  Rank is Pref*1000000000 + Base0 + BaseInst + Base1,
  !.

self_cn(Context, C, N) :-
  memberchk(self(Repo://Id), Context),
  query:search([category(C),name(N)], Repo://Id),
  !.

dep_intrinsic_rank(required(Use), Rank) :-
  use_rank(Use, Rank),
  !.
dep_intrinsic_rank(required(minus(Use)), Rank) :-
  use_rank(Use, Rank),
  !.
dep_intrinsic_rank(package_dependency(_Phase,_Strength,_C,N,_O,_V,_S,_U), Rank) :-
  ( atom_concat(_, '-bootstrap', N) -> Rank = 50000
  ; Rank = 0
  ),
  !.
dep_intrinsic_rank(_, 0).

use_rank(Use, Rank) :-
  atom(Use),
  ( llvm_slot_rank(Use, Rank)
  ; lua_single_target_rank(Use, Rank)
  ),
  !.
use_rank(_, 0).

llvm_slot_rank(Use, Rank) :-
  atom_concat('llvm_slot_', Suffix, Use),
  catch(atom_number(Suffix, N), _, fail),
  Rank is 100000 + N.

lua_single_target_rank(Use, Rank) :-
  atom_concat('lua_single_target_lua5-', Suffix, Use),
  catch(atom_number(Suffix, N), _, fail),
  Rank is 90000 + N.

is_preferred_dep(_Context, use_conditional_group(positive, Use, RepoEntry, _Deps)) :-
  \+ Use =.. [minus,_],
  ( RepoEntry = _Repo://_Id ; RepoEntry = _Repo//_Id ),
  use:effective_use_for_entry(RepoEntry, Use, positive),
  !.
is_preferred_dep(_Context, use_conditional_group(negative, Use, RepoEntry, _Deps)) :-
  \+ Use =.. [minus,_],
  ( RepoEntry = _Repo://_Id ; RepoEntry = _Repo//_Id ),
  use:effective_use_for_entry(RepoEntry, Use, negative),
  !.

is_preferred_dep(Context, required(Use)) :-
  Use \= minus(_),
  ( preference:use(Use)
  ; use:effective_use_in_context(Context, Use, positive)
  ),
  !.
is_preferred_dep(Context, required(minus(Use))) :-
  ( preference:use(minus(Use))
  ; use:effective_use_in_context(Context, Use, negative)
  ),
  !.

is_preferred_dep(Context, all_of_group(Deps)) :-
  Deps \= [],
  forall(member(D, Deps), group_member_preferred(Context, D)),
  !.

is_preferred_dep(_Context, package_dependency(_Phase,_Strength,C,N,O,V,_S,_U)) :-
  query:search([name(N),category(C),installed(true)], pkg://Installed),
  ( O == none ; query_search_version_select(O, V, pkg://Installed) ),
  !.


% =============================================================================
%  any_of_group preference helpers (installed satisfaction)
% =============================================================================

%! candidate:group_member_preferred(+Context, +PackageDep)
%
% True if a package_dependency member is "preferred" -- i.e. already
% installed or previously selected in the proof. Used by any_of_group
% rules to try installed alternatives first.

group_member_preferred(Context, package_dependency(Phase,Strength,C,N,O,V,S,U)) :-
  installed_pkg_satisfies_dep(Context, package_dependency(Phase,Strength,C,N,O,V,S,U)),
  !.
group_member_preferred(Context, use_conditional_group(positive, Use, RepoEntry, Deps)) :-
  is_preferred_dep(Context, use_conditional_group(positive, Use, RepoEntry, Deps)),
  !.
group_member_preferred(Context, use_conditional_group(negative, Use, RepoEntry, Deps)) :-
  is_preferred_dep(Context, use_conditional_group(negative, Use, RepoEntry, Deps)),
  !.
group_member_preferred(Context, all_of_group(Deps)) :-
  Deps \= [],
  forall(member(D, Deps), group_member_preferred(Context, D)),
  !.
group_member_preferred(_Context, _Other) :-
  fail.

installed_pkg_satisfies_dep(ParentContext,
                             package_dependency(_Phase,_Strength,C,N,O,V,_S,UseReqs)) :-
  query:search([name(N),category(C),installed(true)], pkg://InstalledId),
  ( O == none
  ; query_search_version_select(O, V, pkg://InstalledId)
  ),
  use:installed_pkg_satisfies_use_reqs(ParentContext, pkg://InstalledId, UseReqs),
  !.

installed_version_mismatch_penalty(package_dependency(_Phase,_Strength,C,N,O,V,_S,_U), Penalty) :-
  O \== none,
  query:search([name(N),category(C),installed(true)], pkg://_),
  \+ ( query:search([name(N),category(C),installed(true)], pkg://InstalledId),
       query_search_version_select(O, V, pkg://InstalledId)
     ),
  Penalty is -50000000,
  !.
installed_version_mismatch_penalty(_Dep, 0).


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

candidate_reverse_deps_compatible_with_parent(Context, FoundRepo://Candidate) :-
  ( memberchk(self(SelfRepo://SelfEntry), Context),
    cache:ordered_entry(SelfRepo, SelfEntry, ParC, ParN, _)
  ->
    \+ candidate_has_incompatible_reverse_dep(FoundRepo, Candidate, ParC, ParN, SelfRepo://SelfEntry)
  ; true
  ).

candidate_has_incompatible_reverse_dep(FoundRepo, Candidate, ParC, ParN, SelfRepo://SelfEntry) :-
  cache:entry_metadata(FoundRepo, Candidate, rdepend, Dep),
  dep_contains_pkg_dep_on(Dep, ParC, ParN, Op, V, SlotReq),
  Op \== none,
  reverse_dep_slot_matches_parent(SlotReq, SelfRepo://SelfEntry),
  \+ query:search(select(version, Op, V), SelfRepo://SelfEntry).

reverse_dep_slot_matches_parent([], _) :- !.
reverse_dep_slot_matches_parent([slot(DepSlot)|_], SelfRepo://SelfEntry) :-
  !,
  query:search(slot(ParSlot), SelfRepo://SelfEntry),
  canon_slot(ParSlot, ParSlotC),
  canon_slot(DepSlot, DepSlotC),
  ParSlotC == DepSlotC.
reverse_dep_slot_matches_parent([any_same_slot|_], _) :- !.
reverse_dep_slot_matches_parent([any_different_slot|_], _) :- !, fail.
reverse_dep_slot_matches_parent(_, _).

dep_contains_pkg_dep_on(package_dependency(_, no, C, N, Op, V, SlotReq, _), C, N, Op, V, SlotReq).
dep_contains_pkg_dep_on(use_conditional_group(_, _, _, SubDeps), C, N, Op, V, SlotReq) :-
  member(D, SubDeps),
  dep_contains_pkg_dep_on(D, C, N, Op, V, SlotReq).
dep_contains_pkg_dep_on(all_of_group(SubDeps), C, N, Op, V, SlotReq) :-
  member(D, SubDeps),
  dep_contains_pkg_dep_on(D, C, N, Op, V, SlotReq).


% =============================================================================
%  Grouped dep slot helpers
% =============================================================================

%! candidate:all_deps_have_explicit_slot(+PackageDeps)
%
% True if every dep in PackageDeps carries a non-empty slot requirement.
% Used to decide whether the grouped dep can be resolved slot-by-slot.

all_deps_have_explicit_slot([]) :- !, fail.
all_deps_have_explicit_slot(Deps) :-
  forall(member(package_dependency(_P,_Strength,_C,_N,_O,_V,SlotReq,_U), Deps),
         slot_req_explicit_slot_key(SlotReq, _S)),
  !.

multiple_distinct_slots(Deps) :-
  member(package_dependency(_,_,_,_,_,_,SR1,_), Deps),
  slot_req_explicit_slot_key(SR1, S1), !,
  member(package_dependency(_,_,_,_,_,_,SR2,_), Deps),
  slot_req_explicit_slot_key(SR2, S2),
  S2 \== S1, !.

slot_req_explicit_slot_key([slot(S0)], S) :-
  canon_slot(S0, S),
  !.
slot_req_explicit_slot_key([slot(S0),equal], S) :-
  canon_slot(S0, S),
  !.
slot_req_explicit_slot_key([slot(S0),subslot(_Ss)], S) :-
  canon_slot(S0, S),
  !.
slot_req_explicit_slot_key([slot(S0),subslot(_Ss),equal], S) :-
  canon_slot(S0, S),
  !.

all_deps_exactish_versioned([]) :- !, fail.
all_deps_exactish_versioned(Deps) :-
  forall(member(package_dependency(_P,_Strength,_C,_N,Op,Ver,SlotReq,_U), Deps),
         ( SlotReq == [],
           ( Op == tilde ; Op == equal ),
           nonvar(Ver)
         )),
  !.

multiple_distinct_exactish_versions(Deps) :-
  findall(Full,
          ( member(package_dependency(_P,_Strength,_C,_N,_Op,Ver,_SlotReq,_U), Deps),
            ( Ver = version(_,_,_,_,_,_,Full) -> true ; Full = Ver )
          ),
          Vs0),
  sort(Vs0, Vs),
  Vs = [_|Rest],
  Rest \== [],
  !.

should_split_grouped_dep(PackageDeps) :-
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

augment_package_deps_with_self_rdepend(install, C, N, Context, PackageDeps0, PackageDeps) :-
  ( memberchk(self(RepoEntry0), Context) ->
      ( RepoEntry0 = Repo://SelfId -> true
      ; RepoEntry0 = Repo//SelfId  -> true
      )
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
augment_package_deps_with_self_rdepend(_OtherAction, _C, _N, _Context, PackageDeps, PackageDeps) :-
  !.

dep_has_version_constraints(C, N, PackageDeps) :-
  member(package_dependency(_Phase, no, C, N, Op, _V, _S, _U), PackageDeps),
  Op \== none,
  !.

self_rdepend_extra_slot_compatible([], _ExtraDep) :-
  !.
self_rdepend_extra_slot_compatible([slot(S0)|_],
                                   package_dependency(_P,_Strength,_C,_N,_Op,_V,SlotReq,_U)) :-
  !,
  canon_slot(S0, S),
  ( SlotReq == []
  ; SlotReq = [slot(S1)|_],
    canon_slot(S1, S)
  ).
self_rdepend_extra_slot_compatible(_BaseSlotReq, _ExtraDep) :-
  !.

self_rdepend_vbounds_for_cn(Repo, SelfId, C, N, Extra) :-
  ( memo:rdepend_vbounds_cache_(Repo, SelfId, C, N, Extra0) ->
    Extra = Extra0
  ;
    build_self_rdepend_vbounds_for_cn(Repo, SelfId, C, N, Extra1),
    assertz(memo:rdepend_vbounds_cache_(Repo, SelfId, C, N, Extra1)),
    Extra = Extra1
  ),
  !.

build_self_rdepend_vbounds_for_cn(Repo, SelfId, C, N, Extra) :-
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

rdepend_collect_vbounds_for_cn(package_dependency(_P, no, C, N, Op, V, SlotReq, _UseDeps),
                                C, N, _SelfRepoEntry,
                                [package_dependency(run, no, C, N, Op, V, SlotReq, [])]) :-
  Op \== none,
  !.
rdepend_collect_vbounds_for_cn(package_dependency(_P, _Strength, _C, _N, _Op, _V, _SlotReq, _UseDeps),
                                _C0, _N0, _SelfRepoEntry, []) :-
  !.
rdepend_collect_vbounds_for_cn(use_conditional_group(Pol, Use, _Self, Deps0), C, N, SelfRepoEntry, Deps) :-
  !,
  ( rdepend_self_use_conditional_active(Pol, Use, SelfRepoEntry) ->
      rdepend_collect_vbounds_for_cn_list(Deps0, C, N, SelfRepoEntry, Deps)
  ; Deps = []
  ).
rdepend_collect_vbounds_for_cn(any_of_group(Deps0), C, N, SelfRepoEntry, Deps) :-
  !,
  rdepend_collect_vbounds_for_cn_choice_intersection(Deps0, C, N, SelfRepoEntry, Deps).
rdepend_collect_vbounds_for_cn(all_of_group(Deps0), C, N, SelfRepoEntry, Deps) :-
  !,
  rdepend_collect_vbounds_for_cn_list(Deps0, C, N, SelfRepoEntry, Deps).
rdepend_collect_vbounds_for_cn(exactly_one_of_group(Deps0), C, N, SelfRepoEntry, Deps) :-
  !,
  rdepend_collect_vbounds_for_cn_choice_intersection(Deps0, C, N, SelfRepoEntry, Deps).
rdepend_collect_vbounds_for_cn(at_most_one_of_group(Deps0), C, N, SelfRepoEntry, Deps) :-
  !,
  rdepend_collect_vbounds_for_cn_choice_intersection(Deps0, C, N, SelfRepoEntry, Deps).
rdepend_collect_vbounds_for_cn(_Other, _C, _N, _SelfRepoEntry, []) :-
  !.

rdepend_collect_vbounds_for_cn_list([], _C, _N, _SelfRepoEntry, []) :- !.
rdepend_collect_vbounds_for_cn_list([T|Ts], C, N, SelfRepoEntry, Deps) :-
  rdepend_collect_vbounds_for_cn(T, C, N, SelfRepoEntry, D0),
  rdepend_collect_vbounds_for_cn_list(Ts, C, N, SelfRepoEntry, D1),
  append(D0, D1, Deps),
  !.

rdepend_self_use_conditional_active(positive, Use, SelfRepoEntry) :-
  ( use:effective_use_for_entry(SelfRepoEntry, Use, positive) ->
      true
  ; \+ rdepend_self_entry_has_iuse_flag(SelfRepoEntry, Use),
    preference:use(Use)
  ),
  !.
rdepend_self_use_conditional_active(negative, Use, SelfRepoEntry) :-
  ( use:effective_use_for_entry(SelfRepoEntry, Use, negative) ->
      true
  ; \+ rdepend_self_entry_has_iuse_flag(SelfRepoEntry, Use),
    preference:use(minus(Use))
  ; \+ rdepend_self_entry_has_iuse_flag(SelfRepoEntry, Use),
    \+ preference:use(Use),
    \+ preference:use(minus(Use))
  ),
  !.
rdepend_self_use_conditional_active(_Pol, _Use, _SelfRepoEntry) :-
  fail.

rdepend_self_entry_has_iuse_flag(Repo://Entry, Use) :-
  use:entry_iuse_info(Repo://Entry, iuse_info(IuseSet, _PlusSet)),
  memberchk(Use, IuseSet),
  !.
rdepend_self_entry_has_iuse_flag(_RepoEntry, _Use) :-
  fail.

rdepend_collect_vbounds_for_cn_choice_intersection([], _C, _N, _SelfRepoEntry, []) :-
  !.
rdepend_collect_vbounds_for_cn_choice_intersection([Dep|Deps], C, N, SelfRepoEntry, Common) :-
  rdepend_collect_vbounds_for_cn(Dep, C, N, SelfRepoEntry, First0),
  sort(First0, First),
  rdepend_collect_vbounds_for_cn_choice_intersection_(Deps, C, N, SelfRepoEntry, First, Common),
  !.

rdepend_collect_vbounds_for_cn_choice_intersection_([], _C, _N, _SelfRepoEntry, Acc, Acc) :-
  !.
rdepend_collect_vbounds_for_cn_choice_intersection_([Dep|Deps], C, N, SelfRepoEntry, Acc0, Common) :-
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

license_masked(Repo://Entry) :-
  effective_license(Repo://Entry, Lic),
  \+ preference:license_accepted(Lic),
  !.

%! candidate:effective_license(+RepoEntry, -License)
%
% Enumerates the effective license atoms for an entry, resolving
% USE-conditional license groups against the entry's effective USE.

effective_license(Repo://Entry, License) :-
  cache:entry_metadata(Repo, Entry, license, LicTerm),
  effective_license_term_(LicTerm, Repo://Entry, License).

effective_license_term_(use_conditional_group(Pol, Use, _Self, Deps), RepoEntry, License) :-
  !,
  rdepend_self_use_conditional_active(Pol, Use, RepoEntry),
  member(D, Deps),
  effective_license_term_(D, RepoEntry, License).
effective_license_term_(License, _RepoEntry, License) :-
  atom(License).

dep_license_ok(package_dependency(_, _, C, N, _, _, _, _)) :- !,
  cache:ordered_entry(Repo, Entry, C, N, _),
  \+ preference:masked(Repo://Entry),
  \+ license_masked(Repo://Entry).
dep_license_ok(grouped_package_dependency(_, C, N, _)) :- !,
  cache:ordered_entry(Repo, Entry, C, N, _),
  \+ preference:masked(Repo://Entry),
  \+ license_masked(Repo://Entry).
dep_license_ok(_).


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

accepted_keyword_candidate(Action, C, N, SlotReq0, Ss0, Context, FoundRepo://Candidate) :-
  accepted_keyword_slot_lock_arg(C, N, SlotReq0, Ss0, Context, SlotReq, Ss, LockKey),
  ( preference:keyword_selection_mode(keyword_order) ->
      preference:accept_keywords(K),
      query_keyword_candidate(Action, C, N, K, Context, FoundRepo://Candidate),
      query_search_slot_constraint(SlotReq, FoundRepo://Candidate, Ss)
  ; ( Action \== run,
      memberchk(self(SelfRepo0://SelfEntry0), Context),
      query:search([category(C),name(N)], SelfRepo0://SelfEntry0)
    ->
      findall(FoundRepo0://Candidate0,
              ( preference:accept_keywords(K0),
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
      ( greedy_candidate_package(C, N) ->
          member(FoundRepo://Candidate, CandidatesSorted),
          query_search_slot_constraint(SlotReq, FoundRepo://Candidate, Ss)
      ; member(FoundRepo://Candidate, CandidatesSorted),
        query_search_slot_constraint(SlotReq, FoundRepo://Candidate, Ss)
      )
    )
  ).

% Fallback: when keyword_acceptance is active, accept candidates with any
% keyword that are not masked. This produces a full resolution (download +
% install + run) rather than a "verify" stub.
accepted_keyword_candidate(Action, C, N, SlotReq0, Ss0, Context, FoundRepo://Candidate) :-
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
accepted_keyword_candidate(Action, C, N, SlotReq0, Ss0, Context, FoundRepo://Candidate) :-
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

% Like query_keyword_candidate but accepts any candidate, including those with
% non-accepted keywords or no keywords at all. Used when keyword_acceptance
% fallback is active to let keyword-filtered packages through.
query_keyword_candidate_any(Action, C, N, Context, FoundRepo://Candidate) :-
  ( Action \== run,
    memberchk(self(SelfRepo0://SelfEntry0), Context),
    query:search([category(C),name(N)], SelfRepo0://SelfEntry0)
  ->
    query:search([name(N),category(C)], FoundRepo://Candidate),
    \+ preference:masked(FoundRepo://Candidate),
    \+ candidate:license_masked(FoundRepo://Candidate),
    ( FoundRepo == SelfRepo0,
      Candidate == SelfEntry0
    ->
      \+ preference:flag(emptytree),
      query:search(installed(true), FoundRepo://Candidate)
    ; true
    )
  ; query:search([name(N),category(C)], FoundRepo://Candidate),
    \+ preference:masked(FoundRepo://Candidate),
    \+ candidate:license_masked(FoundRepo://Candidate)
  ).

% Accepts masked candidates with any accepted keyword. Used when the unmask
% fallback is active to let masked packages through for full resolution.
query_keyword_candidate_masked(Action, C, N, Context, FoundRepo://Candidate) :-
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

accepted_keyword_slot_lock_arg(C, N, SlotReq0, Ss0, Context, SlotReq, Ss, LockKey) :-
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

accepted_keyword_slot_lock_key([any_same_slot], Ss, slot(S)) :-
  nonvar(Ss),
  canon_any_same_slot_meta(Ss, [slot(S)|_]),
  !.
accepted_keyword_slot_lock_key(_SlotReq, _Ss, any) :-
  !.

accepted_keyword_slot_lock_filter([any_same_slot], slot(S), [slot(S)]) :-
  !.
accepted_keyword_slot_lock_filter(_SlotReq, _LockKey, _SsFilter) :-
  !.

greedy_candidate_package('dev-lang', ocaml) :- !.
greedy_candidate_package('dev-ml', findlib) :- !.
greedy_candidate_package('dev-ml', ocamlbuild) :- !.

accepted_keyword_candidates_cached(Action, C, N, SlotReq, LockKey, CandidatesSorted) :-
  ( memo:keyword_cache_(Action, C, N, SlotReq, LockKey, CandidatesSorted) ->
    true
  ;
    accepted_keyword_slot_lock_filter(SlotReq, LockKey, SsFilter),
    findall(FoundRepo0://Candidate0,
            ( preference:accept_keywords(K0),
              query_keyword_candidate(Action, C, N, K0, [], FoundRepo0://Candidate0),
              query_search_slot_constraint(SlotReq, FoundRepo0://Candidate0, SsFilter)
            ),
            Candidates0),
    Candidates0 \== [],
    sort(Candidates0, Candidates1),
    predsort(candidate:compare_candidate_version_desc, Candidates1, CandidatesSorted),
    assertz(memo:keyword_cache_(Action, C, N, SlotReq, LockKey, CandidatesSorted))
  ).

query_keyword_candidate(Action, C, N, K, Context, FoundRepo://Candidate) :-
  ( Action \== run,
    memberchk(self(SelfRepo0://SelfEntry0), Context),
    query:search([category(C),name(N)], SelfRepo0://SelfEntry0)
  ->
    query:search([name(N),category(C),keyword(K)], FoundRepo://Candidate),
    \+ preference:masked(FoundRepo://Candidate),
    \+ candidate:license_masked(FoundRepo://Candidate),
    ( FoundRepo == SelfRepo0,
      Candidate == SelfEntry0
    ->
      \+ preference:flag(emptytree),
      query:search(installed(true), FoundRepo://Candidate)
    ; true
    )
  ; query:search([name(N),category(C),keyword(K)], FoundRepo://Candidate),
    \+ preference:masked(FoundRepo://Candidate),
    \+ candidate:license_masked(FoundRepo://Candidate)
  ).

compare_candidate_version_desc(Delta, RepoA://IdA, RepoB://IdB) :-
  cache:ordered_entry(RepoA, IdA, _Ca, _Na, VerA),
  cache:ordered_entry(RepoB, IdB, _Cb, _Nb, VerB),
  ( eapi:version_compare(>, VerA, VerB) -> Delta = (<)
  ; eapi:version_compare(<, VerA, VerB) -> Delta = (>)
  ; Delta = (=)
  ).


%! candidate:candidate_non_accepted_keyword(+RepoEntry, -NonAccKw) is semidet.
%
% Succeeds with the first keyword on RepoEntry that is not in the
% current ACCEPT_KEYWORDS. Used to tag context when keyword_acceptance
% fallback selects a candidate.

candidate_non_accepted_keyword(Repo://Entry, NonAccKw) :-
  findall(K, preference:accept_keywords(K), AcceptedKs0),
  sort(AcceptedKs0, AcceptedKs),
  ( cache:entry_metadata(Repo, Entry, keywords, NonAccKw),
    \+ memberchk(NonAccKw, AcceptedKs)
  ->
    true
  ; \+ cache:entry_metadata(Repo, Entry, keywords, _),
    NonAccKw = '**'
  ),
  !.


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

candidates_prefer_proven_providers(virtual, _N, SlotReq, Candidates, Reordered) :-
  SlotReq \= [slot(_)|_],
  include(candidate_has_proven_provider, Candidates, Preferred),
  Preferred \== [],
  !,
  subtract(Candidates, Preferred, Rest),
  append(Preferred, Rest, Reordered).
candidates_prefer_proven_providers(_C, _N, _SlotReq, Candidates, Candidates).

candidate_has_proven_provider(Repo://Entry) :-
  cache:entry_metadata(Repo, Entry, rdepend, Dep),
  dep_references_selected_cn(Dep),
  !.

dep_references_selected_cn(package_dependency(_Phase,_Str,C,N,_O,_V,Ss,_U)) :-
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
dep_references_selected_cn(any_of_group(Deps)) :-
  member(D, Deps),
  dep_references_selected_cn(D),
  !.
