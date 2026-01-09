/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> EXPLAINER (generic)
Generic introspection and explanation utilities.

This module is intentionally domain-agnostic. It should explain "why" questions
from existing artifacts (ProofAVL, ModelAVL, Plan, TriggersAVL), without
embedding Gentoo/Portage policy.

Domain-specific explanation belongs in `explanation.pl`.
*/

:- module(explainer, [
  assumption_content_from_proof_key/2,
  assumption_normalize/2,
  term_ctx/2,
  why_in_plan/5,
  why_in_plan/6,
  why_in_proof/3,
  why_in_proof/4,
  why_assumption/4,
  why_assumption/5
]).


% -----------------------------------------------------------------------------
%  Proof/model artifact helpers (generic)
% -----------------------------------------------------------------------------

% Map proof keys to a normalized wrapper that preserves the assumption taxonomy:
% - Domain assumptions: introduced by `rules.pl` (proof key `rule(assumed(X))`)
% - Cycle breaks      : introduced by `prover.pl` (proof key `assumed(rule(X))`)
assumption_content_from_proof_key(rule(assumed(Content)), domain(Content)) :- !.
assumption_content_from_proof_key(assumed(rule(Content)), cycle_break(Content)) :- !.

% Normalize assumptions for stable counting/printing:
% - Canonicalize the literal
% - Preserve context (it may contain tags like assumption_reason/1, self/1, etc.)
assumption_normalize(Content0, Content) :-
  ( Content0 = domain(X) ->
      % Preserve context (it may contain domain-level reason tags).
      ( X = _?{_} ->
          prover:canon_literal(X, Core, Ctx),
          Content = domain(Core?{Ctx})
      ; prover:canon_literal(X, Core, _Ctx) ->
          Content = domain(Core)
      ; Content = domain(X)
      )
  ; Content0 = cycle_break(X) ->
      % Preserve context (it may contain action provenance etc.).
      ( X = _?{_} ->
          prover:canon_literal(X, Core, Ctx),
          Content = cycle_break(Core?{Ctx})
      ; prover:canon_literal(X, Core, _Ctx) ->
          Content = cycle_break(Core)
      ; Content = cycle_break(X)
      )
  ; ( prover:canon_literal(Content0, Core, _Ctx) -> Content = Core ; Content = Content0 )
  ).

% Extract context tags from a term with `?{Ctx}`.
% Supports both list contexts and the legacy `{}` compound form.
term_ctx(_Spec:_Action?{Ctx0}, Ctx) :-
  ( is_list(Ctx0) ->
      Ctx = Ctx0
  ; Ctx0 =.. ['{}'|Ctx] ->
      true
  ; Ctx = []
  ),
  !.
term_ctx(_Other, []).


% -----------------------------------------------------------------------------
%  "Why is X in proof?" (generic)
% -----------------------------------------------------------------------------

%! why_in_proof(+ProofAVL, +Target, -Why) is semidet.
why_in_proof(ProofAVL, Target, Why) :-
  why_in_proof(ProofAVL, Target, _ProofKey, Why).

%! why_in_proof(+ProofAVL, +Target, -ProofKey, -Why) is semidet.
%
% Target is a literal (e.g. `portage://cat/pkg:install?{Ctx}`).
% ProofKey is one of:
% - rule(Lit)               (normal proven rule)
% - assumed(rule(Lit))      (prover cycle-break rule)
% - rule(assumed(Lit))      (domain assumption rule)
%
% Why is a structured term describing what we found.
why_in_proof(ProofAVL, Target0, ProofKey, Why) :-
  prover:canon_literal(Target0, Target, _),
  explainer:proof_lookup(ProofAVL, Target, ProofKey, dep(Count, Body), Ctx),
  Why0 = why_in_proof(Target,
                      proof_key(ProofKey),
                      depcount(Count),
                      body(Body),
                      ctx(Ctx)),
  ( current_predicate(explanation:why_in_proof_hook/2),
    explanation:why_in_proof_hook(Why0, Why1)
  -> Why = Why1
  ;  Why = Why0
  ).

explainer:proof_lookup(ProofAVL, Lit, rule(Lit), dep(Count, Body), Ctx) :-
  get_assoc(rule(Lit), ProofAVL, dep(Count, Body)?Ctx),
  !.
