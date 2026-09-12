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
(EAPI grammar, version domains, constraints, sanitize, depclean,
exception fixups, USE rules, ranking, rebuilds, resolving heuristics,
query layer, synthetic-rule prover core, printer, builder, interface,
VDB import, GLSA), and re-exports the two standalone harnesses
(Source/Test/md5cache.pl, Source/Test/profilemask.pl).

Run via the project wrapper:

  ./Source/Application/Wrapper/portage-ng-dev --mode standalone --shell <<'PL'
  load_files(portage('Source/Test/unittest'), [if(true)]).
  run_tests.
  halt.
  PL

Or via make:

  make test

Profile-mask golden regression (requires `Knowledge/kb.qlf` and
`Knowledge/profile.qlf`; snapshot embedded in Source/Test/profilemask.pl):

  make test-profile-mask-golden

Regenerate the golden snapshot after an intentional mask-logic change:

  make test-profile-mask-golden-update
*/

:- module(unittest, []).

:- use_module(library(plunit)).

:- set_test_options([load(always)]).

:- reexport(portage('Source/Test/md5cache')).
:- reexport(portage('Source/Test/profilemask')).

% =============================================================================
%  UNITTEST declarations
% =============================================================================

:- use_module(portage('Source/Test/Unit/eapitest')).
:- use_module(portage('Source/Test/Unit/versiontest')).
:- use_module(portage('Source/Test/Unit/constrainttest')).
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
:- use_module(portage('Source/Test/Unit/interfacetest')).
:- use_module(portage('Source/Test/Unit/vdbtest')).
:- use_module(portage('Source/Test/Unit/glsatest')).
:- use_module(portage('Source/Test/Unit/bugstest')).
