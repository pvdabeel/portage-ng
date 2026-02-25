/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> EXPLANATION
Domain-specific explanation logic for portage-ng.

This module provides Gentoo/Portage interpretation on top of the generic
introspection layer in `explainer.pl`. It implements hook enrichment
(`why_in_plan_hook/2`, `why_in_proof_hook/2`, `why_assumption_hook/2`) and
assumption diagnosis (`assumption_reason_for_grouped_dep/6`).

See `Documentation/explainer.txt` for architecture, usage examples, and the
full list of assumption reason values.
*/

:- module(explanation, []).


% =============================================================================
%  EXPLANATION declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Hook: why_in_plan_hook/2
% -----------------------------------------------------------------------------

%! explanation:why_in_plan_hook(+Why0, -Why) is det.
%
% Domain-level enrichment for explainer:why_in_plan/6. Given a generic
% `why_in_plan/3` term, returns an enriched form. Currently a pass-through;
% exists as an architectural hook for future domain-specific annotations.

:- multifile why_in_plan_hook/2.

why_in_plan_hook(Why, Why).


% -----------------------------------------------------------------------------
%  Hook: why_in_proof_hook/2
% -----------------------------------------------------------------------------

%! explanation:why_in_proof_hook(+Why0, -Why) is det.
%
% Domain-level enrichment for explainer:why_in_proof/4. Extracts
% domain_reason tags from the proof context or from the target's own
% context, and appends them as `domain_reasons(Reasons)` to the Why term.
% Falls through to identity when no domain reasons are found.

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


% -----------------------------------------------------------------------------
%  Hook: why_assumption_hook/2
% -----------------------------------------------------------------------------

%! explanation:why_assumption_hook(+Why0, -Why) is det.
%
% Domain-level enrichment for explainer:why_assumption/5. Extracts
% domain_reason tags from the assumption term's context and appends them
% as `domain_reasons(Reasons)`. Falls through to identity when no domain
% reasons are found.

:- multifile why_assumption_hook/2.

why_assumption_hook(why_assumption(Key, type(AssType), term(Term), reason(Reason)),
                    why_assumption(Key, type(AssType), term(Term), reason(Reason), domain_reasons(Reasons))) :-
  explainer:term_ctx(Term, Ctx),
  explanation:context_domain_reasons(Ctx, Reasons),
  Reasons \== [],
  !.

why_assumption_hook(Why, Why).


% -----------------------------------------------------------------------------
%  Domain reason extraction
% -----------------------------------------------------------------------------

%! explanation:context_domain_reasons(+Ctx, -Reasons) is det.
%
% Extract and sort all domain_reason tags from a context list. Each context
% element of the form `domain_reason(cn_domain(_C, _N, Tags))` contributes
% its Tags to the result. Returns [] when Ctx is not a list or contains no
% domain_reason tags.

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


%! explanation:target_ctx(+Target, -Ctx) is det.
%
% Extract context from a target term, unwrapping assumed/domain/cycle_break
% wrappers before delegating to explainer:term_ctx/2.

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
%  Assumption diagnosis
% -----------------------------------------------------------------------------

%! explanation:assumption_reason_for_grouped_dep(+Action, +C, +N, +PackageDeps, +Context, -Reason) is det.
%
% Classify why a grouped dependency resolution failed. Called on the fallback
% path when no candidate satisfies all constraints. The diagnosis filters
% candidates through progressively stricter checks:
%
%   1. Existence: does any package with category C, name N exist?
%   2. Self-hosting: if the action requires an installed candidate (non-run
%      action for a self-referencing package), filter to installed only.
%   3. Masking: filter out masked candidates.
%   4. Slot restriction: apply slot constraints from the dependency context.
%   5. Version constraints: check each version constraint individually, then
%      test whether their intersection is non-empty.
%   6. Keywords: check ACCEPT_KEYWORDS compatibility.
%
% Possible Reason values:
%
%   - `missing`               : no package C/N exists in any repository
%   - `installed_required`    : self-hosting requires installed, none found
%   - `masked`                : all candidates are masked
%   - `slot_unsatisfied`      : slot restriction filters out all candidates
%   - `version_no_candidate(O,V)` : at least one version constraint has zero matches
%   - `version_conflict`      : version constraints conflict (individually satisfiable,
%                               but their conjunction is empty)
%   - `keyword_filtered`      : candidates exist but none match ACCEPT_KEYWORDS
%   - `unsatisfied_constraints`: fallback when no specific reason can be isolated

