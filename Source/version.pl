/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> VERSION DOMAIN
Domain-agnostic representation and meet operations for per-(C,N) version/slot
constraints.

The domain remains symbolic (slot restrictions + comparator constraints). It can
be checked against concrete candidates and used to prune/validate selections.
*/

:- module(version_domain, [
  domain_from_packagedeps/5,
  domain_normalize/2,
  domain_meet/3,
  domain_inconsistent/1,
  domain_allows_candidate/2,
  domain_satisfiable/3,
  domain_reason_terms/6
]).

:- use_module(library(ordsets)).
:- use_module(unify). % extension hook target

% -----------------------------------------------------------------------------
%  Optional unify.pl extension hook (generic)
% -----------------------------------------------------------------------------

feature_unification:val_hook(version_domain(S1, B1), version_domain(S2, B2), version_domain(S, B)) :-
  !,
  version_domain:domain_meet(version_domain(S1, B1), version_domain(S2, B2), version_domain(S, B)).
feature_unification:val_hook(none, version_domain(S, B), version_domain(S, B)) :- !.
feature_unification:val_hook(version_domain(S, B), none, version_domain(S, B)) :- !.

% -----------------------------------------------------------------------------
%  Domain construction
% -----------------------------------------------------------------------------

domain_from_packagedeps(_Action, C, N, PackageDeps, Domain) :-
  findall(SlotReq,
          member(package_dependency(_, no, C, N, _Op, _V, SlotReq, _), PackageDeps),
          SlotReqs),
  slot_domain_from_reqs(SlotReqs, SlotDomain),
  findall(bound(OpN, VerN),
          ( member(package_dependency(_, no, C, N, Op0, Ver0, _S, _), PackageDeps),
            normalize_bound_op(Op0, OpN),
            OpN \== none,
            normalize_version_term(Ver0, VerN)
          ),
          Bounds0),
  sort(Bounds0, Bounds),
  ( Bounds == [] ->
      Domain = none
  ; Domain = version_domain(SlotDomain, Bounds)
  ),
  !.

slot_domain_from_reqs([], any) :- !.
slot_domain_from_reqs([Req|Rest], SlotDomain) :-
  slot_req_domain(Req, ReqDomain),
  slot_domain_from_reqs(Rest, RestDomain),
  meet_slot_domains(ReqDomain, RestDomain, SlotDomain),
  !.

slot_req_domain([], any) :- !.
slot_req_domain([slot(S0)|_], slots([S])) :-
  !,
  canon_slot(S0, S).
slot_req_domain([any_same_slot], any) :- !.
slot_req_domain([any_different_slot], any) :- !.
slot_req_domain(_Other, any) :- !.

meet_slot_domains(any, D, D) :- !.
meet_slot_domains(D, any, D) :- !.
meet_slot_domains(slots(S1), slots(S2), slots(S)) :-
  ord_intersection(S1, S2, S),
  !.

% -----------------------------------------------------------------------------
%  Domain normalization + meet
% -----------------------------------------------------------------------------

domain_normalize(none, none) :- !.
domain_normalize(version_domain(S0, B0), version_domain(S, B)) :-
  !,
  normalize_slot_domain(S0, S),
  normalize_bounds(B0, B).
domain_normalize(_Other, none) :-
  !.

normalize_slot_domain(any, any) :- !.
normalize_slot_domain(slots(S0), slots(S)) :-
  !,
  maplist(canon_slot, S0, S1),
  sort(S1, S).
normalize_slot_domain(_Other, any) :-
  !.

normalize_bounds(B0, B) :-
  ( is_list(B0) -> true ; B0 = [] ),
  findall(bound(OpN, VerN),
          ( member(bound(Op0, Ver0), B0),
            normalize_bound_op(Op0, OpN),
            OpN \== none,
            normalize_version_term(Ver0, VerN)
          ),
          Bs0),
  sort(Bs0, B).

domain_meet(D1, D2, DOut) :-
  domain_normalize(D1, N1),
  domain_normalize(D2, N2),
  domain_meet_norm(N1, N2, DOut),
  !.

domain_meet_norm(none, D, D) :- !.
domain_meet_norm(D, none, D) :- !.
domain_meet_norm(version_domain(S1, B1), version_domain(S2, B2), version_domain(S, B)) :-
  meet_slot_domains(S1, S2, S),
  ord_union(B1, B2, B),
  \+ domain_inconsistent(version_domain(S, B)),
  !.

