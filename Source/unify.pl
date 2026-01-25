/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> UNIFY
Non-Destructive Feature Unification.

This is the active version (promoted from `Source/Archive/unify.pl`).

The exported predicate `feature_unification:unify/3` is intended to be used as the
single operation for both:
- merging two feature terms (contexts)
- adding information into an existing feature term

In the portage-ng codebase, the *syntax* uses `...?{Ctx}` where `Ctx` is one of
`{}`, `{[]}`, `{L}`. Note that the curly braces are part of the `?{}` annotation
syntax; inside the engine we typically operate on the inner list `L`.

This module stays domain-agnostic: it does not mention ebuilds, USE flags, or
any domain-specific functors.
*/

:- module(feature_unification, [unify/3]).

:- use_module(library(lists)).   % intersection/3, subset/2

% =============================================================================
%  Public API
% =============================================================================

%! feature_unification:unify(+FeatureTerm, +FeatureTerm, -Unified) is semidet.
%
% Non-destructive feature unification.
%
% Feature terms are represented as *lists* of items. Items may be:
% - feature:value pairs (F:V)
% - plain items (atoms/compounds)
%
% Values can be:
% - `{L}` representing a constrained set (intersection semantics on unify)
% - lists `[ ... ]` representing multi-valued features (union semantics on unify)
% - any other Prolog term unified by normal Prolog unification.
%
% Extra generic consistency rule:
% - a term and its negation-as-failure wrapper cannot both be present:
%     X  and naf(X)  are inconsistent.
%
unify(F1, F2, F3) :-
  normalize_ft(F1, N1),
  normalize_ft(F2, N2),
  hunify(N1, N2, S1, U1),
  hunify(N2, N1, S2, _),
  % Keep top-level concatenation simple (cost is small compared to inner loops).
  append(U1, S1, Tmp),
  append(Tmp, S2, F3).

% =============================================================================
%  Normalization (minimal; domain-agnostic)
% =============================================================================

% Historically some callers used `{}` as an "empty feature term". We treat that as [].
normalize_ft({}, []) :- !.
normalize_ft(F, F) :- is_list(F), !.
normalize_ft(F, F).  % keep as-is (lets unification fail meaningfully later)

is_colon_pair(Term) :-
  compound(Term),
  functor(Term, ':', 2).

% -----------------------------------------------------------------------------
%  Generic "negative" wrappers used inside lists
% -----------------------------------------------------------------------------
%
% We treat both `minus(X)` and `naf(X)` as generic negation wrappers.
% If a merged list contains both X and minus(X), or both X and naf(X),
% the list is inconsistent and unification fails.
is_neg_wrapper(minus(_)).
is_neg_wrapper(naf(_)).

negates(minus(X), X).
negates(naf(X), X).

list_canon_and_check(L0, L) :-
  % Deduplicate + canonical ordering.
  sort(L0, L),
  % Reject contradictions (in either direction).
  \+ ( member(Neg, L),
       negates(Neg, Pos),
       memberchk(Pos, L)
     ).

merge_compound_term(T1, T2, T3) :-
  compound(T1),
  compound(T2),
  \+ is_colon_pair(T1),
  \+ is_colon_pair(T2),
  functor(T1, F, A),
  functor(T2, F, A),
  T1 =.. [F|Args1],
  T2 =.. [F|Args2],
  maplist(val, Args1, Args2, Args3),
  T3 =.. [F|Args3].

same_compound_shape(T1, T2) :-
  compound(T1),
  compound(T2),
  \+ is_colon_pair(T1),
  \+ is_colon_pair(T2),
  functor(T1, F, A),
  functor(T2, F, A).

% =============================================================================
%  Horizontal unification
% =============================================================================

hunify(List, F2, S, U) :-
  hunify_acc(List, F2, [], SRev, [], URev),
  reverse(SRev, S),
  reverse(URev, U).

hunify_acc([Fp|R], F2, S0, S, U0, U) :-
  vunify(Fp, F2, S1, U1),
  add_singleton(S1, S0, S2),
  add_singleton(U1, U0, U2),
  hunify_acc(R, F2, S2, S, U2, U).
