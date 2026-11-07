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
        state(0, E, [], 0),
        state(_, Visited, _, _)),
  map_assoc(components:node_class, Visited, ClassAVL).


node_class(node(_Index, _Lowlink, Class), Class).


% -----------------------------------------------------------------------------
% Depth-first walk
% -----------------------------------------------------------------------------
%
% state(NextIndex, NodeAVL, Stack, NextClass).
%
% NodeAVL maps every visited node to its record node(Index, Lowlink,
% Class); Class is `none` while the node is on the stack. A record is
% inserted once, when its node is first reached, and updated in place
% afterwards (setarg/3 on the lowlink and the class), so the walk costs
% one AVL insertion per node rather than one per lowlink update. The walk
% is deterministic, so the in-place updates are never undone by
% backtracking before classes/3 reads them out. The stack holds
% Node-Record pairs so popping a class needs no lookups.

root(EdgeGoal, V, S0, S) :-
  S0 = state(_, Nodes, _, _),
  ( get_assoc(V, Nodes, _) -> S = S0
  ; components:connect(EdgeGoal, V, S0, S, _)
  ).


connect(EdgeGoal, V, state(N0, Nodes0, Stack0, K0), S, Record) :-
  N1 is N0 + 1,
  Record = node(N0, N0, none),
  put_assoc(V, Nodes0, Record, Nodes1),
  findall(W, call(EdgeGoal, V, W), Ws0),
  sort(Ws0, Ws),
  foldl(components:successor(EdgeGoal, Record), Ws,
        state(N1, Nodes1, [V-Record|Stack0], K0),
        S1),
  S1 = state(N2, Nodes2, Stack2, K2),
  arg(2, Record, LowV),
  ( LowV =:= N0 ->
      components:pop(Stack2, V, K2, Stack3),
      K3 is K2 + 1,
      S = state(N2, Nodes2, Stack3, K3)
  ; S = S1
  ).


successor(EdgeGoal, VRecord, W, S0, S) :-
  S0 = state(_, Nodes, _, _),
  ( get_assoc(W, Nodes, WRecord) ->
      ( arg(3, WRecord, none) ->
          % Back edge to a node still on the stack: take its index.
          arg(1, WRecord, IdxW),
          components:lower(VRecord, IdxW)
      ; % Cross edge to a completed class: no information.
        true
      ),
      S = S0
  ; % Tree edge: recurse, then inherit W's lowlink.
    components:connect(EdgeGoal, W, S0, S, WRecord),
    arg(2, WRecord, LowW),
    components:lower(VRecord, LowW)
  ).


lower(Record, X) :-
  arg(2, Record, Low),
  ( X < Low -> setarg(2, Record, X) ; true ).


pop([W-Record|Rest], V, K, Stack) :-
  setarg(3, Record, K),
  ( W == V -> Stack = Rest
  ; components:pop(Rest, V, K, Stack)
  ).
