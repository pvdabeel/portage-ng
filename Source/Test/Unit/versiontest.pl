/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> VERSIONTEST
Unit tests for the version domain model (Source/Domain/Gentoo/version.pl).

Domain normalization, meet, consistency, bound operations, constraint
satisfaction, slot canonicalization and slot meets.
*/

:- module(versiontest, []).

:- use_module(library(plunit)).
:- use_module(library(lists)).

% =============================================================================
%  VERSIONTEST declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Version domain normalization tests
% -----------------------------------------------------------------------------

:- begin_tests(version_domain_normalize).

test(normalize_none, [true(D == none)]) :-
  version_domain:domain_normalize(none, D).

test(normalize_unknown, [true(D == none)]) :-
  version_domain:domain_normalize(something_else, D).

test(normalize_domain_identity, [nondet]) :-
  version_domain:domain_normalize(
    version_domain(any, [bound(smallerequal, v1)]),
    version_domain(any, [bound(smallerequal, v1)])
  ).

test(normalize_slot_any, [true(S == any)]) :-
  version_domain:normalize_slot_domain(any, S).

test(normalize_slot_sorts, [true(S == slots([a, b, c]))]) :-
  version_domain:normalize_slot_domain(slots([c, a, b]), S).

:- end_tests(version_domain_normalize).


% -----------------------------------------------------------------------------
%  Version domain meet tests
% -----------------------------------------------------------------------------

:- begin_tests(version_domain_meet).

test(meet_none_left, [true(D == version_domain(any, [bound(equal, v1)]))]) :-
  version_domain:domain_meet(
    none,
    version_domain(any, [bound(equal, v1)]),
    D
  ).

test(meet_none_right, [true(D == version_domain(any, [bound(equal, v1)]))]) :-
  version_domain:domain_meet(
    version_domain(any, [bound(equal, v1)]),
    none,
    D
  ).

test(meet_both_none, [true(D == none)]) :-
  version_domain:domain_meet(none, none, D).

test(meet_bounds_union) :-
  version_domain:domain_meet(
    version_domain(any, [bound(equal, v1)]),
    version_domain(any, [bound(smallerequal, v2)]),
    version_domain(any, Bounds)
  ),
  length(Bounds, 2).

test(meet_slot_intersection) :-
  version_domain:domain_meet(
    version_domain(slots([a, b, c]), []),
    version_domain(slots([b, c, d]), []),
    version_domain(slots(S), _)
  ),
  S == [b, c].

test(meet_empty_slot_intersection_fails, [fail]) :-
  version_domain:domain_meet(
    version_domain(slots([a]), []),
    version_domain(slots([b]), []),
    _
  ).

:- end_tests(version_domain_meet).


% -----------------------------------------------------------------------------
%  Version domain consistency tests
% -----------------------------------------------------------------------------

:- begin_tests(version_domain_consistency).

test(empty_slots_inconsistent) :-
  version_domain:domain_inconsistent(version_domain(slots([]), [])).

test(any_slots_consistent, [fail]) :-
  version_domain:domain_inconsistent(version_domain(any, [])).

test(non_domain_consistent, [fail]) :-
  version_domain:domain_inconsistent(something_else).

test(two_different_exact_bounds_inconsistent) :-
  version_domain:bounds_inconsistent([bound(equal, v1), bound(equal, v2)]).

test(single_exact_bound_consistent, [fail]) :-
  version_domain:bounds_inconsistent([bound(equal, v1)]).

test(two_disjoint_wildcard_bounds_inconsistent) :-
  V29 = version([6,29], '', 4, 0, [], 0, '6.29*'),
  V31 = version([6,31], '', 4, 0, [], 0, '6.31*'),
  version_domain:bounds_inconsistent([bound(wildcard, V29), bound(wildcard, V31)]).

test(two_adjacent_wildcard_bounds_inconsistent) :-
  V30 = version([6,30], '', 4, 0, [], 0, '6.30*'),
  V31 = version([6,31], '', 4, 0, [], 0, '6.31*'),
  version_domain:bounds_inconsistent([bound(wildcard, V30), bound(wildcard, V31)]).

:- end_tests(version_domain_consistency).


