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
detection, the VDB reconciliation backstop, and git URI option-injection
rejection (download:git_uri_safe/1).
*/

:- module(buildertest, []).

:- use_module(library(plunit)).
:- use_module(library(lists)).
:- use_module(library(assoc)).

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
%  Planned BWU wins over leftover ^^ suggestion (portage-ng#120)
% -----------------------------------------------------------------------------
%
% The install job for acct-user/git[gitea] can still carry a leftover
% required_use conflict plus suggestion(use_change, [gitea, gitolite])
% next to the planned build_with_use:use_state([gitea], []). The
% executor must not enable gitolite.

:- begin_tests(builder_ctx_use_overrides).

test(planned_bwu_wins_over_leftover_sibling,
     [true(Gitea-Git-Gitolite == positive-negative-negative)]) :-
  empty_assoc(Empty),
  put_assoc(git, Empty, negative, A1),
  put_assoc(gitea, A1, negative, A2),
  put_assoc(gitolite, A2, negative, Base),
  Ctx = [
    build_with_use:use_state([gitea], []),
    required_use:[assumed(conflict(required_use,
      exactly_one_of_group([required(git), required(gitea),
                            required(gitolite)])))],
    suggestion(use_change, qtest://'acct-user/git-0',
               [use_change(gitea, enable), use_change(gitolite, enable)])
  ],
  ebuild_exec:apply_ctx_use_overrides(Ctx, Base, Out),
  get_assoc(gitea, Out, Gitea),
  get_assoc(git, Out, Git),
  get_assoc(gitolite, Out, Gitolite).

test(empty_bwu_still_applies_suggestion,
     [true(Gitea == positive)]) :-
  empty_assoc(Empty),
  put_assoc(gitea, Empty, negative, Base),
  Ctx = [suggestion(use_change, qtest://'p-1', [use_change(gitea, enable)])],
  ebuild_exec:apply_ctx_use_overrides(Ctx, Base, Out),
  get_assoc(gitea, Out, Gitea).

:- end_tests(builder_ctx_use_overrides).


% -----------------------------------------------------------------------------
%  Linkage tests
% -----------------------------------------------------------------------------
:- begin_tests(linkage_is_linkable).

test(shared_object, [nondet]) :-
  linkage:is_linkable('/usr/lib64/libz.so').

test(versioned_so, [nondet]) :-
  linkage:is_linkable('/usr/lib64/libz.so.1.2.13').

test(usr_bin, [nondet]) :-
  linkage:is_linkable('/usr/bin/bash').

test(usr_sbin, [nondet]) :-
  linkage:is_linkable('/usr/sbin/sshd').

test(usr_lib_prefix, [nondet]) :-
  linkage:is_linkable('/usr/lib64/something').

test(bin, [nondet]) :-
  linkage:is_linkable('/bin/sh').

test(sbin, [nondet]) :-
  linkage:is_linkable('/sbin/init').

test(lib_prefix, [nondet]) :-
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

test(reconcile_active_false_when_merge_missing, [setup(stash_build_phases(Saved)),
                                                   cleanup(restore_build_phases(Saved))]) :-
  % Drop `merge` from the build phases. Reconciliation must short-circuit
  % to Active=false with Missing=[] regardless of plan contents.
  retractall(config:build_phases(_)),
  assertz(config:build_phases([clean, setup, unpack, prepare, configure, compile, test, install])),
  Plan = [[rule(portage://'no-such-cat/no-such-pkg-0.0':install?{[]}, [])]],
  builder:reconcile_install_actions(Plan, Missing, Active),
  Active == false,
  Missing == [].

test(reconcile_flags_missing_install_when_active,
     [setup(( stash_build_phases(Saved), stash_done_marks(Marks) )),
      cleanup(( restore_build_phases(Saved), restore_done_marks(Marks) )),
      condition((eapi_repo_registered, pkg_repo_registered))]) :-
  % Build phases include merge, and a registered pkg repo on
  % the host = reconciliation is active. Only install steps recorded
  % as done (resume:done/2) are checked; a succeeded merge with no VDB
  % row must be reported missing.
  retractall(config:build_phases(_)),
  assertz(config:build_phases([clean, setup, unpack, prepare, configure, compile, test, install, merge])),
  assertz(resume:done('no-such-cat/no-such-pkg-0.0', install)),
  Plan = [[rule(portage://'no-such-cat/no-such-pkg-0.0':install?{[]}, [])]],
  builder:reconcile_install_actions(Plan, Missing, Active),
  Active == true,
  Missing = [_|_],
  member(portage://'no-such-cat/no-such-pkg-0.0':install, Missing).

test(reconcile_ignores_failed_install_without_resume_done,
     [setup(( stash_build_phases(Saved), stash_done_marks(Marks) )),
      cleanup(( restore_build_phases(Saved), restore_done_marks(Marks) )),
      condition((eapi_repo_registered, pkg_repo_registered))]) :-
  % portage-ng#11: failed/skipped installs stay out of the plan but must
  % not inflate the reconciliation failure tally.
  retractall(config:build_phases(_)),
  assertz(config:build_phases([clean, setup, unpack, prepare, configure, compile, test, install, merge])),
  Plan = [[rule(portage://'no-such-cat/no-such-pkg-0.0':install?{[]}, [])]],
  builder:reconcile_install_actions(Plan, Missing, Active),
  Active == true,
  Missing == [].

test(apply_reconciliation_increments_failed_count,
     [setup(( stash_build_phases(Saved), stash_done_marks(Marks) )),
      cleanup(( restore_build_phases(Saved), restore_done_marks(Marks) )),
      condition((eapi_repo_registered, pkg_repo_registered))]) :-
  retractall(config:build_phases(_)),
  assertz(config:build_phases([clean, setup, unpack, prepare, configure, compile, test, install, merge])),
  assertz(resume:done('no-such-cat/no-such-pkg-0.0', install)),
  Plan = [[rule(portage://'no-such-cat/no-such-pkg-0.0':install?{[]}, [])]],
  with_output_to(string(_),
    builder:apply_vdb_reconciliation(Plan, 0, Failed, Missing)),
  Missing \= [],
  Failed > 0.

test(apply_reconciliation_leaves_failed_alone_when_inactive, [setup(stash_build_phases(Saved)),
                                                               cleanup(restore_build_phases(Saved))]) :-
  retractall(config:build_phases(_)),
  assertz(config:build_phases([])),
  Plan = [[rule(portage://'no-such-cat/no-such-pkg-0.0':install?{[]}, [])]],
  builder:apply_vdb_reconciliation(Plan, 7, Failed, Missing),
  Failed == 7,
  Missing == [].

% --- helpers -----------------------------------------------------------------

stash_build_phases(Saved) :-
  findall(P, config:build_phases(P), Saved).

restore_build_phases(Saved) :-
  retractall(config:build_phases(_)),
  forall(member(P, Saved), assertz(config:build_phases(P))).

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
                          path(python3), Argv, []),
  Argv = [Helper, ebuild, '--skip-manifest', '/tmp/x.ebuild', "compile"],
  atom_concat(_, 'exec-unblocked', Helper).

test(helper_clears_sigint_mask) :-
  ebuild_exec:exec_unblocked(Helper),
  process_create(path(python3), [Helper, '--self-test'],
                 [process(Pid), stdout(null), stderr(null)]),
  process_wait(Pid, Status),
  assertion(Status == exit(0)).

:- end_tests(ebuild_exec_unblocked).


% -----------------------------------------------------------------------------
%  Git URI option-injection reject (pkgcore 9c6ae8d)
% -----------------------------------------------------------------------------

:- begin_tests(download_git_uri_safe).

test(https_ok) :-
  download:git_uri_safe('https://git.example/repo.git').

test(git_scheme_ok) :-
  download:git_uri_safe('git://git.example/repo.git').

test(git_plus_https_ok) :-
  download:git_uri_safe('git+https://git.example/repo.git').

test(git_plus_ssh_ok) :-
  download:git_uri_safe('git+ssh://git.example/repo.git').

test(leading_dash_rejected, [fail]) :-
  download:git_uri_safe('--upload-pack=evil').

test(git_plus_dash_rejected, [fail]) :-
  download:git_uri_safe('git+--upload-pack=evil').

test(require_unsafe_fails, [fail]) :-
  download:require_git_uri_safe('--upload-pack=evil').

:- end_tests(download_git_uri_safe).


% -----------------------------------------------------------------------------
%  Auto-config write boundary (package.* persistence)
% -----------------------------------------------------------------------------
%
% Lines persisted to /etc/portage/package.* are validated at the write
% boundary: single line, well-formed atom token, safe keyword/flag
% tokens. Invalid lines are refused and never reach the file.

:- begin_tests(builder_auto_config).

%! autoconf_mktemp_dir(-Dir) is det.
%
% Fresh empty temporary directory used as a scratch portage_confdir.

autoconf_mktemp_dir(Dir) :-
  tmp_file(builderautoconf, Tmp),
  ( exists_file(Tmp) -> delete_file(Tmp) ; true ),
  make_directory(Tmp),
  Dir = Tmp.


%! autoconf_rm_rf(+Dir) is det.
%
% Remove a scratch confdir tree created by autoconf_mktemp_dir/1.

autoconf_rm_rf(Dir) :-
  ( exists_directory(Dir)
  -> catch(process_create(path(rm), ['-rf', Dir], [process(Pid)]), _, true),
     ( var(Pid) -> true ; process_wait(Pid, _) )
  ;  true
  ).

test(format_use_changes_keeps_safe_flags,
     [true(Atom == 'ssl -doc')]) :-
  builder:format_use_changes(
    [use_change(ssl, enable), use_change(doc, disable)], Atom).

test(format_use_changes_drops_unsafe_flags,
     [true(Atom == 'ssl')]) :-
  builder:format_use_changes(
    [use_change(ssl, enable),
     use_change('evil flag', enable),
     use_change('x\ny', disable)], Atom).

test(keyword_token_shapes,
     [true(A-B-C-D == amd64-'~amd64'-amd64-'**')]) :-
  builder:keyword_token(stable(amd64), A),
  builder:keyword_token(unstable(amd64), B),
  builder:keyword_token(amd64, C),
  builder:keyword_token('**', D).

test(keyword_token_rejects_term, [fail]) :-
  builder:keyword_token(evil(amd64), _).

test(write_valid_use_line) :-
  autoconf_mktemp_dir(Dir),
  setup_call_cleanup(
    true,
    ( builder:write_auto_config(Dir, 'package.use',
                                '=cat/pkg-1.0 ssl -doc'),
      os:compose_path([Dir, 'package.use', '00portage-ng-auto'], Path),
      exists_file(Path),
      read_file_to_string(Path, Content, []),
      once(sub_string(Content, _, _, _, "=cat/pkg-1.0 ssl -doc"))
    ),
    autoconf_rm_rf(Dir)).

test(write_refuses_newline_injection) :-
  autoconf_mktemp_dir(Dir),
  setup_call_cleanup(
    true,
    ( format(atom(Bad), '~w~n~w',
             ['=cat/pkg-1.0 ssl', '=evil/pkg-9.9 pwned']),
      builder:write_auto_config(Dir, 'package.use', Bad),
      os:compose_path([Dir, 'package.use', '00portage-ng-auto'], Path),
      \+ exists_file(Path)
    ),
    autoconf_rm_rf(Dir)).

test(write_refuses_bad_keyword) :-
  autoconf_mktemp_dir(Dir),
  setup_call_cleanup(
    true,
    ( builder:write_auto_config(Dir, 'package.accept_keywords',
                                '=cat/pkg-1.0 stable(amd64)'),
      os:compose_path([Dir, 'package.accept_keywords',
                       '00portage-ng-auto'], Path),
      \+ exists_file(Path)
    ),
    autoconf_rm_rf(Dir)).

:- end_tests(builder_auto_config).


% -----------------------------------------------------------------------------
%  Blocking domain assumption gate (portage-ng#125)
% -----------------------------------------------------------------------------

:- begin_tests(builder_blocking_assumptions).

test(use_dep_unsat_blocks_build) :-
  Unsat = grouped_package_dependency('x11-libs', libXau, []):install?{
            [assumption_reason(unsatisfied_constraints),
             required_use_violation(use_dep_unsat(portage://'x11-libs/libXau-1.0.12',
                                                  use_state([abi_x86_32], []),
                                                  profile_hard_conflict))]},
  empty_assoc(E),
  Ann = proof_annotations([], [], [], [], [], E, [], [Unsat]),
  builder:plan_has_blocking_domain_assumptions(Ann).

test(soft_blocker_alone_does_not_block_build, [fail]) :-
  Blk = blocker(weak, run, 'media-libs', mesa, none, version_none, []),
  empty_assoc(E),
  Ann = proof_annotations([], [], [], [], [], E, [], [Blk]),
  builder:plan_has_blocking_domain_assumptions(Ann).

test(no_tree_ebuild_orphan_does_not_block_build, [fail]) :-
  Orphan = (pkg://'dev-libs/orphan-1.0':update)?{[assumption_reason(no_tree_ebuild)]},
  empty_assoc(E),
  Ann = proof_annotations([], [], [], [], [], E, [], [Orphan]),
  builder:plan_has_blocking_domain_assumptions(Ann).

:- end_tests(builder_blocking_assumptions).


% -----------------------------------------------------------------------------
%  Full coverage for Domain/Gentoo/Ebuild/ebuild_exec.pl
% -----------------------------------------------------------------------------

:- dynamic ebtest_repo:get_ebuild_file/2.

ebuild_exec:ebtest_cb(_Phase, _Event).
ebtest_cb(_Phase, _Event).

:- begin_tests(ebuild_exec_full_coverage).

test(ebuild_exec_all_phases_and_hooks, [nondet]) :-
  tmp_file(ebtest_cov, TmpDir),
  make_directory_path(TmpDir),
  os:compose_path(TmpDir, 'logs', LogDir),
  os:compose_path(TmpDir, 'Knowledge', KDir),
  make_directory_path(LogDir),
  make_directory_path(KDir),
  os:compose_path(TmpDir, 'pkg-1.0.ebuild', EbuildPath),
  setup_call_cleanup(open(EbuildPath, write, SE), writeln(SE, '# ebuild'), close(SE)),
  os:compose_path(LogDir, 'test.log', LogPath),
  setup_call_cleanup(
    open(LogPath, write, SL),
    writeln(SL, 'ecompress: line 106: wait: pid 822745 is not a child of this shell'),
    close(SL)),
  V1 = version([1,0], '', 4, 0, [], 0, '1.0'),
  setup_call_cleanup(
    ( setenv('PORTAGE_NG_STATE', TmpDir),
      asserta(config:build_log_dir(LogDir)),
      asserta(config:ebuild_command(true)),
      asserta(config:cli_prefix('/opt/gentoo')),
      asserta(ebtest_repo:get_ebuild_file('ecat/epkg-1.0', EbuildPath)),
      asserta(ebtest_repo:get_ebuild_file('sys-devel/gcc-15.0', EbuildPath)),
      asserta(ebtest_repo:get_ebuild_file('dev-lang/ghc-9.8', EbuildPath)),
      assertz(cache:ordered_entry(ebtest_repo, 'ecat/epkg-1.0', ecat, epkg, V1)),
      assertz(cache:entry_metadata(ebtest_repo, 'ecat/epkg-1.0', defined_phases, [compile, install])),
      assertz(cache:entry_metadata(ebtest_repo, 'ecat/epkg-1.0', iuse, plus(flag_a))),
      assertz(cache:entry_metadata(ebtest_repo, 'ecat/epkg-1.0', iuse, minus(flag_b))),
      assertz(cache:ordered_entry(ebtest_repo, 'sys-devel/gcc-15.0', 'sys-devel', gcc, V1)),
      assertz(cache:entry_metadata(ebtest_repo, 'sys-devel/gcc-15.0', slot, slot('15'))),
      assertz(cache:ordered_entry(ebtest_repo, 'dev-lang/ghc-9.8', 'dev-lang', ghc, V1)),
      retractall(config:build_phases(_)),
      asserta(config:build_phases([clean, setup]))
    ),
    with_output_to(string(_),
      ( % 1. Action phases & FEATURES=test
        forall(member(Act, [install, run, reinstall, update, downgrade, uninstall]),
               ebuild_exec:action_phases(Act, [], _)),
        setenv('FEATURES', 'test -test test other'),
        ebuild_exec:features_test_enabled,
        unsetenv('FEATURES'),
        % 2. Ebuild path, defined_phases, display_phases, build_log_path, ensure_log_dir
        ebuild_exec:ebuild_path(ebtest_repo, 'ecat/epkg-1.0', EbuildPath),
        ebuild_exec:defined_phases(ebtest_repo, 'ecat/epkg-1.0', _),
        ebuild_exec:display_phases(install, ebtest_repo, 'ecat/epkg-1.0', [], _),
        ebuild_exec:ensure_log_dir,
        ebuild_exec:build_log_path('ecat/epkg-1.0', _),
        % 3. Phase stats wrappers
        ebuild_exec:phase_stats_file(_),
        ebuild_exec:record_phase_stats('ecat/epkg-1.0', compile, 100, 1.5),
        ebuild_exec:save_phase_stats,
        ebuild_exec:load_phase_stats_file,
        ebuild_exec:load_phase_stats,
        ebuild_exec:phase_bytes('ecat/epkg-1.0', compile, _),
        ebuild_exec:phase_seconds('ecat/epkg-1.0', compile, _),
        ebuild_exec:expected_phase_stats('ecat/epkg-1.0', compile, _, _),
        ebuild_exec:log_file_size(LogPath, _),
        % 4. USE string & prefix_env & dual_progress
        ebuild_exec:collect_use_string(ebtest_repo, 'ecat/epkg-1.0', [], _),
        ebuild_exec:prefix_env(['EPREFIX'='/opt/gentoo']),
        ebuild_exec:dual_progress(50, 100, 1.0, 2.0, _),
        % 5. Serial & transient retry helpers
        forall(member(SP, [compile, test, install]), ebuild_exec:serial_retry_phase(SP)),
        ebuild_exec:serial_env(_),
        ebuild_exec:log_serial_retry(LogPath, compile, 2),
        ebuild_exec:maybe_serial_retry(EbuildPath, compile, LogPath, '', ebtest_cb, 0, 0),
        ebuild_exec:maybe_serial_retry(EbuildPath, compile, LogPath, '', ebtest_cb, 2, 0),
        ebuild_exec:transient_phase_error(LogPath, 0),
        ebuild_exec:log_transient_retry(LogPath, install, 1),
        ebuild_exec:maybe_transient_retry(EbuildPath, install, LogPath, '', ebtest_cb, 0, 0, 0),
        ebuild_exec:maybe_transient_retry(EbuildPath, install, LogPath, '', ebtest_cb, 0, 1, 0),
        ebuild_exec:apply_build_retries(EbuildPath, compile, LogPath, '', ebtest_cb, 0, 1, _),
        ebuild_exec:apply_retry_list([unknown_strategy], EbuildPath, compile, LogPath, '', ebtest_cb, 0, 0, 0),
        % 6. Phase execution & locks
        ebuild_exec:run_phase_logged(EbuildPath, setup, LogPath, '', 0),
        ebuild_exec:with_portage_pkg_merge_lock(merge, true),
        ebuild_exec:with_portage_pkg_merge_lock(qmerge, true),
        ebuild_exec:with_portage_pkg_merge_lock(compile, true),
        % 7. Toolchain & GHC reactivation hooks
        forall(member(TC-TN-TK, [
          'sys-devel'-gcc-compiler,
          'llvm-core'-clang-runtime,
          'sys-devel'-clang-runtime,
          'sys-devel'-binutils-runtime,
          'sys-libs'-glibc-runtime
        ]), ebuild_exec:toolchain_cn(TC, TN, TK)),
        ebuild_exec:gcc_profile_major(ebtest_repo, 'sys-devel/gcc-15.0', '15'),
        ebuild_exec:gcc_chost_from_profile('x86_64-pc-linux-gnu-15', 'x86_64-pc-linux-gnu'),
        \+ ebuild_exec:select_gcc_profile('../unsafe'),
        os:compose_path(TmpDir, 'gcc-config', FakeGccConfig),
        setup_call_cleanup(
          open(FakeGccConfig, write, SGC),
          format(SGC, '#!/bin/sh~necho x86_64-pc-linux-gnu-15~n', []),
          close(SGC)),
        filesex:chmod(FakeGccConfig, 0o755),
        getenv('PATH', OldPath),
        atomic_list_concat([TmpDir, ':', OldPath], NewPath),
        setup_call_cleanup(
          setenv('PATH', NewPath),
          ebuild_exec:select_gcc_profile('15'),
          setenv('PATH', OldPath)),
        ebuild_exec:run_logged_cmd(path(true), []),
        ebuild_exec:capture_cmd(path(echo), ['hello'], 'hello'),
        ebuild_exec:maybe_reactivate_toolchain(install, ebtest_repo, 'sys-devel/gcc-15.0', done),
        ebuild_exec:maybe_reactivate_toolchain(run, ebtest_repo, 'sys-devel/gcc-15.0', done),
        ebuild_exec:maybe_register_ghc_pkg(install, ebtest_repo, 'dev-lang/ghc-9.8', done),
        ebuild_exec:maybe_register_ghc_pkg(run, ebtest_repo, 'dev-lang/ghc-9.8', done),
        % 8. Bulk & sequential execution, execute, execute_with_progress, fail_clean, inject_built
        ebuild_exec:run_phases(EbuildPath, [clean, setup, merge], '', 0),
        ebuild_exec:compute_live_prefix([], [clean], [], []),
        ebuild_exec:execute(run, ebtest_repo, 'ecat/epkg-1.0', [], done),
        ebuild_exec:execute(uninstall, ebtest_repo, 'ecat/epkg-1.0', [], done),
        ebuild_exec:execute(install, ebtest_repo, 'ecat/epkg-1.0', [], done),
        ebuild_exec:execute_with_progress(install, ebtest_repo, 'ecat/epkg-1.0', [], ebtest_cb, done),
        preference:with_local_flag(usepkgonly,
          ( ebuild_exec:execute(install, ebtest_repo, 'ecat/epkg-1.0', [], failed(no_binpkg)),
            ebuild_exec:execute_with_progress(install, ebtest_repo, 'ecat/epkg-1.0', [], ebtest_cb, failed(no_binpkg)),
            ebuild_exec:binpkg_fallback(failed(b), install, ebtest_repo, 'ecat/epkg-1.0', [], failed(b)),
            ebuild_exec:binpkg_fallback_with_progress(failed(b), install, ebtest_repo, 'ecat/epkg-1.0', [], ebtest_cb, failed(b))
          )),
        ebuild_exec:binpkg_fallback(failed(b), install, ebtest_repo, 'ecat/epkg-1.0', [], done),
        ebuild_exec:binpkg_fallback_with_progress(failed(b), install, ebtest_repo, 'ecat/epkg-1.0', [], ebtest_cb, done),
        ebuild_exec:binpkg_outcome(true, done, done),
        preference:with_local_flag(buildpkg,
          ebuild_exec:maybe_inject_built(install, ebtest_repo, 'ecat/epkg-1.0', [], done)),
        preference:with_local_flag(failclean,
          ebuild_exec:maybe_fail_clean(ebtest_repo, 'ecat/epkg-1.0', [], failed(1)))
      )),
    ( unsetenv('PORTAGE_NG_STATE'),
      retractall(config:build_log_dir(LogDir)),
      retractall(config:ebuild_command(true)),
      retractall(config:cli_prefix('/opt/gentoo')),
      retractall(ebtest_repo:get_ebuild_file(_, _)),
      retractall(cache:ordered_entry(ebtest_repo, _, _, _, _)),
      retractall(cache:entry_metadata(ebtest_repo, _, _, _)),
      retractall(config:build_phases(_)),
      assertz(config:build_phases([clean, setup, unpack, prepare, configure, compile, test, install, merge])),
      catch(delete_directory_and_contents(TmpDir), _, true)
    )).

:- end_tests(ebuild_exec_full_coverage).


% -----------------------------------------------------------------------------
%  Full coverage for buildtime, display, jobserver, resume, snapshot, builder
% -----------------------------------------------------------------------------

:- dynamic btest_script_repo:get_type/1.
:- dynamic btest_script_repo:get_location/1.
:- dynamic world:load/0.

ebtest_repo:entry(E) :- cache:ordered_entry(ebtest_repo, E, _, _, _).
ebtest_repo:package(C, N) :- cache:package(ebtest_repo, C, N).
ebtest_repo:ebuild(E, C, N, V) :-
  cache:ordered_entry(ebtest_repo, E, C, N, Ver),
  eapi:version_full(Ver, V).

js_test_exec(Job, _Slot, Result) :-
  ( Job = slotted(LineOff, _, _, _, _, rule(_://ok:_?{_}, _), _)
  -> Result = result(LineOff, done)
  ; Job = slotted(_, _, _, _, _, rule(_://throw_err:_?{_}, _), _)
  -> throw(boom)
  ; Job = slotted(_, _, _, _, _, rule(_://fail_exec:_?{_}, _), _)
  -> fail
  ; Result = malformed_non_result_term
  ).

js_test_cb(_Slot, _Outcome).

:- begin_tests(builder_submodules_and_orchestrator_full_coverage).

test(buildtime_module_full_coverage, [nondet]) :-
  tmp_file(bt_cov, TmpDir),
  make_directory_path(TmpDir),
  os:compose_path([TmpDir, 'vdb', 'dev-libs', 'foo-1.0'], VdbEntryDir),
  make_directory_path(VdbEntryDir),
  os:compose_path(VdbEntryDir, 'SIZE', SizeFile),
  setup_call_cleanup(open(SizeFile, write, SS), writeln(SS, '500000'), close(SS)),
  os:compose_path(TmpDir, 'emerge.log', EmergeLog),
  setup_call_cleanup(
    open(EmergeLog, write, SE),
    ( writeln(SE, '1000:  >>> emerge (1 of 2) app-misc/bar-1.0 to /'),
      writeln(SE, '1045:  ::: completed emerge (1 of 2) app-misc/bar-1.0 to /'),
      writeln(SE, '1050:  >>> emerge (2 of 2) app-misc/bad_pv to /'),
      writeln(SE, '1060:  ::: completed emerge (2 of 2) app-misc/bad_pv to /'),
      writeln(SE, 'unrelated line')
    ),
    close(SE)),
  V1 = version([1,0], '', 4, 0, [], 0, '1.0'),
  os:compose_path(TmpDir, 'vdb', VdbDir),
  setup_call_cleanup(
    ( retractall(buildtime:loaded),
      retractall(buildtime:duration(_, _, _, _)),
      retractall(buildtime:pkg_size(_, _, _)),
      asserta(config:pkg_directory(VdbDir)),
      asserta(config:emerge_log_path(EmergeLog)),
      assertz(cache:ordered_entry(pkg, 'dev-libs/foo-1.0', 'dev-libs', foo, V1)),
      assertz(cache:ordered_entry(portage, 'dev-libs/foo-1.0', 'dev-libs', foo, V1))
    ),
    with_output_to(string(_),
      ( buildtime:load,
        buildtime:load,
        buildtime:estimate('app-misc', bar, 45),
        buildtime:estimate('dev-libs', foo, 10),
        buildtime:estimate('dev-qt', qtbase, 300),
        buildtime:estimate('app-misc', unknown_pkg, 30),
        forall(buildtime:heavy_category(_), true),
        buildtime:format_duration(7200, _),
        buildtime:format_duration(120, _),
        buildtime:format_duration(15, _),
        buildtime:estimate_plan(['app-misc'/bar, 'dev-libs'/foo], _, _),
        buildtime:estimate_plan_waves([[], ['app-misc'/bar, 'dev-libs'/foo]], _, _),
        buildtime:print_estimate('app-misc', bar),
        buildtime:print_plan_estimate(['app-misc'/bar, 'dev-libs'/foo])
      )),
    ( retractall(config:pkg_directory(VdbDir)),
      retractall(config:emerge_log_path(EmergeLog)),
      retractall(cache:ordered_entry(pkg, 'dev-libs/foo-1.0', _, _, _)),
      retractall(cache:ordered_entry(portage, 'dev-libs/foo-1.0', _, _, _)),
      retractall(buildtime:loaded),
      retractall(buildtime:duration(_, _, _, _)),
      retractall(buildtime:pkg_size(_, _, _)),
      catch(delete_directory_and_contents(TmpDir), _, true)
    )).

test(display_jobserver_resume_and_snapshot_coverage, [nondet]) :-
  tmp_file(bsub_cov, TmpDir),
  make_directory_path(TmpDir),
  os:compose_path(TmpDir, 'Knowledge', KDir),
  os:compose_path(TmpDir, 'snapshots', SnapBase),
  os:compose_path(TmpDir, 'world', WorldFile),
  make_directory_path(KDir),
  make_directory_path(SnapBase),
  setup_call_cleanup(open(WorldFile, write, SW), writeln(SW, 'ecat/epkg'), close(SW)),
  os:compose_path(TmpDir, 'epkg-1.0.ebuild', EbuildPath),
  setup_call_cleanup(open(EbuildPath, write, SE), writeln(SE, '# ebuild'), close(SE)),
  V1 = version([1,0], '', 4, 0, [], 0, '1.0'),
  V2 = version([2,0], '', 4, 0, [], 0, '2.0'),
  setup_call_cleanup(
    ( setenv('PORTAGE_NG_STATE', TmpDir),
      retractall(distfiles:get_location(_)),
      asserta(distfiles:get_location(TmpDir)),
      asserta(config:snapshot_dir(SnapBase)),
      asserta(config:world_file(WorldFile)),
      asserta(config:ebuild_command(true)),
      ( catch(world:declared(type(instance(set))), _, fail)
      -> world:init(WorldFile)
      ;  world:newinstance(set(WorldFile))
      ),
      asserta(ebtest_repo:get_type(eapi)),
      asserta(ebtest_repo:get_ebuild_file('ecat/epkg-1.0', EbuildPath)),
      asserta(ebtest_repo:get_ebuild_file('ecat/epkg-2.0', EbuildPath)),
      assertz(cache:ordered_entry(ebtest_repo, 'ecat/epkg-1.0', ecat, epkg, V1)),
      assertz(cache:entry_metadata(ebtest_repo, 'ecat/epkg-1.0', properties, live)),
      assertz(cache:ordered_entry(ebtest_repo, 'ecat/epkg-2.0', ecat, epkg, V2)),
      assertz(cache:ordered_entry(pkg, 'ecat/epkg-1.0', ecat, epkg, V1)),
      assertz(cache:entry_metadata(pkg, 'ecat/epkg-1.0', slot, slot('0')))
    ),
    with_output_to(string(_),
      ( % 1. display.pl
        display:print_pre_action_step([], 0),
        PreAct1 = unmask(ebtest_repo, 'ecat/epkg-1.0', ecat, epkg),
        PreAct2 = accept_keyword(ebtest_repo, 'ecat/epkg-1.0', ecat, epkg, unstable(amd64)),
        display:print_pre_action_step([PreAct1], 1),
        display:print_pre_action_step([PreAct1, PreAct2], 1),
        RulesDisp = [
          rule(ebtest_repo://'ecat/epkg-1.0':download?{[]}, []),
          rule(ebtest_repo://'ecat/epkg-2.0':download?{[]}, []),
          rule(ebtest_repo://'ecat/epkg-2.0':install?{[]}, []),
          rule(ebtest_repo://'ecat/epkg-2.0':uninstall?{[]}, []),
          rule(world('ecat/epkg'):register?{[]}, []),
          other_rule
        ],
        asserta(config:show_build_logs(true)),
        display:assign_slots(RulesDisp, 1, 1, SlottedDisp, TotalLines),
        retractall(config:show_build_logs(true)),
        display: assign_slots(RulesDisp, 1, 1, _, _),
        display:register_slot_info(SlottedDisp),
        display:get_slot_info(0, _, _, _, _, _),
        display:get_slot_info(999, 0, 0, 0, unknown, unknown),
        display:mark_skipped(SlottedDisp, TotalLines),
        display:clear_slot_info,
        % 2. jobserver.pl
        asserta(config:cli_load_average(9999.0)),
        jobserver:init(1, buildertest:js_test_exec),
        JobsJS = [
          slotted(0, 4, 1, 1, 0, rule(ebtest_repo://ok:install?{[]}, []), no_files),
          slotted(1, 4, 1, 1, 1, rule(ebtest_repo://throw_err:install?{[]}, []), no_files),
          slotted(2, 4, 1, 1, 2, rule(ebtest_repo://fail_exec:install?{[]}, []), no_files),
          unrecognised_job
        ],
        jobserver:submit(JobsJS),
        jobserver:collect(4, buildertest:js_test_cb),
        jobserver:shutdown(1),
        retractall(config:cli_load_average(9999.0)),
        % 3. resume.pl
        PlanRes = [[rule(ebtest_repo://'ecat/epkg-1.0':install?{[]}, []),
                    rule(ebtest_repo://'ecat/epkg-2.0':install?{[]}, [])]],
        resume:save_state([ebtest_repo://'ecat/epkg-2.0':run?{[]}], PlanRes),
        resume:mark_done(ebtest_repo://'ecat/epkg-1.0', install),
        resume:flush_done_to_disk,
        resume:load_state(_, LoadedPlan, DoneList),
        asserta(config:skip_atom('epkg-2.0')),
        resume:collect_skip_entries(LoadedPlan, SkipDone),
        retractall(config:skip_atom('epkg-2.0')),
        append(DoneList, SkipDone, AllDone),
        resume:filter_completed_plan(LoadedPlan, AllDone, [[]]),
        resume:clear_state,
        % 4. snapshot.pl
        snapshot:generate_id(_),
        snapshot:pad2(5, '05'),
        snapshot:pad2(12, '12'),
        PlanSnap = [[rule(ebtest_repo://'ecat/epkg-2.0':update?{[replaces(pkg://'ecat/epkg-1.0')]}, []),
                     assumed(rule(ebtest_repo://'ecat/epkg-1.0':install?{[replaces(pkg://'ecat/epkg-1.0')]}, []))]],
        snapshot:create('snap1', PlanSnap),
        \+ snapshot:create('snap1', PlanSnap),
        snapshot:quickpkg_old(ebtest_repo, 'ecat/epkg-1.0'),
        % Place a dummy .gpkg.tar inside snap1/binpkgs/ecat/
        snapshot:binpkg_dir('snap1', SnapBinDir),
        os:compose_path(SnapBinDir, 'ecat', SnapCatDir),
        make_directory_path(SnapCatDir),
        os:compose_path(SnapCatDir, 'epkg-1.0.gpkg.tar', SnapGpkg),
        setup_call_cleanup(open(SnapGpkg, write, SSG), write(SSG, 'x'), close(SSG)),
        % Prepend a non-timestamp term to manifest.pl to exercise find_timestamp recursion
        snapshot:manifest_path('snap1', SnapManPath),
        setup_call_cleanup(
          open(SnapManPath, write, SSM),
          ( writeln(SSM, 'other_header_fact.'),
            writeln(SSM, 'snapshot_timestamp(1000).'),
            format(SSM, 'installed(~q, ~q, ~q, ~q).~n', [ecat, epkg, V1, '0'])
          ),
          close(SSM)),
        snapshot:list,
        snapshot:diff('snap1'),
        % Mutate VDB to exercise Added / Removed / Changed in snapshot:diff
        retractall(cache:ordered_entry(pkg, 'ecat/epkg-1.0', _, _, _)),
        assertz(cache:ordered_entry(pkg, 'ecat/epkg-2.0', ecat, epkg, V2)),
        assertz(cache:ordered_entry(pkg, 'ecat/newpkg-1.0', ecat, newpkg, V1)),
        assertz(cache:ordered_entry(pkg, 'ecat/oldpkg-1.0', ecat, oldpkg, V1)),
        retractall(cache:ordered_entry(pkg, 'ecat/oldpkg-1.0', _, _, _)),
        snapshot:diff('snap1'),
        snapshot:rollback('snap1'),
        snapshot:delete('snap1'),
        snapshot:delete('snap_nonexistent'),
        snapshot:finalize
      )),
    ( unsetenv('PORTAGE_NG_STATE'),
      retractall(distfiles:get_location(TmpDir)),
      retractall(config:snapshot_dir(SnapBase)),
      retractall(config:world_file(WorldFile)),
      retractall(config:ebuild_command(true)),
      retractall(ebtest_repo:get_type(eapi)),
      retractall(ebtest_repo:get_ebuild_file(_, _)),
      retractall(cache:ordered_entry(ebtest_repo, _, _, _, _)),
      retractall(cache:entry_metadata(ebtest_repo, _, _, _)),
      retractall(cache:ordered_entry(pkg, 'ecat/epkg-1.0', _, _, _)),
      retractall(cache:ordered_entry(pkg, 'ecat/epkg-2.0', _, _, _)),
      retractall(cache:ordered_entry(pkg, 'ecat/newpkg-1.0', _, _, _)),
      retractall(cache:entry_metadata(pkg, 'ecat/epkg-1.0', _, _)),
      snapshot:finalize,
      catch(delete_directory_and_contents(TmpDir), _, true)
    )).

test(builder_orchestrator_full_coverage, [nondet]) :-
  tmp_file(borch_cov, TmpDir),
  make_directory_path(TmpDir),
  os:compose_path(TmpDir, 'Knowledge', KDir),
  os:compose_path(TmpDir, 'confdir', ConfDir),
  os:compose_path(TmpDir, 'logs', LogDir),
  make_directory_path(KDir),
  make_directory_path(ConfDir),
  make_directory_path(LogDir),
  os:compose_path(TmpDir, 'epkg-1.0.ebuild', EbuildPath),
  setup_call_cleanup(open(EbuildPath, write, SE), writeln(SE, '# ebuild'), close(SE)),
  V1 = version([1,0], '', 4, 0, [], 0, '1.0'),
  setup_call_cleanup(
    ( unittest:accept_stable_amd64,
      setenv('PORTAGE_NG_STATE', TmpDir),
      retractall(distfiles:get_location(_)),
      asserta(distfiles:get_location(TmpDir)),
      asserta(config:portage_confdir(ConfDir)),
      asserta(config:build_log_dir(LogDir)),
      asserta(config:ebuild_command(true)),
      asserta(config:cli_jobs(1)),
      asserta(ebtest_repo:get_type(eapi)),
      asserta(ebtest_repo:get_ebuild_file('ecat/epkg-1.0', EbuildPath)),
      asserta(btest_script_repo:get_type(git)),
      asserta(btest_script_repo:get_location(TmpDir)),
      assertz(cache:repository(ebtest_repo)),
      assertz(cache:category(ebtest_repo, ecat)),
      assertz(cache:package(ebtest_repo, ecat, epkg)),
      assertz(cache:ordered_entry(ebtest_repo, 'ecat/epkg-1.0', ecat, epkg, V1)),
      assertz(cache:entry_metadata(ebtest_repo, 'ecat/epkg-1.0', keywords, stable(amd64))),
      assertz(cache:entry_metadata(ebtest_repo, 'ecat/epkg-1.0', slot, slot('0')))
    ),
    with_output_to(string(_),
      ( % 1. End-to-end builder:build and builder:build_resume
        retractall(config:build_phases(_)),
        asserta(config:build_phases([])),
        builder:build([ebtest_repo://'ecat/epkg-1.0':run?{[]}]),
        % Save state and test build_resume (both with remaining work and with all done)
        Plan1 = [[rule(ebtest_repo://'ecat/epkg-1.0':install?{[]}, []),
                  rule(world('ecat/epkg'):register?{[]}, []),
                  rule(world('ecat/epkg'):unregister?{[]}, [])]],
        resume:save_state([ebtest_repo://'ecat/epkg-1.0':run?{[]}], Plan1),
        builder:build_resume,
        resume:save_state([ebtest_repo://'ecat/epkg-1.0':run?{[]}], Plan1),
        resume:mark_done(ebtest_repo://'ecat/epkg-1.0', install),
        resume:flush_done_to_disk,
        builder:build_resume,
        \+ builder:build_resume,
        % 2. Replan, skip_remaining, VDB reconciliation warning
        builder:should_replan(0, 1, 0, 1),
        builder:announce_replan(1),
        builder:print_reconciliation_warning([ebtest_repo://'ecat/epkg-1.0':install], 1),
        asserta(config:continue_on_failure(always)),
        builder:should_continue_on_failure,
        retractall(config:continue_on_failure(always)),
        builder:skip_remaining(Plan1, 1, 1, 0, 1, 0, _, _, _),
        % 3. Suggestions & auto-config
        CtxSugg = [suggestion(unmask, ebtest_repo://'ecat/epkg-1.0'),
                   suggestion(accept_keyword, unstable(amd64)),
                   suggestion(use_change, ebtest_repo://'ecat/epkg-1.0', [use_change(ssl, enable)])],
        builder:dispatch_suggestions(ebtest_repo, 'ecat/epkg-1.0', CtxSugg),
        builder:dispatch_suggestions(ebtest_repo, 'ecat/epkg-1.0', [suggestion(accept_keyword, keyword("amd64"))]),
        builder:dispatch_suggestions(ebtest_repo, 'ecat/epkg-1.0', not_a_list),
        builder:auto_config_line_ok('package.unmask', '=ecat/epkg-1.0'),
        builder:auto_config_line_ok('package.other', '=ecat/epkg-1.0 foo'),
        % 4. run_action, run_binpkg_action, run_action_with_phases, phase_callback, outcome_to_status
        builder:binpkg_merge_action(run, install),
        builder:binpkg_merge_action(install, install),
        \+ builder:is_executable_rule(rule(ebtest_repo://'ecat/epkg-1.0':annotate?{[]}, [])),
        \+ builder:is_executable_rule(non_rule_term),
        ignore(catch(builder:run_action(install, btest_script_repo, 'ecat/epkg-1.0', [], _), _, true)),
        builder:run_binpkg_action(install, 'ecat/missing-1.0-1', [], failed(no_source_ebuild)),
        builder:run_action(install, ebtest_repo, 'ecat/epkg-1.0', [], stub),
        retractall(config:build_phases(_)),
        asserta(config:build_phases([setup])),
        builder:run_action(install, ebtest_repo, 'ecat/epkg-1.0', [], done),
        builder:run_action(install, binpkg, 'ecat/missing-1.0-1', [], failed(no_source_ebuild)),
        builder:run_action_with_phases(install, binpkg, 'ecat/missing-1.0-1', [],
                                       2, 1, 1, -1, [setup], '', 0, 1, 1, 0, _),
        builder:run_action_with_phases(install, ebtest_repo, 'ecat/epkg-1.0', [],
                                       3, 1, 1, 2, [setup], '/tmp/t.log', 0, 1, 1, 0, _),
        builder:phase_callback(3, 1, 2, install, [setup], '/tmp/t.log', 'ecat/epkg-1.0', setup, failed(1)),
        builder:phase_callback(3, 1, 2, install, [setup], '/tmp/t.log', 'ecat/epkg-1.0', unlisted_phase, done),
        forall(member(Out-St, [
          done-done, stub-stub, failed(r)-failed(r),
          failed-failed('error'), error(e)-failed(e), other-failed('unknown')
        ]), builder:outcome_to_status(Out, St)),
        builder:execute_build_job(bad_job, 1, _),
        % 5. builder:test_stats and test_single
        retractall(config:build_phases(_)),
        asserta(config:build_phases([setup])),
        builder:test_stats(ebtest_repo),
        builder:test_stats(ebtest_repo, 5),
        builder:test_stats_pkgs(ebtest_repo, [ecat-epkg]),
        builder:test_plan_downloads([[rule(ebtest_repo://'ecat/epkg-1.0':download?{[]}, [])]])
      )),
    ( unsetenv('PORTAGE_NG_STATE'),
      retractall(distfiles:get_location(TmpDir)),
      retractall(config:portage_confdir(ConfDir)),
      retractall(config:build_log_dir(LogDir)),
      retractall(config:ebuild_command(true)),
      retractall(config:cli_jobs(1)),
      retractall(ebtest_repo:get_type(eapi)),
      retractall(ebtest_repo:get_ebuild_file(_, _)),
      retractall(btest_script_repo:get_type(_)),
      retractall(btest_script_repo:get_location(_)),
      retractall(cache:repository(ebtest_repo)),
      retractall(cache:category(ebtest_repo, _)),
      retractall(cache:package(ebtest_repo, _, _)),
      retractall(cache:ordered_entry(ebtest_repo, _, _, _, _)),
      retractall(cache:entry_metadata(ebtest_repo, _, _, _)),
      retractall(config:build_phases(_)),
      assertz(config:build_phases([clean, setup, unpack, prepare, configure, compile, test, install, merge])),
      catch(delete_directory_and_contents(TmpDir), _, true)
    )).

:- end_tests(builder_submodules_and_orchestrator_full_coverage).


% -----------------------------------------------------------------------------
%  A finished install closes phases the callback never named
% -----------------------------------------------------------------------------

:- begin_tests(builder_exec_phase_finish).

test(pending_phases_close_done, [cleanup(retractall(builder:exec_phase_state(99, _, _)))]) :-
  Phases = [clean, setup, unpack, prepare, configure, compile, install, merge],
  builder:init_exec_phase_state(99, Phases),
  builder:close_open_phases(99, Phases, done),
  builder:collect_phase_states(99, Phases, States),
  maplist([_-done]>>true, States).

test(closed_phase_is_kept, [cleanup(retractall(builder:exec_phase_state(99, _, _)))]) :-
  Phases = [clean, setup, merge],
  builder:init_exec_phase_state(99, Phases),
  retract(builder:exec_phase_state(99, clean, _)),
  assertz(builder:exec_phase_state(99, clean, done)),
  retract(builder:exec_phase_state(99, setup, _)),
  assertz(builder:exec_phase_state(99, setup, stub)),
  builder:close_open_phases(99, Phases, done),
  builder:exec_phase_state(99, clean, done),
  builder:exec_phase_state(99, setup, stub),
  builder:exec_phase_state(99, merge, done).

test(unmarked_failure_fails_open_phases, [cleanup(retractall(builder:exec_phase_state(99, _, _)))]) :-
  Phases = [clean, merge],
  builder:init_exec_phase_state(99, Phases),
  \+ builder:phase_already_failed(99),
  builder:close_open_phases(99, Phases, failed),
  builder:exec_phase_state(99, clean, failed),
  builder:exec_phase_state(99, merge, failed).

test(recorded_failure_skips_the_rest, [cleanup(retractall(builder:exec_phase_state(99, _, _)))]) :-
  Phases = [clean, compile, merge],
  builder:init_exec_phase_state(99, Phases),
  retract(builder:exec_phase_state(99, compile, _)),
  assertz(builder:exec_phase_state(99, compile, failed(1))),
  builder:phase_already_failed(99),
  builder:close_open_phases(99, Phases, skipped),
  builder:exec_phase_state(99, clean, skipped),
  builder:exec_phase_state(99, compile, failed(1)),
  builder:exec_phase_state(99, merge, skipped).

:- end_tests(builder_exec_phase_finish).


% -----------------------------------------------------------------------------
%  A build does not start when a planned ebuild is not on disk
% -----------------------------------------------------------------------------

:- dynamic ebcheck_repo:get_type/1.
:- dynamic ebcheck_repo:get_ebuild_file/2.

:- begin_tests(builder_missing_ebuild, [setup(ebcheck_reset), cleanup(ebcheck_reset)]).

test(missing_install_is_reported) :-
  asserta(ebcheck_repo:get_ebuild_file('app-editors/neovim-0.12.3',
                                       '/tmp/portage-ng-no-such-neovim-0.12.3.ebuild')),
  Plan = [[rule(ebcheck_repo://'app-editors/neovim-0.12.3':install?{[]}, []),
           rule(ebcheck_repo://'app-editors/neovim-0.12.3':run?{[]}, []),
           rule(world(neovim):register?{[]}, [])]],
  builder:missing_plan_ebuilds(Plan, Missing),
  Missing == [missing(ebcheck_repo, 'app-editors/neovim-0.12.3',
                      '/tmp/portage-ng-no-such-neovim-0.12.3.ebuild')].

test(present_ebuild_is_not_missing) :-
  Path = '/tmp/portage-ng-ebuild-present.ebuild',
  open(Path, write, Stream),
  close(Stream),
  setup_call_cleanup(
    asserta(ebcheck_repo:get_ebuild_file('app-editors/neovim-0.12.3', Path)),
    ( Plan = [[rule(ebcheck_repo://'app-editors/neovim-0.12.3':reinstall?{[]}, [])]],
      builder:missing_plan_ebuilds(Plan, Missing),
      Missing == []
    ),
    catch(delete_file(Path), _, true)).

test(run_does_not_require_an_ebuild) :-
  Plan = [[rule(ebcheck_repo://'app-editors/neovim-0.12.3':run?{[]}, [])]],
  builder:missing_plan_ebuilds(Plan, Missing),
  Missing == [].

test(duplicate_missing_ebuild_is_listed_once) :-
  asserta(ebcheck_repo:get_ebuild_file('app-editors/neovim-0.12.3',
                                       '/tmp/portage-ng-no-such-neovim-0.12.3.ebuild')),
  Rule = rule(ebcheck_repo://'app-editors/neovim-0.12.3':install?{[]}, []),
  builder:missing_plan_ebuilds([[Rule], [Rule]], Missing),
  length(Missing, 1).

test(report_names_the_missing_file) :-
  Missing = [missing(ebcheck_repo, 'app-editors/neovim-0.12.3',
                     '/tmp/portage-ng-no-such-neovim-0.12.3.ebuild')],
  with_output_to(string(Text), builder:report_missing_ebuilds(Missing)),
  once(sub_string(Text, _, _, _, 'not on disk')),
  once(sub_string(Text, _, _, _, '/tmp/portage-ng-no-such-neovim-0.12.3.ebuild')),
  once(sub_string(Text, _, _, _, 'rebuild the knowledge base')).

:- end_tests(builder_missing_ebuild).


ebcheck_reset :-
  retractall(ebcheck_repo:get_type(_)),
  retractall(ebcheck_repo:get_ebuild_file(_, _)),
  asserta(ebcheck_repo:get_type(eapi)).
