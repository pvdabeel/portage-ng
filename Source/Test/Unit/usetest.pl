/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> USETEST
Unit tests for the USE rules (Source/Domain/Gentoo/Rules/Resolving/use.pl).

build_with_use state helpers, REQUIRED_USE choice-group seeding,
use_dep_unsat fail-closed checks, leftover ^^ conflict reconciliation
(portage-ng#120), use.mask precedence over soft defaults and use.force,
the cross-dependency build_with_use memo, equality USE pins, IUSE
assoc helpers and ABI_X86 flags. Synthetic qtest entries only; no
knowledge base is needed.
*/

:- module(usetest, []).

:- use_module(library(plunit)).
:- use_module(library(assoc)).
:- use_module(library(lists)).

% =============================================================================
%  USETEST declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  USE helper predicate tests
% -----------------------------------------------------------------------------
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


% REQUIRED_USE choice-group seeding (portage-ng#87/#88): when a package is
% pulled with an empty build_with_use but its own `|| ( ... )` / `^^ ( ... )`
% choice group has no satisfied member under the profile defaults, the
% resolver must seed the highest-priority member so the package (and its
% conditional dep[flag?] edges) build with the chosen backend. We exercise
% the profile-independent logic directly using a non-existent entry (so
% effective USE is empty and entry_iuse_plus_default is empty), forcing the
% deterministic "last member" fallback.

:- begin_tests(rules_required_use_choice_seed).

test(pick_falls_back_to_last_member, [true(F == z3)]) :-
  use:requse_pick_satisfying_flag(portage://'nonexistent-pkg-0',
      [required(z1), required(z2), required(z3)], F).

test(any_of_unsatisfied_needs_seed, [true(F == z3)]) :-
  use:choice_group_needs_seed(portage://'nonexistent-pkg-0', [], [],
      any_of_group([required(z1), required(z2), required(z3)]), F).

test(any_of_already_satisfied_no_seed, [fail]) :-
  use:choice_group_needs_seed(portage://'nonexistent-pkg-0', [z2], [],
      any_of_group([required(z1), required(z2), required(z3)]), _).

test(exactly_one_unsatisfied_needs_seed, [true(F == z3)]) :-
  use:choice_group_needs_seed(portage://'nonexistent-pkg-0', [], [],
      exactly_one_of_group([required(z1), required(z2), required(z3)]), F).

test(at_most_one_never_seeds, [fail]) :-
  use:choice_group_needs_seed(portage://'nonexistent-pkg-0', [], [],
      at_most_one_of_group([required(z1), required(z2), required(z3)]), _).

test(seed_term_enables_chosen_flag, [true(Out == use_state([z3], []))]) :-
  use:seed_choice_group_term(portage://'nonexistent-pkg-0',
      any_of_group([required(z1), required(z2), required(z3)]),
      use_state([], []), Out).

test(seed_term_passthrough_when_satisfied, [true(Out == use_state([z2], []))]) :-
  use:seed_choice_group_term(portage://'nonexistent-pkg-0',
      any_of_group([required(z1), required(z2), required(z3)]),
      use_state([z2], []), Out).

% A plain required()/conditional term must NOT be seeded from empty BWU
% (only choice groups are), preserving the documented samba-safe behavior.
test(plain_required_not_seeded, [fail]) :-
  use:choice_group_needs_seed(portage://'nonexistent-pkg-0', [], [],
      required(z1), _).

% The seed loop must seed the choice group but leave conditional terms
% (e.g. net-fs/samba's `gpg? ( addc )`) untouched, so it never flips a
% flag away from the profile default and poisons the build_with_use.
test(seed_loop_ignores_conditional_terms,
     [true(Out == use_state([z3], []))]) :-
  use:seed_choice_groups_loop(portage://'nonexistent-pkg-0',
      [ use_conditional_group(positive, gpg, portage://'nonexistent-pkg-0',
                              [required(addc)]),
        any_of_group([required(z1), required(z2), required(z3)]) ],
      use_state([], []), Out, 5).

% A profile-masked member must never be seeded: the profile strips it back
% off at build time, so seeding it guarantees a REQUIRED_USE failure (e.g.
% ^^ ( elogind systemd ) on a non-systemd profile where `systemd` is
% use-masked -> the seeder must pick elogind). portage-ng#91.
test(masked_member_excluded_from_seed,
     [setup(assertz(preference:local_profile_masked_use_flag(z3))),
      cleanup(retract(preference:local_profile_masked_use_flag(z3))),
      true(F == z2)]) :-
  use:requse_pick_satisfying_flag(portage://'nonexistent-pkg-0',
      [required(z1), required(z2), required(z3)], F).

test(seedable_false_for_masked_flag,
     [setup(assertz(preference:local_profile_masked_use_flag(z3))),
      cleanup(retract(preference:local_profile_masked_use_flag(z3))),
      fail]) :-
  use:requse_flag_seedable(portage://'nonexistent-pkg-0', z3).

test(seedable_true_for_unmasked_flag, [true]) :-
  use:requse_flag_seedable(portage://'nonexistent-pkg-0', z1).

% When every member is masked the group is genuinely unsatisfiable; the
% seeder falls back to the full list (last member) rather than failing, so
% the normal domain-assumption path still reports it.
test(all_masked_falls_back_to_full_list,
     [setup(( assertz(preference:local_profile_masked_use_flag(z1)),
              assertz(preference:local_profile_masked_use_flag(z2)),
              assertz(preference:local_profile_masked_use_flag(z3)) )),
      cleanup(( retract(preference:local_profile_masked_use_flag(z1)),
                retract(preference:local_profile_masked_use_flag(z2)),
                retract(preference:local_profile_masked_use_flag(z3)) )),
      true(F == z3)]) :-
  use:requse_pick_satisfying_flag(portage://'nonexistent-pkg-0',
      [required(z1), required(z2), required(z3)], F).

:- end_tests(rules_required_use_choice_seed).


% Synthetic qtest entry fixtures shared by the USE rule units below. All
% are KB-independent: CI has no Portage tree, so no live metadata may be
% required.

%! use_entry_memo_reset(+Repo://Id) is det.
%
% Drops every per-entry USE memo so a unit starts from cold caches.

use_entry_memo_reset(Repo://Id) :-
  retractall(memo:eff_use_cache_(Repo, Id, _, _)),
  retractall(memo:iuse_default_cache_(Repo, Id, _)),
  retractall(memo:self_use_cache_(Repo, Id, _, _)).


%! use_entry_setup(+Repo://Id, +Category, +Name, +Flag) is det.
%
% Registers Repo://Id as version 0 of Category/Name with Flag declared in
% IUSE (default off), on cold USE memos.

use_entry_setup(Repo://Id, Category, Name, Flag) :-
  use_entry_cleanup(Repo://Id),
  assertz(cache:ordered_entry(Repo, Id, Category, Name,
                              version([0],'',4,0,[],0,'0'))),
  empty_assoc(Empty),
  put_assoc(Flag, Empty, negative, Map),
  assertz(memo:iuse_default_cache_(Repo, Id, Map)).


%! use_entry_cleanup(+Repo://Id) is det.

use_entry_cleanup(Repo://Id) :-
  retractall(cache:ordered_entry(Repo, Id, _, _, _)),
  use_entry_memo_reset(Repo://Id).


% Joint USE-dep / REQUIRED_USE / profile-hard fail-closed checks
% (portage-ng#109/#111 — emerge use_dep_unsat class).
%
% Synthetic qtest entry + memo:eff_use_cache_/4 (same pattern as
% builder_base_use_state).
:- begin_tests(rules_use_dep_unsat).

ude_entry(qtest://'acct-user/git-0').
ude_requse(exactly_one_of_group([required(git), required(gitea),
                                 required(gitolite)])).

ude_setup :-
  ude_entry(E),
  ude_cleanup,
  E = Repo://Id,
  ude_requse(RU),
  assertz(cache:entry_metadata(Repo, Id, required_use, RU)),
  % Profile/default-on sibling (not HARD atom): positive via eff-use memo.
  assertz(memo:eff_use_cache_(Repo, Id, git, positive)).

ude_cleanup :-
  ude_entry(Repo://Id),
  use_entry_memo_reset(Repo://Id),
  retractall(cache:entry_metadata(Repo, Id, required_use, _)).

% Exactly-one-of with two positives: disable the non-HARD sibling.
test(exactly_one_of_n_gt_1_disables_non_hard,
     [setup(ude_setup), cleanup(ude_cleanup),
      true(Fixes == [disable(git)])]) :-
  ude_entry(E), ude_requse(RU),
  use:requse_term_fixes(E, [gitea], [], RU, Fixes).

% Two HARD enables in ^^ cannot be fixed by disable — Fixes fails.
test(exactly_one_of_two_hard_unfixable,
     [setup(ude_setup), cleanup(ude_cleanup), fail]) :-
  ude_entry(E), ude_requse(RU),
  use:requse_term_fixes(E, [git, gitea], [], RU, _).

% HARD enable of a globally masked flag is use_dep_unsat.
test(bwu_rejects_masked_hard_enable,
     [setup(assertz(preference:local_profile_masked_use_flag(gitea))),
      cleanup(retract(preference:local_profile_masked_use_flag(gitea))),
      fail]) :-
  ude_entry(E),
  use:bwu_respects_profile_hard(E, use_state([gitea], [])).

test(bwu_accepts_unmasked_hard_enable, [true]) :-
  ude_entry(E),
  use:bwu_respects_profile_hard(E, use_state([gitea], [])).

% Post-stabilize joint check: REQUIRED_USE ^^ with two HARD enables fails.
test(use_dep_atom_unsat_on_hard_collision,
     [setup(ude_setup), cleanup(ude_cleanup), fail]) :-
  ude_entry(E),
  use:use_dep_atom_satisfiable(E, use_state([git, gitea], [])).

test(use_dep_atom_sat_after_disable_sibling,
     [setup(ude_setup), cleanup(ude_cleanup), true]) :-
  ude_entry(E),
  use:use_dep_atom_satisfiable(E, use_state([gitea], [git, gitolite])).

:- end_tests(rules_use_dep_unsat).


% Leftover REQUIRED_USE ^^ conflict after stabilize (portage-ng#120).
% The :validate model is proved without BWU, so empty profile USE plus
% a parent [gitea] atom records assumed(conflict(required_use, ^^))
% even though BResolved is already legal. That leftover must not invent
% gitolite (last-member pick) for dep-walk, suggestions, or the executor.

:- begin_tests(rules_requse_leftover_conflict).

% Local copy of the #111 qtest fixture: PLUnit setups are module-local.
lfc_entry(qtest://'acct-user/git-0').
lfc_group(exactly_one_of_group([required(git), required(gitea),
                                required(gitolite)])).
lfc_conflict(assumed(conflict(required_use, Group))) :-
  lfc_group(Group).

lfc_setup :-
  lfc_entry(E),
  lfc_cleanup,
  E = Repo://Id,
  lfc_group(RU),
  assertz(cache:entry_metadata(Repo, Id, required_use, RU)),
  assertz(memo:eff_use_cache_(Repo, Id, git, positive)).

lfc_cleanup :-
  lfc_entry(Repo://Id),
  use_entry_memo_reset(Repo://Id),
  retractall(cache:entry_metadata(Repo, Id, required_use, _)).

test(conflict_pick_skipped_when_bwu_has_member, [true(Changes == [])]) :-
  lfc_conflict(C),
  use:model_required_use_changes([C], use_state([gitea], []), Changes).

% z1/z2/z3 are not in global USE, so pick_flag falls back to last.
test(conflict_pick_without_bwu_still_last_member,
     [true(Changes == [use_change(z3, enable)])]) :-
  C = assumed(conflict(required_use,
        exactly_one_of_group([required(z1), required(z2), required(z3)]))),
  use:model_required_use_changes([C], Changes).

test(reconcile_drops_when_verify_ok,
     [setup(lfc_setup), cleanup(lfc_cleanup),
      true(R == [])]) :-
  lfc_entry(E),
  lfc_conflict(C),
  use:reconcile_required_use_model(E, use_state([gitea], [git, gitolite]),
                                   [C], R).

test(reconcile_drops_covered_even_if_verify_open,
     [setup(lfc_setup), cleanup(lfc_cleanup),
      true(R == [])]) :-
  lfc_entry(E),
  lfc_conflict(C),
  use:reconcile_required_use_model(E, use_state([gitea], []), [C], R).

test(reconcile_keeps_conflict_on_empty_bwu,
     [setup(lfc_setup), cleanup(lfc_cleanup)]) :-
  lfc_entry(E),
  lfc_conflict(C),
  use:reconcile_required_use_model(E, use_state([], []), [C], R),
  assertion(R == [C]).

test(reconcile_keeps_real_assumed_flag,
     [setup(lfc_setup), cleanup(lfc_cleanup),
      true(R == [assumed(gitea)])]) :-
  lfc_entry(E),
  lfc_conflict(C),
  use:reconcile_required_use_model(E, use_state([gitea], [git, gitolite]),
                                   [assumed(gitea), C], R).

test(dep_walk_does_not_add_sibling,
     [true(BWU == use_state([gitea], []))]) :-
  lfc_conflict(C),
  use:dep_walk_context([C], use_state([gitea], []), [other:x], Model),
  memberchk(build_with_use:BWU, Model).

:- end_tests(rules_requse_leftover_conflict).


% Global use.mask beats soft profile package.use (clang-runtime abi_x86_32
% on non-multilib amd64). Soft enable must not make optenable `[flag?]`
% force a masked flag onto dependencies.
:- begin_tests(rules_use_mask_beats_soft).

ums_entry(qtest://'llvm-runtimes/clang-runtime-0').

ums_setup :-
  ums_entry(E),
  ums_cleanup,
  % Flag declared in IUSE default-off so soft/mask apply.
  use_entry_setup(E, 'llvm-runtimes', 'clang-runtime', abi_x86_32),
  assertz(preference:local_profile_masked_use_flag(abi_x86_32)),
  assertz(preference:local_profile_use_soft(
            simple('llvm-runtimes', 'clang-runtime', []),
            abi_x86_32, positive)).

ums_cleanup :-
  ums_entry(E),
  use_entry_cleanup(E),
  retractall(preference:local_profile_masked_use_flag(abi_x86_32)),
  retractall(preference:local_profile_use_soft(simple('llvm-runtimes',
                                                     'clang-runtime', _),
                                              abi_x86_32, _)).

test(effective_use_masked_despite_soft_package_use,
     [setup(ums_setup), cleanup(ums_cleanup),
      true(Pol == negative)]) :-
  ums_entry(E),
  use:effective_use_for_entry(E, abi_x86_32, Pol).

test(optenable_skips_globally_masked_flag,
     [setup(ums_setup), cleanup(ums_cleanup),
      true(Req == none)]) :-
  ums_entry(E),
  use:use_dep_requirement([self(E)], optenable(abi_x86_32), negative, Req).

:- end_tests(rules_use_mask_beats_soft).


% Consumer-gated USE deps (`[F?]`, `[!F?]`, `[F=]`, `[!F=]`) must be decided
% from the consumer's SOLVED USE -- the ?{Context} build_with_use that
% dep_walk_context/4 fills with the post-REQUIRED_USE picks -- not from the
% profile + IUSE reading alone (portage-ng#121). Both polarities matter: a
% solved enable makes the gate live, a solved disable vetoes it.
:- begin_tests(rules_gated_use_dep_solved_state).

% Profile says the flag is OFF (IUSE `bar`, i.e. declared default-off).
gus_off_entry(qtest://'x11-libs/consumer-off-0').

% Profile says the flag is ON (IUSE `+bar`, nothing overriding it).
gus_on_entry(qtest://'x11-libs/consumer-on-0').

gus_setup :-
  gus_cleanup,
  gus_off_entry(OffRepo://OffId),
  assertz(cache:ordered_entry(OffRepo, OffId, 'x11-libs', 'consumer-off',
                              version([0],'',4,0,[],0,'0'))),
  assertz(cache:entry_metadata(OffRepo, OffId, iuse, bar)),
  assertz(memo:eff_use_cache_(OffRepo, OffId, bar, negative)),
  gus_on_entry(OnRepo://OnId),
  assertz(cache:ordered_entry(OnRepo, OnId, 'x11-libs', 'consumer-on',
                              version([0],'',4,0,[],0,'0'))),
  assertz(cache:entry_metadata(OnRepo, OnId, iuse, plus(bar))).

gus_cleanup :-
  gus_off_entry(OffRepo://OffId),
  retractall(cache:ordered_entry(OffRepo, OffId, _, _, _)),
  retractall(cache:entry_metadata(OffRepo, OffId, _, _)),
  use_entry_memo_reset(OffRepo://OffId),
  gus_on_entry(OnRepo://OnId),
  retractall(cache:ordered_entry(OnRepo, OnId, _, _, _)),
  retractall(cache:entry_metadata(OnRepo, OnId, _, _)),
  use_entry_memo_reset(OnRepo://OnId).

% REQUIRED_USE forced the flag on: `[bar?]` is live even though the profile
% has it off. The prover's `assumed(bar)` key reaches the gate as the
% consumer's build_with_use via dep_walk_context/4.
test(requse_enable_makes_optenable_live,
     [setup(gus_setup), cleanup(gus_cleanup),
      true(Req == requirement(enable, bar, none))]) :-
  gus_off_entry(E),
  use:dep_walk_context([assumed(bar)], use_state([],[]),
                       [build_with_use:use_state([],[])], Model),
  use:use_dep_requirement([self(E)|Model], optenable(bar), none, Req).

% Same solved state for the bidirectional form.
test(requse_enable_makes_equal_follow,
     [setup(gus_setup), cleanup(gus_cleanup),
      true(Req == requirement(enable, bar, none))]) :-
  gus_off_entry(E),
  use:use_dep_requirement([self(E), build_with_use:use_state([bar],[])],
                          equal(bar), none, Req).

% Nothing flipped the flag: the gate stays inert.
test(profile_off_keeps_optenable_inert,
     [setup(gus_setup), cleanup(gus_cleanup),
      true(Req == none)]) :-
  gus_off_entry(E),
  use:use_dep_requirement([self(E)], optenable(bar), none, Req).

% The veto direction: profile has the flag on, but the solved state turns it
% off, so `[bar?]` must not force `+bar` onto the provider.
test(solved_disable_vetoes_optenable,
     [setup(gus_setup), cleanup(gus_cleanup),
      true(Req == none)]) :-
  gus_on_entry(E),
  use:use_dep_requirement([self(E), build_with_use:use_state([],[bar])],
                          optenable(bar), none, Req).

% Without a solved disable the same edge stays live (profile reading).
test(profile_on_keeps_optenable_live,
     [setup(gus_setup), cleanup(gus_cleanup),
      true(Req == requirement(enable, bar, none))]) :-
  gus_on_entry(E),
  use:use_dep_requirement([self(E)], optenable(bar), none, Req).

% Mirror image: profile has the flag off, the solved state turns it on, so
% `[!bar?]` must not force `-bar` onto the provider.
test(solved_enable_vetoes_optdisable,
     [setup(gus_setup), cleanup(gus_cleanup),
      true(Req == none)]) :-
  gus_off_entry(E),
  use:use_dep_requirement([self(E), build_with_use:use_state([bar],[])],
                          optdisable(bar), none, Req).

test(profile_off_keeps_optdisable_live,
     [setup(gus_setup), cleanup(gus_cleanup),
      true(Req == requirement(disable, bar, none))]) :-
  gus_off_entry(E),
  use:use_dep_requirement([self(E)], optdisable(bar), none, Req).

% A solved disable is also what `[bar=]` / `[!bar=]` follow.
test(solved_disable_drives_equal,
     [setup(gus_setup), cleanup(gus_cleanup),
      true(Req == requirement(disable, bar, none))]) :-
  gus_on_entry(E),
  use:use_dep_requirement([self(E), build_with_use:use_state([],[bar])],
                          equal(bar), none, Req).

test(solved_disable_drives_inverse,
     [setup(gus_setup), cleanup(gus_cleanup),
      true(Req == requirement(enable, bar, none))]) :-
  gus_on_entry(E),
  use:use_dep_requirement([self(E), build_with_use:use_state([],[bar])],
                          inverse(bar), none, Req).

:- end_tests(rules_gated_use_dep_solved_state).


% Global use.mask beats global use.force when both apply (Gentoo
% arch/base big-endian: "Forced and masked by default"). Force-before-
% mask incorrectly enabled the flag and broke strict binpkg USE match
% for ghc (#113).
:- begin_tests(rules_use_mask_beats_force).

umf_entry(qtest://'dev-lang/ghc-0').

umf_setup :-
  umf_entry(E),
  umf_cleanup,
  use_entry_setup(E, 'dev-lang', ghc, 'big-endian'),
  assertz(preference:local_profile_masked_use_flag('big-endian')),
  assertz(preference:local_profile_forced_use_flag('big-endian')).

umf_cleanup :-
  umf_entry(E),
  use_entry_cleanup(E),
  retractall(preference:local_profile_masked_use_flag('big-endian')),
  retractall(preference:local_profile_forced_use_flag('big-endian')).

test(effective_use_masked_despite_global_force,
     [setup(umf_setup), cleanup(umf_cleanup),
      true(Pol == negative)]) :-
  umf_entry(E),
  use:effective_use_for_entry(E, 'big-endian', Pol).

test(candidate_raw_excludes_forced_and_masked,
     [setup(umf_setup), cleanup(umf_cleanup)]) :-
  umf_entry(E),
  \+ use:candidate_effective_use_enabled_raw(E, 'big-endian').

test(categorize_use_mask_beats_force,
     [setup(umf_setup), cleanup(umf_cleanup),
      true(State == negative),
      true(Reason == profile_use_mask)]) :-
  umf_entry(E),
  eapi:categorize_use_for_entry('big-endian', E, State, Reason).

:- end_tests(rules_use_mask_beats_force).


:- begin_tests(use_candidate_bwu_memo, [cleanup(use:clear_bwu_cross_dep_memos)]).

test(merge_empty_ctx_with_memo, [true(B == use_state([wayland],[]))]) :-
  use:clear_bwu_cross_dep_memos,
  assertz(memo:candidate_bwu_('dev-qt', qtbase, use_state([wayland], []))),
  use:merge_memo_candidate_bwu('dev-qt', qtbase, use_state([], []), B).

test(merge_union_ctx_and_memo, [true(B == use_state([gui,wayland],[]))]) :-
  use:clear_bwu_cross_dep_memos,
  assertz(memo:candidate_bwu_('dev-qt', qtbase, use_state([wayland], []))),
  use:merge_memo_candidate_bwu('dev-qt', qtbase, use_state([gui], []), B).

test(accumulate_two_edges, [true(M == use_state([icu,wayland],[]))]) :-
  use:clear_bwu_cross_dep_memos,
  use:accumulate_candidate_bwu('dev-qt', qtbase, use_state([wayland], [])),
  use:accumulate_candidate_bwu('dev-qt', qtbase, use_state([icu], [])),
  memo:candidate_bwu_('dev-qt', qtbase, M).

test(seed_run_before_install_phase, [true(M == use_state([dbus],[]))]) :-
  use:clear_bwu_cross_dep_memos,
  InstallDeps = [grouped_package_dependency(no, 'dev-libs', glib,
      [package_dependency(install, no, 'dev-libs', glib, none, version_none, [], [])])],
  RunDeps = [grouped_package_dependency(no, 'dev-libs', glib,
      [package_dependency(run, no, 'dev-libs', glib, none, version_none, [],
                          [use(enable(dbus), positive)])])],
  ranking:seed_bwu_memo_from_dep_tree(InstallDeps),
  ranking:seed_bwu_memo_from_dep_tree(RunDeps),
  memo:candidate_bwu_('dev-libs', glib, M).

:- end_tests(use_candidate_bwu_memo).


:- begin_tests(equality_use_pin_propagation, [cleanup(use:clear_bwu_cross_dep_memos)]).

test(equal_provider_enabled_enables_self, [true(Mode == enable)]) :-
  use:clear_bwu_cross_dep_memos,
  assertz(memo:candidate_bwu_('dev-qt', qtbase, use_state([icu], []))),
  once(ranking:equality_pin_from_usedep('dev-qt', qtbase, use(equal(icu), negative), icu, Mode)).

test(equal_provider_disabled_disables_self, [true(Mode == disable)]) :-
  use:clear_bwu_cross_dep_memos,
  assertz(memo:candidate_bwu_('dev-qt', qtbase, use_state([], [icu]))),
  once(ranking:equality_pin_from_usedep('dev-qt', qtbase, use(equal(icu), positive), icu, Mode)).

test(inverse_provider_enabled_disables_self, [true(Mode == disable)]) :-
  use:clear_bwu_cross_dep_memos,
  assertz(memo:candidate_bwu_('dev-qt', qtbase, use_state([icu], []))),
  once(ranking:equality_pin_from_usedep('dev-qt', qtbase, use(inverse(icu), negative), icu, Mode)).

test(inverse_provider_disabled_enables_self, [true(Mode == enable)]) :-
  use:clear_bwu_cross_dep_memos,
  assertz(memo:candidate_bwu_('dev-qt', qtbase, use_state([], [icu]))),
  once(ranking:equality_pin_from_usedep('dev-qt', qtbase, use(inverse(icu), positive), icu, Mode)).

test(unpinned_provider_yields_no_pin, [fail]) :-
  use:clear_bwu_cross_dep_memos,
  ranking:equality_pin_from_usedep('dev-qt', qtbase, use(equal(icu), negative), icu, _Mode).

test(term_walk_collects_top_level, [true(Pairs == [icu-enable])]) :-
  use:clear_bwu_cross_dep_memos,
  assertz(memo:candidate_bwu_('dev-qt', qtbase, use_state([icu], []))),
  Term = package_dependency(install, no, 'dev-qt', qtbase, tilde, version_none, [],
                            [use(equal(icu), negative), use(enable(network), positive)]),
  findall(F-M, ranking:equality_pin_from_term(Term, F, M), Pairs).

test(term_walk_descends_all_of_group, [true(Pairs == [icu-enable])]) :-
  use:clear_bwu_cross_dep_memos,
  assertz(memo:candidate_bwu_('dev-qt', qtbase, use_state([icu], []))),
  Term = all_of_group([package_dependency(install, no, 'dev-qt', qtbase, tilde, version_none, [],
                                          [use(equal(icu), negative)])]),
  findall(F-M, ranking:equality_pin_from_term(Term, F, M), Pairs).

test(conditional_group_not_descended, [true(Pairs == [])]) :-
  use:clear_bwu_cross_dep_memos,
  assertz(memo:candidate_bwu_('dev-qt', qtbase, use_state([icu], []))),
  Term = use_conditional_group(positive, someflag, none,
           [package_dependency(install, no, 'dev-qt', qtbase, tilde, version_none, [],
                               [use(equal(icu), negative)])]),
  findall(F-M, ranking:equality_pin_from_term(Term, F, M), Pairs).

test(pin_conflict_detected) :-
  ranking:pin_flags_conflict([icu], [icu]).

test(pin_no_conflict, [fail]) :-
  ranking:pin_flags_conflict([icu], [foo]).

test(seed_conditional_minus_use_recurses, [fail]) :-
  ranking:seed_use_conditional_inactive(positive, minus(foo), some://entry).

test(seed_conditional_non_entry_recurses, [fail]) :-
  ranking:seed_use_conditional_inactive(positive, foo, not_an_entry).

:- end_tests(equality_use_pin_propagation).


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