explainer:proof_lookup(ProofAVL, Lit, assumed(rule(Lit)), dep(Count, Body), Ctx) :-
  get_assoc(assumed(rule(Lit)), ProofAVL, dep(Count, Body)?Ctx),
  !.
explainer:proof_lookup(ProofAVL, Lit, rule(assumed(Lit)), dep(Count, Body), Ctx) :-
  get_assoc(rule(assumed(Lit)), ProofAVL, dep(Count, Body)?Ctx),
  !.


% -----------------------------------------------------------------------------
%  "Why is X in plan?" (generic)
% -----------------------------------------------------------------------------

%! why_in_plan(+Plan, +ProofAVL, +TriggersAVL, +Target, -Why) is semidet.
%
% Generic explanation for why Target appears in the plan:
% - where it appears (step + element)
% - a reverse-dependency path (via TriggersAVL) to some root (if provided)
%
% This predicate is domain-agnostic. A domain module may optionally provide
% `explanation:why_in_plan_hook/2` to enrich the returned Why term.
why_in_plan(Plan, ProofAVL, TriggersAVL, Target, Why) :-
  why_in_plan([], Plan, ProofAVL, TriggersAVL, Target, Why).

%! why_in_plan(+Proposal, +Plan, +ProofAVL, +TriggersAVL, +Target, -Why) is semidet.
%
% Proposal is a list of target literals (same shape as passed to prover:prove/9).
why_in_plan(Proposal, Plan, _ProofAVL, TriggersAVL, Target0, Why) :-
  prover:canon_literal(Target0, Target, _),
  ( explainer:plan_loc(Plan, Target, Step, Elem0) -> true
  ; fail
  ),
  prover:canon_literal(Elem0, Elem, _),
  maplist(explainer:canon_only, Proposal, ProposalKeys0),
  sort(ProposalKeys0, ProposalKeys),
  ( memberchk(Target, ProposalKeys) ->
      Why0 = why_in_plan(Target,
                        location(step(Step), Elem),
                        requested)
  ; explainer:path_to_any_root(Target, ProposalKeys, TriggersAVL, Path) ->
      Why0 = why_in_plan(Target,
                        location(step(Step), Elem),
                        required_by(path(Path)))
  ; explainer:any_dependent(Target, TriggersAVL, Dep0) ->
      prover:canon_literal(Dep0, Dep, _),
      Why0 = why_in_plan(Target,
                        location(step(Step), Elem),
                        has_dependents([Dep]))
  ; Why0 = why_in_plan(Target,
                       location(step(Step), Elem),
                       unknown)
  ),
  ( current_predicate(explanation:why_in_plan_hook/2),
    explanation:why_in_plan_hook(Why0, Why1)
  -> Why = Why1
  ;  Why = Why0
  ).

explainer:canon_only(X0, X) :-
  ( prover:canon_literal(X0, X, _) -> true ; X = X0 ).

% Find location of a target in the plan (first match).
explainer:plan_loc([Wave|_], Target, 1, Elem) :-
  explainer:wave_elem(Wave, Target, Elem),
  !.
explainer:plan_loc([_|Rest], Target, Step, Elem) :-
  explainer:plan_loc(Rest, Target, Step0, Elem),
  Step is Step0 + 1.

explainer:wave_elem([E|_], Target, E) :-
  prover:canon_literal(E, Key, _),
  Key == Target,
  !.
explainer:wave_elem([_|Es], Target, E) :-
  explainer:wave_elem(Es, Target, E).

% Grab any dependent from triggers (reverse graph): prerequisite -> [dependents].
explainer:any_dependent(Target, TriggersAVL, Dep) :-
  ( get_assoc(Target, TriggersAVL, Dependents) -> true ; Dependents = [] ),
  member(Dep, Dependents),
  !.

% Find a reverse-dependency path Target -> ... -> Root via triggers, where Root is
% a proposal key. This returns a list [Target, ..., Root].
explainer:path_to_any_root(Target, Roots, TriggersAVL, Path) :-
  explainer:bfs_paths([[Target]], Roots, TriggersAVL, [], RevPath),
  reverse(RevPath, Path).

