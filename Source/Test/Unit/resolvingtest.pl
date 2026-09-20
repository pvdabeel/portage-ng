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
  \+ heuristic:restart_seed(Info, fakerepo://'cat/other-1.0':install),
  \+ heuristic:restart_seed(Info, grouped_dep(cat, pkg, []):install).

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
