/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> EXPLANATION (domain)
Domain-specific explanation logic for portage-ng.

This module contains interpretation logic that depends on Gentoo/Portage domain
concepts (ACCEPT_KEYWORDS, masking, slot/version constraints, etc.).

The generic "why" / introspection layer belongs in `explainer.pl`. This file is
meant to answer questions like: "why did dependency resolution fail for this
package dependency?" in domain terms.
*/

:- module(explanation, [
  assumption_reason_for_grouped_dep/6,
  why_in_plan_hook/2,
  why_in_proof_hook/2,
  why_assumption_hook/2
]).

:- use_module(library(ordsets)).  % ord_intersection/3 (avoid autoload reliance)

/** <hook> why_in_plan_hook/2
Optional domain-level enrichment for explainer:why_in_plan/6.

Given a generic `why_in_plan/3` term, return an enriched form.
Currently this is intentionally minimal; it exists as an architectural hook.
*/
:- multifile why_in_plan_hook/2.

% Default: pass through (no domain enrichment yet).
why_in_plan_hook(Why, Why).

/** <hook> why_in_proof_hook/2
Optional domain-level enrichment for explainer:why_in_proof/4.
*/
:- multifile why_in_proof_hook/2.

why_in_proof_hook(why_in_proof(Target, proof_key(ProofKey), depcount(DepCount), body(Body), ctx(Ctx)),
                  why_in_proof(Target, proof_key(ProofKey), depcount(DepCount), body(Body), ctx(Ctx), domain_reasons(Reasons))) :-
  ( explanation:context_domain_reasons(Ctx, Reasons)
  ; explanation:target_ctx(Target, TargetCtx),
    explanation:context_domain_reasons(TargetCtx, Reasons)
  ),
  Reasons \== [],
  !.

why_in_proof_hook(Why, Why).

/** <hook> why_assumption_hook/2
Optional domain-level enrichment for explainer:why_assumption/5.
*/
:- multifile why_assumption_hook/2.

why_assumption_hook(why_assumption(Key, type(AssType), term(Term), reason(Reason)),
                    why_assumption(Key, type(AssType), term(Term), reason(Reason), domain_reasons(Reasons))) :-
  explainer:term_ctx(Term, Ctx),
  explanation:context_domain_reasons(Ctx, Reasons),
  Reasons \== [],
  !.

why_assumption_hook(Why, Why).

explanation:context_domain_reasons(Ctx, Reasons) :-
  is_list(Ctx),
  findall(Tag,
          ( member(domain_reason(cn_domain(_C, _N, Tags)), Ctx),
            member(Tag, Tags)
          ),
          Tags0),
  sort(Tags0, Reasons),
  !.
explanation:context_domain_reasons(_Ctx, []).

explanation:target_ctx(assumed(Inner), Ctx) :-
  !,
  explainer:term_ctx(Inner, Ctx).
explanation:target_ctx(domain(Inner), Ctx) :-
  !,
  explainer:term_ctx(Inner, Ctx).
explanation:target_ctx(cycle_break(Inner), Ctx) :-
  !,
  explainer:term_ctx(Inner, Ctx).
explanation:target_ctx(Target, Ctx) :-
  explainer:term_ctx(Target, Ctx).


% -----------------------------------------------------------------------------
%  Assumption diagnosis (used on "no candidate found" fallback)
% -----------------------------------------------------------------------------

