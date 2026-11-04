/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> PRINTERTEST
Unit tests for plan annotation, assumption classification, and merge
printer head normalisation (Source/Pipeline/Printer/Plan/).

Blocker relevance in annotation:collect/2, the assumption polarity
table of assumption:assumption_type/2, `--fetchonly` print filtering,
and printable/render agreement across canon_literal head shapes.
Assumed live-`9999` self-install leftovers are dropped when the same
CN already has a concrete merge.
*/

:- module(printertest, []).

:- use_module(library(plunit)).
:- use_module(library(assoc)).
:- use_module(library(lists)).

% =============================================================================
%  PRINTERTEST declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Printer: blocker relevance (annotation:collect/2)
% -----------------------------------------------------------------------------
%
% Pass 1 records every weak blocker it walks past; annotation:collect/2
% keeps only those whose atom (operator / version / slot / sub-slot)
% actually hits a planned merge or an installed copy the plan leaves in
% place. `!dev-ml/findlib:0/0` against a planned findlib 0/1 and
% `!<dev-util/ragel-7.0.3` against a planned 7.0.4 must vanish from both
% the blocker section and the domain assumption list (they drove the CI
% exit code to 2 for a plan emerge accepts cleanly).

:- begin_tests(annotation_blocker_relevance).

abr_v(V) :- V = version([6,10],'',4,0,[],0,'6.10').
abr_w(V) :- V = version([7,0,4],'',4,0,[],3,'7.0.4-r3').

abr_setup :-
  abr_cleanup,
  abr_v(V6), abr_w(V7),
  assertz(cache:ordered_entry(qtest, 'abrtest/blk-6.10', abrtest, blk, V6)),
  assertz(cache:entry_metadata(qtest, 'abrtest/blk-6.10', slot, slot('0'))),
  assertz(cache:entry_metadata(qtest, 'abrtest/blk-6.10', slot, subslot('0'))),
  assertz(cache:ordered_entry(qtest, 'abrtest/blk-7.0.4-r3', abrtest, blk, V7)),
  assertz(cache:entry_metadata(qtest, 'abrtest/blk-7.0.4-r3', slot, slot('0'))),
  assertz(cache:entry_metadata(qtest, 'abrtest/blk-7.0.4-r3', slot, subslot('1'))),
  assertz(cache:ordered_entry(qtest, 'abrtest/parent-1', abrtest, parent, V6)).

abr_cleanup :-
  retractall(cache:ordered_entry(qtest, _, abrtest, _, _)),
  retractall(cache:entry_metadata(qtest, 'abrtest/blk-6.10', _, _)),
  retractall(cache:entry_metadata(qtest, 'abrtest/blk-7.0.4-r3', _, _)),
  abr_vdb_cleanup.

% Installed copy lives in the active VDB repository (in-memory only).
abr_vdb_setup :-
  abr_setup,
  abr_v(V6),
  knowledgebase:vdb_repository(Vdb),
  assertz(cache:ordered_entry(Vdb, 'abrtest/blk-6.10', abrtest, blk, V6)),
  assertz(cache:entry_metadata(Vdb, 'abrtest/blk-6.10', slot, slot('0'))),
  assertz(cache:entry_metadata(Vdb, 'abrtest/blk-6.10', slot, subslot('0'))).

abr_vdb_cleanup :-
  knowledgebase:vdb_repository(Vdb),
  retractall(cache:ordered_entry(Vdb, _, abrtest, _, _)),
  retractall(cache:entry_metadata(Vdb, 'abrtest/blk-6.10', _, _)).

