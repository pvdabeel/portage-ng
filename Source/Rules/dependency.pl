/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> DEPENDENCY
Package dependency resolution, grouped dependency handling, and blocker
management for the rules engine.

Provides the implementation predicates that rule/2 bodies delegate to for
resolving package dependencies, handling grouped dependencies (including
the decomposition of the complex grouped_package_dependency resolution),
and managing weak/strong blockers.
*/

:- module(dependency, []).
