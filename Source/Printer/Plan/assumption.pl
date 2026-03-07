/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> ASSUMPTION
Assumption classification and context analysis for proof terms.

This module provides predicates that classify normalised assumption terms
into symbolic types for statistics bucketing, extract context tags from
nested wrappers, and locate cycle paths for assumption nodes.

It is purely analytical — no terminal rendering.  Primary consumer is
sampler.pl for cross-entry test statistics aggregation.
*/

:- module(assumption, []).

% =============================================================================
%  ASSUMPTION declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Assumption classification
% -----------------------------------------------------------------------------

%! assumption:assumption_type(+Content, -Type)
%
% Classify a normalised assumption term into a symbolic Type for
% statistics bucketing. Unwraps Action?{Ctx} wrappers early so
% classification can match the underlying term.

assumption:assumption_type('?'(Inner, '{}'(Ctx)), Type) :-
  is_list(Ctx),
  memberchk(assumption_reason(Reason), Ctx),
  ( Inner = grouped_package_dependency(_,_,_):_
  ; Inner = grouped_package_dependency(_,_,_,_):_
  ),
  assumption:assumption_reason_type(Reason, Type),
  !.
assumption:assumption_type('?'(Inner, _Ctx), Type) :-
  !,
  assumption:assumption_type(Inner, Type).
assumption:assumption_type(cycle_break(_), cycle_break) :- !.
assumption:assumption_type(domain(X), Type) :-
  assumption:assumption_reason_from_term(X, Reason),
  assumption:assumption_reason_type(Reason, Type),
  !.
assumption:assumption_type(domain(X), Type) :-
  assumption:assumption_type(X, Type),
  !.
assumption:assumption_type(domain(X), Type) :-
  ( assumption:assumption_reason_from_term(X, Reason) ->
      assumption:assumption_reason_type(Reason, Type),
      !
  ; fail
  ).
