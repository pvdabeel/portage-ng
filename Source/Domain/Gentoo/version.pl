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

:- module(version_domain, []).

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

version_domain:domain_from_packagedeps(_Action, C, N, PackageDeps, Domain) :-
  collect_slots_and_bounds(PackageDeps, C, N, SlotReqs, Bounds0),
  slot_domain_from_reqs(SlotReqs, SlotDomain),
  sort(Bounds0, Bounds),
  ( Bounds == [] ->
      Domain = none
  ; Domain = version_domain(SlotDomain, Bounds)
  ),
  !.


%! collect_slots_and_bounds(+PackageDeps, +C, +N, -SlotReqs, -Bounds)
%
% Single-pass collection of slot requirements and version bounds from
% PackageDeps matching category C and name N (non-blocker only).

version_domain:collect_slots_and_bounds([], _, _, [], []).
version_domain:collect_slots_and_bounds([package_dependency(_, no, C, N, wildcard, Ver0, SlotReq, _)|Rest], C, N, [SlotReq|SRs], Bounds) :-
  !,
  ( wildcard_upper_bound(Ver0, UpperVer) ->
      Bounds = [bound(smaller, UpperVer)|Bounds1]
  ; Bounds = Bounds1
  ),
  collect_slots_and_bounds(Rest, C, N, SRs, Bounds1).
version_domain:collect_slots_and_bounds([package_dependency(_, no, C, N, tilde, Ver0, SlotReq, _)|Rest], C, N, [SlotReq|SRs], Bounds) :-
  !,
  ( tilde_upper_bound(Ver0, UpperVer) ->
      Bounds = [bound(smaller, UpperVer)|Bounds1]
  ; Bounds = Bounds1
  ),
  collect_slots_and_bounds(Rest, C, N, SRs, Bounds1).
version_domain:collect_slots_and_bounds([package_dependency(_, no, C, N, Op0, Ver0, SlotReq, _)|Rest], C, N, [SlotReq|SRs], Bounds) :-
  !,
  ( normalize_bound_op(Op0, OpN),
    OpN \== none,
    normalize_version_term(Ver0, VerN)
  ->
    Bounds = [bound(OpN, VerN)|Bounds1]
  ;
    Bounds = Bounds1
  ),
  collect_slots_and_bounds(Rest, C, N, SRs, Bounds1).
version_domain:collect_slots_and_bounds([_|Rest], C, N, SRs, Bounds) :-
  collect_slots_and_bounds(Rest, C, N, SRs, Bounds).

version_domain:slot_domain_from_reqs([], any) :- !.
version_domain:slot_domain_from_reqs([Req|Rest], SlotDomain) :-
  slot_req_domain(Req, ReqDomain),
  slot_domain_from_reqs(Rest, RestDomain),
  meet_slot_domains(ReqDomain, RestDomain, SlotDomain),
  !.

version_domain:slot_req_domain([], any) :- !.
version_domain:slot_req_domain([slot(S0)|_], slots([S])) :-
  !,
  canon_slot(S0, S).
version_domain:slot_req_domain([any_same_slot], any) :- !.
version_domain:slot_req_domain([any_different_slot], any) :- !.
version_domain:slot_req_domain(_Other, any) :- !.

version_domain:meet_slot_domains(any, D, D) :- !.
version_domain:meet_slot_domains(D, any, D) :- !.
version_domain:meet_slot_domains(slots(S1), slots(S2), slots(S)) :-
  ord_intersection(S1, S2, S),
  !.

% -----------------------------------------------------------------------------
%  Domain normalization + meet
% -----------------------------------------------------------------------------

version_domain:domain_normalize(none, none) :- !.
version_domain:domain_normalize(version_domain(S0, B0), version_domain(S, B)) :-
  !,
  normalize_slot_domain(S0, S),
  normalize_bounds(B0, B).
version_domain:domain_normalize(_Other, none) :-
  !.

version_domain:normalize_slot_domain(any, any) :- !.
version_domain:normalize_slot_domain(slots(S0), slots(S)) :-
  !,
  maplist(canon_slot, S0, S1),
  sort(S1, S).
version_domain:normalize_slot_domain(_Other, any) :-
  !.

version_domain:normalize_bounds(B0, B) :-
  ( is_list(B0) -> true ; B0 = [] ),
  findall(bound(OpN, VerN),
          ( member(bound(Op0, Ver0), B0),
            normalize_bound_op(Op0, OpN),
            OpN \== none,
            normalize_version_term(Ver0, VerN)
          ),
          Bs0),
  sort(Bs0, B).

version_domain:domain_meet(D1, D2, DOut) :-
  domain_normalize(D1, N1),
  domain_normalize(D2, N2),
  domain_meet_norm(N1, N2, DOut),
  !.

