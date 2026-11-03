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
  ( nb_current(memo_selected_cn_snap, Old) -> nb_setval(py_saved_snap, Old)
  ; nb_setval(py_saved_snap, none)
  ),
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
  ( nb_current(py_saved_snap, Saved), Saved \== none ->
      nb_setval(memo_selected_cn_snap, Saved)
  ; empty_assoc(Empty),
    nb_setval(memo_selected_cn_snap, Empty)
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
  % rdepend_collect_vbounds_for_cn, rdepend_self_use_conditional_active
  candidate:rdepend_collect_vbounds_for_cn(all_of_group([PD1]), ccat, cpkg, qtest://'ccat/cpkg-1.0', [_]),
  candidate:rdepend_collect_vbounds_for_cn(other_term, ccat, cpkg, qtest://'ccat/cpkg-1.0', []),
  candidate:rdepend_collect_vbounds_for_cn_choice_intersection([], ccat, cpkg, qtest://'ccat/cpkg-1.0', []),
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
  prover:learned(cn_domain(td, ap, any), Dom),
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
  forall(cache:ordered_entry(qtest, Id, td, _, _),
         assertz(cache:entry_metadata(qtest, Id, keywords, stable(amd64)))),
  heuristic:init_state.

tilde_pin_cleanup :-
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
  ( nb_current(prover_learned_constraints, _) -> nb_delete(prover_learned_constraints) ; true ),
  ( nb_current(prover_root_goals, _) -> nb_delete(prover_root_goals) ; true ),
  memo:clear_caches.

:- end_tests(tilde_pin_domain).
