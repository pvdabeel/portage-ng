/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> USE
USE flag evaluation, conditionals, and build-with-use state management.

This module implements all USE-flag-related logic for the portage-ng resolver.
The rule/2 clauses in rules.pl delegate USE decisions here: effective USE
resolution, IUSE default lookup, USE conditional activation, candidate USE
satisfaction checks, and build-with-use constraint propagation.

== Effective USE resolution ==

Gentoo's USE flag state for a given ebuild is determined by a priority chain:

  1. Per-package profile overrides (`package.use` in profile)
  2. User `package.use` overrides
  3. Gentoo-distributed soft overrides
  4. Profile-level soft overrides
  5. Global `make.conf` USE setting
  6. IUSE defaults from the ebuild (`+flag` / `-flag`)

The `effective_use_in_context/3` and `effective_use_for_entry/3` predicates
implement this chain.  Results are memoized in `memo:eff_use_cache_/4`.

== Build-with-use ==

Bracketed USE dependencies like `dev-libs/foo[bar]` are per-package
constraints.  They are threaded through the dependency context as
`build_with_use:use_state(Enabled, Disabled)` terms.  The key invariant
is that a child's build_with_use must *not* inherit from its parent --
only the directives from the current dependency edge apply.

== REQUIRED_USE ==

REQUIRED_USE evaluation checks whether the current effective USE state
satisfies boolean constraints (any-of, exactly-one-of, at-most-one-of,
conditionals).  `required_use_term_satisfied/2` drives this recursively.

== Newuse ==

The `--newuse` (`-N`) flag triggers rebuilds when the effective USE for an
installed package differs from what it was built with.  `newuse_mismatch/1,2`
implements this comparison.
*/

:- module(use, []).

% -----------------------------------------------------------------------------
%  Optional unify.pl extension hook (generic)
% -----------------------------------------------------------------------------
%
% Merge two use_state/2 compound terms by taking the union of their
% enable/disable sets.  Fails when a flag appears in both sets (conflict).
% This hook is called by feature_unification:val/3 (CASE 0) and is critical
% for the prescience mechanism: sampler:ctx_union must be able to merge
% build_with_use contexts when a literal is re-proven with a changed context.

feature_unification:val_hook(use_state(En1, Dis1), use_state(En2, Dis2), use_state(En, Dis)) :-
    !,
    union(En1, En2, EnU),
    union(Dis1, Dis2, DisU),
    intersection(EnU, DisU, Conflicts),
    Conflicts == [],
    sort(EnU, En),
    sort(DisU, Dis).
feature_unification:val_hook(use_state(En, Dis), [], use_state(En, Dis)) :- !.
feature_unification:val_hook([], use_state(En, Dis), use_state(En, Dis)) :- !.


% =============================================================================
%  Effective USE in context
% =============================================================================

%! use:effective_use_in_context(+Context, +Use, -State)
%
% Determine the effective state of USE flag Use for the ebuild identified
% by the `self/1` term in Context. State is unified with `positive` or
% `negative`. Results are memoized in memo:eff_use_cache_/4.

