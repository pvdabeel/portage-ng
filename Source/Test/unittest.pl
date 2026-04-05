/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> UNITTEST
PLUnit-based unit tests for core modules.

Covers pure-logic predicates in eapi, version_domain, constraint, kahn,
and sanitize that can be tested without a loaded knowledge base.

Run via the project wrapper:

  ./Source/Application/Wrapper/portage-ng-dev --mode standalone --shell <<'PL'
  load_files(portage('Source/Test/unittest'), [if(true)]).
  run_tests.
  halt.
  PL

Or via make:

  make test
*/

:- use_module(library(plunit)).
:- use_module(library(assoc)).
:- use_module(library(lists)).

:- set_test_options([load(always)]).


% =============================================================================
%  UNITTEST declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  EAPI version parsing tests
% -----------------------------------------------------------------------------

:- begin_tests(eapi_version_parsing).

test(simple_version, [true(V == version([1,0], '', 4, 0, '', 0, '1.0')), nondet]) :-
  atom_codes('1.0', Codes),
  phrase(eapi:version(V), Codes, []).

test(three_part_version, [true(V == version([1,2,3], '', 4, 0, '', 0, '1.2.3')), nondet]) :-
  atom_codes('1.2.3', Codes),
  phrase(eapi:version(V), Codes, []).

test(version_with_alpha, [nondet]) :-
  atom_codes('1.0a', Codes),
  phrase(eapi:version(version(_, Alpha, _, _, _, _, _)), Codes, []),
  Alpha \== ''.

test(version_with_revision, [nondet]) :-
  atom_codes('1.0-r1', Codes),
  phrase(eapi:version(version(_, _, _, _, _, Rev, _)), Codes, []),
  Rev == 1.

test(version_with_suffix_alpha, [nondet]) :-
  atom_codes('1.0_alpha1', Codes),
  phrase(eapi:version(version(_, _, Rank, _, _, _, _)), Codes, []),
  Rank == 0.

test(version_with_suffix_beta, [nondet]) :-
  atom_codes('1.0_beta2', Codes),
  phrase(eapi:version(version(_, _, Rank, _, _, _, _)), Codes, []),
  Rank == 1.

test(version_with_suffix_pre, [nondet]) :-
  atom_codes('1.0_pre3', Codes),
  phrase(eapi:version(version(_, _, Rank, _, _, _, _)), Codes, []),
  Rank == 2.

test(version_with_suffix_rc, [nondet]) :-
  atom_codes('1.0_rc1', Codes),
  phrase(eapi:version(version(_, _, Rank, _, _, _, _)), Codes, []),
  Rank == 3.

test(version_with_suffix_p, [nondet]) :-
  atom_codes('1.0_p1', Codes),
  phrase(eapi:version(version(_, _, Rank, _, _, _, _)), Codes, []),
  Rank == 5.

test(version_none_on_empty, [true(V == version_none)]) :-
  phrase(eapi:version0(V), [], []).

:- end_tests(eapi_version_parsing).


% -----------------------------------------------------------------------------
%  EAPI version comparison tests
% -----------------------------------------------------------------------------

:- begin_tests(eapi_version_compare).

test(equal_versions, [nondet]) :-
  atom_codes('1.0', C1), phrase(eapi:version(V1), C1, []),
  atom_codes('1.0', C2), phrase(eapi:version(V2), C2, []),
  eapi:version_compare(=, V1, V2).

test(less_than, [nondet]) :-
  atom_codes('1.0', C1), phrase(eapi:version(V1), C1, []),
  atom_codes('2.0', C2), phrase(eapi:version(V2), C2, []),
  eapi:version_compare(<, V1, V2).

test(greater_than, [nondet]) :-
  atom_codes('3.0', C1), phrase(eapi:version(V1), C1, []),
  atom_codes('2.0', C2), phrase(eapi:version(V2), C2, []),
  eapi:version_compare(>, V1, V2).

