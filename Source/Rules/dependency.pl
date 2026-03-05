/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> DEPENDENCY
Package dependency resolution helpers for the rules engine.

Provides context-management predicates for annotating dependency literals
with provenance information (self-references) and USE-requirement collection.
*/

:- module(dependency, []).


% =============================================================================
%  Dependency context management
% =============================================================================

add_self_to_dep_contexts(_Self, [], []) :- !.
add_self_to_dep_contexts(Self, [D0|Rest0], [D|Rest]) :-
  ( D0 = Term:Action?{Ctx} ->
      ctx_set_self(Ctx, Self, Ctx1),
      D = Term:Action?{Ctx1}
  ; D = D0
  ),
  add_self_to_dep_contexts(Self, Rest0, Rest).

ctx_set_self(Ctx0, Self, Ctx) :-
  ( is_list(Ctx0) ->
      ( selectchk(self(_), Ctx0, Ctx1) -> true ; Ctx1 = Ctx0 ),
      Ctx = [self(Self)|Ctx1]
  ; Ctx = [self(Self)]
  ),
  !.


% =============================================================================
%  USE requirement collection for dependency edges
% =============================================================================

collect_use_requirements([], []).
collect_use_requirements([use(enable(Use), _)|Rest], [required(Use)|RestRequirements]) :-
    !,
    collect_use_requirements(Rest, RestRequirements).
collect_use_requirements([use(disable(Use), _)|Rest], [naf(required(Use))|RestRequirements]) :-
    !,
    collect_use_requirements(Rest, RestRequirements).
collect_use_requirements([use(equal(Use), _)|Rest], [required(Use)|RestRequirements]) :-
    !,
    collect_use_requirements(Rest, RestRequirements).
collect_use_requirements([use(inverse(Use), _)|Rest], [naf(required(Use))|RestRequirements]) :-
    !,
    collect_use_requirements(Rest, RestRequirements).
collect_use_requirements([use(optenable(Use), _)|Rest], [required(Use)|RestRequirements]) :-
    !,
    collect_use_requirements(Rest, RestRequirements).
collect_use_requirements([use(optdisable(Use), _)|Rest], [naf(required(Use))|RestRequirements]) :-
    !,
    collect_use_requirements(Rest, RestRequirements).
collect_use_requirements([_|Rest], RestRequirements) :-
    !,
    collect_use_requirements(Rest, RestRequirements).

process_use(ParentContext, use(Directive, Default), Acc, AccOut) :-
    !,
    use:use_dep_requirement(ParentContext, Directive, Default, Requirement),
    ( Requirement = requirement(enable, Use, _Default) ->
        AccOut = [required(Use), assumed(Use)|Acc]
    ; Requirement = requirement(disable, Use, _Default) ->
        AccOut = [naf(required(Use)), assumed(minus(Use))|Acc]
    ; AccOut = Acc
    ).

process_use(_ParentContext, _Other, Acc, Acc) :- !.


% =============================================================================
%  Slot context propagation
% =============================================================================

process_slot([any_different_slot], _, _, _, _, Context, Context) :- !.
process_slot([slot(_)|_], _SlotMeta, _C, _N, _Repository://_Candidate, Context, Context) :- !.
process_slot(_, Slot, C, N, _Repository://Candidate, Context0, Context) :-
  feature_unification:unify([slot(C, N, Slot):{Candidate}], Context0, Context).


% =============================================================================
%  Build-with-use context propagation
% =============================================================================

process_build_with_use(Directives, Context0, Context, Conditions, Candidate) :-
    ( select(build_with_use:_, Context0, Context1) -> true ; Context1 = Context0 ),
    use:empty_use_state(PrevState),
    foldl(use:process_bwu_directive(Context0), Directives, PrevState, State0),
    use:normalize_build_with_use(State0, State),
    ( State = use_state([], []) ->
        Context = Context1
    ; feature_unification:unify([build_with_use:State], Context1, Context)
    ),
    build_with_use_constraints(Directives, Conditions, Candidate).

build_with_use_constraints(_, [], _) :- !.