% Weak blocker recorded by abrtest/parent-1 against abrtest/blk.
abr_blocker(O, V, SlotReq, Content) :-
  Content = blocker(weak, run, abrtest, blk, O, V, SlotReq)?{[self(qtest://'abrtest/parent-1')]}.

abr_proof(Planned, Content, Proof) :-
  findall(rule(qtest://E:A)-(dep(_,[])?{[]}), member(E:A, Planned), Steps),
  list_to_assoc([rule(assumed(Content))-(dep(_,[])?{[]})|Steps], Proof).

abr_reported(Proof, Content) :-
  annotation:collect(Proof, Ann),
  annotation:domain_assumptions(Ann, Domain),
  memberchk(Content, Domain),
  annotation:blocker_notes(Ann, Notes),
  get_assoc(key(abrtest, blk, run), Notes, note(weak, qtest://'abrtest/parent-1')).

abr_silent(Proof, Content) :-
  annotation:collect(Proof, Ann),
  annotation:domain_assumptions(Ann, Domain),
  \+ memberchk(Content, Domain),
  annotation:blocker_notes(Ann, Notes),
  \+ get_assoc(key(abrtest, blk, _), Notes, _).

% `!<abrtest/blk-7.0.3` with blk-6.10 planned: a real conflict, reported.
test(planned_version_inside_blocker_range_is_reported,
     [setup(abr_setup), cleanup(abr_cleanup)]) :-
  abr_blocker(smaller, version([7,0,3],'',4,0,[],0,'7.0.3'), [], Content),
  abr_proof(['abrtest/blk-6.10':install, 'abrtest/parent-1':install], Content, Proof),
  abr_reported(Proof, Content).

% `!<abrtest/blk-7.0.3` with blk-7.0.4-r3 planned: blocks nothing.
test(planned_version_outside_blocker_range_is_silent,
     [setup(abr_setup), cleanup(abr_cleanup)]) :-
  abr_blocker(smaller, version([7,0,3],'',4,0,[],0,'7.0.3'), [], Content),
  abr_proof(['abrtest/blk-7.0.4-r3':install, 'abrtest/parent-1':install], Content, Proof),
  abr_silent(Proof, Content).

% `!abrtest/blk:0/0` with blk 0/1 planned: sub-slot mismatch, silent
% (the findlib case). Same atom against planned 0/0: reported.
test(subslot_mismatch_is_silent,
     [setup(abr_setup), cleanup(abr_cleanup)]) :-
  abr_blocker(none, version_none, [slot('0'), subslot('0')], Content),
  abr_proof(['abrtest/blk-7.0.4-r3':install, 'abrtest/parent-1':install], Content, Proof),
  abr_silent(Proof, Content).

test(subslot_match_is_reported,
     [setup(abr_setup), cleanup(abr_cleanup)]) :-
  abr_blocker(none, version_none, [slot('0'), subslot('0')], Content),
  abr_proof(['abrtest/blk-6.10':install, 'abrtest/parent-1':install], Content, Proof),
  abr_reported(Proof, Content).

% Nothing of abrtest/blk planned or installed: silent.
test(unplanned_uninstalled_blocked_cn_is_silent,
     [setup(abr_setup), cleanup(abr_cleanup)]) :-
  abr_blocker(none, version_none, [], Content),
  abr_proof(['abrtest/parent-1':install], Content, Proof),
  abr_silent(Proof, Content).

% Installed blk-6.10 matches `!<abrtest/blk-7.0.3` and the plan leaves
% it alone: reported. When the plan replaces it (same slot) with a
% non-matching 7.0.4-r3, or unmerges it, the plan resolves the blocker.
test(installed_copy_left_in_place_is_reported,
     [setup(abr_vdb_setup), cleanup(abr_cleanup)]) :-
  abr_blocker(smaller, version([7,0,3],'',4,0,[],0,'7.0.3'), [], Content),
  abr_proof(['abrtest/parent-1':install], Content, Proof),
  abr_reported(Proof, Content).

test(installed_copy_replaced_by_plan_is_silent,
     [setup(abr_vdb_setup), cleanup(abr_cleanup)]) :-
  abr_blocker(smaller, version([7,0,3],'',4,0,[],0,'7.0.3'), [], Content),
  abr_proof(['abrtest/blk-7.0.4-r3':update, 'abrtest/parent-1':install], Content, Proof),
  abr_silent(Proof, Content).

test(installed_copy_unmerged_by_plan_is_silent,
     [setup(abr_vdb_setup), cleanup(abr_cleanup)]) :-
  abr_blocker(smaller, version([7,0,3],'',4,0,[],0,'7.0.3'), [], Content),
  abr_proof(['abrtest/blk-6.10':uninstall, 'abrtest/parent-1':install], Content, Proof),
  abr_silent(Proof, Content).

test(legacy_build_with_use_proof_key_use_changes,
     [setup(abr_setup), cleanup(abr_cleanup),
      true(Bwu == [use_change(qtest://'abrtest/blk-6.10', [custom_en], [])])]) :-
  Key = qtest://'abrtest/blk-6.10':install?{[build_with_use:use_state([custom_en], [custom_dis])]},
  list_to_assoc([Key-(dep(_,[])?{[]})], Proof),
  annotation:collect(Proof, Ann),
  annotation:bwu_changes(Ann, Bwu).

:- end_tests(annotation_blocker_relevance).


% -----------------------------------------------------------------------------
%  Model-unavailable assumption (not assumed self-install)
% -----------------------------------------------------------------------------
%
% When install_dep_model fails, resolve assumes issue_with_model(Entry),
% not the :install goal it is proving. That leftover stays in the
% domain-assumption list and prints as "model unavailable" even when
% the same CN is already planned — hiding it was a printer bandaid.

:- begin_tests(annotation_model_unavailable).

amu_entry(qtest://'dev-vcs/mercurial-9999').
amu_ver(version([9999],'',4,0,[],0,'9999')).
amu_assumed(issue_with_model(qtest://'dev-vcs/mercurial-9999')?{[issue_with_model(explanation)]}).

amu_setup :-
  amu_cleanup,
  amu_entry(Repo://Id),
  amu_ver(V),
  assertz(cache:ordered_entry(Repo, Id, 'dev-vcs', mercurial, V)).

amu_cleanup :-
  amu_entry(Repo://Id),
  retractall(cache:ordered_entry(Repo, Id, _, _, _)).

amu_proof(Steps, Content, Proof) :-
  findall(rule(qtest://E:A)-(dep(_,[])?{[]}), member(E:A, Steps), Planned),
  list_to_assoc([rule(assumed(Content))-(dep(_,[])?{[]})|Planned], Proof).

amu_state(Plan, State) :-
  empty_assoc(Notes),
  plan:build_planned_pkg_set(Plan, Set),
  State = ps([], Notes, Set).

test(domain_keeps_model_unavailable_when_cn_planned,
     [setup(amu_setup), cleanup(amu_cleanup)]) :-
  amu_assumed(Content),
  amu_proof(['dev-vcs/mercurial-9999':install], Content, Proof),
  annotation:collect(Proof, Ann),
  annotation:domain_assumptions(Ann, Domain),
  memberchk(Content, Domain).

test(verify_shows_model_unavailable_when_install_planned,
     [setup(amu_setup), cleanup(amu_cleanup)]) :-
  amu_entry(Repo://Id),
  Plan = [[rule(Repo://Id:install?{[]}, [])]],
  amu_state(Plan, State),
  Rule = rule(assumed(issue_with_model(Repo://Id)?{[issue_with_model(explanation)]}), []),
  plan:printable_element(State, Rule).

test(does_not_hide_assumed_install_when_cn_planned,
     [setup(amu_setup), cleanup(amu_cleanup)]) :-
  amu_entry(Repo://Id),
  Plan = [[rule(Repo://Id:install?{[]}, [])]],
  amu_state(Plan, State),
  Rule = rule(assumed(Repo://Id:install?{[issue_with_model(explanation)]}), []),
  plan:printable_element(State, Rule).

:- end_tests(annotation_model_unavailable).


% -----------------------------------------------------------------------------
%  Assumption classification: polarity table (issue #73)
% -----------------------------------------------------------------------------
%
% Table-driven tests for assumption:assumption_type/2 and
% assumption:assumption_reason_type/2, organized by the polarity taxonomy
% from the project rules:
%   - positive / actionable: a config change resolves the plan
%     (unmask, accept ~arch, accept license, resolve blocker)
%   - negative / blocking: structurally unsatisfiable as stated
%   - cycle axis: prover cycle-breaks, a separate benign axis
%   - info: bookkeeping types (assumed installed/running)

:- begin_tests(assumption_polarity).

% assumption_type_vector(Polarity, Term, ExpectedType)

% POSITIVE / actionable
assumption_type_vector(positive,
  portage://'app-misc/x-1.0':unmask,
  masked).
assumption_type_vector(positive,
  grouped_package_dependency(no, 'dev-libs', foo, []):install?{[assumption_reason(masked)]},
  masked_dependency).
assumption_type_vector(positive,
  grouped_package_dependency(no, 'dev-libs', foo, []):install?{[assumption_reason(keyword_filtered)]},
  keyword_filtered_dependency).
assumption_type_vector(positive,
  blocker(weak, run, 'app-misc', x, none, version_none, []),
  blocker_assumption).

% NEGATIVE / blocking
assumption_type_vector(negative,
  grouped_package_dependency(no, 'dev-libs', foo, []):install,
  non_existent_dependency).
assumption_type_vector(negative,
  package_dependency(install, no, 'dev-libs', foo, none, version_none, [], []):install,
  non_existent_dependency).
assumption_type_vector(negative,
  grouped_package_dependency(no, 'dev-libs', foo, []):install?{[assumption_reason(missing)]},
  missing_dependency).
assumption_type_vector(negative,
  grouped_package_dependency(no, 'dev-libs', foo, []):install?{[assumption_reason(version_no_candidate(any, []))]},
  version_no_candidate_dependency).
assumption_type_vector(negative,
  grouped_package_dependency(no, 'dev-libs', foo, []):install?{[assumption_reason(version_conflict(x))]},
  version_conflict_dependency).
assumption_type_vector(negative,
  grouped_package_dependency(no, 'dev-libs', foo, []):install?{[assumption_reason(unsatisfied_constraints)]},
  unsatisfied_constraints_dependency).
assumption_type_vector(negative,
  grouped_package_dependency(no, 'acct-user', git, []):install?{[required_use_violation(use_dep_unsat(x, use_state([gitea], []), profile_hard_conflict))]},
  use_dep_unsat).
assumption_type_vector(negative,
  issue_with_model(portage://'app-misc/x-1.0')?{[issue_with_model(explanation)]},
  issue_with_model).
assumption_type_vector(negative,
  issue_with_model(portage://'app-misc/x-1.0'),
  issue_with_model).

% CYCLE axis (benign, separate from domain assumptions)
assumption_type_vector(cycle, cycle_break(foo),                                cycle_break).
assumption_type_vector(cycle, required(flag),                                  use_requirement_cycle).
assumption_type_vector(cycle, blocking(flag),                                  use_requirement_cycle).
assumption_type_vector(cycle, use_conditional_group(positive, f, portage://'a/b-1', []),
                              use_conditional_cycle).
assumption_type_vector(cycle, any_of_group([]),                                dependency_group_cycle).
assumption_type_vector(cycle, all_of_group([]),                                dependency_group_cycle).
assumption_type_vector(cycle, exactly_one_of_group([]),                        dependency_group_cycle).
assumption_type_vector(cycle, at_most_one_of_group([]),                        dependency_group_cycle).
assumption_type_vector(cycle, naf(foo),                                        naf_cycle).

% INFO (bookkeeping). Note: grouped_package_dependency(_,_,_,_):install/run
% classify as non_existent_dependency (the arity-4 catch-all precedes the
% action-specific clauses in assumption.pl), so only the concrete
% R://Entry:Action forms are info-classified.
assumption_type_vector(info, portage://'app-misc/x-1.0':install,               assumed_installed).
assumption_type_vector(info, portage://'app-misc/x-1.0':run,                   assumed_running).

% Catch-all
assumption_type_vector(other, completely_unknown_term(42),                     other).

check_assumption_vectors(Polarity) :-
  forall(assumption_type_vector(Polarity, Term, Expected),
         ( assumption:assumption_type(Term, Got),
           Got == Expected )).

test(positive_actionable_vectors) :- check_assumption_vectors(positive).
test(negative_blocking_vectors)   :- check_assumption_vectors(negative).
test(cycle_axis_vectors)          :- check_assumption_vectors(cycle).
test(info_vectors)                :- check_assumption_vectors(info).
test(other_fallthrough_vector)    :- check_assumption_vectors(other).

% Classification is total and deterministic over all table entries.
test(assumption_type_deterministic) :-
  forall(assumption_type_vector(_, Term, _),
         ( findall(T, assumption:assumption_type(Term, T), [_]) )).

% assumption_reason_type/2: full reason -> bucket table.
test(assumption_reason_type_table) :-
  forall(member(Reason-Type,
                [ missing                      - missing_dependency,
                  masked                       - masked_dependency,
                  keyword_filtered             - keyword_filtered_dependency,
                  installed_required           - installed_required_dependency,
                  slot_unsatisfied             - slot_unsatisfied_dependency,
                  version_no_candidate(any,[]) - version_no_candidate_dependency,
                  version_no_candidate         - version_no_candidate_dependency,
                  version_conflict(x)          - version_conflict_dependency,
                  version_conflict             - version_conflict_dependency,
                  version_unsatisfied          - version_no_candidate_dependency,
                  unsatisfied_constraints      - unsatisfied_constraints_dependency,
                  no_tree_ebuild               - no_tree_ebuild ]),
         ( assumption:assumption_reason_type(Reason, Got),
           Got == Type )).

% Unknown reasons have no bucket (callers fall back explicitly).
test(assumption_reason_type_unknown_fails, [fail]) :-
  assumption:assumption_reason_type(no_such_reason, _).

:- end_tests(assumption_polarity).


% -----------------------------------------------------------------------------
%  Fetchonly print filter
% -----------------------------------------------------------------------------
%
% `--fetchonly` proves :run, then hides merge-phase actions from the
% printed plan and footer. Downloads stay visible.

:- begin_tests(fetchonly_print_filter).

fo_cleanup :-
  retractall(preference:local_flag(fetchonly)),
  retractall(preference:scoped_flag(fetchonly)).

test(hides_install,
     [setup(fo_cleanup), cleanup(fo_cleanup)]) :-
  preference:with_local_flag(fetchonly,
    \+ plan:printable_element(_, rule(r://'p-1':install?{[]}, []))).

test(hides_run,
     [setup(fo_cleanup), cleanup(fo_cleanup)]) :-
  preference:with_local_flag(fetchonly,
    \+ plan:printable_element(_, rule(r://'p-1':run?{[]}, []))).

test(keeps_download,
     [setup(fo_cleanup), cleanup(fo_cleanup)]) :-
  preference:with_local_flag(fetchonly,
    plan:printable_element(_, rule(r://'p-1':download?{[]}, []))).

test(merge_still_prints_install,
     [setup(fo_cleanup), cleanup(fo_cleanup)]) :-
  plan:printable_element(_, rule(r://'p-1':install?{[]}, [])).

test(footer_omits_merge_actions,
     [setup(fo_cleanup), cleanup(fo_cleanup)]) :-
  Plan = [[rule(r://'p-1':download?{[]}, []),
           rule(r://'p-1':install?{[]}, []),
           rule(r://'p-1':run?{[]}, [])]],
  preference:with_local_flag(fetchonly,
    plan:footer_stats_from_plan(Plan, S)),
  S.downloads == 1,
  S.installs == 0,
  S.runs == 0,
  S.actions == 1.

test(scoped_flag_is_thread_local,
     [setup(fo_cleanup), cleanup(fo_cleanup)]) :-
  message_queue_create(Q),
  thread_create(
    preference:with_local_flag(fetchonly,
      ( thread_send_message(Q, inside),
        thread_get_message(Q, done)
      )),
    Id, []),
  thread_get_message(Q, inside),
  plan:printable_element(_, rule(r://'p-1':install?{[]}, [])),
  thread_send_message(Q, done),
  thread_join(Id, true),
  message_queue_destroy(Q).

:- end_tests(fetchonly_print_filter).


% -----------------------------------------------------------------------------
%  Printer: plan-rule head shapes
% -----------------------------------------------------------------------------
%
% The merge printer used to require a rigid `Repo://Entry:Action?{Ctx}`
% functor. Footer stats and the Gantt chart already go through
% prover:canon_literal/3, so context-free and double-wrapped heads were
% counted (and drawn) but not rendered — docker-29.8.0-merge.html showed
% 57 actions grouped into 2 steps. These tests lock the printer to the
% same head normalisation.

:- begin_tests(printer_plan_head_shapes).

printer_empty_state(ps([], Notes, Set)) :-
  empty_assoc(Notes),
  empty_assoc(Set).

phs_fo_cleanup :-
  retractall(preference:local_flag(fetchonly)),
  retractall(preference:scoped_flag(fetchonly)).

test(printable_context_free_install) :-
  printer_empty_state(State),
  Rule = rule(portage://'dev-libs/jansson-2.15.1':install, []),
  plan:printable_element(State, Rule).

test(printable_double_wrapped_install) :-
  printer_empty_state(State),
  Inner = [self(portage://'app-containers/docker-29.8.0')],
  Outer = [slot(0, none, [slot('0')]):{portage://'dev-libs/jansson-2.15.1'}],
  Head = portage://(('dev-libs/jansson-2.15.1':install?{Inner})?{Outer}),
  Rule = rule(Head, []),
  plan:printable_element(State, Rule).

test(printable_parenthesized_install) :-
  printer_empty_state(State),
  Rule = rule(portage://('dev-libs/jansson-2.15.1':install?{[]}), []),
  plan:printable_element(State, Rule).

test(printable_context_free_update) :-
  printer_empty_state(State),
  Rule = rule(portage://'dev-python/installer-1.0.1':update, []),
  plan:printable_element(State, Rule).

test(printable_context_free_run) :-
  printer_empty_state(State),
  Rule = rule(portage://'dev-libs/jansson-2.15.1':run, []),
  plan:printable_element(State, Rule).

test(wrapper_update_still_hidden) :-
  printer_empty_state(State),
  Chosen = portage://'dev-python/installer-1.0.1':update?{[]},
  Wrapper = rule(portage://'dev-python/installer-0.7.0':update?{[]}, [Chosen]),
  \+ plan:printable_element(State, Wrapper).

test(wrapper_update_hidden_context_free_body) :-
  printer_empty_state(State),
  Chosen = portage://'dev-python/installer-1.0.1':update,
  Wrapper = rule(portage://'dev-python/installer-0.7.0':update, [Chosen]),
  \+ plan:printable_element(State, Wrapper).

test(element_kind_context_free_install) :-
  plan:element_kind(rule(portage://'dev-libs/jansson-2.15.1':install, []), install).

test(fetchonly_hides_context_free_install,
     [setup(phs_fo_cleanup), cleanup(phs_fo_cleanup)]) :-
  preference:with_local_flag(fetchonly,
    \+ plan:printable_element(_, rule(portage://'p-1':install, []))).

test(print_steps_counts_context_free_wave) :-
  printer_empty_state(State),
  Step1 = [rule(r://'docker-0-r3':install?{[]}, [])],
  Step2 = [rule(r://'jansson-2.15.1':install, []),
           rule(r://'libnftnl-1.3.2':install, [])],
  with_output_to(string(_),
                 plan:print_steps_in_plan(State, [Step1, Step2], plan:dry_run, 0, Steps)),
  Steps == 2.

test(print_steps_counts_double_wrapped_later_waves) :-
  printer_empty_state(State),
  Inner = [self(r://'docker-29.8.0')],
  Head = r://(('libnftnl-1.3.2':install?{Inner})?{[]}),
  Step1 = [rule(r://'jansson-2.15.1':install?{[]}, [])],
  Step2 = [rule(Head, [])],
  with_output_to(string(Out),
                 plan:print_steps_in_plan(State, [Step1, Step2], plan:dry_run, 0, Steps)),
  Steps == 2,
  once(sub_string(Out, _, _, _, 'libnftnl-1.3.2')).

test(footer_and_printer_agree_on_mixed_heads) :-
  printer_empty_state(State),
  Plan = [[rule(r://'jansson-2.15.1':download?{[]}, []),
           rule(r://'jansson-2.15.1':install, []),
           rule(r://'jansson-2.15.1':run, [])]],
  plan:footer_stats_from_plan(Plan, S),
  S.actions =:= 3,
  with_output_to(string(Out),
                 plan:print_steps_in_plan(State, Plan, plan:dry_run, 0, Steps)),
  Steps == 1,
  once(sub_string(Out, _, _, _, 'download')),
  once(sub_string(Out, _, _, _, 'install')),
  once(sub_string(Out, _, _, _, 'run')).

% Pass-1 dependency-group rules ride along in the plan waves. They are
% not merge actions: printing them (or failing to) produced empty `│`
% rows and empty steps after the docker-29.8.0 head-shape widening.
test(regular_grouped_dep_not_printable) :-
  printer_empty_state(State),
  Rule = rule(grouped_package_dependency(no, 'dev-libs', jansson, []):install?{[]}, []),
  \+ plan:printable_element(State, Rule).

test(regular_package_dep_not_printable) :-
  printer_empty_state(State),
  Rule = rule(package_dependency(install, no, 'dev-libs', jansson,
                                none, version_none, [], []):install?{[]}, []),
  \+ plan:printable_element(State, Rule).

test(assumed_grouped_dep_still_printable) :-
  printer_empty_state(State),
  Rule = rule(assumed(grouped_package_dependency(no, 'dev-libs', missing, []):install?{[assumption_reason(masked)]}), []),
  plan:printable_element(State, Rule).

test(grouped_deps_do_not_emit_blank_rows_or_empty_steps) :-
  printer_empty_state(State),
  Grouped = rule(grouped_package_dependency(no, 'dev-libs', jansson, []):install?{[]}, []),
  Plan = [[Grouped, Grouped],
          [rule(r://'jansson-2.15.1':download?{[]}, []),
           Grouped,
           rule(r://'jansson-2.15.1':install, [])]],
  with_output_to(string(Out),
                 plan:print_steps_in_plan(State, Plan, plan:dry_run, 0, Steps)),
  Steps == 1,
  findall(_, sub_string(Out, _, _, _, '             │ '), Prefs),
  length(Prefs, 1).

:- end_tests(printer_plan_head_shapes).


% -----------------------------------------------------------------------------
%  Full Printer/Plan coverage: assumption, removal, timing, cycle, useflags,
%  warning, and plan
% -----------------------------------------------------------------------------

:- begin_tests(printer_plan_full_coverage).

test(assumption_removal_and_timing_helpers, [nondet]) :-
  % assumption.pl remaining clauses
  assumption:assumption_type('?'(portage://'a/b-1.0':unmask, non_curly_ctx), masked),
  assumption:assumption_type(domain(grouped_package_dependency(no, c, n, []):install?{[assumption_reason(missing)]}),
                             missing_dependency),
  assumption:assumption_type(domain(portage://'a/b-1.0':install), assumed_installed),
  assumption:assumption_type(unreachable(a, b), unreachable),
  assumption:assumption_type(grouped_package_dependency(c, n, []):install, non_existent_dependency),
  forall(member(PkgTerm, [r://e:install, r://e:run, r://e:fetchonly, r://e:unmask,
                          issue_with_model(r://e),
                          grouped_package_dependency(no, c, n, []):install,
                          package_dependency(install, no, c, n, none, version_none, [], []):install]),
         assumption:assumption_is_package_level(PkgTerm)),
  assumption:assumption_head_term(_Unbound, _),
  assumption:assumption_head_key(domain(cycle_break(r://(e:install?{[a]}))), install),
  assumption:assumption_head_key(grouped_package_dependency(no, c, n, []), 'grouped_package_dependency/4'),
  assumption:unwrap_ctx_wrappers('?'('?'(core_lit, [a]), [b]), core_lit),
  assumption:collect_ctx_tags('?'('?'(core_lit, {[a]}), [b]), [b, a]),
  assumption:ctx_term_to_list(non_list_non_curly, []),
  list_to_assoc([(r://a:install)-[r://b:install],
                 (r://b:install)-[r://a:install]], CycTriggers),
  assumption:cycle_for_assumption(cycle_break(r://a:install), CycTriggers, _, _),
  % removal.pl & timing.pl
  removal:pkg_label(non_repo_term, 'non_repo_term'),
  with_output_to(string(_),
    ( removal:print_uninstall_order([]),
      removal:print_retained_claim(r://a, r://b),
      timing:print_timing_header('Merge', 1700000000.0),
      timing:print_timing_footer('Merge', 1700000000.0)
    )).

test(cycle_module_full_coverage,
     [nondet,
      setup(( V1 = version([1,0], '', 4, 0, [], 0, '1.0'),
              assertz(cache:ordered_entry(qtest, 'cyccat/cyca-1.0', cyccat, cyca, V1)),
              assertz(cache:ordered_entry(qtest, 'cyccat/cycb-1.0', cyccat, cycb, V1)),
              LeafB = package_dependency(install, no, cyccat, cycb, none, version_none, [], []),
              LeafA = package_dependency(install, no, cyccat, cyca, none, version_none, [], []),
              Tree1 = (use_conditional_group(positive, fa, qtest://'cyccat/cyca-1.0',
                         [use_conditional_group(negative, fb, qtest://'cyccat/cyca-1.0',
                            [any_of_group([all_of_group([exactly_one_of_group([at_most_one_of_group([
                               grouped_package_dependency(cyccat, cycb, [LeafB]),
                               grouped_package_dependency(no, cyccat, cycb, [LeafB])
                             ])])])])])]):install?{[]}),
              assertz(cache:entry_metadata(qtest, 'cyccat/cyca-1.0', depend, Tree1)),
              assertz(cache:entry_metadata(qtest, 'cyccat/cycb-1.0', rdepend, LeafA)) )),
      cleanup(( retractall(cache:ordered_entry(qtest, _, cyccat, _, _)),
                retractall(cache:entry_metadata(qtest, 'cyccat/cyca-1.0', _, _)),
                retractall(cache:entry_metadata(qtest, 'cyccat/cycb-1.0', _, _)) ))]) :-
  AKey = (qtest://'cyccat/cyca-1.0':install),
  BKey = (qtest://'cyccat/cycb-1.0':install),
  GDepB = (grouped_package_dependency(no, cyccat, cycb,
             [package_dependency(install, no, cyccat, cycb, none, version_none, [], [])]):install),
  GDepA = (grouped_package_dependency(no, cyccat, cyca,
             [package_dependency(install, no, cyccat, cyca, none, version_none, [], [])]):install),
  RawPath = [AKey, GDepA, BKey, GDepB, AKey],
  list_to_assoc([cycle_path(AKey)-RawPath,
                 rule(AKey)-(dep(1, [BKey])?[]),
                 assumed(rule(BKey))-(dep(1, [AKey])?[])], ProofAVL),
  list_to_assoc([AKey-[GDepA],
                 GDepA-[BKey],
                 BKey-[GDepB],
                 GDepB-[AKey],
                 mid1-[mid2],
                 mid2-[AKey]], TriggersAVL),
  % recorded_cycle_path & search_cycle_path variants
  cycle:recorded_cycle_path(AKey, ProofAVL, RawPath, DispPath),
  DispPath \== [],
  empty_assoc(EmptyAssoc),
  cycle:search_cycle_path(AKey, ProofAVL, TriggersAVL, _, _),
  cycle:search_cycle_path(AKey, ProofAVL, EmptyAssoc, _, _),
  cycle:find_cycle_via_triggers(AKey, TriggersAVL, _),
  cycle:find_cycle_via_triggers(mid1, TriggersAVL, _),
  % cycle_start_pkg_key (direct, 1-hop, 2-hop)
  cycle:cycle_start_pkg_key(AKey, TriggersAVL, AKey),
  cycle:cycle_start_pkg_key(GDepB, TriggersAVL, AKey),
  cycle:cycle_start_pkg_key(mid1, TriggersAVL, AKey),
  % cycle_dep_leaf, cycle_pkg_repo_entry, cycle_pkg_cat_name, cycle_edges_from_raw
  cycle:cycle_pkg_repo_entry(qtest://'cyccat/cyca-1.0', qtest://'cyccat/cyca-1.0', unknown),
  cycle:cycle_pkg_cat_name(qtest://'cyccat/cyca-1.0':install, cyccat, cyca),
  cycle:cycle_pkg_cat_name(qtest://'unknown_cat/unknown_pkg-1.0':install, unknown_cat, _),
  cycle:cycle_pkg_cat_name(qtest://'cyccat/cyca-1.0', cyccat, cyca),
  cycle:cycle_pkg_cat_name(qtest://'unknown_cat/unknown_pkg-1.0', unknown_cat, _),
  PDepPlain = package_dependency(install, no, cyccat, cycb, none, version_none, [], []),
  cycle:cycle_dep_leaf(PDepPlain:install, AKey, _),
  cycle:cycle_dep_leaf(PDepPlain, AKey, _),
  cycle:cycle_edges_from_raw([], []),
  cycle:cycle_edges_from_raw([a], []),
  cycle:cycle_edges_from_raw([a, b], []),
  cycle:cycle_edges_from_raw([non_pkg, AKey, GDepA, BKey], [edge(AKey, GDepA, BKey)]),
  % cycle_node_parts, cycle_node_package_key, dedup_consecutive, term_visible_length
  cycle:cycle_node_parts(grouped(c, n):install, 'c/n (group)', install),
  cycle:cycle_node_parts(qtest://'c/n-1':install, 'c/n-1', install),
  cycle:cycle_node_parts(qtest://'c/n-1', 'c/n-1', unknown),
  cycle:cycle_node_parts('c/n-1':install, 'c/n-1', install),
  cycle:cycle_node_parts('c/n-1', 'c/n-1', unknown),
  cycle:cycle_node_package_key((qtest://('c/n-1':install?{[x]}))?{[y]}, qtest://'c/n-1':install),
  cycle:cycle_node_package_key(qtest://'c/n-1', qtest://'c/n-1'),
  cycle:cycle_node_package_key(qtest://('c/n-1':install), qtest://'c/n-1':install),
  cycle:cycle_node_package_key(GDepA, grouped(cyccat, cyca):install),
  cycle:cycle_node_package_key(bare_pkg:install, bare_pkg:install),
  cycle:dedup_consecutive([x, x], [x, x]),
  cycle:dedup_consecutive([], []),
  cycle:dedup_consecutive([a, a, b, b, c], [a, b, c]),
  cycle:term_visible_length(compound_term(1), _),
  cycle:cycle_tree_parts([AKey, BKey], _),
  with_output_to(string(_),
    ( cycle:print_cycle_explanation(AKey, ProofAVL, TriggersAVL),
      cycle:print_cycle_explanation(AKey, TriggersAVL),
      cycle:print_cycle_explanation(not_an_action_key, ProofAVL, TriggersAVL),
      cycle:print_cycle_outcome(found([], [])),
      cycle:print_cycle_outcome(budget_exhausted),
      cycle:print_cycle_outcome(not_found),
      cycle:print_cycle_tree([]),
      cycle:print_cycle_tree([AKey]),
      cycle:print_cycle_tree([AKey, BKey, AKey]),
      list_to_assoc([BKey-'fa'], GuardMap1),
      cycle:print_cycle_tree([AKey, BKey, AKey], GuardMap1)
    )).

test(useflags_module_full_coverage,
     [setup(( V1 = version([1,0], '', 4, 0, [], 0, '1.0'),
              knowledgebase:vdb_repository(Vdb),
              assertz(cache:ordered_entry(Vdb, 'ufcat/ufpkg-1.0', ufcat, ufpkg, V1)),
              assertz(cache:entry_metadata(Vdb, 'ufcat/ufpkg-1.0', slot, slot('1'))),
              assertz(cache:entry_metadata(Vdb, 'ufcat/ufpkg-1.0', iuse, fa)),
              assertz(cache:entry_metadata(Vdb, 'ufcat/ufpkg-1.0', iuse, fb)),
              assertz(cache:entry_metadata(Vdb, 'ufcat/ufpkg-1.0', use, fb)),
              assertz(cache:ordered_entry(qtest, 'ufcat/ufpkg-1.0', ufcat, ufpkg, V1)),
              assertz(cache:entry_metadata(qtest, 'ufcat/ufpkg-1.0', slot, slot('1'))),
              assertz(cache:entry_metadata(qtest, 'ufcat/ufpkg-1.0', slot, subslot('2'))),
              assertz(cache:entry_metadata(qtest, 'ufcat/ufpkg-1.0', iuse, plus(fa))),
              assertz(cache:entry_metadata(qtest, 'ufcat/ufpkg-1.0', iuse, fb)),
              assertz(cache:entry_metadata(qtest, 'ufcat/ufpkg-1.0', iuse, fc)),
              assertz(cache:entry_metadata(qtest, 'ufcat/ufpkg-1.0', iuse, llvm_slot_20)),
              assertz(cache:entry_metadata(qtest, 'ufcat/ufpkg-1.0', src_uri,
                                           uri(https, 'example.com/a.tar.gz', 'a.tar.gz'))),
              assertz(cache:entry_metadata(qtest, 'ufcat/ufpkg-1.0', src_uri,
                                           uri(https, 'example.com/b.tar.gz', 'b.tar.gz'))),
              assertz(cache:manifest(qtest, m_uf, 0, ufcat, ufpkg)),
              assertz(cache:manifest_metadata(qtest, m_uf, dist, 'a.tar.gz', 100, [])),
              assertz(cache:manifest_metadata(qtest, m_uf, dist, 'b.tar.gz', 200, [])),
              assertz(cache:ordered_entry(qtest, 'ufcat/live-9999', ufcat, live, V1)),
              assertz(cache:entry_metadata(qtest, 'ufcat/live-9999', properties, live)),
              assertz(cache:entry_metadata(qtest, 'ufcat/live-9999', slot, slot('2'))),
              assertz(profile:use_description(fa, 'Feature A description')),
              assertz(config:show_use_descriptions(all)),
              memo:clear_caches )),
      cleanup(( knowledgebase:vdb_repository(Vdb),
                retractall(cache:ordered_entry(Vdb, 'ufcat/ufpkg-1.0', _, _, _)),
                retractall(cache:entry_metadata(Vdb, 'ufcat/ufpkg-1.0', _, _)),
                retractall(cache:ordered_entry(qtest, _, ufcat, _, _)),
                retractall(cache:entry_metadata(qtest, 'ufcat/ufpkg-1.0', _, _)),
                retractall(cache:entry_metadata(qtest, 'ufcat/live-9999', _, _)),
                retractall(cache:manifest(qtest, m_uf, _, _, _)),
                retractall(cache:manifest_metadata(qtest, m_uf, _, _, _, _)),
                retractall(profile:use_description(fa, _)),
                retractall(config:show_use_descriptions(_)),
                retractall(config:color_palette(easy)),
                memo:clear_caches ))]) :-
  RE = qtest://'ufcat/ufpkg-1.0',
  with_output_to(string(_),
    ( % print_config_prefix/1,2 for fancy, short, column
      forall(member(St, [fancy, short, column]),
             ( useflags:print_config_prefix(St),
               forall(member(W, [file, live, conf]),
                      useflags:print_config_prefix(St, W))
             )),
      % print_config for all actions & styles
      useflags:print_config(fancy, qtest://'ufcat/live-9999':fetchonly?{[]}),
      useflags:print_config(fancy, qtest://'ufcat/ufpkg-1.0':fetchonly?{[]}),
      useflags:print_config(fancy, qtest://'ufcat/live-9999':download?{[]}),
      useflags:print_config(fancy, qtest://'ufcat/live-9999':install?{[]}),
      useflags:print_config(fancy, qtest://'ufcat/ufpkg-1.0':download?{[]}),
      useflags:print_config(fancy, qtest://'ufcat/ufpkg-1.0':install?{[required_use([assumed(fa)]),
                                                suggestion(use_change, RE,
                                                  [use_change(llvm_slot_20, enable),
                                                   use_change(llvm_slot_20, disable)])]}),
      useflags:print_config(short, qtest://'ufcat/ufpkg-1.0':update?{[]}),
      useflags:print_config(column, qtest://'ufcat/ufpkg-1.0':downgrade?{[]}),
      useflags:print_config(fancy, qtest://'ufcat/ufpkg-1.0':reinstall?{[]}),
      useflags:print_config(fancy, qtest://'ufcat/ufpkg-1.0':run?{[]}),
      useflags:print_config(fancy, qtest://'ufcat/ufpkg-1.0':other_act?{[]}),
      % print_slot_value all clauses
      useflags:print_slot_value([slot('1')]),
      useflags:print_slot_value([slot('1'), subslot('2')]),
      useflags:print_slot_value([slot('1'), subslot('2'), equal]),
      useflags:print_slot_value([slot('1'), equal]),
      useflags:print_slot_value(raw_slot),
      % print_flags_unwrapped, print_easy_*, print_use_flag all reasons
      OldInfo = old_use_info(false, [fb], [fa, fb]),
      UCtx = uctx(fancy, '', OldInfo),
      AllReasonFlags = [flag(positive:preference, fa, []),
                        flag(positive:package_use, fa, []),
                        flag(positive:profile_package_use_force, fa, []),
                        flag(positive:ebuild, fc, []),
                        flag(negative:preference, fb, []),
                        flag(negative:package_use, fb, []),
                        flag(negative:profile_package_use_mask, fb, []),
                        flag(negative:ebuild, fc, []),
                        flag(negative:default, fc, [])],
      useflags:print_flags_unwrapped(UCtx, AllReasonFlags),
      forall(member(flag(RType, Fl, As), AllReasonFlags),
             useflags:get_flag_length(UCtx, RType, Fl, As, _)),
      useflags:get_change_extra_length(UCtx, other_pol, fa, 0),
      useflags:old_use_info(non_entry_term, [], old_use_info(true, [], [])),
      useflags:use_flag_change_type(non_uctx, fa, positive, steady),
      useflags:classify_flag_change(fa, other_pol, false, [], [], steady),
      assertz(preference:local_env_use(fa)),
      assertz(preference:local_env_use(minus(fb))),
      useflags:print_use_flag(UCtx, positive:preference, fa, []),
      useflags:print_use_flag(UCtx, negative:preference, fb, []),
      retractall(preference:local_env_use(_)),
      assertz(config:color_palette(easy)),
      useflags:print_flags_unwrapped(UCtx, AllReasonFlags),
      useflags:print_easy_positive(steady, fa),
      useflags:print_easy_negative(steady, fb),
      retractall(config:color_palette(easy)),
      forall(member(DescMode, [all, new, changed]),
             forall(member(FT, [flag(positive:ebuild, fa, []),
                                flag(negative:ebuild, fa, []),
                                flag(negative:default, fa, [])]),
                    ignore(useflags:flag_has_description(DescMode, FT))))
    )).

test(warning_and_plan_modules_full_coverage,
     [setup(( V1 = version([1,0], '', 4, 0, [], 0, '1.0'),
              V2 = version([2,0], '', 4, 0, [], 0, '2.0'),
              assertz(cache:ordered_entry(qtest, 'wcat/wpkg-1.0', wcat, wpkg, V1)),
              assertz(cache:entry_metadata(qtest, 'wcat/wpkg-1.0', slot, slot('0'))),
              assertz(cache:entry_metadata(qtest, 'wcat/wpkg-1.0', license, 'GPL-2')),
              assertz(cache:ordered_entry(qtest, 'wcat/wpkg-2.0', wcat, wpkg, V2)),
              assertz(feedback:session_discovery(qtest://'wcat/wpkg-1.0', 'sys-devel/bison', bdepend,
                        evidence(symbol(command, bison), phase(configure), exit(1),
                                 resolver(curated_seed), log("bison: not found")))) )),
      cleanup(( retractall(cache:ordered_entry(qtest, _, wcat, _, _)),
                retractall(cache:entry_metadata(qtest, 'wcat/wpkg-1.0', _, _)),
                retractall(feedback:session_discovery(qtest://'wcat/wpkg-1.0', _, _, _)),
                retractall(config:print_blockers(_)),
                assertz(config:print_blockers(gentoo)) ))]) :-
  V1 = version([1,0], '', 4, 0, [], 0, '1.0'),
  V2 = version([2,0], '', 4, 0, [], 0, '2.0'),
  RE1 = qtest://'wcat/wpkg-1.0',
  RE2 = qtest://'wcat/wpkg-2.0',
  % warning.pl: blocker helpers, suggestions, bugreports, assumption details, requse_term_to_text
  Blk1 = blocker(strong, install, wcat, wpkg, greaterequal, V1, [slot('0'), subslot('1'), equal])?{[self(RE2)]},
  Blk2 = blocker(weak, run, wcat, wpkg, none, version_none, [slot('0')]),
  warning:is_blocker_assumption(Blk1),
  warning:is_blocker_assumption(Blk2),
  \+ warning:is_blocker_assumption(not_a_blocker),
  forall(member(SR-Suf, [[slot('0')]-':0',
                         [slot('0'), subslot('1')]-':0/1',
                         [slot('0'), equal]-':0',
                         [slot('0'), subslot('1'), equal]-':0/1',
                         [any_same_slot]-'']),
         warning:blocker_slot_suffix(SR, Suf)),
  forall(member(RAtom, [missing, masked, keyword_filtered, installed_required,
                        slot_unsatisfied, version_no_candidate(equal, V1),
                        version_conflict(x), version_no_candidate,
                        version_conflict, unsatisfied_constraints, no_tree_ebuild]),
         ( warning:assumption_reason_label_(RAtom, _),
           ignore(warning:bugreport_reason_label(RAtom, _))
         )),
  warning:bugreport_reason_label(_UnboundReason, 'unsatisfied dependency'),
  forall(member(RUTerm, [required(fa), required(minus(fa)), blocking(fa),
                         exactly_one_of_group([required(fa), required(fb)]),
                         at_most_one_of_group([required(fa), required(fb)]),
                         any_of_group([required(fa), required(fb)]),
                         use_conditional_group(positive, fa, RE1, [required(fb)]),
                         use_conditional_group(negative, fa, RE1, [required(fb)]),
                         other_ru_term]),
         warning:requse_term_to_text(RUTerm, _)),
  warning:known_bugs_prefix(2, [1, 2, 3], [1, 2]),
  warning:known_bugs_prefix(5, [1, 2], [1, 2]),
  warning:rank_known_bugs([1, 2], wcat, wpkg, version_none, [1, 2]),
  warning:rank_known_bugs([1, 2], wcat, wpkg, V1, _),
  warning:discovered_evidence_fields(bad_evidence, unknown, unknown, unknown, unknown, ''),
  with_output_to(string(_),
    ( % Blocker sections in off, gentoo, and fancy styles
      retractall(config:print_blockers(_)), assertz(config:print_blockers(off)),
      warning:print_blockers_section([Blk1]),
      retractall(config:print_blockers(_)), assertz(config:print_blockers(gentoo)),
      warning:print_blockers_section([Blk1, Blk2]),
      retractall(config:print_blockers(_)), assertz(config:print_blockers(fancy)),
      warning:print_blockers_section([Blk1, Blk2]),
      % Suggestions: license, keyword (>20 and <=20), unmask, use_change
      warning:print_license_suggestions([accept_license(qtest, 'wcat/wpkg-1.0', wcat, wpkg),
                                         accept_license(qtest, 'wcat/no_lic-1.0', wcat, no_lic)]),
      findall(kw(wcat, NAtom, unstable(amd64)),
              ( between(1, 22, I), format(atom(NAtom), 'pkg~d', [I]) ),
              ManyKws),
      warning:print_keyword_suggestions([kw(wcat, wpkg, stable(amd64)), kw(wcat, wpkg, '**')]),
      warning:print_keyword_suggestions(ManyKws),
      warning:print_unmask_suggestions([unmask(qtest, 'wcat/wpkg-1.0', wcat, wpkg),
                                        unmask(qtest, _UnboundE, wcat, wpkg)]),
      warning:print_use_change_suggestions([]),
      warning:print_use_change_suggestions([use_sugg(wcat, wpkg, RE1,
                                                     [use_change(fa, enable), use_change(fb, disable)])]),
      warning:blocker_slot_suffix([], ''),
      warning:assumption_has_unmask_suggestion(qtest://'wcat/wpkg-1.0':unmask?{[suggestion(unmask), masked_cn(wcat, wpkg)]},
                                               qtest, 'wcat/wpkg-1.0', wcat, wpkg),
      % Bug report drafts (proof & discovered)
      empty_assoc(EmptyProof),
      warning:print_proof_bugreport_drafts(EmptyProof),
      PD1 = package_dependency(install, no, wcat, wpkg, greaterequal, V1, [slot('0')], []),
      Ass1 = grouped_package_dependency(wcat, wpkg, [PD1]):install?{[assumption_reason(version_no_candidate(greaterequal, V2)), self(RE2)]},
      Ass2 = grouped_package_dependency(wcat, wpkg, [PD1]):run?{[assumption_reason(version_conflict), self(RE2)]},
      list_to_assoc([rule(assumed(Ass1))-(dep(0, [])?[]),
                     rule(assumed(Ass2))-(dep(0, [])?[])], BugProof),
      warning:print_proof_bugreport_drafts(BugProof),
      forall(member(FixR, [version_no_candidate, slot_unsatisfied, keyword_filtered,
                           masked, installed_required, other_reason]),
             warning:bugreport_potential_fix(FixR, wcat, wpkg, [], RE2)),
      warning:print_discovered_bugreport_drafts,
      % print_assumption_detail all clauses + handle_assumption/1,3
      warning:handle_assumption(rule(assumed(qtest://'wcat/wpkg-1.0':install))),
      warning:handle_assumption(assumed(rule(qtest://'wcat/wpkg-1.0':install))),
      warning:handle_assumption(other_key),
      warning:handle_assumption(rule(assumed(qtest://'wcat/wpkg-1.0':install)), EmptyProof, EmptyProof),
      warning:handle_assumption(assumed(rule(qtest://'wcat/wpkg-1.0':install)), EmptyProof, EmptyProof),
      warning:handle_assumption(other_key, EmptyProof, EmptyProof),
      warning:print_assumption_detail(rule(PD1:install?{[assumption_reason(missing), self(RE2)]}, [])),
      Viol1 = required_use_violation(RE1, [fa], [fb], [required(fa)]),
      Viol2 = use_dep_unsat(RE1, use_state([fa], [fb]), profile_hard_conflict),
      Viol3 = use_dep_unsat(RE1, use_state([fa], [fb]), Viol1),
      Viol4 = use_flag_conflict([fa], [fa], [fa]),
      warning:print_assumption_detail(rule(grouped_package_dependency(wcat, wpkg, []):install?{[required_use_violation(Viol1)]}, [])),
      warning:print_requse_violation_detail(Viol2),
      warning:print_requse_violation_detail(Viol3),
      warning:print_requse_violation_detail(Viol4),
      warning:print_requse_violation_detail(other_viol),
      DomA = version_domain(any, [bound(equal, V1)]),
      SC1 = slot_conflict_info(wcat, wpkg, domain_conflict(DomA, other_dom)),
      SC2 = slot_conflict_info(wcat, wpkg, [slot_entry(qtest, 'wcat/wpkg-1.0', V1, '0')]),
      warning:print_assumption_detail(rule(grouped_package_dependency(wcat, wpkg, []):install?{[slot_conflict(SC1)]}, [])),
      warning:print_slot_conflict_detail(SC2),
      warning:print_slot_conflict_detail(other_sc),
      warning:print_assumption_detail(rule(grouped_package_dependency(no, wcat, wpkg, []):install, [])),
      warning:print_assumption_detail(rule(grouped_package_dependency(no, wcat, wpkg, []):run, [])),
      warning:print_assumption_detail(rule(qtest://'wcat/wpkg-1.0':install, [])),
      warning:print_assumption_detail(rule(qtest://'wcat/wpkg-1.0':run, [])),
      warning:print_assumption_detail(rule(qtest://'wcat/wpkg-1.0':unmask?{[]}, [])),
      warning:print_assumption_detail(rule(qtest://'wcat/wpkg-1.0':unmask, [])),
      warning:print_assumption_detail(rule(qtest://'wcat/wpkg-1.0':install?{[required_use_violation(Viol1)]}, [])),
      warning:print_assumption_detail(rule(qtest://'wcat/wpkg-1.0':install?{[issue_with_model(explanation)]}, [])),
      warning:print_assumption_detail(rule(issue_with_model(RE1)?{[]}, [])),
      warning:print_assumption_detail(rule(issue_with_model(qtest://'no/entry-1.0')?{[]}, [])),
      warning:print_assumption_detail(rule(issue_with_model(RE1), [])),
      warning:print_assumption_detail(rule(arbitrary_other_assumption, [])),

      % plan.pl remaining clauses
      QTarget = qualified_target(none, qtest, wcat, wpkg, version_none, [[], []]),
      list_to_assoc([rule(target(QTarget, 'wcat/wpkg'):run)-(dep(1, [qtest://'wcat/wpkg-1.0':run?{[]}])?[]),
                     rule(target(QTarget, 'wcat/wpkg'):fetchonly)-(dep(1, [qtest://'wcat/wpkg-1.0':fetchonly?{[]}])?[]),
                     rule(target(QTarget, 'wcat/wpkg'):uninstall)-(dep(1, [qtest://'wcat/wpkg-1.0':uninstall?{[]}])?[])],
                    TProof),
      plan:resolve_print_target_one(target(QTarget, 'wcat/wpkg'):run?{[]}, TProof, _, _),
      plan:resolve_print_target_one(target(QTarget, 'wcat/wpkg'):fetchonly?{[]}, TProof, _, _),
      plan:resolve_print_target_one(target(QTarget, 'wcat/wpkg'):uninstall?{[]}, TProof, _, _),
      plan:canonical_print_core(grouped_package_dependency(no, wcat, wpkg, []):install),
      plan:format_blocker_origin(RE1),
      plan:format_blocker_origin(qtest://'no/such-1.0'),
      plan:format_blocker_origin(raw_origin),
      forall(member(RebReason, [newuse, changeduse, changedslot, rebuilt_binary,
                                subslot_change(RE1, '0', '1'), rebuild_if_unbuilt(RE1)]),
             plan:print_newuse_note_if_any(update, [rebuild_reason(RebReason)])),
      forall(member(Act-Ph, [reinstall-install, update-install, download-other,
                             fetchonly-other, weird_act-other]),
             plan:action_phase(Act, Ph)),
      plunit_printer_plan_head_shapes:printer_empty_state(EmptyState),
      plan:printable_element(EmptyState, rule(uri(https, a, b), [])),
      plan:printable_element(EmptyState, rule(uri(a), [])),
      \+ plan:printable_element(EmptyState, assumed(rule(other_cyc, []))),
      plan:printable_kind_action(cycle_break, PD1:install, install),
      \+ plan:printable_kind_action(cycle_break, other_core:other_act, other_act),
      plan:printable_kind_action(domain_assumption, grouped_package_dependency(wcat, wpkg, []):install, install),
      plan:printable_kind_action(domain_assumption, PD1:install, install),
      \+ plan:printable_kind_action(domain_assumption, other_core:other_act, other_act),
      list_to_assoc([(install-wcat-wpkg)-true], PlannedSet),
      StatePlanned = ps([qtest://'wcat/wpkg-1.0':update?{[]}], t, PlannedSet),
      plan:suppress_assumed_planned(StatePlanned, grouped_package_dependency(no, wcat, wpkg, []):install),
      plan:suppress_assumed_planned(StatePlanned, grouped_package_dependency(wcat, wpkg, []):install),
      plan:suppress_assumed_planned(StatePlanned, PD1:install),
      plan:ctx_list(non_list_ctx, []),
      plan:canonical_print_core(grouped_package_dependency(wcat, wpkg, []):install),
      plan:canonical_print_core(PD1:install),
      plan:rebuild_print_rule(domain_assumption, qtest://'wcat/wpkg-1.0':install, [], rule(assumed(qtest://'wcat/wpkg-1.0':install), [])),
      plan:rebuild_print_rule(cycle_break, qtest://'wcat/wpkg-1.0':install, [], assumed(rule(qtest://'wcat/wpkg-1.0':install, []))),
      plan:element_kind(rule(uri(a), []), provide),
      plan:element_kind(rule(uri(a, b, c), []), fetch),
      plan:element_kind(rule(PD1, []), confirm),
      % plan:print_element variants
      plan:print_element(StatePlanned, rule(package_dependency(run_post, no, wcat, wpkg, none, version_none, [], []), [qtest://'wcat/wpkg-1.0':run?{[]}])),
      plan:print_element(StatePlanned, rule(package_dependency(run, no, wcat, wpkg, none, version_none, [], []), [qtest://'wcat/wpkg-1.0':run?{[]}])),
      plan:print_element(StatePlanned, rule(uri(https, 'example.com/a', 'a'), [])),
      plan:print_element(StatePlanned, rule(uri('local_a'), [])),
      plan:print_element(StatePlanned, rule(qtest://'wcat/wpkg-2.0':update?{[replaces(RE1)]}, [])),
      plan:print_element(EmptyState, rule(qtest://'wcat/wpkg-1.0':install?{[suggestion(accept_keyword, unstable(amd64))]}, [])),
      plan:print_element(EmptyState, rule(qtest://'wcat/wpkg-1.0':install?{[suggestion(accept_license, 'GPL-2')]}, [])),
      plan:print_element(EmptyState, rule(qtest://'wcat/wpkg-1.0':install?{[suggestion(unmask, true)]}, [])),
      plan:print_element(EmptyState, rule(qtest://'wcat/wpkg-1.0':install?{[suggestion(use_change, RE1, [use_change(fa, enable)])]}, [])),
      forall(member(AR, [masked, version_conflict, version_conflict(x), version_no_candidate,
                         version_no_candidate(equal, V1), slot_unsatisfied, installed_required,
                         unsatisfied_constraints, no_tree_ebuild]),
             plan:print_element(EmptyState,
               rule(assumed(grouped_package_dependency(wcat, wpkg, []):install?{[assumption_reason(AR)]}), []))),
      plan:print_element(EmptyState, rule(assumed(grouped_package_dependency(wcat, wpkg, []):fetchonly?{[]}), [])),
      plan:print_element(EmptyState, rule(assumed(PD1:install?{[]}), [])),
      plan:print_element(EmptyState, rule(assumed(qtest://'wcat/wpkg-1.0':unmask?{[]}), [])),
      plan:print_element(EmptyState, rule(assumed(issue_with_model(RE1)?{[]}), [])),
      plan:print_element(EmptyState, rule(assumed(issue_with_model(RE1)), [])),
      plan:print_element(EmptyState, rule(assumed(qtest://'wcat/wpkg-1.0':install?{[]}), [])),
      plan:print_element(EmptyState, assumed(rule(qtest://'wcat/wpkg-1.0':install?{[]}, []))),
      plan:print_element(EmptyState, assumed(rule(PD1:install?{[]}, []))),
      plan:print_element_safe(EmptyState, non_matching_element),
      % pre-actions, continuation, footer, variants
      PreActs = [unmask(qtest, 'wcat/wpkg-1.0', wcat, wpkg),
                 accept_license(qtest, 'wcat/wpkg-1.0', wcat, wpkg),
                 accept_keyword(qtest, 'wcat/wpkg-1.0', wcat, wpkg, unstable(amd64)),
                 use_change(qtest, 'wcat/wpkg-1.0', wcat, wpkg, [use_change(fa, enable), use_change(fb, disable)]),
                 kernel_config([config('CONFIG_FOO', y)], ev)],
      plan:print_plan_pre_actions(PreActs, 0, 1),
      plan:print_pre_action_core(use_change(qtest, 'wcat/wpkg-1.0', wcat, wpkg, []), false),
      plan:print_flag_atoms_unwrapped([]),
      plan:print_flag_atoms_unwrapped([fa, fb]),
      plan:print_pre_action_continuation(20),
      plan:is_run_cycle_break(qtest://'wcat/wpkg-1.0':run?{[]}),
      PlanFooter = [[rule(qtest://'wcat/wpkg-1.0':download?{[]}, []),
                     rule(qtest://'wcat/wpkg-1.0':install?{[]}, []),
                     rule(qtest://'wcat/wpkg-1.0':update?{[]}, []),
                     rule(qtest://'wcat/wpkg-1.0':downgrade?{[]}, []),
                     rule(qtest://'wcat/wpkg-1.0':reinstall?{[]}, []),
                     rule(qtest://'wcat/wpkg-1.0':run?{[]}, [])]],
      plan:print_footer(PlanFooter, t, 1, PreActs),
      BasePlan = [[rule(qtest://'wcat/wpkg-1.0':install?{[]}, [])]],
      AltPlan  = [[rule(qtest://'wcat/wpkg-2.0':install?{[]}, [])]],
      plan:print_variants([variant_result(variant(use_flip, RE1, fa, positive, '+fa'), failed),
                           variant_result(variant(use_flip, RE1, fa, negative, '-fa'), t, t, BasePlan, t),
                           variant_result(variant(use_flip, RE1, fb, positive, '+fb'), t, t, AltPlan, t)],
                          BasePlan)
    )).

:- end_tests(printer_plan_full_coverage).


% -----------------------------------------------------------------------------
%  Full coverage for Build/build.pl, News/news.pl, index.pl, info.pl, state.pl, stats.pl
% -----------------------------------------------------------------------------

:- dynamic kb:repository/1.
:- dynamic portage:get_location/1.

:- begin_tests(printer_remaining_modules_full_coverage).

test(build_printer_full_coverage, [nondet]) :-
  tmp_file(bp_cov, TmpDir),
  make_directory_path(TmpDir),
  os:compose_path(TmpDir, 'dist.tar.gz', DistPath),
  setup_call_cleanup(open(DistPath, write, SD), write(SD, 'data'), close(SD)),
  size_file(DistPath, Size),
  mirror:openssl_file_hash(DistPath, '-sha256', Sha256),
  Pairs = [alg_hash(sha256, Sha256)],
  DistFiles = [dist('dist.tar.gz', Size, Pairs),
               dist('missing.tar.gz', 100, Pairs)],
  PhaseList = [clean, setup, unpack, prepare, configure, compile, test, install, package, merge],
  Jobs = [
    slotted(0, 10, 1, 2, 0, rule(qtest://'bcat/bpkg-1.0':download?{[]}, []), live_source(1)),
    slotted(2, 10, 1, 2, 1, rule(qtest://'bcat/bpkg-1.0':download?{[]}, []), files(3, 2, DistFiles, TmpDir)),
    slotted(5, 10, 2, 2, 0, rule(qtest://'bcat/bpkg-1.0':install?{[]}, []), phases(6, 1, 7, PhaseList, '/tmp/b.log')),
    slotted(8, 10, 2, 2, 1, rule(qtest://'bcat/bpkg-1.0':run?{[]}, []), no_files),
    slotted(9, 10, 2, 2, 2, rule(world('bcat/bpkg'):register?{[]}, []), no_files),
    other_job
  ],
  setup_call_cleanup(
    asserta(config:show_build_logs(true)),
    with_output_to(string(_),
      ( build:header(1, 1),
        build:header(2, 3),
        forall(member(Style, ['fancy', 'column', 'short']),
          setup_call_cleanup(
            ( retractall(config:interface_printing_style(_)),
              asserta(config:interface_printing_style(Style)) ),
            ( build:print_job_slots(Jobs, 2),
              build:print_skipped_slots(Jobs, 2),
              build:exec_phase_line_count(PhaseList, _),
              build:exec_content_start_col(_),
              build:exec_wrap_newline(40),
              forall(member(TtyVal, [false, true]),
                setup_call_cleanup(
                  ( retractall(console:output_tty_cached(_)),
                    asserta(console:output_tty_cached(TtyVal)) ),
                  ( forall(member(St, [pending, active, done, failed(err), failed, skipped, stub, other_st]),
                           ignore(build:update_slot(0, 10, St, 1, 2, 0, install, qtest://'bcat/bpkg-1.0'))),
                    forall(member(FSt, [cached, pending, progress(50, 1024), progress(50), done, failed, failed(1), restricted]),
                           ( ignore(build:update_file_subslot(0, 3, 10, FSt, 'dist.tar.gz', Size, TmpDir)),
                             ignore(build:update_file_subslot(1, 3, 10, FSt, 'missing.tar.gz', 100, TmpDir)),
                             ignore(build:render_file_content(FSt, 'dist.tar.gz', Size, TmpDir)) )),
                    forall(member(LSt, [pending, progress(40), done, failed]),
                           ( build:update_live_subslot(0, 1, 10, LSt),
                             build:render_live_content(LSt) )),
                    AllPhaseStates = [clean-done, setup-active, unpack-progress(50), prepare-pending,
                                      configure-failed, compile-failed(1), test-failed(1, '/l'),
                                      install-skipped, package-stub],
                    build:update_exec_line(6, 10, install, AllPhaseStates),
                    build:update_exec_line(6, 10, install, [clean-done, setup-active, package-stub]),
                    build:update_exec_line(6, 10, install, [clean-done, unpack-progress(50), package-stub]),
                    build:update_exec_line(6, 10, install, [clean-done, merge-stub]),
                    build:update_exec_line(6, 10, install, [clean-done, setup-pending]),
                    build:update_exec_line(6, 10, install, [clean-stub]),
                    build:render_phases_wrapped([]),
                    build:print_skipped_conf(not_a_valid_rule_head),
                    build:update_logs_line(7, 10, '/tmp/b.log', failed),
                    build:update_logs_line(7, 10, '/tmp/b.log', failed(1, '/tmp/b.log')),
                    build:update_logs_line(7, 10, '', done)
                  ),
                  retractall(console:output_tty_cached(_))))
            ),
            retractall(config:interface_printing_style(_)))),
        fixup:record(collision, 'bcat/bpkg-1.0', collision_protect),
        fixup:record(custom_mech, 'bcat/bpkg-1.0', detail),
        build:summary(0, 0, 0),
        build:summary(1, 0, 0),
        build:summary(1, 1, 0),
        build:summary(1, 1, 1),
        fixup:clear
      )),
    ( retractall(config:show_build_logs(true)),
      retractall(console:output_tty_cached(_)),
      retractall(config:interface_printing_style(_)),
      fixup:clear,
      catch(delete_directory_and_contents(TmpDir), _, true)
    )).

test(news_index_info_state_and_stats_full_coverage, [nondet]) :-
  tmp_file(ni_cov, TmpDir),
  make_directory_path(TmpDir),
  os:compose_path([TmpDir, 'metadata', 'news', '2026-01-01-test'], NewsItemDir),
  make_directory_path(NewsItemDir),
  os:compose_path(NewsItemDir, '2026-01-01-test.en.txt', NewsTxt),
  setup_call_cleanup(
    open(NewsTxt, write, SN),
    format(SN, 'Title: Test News~nAuthor: Dev~nPosted: 2026-01-01~n~nBody line 1~nBody line 2~n', []),
    close(SN)),
  V1 = version([1,0], '', 4, 0, [], 0, '1.0'),
  V2 = version([2,0], '', 4, 0, [], 0, '2.0'),
  setup_call_cleanup(
    ( ( catch(kb:declared(type(instance(knowledgebase))), _, fail) -> true ; kb:newinstance(knowledgebase) ),
      assertz(cache:repository(portage)),
      asserta(portage:get_location(TmpDir)),
      assertz(cache:category(qtest, 'acat')),
      assertz(cache:category(qtest, 'bcat')),
      assertz(cache:package(qtest, 'acat', apkg)),
      assertz(cache:package(qtest, 'acat', bpkg)),
      assertz(cache:ordered_entry(qtest, 'acat/apkg-1.0', 'acat', apkg, V1)),
      assertz(cache:ordered_entry(qtest, 'acat/apkg-2.0', 'acat', apkg, V2)),
      assertz(cache:entry_metadata(qtest, 'acat/apkg-1.0', eapi, V1)),
      assertz(cache:entry_metadata(qtest, 'acat/apkg-1.0', description, 'desc')),
      assertz(cache:entry_metadata(qtest, 'acat/apkg-1.0', homepage, 'https://ex.org')),
      assertz(cache:entry_metadata(qtest, 'acat/apkg-1.0', license, 'MIT')),
      assertz(cache:entry_metadata(qtest, 'acat/apkg-1.0', keywords, stable(amd64))),
      assertz(cache:entry_metadata(qtest, 'acat/apkg-1.0', slot, slot('0'))),
      assertz(cache:entry_metadata(qtest, 'acat/apkg-1.0', iuse, plus(u1))),
      assertz(cache:entry_metadata(qtest, 'acat/apkg-1.0', iuse, minus(u2))),
      assertz(cache:entry_metadata(qtest, 'acat/apkg-1.0', required_use, required(u1))),
      assertz(cache:entry_metadata(qtest, 'acat/apkg-1.0', required_use, blocking(u2))),
      assertz(cache:entry_metadata(qtest, 'acat/apkg-1.0', src_uri, uri('https', 'ex.org', 'a.tar.gz'))),
      assertz(cache:entry_metadata(qtest, 'acat/apkg-1.0', depend,
        use_conditional_group(negative, u2, qtest://'acat/apkg-1.0', [
          any_of_group([
            all_of_group([
              exactly_one_of_group([
                at_most_one_of_group([
                  package_dependency(install, no, acat, bpkg, none, version_none, [], []),
                  package_dependency(install, weak, acat, bpkg, greater, V1, [any_different_slot],
                    [use(inverse(u1), positive), use(equal(u1), negative),
                     use(optdisable(u1), none), use(optenable(u1), none),
                     use(disable(u1), none), use(enable(u1), none), other_use]),
                  package_dependency(install, strong, acat, bpkg, equal, V1, [any_same_slot], _)
                ])
              ])
            ])
          ])
        ])))
    ),
    with_output_to(string(_),
      ( % 1. news.pl
        news:check,
        news:extract_header([], "Title", "unknown"),
        news:skip_headers(["Header: 1"], []),
        os:compose_path(TmpDir, 'empty_news', EmptyNewsDir),
        make_directory_path(EmptyNewsDir),
        news:display_items(EmptyNewsDir),
        retractall(cache:repository(portage)),
        news:check,
        % 2. index.pl
        index:print_repository_index(qtest),
        index:print_category_index(qtest, 'acat'),
        index:print_package_index(qtest, 'acat', apkg),
        index:emit_grid_open,
        index:index_unit_label(1, versions, version),
        index:index_unit_label(1, packages, package),
        index:index_unit_label(1, categories, category),
        index:print_index(repository, 'T', 'TH', member(E1, [r1]), E1, 's.css'),
        index:print_index(category, 'T', 'TH', member(E2, [c1]), E2, 's.css'),
        index:print_index(package, 'T', 'TH', member(E3, [[p1, '1.0']]), E3, 's.css'),
        % 3. info.pl
        info:print_system,
        info:print_entry(qtest://'acat/apkg-1.0'),
        info:print_metadata_item_detail(depend, '  ',
          grouped_package_dependency(acat, bpkg,
            [package_dependency(install, no, acat, bpkg, none, version_none, [slot('0')], [])])),
        info:print_metadata_item_detail(depend, '  ',
          grouped_package_dependency(no, acat, bpkg,
            [package_dependency(install, no, acat, bpkg, none, version_none, [slot('0'), equal], [])])),
        forall(member(SR, [[], [any_different_slot], [any_same_slot], [slot('0')],
                           [slot('0'), equal], [slot('0'), subslot('1')], [slot('0'), subslot('1'), equal]]),
               info:print_slot_restriction(SR)),
        % 4. state.pl
        state:display_state([], t, t, t),
        empty_assoc(EmptyA),
        put_assoc(rule(a, []), EmptyA, true, ProofA),
        put_assoc(a, EmptyA, [], ModelA),
        put_assoc(constraint(c, [1]), EmptyA, true, ConsA),
        state:display_state([a, b], ProofA, ModelA, ConsA),
        state:display_state(a, EmptyA, EmptyA, EmptyA),
        state:wait_for_input,
        % 5. stats.pl
        stats:test_stats_to_atom(atom_val, atom_val),
        stats:test_stats_to_atom(compound(1), _),
        stats:test_stats_fit_atom('longatom', 1, _),
        stats:test_stats_fit_atom('longatom', 2, _),
        stats:test_stats_fit_atom('longatom', 4, _),
        stats:test_stats_fit_atom('ok', 10, 'ok'),
        stats:test_stats_print_kv_int('K', 1),
        stats:test_stats_print_kv_int_percent('K', 1, 2),
        stats:test_stats_print_ranked_table_rows([2-a, 1-b], 1, 1, 80),
        stats:test_stats_print_top_cycle_mentions([], 5, 1),
        stats:test_stats_print_top_cycle_mentions([2-(qtest://'acat/apkg-1.0'), 1-(qtest://'acat/apkg-2.0')], 1, 1),
        sampler:reset('Testing', 2),
        sampler:set_expected_pkgs(1),
        sampler:record(entry(qtest://'acat/apkg-1.0', EmptyA, EmptyA, EmptyA, true)),
        sampler:record(failed(blocker)),
        sampler:record(failed(timeout)),
        sampler:record(failed(other)),
        forall(member(SFact, [
          failed_entry(qtest://'acat/apkg-2.0', other),
          pkg(processed, 'acat', apkg),
          type(blocker_assumption, entries, 1),
          type(blocker_assumption, occurrences, 2),
          type(other, entries, 1),
          type(other, occurrences, 1),
          type_entry_mention(blocker_assumption, qtest://'acat/apkg-1.0', 2),
          other_head(some_other_head, 1),
          blocker_sp(weak, run, 1),
          blocker_reason(version_mismatch, 1),
          blocker_rp(version_mismatch, install, 1),
          blocker_rp(version_mismatch, run, 1),
          blocker_cn('acat', bpkg, 1),
          cycle_mention(run, qtest://'acat/apkg-1.0', 1),
          cycle_mention(install, qtest://'acat/apkg-1.0', 1),
          entry_time(qtest://'acat/apkg-1.0', 10),
          pkg_time('acat', apkg, 10, 10, 1),
          pkg_cost('acat', apkg, 10, 100, 5, 1),
          pkg_ctx('acat', apkg, 20, 5, 2, 1),
          ctx_len_bin(2, 3),
          ctx_len_bin(5, 2),
          ctx_cost_model(100, 20, 5)
        ]), assertz(sampler:fact(SFact))),
        stats:test_stats_print
      )),
    ( retractall(sampler:fact(_)),
      retractall(cache:repository(portage)),
      retractall(portage:get_location(TmpDir)),
      retractall(cache:category(qtest, _)),
      retractall(cache:package(qtest, _, _)),
      retractall(cache:ordered_entry(qtest, 'acat/apkg-1.0', _, _, _)),
      retractall(cache:ordered_entry(qtest, 'acat/apkg-2.0', _, _, _)),
      retractall(cache:entry_metadata(qtest, 'acat/apkg-1.0', _, _)),
      catch(delete_directory_and_contents(TmpDir), _, true)
    )).

:- end_tests(printer_remaining_modules_full_coverage).


% -----------------------------------------------------------------------------
%  Phase-stats ETA on the build progress edge
% -----------------------------------------------------------------------------

:- begin_tests(build_phase_eta).

test(equal_weight_without_history) :-
  States = [setup-done, compile-progress(0)],
  build:forecast_progress(States, none, Pct, Current, Total, Remain),
  Pct =:= 50,
  Current =:= 2,
  Total =:= 2,
  Remain == none.

test(time_weighted_eta_uses_sibling_version) :-
  Entry = 'zzeta/zzpkg-2.0',
  Sibling = 'zzeta/zzpkg-1.0',
  retractall(phasestats:phase_seconds(Sibling, _, _)),
  retractall(phasestats:phase_seconds(Entry, _, _)),
  retractall(phasestats:forecast_cache(Entry, _, _, _)),
  retractall(phasestats:forecast_cache(Sibling, _, _, _)),
  retractall(phasestats:cn_entry(_, zzpkg, _)),
  assertz(phasestats:phase_seconds(Sibling, setup, 10.0)),
  assertz(phasestats:phase_seconds(Sibling, compile, 100.0)),
  ( phasestats:cn_index_ready
  -> phasestats:entry_cn(Sibling, Cat, Name),
     assertz(phasestats:cn_entry(Cat, Name, Sibling))
  ;  true
  ),
  States = [setup-done, compile-progress(50), merge-pending],
  build:forecast_progress(States, Entry, Pct, Current, Total, Remain),
  Pct =:= 36,
  Current =:= 2,
  Total =:= 3,
  Remain = seconds(Left),
  Delta is abs(Left - 105.0),
  Delta < 0.001,
  build:eta_label(Pct, Current, Total, Remain, Label),
  Label == '(36%) 2/3  ETA 1m 45s',
  retractall(phasestats:phase_seconds(Sibling, _, _)),
  retractall(phasestats:forecast_cache(Entry, _, _, _)),
  retractall(phasestats:forecast_cache(Sibling, _, _, _)),
  retractall(phasestats:cn_entry(_, zzpkg, _)).

:- end_tests(build_phase_eta).