explainer:bfs_paths([[Node|RestPath]|_], Roots, _TriggersAVL, _Seen, [Node|RestPath]) :-
  memberchk(Node, Roots),
  !.
explainer:bfs_paths([[Node|RestPath]|Queue], Roots, TriggersAVL, Seen, Found) :-
  ( memberchk(Node, Seen) ->
      explainer:bfs_paths(Queue, Roots, TriggersAVL, Seen, Found)
  ; ( get_assoc(Node, TriggersAVL, Next0) -> true ; Next0 = [] ),
    findall([Next,Node|RestPath],
            ( member(NextLit, Next0),
              explainer:canon_only(NextLit, Next)
            ),
            NewPaths),
    append(Queue, NewPaths, Queue2),
    explainer:bfs_paths(Queue2, Roots, TriggersAVL, [Node|Seen], Found)
  ).


% -----------------------------------------------------------------------------
%  "Why is this an assumption?" (generic)
% -----------------------------------------------------------------------------

%! why_assumption(+ModelAVL, +ProofAVL, +Key, -Why) is semidet.
%
% Key is typically a model key `assumed(X)` or a proof key `rule(assumed(X))` /
% `assumed(rule(X))`. This predicate returns a normalized description, plus any
% reason tag found in the term context.
why_assumption(ModelAVL, ProofAVL, Key0, Why) :-
  why_assumption(ModelAVL, ProofAVL, Key0, _AssumptionType, Why).

%! why_assumption(+ModelAVL, +ProofAVL, +Key, -AssumptionType, -Why) is semidet.
%
% AssumptionType is one of: domain, cycle_break, model_only.
why_assumption(ModelAVL, ProofAVL, Key0, AssumptionType, Why) :-
  explainer:normalize_assumption_key(Key0, Key, AssumptionTerm0),
  ( explainer:assumption_from_proof(ProofAVL, Key, AssumptionType0, AssumptionTerm1) ->
      AssumptionType = AssumptionType0,
      AssumptionTerm = AssumptionTerm1
  ; explainer:assumption_from_model(ModelAVL, Key, AssumptionTerm0) ->
      AssumptionType = model_only,
      AssumptionTerm = AssumptionTerm0
  ; fail
  ),
  explainer:term_ctx(AssumptionTerm, Ctx),
  ( memberchk(assumption_reason(Reason), Ctx) -> true ; Reason = none ),
  Why0 = why_assumption(Key,
                        type(AssumptionType),
                        term(AssumptionTerm),
                        reason(Reason)),
  ( current_predicate(explanation:why_assumption_hook/2),
    explanation:why_assumption_hook(Why0, Why1)
  -> Why = Why1
  ;  Why = Why0
  ).

explainer:normalize_assumption_key(assumed(X0), assumed(X), X) :-
  prover:canon_literal(X0, X, _),
  !.
explainer:normalize_assumption_key(rule(assumed(X0)), rule(assumed(X)), X) :-
  prover:canon_literal(X0, X, _),
  !.
explainer:normalize_assumption_key(assumed(rule(X0)), assumed(rule(X)), X) :-
  prover:canon_literal(X0, X, _),
  !.
explainer:normalize_assumption_key(Key, Key, Key).

explainer:assumption_from_proof(ProofAVL, assumed(X), domain, X) :-
  % Domain assumptions appear as a rule proving assumed(X).
  prover:canon_literal(X, Core, _),
  get_assoc(rule(assumed(Core)), ProofAVL, _),
  !.
explainer:assumption_from_proof(ProofAVL, assumed(X), cycle_break, X) :-
  % Prover cycle-breaks appear as assumed(rule(X)).
  prover:canon_literal(X, Core, _),
  get_assoc(assumed(rule(Core)), ProofAVL, _),
  !.
explainer:assumption_from_proof(_ProofAVL, rule(assumed(X)), domain, X) :- !.
explainer:assumption_from_proof(_ProofAVL, assumed(rule(X)), cycle_break, X) :- !.

explainer:assumption_from_model(ModelAVL, assumed(X), X) :-
  prover:canon_literal(X, Core, _),
  get_assoc(assumed(Core), ModelAVL, _),
  !.

