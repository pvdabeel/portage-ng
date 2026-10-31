/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> CONSTRAINTTEST
Unit tests for the constraint store (Source/Logic/constraint.pl).

Constraint identification, unification and conversion.
*/

:- module(constrainttest, []).

:- use_module(library(plunit)).
:- use_module(library(assoc)).
:- use_module(library(lists)).

% =============================================================================
%  CONSTRAINTTEST declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Constraint module tests
% -----------------------------------------------------------------------------

:- begin_tests(constraint_identification).

test(is_constraint_true) :-
  constraint:is_constraint(constraint(foo)).

test(is_constraint_false, [fail]) :-
  constraint:is_constraint(not_a_constraint).

:- end_tests(constraint_identification).


:- begin_tests(constraint_unification).

test(unify_ordset_new) :-
  empty_assoc(C0),
  constraint:unify_constraints(constraint(k:{ordset([b,a,c])}), C0, C1),
  get_assoc(k, C1, ordset(V)),
  V == [a,b,c].

test(unify_ordset_merge) :-
  empty_assoc(C0),
  put_assoc(k, C0, ordset([a,c]), C1),
  constraint:unify_constraints(constraint(k:{ordset([b,d])}), C1, C2),
  get_assoc(k, C2, ordset(V)),
  V == [a,b,c,d].

test(unify_atom_new) :-
  empty_assoc(C0),
  constraint:unify_constraints(constraint(k:{hello}), C0, C1),
  get_assoc(k, C1, V),
  V == hello.

test(unify_atom_same_existing) :-
  empty_assoc(C0),
  put_assoc(k, C0, hello, C1),
  constraint:unify_constraints(constraint(k:{hello}), C1, C2),
  get_assoc(k, C2, V),
  V == hello.

test(unify_empty_list_new) :-
  empty_assoc(C0),
  constraint:unify_constraints(constraint(k:{[]}), C0, C1),
  get_assoc(k, C1, V),
  is_assoc(V).

test(unify_list_new) :-
  empty_assoc(C0),
  constraint:unify_constraints(constraint(k:{[a:install]}), C0, C1),
  get_assoc(k, C1, V),
  get_assoc(a:install, V, {}).

test(unify_empty_list_into_existing_assoc) :-
  empty_assoc(E),
  constraint:unify_constraint([], E, Out),
  Out == E.

test(unify_list_into_empty_assoc) :-
  empty_assoc(E),
  constraint:unify_constraint([a:install], E, Out),
  get_assoc(a:install, Out, {}).

:- end_tests(constraint_unification).


:- begin_tests(constraint_conversion).

test(empty_to_list, [true(L == [])]) :-
  empty_assoc(A),
  constraint:constraints_to_list(A, L).

test(list_to_constraints_roundtrip, [true(L == [pkg:install?{[flag]}])]) :-
  constraint:list_to_constraints([pkg:install?{[flag]}], A),
  constraint:constraints_to_list(A, L).

:- end_tests(constraint_conversion).
