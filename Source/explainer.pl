/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> EXPLAINER
Generic introspection and explanation utilities.

This module is intentionally domain-agnostic. It answers "why" questions by
inspecting existing proof artifacts (ProofAVL, ModelAVL, Plan, TriggersAVL),
without embedding Gentoo/Portage policy.

Three families of queries are supported: `why_in_proof`, `why_in_plan`, and
`why_assumption`. Domain-specific enrichment hooks are provided for each
family; `explanation.pl` implements these with Gentoo/Portage logic.

The `explain/2,3` predicates send structured Why terms to an LLM (configured
via `config:llm_default/1`) for human-readable interpretation.

See `Documentation/explainer.txt` for architecture, usage examples, and a
step-by-step guide.
*/

:- module(explainer, []).


% =============================================================================
%  EXPLAINER declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Proof/model artifact helpers
% -----------------------------------------------------------------------------

%! explainer:assumption_content_from_proof_key(+ProofKey, -Wrapped)
%
% Map a proof key to a normalized wrapper that preserves the assumption
% taxonomy:
%
%   - Domain assumptions:  proof key `rule(assumed(X))`  -> `domain(X)`
%   - Prover cycle-breaks: proof key `assumed(rule(X))` -> `cycle_break(X)`

assumption_content_from_proof_key(rule(assumed(Content)), domain(Content)) :- !.
assumption_content_from_proof_key(assumed(rule(Content)), cycle_break(Content)) :- !.


%! explainer:assumption_normalize(+Content0, -Content)
%
% Normalize an assumption for stable counting and printing. Canonicalizes
% the literal via prover:literal/3, preserving any context tags
% (e.g. assumption_reason/1, self/1).

assumption_normalize(Content0, Content) :-
  ( Content0 = domain(X) ->
      ( X = _?{_} ->
          prover:canon_literal(X, Core, Ctx),
          Content = domain(Core?{Ctx})
      ; prover:canon_literal(X, Core, _Ctx) ->
          Content = domain(Core)
      ; Content = domain(X)
      )
  ; Content0 = cycle_break(X) ->
      ( X = _?{_} ->
          prover:canon_literal(X, Core, Ctx),
          Content = cycle_break(Core?{Ctx})
      ; prover:canon_literal(X, Core, _Ctx) ->
          Content = cycle_break(Core)
      ; Content = cycle_break(X)
      )
  ; ( prover:canon_literal(Content0, Core, _Ctx) -> Content = Core ; Content = Content0 )
  ).


%! explainer:term_ctx(+Term, -Ctx)
%
% Extract context tags from a term carrying `?{Ctx}` decoration.
% Supports both list contexts and the legacy `{}` compound form.
% Returns [] when no context is present.

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
%  "Why is X in proof?"
% -----------------------------------------------------------------------------

%! explainer:why_in_proof(+ProofAVL, +Target, -Why) is semidet.
%
% Simplified entry point; delegates to why_in_proof/4 and discards the
% proof key.

why_in_proof(ProofAVL, Target, Why) :-
  why_in_proof(ProofAVL, Target, _ProofKey, Why).


%! explainer:why_in_proof(+ProofAVL, +Target, -ProofKey, -Why) is semidet.
%
% Look up Target (a canonical literal) in the proof AVL. ProofKey is one of:
%
%   - `rule(Lit)`           : normal proven rule
%   - `assumed(rule(Lit))`  : prover cycle-break
%   - `rule(assumed(Lit))`  : domain assumption
%
% Why is a structured term `why_in_proof(Target, proof_key(...), depcount(...),
% body(...), ctx(...))`. If `explanation:why_in_proof_hook/2` is defined, it
% may enrich this term with domain-specific information.

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


%! explainer:proof_lookup(+ProofAVL, +Lit, -ProofKey, -DepInfo, -Ctx) is semidet.
%
% Try each proof key shape in priority order: normal rule, prover cycle-break,
% then domain assumption.

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
%  "Why is X in plan?"
% -----------------------------------------------------------------------------

%! explainer:why_in_plan(+Plan, +ProofAVL, +TriggersAVL, +Target, -Why) is semidet.
%
% Simplified entry point; delegates to why_in_plan/6 with an empty Proposal.

