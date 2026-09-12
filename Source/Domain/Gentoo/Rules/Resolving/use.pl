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
The rule/2 clauses in resolving.pl delegate USE decisions here: effective USE
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

% =============================================================================
%  USE declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Optional unify.pl extension hook (generic)
% -----------------------------------------------------------------------------
%
% Merge two use_state/2 compound terms by taking the union of their
% enable/disable sets.  Fails when a flag appears in both sets (conflict).
% This hook is called by feature_unification:val/3 (CASE 0) and is critical
% for the prescience mechanism: sampler:ctx_union must be able to merge
% build_with_use proof-context values when a literal is re-proven with a
% changed ?{Context} list.

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


% -----------------------------------------------------------------------------
%  Effective USE in proof context
% -----------------------------------------------------------------------------

%! use:effective_use_in_context(+Context, +Use, -State)
%
% Determine the effective state of USE flag Use for the ebuild identified
% by the `self/1` term in the ?{Context} proof-context list. State is
% unified with `positive` or `negative`. Delegates to
% effective_use_for_entry/3, which implements the precedence chain and
% memoizes in memo:eff_use_cache_/4.

use:effective_use_in_context(Context, Use, State) :-
  memberchk(self(RepoEntry), Context),
  use:effective_use_for_entry(RepoEntry, Use, State).