version_domain:domain_meet_norm(none, D, D) :- !.
version_domain:domain_meet_norm(D, none, D) :- !.
version_domain:domain_meet_norm(version_domain(S1, B1), version_domain(S2, B2), version_domain(S, B)) :-
  meet_slot_domains(S1, S2, S),
  ord_union(B1, B2, B),
  \+ domain_inconsistent(version_domain(S, B)),
  !.

% -----------------------------------------------------------------------------
%  Domain checks
% -----------------------------------------------------------------------------

version_domain:domain_inconsistent(version_domain(slots([]), _Bounds)) :-
  !.
version_domain:domain_inconsistent(version_domain(_SlotDomain, Bounds)) :-
  bounds_inconsistent(Bounds),
  !.
version_domain:domain_inconsistent(_Other) :-
  fail.

version_domain:bounds_inconsistent(Bounds) :-
  inconsistent_exact_bounds(Bounds),
  !.
version_domain:bounds_inconsistent(Bounds) :-
  lower_upper_conflict(Bounds),
  !.
version_domain:bounds_inconsistent(_Bounds) :-
  fail.

version_domain:inconsistent_exact_bounds(Bounds) :-
  findall(V, member(bound(equal, V), Bounds), Eq0),
  sort(Eq0, Eq),
  Eq = [_A,_B|_],
  !.
version_domain:inconsistent_exact_bounds(Bounds) :-
  findall(V, member(bound(equal, V), Bounds), Eq0),
  sort(Eq0, [Eq]),
  member(bound(Op, Req), Bounds),
  Op \== equal,
  \+ version_constraint_holds(Eq, bound(Op, Req)),
  !.

version_domain:lower_upper_conflict(Bounds) :-
  strongest_lower(Bounds, lower(LV, LStrict)),
  strongest_upper(Bounds, upper(UV, UStrict)),
  ( eapi:version_compare(>, LV, UV)
  ; eapi:version_compare(=, LV, UV),
    ( LStrict == true ; UStrict == true )
  ),
  !.

version_domain:strongest_lower(Bounds, Lower) :-
  findall(lower(V, Strict),
          ( member(bound(Op, V), Bounds),
            lower_op(Op, Strict)
          ),
          Ls),
  Ls \== [],
  strongest_lower_(Ls, Lower),
  !.

version_domain:strongest_lower_([L], L) :- !.
version_domain:strongest_lower_([lower(V1,S1), lower(V2,S2)|Rest], Out) :-
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

version_domain:strongest_upper(Bounds, Upper) :-
  findall(upper(V, Strict),
          ( member(bound(Op, V), Bounds),
            upper_op(Op, Strict)
          ),
          Us),
  Us \== [],
  strongest_upper_(Us, Upper),
  !.

version_domain:strongest_upper_([U], U) :- !.
version_domain:strongest_upper_([upper(V1,S1), upper(V2,S2)|Rest], Out) :-
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

version_domain:lower_op(greater, true).
version_domain:lower_op(greaterequal, false).

version_domain:upper_op(smaller, true).
version_domain:upper_op(smallerequal, false).

version_domain:domain_allows_candidate(none, _RepoEntry) :-
  !.
version_domain:domain_allows_candidate(version_domain(SlotDomain, Bounds), RepoEntry) :-
  slot_domain_allows_candidate(SlotDomain, RepoEntry),
  bounds_allow_candidate(Bounds, RepoEntry),
  !.

version_domain:slot_domain_allows_candidate(any, _RepoEntry) :-
  !.
