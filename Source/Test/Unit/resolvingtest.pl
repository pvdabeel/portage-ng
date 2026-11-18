/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> RESOLVINGTEST
Unit tests for the resolve-stage heuristics (Source/Domain/Gentoo/Rules/Resolving/heuristic.pl).

Deferred build_with_use force flush (portage-ng#94), conflict-driven
partial restart, and phantom grouped-dependency assumptions
(portage-ng#10, #14, #15).
*/

:- module(resolvingtest, []).

:- use_module(library(plunit)).
:- use_module(library(assoc)).
:- use_module(library(lists)).

% =============================================================================
%  RESOLVINGTEST declarations
% =============================================================================

% Deferred shared-dep USE-force flush (portage-ng#94): newly-learned forces
% are recorded in memo:bwu_force_pending_/3 instead of aborting the pass;
% heuristic:reprove_pending/1 reports them after the pass completes and
% prover:deferred_reprove_pending/3 turns them into a single batched reprove.

:- begin_tests(bwu_force_deferred_flush).

test(record_and_report_pending, [true(Pending == [bwu_force('dev-qt', qtbase, [icu, wayland])])]) :-
  use:clear_bwu_cross_dep_memos,
  use:record_bwu_force_pending('dev-qt', qtbase, [icu, wayland]),
  heuristic:reprove_pending(bwu_force_flush(Pending)).

test(record_replaces_previous_pending_for_same_cn, [true(Pending == [bwu_force('dev-qt', qtbase, [icu, wayland])])]) :-
  use:clear_bwu_cross_dep_memos,
  use:record_bwu_force_pending('dev-qt', qtbase, [icu]),
  use:record_bwu_force_pending('dev-qt', qtbase, [icu, wayland]),
  heuristic:reprove_pending(bwu_force_flush(Pending)).

test(no_pending_after_clear, [fail]) :-
  use:clear_bwu_cross_dep_memos,
  use:record_bwu_force_pending('dev-qt', qtbase, [icu]),
  use:clear_bwu_cross_dep_memos,
  heuristic:reprove_pending(_).

test(handle_reprove_confirms_flush_progress, [true(Added == true)]) :-
  heuristic:handle_reprove(bwu_force_flush([bwu_force('dev-qt', qtbase, [icu])]), Added).

test(deferred_reprove_pending_reports_flush_within_budget,
     [true(Info == bwu_force_flush([bwu_force('dev-qt', qtbase, [icu])])),
      cleanup(use:clear_bwu_cross_dep_memos)]) :-
  use:clear_bwu_cross_dep_memos,
  use:record_bwu_force_pending('dev-qt', qtbase, [icu]),
  prover:deferred_reprove_pending(0, 20, Info).

test(deferred_reprove_pending_fails_when_budget_exhausted,
     [fail, cleanup(use:clear_bwu_cross_dep_memos)]) :-
  use:clear_bwu_cross_dep_memos,
  use:record_bwu_force_pending('dev-qt', qtbase, [icu]),
  prover:deferred_reprove_pending(20, 20, _).

test(deferred_reprove_pending_fails_when_nothing_pending, [fail]) :-
  use:clear_bwu_cross_dep_memos,
  prover:deferred_reprove_pending(0, 20, _).

:- end_tests(bwu_force_deferred_flush).


% Conflict-driven partial restart (non-chronological backtracking): after a
% completed pass reports a deferred conflict, the prover prunes only the
% affected literals (domain seeds + dependents-closure over Triggers) from the
% completed artifacts and resumes proving from that state.  Generic machinery
% lives in prover.pl; seeds, obligation anchors and constraint scoping are
% domain hooks in heuristic.pl.

:- begin_tests(partial_restart).

test(triggers_closure_transitive, [true(Keys == [a, b, c])]) :-
  list_to_assoc([a-[b], b-[c], d-[e]], Triggers),
  prover:triggers_closure([a], Triggers, Affected),
  assoc_to_keys(Affected, Keys).

test(triggers_closure_handles_shared_dependents, [true(Keys == [a, b, c])]) :-
  list_to_assoc([a-[b, c], b-[c], c-[]], Triggers),
  prover:triggers_closure([a], Triggers, Affected),
  assoc_to_keys(Affected, Keys).

test(prune_model_removes_affected_plain_assumed_naf_keys, [true(Keys == [c])]) :-
  list_to_assoc([a-ctx1, assumed(b)-ctx2, naf(a)-ctx3, c-ctx4], Model),
  list_to_assoc([a-true, b-true], Affected),
  prover:prune_model(Model, Affected, RModel),
  assoc_to_keys(RModel, Keys).

test(prune_proof_removes_affected_entries,
     [true(Keys == [obligation_done(pdepend_none(c)), rule(c)])]) :-
  list_to_assoc([rule(a)-v1,
                 assumed(rule(b))-v2,
                 cycle_path(a)-v3,
                 obligation_pending(b)-v4,
                 obligation_done(pdepend(a, bwu))-v5,
                 obligation_done(pdepend_none(c))-v6,
                 rule(c)-v7], Proof),
  list_to_assoc([a-true, b-true], Affected),
  prover:prune_proof(Proof, Affected, bwu_force_flush([]), RProof),
  assoc_to_keys(RProof, Keys).

test(prune_triggers_drops_affected_keys_and_dependents, [true(Pairs == [b-[c]])]) :-
  list_to_assoc([a-[b, c], b-[a, c]], Triggers),
  list_to_assoc([a-true], Affected),
  prover:prune_triggers(Triggers, Affected, RTriggers),
  assoc_to_list(RTriggers, Pairs).

test(restart_seed_matches_pending_provider_actions,
     [setup(( retractall(cache:ordered_entry(fakerepo, _, _, _, _)),
              assertz(cache:ordered_entry(fakerepo, 'cat/pkg-1.0', cat, pkg, v)),
              assertz(cache:ordered_entry(fakerepo, 'cat/other-1.0', cat, other, v)) )),
      cleanup(retractall(cache:ordered_entry(fakerepo, _, _, _, _)))]) :-
  Info = bwu_force_flush([bwu_force(cat, pkg, [icu])]),
  heuristic:restart_seed(Info, fakerepo://'cat/pkg-1.0':install),
  heuristic:restart_seed(Info, fakerepo://'cat/pkg-1.0':run),
  % A degraded literal keeps its context inside the assumed/1 wrapper, so
  % the context-carrying shape has to seed as well or the stale assumption
  % survives the flush.
  heuristic:restart_seed(Info, fakerepo://'cat/pkg-1.0':install?{[issue_with_model(explanation)]}),
  heuristic:restart_seed(Info, issue_with_model(fakerepo://'cat/pkg-1.0')?{[issue_with_model(explanation)]}),
  \+ heuristic:restart_seed(Info, fakerepo://'cat/other-1.0':install),
  \+ heuristic:restart_seed(Info, fakerepo://'cat/other-1.0':install?{[]}),
  \+ heuristic:restart_seed(Info, grouped_dep(cat, pkg, []):install).

test(restart_seed_matches_equality_follow_on_both_ends,
     [setup(( retractall(cache:ordered_entry(fakerepo, _, _, _, _)),
              assertz(cache:ordered_entry(fakerepo, 'cat/consumer-1.0', cat, consumer, v)),
              assertz(cache:ordered_entry(fakerepo, 'cat/provider-1.0', cat, provider, v)),
              assertz(cache:ordered_entry(fakerepo, 'cat/other-1.0', cat, other, v)) )),
      cleanup(retractall(cache:ordered_entry(fakerepo, _, _, _, _)))]) :-
  Info = bwu_force_flush([eq_follow(cat, consumer, use_state([icu], []),
                                    provider(cat, provider))]),
  heuristic:restart_seed(Info, fakerepo://'cat/consumer-1.0':install),
  heuristic:restart_seed(Info, fakerepo://'cat/provider-1.0':install?{[]}),
  \+ heuristic:restart_seed(Info, fakerepo://'cat/other-1.0':install).

test(restart_obligation_head_maps_pdepend_keys) :-
  heuristic:restart_obligation_head(pdepend(fakerepo://'cat/pkg-1.0':install, bwu), Core1),
  Core1 == (fakerepo://'cat/pkg-1.0':install),
  heuristic:restart_obligation_head(pdepend_none(fakerepo://'cat/pkg-1.0':install), Core2),
  Core2 == (fakerepo://'cat/pkg-1.0':install).

test(strip_ctx_strips_action_attached_context) :-
  Lit = fakerepo://'cat/pkg-1.0':install?{[build_with_use:use_state([],[])]},
  heuristic:strip_ctx(Lit, Core),
  Core == (fakerepo://'cat/pkg-1.0':install),
  heuristic:obligation_candidate(Lit).

test(strip_ctx_matches_canon_literal_core) :-
  Lit = fakerepo://('cat/pkg-1.0':install?{[self(x)]}),
  heuristic:strip_ctx(Lit, S),
  prover:canon_literal(Lit, C, _),
  S == C,
  S == (fakerepo://'cat/pkg-1.0':install).

test(strip_ctx_nested_union_ok_matches_canon) :-
  Inner = [build_with_use:use_state([icu],[])],
  Outer = [self(parent)],
  Lit = fakerepo://(('cat/pkg-1.0':install?{Inner})?{Outer}),
  heuristic:strip_ctx(Lit, S),
  prover:canon_literal(Lit, C, Ctx),
  S == C,
  S == (fakerepo://'cat/pkg-1.0':install),
  memberchk(self(parent), Ctx),
  memberchk(build_with_use:use_state([icu],[]), Ctx).

test(strip_ctx_nested_union_conflict_still_peels_core) :-
  Inner = [build_with_use:use_state([x],[])],
  Outer = [build_with_use:use_state([],[x])],
  Lit = fakerepo://(('cat/pkg-1.0':install?{Inner})?{Outer}),
  heuristic:strip_ctx(Lit, Core),
  Core == (fakerepo://'cat/pkg-1.0':install),
  \+ prover:canon_literal(Lit, _, _),
  heuristic:obligation_candidate(Lit).

% The exclusion is by repository name (acceptance:binpkg_repository/1), so
% the binary side must be called `binpkg`; only the synthetic `cat/pkg`
% rows are touched, never the rest of a loaded binpkg cache.
test(query_keyword_candidate_excludes_binpkg_repo,
     [setup(( keyword_candidate_fixture_clear,
              assertz(cache:ordered_entry(binpkg, 'cat/pkg-1.0-1', cat, pkg, v)),
              assertz(cache:ordered_entry(qtest, 'cat/pkg-1.0', cat, pkg, v)),
              assertz(cache:entry_metadata(binpkg, 'cat/pkg-1.0-1', keywords, amd64)),
              assertz(cache:entry_metadata(qtest, 'cat/pkg-1.0', keywords, amd64)) )),
      cleanup(keyword_candidate_fixture_clear)]) :-
  \+ acceptance:query_keyword_candidate(install, cat, pkg, amd64, [], binpkg://_),
  acceptance:query_keyword_candidate(install, cat, pkg, amd64, [], qtest://'cat/pkg-1.0').

keyword_candidate_fixture_clear :-
  retractall(cache:ordered_entry(binpkg, 'cat/pkg-1.0-1', _, _, _)),
  retractall(cache:ordered_entry(qtest, 'cat/pkg-1.0', _, _, _)),
  retractall(cache:entry_metadata(binpkg, 'cat/pkg-1.0-1', _, _)),
  retractall(cache:entry_metadata(qtest, 'cat/pkg-1.0', _, _)).

test(restart_drop_constraint_scopes_use_slot_selected,
     [setup(( retractall(cache:ordered_entry(fakerepo, _, _, _, _)),
              assertz(cache:ordered_entry(fakerepo, 'cat/pkg-1.0', cat, pkg, v)) )),
      cleanup(retractall(cache:ordered_entry(fakerepo, _, _, _, _)))]) :-
  list_to_assoc([(fakerepo://'cat/pkg-1.0':install)-true], Affected),
  heuristic:restart_constraint_scope(bwu_force_flush([]), Affected, Scope),
  heuristic:restart_drop_constraint(Scope, use(fakerepo://'cat/pkg-1.0')),
  heuristic:restart_drop_constraint(Scope, slot(cat, pkg, '0')),
  heuristic:restart_drop_constraint(Scope, selected_cn(cat, pkg)),
  \+ heuristic:restart_drop_constraint(Scope, use(fakerepo://'cat/other-1.0')),
  \+ heuristic:restart_drop_constraint(Scope, slot(cat, other, '0')),
  \+ heuristic:restart_drop_constraint(Scope, cn_domain(cat, pkg, '0')),
  \+ heuristic:restart_drop_constraint(Scope, blocked_cn(cat, pkg)).

test(partial_restart_state_prunes_provider_and_dependents,
     [setup(( retractall(cache:ordered_entry(fakerepo, _, _, _, _)),
              assertz(cache:ordered_entry(fakerepo, 'cat/pkg-1.0', cat, pkg, v)),
              assertz(cache:ordered_entry(fakerepo, 'cat/consumer-1.0', cat, consumer, v)),
              assertz(cache:ordered_entry(fakerepo, 'cat/bystander-1.0', cat, bystander, v)) )),
      cleanup(retractall(cache:ordered_entry(fakerepo, _, _, _, _)))]) :-
  Provider  = (fakerepo://'cat/pkg-1.0':install),
  Consumer  = (fakerepo://'cat/consumer-1.0':run),
  Bystander = (fakerepo://'cat/bystander-1.0':run),
  list_to_assoc([Provider-[], Consumer-[], Bystander-[]], Model),
  list_to_assoc([rule(Provider)-(dep(0, [])?[]),
                 rule(Consumer)-(dep(1, [Provider])?[]),
                 rule(Bystander)-(dep(0, [])?[])], Proof),
  list_to_assoc([Provider-[Consumer]], Triggers),
  list_to_assoc([use(fakerepo://'cat/pkg-1.0')-u1,
                 use(fakerepo://'cat/bystander-1.0')-u2,
                 selected_cn(cat, pkg)-s1,
                 cn_domain(cat, pkg, '0')-d1], Cons),
  Info = bwu_force_flush([bwu_force(cat, pkg, [icu])]),
  prover:partial_restart_state(Info, Proof, Model, Cons, Triggers,
                               RProof, RModel, RCons, RTrig, ResumeLits),
  assoc_to_keys(RModel, [Bystander]),
  assoc_to_keys(RProof, [rule(Bystander)]),
  assoc_to_keys(RTrig, []),
  assoc_to_keys(RCons, [use(fakerepo://'cat/bystander-1.0'), cn_domain(cat, pkg, '0')]),
  ResumeLits == [].


% An obligation contributes literals to the queue instead of to a rule
% body, so the Triggers index holds no edge from a contributed literal
% back to its anchor. Pruning a contributed literal therefore leaves the
% anchor proven and unreachable: unless the done marker is dropped AND
% the anchor re-requested, the contribution is gone from the completed
% proof for good (a PDEPEND closure vanishing when the restart seed sat
% inside it, portage-ng#121).
test(prune_proof_drops_obligation_whose_contribution_is_pruned,
     [true(Keys == [obligation_done(pdepend_none(anchor2)), rule(anchor1), rule(anchor2)])]) :-
  list_to_assoc([rule(anchor1)-v1,
                 rule(anchor2)-v2,
                 rule(contributed)-v3,
                 obligation_done(pdepend(anchor1, bwu))-[contributed],
                 obligation_done(pdepend_none(anchor2))-[]], Proof),
  list_to_assoc([contributed-true], Affected),
  prover:prune_proof(Proof, Affected, bwu_force_flush([]), RProof),
  assoc_to_keys(RProof, Keys).


test(restart_resume_anchors_re_requests_anchor_with_stored_context,
     [true(ResumeLits == [fakerepo://'cat/pkg-1.0':install?{[self(x)]}])]) :-
  Anchor = (fakerepo://'cat/pkg-1.0':install),
  list_to_assoc([obligation_done(pdepend(Anchor, bwu))-[contributed],
                 obligation_done(pdepend_none(other))-[]], Proof),
  list_to_assoc([contributed-true], Affected),
  list_to_assoc([Anchor-[self(x)]], RModel),
  prover:restart_resume_anchors(Proof, Affected, RModel, ResumeLits).


% An anchor that is itself pruned re-walks its body, which re-fires the
% obligation on its own -- no extra resume target needed.
test(restart_resume_anchors_skips_affected_anchor, [true(ResumeLits == [])]) :-
  Anchor = (fakerepo://'cat/pkg-1.0':install),
  list_to_assoc([obligation_done(pdepend(Anchor, bwu))-[contributed]], Proof),
  list_to_assoc([Anchor-true, contributed-true], Affected),
  empty_assoc(RModel),
  prover:restart_resume_anchors(Proof, Affected, RModel, ResumeLits).


test(resume_target_appends_anchors_to_list_and_single_target) :-
  prover:resume_target([], [t1], T1), T1 == [t1],
  prover:resume_target([a1], [t1, t2], T2), T2 == [t1, t2, a1],
  prover:resume_target([a1], t1, T3), T3 == [t1, a1].

test(begin_pass_clears_per_pass_memos_for_both_kinds,
     [cleanup(use:clear_bwu_cross_dep_memos)]) :-
  forall(member(Kind, [fresh, resume]),
         ( use:clear_bwu_cross_dep_memos,
           assertz(memo:candidate_bwu_('dev-qt', qtbase, use_state([icu], []))),
           use:record_bwu_force_pending('dev-qt', qtbase, [icu]),
           heuristic:begin_pass(Kind),
           \+ memo:candidate_bwu_(_, _, _),
           \+ memo:bwu_force_pending_(_, _, _)
         )).

test(mark_resume_pass_consumed_by_next_begin_pass) :-
  prover:mark_resume_pass,
  nb_current(prover_resume_pass, true),
  prover:begin_pass,
  nb_current(prover_resume_pass, false).

test(restart_prior_proven_witnesses_cycle_free_pruned_literals,
     [cleanup(nb_delete(prover_restart_prior_proven))]) :-
  % clean: plain key, no assumed marker -> witnessed
  % broken: plain key AND assumed key (cycle-break) -> not witnessed
  % gone:  affected but not in the model -> not witnessed
  list_to_assoc([clean-ctx1, broken-ctx2, assumed(broken)-ctx3], Model),
  list_to_assoc([clean-true, broken-true, gone-true], Affected),
  prover:restart_note_prior_proven(Model, Affected),
  prover:restart_prior_proven(clean),
  \+ prover:restart_prior_proven(broken),
  \+ prover:restart_prior_proven(gone),
  \+ prover:restart_prior_proven(unrelated).

test(begin_pass_fresh_drops_prior_proven_witness) :-
  list_to_assoc([lit-ctx], Model),
  list_to_assoc([lit-true], Affected),
  prover:restart_note_prior_proven(Model, Affected),
  prover:restart_prior_proven(lit),
  % resume pass keeps the witness set
  prover:mark_resume_pass,
  prover:begin_pass,
  prover:restart_prior_proven(lit),
  % fresh pass drops it
  prover:begin_pass,
  \+ prover:restart_prior_proven(lit).

:- end_tests(partial_restart).


% -----------------------------------------------------------------------------
%  Phantom grouped-dep assumptions (portage-ng#10, #14, #15)
% -----------------------------------------------------------------------------
:- begin_tests(phantom_grouped_dep_assumption).

test(unsatisfied_constraints_is_phantom) :-
  explanation:phantom_grouped_dep_assumption(unsatisfied_constraints, 'media-libs', clutter).

test(masked_is_phantom) :-
  explanation:phantom_grouped_dep_assumption(masked, 'sys-apps', systemd).

test(acct_group_keyword_filtered_is_phantom) :-
  explanation:phantom_grouped_dep_assumption(keyword_filtered, 'acct-group', buildbot).

test(other_keyword_filtered_not_phantom, [fail]) :-
  explanation:phantom_grouped_dep_assumption(keyword_filtered, 'dev-qt', qtbase).

% A phantom-reason grouped dep must still produce a domain assumption at the
% prover (so the proof completes at tier 1 instead of cascading through all
% five prove_with_fallback relaxation tiers, portage-ng#20 perf fallout). The
% emitted assumption carries the assumption_reason tag so the printer can
% classify it downstream (phantom_grouped_dep_assumption/3). The ordering
% engine does not filter aliasing on these tags: its assumed-dep alias
% preference is existence-gated on a concrete planned action, which handles
% phantoms naturally while preserving ordering edges to planned providers
% (portage-ng#95).
test(build_assumption_emits_phantom_with_reason_tag) :-
  assertz(memo:assumption_reason_cache_(install, 'dev-qt', qtbase, unsatisfied_constraints)),
  ( candidate:grouped_dep_build_assumption(install, 'dev-qt', qtbase, [], [], [], Conditions),
    Conditions = [assumed(grouped_package_dependency('dev-qt', qtbase, _):install?{Ctx})],
    memberchk(assumption_reason(unsatisfied_constraints), Ctx)
  -> retractall(memo:assumption_reason_cache_(install, 'dev-qt', qtbase, _))
  ;  retractall(memo:assumption_reason_cache_(install, 'dev-qt', qtbase, _)),
     fail
  ).

test(build_assumption_emits_requse_violation_with_tag) :-
  assertz(memo:assumption_reason_cache_(install, 'dev-qt', qtbase, unsatisfied_constraints)),
  assertz(memo:requse_violation_('dev-qt', qtbase, use_flag_conflict([],[],[]))),
  ( candidate:grouped_dep_build_assumption(install, 'dev-qt', qtbase, [], [], [], Conditions),
    Conditions = [assumed(grouped_package_dependency('dev-qt', qtbase, _):install?{Ctx})],
    memberchk(required_use_violation(_), Ctx)
  -> retractall(memo:assumption_reason_cache_(install, 'dev-qt', qtbase, _)),
     retractall(memo:requse_violation_('dev-qt', qtbase, _))
  ;  retractall(memo:assumption_reason_cache_(install, 'dev-qt', qtbase, _)),
     retractall(memo:requse_violation_('dev-qt', qtbase, _)),
     fail
  ).

% Visibility-hidden dep concretization (portage-ng#14): reason-to-flags
% mapping only covers reasons that relaxing visibility can fix.
test(hidden_reason_flags_keyword_filtered) :-
  candidate:hidden_reason_flags(keyword_filtered, [keyword_acceptance]).

test(hidden_reason_flags_masked) :-
  candidate:hidden_reason_flags(masked, [unmask]).

test(hidden_reason_flags_rejects_other_reasons, [fail]) :-
  member(R, [unsatisfied_constraints, missing, version_conflict,
             slot_unsatisfied, installed_required]),
  candidate:hidden_reason_flags(R, _).

% record_visibility_override extracts the selected candidate from the
% assembled conditions and asserts a memo:visibility_override_/2 fact.
test(record_visibility_override_asserts_selected,
     [cleanup(retractall(memo:visibility_override_(_, _)))]) :-
  Conditions = [constraint(selected_cn('acct-group', buildbot):{ordset([selected(qtest, 'acct-group/buildbot-0-r3', run, v, [])])})],
  candidate:record_visibility_override('acct-group', buildbot, Conditions),
  memo:visibility_override_(qtest, 'acct-group/buildbot-0-r3').

test(record_visibility_override_noop_without_selection,
     [cleanup(retractall(memo:visibility_override_(_, _)))]) :-
  candidate:record_visibility_override('acct-group', buildbot, []),
  \+ memo:visibility_override_(_, _).

:- end_tests(phantom_grouped_dep_assumption).


% A candidate whose hard version pin excludes the already-selected
% package conflicts; the sibling whose pin agrees does not
% (portage-ng#123, opam-installer vs a locked opam-common).
:- begin_tests(selected_pin_conflict).

py_common('dev-ml/common-2.3.0').
py_new('dev-ml/installer-2.5.2').
py_old('dev-ml/installer-2.3.0').
py_ver(common, version([2,3,0],'',4,0,[],0,'2.3.0')).
py_ver(new, version([2,5,2],'',4,0,[],0,'2.5.2')).

py_setup :-
  py_cleanup,
  py_common(CId), py_ver(common, CV),
  assertz(cache:ordered_entry(qtest, CId, 'dev-ml', common, CV)),
  py_new(NId), py_ver(new, NV),
  assertz(cache:entry_metadata(qtest, NId, depend,
    package_dependency(install, no, 'dev-ml', common, tilde, NV, [], []))),
  py_old(OId),
  assertz(cache:entry_metadata(qtest, OId, depend,
    package_dependency(install, no, 'dev-ml', common, tilde, CV, [], []))),
  cnselect:save_cn_snapshots(Old),
  nb_setval(py_saved_snap, Old),
  cnselect:clear_cn_snapshots,
  cnselect:record_selected_cn_snapshot('dev-ml', common,
    [selected(qtest, CId, install, CV, slot(0))]).

py_cleanup :-
  py_common(CId),
  retractall(cache:ordered_entry(qtest, CId, _, _, _)),
  py_new(NId),
  retractall(cache:entry_metadata(qtest, NId, _, _)),
  retractall(memo:entry_version_pins_(qtest://NId, _)),
  py_old(OId),
  retractall(cache:entry_metadata(qtest, OId, _, _)),
  retractall(memo:entry_version_pins_(qtest://OId, _)),
  ( nb_current(py_saved_snap, Saved) ->
      cnselect:restore_cn_snapshots(Saved)
  ; cnselect:clear_cn_snapshots
  ).

test(newer_sibling_conflicts_with_selected_pin,
     [setup(py_setup), cleanup(py_cleanup)]) :-
  py_new(Id),
  candidate:entry_conflicts_with_selected(qtest://Id).

test(matching_sibling_agrees_with_selected_pin,
     [setup(py_setup), cleanup(py_cleanup), fail]) :-
  py_old(Id),
  candidate:entry_conflicts_with_selected(qtest://Id).

% A pin with an explicit slot judges only selected candidates of that
% slot: `>=common-2.5:2` while common:0 is selected is not a conflict.
test(slotted_pin_ignores_other_slot,
     [setup(( py_setup,
              py_ver(new, NV),
              assertz(cache:entry_metadata(qtest, 'dev-ml/slotted-1', depend,
                package_dependency(install, no, 'dev-ml', common, greaterequal, NV, [slot('2')], []))) )),
      cleanup(( retractall(cache:entry_metadata(qtest, 'dev-ml/slotted-1', _, _)),
                retractall(memo:entry_version_pins_(qtest://'dev-ml/slotted-1', _)),
                py_cleanup )),
      fail]) :-
  candidate:entry_conflicts_with_selected(qtest://'dev-ml/slotted-1').

:- end_tests(selected_pin_conflict).


% A learned upper bound must knock a newer || arm out of config-time
% acceptance even when that arm's own version atoms match a tree
% candidate (portage-ng#123, cabal text-2 vs text < 1.3).

:- begin_tests(learned_choice_arm).

ld_old(qtest://'dev-haskell/text-1.2').
ld_new(qtest://'dev-haskell/text-2.1').
ld_cut(version([1,3],'',4,0,[],0,'1.3')).

ld_setup :-
  ld_cleanup,
  ld_old(R1://Id1),
  assertz(cache:ordered_entry(R1, Id1, 'dev-haskell', text,
                              version([1,2],'',4,0,[],0,'1.2'))),
  ld_new(R2://Id2),
  assertz(cache:ordered_entry(R2, Id2, 'dev-haskell', text,
                              version([2,1],'',4,0,[],0,'2.1'))),
  ( nb_current(prover_learned_constraints, Old) ->
      nb_setval(ld_saved_learned, Old)
  ; nb_setval(ld_saved_learned, none)
  ),
  ld_cut(Cut),
  prover:learn(cn_domain('dev-haskell', text, any),
               version_domain(any, [bound(smaller, Cut)]), _).

ld_cleanup :-
  ld_old(R1://Id1),
  retractall(cache:ordered_entry(R1, Id1, _, _, _)),
  ld_new(R2://Id2),
  retractall(cache:ordered_entry(R2, Id2, _, _, _)),
  ( nb_current(ld_saved_learned, Saved), Saved \== none ->
      nb_setval(prover_learned_constraints, Saved)
  ; nb_delete(prover_learned_constraints)
  ).

test(keeps_in_domain_text, [setup(ld_setup), cleanup(ld_cleanup)]) :-
  ld_old(Old),
  candidate:config_learned_domain_allows('dev-haskell', text, [], Old).

test(drops_text_outside_learned_bound,
     [setup(ld_setup), cleanup(ld_cleanup), fail]) :-
  ld_new(New),
  candidate:config_learned_domain_allows('dev-haskell', text, [], New).

:- end_tests(learned_choice_arm).


% -----------------------------------------------------------------------------
%  Model-unavailable fallback is not the install being resolved
% -----------------------------------------------------------------------------

:- begin_tests(model_unavailable_assumption).

test(assumes_issue_with_model_not_the_install) :-
  Entry = fakerepo://'cat/pkg-1.0',
  candidate:model_unavailable_assumption(Entry, [], Assumed),
  Assumed = assumed(issue_with_model(Entry)?{Ctx}),
  memberchk(issue_with_model(explanation), Ctx),
  Assumed \= assumed(Entry:install?{_}).

:- end_tests(model_unavailable_assumption).


% -----------------------------------------------------------------------------
%  Dependency, slotmeta, featureterm, heuristic, and acceptance helpers
% -----------------------------------------------------------------------------

:- begin_tests(resolving_submodules_unit).

test(dependency_pdepend_goals_and_slot_filtering,
     [setup(( V1 = version([1,0], '', 4, 0, [], 0, '1.0'),
              assertz(cache:ordered_entry(qtest, 'depcat/anchor-1.0', depcat, anchor, V1)),
              assertz(cache:entry_metadata(qtest, 'depcat/anchor-1.0', slot, slot('0'))),
              assertz(cache:entry_metadata(qtest, 'depcat/anchor-1.0', pdepend,
                package_dependency(run, no, depcat, ptarget, none, version_none, [slot('1')], []))),
              assertz(cache:ordered_entry(qtest, 'depcat/plain-1.0', depcat, plain, V1)) )),
      cleanup(( retractall(cache:ordered_entry(qtest, _, depcat, _, _)),
                retractall(cache:entry_metadata(qtest, 'depcat/anchor-1.0', _, _)),
                memo:clear_caches ))]) :-
  Plan = [[rule(qtest://'depcat/anchor-1.0':install?{[]}, []),
           rule(qtest://'depcat/plain-1.0':update?{[]}, [])]],
  dependency:pdepend_goals_from_plan(Plan, Goals),
  Goals \== [],
  dependency:assoc_set_from_list([key(depcat, anchor), key(depcat, anchor)], CNSet),
  dependency:assoc_set_from_list([key(depcat, ptarget, '2')], CNSlotSet),
  dependency:filter_redundant_pdepend_goals(CNSet, CNSlotSet, [], []),
  dependency:filter_redundant_pdepend_goals(CNSet, CNSlotSet, not_a_list, not_a_list),
  G4 = grouped_package_dependency(no, depcat, ptarget,
         [package_dependency(run, no, depcat, ptarget, none, version_none, [slot('1')], [])]):run?{[]},
  G3 = grouped_package_dependency(depcat, ptarget,
         [package_dependency(run, no, depcat, ptarget, none, version_none, [slot('1')], [])]):run?{[]},
  GPlain = grouped_package_dependency(no, depcat, anchor, []):run?{[]},
  dependency:goal_specific_slot(G4, '1'),
  dependency:goal_specific_slot(G3, '1'),
  dependency:pdepend_goal_needed(CNSet, CNSlotSet, G4),
  \+ dependency:pdepend_goal_needed(CNSet, CNSlotSet, GPlain),
  dependency:pdepend_goal_needed(CNSet, CNSlotSet, non_dep_goal).

test(slotmeta_merge_slot_restriction_pairs_and_helpers) :-
  slotmeta:merge_slot_restriction_pair([slot('0')], [slot('0'), equal], [slot('0'), equal]),
  slotmeta:merge_slot_restriction_pair([slot('0'), equal], [slot('0')], [slot('0'), equal]),
  slotmeta:merge_slot_restriction_pair([slot('0')], [slot('0'), subslot('1')], [slot('0'), subslot('1')]),
  slotmeta:merge_slot_restriction_pair([slot('0'), subslot('1')], [slot('0')], [slot('0'), subslot('1')]),
  slotmeta:merge_slot_restriction_pair([slot('0')], [slot('0'), subslot('1'), equal], [slot('0'), subslot('1'), equal]),
  slotmeta:merge_slot_restriction_pair([slot('0'), subslot('1'), equal], [slot('0')], [slot('0'), subslot('1'), equal]),
  slotmeta:merge_slot_restriction_pair([slot('0'), equal], [slot('0'), subslot('1')], [slot('0'), subslot('1'), equal]),
  slotmeta:merge_slot_restriction_pair([slot('0'), subslot('1')], [slot('0'), equal], [slot('0'), subslot('1'), equal]),
  slotmeta:merge_slot_restriction_pair([slot('0'), equal], [slot('0'), subslot('1'), equal], [slot('0'), subslot('1'), equal]),
  slotmeta:merge_slot_restriction_pair([slot('0'), subslot('1'), equal], [slot('0'), equal], [slot('0'), subslot('1'), equal]),
  \+ slotmeta:all_deps_have_explicit_slot([]),
  \+ slotmeta:all_deps_exactish_versioned([]),
  slotmeta:slot_req_explicit_slot_key([slot('2'), equal], '2'),
  slotmeta:slot_req_explicit_slot_key([slot('2'), subslot('0'), equal], '2').

test(featureterm_all_context_helpers) :-
  featureterm:add_after_condition(anchor1, anchor1, [c0], [anchor1, c0]),
  featureterm:get_rebuild_after([rebuild_after(anc), other], anc, [other]),
  featureterm:get_rebuild_after([other], none, [other]),
  featureterm:add_rebuild_after_condition(none, [c0], [c0]),
  featureterm:add_rebuild_after_condition(anc, [c0], [constraint(schedule_after(anc):{[]}), c0]),
  featureterm:set(reinstall, r://e, [after(a1)], [a1, r://e:reinstall?{[]}]),
  featureterm:strip_planning([after(a1), world_atom(w), keep], [keep]),
  featureterm:strip_planning(non_list, non_list),
  featureterm:add_after_to_dep_contexts(none, [d], [d]),
  featureterm:add_after_to_dep_contexts(a1, [t:run?{[after(old)]}, bare], [t:run?{[after(a1)]}, bare]),
  featureterm:add_after_to_dep_contexts(a1, non_list, non_list),
  featureterm:add_after(non_list, a1, [after(a1)]),
  featureterm:add_after_only_to_dep_contexts(a1, [], []),
  featureterm:add_after_only_to_dep_contexts(a1, non_list, non_list),
  featureterm:drop_build_with_use_from_dep_contexts([t:run?{[build_with_use:u, keep]}, bare],
                                                    [t:run?{[keep]}, bare]),
  featureterm:drop_build_with_use_from_dep_contexts(non_list, non_list),
  featureterm:drop_assumption_reason([assumption_reason(r), keep], [keep]),
  featureterm:drop_assumption_reason(non_list, non_list),
  featureterm:drop_build_with_use_and_assumption_reason([build_with_use:u, assumption_reason(r), keep], [keep]),
  featureterm:drop_build_with_use_and_assumption_reason(non_list, non_list).

test(heuristic_remaining_predicates,
     [setup(( V1 = version([1,0], '', 4, 0, [], 0, '1.0'),
              assertz(cache:ordered_entry(qtest, 'hcat/hpkg-1.0', hcat, hpkg, V1)),
              assertz(cache:entry_metadata(qtest, 'hcat/hpkg-1.0', pdepend,
                package_dependency(run, no, hcat, other, none, version_none, [], []))) )),
      cleanup(( retractall(cache:ordered_entry(qtest, 'hcat/hpkg-1.0', _, _, _)),
                retractall(cache:entry_metadata(qtest, 'hcat/hpkg-1.0', _, _)) ))]) :-
  heuristic:merge_action(downgrade),
  heuristic:merge_action(reinstall),
  heuristic:strip_ctx_nested_core_(r://((l?{[a]})?{[b]}), r://l),
  heuristic:strip_ctx_nested_core_(plain_atom, plain_atom),
  heuristic:handle_reprove(unknown_reprove_info, false),
  heuristic:issue_with_model_entry(issue_with_model(r://e), r, e),
  heuristic:issue_with_model_entry(issue_with_model(r://e)?{[ctx]}, r, e),
  heuristic:restart_scope_core(naf(assumed((r://e:install)?{[c]})), r://e:install),
  Sel = [selected(qtest, 'hcat/hpkg-1.0', install, v, [slot('0')]),
         selected(qtest, 'hcat/hpkg-2.0', install, v, [slot('1')])],
  heuristic:filter_selected_by_slot('0', Sel, [selected(qtest, 'hcat/hpkg-1.0', install, v, [slot('0')])]),
  heuristic:ctx_sem_key({}, key([], none)),
  heuristic:ctx_sem_key(non_list, key([], none)),
  heuristic:should_union_ctx(assumed(qtest://'hcat/hpkg-1.0':install)),
  empty_assoc(EmptyModel),
  heuristic:proof_obligation_key(qtest://'hcat/hpkg-1.0':reinstall, EmptyModel, pdepend(_, _)),
  heuristic:proof_obligation_key(qtest://'hcat/other-1.0':downgrade, EmptyModel, pdepend_none(_)),
  heuristic:proof_obligation_applicable(qtest://'hcat/hpkg-1.0':reinstall),
  heuristic:proof_obligation_applicable(qtest://'hcat/hpkg-1.0':downgrade),
  heuristic:profile_run_entry(qtest://'hcat/hpkg-1.0', [build_with_use:[a], required_use:[]],
                              report(qtest://'hcat/hpkg-1.0', [_, _, _])).

test(acceptance_remaining_predicates,
     [setup(( V1 = version([1,0], '', 4, 0, [], 0, '1.0'),
              assertz(cache:ordered_entry(qtest, 'acat/apkg-1.0', acat, apkg, V1)),
              assertz(cache:entry_metadata(qtest, 'acat/apkg-1.0', keywords, unstable(sparc))),
              assertz(cache:entry_metadata(qtest, 'acat/apkg-1.0', slot, slot('0'))),
              assertz(cache:entry_metadata(qtest, 'acat/apkg-1.0', license,
                use_conditional_group(positive, doc, qtest://'acat/apkg-1.0', ['MIT']))),
              assertz(cache:entry_metadata(qtest, 'acat/apkg-1.0', iuse, plus(doc))),
              assertz(cache:ordered_entry(qtest, 'acat/live-9999', acat, live, V1)),
              assertz(userconfig:package_license_entry('acat/apkg', 'MIT')),
              assertz(userconfig:package_keyword('acat/live::qtest', '**')),
              assertz(userconfig:package_keyword('acat/apkg', '~sparc')) )),
      cleanup(( retractall(cache:ordered_entry(qtest, _, acat, _, _)),
                retractall(cache:entry_metadata(qtest, 'acat/apkg-1.0', _, _)),
                retractall(userconfig:package_license_entry('acat/apkg', _)),
                retractall(userconfig:package_keyword('acat/live::qtest', _)),
                retractall(userconfig:package_keyword('acat/apkg', _)),
                memo:clear_caches ))]) :-
  acceptance:effective_license(qtest://'acat/apkg-1.0', 'MIT'),
  acceptance:package_license_accepted(qtest://'acat/apkg-1.0', 'MIT'),
  acceptance:dep_license_ok(grouped_package_dependency(no, acat, apkg, [])),
  \+ acceptance:query_keyword_candidate_any(install, acat, apkg, [self(qtest://'acat/apkg-1.0')], qtest://'acat/apkg-1.0'),
  acceptance:query_keyword_candidate_any(install, acat, apkg, [], qtest://'acat/apkg-1.0'),
  acceptance:query_keyword_candidate_masked(install, acat, apkg, [], qtest://'acat/apkg-1.0'),
  acceptance:accepted_keyword_slot_lock_filter([any_same_slot], slot('0'), [slot('0')]),
  acceptance:keyword_spec_matches('acat/*::qtest', acat, apkg, qtest),
  acceptance:raw_kw_to_term_('**', any(*)),
  acceptance:raw_kw_to_term_('~sparc', unstable(sparc)),
  acceptance:query_keyword_candidate(install, acat, live, any(qtest),
                                     [self(qtest://'acat/other-1.0')], qtest://'acat/live-9999'),
  acceptance:query_keyword_self_ok(install, acat, live, [self(qtest://'acat/apkg-1.0')], qtest://'acat/live-9999'),
  acceptance:repository_priority(qtest, _),
  acceptance:repository_priority(unknown_repo_xyz, 0),
  acceptance:candidate_best_keyword_suggestion([stable(amd64)], [unstable(amd64)], unstable(amd64)),
  acceptance:candidate_best_keyword_suggestion([stable(amd64)], [unstable(arm64)], '**'),
  acceptance:candidate_best_keyword_suggestion([stable(amd64)], [], '**'),
  acceptance:entry_has_keyword(qtest://'acat/apkg-1.0'),
  acceptance:entry_has_accepted_keyword(qtest://'acat/live-9999'),
  acceptance:entry_has_accepted_keyword(qtest://'acat/apkg-1.0'),
  retractall(userconfig:package_keyword('acat/apkg', _)),
  retractall(userconfig:package_keyword('acat/live::qtest', _)),
  acceptance:candidate_non_accepted_keyword(qtest://'acat/apkg-1.0', _),
  acceptance:entry_is_keyword_filtered(qtest://'acat/apkg-1.0'),
  acceptance:entry_needs_keyword_acceptance(qtest://'acat/apkg-1.0'),
  acceptance:entry_needs_keyword_acceptance(qtest://'acat/live-9999').

test(cnselect_remaining_predicates,
     [setup(( V1 = version([1,0], '', 4, 0, [], 0, '1.0'),
              V2 = version([2,0], '', 4, 0, [], 0, '2.0'),
              knowledgebase:vdb_repository(Vdb),
              assertz(cache:ordered_entry(Vdb, 'cncat/cnpkg-1.0', cncat, cnpkg, V1)),
              assertz(cache:ordered_entry(qtest, 'cncat/cnpkg-1.0', cncat, cnpkg, V1)),
              assertz(cache:entry_metadata(qtest, 'cncat/cnpkg-1.0', slot, slot('0'))),
              assertz(cache:ordered_entry(qtest, 'cncat/cnpkg-2.0', cncat, cnpkg, V2)),
              assertz(cache:entry_metadata(qtest, 'cncat/cnpkg-2.0', slot, slot('0'))),
              assertz(cache:ordered_entry(qtest, 'cncat/orig-1.0', cncat, orig, V1)),
              assertz(cache:entry_metadata(qtest, 'cncat/orig-1.0', version, V1)),
              assertz(cache:ordered_entry(qtest, 'cncat/src-1.0', cncat, src, V1)),
              heuristic:init_state )),
      cleanup(( heuristic:cleanup_state,
                knowledgebase:vdb_repository(Vdb),
                retractall(cache:ordered_entry(Vdb, 'cncat/cnpkg-1.0', _, _, _)),
                retractall(cache:ordered_entry(qtest, _, cncat, _, _)),
                retractall(cache:entry_metadata(qtest, 'cncat/cnpkg-1.0', _, _)),
                retractall(cache:entry_metadata(qtest, 'cncat/cnpkg-2.0', _, _)),
                retractall(cache:entry_metadata(qtest, 'cncat/orig-1.0', _, _)),
                retractall(memo:slot_conflict_(cncat, cnpkg, _)) ))]) :-
  V1 = version([1,0], '', 4, 0, [], 0, '1.0'),
  V2 = version([2,0], '', 4, 0, [], 0, '2.0'),
  knowledgebase:vdb_repository(Vdb),
  cnselect:installed_entry_cn(cncat, cnpkg, Vdb, 'cncat/cnpkg-1.0'),
  cnselect:installed_entry_satisfies_package_deps(install, cncat, cnpkg, [], Vdb://'cncat/cnpkg-1.0'),
  DepEq1 = package_dependency(install, no, cncat, cnpkg, equal, V1, [slot('0')], []),
  DepSm1 = package_dependency(install, no, cncat, cnpkg, smaller, V2, [slot('0')], []),
  cnselect:installed_entry_satisfies_package_deps(install, cncat, cnpkg, [DepEq1], Vdb://'cncat/cnpkg-1.0'),
  Sel1 = selected(qtest, 'cncat/cnpkg-1.0', install, V1, [slot('0'), subslot('1')]),
  Sel2 = selected(qtest, 'cncat/cnpkg-2.0', install, V2, [slot('0'), subslot('2')]),
  CtxSel = [constraint(selected_cn(cncat, cnpkg):{ordset([Sel1, Sel2])})],
  cnselect:selected_cn_rejected_candidates(install, cncat, cnpkg, [slot('0')], [DepEq1], CtxSel,
                                           [qtest://'cncat/cnpkg-2.0']),
  cnselect:context_cn_domain_reason(cncat, cnpkg,
    [constraint(cn_domain_reason(cncat, cnpkg):{ordset([r1])})], [r1]),
  cnselect:context_cn_domain_reason(cncat, cnpkg,
    [domain_reason(cn_domain(cncat, cnpkg, [r2]))], [r2]),
  cnselect:context_cn_domain_reason(cncat, cnpkg, [], []),
  Dom1 = version_domain(any, [bound(equal, V1)]),
  list_to_assoc([cn_domain(cncat, cnpkg, '0')-Dom1,
                 cn_domain(cncat, cnpkg, any)-Dom1], Cons1),
  cnselect:selected_cn_check_slot_domains(cncat, cnpkg, [Sel1], Cons1),
  cnselect:cn_reject_scope_canon(any, any),
  cnselect:cn_reject_scope_canon(weird_scope, any),
  cnselect:record_blocked_cn_source_snapshot(cncat, cnpkg, []),
  cnselect:record_blocked_cn_source_snapshot(cncat, orig,
    [source(qtest, 'cncat/src-1.0', install, none, version_none, [])]),
  cnselect:snapshot_blocked_cn_sources(cncat, orig, [_]),
  cnselect:record_selected_cn_snapshot(cncat, src,
    [selected(qtest, 'cncat/src-1.0', install, V1, [slot('0')])]),
  Reasons = [introduced_by(qtest://'cncat/orig-1.0', install, version(equal, V1))],
  cnselect:reason_linked_selected_reprove_target(Reasons, cncat, src, [qtest://'cncat/src-1.0']),
  cnselect:add_cn_domain_origin_rejects(Reasons, true),
  cnselect:add_cn_domain_origin_rejects(not_a_list, false),
  cnselect:find_adjustable_origin(Reasons, cncat, orig, qtest://'cncat/orig-1.0'),
  cnselect:maybe_request_cn_domain_reprove(cncat, cnpkg, none, [], []),
  catch(cnselect:maybe_request_cn_domain_reprove(cncat, cnpkg, none, [Sel1]),
        prover_reprove(_), true),
  cnselect:record_slot_conflict_if_multiple(cncat, cnpkg, [Sel1, Sel2]),
  cnselect:selected_cn_partition_by_domain(Dom1, [Sel1, Sel2], [Sel1], [Sel2]),
  catch(cnselect:selected_cn_unique_or_reprove(cncat, cnpkg, [Sel1, Sel2], Cons1),
        prover_reprove(_), true),
  InconsDom = version_domain(any, [bound(equal, V1), bound(equal, V2)]),
  list_to_assoc([cn_domain(cncat, cnpkg, any)-InconsDom,
                 cn_domain_reason(cncat, cnpkg)-ordset(Reasons)], ConsIncons),
  \+ cnselect:selected_cn_unique_or_reprove(cncat, cnpkg, [Sel1, Sel2], ConsIncons),
  empty_assoc(EmptyCons),
  nb_setval(prover_reprove_enabled, false),
  \+ cnselect:selected_cn_unique_or_reprove(cncat, cnpkg, [Sel1, Sel2], EmptyCons),
  nb_setval(prover_reprove_enabled, true),
  cnselect:selected_cn_not_blocked_or_reprove(cncat, cnpkg, [], [Sel1], EmptyCons),
  SpecBlk = blocked(strong, install, none, version_none, []),
  list_to_assoc([blocked_cn_source(cncat, cnpkg)-ordset([source(qtest, 'cncat/src-1.0', install, none, version_none, [])])], ConsBlk),
  catch(cnselect:selected_cn_not_blocked_or_reprove(cncat, cnpkg, [SpecBlk], [Sel1], ConsBlk),
        prover_reprove(_), true),
  nb_setval(prover_reprove_enabled, false),
  \+ cnselect:selected_cn_not_blocked_or_reprove(cncat, cnpkg, [SpecBlk], [Sel1], EmptyCons),
  nb_setval(prover_reprove_enabled, true),
  cnselect:selected_cn_unique_per_slot_or_subslot([Sel1, Sel2]),
  cnselect:dep_has_upper_version_bound(cncat, cnpkg, [DepSm1]),
  cnselect:dep_has_explicit_slot_constraint(cncat, cnpkg, [DepEq1]),
  WDep = package_dependency(install, no, cncat, cnpkg, wildcard, '1.0*', [slot('0')], []),
  MergedDeps = [grouped_package_dependency(no, cncat, cnpkg, [WDep]):install?{[]}],
  cnselect:wildcard_cn_domain_constraints(MergedDeps, WCons),
  WCons \== [].

test(target_and_resolving_rules_coverage,
     [setup(( unittest:accept_stable_amd64,
              V1 = version([1,0], '', 4, 0, [], 0, '1.0'),
              V2 = version([2,0], '', 4, 0, [], 0, '2.0'),
              knowledgebase:vdb_repository(Vdb),
              assertz(cache:ordered_entry(Vdb, 'tcat/tpkg-1.0', tcat, tpkg, V1)),
              assertz(cache:entry_metadata(Vdb, 'tcat/tpkg-1.0', slot, slot('0'))),
              assertz(cache:entry_metadata(Vdb, 'tcat/tpkg-1.0', iuse, flag_a)),
              assertz(cache:ordered_entry(qtest, 'tcat/tpkg-1.0', tcat, tpkg, V1)),
              assertz(cache:entry_metadata(qtest, 'tcat/tpkg-1.0', slot, slot('0'))),
              assertz(cache:entry_metadata(qtest, 'tcat/tpkg-1.0', keywords, stable(amd64))),
              assertz(cache:entry_metadata(qtest, 'tcat/tpkg-1.0', iuse, flag_a)),
              assertz(cache:entry_metadata(qtest, 'tcat/tpkg-1.0', iuse, neg_flag)),
              assertz(cache:ordered_entry(qtest, 'tcat/tpkg-2.0', tcat, tpkg, V2)),
              assertz(cache:entry_metadata(qtest, 'tcat/tpkg-2.0', slot, slot('0'))),
              assertz(cache:entry_metadata(qtest, 'tcat/tpkg-2.0', keywords, stable(amd64))),
              assertz(cache:ordered_entry(qtest, 'tcat/tpkg-3.0', tcat, tpkg, V2)),
              assertz(cache:entry_metadata(qtest, 'tcat/tpkg-3.0', slot, slot('1'))),
              assertz(cache:entry_metadata(qtest, 'tcat/tpkg-3.0', keywords, stable(amd64))),
              assertz(cache:ordered_entry(qtest, 'virtual/tvirt-1.0', virtual, tvirt, V1)),
              assertz(cache:entry_metadata(qtest, 'virtual/tvirt-1.0', slot, slot('0'))),
              assertz(cache:entry_metadata(qtest, 'virtual/tvirt-1.0', keywords, stable(amd64))),
              assertz(config:excluded_atom('tcat/tpkg')) )),
      cleanup(( unittest:restore_stable_amd64,
                knowledgebase:vdb_repository(Vdb),
                retractall(cache:ordered_entry(Vdb, 'tcat/tpkg-1.0', _, _, _)),
                retractall(cache:entry_metadata(Vdb, 'tcat/tpkg-1.0', _, _)),
                retractall(cache:ordered_entry(qtest, _, tcat, _, _)),
                retractall(cache:entry_metadata(qtest, 'tcat/tpkg-1.0', _, _)),
                retractall(cache:entry_metadata(qtest, 'tcat/tpkg-2.0', _, _)),
                retractall(cache:entry_metadata(qtest, 'tcat/tpkg-3.0', _, _)),
                retractall(cache:ordered_entry(qtest, 'virtual/tvirt-1.0', _, _, _)),
                retractall(cache:entry_metadata(qtest, 'virtual/tvirt-1.0', _, _)),
                retractall(config:excluded_atom('tcat/tpkg')),
                retractall(preference:local_flag(_)),
                retractall(preference:local_use(_)),
                memo:clear_caches ))]) :-
  V1 = version([1,0], '', 4, 0, [], 0, '1.0'),
  knowledgebase:vdb_repository(Vdb),
  Q = qualified_target(none, qtest, tcat, tpkg, version_none, [[], []]),
  QInst = qualified_target(none, Vdb, tcat, tpkg, version_none, [[], []]),
  once(target:resolve_candidate(Q, qtest://_)),
  once(target:resolve_installed_candidate(QInst, Vdb://'tcat/tpkg-1.0')),
  target:depclean_rewrite_deps([a:run?{[c]}, b:run, c], [],
                               [a:depclean?{[c]}, b:depclean?{[]}, c:depclean?{[]}]),
  target:is_excluded(qtest://'tcat/tpkg-1.0'),
  target:is_excluded_cn(tcat, tpkg),
  target:cn_installed(qtest://'tcat/tpkg-1.0'),
  ( catch(target:query_installed(Q), _, fail) -> true ; true ),
  assertz(preference:local_flag(withtestdeps)),
  target:target_context([], [with_test_deps]),
  retractall(preference:local_flag(withtestdeps)),
  assertz(preference:local_flag(rebuildnewrev)),
  target:rebuild_if_newer_available(Vdb://'tcat/tpkg-1.0'),
  retractall(preference:local_flag(rebuildnewrev)),
  assertz(preference:local_flag(nobdeps)),
  BDep = grouped_package_dependency(no, tcat, tpkg,
           [package_dependency(bdepend, no, tcat, tpkg, none, version_none, [], [])]):install?{[]},
  target:bdepend_only_dep(BDep),
  retractall(preference:local_flag(nobdeps)),
  RDep = grouped_package_dependency(no, tcat, tpkg,
           [package_dependency(run, no, tcat, tpkg, none, version_none, [], [])]):run?{[]},
  RDep3 = grouped_package_dependency(tcat, tpkg, []):run?{[]},
  target:dep_cn(RDep, tcat, tpkg),
  target:dep_cn(RDep3, tcat, tpkg),
  target:dep_cn(qtest://'tcat/tpkg-1.0':run?{[]}, tcat, tpkg),
  target:dep_cn(qtest://'tcat/tpkg-1.0':run, tcat, tpkg),
  target:deep_update_goals(qtest://'other/self-1.0', [RDep], _DeepUpds),
  % Update / downgrade / upgrade / depclean / fetchonly / download candidate:resolve
  candidate:update_requires_use_rebuild(qtest://'tcat/tpkg-1.0',
    [suggestion(use_change, qtest://'tcat/tpkg-1.0', [use_change(flag_a, enable)])]),
  candidate:update_requires_use_rebuild(qtest://'tcat/tpkg-1.0',
    [rebuild_reason(build_with_use)]),
  candidate:update_requires_use_rebuild(qtest://'tcat/tpkg-1.0',
    [build_with_use:use_state([flag_a], [])]),
  candidate:update_vdb_entry_for_ebuild(qtest://'tcat/tpkg-1.0', Vdb://'tcat/tpkg-1.0'),
  once(candidate:resolve(Vdb://'tcat/tpkg-1.0':update?{[]}, [qtest://'tcat/tpkg-2.0':update?{_}])),
  once(candidate:resolve(qtest://'tcat/tpkg-2.0':update?{[]}, _)),
  once(candidate:resolve(qtest://'tcat/tpkg-1.0':update?{[build_with_use:use_state([flag_a], [])]}, _)),
  assertz(cache:ordered_entry(Vdb, 'tcat/tpkg-3.0', tcat, tpkg, V2)),
  once(candidate:resolve(qtest://'tcat/tpkg-3.0':update?{[]}, [])),
  retractall(cache:ordered_entry(Vdb, 'tcat/tpkg-3.0', _, _, _)),
  once(candidate:resolve(qtest://'tcat/tpkg-1.0':downgrade?{[replaces(Vdb://'tcat/tpkg-1.0')]}, _)),
  once(candidate:resolve(qtest://'tcat/tpkg-1.0':downgrade?{[]}, [])),
  once(candidate:resolve(qtest://'tcat/tpkg-2.0':downgrade?{[]}, [qtest://'tcat/tpkg-2.0':install?{[]}])),
  once(candidate:resolve(qtest://'tcat/tpkg-3.0':upgrade?{[]}, _)),
  once(candidate:resolve(qtest://'tcat/tpkg-1.0':upgrade?{[]}, [])),
  once(candidate:resolve(qtest://'tcat/tpkg-3.0':upgrade?{[replaces(Vdb://'tcat/tpkg-1.0')]}, _)),
  DlAct = download,
  once(candidate:resolve(qtest://'tcat/tpkg-1.0':DlAct?{[]}, [])),
  once(candidate:resolve(qtest://'tcat/tpkg-2.0':fetchonly?{[]}, _)),
  once(candidate:resolve(qtest://'virtual/tvirt-1.0':fetchonly?{[]}, _)),
  once(candidate:resolve(grouped_dep(tcat, tpkg,
    [package_dependency(run, no, tcat, tpkg, equal, V1, [slot('0')], [])]):depclean?{[]}, _)),
  once(candidate:resolve(qtest://'tcat/tpkg-1.0':depclean?{[]}, _)),
  % resolving:rule/2 target, world, ebuild, choice, and USE primitives
  once(resolving:rule(target(Q, 'tcat/tpkg'):fetchonly?{[]}, _)),
  once(resolving:rule(target(QInst, 'tcat/tpkg'):uninstall?{[]}, _)),
  once(resolving:rule(target(Q, 'tcat/tpkg'):run?{[]}, [])),
  retractall(config:excluded_atom('tcat/tpkg')),
  once(resolving:rule(target(Q, 'tcat/tpkg'):run?{[]}, _)),
  once(resolving:rule(world('tcat/tpkg'):register?{[]}, [])),
  once(resolving:rule(qtest://'tcat/tpkg-2.0':fetchonly?{[]}, _)),
  once(resolving:rule(qtest://'virtual/tvirt-1.0':annotate?{[]}, [])),
  once(resolving:rule(qtest://'tcat/tpkg-1.0':reinstall?{[]}, [])),
  once(resolving:rule(qtest://'tcat/tpkg-1.0':uninstall?{[]}, [])),
  once(resolving:rule(qtest://'tcat/tpkg-1.0':update?{[]}, _)),
  once(resolving:rule(qtest://'tcat/tpkg-1.0':downgrade?{[]}, _)),
  once(resolving:rule(qtest://'tcat/tpkg-1.0':upgrade?{[]}, _)),
  once(resolving:rule(qtest://'tcat/tpkg-1.0':depclean?{[]}, _)),
  once(resolving:rule(grouped_package_dependency(no, tcat, tpkg, []):depclean?{[]}, _)),
  once(resolving:rule(grouped_package_dependency(weak, tcat, tpkg, []):depclean?{[]}, [])),
  assertz(preference:local_use(flag_a)),
  memo:clear_caches,
  once(resolving:rule(use_conditional_group(negative, flag_a, qtest://'tcat/tpkg-1.0', []):run?{[]}, [])),
  once(resolving:rule(use_conditional_group(positive, flag_a, qtest://'tcat/tpkg-1.0', [d1]), [d1])),
  once(resolving:rule(use_conditional_group(positive, unkn_flag, qtest://'tcat/tpkg-1.0', [d1]), [])),
  once(resolving:rule(use_conditional_group(negative, flag_a, qtest://'tcat/tpkg-1.0', [d1]), [])),
  assertz(preference:local_use(minus(neg_flag))),
  memo:clear_caches,
  once(resolving:rule(use_conditional_group(negative, neg_flag, qtest://'tcat/tpkg-1.0', [d1]), [d1])),
  % choice groups & at_most_one_of
  CtxSelf = [self(qtest://'tcat/tpkg-1.0')],
  once(resolving:rule(at_most_one_of_group([required(flag_a)]):validate?{CtxSelf}, [])),
  once(resolving:rule(at_most_one_of_group([required(flag_a), required(flag_a)]):validate?{CtxSelf},
                      [assumed(conflict(required_use, _))])),
  once(resolving:rule(at_most_one_of_group([RDep]):run?{[]}, _)),
  once(resolving:rule(at_most_one_of_group([]):run?{[]}, [])),
  once(resolving:rule(all_of_group([d1, d2]), [d1, d2])),
  once(resolving:rule(uri(a, b, c):fetchonly, [])),
  once(resolving:rule(uri(a):fetchonly, [])),
  % required / blocking / naf / conflict / atom
  once(resolving:rule(required(flag_a):validate?{CtxSelf}, [])),
  once(resolving:rule(required(minus(neg_flag)):validate?{CtxSelf}, [])),
  once(resolving:rule(required(unkn_flag):validate?{[]}, [assumed(unkn_flag)])),
  once(resolving:rule(required(minus(unkn_flag)):validate?{[]}, [assumed(minus(unkn_flag))])),
  once(resolving:rule(required(flag_a), [flag_a])),
  once(resolving:rule(required(minus(neg_flag)), [minus(neg_flag)])),
  once(resolving:rule(required(neg_flag), [assumed(conflict(required, neg_flag))])),
  once(resolving:rule(required(minus(flag_a)), [assumed(conflict(required, minus(flag_a)))])),
  once(resolving:rule(blocking(minus(flag_a)):validate?{CtxSelf}, [])),
  once(resolving:rule(blocking(minus(unkn_flag)):validate?{[]},
                      [assumed(unkn_flag), naf(blocking(unkn_flag))])),
  once(resolving:rule(blocking(minus(flag_a)), [flag_a])),
  once(resolving:rule(blocking(minus(neg_flag)), [assumed(conflict(blocking, minus(neg_flag)))])),
  once(resolving:rule(naf(blocking(neg_flag)), [conflict(neg_flag, naf(blocking(neg_flag)))])),
  candidate:with_assume_conflicts(
    resolving:rule(conflict(a, b), [assumed(conflict(a, b))])),
  \+ resolving:rule(conflict(a, b), _),
  once(resolving:rule(naf(other_stmt), [])),
  once(resolving:rule(plain_atom_literal, [])).

test(candidate_remaining_coverage,
     [nondet,
      setup(( unittest:accept_stable_amd64,
              V1 = version([1,0], '', 4, 0, [], 0, '1.0'),
              V2 = version([2,0], '', 4, 0, [], 0, '2.0'),
              knowledgebase:vdb_repository(Vdb),
              assertz(cache:ordered_entry(Vdb, 'ccat/cpkg-1.0', ccat, cpkg, V1)),
              assertz(cache:entry_metadata(Vdb, 'ccat/cpkg-1.0', slot, slot('0'))),
              assertz(cache:entry_metadata(Vdb, 'ccat/cpkg-1.0', iuse, flag_x)),
              assertz(cache:ordered_entry(qtest, 'ccat/cpkg-1.0', ccat, cpkg, V1)),
              assertz(cache:entry_metadata(qtest, 'ccat/cpkg-1.0', slot, slot('0'))),
              assertz(cache:entry_metadata(qtest, 'ccat/cpkg-1.0', keywords, stable(amd64))),
              assertz(cache:entry_metadata(qtest, 'ccat/cpkg-1.0', iuse, plus(flag_x))),
              assertz(cache:ordered_entry(qtest, 'ccat/cpkg-2.0', ccat, cpkg, V2)),
              assertz(cache:entry_metadata(qtest, 'ccat/cpkg-2.0', slot, slot('0'))),
              assertz(cache:entry_metadata(qtest, 'ccat/cpkg-2.0', keywords, stable(amd64))),
              assertz(cache:ordered_entry(qtest, 'ccat/kwpkg-1.0', ccat, kwpkg, V1)),
              assertz(cache:entry_metadata(qtest, 'ccat/kwpkg-1.0', keywords, unstable(sparc))) )),
      cleanup(( unittest:restore_stable_amd64,
                knowledgebase:vdb_repository(Vdb),
                retractall(cache:ordered_entry(Vdb, 'ccat/cpkg-1.0', _, _, _)),
                retractall(cache:entry_metadata(Vdb, 'ccat/cpkg-1.0', _, _)),
                retractall(cache:ordered_entry(qtest, _, ccat, _, _)),
                retractall(cache:entry_metadata(qtest, 'ccat/cpkg-1.0', _, _)),
                retractall(cache:entry_metadata(qtest, 'ccat/cpkg-2.0', _, _)),
                retractall(cache:entry_metadata(qtest, 'ccat/kwpkg-1.0', _, _)),
                retractall(preference:local_flag(_)),
                memo:clear_caches ))]) :-
  V1 = version([1,0], '', 4, 0, [], 0, '1.0'),
  V2 = version([2,0], '', 4, 0, [], 0, '2.0'),
  knowledgebase:vdb_repository(Vdb),
  % action_phase, blocker_version_matches, blocker_slot_matches, make_blocker_constraint
  candidate:action_phase(run, run),
  candidate:action_phase(reinstall, install),
  candidate:action_phase(update, install),
  candidate:action_phase(download, install),
  candidate:action_phase(other_act, run),
  candidate:blocker_version_matches(tilde, V1, V1, qtest, 'ccat/cpkg-1.0'),
  candidate:blocker_slot_matches([slot('0')], [slot('0')], qtest, 'ccat/cpkg-1.0'),
  candidate:blocker_slot_matches([slot('0'), equal], [slot('0')], qtest, 'ccat/cpkg-1.0'),
  candidate:blocker_slot_matches([slot('0'), subslot('1'), equal], [slot('0'), subslot('1')], qtest, 'ccat/cpkg-1.0'),
  candidate:blocker_slot_matches([any_same_slot], [slot('0')], qtest, 'ccat/cpkg-1.0'),
  PD1 = package_dependency(install, no, ccat, cpkg, equal, V1, [slot('0')], []),
  candidate:make_blocker_constraint(ccat, cpkg, [PD1], [], []),
  % reverse_dep_slot_matches_parent, dep_contains_pkg_dep_on, self_rdepend_extra_slot_compatible
  candidate:reverse_dep_slot_matches_parent([], qtest://'ccat/cpkg-1.0'),
  candidate:reverse_dep_slot_matches_parent([slot('0')], qtest://'ccat/cpkg-1.0'),
  candidate:reverse_dep_slot_matches_parent([any_same_slot], qtest://'ccat/cpkg-1.0'),
  \+ candidate:reverse_dep_slot_matches_parent([any_different_slot], qtest://'ccat/cpkg-1.0'),
  candidate:reverse_dep_slot_matches_parent([other_slot_spec], qtest://'ccat/cpkg-1.0'),
  candidate:dep_contains_pkg_dep_on(all_of_group([PD1]), ccat, cpkg, equal, V1, [slot('0')]),
  candidate:self_rdepend_extra_slot_compatible([], PD1),
  candidate:self_rdepend_extra_slot_compatible([slot('0')], PD1),
  candidate:self_rdepend_extra_slot_compatible([any_same_slot], PD1),
  % rdepend_collect_vbounds, rdepend_self_use_conditional_active
  candidate:rdepend_collect_vbounds(all_of_group([PD1]), qtest://'ccat/cpkg-1.0', [_]),
  candidate:rdepend_collect_vbounds(other_term, qtest://'ccat/cpkg-1.0', []),
  candidate:rdepend_collect_vbounds_choice_intersection([], qtest://'ccat/cpkg-1.0', []),
  candidate:rdepend_self_use_conditional_active(negative, non_iuse_flag_xyz, qtest://'ccat/cpkg-1.0'),
  % eligible & installed (called through Goal variable to bypass compile-time goal_expansion)
  GEligDl = candidate:eligible(qtest://'ccat/cpkg-1.0':download?{[]}), call(GEligDl),
  GEligAn = candidate:eligible(qtest://'ccat/cpkg-1.0':annotate?{[]}), call(GEligAn),
  GEligIn = candidate:eligible(qtest://'ccat/cpkg-1.0':install?{[]}), call(GEligIn),
  candidate:eligible(use_conditional(positive, test, qtest://'ccat/cpkg-1.0'):install?{[with_test_deps]}),
  GInst = candidate:installed(qtest://'ccat/cpkg-1.0'), call(GInst),
  candidate:with_assume_blockers(candidate:assume_blockers),
  % any_of_config_* and group_choice_dep
  candidate:any_of_reject_assumed_choice(
    grouped_package_dependency(no, ccat, cpkg, [PD1]),
    [assumed(grouped_package_dependency(ccat, cpkg, [PD1]):install?{[]})]),
  candidate:any_of_config_dep_ok([], all_of_group([PD1])),
  candidate:any_of_config_dep_ok([], any_of_group([PD1])),
  candidate:any_of_config_dep_ok([], use_conditional_group(positive, flag_x, qtest://'ccat/cpkg-1.0', [PD1])),
  candidate:any_of_config_dep_ok([], other_config_term),
  PDMissing = package_dependency(install, no, ccat, missing_pkg, none, version_none, [], []),
  \+ candidate:any_of_config_dep_ok([], PDMissing),
  candidate:with_assume_conflicts(candidate:any_of_config_dep_ok([], PDMissing)),
  prover:learn(cn_domain(ccat, cpkg, any), version_domain(any, [bound(smaller, V1)]), _),
  \+ candidate:any_of_config_dep_ok([], PD1),
  nb_delete(prover_learned_constraints),
  candidate:any_of_config_conditions_all_ok([], [PD1:config?{[]}, other_config_term]),
  candidate:group_choice_dep(PD1, grouped_package_dependency(no, ccat, cpkg, [PD1])),
  % choicelog_version_wrap & choicelog_version_data, verify_candidate, pin_from_dep_term, required_use_term_has_choice
  GD = gd(install, ccat, cpkg, [], [], []),
  GWrap1 = candidate:choicelog_version_wrap(true, GD, qtest://'ccat/cpkg-1.0', true), call(GWrap1),
  GWrap2 = candidate:choicelog_version_wrap(false, GD, qtest://'ccat/cpkg-1.0', true), call(GWrap2),
  candidate:choicelog_version_data(GD, qtest://'ccat/cpkg-1.0', _),
  candidate:grouped_dep_verify_candidate(true, GD, qtest://'ccat/cpkg-1.0'),
  candidate:pin_from_dep_term(all_of_group([PD1]), pin(ccat, cpkg, equal, V1, [slot('0')])),
  candidate:required_use_term_has_choice(any_of_group([required(a)])),
  candidate:required_use_term_has_choice(at_most_one_of_group([required(a)])),
  % grouped_dep_update_reason (all 8 clauses)
  candidate:grouped_dep_update_reason(ccat, cpkg, qtest://'ccat/cpkg-2.0', Vdb://'ccat/cpkg-1.0', [], update, _),
  candidate:grouped_dep_update_reason(ccat, cpkg, qtest://'ccat/cpkg-1.0', Vdb://'ccat/cpkg-1.0',
                                      [build_with_use:use_state([flag_x], [])], update, _),
  assertz(preference:local_flag(newuse)),
  candidate:grouped_dep_update_reason(ccat, cpkg, qtest://'ccat/cpkg-1.0', Vdb://'ccat/cpkg-1.0', [], update, _),
  retractall(preference:local_flag(newuse)),
  assertz(preference:local_flag(changeduse)),
  candidate:grouped_dep_update_reason(ccat, cpkg, qtest://'ccat/cpkg-1.0', Vdb://'ccat/cpkg-1.0', [], update, _),
  retractall(preference:local_flag(changeduse)),
  assertz(preference:local_flag(rebuildnewrev)),
  candidate:grouped_dep_update_reason(ccat, cpkg, qtest://'ccat/cpkg-2.0', Vdb://'ccat/cpkg-1.0', [], update, _),
  retractall(preference:local_flag(rebuildnewrev)),
  assertz(preference:local_flag(changeddeps)),
  \+ candidate:grouped_dep_update_reason(ccat, cpkg, qtest://'ccat/cpkg-1.0', Vdb://'ccat/cpkg-1.0', [], update, _),
  retractall(preference:local_flag(changeddeps)),
  assertz(preference:local_flag(changedslot)),
  \+ candidate:grouped_dep_update_reason(ccat, cpkg, qtest://'ccat/cpkg-1.0', Vdb://'ccat/cpkg-1.0', [], update, _),
  retractall(preference:local_flag(changedslot)),
  assertz(preference:local_flag(rebuiltbinaries)),
  \+ candidate:grouped_dep_update_reason(ccat, cpkg, qtest://'ccat/cpkg-1.0', Vdb://'ccat/cpkg-1.0', [], update, _),
  retractall(preference:local_flag(rebuiltbinaries)),
  % with_assuming_flags & grouped_dep_tag_assumption_suggestion
  candidate:with_assuming_flags([unmask], prover:assuming(unmask)),
  candidate:grouped_dep_tag_assumption_suggestion(ccat, kwpkg, [], keyword_filtered, [], CtxKw),
  memberchk(suggestion(accept_keyword, _), CtxKw),
  candidate:grouped_dep_tag_assumption_suggestion(ccat, kwpkg, [], masked, [], CtxMask),
  memberchk(suggestion(unmask), CtxMask).

:- end_tests(resolving_submodules_unit).


% -----------------------------------------------------------------------------
%  Tilde pin learning (portage-ng#128)
% -----------------------------------------------------------------------------

:- begin_tests(tilde_pin_domain).

test(learn_holding_tilde_and_narrow_chooser,
     [setup(tilde_pin_setup),
      cleanup(tilde_pin_cleanup)]) :-
  V812 = version([8,1,2], '', 4, 0, [], 0, '8.1.2'),
  V813 = version([8,1,3,1], '', 4, 0, [], 0, '8.1.3.1'),
  Sel812 = selected(qtest, 'td/ap-8.1.2', run, V812, [slot('8.1')]),
  Sel813 = selected(qtest, 'td/ap-8.1.3.1', run, V813, [slot('8.1')]),
  At = qtest://'td/at-8.1.2',
  Rl = qtest://'td/rl-8.1.3.1',
  Reasons = [introduced_by(At, run, version(tilde, V812)),
             introduced_by(Rl, run, version(tilde, V813))],
  % actiontext itself was selected under a version pin; railties was not.
  AtReasons = [introduced_by(qtest://'td/root-1.0', run, version(tilde, V812))],
  list_to_assoc([selected_cn(td, ap)-ordset([Sel812, Sel813]),
                 selected_cn_allow_multislot(td, ap)-true,
                 cn_domain_reason(td, ap)-ordset(Reasons),
                 cn_domain_reason(td, at)-ordset(AtReasons)], Cons),
  Dep813 = package_dependency(run, no, td, ap, tilde, V813, [], []),
  % 8.1.3.1 is a real candidate until the holding tilde is learned.
  cnselect:child_reselection_possible(td, ap, [Dep813], []),
  % Reported order: 8.1.2 is already committed, 8.1.3.1 arrives.
  \+ cnselect:selected_cn_unique_or_reprove(td, ap, [Sel813], [Sel812, Sel813], Cons),
  Dom = version_domain(any, [bound(tilde, V812)]),
  prover:learned(cn_domain(td, ap, '8.1'), Dom),
  \+ prover:learned(cn_domain(td, ap, any), _),
  \+ cnselect:child_reselection_possible(td, ap, [Dep813], []),
  Ctx = [self(Rl)],
  catch(cnselect:maybe_learn_parent_narrowing(td, ap, [Dep813], Ctx),
        prover_reprove(cn_domain(td, rl, none, [Rl], [parent_narrowing])),
        true),
  % A root chooser is the request. Rejecting it does not move the plan.
  nb_setval(prover_root_goals, [qtest://'td/rl-8.1.3.1':run]),
  \+ cnselect:maybe_learn_parent_narrowing(td, ap, [Dep813], Ctx).

test(order_flip_prefers_root_tilde,
     [setup(tilde_pin_setup),
      cleanup(tilde_pin_cleanup)]) :-
  V812 = version([8,1,2], '', 4, 0, [], 0, '8.1.2'),
  V813 = version([8,1,3,1], '', 4, 0, [], 0, '8.1.3.1'),
  Sel812 = selected(qtest, 'td/ap-8.1.2', run, V812, [slot('8.1')]),
  Sel813 = selected(qtest, 'td/ap-8.1.3.1', run, V813, [slot('8.1')]),
  Q = qualified_target(equal, qtest, td, at, V812, [[], []]),
  nb_setval(prover_root_goals, [target(Q, '=td/at-8.1.2'):run?{[]}]),
  Reasons = [introduced_by(qtest://'td/at-8.1.2', run, version(tilde, V812)),
             introduced_by(qtest://'td/rl-8.1.3.1', run, version(tilde, V813))],
  list_to_assoc([selected_cn(td, ap)-ordset([Sel813, Sel812]),
                 selected_cn_allow_multislot(td, ap)-true,
                 cn_domain_reason(td, ap)-ordset(Reasons)], Cons),
  % The root's pin arrives after the unconstrained chooser committed 8.1.3.1.
  \+ heuristic:constraint_guard(constraint(selected_cn(td, ap):{ordset([Sel812])}), Cons),
  prover:learned(cn_domain(td, ap, '8.1'), version_domain(any, [bound(tilde, V812)])).

test(constrained_origin_beats_committed_tilde,
     [setup(tilde_pin_setup),
      cleanup(tilde_pin_cleanup)]) :-
  V812 = version([8,1,2], '', 4, 0, [], 0, '8.1.2'),
  V813 = version([8,1,3,1], '', 4, 0, [], 0, '8.1.3.1'),
  Sel812 = selected(qtest, 'td/ap-8.1.2', run, V812, [slot('8.1')]),
  Sel813 = selected(qtest, 'td/ap-8.1.3.1', run, V813, [slot('8.1')]),
  nb_setval(prover_root_goals, []),
  AtPin = [introduced_by(qtest://'td/root-1.0', run, version(tilde, V812))],
  Reasons = [introduced_by(qtest://'td/at-8.1.2', run, version(tilde, V812)),
             introduced_by(qtest://'td/rl-8.1.3.1', run, version(tilde, V813))],
  list_to_assoc([selected_cn_allow_multislot(td, ap)-true,
                 cn_domain_reason(td, ap)-ordset(Reasons),
                 cn_domain_reason(td, at)-ordset(AtPin)], Cons),
  \+ cnselect:selected_cn_unique_or_reprove(td, ap, [Sel812], [Sel813, Sel812], Cons),
  prover:learned(cn_domain(td, ap, '8.1'), version_domain(any, [bound(tilde, V812)])).

test(unversioned_reasons_learn_nothing,
     [setup(tilde_pin_setup),
      cleanup(tilde_pin_cleanup)]) :-
  V812 = version([8,1,2], '', 4, 0, [], 0, '8.1.2'),
  V813 = version([8,1,3,1], '', 4, 0, [], 0, '8.1.3.1'),
  Sel812 = selected(qtest, 'td/ap-8.1.2', run, V812, [slot('8.1')]),
  Sel813 = selected(qtest, 'td/ap-8.1.3.1', run, V813, [slot('8.1')]),
  nb_setval(prover_root_goals, []),
  Reasons = [introduced_by(qtest://'td/at-8.1.2', run, slot('8.1'))],
  list_to_assoc([selected_cn_allow_multislot(td, ap)-true,
                 cn_domain_reason(td, ap)-ordset(Reasons)], Cons),
  \+ cnselect:selected_cn_unique_or_reprove(td, ap, [Sel813], [Sel812, Sel813], Cons),
  \+ prover:learned(cn_domain(td, ap, _), _).

test(empty_delta_does_not_learn,
     [setup(tilde_pin_setup),
      cleanup(tilde_pin_cleanup)]) :-
  V812 = version([8,1,2], '', 4, 0, [], 0, '8.1.2'),
  V813 = version([8,1,3,1], '', 4, 0, [], 0, '8.1.3.1'),
  Sel812 = selected(qtest, 'td/ap-8.1.2', run, V812, [slot('8.1')]),
  Sel813 = selected(qtest, 'td/ap-8.1.3.1', run, V813, [slot('8.1')]),
  Reasons = [introduced_by(qtest://'td/at-8.1.2', run, version(tilde, V812))],
  list_to_assoc([selected_cn_allow_multislot(td, ap)-true,
                 cn_domain_reason(td, ap)-ordset(Reasons)], Cons),
  \+ cnselect:selected_cn_unique_or_reprove(td, ap, [Sel812, Sel813], Cons),
  \+ prover:learned(cn_domain(td, ap, _), _).

test(equal_newcomer_meets_learned_tilde,
     [setup(tilde_pin_setup),
      cleanup(tilde_pin_cleanup)]) :-
  V812 = version([8,1,2], '', 4, 0, [], 0, '8.1.2'),
  V813 = version([8,1,3,1], '', 4, 0, [], 0, '8.1.3.1'),
  prover:learn(cn_domain(td, ap, any), version_domain(any, [bound(tilde, V812)]), true),
  DepEq = package_dependency(run, no, td, ap, equal, V813, [], []),
  \+ cnselect:child_reselection_possible(td, ap, [DepEq], []).

test(slot_learn_excludes_without_any_key,
     [setup(tilde_pin_setup),
      cleanup(tilde_pin_cleanup)]) :-
  V812 = version([8,1,2], '', 4, 0, [], 0, '8.1.2'),
  V813 = version([8,1,3,1], '', 4, 0, [], 0, '8.1.3.1'),
  prover:learn(cn_domain(td, ap, '8.1'), version_domain(any, [bound(tilde, V812)]), true),
  Dep813 = package_dependency(run, no, td, ap, tilde, V813, [], []),
  \+ cnselect:child_reselection_possible(td, ap, [Dep813], []),
  \+ prover:learned(cn_domain(td, ap, any), _).

test(root_slot_occupant_drops_lower_bound_newcomer,
     [setup(tilde_pin_setup),
      cleanup(tilde_pin_cleanup)]) :-
  V22 = version([22,1,8], '', 4, 0, [], 0, '22.1.8'),
  V23 = version([23,1,4], '', 4, 0, [], 1, '23.1.4-r1'),
  Sel22 = selected(qtest, 'td/cc-22.1.8', run, V22, [slot('0')]),
  Sel23 = selected(qtest, 'td/cc-23.1.4-r1', run, V23, [slot('0')]),
  Q = qualified_target(equal, qtest, td, cc, V22, [[], []]),
  nb_setval(prover_root_goals, [target(Q, '=td/cc-22.1.8'):run?{[]}]),
  list_to_assoc([selected_cn_allow_multislot(td, cc)-true], Cons),
  sort([Sel22, Sel23], Merged),
  % clang-common-22 is already in the slot; clang-23 asks for >=23.1.4.
  \+ cnselect:selected_cn_unique_or_reprove(td, cc, [Sel23], Merged, Cons),
  prover:learned(cn_domain(td, cc, '0'), version_domain(any, [bound(equal, V22)])),
  \+ prover:learned(cn_domain(td, cc, any), _),
  Dep23 = package_dependency(run, no, td, cc, greaterequal, V23, [], []),
  \+ cnselect:child_reselection_possible(td, cc, [Dep23], []),
  Ctx = [self(qtest://'td/clang-23.1.4-r1')],
  catch(( cnselect:maybe_learn_parent_narrowing(td, cc, [Dep23], Ctx),
          fail ),
        prover_reprove(cn_domain(td, clang, none, [qtest://'td/clang-23.1.4-r1'], [parent_narrowing])),
        true),
  % The root can also be the version that arrives second.
  ( nb_current(prover_learned_constraints, _) -> nb_delete(prover_learned_constraints) ; true ),
  \+ cnselect:selected_cn_unique_or_reprove(td, cc, [Sel22], Merged, Cons),
  prover:learned(cn_domain(td, cc, '0'), version_domain(any, [bound(equal, V22)])).

test(unversioned_root_does_not_pin_one_slot_version,
     [setup(tilde_pin_setup),
      cleanup(tilde_pin_cleanup)]) :-
  V22 = version([22,1,8], '', 4, 0, [], 0, '22.1.8'),
  V23 = version([23,1,4], '', 4, 0, [], 1, '23.1.4-r1'),
  Sel22 = selected(qtest, 'td/cc-22.1.8', run, V22, [slot('0')]),
  Sel23 = selected(qtest, 'td/cc-23.1.4-r1', run, V23, [slot('0')]),
  Qu = qualified_target(none, qtest, td, cc, version_none, [[], []]),
  nb_setval(prover_root_goals, [target(Qu, 'td/cc'):run?{[]}]),
  list_to_assoc([selected_cn_allow_multislot(td, cc)-true], Cons),
  sort([Sel22, Sel23], Merged),
  \+ cnselect:selected_cn_unique_or_reprove(td, cc, [Sel23], Merged, Cons),
  \+ prover:learned(cn_domain(td, cc, _), _).

test(distinct_slots_stay_unique,
     [setup(tilde_pin_setup),
      cleanup(tilde_pin_cleanup)]) :-
  V18 = version([18], '', 4, 0, [], 0, '18'),
  V19 = version([19], '', 4, 0, [], 0, '19'),
  Sel18 = selected(qtest, 'td/crt-18', run, V18, [slot('18')]),
  Sel19 = selected(qtest, 'td/crt-19', run, V19, [slot('19')]),
  Reasons = [introduced_by(qtest://'td/at-8.1.2', run, version(tilde, V18)),
             introduced_by(qtest://'td/rl-8.1.3.1', run, version(tilde, V19))],
  list_to_assoc([selected_cn_allow_multislot(td, crt)-true,
                 cn_domain_reason(td, crt)-ordset(Reasons)], Cons),
  cnselect:selected_cn_unique_or_reprove(td, crt, [Sel19], [Sel18, Sel19], Cons),
  \+ prover:learned(cn_domain(td, crt, _), _).

test(cli_root_goal_matches_this_entry,
     [setup(tilde_pin_setup),
      cleanup(tilde_pin_cleanup)]) :-
  V812 = version([8,1,2], '', 4, 0, [], 0, '8.1.2'),
  nb_setval(prover_root_goals, [qtest://'td/at-8.1.2':run?{[]}]),
  cnselect:entry_is_root_target(qtest://'td/at-8.1.2'),
  \+ cnselect:entry_is_root_target(qtest://'td/ap-8.1.2'),
  Q = qualified_target(equal, qtest, td, at, V812, [[], []]),
  nb_setval(prover_root_goals, [target(Q, '=td/at-8.1.2'):run?{[]}]),
  cnselect:entry_is_root_target(qtest://'td/at-8.1.2'),
  \+ cnselect:entry_is_root_target(qtest://'td/at-8.1.3.1'),
  Qu = qualified_target(none, qtest, td, at, version_none, [[], []]),
  nb_setval(prover_root_goals, [target(Qu, 'td/at'):run?{[]}]),
  cnselect:entry_is_root_target(qtest://'td/at-8.1.2'),
  cnselect:entry_is_root_target(qtest://'td/at-8.1.3.1'),
  \+ cnselect:entry_is_root_target(qtest://'td/ap-8.1.2').

test(origin_reject_skips_root,
     [setup(tilde_pin_setup),
      cleanup(tilde_pin_cleanup)]) :-
  V812 = version([8,1,2], '', 4, 0, [], 0, '8.1.2'),
  nb_setval(prover_root_goals, [qtest://'td/at-8.1.2':run]),
  Reasons = [introduced_by(qtest://'td/at-8.1.2', run, version(tilde, V812))],
  cnselect:add_cn_domain_origin_rejects(Reasons, false),
  \+ cnselect:cn_domain_candidate_rejected(td, at, none, qtest://'td/at-8.1.2').

tilde_pin_setup :-
  V812 = version([8,1,2], '', 4, 0, [], 0, '8.1.2'),
  V812r1 = version([8,1,2], '', 4, 0, [], 1, '8.1.2-r1'),
  V813 = version([8,1,3,1], '', 4, 0, [], 0, '8.1.3.1'),
  V18 = version([18], '', 4, 0, [], 0, '18'),
  V19 = version([19], '', 4, 0, [], 0, '19'),
  V1 = version([1,0], '', 4, 0, [], 0, '1.0'),
  assertz(cache:ordered_entry(qtest, 'td/ap-8.1.2', td, ap, V812)),
  assertz(cache:entry_metadata(qtest, 'td/ap-8.1.2', slot, slot('8.1'))),
  assertz(cache:ordered_entry(qtest, 'td/ap-8.1.3.1', td, ap, V813)),
  assertz(cache:entry_metadata(qtest, 'td/ap-8.1.3.1', slot, slot('8.1'))),
  assertz(cache:ordered_entry(qtest, 'td/at-8.1.2', td, at, V812)),
  assertz(cache:entry_metadata(qtest, 'td/at-8.1.2', slot, slot('8.1'))),
  assertz(cache:ordered_entry(qtest, 'td/at-8.1.3.1', td, at, V813)),
  assertz(cache:entry_metadata(qtest, 'td/at-8.1.3.1', slot, slot('8.1'))),
  assertz(cache:ordered_entry(qtest, 'td/rl-8.1.3.1', td, rl, V813)),
  assertz(cache:entry_metadata(qtest, 'td/rl-8.1.3.1', slot, slot('8.1'))),
  assertz(cache:ordered_entry(qtest, 'td/rl-8.1.2-r1', td, rl, V812r1)),
  assertz(cache:entry_metadata(qtest, 'td/rl-8.1.2-r1', slot, slot('8.1'))),
  assertz(cache:ordered_entry(qtest, 'td/crt-18', td, crt, V18)),
  assertz(cache:entry_metadata(qtest, 'td/crt-18', slot, slot('18'))),
  assertz(cache:ordered_entry(qtest, 'td/crt-19', td, crt, V19)),
  assertz(cache:entry_metadata(qtest, 'td/crt-19', slot, slot('19'))),
  assertz(cache:ordered_entry(qtest, 'td/root-1.0', td, root, V1)),
  assertz(cache:entry_metadata(qtest, 'td/root-1.0', slot, slot('0'))),
  V22 = version([22,1,8], '', 4, 0, [], 0, '22.1.8'),
  V23 = version([23,1,4], '', 4, 0, [], 1, '23.1.4-r1'),
  assertz(cache:ordered_entry(qtest, 'td/cc-22.1.8', td, cc, V22)),
  assertz(cache:entry_metadata(qtest, 'td/cc-22.1.8', slot, slot('0'))),
  assertz(cache:ordered_entry(qtest, 'td/cc-23.1.4-r1', td, cc, V23)),
  assertz(cache:entry_metadata(qtest, 'td/cc-23.1.4-r1', slot, slot('0'))),
  assertz(cache:ordered_entry(qtest, 'td/clang-23.1.4-r1', td, clang, V23)),
  assertz(cache:entry_metadata(qtest, 'td/clang-23.1.4-r1', slot, slot('23'))),
  forall(cache:ordered_entry(qtest, Id, td, _, _),
         assertz(cache:entry_metadata(qtest, Id, keywords, stable(amd64)))),
  % CI boots PLUnit without preference:init, so ACCEPT_KEYWORDS is empty
  % and a keyworded candidate is keyword_filtered. Parent narrowing then
  % yields and the chooser is never rejected.
  unittest:accept_stable_amd64,
  heuristic:init_state.

tilde_pin_cleanup :-
  unittest:restore_stable_amd64,
  heuristic:cleanup_state,
  retractall(cache:ordered_entry(qtest, _, td, _, _)),
  retractall(cache:entry_metadata(qtest, 'td/ap-8.1.2', _, _)),
  retractall(cache:entry_metadata(qtest, 'td/ap-8.1.3.1', _, _)),
  retractall(cache:entry_metadata(qtest, 'td/at-8.1.2', _, _)),
  retractall(cache:entry_metadata(qtest, 'td/at-8.1.3.1', _, _)),
  retractall(cache:entry_metadata(qtest, 'td/rl-8.1.3.1', _, _)),
  retractall(cache:entry_metadata(qtest, 'td/rl-8.1.2-r1', _, _)),
  retractall(cache:entry_metadata(qtest, 'td/crt-18', _, _)),
  retractall(cache:entry_metadata(qtest, 'td/crt-19', _, _)),
  retractall(cache:entry_metadata(qtest, 'td/root-1.0', _, _)),
  retractall(cache:entry_metadata(qtest, 'td/cc-22.1.8', _, _)),
  retractall(cache:entry_metadata(qtest, 'td/cc-23.1.4-r1', _, _)),
  retractall(cache:entry_metadata(qtest, 'td/clang-23.1.4-r1', _, _)),
  ( nb_current(prover_learned_constraints, _) -> nb_delete(prover_learned_constraints) ; true ),
  ( nb_current(prover_root_goals, _) -> nb_delete(prover_root_goals) ; true ),
  memo:clear_caches.

:- end_tests(tilde_pin_domain).


% -----------------------------------------------------------------------------
%  Conceding a conflict that has no solution
% -----------------------------------------------------------------------------

% One conflict the reprove loop learns nothing new from used to end the
% loop: the final pass ran with reprove disabled and every conflict it
% was the first to meet became an assumption (app-text/pandoc-2.18-r2:
% one conflict without a solution on dev-haskell/primitive, reported
% with six others that rejecting a candidate repairs). The loop now
% concedes that one conflict (heuristic:reprove_concede/1) and goes on.

:- begin_tests(concede_conflict).

test(rejecting_the_rejected_is_no_progress,
     [setup(concede_setup),
      cleanup(concede_cleanup)]) :-
  V2 = version([2], '', 4, 0, [], 0, '2'),
  Dom = version_domain(any, [bound(smaller, V2)]),
  P1 = qtest://'cc/p-1',
  P0 = qtest://'cc/p-0',
  % Parent narrowing rejects under the global key.
  cnselect:add_cn_domain_rejects(cc, p, none, [P1], true),
  cnselect:add_cn_domain_rejects(cc, p, none, [P1], false),
  % The same candidate under a narrower key changes no lookup.
  cnselect:add_cn_domain_rejects(cc, p, Dom, [P1], false),
  \+ ( memo:cn_domain_reject_(key(cc, p, _, KeyDom), _), KeyDom \== none ),
  % A candidate that is news is recorded, the known one is not repeated.
  cnselect:add_cn_domain_rejects(cc, p, Dom, [P0, P1], true),
  cnselect:cn_domain_candidate_rejected(cc, p, Dom, P0),
  \+ cnselect:cn_domain_candidate_rejected(cc, p, none, P0).

test(concede_undoes_the_whole_climb,
     [setup(concede_setup),
      cleanup(concede_cleanup)]) :-
  V2 = version([2], '', 4, 0, [], 0, '2'),
  Dom = version_domain(any, [bound(smaller, V2)]),
  % q needs p, p needs x, and no x fits: parent narrowing rejected p for
  % x, then q for p. u was rejected for an unrelated conflict.
  assertz(memo:cn_narrowed_for_(cc, p, qtest://'cc/p-1', cc, x, [])),
  assertz(memo:cn_narrowed_for_(cc, q, qtest://'cc/q-1', cc, p, [])),
  cnselect:add_cn_domain_rejects(cc, x, Dom, [qtest://'cc/x-3'], true),
  cnselect:add_cn_domain_rejects(cc, p, none, [qtest://'cc/p-1'], true),
  cnselect:add_cn_domain_rejects(cc, q, none, [qtest://'cc/q-1'], true),
  cnselect:add_cn_domain_rejects(cc, u, none, [qtest://'cc/u-1'], true),
  % The consumer of q has no other q: the conflict comes back unchanged.
  Info = cn_domain(cc, q, Dom, [qtest://'cc/q-1'], []),
  heuristic:handle_reprove(Info, false),
  heuristic:reprove_concede(Info),
  cnselect:cn_conceded(cc, q),
  cnselect:cn_conceded(cc, p),
  cnselect:cn_conceded(cc, x),
  \+ cnselect:cn_conceded(cc, u),
  % The climb's rejects are gone, the unrelated one stays.
  \+ cnselect:cn_domain_candidate_rejected(cc, q, none, qtest://'cc/q-1'),
  \+ cnselect:cn_domain_candidate_rejected(cc, p, none, qtest://'cc/p-1'),
  \+ cnselect:cn_domain_candidate_rejected(cc, x, Dom, qtest://'cc/x-3'),
  cnselect:cn_domain_candidate_rejected(cc, u, none, qtest://'cc/u-1'),
  % Conceding twice is no progress: the prover falls back to its final pass.
  \+ heuristic:reprove_concede(Info).

test(concede_forgets_what_the_climb_learned,
     [setup(concede_setup),
      cleanup(concede_cleanup)]) :-
  V2 = version([2], '', 4, 0, [], 0, '2'),
  V3 = version([3], '', 4, 0, [], 0, '3'),
  Below2 = version_domain(any, [bound(smaller, V2)]),
  Below3 = version_domain(any, [bound(smaller, V3)]),
  % Learned in an earlier pass: p below 3, and u below 3.
  prover:learn(cn_domain(cc, p, any), Below3, true),
  prover:learn(cn_domain(cc, u, any), Below3, true),
  % The pass in which the climb starts: x is learned below 2 and p is
  % narrowed for it. Under the p selected instead, p is learned below 2
  % and q below 3.
  cnselect:note_pass_learned,
  prover:learn(cn_domain(cc, x, any), Below2, true),
  cnselect:pass_learned(AtStart),
  assertz(memo:cn_narrowed_for_(cc, p, qtest://'cc/p-1', cc, x, AtStart)),
  prover:learn(cn_domain(cc, p, any), Below2, true),
  prover:learn(cn_domain(cc, q, any), Below3, true),
  % A later pass, with another snapshot: q is narrowed for p.
  cnselect:note_pass_learned,
  cnselect:pass_learned(Later),
  Later \== AtStart,
  assertz(memo:cn_narrowed_for_(cc, q, qtest://'cc/q-1', cc, p, Later)),
  prover:learn(cn_domain(cc, u, any), Below2, true),
  cnselect:concede_cn(cc, q),
  % The climb's packages are back at the start of its first pass: the
  % one snapshot serves all of them. x would stay learned with the
  % snapshot of the narrowing that stalled. q would with a snapshot per
  % package (no narrowing names q before the later pass), and what q
  % learned in between it learned under a p the plan does not keep.
  prover:learned_snapshot(cn_domain(cc, x, _), []),
  prover:learned_snapshot(cn_domain(cc, q, _), []),
  prover:learned(cn_domain(cc, p, any), LearnedP),
  LearnedP == Below3,
  % A package outside the climb keeps what it learned meanwhile.
  prover:learned(cn_domain(cc, u, any), LearnedU),
  LearnedU \== Below3.

test(narrowing_outside_the_stalled_domain_is_settled,
     [setup(concede_setup),
      cleanup(concede_cleanup)]) :-
  V2 = version([2], '', 4, 0, [], 0, '2'),
  V3 = version([3], '', 4, 0, [], 0, '3'),
  Below2 = version_domain(any, [bound(smaller, V2)]),
  Below3 = version_domain(any, [bound(smaller, V3)]),
  % An early pass: q-3 is rejected for its dependency on y, and q-1
  % does without y. That narrowing did its work.
  cnselect:note_pass_learned,
  cnselect:pass_learned(Early),
  assertz(memo:cn_narrowed_for_(cc, q, qtest://'cc/q-3', cc, y, Early)),
  cnselect:add_cn_domain_rejects(cc, q, none, [qtest://'cc/q-3'], true),
  % Later p is learned below 3, and then a climb starts: q-1 is
  % rejected for p, p is learned below 2 on the way.
  prover:learn(cn_domain(cc, p, any), Below3, true),
  cnselect:note_pass_learned,
  cnselect:pass_learned(Later),
  assertz(memo:cn_narrowed_for_(cc, q, qtest://'cc/q-1', cc, p, Later)),
  cnselect:add_cn_domain_rejects(cc, q, none, [qtest://'cc/q-1'], true),
  prover:learn(cn_domain(cc, p, any), Below2, true),
  % The consumer of q wants a q below 2 and there is none left.
  heuristic:reprove_concede(cn_domain(cc, q, Below2, [qtest://'cc/q-1'], [])),
  cnselect:cn_conceded(cc, q),
  cnselect:cn_conceded(cc, p),
  % q-3 could not have served that consumer: y is not conceded, q-3
  % stays rejected, and the climb began in the later pass.
  \+ cnselect:cn_conceded(cc, y),
  cnselect:cn_domain_candidate_rejected(cc, q, none, qtest://'cc/q-3'),
  \+ cnselect:cn_domain_candidate_rejected(cc, q, none, qtest://'cc/q-1'),
  prover:learned(cn_domain(cc, p, any), LearnedP),
  LearnedP == Below3.

test(stall_without_a_domain_follows_every_narrowing,
     [setup(concede_setup),
      cleanup(concede_cleanup)]) :-
  V3 = version([3], '', 4, 0, [], 0, '3'),
  Below3 = version_domain(any, [bound(smaller, V3)]),
  cnselect:note_pass_learned,
  cnselect:pass_learned(Early),
  assertz(memo:cn_narrowed_for_(cc, q, qtest://'cc/q-3', cc, y, Early)),
  cnselect:add_cn_domain_rejects(cc, q, none, [qtest://'cc/q-3'], true),
  prover:learn(cn_domain(cc, p, any), Below3, true),
  cnselect:note_pass_learned,
  cnselect:pass_learned(Later),
  assertz(memo:cn_narrowed_for_(cc, q, qtest://'cc/q-1', cc, p, Later)),
  cnselect:add_cn_domain_rejects(cc, q, none, [qtest://'cc/q-1'], true),
  % Nothing says which version the consumer of q could have used: q ran
  % out of candidates because of both rejects.
  heuristic:reprove_concede(cn_domain(cc, q, none, [qtest://'cc/q-1'], [])),
  cnselect:cn_conceded(cc, p),
  cnselect:cn_conceded(cc, y),
  \+ cnselect:cn_domain_candidate_rejected(cc, q, none, qtest://'cc/q-3'),
  % The climb began with the narrowing for y: p is back at that pass.
  prover:learned_snapshot(cn_domain(cc, p, _), []).

test(concession_is_per_slot_for_a_package_with_several,
     [setup(concede_setup),
      cleanup(concede_cleanup)]) :-
  V9 = version([9], '', 4, 0, [], 0, '9'),
  Below9 = version_domain(any, [bound(smaller, V9)]),
  M1 = qtest://'cc/m-1',
  M2 = qtest://'cc/m-2',
  version_domain:candidate_slot(M1, Slot1),
  version_domain:candidate_slot(M2, Slot2),
  Slot1 \== Slot2,
  cnselect:add_cn_domain_rejects(cc, m, none, [M1, M2], true),
  % A dependency on slot 1 of m that nothing satisfies.
  Stall = cn_domain(cc, m, none, [], [introduced_by(qtest://'cc/q-1', run, slot([slot('1')]))]),
  heuristic:reprove_concede(Stall),
  cnselect:cn_conceded(cc, m, Slot1),
  \+ cnselect:cn_conceded(cc, m, Slot2),
  \+ cnselect:cn_conceded(cc, m),
  % Only the candidates of that slot are eligible again.
  \+ cnselect:cn_domain_candidate_rejected(cc, m, none, M1),
  cnselect:cn_domain_candidate_rejected(cc, m, none, M2),
  % Conflicts about slot 1 are not raised and reject nothing ...
  \+ cnselect:request_reprove(Stall),
  \+ cnselect:request_reprove(cn_domain(cc, m, none, [M1], [])),
  cnselect:add_cn_domain_rejects(cc, m, none, [M1], false),
  cnselect:learn_cn_domain(cc, m, Slot1, Below9, false),
  % ... the other slot, and a conflict that spans slots, are repaired.
  catch(( cnselect:request_reprove(cn_domain(cc, m, none, [M2], [])), fail ),
        prover_reprove(_), true),
  catch(( cnselect:request_reprove(cn_domain(cc, m, none, [M1, M2], [])), fail ),
        prover_reprove(_), true),
  cnselect:learn_cn_domain(cc, m, Slot2, Below9, true),
  % The same stall again is no progress; one that names no slot
  % concedes the package.
  \+ heuristic:reprove_concede(Stall),
  heuristic:reprove_concede(cn_domain(cc, m, none, [M1, M2], [])),
  cnselect:cn_conceded(cc, m),
  \+ cnselect:request_reprove(cn_domain(cc, m, none, [M2], [])).

test(package_with_one_slot_is_conceded_as_a_whole,
     [setup(concede_setup),
      cleanup(concede_cleanup)]) :-
  % The stall names candidates of one slot, and q has no other.
  heuristic:reprove_concede(cn_domain(cc, q, none, [qtest://'cc/q-1'], [])),
  cnselect:cn_conceded(cc, q),
  % A later conflict about q that names no slot is not raised either.
  \+ cnselect:request_reprove(cn_domain(cc, q, none, [], [])).

test(climb_of_a_slot_follows_the_narrowing_in_that_slot,
     [setup(concede_setup),
      cleanup(concede_cleanup)]) :-
  M1 = qtest://'cc/m-1',
  M2 = qtest://'cc/m-2',
  version_domain:candidate_slot(M1, Slot1),
  version_domain:candidate_slot(M2, Slot2),
  V9 = version([9], '', 4, 0, [], 0, '9'),
  Below9 = version_domain(any, [bound(smaller, V9)]),
  % m-2 was rejected for y, m-1 for p; the stall is about m-1.
  assertz(memo:cn_narrowed_for_(cc, m, M2, cc, y, [])),
  assertz(memo:cn_narrowed_for_(cc, m, M1, cc, p, [])),
  cnselect:add_cn_domain_rejects(cc, m, none, [M1, M2], true),
  prover:learn(cn_domain(cc, m, Slot1), Below9, true),
  prover:learn(cn_domain(cc, m, Slot2), Below9, true),
  heuristic:reprove_concede(cn_domain(cc, m, none, [M1], [])),
  cnselect:cn_conceded(cc, m, Slot1),
  cnselect:cn_conceded(cc, p),
  \+ cnselect:cn_conceded(cc, y),
  cnselect:cn_domain_candidate_rejected(cc, m, none, M2),
  % What the climb learned for that slot is forgotten, the other slot
  % keeps its domain.
  \+ prover:learned(cn_domain(cc, m, Slot1), _),
  prover:learned(cn_domain(cc, m, Slot2), Below9).

test(conceded_package_learns_nothing,
     [setup(concede_setup),
      cleanup(concede_cleanup)]) :-
  V2 = version([2], '', 4, 0, [], 0, '2'),
  Below2 = version_domain(any, [bound(smaller, V2)]),
  cnselect:concede_cn(cc, p),
  cnselect:learn_cn_domain(cc, p, any, Below2, false),
  prover:learned_snapshot(cn_domain(cc, p, _), []),
  cnselect:learn_cn_domain(cc, u, any, Below2, true),
  prover:learned(cn_domain(cc, u, any), Below2).

test(stall_without_a_climb_keeps_the_learned_domain,
     [setup(concede_setup),
      cleanup(concede_cleanup)]) :-
  V2 = version([2], '', 4, 0, [], 0, '2'),
  Below2 = version_domain(any, [bound(smaller, V2)]),
  prover:learn(cn_domain(cc, p, any), Below2, true),
  cnselect:concede_cn(cc, p),
  prover:learned(cn_domain(cc, p, any), Below2).

test(conceded_conflict_is_not_raised,
     [setup(concede_setup),
      cleanup(concede_cleanup)]) :-
  Sel = selected(qtest, 'cc/p-1', run, version([1], '', 4, 0, [], 0, '1'), [slot('0')]),
  cnselect:concede_cn(cc, p),
  % Conceded: fails like a caller with reprove disabled, no exception.
  \+ cnselect:request_reprove(cn_domain(cc, p, none, [qtest://'cc/p-1'], [])),
  cnselect:maybe_request_cn_domain_reprove(cc, p, none, [Sel], []),
  % Every other package is still repaired.
  catch(( cnselect:request_reprove(cn_domain(cc, u, none, [qtest://'cc/u-1'], [])),
          fail ),
        prover_reprove(cn_domain(cc, u, none, [qtest://'cc/u-1'], [])),
        true).

test(prover_spends_one_attempt_on_a_stall,
     [setup(concede_setup),
      cleanup(concede_cleanup)]) :-
  Info = cn_domain(cc, q, none, [qtest://'cc/q-1'], []),
  % Learned something: progress.
  prover:reprove_progress(Info),
  \+ cnselect:cn_conceded(cc, q),
  % Learned nothing: conceded, still progress.
  prover:reprove_progress(Info),
  cnselect:cn_conceded(cc, q),
  % Nothing left to learn or to concede.
  \+ prover:reprove_progress(Info),
  % A conflict that names no package cannot be conceded.
  \+ prover:reprove_progress(some_other_conflict).

test(learned_wildcard_domain_is_progress,
     [setup(concede_setup),
      cleanup(concede_cleanup)]) :-
  % The wildcard learner throws only after the learned store changed;
  % there is no candidate to reject and nothing to concede.
  Info = cn_domain(cc, w, none, [], [wildcard_domain_learning]),
  heuristic:handle_reprove(Info, true),
  prover:reprove_progress(Info),
  prover:reprove_progress(Info),
  \+ cnselect:cn_conceded(cc, w).

test(learned_snapshot_and_restore,
     [setup(concede_setup),
      cleanup(concede_cleanup)]) :-
  V2 = version([2], '', 4, 0, [], 0, '2'),
  V3 = version([3], '', 4, 0, [], 0, '3'),
  Below2 = version_domain(any, [bound(smaller, V2)]),
  Below3 = version_domain(any, [bound(smaller, V3)]),
  prover:learned_snapshot(cn_domain(_, _, _), []),
  prover:learn(cn_domain(cc, p, any), Below3, true),
  prover:learn(other(cc, p), kept, true),
  prover:learned_snapshot(cn_domain(_, _, _), Snapshot),
  Snapshot == [cn_domain(cc, p, any)-Below3],
  prover:learn(cn_domain(cc, p, any), Below2, true),
  prover:learn(cn_domain(cc, p, '0'), Below2, true),
  prover:learn(cn_domain(cc, u, any), Below2, true),
  % Only what matches the pattern goes back; the pattern stays unbound.
  Pattern = cn_domain(cc, p, Slot),
  prover:learned_restore(Pattern, Snapshot),
  var(Slot),
  prover:learned(cn_domain(cc, p, any), RestoredP),
  RestoredP == Below3,
  \+ prover:learned(cn_domain(cc, p, '0'), _),
  prover:learned(cn_domain(cc, u, any), Below2),
  prover:learned(other(cc, p), kept),
  % Restoring to an empty snapshot forgets.
  prover:learned_restore(cn_domain(cc, u, _), []),
  prover:learned_snapshot(cn_domain(cc, u, _), []),
  prover:learned(cn_domain(cc, p, any), _).

test(state_is_scoped_to_the_proof,
     [setup(concede_setup),
      cleanup(concede_cleanup)]) :-
  V2 = version([2], '', 4, 0, [], 0, '2'),
  Below2 = version_domain(any, [bound(smaller, V2)]),
  cnselect:concede_cn(cc, p),
  assertz(memo:cn_narrowed_for_(cc, q, qtest://'cc/q-1', cc, p, [])),
  prover:learn(cn_domain(cc, u, any), Below2, true),
  cnselect:note_pass_learned,
  cnselect:pass_learned(OuterPass),
  % A nested reprove-enabled proof starts without the outer concessions
  % and gives them back when it ends.
  heuristic:init_state,
  \+ cnselect:cn_conceded(cc, p),
  \+ memo:cn_narrowed_for_(_, _, _, _, _, _),
  cnselect:concede_cn(cc, u),
  nb_setval(rules_pass_learned, []),
  heuristic:cleanup_state,
  cnselect:cn_conceded(cc, p),
  \+ cnselect:cn_conceded(cc, u),
  memo:cn_narrowed_for_(cc, q, qtest://'cc/q-1', cc, p, []),
  cnselect:pass_learned(Restored),
  Restored == OuterPass,
  OuterPass \== [].

concede_setup :-
  memo:clear_caches,
  ( nb_current(prover_root_goals, _) -> nb_delete(prover_root_goals) ; true ),
  ( nb_current(prover_learned_constraints, _) -> nb_delete(prover_learned_constraints) ; true ),
  ( nb_current(rules_pass_learned, _) -> nb_delete(rules_pass_learned) ; true ),
  % m has one version in each of two slots; the other packages have one
  % slot.
  forall(member(Name-Major-Slot, [p-1-'0', q-3-'0', q-1-'0', x-3-'0', u-1-'0', m-2-'2', m-1-'1']),
         ( atom_number(Full, Major),
           atomic_list_concat(['cc/', Name, '-', Full], Id),
           assertz(cache:ordered_entry(qtest, Id, cc, Name, version([Major], '', 4, 0, [], 0, Full))),
           assertz(cache:entry_metadata(qtest, Id, slot, slot(Slot)))
         )).

concede_cleanup :-
  forall(cache:ordered_entry(qtest, Id, cc, _, _),
         retractall(cache:entry_metadata(qtest, Id, _, _))),
  retractall(cache:ordered_entry(qtest, _, cc, _, _)),
  memo:clear_caches,
  ( nb_current(prover_learned_constraints, _) -> nb_delete(prover_learned_constraints) ; true ),
  ( nb_current(rules_pass_learned, _) -> nb_delete(rules_pass_learned) ; true ).

:- end_tests(concede_conflict).


% -----------------------------------------------------------------------------
%  Alternative proofs: the other side of a conflict
% -----------------------------------------------------------------------------

% The retry loop never reconsiders which side of a conflict it kept, and
% for a target without a clean solution that side decides how many
% dependencies are assumed (dev-haskell/xml-hamlet-0.5.0.1: `<ghc-9.1`
% was kept and twelve dependencies of other packages were assumed, where
% giving up the one `<ghc-9.1` leaves two). After the loop the domain
% names packages to hold to another candidate
% (heuristic:reprove_alternatives/4), the prover proves the target again
% for each and keeps the cheapest proof (prover:prove_best/10).

:- begin_tests(alternative_proofs).

test(cost_counts_assumptions_conflicts_count_dependencies,
     [setup(alternative_setup),
      cleanup(alternative_cleanup)]) :-
  alternative_dep(smaller, 2, Below2),
  Self = [self(qtest://'ap/a-1')],
  list_to_assoc([rule(assumed(grouped_package_dependency(ap, p, [Below2]):install?{Self}))-(dep(0, [])?{[]}),
                 rule(assumed(grouped_package_dependency(ap, p, [Below2]):run?{Self}))-(dep(0, [])?{[]}),
                 rule(assumed(blocker(soft, run, ap, x, none, version_none, [])?{Self}))-(dep(0, [])?{[]}),
                 rule(qtest://'ap/a-1':run)-(dep(0, [])?{[]})],
                Proof),
  % Install and run of one dependency are one conflict in two entries;
  % a blocker record that hits nothing in the plan costs nothing.
  heuristic:proof_cost(Proof, Cost),
  Cost == cost(1, 0, 0, 0, 2),
  heuristic:proof_conflicts(Proof, 1).

test(dependency_without_self_is_one_conflict_in_every_phase,
     [setup(alternative_setup),
      cleanup(alternative_cleanup)]) :-
  alternative_dep(smaller, 2, Below2),
  % A proof context without self/1 does not say who the consumer is:
  % install and run of the dependency are still one conflict.
  list_to_assoc([rule(assumed(grouped_package_dependency(ap, p, [Below2]):install?{[]}))-(dep(0, [])?{[]}),
                 rule(assumed(grouped_package_dependency(ap, p, [Below2]):run?{[]}))-(dep(0, [])?{[]})],
                NoSelf),
  heuristic:assumption_conflict(grouped_package_dependency(ap, p, [Below2]):install?{[]}, Install),
  heuristic:assumption_conflict(grouped_package_dependency(ap, p, [Below2]):run?{[]}, Run),
  Install == dependency(ap, p),
  Run == Install,
  heuristic:proof_conflicts(NoSelf, 1),
  heuristic:proof_cost(NoSelf, CostNoSelf),
  CostNoSelf == cost(1, 0, 0, 0, 2),
  % A dependency on another package is another conflict, and so is the
  % same dependency of a consumer that is known.
  Self = [self(qtest://'ap/a-1')],
  list_to_assoc([rule(assumed(grouped_package_dependency(ap, p, [Below2]):install?{[]}))-(dep(0, [])?{[]}),
                 rule(assumed(grouped_package_dependency(ap, q, [Below2]):run?{[]}))-(dep(0, [])?{[]}),
                 rule(assumed(grouped_package_dependency(ap, p, [Below2]):run?{Self}))-(dep(0, [])?{[]})],
                Three),
  heuristic:proof_conflicts(Three, 3).

test(cost_orders_conflicts_before_entries_and_negative_before_positive,
     [setup(alternative_setup),
      cleanup(alternative_cleanup)]) :-
  alternative_dep(smaller, 2, Below2),
  alternative_dep(greaterequal, 2, From2),
  A = [self(qtest://'ap/a-1')],
  B = [self(qtest://'ap/b-1')],
  Wide = [self(qtest://'ap/a-1'), build_with_use:use_state([x], [])],
  Masked = [self(qtest://'ap/a-1'), assumption_reason(masked)],
  % One conflict listed three times: two phases, and one phase again
  % under a wider proof context.
  list_to_assoc([rule(assumed(grouped_package_dependency(ap, p, [Below2]):install?{A}))-(dep(0, [])?{[]}),
                 rule(assumed(grouped_package_dependency(ap, p, [Below2]):install?{Wide}))-(dep(0, [])?{[]}),
                 rule(assumed(grouped_package_dependency(ap, p, [Below2]):run?{A}))-(dep(0, [])?{[]})],
                OneInThree),
  % Two conflicts listed once each.
  list_to_assoc([rule(assumed(grouped_package_dependency(ap, p, [Below2]):install?{A}))-(dep(0, [])?{[]}),
                 rule(assumed(grouped_package_dependency(ap, p, [From2]):install?{B}))-(dep(0, [])?{[]})],
                TwoInTwo),
  % Two masked dependencies, and a cycle break.
  list_to_assoc([rule(assumed(grouped_package_dependency(ap, p, [Below2]):install?{Masked}))-(dep(0, [])?{[]}),
                 rule(assumed(grouped_package_dependency(ap, q, [Below2]):install?{Masked}))-(dep(0, [])?{[]}),
                 assumed(rule(qtest://'ap/a-1':run))-(dep(-1, [])?{[]})],
                TwoMasked),
  heuristic:proof_cost(OneInThree, CostOne),
  heuristic:proof_cost(TwoInTwo, CostTwo),
  heuristic:proof_cost(TwoMasked, CostMasked),
  CostOne == cost(1, 0, 0, 0, 3),
  CostTwo == cost(2, 0, 0, 0, 2),
  CostMasked == cost(0, 2, 0, 1, 2),
  % Fewer conflicts beat fewer entries; what the user can configure
  % away beats what cannot be satisfied, whatever the numbers.
  CostOne @< CostTwo,
  CostMasked @< CostOne.

test(no_alternatives_for_one_conflict_or_without_concession,
     [setup(alternative_setup),
      cleanup(alternative_cleanup)]) :-
  alternative_dep(smaller, 2, Below2),
  V2 = version([2], '', 4, 0, [], 0, '2'),
  A = [self(qtest://'ap/a-1')],
  B = [self(qtest://'ap/b-1')],
  list_to_assoc([rule(assumed(grouped_package_dependency(ap, p, [Below2]):install?{A}))-(dep(0, [])?{[]}),
                 rule(assumed(grouped_package_dependency(ap, p, [Below2]):run?{A}))-(dep(0, [])?{[]})],
                One),
  list_to_assoc([rule(assumed(grouped_package_dependency(ap, p, [Below2]):install?{A}))-(dep(0, [])?{[]}),
                 rule(assumed(grouped_package_dependency(ap, p, [Below2]):install?{B}))-(dep(0, [])?{[]})],
                Two),
  empty_assoc(Cons),
  prover:learn(cn_domain(ap, p, any), version_domain(any, [bound(smaller, V2)]), true),
  % Nothing was conceded: the retry loop repaired what it met.
  heuristic:reprove_alternatives(Two, Cons, [], []),
  cnselect:concede_cn(ap, p),
  % One conflict: its other side costs one assumption as well.
  heuristic:reprove_alternatives(One, Cons, [], []),
  heuristic:reprove_alternatives(Two, Cons, [], [overrule(ap, p, qtest://'ap/p-3')]).

test(reversal_names_the_best_candidate_the_learned_domain_excludes,
     [setup(alternative_setup),
      cleanup(alternative_cleanup)]) :-
  V3 = version([3], '', 4, 0, [], 0, '3'),
  empty_assoc(Proof),
  empty_assoc(Cons),
  prover:learn(cn_domain(ap, p, any), version_domain(any, [bound(smaller, V3)]), true),
  % A learned domain nobody was narrowed or conceded for is left alone.
  cnselect:overrule_alternatives(Proof, Cons, []),
  assertz(memo:cn_narrowed_for_(ap, q, qtest://'ap/q-2', ap, p, [])),
  cnselect:overrule_alternatives(Proof, Cons, [overrule(ap, p, qtest://'ap/p-3')]),
  % The package of a root target is the request, not a choice.
  nb_setval(prover_root_goals, [qtest://'ap/p-1':run?{[]}]),
  cnselect:overrule_alternatives(Proof, Cons, []),
  % Also when the root target is no accepted candidate (not keyworded).
  V9 = version([9], '', 4, 0, [], 0, '9'),
  assertz(cache:ordered_entry(qtest, 'ap/p-9', ap, p, V9)),
  nb_setval(prover_root_goals, [qtest://'ap/p-9':run?{[]}]),
  findall(Listing, acceptance:accepted_keyword_candidate(install, ap, p, [], _, [], Listing), Listed),
  \+ memberchk(qtest://'ap/p-9', Listed),
  cnselect:overrule_alternatives(Proof, Cons, []).

test(majority_names_the_candidate_most_dependencies_accept,
     [setup(alternative_setup),
      cleanup(alternative_cleanup)]) :-
  V1 = version([1], '', 4, 0, [], 0, '1'),
  alternative_dep(smaller, 2, Below2),
  alternative_dep(greaterequal, 2, From2),
  alternative_dep(greaterequal, 3, From3),
  % a needs p below 2 and p-1 is selected; b, c and d need a newer p and
  % are assumed. p-3 satisfies all three, p-2 only two.
  list_to_assoc([rule(qtest://'ap/a-1':install)-(dep(1, [grouped_package_dependency(no, ap, p, [Below2]):install?{[]}])?{[]}),
                 rule(qtest://'ap/b-1':install)-(dep(1, [grouped_package_dependency(no, ap, p, [From2]):install?{[]}])?{[]}),
                 rule(qtest://'ap/c-1':install)-(dep(1, [grouped_package_dependency(no, ap, p, [From2]):install?{[]}])?{[]}),
                 rule(qtest://'ap/d-1':install)-(dep(1, [grouped_package_dependency(no, ap, p, [From3]):install?{[]}])?{[]})],
                Proof),
  list_to_assoc([selected_cn(ap, p)-ordset([selected(qtest, 'ap/p-1', install, V1, [slot('0')])])], Cons),
  % Dependencies on a package that was not conceded are not reviewed.
  cnselect:overrule_alternatives(Proof, Cons, []),
  cnselect:concede_cn(ap, p),
  cnselect:conceded_demands(Proof, Demands),
  length(Demands, 4),
  cnselect:overrule_candidates(ap, p, Candidates),
  cnselect:overrule_by_majority(ap, p, Candidates, Demands, Cons, Candidate, Gain),
  Candidate == qtest://'ap/p-3',
  Gain == 2,
  cnselect:overrule_alternatives(Proof, Cons, [overrule(ap, p, qtest://'ap/p-3')]),
  % The selected candidate is the majority's choice already: nothing to gain.
  V3 = version([3], '', 4, 0, [], 0, '3'),
  list_to_assoc([selected_cn(ap, p)-ordset([selected(qtest, 'ap/p-3', install, V3, [slot('0')])])], Cons3),
  \+ cnselect:overrule_by_majority(ap, p, Candidates, Demands, Cons3, _, _).

test(majority_counts_a_package_conceded_in_one_slot,
     [setup(alternative_setup),
      cleanup(alternative_cleanup)]) :-
  V1 = version([1], '', 4, 0, [], 0, '1'),
  V9 = version([9], '', 4, 0, [], 0, '9'),
  alternative_dep(smaller, 2, Below2),
  alternative_dep(greaterequal, 2, From2),
  alternative_dep(greaterequal, 3, From3),
  % p has a second slot in the tree that is no candidate (not keyworded):
  % a stall about slot 0 concedes that slot, not the package.
  assertz(cache:ordered_entry(qtest, 'ap/p-9', ap, p, V9)),
  assertz(cache:entry_metadata(qtest, 'ap/p-9', slot, slot('9'))),
  P1 = qtest://'ap/p-1',
  version_domain:candidate_slot(P1, Slot),
  heuristic:reprove_concede(cn_domain(ap, p, none, [P1], [])),
  cnselect:cn_conceded(ap, p, Slot),
  \+ cnselect:cn_conceded(ap, p),
  cnselect:cn_conceded_any(ap, p),
  % The same proof as above: three of four dependencies want a newer p.
  list_to_assoc([rule(qtest://'ap/a-1':install)-(dep(1, [grouped_package_dependency(no, ap, p, [Below2]):install?{[]}])?{[]}),
                 rule(qtest://'ap/b-1':install)-(dep(1, [grouped_package_dependency(no, ap, p, [From2]):install?{[]}])?{[]}),
                 rule(qtest://'ap/c-1':install)-(dep(1, [grouped_package_dependency(no, ap, p, [From2]):install?{[]}])?{[]}),
                 rule(qtest://'ap/d-1':install)-(dep(1, [grouped_package_dependency(no, ap, p, [From3]):install?{[]}])?{[]})],
                Proof),
  list_to_assoc([selected_cn(ap, p)-ordset([selected(qtest, 'ap/p-1', install, V1, [slot('0')])])], Cons),
  % The dependencies on it are reviewed and the majority is offered.
  % Nothing was learned for p, so no other reading names it.
  prover:learned_snapshot(cn_domain(ap, p, _), []),
  cnselect:conceded_demands(Proof, Demands),
  length(Demands, 4),
  cnselect:overrule_candidates(ap, p, Candidates),
  cnselect:overrule_by_majority(ap, p, Candidates, Demands, Cons, Candidate, Gain),
  Candidate == qtest://'ap/p-3',
  Gain == 2,
  cnselect:overrule_alternatives(Proof, Cons, Alternatives),
  Alternatives == [overrule(ap, p, qtest://'ap/p-3')].

test(overrule_starts_over_and_holds_the_package_to_one_candidate,
     [setup(alternative_setup),
      cleanup(alternative_cleanup)]) :-
  V2 = version([2], '', 4, 0, [], 0, '2'),
  Below2 = version_domain(any, [bound(smaller, V2)]),
  % What the retry loop left behind: a learned domain, a reject, a
  % narrowing record and a concession, for p and for an unrelated u.
  prover:learn(cn_domain(ap, p, any), Below2, true),
  prover:learn(cn_domain(ap, u, any), Below2, true),
  cnselect:add_cn_domain_rejects(ap, p, none, [qtest://'ap/p-3'], true),
  assertz(memo:cn_narrowed_for_(ap, q, qtest://'ap/q-2', ap, p, [])),
  cnselect:concede_cn(ap, u),
  heuristic:alternative_begin(overrule(ap, p, qtest://'ap/p-3')),
  % All of it answered the candidate now given up.
  \+ cnselect:cn_domain_candidate_rejected(ap, p, none, qtest://'ap/p-3'),
  \+ memo:cn_narrowed_for_(_, _, _, _, _, _),
  \+ cnselect:cn_conceded(ap, u),
  prover:learned_snapshot(cn_domain(ap, u, _), []),
  % p is held to p-3: the only candidate, learned as an exact pin, and
  % conceded so that no conflict about it is raised.
  cnselect:overruled_excludes(ap, p, qtest://'ap/p-2'),
  \+ cnselect:overruled_excludes(ap, p, qtest://'ap/p-3'),
  \+ cnselect:overruled_excludes(ap, u, qtest://'ap/p-2'),
  cnselect:cn_conceded(ap, p),
  prover:learned(cn_domain(ap, p, any), Pin),
  version_domain:domain_allows_candidate(Pin, qtest://'ap/p-3'),
  \+ version_domain:domain_allows_candidate(Pin, qtest://'ap/p-2'),
  % An overruled package is not offered or overruled again.
  \+ cnselect:overrule_candidates(ap, p, _),
  \+ heuristic:alternative_begin(overrule(ap, p, qtest://'ap/p-2')),
  % A proof that was not kept withdraws the hold, and with it the
  % concession and the pin: p is a package like any other again.
  heuristic:alternative_end(overrule(ap, p, qtest://'ap/p-3'), false),
  \+ cnselect:overruled_excludes(ap, p, qtest://'ap/p-2'),
  \+ memo:cn_overruled_(ap, p, _),
  \+ cnselect:cn_conceded_any(ap, p),
  prover:learned_snapshot(cn_domain(ap, p, _), []),
  cnselect:learn_cn_domain(ap, p, any, Below2, true),
  cnselect:overrule_candidates(ap, p, [_|_]).

test(kept_overrule_survives_the_next_alternative,
     [setup(alternative_setup),
      cleanup(alternative_cleanup)]) :-
  heuristic:alternative_begin(overrule(ap, p, qtest://'ap/p-3')),
  heuristic:alternative_end(overrule(ap, p, qtest://'ap/p-3'), true),
  cnselect:add_cn_domain_rejects(ap, u, none, [qtest://'ap/u-1'], true),
  heuristic:alternative_begin(overrule(ap, q, qtest://'ap/q-1')),
  \+ cnselect:cn_domain_candidate_rejected(ap, u, none, qtest://'ap/u-1'),
  cnselect:overruled_excludes(ap, p, qtest://'ap/p-2'),
  cnselect:overruled_excludes(ap, q, qtest://'ap/q-2'),
  cnselect:cn_conceded(ap, p),
  cnselect:cn_conceded(ap, q),
  prover:learned(cn_domain(ap, p, any), PinP),
  prover:learned(cn_domain(ap, q, any), _),
  % Dropping the second leaves the first as it was: held, conceded and
  % pinned.
  heuristic:alternative_end(overrule(ap, q, qtest://'ap/q-1'), false),
  \+ cnselect:overruled_excludes(ap, q, qtest://'ap/q-2'),
  \+ cnselect:cn_conceded_any(ap, q),
  prover:learned_snapshot(cn_domain(ap, q, _), []),
  cnselect:overruled_excludes(ap, p, qtest://'ap/p-2'),
  cnselect:cn_conceded(ap, p),
  prover:learned(cn_domain(ap, p, any), StillP),
  StillP == PinP.

test(overrules_are_scoped_to_the_proof,
     [setup(alternative_setup),
      cleanup(alternative_cleanup)]) :-
  heuristic:alternative_begin(overrule(ap, p, qtest://'ap/p-3')),
  heuristic:init_state,
  \+ cnselect:overruled_excludes(ap, p, qtest://'ap/p-2'),
  heuristic:alternative_begin(overrule(ap, q, qtest://'ap/q-1')),
  heuristic:cleanup_state,
  cnselect:overruled_excludes(ap, p, qtest://'ap/p-2'),
  \+ cnselect:overruled_excludes(ap, q, qtest://'ap/q-2').

test(prover_keeps_the_best_proof_when_no_alternative_is_proven,
     [setup(alternative_setup),
      cleanup(alternative_cleanup)]) :-
  Best = best(3, proof, model, cons, triggers),
  % No alternatives, none left to spend: Best stands.
  prover:prove_alternatives([], 2, t, p, m, c, tr, 20, Best, Out1),
  Out1 == Best,
  prover:prove_alternatives([overrule(ap, p, qtest://'ap/p-3')], 0, t, p, m, c, tr, 20, Best, Out2),
  Out2 == Best,
  \+ cnselect:overruled_excludes(ap, p, qtest://'ap/p-2'),
  % An alternative the domain declines costs nothing.
  prover:prove_alternatives([unknown_alternative], 1, t, p, m, c, tr, 20, Best, Out4),
  Out4 == Best.

test(prover_keeps_a_cheaper_alternative_and_goes_on_with_the_untried,
     [setup(alternative_setup),
      cleanup(alternative_cleanup)]) :-
  % Holding p leaves two assumptions, holding q as well leaves one.
  alternative_rules(( memo:cn_overruled_(ap, q, _) -> Body = [assumed(a)]
                    ; memo:cn_overruled_(ap, p, _) -> Body = [assumed(a), assumed(b)]
                    ; Body = [assumed(a), assumed(b), assumed(c)]
                    ), Body),
  Loop = best(cost(3, 0, 0, 0, 3), proof, model, cons, triggers),
  prover:with_rule_module(resolving,
    prover:prove_alternatives([overrule(ap, p, qtest://'ap/p-3'), overrule(ap, q, qtest://'ap/q-1')],
                              2, [goal], t, t, t, t, 20, Loop, best(Cost, Proof, _, _, _))),
  Cost == cost(1, 0, 0, 0, 1),
  get_assoc(rule(assumed(a)), Proof, _),
  \+ get_assoc(rule(assumed(b)), Proof, _),
  % The proof that holds p names no alternative itself (p is the only
  % package with a learned domain or a concession, and it is overruled):
  % q was still tried, on top of p.
  cnselect:overruled_excludes(ap, p, qtest://'ap/p-2'),
  cnselect:overruled_excludes(ap, q, qtest://'ap/q-2').

test(prover_drops_an_alternative_that_is_not_cheaper,
     [setup(alternative_setup),
      cleanup(alternative_cleanup)]) :-
  alternative_rules(Body = [assumed(a), assumed(b)], Body),
  Loop = best(cost(2, 0, 0, 0, 2), proof, model, cons, triggers),
  prover:with_rule_module(resolving,
    prover:prove_alternatives([overrule(ap, p, qtest://'ap/p-3')],
                              2, [goal], t, t, t, t, 20, Loop, Best)),
  % As cheap is not cheaper: the proof of the retry loop stands and the
  % hold is withdrawn.
  Best == Loop,
  \+ cnselect:overruled_excludes(ap, p, qtest://'ap/p-2').

test(prover_stops_at_a_proof_with_one_conflict,
     [setup(alternative_setup),
      cleanup(alternative_cleanup)]) :-
  alternative_rules(( memo:cn_overruled_(ap, p, _) -> Body = [assumed(a)]
                    ; Body = [assumed(a), assumed(b)]
                    ), Body),
  Loop = best(cost(2, 0, 0, 0, 2), proof, model, cons, triggers),
  prover:with_rule_module(resolving,
    prover:prove_alternatives([overrule(ap, p, qtest://'ap/p-3'), overrule(ap, q, qtest://'ap/q-1')],
                              2, [goal], t, t, t, t, 20, Loop, best(Cost, _, _, _, _))),
  Cost == cost(1, 0, 0, 0, 1),
  % One conflict left: its other side is no cheaper, q is not tried.
  \+ cnselect:overruled_excludes(ap, q, qtest://'ap/q-2').

test(alternatives_repair_conflicts_after_a_loop_that_ran_out_of_retries,
     [setup(alternative_setup),
      cleanup(alternative_cleanup)]) :-
  V2 = version([2], '', 4, 0, [], 0, '2'),
  V3 = version([3], '', 4, 0, [], 0, '3'),
  Below2 = version_domain(any, [bound(smaller, V2)]),
  Below3 = version_domain(any, [bound(smaller, V3)]),
  AboutP = cn_domain(ap, p, Below3, [qtest://'ap/p-3'], []),
  AboutQ = cn_domain(ap, q, Below2, [qtest://'ap/q-2'], []),
  % The retry loop: a conflict about p that stalls and is conceded, then
  % a conflict about q that uses up the budget, so the loop ends in its
  % final pass (reprove disabled) with two assumptions. An alternative
  % that holds p needs conflict repair to get down to one assumption:
  % proven with reprove still disabled it would end with three.
  alternative_rules(( memo:cn_overruled_(ap, p, _) ->
                        ( prover:reprove_enabled -> Body = [assumed(a)]
                        ; Body = [assumed(a), assumed(b), assumed(c)]
                        )
                    ; \+ prover:reprove_enabled ->
                        Body = [assumed(a), assumed(b)]
                    ; \+ cnselect:cn_conceded(ap, p) ->
                        cnselect:learn_cn_domain(ap, p, any, Below3, _),
                        throw(prover_reprove(AboutP))
                    ; throw(prover_reprove(AboutQ))
                    ), Body),
  % A second way to prove `goal`, never taken: as in the real rule set, a
  % completed pass leaves choicepoints behind.
  assertz(resolving:test_rule(goal, [assumed(a), assumed(b), assumed(c), assumed(d)])),
  ( prover:reprove_enabled -> Before = on ; Before = off ),
  prover:with_rule_module(resolving,
    prover:with_root_goals([goal],
      prover:with_reprove_state(
        ( prover:prove_best([goal], t, Proof, t, _, t, _, t, _, 3),
          heuristic:proof_cost(Proof, cost(Cost, _, _, _, _)),
          ( cnselect:overruled_excludes(ap, p, qtest://'ap/p-2') -> Held = true ; Held = false )
        )))),
  Cost == 1,
  Held == true,
  % The proof is over: reprove is as it was, nothing is held.
  \+ cnselect:overruled_excludes(ap, p, qtest://'ap/p-2'),
  ( prover:reprove_enabled -> After = on ; After = off ),
  After == Before.

test(alternatives_share_one_retry_budget,
     [setup(alternative_setup),
      cleanup(alternative_cleanup)]) :-
  V2 = version([2], '', 4, 0, [], 0, '2'),
  AboutU = cn_domain(ap, u, version_domain(any, [bound(smaller, V2)]), [qtest://'ap/u-1'], []),
  % Holding p meets the same conflict on every pass: rejected, conceded,
  % and then out of retries. Holding q meets it once (QRetries = 1) or
  % not at all (QRetries = 0).
  alternative_rules(( memo:cn_overruled_(ap, q, _) ->
                        ( nb_getval(alternative_q_retries, 1),
                          \+ memo:cn_domain_reject_(_, _) ->
                            throw(prover_reprove(AboutU))
                        ; Body = [assumed(a)]
                        )
                    ; memo:cn_overruled_(ap, p, _) ->
                        throw(prover_reprove(AboutU))
                    ; Body = [assumed(a), assumed(b)]
                    ), Body),
  Loop = best(cost(2, 0, 0, 0, 2), proof, model, cons, triggers),
  Alternatives = [overrule(ap, p, qtest://'ap/p-3'), overrule(ap, q, qtest://'ap/q-1')],
  % p takes the whole budget. One pass is left for q, which is enough
  % when q meets no conflict ...
  nb_setval(alternative_q_retries, 0),
  prover:with_rule_module(resolving,
    prover:prove_alternatives(Alternatives, 2, [goal], t, t, t, t, 3, Loop, best(Cost, _, _, _, _))),
  Cost == cost(1, 0, 0, 0, 1),
  % ... and not when it needs a retry.
  retractall(memo:cn_overruled_(_, _, _)),
  nb_setval(alternative_q_retries, 1),
  prover:with_rule_module(resolving,
    prover:prove_alternatives(Alternatives, 2, [goal], t, t, t, t, 3, Loop, Best)),
  Best == Loop,
  % With the budget to itself q is proven.
  retractall(memo:cn_overruled_(_, _, _)),
  prover:with_rule_module(resolving,
    prover:prove_alternatives([overrule(ap, q, qtest://'ap/q-1')], 2, [goal], t, t, t, t, 3, Loop, best(Alone, _, _, _, _))),
  Alone == cost(1, 0, 0, 0, 1).

test(error_in_an_alternative_costs_the_alternative_not_the_prove,
     [setup(alternative_setup),
      cleanup(alternative_cleanup)]) :-
  alternative_rules(( memo:cn_overruled_(ap, p, _) -> atom_length(_, _)
                    ; Body = [assumed(a), assumed(b)]
                    ), Body),
  Loop = best(cost(2, 0, 0, 0, 2), proof, model, cons, triggers),
  retractall(message:catch_log_warned('alternative proof')),
  prover:with_rule_module(resolving,
    with_output_to(string(_),
      prover:prove_alternatives([overrule(ap, p, qtest://'ap/p-3')],
                                2, [goal], t, t, t, t, 20, Loop, Best))),
  Best == Loop,
  % Reported, and the hold is withdrawn.
  message:catch_log_warned('alternative proof'),
  \+ cnselect:overruled_excludes(ap, p, qtest://'ap/p-2').

test(time_limit_and_request_exit_pass_through_an_alternative,
     [setup(alternative_setup),
      cleanup(alternative_cleanup)]) :-
  Loop = best(cost(2, 0, 0, 0, 2), proof, model, cons, triggers),
  forall(member(Ball, [time_limit_exceeded, request_exit(2)]),
         ( alternative_rules(( memo:cn_overruled_(ap, p, _) -> throw(Ball)
                             ; Body = [assumed(a), assumed(b)]
                             ), Body),
           catch(prover:with_rule_module(resolving,
                   prover:prove_alternatives([overrule(ap, p, qtest://'ap/p-3')],
                                             2, [goal], t, t, t, t, 20, Loop, _)),
                 Caught, true),
           Caught == Ball,
           % The flag of the alternative does not outlive it, and neither
           % does what the domain changed for it: the hold, the
           % concession and the pin are withdrawn before the ball leaves
           % (the second round could not begin otherwise).
           nb_getval(prover_alternative_proof, false),
           \+ memo:cn_overruled_(ap, p, _),
           \+ cnselect:cn_conceded_any(ap, p),
           prover:learned_snapshot(cn_domain(ap, p, _), [])
         )).

test(alternative_gets_no_final_pass,
     [setup(alternative_setup),
      cleanup(alternative_cleanup)]) :-
  V2 = version([2], '', 4, 0, [], 0, '2'),
  Info = cn_domain(ap, p, version_domain(any, [bound(smaller, V2)]), [qtest://'ap/p-3'], []),
  % Out of retries inside an alternative: abandoned, not finished with
  % reprove disabled.
  nb_setval(prover_alternative_proof, true),
  catch(prover:handle_reprove(t, p, _, m, _, c, _, tr, _, 20, 20, Info), Thrown, true),
  nb_setval(prover_alternative_proof, false),
  Thrown == prover_alternative_exhausted.

% Synthetic rule store: `goal` is proven by the body Goal binds Body to,
% and every assumed(_) literal is a domain assumption.
alternative_rules(Goal, Body) :-
  resolving:enable_test_rules,
  retractall(resolving:test_rule(_, _)),
  assertz(( resolving:test_rule(goal, Body) :- Goal )),
  assertz(resolving:test_rule(assumed(_), [])).

alternative_dep(Comparator, Major, package_dependency(install, no, ap, p, Comparator, Version, [], [])) :-
  atom_number(Full, Major),
  Version = version([Major], '', 4, 0, [], 0, Full).

alternative_setup :-
  memo:clear_caches,
  ( nb_current(prover_root_goals, _) -> nb_delete(prover_root_goals) ; true ),
  ( nb_current(prover_learned_constraints, _) -> nb_delete(prover_learned_constraints) ; true ),
  ( nb_current(rules_pass_learned, _) -> nb_delete(rules_pass_learned) ; true ),
  % Newest first, as the cache orders the entries of a package.
  forall(member(Name-Major, [p-3, p-2, p-1, q-2, q-1, u-1]),
         ( atom_number(Full, Major),
           atomic_list_concat(['ap/', Name, '-', Full], Id),
           assertz(cache:ordered_entry(qtest, Id, ap, Name, version([Major], '', 4, 0, [], 0, Full))),
           assertz(cache:entry_metadata(qtest, Id, slot, slot('0'))),
           assertz(cache:entry_metadata(qtest, Id, keywords, stable(amd64)))
         )),
  unittest:accept_stable_amd64.

alternative_cleanup :-
  resolving:disable_test_rules,
  unittest:restore_stable_amd64,
  forall(cache:ordered_entry(qtest, Id, ap, _, _),
         retractall(cache:entry_metadata(qtest, Id, _, _))),
  retractall(cache:ordered_entry(qtest, _, ap, _, _)),
  retractall(memo:cn_overruled_(_, _, _)),
  ( nb_current(prover_learned_constraints, _) -> nb_delete(prover_learned_constraints) ; true ),
  ( nb_current(prover_root_goals, _) -> nb_delete(prover_root_goals) ; true ),
  ( nb_current(rules_pass_learned, _) -> nb_delete(rules_pass_learned) ; true ),
  ( nb_current(prover_alternative_proof, _) -> nb_delete(prover_alternative_proof) ; true ),
  ( nb_current(alternative_q_retries, _) -> nb_delete(alternative_q_retries) ; true ),
  memo:clear_caches.

:- end_tests(alternative_proofs).
