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
  components:classes_enum(Nodes, components:edge_succs(EdgeGoal), ClassAVL).


%! components:classes_succ(+Nodes, +SuccAVL, -ClassAVL)
%
% Like classes/3, but the successors of each node are the sorted list
% stored under that node in SuccAVL (empty when the node is absent).
% Callers that already hold an adjacency list skip the per-node
% findall of EdgeGoal.

classes_succ(Nodes, SuccAVL, ClassAVL) :-
  components:classes_enum(Nodes, components:avl_succs(SuccAVL), ClassAVL).


node_class(node(_Index, _Lowlink, Class), Class).


edge_succs(EdgeGoal, V, Ws) :-
  findall(W, call(EdgeGoal, V, W), Ws0),
  sort(Ws0, Ws).


avl_succs(SuccAVL, V, Ws) :-
  ( get_assoc(V, SuccAVL, Ws) -> true ; Ws = [] ).


% -----------------------------------------------------------------------------
% Depth-first walk
% -----------------------------------------------------------------------------
%
% state(NextIndex, NodeAVL, Stack, NextClass).
%
% NodeAVL is pre-allocated for every node in Nodes with Index 0 meaning
% unvisited; discovery indexes run from 1. A record is updated in place
% (setarg/3 on the index, the lowlink and the class), so the walk costs
% one AVL insertion per node rather than one per lowlink update.
% Successors outside Nodes are inserted on first reach. The walk is
% deterministic, so the in-place updates are never undone by
% backtracking before classes/3 reads them out. The stack holds
% Node-Record pairs so popping a class needs no lookups.

classes_enum(Nodes, SuccGoal, ClassAVL) :-
  sort(Nodes, Sorted),
  components:empty_node_pairs(Sorted, Pairs),
  list_to_assoc(Pairs, NodeAVL),
  foldl(components:root(SuccGoal), Sorted,
        state(1, NodeAVL, [], 0),
        state(_, Visited, _, _)),
  map_assoc(components:node_class, Visited, ClassAVL).


empty_node_pairs([], []).
empty_node_pairs([V|Vs], [V-node(0, 0, none)|Pairs]) :-
  components:empty_node_pairs(Vs, Pairs).


root(SuccGoal, V, S0, S) :-
  S0 = state(_, Nodes, _, _),
  get_assoc(V, Nodes, Record),
  ( arg(1, Record, 0) ->
      components:connect(SuccGoal, V, Record, S0, S)
  ; S = S0
  ).


connect(SuccGoal, V, Record, state(N0, Nodes0, Stack0, K0), S) :-
  N1 is N0 + 1,
  setarg(1, Record, N0),
  setarg(2, Record, N0),
  call(SuccGoal, V, Ws),
  foldl(components:successor(SuccGoal, Record), Ws,
        state(N1, Nodes0, [V-Record|Stack0], K0),
        S1),
  S1 = state(N2, Nodes2, Stack2, K2),
  arg(2, Record, LowV),
  ( LowV =:= N0 ->
      components:pop(Stack2, V, K2, Stack3),
      K3 is K2 + 1,
      S = state(N2, Nodes2, Stack3, K3)
  ; S = S1
  ).


successor(SuccGoal, VRecord, W, S0, S) :-
  S0 = state(_, Nodes0, _, _),
  ( get_assoc(W, Nodes0, WRecord) ->
      ( arg(1, WRecord, 0) ->
          % Pre-allocated, still unvisited: tree edge.
          components:connect(SuccGoal, W, WRecord, S0, S),
          arg(2, WRecord, LowW),
          components:lower(VRecord, LowW)
      ; arg(3, WRecord, none) ->
          % Back edge to a node still on the stack: take its index.
          arg(1, WRecord, IdxW),
          components:lower(VRecord, IdxW),
          S = S0
      ; % Cross edge to a completed class: no information.
        S = S0
      )
  ; % Successor outside Nodes: insert, then recurse.
    WRecord = node(0, 0, none),
    S0 = state(N0, Nodes0, Stack0, K0),
    put_assoc(W, Nodes0, WRecord, Nodes1),
    components:connect(SuccGoal, W, WRecord,
                       state(N0, Nodes1, Stack0, K0), S),
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