test(revision_ordering, [nondet]) :-
  atom_codes('1.0-r1', C1), phrase(eapi:version(V1), C1, []),
  atom_codes('1.0-r2', C2), phrase(eapi:version(V2), C2, []),
  eapi:version_compare(<, V1, V2).

test(suffix_ordering_alpha_before_beta, [nondet]) :-
  atom_codes('1.0_alpha1', C1), phrase(eapi:version(V1), C1, []),
  atom_codes('1.0_beta1', C2), phrase(eapi:version(V2), C2, []),
  eapi:version_compare(<, V1, V2).

test(suffix_ordering_rc_before_release, [nondet]) :-
  atom_codes('1.0_rc1', C1), phrase(eapi:version(V1), C1, []),
  atom_codes('1.0', C2), phrase(eapi:version(V2), C2, []),
  eapi:version_compare(<, V1, V2).

test(suffix_ordering_release_before_p, [nondet]) :-
  atom_codes('1.0', C1), phrase(eapi:version(V1), C1, []),
  atom_codes('1.0_p1', C2), phrase(eapi:version(V2), C2, []),
  eapi:version_compare(<, V1, V2).

test(pms_suffix_chain, [true(Order == [VA,VB,VC,VD,VE,VF]), nondet]) :-
  atom_codes('1.0_alpha1', CA), phrase(eapi:version(VA), CA, []),
  atom_codes('1.0_beta1', CB), phrase(eapi:version(VB), CB, []),
  atom_codes('1.0_pre1', CC), phrase(eapi:version(VC), CC, []),
  atom_codes('1.0_rc1', CD), phrase(eapi:version(VD), CD, []),
  atom_codes('1.0', CE), phrase(eapi:version(VE), CE, []),
  atom_codes('1.0_p1', CF), phrase(eapi:version(VF), CF, []),
  msort([VF, VD, VB, VE, VC, VA], Order).

:- end_tests(eapi_version_compare).


% -----------------------------------------------------------------------------
%  EAPI operator parsing tests
% -----------------------------------------------------------------------------

:- begin_tests(eapi_operator_parsing).

test(greater_equal, [true(Op == greaterequal)]) :-
  phrase(eapi:operator(Op), [62,61], []).

test(smaller_equal, [true(Op == smallerequal)]) :-
  phrase(eapi:operator(Op), [60,61], []).

test(greater, [true(Op == greater)]) :-
  phrase(eapi:operator(Op), [62], []).

test(smaller, [true(Op == smaller)]) :-
  phrase(eapi:operator(Op), [60], []).

test(equal, [true(Op == equal)]) :-
  phrase(eapi:operator(Op), [61], []).

test(tilde, [true(Op == tilde)]) :-
  phrase(eapi:operator(Op), [126], []).

test(none, [true(Op == none)]) :-
  phrase(eapi:operator(Op), [], []).

:- end_tests(eapi_operator_parsing).


% -----------------------------------------------------------------------------
%  EAPI blocking parsing tests
% -----------------------------------------------------------------------------

:- begin_tests(eapi_blocking_parsing).

test(strong_block, [true(B == strong)]) :-
  phrase(eapi:blocking(B), [33,33], []).

test(weak_block, [true(B == weak)]) :-
  phrase(eapi:blocking(B), [33], []).

test(no_block, [true(B == no)]) :-
  phrase(eapi:blocking(B), [], []).

:- end_tests(eapi_blocking_parsing).


% -----------------------------------------------------------------------------
%  EAPI keyword parsing tests
% -----------------------------------------------------------------------------

:- begin_tests(eapi_keyword_parsing).

test(stable_keyword, [true(K == stable(amd64))]) :-
  atom_codes(amd64, Codes),
  phrase(eapi:keyword(K), Codes, []).

test(unstable_keyword, [true(K == unstable(amd64))]) :-
  atom_codes('~amd64', Codes),
  phrase(eapi:keyword(K), Codes, []).

test(broken_keyword, [true(K == broken(amd64))]) :-
  atom_codes('-amd64', Codes),
  phrase(eapi:keyword(K), Codes, []).

