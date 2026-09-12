/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> COMPONENTS
Mutual-reachability classes over a caller-supplied edge relation.

Two nodes belong to the same class exactly when each is reachable from
the other (a strongly connected component). The module knows nothing
about the nodes: it is handed the node list and an edge goal, and returns
an AVL mapping every node to an opaque class identifier. Callers compare
identifiers; they never inspect them.

Used by the ordering rule set to decide which preferences lie on a
cycle (Source/Domain/Gentoo/Rules/ordering.pl, ordering:same_component/2).
*/

:- module(components, []).

:- use_module(library(assoc)).

% =============================================================================
%  COMPONENTS declarations
% =============================================================================

% -----------------------------------------------------------------------------
% Public entry point
% -----------------------------------------------------------------------------

%! components:classes(+Nodes, :EdgeGoal, -ClassAVL)
%
% ClassAVL maps every node in Nodes to a class identifier such that two
% nodes share an identifier iff each is reachable from the other over
% the edges enumerated by call(EdgeGoal, Node, Successor). Successors
% outside Nodes are followed and classified too. One depth-first pass
% (Tarjan): linear in nodes plus edges.

:- meta_predicate components:classes(+, 2, -).

classes(Nodes, EdgeGoal, ClassAVL) :-
  empty_assoc(E),
  foldl(components:root(EdgeGoal), Nodes,
        state(0, E, E, [], E, 0),
        state(_, _, _, _, ClassAVL, _)).


% -----------------------------------------------------------------------------
% Depth-first walk
% -----------------------------------------------------------------------------
%
% state(NextIndex, IndexAVL, LowlinkAVL, Stack, ClassAVL, NextClass).
% A node is on the stack iff it has an index but no class yet.

root(EdgeGoal, V, S0, S) :-
  S0 = state(_, Index, _, _, _, _),
  ( get_assoc(V, Index, _) -> S = S0
  ; components:connect(EdgeGoal, V, S0, S)
  ).


connect(EdgeGoal, V, state(N0, I0, L0, Stack0, C0, K0), S) :-
  N1 is N0 + 1,
  put_assoc(V, I0, N0, I1),
  put_assoc(V, L0, N0, L1),
  findall(W, call(EdgeGoal, V, W), Ws0),
  sort(Ws0, Ws),
  foldl(components:successor(EdgeGoal, V), Ws,
        state(N1, I1, L1, [V|Stack0], C0, K0),
        S1),
  S1 = state(N2, I2, L2, Stack2, C2, K2),
  get_assoc(V, L2, LowV),
  get_assoc(V, I2, IdxV),
  ( LowV =:= IdxV ->
      components:pop(Stack2, V, K2, C2, Stack3, C3),
      K3 is K2 + 1,
      S = state(N2, I2, L2, Stack3, C3, K3)
  ; S = S1
  ).


successor(EdgeGoal, V, W, S0, S) :-
  S0 = state(_, Index, _, _, Class, _),
  ( \+ get_assoc(W, Index, _) ->
      % Tree edge: recurse, then inherit W's lowlink.
      components:connect(EdgeGoal, W, S0, S1),
      S1 = state(N, I, L, Stack, C, K),
      get_assoc(W, L, LowW),
      components:lower(V, LowW, L, L2),
      S = state(N, I, L2, Stack, C, K)
  ; \+ get_assoc(W, Class, _) ->
      % Back edge to a node still on the stack: take its index.
      S0 = state(N, I, L, Stack, C, K),
      get_assoc(W, I, IdxW),
      components:lower(V, IdxW, L, L2),
      S = state(N, I, L2, Stack, C, K)
  ; % Cross edge to a completed class: no information.
    S = S0
  ).


lower(V, X, L0, L) :-
  get_assoc(V, L0, LowV),
  ( X < LowV -> put_assoc(V, L0, X, L) ; L = L0 ).


pop([W|Rest], V, K, C0, Stack, C) :-
  put_assoc(W, C0, K, C1),
  ( W == V -> Stack = Rest, C = C1
  ; components:pop(Rest, V, K, C1, Stack, C)
  ).
