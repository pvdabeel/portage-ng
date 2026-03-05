/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> TARGET
Action-level implementation helpers for update/downgrade transactions.

Provides transactional update condition building, deep-update goal
generation, and dependency CN extraction.
*/

:- module(target, []).


% =============================================================================
%  Transactional update prerequisites
% =============================================================================

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

dep_cn(grouped_package_dependency(_,C,N,_):_Action?{_Ctx}, C, N) :- !.
dep_cn(grouped_package_dependency(C,N,_):_Action?{_Ctx}, C, N) :- !.
dep_cn(Repo://Entry:_Action?{_Ctx}, C, N) :-
  query:search([category(C),name(N)], Repo://Entry),
  !.
dep_cn(Repo://Entry:_Action, C, N) :-
  query:search([category(C),name(N)], Repo://Entry),
  !.
