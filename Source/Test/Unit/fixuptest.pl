/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> FIXUPTEST
Unit tests for the build-time exception fixups (Source/Domain/Gentoo/Exceptions/).

Missing-provider detectors and curated seeds (portage-ng#102), USE
enable detectors, GHC boot-library dependencies and the
CABAL_CORE_LIB_GHC_PV filter (portage-ng#108, #112).
*/

:- module(fixuptest, []).

:- use_module(library(plunit)).
:- use_module(library(lists)).
:- use_module(library(assoc)).

% =============================================================================
%  FIXUPTEST declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Missing-provider detector corpus (portage-ng#102): each signature variant
%  normalizes to symbol(Kind, Name)
% -----------------------------------------------------------------------------

:- begin_tests(missing_provider_detectors).

test(cmd_not_found_bash, [true(Sym == symbol(command, semodule_package)), nondet]) :-
  missing_provider:detector(["/bin/sh: line 1: semodule_package: command not found"], Sym, _).

test(cmd_not_found_prefix, [true(Sym == symbol(command, semodule_package)), nondet]) :-
  missing_provider:detector(["make[1]: semodule_package: command not found"], Sym, _).

test(cmd_not_found_dash, [true(Sym == symbol(command, checkmodule)), nondet]) :-
  missing_provider:detector(["sh: 1: checkmodule: not found"], Sym, _).

test(cmd_not_found_env, [true(Sym == symbol(command, gperf)), nondet]) :-
  missing_provider:detector(["env: 'gperf': No such file or directory"], Sym, _).

test(missing_header, [true(Sym == symbol(header, 'foo/bar.h')), nondet]) :-
  missing_provider:detector(["main.c:3:10: fatal error: foo/bar.h: No such file or directory"], Sym, _).

test(missing_lib, [true(Sym == symbol(lib, crypto)), nondet]) :-
  missing_provider:detector(["/usr/bin/ld: cannot find -lcrypto"], Sym, _).

test(missing_soname, [true(Sym == symbol(soname, 'libfoo.so.1')), nondet]) :-
  missing_provider:detector(["prog: error while loading shared libraries: libfoo.so.1: cannot open shared object file: No such file"], Sym, _).

test(pkgconfig_notfound, [true(Sym == symbol(pkgconfig, glib_2_0)), nondet]) :-
  missing_provider:detector(["No package 'glib_2_0' found"], Sym, _).

test(pkgconfig_searchpath, [true(Sym == symbol(pkgconfig, 'libssl')), nondet]) :-
  missing_provider:detector(["Package libssl was not found in the pkg-config search path"], Sym, _).

test(python_module, [true(Sym == symbol(python_module, setuptools)), nondet]) :-
  missing_provider:detector(["ModuleNotFoundError: No module named 'setuptools'"], Sym, _).

test(perl_module, [true(Sym == symbol(perl_module, 'Foo/Bar.pm')), nondet]) :-
  missing_provider:detector(["Can't locate Foo/Bar.pm in @INC (you may need to install the Foo::Bar module)"], Sym, _).

test(no_false_positive_on_prose, [fail]) :-
  missing_provider:detector(["checking for a working compiler... yes", "configure: creating ./config.status"], symbol(command, _), _).

:- end_tests(missing_provider_detectors).


% -----------------------------------------------------------------------------
%  Provider dependency term shape (unioned into BDEPEND)
% -----------------------------------------------------------------------------

:- begin_tests(missing_provider_provider_dep).

test(unversioned_shape,
     [true(Dep == package_dependency(install, no, 'sys-apps', 'semodule-utils', none, version_none, [], []))]) :-
  feedback:provider_dep('sys-apps/semodule-utils', Dep).

test(rejects_non_cn, [fail]) :-
  feedback:provider_dep('semodule-utils', _).

test(usedep_shape,
     [true(Dep == package_dependency(install, no, 'kde-frameworks', kwindowsystem, none, version_none, [],
                                     [use(enable('X'), none)]))]) :-
  feedback:provider_dep('kde-frameworks/kwindowsystem',
                        [use(enable('X'), none)], Dep).

:- end_tests(missing_provider_provider_dep).


% USE-enable learning from build failures (portage-ng#110).
:- begin_tests(useenable_detectors).

test(kx11extras_header, [nondet]) :-
  useenable:detector(
    ["fatal error: KX11Extras: No such file or directory"],
    symbol(kf_header, 'KX11Extras'), _).

test(kstartupinfo_header, [nondet]) :-
  useenable:detector(
    ["error: KStartupInfo: No such file or directory"],
    symbol(kf_header, 'KStartupInfo'), _).

test(pimcommon_activities_header, [nondet]) :-
  useenable:detector(
    ["fatal error: KPim6PimCommonActivities: No such file or directory"],
    symbol(kf_header, 'KPim6PimCommonActivities'), _).

% Real kaddressbook configure log: CMake find_package, not a fatal #include.
test(pimcommon_activities_could_not_find, [nondet]) :-
  useenable:detector(
    ["-- Could NOT find KPim6PimCommonActivities (missing: KPim6PimCommonActivities_DIR)"],
    symbol(kf_header, 'KPim6PimCommonActivities'), _).

% Real kget compile log: GCC colors wrap the header token in CSI sequences.
test(kx11extras_ansi_colored, [nondet]) :-
  useenable:detector(
    ["\u001b[01m\u001b[K/tmp/droptarget.cpp:37:10:\u001b[m\u001b[K \u001b[01;31m\u001b[Kfatal error: \u001b[m\u001b[KKX11Extras: No such file or directory"],
    symbol(kf_header, 'KX11Extras'), _).

test(strip_ansi_removes_embedded_csi) :-
  useenable:strip_ansi(
    "fatal error: \u001b[m\u001b[KKX11Extras: No such file",
    Clean),
  Clean == "fatal error: KX11Extras: No such file".

test(cmake_xdamage, [nondet]) :-
  useenable:detector(
    ["-- Looking for X11_Xdamage_LIB - NOTFOUND"],
    symbol(cmake_lib, 'X11_Xdamage'), _).

test(ignores_regular_header, [fail]) :-
  useenable:detector(
    ["fatal error: foo/bar.h: No such file or directory"],
    symbol(kf_header, _), _).

test(ignores_unrelated_could_not_find, [fail]) :-
  useenable:detector(
    ["-- Could NOT find ReuseTool (missing: REUSETOOL_EXECUTABLE)"],
    symbol(kf_header, _), _).

:- end_tests(useenable_detectors).


:- begin_tests(useenable_seed).

test(kx11extras_maps_to_kwindowsystem_x) :-
  useenable:provides_usedep(kf_header, 'KX11Extras',
                            'kde-frameworks/kwindowsystem',
                            [use(enable('X'), none)]).

test(activities_maps_to_pimcommon) :-
  useenable:provides_usedep(kf_header, 'KPim6PimCommonActivities',
                            'kde-apps/pimcommon',
                            [use(enable(activities), none)]).

test(xdamage_bare_cn) :-
  useenable:provides_usedep(cmake_lib, 'X11_Xdamage',
                            'x11-libs/libXdamage', []).

:- end_tests(useenable_seed).


% GHC boot-lib / ghc-pkg readiness (portage-ng#108).
:- begin_tests(ghcabi_boot_dep).

test(boot_dep_detects_cabal_missing,
     [true(Libs == [bytestring, deepseq, 'ghc-prim', 'template-haskell'])]) :-
  tmp_file(ghcboot, Path),
  setup_call_cleanup(
    ( open(Path, write, S),
      format(S,
"Error: setup: Encountered missing or private dependencies:~n\
bytestring >=0.10.4 && <0.12,~n\
deepseq >=1.1 && <1.5,~n\
ghc-prim >=0.2 && <0.9,~n\
template-haskell >=2.5 && <2.19~n", []),
      close(S) ),
    ghcabi:boot_dep_error(Path, 0, Libs),
    catch(delete_file(Path), _, true)).

test(boot_dep_ignores_unrelated_log, [fail]) :-
  tmp_file(ghcboot2, Path),
  setup_call_cleanup(
    ( open(Path, write, S),
      format(S, "configure: error: something else~n", []),
      close(S) ),
    ghcabi:boot_dep_error(Path, 0, _),
    catch(delete_file(Path), _, true)).

test(excluded_version_roundtrip,
     [setup(( feedback:record_excluded_version('dev-haskell', text,
                 version([1,2,5], '', 4, 0, [], 1, '1.2.5.0-r1'),
                 evidence(test)) )),
      cleanup(retractall(feedback:excluded_version('dev-haskell', text, _, _))),
      nondet]) :-
  feedback:excluded_version('dev-haskell', text, _, evidence(test)),
  feedback:excluded_version_count(N),
  N >= 1.

:- end_tests(ghcabi_boot_dep).


% -----------------------------------------------------------------------------
%  Curated seed resolver
% -----------------------------------------------------------------------------

:- begin_tests(missing_provider_resolver).

test(seed_semodule, [true(P-C == 'sys-apps/semodule-utils'-curated_seed), nondet]) :-
  missing_provider:provider_of(command, semodule_package, P, C).

test(seed_unknown_fails, [fail]) :-
  missing_provider:provider_of(command, this_command_has_no_provider_xyz, _, curated_seed).

:- end_tests(missing_provider_resolver).


% CABAL_CORE_LIB_GHC_PV parse + match (portage-ng#112).
:- begin_tests(ghcabi_cabal_core).

test(parse_quoted_list,
     [true(PVs == ['9.0.2','9.2.8'])]) :-
  ghcabi:parse_cabal_core_line('CABAL_CORE_LIB_GHC_PV="9.0.2 9.2.8"', PVs), !.

test(match_exact) :-
  ghcabi:cabal_core_matches(['9.8.2','9.8.4'], '9.8.4').

test(match_glob) :-
  ghcabi:cabal_core_matches(['9.8.*'], '9.8.4').

test(nomatch_other_series, [fail]) :-
  ghcabi:cabal_core_matches(['9.0.2','9.2.8'], '9.8.4').

:- end_tests(ghcabi_cabal_core).


% The cabal-core filter must not discard the only core-lib version a
% dependency admits just because a newer sibling matches the selected
% GHC (portage-ng#123). That sibling is not an alternative when it sits
% outside the dep's version domain; rejecting the in-domain lib is what
% pinned =adjunctions-4.4 to ghc-9.8.
:- dynamic cc_saved_snap/1.

:- begin_tests(ghcabi_core_lib_domain).

cc_old(qtest://'dev-haskell/mtl-1.0').
cc_new(qtest://'dev-haskell/mtl-2.0').
cc_ghc(qtest://'dev-lang/ghc-9.8.4').
cc_ver(1, version([1],'',4,0,[],0,'1')).
cc_ver(2, version([2],'',4,0,[],0,'2')).
cc_ver(ghc, version([9,8,4],'',4,0,[],0,'9.8.4')).

cc_setup :-
  cc_cleanup,
  cc_old(ORepo://OId), cc_ver(1, OV),
  assertz(cache:ordered_entry(ORepo, OId, 'dev-haskell', mtl, OV)),
  cc_new(NRepo://NId), cc_ver(2, NV),
  assertz(cache:ordered_entry(NRepo, NId, 'dev-haskell', mtl, NV)),
  cc_ghc(GRepo://GId), cc_ver(ghc, GV),
  assertz(cache:ordered_entry(GRepo, GId, 'dev-lang', ghc, GV)),
  assertz(ghcabi:cabal_core_cache_(ORepo://OId, ['9.2.8'])),
  assertz(ghcabi:cabal_core_cache_(NRepo://NId, ['9.8.4'])),
  ( nb_current(memo_selected_cn_snap, Old) -> assertz(cc_saved_snap(Old)) ; true ),
  cnselect:record_selected_cn_snapshot('dev-lang', ghc,
    [selected(GRepo, GId, install, GV, slot(0))]).

cc_cleanup :-
  cc_old(ORepo://OId),
  retractall(cache:ordered_entry(ORepo, OId, _, _, _)),
  retractall(ghcabi:cabal_core_cache_(ORepo://OId, _)),
  cc_new(NRepo://NId),
  retractall(cache:ordered_entry(NRepo, NId, _, _, _)),
  retractall(ghcabi:cabal_core_cache_(NRepo://NId, _)),
  cc_ghc(GRepo://GId),
  retractall(cache:ordered_entry(GRepo, GId, _, _, _)),
  ( retract(cc_saved_snap(Saved)) ->
      nb_setval(memo_selected_cn_snap, Saved)
  ; empty_assoc(Empty),
    nb_setval(memo_selected_cn_snap, Empty)
  ).

% Unconstrained domain: the GHC-9.8 sibling is a real alternative, so the
% old core lib is incompatible (#112).
test(rejects_when_matching_sibling_is_in_domain,
     [setup(cc_setup), cleanup(cc_cleanup)]) :-
  cc_old(Old),
  ghcabi:version_incompatible_with_selected_ghc('dev-haskell', mtl,
    version_domain(any, []), Old).

% `mtl < 2` admits only the old core lib. The GHC-9.8 sibling is outside
% that bound, so the old lib must stay eligible (#123).
test(keeps_in_domain_core_lib_when_sibling_is_outside,
     [setup(cc_setup), cleanup(cc_cleanup), fail]) :-
  cc_old(Old), cc_ver(2, NV),
  ghcabi:version_incompatible_with_selected_ghc('dev-haskell', mtl,
    version_domain(any, [bound(smaller, NV)]), Old).

:- end_tests(ghcabi_core_lib_domain).


% -----------------------------------------------------------------------------
%  Metacircular draft_fixup filename guard
% -----------------------------------------------------------------------------
%
% The mechanism name of an LLM-proposed draft_fixup becomes a filename
% under Knowledge/drafts/; traversal shapes must be rejected at
% validation time (and again at write time).

:- begin_tests(metacircular_draft_guard).

test(valid_draft_mechanism) :-
  metacircular:valid_action(action(draft_fixup, collision, 'synopsis', 'body')).

test(reject_draft_traversal, [fail]) :-
  metacircular:valid_action(action(draft_fixup, '../../tmp/evil', 's', 'b')).

test(reject_draft_subdirectory, [fail]) :-
  metacircular:valid_action(action(draft_fixup, 'a/b', 's', 'b')).

test(write_draft_refuses_traversal, [fail]) :-
  metacircular:write_draft_fixup('../../tmp/evil', 's', 'b').

:- end_tests(metacircular_draft_guard).


% -----------------------------------------------------------------------------
%  Kernel CONFIG_CHECK detector and cascade recording (portage-ng#105/#127)
% -----------------------------------------------------------------------------

:- begin_tests(kernelconfig_detectors).

test(stock_is_not_set_and_is_required_for,
     [true(Opts == [config('CONFIG_IIO', y),
                    config('CONFIG_LEDS_CLASS_MULTICOLOR', y)])]) :-
  Lines = [
    " *   CONFIG_IIO:\t is not set when it should be.",
    " *   CONFIG_LEDS_CLASS_MULTICOLOR: is required for keyboard backlight"
  ],
  kernelconfig:detect_options(Lines, Opts, _).

test(nvidia_drm_ttm_helper_maps_to_drm_qxl_and_ignores_prose,
     [true(Opts == [config('CONFIG_DRM_QXL', m)])]) :-
  Lines = [
    " *   CONFIG_DRM_TTM_HELPER: is not set but is needed to compile when using",
    " * \tkernel version 6.11.x or newer while DRM_FBDEV_EMULATION is set.",
    " * \tCannot be directly selected in the kernel's config menus, and may need",
    " * \tselection of a DRM device even if unused, e.g. CONFIG_DRM_QXL=m or",
    " * \tDRM_AMDGPU=m (among others, consult the kernel config's help), can",
    " * \talso use DRM_NOUVEAU=m as long as built as module *not* built-in."
  ],
  kernelconfig:detect_options(Lines, Opts, _).

test(cascade_records_second_option_for_same_target) :-
  T = qtest://'x11-drivers/nvidia-drivers-615.78.08',
  tmp_file(kcstate, TmpDir),
  ( getenv('PORTAGE_NG_STATE', OldEnv) -> HadEnv = true ; HadEnv = false ),
  setup_call_cleanup(
    ( make_directory(TmpDir),
      atom_concat(TmpDir, '/Knowledge', KDir),
      make_directory(KDir),
      setenv('PORTAGE_NG_STATE', TmpDir),
      retractall(feedback:required_kernel_config(T, _, _)),
      retractall(feedback:session_kernel_config(T, _, _))
    ),
    ( feedback:kernel_config_count(C0),
      feedback:record_kernel_config(T, [config('CONFIG_DRM_FBDEV_EMULATION', y)], ev1),
      feedback:kernel_config_count(C1),
      C1 =:= C0 + 1,
      feedback:record_kernel_config(T, [config('CONFIG_DRM_QXL', m)], ev2),
      feedback:kernel_config_count(C2),
      C2 =:= C1 + 1,
      feedback:record_kernel_config(T, [config('CONFIG_DRM_QXL', m)], ev3),
      feedback:kernel_config_count(C3),
      C3 =:= C2
    ),
    ( retractall(feedback:required_kernel_config(T, _, _)),
      retractall(feedback:session_kernel_config(T, _, _)),
      ( HadEnv == true -> setenv('PORTAGE_NG_STATE', OldEnv) ; unsetenv('PORTAGE_NG_STATE') ),
      catch(process_create(path(rm), ['-rf', TmpDir], [process(Pid)]), _, true),
      ( var(Pid) -> true ; process_wait(Pid, _) )
    )).

:- end_tests(kernelconfig_detectors).


% -----------------------------------------------------------------------------
%  Comprehensive exception fixup mechanisms coverage
% -----------------------------------------------------------------------------

fixup_noop_cb(_Phase, _Event).

fixup_mktemp_dir(Prefix, Dir) :-
  tmp_file(Prefix, Tmp),
  ( exists_file(Tmp) -> delete_file(Tmp) ; true ),
  make_directory(Tmp),
  Dir = Tmp.

fixup_rm_rf(Dir) :-
  ( exists_directory(Dir)
  -> catch(process_create(path(rm), ['-rf', Dir], [process(Pid)]), _, true),
     ( var(Pid) -> true ; process_wait(Pid, _) )
  ;  true
  ).

:- begin_tests(exceptions_full_coverage).

test(fixup_registry_and_helpers, [nondet]) :-
  fixup_mktemp_dir(fixup_reg, TmpDir),
  ( getenv('PORTAGE_NG_STATE', OldEnv) -> HadEnv = true ; HadEnv = false ),
  V1 = version([1,0], '', 4, 0, [], 0, '1.0'),
  setup_call_cleanup(
    ( setenv('PORTAGE_NG_STATE', TmpDir),
      os:compose_path(TmpDir, 'Knowledge', KDir),
      make_directory(KDir),
      os:compose_path(TmpDir, 'pkg', PkgDir),
      make_directory_path(PkgDir),
      asserta(config:pkg_directory(PkgDir)),
      asserta(config:ebuild_command('/usr/bin/true')),
      os:compose_path(TmpDir, 'fake.ebuild', FakeEbuild),
      setup_call_cleanup(open(FakeEbuild, write, S0),
        writeln(S0, 'CABAL_CORE_LIB_GHC_PV="9.0.2  9.2.8"'),
        close(S0)),
      assertz(qtest:get_ebuild_file('fcat/fpkg-1.0', FakeEbuild)),
      assertz(qtest:get_ebuild_file('fcat/missing_eb-1.0', '/tmp/no-such-portage-ng.ebuild')),
      assertz(cache:ordered_entry(pkg, 'fcat/fpkg-1.0', fcat, fpkg, V1)),
      assertz(cache:ordered_entry(qtest, 'fcat/fpkg-1.0', fcat, fpkg, V1)),
      assertz(cache:entry_metadata(qtest, 'fcat/fpkg-1.0', iuse, fa)),
      assertz(cache:entry_metadata(qtest, 'fcat/fpkg-1.0', iuse, fb)),
      os:compose_path([PkgDir, 'fcat/fpkg-1.0'], VdbEntryDir),
      make_directory_path(VdbEntryDir),
      os:compose_path(VdbEntryDir, 'USE', UseFile),
      setup_call_cleanup(open(UseFile, write, SU), writeln(SU, 'fa'), close(SU)),
      os:compose_path(VdbEntryDir, 'CONTENTS', ContentsFile),
      setup_call_cleanup(open(ContentsFile, write, SC),
        ( writeln(SC, 'obj /usr/lib64/ocaml/site-lib/res/res.cmi abc 123'),
          writeln(SC, 'dir /usr/lib64/ocaml/site-lib/camlp5'),
          writeln(SC, 'obj /usr/include/myhdr.h abc 123'),
          writeln(SC, 'obj /usr/lib64/pkgconfig/mypkg.pc abc 123'),
          writeln(SC, 'obj /usr/lib64/libmylib.so abc 123')
        ),
        close(SC)),
      assertz(cache:ordered_entry(pkg, 'dev-lang/ocaml-5.0', 'dev-lang', ocaml, V1)),
      fixup:clear
    ),
    ( % 1. fixup.pl core helpers & repair_rebuild
      fixup:record(collision, 'fcat/fpkg-1.0', d1),
      fixup:record(collision, 'fcat/fpkg-1.0', d2),
      fixup:applied(collision, 'fcat/fpkg-1.0', d1),
      fixup:clear,
      \+ fixup:applied(_, _, _),
      fixup:tree_entry('fcat/fpkg-1.0', qtest, fcat, fpkg),
      fixup:installed_tree_entry('fcat/fpkg-1.0', qtest),
      os:compose_path(TmpDir, 'test.log', LogFile),
      fixup:scan_log('/tmp/nonexistent-portage-ng-log-xyz', 0, []),
      fixup:log_marker(LogFile, 'marker ~w', [1]),
      fixup:scan_log(LogFile, 0, ScanLines),
      ScanLines \== [],
      fixup:packages_word(1, package),
      fixup:packages_word(2, packages),
      forall(member(M, [collision, ghcabi, gitlock, kernelconfig, missing_provider, ocamlabi, useenable]),
             ( fixup:mechanism(M),
               fixup:mechanism_note(M, 1, _),
               fixup:mechanism_note(M, 2, _)
             )),
      fixup:repair_rebuild_use(qtest, 'fcat/fpkg-1.0', UseStr1),
      sub_atom(UseStr1, _, _, _, 'fa'),
      sub_atom(UseStr1, _, _, _, '-fb'),
      fixup:repair_rebuild_use(qtest, 'fcat/other-1.0', _UseStr2),
      fixup:repair_rebuild(qtest, 'fcat/fpkg-1.0', 'test repair', 0),
      fixup:repair_rebuild(qtest, 'fcat/no_ebuild_path-1.0', 'test repair', -1),
      fixup:maybe_phase_retry(FakeEbuild, 'fcat/fpkg-1.0', compile, LogFile, '', fixuptest:fixup_noop_cb, 0, 0, 0),
      fixup:fold_phase_retry([], FakeEbuild, 'fcat/fpkg-1.0', compile, LogFile, '', fixuptest:fixup_noop_cb, 0, 1, 1),
      fixup:fold_phase_retry([collision], FakeEbuild, 'fcat/fpkg-1.0', compile, LogFile, '', fixuptest:fixup_noop_cb, 0, 0, 0),

      % 2. collision.pl
      collision:deconflict_mode(override),
      setup_call_cleanup(open(LogFile, write, SCol),
        writeln(SCol, ' * Package NOT merged due to file collisions.'),
        close(SCol)),
      collision:phase_error(LogFile, 0),
      fixup:maybe_phase_retry(FakeEbuild, 'fcat/fpkg-1.0', merge, LogFile, '', fixuptest:fixup_noop_cb, 0, 1, 0),

      % 3. gitlock.pl
      gitlock:retry_phase(unpack),
      setup_call_cleanup(open(LogFile, write, SGit),
        writeln(SGit, 'error: Unable to update HEAD'),
        close(SGit)),
      gitlock:phase_error(LogFile, 0),
      gitlock:retry(FakeEbuild, 'fcat/fpkg-1.0', unpack, LogFile, '', fixuptest:fixup_noop_cb, 1, 6, 1),
      fixup:phase_retry_hook(gitlock, FakeEbuild, 'fcat/fpkg-1.0', compile, LogFile, '', fixuptest:fixup_noop_cb, 0, 1, 1),
      fixup:phase_retry_hook(gitlock, FakeEbuild, 'fcat/fpkg-1.0', unpack, LogFile, '', fixuptest:fixup_noop_cb, 0, 1, 0),

      % 4. ghcabi.pl
      ghcabi:repair_enabled,
      ghcabi:retry_phase(setup),
      ghcabi:retry_phase(configure),
      ghcabi:retry_phase(compile),
      ghcabi:strip_ansi("fpkg-1.0\u001b[0m", "fpkg-1.0"),
      ghcabi:pv_token('fpkg-1.0'),
      ghcabi:token_entry('fpkg-1.0', qtest, 'fcat/fpkg-1.0'),
      ghcabi:read_cabal_core_from_ebuild(qtest://'fcat/fpkg-1.0', ['9.0.2', '9.2.8']),
      ghcabi:read_cabal_core_from_ebuild(qtest://'fcat/missing_eb-1.0', []),
      open_string("# comment\n", SStream),
      setup_call_cleanup(true, ghcabi:scan_cabal_core_stream(SStream, []), close(SStream)),
      ghcabi:empty_string(""),
      retractall(ghcabi:repair_applied_(_, _)),
      setup_call_cleanup(open(LogFile, write, SGhc),
        ( writeln(SGhc, 'haskell-updater'),
          writeln(SGhc, 'Detected broken packages: fpkg-1.0\u001b[0m unmappable-2.0')
        ),
        close(SGhc)),
      ghcabi:phase_error(LogFile, 0, ['fpkg-1.0', 'unmappable-2.0']),
      fixup:phase_retry_hook(ghcabi, FakeEbuild, 'fcat/fpkg-1.0', compile, LogFile, '', fixuptest:fixup_noop_cb, 0, 1, 0),
      ghcabi:repair_tokens(['fpkg-1.0'], 1),
      ghcabi:retry_loop(0, FakeEbuild, 'fcat/fpkg-1.0', compile, LogFile, '', fixuptest:fixup_noop_cb, 0, 1, 1),
      fixup:phase_retry_hook(ghcabi, FakeEbuild, 'fcat/fpkg-1.0', unpack, LogFile, '', fixuptest:fixup_noop_cb, 0, 1, 1),
      % boot_dep_error -> recache on round 1, then exclude_failing_version on round 2
      retractall(ghcabi:repair_applied_(_, _)),
      setup_call_cleanup(open(LogFile, write, SBoot),
        writeln(SBoot, 'Encountered missing or private dependencies: bytestring >= 0.10'),
        close(SBoot)),
      fixup:phase_retry_hook(ghcabi, FakeEbuild, 'fcat/fpkg-1.0', configure, LogFile, '', fixuptest:fixup_noop_cb, 0, 1, 0),
      with_output_to(string(_),
        fixup:phase_retry_hook(ghcabi, FakeEbuild, 'fcat/fpkg-1.0', configure, LogFile, '', fixuptest:fixup_noop_cb, 0, 1, 1)),

      % 5. ocamlabi.pl
      ocamlabi:repair_enabled,
      ocamlabi:retry_phase(configure),
      ocamlabi:retry_phase(compile),
      forall(member(Ext, [".cmi", ".cmo", ".cma", ".cmx", ".cmxa", ".cmxs"]),
             ocamlabi:cm_extension(Ext)),
      retractall(ocamlabi:repair_applied_(_, _)),
      setup_call_cleanup(open(LogFile, write, SOcaml),
        ( writeln(SOcaml, 'Error: The files /usr/lib64/ocaml/site-lib/res/res.cmi'),
          writeln(SOcaml, '       and /usr/lib64/ocaml/stdlib.cmi'),
          writeln(SOcaml, '       make inconsistent assumptions over interface Stdlib'),
          writeln(SOcaml, 'ocamlfind: Package `camlp5'' not found'),
          writeln(SOcaml, 'Error: Unbound module Camlp5')
        ),
        close(SOcaml)),
      ocamlabi:phase_error(LogFile, 0, OTail),
      ocamlabi:stale_units(OTail, OPaths, ONames),
      OPaths \== [], ONames \== [],
      ocamlabi:compiler_entry('dev-lang/ocaml-5.0'),
      ocamlabi:stale_owners([], ONames, 'fcat/self-1.0', ['fcat/fpkg-1.0']),
      ocamlabi:stale_owners(OPaths, ONames, 'fcat/self-1.0', ['fcat/fpkg-1.0']),
      fixup:phase_retry_hook(ocamlabi, FakeEbuild, 'fcat/self-1.0', compile, LogFile, '', fixuptest:fixup_noop_cb, 0, 1, 0),
      ocamlabi:repair_owners(['fcat/fpkg-1.0', 'fcat/gone-1.0'], 1),
      ocamlabi:retry_loop(0, FakeEbuild, 'fcat/self-1.0', compile, LogFile, '', fixuptest:fixup_noop_cb, 0, 1, 1),
      fixup:phase_retry_hook(ocamlabi, FakeEbuild, 'fcat/self-1.0', unpack, LogFile, '', fixuptest:fixup_noop_cb, 0, 1, 1),

      % 6. kernelconfig.pl
      kernelconfig:enabled,
      os:compose_path(TmpDir, 'linux', KSrcDir),
      os:compose_path(KSrcDir, 'scripts', KScriptsDir),
      make_directory_path(KScriptsDir),
      os:compose_path(KSrcDir, '.config', KConfigFile),
      setup_call_cleanup(open(KConfigFile, write, SKC), writeln(SKC, '# config'), close(SKC)),
      os:compose_path(KScriptsDir, 'config', KScriptBin),
      setup_call_cleanup(open(KScriptBin, write, SKS),
        ( writeln(SKS, '#!/bin/sh'), writeln(SKS, 'exit 0') ),
        close(SKS)),
      process_create(path(chmod), ['+x', KScriptBin], [process(ChPid)]),
      process_wait(ChPid, _),
      asserta(config:kernel_source_dir(KSrcDir)),
      kernelconfig:kernel_source_dir(KSrcDir),
      kernelconfig:config_token("\e[31m * \tCONFIG_FOO: is not set", 'CONFIG_FOO'),
      kernelconfig:strip_prefix('FOO_NO_PREFIX', 'FOO_NO_PREFIX'),
      setup_call_cleanup(open(LogFile, write, SKLog),
        ( writeln(SKLog, "\e[01;31m * \tCONFIG_IIO: is not set when it should be."),
          writeln(SKLog, " * CONFIG_BAR: is set when it should not be."),
          writeln(SKLog, " * CONFIG_DRM_TTM_HELPER: is required")
        ),
        close(SKLog)),
      with_output_to(string(_),
        ( fixup:phase_retry_hook(kernelconfig, FakeEbuild, 'fcat/fpkg-1.0', setup, LogFile, '', fixuptest:fixup_noop_cb, 0, 1, 1),
          kernelconfig:apply_planned([kernel_config([config('CONFIG_IIO', y),
                                                     config('CONFIG_DRM_QXL', m),
                                                     config('CONFIG_BAR', n),
                                                     config('bad-token!', y)], ev)]),
          delete_file(KConfigFile),
          kernelconfig:apply_options([config('CONFIG_IIO', y)])
        )),

      % 7. missing_provider.pl
      missing_provider:enabled,
      forall(member(Ph, [prepare, configure, compile, install, test]),
             missing_provider:retry_phase(Ph)),
      forall(member(Ch, ['_', '-', '.', '+']),
             missing_provider:name_char(Ch)),
      forall(missing_provider:provides(Kind, SymName, Prov),
             once(missing_provider:provider_of(Kind, SymName, Prov, _))),
      once(missing_provider:provider_of(header, 'foo/myhdr.h', 'fcat/fpkg', vdb_index)),
      once(missing_provider:provider_of(pkgconfig, mypkg, 'fcat/fpkg', vdb_index)),
      once(missing_provider:provider_of(soname, 'libmylib.so', 'fcat/fpkg', vdb_index)),
      once(missing_provider:provider_of(lib, mylib, 'fcat/fpkg', vdb_index)),
      PDM = package_dependency(install, no, 'sys-apps', 'semodule-utils', none, version_none, [], []),
      once(missing_provider:dep_mentions(use_conditional_group(positive, fa, qtest://'fcat/fpkg-1.0', [PDM]), 'sys-apps', 'semodule-utils')),
      once(missing_provider:dep_mentions(any_of_group([PDM]), 'sys-apps', 'semodule-utils')),
      once(missing_provider:dep_mentions(all_of_group([PDM]), 'sys-apps', 'semodule-utils')),
      once(missing_provider:dep_mentions(exactly_one_of_group([PDM]), 'sys-apps', 'semodule-utils')),
      once(missing_provider:dep_mentions(at_most_one_of_group([PDM]), 'sys-apps', 'semodule-utils')),
      once(missing_provider:dep_mentions([PDM], 'sys-apps', 'semodule-utils')),
      assertz(cache:ordered_entry(qtest, 'sys-apps/semodule-utils-1.0', 'sys-apps', 'semodule-utils', V1)),
      setup_call_cleanup(open(LogFile, write, SMP),
        ( writeln(SMP, '/bin/sh: line 1: semodule_package: command not found'),
          writeln(SMP, '/bin/sh: line 2: unknown_cmd_xyz: command not found')
        ),
        close(SMP)),
      with_output_to(string(_),
        ( fixup:phase_retry_hook(missing_provider, FakeEbuild, 'fcat/fpkg-1.0', compile, LogFile, '', fixuptest:fixup_noop_cb, 0, 1, 1),
          assertz(cache:entry_metadata(qtest, 'fcat/fpkg-1.0', bdepend, PDM)),
          fixup:phase_retry_hook(missing_provider, FakeEbuild, 'fcat/fpkg-1.0', compile, LogFile, '', fixuptest:fixup_noop_cb, 0, 1, 1)
        )),

      % 8. useenable.pl
      useenable:enabled,
      forall(member(PhU, [configure, compile, prepare]),
             useenable:retry_phase(PhU)),
      useenable:provides_usedep(kf_header, 'KStartupInfo', 'kde-frameworks/kwindowsystem', _),
      useenable:strip_ansi(atom_input, "atom_input"),
      useenable:strip_ansi(123, "123"),
      useenable:strip_ansi("\u001b[", ""),
      useenable:strip_ansi("\u001b", ""),
      useenable:strip_ansi("\u001b(Bhello\u001bM", "hello"),
      UDep = [use(enable('X'), none)],
      PDU = package_dependency(install, no, 'kde-frameworks', kwindowsystem, none, version_none, [], UDep),
      once(useenable:dep_has_hard_usedeps(use_conditional_group(positive, fa, qtest://'fcat/fpkg-1.0', [PDU]), 'kde-frameworks', kwindowsystem, UDep)),
      once(useenable:dep_has_hard_usedeps(any_of_group([PDU]), 'kde-frameworks', kwindowsystem, UDep)),
      once(useenable:dep_has_hard_usedeps(all_of_group([PDU]), 'kde-frameworks', kwindowsystem, UDep)),
      once(useenable:dep_has_hard_usedeps(exactly_one_of_group([PDU]), 'kde-frameworks', kwindowsystem, UDep)),
      once(useenable:dep_has_hard_usedeps(at_most_one_of_group([PDU]), 'kde-frameworks', kwindowsystem, UDep)),
      once(useenable:dep_has_hard_usedeps([PDU], 'kde-frameworks', kwindowsystem, UDep)),
      assertz(cache:ordered_entry(qtest, 'kde-frameworks/kwindowsystem-1.0', 'kde-frameworks', kwindowsystem, V1)),
      assertz(cache:ordered_entry(qtest, 'x11-libs/libXdamage-1.0', 'x11-libs', 'libXdamage', V1)),
      setup_call_cleanup(open(LogFile, write, SUE),
        ( writeln(SUE, 'fatal error: KX11Extras: No such file or directory'),
          writeln(SUE, '-- Looking for X11_Xdamage_LIB - NOTFOUND')
        ),
        close(SUE)),
      with_output_to(string(_),
        ( fixup:phase_retry_hook(useenable, FakeEbuild, 'fcat/fpkg-1.0', compile, LogFile, '', fixuptest:fixup_noop_cb, 0, 1, 1),
          assertz(cache:entry_metadata(qtest, 'fcat/fpkg-1.0', depend, PDU)),
          fixup:phase_retry_hook(useenable, FakeEbuild, 'fcat/fpkg-1.0', compile, LogFile, '', fixuptest:fixup_noop_cb, 0, 1, 1)
        ))
    ),
    ( retractall(config:pkg_directory(PkgDir)),
      retractall(config:ebuild_command('/usr/bin/true')),
      retractall(config:kernel_source_dir(_)),
      assertz(config:kernel_source_dir('/usr/src/linux')),
      retractall(qtest:get_ebuild_file(_, _)),
      retractall(cache:ordered_entry(pkg, 'fcat/fpkg-1.0', _, _, _)),
      retractall(cache:ordered_entry(pkg, 'dev-lang/ocaml-5.0', _, _, _)),
      retractall(cache:ordered_entry(qtest, _, fcat, _, _)),
      retractall(cache:ordered_entry(qtest, 'sys-apps/semodule-utils-1.0', _, _, _)),
      retractall(cache:ordered_entry(qtest, 'kde-frameworks/kwindowsystem-1.0', _, _, _)),
      retractall(cache:ordered_entry(qtest, 'x11-libs/libXdamage-1.0', _, _, _)),
      retractall(cache:entry_metadata(qtest, 'fcat/fpkg-1.0', _, _)),
      retractall(ghcabi:repair_applied_(_, _)),
      retractall(ghcabi:cabal_core_cache_(_, _)),
      retractall(ocamlabi:repair_applied_(_, _)),
      retractall(feedback:excluded_version(fcat, fpkg, _, _)),
      fixup:clear,
      ( HadEnv == true -> setenv('PORTAGE_NG_STATE', OldEnv) ; unsetenv('PORTAGE_NG_STATE') ),
      fixup_rm_rf(TmpDir)
    )).

:- end_tests(exceptions_full_coverage).