version_domain:slot_domain_allows_candidate(slots(Slots), Repo://Entry) :-
  candidate_slot(Repo://Entry, Slot),
  memberchk(Slot, Slots),
  !.

version_domain:candidate_slot(Repo://Entry, Slot) :-
  ( query:search(slot(S0), Repo://Entry) ->
      canon_slot(S0, Slot)
  ; Slot = '0'
  ),
  !.

version_domain:bounds_allow_candidate([], _RepoEntry) :-
  !.
version_domain:bounds_allow_candidate([B|Rest], RepoEntry) :-
  candidate_satisfies_bound(RepoEntry, B),
  bounds_allow_candidate(Rest, RepoEntry).

version_domain:candidate_satisfies_bound(_RepoEntry, bound(none, _Req)) :-
  !.
version_domain:candidate_satisfies_bound(Repo://Entry, bound(Op, Req)) :-
  query:search(select(version, Op, Req), Repo://Entry),
  !.

version_domain:domain_satisfiable(_C, _N, none) :-
  !.
version_domain:domain_satisfiable(C, N, Domain0) :-
  domain_normalize(Domain0, Domain),
  \+ domain_inconsistent(Domain),
  cache:ordered_entry(Repo, Entry, C, N, _Ver),
  \+ preference:masked(Repo://Entry),
  domain_allows_candidate(Domain, Repo://Entry),
  !.

% -----------------------------------------------------------------------------
%  Provenance helpers
% -----------------------------------------------------------------------------

version_domain:domain_reason_terms(Action, C, N, PackageDeps, Context, Reasons) :-
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

version_domain:normalize_bound_op(smallerorequal, smallerequal) :- !.
version_domain:normalize_bound_op(smallerequal, smallerequal) :- !.
version_domain:normalize_bound_op(smaller, smaller) :- !.
% Keep domain narrowing conservative:
% - include upper-bounds and exact-equality bounds;
% - still avoid lower-bounds, which were a major source of broad search blowups.
% Wildcard (=pkg-X.Y*) and tilde (~pkg-X.Y.Z) are handled separately in
% collect_slots_and_bounds via wildcard_upper_bound / tilde_upper_bound,
% producing an upper bound (smaller).
version_domain:normalize_bound_op(equal, equal) :- !.
version_domain:normalize_bound_op(wildcard, none) :- !.
version_domain:normalize_bound_op(tilde, none) :- !.
version_domain:normalize_bound_op(_Other, none).


%! version_domain:wildcard_upper_bound(+Ver, -UpperVer) is semidet.
%
% Computes the exclusive upper bound for a wildcard version constraint.
% =pkg-0.6* matches [0.6, 0.7), so the upper bound is 0.7.
% The bound is constructed by incrementing the last component of the
% version number list.

version_domain:wildcard_upper_bound(Ver0, version(UpperNums, '', 4, 0, '', 0, UpperFull)) :-
  normalize_version_term(Ver0, version(Nums, _, _, _, _, _, _)),
  Nums \== [],
  increment_last(Nums, UpperNums),
  atomic_list_concat(UpperNums, '.', UpperFull).


%! version_domain:tilde_upper_bound(+Ver, -UpperVer) is semidet.
%
% Computes the exclusive upper bound for a tilde version constraint.
% ~pkg-8.1.1 matches [8.1.1, 8.1.2) (same base version, any revision),
% so the upper bound is 8.1.2.

version_domain:tilde_upper_bound(Ver0, version(UpperNums, '', 4, 0, '', 0, UpperFull)) :-
  normalize_version_term(Ver0, version(Nums, _, _, _, _, _, _)),
  Nums \== [],
  increment_last(Nums, UpperNums),
  atomic_list_concat(UpperNums, '.', UpperFull).


version_domain:increment_last([X], [X1]) :- !,
  X1 is X + 1.
version_domain:increment_last([H|T], [H|T1]) :-
  increment_last(T, T1).

version_domain:canon_slot(S0, S) :-
  ( atom(S0)   -> S = S0
  ; integer(S0) -> atom_number(S, S0)
  ; number(S0)  -> atom_number(S, S0)
  ; S = S0
  ),
  !.

version_domain:normalize_version_term(V, V) :-
  var(V), !.
version_domain:normalize_version_term(version(A,B,C,D,E,F,G), version(A,B,C,D,E,F,G)) :- !.
version_domain:normalize_version_term(V, R) :-
  normalize_version_term_other(V, R).


version_domain:normalize_version_term_other(version(_,_,_,_,_,_,_)=Ver, Ver) :- !.
version_domain:normalize_version_term_other(Full, version([0], '', 4, 0, '', 0, Full)) :-
  atom(Full),
  sub_atom(Full, _, 1, 0, '*'),
  !.
version_domain:normalize_version_term_other(Full, version(Nums, '', 4, 0, '', 0, Full)) :-
  atom(Full),
  eapi:version2numberlist(Full, Nums),
  Nums \== [],
  !.
version_domain:normalize_version_term_other(Num, Ver) :-
  number(Num),
  !,
  number_string(Num, S),
  atom_string(Full, S),
  normalize_version_term_other(Full, Ver).
version_domain:normalize_version_term_other(Other, Other).

version_domain:version_constraint_holds(_Ver, bound(none, _Req)) :- !.
version_domain:version_constraint_holds(Ver, bound(equal, Req)) :- !, Ver == Req.
version_domain:version_constraint_holds(Ver, bound(notequal, Req)) :- !, Ver \== Req.
version_domain:version_constraint_holds(Ver, bound(smaller, Req)) :- !, eapi:version_compare(<, Ver, Req).
version_domain:version_constraint_holds(Ver, bound(smallerequal, Req)) :- !,
  ( eapi:version_compare(<, Ver, Req)
  ; eapi:version_compare(=, Ver, Req)
  ).
version_domain:version_constraint_holds(Ver, bound(greater, Req)) :- !, eapi:version_compare(>, Ver, Req).
version_domain:version_constraint_holds(Ver, bound(greaterequal, Req)) :- !,
  ( eapi:version_compare(>, Ver, Req)
  ; eapi:version_compare(=, Ver, Req)
  ).
% Keep unknown operators non-blocking for symbolic consistency checks.
version_domain:version_constraint_holds(_Ver, _Other) :- !.