test(keyword_list, [true(length(Ks, 3))]) :-
  atom_codes('amd64 ~arm64 -x86', Codes),
  phrase(eapi:keywords(Ks), Codes, []).

:- end_tests(eapi_keyword_parsing).


% -----------------------------------------------------------------------------
%  EAPI slot parsing tests
% -----------------------------------------------------------------------------

:- begin_tests(eapi_slot_parsing).

test(simple_slot, [true(S == [slot('0')])]) :-
  atom_codes('0', Codes),
  phrase(eapi:slot(S), Codes, []).

test(slot_with_subslot, [true(S == [slot('5'), subslot('3')])]) :-
  atom_codes('5/3', Codes),
  phrase(eapi:slot(S), Codes, []).

test(slot_restriction_star, [true(S == [any_different_slot])]) :-
  phrase(eapi:slot_restriction(S), [58,42], []).

test(slot_restriction_equal, [true(S == [any_same_slot])]) :-
  phrase(eapi:slot_restriction(S), [58,61], []).

test(slot_restriction_empty, [true(S == [])]) :-
  phrase(eapi:slot_restriction(S), [], []).

:- end_tests(eapi_slot_parsing).


% -----------------------------------------------------------------------------
%  EAPI IUSE parsing tests
% -----------------------------------------------------------------------------

:- begin_tests(eapi_iuse_parsing).

