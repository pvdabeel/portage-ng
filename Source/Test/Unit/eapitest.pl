/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> EAPITEST
Unit tests for the EAPI grammar (Source/Domain/Gentoo/eapi.pl).

Version parsing and PMS comparison, operators, blockers, keywords,
slots, IUSE, package and category names, dependency trees, key=value
metadata, Manifest and SRC_URI lines, REQUIRED_USE, LICENSE, bracketed
USE dependencies, VDB slot lines, metadata normalization, and nested
`@set` expansion. Grammar tests need no knowledge base; set-expansion
tests assert temporary `preference:local_set/2` facts.
*/

:- module(eapitest, []).

:- use_module(library(plunit)).
:- use_module(library(lists)).

% =============================================================================
%  EAPITEST declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  EAPI version parsing tests
% -----------------------------------------------------------------------------

:- begin_tests(eapi_version_parsing).

test(simple_version, [true(V == version([1,0], '', 4, 0, [], 0, '1.0')), nondet]) :-
  atom_codes('1.0', Codes),
  phrase(eapi:version(V), Codes, []).

test(three_part_version, [true(V == version([1,2,3], '', 4, 0, [], 0, '1.2.3')), nondet]) :-
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

%! pms_version(+Atom, -Version) is det.
%
% Parses a PMS version atom into its version/7 term. Shared fixture for the
% version comparison units below.

pms_version(Atom, V) :-
  atom_codes(Atom, Codes),
  phrase(eapi:version(V), Codes, []),
  !.


%! pms_compare(+Op, +AtomA, +AtomB) is semidet.
%
% eapi:version_compare/3 on two PMS version atoms.

pms_compare(Op, A, B) :-
  pms_version(A, VA),
  pms_version(B, VB),
  eapi:version_compare(Op, VA, VB).


:- begin_tests(eapi_version_compare).

test(equal_versions) :-
  pms_compare(=, '1.0', '1.0').

test(less_than) :-
  pms_compare(<, '1.0', '2.0').

test(greater_than) :-
  pms_compare(>, '3.0', '2.0').

test(revision_ordering) :-
  pms_compare(<, '1.0-r1', '1.0-r2').

test(suffix_ordering_alpha_before_beta) :-
  pms_compare(<, '1.0_alpha1', '1.0_beta1').

test(suffix_ordering_rc_before_release) :-
  pms_compare(<, '1.0_rc1', '1.0').

test(suffix_ordering_release_before_p) :-
  pms_compare(<, '1.0', '1.0_p1').

test(pms_suffix_chain, [true(Order == Expected)]) :-
  maplist(pms_version,
          ['1.0_alpha1', '1.0_beta1', '1.0_pre1', '1.0_rc1', '1.0', '1.0_p1'],
          Expected),
  Expected = [VA, VB, VC, VD, VE, VF],
  msort([VF, VD, VB, VE, VC, VA], Order).