why_in_plan(Plan, ProofAVL, TriggersAVL, Target, Why) :-
  why_in_plan([], Plan, ProofAVL, TriggersAVL, Target, Why).


%! explainer:why_in_plan(+Proposal, +Plan, +ProofAVL, +TriggersAVL, +Target, -Why) is semidet.
%
% Locate Target in the wave-plan and determine why it is there:
%
%   - `requested`           : Target is one of the proposal literals
%   - `required_by(path(P))`: a reverse-dependency path from Target to a root
%   - `has_dependents([D])` : at least one dependent exists in the trigger graph
%   - `unknown`             : present in plan but no dependency path found
%
% Proposal is a list of target literals (same shape as passed to prover:prove/9).
% If `explanation:why_in_plan_hook/2` is defined, it may enrich the result.

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


%! explainer:canon_only(+X0, -X) is det.
%
% Canonicalize a literal, falling back to the original term if
% prover:literal/3 does not apply.

explainer:canon_only(X0, X) :-
  ( prover:canon_literal(X0, X, _) -> true ; X = X0 ).


% -----------------------------------------------------------------------------
%  Plan location helpers
% -----------------------------------------------------------------------------

%! explainer:plan_loc(+Plan, +Target, -Step, -Elem) is semidet.
%
% Find the first occurrence of Target in the plan. Returns the 1-based
% wave Step number and the matching Elem.

explainer:plan_loc([Wave|_], Target, 1, Elem) :-
  explainer:wave_elem(Wave, Target, Elem),
  !.
explainer:plan_loc([_|Rest], Target, Step, Elem) :-
  explainer:plan_loc(Rest, Target, Step0, Elem),
  Step is Step0 + 1.


%! explainer:wave_elem(+Wave, +Target, -Elem) is semidet.
%
% Find Target within a single wave (list of plan elements).

explainer:wave_elem([E|_], Target, E) :-
  prover:canon_literal(E, Key, _),
  Key == Target,
  !.
explainer:wave_elem([_|Es], Target, E) :-
  explainer:wave_elem(Es, Target, E).


% -----------------------------------------------------------------------------
%  Reverse-dependency path (BFS via TriggersAVL)
% -----------------------------------------------------------------------------

%! explainer:any_dependent(+Target, +TriggersAVL, -Dep) is semidet.
%
% Grab any direct dependent of Target from the reverse-dependency graph.

explainer:any_dependent(Target, TriggersAVL, Dep) :-
  ( get_assoc(Target, TriggersAVL, Dependents) -> true ; Dependents = [] ),
  member(Dep, Dependents),
  !.


%! explainer:path_to_any_root(+Target, +Roots, +TriggersAVL, -Path) is semidet.
%
% BFS through the reverse-dependency graph (TriggersAVL) to find a path
% from Target to any Root in the proposal. Returns [Target, ..., Root].

explainer:path_to_any_root(Target, Roots, TriggersAVL, Path) :-
  explainer:bfs_paths([[Target]], Roots, TriggersAVL, [], RevPath),
  reverse(RevPath, Path).


%! explainer:bfs_paths(+Queue, +Roots, +TriggersAVL, +Seen, -Path) is semidet.
%
% BFS work loop. Each queue element is a partial path (newest node first).
% Succeeds when a queue element's head is a member of Roots.

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
%  "Why is this an assumption?"
% -----------------------------------------------------------------------------

%! explainer:why_assumption(+ModelAVL, +ProofAVL, +Key, -Why) is semidet.
%
% Simplified entry point; delegates to why_assumption/5 and discards the
% assumption type.

why_assumption(ModelAVL, ProofAVL, Key0, Why) :-
  why_assumption(ModelAVL, ProofAVL, Key0, _AssumptionType, Why).


%! explainer:why_assumption(+ModelAVL, +ProofAVL, +Key, -AssumptionType, -Why) is semidet.
%
% Classify an assumption key and build a structured explanation:
%
%   - AssumptionType is one of: `domain`, `cycle_break`, `model_only`
%   - Why is `why_assumption(Key, type(...), term(...), reason(...))`,
%     optionally enriched by `explanation:why_assumption_hook/2`
%
% The reason is extracted from `assumption_reason(R)` tags in the term
% context, or `none` if no such tag exists.

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


