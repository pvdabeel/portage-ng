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
conditionals).  `required_use_term_satisfied/1` drives this recursively.

== Newuse ==

The `--newuse` (`-N`) flag triggers rebuilds when the effective USE for an
installed package differs from what it was built with.  `newuse_mismatch/1,2`
implements this comparison.
*/

:- module(use, []).


% =============================================================================
%  Effective USE in context
% =============================================================================

%! use:effective_use_in_context(+Context, +Use, -State)
%
% Determine the effective state of USE flag Use for the ebuild identified
% by the `self/1` term in Context (or the global `query_required_use_self`).
% State is unified with `positive` or `negative`.
% Results are memoized in memo:eff_use_cache_/4.

effective_use_in_context(Context, Use, State) :-
  ( memberchk(self(RepoEntry0), Context) ->
      ( RepoEntry0 = Repo://Id -> true
      ; RepoEntry0 = Repo//Id  -> true
      )
  ; nb_current(query_required_use_self, Repo://Id)
  ),
  \+ Use =.. [minus,_],
  ( memo:eff_use_cache_(Repo, Id, Use, Cached) ->
      State = Cached
  ;
  entry_iuse_default(Repo://Id, Use, Default),
  cache:ordered_entry(Repo, Id, C, N, _),
      ( preference:profile_package_use_override_for_entry(Repo://Id, Use, Eff, _Reason0) ->
      true
  ; preference:package_use_override(C, N, Use, positive) ->
      Eff = positive
  ; preference:package_use_override(C, N, Use, negative) ->
      Eff = negative
  ; preference:gentoo_package_use_override_for_entry_soft(Repo://Id, Use, Eff0) ->
      Eff = Eff0
  ; preference:profile_package_use_override_for_entry_soft(Repo://Id, Use, Eff0) ->
      Eff = Eff0
  ; preference:use(Use) ->
      Eff = positive
  ; preference:use(minus(Use)) ->
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

effective_use_for_entry(RepoEntry0, Use, State) :-
  ( RepoEntry0 = Repo://Id -> true
  ; RepoEntry0 = Repo//Id  -> true
  ),
  \+ Use =.. [minus,_],
  ( memo:eff_use_cache_(Repo, Id, Use, Cached) ->
      State = Cached
  ;
  entry_iuse_default(Repo://Id, Use, Default),
  cache:ordered_entry(Repo, Id, C, N, _),
      ( preference:profile_package_use_override_for_entry(Repo://Id, Use, Eff, _Reason0) ->
      true
  ; preference:package_use_override(C, N, Use, positive) ->
      Eff = positive
  ; preference:package_use_override(C, N, Use, negative) ->
      Eff = negative
  ; preference:gentoo_package_use_override_for_entry_soft(Repo://Id, Use, Eff0) ->
      Eff = Eff0
  ; preference:profile_package_use_override_for_entry_soft(Repo://Id, Use, Eff0) ->
      Eff = Eff0
  ; preference:use(Use) ->
      Eff = positive
  ; preference:use(minus(Use)) ->
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

entry_iuse_default(Repo://Entry, Use, Default) :-
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
    iuse_default_pairs_to_assoc(Pairs, Map),
    assertz(memo:iuse_default_cache_(Repo, Entry, Map)),
    get_assoc(Use, Map, Default),
    !
  ).

%! use:iuse_default_pairs_to_assoc(+Pairs, -Map)
%
% Build an AVL map from Use-Default pairs. If a flag appears multiple
% times, `positive` wins (IUSE `+flag` overrides bare `flag`).

iuse_default_pairs_to_assoc(Pairs, Map) :-
  empty_assoc(M0),
  iuse_default_pairs_to_assoc_(Pairs, M0, Map).

iuse_default_pairs_to_assoc_([], M, M) :- !.
iuse_default_pairs_to_assoc_([U-Def|Rest], M0, M) :-
  ( get_assoc(U, M0, Existing) ->
      ( Existing == positive -> M1 = M0
      ; Def == positive -> put_assoc(U, M0, positive, M1)
      ; M1 = M0
      )
  ; put_assoc(U, M0, Def, M1)
  ),
  iuse_default_pairs_to_assoc_(Rest, M1, M).


% =============================================================================
%  Per-entry IUSE memoization
% =============================================================================

%! use:entry_iuse_info(+RepoEntry, -Info)
%
% Retrieve the memoized IUSE info for an entry. Info is a compound
% `iuse_info(IuseSet, PlusSet)` where IuseSet is the sorted list of
% all IUSE flag atoms and PlusSet is the sorted list of flags declared
% with `+` (default-on).

entry_iuse_info(Repo://Entry, Info) :-
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

empty_use_state(use_state([],[])).

%! use:normalize_build_with_use(+BWU0, -BWU)
%
% Normalize a build_with_use term to canonical `use_state(En, Dis)` form
% with sorted lists. Handles use_state/2 compounds, legacy flat lists,
% and unknown formats (normalised to empty).

normalize_build_with_use(use_state(En0, Dis0), use_state(En, Dis)) :-
  !,
  sort(En0, En),
  sort(Dis0, Dis).
normalize_build_with_use(BWU0, use_state(En, Dis)) :-
  is_list(BWU0),
  !,
  build_with_use_requirements(BWU0, En, Dis).
normalize_build_with_use(_Other, use_state([],[])) :-
  !.

%! use:context_build_with_use_state(+Context, -State)
%
% Extract and normalize the build_with_use state from a dependency
% context. Returns empty state if no build_with_use term is present.

context_build_with_use_state(Context, State) :-
  ( memberchk(build_with_use:BWU, Context) ->
      normalize_build_with_use(BWU, State)
  ; empty_use_state(State)
  ),
  !.

%! use:process_bwu_directive(+ParentCtx, +Directive, +State0, -State)
%
% Fold helper for building up build-with-use state. Resolves a single
% USE directive against the parent context, then adds the flag to the
% enable or disable set. Conflicting directives (enable a flag already
% in Dis, or vice versa) cause failure to preserve determinism.

process_bwu_directive(ParentContext, use(Directive, Default), use_state(En0, Dis0), use_state(En, Dis)) :-
  !,
  use_dep_requirement(ParentContext, Directive, Default, Requirement),
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
process_bwu_directive(_ParentContext, _Other, State, State) :- !.


% =============================================================================
%  Context helpers for per-package USE (build_with_use)
% =============================================================================

%! use:ctx_assumed(+Context, +Use)
%
% True if Use is positively assumed in Context -- either via an explicit
% `assumed(Use)` term or via the enable set of a `build_with_use` state.

ctx_assumed(Ctx, Use) :-
  memberchk(assumed(Use), Ctx),
  !.
ctx_assumed(Ctx, Use) :-
  memberchk(build_with_use:BU, Ctx),
  BU = use_state(En, _Dis),
  memberchk(Use, En),
  !.
ctx_assumed(Ctx, Use) :-
  memberchk(build_with_use:BU, Ctx),
  is_list(BU),
  memberchk(assumed(Use), BU),
  !.

%! use:ctx_assumed_minus(+Context, +Use)
%
% True if Use is negatively assumed in Context -- either via an explicit
% `assumed(minus(Use))` term or via the disable set of a `build_with_use`.

ctx_assumed_minus(Ctx, Use) :-
  memberchk(assumed(minus(Use)), Ctx),
  !.
ctx_assumed_minus(Ctx, Use) :-
  memberchk(build_with_use:BU, Ctx),
  BU = use_state(_En, Dis),
  memberchk(Use, Dis),
  !.
ctx_assumed_minus(Ctx, Use) :-
  memberchk(build_with_use:BU, Ctx),
  is_list(BU),
  memberchk(assumed(minus(Use)), BU),
  !.


% =============================================================================
%  Self-context USE state
% =============================================================================

%! use:self_context_use_state(+Context, +Use, -State)
%
% Determine the USE state for flag Use on the "self" entry in Context.
% This is used by optional USE deps (`foo(+)`, `foo(-)`) to check the
% parent ebuild's own USE configuration. Results are memoized in
% memo:self_use_cache_/4.

self_context_use_state(Ctx, Use, State) :-
  memberchk(self(RepoEntry0), Ctx),
  ( RepoEntry0 = Repo://Id -> true
  ; RepoEntry0 = Repo//Id  -> true
  ),
  ( memo:self_use_cache_(Repo, Id, Use, Cached) ->
      Cached \== miss,
      State = Cached
  ;
      ( self_context_use_state_compute_(Repo, Id, Use, S0) ->
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

self_context_use_state_compute_(Repo, Id, Use, State) :-
  entry_iuse_info(Repo://Id, iuse_info(IuseSet, _PlusSet)),
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

use_dep_requirement(_Ctx, enable(Use), Default, requirement(enable, Use, Default)) :- !.
use_dep_requirement(_Ctx, disable(Use), Default, requirement(disable, Use, Default)) :- !.

use_dep_requirement(Ctx, equal(Use), Default, requirement(enable, Use, Default)) :-
  ctx_assumed(Ctx, Use), !.
use_dep_requirement(Ctx, equal(Use), Default, requirement(disable, Use, Default)) :-
  ctx_assumed_minus(Ctx, Use), !.
use_dep_requirement(Ctx, equal(Use), Default, requirement(enable, Use, Default)) :-
  effective_use_in_context(Ctx, Use, positive), !.
use_dep_requirement(Ctx, equal(Use), Default, requirement(disable, Use, Default)) :-
  effective_use_in_context(Ctx, Use, negative), !.
use_dep_requirement(_Ctx, equal(Use), Default, Requirement) :-
  ( Default == positive -> Requirement = requirement(enable, Use, Default)
  ; Default == negative -> Requirement = requirement(disable, Use, Default)
  ; Requirement = none
  ),
  !.

use_dep_requirement(Ctx, inverse(Use), Default, requirement(disable, Use, Default)) :-
  ctx_assumed(Ctx, Use), !.
use_dep_requirement(Ctx, inverse(Use), Default, requirement(enable, Use, Default)) :-
  ctx_assumed_minus(Ctx, Use), !.
use_dep_requirement(Ctx, inverse(Use), Default, requirement(disable, Use, Default)) :-
  effective_use_in_context(Ctx, Use, positive), !.
use_dep_requirement(Ctx, inverse(Use), Default, requirement(enable, Use, Default)) :-
  effective_use_in_context(Ctx, Use, negative), !.
use_dep_requirement(_Ctx, inverse(Use), Default, Requirement) :-
  ( Default == positive -> Requirement = requirement(disable, Use, Default)
  ; Default == negative -> Requirement = requirement(enable, Use, Default)
  ; Requirement = none
  ),
  !.

use_dep_requirement(Ctx, optenable(Use), Default, requirement(enable, Use, Default)) :-
  ( ctx_assumed(Ctx, Use)
  ; self_context_use_state(Ctx, Use, positive)
  ; \+ memberchk(self(_), Ctx),
    effective_use_in_context(Ctx, Use, positive)
  ),
  !.
use_dep_requirement(_Ctx, optenable(_Use), _Default, none) :- !.

use_dep_requirement(Ctx, optdisable(Use), Default, requirement(disable, Use, Default)) :-
  ( ctx_assumed_minus(Ctx, Use)
  ; self_context_use_state(Ctx, Use, negative)
  ; \+ memberchk(self(_), Ctx),
    effective_use_in_context(Ctx, Use, negative)
  ),
  !.
use_dep_requirement(_Ctx, optdisable(_Use), _Default, none) :- !.

use_dep_requirement(_Ctx, _Directive, _Default, none).


% =============================================================================
%  Candidate USE-dependency enforcement
% =============================================================================

%! use:candidate_satisfies_use_deps(+ParentCtx, +Candidate, +UseDeps)
%
% True if Candidate satisfies all bracketed USE requirements in UseDeps.
% For optional deps (optenable/optdisable), satisfaction is checked only
% when the flag is present in the candidate's IUSE.

candidate_satisfies_use_deps(_ParentContext, _Repo://_Entry, []) :- !.
candidate_satisfies_use_deps(ParentContext, Repo://Entry, [use(Directive, Default)|Rest]) :-
  use_dep_requirement(ParentContext, Directive, Default, Requirement),
  candidate_satisfies_use_requirement_opt(Directive, Repo://Entry, Requirement),
  candidate_satisfies_use_deps(ParentContext, Repo://Entry, Rest).

%! use:candidate_satisfies_use_requirement_opt(+Directive, +Entry, +Req)
%
% For optional directives (optenable/optdisable), only enforce the
% requirement if the flag is present in the candidate's IUSE.

candidate_satisfies_use_requirement_opt(optenable(Use), Repo://Entry, Requirement) :-
  !,
  ( candidate_iuse_present(Repo://Entry, Use) ->
      candidate_satisfies_use_requirement(Repo://Entry, Requirement)
  ; true
  ).
candidate_satisfies_use_requirement_opt(optdisable(Use), Repo://Entry, Requirement) :-
  !,
  ( candidate_iuse_present(Repo://Entry, Use) ->
      candidate_satisfies_use_requirement(Repo://Entry, Requirement)
  ; true
  ).
candidate_satisfies_use_requirement_opt(_, Repo://Entry, Requirement) :-
  candidate_satisfies_use_requirement(Repo://Entry, Requirement).

%! use:candidate_satisfies_use_requirement(+Entry, +Requirement)
%
% Check whether Entry's effective USE satisfies Requirement.
% If the flag is not in IUSE, the IUSE default semantics from the
% dependency (`(+)` or `(-)`) determine satisfaction.

candidate_satisfies_use_requirement(_Repo://_Entry, none) :- !.
candidate_satisfies_use_requirement(Repo://Entry, requirement(Mode, Use, Default)) :-
  ( candidate_iuse_present(Repo://Entry, Use)
  -> ( Mode == enable
     -> candidate_effective_use_enabled_in_iuse(Repo://Entry, Use)
     ; Mode == disable
     -> \+ candidate_effective_use_enabled_in_iuse(Repo://Entry, Use)
     )
  ; use_dep_default_satisfies_absent_iuse(Default, Mode)
  ).

%! use:candidate_iuse_present(+RepoEntry, +Use)
%
% True if Use is declared in the entry's IUSE (regardless of default).

candidate_iuse_present(Repo://Entry, Use) :-
  entry_iuse_info(Repo://Entry, iuse_info(IuseSet, _PlusSet)),
  memberchk(Use, IuseSet),
  !.

%! use:use_dep_default_satisfies_absent_iuse(+Default, +Mode)
%
% When a flag is absent from IUSE, `(+)` defaults satisfy `enable`
% requirements and `(-)` defaults satisfy `disable` requirements.

use_dep_default_satisfies_absent_iuse(positive, enable) :- !.
use_dep_default_satisfies_absent_iuse(negative, disable) :- !.
use_dep_default_satisfies_absent_iuse(_Default, _Mode) :- fail.


% =============================================================================
%  Candidate effective USE evaluation
% =============================================================================

%! use:candidate_effective_use_enabled_in_iuse(+RepoEntry, +Use)
%
% True if Use is effectively enabled for the given entry, considering
% the full priority chain (profile overrides, package.use, IUSE defaults).

candidate_effective_use_enabled_in_iuse(Repo://Entry, Use) :-
  entry_effective_use_set(Repo://Entry, EnabledSet),
  memberchk(Use, EnabledSet).

%! use:entry_effective_use_set(+RepoEntry, -EnabledSet)
%
% Compute (and memoize) the set of effectively enabled USE flags for an
% entry. EnabledSet is a sorted list of atoms.

entry_effective_use_set(Repo://Entry, EnabledSet) :-
  ( memo:effective_use_fact(Repo, Entry, EnabledSet) ->
    true
  ;
    entry_iuse_info(Repo://Entry, iuse_info(IuseSet, _PlusSet)),
    findall(U,
            ( member(U, IuseSet),
              candidate_effective_use_enabled_raw(Repo://Entry, U)
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

candidate_effective_use_enabled_raw(Repo://Entry, Use) :-
  cache:ordered_entry(Repo, Entry, C, N, _),
  ( preference:profile_package_use_override_for_entry(Repo://Entry, Use, positive, _Reason0) ->
      true
  ; preference:profile_package_use_override_for_entry(Repo://Entry, Use, negative, _Reason0) ->
      fail
  ; preference:package_use_override(C, N, Use, positive) ->
      true
  ; preference:package_use_override(C, N, Use, negative) ->
      fail
  ; preference:gentoo_package_use_override_for_entry_soft(Repo://Entry, Use, positive) ->
      true
  ; preference:gentoo_package_use_override_for_entry_soft(Repo://Entry, Use, negative) ->
      fail
  ; preference:profile_package_use_override_for_entry_soft(Repo://Entry, Use, positive) ->
      true
  ; preference:profile_package_use_override_for_entry_soft(Repo://Entry, Use, negative) ->
      fail
  ; preference:use(Use) ->
      true
  ; use_expand_selector_flag_unset(Use) ->
      fail
  ; preference:use(minus(Use)),
    \+ is_abi_x86_flag(Use) ->
      fail
  ; entry_iuse_info(Repo://Entry, iuse_info(_IuseSet, PlusSet)),
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

use_expand_selector_flag_unset(Use) :-
  atom(Use),
  preference:use_expand_env(_EnvVar, Prefix),
  atom_concat(Prefix, '_', PrefixUnderscore),
  atom_concat(PrefixUnderscore, _, Use),
  use_expand_prefix_has_explicit_selection(Prefix),
  \+ preference:use(Use),
  \+ preference:use(minus(Use)),
  !.

%! use:use_expand_prefix_has_explicit_selection(+Prefix)
%
% True if any USE flag with the given USE_EXPAND prefix is explicitly
% set (positively or negatively) in the user/profile configuration.

use_expand_prefix_has_explicit_selection(Prefix) :-
  atom_concat(Prefix, '_', PrefixUnderscore),
  ( preference:use(Use0)
  ; preference:use(minus(Use0))
  ),
  atom(Use0),
  atom_concat(PrefixUnderscore, _, Use0),
  !.

%! use:is_abi_x86_flag(+Use)
%
% True if Use starts with `abi_x86_`. These flags receive special
% treatment: `preference:use(minus(abi_x86_*))` does not override
% IUSE `+` defaults, because ABI flags are typically profile-managed.

is_abi_x86_flag(Use) :-
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

installed_pkg_satisfies_use_reqs(_ParentContext, _Installed, []) :- !.
installed_pkg_satisfies_use_reqs(ParentContext, pkg://InstalledId,
                                    [use(Directive, Default)|Rest]) :-
  !,
  use_dep_requirement(ParentContext, Directive, Default, Req),
  installed_pkg_satisfies_use_requirement(pkg://InstalledId, Req),
  installed_pkg_satisfies_use_reqs(ParentContext, pkg://InstalledId, Rest).
installed_pkg_satisfies_use_reqs(ParentContext, Installed, [_|Rest]) :-
  installed_pkg_satisfies_use_reqs(ParentContext, Installed, Rest).

%! use:installed_pkg_satisfies_use_requirement(+Installed, +Requirement)
%
% Check a single USE requirement against an installed package's VDB USE.

installed_pkg_satisfies_use_requirement(_Installed, none) :- !.
installed_pkg_satisfies_use_requirement(pkg://InstalledId, requirement(enable, Use, _Default)) :-
  query:search(use(Use), pkg://InstalledId),
  !.
installed_pkg_satisfies_use_requirement(pkg://InstalledId, requirement(disable, Use, _Default)) :-
  \+ query:search(use(Use), pkg://InstalledId),
  !.


% =============================================================================
%  Build-with-use constraint satisfaction
% =============================================================================

%! use:context_build_with_use_list(+Context, -List)
%
% Extract build-with-use assumptions from Context as a flat list of
% `assumed(Use)` and `assumed(minus(Use))` terms.

context_build_with_use_list(Context, List) :-
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

build_with_use_requirements(use_state(En, Dis), MustEnable, MustDisable) :-
  !,
  sort(En, MustEnable),
  sort(Dis, MustDisable).
build_with_use_requirements(BuildWithUse, MustEnable, MustDisable) :-
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

installed_entry_satisfies_build_with_use(pkg://InstalledEntry, Context) :-
  context_build_with_use_state(Context, State),
  build_with_use_requirements(State, MustEnable, MustDisable),
  vdb_enabled_use_set(pkg://InstalledEntry, BuiltUse),
  vdb_iuse_set(pkg://InstalledEntry, BuiltIuse),
  forall(member(U, MustEnable),
         ( memberchk(U, BuiltIuse) -> memberchk(U, BuiltUse)
         ; true
         )),
  forall(member(U, MustDisable),
         ( memberchk(U, BuiltIuse) -> \+ memberchk(U, BuiltUse)
         ; true
         )).


% =============================================================================
%  --newuse support (Portage-like -N)
% =============================================================================

%! use:newuse_mismatch(+InstalledEntry)
%
% True if the installed package has a USE mismatch compared to the
% currently effective USE for the same version in the repo set.
% Used to implement `--newuse` / `-N` rebuild semantics.

newuse_mismatch(pkg://InstalledEntry) :-
  query:search([category(C),name(N),version(V)], pkg://InstalledEntry),
  preference:accept_keywords(K),
  ( query:search([select(repository,notequal,pkg),category(C),name(N),keywords(K),version(V)],
                 CurRepo//CurEntry)
  -> newuse_mismatch(pkg://InstalledEntry, CurRepo//CurEntry)
  ;  fail
  ).

%! use:newuse_mismatch(+InstalledEntry, +RepoEntry)
%
% True if the installed package's built USE or IUSE differs from the
% current repo entry's effective USE or IUSE. Checks both the enabled
% USE set and the declared IUSE set for symmetric differences.

newuse_mismatch(pkg://InstalledEntry, CurRepo//CurEntry) :-
  vdb_enabled_use_set(pkg://InstalledEntry, BuiltUse),
  entry_enabled_use_set(CurRepo//CurEntry, CurUse),
  ( symmetric_diff_nonempty(BuiltUse, CurUse)
  ; vdb_iuse_set(pkg://InstalledEntry, BuiltIuse),
    entry_iuse_set(CurRepo//CurEntry, CurIuse),
    BuiltIuse \== [],
    CurIuse \== [],
    symmetric_diff_nonempty(BuiltIuse, CurIuse)
  ),
  !.

%! use:vdb_enabled_use_set(+RepoEntry, -UseSet)
%
% Collect the USE flags recorded as enabled in the VDB for an entry.

vdb_enabled_use_set(RepoEntry, UseSet) :-
  findall(U, query:search(use(U), RepoEntry), Us0),
  sort(Us0, UseSet).

%! use:entry_iuse_set(+RepoEntry, -IuseSet)
%
% Collect the bare IUSE flag names for an entry (stripping defaults).

entry_iuse_set(RepoEntry, IuseSet) :-
  findall(U,
          ( query:search(iuse(Value), RepoEntry),
            eapi:strip_use_default(Value, U)
          ),
          Us0),
  sort(Us0, IuseSet).

%! use:vdb_iuse_set(+RepoEntry, -IuseSet)
%
% Alias for entry_iuse_set/2 (VDB entries store IUSE the same way).

vdb_iuse_set(RepoEntry, IuseSet) :-
  entry_iuse_set(RepoEntry, IuseSet).

%! use:entry_enabled_use_set(+RepoEntry, -UseSet)
%
% Compute the set of USE flags that would be enabled for a repo entry
% based on IUSE categorization. Used for --newuse comparison.

entry_enabled_use_set(RepoEntry, UseSet) :-
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

symmetric_diff_nonempty(A, B) :-
  ( member(X, A), \+ memberchk(X, B) -> true
  ; member(X, B), \+ memberchk(X, A) -> true
  ).


% =============================================================================
%  REQUIRED_USE helpers
% =============================================================================

%! use:required_use_term_satisfied(+Term)
%
% Recursively check whether a REQUIRED_USE term is satisfied by the
% current effective USE state. Handles required/1, use_conditional_group/4,
% any_of_group/1, exactly_one_of_group/1, and at_most_one_of_group/1.

required_use_term_satisfied(required(Use)) :-
  \+ Use =.. [minus,_],
  effective_use_in_context([], Use, positive),
  !.
required_use_term_satisfied(required(minus(Use))) :-
  \+ Use =.. [minus,_],
  effective_use_in_context([], Use, negative),
  !.
required_use_term_satisfied(use_conditional_group(positive, Use, Self, Deps)) :-
  nb_current(query_required_use_self, Self),
  ( effective_use_in_context([], Use, positive) ->
      forall(member(D, Deps), required_use_term_satisfied(D))
  ; true
  ),
  !.
required_use_term_satisfied(use_conditional_group(negative, Use, Self, Deps)) :-
  nb_current(query_required_use_self, Self),
  ( effective_use_in_context([], Use, negative) ->
      forall(member(D, Deps), required_use_term_satisfied(D))
  ; true
  ),
  !.
required_use_term_satisfied(any_of_group(Deps)) :-
  member(D, Deps),
  required_use_term_satisfied(D),
  !.
required_use_term_satisfied(exactly_one_of_group(Deps)) :-
  findall(1, (member(D, Deps), required_use_term_satisfied(D)), Ones),
  length(Ones, 1),
  !.
required_use_term_satisfied(at_most_one_of_group(Deps)) :-
  findall(1, (member(D, Deps), required_use_term_satisfied(D)), Ones),
  length(Ones, N),
  N =< 1,
  !.
