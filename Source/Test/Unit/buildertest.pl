/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> BUILDERTEST
Unit tests for the builder (Source/Pipeline/builder.pl and Source/Domain/Gentoo/Ebuild/).

The base USE state handed to ebuild (portage-ng#22), linkable-object
detection and the VDB reconciliation backstop.
*/

:- module(buildertest, []).

:- use_module(library(plunit)).
:- use_module(library(lists)).

% =============================================================================
%  BUILDERTEST declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Builder base USE state matches resolver (portage-ng#22)
% -----------------------------------------------------------------------------
%
% The builder's base USE string (ebuild_exec:collect_use_string/4) must agree
% with the resolver's view of each IUSE flag. Previously the builder folded the
% raw iuse/2 facts with a last-wins dedup, which picked the wrong polarity for
% flags declared with conflicting facts (e.g. x11-libs/wxGTK exposes `X` as
% [positive:ebuild, negative:default], so last-wins gave `-X` while the resolver
% resolved `+X`, breaking REQUIRED_USE="spell? ( X )" at setup). The fix routes
% the base polarity through use:effective_use_for_entry/3.
%
% These tests are KB-independent: they pre-seed memo:eff_use_cache_/4 so the
% effective lookup short-circuits without needing cache:ordered_entry/5 (absent
% in CI).

:- begin_tests(builder_base_use_state).

test(prefers_effective_positive, [true(S == positive)]) :-
  retractall(memo:eff_use_cache_(testrepo, 'cat/p-1', _, _)),
  assertz(memo:eff_use_cache_(testrepo, 'cat/p-1', 'X', positive)),
  ( ebuild_exec:base_use_state(testrepo://'cat/p-1', 'X', S)
  -> retractall(memo:eff_use_cache_(testrepo, 'cat/p-1', _, _))
  ;  retractall(memo:eff_use_cache_(testrepo, 'cat/p-1', _, _)), fail
  ).

test(prefers_effective_negative, [true(S == negative)]) :-
  retractall(memo:eff_use_cache_(testrepo, 'cat/p-1', _, _)),
  assertz(memo:eff_use_cache_(testrepo, 'cat/p-1', spell, negative)),
  ( ebuild_exec:base_use_state(testrepo://'cat/p-1', spell, S)
  -> retractall(memo:eff_use_cache_(testrepo, 'cat/p-1', _, _))
  ;  retractall(memo:eff_use_cache_(testrepo, 'cat/p-1', _, _)), fail
  ).

:- end_tests(builder_base_use_state).


% -----------------------------------------------------------------------------
%  Linkage tests
% -----------------------------------------------------------------------------
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


% -----------------------------------------------------------------------------
%  Builder: VDB reconciliation backstop tests
% -----------------------------------------------------------------------------
%
% Defensive backstop for the "silent --ci --build exit 0 despite a
% sub-dep install failure" class of regression. Verifies the predicates
% in `Source/Pipeline/builder.pl` (builder:reconcile_install_actions/3,
% builder:apply_vdb_reconciliation/4, etc.) behave as documented when
% the input plan contains a mix of install rules whose VDB entries do
% or do not exist on disk.

:- begin_tests(builder_vdb_reconciliation).

% A bogus entry that is guaranteed not to exist in any host's VDB.
% Used to simulate the "install action whose target never landed"
% scenario without needing a real failing build.

test(is_install_rule_install_matches, [nondet, condition(eapi_repo_registered)]) :-
  Rule = rule(portage://'app-misc/jq-1.8.1':install?{[]}, []),
  builder:is_install_rule(Rule, R, E, A),
  R == portage, E == 'app-misc/jq-1.8.1', A == install.

test(is_install_rule_reinstall_matches, [nondet, condition(eapi_repo_registered)]) :-
  Rule = rule(portage://'app-misc/jq-1.8.1':reinstall?{[]}, []),
  builder:is_install_rule(Rule, _, _, A),
  A == reinstall.

test(is_install_rule_rejects_non_install_actions, [fail]) :-
  Rule = rule(portage://'app-misc/jq-1.8.1':run?{[]}, []),
  builder:is_install_rule(Rule, _, _, _).

test(is_install_rule_rejects_world_rules, [fail]) :-
  Rule = rule(world('@world'):register?{[]}, []),
  builder:is_install_rule(Rule, _, _, _).

test(is_install_rule_rejects_uninstall, [fail]) :-
  Rule = rule(portage://'app-misc/jq-1.8.1':uninstall?{[]}, []),
  builder:is_install_rule(Rule, _, _, _).

test(is_install_rule_rejects_non_eapi_repo, [fail]) :-
  % `pkg` is the VDB repo (type=vdb). Rules synthesized for VDB-typed
  % targets are not real plan installs and must be skipped by the
  % backstop -- otherwise unrelated entries would falsely trip it.
  Rule = rule(pkg://'app-misc/jq-1.8.1':install?{[]}, []),
  builder:is_install_rule(Rule, _, _, _).

test(vdb_entry_present_false_for_bogus, [fail]) :-
  builder:vdb_entry_present('/var/db/pkg', 'no-such-cat/no-such-pkg-0.0').

test(reconcile_active_false_when_merge_missing, [setup(stash_live_phases(Saved)),
                                                   cleanup(restore_live_phases(Saved))]) :-
  % Drop `merge` from live phases. Reconciliation must short-circuit
  % to Active=false with Missing=[] regardless of plan contents.
  retractall(config:build_live_phases(_)),
  assertz(config:build_live_phases([clean, setup, unpack, prepare, configure, compile, test, install])),
  Plan = [[rule(portage://'no-such-cat/no-such-pkg-0.0':install?{[]}, [])]],
  builder:reconcile_install_actions(Plan, Missing, Active),
  Active == false,
  Missing == [].

test(reconcile_flags_missing_install_when_active,
     [setup(( stash_live_phases(Saved), stash_done_marks(Marks) )),
      cleanup(( restore_live_phases(Saved), restore_done_marks(Marks) )),
      condition((eapi_repo_registered, pkg_repo_registered))]) :-
  % Full live phases (including merge) AND a registered pkg repo on
  % the host = reconciliation is active. Only install steps recorded
  % as done (resume:done/2) are checked; a succeeded merge with no VDB
  % row must be reported missing.
  retractall(config:build_live_phases(_)),
  assertz(config:build_live_phases([clean, setup, unpack, prepare, configure, compile, test, install, merge])),
  assertz(resume:done('no-such-cat/no-such-pkg-0.0', install)),
  Plan = [[rule(portage://'no-such-cat/no-such-pkg-0.0':install?{[]}, [])]],
  builder:reconcile_install_actions(Plan, Missing, Active),
  Active == true,
  Missing = [_|_],
  member(portage://'no-such-cat/no-such-pkg-0.0':install, Missing).

test(reconcile_ignores_failed_install_without_resume_done,
     [setup(( stash_live_phases(Saved), stash_done_marks(Marks) )),
      cleanup(( restore_live_phases(Saved), restore_done_marks(Marks) )),
      condition((eapi_repo_registered, pkg_repo_registered))]) :-
  % portage-ng#11: failed/skipped installs stay out of the plan but must
  % not inflate the reconciliation failure tally.
  retractall(config:build_live_phases(_)),
  assertz(config:build_live_phases([clean, setup, unpack, prepare, configure, compile, test, install, merge])),
  Plan = [[rule(portage://'no-such-cat/no-such-pkg-0.0':install?{[]}, [])]],
  builder:reconcile_install_actions(Plan, Missing, Active),
  Active == true,
  Missing == [].

test(apply_reconciliation_increments_failed_count,
     [setup(( stash_live_phases(Saved), stash_done_marks(Marks) )),
      cleanup(( restore_live_phases(Saved), restore_done_marks(Marks) )),
      condition((eapi_repo_registered, pkg_repo_registered))]) :-
  retractall(config:build_live_phases(_)),
  assertz(config:build_live_phases([clean, setup, unpack, prepare, configure, compile, test, install, merge])),
  assertz(resume:done('no-such-cat/no-such-pkg-0.0', install)),
  Plan = [[rule(portage://'no-such-cat/no-such-pkg-0.0':install?{[]}, [])]],
  with_output_to(string(_),
    builder:apply_vdb_reconciliation(Plan, 0, Failed, Missing)),
  Missing \= [],
  Failed > 0.

test(apply_reconciliation_leaves_failed_alone_when_inactive, [setup(stash_live_phases(Saved)),
                                                               cleanup(restore_live_phases(Saved))]) :-
  retractall(config:build_live_phases(_)),
  assertz(config:build_live_phases([])),
  Plan = [[rule(portage://'no-such-cat/no-such-pkg-0.0':install?{[]}, [])]],
  builder:apply_vdb_reconciliation(Plan, 7, Failed, Missing),
  Failed == 7,
  Missing == [].

% --- helpers -----------------------------------------------------------------

stash_live_phases(Saved) :-
  findall(P, config:build_live_phases(P), Saved).

restore_live_phases(Saved) :-
  retractall(config:build_live_phases(_)),
  forall(member(P, Saved), assertz(config:build_live_phases(P))).

% The resume ledger (resume:done/2) belongs to the running build; the
% reconciliation tests start from an empty ledger and put the real marks
% back afterwards.
stash_done_marks(Saved) :-
  findall(E-A, resume:done(E, A), Saved),
  retractall(resume:done(_, _)).

restore_done_marks(Saved) :-
  retractall(resume:done(_, _)),
  forall(member(E-A, Saved), assertz(resume:done(E, A))).

pkg_repo_registered :-
  current_predicate(pkg:get_location/1),
  catch(pkg:get_location(Root), _, fail),
  exists_directory(Root).

eapi_repo_registered :-
  catch(portage:get_type(eapi), _, fail).

:- end_tests(builder_vdb_reconciliation).


% -----------------------------------------------------------------------------
%  Fetchonly execute filter
% -----------------------------------------------------------------------------
%
% `--fetchonly` proves :run, then builder:is_executable_rule/1 keeps only
% downloads (and skips @world side effects).

:- begin_tests(fetchonly_execute_filter).

fo_cleanup :-
  retractall(preference:local_flag(fetchonly)),
  retractall(preference:scoped_flag(fetchonly)).

test(keeps_download,
     [setup(fo_cleanup), cleanup(fo_cleanup)]) :-
  preference:with_local_flag(fetchonly,
    builder:is_executable_rule(rule(r://'p-1':download?{[]}, []))).

test(skips_install,
     [setup(fo_cleanup), cleanup(fo_cleanup)]) :-
  preference:with_local_flag(fetchonly,
    \+ builder:is_executable_rule(rule(r://'p-1':install?{[]}, []))).

test(skips_run,
     [setup(fo_cleanup), cleanup(fo_cleanup)]) :-
  preference:with_local_flag(fetchonly,
    \+ builder:is_executable_rule(rule(r://'p-1':run?{[]}, []))).

test(skips_world,
     [setup(fo_cleanup), cleanup(fo_cleanup)]) :-
  preference:with_local_flag(fetchonly,
    \+ builder:is_executable_rule(rule(world(foo):register?{[]}, []))).

test(merge_still_executes_install,
     [setup(fo_cleanup), cleanup(fo_cleanup)]) :-
  builder:is_executable_rule(rule(r://'p-1':install?{[]}, [])).

:- end_tests(fetchonly_execute_filter).


% -----------------------------------------------------------------------------
%  ebuild spawn unblocks SIGINT (netkit BSD-signal configure)
% -----------------------------------------------------------------------------
%
% Jobserver workers are SWI threads that block SIGINT. process_create/3
% inherits that mask, so netkit ./configure's kill(getpid(), SIGINT)
% probe never fires and MCONFIG is never written. Both argv sinks prefix
% exec-unblocked.

:- begin_tests(ebuild_exec_unblocked).

test(null_sink_prefixes_helper) :-
  ebuild_exec:ebuild_argv(null, ebuild, '/tmp/x.ebuild', ["compile"],
                          path(python3), Argv, [stdout(null), stderr(null)]),
  Argv = [Helper, ebuild, '--skip-manifest', '/tmp/x.ebuild', "compile"],
  atom_concat(_, 'exec-unblocked', Helper).

test(log_sink_prefixes_helper) :-
  ebuild_exec:ebuild_argv(log('/tmp/x.log'), ebuild, '/tmp/x.ebuild', ["compile"],
                          path(sh), Argv, []),
  Argv = ['-c', _Script, '_', python3, Helper, ebuild, '/tmp/x.ebuild',
          '/tmp/x.log', "compile"],
  atom_concat(_, 'exec-unblocked', Helper).

test(helper_clears_sigint_mask) :-
  ebuild_exec:exec_unblocked(Helper),
  process_create(path(python3), [Helper, '--self-test'],
                 [process(Pid), stdout(null), stderr(null)]),
  process_wait(Pid, Status),
  assertion(Status == exit(0)).

:- end_tests(ebuild_exec_unblocked).