% -----------------------------------------------------------------------------
%  Assumption key normalization and lookup
% -----------------------------------------------------------------------------

%! explainer:normalize_assumption_key(+Key0, -Key, -AssumptionTerm) is det.
%
% Canonicalize assumption keys to their standard forms. Handles all three
% key shapes: `assumed(X)`, `rule(assumed(X))`, `assumed(rule(X))`.

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


%! explainer:assumption_from_proof(+ProofAVL, +Key, -Type, -Term) is semidet.
%
% Look up an assumption key in the proof AVL and classify it:
%
%   - `assumed(X)` with `rule(assumed(Core))` in proof -> `domain`
%   - `assumed(X)` with `assumed(rule(Core))` in proof -> `cycle_break`
%   - `rule(assumed(X))` key shape -> `domain` (by construction)
%   - `assumed(rule(X))` key shape -> `cycle_break` (by construction)

explainer:assumption_from_proof(ProofAVL, assumed(X), domain, X) :-
  prover:canon_literal(X, Core, _),
  get_assoc(rule(assumed(Core)), ProofAVL, _),
  !.
explainer:assumption_from_proof(ProofAVL, assumed(X), cycle_break, X) :-
  prover:canon_literal(X, Core, _),
  get_assoc(assumed(rule(Core)), ProofAVL, _),
  !.
explainer:assumption_from_proof(_ProofAVL, rule(assumed(X)), domain, X) :- !.
explainer:assumption_from_proof(_ProofAVL, assumed(rule(X)), cycle_break, X) :- !.


%! explainer:assumption_from_model(+ModelAVL, +Key, -Term) is semidet.
%
% Look up an assumption in the model AVL (fallback when the assumption is
% not found in the proof).

explainer:assumption_from_model(ModelAVL, assumed(X), X) :-
  prover:canon_literal(X, Core, _),
  get_assoc(assumed(Core), ModelAVL, _),
  !.


% -----------------------------------------------------------------------------
%  LLM-powered human-readable explanation
% -----------------------------------------------------------------------------

%! explainer:explain(+Service, +Why, -Response) is det.
%
% Send a structured Why term (from why_in_proof, why_in_plan, or
% why_assumption) to an LLM service for human-readable interpretation.
%
% Service is an atom naming the LLM backend (e.g. `claude`, `grok`,
% `chatgpt`, `gemini`, `ollama`). The Why term is formatted into a
% prompt that includes the structured data and asks for a concise,
% human-readable explanation in Gentoo/Portage domain terms.
%
% Response is the LLM's textual answer.
%
% Example:
%
%   ?- explainer:why_in_proof(ProofAVL, Target, Why),
%      explainer:explain(claude, Why, Response).

explainer:explain(Service, Why, Response) :-
  explainer:format_why_prompt(Why, Prompt),
  explainer:call_llm(Service, Prompt, Response).


%! explainer:explain(+Why, -Response) is det.
%
% Convenience form using the default LLM service from config:llm_default/1.

explainer:explain(Why, Response) :-
  config:llm_default(Service),
  explainer:explain(Service, Why, Response).


%! explainer:format_why_prompt(+Why, -Prompt) is det.
%
% Convert a structured Why term into a natural-language prompt for the LLM.

explainer:format_why_prompt(Why, Prompt) :-
  term_to_atom(Why, WhyAtom),
  atomic_list_concat([
    'You are a Gentoo Linux package management expert. ',
    'Below is structured output from a dependency resolver. ',
    'Please provide a concise, human-readable explanation of what it means ',
    'and what action the user should take (if any). ',
    'Use plain language; avoid Prolog syntax in your answer.\n\n',
    WhyAtom
  ], Prompt).


%! explainer:call_llm(+Service, +Prompt, -Response) is det.
%
% Dispatch a prompt to the named LLM service. The service module must
% provide a Service/2 predicate (e.g. claude/2, grok/2).

explainer:call_llm(Service, Prompt, Response) :-
  Goal =.. [Service, Prompt, Response],
  call(Service:Goal).
