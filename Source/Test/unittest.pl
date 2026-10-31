/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> UNITTEST
PLUnit-based unit tests for core modules.

Loads the unit test files under Source/Test/Unit/, one per subject
(EAPI grammar, version domains, constraints, mutual-reachability classes,
sanitize, depclean,
exception fixups, USE rules, ranking, rebuilds, resolving heuristics,
query layer, synthetic-rule prover core, printer, builder, binpkg,
interface, VDB import, GLSA, profile parents, ebuild protocol), and re-exports the two standalone harnesses
(Source/Test/md5cache.pl, Source/Test/profilemask.pl).

Run via the project wrapper:

  ./Source/Application/Wrapper/portage-ng-dev --mode standalone --shell <<'PL'
  load_files(portage('Source/Test/unittest'), [if(true)]).
  run_tests.
  halt.
  PL

Or via make:

  make test
*/

:- module(unittest, []).

:- use_module(library(plunit)).

:- set_test_options([load(always)]).

% GitHub Actions loads standalone and then this file. It does not pass
% through --shell, so the build, graph, bulk, cluster and language-model
% groups are still unloaded. The tests call those modules.
unittest:ensure_runtime :-
  loader:ensure(build),
  loader:ensure(graph),
  loader:ensure(bulk),
  loader:ensure(cluster),
  ( config:load_llm_modules(true) -> loader:ensure(llm) ; true ).

% The GitHub Actions PLUnit job never runs preference:init, so
% ACCEPT_KEYWORDS is empty and keyworded fixtures have no visible
% candidate. A booted standalone process already has keywords; leave
% those in place. Paired with unittest:restore_stable_amd64/0 from
% the test cleanup.

unittest:accept_stable_amd64 :-
  ( preference:local_accept_keywords(_) ->
      nb_setval(unittest_added_amd64, false)
  ; assertz(preference:local_accept_keywords(stable(amd64))),
    nb_setval(unittest_added_amd64, true)
  ).


unittest:restore_stable_amd64 :-
  ( nb_current(unittest_added_amd64, true) ->
      retractall(preference:local_accept_keywords(stable(amd64)))
  ; true
  ),
  ( nb_current(unittest_added_amd64, _) ->
      nb_delete(unittest_added_amd64)
  ; true
  ).

:- initialization(unittest:ensure_runtime, now).

:- reexport(portage('Source/Test/md5cache')).
:- reexport(portage('Source/Test/profilemask')).

% =============================================================================
%  UNITTEST declarations
% =============================================================================

:- use_module(portage('Source/Test/Unit/eapitest')).
:- use_module(portage('Source/Test/Unit/versiontest')).
:- use_module(portage('Source/Test/Unit/constrainttest')).
:- use_module(portage('Source/Test/Unit/componentstest')).
:- use_module(portage('Source/Test/Unit/sanitizetest')).
:- use_module(portage('Source/Test/Unit/depcleantest')).
:- use_module(portage('Source/Test/Unit/fixuptest')).
:- use_module(portage('Source/Test/Unit/usetest')).
:- use_module(portage('Source/Test/Unit/rankingtest')).
:- use_module(portage('Source/Test/Unit/rebuildtest')).
:- use_module(portage('Source/Test/Unit/resolvingtest')).
:- use_module(portage('Source/Test/Unit/querytest')).
:- use_module(portage('Source/Test/Unit/synthetictest')).
:- use_module(portage('Source/Test/Unit/printertest')).
:- use_module(portage('Source/Test/Unit/buildertest')).
:- use_module(portage('Source/Test/Unit/binpkgtest')).
:- use_module(portage('Source/Test/Unit/interfacetest')).
:- use_module(portage('Source/Test/Unit/vdbtest')).
:- use_module(portage('Source/Test/Unit/glsatest')).
:- use_module(portage('Source/Test/Unit/profiletest')).
:- use_module(portage('Source/Test/Unit/bugstest')).
:- use_module(portage('Source/Test/Unit/navthemetest')).
:- use_module(portage('Source/Test/Unit/messagetest')).
:- use_module(portage('Source/Test/Unit/httpfetchtest')).
:- use_module(portage('Source/Test/Unit/downloadtest')).
:- use_module(portage('Source/Test/Unit/daemontest')).
:- use_module(portage('Source/Test/Unit/ebuildtest')).
:- use_module(portage('Source/Test/Unit/jobtest')).
