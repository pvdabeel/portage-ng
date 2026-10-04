/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> REBUILDTEST
Unit tests for rebuilds of already-installed packages.

Sub-slot (:=) ABI rebuild obligations (portage-ng#89), bracketed-USE
rebuilds, suggestion(use_change) rebuilds (portage-ng#85) and the
same-version :update on a USE change (issue #9). The VDB-dependent
units skip when no installed package with a matching flag exists.
*/

:- module(rebuildtest, []).

:- use_module(library(plunit)).
:- use_module(library(assoc)).
:- use_module(library(lists)).

% =============================================================================
%  REBUILDTEST declarations
% =============================================================================

% Sub-slot (:=) ABI rebuild obligations (portage-ng#89, abirebuild module).
:- begin_tests(abirebuild).

% A := dependency (any_same_slot) binds to the provider's sub-slot in any slot.
test(any_same_slot_binds_any_slot, [true]) :-
  abirebuild:bound_slotspec([any_same_slot], '0').

test(any_same_slot_binds_other_slot, [true]) :-
  abirebuild:bound_slotspec([any_same_slot], '2').

% A :slot= dependency binds only when the slot matches the changed provider.
test(slot_equal_binds_matching_slot, [true]) :-
  abirebuild:bound_slotspec([slot('0'), equal], '0').

test(slot_equal_rejects_other_slot, [fail]) :-
  abirebuild:bound_slotspec([slot('1'), equal], '0').

% A :slot/subslot= dependency binds on slot match (sub-slot is the trigger).
test(slot_subslot_equal_binds_matching_slot, [true]) :-
  abirebuild:bound_slotspec([slot('0'), subslot('1.2'), equal], '0').

% A plain slot / sub-slot dependency without `=` is NOT a rebuild trigger.
test(plain_slot_not_bound, [fail]) :-
  abirebuild:bound_slotspec([slot('0')], '0').

test(plain_slot_subslot_not_bound, [fail]) :-
  abirebuild:bound_slotspec([slot('0'), subslot('1.2')], '0').

test(any_different_slot_not_bound, [fail]) :-
  abirebuild:bound_slotspec([any_different_slot], '0').

test(empty_slot_not_bound, [fail]) :-
  abirebuild:bound_slotspec([], '0').

% The consumer rebuild goal is a same-version :update that replaces the VDB
% entry and carries the subslot_change reason so the printer renders the note
% and the prover re-walks deps (ordering the rebuild after the provider).
test(consumer_goal_shape,
     [true(Goal == portage://'dev-x/c-1':update?{[replaces(pkg://'dev-x/c-1'),
              rebuild_reason(subslot_change('dev-x'/p, '0', '1'))]})]) :-
  abirebuild:consumer_goal(
      c('dev-x/c-1', portage, subslot_change('dev-x'/p, '0', '1')), Goal).

% Eligible rebuild goals gain a rebuild_after(Anchor) ordering marker, which
% rule expansion turns into a constraint(schedule_after(Anchor)) body literal
% so pass 2 places the rebuild after the provider (plain anchoring — not the
% order_after/PDEPEND-completion channel, which would serialize the plan).
test(ordered_goal_adds_rebuild_after_marker,
     [true(Goal == portage://'dev-x/c-1':update?{[rebuild_after(portage://'dev-x/p-2':update),
              replaces(pkg://'dev-x/c-1')]})]) :-
  abirebuild:ordered_goal(portage://'dev-x/p-2':update,
      portage://'dev-x/c-1':update?{[replaces(pkg://'dev-x/c-1')]}, Goal).

% A VDB-only orphan is reported as assumed(... no_tree_ebuild), not as
% a masked/keyword leftover. The wrap is the standard domain-assumption
% rule so the proof does not climb the unmask tier.
test(skipped_assumption_adds_reason,
     [true(Assumed == assumed(pkg://'dev-x/c-1':update?{[assumption_reason(no_tree_ebuild),
              replaces(pkg://'dev-x/c-1'),
              rebuild_reason(subslot_change('dev-x'/p, '0', '1'))]}))]) :-
  Goal = pkg://'dev-x/c-1':update?{[replaces(pkg://'dev-x/c-1'),
              rebuild_reason(subslot_change('dev-x'/p, '0', '1'))]},
  abirebuild:skipped_assumption(no_tree_ebuild, Goal, Assumed).

% Visible sibling older than the installed CPV is a downgrade; newer or
% equal is an update. Mask substitute uses this; keyword-filtered never
% does (it stays on the installed CPV).
test(replace_action_older_is_downgrade,
     [true(Action == downgrade)]) :-
  atom_codes('0.470.0', OldCs), once(phrase(eapi:version(Old), OldCs)),
  atom_codes('0.480.0', NewCs), once(phrase(eapi:version(New), NewCs)),
  abirebuild:replace_action(New, Old, Action).

test(replace_action_newer_is_update,
     [true(Action == update)]) :-
  atom_codes('0.470.0', OldCs), once(phrase(eapi:version(Old), OldCs)),
  atom_codes('0.480.0', NewCs), once(phrase(eapi:version(New), NewCs)),
  abirebuild:replace_action(Old, New, Action).

test(replace_action_equal_is_update,
     [true(Action == update)]) :-
  atom_codes('0.480.0', Cs), once(phrase(eapi:version(V), Cs)),
  abirebuild:replace_action(V, V, Action).

% Same-CPV ABI repair context passes eligibility without assuming unmask.
test(abi_repair_eligible_same_cpv, [true]) :-
  candidate:abi_repair_eligible(portage, 'dev-x/c-1',
      [rebuild_reason(subslot_change('dev-x'/p, '0', '1')),
       replaces(pkg://'dev-x/c-1')]).

test(abi_repair_eligible_rejects_other_cpv, [fail]) :-
  candidate:abi_repair_eligible(portage, 'dev-x/other-1',
      [rebuild_reason(subslot_change('dev-x'/p, '0', '1')),
       replaces(pkg://'dev-x/c-1')]).

test(abi_repair_eligible_rejects_plain_update, [fail]) :-
  candidate:abi_repair_eligible(portage, 'dev-x/c-1', []).

% A consumer whose entry is already merged in the model needs no rebuild.
test(model_merge_covers_rebuild, [true]) :-
  list_to_assoc([(portage://'dev-x/c-1':update)-[]], Model),
  abirebuild:model_merges_entry(Model,
      portage://'dev-x/c-1':update?{[replaces(pkg://'dev-x/c-1')]}).

test(empty_model_covers_nothing, [fail]) :-
  abirebuild:model_merges_entry(t,
      portage://'dev-x/c-1':update?{[replaces(pkg://'dev-x/c-1')]}).

% Obligations short-circuit to [] when suspended (test_stats harness mode)
% and when the anchor changes no provider sub-slot.
test(obligations_empty_when_suspended,
     [setup(assertz(abirebuild:suspended)),
      cleanup(retractall(abirebuild:suspended)),
      true(Lits == [])]) :-
  abirebuild:obligations(portage://'dev-x/p-1':install, t, Lits).

test(obligations_empty_without_provider_change, [true(Lits == [])]) :-
  abirebuild:obligations(portage://'dev-x/does-not-exist-1':install, t, Lits).

:- end_tests(abirebuild).


% -----------------------------------------------------------------------------
%  Bracketed-USE rebuild for already-installed packages
% -----------------------------------------------------------------------------
% Regression test for the resolver gap that caused podman → iptables[nftables]
% to schedule libnftnl/libmnl AFTER iptables. Root cause: rule(:install/:run
% ?{Ctx}) short-circuited to []/[reinstall] for already-installed packages
% without checking whether the requested build_with_use matched the VDB-
% recorded USE. Fix: when BWU mismatches, re-emit as a transactional :update
% with `replaces(pkg://Ebuild)` so candidate:resolve walks DEPEND/BDEPEND
% under the new BWU and the orderer places newly-required deps before
% the rebuild.

% Find an installed package with at least one IUSE flag the VDB build
% does NOT have enabled, so we can construct a real BWU mismatch. We
% prefer net-firewall/iptables (has nftables IUSE) and fall back to any
% installed entry that satisfies the predicate. Defined at file level so
% both the rules_install_run_bwu_rebuild and update_use_change_resolve
% units below can share it (PLUnit units inherit from this module).
test_setup_pick(pkg://Ebuild, Flag) :-
  ( query:search([category('net-firewall'),name(iptables),installed(true)], pkg://Ebuild),
    Flag = nftables,
    cache:entry_metadata(pkg, Ebuild, iuse, Flag),
    \+ cache:entry_metadata(pkg, Ebuild, use, Flag), !
  ; query:search([category(C),name(N),installed(true)], pkg://Ebuild),
    cache:entry_metadata(pkg, Ebuild, iuse, Flag),
    \+ cache:entry_metadata(pkg, Ebuild, use, Flag),
    \+ memberchk(C, ['virtual','acct-group','acct-user']),
    atom(N), atom(Flag), !
  ).


:- begin_tests(rules_install_run_bwu_rebuild).

% NOTE: these tests require a populated VDB (installed packages with IUSE
% metadata) and so are gated on `condition(test_setup_pick/2 succeeds)`.
% In CI (no portage tree, no VDB) they are reported as `[blocked]` rather
% than failed. Locally with a real VDB they run end-to-end.

% Pre-fix probe: confirms `installed_entry_satisfies_build_with_use` returns
% false for the chosen mismatched flag (i.e. the test scenario is valid).
test(probe_setup,
     [condition(test_setup_pick(_, _))]) :-
  test_setup_pick(pkg://Ebuild, Flag),
  Ctx = [build_with_use:use_state([Flag],[])],
  \+ use:installed_entry_satisfies_build_with_use(pkg://Ebuild, Ctx).

% rule(:install?{Ctx with mismatched bracketed-USE}) on an installed entry
% must NOT short-circuit to []. It must emit a :update?{[...,replaces,...]}
% literal so the dep walker runs.
test(install_rule_emits_update_on_bwu_mismatch,
     [condition(test_setup_pick(_, _))]) :-
  test_setup_pick(pkg://Ebuild, Flag),
  Ctx = [build_with_use:use_state([Flag],[])],
  resolving:rule(portage://Ebuild:install?{Ctx}, Conds),
  Conds = [portage://Ebuild:update?{UpdCtx}],
  memberchk(replaces(pkg://Ebuild), UpdCtx),
  memberchk(rebuild_reason(build_with_use), UpdCtx).

% rule(:run?{Ctx with mismatched bracketed-USE}) on an installed entry must
% emit the same :update literal (instead of degrading to :reinstall with an
% empty body).
test(run_rule_emits_update_on_bwu_mismatch,
     [condition(test_setup_pick(_, _))]) :-
  test_setup_pick(pkg://Ebuild, Flag),
  Ctx = [build_with_use:use_state([Flag],[])],
  resolving:rule(portage://Ebuild:run?{Ctx}, Conds),
  Conds = [portage://Ebuild:update?{UpdCtx}],
  memberchk(replaces(pkg://Ebuild), UpdCtx),
  memberchk(rebuild_reason(build_with_use), UpdCtx).

% Empty Ctx (no bracketed-USE annotation) on an installed entry preserves
% the existing fast-path: no rebuild emitted.
test(install_rule_empty_ctx_keeps_short_circuit,
     [condition(test_setup_pick(_, _))]) :-
  test_setup_pick(pkg://Ebuild, _),
  resolving:rule(portage://Ebuild:install?{[]}, Conds),
  Conds == [].

% End-to-end: prove + plan iptables:run with bracketed-[nftables].
% Verify (a) libnftnl ends up in the proof, (b) iptables:update appears in
% the plan, (c) libnftnl:install is in an EARLIER wave than iptables:update.
test(plan_orders_bwu_dep_before_rebuild,
     [condition(query:search([category('net-firewall'),name(iptables),
                              installed(true)], pkg://_))]) :-
  query:search([category('net-firewall'),name(iptables)], portage://RepoE),
  !,
  Goal = portage://RepoE:run?{[build_with_use:use_state([nftables],[])]},
  pipeline:prove_with_fallback([Goal], Proof, _Model, Triggers),
  orderer:order(Proof, Triggers, _ProofOut, Plan),
  % Find the wave index of any libnftnl literal vs any iptables-VVV:update.
  nth1(WLib, Plan, WaveLib),
    member(RLib, WaveLib),
    prover:rule_parts(RLib, HLib, _, _),
    prover:canon_literal(HLib, CHLib, _),
    term_to_atom(CHLib, ALib), sub_atom(ALib, _, _, _, libnftnl), !,
  nth1(WIp, Plan, WaveIp),
    member(RIp, WaveIp),
    prover:rule_parts(RIp, HIp, _, _),
    prover:canon_literal(HIp, CHIp, _),
    term_to_atom(CHIp, AIp), sub_atom(AIp, _, _, _, 'iptables'),
    sub_atom(AIp, _, _, _, ':update'), !,
  WLib < WIp.

:- end_tests(rules_install_run_bwu_rebuild).


% -----------------------------------------------------------------------------
%  suggestion(use_change) rebuild for already-installed packages (portage-ng#85)
% -----------------------------------------------------------------------------
% Regression test for the asymmetry that left an already-installed package
% short-circuited to []/reinstall when a self USE flip arrived as a
% suggestion(use_change) with an EMPTY build_with_use term (e.g. a
% REQUIRED_USE pick, or a flip propagated via the per-(C,N) memo). The
% install/run short-circuit consulted installed_entry_satisfies_build_with_use/2
% only, which reported the installed -USE build as satisfactory and never
% reached candidate:update_requires_use_rebuild/2. Fix: consult
% use:installed_entry_satisfies_plan_use/3, which also honours self
% suggestion(use_change) flips, so a transactional :update is emitted and the
% deps gated by the flipped flag enter the plan.

:- begin_tests(rules_install_run_use_change_rebuild).

% installed_entry_satisfies_plan_use/3 must report NOT satisfied when a
% self suggestion(use_change) enables a flag the installed build lacks
% (and the flag is in the entry's IUSE).
test(plan_use_unsatisfied_on_suggestion_flip,
     [condition(test_setup_pick(_, _))]) :-
  test_setup_pick(pkg://Ebuild, Flag),
  Ctx = [suggestion(use_change, portage://Ebuild, [use_change(Flag, enable)])],
  \+ use:installed_entry_satisfies_plan_use(pkg://Ebuild, portage://Ebuild, Ctx).

% rule(:install?{Ctx with suggestion(use_change) flip}) on an installed entry
% must NOT short-circuit to []. It must emit a :update?{[...,replaces,...]}
% literal so the dep walker runs under the flipped USE.
test(install_rule_emits_update_on_use_change,
     [condition(test_setup_pick(_, _))]) :-
  test_setup_pick(pkg://Ebuild, Flag),
  Ctx = [suggestion(use_change, portage://Ebuild, [use_change(Flag, enable)])],
  resolving:rule(portage://Ebuild:install?{Ctx}, Conds),
  Conds = [portage://Ebuild:update?{UpdCtx}],
  memberchk(replaces(pkg://Ebuild), UpdCtx),
  memberchk(rebuild_reason(build_with_use), UpdCtx).

% rule(:run?{Ctx with suggestion(use_change) flip}) on an installed entry must
% emit the same :update literal (instead of degrading to :reinstall with an
% empty body).
test(run_rule_emits_update_on_use_change,
     [condition(test_setup_pick(_, _))]) :-
  test_setup_pick(pkg://Ebuild, Flag),
  Ctx = [suggestion(use_change, portage://Ebuild, [use_change(Flag, enable)])],
  resolving:rule(portage://Ebuild:run?{Ctx}, Conds),
  Conds = [portage://Ebuild:update?{UpdCtx}],
  memberchk(replaces(pkg://Ebuild), UpdCtx),
  memberchk(rebuild_reason(build_with_use), UpdCtx).

% A suggestion(use_change) for a flag NOT in the entry's IUSE cannot change
% the build, so it must preserve the short-circuit (no spurious rebuild).
test(install_rule_absent_flag_keeps_short_circuit,
     [condition(test_setup_pick(_, _))]) :-
  test_setup_pick(pkg://Ebuild, _),
  Ctx = [suggestion(use_change, portage://Ebuild,
                    [use_change('portage_ng_nonexistent_flag', enable)])],
  resolving:rule(portage://Ebuild:install?{Ctx}, Conds),
  Conds == [].

:- end_tests(rules_install_run_use_change_rebuild).


% -----------------------------------------------------------------------------
%  Issue #9: same-version :update must not no-op on USE change
% -----------------------------------------------------------------------------
:- begin_tests(update_use_change_resolve).

test_setup_same_version_installed(portage://RepoE, pkg://PkgE, Flag) :-
  test_setup_pick(pkg://PkgE, Flag),
  query:search([category(C),name(N),version(V)], pkg://PkgE),
  query:search([category(C),name(N),version(V)], portage://RepoE).

test(update_resolve_not_empty_on_use_change,
     [condition(test_setup_same_version_installed(_, _, _)), nondet]) :-
  test_setup_same_version_installed(portage://RepoE, _PkgE, Flag),
  Changes = [use_change(Flag, enable)],
  Ctx = [suggestion(use_change, portage://RepoE, Changes)],
  candidate:resolve(portage://RepoE:update?{Ctx}, Conds),
  Conds \== [].

:- end_tests(update_use_change_resolve).