test(simple_iuse, [true(I == [test])]) :-
  atom_codes('test', Codes),
  phrase(eapi:iuse(repo://entry, I), Codes, []).

test(iuse_with_plus, [true(I == [plus(ssl)])]) :-
  atom_codes('+ssl', Codes),
  phrase(eapi:iuse(repo://entry, I), Codes, []).

test(iuse_with_minus, [true(I == [minus(debug)])]) :-
  atom_codes('-debug', Codes),
  phrase(eapi:iuse(repo://entry, I), Codes, []).

test(iuse_list, [true(length(I, 3))]) :-
  atom_codes('+ssl -debug test', Codes),
  phrase(eapi:iuse(repo://entry, I), Codes, []).

test(iuse_empty, [true(I == [])]) :-
  phrase(eapi:iuse(repo://entry, I), [], []).

:- end_tests(eapi_iuse_parsing).


% -----------------------------------------------------------------------------
%  EAPI package name parsing tests
% -----------------------------------------------------------------------------

:- begin_tests(eapi_package_parsing).

test(simple_name, [true(P == gcc)]) :-
  atom_codes(gcc, Codes),
  phrase(eapi:package(P), Codes, []).

test(hyphenated_name, [true(P == 'libxml2-utils')]) :-
  atom_codes('libxml2-utils', Codes),
  phrase(eapi:package(P), Codes, []).

test(name_with_plus, [true(P == 'gtk+')]) :-
  atom_codes('gtk+', Codes),
  phrase(eapi:package(P), Codes, []).

:- end_tests(eapi_package_parsing).


% -----------------------------------------------------------------------------
%  EAPI category parsing tests
% -----------------------------------------------------------------------------

:- begin_tests(eapi_category_parsing).

test(simple_category, [true(C == 'sys-apps')]) :-
  atom_codes('sys-apps', Codes),
  phrase(eapi:category(C), Codes, []).

test(virtual_category, [true(C == virtual)]) :-
  atom_codes(virtual, Codes),
  phrase(eapi:category(C), Codes, []).

:- end_tests(eapi_category_parsing).


% -----------------------------------------------------------------------------
%  EAPI dependency parsing tests
% -----------------------------------------------------------------------------

:- begin_tests(eapi_dependency_parsing).

test(simple_dep, [true(D == [package_dependency(install, no, 'dev-libs', openssl, none, version_none, [], [])])]) :-
  atom_codes('dev-libs/openssl', Codes),
  phrase(eapi:depend(repo://entry, D), Codes, []).

test(versioned_dep, [nondet]) :-
  atom_codes('>=dev-libs/openssl-1.1.0', Codes),
  phrase(eapi:depend(repo://entry, [package_dependency(install, no, 'dev-libs', openssl, greaterequal, V, [], [])]), Codes, []),
  V \== version_none.

test(blocked_dep, [true(D == [package_dependency(install, weak, 'dev-libs', foo, none, version_none, [], [])])]) :-
  atom_codes('!dev-libs/foo', Codes),
  phrase(eapi:depend(repo://entry, D), Codes, []).

test(strong_blocked_dep, [true(D == [package_dependency(install, strong, 'dev-libs', foo, none, version_none, [], [])])]) :-
  atom_codes('!!dev-libs/foo', Codes),
  phrase(eapi:depend(repo://entry, D), Codes, []).

test(multiple_deps, [true(length(D, 2))]) :-
  atom_codes('dev-libs/openssl dev-libs/glib', Codes),
  phrase(eapi:depend(repo://entry, D), Codes, []).

test(use_conditional_dep, [nondet]) :-
  atom_codes('ssl? ( dev-libs/openssl )', Codes),
  phrase(eapi:depend(repo://entry, [use_conditional_group(positive, ssl, _, _)]), Codes, []).

test(any_of_dep, [nondet]) :-
  atom_codes('|| ( dev-libs/openssl dev-libs/libressl )', Codes),
  phrase(eapi:depend(repo://entry, [any_of_group(_)]), Codes, []).

test(empty_dep, [true(D == [])]) :-
  phrase(eapi:depend(repo://entry, D), [], []).

:- end_tests(eapi_dependency_parsing).


% -----------------------------------------------------------------------------
%  EAPI metadata key=value parsing tests
% -----------------------------------------------------------------------------

:- begin_tests(eapi_keyvalue_parsing).

test(parse_description, [true(M == description(["A test package"]))]) :-
  atom_codes('DESCRIPTION=A test package', Codes),
  eapi:parse(metadata, repo://entry, Codes, M).

test(parse_slot, [true(M == slot([slot('0')]))]) :-
  atom_codes('SLOT=0', Codes),
  eapi:parse(metadata, repo://entry, Codes, M).

test(parse_eapi, [nondet]) :-
  atom_codes('EAPI=8', Codes),
  eapi:parse(metadata, repo://entry, Codes, eapi(_)).

test(parse_keywords, [nondet]) :-
  atom_codes('KEYWORDS=amd64 ~arm64', Codes),
  eapi:parse(metadata, repo://entry, Codes, keywords(Ks)),
  length(Ks, 2).

test(parse_defined_phases, [nondet]) :-
  atom_codes('DEFINED_PHASES=compile configure install', Codes),
  eapi:parse(metadata, repo://entry, Codes, defined_phases(P)),
  length(P, 3).

:- end_tests(eapi_keyvalue_parsing).


% -----------------------------------------------------------------------------
%  EAPI helper tests
% -----------------------------------------------------------------------------

:- begin_tests(eapi_helpers).

test(strip_use_default_plus, [true(U == ssl)]) :-
  eapi:strip_use_default(plus(ssl), U).

test(strip_use_default_minus, [true(U == debug)]) :-
  eapi:strip_use_default(minus(debug), U).

test(strip_use_default_bare, [true(U == test)]) :-
  eapi:strip_use_default(test, U).

test(check_prefix_atom_match) :-
  eapi:check_prefix_atom(python_targets, python_targets_python3_12).

test(check_prefix_atom_no_match, [fail]) :-
  eapi:check_prefix_atom(python_targets, ruby_targets_ruby31).

test(check_use_expand_atom_match) :-
  eapi:check_use_expand_atom(python_targets_python3_12).

test(check_use_expand_atom_no_match, [fail]) :-
  eapi:check_use_expand_atom(ssl).

test(version2numberlist, [true(N == [1,2,3])]) :-
  eapi:version2numberlist('1.2.3', N).

test(version2numberlist_empty, [true(N == [])]) :-
  eapi:version2numberlist('', N).

test(split_ws_atoms, [true(A == [foo, bar, baz])]) :-
  eapi:split_ws_atoms("foo bar baz", A).

test(split_ws_atoms_empty, [true(A == [])]) :-
  eapi:split_ws_atoms("", A).

test(parse_iuse_search_plus, [true((Sign == plus, Pat == foo))]) :-
  eapi:parse_iuse_search_value('+foo', Sign, Pat).

test(parse_iuse_search_minus, [true((Sign == minus, Pat == bar))]) :-
  eapi:parse_iuse_search_value('-bar', Sign, Pat).

test(parse_iuse_search_bare, [true((Sign == any, Pat == baz))]) :-
  eapi:parse_iuse_search_value(baz, Sign, Pat).

:- end_tests(eapi_helpers).


% -----------------------------------------------------------------------------
%  EAPI manifest parsing tests
% -----------------------------------------------------------------------------

:- begin_tests(eapi_manifest_parsing).

test(parse_ebuild_manifest, [nondet]) :-
  atom_codes('EBUILD foo-1.0.ebuild 1234 SHA512:abc', Codes),
  eapi:parse(manifest, repo://entry, Codes, manifest(ebuild, _, _, _)).

test(parse_dist_manifest, [nondet]) :-
  atom_codes('DIST foo-1.0.tar.gz 56789 SHA512:def', Codes),
  eapi:parse(manifest, repo://entry, Codes, manifest(dist, _, Size, _)),
  Size == 56789.

:- end_tests(eapi_manifest_parsing).


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
%  Constraint module tests
% -----------------------------------------------------------------------------

:- begin_tests(constraint_identification).

test(is_constraint_true) :-
  constraint:is_constraint(constraint(foo)).

test(is_constraint_false, [fail]) :-
  constraint:is_constraint(not_a_constraint).

:- end_tests(constraint_identification).


:- begin_tests(constraint_unification).

test(unify_ordset_new) :-
  empty_assoc(C0),
  constraint:unify_constraints(constraint(k:{ordset([b,a,c])}), C0, C1),
  get_assoc(k, C1, ordset(V)),
  V == [a,b,c].

test(unify_ordset_merge) :-
  empty_assoc(C0),
  put_assoc(k, C0, ordset([a,c]), C1),
  constraint:unify_constraints(constraint(k:{ordset([b,d])}), C1, C2),
  get_assoc(k, C2, ordset(V)),
  V == [a,b,c,d].

test(unify_atom_new) :-
  empty_assoc(C0),
  constraint:unify_constraints(constraint(k:{hello}), C0, C1),
  get_assoc(k, C1, V),
  V == hello.

:- end_tests(constraint_unification).


:- begin_tests(constraint_conversion).

test(empty_to_list, [true(L == [])]) :-
  empty_assoc(A),
  constraint:constraints_to_list(A, L).

:- end_tests(constraint_conversion).


% -----------------------------------------------------------------------------
%  EAPI VDB slot parsing tests
% -----------------------------------------------------------------------------

:- begin_tests(eapi_vdb_slot).

test(simple_slot_line, [true(T == [slot('0')])]) :-
  eapi:parse_vdb_slot_line('0', T).

test(slot_with_subslot, [true(T == [slot('5'), subslot('3')])]) :-
  eapi:parse_vdb_slot_line('5/3', T).

:- end_tests(eapi_vdb_slot).


% -----------------------------------------------------------------------------
%  EAPI metadata normalization tests
% -----------------------------------------------------------------------------

:- begin_tests(eapi_normalize_metadata).

test(slot_number_normalized) :-
  eapi:normalize_entry_metadata(slot, slot(3), slot('3')).

test(non_slot_passthrough, [true(I == depend(foo))]) :-
  eapi:normalize_entry_metadata(depend, depend(foo), I).

:- end_tests(eapi_normalize_metadata).


% =============================================================================
%  Kahn topological sort tests
% =============================================================================

:- begin_tests(kahn_toposort).

test(empty_graph, [true(Order-Cyclic == []-false)]) :-
  empty_assoc(E),
  kahn:toposort([], E, Order, Cyclic).

test(single_node, [true(Order-Cyclic == [a]-false)]) :-
  list_to_assoc([a-[]], E),
  kahn:toposort([a], E, Order, Cyclic).

test(linear_chain, [true(Order-Cyclic == [a,b,c]-false)]) :-
  list_to_assoc([a-[b], b-[c], c-[]], E),
  kahn:toposort([a,b,c], E, Order, Cyclic).

test(diamond_dag, [true(Cyclic == false)]) :-
  list_to_assoc([a-[b,c], b-[d], c-[d], d-[]], E),
  kahn:toposort([a,b,c,d], E, Order, Cyclic),
  Order = [a|_],
  last(Order, d).

test(two_component, [true(Cyclic == false)]) :-
  list_to_assoc([a-[b], b-[], x-[y], y-[]], E),
  kahn:toposort([a,b,x,y], E, Order, Cyclic),
  length(Order, 4).

test(simple_cycle, [true(Cyclic == true)]) :-
  list_to_assoc([a-[b], b-[a]], E),
  kahn:toposort([a,b], E, Order, Cyclic),
  length(Order, 2).

test(partial_cycle, [true(Cyclic == true)]) :-
  list_to_assoc([a-[b], b-[c], c-[b], d-[]], E),
  kahn:toposort([a,b,c,d], E, Order, Cyclic),
  memberchk(d, Order).

test(self_loop, [true(Cyclic == true)]) :-
  list_to_assoc([a-[a]], E),
  kahn:toposort([a], E, Order, Cyclic),
  length(Order, 1).

:- end_tests(kahn_toposort).


% =============================================================================
%  Sanitize validation tests
% =============================================================================

:- begin_tests(sanitize_path).

test(valid_component) :-
  sanitize:safe_path_component(hello).

test(valid_component_with_dot) :-
  sanitize:safe_path_component('file.txt').

test(reject_empty, [fail]) :-
  sanitize:safe_path_component('').

test(reject_slash, [fail]) :-
  sanitize:safe_path_component('a/b').

test(reject_dotdot, [fail]) :-
  sanitize:safe_path_component('..').

test(reject_embedded_dotdot, [fail]) :-
  sanitize:safe_path_component('foo/../bar').

test(reject_non_atom, [fail]) :-
  sanitize:safe_path_component(123).

:- end_tests(sanitize_path).


:- begin_tests(sanitize_filename).

test(valid_filename) :-
  sanitize:safe_filename('package-1.0.ebuild').

test(reject_directory_traversal, [fail]) :-
  sanitize:safe_filename('../etc/passwd').

:- end_tests(sanitize_filename).


:- begin_tests(sanitize_category).

test(valid_category) :-
  sanitize:safe_portage_category('sys-apps').

test(reject_slash, [fail]) :-
  sanitize:safe_portage_category('sys/apps').

test(reject_empty, [fail]) :-
  sanitize:safe_portage_category('').

:- end_tests(sanitize_category).


:- begin_tests(sanitize_name).

test(valid_name) :-
  sanitize:safe_portage_name(portage).

test(reject_traversal, [fail]) :-
  sanitize:safe_portage_name('../../etc').

:- end_tests(sanitize_name).


:- begin_tests(sanitize_snapshot).

test(valid_id) :-
  sanitize:safe_snapshot_id('snap-2026-01-01').

test(reject_slash, [fail]) :-
  sanitize:safe_snapshot_id('snap/bad').

test(reject_backslash, [fail]) :-
  sanitize:safe_snapshot_id('snap\\bad').

test(reject_dotdot, [fail]) :-
  sanitize:safe_snapshot_id('snap..bad').

:- end_tests(sanitize_snapshot).


:- begin_tests(sanitize_phase).

test(known_phase) :-
  sanitize:safe_phase(compile).

test(all_phases) :-
  forall(member(P, [clean,setup,unpack,prepare,configure,compile,
                    test,install,package,merge,unmerge,
                    preinst,postinst,prerm,postrm,config,info,nofetch]),
         sanitize:safe_phase(P)).

test(unknown_phase, [fail]) :-
  sanitize:safe_phase(bogus).

:- end_tests(sanitize_phase).


:- begin_tests(sanitize_daemon_request).

test(shutdown) :-
  sanitize:safe_daemon_request(shutdown).

test(valid_request) :-
  sanitize:safe_daemon_request(request([foo, bar], 80, 24)).

test(valid_request_with_env) :-
  sanitize:safe_daemon_request(request([foo], 80, 24, [a,b])).

test(reject_bad_args, [fail]) :-
  sanitize:safe_daemon_request(request(notalist, 80, 24)).

:- end_tests(sanitize_daemon_request).


% =============================================================================
%  Depclean structural predicate tests
% =============================================================================

:- begin_tests(depclean_model_item).

test(extract_depclean_bare, [true(R == myrepo://'cat/pkg-1.0')]) :-
  depclean:model_item_repo_entry(myrepo://'cat/pkg-1.0':depclean, R).

test(extract_depclean_ctx, [true(R == myrepo://'cat/pkg-1.0')]) :-
  depclean:model_item_repo_entry(myrepo://'cat/pkg-1.0':depclean?{[]}, R).

test(reject_non_depclean, [fail]) :-
  depclean:model_item_repo_entry(myrepo://'cat/pkg-1.0':install, _).

test(reject_plain_atom, [fail]) :-
  depclean:model_item_repo_entry(something, _).

:- end_tests(depclean_model_item).


:- begin_tests(depclean_dep_term_cn).

test(with_action_ctx, [true(A-C-N == run-'sys-libs'-glibc)]) :-
  depclean:dep_term_cn_deps(
    grouped_package_dependency(strong,'sys-libs',glibc,[dep1]):run?{[some_ctx]},
    A, C, N, _).

test(with_action_bare, [true(A-C-N == install-'dev-libs'-openssl)]) :-
  depclean:dep_term_cn_deps(
    grouped_package_dependency(weak,'dev-libs',openssl,[]):install,
    A, C, N, _).

test(no_action_defaults_run, [true(A-C-N == run-'app-misc'-foo)]) :-
  depclean:dep_term_cn_deps(
    grouped_package_dependency(strong,'app-misc',foo,[d1,d2]),
    A, C, N, _).

test(extracts_packagedeps, [true(PD == [d1,d2])]) :-
  depclean:dep_term_cn_deps(
    grouped_package_dependency(strong,c,n,[d1,d2]),
    _, _, _, PD).

:- end_tests(depclean_dep_term_cn).


:- begin_tests(depclean_provides_tok).

test(new_token, [true(V == [pkg://e1])]) :-
  empty_assoc(E),
  depclean:provides_tok_put(pkg://e1, 'libfoo.so', E, Out),
  get_assoc('libfoo.so', Out, V).

test(existing_token, [true(V == [pkg://e1, pkg://e2])]) :-
  list_to_assoc(['libfoo.so'-[pkg://e1]], In),
  depclean:provides_tok_put(pkg://e2, 'libfoo.so', In, Out),
  get_assoc('libfoo.so', Out, V).

:- end_tests(depclean_provides_tok).


% =============================================================================
%  USE helper predicate tests
% =============================================================================

:- begin_tests(use_empty_state).

test(empty_state, [true(S == use_state([],[]))]) :-
  use:empty_use_state(S).

:- end_tests(use_empty_state).


:- begin_tests(use_normalize_bwu).

test(already_state, [true(R == use_state([a,b],[c]))]) :-
  use:normalize_build_with_use(use_state([b,a],[c]), R).

test(list_form, [true(R == use_state([x],[y]))]) :-
  use:normalize_build_with_use([required(x), naf(required(y))], R).

test(unknown_form, [true(R == use_state([],[]))]) :-
  use:normalize_build_with_use(42, R).

:- end_tests(use_normalize_bwu).


:- begin_tests(use_context_bwu).

test(with_bwu, [true(S == use_state([a],[]))]) :-
  use:context_build_with_use_state([build_with_use:use_state([a],[])], S).

test(without_bwu, [true(S == use_state([],[]))]) :-
  use:context_build_with_use_state([other_key:val], S).

test(empty_ctx, [true(S == use_state([],[]))]) :-
  use:context_build_with_use_state([], S).

:- end_tests(use_context_bwu).


:- begin_tests(use_bwu_requirements).

test(state_form, [true(En-Dis == [a,b]-[c])]) :-
  use:build_with_use_requirements(use_state([b,a],[c]), En, Dis).

test(list_form_enable, [true(En == [x])]) :-
  use:build_with_use_requirements([required(x)], En, _).

test(list_form_disable_naf, [true(Dis == [y])]) :-
  use:build_with_use_requirements([naf(required(y))], _, Dis).

test(list_form_disable_assumed, [true(Dis == [z])]) :-
  use:build_with_use_requirements([assumed(minus(z))], _, Dis).

:- end_tests(use_bwu_requirements).


:- begin_tests(use_iuse_assoc).

test(single_pair, [true(V == positive)]) :-
  use:iuse_default_pairs_to_assoc([foo-positive], M),
  get_assoc(foo, M, V).

test(positive_wins, [true(V == positive)]) :-
  use:iuse_default_pairs_to_assoc([foo-negative, foo-positive], M),
  get_assoc(foo, M, V).

test(negative_no_override, [true(V == negative)]) :-
  use:iuse_default_pairs_to_assoc([foo-negative, foo-negative], M),
  get_assoc(foo, M, V).

test(empty_list) :-
  use:iuse_default_pairs_to_assoc([], M),
  empty_assoc(M).

:- end_tests(use_iuse_assoc).


:- begin_tests(use_symmetric_diff).

test(different_lists) :-
  use:symmetric_diff_nonempty([a,b], [b,c]).

test(same_lists, [fail]) :-
  use:symmetric_diff_nonempty([a,b], [a,b]).

test(both_empty, [fail]) :-
  use:symmetric_diff_nonempty([], []).

test(one_empty) :-
  use:symmetric_diff_nonempty([a], []).

:- end_tests(use_symmetric_diff).


:- begin_tests(use_abi_x86_flag).

test(valid_abi_flag) :-
  use:is_abi_x86_flag(abi_x86_64).

test(valid_abi_flag_32) :-
  use:is_abi_x86_flag(abi_x86_32).

test(not_abi_flag, [fail]) :-
  use:is_abi_x86_flag(python_targets_python3_12).

test(not_atom, [fail]) :-
  use:is_abi_x86_flag(123).

:- end_tests(use_abi_x86_flag).


% =============================================================================
%  Linkage tests
% =============================================================================

:- begin_tests(linkage_is_linkable).

test(shared_object) :-
  linkage:is_linkable('/usr/lib64/libz.so').

test(versioned_so) :-
  linkage:is_linkable('/usr/lib64/libz.so.1.2.13').

test(usr_bin) :-
  linkage:is_linkable('/usr/bin/bash').

test(usr_sbin) :-
  linkage:is_linkable('/usr/sbin/sshd').

test(usr_lib_prefix) :-
  linkage:is_linkable('/usr/lib64/something').

test(bin) :-
  linkage:is_linkable('/bin/sh').

test(sbin) :-
  linkage:is_linkable('/sbin/init').

test(lib_prefix) :-
  linkage:is_linkable('/lib64/ld-linux-x86-64.so.2').

test(reject_etc, [fail]) :-
  linkage:is_linkable('/etc/portage/make.conf').

test(reject_var, [fail]) :-
  linkage:is_linkable('/var/log/messages').

test(reject_share, [fail]) :-
  linkage:is_linkable('/usr/share/doc/readme.txt').

:- end_tests(linkage_is_linkable).


% =============================================================================
%  Version domain additional tests
% =============================================================================

:- begin_tests(version_normalize_term).

test(var_passthrough) :-
  version_domain:normalize_version_term(X, Y),
  var(Y),
  X == Y.

test(wildcard_atom, [true(Ver == version([0],'',4,0,'',0,'1.0.*'))]) :-
  version_domain:normalize_version_term('1.0.*', Ver).

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

:- end_tests(version_slot_domain_from_reqs).