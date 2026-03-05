/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> CANDIDATE
Candidate selection, slot management, version handling, and ranking for
the rules engine.

Provides implementation predicates for selecting suitable ebuild candidates,
merging slot restrictions, coercing version terms, ranking dependencies for
deterministic group choice, and verifying installed package satisfaction.
*/

:- module(candidate, []).
