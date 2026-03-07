/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> TARGET
Action-level implementation helpers for update and downgrade transactions.

This module provides the shared implementation for transactional version
changes (update and downgrade).  Both actions follow the same pattern:

  1. Compute the required_use model and build_with_use state for the new
     version.
  2. Compute and memoize the grouped dependency model.
  3. Optionally generate deep-update goals (when `--deep` is active).
  4. Assemble proof conditions: USE constraints, slot constraint, download
     goal (unless virtual/acct-*), and the dependency closure.

The rule/2 clauses for `:update` and `:downgrade` in rules.pl delegate
here via `target:update_txn_conditions/3`.

== Deep updates ==

When `preference:flag(deep)` is set, `deep_update_goals/3` scans the
dependency model for installed packages that have a newer version
available in the same slot, and schedules transactional update goals
for them.

== Dependency CN extraction ==

`dep_cn/3` extracts the category/name pair from various dependency
literal formats.  It is used by deep_update_goals/3 and by the printer
module for PDEPEND goal filtering.
*/

:- module(target, []).


% =============================================================================
%  Target candidate resolution (CN vs CNV)
% =============================================================================

%! target:is_cn_target(+Q) is semidet.
%
% True when Q is a category/name-only target (no version constraint).

target:is_cn_target(qualified_target(none, _, _, _, version_none, _)).
target:is_cn_target(qualified_target(none, _, _, _, [[],'','','',''], _)).


%! target:resolve_candidate(+Q, -Repository://Ebuild) is nondet.
%
% For CN targets: generates visible candidates first (not masked, keyword-
% accepted, not license-masked), then falls back to all candidates.  This
% ensures the prover picks a visible version before resorting to relaxation.
%
% For CNV targets: generates candidates in standard version-descending order
% without visibility bias, since the user explicitly requested a specific
% version and relaxation is the expected path if it's not visible.

target:resolve_candidate(Q, Repository://Ebuild) :-
  ( target:is_cn_target(Q) ->
      ( kb:query(Q, Repository://Ebuild),
        rules:entry_has_accepted_keyword(Repository://Ebuild),
        \+ query:search(masked(true), Repository://Ebuild),
        \+ candidate:license_masked(Repository://Ebuild)
      ; kb:query(Q, Repository://Ebuild)
      )
  ; kb:query(Q, Repository://Ebuild)
  ).


% =============================================================================
%  Transactional update prerequisites
% =============================================================================

%! target:update_txn_conditions(+RepoEntry, +Context, -Conditions)
%
% Computes the proof conditions for a transactional update or downgrade.
% Context must contain `replaces(OldRepo://OldEntry)`.
%
% Steps: 1) resolve required_use model + build_with_use state; 2) compute
% grouped dependency model (memoized); 3) inject self-references into
% dependency contexts; 4) optionally generate deep-update goals; 5) assemble
% conditions (USE + slot + download + deps). For virtual/acct-group/acct-user
% packages the download goal is omitted.

update_txn_conditions(Repository://Ebuild, Context, Conditions) :-
  use:context_build_with_use_state(Context, B),
  (memberchk(required_use:R,Context) -> true ; R = []),
  query:search(model(Model,required_use(R),build_with_use(B)),Repository://Ebuild),

  query:memoized_search(model(dependency(MergedDeps0,install)):config?{Model},Repository://Ebuild),
  dependency:add_self_to_dep_contexts(Repository://Ebuild, MergedDeps0, MergedDeps),

  ( preference:flag(deep)
  -> deep_update_goals(Repository://Ebuild, MergedDeps, DeepUpdates)
  ;  DeepUpdates = []
  ),

  query:search([category(CNew),name(NNew),select(slot,constraint([]),SAll)], Repository://Ebuild),
  ( memberchk(CNew,['virtual','acct-group','acct-user'])
    -> Base0 = [ constraint(use(Repository://Ebuild):{R}),
                 constraint(slot(CNew,NNew,SAll):{Ebuild})
                 |DeepUpdates],
       append(Base0, MergedDeps, Conditions)
    ;  Base0 = [ constraint(use(Repository://Ebuild):{R}),
                 constraint(slot(CNew,NNew,SAll):{Ebuild}),
                 Repository://Ebuild:download?{[required_use:R,build_with_use:B]}
                 |DeepUpdates],
       append(Base0, MergedDeps, Conditions)
  ).


% =============================================================================
%  Deep-update goal generation
% =============================================================================

%! target:deep_update_goals(+Self, +MergedDeps, -DeepUpdates)
%
% When `--deep` is active, scans MergedDeps for dependency packages that are
% currently installed and have a newer version available in the same slot.
% For each such package, generates a transactional update goal annotated with
% `replaces(OldRepo://OldEntry)`. Only packages from the VDB (`pkg`) are
% considered. The parent entry (Self) is excluded to prevent self-update loops.

deep_update_goals(Self, MergedDeps, DeepUpdates) :-
  ( preference:accept_keywords(K)
    -> KeywordQ = [keywords(K)]
    ;  KeywordQ = []
  ),
  findall(C-N, (member(Dep, MergedDeps), dep_cn(Dep, C, N)), CN0),
  sort(CN0, CN),
  findall(NewRepo://NewEntry:update?{[replaces(OldRepo://OldEntry)]},
          ( member(C-N, CN),
            query:search([name(N),category(C),installed(true)], pkg://OldEntry),
            OldRepo = pkg,
            pkg://OldEntry \== Self,
            query:search(version(OldVer), pkg://OldEntry),
            query:search(slot(Slot0), pkg://OldEntry),
            candidate:canon_slot(Slot0, Slot),
            ( KeywordQ == []
              -> query:search(latest([select(repository,notequal,pkg),
                                      category(C),name(N),slot(Slot),
                                      select(version,greater,OldVer)]),
                              NewRepo://NewEntry)
              ;  query:search(latest([select(repository,notequal,pkg),
                                      category(C),name(N),slot(Slot),keywords(K),
                                      select(version,greater,OldVer)]),
                              NewRepo://NewEntry)
            )
          ),
          Updates0),
  sort(Updates0, DeepUpdates).


% =============================================================================
%  Dependency CN extraction
% =============================================================================

%! target:dep_cn(+DepLiteral, -C, -N)
%
% Extracts the category (C) and name (N) from a dependency literal. Handles
% grouped_package_dependency/4, grouped_package_dependency/3, and concrete
% Repo://Entry:Action literals.

dep_cn(grouped_package_dependency(_,C,N,_):_Action?{_Ctx}, C, N) :- !.
dep_cn(grouped_package_dependency(C,N,_):_Action?{_Ctx}, C, N) :- !.
dep_cn(Repo://Entry:_Action?{_Ctx}, C, N) :-
  query:search([category(C),name(N)], Repo://Entry),
  !.
dep_cn(Repo://Entry:_Action, C, N) :-
  query:search([category(C),name(N)], Repo://Entry),
  !.