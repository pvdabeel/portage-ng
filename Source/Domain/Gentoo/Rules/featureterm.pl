/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> FEATURETERM
Proof-context list manipulation helpers for rule/2 bodies.

The planner uses `after/1` and `after_only/1` markers in dependency
contexts to express ordering constraints between actions.  The
predicates in this module thread, extract, and strip these markers.

Additional helpers strip `build_with_use:_` and `assumption_reason(_)`
terms from contexts when they should not propagate (e.g. PDEPEND edges).
*/

:- module(featureterm, []).


% =============================================================================
%  FEATURETERM declarations
% =============================================================================


% -----------------------------------------------------------------------------
%  Planning-only ordering markers
% -----------------------------------------------------------------------------

%! featureterm:get_after(+Context0, -After, -Context)
%
% Extracts the first `after(Literal)` marker from Context0.
% Unifies After with `none` if no marker is present.

featureterm:get_after(Context0, After, Context) :-
  ( is_list(Context0),
    select(after(After1), Context0, Context1) ->
      After = After1,
      Context = Context1
  ; After = none,
    Context = Context0
  ),
  !.


%! featureterm:get_after_with_mode(+Context0, -After, -AfterForDeps, -Context)
%
% Like get_after/3 but distinguishes `after/1` (propagates to deps)
% from `after_only/1` (does not propagate -- AfterForDeps = none).

featureterm:get_after_with_mode(Context0, After, AfterForDeps, Context) :-
  ( is_list(Context0),
    select(after_only(After1), Context0, Ctx1) ->
      After = After1,
      AfterForDeps = none,
      ( select(after(_), Ctx1, Context) -> true ; Context = Ctx1 )
  ; is_list(Context0),
    select(after(After1), Context0, Ctx1) ->
      After = After1,
      AfterForDeps = After1,
      ( select(after_only(_), Ctx1, Context) -> true ; Context = Ctx1 )
  ; After = none,
    AfterForDeps = none,
    Context = Context0
  ),
  !.


%! featureterm:add_after_condition(+After, +AfterForDeps, +Conds0, -Conds)
%
% Prepends an ordering constraint to Conds0 based on the extracted markers.
% `after/1` becomes a real dependency; `after_only/1` becomes a
% `constraint(order_after(...))` that the planner uses for ordering only.

featureterm:add_after_condition(none, _AfterForDeps, Conditions, Conditions) :- !.
featureterm:add_after_condition(After, none, Conditions0, [constraint(order_after(After):{[]} )|Conditions0]) :-
  After \== none,
  !.
featureterm:add_after_condition(After, _AfterForDeps, Conditions0, [After|Conditions0]) :-
  !.


%! featureterm:get(+Feature, +Context, -Conditions)
%
% Extracts a feature from Context and converts it to a condition list.

featureterm:get(after, Context, Conditions) :-
  featureterm:get_after(Context, After, _),
  ( After == none -> Conditions = [] ; Conditions = [After] ).


%! featureterm:set(+Feature, +Entry, +Context, -Conditions)
%
% Builds a reinstall literal from Entry and Context, prepending any
% ordering constraint extracted from the after/after_only markers.

