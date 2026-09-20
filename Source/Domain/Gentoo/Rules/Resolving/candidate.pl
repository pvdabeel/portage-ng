/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> CANDIDATE
Grouped-dependency resolution pipeline for the portage-ng resolver.

Called by the grouped_package_dependency rule/2 clauses in resolving.pl and
by the candidate:resolve/2 protocol clauses in target.pl. Slot
canonicalization lives in slotmeta.pl, CN-consistency and learned-domain
bookkeeping in cnselect.pl, keyword/mask/license acceptance in
acceptance.pl, and dependency ordering/ranking in ranking.pl (all split
out of this module, issue #64).

== Major sections ==

  1. *Blocker matching* -- specs_violate_selected/2,
     blocker_spec_matches_selected/7: strong blocker enforcement against
     already-selected candidates, plus blocker spec/assumption builders.

  2. *Reverse-dep pre-filter* -- candidate_reverse_deps_compatible_with_parent/2:
     avoid selecting a candidate whose RDEPEND would conflict with the parent.

  3. *Self-RDEPEND propagation* -- augment_package_deps_with_self_rdepend/6:
     propagate version bounds from a parent's RDEPEND to tighten child
     candidate selection.

  4. *Candidate eligibility* -- eligible/1, installed/1: the protocol
     predicates inlined at compile time via candidate:goal_expansion/2
     hooks in query.pl (they must stay in this module for the hooks to
     fire).

  5. *Blocker/conflict assumption overrides* -- assume_blockers/0,
     assume_conflicts/0 and their scoped with_* wrappers.

  6. *any_of config-phase validation* -- any_of_config_dep_ok/2 and
     friends: validate choice-group alternatives during the config phase.

  7. *Grouped-dependency resolution pipeline* -- grouped_dep_keep_installed/5,
     grouped_dep_select_and_build/6, grouped_dep_build_assumption/7: the
     phase 2/3/5 entry points of grouped dependency resolution. The
     internal stages share a gd/6 state term (see "Pipeline state term"
     below).

== Pipeline state term ==

The selection pipeline threads a single state term through its stages:

  gd(Action, C, N, PackageDeps, SlotReq, Context)

holding the requested action, category/name, the package_dependency/8
list, the merged slot restriction, and the proof context (`?{Context}`
list) at pipeline entry. Stages destructure the term in their clause
heads, so an argument mismatch fails visibly at the head instead of
hiding in an 8-10 argument positional signature (issue #64).
*/

:- module(candidate, []).

% =============================================================================
%  CANDIDATE declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Blocker matching
% -----------------------------------------------------------------------------

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

% Standard comparison operators use the shared eapi:version_op_match/3 core
% (note arg order: SelVer is the proposed version, Req the required); any other
% operator (tilde/wildcard/...) falls back to the query engine.
candidate:blocker_version_matches(Op, Req, SelVer, _Repo, _Entry) :-
  eapi:version_op(Op),
  !,
  eapi:version_op_match(Op, SelVer, Req).
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


% -----------------------------------------------------------------------------
%  Blocker helpers
% -----------------------------------------------------------------------------

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


% -----------------------------------------------------------------------------
%  Reverse-dep candidate pre-filter (RDEPEND only)
% -----------------------------------------------------------------------------

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
  slotmeta:canon_slot(ParSlot, ParSlotC),
  slotmeta:canon_slot(DepSlot, DepSlotC),
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


% -----------------------------------------------------------------------------
%  Self-RDEPEND version-bound propagation (timeout-safe)
% -----------------------------------------------------------------------------

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
    ( slotmeta:merge_slot_restriction(install, C, N, PackageDeps0, BaseSlotReq) ->
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
  slotmeta:canon_slot(S0, S),
  ( SlotReq == []
  ; SlotReq = [slot(S1)|_],
    slotmeta:canon_slot(S1, S)
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


% -----------------------------------------------------------------------------
%  Candidate eligibility
% -----------------------------------------------------------------------------

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

candidate:eligible(Repo://Entry:annotate?{_}) :-
  !,
  query:search(ebuild(Entry), Repo://Entry).

candidate:eligible(Repo://Entry:_Action?{_}) :-
  ( query:search(masked(true), Repo://Entry) ->
      ( prover:assuming(unmask) -> true
      ; memo:visibility_override_(Repo, Entry)
      )
  ; true
  ),
  ( acceptance:entry_has_accepted_keyword(Repo://Entry) ->
      true
  ; prover:assuming(keyword_acceptance) -> true
  ; memo:visibility_override_(Repo, Entry)
  ).


%! candidate:eligible(use_conditional(+Polarity, +Use, +R://+E):+Action?{+Context})
%
% Succeeds when a USE conditional is active. Checks in order:
%   1. Context-assumed (dependency-induced or required_use)
%   2. `test?` groups of a requested target under --with-test-deps
%      (the `with_test_deps` context marker, target:target_context/2)
%   3. Global profile USE on a non-IUSE flag (e.g. kernel_linux)
%   4. Effective USE for the ebuild (IUSE defaults + profile/env/package.use)

candidate:eligible(use_conditional(positive, Use, _R://_E):_?{Context}) :-
  use:assumed(Context, Use), !.
candidate:eligible(use_conditional(positive, test, _R://_E):_?{Context}) :-
  memberchk(with_test_deps, Context), !.
candidate:eligible(use_conditional(positive, Use, R://E):_?{_}) :-
  Use \= minus(_),
  preference:global_use(Use),
  \+ ( query:search(iuse(Value), R://E),
       eapi:use_flag_name(Value, Use) ), !.
candidate:eligible(use_conditional(positive, Use, R://E):_?{_}) :-
  use:effective_use_for_entry(R://E, Use, positive), !.

candidate:eligible(use_conditional(negative, Use, _R://_E):_?{Context}) :-
  use:assumed_minus(Context, Use), !.
candidate:eligible(use_conditional(negative, Use, R://E):_?{_}) :-
  preference:global_use(minus(Use)),
  \+ ( query:search(iuse(Value), R://E),
       eapi:use_flag_name(Value, Use) ), !.
candidate:eligible(use_conditional(negative, Use, R://E):_?{_}) :-
  \+ preference:global_use(Use),
  \+ preference:global_use(minus(Use)),
  \+ ( query:search(iuse(Value), R://E),
       eapi:use_flag_name(Value, Use) ), !.
candidate:eligible(use_conditional(negative, Use, R://E):_?{_}) :-
  use:effective_use_for_entry(R://E, Use, negative), !.




%! candidate:installed(+RepoEntry) is semidet.
%
% Succeeds when the entry is installed (exists in the active VDB
% repository, see knowledgebase:vdb_repository/1). Goal-expanded at
% compile time to a cache:ordered_entry/5 lookup on that repository.

candidate:installed(Repo://Entry) :-
  query:search(installed(true), Repo://Entry).


% -----------------------------------------------------------------------------
%  Blocker/conflict assumption overrides
% -----------------------------------------------------------------------------

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


% -----------------------------------------------------------------------------
%  any_of config-phase validation
% -----------------------------------------------------------------------------

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
          ( acceptance:accepted_keyword_candidate(Phase, C, N, SlotReq, _Ss, Context, Repo://Id),
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
  slotmeta:merge_slot_restriction(Action, C, N, PackageDeps1, SlotReq),
  knowledgebase:vdb_repository(VdbRepo),
  query:search([name(N),category(C),installed(true)], VdbRepo://InstalledEntry),
  slotmeta:query_search_slot_constraint(SlotReq, VdbRepo://InstalledEntry, _),
  cnselect:installed_entry_satisfies_package_deps(Action, C, N, PackageDeps1, VdbRepo://InstalledEntry),
  % PDEPEND deps are post-merge runtime deps. In the full pipeline they are
  % expanded via the prover hook (heuristic:proof_obligation) with
  % build_with_use dropped, so an installed entry that satisfies the version
  % constraint is kept even when its recorded USE (e.g. an older
  % PYTHON_TARGETS) no longer matches the parent's build_with_use. The
  % fetchonly dep union folds the pdepend-tagged leaves into the regular
  % closure, so mirror that build_with_use-drop here;
  % otherwise a satisfied-but-USE-drifted PDEPEND package would be needlessly
  % rebuilt and fetched, diverging from the equivalent merge plan (and
  % forming a parent<->child fetchonly cycle). Mirrors grouped_dep_use_and_slot/3.
  ( member(package_dependency(pdepend,_,C,N,_,_,_,_), PackageDeps1) ->
      MergedUse = []
  ; findall(U0, member(package_dependency(_P0,no,C,N,_O,_V,_,U0),PackageDeps1), MergedUse0),
    append(MergedUse0, MergedUse)
  ),
  dependency:process_build_with_use(MergedUse, Context, ContextWU, _BWUCons, VdbRepo://InstalledEntry),
  use:context_build_with_use_state(ContextWU, BWUEdge),
  use:accumulate_candidate_bwu(C, N, BWUEdge),
  ( memo:candidate_bwu_(C, N, BWUEff) -> true ; BWUEff = BWUEdge ),
  ( C == 'virtual'
  -> true
  ; use:installed_entry_satisfies_build_with_use(VdbRepo://InstalledEntry,
                                                 [build_with_use:BWUEff])
  ),
  ( preference:flag(newuse) ->
      \+ use:newuse_mismatch(VdbRepo://InstalledEntry)
  ; preference:flag(changeduse) ->
      \+ use:changeduse_mismatch(VdbRepo://InstalledEntry)
  ; true
  ),
  ( preference:flag(changeddeps) ->
      \+ sets:entry_deps_outdated(VdbRepo://InstalledEntry)
  ; true
  ),
  ( preference:flag(changedslot) ->
      \+ sets:entry_slot_changed(VdbRepo://InstalledEntry)
  ; true
  ),
  ( preference:flag(rebuiltbinaries) ->
      \+ sets:entry_has_rebuilt_binary(VdbRepo://InstalledEntry)
  ; true
  ),
  \+ target:rebuild_if_newer_available(VdbRepo://InstalledEntry),
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
%
% The invariant stage parameters (Action, C, N, PackageDeps, the merged
% SlotReq, and the entry Context) are bundled into a gd/6 state term so
% the stage signatures stay short and head-pattern mistakes fail visibly
% (issue #64).

candidate:grouped_dep_select_and_build(Action, C, N, PackageDeps1, Context, Conditions) :-
  slotmeta:merge_slot_restriction(Action, C, N, PackageDeps1, SlotReq),
  GD = gd(Action, C, N, PackageDeps1, SlotReq, Context),
  candidate:grouped_dep_slot_lock(GD, SsLock),
  candidate:grouped_dep_find_candidate(GD, SsLock, FoundRepo://Candidate, CandPreVerified),
  candidate:choicelog_version_wrap(CandPreVerified, GD, FoundRepo://Candidate,
    ( candidate:grouped_dep_avoid_self(GD, FoundRepo://Candidate),
      candidate:grouped_dep_verify_candidate(CandPreVerified, GD, FoundRepo://Candidate),
      candidate:candidate_reverse_deps_compatible_with_parent(Context, FoundRepo://Candidate),
      candidate:grouped_dep_use_and_slot(GD, FoundRepo://Candidate,
                                         Constraints, SlotMeta, NewerContext0),
      candidate:grouped_dep_tag_suggestions(FoundRepo://Candidate, NewerContext0, NewerContext),
      candidate:grouped_dep_determine_action(GD, FoundRepo://Candidate,
                                             SlotMeta, NewerContext, ActionGoal),
      candidate:grouped_dep_assemble_conditions(GD, FoundRepo://Candidate, SlotMeta,
                                                Constraints, ActionGoal, Conditions)
    )).


%! candidate:choicelog_version_wrap(+PreVerified, +GD, +Entry, :Goal) is nondet.
%
% When the choice log is armed and this is a fresh multi-candidate bind,
% wrap Goal with trying/succeeded/failed version events. Otherwise run Goal.

candidate:choicelog_version_wrap(true, _GD, _Entry, Goal) :-
  !,
  call(Goal).
candidate:choicelog_version_wrap(false, GD, Entry, Goal) :-
  ( choicelog:armed,
    candidate:choicelog_version_data(GD, Entry, Data)
  -> choicelog:do_wrap(version, Data, Goal)
  ; call(Goal)
  ).


%! candidate:choicelog_version_data(+GD, +Entry, -Data) is semidet.
%
% Builds version-event Data for alternative multi-candidate binds only
% (Index > 1). The first pick of a multi-candidate set is omitted to
% keep the log focused on backtracks; singleton lists are skipped.

candidate:choicelog_version_data(gd(Action, C, N, PackageDeps, SlotReq, Context),
                                  FoundRepo://Candidate, Data) :-
  candidate:grouped_dep_slot_lock(gd(Action, C, N, PackageDeps, SlotReq, Context), SsLock),
  findall(E,
          acceptance:accepted_keyword_candidate(Action, C, N, SlotReq, SsLock, Context, E),
          Candidates),
  length(Candidates, CandCount),
  CandCount > 1,
  choicelog:nth_member(Candidates, FoundRepo://Candidate, Index),
  Index > 1,
  choicelog:parent_summary(Context, Parent),
  cache:ordered_entry(FoundRepo, Candidate, _, _, CandVer),
  ( SlotReq = [slot(Slot)|_] -> true
  ; SlotReq = [any_same_slot] -> Slot = ':='
  ; Slot = '*'
  ),
  Data = version(Parent, C, N, CandVer, Slot, Index, CandCount).


%! candidate:grouped_dep_slot_lock(+GD, -SsLock) is det.
%
% When the context carries a slot lock for (C,N) via :=, bind SsLock to
% restrict candidate enumeration. Otherwise SsLock is unbound.

candidate:grouped_dep_slot_lock(gd(_Action, C, N, _PackageDeps, [any_same_slot], Context), SsLock) :-
  memberchk(slot(C,N,SsLock0):{_}, Context),
  slotmeta:canon_any_same_slot_meta(SsLock0, SsLock),
  !.
candidate:grouped_dep_slot_lock(gd(_Action, _C, _N, _PackageDeps, _SlotReq, _Context), _SsLock).


%! candidate:grouped_dep_find_candidate(+GD, +SsLock, -Entry, -PreVerified) is nondet.
%
% Enumerates candidate entries respecting slot constraints and CN-consistency.
%
% For explicit slot/subslot deps (cat/pkg:0/0.16, :=0/0.16, etc.) we first
% try to reuse an *already-selected* selected_cn(C,N) candidate, but only
% when it is verified compatible with this edge's slot AND version/domain
% constraints (cnselect:selected_cn_candidate_compatible/7). Reuse is
% committed (deterministic) so the prover cannot backtrack into alternative
% fresh candidates that then fail downstream and degrade into spurious
% `unsatisfied_constraints` assumptions — the multi-consumer cascade that
% turned the whole Qt/KDE stack to exit-2 even though the shared provider
% (e.g. dev-qt/qtbase-6.11.1) was already pinned and satisfied every edge
% (portage-ng#91). We must still NOT blindly reuse an *incompatible*
% slot/subslot selection (that degrades into a bogus "non-existent" domain
% assumption); the compatibility check guards against this, and any edge
% without a compatible pin falls through to fresh enumeration with full
% downstream verification (PreVerified = false).

candidate:grouped_dep_find_candidate(gd(Action, C, N, PackageDeps1, SlotReq, Context), _SsLock,
                                     FoundRepo://Candidate, PreVerified) :-
  SlotReq = [slot(_)|_],
  !,
  ( cnselect:selected_cn_candidate_compatible(Action, C, N, SlotReq, PackageDeps1, Context,
                                              FoundRepo://Candidate)
  -> PreVerified = true
  ;  PreVerified = false,
     acceptance:accepted_keyword_candidate(Action, C, N, SlotReq, _Ss0, Context,
                                           FoundRepo://Candidate)
  ).
candidate:grouped_dep_find_candidate(gd(Action, C, N, PackageDeps1, SlotReq, Context), _SsLock,
                                     FoundRepo://Candidate, true) :-
  cnselect:selected_cn_candidate_compatible(Action, C, N, SlotReq, PackageDeps1, Context, FoundRepo://Candidate),
  !.
candidate:grouped_dep_find_candidate(gd(Action, C, N, PackageDeps1, SlotReq, Context), SsLock,
                                     FoundRepo://Candidate, false) :-
  cnselect:grouped_dep_effective_domain_precomputed(Action, C, N, PackageDeps1, Context, EffDom, RejectDom),
  acceptance:accepted_keyword_candidate(Action, C, N, SlotReq, SsLock, Context, FoundRepo://Candidate),
  ( cnselect:selected_cn_candidate(Action, C, N, Context, FoundRepo://Candidate),
    slotmeta:query_search_slot_constraint(SlotReq, FoundRepo://Candidate, _)
  ->
    cnselect:grouped_dep_candidate_satisfies_constraints_precomputed(
        C, N, PackageDeps1, EffDom, RejectDom, FoundRepo://Candidate)
  ; true
  ).


%! candidate:grouped_dep_avoid_self(+GD, +Entry) is semidet.
%
% Prevents resolving a dependency to the parent package itself unless
% the candidate is already installed.

candidate:grouped_dep_avoid_self(gd(_Action, C, N, _PackageDeps, _SlotReq, Context), FoundRepo://Candidate) :-
  ( ( memberchk(self(_SelfRepo://SelfEntry1), Context)
    ; memberchk(slot(C,N,_SelfSlot):{SelfEntry1}, Context)
    ),
    Candidate == SelfEntry1
  ->
    \+ preference:flag(emptytree),
    query:search(installed(true), FoundRepo://Candidate)
  ; true
  ).


%! candidate:grouped_dep_verify_candidate(+PreVerified, +GD, +Entry) is semidet.
%
% When PreVerified is false, checks that the candidate satisfies all
% version constraints and the effective domain.

candidate:grouped_dep_verify_candidate(true, _GD, _Entry) :- !.
candidate:grouped_dep_verify_candidate(false, gd(Action, C, N, PackageDeps1, _SlotReq, Context),
                                       FoundRepo://Candidate) :-
  cache:ordered_entry(FoundRepo, Candidate, _, _, CandVer),
  forall(member(package_dependency(_P1,no,C,N,O,V,_,_), PackageDeps1),
         preference:version_match(O, CandVer, V)),
  cnselect:grouped_dep_candidate_satisfies_effective_domain(Action, C, N, PackageDeps1, Context, FoundRepo://Candidate).


%! candidate:grouped_dep_use_and_slot(+GD, +Entry, -Constraints, -SlotMeta, -NewContext) is semidet.
%
% Processes USE deps (bracketed constraints, PDEPEND stripping, BWU conflict
% checks) and slot binding for the selected candidate.

candidate:grouped_dep_use_and_slot(gd(_Action, C, N, PackageDeps1, SlotReq, Context),
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
  dependency:process_build_with_use(MergedUse, ContextDep, NewContext0, Constraints, FoundRepo://Candidate),
  % Before REQUIRED_USE gets a say: remember which value this edge's
  % `[F=]` / `[!F=]` directives projected, so a stabilization that
  % overturns one can make the consumer follow instead (portage-ng#121).
  use:record_eq_edge_origins(C, N, ContextDep, MergedUse),
  candidate:grouped_dep_stabilize_bwu(FoundRepo://Candidate, NewContext0, NewContext1),
  candidate:grouped_dep_apply_equality_pins(FoundRepo://Candidate, NewContext1, NewContext),
  use:check_bwu_ed_conflict_pv(C, N, ContextDep, MergedUse, NewContext),
  use:maybe_force_shared_dep_use(C, N, FoundRepo://Candidate),
  use:unify_memo_bwu_into_context(C, N, NewContext, NewContextMemo),
  slotmeta:query_search_slot_constraint(SlotReq, FoundRepo://Candidate, SlotMeta),
  dependency:process_slot(SlotReq, SlotMeta, C, N, FoundRepo://Candidate, NewContextMemo, NewerContext0).


%! candidate:grouped_dep_apply_equality_pins(+RepoEntry, +CtxIn, -CtxOut) is det.
%
% Back-propagate USE-equal pins (portage-ng#87/#88): when this dependency
% candidate has its own `provider[F=]` / `provider[!F=]` edges and the
% provider is already pinned in the cross-dep BWU memo, adopt the matching
% flag value so the candidate follows the provider's resolved USE (e.g.
% cairo pinned [X] -> dev-cpp/cairomm builds with X to honour cairo[X=]).
% A no-op when nothing is pinned or the pin clashes with the candidate's
% existing build_with_use (left for the conflict machinery to report).

candidate:grouped_dep_apply_equality_pins(Repo://Entry, CtxIn, CtxOut) :-
  use:context_build_with_use_state(CtxIn, BWU0),
  ranking:apply_equality_pins(Repo://Entry, BWU0, BWU1),
  ( BWU1 == BWU0
  -> CtxOut = CtxIn
  ; ( select(build_with_use:_, CtxIn, Ctx1) -> true ; Ctx1 = CtxIn ),
    feature_unification:unify([build_with_use:BWU1], Ctx1, CtxOut)
  ).


%! candidate:entry_has_choice_required_use(+Repo, +Entry) is semidet.
%
% True when the ebuild has REQUIRED_USE choice groups (||, ^^, etc.)
% that grouped_dep stabilization may need to resolve from a partial BWU.
% Cheap metadata scan only; avoids calling verify/stabilize on every
% foo[bar] edge (PR #16 regression).

candidate:entry_has_choice_required_use(Repo, Entry) :-
  cache:entry_metadata(Repo, Entry, required_use, Term),
  candidate:required_use_term_has_choice(Term).


%! candidate:required_use_term_has_choice(+Term) is semidet.

candidate:required_use_term_has_choice(any_of_group(_)).
candidate:required_use_term_has_choice(exactly_one_of_group(_)).
candidate:required_use_term_has_choice(at_most_one_of_group(_)).
candidate:required_use_term_has_choice(use_conditional_group(_, _, _, SubDeps)) :-
  member(Sub, SubDeps),
  candidate:required_use_term_has_choice(Sub).


%! candidate:grouped_dep_stabilize_bwu(+RepoEntry, +CtxIn, -CtxOut) is semidet.
%
% Bug B (clutter[introspection]): bracket USE can thread a partial BWU
% before || ( aqua wayland X ) picks a global flag. Only packages with
% choice-shaped REQUIRED_USE need an extra stabilize here; target.pl
% already stabilizes the root :run/:install candidate.
%
% Empty-BWU case (portage-ng#87/#88): a dependency pulled with no
% bracketed USE directives still needs REQUIRED_USE choice resolution
% when its own `|| ( ... )` / `^^ ( ... )` has no satisfied member under
% the profile defaults (e.g. headless `-X -wayland -aqua` vs
% gui-libs/gtk `|| ( aqua wayland X )`). Without this, the package's
% preferred backend is never enabled, its conditional `dep[flag?]`
% edges (e.g. cairo[X?]) contribute nothing, and the build is planned
% with the backend off -> cascading unsatisfied_constraints. We gate the
% extra work behind the cheap entry_has_choice_required_use/2 scan to
% preserve the empty-BWU fast path for the (vast) majority of edges.
%
% Post-stabilize verification (portage-ng#109/#111): never unify a BWU
% that still violates REQUIRED_USE or profile use.mask/force. Fail the
% edge so selection falls through to a domain assumption (emerge's
% use_dep_unsat class) instead of planning a doomed build.

candidate:grouped_dep_stabilize_bwu(Repo://Entry, CtxIn, CtxOut) :-
  use:context_build_with_use_state(CtxIn, BWU0),
  ( BWU0 == use_state([], [])
  -> ( candidate:entry_has_choice_required_use(Repo, Entry),
       use:stabilize_required_use(Repo://Entry, BWU0, BWU2),
       BWU2 \== BWU0
     -> candidate:commit_stabilized_bwu(Repo://Entry, CtxIn, BWU2, CtxOut)
     ; CtxOut = CtxIn
     )
  ; use:use_dep_atom_satisfiable(Repo://Entry, BWU0)
  -> CtxOut = CtxIn
  ; use:build_with_use_resolve_required_use(BWU0, Repo://Entry, BWU1),
    use:stabilize_required_use(Repo://Entry, BWU1, BWU2),
    candidate:commit_stabilized_bwu(Repo://Entry, CtxIn, BWU2, CtxOut)
  ).


%! candidate:commit_stabilized_bwu(+RepoEntry, +CtxIn, +BWU, -CtxOut) is semidet.
%
% Unify BWU into the proof context only when the joint USE-dep check
% passes. On failure, record a requse_violation_ memo (so the assumption
% fallback can tag the domain assumption) and fail the edge.
%
% Both failure paths -- the atom is unsatisfiable, or the stabilized BWU
% no longer unifies with the one already in the context -- mean the
% provider did not take the value some directive asked for. When that
% directive was an equality, the consumer can follow instead, so record
% the follow before failing (portage-ng#121); the edge still fails here,
% and the batched reprove at the end of the pass applies the follow,
% exactly like a shared-dep HARD force.

candidate:commit_stabilized_bwu(Repo://Entry, CtxIn, BWU, CtxOut) :-
  ( use:use_dep_atom_satisfiable(Repo://Entry, BWU)
  -> ( feature_unification:unify([build_with_use:BWU], CtxIn, CtxOut)
     -> true
     ;  candidate:follow_equality_overturn(Repo://Entry, BWU),
        fail
     )
  ; use:describe_use_dep_unsat(Repo://Entry, BWU, ViolDesc),
    cache:ordered_entry(Repo, Entry, C, N, _),
    use:maybe_follow_equality_overturns(C, N, Repo://Entry, BWU),
    ( \+ memo:requse_violation_(C, N, _) ->
        assertz(memo:requse_violation_(C, N, ViolDesc))
    ; true
    ),
    fail
  ).


%! candidate:follow_equality_overturn(+RepoEntry, +BWU) is det.
%
% Let consumers follow a provider that settled on BWU instead of on the
% value their `[F=]` / `[!F=]` edge projected (portage-ng#121). Used where
% the provider's (C,N) is not already at hand.

candidate:follow_equality_overturn(Repo://Entry, BWU) :-
  ( cache:ordered_entry(Repo, Entry, C, N, _) ->
      use:maybe_follow_equality_overturns(C, N, Repo://Entry, BWU)
  ; true
  ).


%! candidate:grouped_dep_tag_suggestions(+Entry, +Context0, -Context) is det.
%
% Tags the context with keyword-acceptance, package unmask, license acceptance,
% and USE-change suggestions when applicable.

candidate:grouped_dep_tag_suggestions(FoundRepo://Candidate, Ctx0, Ctx) :-
  ( prover:assuming(keyword_acceptance),
    acceptance:candidate_non_accepted_keyword(FoundRepo://Candidate, NonAccKw)
  ->
    feature_unification:unify([suggestion(accept_keyword, NonAccKw)], Ctx0, Ctx1)
  ; prover:assuming(unmask),
    preference:masked(FoundRepo://Candidate)
  ->
    feature_unification:unify([suggestion(unmask, FoundRepo://Candidate)], Ctx0, Ctx1)
  ; acceptance:license_masked(FoundRepo://Candidate)
  ->
    feature_unification:unify([suggestion(accept_license, FoundRepo://Candidate)], Ctx0, Ctx1)
  ; Ctx1 = Ctx0
  ),
  ( use:context_build_with_use_state(Ctx1, BWUState),
    use:build_with_use_changes(BWUState, FoundRepo://Candidate, UseChanges),
    UseChanges \== []
  ->
    feature_unification:unify([suggestion(use_change, FoundRepo://Candidate, UseChanges)], Ctx1, Ctx)
  ; Ctx = Ctx1
  ).


%! candidate:grouped_dep_determine_action(+GD, +Entry, +SlotMeta, +Context, -ActionGoal) is det.
%
% Determines whether the dep is a fresh install, update, downgrade, or
% rebuild based on the installed VDB state and CLI flags.
%
% Download-only parent actions (fetchonly, download) are special: they
% never merge anything, so the install/update/downgrade distinction is
% meaningless for them. Rewriting a fetchonly dep into :update would
% cascade through the update->run->install rules and leak spurious
% "update"/"install"/"run" entries into the --fetchonly plan. Instead we
% keep the action as a pure download, but still run the installed-state
% detection so the replaces() marker rides along in the context: this
% tells the fetchonly leaf rule to fetch the sources of a same-version
% rebuild (USE/BWU change) rather than prune it as "already installed",
% preserving the full download closure of the equivalent merge plan.

candidate:grouped_dep_determine_action(gd(Action, C, N, _PackageDeps, _SlotReq, _Context),
                                       FoundRepo://Candidate,
                                       SlotMeta, NewerContext, ActionGoal) :-
  ( \+ preference:flag(emptytree),
    cnselect:selected_cn_slot_key_(SlotMeta, SlotChosen),
    knowledgebase:vdb_repository(VdbRepo),
    query:search([name(N),category(C),installed(true)], VdbRepo://InstalledEntry2),
    ( query:search(slot(SlotInstalled0), VdbRepo://InstalledEntry2)
      -> slotmeta:canon_slot(SlotInstalled0, SlotInstalled)
      ;  SlotInstalled = SlotChosen
    ),
    SlotInstalled == SlotChosen,
    !,
    candidate:grouped_dep_update_reason(C, N, FoundRepo://Candidate,
                                        VdbRepo://InstalledEntry2, NewerContext,
                                        DepUpdateAction, UpdateCtx)
  ->
    ( memberchk(Action, [fetchonly, download])
    -> ActionGoal = FoundRepo://Candidate:Action?{UpdateCtx}
    ;  ActionGoal = FoundRepo://Candidate:DepUpdateAction?{UpdateCtx}
    )
  ; ActionGoal = FoundRepo://Candidate:Action?{NewerContext}
  ).


%! candidate:grouped_dep_update_reason(+C, +N, +CandEntry, +InstalledEntry, +Context, -UpdateAction, -UpdateCtx) is semidet.
%
% Determines the specific update reason (version change, BWU rebuild,
% --newuse, --changed-use, --changed-deps, --changed-slot,
% --rebuilt-binaries, --rebuild-if-new-*).

candidate:grouped_dep_update_reason(_C, _N, FoundRepo://Candidate,
                                    VdbRepo://InstalledEntry2, NewerContext,
                                    DepUpdateAction, UpdateCtx) :-
  InstalledEntry2 \== Candidate,
  query:search(version(OldVer), VdbRepo://InstalledEntry2),
  query:search(version(CandVer0), FoundRepo://Candidate),
  OldVer \== CandVer0,
  !,
  feature_unification:unify([replaces(VdbRepo://InstalledEntry2)], NewerContext, UpdateCtx),
  ( eapi:version_compare(<, CandVer0, OldVer)
  -> DepUpdateAction = downgrade
  ;  DepUpdateAction = update
  ).
candidate:grouped_dep_update_reason(C, _N, _FoundRepo://_Candidate,
                                    VdbRepo://InstalledEntry2, NewerContext,
                                    update, UpdateCtx) :-
  ( current_predicate(config:avoid_reinstall/1),
    config:avoid_reinstall(true) ->
      fail
  ; C \== 'virtual',
    \+ use:installed_entry_satisfies_build_with_use(VdbRepo://InstalledEntry2, NewerContext)
  ),
  !,
  feature_unification:unify([replaces(VdbRepo://InstalledEntry2),rebuild_reason(build_with_use)], NewerContext, UpdateCtx).
candidate:grouped_dep_update_reason(_C, _N, FoundRepo://Candidate,
                                    VdbRepo://InstalledEntry2, NewerContext,
                                    update, UpdateCtx) :-
  preference:flag(newuse),
  use:newuse_mismatch(VdbRepo://InstalledEntry2, FoundRepo://Candidate),
  !,
  feature_unification:unify([replaces(VdbRepo://InstalledEntry2),rebuild_reason(newuse)], NewerContext, UpdateCtx).
candidate:grouped_dep_update_reason(_C, _N, FoundRepo://Candidate,
                                    VdbRepo://InstalledEntry2, NewerContext,
                                    update, UpdateCtx) :-
  preference:flag(changeduse),
  use:changeduse_mismatch(VdbRepo://InstalledEntry2, FoundRepo://Candidate),
  !,
  feature_unification:unify([replaces(VdbRepo://InstalledEntry2),rebuild_reason(changeduse)], NewerContext, UpdateCtx).
candidate:grouped_dep_update_reason(_C, _N, _FoundRepo://_Candidate,
                                    VdbRepo://InstalledEntry2, NewerContext,
                                    update, UpdateCtx) :-
  preference:flag(changeddeps),
  sets:entry_deps_outdated(VdbRepo://InstalledEntry2),
  !,
  feature_unification:unify([replaces(VdbRepo://InstalledEntry2),rebuild_reason(changeddeps)], NewerContext, UpdateCtx).
candidate:grouped_dep_update_reason(_C, _N, _FoundRepo://_Candidate,
                                    VdbRepo://InstalledEntry2, NewerContext,
                                    update, UpdateCtx) :-
  preference:flag(changedslot),
  sets:entry_slot_changed(VdbRepo://InstalledEntry2),
  !,
  feature_unification:unify([replaces(VdbRepo://InstalledEntry2),rebuild_reason(changedslot)], NewerContext, UpdateCtx).
candidate:grouped_dep_update_reason(_C, _N, _FoundRepo://_Candidate,
                                    VdbRepo://InstalledEntry2, NewerContext,
                                    update, UpdateCtx) :-
  preference:flag(rebuiltbinaries),
  sets:entry_has_rebuilt_binary(VdbRepo://InstalledEntry2),
  !,
  feature_unification:unify([replaces(VdbRepo://InstalledEntry2),rebuild_reason(rebuilt_binary)], NewerContext, UpdateCtx).
candidate:grouped_dep_update_reason(_C, _N, _FoundRepo://_Candidate,
                                    VdbRepo://InstalledEntry2, NewerContext,
                                    update, UpdateCtx) :-
  target:rebuild_if_newer_available(VdbRepo://InstalledEntry2),
  feature_unification:unify([replaces(VdbRepo://InstalledEntry2),rebuild_reason(rebuild)], NewerContext, UpdateCtx).


%! candidate:grouped_dep_assemble_conditions(+GD, +Entry, +SlotMeta, +Constraints, +ActionGoal, -Conditions) is det.
%
% Assembles the final proof conditions list from the selected candidate,
% its constraints, domain constraints, and the action goal.

candidate:grouped_dep_assemble_conditions(gd(Action, C, N, PackageDeps1, SlotReq, Context),
                                          FoundRepo://Candidate, SlotMeta,
                                          Constraints, ActionGoal, Conditions) :-
  ( ActionGoal = _://_:ActSel?{_} -> true
  ; ActionGoal = _://_:ActSel     -> true
  ; ActSel = Action
  ),
  query:search(version(CandVer), FoundRepo://Candidate),
  Selected = constraint(selected_cn(C,N):{ordset([selected(FoundRepo,Candidate,ActSel,CandVer,SlotMeta)])}),
  cnselect:selected_cn_allow_multislot_constraints(C, N, SlotReq, PackageDeps1, AllowMultiSlotCons),
  cnselect:cn_domain_constraints(Action, C, N, PackageDeps1, Context, DomainCons0, _DomainReasonTags),
  cnselect:domain_constraints_for_any_different_slot(SlotReq, DomainCons0, DomainCons),
  append(Constraints, [ActionGoal], ConstraintsTail),
  append(AllowMultiSlotCons, [Selected|ConstraintsTail], Suffix),
  append(DomainCons, Suffix, Conditions).


% -----------------------------------------------------------------------------
%  Phase 4b: Last-resort concretization of visibility-hidden deps (#14)
% -----------------------------------------------------------------------------

%! candidate:grouped_dep_concretize_hidden(+Action, +C, +N, +PackageDeps, +PackageDepsOrig, +Context, -Conditions) is semidet.
%
% Called when regular selection failed. When the diagnosed failure
% reason is purely a visibility filter (masked / keyword_filtered),
% retries the selection with the matching prover:assuming flags scoped
% to the selection call, and records a memo:visibility_override_/2 fact
% for the chosen candidate so its own :install/:run eligibility checks
% pass for the remainder of this proof. The dep is thereby planned as a
% concrete install carrying the unmask / accept-keyword suggestion
% (tagged inside grouped_dep_select_and_build by
% grouped_dep_tag_suggestions), instead of the verify-only phantom that
% let consumers build without their provider (portage-ng#14:
% acct-user/buildbot merged while its keyword-filtered acct-group was
% only "assumed accepted" — useradd failed in preinst).
%
% This deliberately happens in-place at the current relaxation tier: an
% earlier attempt that failed such deps up the pipeline:with_fallback
% ladder instead sent heavy meta-packages (kde-plasma/plasma-meta)
% through multiple full proof attempts and into timeouts. Committed
% choice (once/1): if the chosen candidate's subtree later fails, the
% prover retries resolve/2 and lands on the assumption clause below —
% i.e. worst case equals the old phantom behaviour.

candidate:grouped_dep_concretize_hidden(Action, C, N, PackageDeps1, PackageDepsOrig, Context, Conditions) :-
  explanation:assumption_reason_for_grouped_dep(Action, C, N, PackageDepsOrig, Context, Reason),
  candidate:hidden_reason_flags(Reason, Flags),
  once(( candidate:with_assuming_flags(Flags,
             once(candidate:grouped_dep_select_and_build(Action, C, N, PackageDeps1, Context, Conditions)))
       ; candidate:with_assuming_flags([keyword_acceptance, unmask],
             once(candidate:grouped_dep_select_and_build(Action, C, N, PackageDeps1, Context, Conditions)))
       )),
  candidate:record_visibility_override(C, N, Conditions).


%! candidate:hidden_reason_flags(+Reason, -Flags) is semidet.
%
% Maps a visibility-only failure reason to the prover:assuming flags
% that lift it. Fails for any other reason (version conflicts,
% REQUIRED_USE, missing, unsatisfied_constraints, ...), so
% concretization never fires for failures that relaxing visibility
% cannot fix.

candidate:hidden_reason_flags(keyword_filtered, [keyword_acceptance]).
candidate:hidden_reason_flags(masked,           [unmask]).


%! candidate:with_assuming_flags(+Flags, :Goal) is nondet.
%
% Runs Goal with each prover:assuming flag in Flags active, restoring
% them afterwards (nested prover:assuming/2 scopes).

candidate:with_assuming_flags([], Goal) :-
  call(Goal).
candidate:with_assuming_flags([F|Fs], Goal) :-
  prover:assuming(F, candidate:with_assuming_flags(Fs, Goal)).


%! candidate:record_visibility_override(+C, +N, +Conditions) is det.
%
% Extracts the selected candidate from the assembled conditions
% (selected_cn constraint) and records a visibility override for it, so
% the candidate's own ebuild-level rules pass candidate:eligible/1
% outside the scoped assuming flags. Cleared by memo:clear_caches at
% the start of each proof run.

candidate:record_visibility_override(C, N, Conditions) :-
  ( memberchk(constraint(selected_cn(C,N):{ordset(Sels)}), Conditions),
    memberchk(selected(Repo, Entry, _A, _V, _S), Sels)
  ->
    ( memo:visibility_override_(Repo, Entry) -> true
    ; assertz(memo:visibility_override_(Repo, Entry))
    )
  ; true
  ).


% -----------------------------------------------------------------------------
%  Phase 5: Assumption fallback with diagnostics
% -----------------------------------------------------------------------------

%! candidate:grouped_dep_build_assumption(+Action, +C, +N, +PackageDeps, +PackageDepsOrig, +Context, -Conditions) is det.
%
% Builds an assumption condition when no candidate could satisfy the
% grouped dependency. Tags context with explanation reason and
% actionable suggestions (keyword, unmask, slot conflict, REQUIRED_USE).
%
% Phantom reasons (unsatisfied_constraints / masked / acct-group
% keyword_filtered) and REQUIRED_USE violations (portage-ng#10, #14, #15)
% are NOT failed here. Failing the assumption makes candidate:resolve/2
% fail, which forces pipeline:prove_with_fallback through all five
% relaxation tiers per target — a ~5x proof-cost regression on heavy
% packages (portage-ng#20 fallout). Instead the assumption is emitted and
% tagged (assumption_reason / required_use_violation) so the prover
% completes with a domain assumption; the printer classifies it as a
% domain assumption downstream. The ordering engine's assumed-dep alias
% preference still orders the consumer after any concrete planned action
% for the same package — that aliasing is existence-gated, so a true phantom
% (provider absent from the plan) never inherits a wave, while a
% provider that IS planned keeps its ordering edge (portage-ng#95).
%
% Note that purely visibility-caused failures (masked /
% keyword_filtered) normally never reach this clause anymore: the
% grouped_dep_concretize_hidden/7 resolve clause above plans them as
% concrete installs with an unmask / accept-keyword suggestion
% (portage-ng#14). This assumption path remains their fallback when
% even the visibility-relaxed selection fails.

candidate:grouped_dep_build_assumption(Action, C, N, PackageDeps1, PackageDepsOrig, Context, Conditions) :-
  explanation:assumption_reason_for_grouped_dep(Action, C, N, PackageDepsOrig, Context, Reason),
  version_domain:domain_reason_terms(Action, C, N, PackageDeps1, Context, DomainReasonTags),
  cnselect:add_domain_reason_context(C, N, DomainReasonTags, Context, Ctx2),
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
  Conditions = [assumed(grouped_package_dependency(C,N,PackageDeps1):Action?{Ctx6})],
  Lit = grouped_package_dependency(C, N, PackageDeps1):Action,
  choicelog:clog_emit(assumption, recorded, assumption(Reason, Lit)).


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
        acceptance:candidate_best_keyword_suggestion(AKs, CandKws, SuggestedKw)
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
