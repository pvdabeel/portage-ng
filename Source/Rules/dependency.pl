/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> DEPENDENCY
Package dependency context management for the rules engine.

This module provides predicates that annotate dependency literals with
provenance information (self-references), manage slot context propagation
across dependency edges, and handle build-with-use state threading.

The rule/2 clauses in rules.pl call into this module when they need to:

  1. Tag dependency literals with `self(Repo://Entry)` so downstream rules
     can distinguish self-dependencies from external ones.

  2. Propagate slot locks into the dependency context so that `:=`
     (rebuild-on-slot-change) semantics work correctly.

  3. Thread `build_with_use` state from bracketed USE constraints
     (e.g. `dev-libs/foo[bar]`) into the child dependency context.

  4. Collect USE requirements from dependency edges into the format
     expected by the prover's assumption mechanism.

== Key design constraints ==

  * Self-context (`self/1`): at most one `self/1` term is kept in any
    context to prevent context growth along deep dependency chains (which
    would defeat memoization).

  * Build-with-use: per-package state.  A child's build_with_use must NOT
    inherit the parent's; only the directives from the current dependency
    edge are applied.  This prevents parent USE state from leaking into
    dependencies and causing Portage-divergent rebuilds.
*/

:- module(dependency, []).


% =============================================================================
%  Dependency context management
% =============================================================================

%! add_self_to_dep_contexts(+Self, +Deps0, -Deps) is det.
%
%  Annotate every dependency literal in Deps0 with `self(Self)` so that
%  downstream rules can identify the parent ebuild.  Keeps at most one
%  `self/1` term per context to prevent growth along chains.
%
%  @arg Self   The parent entry, e.g. `portage://dev-libs/foo-1.0`
%  @arg Deps0  Input dependency list (Term:Action?{Ctx} elements)
%  @arg Deps   Output with self/1 injected into each context

add_self_to_dep_contexts(_Self, [], []) :- !.
add_self_to_dep_contexts(Self, [D0|Rest0], [D|Rest]) :-
  ( D0 = Term:Action?{Ctx} ->
      ctx_set_self(Ctx, Self, Ctx1),
      D = Term:Action?{Ctx1}
  ; D = D0
  ),
  add_self_to_dep_contexts(Self, Rest0, Rest).

%! ctx_set_self(+Ctx0, +Self, -Ctx) is det.
%
%  Replace or insert a `self(Self)` term in context Ctx0.
%  If Ctx0 already contains a self/1 term it is replaced (not stacked).

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

%! collect_use_requirements(+UseDeps, -Requirements) is det.
%
%  Convert a list of `use(Directive, Default)` terms into the prover's
%  assumption format: `required(Use)` for enable directives,
%  `naf(required(Use))` for disable directives.
%
%  @arg UseDeps       List of use/2 terms from package_dependency USE field
%  @arg Requirements  Corresponding prover literals

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

%! process_use(+ParentContext, +UseDirective, +Acc, -AccOut) is det.
%
%  Fold helper: processes a single USE dependency directive and accumulates
%  assumption terms for the dependency context.
%
%  CRITICAL: this predicate must be deterministic.  Non-determinism here
%  causes massive backtracking explosions when build-with-use context is
%  propagated through dependency cycles.
%
%  @arg ParentContext  The parent's dependency context
%  @arg UseDirective   A `use(Directive, Default)` term
%  @arg Acc            Accumulator (list of assumption terms)
%  @arg AccOut         Extended accumulator

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

%! process_slot(+SlotReq, +SlotMeta, +C, +N, +RepoEntry, +Ctx0, -Ctx) is det.
%
%  Propagate a slot lock into the dependency context after a candidate has
%  been selected.  Explicit slot requirements (`[slot(_)|_]`) and
%  `any_different_slot` are not locked -- explicit slots allow multi-slot
%  coexistence (e.g. Ruby :3.2 + :3.3) and `any_different_slot` is by
%  definition not lockable.
%
%  @arg SlotReq    Slot requirement list from the dependency
%  @arg SlotMeta   Resolved slot metadata from the candidate
%  @arg C          Category atom
%  @arg N          Name atom
%  @arg RepoEntry  Selected candidate (Repo://Entry)
%  @arg Ctx0       Input context
%  @arg Ctx        Output context (with slot lock if applicable)

process_slot([any_different_slot], _, _, _, _, Context, Context) :- !.
process_slot([slot(_)|_], _SlotMeta, _C, _N, _Repository://_Candidate, Context, Context) :- !.
process_slot(_, Slot, C, N, _Repository://Candidate, Context0, Context) :-
  feature_unification:unify([slot(C, N, Slot):{Candidate}], Context0, Context).


% =============================================================================
%  Build-with-use context propagation
% =============================================================================

%! process_build_with_use(+Directives, +Ctx0, -Ctx, -Conditions, +Candidate) is det.
%
%  Thread bracketed USE constraints from a dependency edge into the child
%  context.  Strips any inherited build_with_use from the parent context
%  and builds fresh per-package USE state from the current directives only.
%
%  IMPORTANT (correctness): build_with_use is per-package state.  The child
%  must not inherit the parent's build_with_use -- otherwise parent USE state
%  (e.g. gui/widgets, abi_x86_*) leaks into the dependency and causes
%  Portage-divergent rebuilds.
%
%  IMPORTANT (performance): at most one build_with_use term is kept in the
%  context to prevent growth that defeats cycle detection/memoization.
%
%  @arg Directives  List of use/2 directives from the dependency
%  @arg Ctx0        Parent context (may contain build_with_use to strip)
%  @arg Ctx         Child context with fresh build_with_use
%  @arg Conditions  Build-with-use constraint literals (currently [])
%  @arg Candidate   The selected candidate entry

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

%! build_with_use_constraints(+Directives, -Conditions, +Candidate) is det.
%
%  Generate global constraint literals from build-with-use directives.
%  Currently a no-op (returns []) because Portage-style USE deps are
%  per-package constraints modelled via context, not global constraints.

build_with_use_constraints(_, [], _) :- !.
