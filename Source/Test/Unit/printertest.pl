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

:- end_tests(annotation_blocker_relevance).


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
                  unsatisfied_constraints      - unsatisfied_constraints_dependency ]),
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
