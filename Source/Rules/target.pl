/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> TARGET
Action-level implementation for the rules engine: install, update,
downgrade, fetchonly, depclean, run, reinstall, and uninstall.

Provides the implementation predicates that rule/2 bodies delegate to
for action-specific logic such as eligibility checks, model building,
download condition generation, dependency ordering, and transactional
update/downgrade context management.
*/

:- module(target, []).
