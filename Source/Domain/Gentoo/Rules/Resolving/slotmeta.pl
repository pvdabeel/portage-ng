/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> SLOTMETA
Slot canonicalization and slot metadata for the portage-ng resolver.

Split out of candidate.pl (issue #64). Contains the slot primitives
(canon_slot/2, entry_slot_default/3, self-dep detection), slot
restriction merging (merge_slot_restriction/5), slot constraint queries
(query_search_slot_constraint/3 with the memoized slot metadata cache),
and the grouped-dep slot helpers (should_split_grouped_dep/1 and
friends).
*/

:- module(slotmeta, []).

% =============================================================================
%  SLOTMETA declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Slot primitives
% -----------------------------------------------------------------------------

%! slotmeta:canon_slot(+S0, -S)
%
% Canonicalises a slot value to an atom. Integers and numbers are
% converted via atom_number/2; atoms pass through unchanged.

slotmeta:canon_slot(S0, S) :-
  eapi:normalize_slot_value_(S0, S).

%! slotmeta:canon_any_same_slot_meta(+Meta0, -Canonical)
%
% Extracts and canonicalises the slot from a slot metadata list.
% Succeeds with `[slot(S)]` if Meta0 contains a slot/1 element.

slotmeta:canon_any_same_slot_meta(Meta0, [slot(S)]) :-
  is_list(Meta0),
  member(slot(S0), Meta0),
  canon_slot(S0, S),
  !.

%! slotmeta:is_self_dep(+C, +N, +Phase, +DepSlotReq, +Context)
%
% True when Context indicates a build/install self-dependency: the
% parent ebuild (self/1) has the same category and name as the dep,
% and the dep's slot requirement (if any) matches the parent's slot.
% Cross-slot deps (e.g. antlr-tool:4 depending on antlr-tool:3.5)
% are regular deps, not bootstrap self-deps.

slotmeta:is_self_dep(C, N, Phase, DepSlotReq, Context) :-
  memberchk(self(SelfRepo://SelfEntry), Context),
  query:search([category(C),name(N)], SelfRepo://SelfEntry),
  Phase \== run,
  \+ preference:flag(emptytree),
  \+ is_cross_slot_dep(SelfRepo, SelfEntry, DepSlotReq).

slotmeta:is_cross_slot_dep(Repo, Entry, DepSlotReq) :-
  is_list(DepSlotReq),
  member(slot(DepSlot), DepSlotReq),
  entry_slot_default(Repo, Entry, SelfSlot),
  DepSlot \== SelfSlot.


%! slotmeta:self_dep_satisfiable(+C, +N, +O, +V, +S, +Context)
%
% True when an installed version of C/N satisfies the version and slot
% constraints. Fails otherwise, causing backtracking to bootstrap
% alternatives.

slotmeta:self_dep_satisfiable(C, N, O, V, S, Context) :-
  preference:accept_keywords(K),
  ( memberchk(slot(C,N,Ss):{_}, Context) -> true ; Ss = _ ),
  query:search([name(N),category(C),keyword(K),installed(true),
                select(version,O,V),select(slot,constraint(S),Ss)],
               _://_).


%! slotmeta:entry_slot_default(+Repo, +Entry, -Slot)
%
% Looks up the slot for an entry, defaulting to '0' if unset.

slotmeta:entry_slot_default(Repo, Entry, Slot) :-
  ( query:search(slot(Slot0), Repo://Entry)
    -> canon_slot(Slot0, Slot)
    ;  Slot = '0'
  ).


% -----------------------------------------------------------------------------
%  Slot restriction merging
% -----------------------------------------------------------------------------

%! slotmeta:merge_slot_restriction(+Action, +C, +N, +PackageDeps, -SlotReq)
%
% Combines slot requirements from all package_dependency/8 terms in
% PackageDeps that match (C,N). Returns `[]` if no slot requirement
% is present, or the merged slot restriction list (e.g. `[slot('3')]`).
% Fails if incompatible slot requirements cannot be merged.

slotmeta:merge_slot_restriction(Action, C, N, PackageDeps, SlotReq) :-
  merge_slot_restriction_(PackageDeps, Action, C, N, none, Slot0),
  ( Slot0 == none -> SlotReq = []
  ; SlotReq = Slot0
  ).

slotmeta:merge_slot_restriction_([], _Action, _C, _N, Acc, Acc) :- !.
slotmeta:merge_slot_restriction_([package_dependency(_Phase,no,C,N,_O,_V,S,_U)|Rest], Action, C, N, Acc0, Acc) :-
  !,
  ( S == []      -> Acc1 = Acc0
  ; Acc0 == none -> Acc1 = S
  ; Acc0 == S    -> Acc1 = Acc0
  ; merge_slot_restriction_pair(Acc0, S, Acc1) -> true
  ; fail
  ),
  merge_slot_restriction_(Rest, Action, C, N, Acc1, Acc).
slotmeta:merge_slot_restriction_([_|Rest], Action, C, N, Acc0, Acc) :-
  merge_slot_restriction_(Rest, Action, C, N, Acc0, Acc).

slotmeta:merge_slot_restriction_pair([slot(S0)], [slot(S1),equal], [slot(S),equal]) :-
  canon_slot(S0, S),
  canon_slot(S1, S),
  !.
slotmeta:merge_slot_restriction_pair([slot(S0),equal], [slot(S1)], [slot(S),equal]) :-
  canon_slot(S0, S),
  canon_slot(S1, S),
  !.
slotmeta:merge_slot_restriction_pair([slot(S0)], [slot(S1),subslot(Ss0)], [slot(S),subslot(Ss)]) :-
  canon_slot(S0, S),
  canon_slot(S1, S),
  canon_slot(Ss0, Ss),
  !.
slotmeta:merge_slot_restriction_pair([slot(S0),subslot(Ss0)], [slot(S1)], [slot(S),subslot(Ss)]) :-
  canon_slot(S0, S),
  canon_slot(S1, S),
  canon_slot(Ss0, Ss),
  !.
slotmeta:merge_slot_restriction_pair([slot(S0)], [slot(S1),subslot(Ss0),equal], [slot(S),subslot(Ss),equal]) :-
  canon_slot(S0, S),
  canon_slot(S1, S),
  canon_slot(Ss0, Ss),
  !.
slotmeta:merge_slot_restriction_pair([slot(S0),subslot(Ss0),equal], [slot(S1)], [slot(S),subslot(Ss),equal]) :-
  canon_slot(S0, S),
  canon_slot(S1, S),
  canon_slot(Ss0, Ss),
  !.
slotmeta:merge_slot_restriction_pair([slot(S0),equal], [slot(S1),subslot(Ss0)], [slot(S),subslot(Ss),equal]) :-
  canon_slot(S0, S),
  canon_slot(S1, S),
  canon_slot(Ss0, Ss),
  !.
slotmeta:merge_slot_restriction_pair([slot(S0),subslot(Ss0)], [slot(S1),equal], [slot(S),subslot(Ss),equal]) :-
  canon_slot(S0, S),
  canon_slot(S1, S),
  canon_slot(Ss0, Ss),
  !.
slotmeta:merge_slot_restriction_pair([slot(S0),equal], [slot(S1),subslot(Ss0),equal], [slot(S),subslot(Ss),equal]) :-
  canon_slot(S0, S),
  canon_slot(S1, S),
  canon_slot(Ss0, Ss),
  !.
slotmeta:merge_slot_restriction_pair([slot(S0),subslot(Ss0),equal], [slot(S1),equal], [slot(S),subslot(Ss),equal]) :-
  canon_slot(S0, S),
  canon_slot(S1, S),
  canon_slot(Ss0, Ss),
  !.


% -----------------------------------------------------------------------------
%  Slot constraint queries
% -----------------------------------------------------------------------------

%! slotmeta:query_search_slot_constraint(+SlotReq, +RepoEntry, -SlotMeta)
%
% Queries the knowledge base for entries matching a slot constraint.
% Bridges between the dependency's slot requirement format and the
% query engine's `select(slot, constraint(...), ...)` interface.
% Handles all slot requirement forms: `[]` (any), `[slot(S)]`,
% `[slot(S),subslot(Ss)]`, `[slot(S),equal]`, `[any_same_slot]`,
% `[any_different_slot]`, and combinations with `equal`.

slotmeta:query_search_slot_constraint(SlotReq, RepoEntry, SlotMeta) :-
  RepoEntry = Repo://Id,
  cached_slot_meta(Repo, Id, AllMeta),
  slot_constraint_match(SlotReq, Repo, Id, AllMeta, SlotMeta).


%! slotmeta:cached_slot_meta(+Repo, +Id, -AllMeta)
%
% Returns the full slot metadata list for Repo/Id, memoised per proof in
% the memo_slot_meta_cache store to avoid redundant findall allocations.

slotmeta:cached_slot_meta(Repo, Id, AllMeta) :-
  ( nbstore:get(memo_slot_meta_cache, Repo-Id, Cached)
  ->
    AllMeta = Cached
  ;
    findall(R, cache:entry_metadata(Repo, Id, slot, R), AllMeta),
    nbstore:put(memo_slot_meta_cache, Repo-Id, AllMeta)
  ).


%! slotmeta:slot_constraint_match(+SlotReq, +Repo, +Id, +AllMeta, -SlotMeta)
%
% Validates a slot constraint against the cached slot metadata and returns
% the appropriate metadata list. Preserves the semantics of the original
% query:search(select(slot,...)) dispatch.

slotmeta:slot_constraint_match(SlotReq, Repo, Id, AllMeta, SlotMeta) :-
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


% -----------------------------------------------------------------------------
%  Grouped dep slot helpers
% -----------------------------------------------------------------------------

%! slotmeta:all_deps_have_explicit_slot(+PackageDeps)
%
% True if every dep in PackageDeps carries a non-empty slot requirement.
% Used to decide whether the grouped dep can be resolved slot-by-slot.

slotmeta:all_deps_have_explicit_slot([]) :- !, fail.
slotmeta:all_deps_have_explicit_slot(Deps) :-
  forall(member(package_dependency(_P,_Strength,_C,_N,_O,_V,SlotReq,_U), Deps),
         slot_req_explicit_slot_key(SlotReq, _S)),
  !.

%! slotmeta:multiple_distinct_slots(+Deps)
%
% True if Deps contains package_dependency terms targeting more than one
% distinct slot.

slotmeta:multiple_distinct_slots(Deps) :-
  member(package_dependency(_,_,_,_,_,_,SR1,_), Deps),
  slot_req_explicit_slot_key(SR1, S1), !,
  member(package_dependency(_,_,_,_,_,_,SR2,_), Deps),
  slot_req_explicit_slot_key(SR2, S2),
  S2 \== S1, !.

%! slotmeta:slot_req_explicit_slot_key(+SlotReq, -Slot)
%
% Extracts and canonicalises the explicit slot from a slot requirement list.

slotmeta:slot_req_explicit_slot_key([slot(S0)], S) :-
  canon_slot(S0, S),
  !.
slotmeta:slot_req_explicit_slot_key([slot(S0),equal], S) :-
  canon_slot(S0, S),
  !.
slotmeta:slot_req_explicit_slot_key([slot(S0),subslot(_Ss)], S) :-
  canon_slot(S0, S),
  !.
slotmeta:slot_req_explicit_slot_key([slot(S0),subslot(_Ss),equal], S) :-
  canon_slot(S0, S),
  !.

%! slotmeta:all_deps_exactish_versioned(+Deps)
%
% True if every dep uses `tilde` or `equal` with a bound version and no slot.

slotmeta:all_deps_exactish_versioned([]) :- !, fail.
slotmeta:all_deps_exactish_versioned(Deps) :-
  forall(member(package_dependency(_P,_Strength,_C,_N,Op,Ver,SlotReq,_U), Deps),
         ( SlotReq == [],
           ( Op == tilde ; Op == equal ),
           nonvar(Ver)
         )),
  !.

slotmeta:multiple_distinct_exactish_versions(Deps) :-
  findall(Full,
          ( member(package_dependency(_P,_Strength,_C,_N,_Op,Ver,_SlotReq,_U), Deps),
            ( Ver = version(_,_,_,_,_,_,Full) -> true ; Full = Ver )
          ),
          Vs0),
  sort(Vs0, Vs),
  Vs = [_|Rest],
  Rest \== [],
  !.

%! slotmeta:should_split_grouped_dep(+PackageDeps)
%
% True if the grouped dependency should be split into per-slot or
% per-version sub-groups for independent resolution.

slotmeta:should_split_grouped_dep(PackageDeps) :-
  ( all_deps_have_explicit_slot(PackageDeps),
    multiple_distinct_slots(PackageDeps)
  ; all_deps_exactish_versioned(PackageDeps),
    multiple_distinct_exactish_versions(PackageDeps)
  ),
  !.
