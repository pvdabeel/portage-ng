/*
 Author: Pieter Van den Abeele
 E-mail: pvdabeel@mac.com
 Copyright (c) 2005-2026, Pieter Van den Abeele

 Distributed under the terms of the LICENSE file in the root directory of this
 project.
*/

/** <module> MESSAGETEST
Unit tests for the message module's best-effort execution helper
(Source/Application/Output/message.pl).

message:catch_log/2 always succeeds: failure of the goal is normal
control flow, an exception is reported once per label.
*/

:- module(messagetest, []).

:- use_module(library(plunit)).
:- use_module(library(prolog_wrap)).

% =============================================================================
%  MESSAGETEST declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  catch_log tests
% -----------------------------------------------------------------------------

:- begin_tests(message_catch_log).

test(succeeding_goal_runs) :-
  message:catch_log('messagetest:ok', true).

test(failing_goal_is_swallowed) :-
  message:catch_log('messagetest:fail', fail).

test(throwing_goal_is_swallowed) :-
  message:catch_log('messagetest:throw',
                    throw(error(test_error, messagetest))).

test(report_once_per_label) :-
  retractall(message:catch_log_warned('messagetest:once')),
  message:catch_log('messagetest:once',
                    throw(error(first, messagetest))),
  message:catch_log_warned('messagetest:once'),
  % Second throw under the same label stays silent but still succeeds.
  message:catch_log('messagetest:once',
                    throw(error(second, messagetest))),
  retractall(message:catch_log_warned('messagetest:once')).

:- end_tests(message_catch_log).


