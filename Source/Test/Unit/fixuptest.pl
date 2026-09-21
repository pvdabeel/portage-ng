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

test(kx11extras_header) :-
  useenable:detector(
    ["fatal error: KX11Extras: No such file or directory"],
    symbol(kf_header, 'KX11Extras'), _).

test(kstartupinfo_header) :-
  useenable:detector(
    ["error: KStartupInfo: No such file or directory"],
    symbol(kf_header, 'KStartupInfo'), _).

test(pimcommon_activities_header) :-
  useenable:detector(
    ["fatal error: KPim6PimCommonActivities: No such file or directory"],
    symbol(kf_header, 'KPim6PimCommonActivities'), _).

% Real kaddressbook configure log: CMake find_package, not a fatal #include.
test(pimcommon_activities_could_not_find) :-
  useenable:detector(
    ["-- Could NOT find KPim6PimCommonActivities (missing: KPim6PimCommonActivities_DIR)"],
    symbol(kf_header, 'KPim6PimCommonActivities'), _).

% Real kget compile log: GCC colors wrap the header token in CSI sequences.
test(kx11extras_ansi_colored) :-
  useenable:detector(
    ["\u001b[01m\u001b[K/tmp/droptarget.cpp:37:10:\u001b[m\u001b[K \u001b[01;31m\u001b[Kfatal error: \u001b[m\u001b[KKX11Extras: No such file or directory"],
    symbol(kf_header, 'KX11Extras'), _).

test(strip_ansi_removes_embedded_csi) :-
  useenable:strip_ansi(
    "fatal error: \u001b[m\u001b[KKX11Extras: No such file",
    Clean),
  Clean == "fatal error: KX11Extras: No such file".

test(cmake_xdamage) :-
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
      cleanup(retractall(feedback:excluded_version('dev-haskell', text, _, _)))]) :-
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
