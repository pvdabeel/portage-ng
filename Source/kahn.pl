/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> KAHN
Kahn's algorithm for topological sorting. Operates on an adjacency list
represented as an assoc (Node -> [Successor...]) where an edge A -> B means
A depends on B. Detects cycles and returns unprocessed nodes separately.
*/

:- module(kahn, []).


% =============================================================================
%  KAHN declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Topological sort
% -----------------------------------------------------------------------------

%! kahn:toposort(+Nodes, +Edges, -Order, -Cyclic)
%
% Topological sort via Kahn's algorithm. Edges is an assoc mapping each
% node to its list of successors (dependencies). Returns the sorted Order
% and Cyclic = true if a cycle prevents full ordering (remaining nodes
% are appended to the order).

kahn:toposort(Nodes, Edges, Order, Cyclic) :-
  kahn:indegrees(Nodes, Edges, InDeg0),
  findall(N, (member(N, Nodes), get_assoc(N, InDeg0, 0)), Q0),
  kahn:process(Q0, Nodes, Edges, InDeg0, [], Order0, Remaining),
  ( Remaining == [] ->
      Cyclic = false,
      Order = Order0
  ; Cyclic = true,
    append(Order0, Remaining, Order)
  ).


% -----------------------------------------------------------------------------
%  In-degree computation
% -----------------------------------------------------------------------------

%! kahn:indegrees(+Nodes, +Edges, -InDeg)
%
% Build the initial in-degree map for all nodes.

kahn:indegrees(Nodes, Edges, InDeg) :-
  empty_assoc(Empty0),
  foldl([N,In,Out]>>put_assoc(N, In, 0, Out), Nodes, Empty0, Empty1),
  foldl(kahn:indegree_acc(Edges), Nodes, Empty1, InDeg).


%! kahn:indegree_acc(+Edges, +Node, +InDegIn, -InDegOut)
%
% Accumulate in-degrees contributed by Node's successors.

kahn:indegree_acc(Edges, A, In, Out) :-
  ( get_assoc(A, Edges, Bs) -> true ; Bs = [] ),
  foldl(kahn:inc_indeg, Bs, In, Out).


%! kahn:inc_indeg(+Node, +InDegIn, -InDegOut)
%
% Increment the in-degree counter for Node by one.

kahn:inc_indeg(B, In, Out) :-
  ( get_assoc(B, In, V0) ->
      V1 is V0 + 1,
      put_assoc(B, In, V1, Out)
  ; put_assoc(B, In, 1, Out)
  ).


% -----------------------------------------------------------------------------
%  Work loop
% -----------------------------------------------------------------------------

%! kahn:process(+Queue, +Nodes, +Edges, +InDeg, +Acc, -Order, -Remaining)
%
% Work loop. Processes zero-in-degree nodes, decrements neighbors, and
% collects the topological order. Remaining holds any nodes still
% unprocessed (cycle members).

kahn:process([], Nodes, _Edges, InDeg, Acc, Order, Remaining) :-
  reverse(Acc, Order),
  findall(N, (member(N, Nodes), get_assoc(N, InDeg, V), V > 0), Remaining).
kahn:process([N|Q], Nodes, Edges, InDeg0, Acc, Order, Remaining) :-
  ( get_assoc(N, Edges, Bs) -> true ; Bs = [] ),
  put_assoc(N, InDeg0, -1, InDeg1),
  kahn:dec_neighbors(Bs, InDeg1, InDeg2, NewZeros),
  append(Q, NewZeros, Q2),
  kahn:process(Q2, Nodes, Edges, InDeg2, [N|Acc], Order, Remaining).


%! kahn:dec_neighbors(+Neighbors, +InDegIn, -InDegOut, -NewZeros)
%
% Decrement in-degree for each neighbor; collect those that reach zero.

kahn:dec_neighbors([], InDeg, InDeg, []).
kahn:dec_neighbors([B|Bs], InDeg0, InDeg, NewZeros) :-
  ( get_assoc(B, InDeg0, V0),
    V0 >= 0 ->
      V1 is V0 - 1,
      put_assoc(B, InDeg0, V1, InDeg1),
      ( V1 =:= 0 -> NewZeros = [B|RestZeros] ; NewZeros = RestZeros ),
      kahn:dec_neighbors(Bs, InDeg1, InDeg, RestZeros)
  ; kahn:dec_neighbors(Bs, InDeg0, InDeg, NewZeros)
  ).
