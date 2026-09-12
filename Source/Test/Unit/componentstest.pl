/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> COMPONENTSTEST
Unit tests for the mutual-reachability classes (Source/Logic/components.pl).

Two nodes share a class iff each is reachable from the other over the
supplied edge relation; everything else gets a class of its own.
*/

:- module(componentstest, []).

:- use_module(library(plunit)).
:- use_module(library(assoc)).
:- use_module(library(lists)).

% =============================================================================
%  COMPONENTSTEST declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Fixture: an edge relation given as a list of From-To pairs
% -----------------------------------------------------------------------------

edge_in(Edges, X, Y) :- member(X-Y, Edges).

classes_of(Nodes, Edges, Idx) :-
  components:classes(Nodes, componentstest:edge_in(Edges), Idx).

same(Idx, X, Y) :-
  get_assoc(X, Idx, C), get_assoc(Y, Idx, C).


% -----------------------------------------------------------------------------
%  Class structure
% -----------------------------------------------------------------------------

:- begin_tests(components).

test(every_node_classified) :-
  classes_of([a, b, c], [a-b], Idx),
  forall(member(N, [a, b, c]), get_assoc(N, Idx, _)).

test(chain_has_singleton_classes) :-
  classes_of([a, b, c], [a-b, b-c], Idx),
  \+ same(Idx, a, b), \+ same(Idx, b, c), \+ same(Idx, a, c).

test(two_cycle_is_one_class) :-
  classes_of([a, b], [a-b, b-a], Idx),
  same(Idx, a, b).

test(long_cycle_is_one_class) :-
  classes_of([a, b, c, d], [a-b, b-c, c-d, d-a], Idx),
  same(Idx, a, b), same(Idx, b, c), same(Idx, c, d).

test(one_way_reachability_is_not_enough) :-
  % a reaches b and c, nothing reaches back: three classes.
  classes_of([a, b, c], [a-b, a-c, b-c], Idx),
  \+ same(Idx, a, b), \+ same(Idx, a, c), \+ same(Idx, b, c).

test(two_cycles_joined_one_way_stay_apart) :-
  % {a,b} -> {c,d}: the bridge is not mutual.
  classes_of([a, b, c, d], [a-b, b-a, b-c, c-d, d-c], Idx),
  same(Idx, a, b), same(Idx, c, d), \+ same(Idx, b, c).

test(cycle_plus_tail_splits) :-
  % a<->b, and b -> c (a dead end): c is its own class.
  classes_of([a, b, c], [a-b, b-a, b-c], Idx),
  same(Idx, a, b), \+ same(Idx, b, c).

test(self_loop_is_a_class) :-
  classes_of([a], [a-a], Idx),
  get_assoc(a, Idx, _).

test(successor_outside_node_list_is_classified) :-
  classes_of([a], [a-b, b-a], Idx),
  same(Idx, a, b).

test(disconnected_nodes_get_distinct_classes) :-
  classes_of([a, b, c], [], Idx),
  \+ same(Idx, a, b), \+ same(Idx, b, c).

test(result_independent_of_node_order) :-
  Edges = [p-q, q-r, r-p, r-s, s-t, t-s, u-p],
  classes_of([p, q, r, s, t, u], Edges, I1),
  classes_of([u, t, s, r, q, p], Edges, I2),
  forall(( member(X, [p, q, r, s, t, u]), member(Y, [p, q, r, s, t, u]) ),
         ( same(I1, X, Y) -> same(I2, X, Y) ; \+ same(I2, X, Y) )).

test(nested_terms_as_nodes) :-
  % Plan-step shaped nodes: the module treats them as opaque keys.
  N = repo://'cat/nautilus-1':run,
  S = repo://'cat/sushi-1':run,
  GN = grouped(nautilus):run,
  GS = grouped(sushi):run,
  classes_of([N, S, GN, GS], [N-GS, GS-S, S-GN, GN-N], Idx),
  same(Idx, N, S), same(Idx, N, GN), same(Idx, N, GS).

:- end_tests(components).