% -----------------------------------------------------------------------------
%  Full coverage for Application/System/*, Performance/*, Output/{message,writer,report}, config, loader
% -----------------------------------------------------------------------------

:- dynamic interface:get_port/1.

:- begin_tests(application_sys_perf_output_cfg_coverage).

test(message_and_report_full_coverage, [nondet]) :-
  with_output_to(string(_),
    ( % 1. Stub predicates in message.pl (meta-called to bypass goal_expansion)
      forall(member(Stub, [
        color(red), bgcolor(red), style(bold), bell, el, hc, sc, bl, cl,
        clean, title_reset, title('t'), print('p'), column(10, 'c'),
        level(inform), msg(false, inform, 'm'), msg(inform, 'm'),
        scroll_msg(inform, 'm'), failure('f'), warning('w'), success('s'),
        inform('i'), notice('n'), debug('d'), log('l'), scroll('sc'),
        scroll_failure('sf'), scroll_warning('sw'), scroll_success('ss'),
        scroll_inform('si'), scroll_notice('sn'), scroll_debug('sd'),
        scroll_log('sl')
      ]), message:Stub),
      % 2. All ansi_code/2 facts
      forall(message:ansi_code(_, _), true),
      ignore(message:ansi_escapes_affect_line_pos),
      % 3. Bubbles (powerline & angle, colored & plain)
      setup_call_cleanup(
        ( retractall(console:powerline_bubbles_cached(_)),
          asserta(console:powerline_bubbles_cached(false)) ),
        ( message:bubble(green, 'ok'),
          message:bubble(red, 'step  1'),
          message:bubble_plain_angle('plain') ),
        retractall(console:powerline_bubbles_cached(_))),
      % 4. Gradients, logo, eend, hl, debug flags, datetime, spinners, clear, wrap
      message:print_gradient(""),
      message:print_gradient("ab"),
      message:logo(['portage', '-ng']),
      message:logo(['portage', '-ng'], standalone),
      message:eend('ok'),
      message:hl('Section'),
      message:hl,
      message:enable_debug,
      message:is_debug_enabled,
      message:disable_debug,
      message:datetime(_),
      forall(member(SpStyle, [braille, block, quarter, line]),
             message:spinner_frame(SpStyle, 1, _)),
      message:clear,
      message:wrap(true),
      % 5. report.pl
      V1 = version([1,0], '', 4, 0, [], 0, '1.0'),
      V2 = version([2,0], '', 4, 0, [], 0, '2.0'),
      setup_call_cleanup(
        ( unittest:accept_stable_amd64,
          assertz(cache:ordered_entry(pkg, 'rcat/removed-1.0', rcat, removed, V1)),
          assertz(cache:ordered_entry(pkg, 'rcat/masked-1.0',  rcat, masked,  V1)),
          assertz(cache:ordered_entry(pkg, 'rcat/outdated-1.0', rcat, outdated, V1)),
          assertz(cache:ordered_entry(portage, 'rcat/masked-1.0', rcat, masked, V1)),
          assertz(cache:entry_metadata(portage, 'rcat/masked-1.0', masked, true)),
          assertz(cache:ordered_entry(portage, 'rcat/outdated-2.0', rcat, outdated, V2)),
          assertz(cache:entry_metadata(portage, 'rcat/outdated-2.0', keywords, stable(amd64)))
        ),
        ( report:extract_name('rcat/unindexed-1.0', unindexed),
          report:extract_name('rcat/noversion', noversion),
          report:check(Issues),
          report:print_results([]),
          report:print_results([issue('rcat/other-1.0', unknown_type, d)|Issues])
        ),
        ( retractall(cache:ordered_entry(pkg, 'rcat/removed-1.0', _, _, _)),
          retractall(cache:ordered_entry(pkg, 'rcat/masked-1.0', _, _, _)),
          retractall(cache:ordered_entry(pkg, 'rcat/outdated-1.0', _, _, _)),
          retractall(cache:ordered_entry(portage, 'rcat/masked-1.0', _, _, _)),
          retractall(cache:entry_metadata(portage, 'rcat/masked-1.0', _, _)),
          retractall(cache:ordered_entry(portage, 'rcat/outdated-2.0', _, _, _)),
          retractall(cache:entry_metadata(portage, 'rcat/outdated-2.0', _, _))
        ))
    )).

test(choicelog_and_sampler_full_coverage, [nondet]) :-
  V1 = version([1,0], '', 4, 0, [], 0, '1.0'),
  setup_call_cleanup(
    assertz(cache:ordered_entry(qtest, 'scat/spkg-1.0', scat, spkg, V1)),
    with_output_to(string(_),
      ( % 1. choicelog.pl (meta-call gated predicates so goal_expansion doesn't strip them)
        choicelog:arm,
        choicelog:armed,
        choicelog:reset,
        choicelog:with_logging(true),
        choicelog:arm,
        choicelog:emit(any_of, trying, any_of(p, 1, 2, a)),
        GWrap = clog_wrap(version, version(p, c, n, V1, '0', 1, 1), true),
        choicelog:GWrap,
        choicelog:wrap(reject, reject(c, n, dom, [a], [r]), true),
        \+ choicelog:wrap(learn, learn(l, c, true), fail),
        GAny = wrap_any_of([self(qtest://'scat/spkg-1.0')],
                           [grouped_package_dependency(no, c, n,
                              [package_dependency(install, no, c, n, equal, V1, [slot('0')], [use(enable(u), none)])])],
                           grouped_package_dependency(no, c, n,
                              [package_dependency(install, no, c, n, equal, V1, [slot('0')], [use(enable(u), none)])]),
                           true),
        choicelog:GAny,
        forall(member(ArmTerm, [
          grouped_package_dependency(no, c, n, []),
          package_dependency(install, no, c, n, none, version_none, [], []),
          all_of_group([a]),
          any_of_group([a]),
          use_conditional_group(positive, u, _://_, []),
          other_arm
        ]), choicelog:summarize_arm(ArmTerm, _)),
        forall(member(DataTerm, [
          any_of(p, 1, 2, a),
          any_of(p, 1, 2, a, r),
          version(p, c, n, V1, '0', 1, 1),
          version(p, c, n, version_none, '0', 1, 1),
          reject(c, n, dom, [a], [r]),
          learn(l, c, true),
          reprove(info),
          assumption(t, l),
          other_data
        ]), choicelog:format_data(DataTerm, _)),
        GDump = maybe_dump,
        choicelog:GDump,
        choicelog:disarm,
        choicelog:GWrap,
        choicelog:GAny,
        % 2. sampler.pl (meta-call gated predicates)
        forall(member(SG, [
          hook_perf_reset, hook_done_hit, hook_fired([a]), hook_fresh([b]),
          hook_counter_reset, hook_counter_report, hook_perf_report,
          phase_walltime(_), phase_record(0, 10, 25), phase_perf_reset,
          phase_perf_report, rule_call, maybe_timeout_trace(required(u))
        ]), sampler:SG),
        sampler:hook_maybe_sample(true),
        sampler:pdepend_perf_reset,
        sampler:pdepend_perf_report,
        sampler:pdepend_perf_add(10, 2, 5, 1, 3),
        sampler:pdepend_perf_report,
        sampler:phase_perf_add(10, 5),
        SPReport = phase_perf_report,
        sampler:SPReport,
        sampler:reset_counters,
        SRule = rule_call,
        sampler:SRule,
        sampler:ctx_union([self(a), x], [self(b), y], _),
        sampler:ctx_union_raw([x], [y], _),
        sampler:ctx_counters(_, _, _, _),
        sampler:ctx_distribution(_, _, _, _),
        sampler:reset('Proving', 2),
        sampler:stage_at_least(prover),
        forall(sampler:stage_rank(_, _), true),
        sampler:set_current_entry(qtest://'scat/spkg-1.0'),
        sampler:note_cycle_for_entry,
        sampler:clear_current_entry,
        sampler:inc(type(t1, occurrences, 1)),
        sampler:inc(cycle_mention(run, qtest://'scat/spkg-1.0')),
        sampler:inc(type_entry_mention(t1, qtest://'scat/spkg-1.0')),
        sampler:inc(other_head(domain(foo(bar)))),
        sampler:inc(blocker_reason(r1, run)),
        sampler:record(failed_entry(qtest://'scat/spkg-1.0', other)),
        sampler:record(blocker_breakdown(weak, run, scat, spkg)),
        sampler:record(costs(qtest://'scat/spkg-1.0', 10, 100, 5)),
        sampler:record(costs(qtest://'scat/spkg-1.0', 20, 200, 10)),
        sampler:record(ctx_costs(qtest://'scat/spkg-1.0', 5, 10, 3)),
        sampler:record(ctx_costs(qtest://'scat/spkg-1.0', 8, 20, 4, 2)),
        sampler:record(ctx_dist([2-3, 4-1], 10, 5, 4)),
        sampler:record(blocker(domain(blocker(weak, run, scat, spkg, none, version_none, []):run?{[assumption_reason(r1)]}))),
        sampler:record(blocker(unparseable_blocker)),
        sampler:record(cycle([], [qtest://'scat/spkg-1.0':run?{[]}])),
        % Timeout trace & simplify
        sampler:timeout_trace_reset,
        STrace = maybe_timeout_trace(required(u)),
        sampler:STrace,
        forall(member(TItem, [
          _Var, required(u), assumed(u), naf(required(u)), naf(blocking(u)),
          naf(other), conflict(a, b), foo:install, constraint(k:{v}),
          use_conditional_group(positive, u, r://e, [a]),
          any_of_group([a]), exactly_one_of_group([a]), at_most_one_of_group([a]),
          grouped_package_dependency(no, c, n, [package_dependency(run, no, c, n, none, version_none, [], [])]),
          grouped_package_dependency(no, c, n, []),
          package_dependency(run, no, c, n, none, version_none, [], []),
          r://e:run, r://e, [1, 2], comp(1, 2), atom_item
        ]), sampler:trace_simplify(TItem, _)),
        sampler:timeout_trace_hook(qtest://'scat/spkg-1.0':run?{[]}, t, t, t),
        sampler:diagnose_timeout_counts([qtest://'scat/spkg-1.0':run?{[]}], 0.05, _, _),
        % Callsite tracking
        sampler:enable_callsite_stats,
        sampler:enable_callsite_stats,
        sampler:reset_callsites,
        sampler:set_callsite_rate(1),
        sampler:maybe_record_callsite([name(spkg), atom], qtest://'scat/spkg-1.0'),
        sampler:maybe_record_callsite(select(slot, _VarOp, v), other_entry),
        sampler:maybe_record_callsite(select(slot, equal, v), qtest://'scat/spkg-1.0'),
        sampler:maybe_record_callsite(select(slot, constraint([], _), v), qtest://'scat/spkg-1.0'),
        sampler:maybe_record_callsite(select(slot, constraint([a], _), v), qtest://'scat/spkg-1.0'),
        sampler:maybe_record_callsite(select(slot, constraint(_VarC, _), v), qtest://'scat/spkg-1.0'),
        sampler:maybe_record_callsite(select(slot, constraint(other, _), v), qtest://'scat/spkg-1.0'),
        sampler:maybe_record_callsite(select(slot, other_comp(1), v), qtest://'scat/spkg-1.0'),
        sampler:maybe_record_callsite(name(spkg), qtest://'scat/spkg-1.0'),
        sampler:maybe_record_callsite(atom_q, other_entry),
        sampler:report_callsites(5),
        sampler:report_callsites_sig(5),
        sampler:print_callsite_sig_rows([], 1, 1),
        sampler:print_callsite_sig_rows([1-f-1-p-s], 1, 2),
        sampler:frame_predicate_indicator(0, unknown/0),
        forall(sampler:skip_frame_pi(_), true),
        sampler:disable_callsite_stats,
        sampler:reset_callsites
      )),
    retractall(cache:ordered_entry(qtest, 'scat/spkg-1.0', _, _, _))).

test(system_writer_config_and_loader_full_coverage, [nondet]) :-
  tmp_file(sys_cov, TmpDir),
  make_directory_path(TmpDir),
  os:compose_path(TmpDir, 'bin', BinDir),
  make_directory_path(BinDir),
  % Fake dns-sd, ldd, otool, emerge-vp, pmerge in BinDir
  os:compose_path(BinDir, 'dns-sd', FakeDnsSd),
  setup_call_cleanup(
    open(FakeDnsSd, write, SDNS),
    format(SDNS, '#!/bin/sh~nfor a in "$@"; do case "$a" in _empty._tcp.) exit 0;; -B) echo "12:00:00.000  Add        2   4 local.               _portage._tcp.       mac-pro"; exit 0;; -L) echo "mac-pro._portage._tcp.local. can be reached at mac-pro.local.:4000 (interface 4)"; exit 0;; -R) sleep 5; exit 0;; esac; done~n', []),
    close(SDNS)),
  filesex:chmod(FakeDnsSd, 0o755),
  os:compose_path(BinDir, 'ldd', FakeLdd),
  setup_call_cleanup(
    open(FakeLdd, write, SLDD),
    format(SLDD, '#!/bin/sh~necho "\tlibmissing.so.1 => not found"~n', []),
    close(SLDD)),
  filesex:chmod(FakeLdd, 0o755),
  os:compose_path(BinDir, 'otool', FakeOtool),
  setup_call_cleanup(
    open(FakeOtool, write, SOTO),
    format(SOTO, '#!/bin/sh~necho "/opt/nonexistent/libmissing.dylib (compatibility version 1.0.0)"~n', []),
    close(SOTO)),
  filesex:chmod(FakeOtool, 0o755),
  os:compose_path(BinDir, 'fake-emerge-vp', FakeEmergeVp),
  setup_call_cleanup(
    open(FakeEmergeVp, write, SEVP),
    format(SEVP, '#!/bin/sh~necho "[ebuild  N     ] wcat/wpkg-1.0"~n', []),
    close(SEVP)),
  filesex:chmod(FakeEmergeVp, 0o755),
  os:compose_path(TmpDir, 'libtest.so', FakeSo),
  setup_call_cleanup(open(FakeSo, write, SSO), write(SSO, 'elf'), close(SSO)),
  os:compose_path([TmpDir, 'vdb', 'wcat', 'wpkg-1.0'], VdbEntryDir),
  make_directory_path(VdbEntryDir),
  os:compose_path(VdbEntryDir, 'CONTENTS', ContentsFile),
  setup_call_cleanup(
    open(ContentsFile, write, SC),
    format(SC, 'obj ~w 00000000000000000000000000000000 12345~n', [FakeSo]),
    close(SC)),
  os:compose_path([TmpDir, 'wcat', 'wpkg'], EbuildDir),
  make_directory_path(EbuildDir),
  os:compose_path(EbuildDir, 'wpkg-1.0.ebuild', EbuildFile),
  setup_call_cleanup(open(EbuildFile, write, SEB), writeln(SEB, '# ebuild'), close(SEB)),
  os:compose_path(TmpDir, 'graph/wcat', GraphCatDir),
  make_directory_path(GraphCatDir),
  os:compose_path(TmpDir, 'graph', GraphDir),
  V1 = version([1,0], '', 4, 0, [], 0, '1.0'),
  getenv('PATH', OldPath),
  atomic_list_concat([BinDir, ':', OldPath], NewPath),
  os:compose_path(TmpDir, 'vdb', VdbDir),
  setup_call_cleanup(
    ( setenv('PATH', NewPath),
      unittest:accept_stable_amd64,
      ( catch(kb:declared(type(instance(knowledgebase))), _, fail) -> true ; kb:newinstance(knowledgebase) ),
      ( catch(wtest_repo:declared(type(instance(repository))), _, fail) -> true ; wtest_repo:newinstance(repository) ),
      wtest_repo:init(TmpDir, TmpDir, 'https://ex.org', git, eapi),
      wrap_predicate(interface:get_port(GPort), test_cov, _, GPort = 4000),
      asserta(config:pkg_directory(VdbDir)),
      asserta(config:emerge_vp_path(FakeEmergeVp)),
      asserta(config:pmerge_path(FakeEmergeVp)),
      assertz(cache:category(wtest_repo, wcat)),
      assertz(cache:package(wtest_repo, wcat, wpkg)),
      assertz(cache:ordered_entry(wtest_repo, 'wcat/wpkg-1.0', wcat, wpkg, V1)),
      assertz(cache:entry_metadata(wtest_repo, 'wcat/wpkg-1.0', timestamp, 0)),
      assertz(cache:entry_metadata(wtest_repo, 'wcat/wpkg-1.0', keywords, stable(amd64))),
      assertz(cache:ordered_entry(pkg, 'wcat/wpkg-1.0', wcat, wpkg, V1))
    ),
    with_output_to(string(_),
      ( % 1. bonjour.pl & subprocess.pl
        bonjour:advertise,
        bonjour:advertise('test-host', 4000),
        bonjour:discover(_),
        bonjour:discover('_empty._tcp.', []),
        subprocess:stop_advertised,
        \+ subprocess:spawn(false, [], _),
        subprocess:spawn_failure_reason(error(timeout_error(read, s), _), exit(1), 5, _),
        subprocess:status_exit_code(exit(0), 0),
        subprocess:status_exit_code(killed(9), 137),
        subprocess:noninteractive_git_env(_),
        subprocess:spawn_background(sleep, ['5'], BgPid),
        subprocess:wait_with_timeout(BgPid, _, [timeout(0.05), grace(0.05)]),
        subprocess:spawn_background(true, [], BgPid2),
        sleep(0.05),
        ignore(subprocess:poll_exit(BgPid2, _)),
        subprocess:spawn_background(true, [], BgPid3),
        ignore(subprocess:wait_with_timeout(BgPid3, _)),
        % 2. linkage.pl
        linkage:broken_libs('/no/such/file.so', []),
        linkage:broken_libs_linux(FakeSo, [_]),
        linkage:broken_libs_macos(FakeSo, [_]),
        % linkage:check/1 looks at every installed package. With the
        % VDB of this machine loaded that is a few thousand packages,
        % so the check is held to the package of this test.
        wrap_predicate(vdb:installed_entry(Installed), test_cov, InstalledEntry,
                       ( InstalledEntry, Installed == 'wcat/wpkg-1.0' )),
        call_cleanup(linkage:check([_]),
                     unwrap_predicate(vdb:installed_entry/1, test_cov)),
        % 3. lock.pl
        lock:with_system_lock('test/lock:0', true),
        lock:with_system_lock('test/lock:1', true, [timeout(1), stale(1)]),
        lock:lock_dir('test/stale:lock', StaleLockDir),
        make_directory_path(StaleLockDir),
        lock:lock_meta_path(StaleLockDir, StaleMeta),
        setup_call_cleanup(
          open(StaleMeta, write, SM),
          format(SM, 'pid=999999~ncreated_at=1~n', []),
          close(SM)),
        lock:with_system_lock('test/stale:lock', true, [timeout(1), stale(1)]),
        % Timeout when lock is held by current live PID and not stale
        lock:lock_dir('test/held:lock', HeldLockDir),
        make_directory_path(HeldLockDir),
        lock:lock_meta_path(HeldLockDir, HeldMeta),
        lock:lock_write_meta(HeldMeta, 'test/held:lock'),
        catch(lock:with_system_lock('test/held:lock', true, [timeout(0), stale(9999)]), _, true),
        lock:lock_release(HeldLockDir),
        % 4. os.pl, runtimepath.pl, script.pl
        EnsureDir =.. [ensure_directory_path, TmpDir],
        os:EnsureDir,
        os:contains('wpkg-1.0.ebuild', EbuildDir),
        os:directory_content(TmpDir, _),
        os:compose_path(TmpDir, 'rm_sub', RmSub),
        os:make_directory(RmSub),
        os:find_files(TmpDir, '*.ebuild', _),
        os:current_load_average(_),
        runtimepath:daemon_runtime_dir(_),
        runtimepath:daemon_runtime_dir_for(0, '/tmp', '/var/run/portage-ng'),
        runtimepath:daemon_runtime_dir_for(501, '/run/user/501', '/run/user/501/portage-ng'),
        runtimepath:daemon_runtime_dir_for(501, '', '/tmp/portage-ng-501'),
        % script.pl
        setup_call_cleanup(
          open_string("line1\nline2\rtrailing", SStream),
          script:stream_prefix_chars(SStream, true),
          close(SStream)),
        script:exec(version, _VerStr),
        script:exec(version, [], [], OutS),
        read_string(OutS, _, _),
        close(OutS),
        script:exec_streaming(version, [], []),
        ignore(catch(script:exec(nonexistent_script, [a]), _, true)),
        % 5. writer.pl
        writer:write_merge_file(GraphDir, wtest_repo://'wcat/wpkg-1.0'),
        writer:write_fetchonly_file(GraphDir, wtest_repo://'wcat/wpkg-1.0'),
        writer:write_info_file(GraphDir, wtest_repo://'wcat/wpkg-1.0'),
        writer:write_plan_failure(GraphDir, 'wcat/wpkg-1.0', merge),
        writer:write_plan_failure(GraphDir, 'wcat/wpkg-1.0', fetchonly),
        writer:write_emerge_file(GraphDir, wtest_repo://'wcat/wpkg-1.0'),
        writer:write_emerge_file(GraphDir, wtest_repo://'wcat/wpkg-1.0'),
        writer:write_pmerge_file(GraphDir, wtest_repo://'wcat/wpkg-1.0'),
        writer:write_pmerge_file(GraphDir, wtest_repo://'wcat/wpkg-1.0'),
        writer:write_emerge_files(GraphDir, wtest_repo),
        writer:write_pmerge_files(GraphDir, wtest_repo),
        writer:write_index_files(GraphDir, wtest_repo),
        writer:write_proof_files(GraphDir, wtest_repo),
        writer:write_repository(GraphDir, wtest_repo),
        writer:write_graph_files(GraphDir, wtest_repo),
        ignore(catch(writer:produce_html(GraphDir), _, true)),
        % 6. config.pl & loader.pl
        forall(( current_predicate(config:F/A),
                 \+ memberchk(F/A, [initialize_cacert/0, systemconfig/1]) ),
               ( functor(CHead, F, A),
                 ignore(catch(forall(config:CHead, true), _, true)) )),
        ignore(catch(config:initialize_cacert, _, true)),
        ignore(catch(config:systemconfig(_), _, true)),
        setup_call_cleanup(
          ( setenv('PORTAGE_NG_HOME', TmpDir),
            unsetenv('PORTAGE_NG_STATE') ),
          config:state_dir('/var/lib/portage-ng'),
          unsetenv('PORTAGE_NG_HOME')),
        findall(P, retract(user:file_search_path(portage, P)), SavedPaths),
        call_cleanup(
          config:installation_dir('/usr/local/share/portage-ng'),
          forall(member(P, SavedPaths), assertz(user:file_search_path(portage, P)))),
        forall(loader:group(_, _), true),
        forall(loader:mode(_, _), true),
        forall(loader:capability(_, _), true),
        setup_call_cleanup(
          ( retractall(config:load_llm_modules(_)),
            asserta(config:load_llm_modules(false)) ),
          loader:ensure(llm),
          ( retractall(config:load_llm_modules(_)),
            assertz(config:load_llm_modules(true)) )),
        retractall(loader:capability_loaded(bulk)),
        loader:ensure(bulk),
        loader:ensure(build),
        loader:load_test_modules,
        load_modules(common)
      )),
    ( setenv('PATH', OldPath),
      subprocess:stop_advertised,
      unwrap_predicate(interface:get_port/1, test_cov),
      retractall(config:pkg_directory(VdbDir)),
      retractall(config:emerge_vp_path(FakeEmergeVp)),
      retractall(config:pmerge_path(FakeEmergeVp)),
      retractall(cache:category(wtest_repo, _)),
      retractall(cache:package(wtest_repo, _, _)),
      retractall(cache:ordered_entry(wtest_repo, _, _, _, _)),
      retractall(cache:entry_metadata(wtest_repo, _, _, _)),
      retractall(cache:ordered_entry(pkg, 'wcat/wpkg-1.0', _, _, _)),
      catch(delete_directory_and_contents(TmpDir), _, true)
    )).

:- end_tests(application_sys_perf_output_cfg_coverage).