assumption_reason_for_grouped_dep(Action, C, N, PackageDeps, Context, Reason) :-
  findall(Repo://Entry,
          query:search([category(C), name(N)], Repo://Entry),
          Any0),
  ( Any0 == [] ->
      Reason = missing
  ; self_hosting_requires_installed(Action, C, N, Context, RequireInstalled),
    ( RequireInstalled == true ->
        include(is_installed_candidate, Any0, Any1)
    ; Any1 = Any0
    ),
    ( Any1 == [] ->
        Reason = installed_required
    ; include(is_unmasked_candidate, Any1, Unmasked1),
      ( Unmasked1 == [] ->
          Reason = masked
      ; ( memberchk(slot(C,N,Ss):{_}, Context) -> true ; Ss = _ ),
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
        ; version_constraint_analysis(Action, C, N, PackageDeps, SlotUnmasked, VersionOkAll, VersionReason),
          ( VersionOkAll == [] ->
              Reason = VersionReason
          ; any_candidate_matches_keywords(VersionOkAll, KeywordOk),
            ( KeywordOk == [] ->
                Reason = keyword_filtered
            ; Reason = unsatisfied_constraints
            )
          )
        )
        )
      )
    )
  ).


% -----------------------------------------------------------------------------
%  Helpers (private)
% -----------------------------------------------------------------------------

%! explanation:self_hosting_requires_installed(+Action, +C, +N, +Context, -Required) is det.
%
% Determine whether the resolver must restrict candidates to already-installed
% packages. This applies when the action is not :run, the dependency is
% self-referencing (the package depends on itself), and --emptytree is not set.

self_hosting_requires_installed(Action, C, N, Context, true) :-
  Action \== run,
  memberchk(self(SelfRepo://SelfEntry), Context),
  cache:ordered_entry(SelfRepo, SelfEntry, C, N, _),
  \+ preference:flag(emptytree),
  !.
self_hosting_requires_installed(_Action, _C, _N, _Context, false).


%! explanation:is_installed_candidate(+Repo://Entry) is semidet.
%
% True if the candidate has `installed` metadata set to `true`.

is_installed_candidate(Repo://Entry) :-
  cache:entry_metadata(Repo, Entry, installed, true).


%! explanation:is_unmasked_candidate(+Repo://Entry) is semidet.
%
% True if the candidate is not in the current mask set.

is_unmasked_candidate(Repo://Entry) :-
  \+ preference:masked(Repo://Entry).


%! explanation:any_candidate_matches_keywords(+Candidates, -KeywordOk) is det.
%
% Filter Candidates to those matching at least one accepted keyword from
% `preference:accept_keywords/1`. Returns a sorted list.

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


%! explanation:any_candidate_matches_versions(+Action, +C, +N, +PackageDeps, +Candidates, -VersionOk) is det.
%
% Filter Candidates to those satisfying all version constraints from
% PackageDeps. A candidate must pass every version operator/value pair.

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


%! explanation:version_constraint_analysis(+Action, +C, +N, +PackageDeps, +Candidates, -VersionOk, -Reason) is det.
%
% Analyze version constraints to distinguish between:
%
%   - `version_no_candidate(O, V)`: at least one constraint has zero matching
%     candidates (reports the first such constraint)
%   - `version_conflict`: each constraint individually has matches, but their
%     intersection is empty

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


%! explanation:intersection_all(+ListOfSortedLists, -Intersection) is det.
%
% Compute the intersection of a non-empty list of sorted lists using
% ord_intersection/3.

intersection_all([First|Rest], Intersection) :-
  foldl(intersection_sorted, Rest, First, Intersection).


%! explanation:intersection_sorted(+A, +B, -Out) is det.
%
% Wrapper around ord_intersection/3 for use with foldl/4.

intersection_sorted(A, B, Out) :-
  ord_intersection(A, B, Out).