hunify_acc([], _F2, S, S, U, U).

add_singleton([], Acc, Acc) :- !.
add_singleton([X], Acc, [X|Acc]) :- !.
add_singleton(L, _Acc, _Out) :-
  % By construction vunify/4 should only ever return [] or a singleton here.
  % Fail fast if that assumption is violated so we don't silently change semantics.
  is_list(L),
  length(L, Len),
  Len =\= 1,
  !,
  fail.

% =============================================================================
%  Value unification
% =============================================================================

% CASE 1: default (identical)
val(V, V, V) :- !.

% CASE 2: constrained sets {..} x {..} => intersection (must be non-empty)
val({V1}, {V2}, {V3}) :-
  !,
  intersection(V1, V2, V3),
  \+ empty(V3).

% CASE 3: multi-valued lists [..] x [..] => merge
val([V1|V1r], [V2|V2r], V3) :-
  !,
  append([V1|V1r], [V2|V2r], L0),
  list_canon_and_check(L0, L),
  V3 = L.

% CASE 4: [..] x {..} => subset check (consistency)
val([V1|V1r], {V2}, {V2}) :-
  !,
  subset([V1|V1r], V2),
  subset(V2, [V1|V1r]).

val([], {V2}, {V2}) :-
  !,
  \+ empty(V2).

% CASE 5: {..} x [..] => subset check (consistency)
val({V1}, [V2|V2r], {V1}) :-
  !,
  subset([V2|V2r], V1),
  subset(V1, [V2|V2r]).

val({V1}, [], {V1}) :-
  !.

% CASE 6: atom/term x [..] => treat as singleton list then list-merge
val(V1, [V2|V2r], V3) :-
  !,
  append([V1], [V2|V2r], L0),
  list_canon_and_check(L0, L),
  V3 = L.

% CASE 7: [..] x atom/term => treat as singleton list then list-merge
val([V1|V1r], V2, V3) :-
  !,
  append([V1|V1r], [V2], L0),
  list_canon_and_check(L0, L),
  V3 = L.

% CASE 8: atom/term x {..} => intersection singleton (must be non-empty)
val(V1, {V2}, V3) :-
  !,
  intersection([V1], V2, [V3]),
  \+ empty(V3).

% CASE 9: {..} x atom/term => intersection singleton (must be non-empty)
val({V1}, V2, V3) :-
  !,
  intersection(V1, [V2], [V3]),
  \+ empty(V3).

empty([]) :- !.

% =============================================================================
%  Vertical unification
% =============================================================================

% CASE 1a: feature:value requires unification
vunify(F:V1, [F:V2|R], [], U) :-
  !,
  val(V1, V2, Vu),
  vunify(F:Vu, R, [], U).

% CASE 1b: feature:value does not require unification
vunify(F1:V1, [_:_|R], S, U) :-
  !,
  vunify(F1:V1, R, S, U).

% CASE 2a: not a feature:value pair, but would require unification
% (plain duplicate, or naf-contradiction checks)
vunify(Nocolon, [Head|R], S, U) :-
  \+ is_colon_pair(Nocolon),
  !,
  % If the other side has a feature:value pair, this plain item can't unify with it.
  ( is_colon_pair(Head) ->
      vunify(Nocolon, R, S, U)
  ;
  ( Head = naf(X), Nocolon == X ->
      fail
  ; Nocolon = naf(X), Head == X ->
      fail
  ; Nocolon == Head ->
      % From now on Skipped shall be empty because we have detected at least one
      % unification so far.
      vunify(Nocolon, R, [], U)
  ; same_compound_shape(Nocolon, Head) ->
      % Same functor/arity: must unify as a "feature"; if values are inconsistent
      % (e.g. list contains X and minus(X)), the whole unification fails.
      ( merge_compound_term(Nocolon, Head, Merged) ->
          vunify(Merged, R, [], U)
      ; fail
      )
  ; vunify(Nocolon, R, S, U)
  )).

% CASE 3a: nothing to unify against, no earlier unifications
vunify(F, [], [F], []) :- !.

% CASE 3b: nothing to unify against, earlier unifications detected
vunify(F, [], [], [F]) :- !.

