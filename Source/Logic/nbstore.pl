/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> NBSTORE
Backtrack-safe key/value stores held in thread global variables.

A store is a red-black tree (library(rbtrees)) kept under a global
variable name with nb_setval/2 and updated in place with
library(nb_rbtrees). Puts therefore cost O(log n) and copy only the key
and value, where storing a fresh copy of an AVL with nb_setval/2 after
every put_assoc/4 copies the whole tree (O(n) per put, O(n^2) per proof).

Like nb_setval/2, every value put into a store is copied, survives
backtracking, and is returned by get/3 without copying. The stores are
per thread, exactly as the global variables that hold them.

This module stays domain-agnostic: callers choose the store names and
key shapes.
*/

:- module(nbstore, []).

% =============================================================================
%  NBSTORE declarations
% =============================================================================

:- use_module(library(rbtrees), [rb_new/1, rb_lookup/3]).
:- use_module(library(nb_rbtrees), [nb_rb_insert/3,
                                    nb_rb_get_node/3,
                                    nb_rb_set_node_value/2]).


% -----------------------------------------------------------------------------
%  Store lifecycle
% -----------------------------------------------------------------------------

%! nbstore:empty(-Store) is det.
%
% Store is a fresh empty store term, suitable for saving as the
% "nothing recorded" state of a store that has not been reset yet.

nbstore:empty(Store) :-
  rb_new(Store).


%! nbstore:reset(+Name) is det.
%
% Installs a fresh empty store under global variable Name, discarding
% whatever Name held before.

nbstore:reset(Name) :-
  rb_new(Store),
  nb_setval(Name, Store).


% -----------------------------------------------------------------------------
%  Lookup and update
% -----------------------------------------------------------------------------

%! nbstore:get(+Name, +Key, -Value) is semidet.
%
% Value is the value recorded under Key in store Name. Fails when Name
% holds no store or Key has no entry.

nbstore:get(Name, Key, Value) :-
  nb_current(Name, Store),
  rb_lookup(Key, Value, Store).


%! nbstore:put(+Name, +Key, +Value) is det.
%
% Records Value under Key in store Name, replacing a previous value for
% Key. A missing store is created first. Value is copied, as nb_setval/2
% would copy it.

nbstore:put(Name, Key, Value) :-
  ( nb_current(Name, Store) ->
      true
  ; rb_new(Store0),
    nb_setval(Name, Store0),
    nb_current(Name, Store)
  ),
  ( nb_rb_get_node(Store, Key, Node) ->
      nb_rb_set_node_value(Node, Value)
  ; nb_rb_insert(Store, Key, Value)
  ).