% -----------------------------------------------------------------------------
%  Version domain bound normalization tests
% -----------------------------------------------------------------------------

:- begin_tests(version_domain_bound_ops).

test(normalize_smallerorequal, [true(N == smallerequal)]) :-
  version_domain:normalize_bound_op(smallerorequal, N).

test(normalize_smallerequal, [true(N == smallerequal)]) :-
  version_domain:normalize_bound_op(smallerequal, N).

test(normalize_smaller, [true(N == smaller)]) :-
  version_domain:normalize_bound_op(smaller, N).

test(normalize_equal, [true(N == equal)]) :-
  version_domain:normalize_bound_op(equal, N).

test(normalize_wildcard, [true(N == wildcard)]) :-
  version_domain:normalize_bound_op(wildcard, N).

test(normalize_greater_drops, [true(N == none)]) :-
  version_domain:normalize_bound_op(greater, N).

test(normalize_greaterequal_drops, [true(N == none)]) :-
  version_domain:normalize_bound_op(greaterequal, N).

test(normalize_unknown_drops, [true(N == none)]) :-
  version_domain:normalize_bound_op(random_op, N).

:- end_tests(version_domain_bound_ops).


% -----------------------------------------------------------------------------
%  Version constraint holds tests
% -----------------------------------------------------------------------------

:- begin_tests(version_constraint_holds).

test(none_bound_always_holds) :-
  version_domain:version_constraint_holds(anything, bound(none, anything)).

test(equal_holds) :-
  version_domain:version_constraint_holds(v1, bound(equal, v1)).

test(equal_fails, [fail]) :-
  version_domain:version_constraint_holds(v1, bound(equal, v2)).

test(notequal_holds) :-
  version_domain:version_constraint_holds(v1, bound(notequal, v2)).

test(notequal_fails, [fail]) :-
  version_domain:version_constraint_holds(v1, bound(notequal, v1)).

test(unknown_op_non_blocking) :-
  version_domain:version_constraint_holds(v1, bound(weird_op, v2)).

test(wildcard_holds_for_matching_prefix) :-
  Pat = version([6,31], '', 4, 0, [], 0, '6.31*'),
  Ver = version([6,31,0], '', 4, 0, [], 0, '6.31.0'),
  version_domain:version_constraint_holds(Ver, bound(wildcard, Pat)).

test(wildcard_fails_for_older_prefix, [fail]) :-
  Pat = version([6,31], '', 4, 0, [], 0, '6.31*'),
  Ver = version([6,29,0], '', 4, 0, [], 0, '6.29.0'),
  version_domain:version_constraint_holds(Ver, bound(wildcard, Pat)).

:- end_tests(version_constraint_holds).


% -----------------------------------------------------------------------------
%  Canon slot tests
% -----------------------------------------------------------------------------

:- begin_tests(version_domain_canon_slot).

test(atom_passthrough, [true(S == foo)]) :-
  version_domain:canon_slot(foo, S).

test(integer_to_atom, [true(S == '42')]) :-
  version_domain:canon_slot(42, S).

test(float_to_atom) :-
  version_domain:canon_slot(3.2, S),
  atom(S).

:- end_tests(version_domain_canon_slot).


% -----------------------------------------------------------------------------
%  Slot domain meet tests
% -----------------------------------------------------------------------------

:- begin_tests(version_domain_slot_meet).

test(any_any, [true(D == any)]) :-
  version_domain:meet_slot_domains(any, any, D).

test(any_slots, [true(D == slots([a]))]) :-
  version_domain:meet_slot_domains(any, slots([a]), D).

test(slots_any, [true(D == slots([b]))]) :-
  version_domain:meet_slot_domains(slots([b]), any, D).

test(slots_intersection, [true(D == slots([b]))]) :-
  version_domain:meet_slot_domains(slots([a,b,c]), slots([b,d]), D).

:- end_tests(version_domain_slot_meet).


% -----------------------------------------------------------------------------
%  Version domain additional tests
% -----------------------------------------------------------------------------
:- begin_tests(version_normalize_term).

test(var_passthrough) :-
  Goal = version_domain:normalize_version_term(X, Y),
  call(Goal),
  var(Y),
  X == Y.

