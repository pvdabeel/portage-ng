/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> USE
USE flag evaluation, conditionals, REQUIRED_USE groups, and build_with_use
state management for the rules engine.

Provides the implementation predicates that rule/2 bodies delegate to for
USE-related decisions: effective USE resolution, IUSE defaults, USE
conditional activation, candidate USE satisfaction checks, and
build_with_use constraint propagation.
*/

:- module(use, [effective_use_in_context/3,
                effective_use_for_entry/3,
                entry_iuse_default/3,
                context_build_with_use_state/2,
                candidate_satisfies_use_deps/3,
                use_dep_requirement/4,
                self_context_use_state/3,
                entry_iuse_info/2,
                entry_effective_use_set/2,
                candidate_iuse_present/2,
                candidate_effective_use_enabled_in_iuse/2,
                installed_pkg_satisfies_use_reqs/3,
                installed_entry_satisfies_build_with_use/2,
                context_build_with_use_list/2,
                build_with_use_requirements/3,
                newuse_mismatch/1,
                newuse_mismatch/2,
                required_use_term_satisfied/1]).


% =============================================================================
%  Effective USE in context
% =============================================================================

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
%  Per-entry IUSE default map (performance)
% =============================================================================

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
%  Per-entry IUSE memoization (performance)
% =============================================================================

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

empty_use_state(use_state([],[])).

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

context_build_with_use_state(Context, State) :-
  ( memberchk(build_with_use:BWU, Context) ->
      normalize_build_with_use(BWU, State)
  ; empty_use_state(State)
  ),
  !.

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

candidate_satisfies_use_deps(_ParentContext, _Repo://_Entry, []) :- !.
candidate_satisfies_use_deps(ParentContext, Repo://Entry, [use(Directive, Default)|Rest]) :-
  use_dep_requirement(ParentContext, Directive, Default, Requirement),
  candidate_satisfies_use_requirement_opt(Directive, Repo://Entry, Requirement),
  candidate_satisfies_use_deps(ParentContext, Repo://Entry, Rest).

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

candidate_iuse_present(Repo://Entry, Use) :-
  entry_iuse_info(Repo://Entry, iuse_info(IuseSet, _PlusSet)),
  memberchk(Use, IuseSet),
  !.

use_dep_default_satisfies_absent_iuse(positive, enable) :- !.
use_dep_default_satisfies_absent_iuse(negative, disable) :- !.
use_dep_default_satisfies_absent_iuse(_Default, _Mode) :- fail.


% =============================================================================
%  Candidate effective USE evaluation
% =============================================================================

candidate_effective_use_enabled_in_iuse(Repo://Entry, Use) :-
  entry_effective_use_set(Repo://Entry, EnabledSet),
  memberchk(Use, EnabledSet).

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

use_expand_selector_flag_unset(Use) :-
  atom(Use),
  preference:use_expand_env(_EnvVar, Prefix),
  atom_concat(Prefix, '_', PrefixUnderscore),
  atom_concat(PrefixUnderscore, _, Use),
  use_expand_prefix_has_explicit_selection(Prefix),
  \+ preference:use(Use),
  \+ preference:use(minus(Use)),
  !.

use_expand_prefix_has_explicit_selection(Prefix) :-
  atom_concat(Prefix, '_', PrefixUnderscore),
  ( preference:use(Use0)
  ; preference:use(minus(Use0))
  ),
  atom(Use0),
  atom_concat(PrefixUnderscore, _, Use0),
  !.

is_abi_x86_flag(Use) :-
  atom(Use),
  sub_atom(Use, 0, _, _, abi_x86_),
  !.


% =============================================================================
%  Installed package USE satisfaction checks
% =============================================================================

installed_pkg_satisfies_use_reqs(_ParentContext, _Installed, []) :- !.
installed_pkg_satisfies_use_reqs(ParentContext, pkg://InstalledId,
                                    [use(Directive, Default)|Rest]) :-
  !,
  use_dep_requirement(ParentContext, Directive, Default, Req),
  installed_pkg_satisfies_use_requirement(pkg://InstalledId, Req),
  installed_pkg_satisfies_use_reqs(ParentContext, pkg://InstalledId, Rest).
installed_pkg_satisfies_use_reqs(ParentContext, Installed, [_|Rest]) :-
  installed_pkg_satisfies_use_reqs(ParentContext, Installed, Rest).

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

newuse_mismatch(pkg://InstalledEntry) :-
  query:search([category(C),name(N),version(V)], pkg://InstalledEntry),
  preference:accept_keywords(K),
  ( query:search([select(repository,notequal,pkg),category(C),name(N),keywords(K),version(V)],
                 CurRepo//CurEntry)
  -> newuse_mismatch(pkg://InstalledEntry, CurRepo//CurEntry)
  ;  fail
  ).

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

vdb_enabled_use_set(RepoEntry, UseSet) :-
  findall(U, query:search(use(U), RepoEntry), Us0),
  sort(Us0, UseSet).

entry_iuse_set(RepoEntry, IuseSet) :-
  findall(U,
          ( query:search(iuse(Value), RepoEntry),
            eapi:strip_use_default(Value, U)
          ),
          Us0),
  sort(Us0, IuseSet).

vdb_iuse_set(RepoEntry, IuseSet) :-
  entry_iuse_set(RepoEntry, IuseSet).

entry_enabled_use_set(RepoEntry, UseSet) :-
  findall(U,
          ( query:search(iuse(Value), RepoEntry),
            eapi:categorize_use(Value, positive, _Reason),
            eapi:strip_use_default(Value, U)
          ),
          Us0),
  sort(Us0, UseSet).

symmetric_diff_nonempty(A, B) :-
  ( member(X, A), \+ memberchk(X, B) -> true
  ; member(X, B), \+ memberchk(X, A) -> true
  ).


% =============================================================================
%  REQUIRED_USE helpers
% =============================================================================

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