use:effective_use_in_context(Context, Use, State) :-
  memberchk(self(RepoEntry0), Context),
  RepoEntry0 = Repo://Id,
  \+ Use =.. [minus,_],
  ( memo:eff_use_cache_(Repo, Id, Use, Cached) ->
      State = Cached
  ;
  use:entry_iuse_default(Repo://Id, Use, Default),
  cache:ordered_entry(Repo, Id, C, N, _),
      ( variant:use_overridden(Use, Eff) ->
      true
  ; preference:profile_use_hard(Repo://Id, Use, Eff, _Reason0) ->
      true
  ; preference:userconfig_use(C, N, Use, positive) ->
      Eff = positive
  ; preference:userconfig_use(C, N, Use, negative) ->
      Eff = negative
  ; preference:userconfig_use_match(Repo://Id, Use, Eff0) ->
      Eff = Eff0
  ; preference:profile_use_soft_match(Repo://Id, Use, Eff0) ->
      Eff = Eff0
  ; preference:global_use(Use) ->
      Eff = positive
  ; preference:global_use(minus(Use)) ->
      Eff = negative
  ; Eff = Default
  ),
      assertz(memo:eff_use_cache_(Repo, Id, Use, Eff)),
      State = Eff
  ),
  !.

%! use:effective_use_for_entry(+RepoEntry, +Use, -State)
%
% Like effective_use_in_context/3 but takes a direct repo entry instead
% of extracting it from a context. Used by use_conditional_group rules
% for the ebuild that owns the conditional.

use:effective_use_for_entry(RepoEntry0, Use, State) :-
  RepoEntry0 = Repo://Id,
  \+ Use =.. [minus,_],
  ( memo:eff_use_cache_(Repo, Id, Use, Cached) ->
      State = Cached
  ;
  use:entry_iuse_default(Repo://Id, Use, Default),
  cache:ordered_entry(Repo, Id, C, N, _),
      ( variant:use_overridden(Use, Eff) ->
      true
  ; preference:profile_use_hard(Repo://Id, Use, Eff, _Reason0) ->
      true
  ; preference:userconfig_use(C, N, Use, positive) ->
      Eff = positive
  ; preference:userconfig_use(C, N, Use, negative) ->
      Eff = negative
  ; preference:userconfig_use_match(Repo://Id, Use, Eff0) ->
      Eff = Eff0
  ; preference:profile_use_soft_match(Repo://Id, Use, Eff0) ->
      Eff = Eff0
  ; preference:global_use(Use) ->
      Eff = positive
  ; preference:global_use(minus(Use)) ->
      Eff = negative
  ; Eff = Default
  ),
      assertz(memo:eff_use_cache_(Repo, Id, Use, Eff)),
      State = Eff
  ),
  !.


% =============================================================================
%  Per-entry IUSE default map
% =============================================================================

%! use:entry_iuse_default(+RepoEntry, +Use, -Default)
%
% Look up the IUSE default polarity for Use in the given ebuild.
% Fails if Use is not declared in IUSE. Defaults are determined by
% `+flag` (positive) or `-flag`/bare (negative) syntax in IUSE.
% Results are memoized in an AVL map per entry (memo:iuse_default_cache_/3).

use:entry_iuse_default(Repo://Entry, Use, Default) :-
  ( memo:iuse_default_cache_(Repo, Entry, Map) ->
    get_assoc(Use, Map, Default),
    !
  ;
    findall(Raw, query:search(iuse(Raw), Repo://Entry), RawIuse0),
    sort(RawIuse0, RawIuse),
    findall(U-Def,
            ( member(Raw, RawIuse),
              ( Raw = plus(U)  -> Def = positive
              ; Raw = minus(U) -> Def = negative
              ; eapi:strip_use_default(Raw, U),
                Def = negative
              )
            ),
            Pairs0),
    sort(Pairs0, Pairs),
    use:iuse_default_pairs_to_assoc(Pairs, Map),
    assertz(memo:iuse_default_cache_(Repo, Entry, Map)),
    get_assoc(Use, Map, Default),
    !
  ).

%! use:iuse_default_pairs_to_assoc(+Pairs, -Map)
%
% Build an AVL map from Use-Default pairs. If a flag appears multiple
% times, `positive` wins (IUSE `+flag` overrides bare `flag`).

use:iuse_default_pairs_to_assoc(Pairs, Map) :-
  empty_assoc(M0),
  use:iuse_default_pairs_to_assoc_(Pairs, M0, Map).

use:iuse_default_pairs_to_assoc_([], M, M) :- !.
use:iuse_default_pairs_to_assoc_([U-Def|Rest], M0, M) :-
  ( get_assoc(U, M0, Existing) ->
      ( Existing == positive -> M1 = M0
      ; Def == positive -> put_assoc(U, M0, positive, M1)
      ; M1 = M0
      )
  ; put_assoc(U, M0, Def, M1)
  ),
  use:iuse_default_pairs_to_assoc_(Rest, M1, M).


% =============================================================================
%  Per-entry IUSE memoization
% =============================================================================

%! use:entry_iuse_info(+RepoEntry, -Info)
%
% Retrieve the memoized IUSE info for an entry. Info is a compound
% `iuse_info(IuseSet, PlusSet)` where IuseSet is the sorted list of
% all IUSE flag atoms and PlusSet is the sorted list of flags declared
% with `+` (default-on).

use:entry_iuse_info(Repo://Entry, Info) :-
  ( memo:iuse_info_cache_(Repo, Entry, Info) ->
    true
  ;
    findall(Raw, query:search(iuse(Raw), Repo://Entry), RawIuse0),
    sort(RawIuse0, RawIuse),
    findall(U,
            ( member(Raw, RawIuse),
              eapi:strip_use_default(Raw, U)
            ),
            Iuse0),
    sort(Iuse0, IuseSet),
    findall(U,
            member(plus(U), RawIuse),
            Plus0),
    sort(Plus0, PlusSet),
    Info = iuse_info(IuseSet, PlusSet),
    assertz(memo:iuse_info_cache_(Repo, Entry, Info))
  ).


% =============================================================================
%  Build-with-use state management
% =============================================================================

%! use:empty_use_state(-State)
%
% The empty build-with-use state (no enables, no disables).

use:empty_use_state(use_state([],[])).

%! use:normalize_build_with_use(+BWU0, -BWU)
%
% Normalize a build_with_use term to canonical `use_state(En, Dis)` form
% with sorted lists. Handles use_state/2 compounds, legacy flat lists,
% and unknown formats (normalised to empty).

use:normalize_build_with_use(use_state(En0, Dis0), use_state(En, Dis)) :-
  !,
  sort(En0, En),
  sort(Dis0, Dis).
use:normalize_build_with_use(BWU0, use_state(En, Dis)) :-
  is_list(BWU0),
  !,
  use:build_with_use_requirements(BWU0, En, Dis).
use:normalize_build_with_use(_Other, use_state([],[])) :-
  !.

%! use:context_build_with_use_state(+Context, -State)
%
% Extract and normalize the build_with_use state from a dependency
% context. Returns empty state if no build_with_use term is present.

use:context_build_with_use_state(Context, State) :-
  ( memberchk(build_with_use:BWU, Context) ->
      use:normalize_build_with_use(BWU, State)
  ; empty_use_state(State)
  ),
  !.

%! use:process_bwu_directive(+ParentCtx, +Directive, +State0, -State)
%
% Fold helper for building up build-with-use state. Resolves a single
% USE directive against the parent context, then adds the flag to the
% enable or disable set. Conflicting directives (enable a flag already
% in Dis, or vice versa) cause failure to preserve determinism.

use:process_bwu_directive(ParentContext, use(Directive, Default), use_state(En0, Dis0), use_state(En, Dis)) :-
  !,
  use:use_dep_requirement(ParentContext, Directive, Default, Requirement),
  ( Requirement = requirement(enable, Use, _D) ->
      \+ memberchk(Use, Dis0),
      sort([Use|En0], En),
      Dis = Dis0
  ; Requirement = requirement(disable, Use, _D) ->
      \+ memberchk(Use, En0),
      sort([Use|Dis0], Dis),
      En = En0
  ; En = En0,
    Dis = Dis0
  ).
use:process_bwu_directive(_ParentContext, _Other, State, State) :- !.


%! use:build_with_use_changes(+State, +RepoEntry, -Changes)
%
% Compute the list of USE flags that build_with_use would change from
% the candidate's current effective state.  Each element of Changes
% is `use_change(Flag, enable)` or `use_change(Flag, disable)`.
% Empty list if no changes are needed.

use:build_with_use_changes(use_state([], []), _, []) :- !.
use:build_with_use_changes(use_state(Enable, Disable), Repo://Entry, Changes) :-
    findall(use_change(F, enable),
            ( member(F, Enable),
              use:candidate_iuse_present(Repo://Entry, F),
              \+ use:candidate_effective_use_enabled_in_iuse(Repo://Entry, F)
            ),
            EnableChanges),
    findall(use_change(F, disable),
            ( member(F, Disable),
              use:candidate_iuse_present(Repo://Entry, F),
              use:candidate_effective_use_enabled_in_iuse(Repo://Entry, F)
            ),
            DisableChanges),
    append(EnableChanges, DisableChanges, Changes).


%! use:model_required_use_changes(+ModelKeys, -Changes)
%
% Extract USE flag changes that the REQUIRED_USE model proof had to assume.
% ModelKeys is the R list from query:search(model(_,required_use(R),_), ...).
% Returns use_change(Flag, enable|disable) for each assumption.
% Handles both individual flag assumptions and group-level REQUIRED_USE
% assumptions (exactly_one_of_group, any_of_group, at_most_one_of_group).

use:model_required_use_changes(ModelKeys, Changes) :-
    findall(Change,
            ( member(A, ModelKeys),
              use:model_assumption_to_change(A, Change)
            ),
            Changes).

use:model_assumption_to_change(assumed(Use), use_change(Use, enable)) :-
    atom(Use), \+ Use = minus(_).
use:model_assumption_to_change(assumed(minus(Use)), use_change(Use, disable)) :-
    atom(Use), \+ Use = minus(_).
use:model_assumption_to_change(assumed(conflict(required, Use)), use_change(Use, enable)) :-
    atom(Use), \+ Use = minus(_).
use:model_assumption_to_change(assumed(conflict(required, minus(Use))), use_change(Use, disable)) :-
    atom(Use), \+ Use = minus(_).
use:model_assumption_to_change(assumed(conflict(blocking, minus(Use))), use_change(Use, enable)) :-
    atom(Use), \+ Use = minus(_).
use:model_assumption_to_change(assumed(conflict(blocking, Use)), use_change(Use, disable)) :-
    atom(Use), \+ Use = minus(_).

use:model_assumption_to_change(assumed(conflict(required_use, exactly_one_of_group(Deps))),
                           use_change(Flag, enable)) :-
    use:required_use_group_pick_flag(Deps, Flag).
use:model_assumption_to_change(assumed(conflict(required_use, any_of_group(Deps))),
                           use_change(Flag, enable)) :-
    use:required_use_group_pick_flag(Deps, Flag).

use:model_assumption_to_change(assumed(conflict(required_use, at_most_one_of_group(Deps))),
                           use_change(Flag, disable)) :-
    use:required_use_group_excess_flags(Deps, Flag).

%! use:required_use_group_pick_flag(+Deps, -Flag)
% Pick a single flag from a REQUIRED_USE group to satisfy the constraint.
% Prefers flags that are already set in the system's USE_EXPAND defaults;
% falls back to the last flag in the list (typically the highest version).
use:required_use_group_pick_flag(Deps, Flag) :-
    findall(F, ( member(required(F), Deps), atom(F), \+ F = minus(_) ), Flags),
    Flags \== [],
    ( member(F, Flags), preference:global_use(F) ->
        Flag = F
    ; last(Flags, Flag)
    ).

%! use:required_use_group_excess_flags(+Deps, -Flag)
% For at_most_one_of, yield each flag that is currently enabled beyond
% the first. The first enabled flag is kept; extras should be disabled.
use:required_use_group_excess_flags(Deps, Flag) :-
    findall(F, ( member(required(F), Deps), atom(F), \+ F = minus(_),
                 preference:global_use(F) ), Enabled),
    Enabled = [_Keep|Extras],
    Extras \== [],
    member(Flag, Extras).


% =============================================================================
%  Context helpers for per-package USE (build_with_use)
% =============================================================================

%! use:assumed(+Context, +Use)
%
% True if Use is positively assumed in Context -- either via an explicit
% `assumed(Use)` term or via the enable set of a `build_with_use` state.

use:assumed(Ctx, Use) :-
  memberchk(assumed(Use), Ctx),
  !.
use:assumed(Ctx, Use) :-
  memberchk(build_with_use:BU, Ctx),
  BU = use_state(En, _Dis),
  memberchk(Use, En),
  !.
use:assumed(Ctx, Use) :-
  memberchk(build_with_use:BU, Ctx),
  is_list(BU),
  memberchk(assumed(Use), BU),
  !.

%! use:assumed_minus(+Context, +Use)
%
% True if Use is negatively assumed in Context -- either via an explicit
% `assumed(minus(Use))` term or via the disable set of a `build_with_use`.

use:assumed_minus(Ctx, Use) :-
  memberchk(assumed(minus(Use)), Ctx),
  !.
use:assumed_minus(Ctx, Use) :-
  memberchk(build_with_use:BU, Ctx),
  BU = use_state(_En, Dis),
  memberchk(Use, Dis),
  !.
use:assumed_minus(Ctx, Use) :-
  memberchk(build_with_use:BU, Ctx),
  is_list(BU),
  memberchk(assumed(minus(Use)), BU),
  !.


% =============================================================================
%  Self-entry USE state (from ?{Context} list)
% =============================================================================

%! use:self_context_use_state(+Context, +Use, -State)
%
% Determine the USE state for flag Use on the self/1 entry in the
% ?{Context} list.  This is used by optional USE deps (`foo(+)`,
% `foo(-)`) to check the parent ebuild's own USE configuration.
% Results are memoized in memo:self_use_cache_/4.

use:self_context_use_state(Ctx, Use, State) :-
  memberchk(self(RepoEntry0), Ctx),
  RepoEntry0 = Repo://Id,
  ( memo:self_use_cache_(Repo, Id, Use, Cached) ->
      Cached \== miss,
      State = Cached
  ;
      ( use:self_context_use_state_compute_(Repo, Id, Use, S0) ->
          assertz(memo:self_use_cache_(Repo, Id, Use, S0)),
          State = S0
      ;
          assertz(memo:self_use_cache_(Repo, Id, Use, miss)),
          fail
      )
  ),
  !.

%! use:self_context_use_state_compute_(+Repo, +Id, +Use, -State)
%
% Compute the USE state for a flag on an entry by inspecting IUSE
% metadata and categorizing the flag via eapi:categorize_use_for_entry/4.
% Handles both plain flags and USE_EXPAND-prefixed flags.

use:self_context_use_state_compute_(Repo, Id, Use, State) :-
  use:entry_iuse_info(Repo://Id, iuse_info(IuseSet, _PlusSet)),
  memberchk(Use, IuseSet),
  ( \+ eapi:check_use_expand_atom(Use),
    findall(S0:R0,
            ( cache:entry_metadata(Repo, Id, iuse, Arg),
              eapi:strip_use_default(Arg, Use),
              eapi:categorize_use_for_entry(Arg, Repo://Id, S0, R0)
            ),
            States0),
    States0 \== [],
    query:iuse_effective_state_(States0, State, _)
  ; atom(Use),
    sub_atom(Use, Before, 1, _, '_'),
    Before > 0,
    sub_atom(Use, 0, Before, _, Prefix),
    eapi:use_expand(Prefix),
    eapi:strip_prefix_atom(Prefix, Use, Value),
    cache:entry_metadata(Repo, Id, iuse, UEArg),
    eapi:categorize_use_for_entry(UEArg, Repo://Id, State, _),
    eapi:strip_use_default(UEArg, UEArgB),
    eapi:check_prefix_atom(Prefix, UEArgB),
    eapi:strip_prefix_atom(Prefix, UEArgB, Value)
  ).


% =============================================================================
%  USE-dependency requirement resolution
% =============================================================================

%! use:use_dep_requirement(+Context, +Directive, +Default, -Requirement)
%
% Resolve a USE dependency directive into a concrete requirement.
% Directives come from bracketed USE deps (e.g. `[foo]`, `[!bar?]`,
% `[baz(+)]`) and are one of: enable/1, disable/1, equal/1, inverse/1,
% optenable/1, optdisable/1.
% Returns `requirement(Mode, Use, Default)` where Mode is `enable` or
% `disable`, or the atom `none` for optional deps where the flag is
% not actively set.

use:use_dep_requirement(_Ctx, enable(Use), Default, requirement(enable, Use, Default)) :- !.
use:use_dep_requirement(_Ctx, disable(Use), Default, requirement(disable, Use, Default)) :- !.

use:use_dep_requirement(Ctx, equal(Use), Default, requirement(enable, Use, Default)) :-
  use:assumed(Ctx, Use), !.
use:use_dep_requirement(Ctx, equal(Use), Default, requirement(disable, Use, Default)) :-
  use:assumed_minus(Ctx, Use), !.
use:use_dep_requirement(Ctx, equal(Use), Default, requirement(enable, Use, Default)) :-
  use:effective_use_in_context(Ctx, Use, positive), !.
use:use_dep_requirement(Ctx, equal(Use), Default, requirement(disable, Use, Default)) :-
  use:effective_use_in_context(Ctx, Use, negative), !.
use:use_dep_requirement(_Ctx, equal(Use), Default, Requirement) :-
  ( Default == positive -> Requirement = requirement(enable, Use, Default)
  ; Default == negative -> Requirement = requirement(disable, Use, Default)
  ; Requirement = none
  ),
  !.

use:use_dep_requirement(Ctx, inverse(Use), Default, requirement(disable, Use, Default)) :-
  use:assumed(Ctx, Use), !.
use:use_dep_requirement(Ctx, inverse(Use), Default, requirement(enable, Use, Default)) :-
  use:assumed_minus(Ctx, Use), !.
use:use_dep_requirement(Ctx, inverse(Use), Default, requirement(disable, Use, Default)) :-
  use:effective_use_in_context(Ctx, Use, positive), !.
use:use_dep_requirement(Ctx, inverse(Use), Default, requirement(enable, Use, Default)) :-
  use:effective_use_in_context(Ctx, Use, negative), !.
use:use_dep_requirement(_Ctx, inverse(Use), Default, Requirement) :-
  ( Default == positive -> Requirement = requirement(disable, Use, Default)
  ; Default == negative -> Requirement = requirement(enable, Use, Default)
  ; Requirement = none
  ),
  !.

use:use_dep_requirement(Ctx, optenable(Use), Default, requirement(enable, Use, Default)) :-
  ( use:assumed(Ctx, Use)
  ; use:self_context_use_state(Ctx, Use, positive)
  ; \+ memberchk(self(_), Ctx),
    use:effective_use_in_context(Ctx, Use, positive)
  ),
  !.
use:use_dep_requirement(_Ctx, optenable(_Use), _Default, none) :- !.

use:use_dep_requirement(Ctx, optdisable(Use), Default, requirement(disable, Use, Default)) :-
  ( use:assumed_minus(Ctx, Use)
  ; use:self_context_use_state(Ctx, Use, negative)
  ; \+ memberchk(self(_), Ctx),
    use:effective_use_in_context(Ctx, Use, negative)
  ),
  !.
use:use_dep_requirement(_Ctx, optdisable(_Use), _Default, none) :- !.

use:use_dep_requirement(_Ctx, _Directive, _Default, none).


% =============================================================================
%  Candidate USE-dependency enforcement
% =============================================================================

%! use:candidate_satisfies_use_deps(+ParentCtx, +Candidate, +UseDeps)
%
% True if Candidate satisfies all bracketed USE requirements in UseDeps.
% For optional deps (optenable/optdisable), satisfaction is checked only
% when the flag is present in the candidate's IUSE.

use:candidate_satisfies_use_deps(_ParentContext, _Repo://_Entry, []) :- !.
use:candidate_satisfies_use_deps(ParentContext, Repo://Entry, [use(Directive, Default)|Rest]) :-
  use:use_dep_requirement(ParentContext, Directive, Default, Requirement),
  use:candidate_satisfies_use_requirement_opt(Directive, Repo://Entry, Requirement),
  use:candidate_satisfies_use_deps(ParentContext, Repo://Entry, Rest).

%! use:candidate_satisfies_use_requirement_opt(+Directive, +Entry, +Req)
%
% For optional directives (optenable/optdisable), only enforce the
% requirement if the flag is present in the candidate's IUSE.

use:candidate_satisfies_use_requirement_opt(optenable(Use), Repo://Entry, Requirement) :-
  !,
  ( use:candidate_iuse_present(Repo://Entry, Use) ->
      use:candidate_satisfies_use_requirement(Repo://Entry, Requirement)
  ; true
  ).
use:candidate_satisfies_use_requirement_opt(optdisable(Use), Repo://Entry, Requirement) :-
  !,
  ( use:candidate_iuse_present(Repo://Entry, Use) ->
      use:candidate_satisfies_use_requirement(Repo://Entry, Requirement)
  ; true
  ).
use:candidate_satisfies_use_requirement_opt(_, Repo://Entry, Requirement) :-
  use:candidate_satisfies_use_requirement(Repo://Entry, Requirement).

%! use:candidate_satisfies_use_requirement(+Entry, +Requirement)
%
% Check whether Entry's effective USE satisfies Requirement.
% If the flag is not in IUSE, the IUSE default semantics from the
% dependency (`(+)` or `(-)`) determine satisfaction.

use:candidate_satisfies_use_requirement(_Repo://_Entry, none) :- !.
use:candidate_satisfies_use_requirement(Repo://Entry, requirement(Mode, Use, Default)) :-
  ( use:candidate_iuse_present(Repo://Entry, Use)
  -> true
  ; use:use_dep_default_satisfies_absent_iuse(Default, Mode)
  ).

%! use:candidate_iuse_present(+RepoEntry, +Use)
%
% True if Use is declared in the entry's IUSE (regardless of default).

use:candidate_iuse_present(Repo://Entry, Use) :-
  use:entry_iuse_info(Repo://Entry, iuse_info(IuseSet, _PlusSet)),
  memberchk(Use, IuseSet),
  !.

%! use:use_dep_default_satisfies_absent_iuse(+Default, +Mode)
%
% When a flag is absent from IUSE, `(+)` defaults satisfy `enable`
% requirements and `(-)` defaults satisfy `disable` requirements.

use:use_dep_default_satisfies_absent_iuse(positive, enable) :- !.
use:use_dep_default_satisfies_absent_iuse(negative, disable) :- !.
use:use_dep_default_satisfies_absent_iuse(_Default, _Mode) :- fail.


% =============================================================================
%  Candidate effective USE evaluation
% =============================================================================

%! use:candidate_effective_use_enabled_in_iuse(+RepoEntry, +Use)
%
% True if Use is effectively enabled for the given entry, considering
% the full priority chain (profile overrides, package.use, IUSE defaults).

use:candidate_effective_use_enabled_in_iuse(Repo://Entry, Use) :-
  use:entry_effective_use_set(Repo://Entry, EnabledSet),
  memberchk(Use, EnabledSet).

%! use:entry_effective_use_set(+RepoEntry, -EnabledSet)
%
% Compute (and memoize) the set of effectively enabled USE flags for an
% entry. EnabledSet is a sorted list of atoms.

use:entry_effective_use_set(Repo://Entry, EnabledSet) :-
  ( memo:effective_use_fact(Repo, Entry, EnabledSet) ->
    true
  ;
    use:entry_iuse_info(Repo://Entry, iuse_info(IuseSet, _PlusSet)),
    findall(U,
            ( member(U, IuseSet),
              use:candidate_effective_use_enabled_raw(Repo://Entry, U)
            ),
            Enabled0),
    sort(Enabled0, EnabledSet),
    assertz(memo:effective_use_fact(Repo, Entry, EnabledSet))
  ).

%! use:candidate_effective_use_enabled_raw(+RepoEntry, +Use)
%
% Raw evaluation of whether Use is enabled for RepoEntry, walking the
% full priority chain. Not memoized directly -- callers should use
% entry_effective_use_set/2 instead.

use:candidate_effective_use_enabled_raw(Repo://Entry, Use) :-
  cache:ordered_entry(Repo, Entry, C, N, _),
  ( preference:profile_use_hard(Repo://Entry, Use, positive, _Reason0) ->
      true
  ; preference:profile_use_hard(Repo://Entry, Use, negative, _Reason0) ->
      fail
  ; preference:userconfig_use(C, N, Use, positive) ->
      true
  ; preference:userconfig_use(C, N, Use, negative) ->
      fail
  ; preference:userconfig_use_match(Repo://Entry, Use, positive) ->
      true
  ; preference:userconfig_use_match(Repo://Entry, Use, negative) ->
      fail
  ; preference:profile_use_soft_match(Repo://Entry, Use, positive) ->
      true
  ; preference:profile_use_soft_match(Repo://Entry, Use, negative) ->
      fail
  ; preference:global_use(Use) ->
      true
  ; use:use_expand_selector_flag_unset(Use) ->
      fail
  ; preference:global_use(minus(Use)),
    \+ use:is_abi_x86_flag(Use) ->
      fail
  ; use:entry_iuse_info(Repo://Entry, iuse_info(_IuseSet, PlusSet)),
    memberchk(Use, PlusSet) ->
      true
  ; fail
  ).

%! use:use_expand_selector_flag_unset(+Use)
%
% True if Use is a USE_EXPAND flag (e.g. `python_targets_python3_12`)
% for which the USE_EXPAND group has explicit selections but this
% particular value is not among them. This prevents USE_EXPAND flags
% from being enabled by IUSE `+` defaults when the user/profile has
% made an explicit selection for that group.

use:use_expand_selector_flag_unset(Use) :-
  atom(Use),
  preference:use_expand_env(_EnvVar, Prefix),
  atom_concat(Prefix, '_', PrefixUnderscore),
  atom_concat(PrefixUnderscore, _, Use),
  use:use_expand_prefix_has_explicit_selection(Prefix),
  \+ preference:global_use(Use),
  \+ preference:global_use(minus(Use)),
  !.

%! use:use_expand_prefix_has_explicit_selection(+Prefix)
%
% True if any USE flag with the given USE_EXPAND prefix is explicitly
% set (positively or negatively) in the user/profile configuration.

use:use_expand_prefix_has_explicit_selection(Prefix) :-
  atom_concat(Prefix, '_', PrefixUnderscore),
  ( preference:global_use(Use0)
  ; preference:global_use(minus(Use0))
  ),
  atom(Use0),
  atom_concat(PrefixUnderscore, _, Use0),
  !.

%! use:is_abi_x86_flag(+Use)
%
% True if Use starts with `abi_x86_`. These flags receive special
% treatment: `preference:global_use(minus(abi_x86_*))` does not override
% IUSE `+` defaults, because ABI flags are typically profile-managed.

use:is_abi_x86_flag(Use) :-
  atom(Use),
  sub_atom(Use, 0, _, _, abi_x86_),
  !.


% =============================================================================
%  Installed package USE satisfaction checks
% =============================================================================

%! use:installed_pkg_satisfies_use_reqs(+ParentCtx, +Installed, +UseDeps)
%
% True if the installed package satisfies all USE requirements in UseDeps.
% Uses the VDB's recorded USE state rather than effective USE.

use:installed_pkg_satisfies_use_reqs(_ParentContext, _Installed, []) :- !.
use:installed_pkg_satisfies_use_reqs(ParentContext, pkg://InstalledId,
                                    [use(Directive, Default)|Rest]) :-
  !,
  use:use_dep_requirement(ParentContext, Directive, Default, Req),
  use:installed_pkg_satisfies_use_requirement(pkg://InstalledId, Req),
  use:installed_pkg_satisfies_use_reqs(ParentContext, pkg://InstalledId, Rest).
use:installed_pkg_satisfies_use_reqs(ParentContext, Installed, [_|Rest]) :-
  use:installed_pkg_satisfies_use_reqs(ParentContext, Installed, Rest).

%! use:installed_pkg_satisfies_use_requirement(+Installed, +Requirement)
%
% Check a single USE requirement against an installed package's VDB USE.

use:installed_pkg_satisfies_use_requirement(_Installed, none) :- !.
use:installed_pkg_satisfies_use_requirement(pkg://InstalledId, requirement(enable, Use, _Default)) :-
  query:search(use(Use), pkg://InstalledId),
  !.
use:installed_pkg_satisfies_use_requirement(pkg://InstalledId, requirement(disable, Use, _Default)) :-
  \+ query:search(use(Use), pkg://InstalledId),
  !.


% =============================================================================
%  Build-with-use constraint satisfaction
% =============================================================================

%! use:context_build_with_use_list(+Context, -List)
%
% Extract build-with-use assumptions from Context as a flat list of
% `assumed(Use)` and `assumed(minus(Use))` terms.

use:context_build_with_use_list(Context, List) :-
  ( memberchk(build_with_use:use_state(En, Dis), Context) ->
      findall(assumed(U), member(U, En), Pos),
      findall(assumed(minus(U)), member(U, Dis), Neg),
      append(Pos, Neg, List0),
      sort(List0, List)
  ; memberchk(build_with_use:List0, Context) ->
      List = List0
  ; List = []
  ).

%! use:build_with_use_requirements(+BWU, -MustEnable, -MustDisable)
%
% Extract sorted enable/disable lists from a build_with_use term.
% Handles both use_state/2 compounds and legacy flat lists.

use:build_with_use_requirements(use_state(En, Dis), MustEnable, MustDisable) :-
  !,
  sort(En, MustEnable),
  sort(Dis, MustDisable).
use:build_with_use_requirements(BuildWithUse, MustEnable, MustDisable) :-
  findall(U,
          ( member(required(U), BuildWithUse),
            \+ U =.. [minus,_]
          ),
          En0),
  findall(U,
          ( ( member(naf(required(U)), BuildWithUse)
            ; member(assumed(minus(U)), BuildWithUse)
            ),
            \+ U =.. [minus,_]
          ),
          Dis0),
  sort(En0, MustEnable),
  sort(Dis0, MustDisable).

%! use:installed_entry_satisfies_build_with_use(+Installed, +Context)
%
% True if the installed package's built USE state satisfies the
% build_with_use constraints in Context. Flags not in the package's
% IUSE are ignored (they cannot influence the build).

use:installed_entry_satisfies_build_with_use(pkg://InstalledEntry, Context) :-
  use:context_build_with_use_state(Context, State),
  use:build_with_use_requirements(State, MustEnable, MustDisable),
  use:vdb_enabled_use_set(pkg://InstalledEntry, BuiltUse),
  use:vdb_iuse_set(pkg://InstalledEntry, BuiltIuse),
  forall(member(U, MustEnable),
         ( memberchk(U, BuiltIuse) -> memberchk(U, BuiltUse)
         ; true
         )),
  forall(member(U, MustDisable),
         ( memberchk(U, BuiltIuse) -> \+ memberchk(U, BuiltUse)
         ; true
         )).


% =============================================================================
%  --newuse / --changed-use support
% =============================================================================

%! use:newuse_mismatch(+InstalledEntry)
%
% True if the installed package has a USE mismatch compared to the
% currently effective USE for the same version in the repo set.
% Checks both enabled USE and declared IUSE for changes.
% Used to implement `--newuse` / `-N` rebuild semantics.

use:newuse_mismatch(pkg://InstalledEntry) :-
  query:search([category(C),name(N),version(V)], pkg://InstalledEntry),
  preference:accept_keywords(K),
  ( query:search([select(repository,notequal,pkg),category(C),name(N),keywords(K),version(V)],
                 CurRepo://CurEntry)
  -> use:newuse_mismatch(pkg://InstalledEntry, CurRepo://CurEntry)
  ;  fail
  ).

%! use:newuse_mismatch(+InstalledEntry, +RepoEntry)
%
% True if the installed package's built USE or IUSE differs from the
% current repo entry's effective USE or IUSE. Checks both the enabled
% USE set and the declared IUSE set for symmetric differences.

use:newuse_mismatch(pkg://InstalledEntry, CurRepo://CurEntry) :-
  use:vdb_enabled_use_set(pkg://InstalledEntry, BuiltUse),
  use:entry_enabled_use_set(CurRepo://CurEntry, CurUse),
  ( use:symmetric_diff_nonempty(BuiltUse, CurUse)
  ; use:vdb_iuse_set(pkg://InstalledEntry, BuiltIuse),
    use:entry_iuse_set(CurRepo://CurEntry, CurIuse),
    BuiltIuse \== [],
    CurIuse \== [],
    use:symmetric_diff_nonempty(BuiltIuse, CurIuse)
  ),
  !.


%! use:changeduse_mismatch(+InstalledEntry)
%
% True if the installed package's effective USE flags differ from what
% the current configuration would produce. Unlike newuse_mismatch/1,
% this ignores IUSE additions/removals and only checks whether flags
% that are actually enabled/disabled have changed.

use:changeduse_mismatch(pkg://InstalledEntry) :-
  query:search([category(C),name(N),version(V)], pkg://InstalledEntry),
  preference:accept_keywords(K),
  ( query:search([select(repository,notequal,pkg),category(C),name(N),keywords(K),version(V)],
                 CurRepo://CurEntry)
  -> use:changeduse_mismatch(pkg://InstalledEntry, CurRepo://CurEntry)
  ;  fail
  ).


%! use:changeduse_mismatch(+InstalledEntry, +RepoEntry)
%
% True if the installed package's built USE set differs from the
% current repo entry's effective USE set. Only compares the enabled
% flag sets, ignoring IUSE changes.

use:changeduse_mismatch(pkg://InstalledEntry, CurRepo://CurEntry) :-
  use:vdb_enabled_use_set(pkg://InstalledEntry, BuiltUse),
  use:entry_enabled_use_set(CurRepo://CurEntry, CurUse),
  use:symmetric_diff_nonempty(BuiltUse, CurUse),
  !.


%! use:vdb_enabled_use_set(+RepoEntry, -UseSet)
%
% Collect the USE flags recorded as enabled in the VDB for an entry.

use:vdb_enabled_use_set(RepoEntry, UseSet) :-
  findall(U, query:search(use(U), RepoEntry), Us0),
  sort(Us0, UseSet).

%! use:entry_iuse_set(+RepoEntry, -IuseSet)
%
% Collect the bare IUSE flag names for an entry (stripping defaults).

use:entry_iuse_set(RepoEntry, IuseSet) :-
  findall(U,
          ( query:search(iuse(Value), RepoEntry),
            eapi:strip_use_default(Value, U)
          ),
          Us0),
  sort(Us0, IuseSet).

%! use:vdb_iuse_set(+RepoEntry, -IuseSet)
%
% Alias for entry_iuse_set/2 (VDB entries store IUSE the same way).

use:vdb_iuse_set(RepoEntry, IuseSet) :-
  use:entry_iuse_set(RepoEntry, IuseSet).

%! use:entry_enabled_use_set(+RepoEntry, -UseSet)
%
% Compute the set of USE flags that would be enabled for a repo entry
% based on IUSE categorization. Used for --newuse comparison.

use:entry_enabled_use_set(RepoEntry, UseSet) :-
  findall(U,
          ( query:search(iuse(Value), RepoEntry),
            eapi:categorize_use(Value, positive, _Reason),
            eapi:strip_use_default(Value, U)
          ),
          Us0),
  sort(Us0, UseSet).

%! use:symmetric_diff_nonempty(+A, +B)
%
% True if the symmetric difference of sorted lists A and B is non-empty
% (i.e. there exists an element in A not in B, or vice versa).

use:symmetric_diff_nonempty(A, B) :-
  ( member(X, A), \+ memberchk(X, B) -> true
  ; member(X, B), \+ memberchk(X, A) -> true
  ).


% =============================================================================
%  REQUIRED_USE helpers
% =============================================================================

%! use:required_use_term_satisfied(+Context, +Term)
%
% Recursively check whether a REQUIRED_USE term is satisfied by the
% effective USE state for the ebuild identified by self/1 in Context.
% Handles required/1, use_conditional_group/4, any_of_group/1,
% exactly_one_of_group/1, and at_most_one_of_group/1.

use:required_use_term_satisfied(Ctx, required(Use)) :-
  \+ Use =.. [minus,_],
  use:effective_use_in_context(Ctx, Use, positive),
  !.
use:required_use_term_satisfied(Ctx, required(minus(Use))) :-
  \+ Use =.. [minus,_],
  use:effective_use_in_context(Ctx, Use, negative),
  !.
use:required_use_term_satisfied(Ctx, use_conditional_group(positive, Use, _Self, Deps)) :-
  ( use:effective_use_in_context(Ctx, Use, positive) ->
      forall(member(D, Deps), use:required_use_term_satisfied(Ctx, D))
  ; true
  ),
  !.
use:required_use_term_satisfied(Ctx, use_conditional_group(negative, Use, _Self, Deps)) :-
  ( use:effective_use_in_context(Ctx, Use, negative) ->
      forall(member(D, Deps), use:required_use_term_satisfied(Ctx, D))
  ; true
  ),
  !.
use:required_use_term_satisfied(Ctx, any_of_group(Deps)) :-
  member(D, Deps),
  use:required_use_term_satisfied(Ctx, D),
  !.
use:required_use_term_satisfied(Ctx, exactly_one_of_group(Deps)) :-
  findall(1, (member(D, Deps), use:required_use_term_satisfied(Ctx, D)), Ones),
  length(Ones, 1),
  !.
use:required_use_term_satisfied(Ctx, at_most_one_of_group(Deps)) :-
  findall(1, (member(D, Deps), use:required_use_term_satisfied(Ctx, D)), Ones),
  length(Ones, N),
  N =< 1,
  !.


% =============================================================================
%  Build-with-use / REQUIRED_USE compatibility
% =============================================================================

%! use:build_with_use_resolve_required_use(+StateIn, +RepoEntry, -StateOut)
%
% Auto-resolves conflicts between the build_with_use Enable set and
% exactly_one_of / at_most_one_of REQUIRED_USE constraints.  When enabling
% a flag would create a mutual-exclusion violation (another group member is
% already positive), the conflicting flag is added to the Disable set
% instead of failing the model computation outright.

use:build_with_use_resolve_required_use(use_state([], []), _, use_state([], [])) :- !.
use:build_with_use_resolve_required_use(use_state(Enable, Disable), Repo://Entry, use_state(Enable, DisableOut)) :-
    ( Enable == [] ->
        DisableOut = Disable
    ; findall(ReqUse,
              cache:entry_metadata(Repo, Entry, required_use, ReqUse),
              AllReqUse),
      foldl(use:bwu_resolve_conflict(Enable, Repo://Entry), AllReqUse, Disable, DisableOut)
    ).

%! use:bwu_resolve_conflict(+Enable, +RepoEntry, +Term, +Dis0, -Dis)
%
% Fold helper: for a single REQUIRED_USE term, collect any flags that
% must be disabled to avoid mutual-exclusion violations with the Enable
% set, and merge them into the accumulator.

use:bwu_resolve_conflict(Enable, RepoEntry, Term, Dis0, Dis) :-
    findall(Other,
            use:bwu_conflict_disable(Term, Enable, RepoEntry, Other),
            Extras),
    append(Dis0, Extras, Dis1),
    sort(Dis1, Dis).

%! use:bwu_conflict_disable(+Term, +Enable, +RepoEntry, -DisableFlag)
%
% Yields each flag that must be disabled to resolve a mutual-exclusion
% conflict.  A conflict exists when a flag in Enable is currently negative
% (will be switched on) and another member of the same exactly_one_of or
% at_most_one_of group is currently positive.

use:bwu_conflict_disable(exactly_one_of_group(Deps), Enable, RepoEntry, Other) :-
    member(required(Flag), Deps),
    memberchk(Flag, Enable),
    use:effective_use_for_entry(RepoEntry, Flag, negative),
    member(required(Other), Deps),
    Other \== Flag,
    use:effective_use_for_entry(RepoEntry, Other, positive).
use:bwu_conflict_disable(at_most_one_of_group(Deps), Enable, RepoEntry, Other) :-
    member(required(Flag), Deps),
    memberchk(Flag, Enable),
    use:effective_use_for_entry(RepoEntry, Flag, negative),
    member(required(Other), Deps),
    Other \== Flag,
    use:effective_use_for_entry(RepoEntry, Other, positive).
use:bwu_conflict_disable(use_conditional_group(positive, Use, _, SubDeps), Enable, RepoEntry, Other) :-
    ( use:effective_use_for_entry(RepoEntry, Use, positive) ; memberchk(Use, Enable) ),
    member(SubTerm, SubDeps),
    use:bwu_conflict_disable(SubTerm, Enable, RepoEntry, Other).
use:bwu_conflict_disable(use_conditional_group(negative, Use, _, SubDeps), Enable, RepoEntry, Other) :-
    use:effective_use_for_entry(RepoEntry, Use, negative),
    \+ memberchk(Use, Enable),
    member(SubTerm, SubDeps),
    use:bwu_conflict_disable(SubTerm, Enable, RepoEntry, Other).


% =============================================================================
%  Post-BWU REQUIRED_USE stabilization
% =============================================================================
%
% After build_with_use_resolve_required_use handles mutual-exclusion
% conflicts, some REQUIRED_USE constraints may still be violated --
% typically any_of_group or exactly_one_of_group where no member is
% currently satisfied, or conditional groups whose sub-requirements
% fail after BWU adjustments.
%
% Portage explicitly does not auto-unmask for REQUIRED_USE (see
% depgraph.py: "unsatisfied REQUIRED_USE (currently has no autounmask
% support)").  This stabilization step goes beyond Portage by
% proactively adjusting the BWU Enable/Disable sets to satisfy
% constraints, reducing false domain-assumption rejections.

%! use:stabilize_required_use(+RepoEntry, +BWU_In, -BWU_Out)
%
% Adjusts the build_with_use state to satisfy REQUIRED_USE constraints
% that build_with_use_resolve_required_use could not handle.  Handles
% any_of_group (enable one member), exactly_one_of_group (enable one
% when zero satisfied), nested conditional groups, and simple
% required(Flag) implications.
%
% Uses a fixed-point loop: enabling a flag to satisfy one constraint
% (e.g. webengine requires quick) may activate another conditional
% (e.g. quick requires qml).  The loop repeats until no more changes
% are made, capped at 5 iterations to avoid infinite loops.

use:stabilize_required_use(Repo://Entry, BWU_In, BWU_Out) :-
    BWU_In = use_state(Enable0, Disable0),
    ( Enable0 == [], Disable0 == [] ->
        BWU_Out = BWU_In
    ; findall(ReqUse,
              cache:entry_metadata(Repo, Entry, required_use, ReqUse),
              AllReqUse),
      ( AllReqUse == [] ->
          BWU_Out = BWU_In
      ; use:stabilize_required_use_loop(Repo://Entry, AllReqUse, BWU_In, BWU_Out, 5)
      )
    ).


%! use:stabilize_required_use_loop(+RepoEntry, +AllReqUse, +BWU_In, -BWU_Out, +Limit)
%
% Fixed-point iteration: runs one stabilization pass over all
% REQUIRED_USE terms.  If the BWU changed, repeats (up to Limit
% times) to resolve cascading implications.

use:stabilize_required_use_loop(_RepoEntry, _AllReqUse, BWU_In, BWU_In, 0) :- !.
use:stabilize_required_use_loop(RepoEntry, AllReqUse, BWU_In, BWU_Out, Limit) :-
    foldl(use:stabilize_requse_term(RepoEntry), AllReqUse, BWU_In, BWU_Mid),
    ( BWU_Mid == BWU_In ->
        BWU_Out = BWU_Mid
    ; Limit1 is Limit - 1,
      use:stabilize_required_use_loop(RepoEntry, AllReqUse, BWU_Mid, BWU_Out, Limit1)
    ).


%! use:stabilize_requse_term(+RepoEntry, +Term, +BWU_In, -BWU_Out)
%
% Fold helper: if Term is satisfied under the current BWU, pass through.
% Otherwise compute fixes and apply them.

use:stabilize_requse_term(RepoEntry, Term, use_state(En0, Dis0), use_state(EnOut, DisOut)) :-
    ( use:requse_term_ok_with_bwu(RepoEntry, En0, Dis0, Term) ->
        EnOut = En0, DisOut = Dis0
    ; use:requse_term_fixes(RepoEntry, En0, Dis0, Term, Fixes),
      Fixes \== [] ->
        foldl(use:apply_requse_fix, Fixes, use_state(En0, Dis0), use_state(EnOut, DisOut))
    ; EnOut = En0, DisOut = Dis0
    ).


%! use:requse_term_fixes(+RepoEntry, +Enable, +Disable, +Term, -Fixes)
%
% Computes a list of enable(Flag)/disable(Flag) fixes for a violated
% REQUIRED_USE term.

use:requse_term_fixes(_RepoEntry, _En, _Dis, any_of_group(Deps), [enable(Flag)]) :-
    use:requse_pick_satisfying_flag(Deps, Flag), !.
use:requse_term_fixes(RepoEntry, En, Dis, exactly_one_of_group(Deps), []) :-
    findall(1, (member(D, Deps), use:requse_term_ok_with_bwu(RepoEntry, En, Dis, D)), Sat),
    length(Sat, N), N > 1, !.
use:requse_term_fixes(RepoEntry, En, Dis, exactly_one_of_group(Deps), [enable(Flag)]) :-
    findall(1, (member(D, Deps), use:requse_term_ok_with_bwu(RepoEntry, En, Dis, D)), Sat),
    length(Sat, 0),
    use:requse_pick_satisfying_flag(Deps, Flag), !.
use:requse_term_fixes(RepoEntry, En, Dis,
                  use_conditional_group(positive, Use, _, SubDeps), Fixes) :-
    use:requse_flag_is_positive(RepoEntry, En, Dis, Use),
    foldl(use:collect_requse_fixes(RepoEntry, En, Dis), SubDeps, [], Fixes),
    Fixes \== [], !.
use:requse_term_fixes(RepoEntry, En, Dis,
                  use_conditional_group(negative, Use, _, SubDeps), Fixes) :-
    use:requse_flag_is_negative(RepoEntry, En, Dis, Use),
    foldl(use:collect_requse_fixes(RepoEntry, En, Dis), SubDeps, [], Fixes),
    Fixes \== [], !.
use:requse_term_fixes(RepoEntry, En, Dis, required(Use), [enable(Use)]) :-
    \+ Use =.. [minus,_],
    \+ use:requse_flag_is_positive(RepoEntry, En, Dis, Use), !.
use:requse_term_fixes(RepoEntry, En, Dis, required(minus(Use)), [disable(Use)]) :-
    \+ Use =.. [minus,_],
    \+ use:requse_flag_is_negative(RepoEntry, En, Dis, Use), !.
use:requse_term_fixes(RepoEntry, En, Dis, blocking(Use), [disable(Use)]) :-
    \+ Use =.. [minus,_],
    \+ use:requse_flag_is_negative(RepoEntry, En, Dis, Use), !.
use:requse_term_fixes(RepoEntry, En, Dis, at_most_one_of_group(Deps), []) :-
    findall(1, (member(D, Deps), use:requse_term_ok_with_bwu(RepoEntry, En, Dis, D)), Sat),
    length(Sat, N), N > 1, !.
use:requse_term_fixes(_RepoEntry, _En, _Dis, _, []).


%! use:requse_pick_satisfying_flag(+Deps, -Flag)
%
% Pick a flag from a REQUIRED_USE group to enable.  Prefers flags
% already in USE defaults; falls back to the last flag in the list.

use:requse_pick_satisfying_flag(Deps, Flag) :-
    findall(F, (member(required(F), Deps), atom(F), \+ F = minus(_)), Flags),
    Flags \== [],
    ( member(F, Flags), preference:global_use(F) ->
        Flag = F
    ; last(Flags, Flag)
    ).


%! use:requse_flag_is_positive(+RepoEntry, +Enable, +Disable, +Use)
%
% True if Use is effectively positive under the current BWU state.

use:requse_flag_is_positive(RepoEntry, En, Dis, Use) :-
    ( memberchk(Use, En) -> true
    ; \+ memberchk(Use, Dis),
      use:effective_use_for_entry(RepoEntry, Use, positive)
    ).


%! use:requse_flag_is_negative(+RepoEntry, +Enable, +Disable, +Use)
%
% True if Use is effectively negative under the current BWU state.

use:requse_flag_is_negative(RepoEntry, En, Dis, Use) :-
    ( memberchk(Use, Dis) -> true
    ; \+ memberchk(Use, En),
      use:effective_use_for_entry(RepoEntry, Use, negative)
    ).


%! use:collect_requse_fixes(+RepoEntry, +Enable, +Disable, +Term, +Fixes0, -FixesOut)
%
% Fold helper: collects fixes for sub-terms of a conditional group.

use:collect_requse_fixes(RepoEntry, En, Dis, Term, Fixes0, FixesOut) :-
    ( use:requse_term_ok_with_bwu(RepoEntry, En, Dis, Term) ->
        FixesOut = Fixes0
    ; use:requse_term_fixes(RepoEntry, En, Dis, Term, NewFixes),
      NewFixes \== [] ->
        append(Fixes0, NewFixes, FixesOut)
    ; FixesOut = Fixes0
    ).


%! use:apply_requse_fix(+Fix, +BWU_In, -BWU_Out)
%
% Applies a single enable/disable fix to the BWU state, maintaining
% consistency (a flag cannot be in both Enable and Disable).

use:apply_requse_fix(enable(Flag), use_state(En0, Dis0), use_state(En1, Dis1)) :-
    ( memberchk(Flag, En0) -> En1 = En0 ; sort([Flag|En0], En1) ),
    ( select(Flag, Dis0, Dis1) -> true ; Dis1 = Dis0 ).
use:apply_requse_fix(disable(Flag), use_state(En0, Dis0), use_state(En1, Dis1)) :-
    ( memberchk(Flag, Dis0) -> Dis1 = Dis0 ; sort([Flag|Dis0], Dis1) ),
    ( select(Flag, En0, En1) -> true ; En1 = En0 ).


% =============================================================================
%  Post-BWU REQUIRED_USE validation
% =============================================================================

%! use:verify_required_use_with_bwu(+RepoEntry, +BWU)
%
% Fails when the build_with_use overrides (Enable/Disable lists) would
% violate the ebuild's REQUIRED_USE.  Called after
% build_with_use_resolve_required_use to catch irreconcilable conflicts
% (e.g. [linux] USE dep vs REQUIRED_USE=!linux).

use:verify_required_use_with_bwu(Repo://Entry, use_state(Enable, Disable)) :-
    ( Enable == [], Disable == [] -> true
    ; findall(ReqUse,
              cache:entry_metadata(Repo, Entry, required_use, ReqUse),
              AllReqUse),
      ( AllReqUse == [] -> true
      ; forall(member(Term, AllReqUse),
               use:requse_term_ok_with_bwu(Repo://Entry, Enable, Disable, Term))
      )
    ).


%! use:requse_term_ok_with_bwu(+RepoEntry, +Enable, +Disable, +Term)
%
% Succeeds when a single REQUIRED_USE term is satisfiable after
% applying the Enable/Disable overrides.

use:requse_term_ok_with_bwu(RepoEntry, Enable, Disable, required(Use)) :-
    \+ Use =.. [minus,_], !,
    ( memberchk(Use, Enable) -> true
    ; memberchk(Use, Disable) -> fail
    ; use:effective_use_for_entry(RepoEntry, Use, positive)
    ).
use:requse_term_ok_with_bwu(RepoEntry, Enable, Disable, required(minus(Use))) :-
    \+ Use =.. [minus,_], !,
    ( memberchk(Use, Disable) -> true
    ; memberchk(Use, Enable) -> fail
    ; use:effective_use_for_entry(RepoEntry, Use, negative)
    ).
use:requse_term_ok_with_bwu(RepoEntry, Enable, Disable, blocking(Use)) :-
    \+ Use =.. [minus,_], !,
    ( memberchk(Use, Disable) -> true
    ; memberchk(Use, Enable) -> fail
    ; use:effective_use_for_entry(RepoEntry, Use, negative)
    ).
use:requse_term_ok_with_bwu(RepoEntry, Enable, Disable,
                        use_conditional_group(positive, Use, _, SubDeps)) :- !,
    ( ( memberchk(Use, Enable) -> true
      ; \+ memberchk(Use, Disable),
        use:effective_use_for_entry(RepoEntry, Use, positive)
      )
    -> forall(member(D, SubDeps),
              use:requse_term_ok_with_bwu(RepoEntry, Enable, Disable, D))
    ; true
    ).
use:requse_term_ok_with_bwu(RepoEntry, Enable, Disable,
                        use_conditional_group(negative, Use, _, SubDeps)) :- !,
    ( ( memberchk(Use, Disable) -> true
      ; \+ memberchk(Use, Enable),
        use:effective_use_for_entry(RepoEntry, Use, negative)
      )
    -> forall(member(D, SubDeps),
              use:requse_term_ok_with_bwu(RepoEntry, Enable, Disable, D))
    ; true
    ).
use:requse_term_ok_with_bwu(RepoEntry, Enable, Disable, any_of_group(Deps)) :- !,
    member(D, Deps),
    use:requse_term_ok_with_bwu(RepoEntry, Enable, Disable, D), !.
use:requse_term_ok_with_bwu(RepoEntry, Enable, Disable, exactly_one_of_group(Deps)) :- !,
    findall(1, (member(D, Deps),
                use:requse_term_ok_with_bwu(RepoEntry, Enable, Disable, D)),
            Sat),
    length(Sat, 1).
use:requse_term_ok_with_bwu(RepoEntry, Enable, Disable, at_most_one_of_group(Deps)) :- !,
    findall(1, (member(D, Deps),
                use:requse_term_ok_with_bwu(RepoEntry, Enable, Disable, D)),
            Sat),
    length(Sat, N), N =< 1.
use:requse_term_ok_with_bwu(_, _, _, _).


%! use:describe_required_use_violation(+RepoEntry, +BWU, -Description)
%
% Collects the REQUIRED_USE terms that are violated by the build_with_use
% overrides and produces a structured description for the assumption printer.

use:describe_required_use_violation(Repo://Entry, use_state(Enable, Disable), Desc) :-
    findall(Term,
            ( cache:entry_metadata(Repo, Entry, required_use, Term),
              \+ use:requse_term_ok_with_bwu(Repo://Entry, Enable, Disable, Term)
            ),
            Violated),
    Desc = required_use_violation(Repo://Entry, Enable, Disable, Violated).


% =============================================================================
%  Cross-dependency BWU REQUIRED_USE conflict detection
% =============================================================================

%! use:check_bwu_cross_dep(+C, +N, +RepoEntry, +BWU)
%
% Detects irreconcilable REQUIRED_USE conflicts across independent dependency
% branches.  Uses a memo to track committed BWU per (C,N).

use:check_bwu_cross_dep(C, N, RepoEntry, BWU) :-
    ( BWU \= use_state([], []) ->
        ( memo:candidate_bwu_(C, N, OldBWU) ->
            ( feature_unification:val_hook(OldBWU, BWU, MergedBWU) ->
                ( use:verify_required_use_with_bwu(RepoEntry, MergedBWU) ->
                    retractall(memo:candidate_bwu_(C, N, _)),
                    assertz(memo:candidate_bwu_(C, N, MergedBWU))
                ; use:describe_required_use_violation(RepoEntry, MergedBWU, ViolDesc),
                  ( \+ memo:requse_violation_(C, N, _) ->
                      assertz(memo:requse_violation_(C, N, ViolDesc))
                  ; true
                  ),
                  fail
                )
            ; use:compute_ed_conflict_desc(OldBWU, BWU, ViolDesc),
              ( \+ memo:requse_violation_(C, N, _) ->
                  assertz(memo:requse_violation_(C, N, ViolDesc))
              ; true
              ),
              fail
            )
        ; assertz(memo:candidate_bwu_(C, N, BWU))
        )
    ; true
    ).


%! use:clear_bwu_cross_dep_memos
%
% Cleans up candidate_bwu_ memos.  Called at proof initialization.

use:clear_bwu_cross_dep_memos :-
    retractall(memo:candidate_bwu_(_, _, _)).


%! use:check_bwu_ed_conflict(+C, +N, +Context)
%
% Lightweight Enable/Disable conflict check for grouped_package_dependency.

use:check_bwu_ed_conflict(C, N, Context) :-
    ( use:context_build_with_use_state(Context, BWU),
      BWU \= use_state([], []) ->
        ( memo:candidate_bwu_(C, N, OldBWU) ->
            ( feature_unification:val_hook(OldBWU, BWU, _) ->
                true
            ; use:compute_ed_conflict_desc(OldBWU, BWU, ViolDesc),
              ( \+ memo:requse_violation_(C, N, _) ->
                  assertz(memo:requse_violation_(C, N, ViolDesc))
              ; true
              ),
              fail
            )
        ; true
        )
    ; true
    ).


%! use:compute_ed_conflict_desc(+OldBWU, +NewBWU, -ViolDesc)
%
% Computes a use_flag_conflict descriptor from two incompatible BWU states.

use:compute_ed_conflict_desc(use_state(OldEn, OldDis), use_state(NewEn, NewDis),
                               use_flag_conflict(Conflicts, AllEn, AllDis)) :-
    ord_union(OldEn, NewEn, AllEn),
    ord_union(OldDis, NewDis, AllDis),
    ord_intersection(AllEn, AllDis, Conflicts).


%! use:find_dep_slot_conflict(+C, +N, -SlotConflictDesc)
%
% Checks whether a slot conflict memo exists for any dependency of (C,N).

use:find_dep_slot_conflict(C, N, slot_conflict_info(ConflictC, ConflictN, ConflictData)) :-
    memo:slot_conflict_(ConflictC, ConflictN, ConflictData),
    query:search([category(C), name(N)], Repo://Entry),
    use:candidate_depends_on(Repo://Entry, ConflictC, ConflictN),
    !.
use:find_dep_slot_conflict(_C, _N, slot_conflict_info(ConflictC, ConflictN, ConflictData)) :-
    memo:slot_conflict_(ConflictC, ConflictN, ConflictData),
    !.


%! use:candidate_depends_on(+RepoEntry, +DepC, +DepN)
%
% True if RepoEntry has any dependency on category DepC, name DepN.

use:candidate_depends_on(Repo://Entry, DepC, DepN) :-
    member(Phase, [depend, rdepend, bdepend, pdepend, idepend]),
    cache:entry_metadata(Repo, Entry, Phase,
                         package_dependency(_, _, DepC, DepN, _, _, _, _)),
    !.