test(version_compound_passthrough) :-
  V = version([1,0], '', 4, 0, [], 0, '1.0'),
  Goal = version_domain:normalize_version_term(V, Out),
  call(Goal),
  Out == V.

test(wildcard_atom, [true(Ver == version([0],'',4,0,[],0,'1.0.*'))]) :-
  Goal = version_domain:normalize_version_term('1.0.*', Ver),
  call(Goal).

test(compound_passthrough, [true(Ver == foo(bar))]) :-
  version_domain:normalize_version_term(foo(bar), Ver).

test(version_eq_strip, [true(Ver == myver)]) :-
  version_domain:normalize_version_term(version(a,b,c,d,e,f,g)=myver, Ver).

:- end_tests(version_normalize_term).


:- begin_tests(version_slot_domain_from_reqs).

test(empty_reqs, [true(D == any)]) :-
  version_domain:slot_domain_from_reqs([], D).

test(single_slot_req, [true(D == slots(['3']))]) :-
  version_domain:slot_domain_from_reqs([[slot(3)]], D).

test(any_same_slot, [true(D == any)]) :-
  version_domain:slot_domain_from_reqs([[any_same_slot]], D).

test(any_different_slot, [true(D == any)]) :-
  version_domain:slot_domain_from_reqs([[any_different_slot]], D).

test(unknown_slot_req_defaults_to_any, [true(D == any)]) :-
  version_domain:slot_req_domain([other_req], D).

test(normalize_slot_domain_fallback, [true(D == any)]) :-
  version_domain:normalize_slot_domain(other_domain_shape, D).

test(feature_unification_val_hook_variants) :-
  D1 = version_domain(any, [bound(equal, v1)]),
  D2 = version_domain(any, [bound(smallerequal, v2)]),
  feature_unification:val_hook(D1, D2, version_domain(any, Bounds)),
  length(Bounds, 2),
  feature_unification:val_hook(none, D1, D1),
  feature_unification:val_hook(D1, none, D1).

test(collect_slots_and_bounds_skips_other_cn) :-
  V1 = version([1,0], '', 4, 0, [], 0, '1.0'),
  Deps = [package_dependency(install, no, other_cat, other_pkg, smaller, V1, [slot('0')], []),
          package_dependency(install, no, my_cat, my_pkg, smallerorequal, V1, [slot('1')], [])],
  version_domain:domain_from_packagedeps(install, my_cat, my_pkg, Deps, Dom),
  Dom == version_domain(slots(['1']), [bound(smallerequal, V1)]).

test(lower_and_upper_op_conflicts) :-
  V1 = version([1,0], '', 4, 0, [], 0, '1.0'),
  V2 = version([2,0], '', 4, 0, [], 0, '2.0'),
  version_domain:bounds_inconsistent([bound(greater, V2), bound(smaller, V1)]),
  version_domain:bounds_inconsistent([bound(greaterequal, V2), bound(smallerequal, V1)]).

test(candidate_satisfies_none_bound_and_domain_satisfiable,
     [setup(assertz(cache:ordered_entry(vtest_repo, 'vtest_cat/vtest_pkg-1.0',
                                        vtest_cat, vtest_pkg,
                                        version([1,0],'',4,0,[],0,'1.0')))),
      cleanup(retractall(cache:ordered_entry(vtest_repo, _, _, _, _)))]) :-
  version_domain:candidate_satisfies_bound(vtest_repo://'vtest_cat/vtest_pkg-1.0',
                                           bound(none, anything)),
  version_domain:domain_satisfiable(vtest_cat, vtest_pkg, none),
  version_domain:domain_satisfiable(vtest_cat, vtest_pkg, version_domain(any, [])).

test(display_atom_and_upper_bound_helpers) :-
  version_domain:display_atom(custom_term(1), 'custom_term(1)'),
  version_domain:dep_bound_op(smallerorequal, smallerequal),
  version_domain:wildcard_base_nums([1, 2, 3, '0.6*'], [0, 6]),
  version_domain:wildcard_upper_bound('0.6*', version([0, 7], '', 4, 0, [], 0, '0.7')),
  version_domain:tilde_upper_bound('8.1.1', version([8, 1, 2], '', 4, 0, [], 0, '8.1.2')).

:- end_tests(version_slot_domain_from_reqs).