% PMS algorithm 3.5/3.6: multi-suffix versions compare pairwise by suffix
% type then number, not lexicographically on the rest string (issue #30).
test(multi_suffix_p_beats_pre) :-
  pms_compare(>, '1.0_rc1_p2', '1.0_rc1_pre1').

test(multi_suffix_numeric_not_lexicographic) :-
  pms_compare(>, '1.0_rc1_p10', '1.0_rc1_p9').

test(multi_suffix_shorter_below_p) :-
  pms_compare(<, '1.0_rc1', '1.0_rc1_p1').

test(multi_suffix_shorter_above_pre) :-
  pms_compare(>, '1.0_rc1', '1.0_rc1_pre1').

test(multi_suffix_pms_chain, [true(Order == Expected)]) :-
  maplist(pms_version,
          ['1.0_rc1_pre1', '1.0_rc1', '1.0_rc1_p2', '1.0_rc1_p10', '1.0'],
          Expected),
  Expected = [VA, VB, VC, VD, VE],
  msort([VE, VC, VA, VD, VB], Order).

test(multi_suffix_equal_versions) :-
  pms_compare(=, '1.0_rc1_p2', '1.0_rc1_p2').

:- end_tests(eapi_version_compare).


% -----------------------------------------------------------------------------
%  EAPI version comparison: PMS section 3.3 vectors (issue #73)
% -----------------------------------------------------------------------------
%
% Table-driven vectors for the numeric-component comparison rules of PMS
% algorithms 3.2/3.3, focusing on component count and numeric padding.

:- begin_tests(eapi_version_pms_vectors).

% Each vector is A-Op-B, asserting eapi:version_compare(Op, A, B).
pms_order_vector('1'    < '1.0').     % more numeric components wins
pms_order_vector('1.0'  < '1.0.0').
pms_order_vector('1.0'  < '1.1').
pms_order_vector('1.2'  < '1.10').    % numeric, not lexicographic
pms_order_vector('1.01' < '1.1').     % leading zero sorts first (PMS 3.3)
pms_order_vector('9.0'  < '10.0').    % multi-digit first component
pms_order_vector('1.99' < '2.0').

test(pms_numeric_order_vectors) :-
  forall(pms_order_vector(A < B),
         ( pms_compare(<, A, B),
           pms_compare(>, B, A)
         )).

% Numeric padding (PMS 3.3): trailing zeros in a padded component must not
% change the normalized numeric key ('1.0' and '1.00' share [1,0]). The
% version/7 term keeps the display string as final tie-break, so the full
% terms stay distinguishable for entry identity, but the order-relevant
% numeric prefix is identical.
test(pms_padding_same_numeric_key) :-
  pms_version('1.0',  version(N1, A1, R1, S1, T1, Rev1, _)),
  pms_version('1.00', version(N2, A2, R2, S2, T2, Rev2, _)),
  N1 == N2, A1 == A2, R1 == R2, S1 == S2, T1 == T2, Rev1 == Rev2.

test(pms_padding_not_smaller_than_unpadded, [fail]) :-
  pms_compare(<, '1.00', '1.0').

:- end_tests(eapi_version_pms_vectors).


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

% Strict PMS-only grammar: non-PMS synonyms and the ':=' slot operator
% must not be consumed as version operators (issue #31).
test(strict_rejects_arrow_ge, [fail]) :-
  phrase(eapi:operator(_), [61,62], []).                 % =>

test(strict_rejects_arrow_le, [fail]) :-
  phrase(eapi:operator(_), [61,60], []).                 % =<

test(strict_rejects_slot_operator, [fail]) :-
  phrase(eapi:operator(_), [58,61], []).                 % :=

% Lenient CLI grammar: accepts => and =< synonyms, still rejects ':='.
test(query_arrow_ge, [true(Op == greaterequal)]) :-
  phrase(eapi:query_operator(Op), [61,62], []).          % =>

test(query_arrow_le, [true(Op == smallerequal)]) :-
  phrase(eapi:query_operator(Op), [61,60], []).          % =<

test(query_greater_equal, [true(Op == greaterequal)]) :-
  phrase(eapi:query_operator(Op), [62,61], []).          % >=

test(query_rejects_slot_operator, [fail]) :-
  phrase(eapi:query_operator(_), [58,61], []).           % :=

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

% Metadata parsing must fail hard on non-PMS operator spellings (issue #31):
% ':=' is the slot operator, never a version operator; => and =< are
% CLI-only synonyms.
test(metadata_rejects_slot_operator_prefix, [fail]) :-
  atom_codes(':=dev-libs/openssl', Codes),
  phrase(eapi:depend(repo://entry, _), Codes, []).

test(metadata_rejects_arrow_ge, [fail]) :-
  atom_codes('=>dev-libs/openssl-1.1.0', Codes),
  phrase(eapi:depend(repo://entry, _), Codes, []).

test(metadata_rejects_arrow_le, [fail]) :-
  atom_codes('=<dev-libs/openssl-1.1.0', Codes),
  phrase(eapi:depend(repo://entry, _), Codes, []).

% Slot operator in its legal position (after the package name) still parses.
test(metadata_slot_operator_legal_position, [true(S == [any_same_slot]), nondet]) :-
  atom_codes('dev-libs/glib:=', Codes),
  phrase(eapi:depend(repo://entry,
    [package_dependency(install, no, 'dev-libs', glib, none, version_none, S, [])]), Codes, []).

test(use_conditional_dep, [nondet]) :-
  atom_codes('ssl? ( dev-libs/openssl )', Codes),
  phrase(eapi:depend(repo://entry, [use_conditional_group(positive, ssl, _, _)]), Codes, []).

test(any_of_dep, [nondet]) :-
  atom_codes('|| ( dev-libs/openssl dev-libs/libressl )', Codes),
  phrase(eapi:depend(repo://entry, [any_of_group(_)]), Codes, []).

test(empty_dep, [true(D == [])]) :-
  phrase(eapi:depend(repo://entry, D), [], []).

% Each dependency key tags its leaves with its own phase at parse time,
% including inside groups; nothing downstream re-tags them.
test(phase_tag_per_key, [true(Phases == [install, run, pdepend])]) :-
  atom_codes('ssl? ( dev-libs/openssl )', Codes),
  phrase(eapi:depend(repo://entry,  [use_conditional_group(_, _, _, [package_dependency(P1, _, _, _, _, _, _, _)])]), Codes, []),
  phrase(eapi:rdepend(repo://entry, [use_conditional_group(_, _, _, [package_dependency(P2, _, _, _, _, _, _, _)])]), Codes, []),
  phrase(eapi:pdepend(repo://entry, [use_conditional_group(_, _, _, [package_dependency(P3, _, _, _, _, _, _, _)])]), Codes, []),
  Phases = [P1, P2, P3].

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

test(use_flag_plus, [true(U == ssl)]) :-
  eapi:use_flag_name(plus(ssl), U).

test(use_flag_minus, [true(U == debug)]) :-
  eapi:use_flag_name(minus(debug), U).

test(use_flag_bare, [true(U == test)]) :-
  eapi:use_flag_name(test, U).

test(use_flag_directive, [true(U == ssl)]) :-
  eapi:use_flag_name(inverse(ssl), U).

test(use_flag_polarity, [true(Ps == [positive,negative,positive,positive,positive,negative,negative,negative])]) :-
  findall(P,
          ( member(T, [plus(f),minus(f),enable(f),equal(f),optenable(f),disable(f),inverse(f),optdisable(f)]),
            eapi:use_flag_polarity(T, P, f) ),
          Ps).

test(use_flag_bare_has_no_polarity, [fail]) :-
  eapi:use_flag_polarity(ssl, _, _).

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
%  EAPI SRC_URI / URI parsing tests
% -----------------------------------------------------------------------------
%
% Covers the eapi:uri/3 DCG, especially the `->` rename form (PMS 9 §7.3.2).
% The historical operator-precedence bug in the inline if-then-else left the
% Proto/Base atoms unbound on renamed distfiles, which then propagated to
% download:resolve_mirror_uri/3 -> atom_string/2 -> instantiation_error in
% the upstream-fallback path. These tests pin both the rename and non-rename
% shapes so the bug cannot regress silently.

:- begin_tests(eapi_uri_parsing).

test(plain_uri, [nondet]) :-
  atom_codes('https://example.com/foo-1.0.tar.gz', Codes),
  phrase(eapi:uri(uri(P, B, L)), Codes, []),
  P == https,
  B == 'example.com/foo-1.0.tar.gz',
  L == 'foo-1.0.tar.gz'.

test(plain_uri_local_is_basename, [true(L == 'bar.tar.xz'), nondet]) :-
  atom_codes('ftp://mirror.example.org/pub/path/bar.tar.xz', Codes),
  phrase(eapi:uri(uri(_, _, L)), Codes, []).

test(mirror_uri, [nondet]) :-
  atom_codes('mirror://gnu/emacs/emacs-29.4.tar.xz', Codes),
  phrase(eapi:uri(uri(P, B, L)), Codes, []),
  P == mirror,
  B == 'gnu/emacs/emacs-29.4.tar.xz',
  L == 'emacs-29.4.tar.xz'.

% Renamed distfile (the actual regression case). Every field must be a
% ground atom -- veracrypt-1.26.20 used to come back as uri(_,_,'veracrypt-
% 1.26.20.tar.gz') with Proto and Base unbound.

test(renamed_uri_binds_all_fields, [nondet]) :-
  atom_codes('https://github.com/veracrypt/VeraCrypt/archive/VeraCrypt_1.26.20.tar.gz -> veracrypt-1.26.20.tar.gz', Codes),
  phrase(eapi:uri(uri(P, B, L)), Codes, []),
  ground(P), ground(B), ground(L),
  P == https,
  B == 'github.com/veracrypt/VeraCrypt/archive/VeraCrypt_1.26.20.tar.gz',
  L == 'veracrypt-1.26.20.tar.gz'.

test(renamed_uri_proto_not_unbound, [nondet]) :-
  atom_codes('https://example.org/upstream-name.tgz -> local-name.tgz', Codes),
  phrase(eapi:uri(uri(P, _, _)), Codes, []),
  nonvar(P).

test(renamed_uri_base_not_unbound, [nondet]) :-
  atom_codes('https://example.org/upstream-name.tgz -> local-name.tgz', Codes),
  phrase(eapi:uri(uri(_, B, _)), Codes, []),
  nonvar(B).

test(renamed_uri_local_matches_arrow_target, [nondet]) :-
  atom_codes('https://example.org/very/long/path/upstream-original.tar.gz -> short.tar.gz', Codes),
  phrase(eapi:uri(uri(_, _, L)), Codes, []),
  L == 'short.tar.gz'.

% Non-prototyped URI (rare, but covered by the second eapi:uri/3 clause).

test(nonprototyped_uri, [nondet]) :-
  atom_codes('plain-distfile.tar.gz', Codes),
  phrase(eapi:uri(uri(P, B, L)), Codes, []),
  P == '',
  B == '',
  L == 'plain-distfile.tar.gz'.

:- end_tests(eapi_uri_parsing).


% -----------------------------------------------------------------------------
%  EAPI REQUIRED_USE expression parsing tests (issue #73)
% -----------------------------------------------------------------------------
%
% PMS 8, Section 7.3.4: REQUIRED_USE supports flags, '!'-prefixed flags,
% USE-conditionals, '||' (or), '^^' (exactly-one-of) and '??'
% (at-most-one-of) groups, with arbitrary nesting.

:- begin_tests(eapi_required_use_parsing).

requse(Atom, U) :-
  atom_codes(Atom, Codes),
  phrase(eapi:required_use(test://e, U), Codes, []),
  !.

test(requse_plain_flag, [true(U == [required(foo)])]) :-
  requse('foo', U).

test(requse_blocking_flag, [true(U == [blocking(foo)])]) :-
  requse('!foo', U).

test(requse_flag_sequence, [true(U == [required(a), blocking(b), required(c)])]) :-
  requse('a !b c', U).

test(requse_positive_conditional,
     [true(U == [use_conditional_group(positive, doc, test://e, [required(man)])])]) :-
  requse('doc? ( man )', U).

test(requse_negative_conditional,
     [true(U == [use_conditional_group(negative, doc, test://e, [required(man)])])]) :-
  requse('!doc? ( man )', U).

test(requse_any_of_group,
     [true(U == [any_of_group([required(a), required(b)])])]) :-
  requse('|| ( a b )', U).

test(requse_exactly_one_of_group,
     [true(U == [exactly_one_of_group([required(a), required(b), required(c)])])]) :-
  requse('^^ ( a b c )', U).

test(requse_at_most_one_of_group,
     [true(U == [at_most_one_of_group([required(a), required(b)])])]) :-
  requse('?? ( a b )', U).

test(requse_nested_xor_in_conditional,
     [true(U == [use_conditional_group(positive, x, test://e,
                   [exactly_one_of_group([required(a), required(b)])])])]) :-
  requse('x? ( ^^ ( a b ) )', U).

test(requse_nested_conditional_in_or,
     [true(U == [any_of_group([use_conditional_group(positive, x, test://e,
                                 [required(a)]),
                               required(b)])])]) :-
  requse('|| ( x? ( a ) b )', U).

test(requse_blocking_inside_group,
     [true(U == [exactly_one_of_group([required(a), blocking(b)])])]) :-
  requse('^^ ( a !b )', U).

:- end_tests(eapi_required_use_parsing).


% -----------------------------------------------------------------------------
%  EAPI LICENSE group parsing tests (issue #73)
% -----------------------------------------------------------------------------
%
% PMS 8, Section 7.3: LICENSE is a dependency sequence whose leaves are
% license names; '||' groups, all-of groups and USE-conditionals apply.

:- begin_tests(eapi_license_parsing).

lic(Atom, L) :-
  atom_codes(Atom, Codes),
  phrase(eapi:license(test://e, L), Codes, []),
  !.

test(license_single, [true(L == ['GPL-2'])]) :-
  lic('GPL-2', L).

test(license_sequence, [true(L == ['GPL-2', 'LGPL-2.1'])]) :-
  lic('GPL-2 LGPL-2.1', L).

test(license_any_of_group,
     [true(L == [any_of_group(['GPL-2', 'BSD'])])]) :-
  lic('|| ( GPL-2 BSD )', L).

test(license_use_conditional,
     [true(L == [use_conditional_group(positive, doc, test://e, ['FDL-1.3'])])]) :-
  lic('doc? ( FDL-1.3 )', L).

test(license_all_of_inside_any_of,
     [true(L == [any_of_group([all_of_group(['MIT', 'BSD']), 'GPL-2'])])]) :-
  lic('|| ( ( MIT BSD ) GPL-2 )', L).

test(license_plus_suffix, [true(L == ['GPL-2+'])]) :-
  lic('GPL-2+', L).

:- end_tests(eapi_license_parsing).


% -----------------------------------------------------------------------------
%  EAPI bracketed USE-dependency syntax tests (issue #73)
% -----------------------------------------------------------------------------
%
% PMS 8, Section 8.3.4: 4-style USE dependencies ([flag], [-flag], [flag=],
% [!flag=], [flag?], [!flag?]) with (+)/(-) defaults.

:- begin_tests(eapi_usedep_brackets).

usedeps(Atom, U) :-
  atom_codes(Atom, Codes),
  phrase(eapi:use_dependencies(U), Codes, []),
  !.

test(usedep_enable, [true(U == [use(enable(foo), none)])]) :-
  usedeps('[foo]', U).

test(usedep_disable, [true(U == [use(disable(foo), none)])]) :-
  usedeps('[-foo]', U).

test(usedep_equal, [true(U == [use(equal(foo), none)])]) :-
  usedeps('[foo=]', U).

test(usedep_inverse_equal, [true(U == [use(inverse(foo), none)])]) :-
  usedeps('[!foo=]', U).

test(usedep_optenable, [true(U == [use(optenable(foo), none)])]) :-
  usedeps('[foo?]', U).

test(usedep_optdisable, [true(U == [use(optdisable(foo), none)])]) :-
  usedeps('[!foo?]', U).

test(usedep_default_positive, [true(U == [use(enable(foo), positive)])]) :-
  usedeps('[foo(+)]', U).

test(usedep_default_negative, [true(U == [use(enable(foo), negative)])]) :-
  usedeps('[foo(-)]', U).

test(usedep_equal_with_default, [true(U == [use(equal(foo), positive)])]) :-
  usedeps('[foo(+)=]', U).

test(usedep_optional_with_default, [true(U == [use(optdisable(foo), negative)])]) :-
  usedeps('[!foo(-)?]', U).

test(usedep_comma_list,
     [true(U == [use(enable(a), none),
                 use(equal(b), none),
                 use(optdisable(c), none)])]) :-
  usedeps('[a,b=,!c?]', U).

% Full package dependency carrying bracketed USE deps.
test(usedep_in_package_dependency, [nondet]) :-
  atom_codes('>=dev-libs/foo-1.2[bar=,!baz?]', Codes),
  phrase(eapi:package_dependency(install, test://e, D), Codes, []),
  D = package_dependency(install, no, 'dev-libs', foo, greaterequal, V, [], U),
  eapi:version_full(V, '1.2'),
  U == [use(equal(bar), none), use(optdisable(baz), none)].

:- end_tests(eapi_usedep_brackets).


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


% -----------------------------------------------------------------------------
%  Nested @set expansion (pkgcore issue 280)
% -----------------------------------------------------------------------------

:- begin_tests(eapi_nested_sets).

test(expands_nested_file_set,
     [setup(eapitest:install_sets_(outer_inner)),
      cleanup(eapitest:uninstall_sets_(outer_inner))]) :-
  eapi:substitute_sets(['@eapi_test_outer'], Result),
  Result == ['testcat/inner', 'testcat/outer'].

test(expands_three_levels,
     [setup(eapitest:install_sets_(three_deep)),
      cleanup(eapitest:uninstall_sets_(three_deep))]) :-
  eapi:substitute_sets(['@eapi_test_a'], Result),
  Result == ['testcat/c', 'testcat/b', 'testcat/a'].

test(cycle_fails,
     [setup(eapitest:install_sets_(cycle_ab)),
      cleanup(eapitest:uninstall_sets_(cycle_ab)),
      fail]) :-
  eapi:substitute_sets(['@eapi_test_a'], _).

test(self_cycle_fails,
     [setup(eapitest:install_sets_(self_cycle)),
      cleanup(eapitest:uninstall_sets_(self_cycle)),
      fail]) :-
  eapi:substitute_sets(['@eapi_test_self'], _).

test(unknown_nested_fails,
     [setup(eapitest:install_sets_(unknown_nested)),
      cleanup(eapitest:uninstall_sets_(unknown_nested)),
      fail]) :-
  eapi:substitute_sets(['@eapi_test_bad'], _).

test(unknown_cli_passthrough) :-
  eapi:substitute_sets(['@eapi_test_unknown_cli'], Result),
  Result == ['@eapi_test_unknown_cli'].

test(plain_atom_passthrough) :-
  eapi:substitute_sets(['testcat/pkg'], Result),
  Result == ['testcat/pkg'].

test(string_member_coerced,
     [setup(eapitest:install_sets_(string_member)),
      cleanup(eapitest:uninstall_sets_(string_member))]) :-
  eapi:substitute_sets(['@eapi_test_str'], Result),
  Result == ['testcat/from-string'].

:- end_tests(eapi_nested_sets).


%! eapitest:set_pairs_(+Id, -Pairs) is det.
%
% Named `preference:local_set/2` fixtures for nested-set tests.

eapitest:set_pairs_(outer_inner,
  ['@eapi_test_outer'-['@eapi_test_inner', 'testcat/outer'],
   '@eapi_test_inner'-['testcat/inner']]).
eapitest:set_pairs_(three_deep,
  ['@eapi_test_a'-['@eapi_test_b', 'testcat/a'],
   '@eapi_test_b'-['@eapi_test_c', 'testcat/b'],
   '@eapi_test_c'-['testcat/c']]).
eapitest:set_pairs_(cycle_ab,
  ['@eapi_test_a'-['@eapi_test_b'],
   '@eapi_test_b'-['@eapi_test_a']]).
eapitest:set_pairs_(self_cycle,
  ['@eapi_test_self'-['@eapi_test_self', 'testcat/x']]).
eapitest:set_pairs_(unknown_nested,
  ['@eapi_test_bad'-['@eapi_test_missing', 'testcat/x']]).
eapitest:set_pairs_(string_member,
  ['@eapi_test_str'-["@eapi_test_inner"],
   '@eapi_test_inner'-['testcat/from-string']]).


%! eapitest:install_sets_(+Id) is det.
%! eapitest:uninstall_sets_(+Id) is det.
%
% Assert or retract the fixture identified by Id.

eapitest:install_sets_(Id) :-
  eapitest:set_pairs_(Id, Pairs),
  eapitest:uninstall_set_pairs_(Pairs),
  forall(member(Name-Entries, Pairs),
         assertz(preference:local_set(Name, Entries))).


eapitest:uninstall_sets_(Id) :-
  eapitest:set_pairs_(Id, Pairs),
  eapitest:uninstall_set_pairs_(Pairs).


eapitest:uninstall_set_pairs_(Pairs) :-
  forall(member(Name-_, Pairs),
         retractall(preference:local_set(Name, _))).