%! use:effective_use_for_entry(+RepoEntry, +Use, -State)
%
% Like effective_use_in_context/3 but takes a direct repo entry instead
% of extracting it from a context. Used by use_conditional_group rules
% for the ebuild that owns the conditional. This is the single
% implementation of the USE precedence chain (variant override ->
% package use.mask/force -> global use.mask/use.force -> userconfig
% per-CN -> userconfig match -> profile soft -> global USE -> IUSE
% default).
%
% Global use.mask/use.force beat soft package.use (profile or user): a
% profile `package.use` line cannot enable a use.mask'd flag (Portage;
% e.g. abi_x86_32 on non-multilib amd64). Without this, optenable
% `[abi_x86_32(-)?]` on clang-runtime spuriously forced abi_x86_32 onto
% compiler-rt and reported use_dep_unsat.
%
% When a flag is both globally forced and masked (Gentoo arch/base
% `big-endian`), use.mask wins — matching profile:profile_finalize/2
% and Portage. Checking force before mask would enable the flag and
% break strict binpkg USE matching (#113).

use:effective_use_for_entry(RepoEntry0, Use, State) :-
  RepoEntry0 = Repo://Id,
  Use \= minus(_),
  ( memo:eff_use_cache_(Repo, Id, Use, Cached) ->
      State = Cached
  ;
  use:entry_iuse_default(Repo://Id, Use, Default),
  cache:ordered_entry(Repo, Id, C, N, _),
      ( variant:use_overridden(C, N, Use, Eff) ->
          true
      ; use:profile_hard_use_state(Repo://Id, Use, Eff) ->
          true
      ; preference:profile_masked_use_flag(Use) ->
          Eff = negative
      ; preference:profile_forced_use_flag(Use) ->
          Eff = positive
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


%! use:profile_hard_use_state(+RepoEntry, +Use, -State) is semidet.
%
% Package-level profile use.mask/force for an entry. A global use.mask
% beats package.use.force (flag stays masked), matching
% eapi:categorize_use_for_entry/4.

use:profile_hard_use_state(RepoEntry, Use, State) :-
  preference:profile_use_hard(RepoEntry, Use, State0, Reason0),
  \+ ( State0 == positive,
       Reason0 == profile_package_use_force,
       preference:profile_masked_use_flag(Use)
     ),
  State = State0.


% -----------------------------------------------------------------------------
%  Per-entry IUSE default map
% -----------------------------------------------------------------------------

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
              ; eapi:use_flag_name(Raw, U),
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


% -----------------------------------------------------------------------------
%  Per-entry IUSE memoization
% -----------------------------------------------------------------------------

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
              eapi:use_flag_name(Raw, U)
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


% -----------------------------------------------------------------------------
%  Build-with-use state management
% -----------------------------------------------------------------------------

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


%! use:dep_walk_context(+R, +BResolved, +Model0, -Model)
%
% Build a dep-walk Context whose `build_with_use` reflects BResolved
% PLUS the REQUIRED_USE-driven flag changes derived from R (the
% prover's REQUIRED_USE proof keys). This closes the REQUIRED_USE →
% conditional-dep gap: when REQUIRED_USE forces a flag ON for a
% package, conditional dep groups gated by that flag must expand
% under the new state. Without this, the downstream
% `model(dependency(_,_)):config?{Model0}` walks the conditionals
% under the *original* BWU and silently drops the activated branches,
% producing a plan that builds the package but misses its now-required
% runtime/build dependencies.
%
% Why drive off R (not the rules-side stabiliser)?
% R encodes only the assumptions the prover actually had to make to
% satisfy REQUIRED_USE. Reusing the rules-side stabilisation loop
% (`stabilize_required_use`) on an empty input introduces unwanted
% chain effects: e.g. for net-fs/samba, `gpg?(addc)` would force addc
% on (because gpg is in global_use) even though gpg is never enabled
% on the actual VM, and then `!ads?(!addc)` would flip it back.
% Trusting R keeps us aligned with the prover's view of what flags
% will actually change for this package, with no extra speculation.
% Group-level leftover conflicts (`assumed(conflict(required_use, ^^))`)
% are interpreted against BResolved: if stabilize already chose a
% member, do not invent a sibling via last-flag fallback (portage-ng#120).
%
% Examples (observed in the all-packages matrix):
%   - app-admin/fluentd: REQUIRED_USE=||(ruby_targets_ruby32) →
%     ruby_targets_ruby32 must be enabled, but global_use does not
%     set it (RUBY_TARGETS empty in make.conf). Without this fix,
%     dev-lang/ruby:3.2 + dev-ruby/* are dropped from the plan.
%   - x11-misc/xdg-utils: parent xdg-utils gates xmlto[text(+)],
%     which flips xmlto's text USE; xmlto's RDEPEND has
%     `text? ( || (virtual/w3m ...) )` that needs the flipped state
%     to pull a text-mode browser.

use:dep_walk_context(R, BResolved, Model0, Model) :-
  use:model_required_use_changes(R, BResolved, Changes),
  use:apply_use_changes_to_state(Changes, BResolved, BWUEff),
  ( select(build_with_use:_, Model0, Rest) -> true ; Rest = Model0 ),
  Model = [build_with_use:BWUEff | Rest].


%! use:apply_use_changes_to_state(+Changes, +BWU_In, -BWU_Out)
%
% Fold a list of `use_change(Flag, enable|disable)` into a BWU state.
% enable/disable are mutually exclusive: enabling a flag also removes
% it from Disable, and vice versa.

use:apply_use_changes_to_state([], BWU, BWU) :- !.
use:apply_use_changes_to_state([use_change(F, enable)|T], use_state(En0, Dis0), Out) :-
  ( memberchk(F, En0) -> En1 = En0 ; sort([F|En0], En1) ),
  ( select(F, Dis0, Dis1) -> true ; Dis1 = Dis0 ),
  use:apply_use_changes_to_state(T, use_state(En1, Dis1), Out).
use:apply_use_changes_to_state([use_change(F, disable)|T], use_state(En0, Dis0), Out) :-
  ( memberchk(F, Dis0) -> Dis1 = Dis0 ; sort([F|Dis0], Dis1) ),
  ( select(F, En0, En1) -> true ; En1 = En0 ),
  use:apply_use_changes_to_state(T, use_state(En1, Dis1), Out).


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
%! use:model_required_use_changes(+ModelKeys, +BWU, -Changes)
%
% Extract USE flag changes that the REQUIRED_USE model proof had to assume.
% ModelKeys is the R list from query:search(model(_,required_use(R),_), ...).
% Returns use_change(Flag, enable|disable) for each assumption.
% Handles both individual flag assumptions and group-level REQUIRED_USE
% assumptions (exactly_one_of_group, any_of_group, at_most_one_of_group).
%
% The BWU-aware form skips a group-conflict pick when BWU already
% enables a member of that group, so a leftover `^^` assumption cannot
% invent a sibling (portage-ng#120). The 2-argument form uses an empty
% BWU and keeps the historical last-member fallback.

use:model_required_use_changes(ModelKeys, Changes) :-
    use:model_required_use_changes(ModelKeys, use_state([], []), Changes).


use:model_required_use_changes(ModelKeys, BWU, Changes) :-
    findall(Change,
            ( member(A, ModelKeys),
              use:model_assumption_to_change(A, BWU, Change)
            ),
            Changes).


use:model_assumption_to_change(A, Change) :-
    use:model_assumption_to_change(A, use_state([], []), Change).


use:model_assumption_to_change(assumed(Use), _BWU, use_change(Use, enable)) :-
    atom(Use), \+ Use = minus(_).
use:model_assumption_to_change(assumed(minus(Use)), _BWU, use_change(Use, disable)) :-
    atom(Use), \+ Use = minus(_).
use:model_assumption_to_change(assumed(conflict(required, Use)), _BWU, use_change(Use, enable)) :-
    atom(Use), \+ Use = minus(_).
use:model_assumption_to_change(assumed(conflict(required, minus(Use))), _BWU, use_change(Use, disable)) :-
    atom(Use), \+ Use = minus(_).
use:model_assumption_to_change(assumed(conflict(blocking, minus(Use))), _BWU, use_change(Use, enable)) :-
    atom(Use), \+ Use = minus(_).
use:model_assumption_to_change(assumed(conflict(blocking, Use)), _BWU, use_change(Use, disable)) :-
    atom(Use), \+ Use = minus(_).
use:model_assumption_to_change(assumed(conflict(required_use, exactly_one_of_group(Deps))),
                               use_state(En, Dis),
                               use_change(Flag, enable)) :-
    \+ use:bwu_covers_required_use_member(En, Dis, Deps),
    use:required_use_group_pick_flag(Deps, Flag).
use:model_assumption_to_change(assumed(conflict(required_use, any_of_group(Deps))),
                               use_state(En, Dis),
                               use_change(Flag, enable)) :-
    \+ use:bwu_covers_required_use_member(En, Dis, Deps),
    use:required_use_group_pick_flag(Deps, Flag).
use:model_assumption_to_change(assumed(conflict(required_use, at_most_one_of_group(Deps))),
                               use_state(En, Dis),
                               use_change(Flag, disable)) :-
    \+ use:bwu_covers_required_use_member(En, Dis, Deps),
    use:required_use_group_excess_flags(Deps, Flag).


%! use:bwu_covers_required_use_member(+Enable, +Disable, +Deps) is semidet.
%
% True when at least one required(F) member of Deps is already enabled
% in the BWU state. Keeps leftover REQUIRED_USE group-conflict
% assumptions from inventing a second ^^ / || member (portage-ng#120).

use:bwu_covers_required_use_member(En, Dis, Deps) :-
    member(required(F), Deps),
    atom(F),
    \+ F = minus(_),
    memberchk(F, En),
    \+ memberchk(F, Dis).


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


% -----------------------------------------------------------------------------
%  Proof-context helpers for per-package USE (build_with_use)
% -----------------------------------------------------------------------------

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


% -----------------------------------------------------------------------------
%  Self-entry USE state (from ?{Context} list)
% -----------------------------------------------------------------------------

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
              eapi:use_flag_name(Arg, Use),
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
    eapi:use_flag_name(UEArg, UEArgB),
    eapi:check_prefix_atom(Prefix, UEArgB),
    eapi:strip_prefix_atom(Prefix, UEArgB, Value)
  ).


% -----------------------------------------------------------------------------
%  USE-dependency requirement resolution
% -----------------------------------------------------------------------------

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


% -----------------------------------------------------------------------------
%  Candidate USE-dependency enforcement
% -----------------------------------------------------------------------------

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


% -----------------------------------------------------------------------------
%  Candidate effective USE evaluation
% -----------------------------------------------------------------------------

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
  ( use:profile_hard_use_state(Repo://Entry, Use, positive) ->
      true
  ; use:profile_hard_use_state(Repo://Entry, Use, negative) ->
      fail
  ; % Global use.mask beats use.force (arch/base big-endian pattern).
    preference:profile_masked_use_flag(Use) ->
      fail
  ; preference:profile_forced_use_flag(Use) ->
      true
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


% -----------------------------------------------------------------------------
%  Installed package USE satisfaction checks
% -----------------------------------------------------------------------------

%! use:installed_pkg_satisfies_use_reqs(+ParentCtx, +Installed, +UseDeps)
%
% True if the installed package satisfies all USE requirements in UseDeps.
% Uses the VDB's recorded USE state rather than effective USE.

use:installed_pkg_satisfies_use_reqs(_ParentContext, _Installed, []) :- !.
use:installed_pkg_satisfies_use_reqs(ParentContext, VdbRepo://InstalledId,
                                    [use(Directive, Default)|Rest]) :-
  !,
  use:use_dep_requirement(ParentContext, Directive, Default, Req),
  use:installed_pkg_satisfies_use_requirement(VdbRepo://InstalledId, Req),
  use:installed_pkg_satisfies_use_reqs(ParentContext, VdbRepo://InstalledId, Rest).
use:installed_pkg_satisfies_use_reqs(ParentContext, Installed, [_|Rest]) :-
  use:installed_pkg_satisfies_use_reqs(ParentContext, Installed, Rest).

%! use:installed_pkg_satisfies_use_requirement(+Installed, +Requirement)
%
% Check a single USE requirement against an installed package's VDB USE.

use:installed_pkg_satisfies_use_requirement(_Installed, none) :- !.
use:installed_pkg_satisfies_use_requirement(VdbRepo://InstalledId, requirement(enable, Use, _Default)) :-
  query:search(use(Use), VdbRepo://InstalledId),
  !.
use:installed_pkg_satisfies_use_requirement(VdbRepo://InstalledId, requirement(disable, Use, _Default)) :-
  \+ query:search(use(Use), VdbRepo://InstalledId),
  !.


% -----------------------------------------------------------------------------
%  Build-with-use constraint satisfaction
% -----------------------------------------------------------------------------

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
            U \= minus(_)
          ),
          En0),
  findall(U,
          ( ( member(naf(required(U)), BuildWithUse)
            ; member(assumed(minus(U)), BuildWithUse)
            ),
            U \= minus(_)
          ),
          Dis0),
  sort(En0, MustEnable),
  sort(Dis0, MustDisable).

%! use:installed_entry_satisfies_build_with_use(+Installed, +Context)
%
% True if the installed package's built USE state satisfies the
% build_with_use constraints in Context. Flags not in the package's
% IUSE are ignored (they cannot influence the build).

use:installed_entry_satisfies_build_with_use(VdbRepo://InstalledEntry, Context) :-
  use:context_build_with_use_state(Context, State),
  use:build_with_use_requirements(State, MustEnable, MustDisable),
  use:vdb_enabled_use_set(VdbRepo://InstalledEntry, BuiltUse),
  use:vdb_iuse_set(VdbRepo://InstalledEntry, BuiltIuse),
  forall(member(U, MustEnable),
         ( memberchk(U, BuiltIuse) -> memberchk(U, BuiltUse)
         ; true
         )),
  forall(member(U, MustDisable),
         ( memberchk(U, BuiltIuse) -> \+ memberchk(U, BuiltUse)
         ; true
         )).


%! use:installed_entry_satisfies_use_change(+Installed, +Changes)
%
% True if the installed package's built USE state already satisfies every
% `use_change(Flag, enable|disable)` in Changes. Flags not in the package's
% recorded IUSE are ignored (they cannot influence the build). Mirrors the
% semantics of installed_entry_satisfies_build_with_use/2 but for the
% resolver's suggestion(use_change) self-flips rather than bracketed USE.

use:installed_entry_satisfies_use_change(_Installed, []) :- !.
use:installed_entry_satisfies_use_change(VdbRepo://InstalledEntry, Changes) :-
  use:vdb_enabled_use_set(VdbRepo://InstalledEntry, BuiltUse),
  use:vdb_iuse_set(VdbRepo://InstalledEntry, BuiltIuse),
  forall(member(use_change(F, enable), Changes),
         ( memberchk(F, BuiltIuse) -> memberchk(F, BuiltUse)
         ; true
         )),
  forall(member(use_change(F, disable), Changes),
         ( memberchk(F, BuiltIuse) -> \+ memberchk(F, BuiltUse)
         ; true
         )).


%! use:installed_entry_satisfies_plan_use(+Installed, +SrcEntry, +Context)
%
% True if the installed package's built USE state satisfies BOTH the
% bracketed `build_with_use` constraints AND any self-targeted
% `suggestion(use_change, SrcEntry, Changes)` recorded in Context.
%
% This is the guard the :install / :run rules consult before short-
% circuiting an already-installed package to a no-op. Checking
% build_with_use alone was insufficient: when the prover records a USE
% flip purely as a suggestion(use_change) (e.g. a REQUIRED_USE pick, or a
% bracketed-USE requirement that reached the entry via the per-(C,N) memo
% rather than this literal's own build_with_use term), the build_with_use
% state on this exact context can be empty and the short-circuit would
% wrongly report the installed -USE build as satisfactory. That left
% candidate:update_requires_use_rebuild/2 (which DOES honour
% suggestion(use_change)) unreachable, so the transactional :update that
% walks DEPEND/BDEPEND under the flipped USE was never scheduled
% (portage-ng#85).
%
% SrcEntry is the source-tree literal whose suggestion(use_change) tags
% refer to this package; only suggestions keyed to SrcEntry are honoured
% so a suggestion meant for a different (introduced) candidate cannot
% spuriously force a rebuild here.

use:installed_entry_satisfies_plan_use(VdbRepo://InstalledEntry, SrcRepo://SrcEntry, Context) :-
  use:installed_entry_satisfies_build_with_use(VdbRepo://InstalledEntry, Context),
  ( memberchk(suggestion(use_change, SrcRepo://SrcEntry, Changes), Context)
  -> use:installed_entry_satisfies_use_change(VdbRepo://InstalledEntry, Changes)
  ;  true
  ).


% -----------------------------------------------------------------------------
%  --newuse / --changed-use support
% -----------------------------------------------------------------------------

%! use:newuse_mismatch(+InstalledEntry)
%
% True if the installed package has a USE mismatch compared to the
% currently effective USE for the same version in the repo set.
% Checks both enabled USE and declared IUSE for changes.
% Used to implement `--newuse` / `-N` rebuild semantics.

use:newuse_mismatch(VdbRepo://InstalledEntry) :-
  query:search([category(C),name(N),version(V)], VdbRepo://InstalledEntry),
  preference:accept_keywords(K),
  ( query:search([select(repository,notequal,pkg),category(C),name(N),keywords(K),version(V)],
                 CurRepo://CurEntry)
  -> use:newuse_mismatch(VdbRepo://InstalledEntry, CurRepo://CurEntry)
  ;  fail
  ).

%! use:newuse_mismatch(+InstalledEntry, +RepoEntry)
%
% True if the installed package's built USE or IUSE differs from the
% current repo entry's effective USE or IUSE. Checks both the enabled
% USE set and the declared IUSE set for symmetric differences.

use:newuse_mismatch(VdbRepo://InstalledEntry, CurRepo://CurEntry) :-
  use:vdb_enabled_use_set(VdbRepo://InstalledEntry, BuiltUse),
  use:entry_enabled_use_set(CurRepo://CurEntry, CurUse),
  ( use:symmetric_diff_nonempty(BuiltUse, CurUse)
  ; use:vdb_iuse_set(VdbRepo://InstalledEntry, BuiltIuse),
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

use:changeduse_mismatch(VdbRepo://InstalledEntry) :-
  query:search([category(C),name(N),version(V)], VdbRepo://InstalledEntry),
  preference:accept_keywords(K),
  ( query:search([select(repository,notequal,pkg),category(C),name(N),keywords(K),version(V)],
                 CurRepo://CurEntry)
  -> use:changeduse_mismatch(VdbRepo://InstalledEntry, CurRepo://CurEntry)
  ;  fail
  ).


%! use:changeduse_mismatch(+InstalledEntry, +RepoEntry)
%
% True if the installed package's built USE set differs from the
% current repo entry's effective USE set. Only compares the enabled
% flag sets, ignoring IUSE changes.

use:changeduse_mismatch(VdbRepo://InstalledEntry, CurRepo://CurEntry) :-
  use:vdb_enabled_use_set(VdbRepo://InstalledEntry, BuiltUse),
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
            eapi:use_flag_name(Value, U)
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
            eapi:use_flag_name(Value, U)
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


% -----------------------------------------------------------------------------
%  REQUIRED_USE helpers
% -----------------------------------------------------------------------------

%! use:required_use_term_satisfied(+Context, +Term)
%
% Recursively check whether a REQUIRED_USE term is satisfied by the
% effective USE state for the ebuild identified by self/1 in Context.
% Handles required/1, use_conditional_group/4, any_of_group/1,
% exactly_one_of_group/1, and at_most_one_of_group/1.

use:required_use_term_satisfied(Ctx, required(Use)) :-
  Use \= minus(_),
  use:effective_use_in_context(Ctx, Use, positive),
  !.
use:required_use_term_satisfied(Ctx, required(minus(Use))) :-
  Use \= minus(_),
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
  aggregate_all(count, (member(D, Deps), use:required_use_term_satisfied(Ctx, D)), 1),
  !.
use:required_use_term_satisfied(Ctx, at_most_one_of_group(Deps)) :-
  aggregate_all(count, (member(D, Deps), use:required_use_term_satisfied(Ctx, D)), N),
  N =< 1,
  !.


% -----------------------------------------------------------------------------
%  Build-with-use / REQUIRED_USE compatibility
% -----------------------------------------------------------------------------

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


% -----------------------------------------------------------------------------
%  Post-BWU REQUIRED_USE stabilization
% -----------------------------------------------------------------------------
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
    findall(ReqUse,
            cache:entry_metadata(Repo, Entry, required_use, ReqUse),
            AllReqUse),
    ( AllReqUse == [] ->
        BWU_Out = BWU_In
    ; BWU_In == use_state([], []) ->
        use:stabilize_required_use_seed(Repo://Entry, AllReqUse, BWU_In, BWU_Out)
    ; use:stabilize_required_use_loop(Repo://Entry, AllReqUse, BWU_In, BWU_Out, 5)
    ).


%! use:stabilize_required_use_seed(+RepoEntry, +AllReqUse, +BWU_In, -BWU_Out)
%
% Empty-BWU stabilization entry point. The package was pulled with no
% bracketed USE directives, so its build_with_use is empty. If its own
% REQUIRED_USE contains an *unsatisfied* choice group (any_of `||` or
% exactly_one_of `^^`) under the current effective USE, seed it by
% enabling the highest-priority member, then run the normal fixed-point
% loop to resolve the cascading implications of that committed choice.
%
% Speculation from empty BWU is deliberately restricted to choice
% groups. Conditional (`use? ( ... )`) and plain `required(Flag)`
% implications are NOT seeded here, because flipping them from a global
% USE state causes the chain-effects documented in dep_walk_context/4
% (e.g. net-fs/samba `gpg? ( addc )`). A choice group, by contrast,
% encodes a genuine "pick at least one" requirement that has no
% satisfying assignment under the profile defaults, so enabling the
% preferred member is the actionable resolution (surfaced downstream as
% a positive `suggestion(use_change)`).

use:stabilize_required_use_seed(RepoEntry, AllReqUse, BWU_In, BWU_Out) :-
    use:seed_choice_groups_loop(RepoEntry, AllReqUse, BWU_In, BWUSeed, 5),
    ( BWUSeed == BWU_In ->
        BWU_Out = BWU_In
    ; use:verify_required_use_with_bwu(RepoEntry, BWUSeed) ->
        BWU_Out = BWUSeed
    ; % Seeding the choice group alone cannot satisfy the full REQUIRED_USE
      % (e.g. net-fs/samba's `gpg? ( addc )` chain, where forcing the python
      % single-target leaves a conditional that only the prover's use_change
      % machinery can resolve). Committing a non-empty-but-inconsistent BWU
      % would push the entry down the strict verification path and hard-fail
      % it; instead leave the BWU empty so the proof proceeds exactly as for
      % a package whose choice group was already satisfied by the profile,
      % surfacing a graceful suggestion(use_change) downstream.
      BWU_Out = BWU_In
    ).


%! use:seed_choice_groups_loop(+RepoEntry, +AllReqUse, +BWU_In, -BWU_Out, +Limit)
%
% Fixed-point iteration restricted to choice-group seeding. Unlike
% stabilize_required_use_loop/5 (used on the non-empty BWU path), this
% deliberately does NOT apply conditional/required fixes: from an empty
% BWU those would flip flags away from the profile defaults and trigger
% the `gpg? ( addc )`-style chain effects called out above. Seeding a
% choice group can, however, satisfy or unsatisfy another choice group,
% so we re-run until the choice-group seed reaches a fixpoint (or Limit
% is hit). Conditional implications of the committed choice are left to
% the prover's use_change machinery, exactly as for a package whose
% choice group was already satisfied by the profile.

use:seed_choice_groups_loop(_RepoEntry, _AllReqUse, BWU, BWU, 0) :- !.
use:seed_choice_groups_loop(RepoEntry, AllReqUse, BWU_In, BWU_Out, Limit) :-
    foldl(use:seed_choice_group_term(RepoEntry), AllReqUse, BWU_In, BWU_Mid),
    ( BWU_Mid == BWU_In ->
        BWU_Out = BWU_In
    ; Limit1 is Limit - 1,
      use:seed_choice_groups_loop(RepoEntry, AllReqUse, BWU_Mid, BWU_Out, Limit1)
    ).


%! use:seed_choice_group_term(+RepoEntry, +Term, +BWU_In, -BWU_Out)
%
% Fold helper: if Term is an unsatisfied choice group, enable its
% highest-priority member; otherwise pass the BWU through unchanged.

use:seed_choice_group_term(RepoEntry, Term, BWU_In, BWU_Out) :-
    BWU_In = use_state(En, Dis),
    ( use:choice_group_needs_seed(RepoEntry, En, Dis, Term, Flag) ->
        use:apply_requse_fix(enable(Flag), BWU_In, BWU_Out)
    ; BWU_Out = BWU_In
    ).


%! use:choice_group_needs_seed(+RepoEntry, +En, +Dis, +Term, -Flag)
%
% True when Term is a top-level choice group (any_of `||` or
% exactly_one_of `^^`) with no satisfied member under the current
% Enable/Disable state, binding Flag to the member to enable.
% at_most_one_of is excluded (zero members is a valid assignment, so it
% never needs seeding); nested choices inside conditionals are excluded
% to keep empty-BWU speculation conservative.

use:choice_group_needs_seed(RepoEntry, En, Dis, any_of_group(Deps), Flag) :-
    \+ ( member(D, Deps), use:requse_term_ok_with_bwu(RepoEntry, En, Dis, D) ),
    use:requse_pick_satisfying_flag(RepoEntry, Deps, Flag).
use:choice_group_needs_seed(RepoEntry, En, Dis, exactly_one_of_group(Deps), Flag) :-
    \+ ( member(D, Deps), use:requse_term_ok_with_bwu(RepoEntry, En, Dis, D) ),
    use:requse_pick_satisfying_flag(RepoEntry, Deps, Flag).


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

use:requse_term_fixes(RepoEntry, _En, _Dis, any_of_group(Deps), [enable(Flag)]) :-
    use:requse_pick_satisfying_flag(RepoEntry, Deps, Flag), !.
% Exactly-one-of with multiple members currently positive (portage-ng#111):
% keep HARD-forced Enable flags; disable every other satisfied sibling so
% stabilize can reach a legal ^^ assignment. When two HARD enables collide
% Fixes stays empty and post-stabilize verify fails closed.
use:requse_term_fixes(RepoEntry, En, Dis, exactly_one_of_group(Deps), Fixes) :-
    findall(Flag,
            ( member(required(Flag), Deps),
              use:requse_term_ok_with_bwu(RepoEntry, En, Dis, required(Flag))
            ),
            SatFlags),
    length(SatFlags, N), N > 1, !,
    findall(disable(Other),
            ( member(Other, SatFlags),
              \+ memberchk(Other, En)
            ),
            Fixes0),
    Fixes0 \== [],
    Fixes = Fixes0.
use:requse_term_fixes(RepoEntry, En, Dis, exactly_one_of_group(Deps), [enable(Flag)]) :-
    aggregate_all(count, (member(D, Deps), use:requse_term_ok_with_bwu(RepoEntry, En, Dis, D)), 0),
    use:requse_pick_satisfying_flag(RepoEntry, Deps, Flag), !.
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
    Use \= minus(_),
    \+ use:requse_flag_is_positive(RepoEntry, En, Dis, Use), !.
use:requse_term_fixes(RepoEntry, En, Dis, required(minus(Use)), [disable(Use)]) :-
    Use \= minus(_),
    \+ use:requse_flag_is_negative(RepoEntry, En, Dis, Use), !.
use:requse_term_fixes(RepoEntry, En, Dis, blocking(Use), [disable(Use)]) :-
    Use \= minus(_),
    \+ use:requse_flag_is_negative(RepoEntry, En, Dis, Use), !.
use:requse_term_fixes(RepoEntry, En, Dis, at_most_one_of_group(Deps), []) :-
    aggregate_all(count, (member(D, Deps), use:requse_term_ok_with_bwu(RepoEntry, En, Dis, D)), N),
    N > 1, !.
use:requse_term_fixes(_RepoEntry, _En, _Dis, _, []).


%! use:requse_pick_satisfying_flag(+RepoEntry, +Deps, -Flag)
%
% Pick a flag from a REQUIRED_USE choice group to enable. Preference
% order: (1) a member already enabled in the global USE configuration,
% (2) a member declared `+` (default-on) in the package's own IUSE --
% the package's preferred backend, (3) the last listed member.

use:requse_pick_satisfying_flag(RepoEntry, Deps, Flag) :-
    findall(F, (member(required(F), Deps), atom(F), \+ F = minus(_)), AllFlags),
    AllFlags \== [],
    % Never seed a profile-masked / force-disabled flag: the profile strips
    % it back off at build time, so the ebuild would run with neither member
    % of the choice group set and die on its own REQUIRED_USE check (e.g.
    % ^^ ( elogind systemd ) on a non-systemd profile where `systemd` is
    % use-masked -- the only buildable choice is elogind). When every
    % candidate is masked the group is genuinely unsatisfiable, so fall back
    % to the full list and let the normal domain-assumption path report it.
    include(use:requse_flag_seedable(RepoEntry), AllFlags, Seedable),
    ( Seedable == [] -> Flags = AllFlags ; Flags = Seedable ),
    ( member(F, Flags), preference:global_use(F) ->
        Flag = F
    ; member(F, Flags), use:entry_iuse_plus_default(RepoEntry, F) ->
        Flag = F
    ; last(Flags, Flag)
    ).


%! use:requse_flag_seedable(+RepoEntry, +Flag) is semidet.
%
% True when Flag can actually be enabled for the entry, i.e. the profile
% does not force it off via a global USE mask or a package-level USE mask.
% Used to keep REQUIRED_USE choice-group seeding from picking a member the
% profile will strip back off (which would guarantee a build-time
% REQUIRED_USE violation).

use:requse_flag_seedable(RepoEntry, Flag) :-
    \+ preference:profile_masked_use_flag(Flag),
    \+ catch(preference:profile_use_hard(RepoEntry, Flag, negative, _), _, fail).


%! use:entry_iuse_plus_default(+RepoEntry, +Flag)
%
% True when Flag is declared with a `+` (default-on) IUSE default for
% the entry.

use:entry_iuse_plus_default(RepoEntry, Flag) :-
    use:entry_iuse_info(RepoEntry, iuse_info(_IuseSet, PlusSet)),
    memberchk(Flag, PlusSet).


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


% -----------------------------------------------------------------------------
%  Post-BWU REQUIRED_USE validation
% -----------------------------------------------------------------------------

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


%! use:bwu_respects_profile_hard(+RepoEntry, +BWU) is semidet.
%
% True when no HARD build_with_use enable/disable contradicts a profile
% use.mask / use.force (global or per-package). A HARD `[flag]` against a
% masked flag is emerge's use_dep_unsat class (portage-ng#109/#111).

use:bwu_respects_profile_hard(RepoEntry, use_state(Enable, Disable)) :-
    forall(member(F, Enable),
           ( \+ preference:profile_masked_use_flag(F),
             \+ catch(preference:profile_use_hard(RepoEntry, F, negative, _), _, fail)
           )),
    forall(member(F, Disable),
           \+ catch(preference:profile_use_hard(RepoEntry, F, positive, _), _, fail)).


%! use:describe_use_dep_unsat(+RepoEntry, +BWU, -Description)
%
% Structured descriptor for a joint USE-dep / REQUIRED_USE / profile-hard
% failure (emerge use_dep_unsat), used by the assumption printer.

use:describe_use_dep_unsat(RepoEntry, BWU, use_dep_unsat(RepoEntry, BWU, Why)) :-
    ( use:bwu_respects_profile_hard(RepoEntry, BWU)
    -> use:describe_required_use_violation(RepoEntry, BWU, Why)
    ; Why = profile_hard_conflict
    ).


%! use:use_dep_atom_satisfiable(+RepoEntry, +BWU) is semidet.
%
% Joint check after BWU resolve+stabilize: REQUIRED_USE holds and no HARD
% flag fights profile use.mask/force. Fail closed = emerge use_dep_unsat.

use:use_dep_atom_satisfiable(RepoEntry, BWU) :-
    use:bwu_respects_profile_hard(RepoEntry, BWU),
    use:verify_required_use_with_bwu(RepoEntry, BWU).


%! use:reconcile_required_use_model(+RepoEntry, +BResolved, +R0, -R) is det.
%
% After stabilize succeeds, drop leftover
% `assumed(conflict(required_use, ...))` keys that BResolved already
% resolved. The :validate model is proved against `self/1` only (no
% BWU), so a parent `[gitea]` atom plus empty profile USE records a
% `^^` conflict even though BResolved is legal (portage-ng#111).
% Leaving that key in R lets `required_use_group_pick_flag/2` invent a
% sibling enable (last member = gitolite) that the executor then
% applies (portage-ng#120).
%
% Real `assumed(Flag)` keys are kept — those are what
% `dep_walk_context/4` needs for fluentd-style `||` seeds. Empty BWU
% keeps every conflict key (stabilize has not chosen a member yet).

use:reconcile_required_use_model(RepoEntry, BResolved, R0, R) :-
    ( is_list(R0) -> RIn = R0 ; RIn = [] ),
    ( BResolved = use_state(En, Dis),
      ( En \== [] ; Dis \== [] ),
      use:verify_required_use_with_bwu(RepoEntry, BResolved)
    -> exclude(use:required_use_conflict_assumption, RIn, R)
    ; exclude(use:stale_required_use_conflict(BResolved), RIn, R)
    ).


%! use:required_use_conflict_assumption(+Term) is semidet.
%
% True for a group-level REQUIRED_USE conflict assumption.

use:required_use_conflict_assumption(assumed(conflict(required_use, _))).


%! use:stale_required_use_conflict(+BWU, +Term) is semidet.
%
% True when Term is a REQUIRED_USE group conflict whose group already
% has a member enabled in BWU (the leftover is stale relative to
% stabilize).

use:stale_required_use_conflict(use_state(En, Dis),
                               assumed(conflict(required_use, Group))) :-
    use:required_use_conflict_group_deps(Group, Deps),
    use:bwu_covers_required_use_member(En, Dis, Deps).


%! use:required_use_conflict_group_deps(+Group, -Deps) is semidet.

use:required_use_conflict_group_deps(exactly_one_of_group(Deps), Deps).
use:required_use_conflict_group_deps(any_of_group(Deps), Deps).
use:required_use_conflict_group_deps(at_most_one_of_group(Deps), Deps).


%! use:requse_term_ok_with_bwu(+RepoEntry, +Enable, +Disable, +Term)
%
% Succeeds when a single REQUIRED_USE term is satisfiable after
% applying the Enable/Disable overrides.

use:requse_term_ok_with_bwu(RepoEntry, Enable, Disable, required(Use)) :-
    Use \= minus(_), !,
    ( memberchk(Use, Enable) -> true
    ; memberchk(Use, Disable) -> fail
    ; use:effective_use_for_entry(RepoEntry, Use, positive)
    ).
use:requse_term_ok_with_bwu(RepoEntry, Enable, Disable, required(minus(Use))) :-
    Use \= minus(_), !,
    ( memberchk(Use, Disable) -> true
    ; memberchk(Use, Enable) -> fail
    ; use:effective_use_for_entry(RepoEntry, Use, negative)
    ).
use:requse_term_ok_with_bwu(RepoEntry, Enable, Disable, blocking(Use)) :-
    Use \= minus(_), !,
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
    aggregate_all(count,
                  ( member(D, Deps),
                    use:requse_term_ok_with_bwu(RepoEntry, Enable, Disable, D) ),
                  1).
use:requse_term_ok_with_bwu(RepoEntry, Enable, Disable, at_most_one_of_group(Deps)) :- !,
    aggregate_all(count,
                  ( member(D, Deps),
                    use:requse_term_ok_with_bwu(RepoEntry, Enable, Disable, D) ),
                  N),
    N =< 1.
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


% -----------------------------------------------------------------------------
%  Cross-dependency BWU aggregation (per category/name)
% -----------------------------------------------------------------------------

%! use:merge_memo_candidate_bwu(+C, +N, +BWU0, -BWU) is det.
%
% Union incoming context BWU with the per-(C,N) memo accumulated from every
% grouped_dep edge that targeted this package (bracketed USE on BDEPEND/DEPEND).
% Used when resolving a provider's :install/:run entry so early proofs without
% bracket USE still pick up requirements discovered later in the proof.

use:merge_memo_candidate_bwu(C, N, BWU0, BWU) :-
    ( memo:candidate_bwu_(C, N, BAgg) ->
        ( BWU0 == use_state([], []) ->
            BWU1 = BAgg
        ; feature_unification:val_hook(BWU0, BAgg, BWU1) ->
            true
        ; BWU1 = BWU0
        )
    ; BWU1 = BWU0
    ),
    use:apply_learned_bwu_force(C, N, BWU1, BWU).


%! use:apply_learned_bwu_force(+C, +N, +BWU0, -BWU) is det.
%
% Union any persistent `bwu_force(C,N)` learned during an earlier reprove
% attempt into BWU0 (portage-ng#91 sub-mechanism B). The learned store
% survives `clear_bwu_cross_dep_memos/0` (unlike the per-pass candidate_bwu_
% memo), so a HARD flag a consumer required *after* this provider was first
% committed (e.g. qtbase[icu]) is re-applied here on the re-proof, forcing the
% provider's :install to build with the flag. A no-op when nothing is learned.

use:apply_learned_bwu_force(C, N, use_state(En0, Dis0), use_state(En, Dis)) :-
    ( prover:learned(bwu_force(C, N), use_state(ForceEn0, _)),
      ForceEn0 \== []
    ->
        % HARD beats EQ: a forced enable overrides any soft/following disable,
        % so drop the forced flags from the disable set and add them to enables
        % rather than unioning via val_hook (which would treat enable-vs-disable
        % as an irreconcilable conflict and lose the force).
        sort(ForceEn0, ForceEn),
        sort(En0, En0s),
        sort(Dis0, Dis0s),
        ord_subtract(Dis0s, ForceEn, Dis),
        ord_union(En0s, ForceEn, En)
    ; En = En0, Dis = Dis0
    ).


%! use:shared_dep_use_forcing_enabled is semidet.
%
% Gate for the shared-dependency HARD-USE forcing pass (portage-ng#91
% sub-mechanism B). Enabled by default; set config:shared_dep_use_forcing(false)
% to disable.

use:shared_dep_use_forcing_enabled :-
    ( current_predicate(config:shared_dep_use_forcing/1) ->
        config:shared_dep_use_forcing(true)
    ; true
    ).


%! use:maybe_force_shared_dep_use(+C, +N, +RepoEntry) is det.
%
% portage-ng#91 sub-mechanism B. Detect that a consumer hard-requires
% `provider[flag]` but the provider (C,N) is *already committed* in the
% current proof pass (its :install was proved before this HARD flag was
% accumulated), so the committed USE cannot include it. Learn a persistent
% `bwu_force(C,N)` for the missing HARD flags so the provider is rebuilt with
% them on the next attempt (applied via apply_learned_bwu_force/4). Otherwise a
% no-op, so resolution continues normally.
%
% Deferred flush (portage-ng#94): a newly-learned force does NOT abort the
% pass. It is recorded in memo:bwu_force_pending_/3 and the pass continues --
% because the force is already in the learned store, apply_learned_bwu_force/4
% folds it into every subsequent BWU merge of the same pass (including this
% very edge via unify_memo_bwu_into_context/4), so the provider's :install is
% re-derived with the flag through the prover's ctx-union mechanism and the
% rest of the closure keeps resolving instead of degrading. When the pass
% completes, heuristic:reprove_pending/1 reports the pending forces and the
% prover runs ONE clean re-proof with all of them applied from the start.
% Deeper forces only exposed by that re-proof are learned on the next pass,
% so the incremental "satisfy -> re-resolve -> expose next" loop that
% guarantees convergence on deep stacks is preserved -- but at one full pass
% per *level* of the cascade instead of one aborted pass per *flag*
% (app-text/ktikz: 14 reproves -> 2). This replaced the original
% throw(prover_reprove(bwu_force(...)))-per-flag design, which doubled
% resolver:test_stats on KDE/GNOME stacks.
%
% Narrow + self-limiting: fires only for an already-committed provider, only
% for HARD (forcing) enable flags that are seedable (not profile-masked) and
% not default-on, USE_EXPAND excluded, and at most once per newly-learned flag
% set (learned-store dedup via Added). A per-(C,N) seen-set dedup
% (memo:bwu_force_seen_/3) skips the expensive per-edge recomputation when the
% provider's HARD set is unchanged within a pass. EQ (`[flag=]`) flags never
% force a rebuild -- they follow via ranking:apply_equality_pins/3.

use:maybe_force_shared_dep_use(C, N, RepoEntry) :-
    ( use:shared_dep_use_forcing_enabled,
      cnselect:cn_domain_reprove_enabled,
      cnselect:snapshot_selected_cn_candidates(C, N, _Committed),
      memo:candidate_bwu_hard_(C, N, use_state(HardEn, _)),
      HardEn \== [],
      \+ use:bwu_force_already_seen(C, N, HardEn)
    ->
        use:mark_bwu_force_seen(C, N, HardEn),
        ( use:shared_dep_force_flags(RepoEntry, HardEn, ForceEn),
          ForceEn \== [],
          prover:learn(bwu_force(C, N), use_state(ForceEn, []), Added),
          Added == true
        ->
            use:record_bwu_force_pending(C, N, ForceEn)
        ; true
        )
    ; true
    ).


%! use:record_bwu_force_pending(+C, +N, +ForceEn) is det.
%
% Record a newly-learned shared-dep USE force for the end-of-pass batched
% reprove (portage-ng#94). One fact per (C,N); a second learn for the same
% pair within a pass replaces the pending set with the merged flags.

use:record_bwu_force_pending(C, N, ForceEn) :-
    retractall(memo:bwu_force_pending_(C, N, _)),
    assertz(memo:bwu_force_pending_(C, N, ForceEn)).


%! use:bwu_force_pending_any(-Pending) is semidet.
%
% True when the current pass learned at least one new shared-dep USE force.
% Pending lists the (C,N)-force triples, for reprove diagnostics.

use:bwu_force_pending_any(Pending) :-
    findall(bwu_force(C, N, ForceEn),
            memo:bwu_force_pending_(C, N, ForceEn),
            Pending),
    Pending \== [].


%! use:bwu_force_already_seen(+C, +N, +HardEn) is semidet.
%
% True when the shared-dep USE forcing pass already processed this exact HARD
% enable set for (C,N) in the current proof pass, so it can skip recomputation.
% The HARD memo is a canonical ord-set union, so == comparison is reliable.

use:bwu_force_already_seen(C, N, HardEn) :-
    memo:bwu_force_seen_(C, N, Seen),
    Seen == HardEn.


%! use:mark_bwu_force_seen(+C, +N, +HardEn) is det.
%
% Record the HARD enable set just processed for (C,N) (one entry per pair).

use:mark_bwu_force_seen(C, N, HardEn) :-
    retractall(memo:bwu_force_seen_(C, N, _)),
    assertz(memo:bwu_force_seen_(C, N, HardEn)).


%! use:shared_dep_force_flags(+RepoEntry, +HardEn, -ForceEn) is det.
%
% From the accumulated HARD enable flags, keep those a committed provider
% would not already carry: not default-on (`+`) in IUSE, and seedable (the
% profile does not force them off). These are the flags worth forcing a
% provider rebuild for.

use:shared_dep_force_flags(RepoEntry, HardEn, ForceEn) :-
    findall(F,
            ( member(F, HardEn),
              \+ use:is_use_expand_flag(F),
              \+ use:entry_iuse_plus_default(RepoEntry, F),
              use:requse_flag_seedable(RepoEntry, F)
            ),
            ForceEn0),
    sort(ForceEn0, ForceEn).


%! use:is_use_expand_flag(+Flag) is semidet.
%
% True when Flag is a USE_EXPAND-derived flag (e.g. python_targets_python3_14,
% abi_x86_64, cpu_flags_x86_sse2). These are managed by their eclasses /
% multilib handling, so the shared-dep HARD-USE forcing pass leaves them to the
% normal resolution path rather than learning a persistent bwu_force for them.

use:is_use_expand_flag(Flag) :-
    eapi:use_expand(Prefix),
    atom_concat(Prefix, '_', PrefixUnderscore),
    atom_concat(PrefixUnderscore, _, Flag),
    !.


%! use:unify_memo_bwu_into_context(+C, +N, +Ctx0, -Ctx) is det.
%
% Merge per-(C,N) memo:candidate_bwu_/3 into Ctx0 as build_with_use:use_state/2
% so grouped_dep action goals and nested :install sub-goals see bracket USE
% discovered on other edges (e.g. RDEPEND after COMMON_DEPEND in :run proofs).

use:unify_memo_bwu_into_context(C, N, Ctx0, Ctx) :-
    use:context_build_with_use_state(Ctx0, BWU0),
    use:merge_memo_candidate_bwu(C, N, BWU0, BWUMerged),
    ( BWUMerged == use_state([], []) ->
        Ctx = Ctx0
    ; ( select(build_with_use:_, Ctx0, Ctx1) -> true ; Ctx1 = Ctx0 ),
      feature_unification:unify([build_with_use:BWUMerged], Ctx1, Ctx)
    ).


%! use:replace_candidate_bwu(+C, +N, +BWU) is det.
%
% Store (or replace) the aggregated build_with_use state for (C,N).

use:replace_candidate_bwu(C, N, BWU) :-
    retractall(memo:candidate_bwu_(C, N, _)),
    assertz(memo:candidate_bwu_(C, N, BWU)).


%! use:accumulate_candidate_bwu(+C, +N, +BWU)
%
% Merge a forcing (HARD) BWU from a dependency edge into the per-(C,N)
% memo.  Convenience wrapper over accumulate_candidate_bwu_pv/4 used by
% the seed path (ranking:seed_accumulate_bwu), where seeded directives
% are context-independent `[F]`/`[-F]` (i.e. always HARD).  Fails on
% enable/disable conflicts.  Does not run REQUIRED_USE verification (the
% provider entry is not fixed yet on grouped_dep edges).

use:accumulate_candidate_bwu(_C, _N, use_state([], [])) :- !.
use:accumulate_candidate_bwu(C, N, BWU) :-
    use:accumulate_candidate_bwu_pv(C, N, BWU, use_state([], [])).


%! use:accumulate_candidate_bwu_pv(+C, +N, +HardState, +EqState)
%
% Provenance-aware accumulation of a dependency edge's build_with_use
% into the per-(C,N) cross-dep memo (portage-ng#87/#88).  HardState holds
% the forcing directives (`[F]`/`[F?]`/`[!F]`/`[!F?]` and seeded/pinned
% flags); EqState holds the following directives (`[F=]`/`[!F=]`).
%
% HARD and EQ contributions are accumulated in separate memos, and the
% effective `candidate_bwu_/3` is recomputed as "HARD beats EQ": a flag a
% USE-equal consumer wants OFF yields to another consumer that hard-
% requires it ON (and vice versa), instead of being reported as an
% irreconcilable conflict.  The EQ merge itself also ignores flags the
% HARD component determines (merge_eq_states_under_hard/4, portage-ng#96):
% two `=` consumers projecting opposite values is only a genuine conflict
% when nothing hard-requires the flag.  Genuine conflicts remain:
% HARD-vs-HARD (two hard consumers disagree) and EQ-vs-EQ on a
% HARD-undetermined flag still fail and record a violation descriptor.

use:accumulate_candidate_bwu_pv(_C, _N, use_state([], []), use_state([], [])) :- !.
use:accumulate_candidate_bwu_pv(C, N, HardState, EqState) :-
    use:current_bwu_component(candidate_bwu_hard_, C, N, OldHard),
    use:current_bwu_component(candidate_bwu_eq_, C, N, OldEq),
    ( use:merge_bwu_state(OldHard, HardState, NewHard),
      use:merge_eq_states_under_hard(NewHard, OldEq, EqState, NewEq),
      use:combine_hard_eq_bwu(NewHard, NewEq, Effective)
    ->
        use:store_bwu_component(candidate_bwu_hard_, C, N, NewHard),
        use:store_bwu_component(candidate_bwu_eq_, C, N, NewEq),
        use:replace_candidate_bwu(C, N, Effective)
    ;
        use:record_bwu_pv_conflict(C, N, OldHard, HardState, OldEq, EqState),
        fail
    ).


%! use:current_bwu_component(+Memo, +C, +N, -State)
%
% Read a HARD/EQ provenance component memo for (C,N); empty when unset.

use:current_bwu_component(candidate_bwu_hard_, C, N, State) :-
    ( memo:candidate_bwu_hard_(C, N, State0) -> State = State0
    ; State = use_state([], [])
    ).
use:current_bwu_component(candidate_bwu_eq_, C, N, State) :-
    ( memo:candidate_bwu_eq_(C, N, State0) -> State = State0
    ; State = use_state([], [])
    ).


%! use:store_bwu_component(+Memo, +C, +N, +State)
%
% Replace a HARD/EQ provenance component memo for (C,N) (no-op for empty).

use:store_bwu_component(candidate_bwu_hard_, C, N, State) :-
    retractall(memo:candidate_bwu_hard_(C, N, _)),
    ( State == use_state([], []) -> true ; assertz(memo:candidate_bwu_hard_(C, N, State)) ).
use:store_bwu_component(candidate_bwu_eq_, C, N, State) :-
    retractall(memo:candidate_bwu_eq_(C, N, _)),
    ( State == use_state([], []) -> true ; assertz(memo:candidate_bwu_eq_(C, N, State)) ).


%! use:merge_bwu_state(+A, +B, -Merged)
%
% Union two use_state/2 BWU components; fails on enable/disable conflict.

use:merge_bwu_state(A, B, Merged) :-
    feature_unification:val_hook(A, B, Merged).


%! use:merge_eq_states_under_hard(+Hard, +OldEq, +EqState, -NewEq)
%
% Union two EQ components, ignoring flags the HARD component already
% determines (portage-ng#96).  Two `=` consumers projecting opposite
% values onto a provider flag is only a genuine conflict when nothing
% hard-requires the flag: once HARD fixes it, the effective BWU follows
% HARD anyway ("HARD beats EQ") and each `=` consumer is brought in line
% by back-propagation (ranking:apply_equality_pins/3), so the stale EQ
% projections must not fail the merge (e.g. qtdeclarative[opengl=off]
% vs a second consumer [opengl=on] after qtwayland hard-enabled opengl
% on qtbase).  EQ-vs-EQ conflicts on HARD-undetermined flags still fail.

use:merge_eq_states_under_hard(use_state(HEn, HDis), OldEq, EqState, NewEq) :-
    ord_union(HEn, HDis, Determined),
    OldEq = use_state(OEn, ODis),
    EqState = use_state(En, Dis),
    ord_subtract(OEn, Determined, OEn1),
    ord_subtract(ODis, Determined, ODis1),
    ord_subtract(En, Determined, En1),
    ord_subtract(Dis, Determined, Dis1),
    use:merge_bwu_state(use_state(OEn1, ODis1), use_state(En1, Dis1), NewEq).


%! use:combine_hard_eq_bwu(+Hard, +Eq, -Effective)
%
% Combine the HARD and EQ components into an effective BWU where HARD
% wins: an EQ-following flag that contradicts a HARD-forced flag is
% dropped (the `=` consumer must follow, handled by back-propagation via
% ranking:apply_equality_pins/3).  Fails only on a residual conflict
% (two EQ consumers disagreeing on a flag HARD does not determine).

use:combine_hard_eq_bwu(use_state(HEn, HDis), use_state(EEn, EDis), use_state(En, Dis)) :-
    ord_subtract(EEn, HDis, EEn1),
    ord_subtract(EDis, HEn, EDis1),
    ord_union(HEn, EEn1, En),
    ord_union(HDis, EDis1, Dis),
    ord_intersection(En, Dis, []).


%! use:reconcile_cross_dep_bwu(+C, +N, +OldBWU, +NewBWU, -Merged)
%
% Conflict-time reconciliation for check_bwu_cross_dep (portage-ng#96).
% Called only after a plain val_hook merge of the memo effective (OldBWU)
% and a fresh resolution (NewBWU) failed on enable/disable conflicts.
% Both states mix provenances: the memo carries EQ-following and pin
% snapshots taken before a provider flag flipped, and the fresh state may
% carry stale `?{Context}` bracket values threaded through earlier proof
% literals.  Resolve each conflicting flag by provenance:
%
%   - flags the HARD component memo determines keep the memo value
%     (forcing consumers win; the fresh side's opposite value is a stale
%     following snapshot),
%   - all other conflicting flags take the FRESH value (newest snapshot
%     wins: EQ/pin followers track mutable provider state).
%
% The result is verified against REQUIRED_USE by the caller, so genuine
% unsatisfiable combinations still fail there; genuine HARD-vs-HARD
% bracket conflicts are still detected on the grouped-dep edge path
% (accumulate_candidate_bwu_pv/4).

use:reconcile_cross_dep_bwu(C, N, use_state(OEn, ODis), use_state(NEn, NDis), Merged) :-
    use:current_bwu_component(candidate_bwu_hard_, C, N, use_state(HEn, HDis)),
    ord_intersection(OEn, NDis, C1),
    ord_intersection(ODis, NEn, C2),
    ord_union(C1, C2, Conflicts),
    Conflicts \== [],
    ord_subtract(OEn, Conflicts, OEn1), ord_subtract(ODis, Conflicts, ODis1),
    ord_subtract(NEn, Conflicts, NEn1), ord_subtract(NDis, Conflicts, NDis1),
    feature_unification:val_hook(use_state(OEn1, ODis1), use_state(NEn1, NDis1),
                                 use_state(MEn0, MDis0)),
    ord_intersection(Conflicts, HEn, ResEnH),
    ord_intersection(Conflicts, HDis, ResDisH0),
    ord_subtract(ResDisH0, ResEnH, ResDisH),
    ord_union(ResEnH, ResDisH, HardDetermined),
    ord_subtract(Conflicts, HardDetermined, Rest),
    ord_intersection(Rest, NEn, ResEnF),
    ord_intersection(Rest, NDis, ResDisF),
    ord_union([MEn0, ResEnH, ResEnF], MEn),
    ord_union([MDis0, ResDisH, ResDisF], MDis),
    ord_intersection(MEn, MDis, []),
    Merged = use_state(MEn, MDis).


%! use:record_bwu_pv_conflict(+C, +N, +OldHard, +HardState, +OldEq, +EqState)
%
% Record a use-flag conflict descriptor for the (C,N) memo when HARD/EQ
% accumulation cannot be reconciled (HARD-vs-HARD or EQ-vs-EQ).

use:record_bwu_pv_conflict(C, N, OldHard, HardState, OldEq, EqState) :-
    OldHard = use_state(OHEn, OHDis), HardState = use_state(HEn, HDis),
    OldEq = use_state(OEEn, OEDis), EqState = use_state(EEn, EDis),
    ord_union(OHEn, HEn, AllHEn0), ord_union(AllHEn0, OEEn, AllEn0), ord_union(AllEn0, EEn, AllEn),
    ord_union(OHDis, HDis, AllHDis0), ord_union(AllHDis0, OEDis, AllDis0), ord_union(AllDis0, EDis, AllDis),
    ord_intersection(AllEn, AllDis, Conflicts),
    ( \+ memo:requse_violation_(C, N, _) ->
        assertz(memo:requse_violation_(C, N, use_flag_conflict(Conflicts, AllEn, AllDis)))
    ; true
    ).


%! use:verify_candidate_satisfies_bwu_state(+RepoEntry, +BWU) is semidet.
%
% True when the portage candidate's effective IUSE matches aggregated BWU.

use:verify_candidate_satisfies_bwu_state(Repo://Entry, use_state(En, Dis)) :-
    forall(member(F, En),
           use:candidate_effective_use_enabled_in_iuse(Repo://Entry, F)),
    forall(member(F, Dis),
           \+ use:candidate_effective_use_enabled_in_iuse(Repo://Entry, F)).


% -----------------------------------------------------------------------------
%  Cross-dependency BWU REQUIRED_USE conflict detection
% -----------------------------------------------------------------------------

%! use:check_bwu_cross_dep(+C, +N, +RepoEntry, +BWU)
%
% Detects irreconcilable REQUIRED_USE conflicts across independent dependency
% branches.  Uses a memo to track committed BWU per (C,N).
%
% When the plain merge of the memo effective and a fresh resolution fails
% on enable/disable conflicts, reconcile_cross_dep_bwu/5 retries with
% provenance-aware conflict resolution before reporting a violation
% (portage-ng#96): both states carry snapshots of EQ-following / pin
% flags taken at different times, and a since-flipped provider flag must
% be refreshed (HARD memo value wins, otherwise the fresh value), not
% reported as an irreconcilable conflict.

use:check_bwu_cross_dep(C, N, RepoEntry, BWU) :-
    ( BWU \= use_state([], []) ->
        ( memo:candidate_bwu_(C, N, OldBWU) ->
            ( ( feature_unification:val_hook(OldBWU, BWU, MergedBWU)
              ; use:reconcile_cross_dep_bwu(C, N, OldBWU, BWU, MergedBWU)
              ) ->
                ( use:verify_required_use_with_bwu(RepoEntry, MergedBWU) ->
                    use:replace_candidate_bwu(C, N, MergedBWU)
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
        ; ( use:verify_required_use_with_bwu(RepoEntry, BWU) ->
              assertz(memo:candidate_bwu_(C, N, BWU))
          ; use:describe_required_use_violation(RepoEntry, BWU, ViolDesc),
            ( \+ memo:requse_violation_(C, N, _) ->
                assertz(memo:requse_violation_(C, N, ViolDesc))
            ; true
            ),
            fail
          )
        )
    ; true
    ).


%! use:clear_bwu_cross_dep_memos
%
% Cleans up candidate_bwu_ memos.  Called at proof initialization.

use:clear_bwu_cross_dep_memos :-
    retractall(memo:candidate_bwu_(_, _, _)),
    retractall(memo:candidate_bwu_hard_(_, _, _)),
    retractall(memo:candidate_bwu_eq_(_, _, _)),
    retractall(memo:bwu_force_seen_(_, _, _)),
    retractall(memo:bwu_force_pending_(_, _, _)).


%! use:check_bwu_ed_conflict(+C, +N, +Context)
%
% Lightweight Enable/Disable conflict check for grouped_package_dependency.
% Treats the whole context BWU as forcing (HARD); used where no edge
% directive provenance is available.

use:check_bwu_ed_conflict(C, N, Context) :-
    use:context_build_with_use_state(Context, BWU),
    use:accumulate_candidate_bwu(C, N, BWU).


%! use:check_bwu_ed_conflict_pv(+C, +N, +ParentCtx, +UseDeps, +Context)
%
% Provenance-aware Enable/Disable conflict check (portage-ng#87/#88).
% Splits the dependency edge's effective BWU (in Context) into a HARD
% component and a USE-equal (EQ) component derived from UseDeps, so that
% the cross-dep aggregation can let HARD requirements win over `=`
% following constraints (see accumulate_candidate_bwu_pv/4).  EqState is
% resolved from the `[F=]`/`[!F=]` directives against the consumer's
% ParentCtx; the HARD component is everything else in the edge BWU
% (plain/optional brackets plus any seeded or equality-pinned flags).

use:check_bwu_ed_conflict_pv(C, N, ParentCtx, UseDeps, Context) :-
    use:context_build_with_use_state(Context, FullBWU),
    use:edge_eq_state(ParentCtx, UseDeps, EqState),
    use:split_hard_from_full(FullBWU, EqState, HardState),
    use:accumulate_candidate_bwu_pv(C, N, HardState, EqState).


%! use:edge_eq_state(+ParentCtx, +UseDeps, -EqState)
%
% Resolve only the USE-equal directives (`[F=]`/`[!F=]`) of an edge into
% a build_with_use state against the consumer's ParentCtx.

use:edge_eq_state(ParentCtx, UseDeps, EqState) :-
    include(use:is_eq_directive, UseDeps, EqDeps),
    use:directives_to_bwu(ParentCtx, EqDeps, EqState).


%! use:is_eq_directive(+Directive)
%
% True for the bidirectional USE-equal directives.

use:is_eq_directive(use(equal(_), _)).
use:is_eq_directive(use(inverse(_), _)).


%! use:directives_to_bwu(+ParentCtx, +Directives, -State)
%
% Fold a list of bracketed USE directives into a normalized
% build_with_use state, resolving each against ParentCtx.

use:directives_to_bwu(ParentCtx, Directives, State) :-
    use:empty_use_state(Empty),
    foldl(use:process_bwu_directive(ParentCtx), Directives, Empty, State0),
    use:normalize_build_with_use(State0, State).


%! use:split_hard_from_full(+FullBWU, +EqState, -HardState)
%
% HardState is FullBWU with the EQ-only flags removed, so the forcing
% (HARD) component excludes flags contributed solely by `=` following
% constraints.

use:split_hard_from_full(use_state(FEn, FDis), use_state(QEn, QDis),
                         use_state(HEn, HDis)) :-
    ord_subtract(FEn, QEn, HEn),
    ord_subtract(FDis, QDis, HDis).


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
