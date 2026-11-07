/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> NBSTORE
Backtrack-safe key/value stores held in thread global variables.

A store is a hash table kept under a global variable name with
nb_setval/2 and updated in place with nb_setarg/3: a store(Count,
Buckets) term whose Buckets compound holds one Key-Value chain per
argument, the bucket count being its arity. get/3 costs one term_hash/2
and one arg/3; put/3 rewrites a single chain and, when Count exceeds the
bucket count, swaps in a compound of twice the arity with one nb_setarg/3,
so the store is consistent at every step.

Why this and not the two obvious alternatives, both measured:

  - An AVL (library(assoc)) stored back with nb_setval/2 after every
    put copies the whole tree per put: O(n) per update, O(n^2) per
    proof.
  - A thread_local fact table reads faster still (first-argument JIT
    index), but every assertz/retract on a thread_local predicate takes
    a process-wide lock in SWI-Prolog. Ten threads each doing 300k
    updates ran 6-23x slower per thread than one thread did; the
    resolver's single-thread gain from fact tables vanished entirely
    under `resolver:test_stats`. Global-variable terms live on the
    thread's own stacks, so this store scales linearly.

Like nb_setval/2, every value put into a store is copied, survives
backtracking, and is returned by get/3 without copying. Keys must be
ground. The stores are per thread, exactly as the global variables
that hold them.

This module stays domain-agnostic: callers choose the store names and
key shapes.
*/

:- module(nbstore, []).

% =============================================================================
%  NBSTORE declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Store lifecycle
% -----------------------------------------------------------------------------

%! nbstore:empty(-Store) is det.
%
% Store is a fresh empty store term, suitable for saving as the
% "nothing recorded" state of a store that has not been reset yet.

nbstore:empty(Store) :-
  nbstore:new_store(16, Store).


%! nbstore:reset(+Name) is det.
%
% Installs a fresh empty store under global variable Name, discarding
% whatever Name held before.

nbstore:reset(Name) :-
  nbstore:empty(Store),
  nb_setval(Name, Store).


%! nbstore:new_store(+Size, -Store) is det.
%
% An empty store with Size buckets.

nbstore:new_store(Size, store(0, Buckets)) :-
  nbstore:empty_buckets(Size, Buckets).


%! nbstore:empty_buckets(+Size, -Buckets) is det.
%
% A buckets compound of arity Size with every chain empty. The initial
% size is a literal: every store is reset at the start of every proof,
% and nb_setval/2 copies the term anyway.

nbstore:empty_buckets(16, b([],[],[],[],[],[],[],[],[],[],[],[],[],[],[],[])) :-
  !.
nbstore:empty_buckets(Size, Buckets) :-
  length(Chains, Size),
  maplist(=([]), Chains),
  compound_name_arguments(Buckets, b, Chains).


% -----------------------------------------------------------------------------
%  Lookup and update
% -----------------------------------------------------------------------------

%! nbstore:get(+Name, +Key, -Value) is semidet.
%
% Value is the value recorded under ground Key in store Name. Fails when
% Name holds no store or Key has no entry.

nbstore:get(Name, Key, Value) :-
  nb_current(Name, store(_, Buckets)),
  nbstore:bucket(Key, Buckets, I),
  arg(I, Buckets, Chain),
  memberchk(Key-Value, Chain).


%! nbstore:put(+Name, +Key, +Value) is det.
%
% Records Value under ground Key in store Name, replacing a previous
% value for Key. A missing store is created first. Value is copied, as
% nb_setval/2 would copy it.

nbstore:put(Name, Key, Value) :-
  ( nb_current(Name, Store) ->
      true
  ; nbstore:reset(Name),
    nb_current(Name, Store)
  ),
  Store = store(Count, Buckets),
  nbstore:bucket(Key, Buckets, I),
  arg(I, Buckets, Chain),
  ( selectchk(Key-_, Chain, Rest) ->
      nb_setarg(I, Buckets, [Key-Value|Rest])
  ; nb_setarg(I, Buckets, [Key-Value|Chain]),
    Count1 is Count + 1,
    nb_setarg(1, Store, Count1),
    functor(Buckets, _, Size),
    ( Count1 > Size ->
        nbstore:grow(Store)
    ; true
    )
  ).


%! nbstore:bucket(+Key, +Buckets, -I) is det.
%
% I is the 1-based argument of Buckets that holds Key's chain.

nbstore:bucket(Key, Buckets, I) :-
  term_hash(Key, Hash),
  functor(Buckets, _, Size),
  I is Hash mod Size + 1.


%! nbstore:grow(!Store) is det.
%
% Doubles the bucket count of Store: every pair is rehashed into a fresh
% Buckets compound of twice the arity, which then replaces the old one
% with a single in-place assignment. An exception before that assignment
% leaves the old table intact and the next put retries the growth.

nbstore:grow(Store) :-
  Store = store(_, Buckets),
  functor(Buckets, _, Size),
  Size2 is Size * 2,
  nbstore:empty_buckets(Size2, Buckets2),
  forall(( arg(_, Buckets, Chain),
           member(Pair, Chain)
         ),
         ( Pair = Key-_,
           nbstore:bucket(Key, Buckets2, I),
           arg(I, Buckets2, Chain2),
           nb_setarg(I, Buckets2, [Pair|Chain2])
         )),
  nb_setarg(2, Store, Buckets2).