% Map a failed grouped dependency resolution to a coarse reason:
% - missing               : no such package exists in the repository set
% - masked                : candidates exist but are all masked
% - keyword_filtered      : candidates exist but none match ACCEPT_KEYWORDS / unkeyworded
% - installed_required    : candidates exist, but only installed candidates are allowed (self-hosting) and none match
% - slot_unsatisfied      : candidates exist, but slot restriction filters them all out
% - version_no_candidate  : candidates exist, but at least one version constraint has zero matches
% - version_conflict      : version constraints have matches individually, but their conjunction is empty
% - unsatisfied_constraints: candidates exist, but other constraints make it unsatisfiable (fallback)
%
% NOTE: keep this inexpensive; it's only evaluated on the fallback path.
assumption_reason_for_grouped_dep(Action, C, N, PackageDeps, Context, Reason) :-
  % If any candidate exists at all, it is not "missing".
  findall(Repo://Entry,
          query:search([category(C), name(N)], Repo://Entry),
          Any0),
  ( Any0 == [] ->
      Reason = missing
  ; % Respect self-hosting restriction used in the main resolver:
    self_hosting_requires_installed(Action, C, N, Context, RequireInstalled),
    ( RequireInstalled == true ->
        include(is_installed_candidate, Any0, Any1)
    ; Any1 = Any0
    ),
    ( Any1 == [] ->
        % Only self-hosting installed candidates are allowed; none exist.
        Reason = installed_required
    ; include(is_unmasked_candidate, Any1, Unmasked1),
      ( Unmasked1 == [] ->
          Reason = masked
      ; % Slot restriction filter
        ( memberchk(slot(C,N,Ss):{_}, Context) -> true ; Ss = _ ),
        rules:merge_slot_restriction(Action, C, N, PackageDeps, SlotReq),
        ( RequireInstalled == true ->
            findall(Repo2://Entry2,
                    query:search([category(C), name(N), installed(true), select(slot,constraint(SlotReq),Ss)], Repo2://Entry2),
                    SlotCands0)
        ; findall(Repo2://Entry2,
                  query:search([category(C), name(N), select(slot,constraint(SlotReq),Ss)], Repo2://Entry2),
                  SlotCands0)
        ),
        sort(SlotCands0, SlotCands),
        ( SlotCands == [] ->
            Reason = slot_unsatisfied
        ;
        include(is_unmasked_candidate, SlotCands, SlotUnmasked),
        ( SlotUnmasked == [] ->
            Reason = masked
        ; % First check whether any candidate satisfies slot+version constraints (ignoring keywords).
          version_constraint_analysis(Action, C, N, PackageDeps, SlotUnmasked, VersionOkAll, VersionReason),
          ( VersionOkAll == [] ->
              Reason = VersionReason
          ; % Now check whether any of those candidates pass ACCEPT_KEYWORDS.
            any_candidate_matches_keywords(VersionOkAll, KeywordOk),
            ( KeywordOk == [] ->
                Reason = keyword_filtered
            ; % The main resolver still failed; classify conservatively.
              Reason = unsatisfied_constraints
            )
          )
        )
        )
      )
    )
  ).


% -----------------------------------------------------------------------------
%  Helpers (kept private)
% -----------------------------------------------------------------------------

self_hosting_requires_installed(Action, C, N, Context, true) :-
  Action \== run,
  memberchk(self(SelfRepo://SelfEntry), Context),
  cache:ordered_entry(SelfRepo, SelfEntry, C, N, _),
  \+ preference:flag(emptytree),
  !.
self_hosting_requires_installed(_Action, _C, _N, _Context, false).

is_installed_candidate(Repo://Entry) :-
  cache:entry_metadata(Repo, Entry, installed, true).

is_unmasked_candidate(Repo://Entry) :-
  \+ preference:masked(Repo://Entry).

any_candidate_matches_keywords(Candidates, KeywordOk) :-
  findall(K, preference:accept_keywords(K), Ks0),
  sort(Ks0, Ks),
  findall(Cand,
          ( member(Cand, Candidates),
            member(K, Ks),
            Cand = Repo://Entry,
            query:search(keyword(K), Repo://Entry),
            !
          ),
          KeywordOk0),
  sort(KeywordOk0, KeywordOk).

any_candidate_matches_versions(Action, C, N, PackageDeps, Candidates, VersionOk) :-
  findall(Cand,
          ( member(Cand, Candidates),
            forall(member(package_dependency(Action,no,C,N,O,V,_,_), PackageDeps),
                   ( Cand = Repo://Entry,
                     query:search(select(version,O,V), Repo://Entry)
                   ))
          ),
          VersionOk0),
  sort(VersionOk0, VersionOk).

% Analyze version constraints to distinguish "no candidate satisfies constraint" vs "constraints conflict".
version_constraint_analysis(Action, C, N, PackageDeps, Candidates, VersionOk, VersionReason) :-
  findall(O-V,
          member(package_dependency(Action,no,C,N,O,V,_,_), PackageDeps),
          OV0),
  sort(OV0, OVs),
  ( OVs == [] ->
      VersionOk = Candidates,
      VersionReason = version_conflict
  ; findall((O-V)-Matches,
            ( member(O-V, OVs),
              findall(Cand,
                      ( member(Cand, Candidates),
                        Cand = Repo://Entry,
                        query:search(select(version,O,V), Repo://Entry)
                      ),
                      Matches0),
              sort(Matches0, Matches)
            ),
            MatchesByConstraint),
    ( member((OV)-[], MatchesByConstraint) ->
        OV = (O-V),
        VersionOk = [],
        VersionReason = version_no_candidate(O, V)
    ; findall(Ms, member(_-Ms, MatchesByConstraint), MatchesPerConstraint),
      intersection_all(MatchesPerConstraint, VersionOk0),
      sort(VersionOk0, VersionOk),
      ( VersionOk == [] -> VersionReason = version_conflict ; VersionReason = version_conflict )
    )
  ).

intersection_all([First|Rest], Intersection) :-
  foldl(intersection_sorted, Rest, First, Intersection).

intersection_sorted(A, B, Out) :-
  ord_intersection(A, B, Out).