% -----------------------------------------------------------------------------
%  Domain checks
% -----------------------------------------------------------------------------

domain_inconsistent(version_domain(slots([]), _Bounds)) :-
  !.
domain_inconsistent(version_domain(_SlotDomain, Bounds)) :-
  bounds_inconsistent(Bounds),
  !.
domain_inconsistent(_Other) :-
  fail.

bounds_inconsistent(Bounds) :-
  inconsistent_exact_bounds(Bounds),
  !.
bounds_inconsistent(Bounds) :-
  lower_upper_conflict(Bounds),
  !.
bounds_inconsistent(_Bounds) :-
  fail.

inconsistent_exact_bounds(Bounds) :-
  findall(V, member(bound(equal, V), Bounds), Eq0),
  sort(Eq0, Eq),
  Eq = [_A,_B|_],
  !.
inconsistent_exact_bounds(Bounds) :-
  findall(V, member(bound(equal, V), Bounds), Eq0),
  sort(Eq0, [Eq]),
  member(bound(Op, Req), Bounds),
  Op \== equal,
  \+ version_constraint_holds(Eq, bound(Op, Req)),
  !.

lower_upper_conflict(Bounds) :-
  strongest_lower(Bounds, lower(LV, LStrict)),
  strongest_upper(Bounds, upper(UV, UStrict)),
  ( eapi:version_compare(>, LV, UV)
  ; eapi:version_compare(=, LV, UV),
    ( LStrict == true ; UStrict == true )
  ),
  !.

strongest_lower(Bounds, Lower) :-
  findall(lower(V, Strict),
          ( member(bound(Op, V), Bounds),
            lower_op(Op, Strict)
          ),
          Ls),
  Ls \== [],
  strongest_lower_(Ls, Lower),
  !.

strongest_lower_([L], L) :- !.
strongest_lower_([lower(V1,S1), lower(V2,S2)|Rest], Out) :-
  ( eapi:version_compare(>, V1, V2) ->
      Best = lower(V1, S1)
  ; eapi:version_compare(<, V1, V2) ->
      Best = lower(V2, S2)
  ; % equal version: strict wins
    ( S1 == true ; S2 == true ) ->
      Best = lower(V1, true)
  ; Best = lower(V1, false)
  ),
  strongest_lower_([Best|Rest], Out).

strongest_upper(Bounds, Upper) :-
  findall(upper(V, Strict),
          ( member(bound(Op, V), Bounds),
            upper_op(Op, Strict)
          ),
          Us),
  Us \== [],
  strongest_upper_(Us, Upper),
  !.

strongest_upper_([U], U) :- !.
strongest_upper_([upper(V1,S1), upper(V2,S2)|Rest], Out) :-
  ( eapi:version_compare(<, V1, V2) ->
      Best = upper(V1, S1)
  ; eapi:version_compare(>, V1, V2) ->
      Best = upper(V2, S2)
  ; % equal version: strict wins
    ( S1 == true ; S2 == true ) ->
      Best = upper(V1, true)
  ; Best = upper(V1, false)
  ),
  strongest_upper_([Best|Rest], Out).

lower_op(greater, true).
lower_op(greaterequal, false).

upper_op(smaller, true).
upper_op(smallerequal, false).

domain_allows_candidate(none, _RepoEntry) :-
  !.
domain_allows_candidate(version_domain(SlotDomain, Bounds), RepoEntry) :-
  slot_domain_allows_candidate(SlotDomain, RepoEntry),
  bounds_allow_candidate(Bounds, RepoEntry),
  !.

slot_domain_allows_candidate(any, _RepoEntry) :-
  !.
