/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> VARIANT
Multi-variant pretend support. Detects pivot points (USE flags and
branch choices) in a completed proof and generates variant specifications
that can be re-proved in parallel to show alternative plans.
*/

:- module(variant, []).

% =============================================================================
%  VARIANT declarations
% =============================================================================

:- thread_local variant:use_override/2.
:- thread_local variant:branch_prefer/1.


% -----------------------------------------------------------------------------
%  Thread-local USE override check
% -----------------------------------------------------------------------------

%! variant:use_overridden(+Use, -State) is semidet.
%
% Succeeds when the current thread has a USE flag override active.
% State is unified with positive or negative.

variant:use_overridden(Use, State) :-
  variant:use_override(Use, State).


% -----------------------------------------------------------------------------
%  Pivot detection: USE flags
% -----------------------------------------------------------------------------

%! variant:detect_use_pivots(+ProofAVL, +Targets, +MaxPivots, -Pivots) is det.
%
% Scans the proof for target entries and identifies USE flags that gate
% package_dependency terms in the ebuild metadata. Each pivot represents
% a USE flag whose toggling changes the dependency tree.

variant:detect_use_pivots(_ProofAVL, Goals, MaxPivots, Pivots) :-
  findall(use_pivot(Repo://Entry, Flag, CurrentState),
    ( member(Goal, Goals),
      variant:goal_to_entry(Goal, Repo://Entry),
      variant:impactful_use_flag(Repo://Entry, Flag, CurrentState)
    ),
    AllPivots0),
  sort(AllPivots0, AllPivots),
  length(AllPivots, Len),
  ( Len > MaxPivots
  -> length(Pivots, MaxPivots),
     append(Pivots, _, AllPivots)
  ;  Pivots = AllPivots
  ).


%! variant:goal_to_entry(+Goal, -RepoEntry) is semidet.
%
% Extracts a portage tree Repo://Entry from a proposal goal term.
% VDB entries (pkg://) are mapped to their portage tree counterpart
% since VDB entries lack dependency metadata for pivot detection.

variant:goal_to_entry(Repo://Entry:_Action?{_Ctx}, TreeEntry) :-
  !,
  variant:ensure_tree_entry(Repo://Entry, TreeEntry).
variant:goal_to_entry(target(_Q, Arg):_Action?{_Ctx}, TreeEntry) :-
  atom_codes(Arg, Codes),
  phrase(eapi:qualified_target(Q), Codes),
  once(kb:query(Q, Repo://Entry)),
  variant:ensure_tree_entry(Repo://Entry, TreeEntry).


%! variant:ensure_tree_entry(+RepoEntry, -TreeEntry) is semidet.
%
% If the entry is from VDB (pkg://), finds the corresponding portage tree
% entry with the same category, name, and version. Otherwise passes through.

variant:ensure_tree_entry(pkg://Entry, portage://TreeId) :-
  !,
  cache:ordered_entry(pkg, Entry, C, N, V),
  ( cache:ordered_entry(portage, TreeId, C, N, V)
  -> true
  ;  cache:ordered_entry(portage, TreeId, C, N, _)
  ).
variant:ensure_tree_entry(Entry, Entry).


%! variant:impactful_use_flag(+RepoEntry, -Flag, -CurrentState) is nondet.
%
% A USE flag is impactful if it gates at least one use_conditional_group
% in the ebuild's dependency metadata that contains a package_dependency.

variant:impactful_use_flag(Repo://Entry, Flag, CurrentState) :-
  query:search(iuse(RawIuse), Repo://Entry),
  eapi:strip_use_default(RawIuse, Flag),
  \+ variant:is_implicit_use(Flag),
  variant:flag_gates_dep(Repo, Entry, Flag),
  use:effective_use_for_entry(Repo://Entry, Flag, CurrentState).


%! variant:is_implicit_use(+Flag) is semidet.
%
% Filters out implicit/arch USE flags that are not meaningful to toggle.

variant:is_implicit_use(Flag) :-
  ( sub_atom(Flag, 0, _, _, 'kernel_')
  ; sub_atom(Flag, 0, _, _, 'elibc_')
  ; sub_atom(Flag, 0, _, _, 'userland_')
  ; sub_atom(Flag, 0, _, _, 'abi_')
  ; Flag == 'split-usr'
  ).


%! variant:flag_gates_dep(+Repo, +Entry, +Flag) is semidet.
%
% Succeeds if Flag gates a use_conditional_group containing at least
% one package_dependency in any dependency class of the ebuild.

variant:flag_gates_dep(Repo, Entry, Flag) :-
  member(DepKey, [bdepend, cdepend, depend, idepend, rdepend, pdepend]),
  cache:entry_metadata(Repo, Entry, DepKey, Dep),
  variant:term_contains_gated_dep(Dep, Flag),
  !.


%! variant:term_contains_gated_dep(+Term, +Flag) is semidet.
%
% Recursively checks whether Term is or contains a use_conditional_group
% gated by Flag that ultimately contains a package_dependency.

variant:term_contains_gated_dep(use_conditional_group(positive, Flag, _, Deps), Flag) :-
  !, variant:deps_contain_package_dep(Deps).
variant:term_contains_gated_dep(use_conditional_group(negative, Flag, _, Deps), Flag) :-
  !, variant:deps_contain_package_dep(Deps).
variant:term_contains_gated_dep(use_conditional_group(_, _, _, Deps), Flag) :-
  member(D, Deps),
  variant:term_contains_gated_dep(D, Flag).
variant:term_contains_gated_dep(any_of_group(Deps), Flag) :-
  member(D, Deps),
  variant:term_contains_gated_dep(D, Flag).
variant:term_contains_gated_dep(all_of_group(Deps), Flag) :-
  member(D, Deps),
  variant:term_contains_gated_dep(D, Flag).
variant:term_contains_gated_dep(exactly_one_of_group(Deps), Flag) :-
  member(D, Deps),
  variant:term_contains_gated_dep(D, Flag).
variant:term_contains_gated_dep(at_most_one_of_group(Deps), Flag) :-
  member(D, Deps),
  variant:term_contains_gated_dep(D, Flag).


%! variant:deps_contain_package_dep(+Deps) is semidet.
%
% Succeeds if the list contains at least one package_dependency.

variant:deps_contain_package_dep(Deps) :-
  member(D, Deps),
  ( D = package_dependency(_, _, _, _, _, _, _, _)
  ; variant:deps_contain_package_dep_nested(D)
  ),
  !.


%! variant:deps_contain_package_dep_nested(+Term) is semidet.

variant:deps_contain_package_dep_nested(all_of_group(Deps)) :-
  variant:deps_contain_package_dep(Deps).
variant:deps_contain_package_dep_nested(any_of_group(Deps)) :-
  variant:deps_contain_package_dep(Deps).
variant:deps_contain_package_dep_nested(use_conditional_group(_, _, _, Deps)) :-
  variant:deps_contain_package_dep(Deps).
variant:deps_contain_package_dep_nested(exactly_one_of_group(Deps)) :-
  variant:deps_contain_package_dep(Deps).
variant:deps_contain_package_dep_nested(at_most_one_of_group(Deps)) :-
  variant:deps_contain_package_dep(Deps).


% -----------------------------------------------------------------------------
%  Pivot detection: branch choices (|| and ^^)
% -----------------------------------------------------------------------------

%! variant:detect_branch_pivots(+ProofAVL, +Targets, +MaxPivots, -Pivots) is det.
%
% Scans dependency metadata for any_of_group and exactly_one_of_group
% terms where multiple package_dependency alternatives exist.

variant:detect_branch_pivots(_ProofAVL, Goals, MaxPivots, Pivots) :-
  findall(branch_pivot(GroupType, Chosen, Alt),
    ( member(Goal, Goals),
      variant:goal_to_entry(Goal, Repo://Entry),
      variant:branch_choice_in_entry(Repo, Entry, GroupType, Chosen, Alt)
    ),
    AllPivots0),
  variant:dedup_branch_pivots(AllPivots0, AllPivots1),
  sort(AllPivots1, AllPivots),
  length(AllPivots, Len),
  ( Len > MaxPivots
  -> length(Pivots, MaxPivots),
     append(Pivots, _, AllPivots)
  ;  Pivots = AllPivots
  ).


%! variant:branch_choice_in_entry(+Repo, +Entry, -GroupType, -Chosen, -Alt) is nondet.
%
% Finds || or ^^ groups in the dependency metadata of Repo://Entry
% that contain multiple concrete package_dependency alternatives.

variant:branch_choice_in_entry(Repo, Entry, GroupType, Chosen, Alt) :-
  member(DepKey, [bdepend, cdepend, depend, idepend, rdepend, pdepend]),
  cache:entry_metadata(Repo, Entry, DepKey, Dep),
  variant:find_branch_group(Dep, GroupType, Members),
  include(variant:is_concrete_dep, Members, ConcreteDeps),
  variant:distinct_cn_deps(ConcreteDeps, DistinctDeps),
  length(DistinctDeps, L), L >= 2,
  DistinctDeps = [Chosen|Alts],
  member(Alt, Alts).


%! variant:distinct_cn_deps(+Deps, -Unique) is det.
%
% Keeps only deps with distinct Category-Name pairs.

variant:distinct_cn_deps([], []).
variant:distinct_cn_deps([D|Rest], [D|Unique]) :-
  D = package_dependency(_, _, C, N, _, _, _, _),
  exclude(variant:same_cn(C, N), Rest, Filtered),
  variant:distinct_cn_deps(Filtered, Unique).

variant:same_cn(C, N, package_dependency(_, _, C, N, _, _, _, _)).


%! variant:dedup_branch_pivots(+Pivots, -Deduped) is det.
%
% Removes duplicate branch pivots that have the same alternative
% Category-Name (same dep chosen from different dep classes).

variant:dedup_branch_pivots([], []).
variant:dedup_branch_pivots([P|Rest], [P|Deduped]) :-
  P = branch_pivot(_, _, Alt),
  variant:pivot_alt_cn(Alt, AC, AN),
  exclude(variant:same_alt_cn(AC, AN), Rest, Filtered),
  variant:dedup_branch_pivots(Filtered, Deduped).

variant:pivot_alt_cn(package_dependency(_, _, C, N, _, _, _, _), C, N).

variant:same_alt_cn(C, N, branch_pivot(_, _, Alt)) :-
  variant:pivot_alt_cn(Alt, C, N).


%! variant:find_branch_group(+Term, -GroupType, -Members) is nondet.
%
% Recursively finds any_of_group or exactly_one_of_group terms.

variant:find_branch_group(any_of_group(Deps), any_of, Deps).
variant:find_branch_group(exactly_one_of_group(Deps), exactly_one_of, Deps).
variant:find_branch_group(Term, GroupType, Members) :-
  Term =.. [Functor|Args],
  member(Functor, [all_of_group, any_of_group, exactly_one_of_group,
                   at_most_one_of_group, use_conditional_group]),
  last(Args, SubDeps),
  is_list(SubDeps),
  member(Sub, SubDeps),
  variant:find_branch_group(Sub, GroupType, Members).


%! variant:is_concrete_dep(+Term) is semidet.
%
% Succeeds if Term is a package_dependency.

variant:is_concrete_dep(package_dependency(_, _, _, _, _, _, _, _)).


% -----------------------------------------------------------------------------
%  Combined pivot detection
% -----------------------------------------------------------------------------

%! variant:detect_pivots(+ProofAVL, +Targets, +MaxPivots, -UsePivots, -BranchPivots) is det.
%
% Detects both USE flag and branch pivots, bounded by MaxPivots each.

variant:detect_pivots(ProofAVL, Targets, MaxPivots, UsePivots, BranchPivots) :-
  variant:detect_use_pivots(ProofAVL, Targets, MaxPivots, UsePivots),
  variant:detect_branch_pivots(ProofAVL, Targets, MaxPivots, BranchPivots).


%! variant:pivots_to_specs(+UsePivots, +BranchPivots, -Specs) is det.
%
% Converts detected pivots into variant specifications suitable for
% re-proving.

variant:pivots_to_specs(UsePivots, BranchPivots, Specs) :-
  findall(variant(use_flip, Repo://Entry, Flag, NewState, Label),
    ( member(use_pivot(Repo://Entry, Flag, CurrentState), UsePivots),
      variant:flip_state(CurrentState, NewState),
      variant:use_flip_label(Repo://Entry, Flag, CurrentState, NewState, Label)
    ),
    UseSpecs),
  findall(variant(branch_alt, none, AltDep, none, Label),
    ( member(branch_pivot(GroupType, Chosen, AltDep), BranchPivots),
      variant:branch_label(GroupType, Chosen, AltDep, Label)
    ),
    BranchSpecs),
  append(UseSpecs, BranchSpecs, Specs).


%! variant:user_flags_to_specs(+Flags, +Targets, +ProofAVL, -Specs) is det.
%
% Converts user-specified flag names into variant specifications.
% Each flag is toggled from its current effective state.

variant:user_flags_to_specs(Flags, Goals, _ProofAVL, Specs) :-
  findall(variant(use_flip, Repo://Entry, Flag, NewState, Label),
    ( member(Flag, Flags),
      member(Goal, Goals),
      variant:goal_to_entry(Goal, Repo://Entry),
      use:effective_use_for_entry(Repo://Entry, Flag, CurrentState),
      variant:flip_state(CurrentState, NewState),
      variant:use_flip_label(Repo://Entry, Flag, CurrentState, NewState, Label)
    ),
    Specs).


%! variant:flip_state(+State, -Flipped) is det.

variant:flip_state(positive, negative).
variant:flip_state(negative, positive).


%! variant:use_flip_label(+RepoEntry, +Flag, +OldState, +NewState, -Label) is det.

variant:use_flip_label(Repo://Entry, Flag, _OldState, NewState, Label) :-
  cache:ordered_entry(Repo, Entry, C, N, _),
  ( NewState == positive -> StateStr = 'on' ; StateStr = 'off' ),
  format(atom(Label), 'USE ~w=~w on ~w/~w', [Flag, StateStr, C, N]).


%! variant:branch_label(+GroupType, +Chosen, +Alt, -Label) is det.

variant:branch_label(GroupType, Chosen, Alt, Label) :-
  ( Chosen = package_dependency(_, _, CC, CN, _, _, _, _)
  -> format(atom(ChosenStr), '~w/~w', [CC, CN])
  ;  format(atom(ChosenStr), '~w', [Chosen])
  ),
  ( Alt = package_dependency(_, _, AC, AN, _, _, _, _)
  -> format(atom(AltStr), '~w/~w', [AC, AN])
  ;  format(atom(AltStr), '~w', [Alt])
  ),
  ( GroupType == any_of -> GroupStr = '||'
  ; GroupType == exactly_one_of -> GroupStr = '^^'
  ; format(atom(GroupStr), '~w', [GroupType])
  ),
  format(atom(Label), '~w branch ~w (instead of ~w)', [GroupStr, AltStr, ChosenStr]).


% -----------------------------------------------------------------------------
%  Variant application
% -----------------------------------------------------------------------------

%! variant:apply(+Spec) is det.
%
% Asserts thread-local overrides for a variant specification.
% Must be paired with variant:cleanup/0 in setup_call_cleanup.

variant:apply(variant(use_flip, _RepoEntry, Flag, NewState, _Label)) :-
  !,
  ( NewState == positive
  -> assertz(variant:use_override(Flag, positive))
  ;  assertz(variant:use_override(Flag, negative))
  ).

variant:apply(variant(branch_alt, _None, AltDep, _None2, _Label)) :-
  !,
  assertz(variant:branch_prefer(AltDep)).

variant:apply(_).


%! variant:cleanup is det.
%
% Retracts all thread-local variant overrides.

variant:cleanup :-
  retractall(variant:use_override(_, _)),
  retractall(variant:branch_prefer(_)).


% -----------------------------------------------------------------------------
%  Plan diffing
% -----------------------------------------------------------------------------

%! variant:plan_entries(+Plan, -Entries) is det.
%
% Extracts a sorted list of C-N-Action entries from a plan for diffing.

variant:plan_entries(Plan, Entries) :-
  findall(entry(C, N, Ver, Action),
    ( member(Step, Plan),
      ( Step = [_|_] -> member(Rule, Step) ; Rule = Step ),
      variant:rule_to_entry(Rule, C, N, Ver, Action)
    ),
    Entries0),
  sort(Entries0, Entries).


%! variant:rule_to_entry(+Rule, -C, -N, -Ver, -Action) is semidet.

variant:rule_to_entry(rule(Repo://Entry:Action?{_Ctx}, _Body), C, N, Ver, Action) :-
  cache:ordered_entry(Repo, Entry, C, N, Ver).
variant:rule_to_entry(assumed(rule(Repo://Entry:Action?{_Ctx}, _Body)), C, N, Ver, Action) :-
  cache:ordered_entry(Repo, Entry, C, N, Ver).
variant:rule_to_entry(rule(assumed(Repo://Entry:Action?{_Ctx}), _Body), C, N, Ver, Action) :-
  cache:ordered_entry(Repo, Entry, C, N, Ver).


%! variant:plan_diff(+BaseEntries, +VariantEntries, -Diff) is det.
%
% Computes the difference between two plan entry lists.
% Diff = diff(Added, Removed, Changed) where:
%   Added   = entries in Variant but not in Base (by C-N)
%   Removed = entries in Base but not in Variant (by C-N)
%   Changed = entries where C-N matches but Ver or Action differs

variant:plan_diff(BaseEntries, VariantEntries, diff(Added, Removed, Changed)) :-
  variant:unique_cn(BaseEntries, BaseCNs),
  variant:unique_cn(VariantEntries, VarCNs),
  findall(entry(C, N, Ver, ''),
    ( member(cn(C, N, Ver), VarCNs),
      \+ member(cn(C, N, _), BaseCNs)
    ),
    Added),
  findall(entry(C, N, Ver, ''),
    ( member(cn(C, N, Ver), BaseCNs),
      \+ member(cn(C, N, _), VarCNs)
    ),
    Removed),
  findall(changed(C, N, BaseVer, VarVer),
    ( member(cn(C, N, BaseVer), BaseCNs),
      member(cn(C, N, VarVer), VarCNs),
      BaseVer \== VarVer
    ),
    Changed).


%! variant:unique_cn(+Entries, -CNs) is det.
%
% Extracts unique C-N-Ver triples from plan entries (deduplicates
% across actions like download/install/run).

variant:unique_cn(Entries, CNs) :-
  findall(cn(C, N, Ver),
    member(entry(C, N, Ver, _), Entries),
    All),
  sort(All, CNs).