assumption:assumption_type(package_dependency(_,_,_,_,_,_,_,_):_,              non_existent_dependency) :- !.
assumption:assumption_type(grouped_package_dependency(_,_,_):_,                non_existent_dependency) :- !.
assumption:assumption_type(grouped_package_dependency(_,_,_,_):_,              non_existent_dependency) :- !.
assumption:assumption_type(_://_:unmask,                                       masked) :- !.
assumption:assumption_type(_://_:install,                                      assumed_installed) :- !.
assumption:assumption_type(_://_:run,                                          assumed_running) :- !.
assumption:assumption_type(grouped_package_dependency(_,_,_,_):install?{_},    assumed_installed) :- !.
assumption:assumption_type(grouped_package_dependency(_,_,_,_):run?{_},        assumed_running) :- !.
assumption:assumption_type(grouped_package_dependency(_,_,_,_):install,        assumed_installed) :- !.
assumption:assumption_type(grouped_package_dependency(_,_,_,_):run,            assumed_running) :- !.
assumption:assumption_type(blocker(_Strength,_Phase,_C,_N,_O,_V,_SlotReq),     blocker_assumption) :- !.
assumption:assumption_type(Term, issue_with_model) :-
  explainer:term_ctx(Term, Ctx),
  memberchk(issue_with_model(_), Ctx),
  !.
assumption:assumption_type(required(_),                                        use_requirement_cycle) :- !.
assumption:assumption_type(blocking(_),                                        use_requirement_cycle) :- !.
assumption:assumption_type(use_conditional_group(_,_,_,_),                     use_conditional_cycle) :- !.
assumption:assumption_type(any_of_group(_),                                    dependency_group_cycle) :- !.
assumption:assumption_type(all_of_group(_),                                    dependency_group_cycle) :- !.
assumption:assumption_type(exactly_one_of_group(_),                            dependency_group_cycle) :- !.
assumption:assumption_type(at_most_one_of_group(_),                            dependency_group_cycle) :- !.
assumption:assumption_type(naf(_),                                             naf_cycle) :- !.
assumption:assumption_type(_,                                                  other).


%! assumption:assumption_reason_from_term(+Term, -Reason)
%
% Extract the assumption_reason/1 tag from Term's context (if present).

assumption:assumption_reason_from_term(Term, Reason) :-
  explainer:term_ctx(Term, Ctx),
  memberchk(assumption_reason(Reason), Ctx),
  !.


%! assumption:assumption_reason_type(+Reason, -Type)
%
% Map an assumption reason atom to its statistics bucket type.

assumption:assumption_reason_type(missing,                                     missing_dependency).
assumption:assumption_reason_type(masked,                                      masked_dependency).
assumption:assumption_reason_type(keyword_filtered,                            keyword_filtered_dependency).
assumption:assumption_reason_type(installed_required,                          installed_required_dependency).
assumption:assumption_reason_type(slot_unsatisfied,                            slot_unsatisfied_dependency).
assumption:assumption_reason_type(version_no_candidate(_,_),                   version_no_candidate_dependency).
assumption:assumption_reason_type(version_conflict(_),                         version_conflict_dependency).
assumption:assumption_reason_type(version_no_candidate,                        version_no_candidate_dependency).
assumption:assumption_reason_type(version_conflict,                            version_conflict_dependency).
assumption:assumption_reason_type(version_unsatisfied,                         version_no_candidate_dependency).
assumption:assumption_reason_type(unsatisfied_constraints,                     unsatisfied_constraints_dependency).


%! assumption:assumption_is_package_level(+Content)
%
% True when Content represents a package-level assumption.

assumption:assumption_is_package_level(_://_:install) :- !.
assumption:assumption_is_package_level(_://_:run) :- !.
assumption:assumption_is_package_level(_://_:fetchonly) :- !.
assumption:assumption_is_package_level(_://_:unmask) :- !.
assumption:assumption_is_package_level(grouped_package_dependency(_,_,_,_):_) :- !.
assumption:assumption_is_package_level(package_dependency(_,_,_,_,_,_,_,_):_) :- !.


%! assumption:assumption_head_key(+Content, -Key)
%
% Generate a stable head key (functor/arity atom) for an assumption term.

assumption:assumption_head_key(Content, Key) :-
  assumption:assumption_head_term(Content, Head),
  ( atomic(Head) ->
      Key = Head
  ; Head =.. [F|Args],
    length(Args, A),
    format(atom(Key), '~w/~d', [F, A])
  ).


%! assumption:assumption_head_term(+Term0, -Term)
%
% Recursively strip common wrappers to expose the core functor.

assumption:assumption_head_term(Term0, Term) :-
  ( var(Term0) ->
      Term = Term0
  ; Term0 = '?'(Inner, _Ctx) ->
      assumption:assumption_head_term(Inner, Term)
  ; Term0 = ':'(_M, Goal) ->
      assumption:assumption_head_term(Goal, Term)
  ; Term0 = '://'(_Repo, Entry) ->
      assumption:assumption_head_term(Entry, Term)
  ; Term0 =.. [_F, A] ->
      ( Term0 = domain(X)      -> assumption:assumption_head_term(X, Term)
      ; Term0 = cycle_break(X) -> assumption:assumption_head_term(X, Term)
      ; Term = Term0
      ),
      A = A
  ; Term = Term0
  ).


% =============================================================================
%  Context unwrapping
% =============================================================================

%! assumption:unwrap_ctx_wrappers(+Term, -Core)
%
% Strip all nested ?/2 context wrappers to expose the core literal.

assumption:unwrap_ctx_wrappers('?'(Inner, _Ctx), Core) :-
  !,
  assumption:unwrap_ctx_wrappers(Inner, Core).
assumption:unwrap_ctx_wrappers(Core, Core).


%! assumption:collect_ctx_tags(+Term, -Tags)
%
% Collect all context tag lists from nested ?/2 wrappers into a flat list.

assumption:collect_ctx_tags('?'(Inner, Ctx0), Tags) :-
  !,
  assumption:ctx_term_to_list(Ctx0, Tags0),
  assumption:collect_ctx_tags(Inner, Tags1),
  append(Tags0, Tags1, Tags).
assumption:collect_ctx_tags(_Other, []).


%! assumption:ctx_term_to_list(+Ctx0, -Tags)
%
% Normalise a context term to a list.

assumption:ctx_term_to_list(Ctx0, Tags) :-
  ( is_list(Ctx0) ->
      Tags = Ctx0
  ; Ctx0 =.. ['{}'|Tags] ->
      true
  ; Tags = []
  ).


% =============================================================================
%  Cycle lookup for assumption nodes
% =============================================================================

%! assumption:cycle_for_assumption(+StartKey0, +TriggersAVL, -CyclePath0, -CyclePath)
%
% Compute a cycle path (if any) for an assumption key.

assumption:cycle_for_assumption(StartKey0, TriggersAVL, CyclePath0, CyclePath) :-
  ( StartKey0 = cycle_break(X) -> StartKey1 = X ; StartKey1 = StartKey0 ),
  ( prover:canon_literal(StartKey1, StartKey, _) -> true ; StartKey = StartKey1 ),
  ( StartKey = _://_:install ; StartKey = _://_:run ; StartKey = _://_:fetchonly
  ; StartKey = _:install     ; StartKey = _:run     ; StartKey = _:fetchonly
  ),
  cycle:cycle_start_pkg_key(StartKey, TriggersAVL, StartPkg),
  cycle:find_cycle_via_triggers(StartPkg, TriggersAVL, CyclePath0),
  cycle:cycle_display_path(CyclePath0, CyclePath),
  CyclePath = [_|_].