slot_domain_allows_candidate(slots(Slots), Repo://Entry) :-
  candidate_slot(Repo://Entry, Slot),
  memberchk(Slot, Slots),
  !.

candidate_slot(Repo://Entry, Slot) :-
  ( query:search(slot(S0), Repo://Entry) ->
      canon_slot(S0, Slot)
  ; Slot = '0'
  ),
  !.

bounds_allow_candidate([], _RepoEntry) :-
  !.
bounds_allow_candidate([B|Rest], RepoEntry) :-
  candidate_satisfies_bound(RepoEntry, B),
  bounds_allow_candidate(Rest, RepoEntry).

candidate_satisfies_bound(_RepoEntry, bound(none, _Req)) :-
  !.
candidate_satisfies_bound(Repo://Entry, bound(Op, Req)) :-
  query:search(select(version, Op, Req), Repo://Entry),
  !.

domain_satisfiable(_C, _N, none) :-
  !.
domain_satisfiable(C, N, Domain0) :-
  domain_normalize(Domain0, Domain),
  \+ domain_inconsistent(Domain),
  cache:ordered_entry(Repo, Entry, C, N, _Ver),
  \+ preference:masked(Repo://Entry),
  domain_allows_candidate(Domain, Repo://Entry),
  !.

% -----------------------------------------------------------------------------
%  Provenance helpers
% -----------------------------------------------------------------------------

domain_reason_terms(Action, C, N, PackageDeps, Context, Reasons) :-
  ( is_list(Context),
    memberchk(self(Self), Context) ->
      Origin = Self
  ; Origin = unknown
  ),
  findall(introduced_by(Origin, Action, version(OpN, VerN)),
          ( member(package_dependency(_, no, C, N, Op0, Ver0, _SlotReq, _), PackageDeps),
            normalize_bound_op(Op0, OpN),
            OpN \== none,
            normalize_version_term(Ver0, VerN)
          ),
          VersionReasons),
  findall(introduced_by(Origin, Action, slot(SlotReq)),
          ( member(package_dependency(_, no, C, N, _Op, _Ver, SlotReq, _), PackageDeps),
            SlotReq \== []
          ),
          SlotReasons),
  append(VersionReasons, SlotReasons, R0),
  sort(R0, Reasons),
  !.

% -----------------------------------------------------------------------------
%  Utilities
% -----------------------------------------------------------------------------

normalize_bound_op(smallerorequal, smallerequal) :- !.
normalize_bound_op(smallerequal, smallerequal) :- !.
normalize_bound_op(smaller, smaller) :- !.
% Keep domain narrowing conservative:
% - include upper-bounds and exact-equality bounds;
% - still avoid lower-bounds, which were a major source of broad search blowups.
normalize_bound_op(equal, equal) :- !.
normalize_bound_op(_Other, none).

canon_slot(S0, S) :-
  ( atom(S0)   -> S = S0
  ; integer(S0) -> atom_number(S, S0)
  ; number(S0)  -> atom_number(S, S0)
  ; S = S0
  ),
  !.

normalize_version_term(Ver0, Ver) :-
  var(Ver0),
  !,
  Ver = Ver0.
normalize_version_term([_Nums,_A,_S,_Full]=Ver, Ver) :-
  !.
normalize_version_term(Full, [[], '', '', Full]) :-
  atom(Full),
  sub_atom(Full, _, 1, 0, '*'),
  !.
normalize_version_term(Full, [Nums, '', '', Full]) :-
  atom(Full),
  eapi:version2numberlist(Full, Nums),
  Nums \== [],
  !.
normalize_version_term(Num, Ver) :-
  number(Num),
  !,
  number_string(Num, S),
  atom_string(Full, S),
  normalize_version_term(Full, Ver).
normalize_version_term(Other, Other).

version_constraint_holds(_Ver, bound(none, _Req)) :- !.
version_constraint_holds(Ver, bound(equal, Req)) :- !, Ver == Req.
version_constraint_holds(Ver, bound(notequal, Req)) :- !, Ver \== Req.
version_constraint_holds(Ver, bound(smaller, Req)) :- !, eapi:version_compare(<, Ver, Req).
version_constraint_holds(Ver, bound(smallerequal, Req)) :- !,
  ( eapi:version_compare(<, Ver, Req)
  ; eapi:version_compare(=, Ver, Req)
  ).
version_constraint_holds(Ver, bound(greater, Req)) :- !, eapi:version_compare(>, Ver, Req).
version_constraint_holds(Ver, bound(greaterequal, Req)) :- !,
  ( eapi:version_compare(>, Ver, Req)
  ; eapi:version_compare(=, Ver, Req)
  ).
% Keep unknown operators non-blocking for symbolic consistency checks.
version_constraint_holds(_Ver, _Other) :- !.

