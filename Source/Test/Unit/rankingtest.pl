/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> RANKINGTEST
Unit tests for choice-arm ranking (Source/Domain/Gentoo/Rules/Resolving/ranking.pl).

||-branch ranking by admitted version, the preference keys of
prioritize_deps_keep_all/3, USE_EXPAND target ranking and the
declared criterion / tightness-class orders.
*/

:- module(rankingtest, []).

:- use_module(library(plunit)).
:- use_module(library(lists)).
:- use_module(portage('Source/Test/Unit/fixture')).

% =============================================================================
%  RANKINGTEST declarations
% =============================================================================

% dev-haskell/text 1.2 vs 2.x fixture shared by the ||-branch ranking units
% (portage-ng#112 — cabal's text OR): two tree versions and the two
% version-bounded arms that select them.

text_tree_setup :-
  text_tree_cleanup,
  assertz(cache:ordered_entry(qtest, 'dev-haskell/text-1.2.5.0-r1',
                              'dev-haskell', text,
                              version([1,2,5,0],'',4,0,[],1,'1.2.5.0-r1'))),
  assertz(cache:ordered_entry(qtest, 'dev-haskell/text-2.1.1',
                              'dev-haskell', text,
                              version([2,1,1],'',4,0,[],0,'2.1.1'))).

text_tree_cleanup :-
  retractall(cache:ordered_entry(qtest, _, 'dev-haskell', text, _)).

text_arm12(all_of_group([
  package_dependency(run,no,'dev-haskell',text,greaterequal,
                     version([1,2,3,0],'',4,0,[],0,'1.2.3.0'),[],[]),
  package_dependency(run,no,'dev-haskell',text,smaller,
                     version([1,3],'',4,0,[],0,'1.3'),[],[])])).

text_arm2(all_of_group([
  package_dependency(run,no,'dev-haskell',text,greaterequal,
                     version([2,0],'',4,0,[],0,'2.0'),[],[]),
  package_dependency(run,no,'dev-haskell',text,smaller,
                     version([2,2],'',4,0,[],0,'2.2'),[],[])])).


% ||-branch ranking prefers the arm that admits the newest tree version.
:- begin_tests(ranking_any_of_version_branch).

test(prefers_newer_text_branch_first,
     [setup(text_tree_setup), cleanup(text_tree_cleanup)]) :-
  text_arm12(B1), text_arm2(B2),
  ranking:prioritize_deps_keep_all([B1, B2], [], [First|_]),
  First == B2.

test(prefers_newer_even_when_listed_second,
     [setup(text_tree_setup), cleanup(text_tree_cleanup)]) :-
  text_arm12(B1), text_arm2(B2),
  ranking:prioritize_deps_keep_all([B2, B1], [], [First|_]),
  First == B2.

:- end_tests(ranking_any_of_version_branch).


% ||-branch ranking: USE-sat, SnapAll, SlotScore, NoDowngrade (emerge bins).
:- begin_tests(ranking_any_of_preference_keys).

rap_foo_entry(qtest://'cat/foo-1.0').
rap_foo_ver(version([1,0],'',4,0,[],0,'1.0')).

rap_use_setup :-
  rap_foo_entry(R://Id),
  rap_foo_ver(V),
  retractall(cache:ordered_entry(qtest, _, cat, foo, _)),
  retractall(memo:iuse_info_cache_(qtest, Id, _)),
  retractall(memo:effective_use_fact(qtest, Id, _)),
  assertz(cache:ordered_entry(R, Id, cat, foo, V)),
  assertz(memo:iuse_info_cache_(R, Id, iuse_info([a, b], []))),
  assertz(memo:effective_use_fact(R, Id, [a])).

rap_use_cleanup :-
  rap_foo_entry(_://Id),
  retractall(cache:ordered_entry(qtest, _, cat, foo, _)),
  retractall(memo:iuse_info_cache_(qtest, Id, _)),
  retractall(memo:effective_use_fact(qtest, Id, _)),
  retractall(preference:local_profile_masked_use_flag(b)).

rap_arm_use(Flag, package_dependency(run, no, cat, foo, none, version_none, [],
                                     [use(enable(Flag), none)])).

test(prefers_use_satisfied_arm,
     [setup(rap_use_setup), cleanup(rap_use_cleanup)]) :-
  rap_arm_use(a, Ba),
  rap_arm_use(b, Bb),
  ranking:prioritize_deps_keep_all([Bb, Ba], [], [First|_]),
  First == Ba.

test(prefers_use_unmasked_among_unsat,
     [setup(( rap_use_setup,
              rap_foo_entry(_://Id),
              retractall(memo:effective_use_fact(qtest, Id, _)),
              assertz(memo:effective_use_fact(qtest, Id, [])),
              assertz(preference:local_profile_masked_use_flag(b)) )),
      cleanup(rap_use_cleanup)]) :-
  rap_arm_use(a, Ba),
  rap_arm_use(b, Bb),
  ranking:prioritize_deps_keep_all([Bb, Ba], [], [First|_]),
  First == Ba.

rap_snap_setup(Saved) :-
  stash_selected_cn_snap(Saved),
  retractall(cache:ordered_entry(qtest, _, cat, _, _)),
  assertz(cache:ordered_entry(qtest, 'cat/a-1', cat, a,
                              version([1],'',4,0,[],0,'1'))),
  assertz(cache:ordered_entry(qtest, 'cat/b-1', cat, b,
                              version([1],'',4,0,[],0,'1'))),
  assertz(cache:ordered_entry(qtest, 'cat/c-1', cat, c,
                              version([1],'',4,0,[],0,'1'))),
  cnselect:record_selected_cn_snapshot(cat, a,
    [selected(qtest, 'cat/a-1', run, v, '0')]),
  cnselect:record_selected_cn_snapshot(cat, b,
    [selected(qtest, 'cat/b-1', run, v, '0')]).

rap_snap_cleanup(Saved) :-
  restore_selected_cn_snap(Saved),
  retractall(cache:ordered_entry(qtest, _, cat, _, _)).

rap_pkg(N, package_dependency(run, no, cat, N, none, version_none, [], [])).

test(prefers_snap_all_arm,
     [setup(rap_snap_setup(Saved)), cleanup(rap_snap_cleanup(Saved))]) :-
  rap_pkg(a, A), rap_pkg(b, B), rap_pkg(c, C),
  All = all_of_group([A, B]),
  Partial = all_of_group([A, C]),
  ranking:prioritize_deps_keep_all([Partial, All], [], [First|_]),
  First == All.

rap_slot_setup :-
  retractall(cache:ordered_entry(qtest, _, cat, llvm, _)),
  assertz(cache:ordered_entry(qtest, 'cat/llvm-18', cat, llvm,
                              version([18],'',4,0,[],0,'18'))),
  assertz(cache:ordered_entry(qtest, 'cat/llvm-20', cat, llvm,
                              version([20],'',4,0,[],0,'20'))).

rap_slot_cleanup :-
  retractall(cache:ordered_entry(qtest, _, cat, llvm, _)).

rap_slot_arm(Slot, package_dependency(run, no, cat, llvm, none, version_none,
                                      [slot(Slot)], [])).

test(prefers_higher_slot_arm,
     [setup(rap_slot_setup), cleanup(rap_slot_cleanup)]) :-
  rap_slot_arm(18, S18),
  rap_slot_arm(20, S20),
  ranking:prioritize_deps_keep_all([S18, S20], [], [First|_]),
  First == S20.

% text_tree_setup/0 plus a selected-cn snapshot already on text 2.1.1, so
% the 1.2 arm is a downgrade.
rap_text_setup(Saved) :-
  text_tree_setup,
  stash_selected_cn_snap(Saved),
  cnselect:record_selected_cn_snapshot('dev-haskell', text,
    [selected(qtest, 'dev-haskell/text-2.1.1', run,
              version([2,1,1],'',4,0,[],0,'2.1.1'), '0')]).

rap_text_cleanup(Saved) :-
  text_tree_cleanup,
  restore_selected_cn_snap(Saved).

test(no_downgrade_demotes_older_arm,
     [setup(rap_text_setup(Saved)), cleanup(rap_text_cleanup(Saved))]) :-
  text_arm12(B1), text_arm2(B2),
  ranking:analyse_arm([], B1, A1),
  ranking:analyse_arm([], B2, A2),
  ranking:criterion_value(no_downgrade, [], same_cn, A1, ND1),
  ranking:criterion_value(no_downgrade, [], same_cn, A2, ND2),
  ND1 == no,
  ND2 == yes.

% VerScore must stay inactive across different CNs: a 9999 live ebuild of a
% later arm must not beat the first arm's ebuild order (portage-ng#115/#116,
% virtual/mta notqmail-9999 vs nullmailer, virtual/jdk openjdk vs -bin).
rap_mixed_setup :-
  retractall(cache:ordered_entry(qtest, _, 'qtest-mta', _, _)),
  assertz(cache:ordered_entry(qtest, 'qtest-mta/lightmta-2.2', 'qtest-mta',
                              lightmta, version([2,2],'',4,0,[],0,'2.2'))),
  assertz(cache:ordered_entry(qtest, 'qtest-mta/livemta-9999', 'qtest-mta',
                              livemta, version([9999],'',4,0,[],0,'9999'))).

rap_mixed_cleanup :-
  retractall(cache:ordered_entry(qtest, _, 'qtest-mta', _, _)).

test(mixed_cn_group_keeps_ebuild_order,
     [setup(rap_mixed_setup), cleanup(rap_mixed_cleanup)]) :-
  rap_pkg2('qtest-mta', lightmta, A),
  rap_pkg2('qtest-mta', livemta, B),
  ranking:prioritize_deps_keep_all([A, B], [], [First|_]),
  First == A.

test(same_cn_group_still_version_ranked,
     [setup(rap_text_setup(Saved)), cleanup(rap_text_cleanup(Saved))]) :-
  text_arm12(B1), text_arm2(B2),
  ranking:prioritize_deps_keep_all([B1, B2], [], [First|_]),
  First == B2.

% A selected text-1.2 must keep the 1.2 arm ahead of the newer 2.x arm
% (portage-ng#123). Nothing selected still prefers 2.x via `version`.
rap_text12_setup(Saved) :-
  text_tree_setup,
  stash_selected_cn_snap(Saved),
  cnselect:record_selected_cn_snapshot('dev-haskell', text,
    [selected(qtest, 'dev-haskell/text-1.2.5.0-r1', run,
              version([1,2,5,0],'',4,0,[],1,'1.2.5.0-r1'), '0')]).

test(selected_older_text_keeps_admitting_arm,
     [setup(rap_text12_setup(Saved)), cleanup(rap_text_cleanup(Saved))]) :-
  text_arm12(B1), text_arm2(B2),
  ranking:prioritize_deps_keep_all([B2, B1], [], [First|_]),
  First == B1.

% SlotScore must likewise stay inactive across different CNs: a later arm
% carrying a higher-slotted package must not beat the first arm's ebuild
% order. ruby-single || arms list the profile-default target first, and
% emerge keeps that order: ( ruby:3.3 rubygems[ruby33] ) wins over
% ( ruby:4.0 rubygems[ruby40] ) even though slot 4.0 > 3.3 (webkit-gtk
% cluster, Aug-2026 tinderbox regression).
rap_ruby_arm(Slot, Flag, all_of_group([
  package_dependency(run, no, 'qtest-lang', ruby, none, version_none,
                     [slot(Slot)], []),
  package_dependency(run, no, 'qtest-virtual', rubygems, none, version_none,
                     [], [use(enable(Flag), none)])])).

test(mixed_cn_group_not_slot_ranked) :-
  rap_ruby_arm('3.3', ruby_targets_ruby33, Arm33),
  rap_ruby_arm('4.0', ruby_targets_ruby40, Arm40),
  ranking:prioritize_deps_keep_all([Arm33, Arm40], [], [First|_]),
  First == Arm33.

rap_pkg2(C, N, package_dependency(run, no, C, N, none, version_none, [], [])).

:- end_tests(ranking_any_of_preference_keys).


% -----------------------------------------------------------------------------
%  USE_EXPAND target ranking is family-agnostic
% -----------------------------------------------------------------------------
%
% The any_of/exactly-one choice ranking prefers the newest USE_EXPAND target
% when the profile has not forced one. This used to be hardcoded for the
% llvm_slot and lua5 families only (ecosystem-specific literals in the domain
% rules). It is now generic over every eapi:use_expand/1 family: the key is
% the list of digit groups of the flag, compared in the standard order of
% terms (newer = larger); `none` when the flag carries no digits.

:- begin_tests(use_expand_target_rank).

test(llvm_slot_key, [true(K == [20])]) :-
  ranking:use_expand_target_key('llvm_slot_20', K).

test(llvm_slot_newer_ranks_higher) :-
  ranking:use_expand_target_key('llvm_slot_20', K20),
  ranking:use_expand_target_key('llvm_slot_19', K19),
  K20 @> K19.

test(python_single_target_newer_ranks_higher) :-
  ranking:use_expand_target_key('python_single_target_python3_13', K13),
  ranking:use_expand_target_key('python_single_target_python3_12', K12),
  K13 @> K12.

test(lua5_newer_ranks_higher) :-
  ranking:use_expand_target_key('lua_single_target_lua5-4', K4),
  ranking:use_expand_target_key('lua_single_target_lua5-3', K3),
  K4 @> K3.

test(lua_non_numeric_is_none, [true(K == none)]) :-
  ranking:use_expand_target_key('lua_single_target_luajit', K).

test(non_use_expand_is_none, [true(K == none)]) :-
  ranking:use_expand_target_key(some_random_flag, K).

test(none_sorts_below_every_target) :-
  ranking:use_expand_target_key('llvm_slot_19', K19),
  none @< K19.

test(digit_groups_multi, [true(G == [3,13])]) :-
  atom_codes('python3_13', Cs),
  ranking:digit_groups(Cs, G).

test(digit_groups_none, [true(G == [])]) :-
  atom_codes(luajit, Cs),
  ranking:digit_groups(Cs, G).

:- end_tests(use_expand_target_rank).


% -----------------------------------------------------------------------------
%  Declarative preference ranking
% -----------------------------------------------------------------------------
%
% Choice-arm preference and proof-order tightness are *declared* orders
% (ranking:choice_criteria/1, ranking:tightness_classes/1) compared with
% the standard order of terms -- not weighted sums or packed integers.
% These tests pin the declared order, the comparator, and the value
% encodings the criteria rely on.

:- begin_tests(ranking_declarative).

% The documented criterion order (12-doc-resolution.md, "Preference keys").
test(choice_criteria_order) :-
  ranking:choice_criteria(Cs),
  Cs == [license_ok, use_sat, use_unmasked, preference, snap_all, snap_admits,
         slot, no_downgrade, installed, overlap, version, use_expand].

% Every criterion yields a value for every arm shape (keys always align).
test(arm_key_is_total_over_arm_shapes) :-
  ranking:choice_criteria(Cs),
  length(Cs, N),
  forall(member(Dep, [package_dependency(run,no,cat,pkg,none,version_none,[],[]),
                      all_of_group([package_dependency(run,no,cat,pkg,none,version_none,[],[])]),
                      use_conditional_group(positive, flag, qtest://'cat/parent-0', []),
                      required(llvm_slot_20),
                      required(minus(llvm_slot_20))]),
         ( ranking:analyse_arm([], Dep, Arm),
           ranking:arm_key([], multi_cn, Arm, Key),
           length(Key, N)
         )).

% Lexicographic: the first differing criterion decides, larger preferred.
test(compare_preference_first_difference_wins) :-
  ranking:compare_preference(O1, [yes, no, 0], [yes, yes, 9]),
  O1 == (>),
  ranking:compare_preference(O2, [yes, yes, 0], [no, yes, 9]),
  O2 == (<),
  ranking:compare_preference(O3, [yes, 1], [yes, 1]),
  O3 == (=).

% Equal keys keep ebuild order (index ascending); nothing is dropped.
test(prefer_arm_ties_keep_ebuild_order) :-
  ranking:prefer_arm(O1, [yes]-2-b, [yes]-1-a),
  O1 == (>),
  ranking:prefer_arm(O2, [yes]-1-a, [no]-2-b),
  O2 == (<).

% Slot keys are digit-group lists: '3.10' is newer than '3.3' (atom_number
% would read 3.1), and slot 0 counts as no explicit slot.
test(slot_value_compares_component_wise) :-
  ranking:dep_slot_value([package_dependency(run,no,'dev-lang',ruby,none,version_none,[slot('3.10')],[])], S310),
  ranking:dep_slot_value([package_dependency(run,no,'dev-lang',ruby,none,version_none,[slot('3.3')],[])], S33),
  S310 == [3,10],
  S310 @> S33.

test(slot_zero_is_none, [true(S == none)]) :-
  ranking:dep_slot_value([package_dependency(run,no,cat,pkg,none,version_none,[slot('0'),subslot('1')],[])], S).

test(slot_value_takes_highest, [true(S == [20])]) :-
  ranking:dep_slot_value([package_dependency(run,no,'llvm-core',llvm,none,version_none,[slot('19')],[]),
                          package_dependency(run,no,'llvm-core',llvm,none,version_none,[slot('20')],[])], S).

% version/7 terms compare as versions; version_none sorts below them.
test(version_criterion_orders_versions) :-
  V1 = version([1,2,5,0],'',4,0,[],1,'1.2.5.0-r1'),
  V2 = version([2,1,1],'',4,0,[],0,'2.1.1'),
  V2 @> V1,
  version_none @< V1.

% pref/6: Preferred dominates --favour, which dominates self-CN, which
% dominates a forced upgrade, which dominates -bootstrap, which dominates
% the USE_EXPAND target -- strictly, by argument position.
test(preference_signal_order) :-
  pref(yes, -1, no, no, no, none) @> pref(no, 1, yes, yes, yes, [20]),
  pref(no, 1, no, no, no, none)   @> pref(no, 0, yes, yes, yes, [20]),
  pref(no, 0, yes, no, no, none)  @> pref(no, 0, no, yes, yes, [20]),
  pref(no, 0, yes, yes, no, none) @> pref(no, 0, yes, no, yes, [20]),
  pref(no, 0, yes, yes, yes, none) @> pref(no, 0, yes, yes, no, [20]),
  pref(no, 0, yes, yes, no, [20]) @> pref(no, 0, yes, yes, no, [19]),
  pref(no, 0, yes, yes, no, [19]) @> pref(no, 0, yes, yes, no, none).

test(favour_signal_values) :-
  ranking:favour_signal_(yes, no, 1),
  ranking:favour_signal_(no, yes, -1),
  ranking:favour_signal_(yes, yes, 0),
  ranking:favour_signal_(no, no, 0).

test(bootstrap_package_is_flagged) :-
  ranking:preference_value([], package_dependency(run,no,'dev-lang',
                              'rust-bootstrap',none,version_none,[],[]),
                           pref(_, _, _, _, Bootstrap, none)),
  Bootstrap == yes.

test(required_use_arm_carries_target) :-
  ranking:preference_value([], required(llvm_slot_20), pref(_, 0, yes, yes, no, [20])),
  ranking:preference_value([], required(minus(llvm_slot_19)), pref(_, 0, yes, yes, no, [19])),
  ranking:preference_value([], all_of_group([]), pref(_, 0, yes, yes, no, none)).

% Proof-order tightness: the declared class order, and the first
% applicable class wins (a sub-slot pin beats a tight upper bound; an
% upper bound beats a tilde; a plain slot pin beats a wildcard).
test(tightness_classes_order) :-
  ranking:tightness_classes(Cs),
  Cs == [subslot_pinned, upper_bounded, tilde, slot_pinned, wildcard,
         any_same_slot, any_different_slot, unconstrained, other_slot_req,
         no_slot_restriction, not_a_package_dep].

rd_dep(SlotReq, Ops, grouped_package_dependency(no, cat, pkg, PDs):install?{[]}) :-
  findall(package_dependency(install, no, cat, pkg, Op, V, SlotReq, []),
          member(Op-V, Ops), PDs).

rd_pos(Dep, Pos) :- ranking:dep_priority(Dep, key(Pos, _, _, _)).

test(dep_priority_first_applicable_class) :-
  V = version([1],'',4,0,[],0,'1'),
  rd_dep([slot('0'),subslot('1')], [smaller-V], SubslotAndUpper),
  rd_dep([], [smaller-V], Upper),
  rd_dep([], [tilde-V], Tilde),
  rd_dep([slot('0')], [none-version_none], Slot),
  rd_dep([], [none-version_none], Plain),
  rd_dep([any_same_slot], [none-version_none], AnySame),
  rd_dep([any_different_slot], [none-version_none], AnyDiff),
  maplist(rd_pos, [SubslotAndUpper, Upper, Tilde, Slot, AnySame, AnyDiff, Plain], Ps),
  ranking:tightness_position(subslot_pinned, P0),
  ranking:tightness_position(upper_bounded, P1),
  ranking:tightness_position(tilde, P2),
  ranking:tightness_position(slot_pinned, P3),
  ranking:tightness_position(any_same_slot, P5),
  ranking:tightness_position(any_different_slot, P6),
  ranking:tightness_position(unconstrained, P7),
  Ps == [P0, P1, P2, P3, P5, P6, P7],
  msort(Ps, Ps).

test(dep_priority_upper_bound_carried, [true(T == V)]) :-
  V = version([1],'',4,0,[],0,'1'),
  rd_dep([], [smaller-V], Dep),
  ranking:dep_priority(Dep, key(_, T, cat, pkg)).

test(dep_priority_non_package_dep_last) :-
  ranking:dep_priority(constraint(foo), key(Pos, none, zz, zz)),
  ranking:tightness_position(not_a_package_dep, Pos),
  ranking:tightness_classes(Cs),
  length(Cs, Len),
  Pos =:= Len - 1.

:- end_tests(ranking_declarative).