featureterm:set(reinstall, Repository://Ebuild, Context, Conditions) :-
  featureterm:get_after_with_mode(Context, After, AfterForDeps, Context1),
  Cond0 = [Repository://Ebuild:reinstall?{Context1}],
  featureterm:add_after_condition(After, AfterForDeps, Cond0, Conditions).


%! featureterm:strip_planning(+Context0, -Context)
%
% Removes planning-only markers (after/1, world_atom/1) from a context
% so they do not affect dependency-model memoization keys.

featureterm:strip_planning(Context0, Context) :-
  ( is_list(Context0) ->
      findall(X,
              ( member(X, Context0),
                \+ X = after(_),
                \+ X = world_atom(_)
              ),
              Context)
  ; Context = Context0
  ),
  !.


% -----------------------------------------------------------------------------
%  After/after_only injection into dependency lists
% -----------------------------------------------------------------------------

%! featureterm:add_after_to_dep_contexts(+After, +Deps0, -Deps)
%
% Injects an `after/1` marker into each dependency literal's context.

featureterm:add_after_to_dep_contexts(none, Deps, Deps) :- !.
featureterm:add_after_to_dep_contexts(After, Deps0, Deps) :-
  is_list(Deps0),
  !,
  findall(D,
          ( member(D0, Deps0),
            ( D0 = Term:Action?{Ctx0} ->
                featureterm:add_after(Ctx0, After, Ctx),
                D = Term:Action?{Ctx}
            ; D = D0
            )
          ),
          Deps).
featureterm:add_after_to_dep_contexts(_After, Deps, Deps).


featureterm:add_after(Ctx0, After, Ctx) :-
  ( is_list(Ctx0) ->
      ( select(after(_), Ctx0, Ctx1) -> true ; Ctx1 = Ctx0 ),
      Ctx = [after(After)|Ctx1]
  ; Ctx = [after(After)]
  ),
  !.


%! featureterm:add_after_only_to_dep_contexts(+After, +Deps0, -Deps)
%
% Injects an `after_only/1` marker into each dependency literal's context.
% Unlike after/1, after_only/1 does not propagate into the dependency's
% own closure (ordering applies only to the direct goal).

featureterm:add_after_only_to_dep_contexts(_After, [], []) :- !.
featureterm:add_after_only_to_dep_contexts(After, Deps0, Deps) :-
  is_list(Deps0),
  !,
  findall(D,
          ( member(D0, Deps0),
            ( D0 = Term:Action?{Ctx0} ->
                featureterm:add_after_only(Ctx0, After, Ctx),
                D = Term:Action?{Ctx}
            ; D = D0
            )
          ),
          Deps).
featureterm:add_after_only_to_dep_contexts(_After, Deps, Deps).


featureterm:add_after_only(Ctx0, After, Ctx) :-
  ( is_list(Ctx0) ->
      ( select(after(_), Ctx0, Ctx1) -> true ; Ctx1 = Ctx0 ),
      ( select(after_only(_), Ctx1, Ctx2) -> true ; Ctx2 = Ctx1 ),
      Ctx = [after_only(After)|Ctx2]
  ; Ctx = [after_only(After)]
  ),
  !.


% -----------------------------------------------------------------------------
%  Build-with-use / assumption-reason stripping
% -----------------------------------------------------------------------------

%! featureterm:drop_build_with_use_from_dep_contexts(+Deps0, -Deps)
%
% Strips `build_with_use` terms from each dependency context.
% Used during PDEPEND expansion where build_with_use serves only as a
% memoization key, not a semantic constraint on the targets.

featureterm:drop_build_with_use_from_dep_contexts([], []) :- !.
featureterm:drop_build_with_use_from_dep_contexts([D0|Rest0], [D|Rest]) :-
  !,
  featureterm:drop_build_with_use_from_dep_context(D0, D),
  featureterm:drop_build_with_use_from_dep_contexts(Rest0, Rest).
featureterm:drop_build_with_use_from_dep_contexts(Deps, Deps).


featureterm:drop_build_with_use_from_dep_context(Dep0:Act?{Ctx0}, Dep:Act?{Ctx}) :-
  !,
  Dep = Dep0,
  featureterm:drop_build_with_use(Ctx0, Ctx).
featureterm:drop_build_with_use_from_dep_context(Other, Other).


%! featureterm:drop_build_with_use(+Ctx0, -Ctx)
%
% Removes all `build_with_use:_` terms from a context.

featureterm:drop_build_with_use(Ctx0, Ctx) :-
  ( is_list(Ctx0) ->
      exclude(featureterm:is_build_with_use_term, Ctx0, Ctx)
  ; Ctx = Ctx0
  ),
  !.

featureterm:is_build_with_use_term(build_with_use:_) :- !.


%! featureterm:drop_assumption_reason(+Ctx0, -Ctx)
%
% Removes all `assumption_reason(_)` terms from a context.

featureterm:drop_assumption_reason(Ctx0, Ctx) :-
  ( is_list(Ctx0) ->
      exclude(featureterm:is_assumption_reason_term, Ctx0, Ctx)
  ; Ctx = Ctx0
  ),
  !.

featureterm:is_assumption_reason_term(assumption_reason(_)) :- !.


%! featureterm:drop_build_with_use_and_assumption_reason(+Ctx0, -Ctx)
%
% Removes both `build_with_use:_` and `assumption_reason(_)` from a context.
% Used for PDEPEND edges where neither should propagate.

featureterm:drop_build_with_use_and_assumption_reason(Ctx0, Ctx) :-
  ( is_list(Ctx0) ->
      exclude(featureterm:is_bwu_or_assumption_reason, Ctx0, Ctx)
  ; Ctx = Ctx0
  ),
  !.

featureterm:is_bwu_or_assumption_reason(build_with_use:_) :- !.
featureterm:is_bwu_or_assumption_reason(assumption_reason(_)) :- !.