/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> RANKING
Dependency ordering and ranking heuristics for the portage-ng resolver.

Split out of candidate.pl (issue #64). Contains the dependency ordering
heuristic (order_deps_for_proof/3, dep_priority/2 over the declared
tightness_classes/1), bracket-USE memo seeding, equality-USE pin
propagation, choice-group arm ranking (prioritize_deps_keep_all/3 over
the declared choice_criteria/1, criterion_value/5, preference_value/3),
USE_EXPAND profile-match scoring, any_of_group preference helpers, and
provider-reuse candidate reordering.

Every preference in this module is an *ordered declaration* -- a list of
classes or criteria, most significant first -- compared with the
standard order of terms. Nothing is encoded as a weighted sum, a
negated integer, or digits packed into one number.
*/

:- module(ranking, []).

% =============================================================================
%  RANKING declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Dependency ordering heuristic
% -----------------------------------------------------------------------------

%! ranking:order_deps_for_proof(+Action, +Deps, -Ordered)
%
% Sorts dependency groups for deterministic proof search. Tighter
% constraints (fewer candidates, installed packages, blockers) are
% proved first, reducing the backtracking search space. The key is
% dep_priority/2, whose leading component is the dep's position in
% tightness_classes/1.

ranking:order_deps_for_proof(_Action, Deps, Ordered) :-
  maplist(dep_priority_kv, Deps, KVs),
  keysort(KVs, Sorted),
  pairs_values(Sorted, Ordered),
  !.


% -----------------------------------------------------------------------------
%  Bracket USE memo seeding (cross-phase, before dep proof order)
% -----------------------------------------------------------------------------

%! ranking:seed_bwu_memo_from_dep_tree(+Deps) is det
%
% Walk a merged dependency model and union every bracketed USE atom into
% memo:candidate_bwu_/3 before any grouped_dep is proved.  Fixes RDEPEND
% bracket USE (e.g. glib[dbus]) being discovered only after an install-phase
% subtree already scheduled the provider's first :install (issue #7).

ranking:seed_bwu_memo_from_dep_tree(Deps) :-
  is_list(Deps),
  !,
  forall(member(Dep, Deps), ranking:seed_bwu_memo_from_dep(Dep)).
ranking:seed_bwu_memo_from_dep_tree(_).


%! ranking:seed_bwu_memo_from_dep(+Dep) is det
%
% Recurse dependency groups; accumulate bracket USE on package_dependency
% leaves.  Ignores blockers and unknown node shapes.

ranking:seed_bwu_memo_from_dep(grouped_package_dependency(_, _, _, PackageDeps):_) :- !,
  ranking:seed_bwu_memo_from_dep_tree(PackageDeps).
ranking:seed_bwu_memo_from_dep(grouped_package_dependency(_, _, _, PackageDeps)) :- !,
  ranking:seed_bwu_memo_from_dep_tree(PackageDeps).
ranking:seed_bwu_memo_from_dep(grouped_package_dependency(_, _, _, PackageDeps):_Action?{_}) :- !,
  ranking:seed_bwu_memo_from_dep_tree(PackageDeps).
ranking:seed_bwu_memo_from_dep(package_dependency(_, _, C, N, _, _, _, UseReqs)) :-
  UseReqs \== [],
  !,
  ranking:seed_bwu_memo_for_cn(C, N, UseReqs).
ranking:seed_bwu_memo_from_dep(all_of_group(Deps)) :- !,
  ranking:seed_bwu_memo_from_dep_tree(Deps).
ranking:seed_bwu_memo_from_dep(any_of_group(Deps)) :- !,
  ranking:seed_bwu_memo_from_dep_tree(Deps).
ranking:seed_bwu_memo_from_dep(exactly_one_of_group(Deps)) :- !,
  ranking:seed_bwu_memo_from_dep_tree(Deps).
ranking:seed_bwu_memo_from_dep(at_most_one_of_group(Deps)) :- !,
  ranking:seed_bwu_memo_from_dep_tree(Deps).
ranking:seed_bwu_memo_from_dep(use_conditional_group(Pol, Use, RepoEntry, Deps)) :- !,
  ( ranking:seed_use_conditional_inactive(Pol, Use, RepoEntry) ->
      true
  ; ranking:seed_bwu_memo_from_dep_tree(Deps)
  ).
ranking:seed_bwu_memo_from_dep(_).


%! ranking:seed_use_conditional_inactive(+Polarity, +Use, +RepoEntry) is semidet
%
% True only when the USE-conditional guard is *positively determined* to be
% inactive for its owning entry, i.e. seeding its bracketed USE would be
% spurious.  A `flag? ( ... )` group is inactive when the entry has the flag
% off; a `!flag? ( ... )` group is inactive when the flag is on.  Fails (so
% the caller still recurses) when the state cannot be determined (flag not in
% IUSE, minus-wrapped, or RepoEntry unbound), keeping seeding conservative.

ranking:seed_use_conditional_inactive(positive, Use, Repo://Id) :-
  Use \= minus(_),
  use:effective_use_for_entry(Repo://Id, Use, negative),
  !.
ranking:seed_use_conditional_inactive(negative, Use, Repo://Id) :-
  Use \= minus(_),
  use:effective_use_for_entry(Repo://Id, Use, positive),
  !.


%! ranking:seed_bwu_memo_for_cn(+C, +N, +UseReqs) is det
%
% Build BWU from bracket atoms on one edge and merge into the (C,N) memo.
% Never fails the caller (conflicting edges leave the memo unchanged).
%
% Only context-independent directives (plain `[flag]` / `[-flag]`) are
% seeded.  Equality (`[flag=]`), inverse (`[!flag=]`) and optional
% (`[flag?]` / `[!flag?]`) directives resolve against the *parent's*
% effective USE state, which is not available during seeding (the seed
% runs with an empty parent context).  Resolving them here would make
% use:use_dep_requirement/4 fall back to the bracket's IUSE default --
% disabling a flag the parent actually enables -- and that bogus pin then
% conflicts with the correct value the prover derives later under the real
% parent context (e.g. net-misc/curl[curl_ssl_openssl=] from a consumer
% with openssl on, issue #82).  These directives are accumulated correctly
% at proof time via use:check_bwu_ed_conflict/3.

ranking:seed_bwu_memo_for_cn(C, N, UseReqs) :-
  include(ranking:context_independent_use_directive, UseReqs, SeedReqs),
  ( SeedReqs == [] ->
      true
  ; dependency:process_build_with_use(SeedReqs, [], Ctx, _, _),
    ( use:context_build_with_use_state(Ctx, BWU) ->
        ranking:seed_accumulate_bwu(C, N, BWU)
    ; true
    )
  ).


%! ranking:context_independent_use_directive(+Directive) is semidet
%
% True for bracketed USE directives whose enable/disable outcome does not
% depend on the parent ebuild's effective USE state, i.e. plain `enable`
% and `disable`.  Equality/inverse/optional directives are excluded.

ranking:context_independent_use_directive(use(enable(_), _)).
ranking:context_independent_use_directive(use(disable(_), _)).


%! ranking:seed_accumulate_bwu(+C, +N, +BWU) is det

ranking:seed_accumulate_bwu(_C, _N, use_state([], [])) :- !.
ranking:seed_accumulate_bwu(C, N, BWU) :-
  ( use:accumulate_candidate_bwu(C, N, BWU) -> true ; true ).


% -----------------------------------------------------------------------------
%  Equality-USE pin propagation ([flag=] / [!flag=])
% -----------------------------------------------------------------------------

%! ranking:equality_pins_from_providers(+RepoEntry, -PinState) is det
%
% Scan RepoEntry's own DEPEND/RDEPEND/BDEPEND for unconditional bracketed
% equality USE deps (`provider[flag=]` / `provider[!flag=]`).  For each such
% dep whose provider already has the flag pinned in memo:candidate_bwu_/3,
% derive the flag value this entry must itself build with, so that
% REQUIRED_USE resolution honours the bidirectional `=` constraint.
%
%   [flag=]  : this.flag == provider.flag    (provider on  -> enable here)
%   [!flag=] : this.flag == \+ provider.flag (provider on  -> disable here)
%
% Only top-level / all_of_group deps are scanned (no descent into USE-
% conditional or choice groups): a flag pinned from inside such a group is
% the very flag being resolved, so it is left to normal resolution.  A pin
% that would force a flag both on and off (independent providers disagree)
% is dropped, letting the existing conflict machinery report it.  Returns
% use_state([],[]) when nothing is pinned (the common case).

ranking:equality_pins_from_providers(Repo://Entry, PinState) :-
  findall(F-Mode,
          ( member(Key, [depend, rdepend, bdepend]),
            cache:entry_metadata(Repo, Entry, Key, Term),
            ranking:equality_pin_from_term(Term, F, Mode)
          ),
          Pins0),
  ( Pins0 == [] ->
      use:empty_use_state(PinState)
  ; sort(Pins0, Pins),
    findall(EF, member(EF-enable, Pins), En0), sort(En0, En),
    findall(DF, member(DF-disable, Pins), Dis0), sort(Dis0, Dis),
    ( ranking:pin_flags_conflict(En, Dis) ->
        use:empty_use_state(PinState)
    ; PinState = use_state(En, Dis)
    )
  ).


%! ranking:pin_flags_conflict(+Enable, +Disable) is semidet
%
% True when a flag appears in both the enable and disable pin sets.

ranking:pin_flags_conflict(En, Dis) :-
  member(F, En),
  memberchk(F, Dis),
  !.


%! ranking:equality_pin_from_term(+DepTerm, -Flag, -Mode) is nondet
%
% Yield Flag-Mode (Mode = enable|disable) for each unconditional equality
% bracket USE dep in DepTerm whose provider is pinned in the BWU memo.
% Descends only all_of_group; choice and USE-conditional groups are skipped.

ranking:equality_pin_from_term(package_dependency(_P, _S, PC, PN, _O, _V, _Slot, UseDeps), F, Mode) :-
  member(UseDep, UseDeps),
  ranking:equality_pin_from_usedep(PC, PN, UseDep, F, Mode).
ranking:equality_pin_from_term(all_of_group(Deps), F, Mode) :-
  member(D, Deps),
  ranking:equality_pin_from_term(D, F, Mode).


%! ranking:equality_pin_from_usedep(+PC, +PN, +UseDep, -Flag, -Mode) is nondet
%
% Map one `use(equal(F),_)` / `use(inverse(F),_)` directive on provider
% (PC,PN) to the flag value this entry must build with, given the provider's
% current BWU pin.

ranking:equality_pin_from_usedep(PC, PN, use(equal(F), _), F, Mode) :-
  ranking:provider_pin_mode(PC, PN, F, Mode).
ranking:equality_pin_from_usedep(PC, PN, use(inverse(F), _), F, Mode) :-
  ranking:provider_pin_mode(PC, PN, F, ProviderMode),
  ranking:invert_pin_mode(ProviderMode, Mode).


%! ranking:provider_pin_mode(+PC, +PN, +Flag, -Mode) is semidet
%
% Mode is enable/disable iff provider (PC,PN) has Flag pinned on/off in the
% BWU memo.  Fails when the flag is unpinned (equality resolves normally).

ranking:provider_pin_mode(PC, PN, F, enable) :-
  memo:candidate_bwu_(PC, PN, use_state(En, _Dis)),
  memberchk(F, En),
  !.
ranking:provider_pin_mode(PC, PN, F, disable) :-
  memo:candidate_bwu_(PC, PN, use_state(_En, Dis)),
  memberchk(F, Dis),
  !.


%! ranking:invert_pin_mode(+Mode, -Inverted) is det

ranking:invert_pin_mode(enable, disable).
ranking:invert_pin_mode(disable, enable).


%! ranking:apply_equality_pins(+RepoEntry, +BWU0, -BWU) is det
%
% Union the equality-USE pins derived from RepoEntry's providers into the
% candidate's own build_with_use state before REQUIRED_USE resolution.  When
% a pin contradicts the existing state, BWU0 is kept unchanged and the clash
% is left for check_bwu_cross_dep / REQUIRED_USE verification to report.

ranking:apply_equality_pins(Repo://Entry, BWU0, BWU) :-
  ranking:equality_pins_from_providers(Repo://Entry, PinState),
  ( PinState == use_state([], []) ->
      BWU = BWU0
  ; BWU0 == use_state([], []) ->
      BWU = PinState
  ; feature_unification:val_hook(BWU0, PinState, BWU) ->
      true
  ; BWU = BWU0
  ).


% -----------------------------------------------------------------------------
%  Proof-order tightness classes
% -----------------------------------------------------------------------------

%! ranking:tightness_classes(-Classes)
%
% Proof-order tightness classes, tightest first. A grouped dependency is
% proved in the order of the *first* class in this list that applies to
% it: a sub-slot pin beats a tight upper bound, which beats a tilde
% constraint, which beats a plain slot pin, which beats a wildcard, and
% so on down to unconstrained deps. Tight constraints are proved first so
% that `selected_cn` locks the version before a looser sibling picks a
% conflicting one. The position in this list is the sort key; nothing
% else encodes the order.

ranking:tightness_classes([subslot_pinned,
                           upper_bounded,
                           tilde,
                           slot_pinned,
                           wildcard,
                           any_same_slot,
                           any_different_slot,
                           unconstrained,
                           other_slot_req,
                           no_slot_restriction,
                           not_a_package_dep]).


%! ranking:tightness_position(+Class, -Pos) is det.
%
% Position of Class in tightness_classes/1 (lower is proved first).

ranking:tightness_position(Class, Pos) :-
  ranking:tightness_classes(Classes),
  nth0(Pos, Classes, Class),
  !.


%! ranking:dep_priority(+DepLiteral, -Key)
%
% Proof-order key for a dependency literal; lower keys are proved first.
% Key is `key(Pos, TightUpper, C, N)`: Pos is the dep's tightness class
% position (tightness_classes/1), TightUpper the tightest `<`/`<=` bound
% (or `none`) so that, among upper-bounded deps, the tighter bound goes
% first, and (C, N) keep the order deterministic.

ranking:dep_priority(grouped_package_dependency(_T,C,N,PackageDeps):Action?{_Context},
                     key(Pos, TightUpper, C, N)) :-
  !,
  ( slotmeta:merge_slot_restriction(Action, C, N, PackageDeps, SlotReq) ->
      ( ranking:dep_tightest_upper_bound(C, N, PackageDeps, TightUpper) -> true
      ; TightUpper = none
      ),
      ranking:tightness_class(dep(C, N, PackageDeps, SlotReq, TightUpper), Class)
  ; TightUpper = none,
    Class = no_slot_restriction
  ),
  ranking:tightness_position(Class, Pos).
ranking:dep_priority(_Other, key(Pos, none, zz, zz)) :-
  ranking:tightness_position(not_a_package_dep, Pos).


ranking:dep_priority_kv(Dep, K-Dep) :-
  ranking:dep_priority(Dep, K),
  !.


%! ranking:tightness_class(+Dep, -Class) is det.
%
% First class in tightness_classes/1 that applies to
% dep(C, N, PackageDeps, SlotReq, TightUpper).

ranking:tightness_class(Dep, Class) :-
  ranking:tightness_classes(Classes),
  member(Class, Classes),
  ranking:in_tightness_class(Dep, Class),
  !.


%! ranking:in_tightness_class(+Dep, +Class) is semidet.
%
% Membership test per class. `other_slot_req` applies to every
% slot-restricted dep and closes the list for them.

ranking:in_tightness_class(dep(_, _, _, [slot(_),subslot(_)|_], _), subslot_pinned).
ranking:in_tightness_class(dep(_, _, _, _, TightUpper), upper_bounded) :-
  TightUpper \== none.
ranking:in_tightness_class(dep(C, N, PackageDeps, _, _), tilde) :-
  cnselect:dep_has_tilde_constraint(C, N, PackageDeps).
ranking:in_tightness_class(dep(_, _, _, [slot(_)|_], _), slot_pinned).
ranking:in_tightness_class(dep(C, N, PackageDeps, _, _), wildcard) :-
  cnselect:dep_has_equal_wildcard_constraint(C, N, PackageDeps).
ranking:in_tightness_class(dep(_, _, _, [any_same_slot], _), any_same_slot).
ranking:in_tightness_class(dep(_, _, _, [any_different_slot], _), any_different_slot).
ranking:in_tightness_class(dep(_, _, _, [], _), unconstrained).
ranking:in_tightness_class(dep(_, _, _, _, _), other_slot_req).


%! ranking:dep_tightest_upper_bound(+C, +N, +PackageDeps, -Tightest) is semidet.
%
% Tightest `<` / `<=` version bound on (C, N) among PackageDeps.

ranking:dep_tightest_upper_bound(C, N, PackageDeps, Tightest) :-
  member(package_dependency(_, no, C, N, Op0, _, _, _), PackageDeps),
  ( Op0 == smaller ; Op0 == smallerorequal ),
  !,
  findall(V,
          ( member(package_dependency(_Phase, no, C, N, Op, V, _S, _U), PackageDeps),
            ( Op == smaller ; Op == smallerorequal )
          ),
          [First|Rest]),
  foldl(min_version_bound_, Rest, First, Tightest).

ranking:min_version_bound_(V, Best0, Best) :-
  ( eapi:version_compare(<, V, Best0) ->
      Best = V
  ; Best = Best0
  ),
  !.


%! ranking:dep_extract_cn_packagedeps(+DepLiteral, -C, -N, -PackageDeps) is semidet.
%
% Extracts the category, name, and package deps from a grouped
% dependency literal. Handles both Context and bare forms.

ranking:dep_extract_cn_packagedeps(grouped_package_dependency(_T, C, N, PackageDeps):_Action?{_}, C, N, PackageDeps) :- !.
ranking:dep_extract_cn_packagedeps(grouped_package_dependency(_T, C, N, PackageDeps):_Action, C, N, PackageDeps) :- !.


% -----------------------------------------------------------------------------
%  Choice-group arm ranking (emerge dep_zapdeps alignment)
% -----------------------------------------------------------------------------

%! ranking:choice_criteria(-Criteria)
%
% Ordered preference criteria for the arms of a choice group (`||`, `^^`,
% `??`), most significant first. Each criterion yields a term for an arm
% (criterion_value/5); arms are compared criterion by criterion using the
% standard order of terms, and a *larger* term is preferred. Values are
% therefore chosen so that standard order is the preference order:
% `no @< yes`, counts are integers, versions are version/7 terms (see
% .cursorrules, "Version representation"), slots and USE_EXPAND targets
% are digit-group lists (`'3.10'` -> [3,10] @> [3,3]), and `none` (an
% atom) sorts below every list or compound. No arithmetic, no negation,
% no packing of several signals into one integer.
%
% The order mirrors emerge's dep_zapdeps choice bins; see
% Documentation/Handbook/12-doc-resolution.md ("Any-of (||) arm
% selection") for the intent and emerge analogue of every criterion.
%
%   license_ok    arm is license-acceptable
%   use_sat       bracket USE needs no flip on the arm's best candidate
%   use_unmasked  required flips respect profile use.mask / use.force
%   preference    installed / profile-preferred / --favour / self-CN
%                 (pref/6 compound, see preference_value/3)
%   snap_all      every non-virtual CN already in the selected_cn snapshot
%   snap_admits   the already-selected candidate satisfies the arm's
%                 version bounds (portage-ng#123). Vacuous when nothing
%                 of that CN is selected, so `version` still picks the
%                 newest arm (portage-ng#112).
%   slot          highest explicit slot -- same-CN groups only
%   no_downgrade  newest admitted version not below installed / snapshot
%   installed     number of installed CNs the arm reuses
%   overlap       arm's CN appears in several sibling || groups
%   version       newest admitted tree version -- same-CN groups only
%   use_expand    USE_EXPAND alignment with the profile selection
%
% `slot` and `version` only apply when every arm targets one single (C,N)
% (portage-ng#112 cabal text ranges, `|| ( llvm:20 llvm:19 )`). Comparing
% newest versions or highest slots of *different* packages is meaningless
% and flips choices away from ebuild order (portage-ng#115 openjdk vs
% openjdk-bin, portage-ng#116 notqmail-9999 vs nullmailer, ruby-single
% `( ruby:3.3 rubygems[ruby33] )` vs `( ruby:4.0 rubygems[ruby40] )` in
% the webkit-gtk cluster). Emerge never ranks across CPs inside a choice;
% it falls back to ebuild order, and so do we: the arm's original index
% breaks every remaining tie.

ranking:choice_criteria([license_ok,
                         use_sat,
                         use_unmasked,
                         preference,
                         snap_all,
                         snap_admits,
                         slot,
                         no_downgrade,
                         installed,
                         overlap,
                         version,
                         use_expand]).


%! ranking:prioritize_deps_keep_all(+Deps, +Context, -SortedDeps)
%
% Orders the arms of a choice group most-preferred first, keeping every
% arm, by the criteria of choice_criteria/1 with the original ebuild
% index as the final tie-breaker. A thread-local variant:branch_prefer/1
% override moves its arms to the front afterwards.

ranking:prioritize_deps_keep_all(Deps, Context, SortedDeps) :-
  setup_call_cleanup(
    ( empty_assoc(Empty),
      nb_setval(ranking_choice_cache, Empty)
    ),
    ranking:prioritize_deps_keep_all_body(Deps, Context, SortedDeps),
    catch(nb_delete(ranking_choice_cache), _, true)
  ).


ranking:prioritize_deps_keep_all_body(Deps, Context, SortedDeps) :-
  ( ranking:deps_share_single_cn(Deps) -> Gate = same_cn ; Gate = multi_cn ),
  findall(Key-I-Dep,
          ( nth1(I, Deps, Dep),
            ranking:analyse_arm(Context, Dep, Arm),
            ranking:arm_key(Context, Gate, Arm, Key)
          ),
          Keyed),
  predsort(ranking:prefer_arm, Keyed, Sorted),
  findall(Dep, member(_-_-Dep, Sorted), SortedDeps0),
  ranking:boost_variant_preferred(SortedDeps0, SortedDeps),
  !.


%! ranking:arm_key(+Context, +Gate, +Arm, -Key) is det.
%
% Key is the list of criterion values for Arm, in choice_criteria/1
% order. Every criterion is det, so keys of different arms align.

ranking:arm_key(Context, Gate, Arm, Key) :-
  ranking:choice_criteria(Criteria),
  maplist(ranking:arm_criterion(Context, Gate, Arm), Criteria, Key).


ranking:arm_criterion(Context, Gate, Arm, Criterion, Value) :-
  ranking:criterion_value(Criterion, Context, Gate, Arm, Value),
  !.


%! ranking:prefer_arm(-Order, +KeyedA, +KeyedB) is det.
%
% predsort/3 comparator over Key-Index-Dep triples: the arm with the
% larger value on the first differing criterion sorts first; equal keys
% fall back to the original (ascending) index, so no arm is ever dropped.

ranking:prefer_arm(Order, KeyA-IA-_, KeyB-IB-_) :-
  ( ranking:compare_preference(O, KeyA, KeyB),
    O \== (=)
  -> Order = O
  ;  compare(Order, IA, IB)
  ).


%! ranking:compare_preference(-Order, +KeyA, +KeyB) is det.
%
% Lexicographic comparison of two criterion-value lists in which a
% larger value is preferred (sorts first): Order is `<` when KeyA is
% preferred over KeyB.

ranking:compare_preference(=, [], []) :- !.
ranking:compare_preference(Order, [A|As], [B|Bs]) :-
  compare(C, B, A),
  ( C == (=) ->
      ranking:compare_preference(Order, As, Bs)
  ; Order = C
  ).


% -----------------------------------------------------------------------------
%  Arm analysis (computed once per arm, shared by the criteria)
% -----------------------------------------------------------------------------

%! ranking:analyse_arm(+Context, +Dep, -Arm) is det.
%
% Arm = arm(Dep, Atoms, BestRE, BestVer, UseFit): the arm's package
% atoms, its newest tree candidate admitted by the arm's same-CN version
% domain (Repo://Entry and version/7, or `none` / `version_none`), and
% use_fit(UseSat, UseUnmasked) for the arm's bracket USE against that
% candidate. Computed once per arm; the criteria only read it.

ranking:analyse_arm(Context, Dep, arm(Dep, Atoms, BestRE, BestVer, use_fit(UseSat, UseUnmasked))) :-
  ranking:dep_arm_package_atoms(Dep, Atoms),
  ranking:dep_best_admitted(Dep, BestRE, BestVer),
  ranking:dep_use_fit(Context, Atoms, BestRE, UseSat, UseUnmasked),
  !.


%! ranking:criterion_value(+Criterion, +Context, +Gate, +Arm, -Value) is det.
%
% Value of one criterion of choice_criteria/1 for Arm. Larger is
% preferred (standard order of terms). Gate is `same_cn` or `multi_cn`;
% the two gated criteria yield their bottom value for multi-CN groups.

ranking:criterion_value(license_ok, _Context, _Gate, arm(Dep, _, _, _, _), Value) :-
  ranking:yes_no(acceptance:dep_license_ok(Dep), Value).
ranking:criterion_value(use_sat, _Context, _Gate, arm(_, _, _, _, use_fit(UseSat, _)), UseSat).
ranking:criterion_value(use_unmasked, _Context, _Gate, arm(_, _, _, _, use_fit(_, UseUnmasked)), UseUnmasked).
ranking:criterion_value(preference, Context, _Gate, arm(Dep, _, _, _, _), Pref) :-
  ranking:preference_value(Context, Dep, Pref).
ranking:criterion_value(snap_all, _Context, _Gate, arm(_, Atoms, _, _, _), Value) :-
  ranking:yes_no(ranking:dep_snap_all_ok(Atoms), Value).
ranking:criterion_value(snap_admits, _Context, _Gate, arm(_, Atoms, _, _, _), Value) :-
  ranking:yes_no(ranking:dep_snap_admits(Atoms), Value).
ranking:criterion_value(slot, _Context, same_cn, arm(_, Atoms, _, _, _), Slot) :-
  ranking:dep_slot_value(Atoms, Slot).
ranking:criterion_value(slot, _Context, multi_cn, _Arm, none).
ranking:criterion_value(no_downgrade, _Context, _Gate, arm(Dep, _, _, BestVer, _), Value) :-
  ranking:dep_no_downgrade_value(Dep, BestVer, Value).
ranking:criterion_value(installed, _Context, _Gate, arm(_, Atoms, _, _, _), Count) :-
  ranking:dep_installed_count(Atoms, Count).
ranking:criterion_value(overlap, Context, _Gate, arm(Dep, _, _, _, _), Overlap) :-
  ranking:dep_overlap_group_count(Context, Dep, Raw),
  ( Raw > 1 -> Overlap = Raw ; Overlap = 0 ).
ranking:criterion_value(version, _Context, same_cn, arm(_, _, _, BestVer, _), BestVer).
ranking:criterion_value(version, _Context, multi_cn, _Arm, version_none).
ranking:criterion_value(use_expand, _Context, _Gate, arm(Dep, _, _, _, _), Score) :-
  ranking:dep_use_expand_profile_score(Dep, Score).


%! ranking:yes_no(:Goal, -Value) is det.
%
% Value is `yes` when Goal succeeds, `no` otherwise (`no @< yes`).

ranking:yes_no(Goal, Value) :-
  ( call(Goal) -> Value = yes ; Value = no ).


%! ranking:boost_variant_preferred(+Deps, -Reordered) is det.
%
% When a thread-local variant:branch_prefer/1 override is active,
% moves matching deps to the front so the any_of_group cut selects them.

ranking:boost_variant_preferred(Deps, Reordered) :-
  ( variant:branch_prefer(Pref),
    partition(ranking:dep_matches_prefer(Pref), Deps, Front, Rest),
    Front \== []
  -> append(Front, Rest, Reordered)
  ;  Reordered = Deps
  ).


% -----------------------------------------------------------------------------
%  Criterion helpers
% -----------------------------------------------------------------------------

%! ranking:deps_share_single_cn(+Deps) is semidet.
%
% True when every package atom across all arms of a choice group targets
% one single (C,N) — e.g. cabal's text 1.x-range vs 2.x-range arms
% (portage-ng#112). Gates the VerScore and SlotScore sort keys:
% version- or slot-ranking arms of *different* packages diverges from
% emerge's ebuild-order fallback (portage-ng#115/#116, ruby-single
% webkit-gtk regression).

ranking:deps_share_single_cn(Deps) :-
  findall(C-N,
          ( member(Dep, Deps),
            ranking:dep_arm_package_atoms(Dep, Atoms),
            member(package_dependency(_, _, C, N, _, _, _, _), Atoms)
          ),
          CNs),
  sort(CNs, [_]).


%! ranking:dep_arm_package_atoms(+Dep, -Atoms) is det.
%
% Flatten package_dependency leaves from an || arm (all_of_group /
% use_conditional_group recursion).

ranking:dep_arm_package_atoms(package_dependency(Ph, St, C, N, O, V, S, U),
                              [package_dependency(Ph, St, C, N, O, V, S, U)]) :- !.
ranking:dep_arm_package_atoms(all_of_group(Deps), Atoms) :-
  is_list(Deps),
  !,
  findall(A,
          ( member(D, Deps),
            ranking:dep_arm_package_atoms(D, As),
            member(A, As)
          ),
          Atoms).
ranking:dep_arm_package_atoms(use_conditional_group(_, _, _, Deps), Atoms) :-
  is_list(Deps),
  !,
  ranking:dep_arm_package_atoms(all_of_group(Deps), Atoms).
ranking:dep_arm_package_atoms(_, []).


%! ranking:dep_blocker_strength(+Strength) is semidet.

ranking:dep_blocker_strength(weak).
ranking:dep_blocker_strength(strong).


%! ranking:dep_use_fit(+Context, +Atoms, +BestRE, -UseSat, -UseUnmasked) is det.
%
% UseSat = yes when bracket USE needs no change on BestRE (or there are
% no USE deps). UseUnmasked = yes when the required flips respect profile
% use.mask / use.force. Neutral (yes, yes) when BestRE is unavailable so
% incomplete arms are not demoted spuriously.

ranking:dep_use_fit(Context, Atoms, BestRE, UseSat, UseUnmasked) :-
  findall(U,
          ( member(package_dependency(_, Str, _, _, _, _, _, Us), Atoms),
            \+ ranking:dep_blocker_strength(Str),
            is_list(Us),
            member(U, Us)
          ),
          UseDeps),
  ( UseDeps == []
  -> UseSat = yes,
     UseUnmasked = yes
  ; BestRE == none
  -> UseSat = yes,
     UseUnmasked = yes
  ; catch(use:directives_to_bwu(Context, UseDeps, BWU), _,
          BWU = use_state([], [])),
    ( BWU = use_state([], [])
    -> UseSat = yes,
       UseUnmasked = yes
    ; use:build_with_use_changes(BWU, BestRE, Changes),
      ranking:yes_no(Changes == [], UseSat),
      ranking:yes_no(catch(use:bwu_respects_profile_hard(BestRE, BWU), _, fail),
                     UseUnmasked)
    )
  ).


%! ranking:dep_snap_all_ok(+Atoms) is semidet.
%
% True iff Atoms is non-empty and every non-blocker, non-virtual package
% atom's (C,N) is present in the selected_cn snapshot (emerge
% all_in_graph stand-in).

ranking:dep_snap_all_ok(Atoms) :-
  Atoms \== [],
  forall(member(package_dependency(_, Str, C, N, _, _, _, _), Atoms),
         ( ranking:dep_blocker_strength(Str) -> true
         ; C == virtual -> true
         ; cnselect:snapshot_selected_cn_candidates(C, N, _)
         )).


%! ranking:dep_snap_admits(+Atoms) is semidet.
%
% True when every already-selected candidate of an atom's (C,N) satisfies
% that atom's version operator. An atom with nothing selected is vacuous,
% so an unconstrained choice still falls through to the `version`
% criterion (portage-ng#112). An arm that excludes the selected candidate
% loses to one that admits it (portage-ng#123: cabal's text-2 arm must
% not beat the text-1.2 arm once text-1.2.5.0 is selected). An atom with
% an explicit slot judges only the selected candidates of that slot;
% another slot can be installed side by side, so it is vacuous too.

ranking:dep_snap_admits(Atoms) :-
  forall(member(package_dependency(_, Str, C, N, Op, Ver, SlotReq, _), Atoms),
         ( ranking:dep_blocker_strength(Str) -> true
         ; C == virtual -> true
         ; \+ cnselect:snapshot_selected_cn_candidates(C, N, _) -> true
         ; cnselect:snapshot_selected_cn_candidates(C, N, Selected0),
           candidate:pin_slot_selected(SlotReq, Selected0, Selected),
           ( Selected == [] -> true
           ; member(SRepo://SEntry, Selected),
             query:search(select(version, Op, Ver), SRepo://SEntry)
           )
         )).


%! ranking:dep_slot_value(+Atoms, -Slot) is det.
%
% Highest explicit slot among the arm's non-blocker atoms as a
% version_key/2 digit-group list (llvm-style `|| ( llvm:20 llvm:19 )`
% slot preference), or `none` when no atom pins a non-zero numeric slot.
% Only honoured for same-CN groups (criterion_value/5 yields `none` for
% multi-CN groups, see deps_share_single_cn/1).

ranking:dep_slot_value(Atoms, Slot) :-
  findall(Key,
          ( member(package_dependency(_, Str, _, _, _, _, [slot(S)|_], _), Atoms),
            \+ ranking:dep_blocker_strength(Str),
            ranking:version_key(S, Key),
            Key \== [0]
          ),
          Keys),
  ( Keys == [] -> Slot = none ; max_member(Slot, Keys) ).


%! ranking:dep_no_downgrade_value(+Dep, +BestVer, -NoDowngrade) is det.
%
% `no` when the arm's newest admitted version is strictly below the
% highest installed or snap-selected version for that CN (emerge
% downgrade demotion), `yes` otherwise. Under `--permit-downgrade` the
% criterion is neutral (`yes` for every arm): an older version is as
% acceptable as the installed one.

ranking:dep_no_downgrade_value(_Dep, _BestVer, yes) :-
  preference:flag(permitdowngrade),
  !.
ranking:dep_no_downgrade_value(Dep, BestVer, NoDowngrade) :-
  BestVer \== version_none,
  compound(BestVer),
  ranking:dep_cn_version_domain(Dep, C, N, _),
  C \== virtual,
  ranking:reference_highest_version(C, N, RefVer),
  RefVer \== version_none,
  !,
  ranking:yes_no(BestVer @>= RefVer, NoDowngrade).
ranking:dep_no_downgrade_value(_, _, yes).


%! ranking:reference_highest_version(+C, +N, -Ver) is det.
%
% Highest of installed VDB version and snap-selected versions for (C,N).
% Cached per prioritize_deps_keep_all/3 call. version_none if neither.

ranking:reference_highest_version(C, N, Ver) :-
  ( ranking:choice_cache_get(refver(C-N), Ver) -> true
  ; ranking:lookup_reference_highest_version(C, N, Ver),
    ranking:choice_cache_put(refver(C-N), Ver)
  ).


ranking:lookup_reference_highest_version(C, N, Ver) :-
  findall(V, ranking:reference_version_candidate(C, N, V), Vers),
  ( Vers == []
  -> Ver = version_none
  ; sort(Vers, Sorted),
    last(Sorted, Ver)
  ).


ranking:reference_version_candidate(C, N, Ver) :-
  catch(( knowledgebase:vdb_repository(VdbRepo),
          query:search([name(N), category(C), installed(true)], VdbRepo://Id),
          query:search(version(Ver), VdbRepo://Id)
        ), _, fail).
ranking:reference_version_candidate(C, N, Ver) :-
  cnselect:snapshot_selected_cn_candidates(C, N, Cands),
  member(Repo://Entry, Cands),
  catch(query:search(version(Ver), Repo://Entry), _, fail).


%! ranking:dep_installed_count(+Atoms, -Count) is det.
%
% Number of non-blocker, non-virtual atoms whose CN is installed (partial
% other_installed fuzzy bin).

ranking:dep_installed_count(Atoms, Count) :-
  aggregate_all(count,
                ( member(package_dependency(_, Str, C, N, _, _, _, _), Atoms),
                  \+ ranking:dep_blocker_strength(Str),
                  C \== virtual,
                  ranking:cn_is_installed(C, N)
                ),
                Count).


%! ranking:cn_is_installed(+C, +N) is semidet.

ranking:cn_is_installed(C, N) :-
  ( ranking:choice_cache_get(inst(C-N), Hit) -> Hit == true
  ; ( catch(( knowledgebase:vdb_repository(VdbRepo),
              query:search([name(N), category(C), installed(true)], VdbRepo://_)
            ), _, fail)
    -> ranking:choice_cache_put(inst(C-N), true),
       true
    ; ranking:choice_cache_put(inst(C-N), false),
      fail
    )
  ).


%! ranking:choice_cache_get(+Key, -Value) is semidet.
%! ranking:choice_cache_put(+Key, +Value) is det.
%
% The per-choice-group memo of prioritize_deps_keep_all/3. It exists
% only inside that predicate's setup_call_cleanup scope: a put from
% outside the scope is dropped rather than creating a global that would
% outlive the choice group and never be invalidated.

ranking:choice_cache_get(Key, Value) :-
  nb_current(ranking_choice_cache, AVL),
  get_assoc(Key, AVL, Value),
  !.

ranking:choice_cache_put(Key, Value) :-
  ( nb_current(ranking_choice_cache, AVL0)
  -> put_assoc(Key, AVL0, Value, AVL1),
     nb_setval(ranking_choice_cache, AVL1)
  ;  true
  ).


%! ranking:dep_best_admitted(+Dep, -BestRE, -BestVer) is det.
%
% Newest tree version admitted by Dep's same-CN version domain, plus its
% Repo://Entry (or none / version_none when not applicable). BestVer is
% a version/7 term and is compared directly by the `version` criterion:
% standard order on version/7 is the PMS version order, and the atom
% version_none sorts below every version term.

ranking:dep_best_admitted(Dep, BestRE, BestVer) :-
  ranking:dep_cn_version_domain(Dep, C, N, Domain),
  \+ version_domain:domain_inconsistent(Domain),
  !,
  findall(Ver-(Repo://Entry),
          ( cache:ordered_entry(Repo, Entry, C, N, Ver),
            version_domain:domain_allows_candidate(Domain, Repo://Entry)
          ),
          Pairs),
  ( Pairs == []
  -> BestRE = none,
     BestVer = version_none
  ; sort(Pairs, Sorted),
    last(Sorted, BestVer-BestRE)
  ).
ranking:dep_best_admitted(_Dep, none, version_none).


%! ranking:dep_cn_version_domain(+Dep, -C, -N, -Domain) is semidet.
%
% Succeeds when Dep is a package_dependency or an all_of_group whose
% members are all package_dependency terms on the same (C,N).

ranking:dep_cn_version_domain(package_dependency(Ph, St, C, N, O, V, S, U), C, N, Domain) :-
  !,
  version_domain:domain_from_packagedeps(Ph, C, N,
    [package_dependency(Ph, St, C, N, O, V, S, U)], Domain).
ranking:dep_cn_version_domain(all_of_group(Deps), C, N, Domain) :-
  Deps \== [],
  Deps = [package_dependency(_, _, C, N, _, _, _, _)|_],
  forall(member(D, Deps),
         D = package_dependency(_, _, C, N, _, _, _, _)),
  !,
  version_domain:domain_from_packagedeps(run, C, N, Deps, Domain).


%! ranking:dep_matches_prefer(+Preferred, +Dep) is semidet.

ranking:dep_matches_prefer(Pref, Dep) :-
  Pref = package_dependency(_, _, PC, PN, _, _, _, _),
  Dep  = package_dependency(_, _, PC, PN, _, _, _, _).


%! ranking:dep_overlap_group_count(+Context, +Dep, -Count) is det.
%
% Number of active `||` groups in the parent ebuild's dependency strings
% that mention Dep's (C,N); 0 for non-package arms or without a parent.

ranking:dep_overlap_group_count(Context, package_dependency(_,_,C,N,_,_,_,_), Count) :-
  memberchk(self(Repo://Ebuild), Context),
  !,
  aggregate_all(count, (
    member(DepKey, [rdepend, depend, bdepend, pdepend, cdepend, idepend]),
    cache:entry_metadata(Repo, Ebuild, DepKey, DepEntry),
    dep_entry_active_any_of_with_cn(DepEntry, Repo://Ebuild, C, N)
  ), Count).
ranking:dep_overlap_group_count(_, _, 0).

ranking:dep_entry_active_any_of_with_cn(any_of_group(Deps), _, C, N) :-
  member(package_dependency(_, _, C, N, _, _, _, _), Deps), !.
ranking:dep_entry_active_any_of_with_cn(use_conditional_group(Pol, Use, RepoEntry, Deps), _, C, N) :-
  candidate:rdepend_self_use_conditional_active(Pol, Use, RepoEntry),
  member(D, Deps),
  dep_entry_active_any_of_with_cn(D, RepoEntry, C, N), !.
ranking:dep_entry_active_any_of_with_cn(all_of_group(Deps), RepoEntry, C, N) :-
  member(D, Deps),
  dep_entry_active_any_of_with_cn(D, RepoEntry, C, N), !.


% -----------------------------------------------------------------------------
%  The `preference` criterion
% -----------------------------------------------------------------------------

%! ranking:preference_value(+Context, +Dep, -Pref) is det.
%
% Pref = pref(Preferred, Favour, NotSelf, InstalledOk, Bootstrap, Target),
% compared argument-wise by the standard order of terms, so the six
% signals form a strict lexicographic order (most significant first):
%
%   Preferred    yes when is_preferred_dep/2 holds (profile-selected USE,
%                installed package satisfying the atom, ...)
%   Favour       1 / 0 / -1 for --favour / neither or both / --avoid
%   NotSelf      no when the atom names the parent's own (C,N)
%   InstalledOk  no when the CN is installed but no installed version
%                satisfies the atom (a forced upgrade)
%   Bootstrap    yes for `*-bootstrap` packages
%   Target       USE_EXPAND target digits of a `required(Use)` arm
%                (use_expand_target_key/2), else `none`
%
% Non-package arms (all_of_group, use_conditional_group, required(Use))
% are neutral on the package-only signals.

ranking:preference_value(Context, package_dependency(Phase,Strength,C,N,O,V,S,U),
                         pref(Preferred, Favour, NotSelf, InstalledOk, Bootstrap, none)) :-
  !,
  Dep = package_dependency(Phase,Strength,C,N,O,V,S,U),
  ranking:yes_no(ranking:is_preferred_dep(Context, Dep), Preferred),
  ranking:favour_signal(C, N, Favour),
  ranking:yes_no(\+ ranking:self_cn(Context, C, N), NotSelf),
  ranking:yes_no(\+ ranking:installed_version_mismatch(Dep), InstalledOk),
  ranking:yes_no(atom_concat(_, '-bootstrap', N), Bootstrap).
ranking:preference_value(Context, Dep, pref(Preferred, 0, yes, yes, no, Target)) :-
  ranking:yes_no(ranking:is_preferred_dep(Context, Dep), Preferred),
  ranking:required_use_target(Dep, Target).


%! ranking:self_cn(+Context, +C, +N) is semidet.
%
% True when (C, N) is the parent ebuild carried in the proof context.

ranking:self_cn(Context, C, N) :-
  memberchk(self(Repo://Id), Context),
  query:search([category(C),name(N)], Repo://Id),
  !.


%! ranking:favour_signal(+Category, +Name, -Signal) is det.
%
% 1 for a --favour'd package, -1 for an --avoid'd one, 0 otherwise (or
% when both apply).

ranking:favour_signal(C, N, Signal) :-
  atomic_list_concat([C, '/', N], CN),
  ranking:yes_no(( config:dep_favour(CN) ; config:dep_favour(N) ), Fav),
  ranking:yes_no(( config:dep_avoid(CN)  ; config:dep_avoid(N)  ), Avoid),
  ranking:favour_signal_(Fav, Avoid, Signal).

ranking:favour_signal_(yes, no,  1).
ranking:favour_signal_(no,  yes, -1).
ranking:favour_signal_(yes, yes, 0).
ranking:favour_signal_(no,  no,  0).


%! ranking:required_use_target(+Dep, -Target) is det.
%
% USE_EXPAND target key of a `required(Use)` / `required(minus(Use))`
% arm (use_expand_target_key/2), `none` for every other arm.

ranking:required_use_target(required(minus(Use)), Target) :-
  !,
  ranking:use_expand_target_key(Use, Target).
ranking:required_use_target(required(Use), Target) :-
  !,
  ranking:use_expand_target_key(Use, Target).
ranking:required_use_target(_, none).


%! ranking:use_expand_target_key(+Use, -Key) is det.
%
% Version key of a USE_EXPAND target/slot flag, so that when a choice
% group offers several single-target alternatives and the profile has
% NOT forced one, the newest target/slot is preferred -- mirroring
% emerge's "highest available slot" behaviour. `none` when Use is not a
% USE_EXPAND flag or carries no digits.
%
% Generic across every USE_EXPAND family registered in eapi:use_expand/1
% (llvm_slot, lua_single_target, python_single_target, ruby_targets, ...):
% the family prefix is stripped and the remaining digit groups form the
% key, e.g. llvm_slot_20 -> [20], lua_single_target_lua5-4 -> [5,4],
% python_single_target_python3_13 -> [3,13]; lua_single_target_luajit ->
% none. Profile-selected targets are handled separately by
% is_preferred_dep/2 (the Preferred signal of pref/6), which always
% dominates this tiebreaker.

ranking:use_expand_target_key(Use, Key) :-
  atom(Use),
  preference:use_expand_env(_EnvVar, Prefix),
  atom_concat(Prefix, '_', PrefixU),
  atom_concat(PrefixU, Value, Use),
  Value \== '',
  ranking:version_key(Value, Key),
  !.
ranking:use_expand_target_key(_, none).


% -----------------------------------------------------------------------------
%  Version keys for slots and USE_EXPAND targets
% -----------------------------------------------------------------------------

%! ranking:version_key(+Atomic, -Key) is semidet.
%
% Key is the list of maximal decimal-digit runs in Atomic, e.g. '3.10' ->
% [3,10], 'python3_13' -> [3,13], 'lua5-4' -> [5,4], 20 -> [20]. Lists of
% integers compare component-wise in the standard order of terms, so
% [3,10] @> [3,3] and [20] @> [19] -- newer is larger without packing the
% components into one integer (and without atom_number/2 reading '3.10'
% as 3.1). Fails when Atomic carries no digits ('luajit').

ranking:version_key(Atomic, Key) :-
  atomic(Atomic),
  atom_codes(Atomic, Codes),
  ranking:digit_groups(Codes, Key),
  Key \== [].


%! ranking:digit_groups(+Codes, -Groups) is det.
%
% Extracts the maximal runs of decimal digits in Codes as integers, in
% left-to-right order. e.g. "python3_13" -> [3,13], "lua5-4" -> [5,4],
% "20" -> [20], "luajit" -> [].

ranking:digit_groups([], []) :- !.
ranking:digit_groups(Codes, [N|Rest]) :-
  ranking:take_digits(Codes, DigitCodes, Codes1),
  DigitCodes \== [],
  !,
  number_codes(N, DigitCodes),
  ranking:digit_groups(Codes1, Rest).
ranking:digit_groups([_|Codes], Rest) :-
  ranking:digit_groups(Codes, Rest).


%! ranking:take_digits(+Codes, -DigitCodes, -Rest) is det.

ranking:take_digits([C|Cs], [C|Ds], Rest) :-
  code_type(C, digit),
  !,
  ranking:take_digits(Cs, Ds, Rest).
ranking:take_digits(Cs, [], Cs).


% -----------------------------------------------------------------------------
%  Preferred arms (profile USE, installed satisfaction)
% -----------------------------------------------------------------------------

%! ranking:is_preferred_dep(+Context, +Dep)
%
% True if a dependency is "preferred" based on USE flags, installed
% status, or all_of_group member satisfaction.

ranking:is_preferred_dep(_Context, use_conditional_group(positive, Use, RepoEntry, _Deps)) :-
  Use \= minus(_),
  RepoEntry = _Repo://_Id,
  use:effective_use_for_entry(RepoEntry, Use, positive),
  !.
ranking:is_preferred_dep(_Context, use_conditional_group(negative, Use, RepoEntry, _Deps)) :-
  Use \= minus(_),
  RepoEntry = _Repo://_Id,
  use:effective_use_for_entry(RepoEntry, Use, negative),
  !.

ranking:is_preferred_dep(Context, required(Use)) :-
  Use \= minus(_),
  ( preference:global_use(Use)
  ; use:effective_use_in_context(Context, Use, positive)
  ),
  !.
ranking:is_preferred_dep(Context, required(minus(Use))) :-
  ( preference:global_use(minus(Use))
  ; use:effective_use_in_context(Context, Use, negative)
  ),
  !.

ranking:is_preferred_dep(Context, all_of_group(Deps)) :-
  Deps \= [],
  forall(member(D, Deps), group_member_preferred(Context, D)),
  !.

ranking:is_preferred_dep(_Context, package_dependency(_Phase,_Strength,C,N,O,V,_S,_U)) :-
  knowledgebase:vdb_repository(VdbRepo),
  query:search([name(N),category(C),installed(true)], VdbRepo://Installed),
  ( O == none ; query:search(select(version, O, V), VdbRepo://Installed) ),
  !.


% -----------------------------------------------------------------------------
%  USE_EXPAND profile-match scoring for any_of_group ranking
% -----------------------------------------------------------------------------

%! ranking:dep_use_expand_profile_score(+Dep, -Score) is det.
%
% Scores how well a dep's USE_EXPAND USE-deps (e.g.
% [python_targets_python3_13(-)]) align with the active profile's
% USE_EXPAND selection (e.g. PYTHON_TARGETS="python3_13").
%
% Used as a tiebreaker in any_of_group / choice_group ranking so that
% portage-ng mirrors emerge's behaviour: prefer the alternative whose
% USE_EXPAND requirements are already satisfied by the profile defaults.
% Without this signal, branches with equal LicOk/Rank/Overlap/Snap fall
% back to left-to-right order and often pick a non-default Python (or
% Ruby/PHP/etc.) target slot, forcing rebuilds of build-helpers like
% python-gnupg, setuptools, gpep517 with the wrong PYTHON_TARGETS.
%
% Each matching USE_EXPAND USE-dep contributes +1; each mismatching
% one contributes -1; non-USE_EXPAND USE-deps contribute 0. The score
% recurses into all_of_group and use_conditional_group members; nested
% any_of_group takes the maximum branch score.

ranking:dep_use_expand_profile_score(Dep, Score) :-
  catch(ranking:use_expand_score(Dep, Score), _, Score = 0).


ranking:use_expand_score(package_dependency(_,_,_,_,_,_,_,U), Score) :-
  is_list(U),
  !,
  ranking:use_expand_score_list(U, 0, Score).
ranking:use_expand_score(all_of_group(Deps), Score) :-
  is_list(Deps),
  !,
  foldl(ranking:use_expand_score_acc, Deps, 0, Score).
ranking:use_expand_score(any_of_group(Deps), Score) :-
  is_list(Deps), Deps \== [],
  !,
  findall(S, ( member(D, Deps), ranking:use_expand_score(D, S) ), Scores),
  ( Scores == [] -> Score = 0 ; max_list(Scores, Score) ).
ranking:use_expand_score(use_conditional_group(_,_,_,Deps), Score) :-
  is_list(Deps),
  !,
  foldl(ranking:use_expand_score_acc, Deps, 0, Score).
ranking:use_expand_score(_, 0).


ranking:use_expand_score_acc(D, Acc0, Acc) :-
  ranking:use_expand_score(D, S),
  Acc is Acc0 + S.


ranking:use_expand_score_list([], Acc, Acc).
ranking:use_expand_score_list([U|Rest], Acc0, Acc) :-
  ( ranking:use_dep_use_expand_signal(U, Sig)
  -> Acc1 is Acc0 + Sig
  ;  Acc1 = Acc0
  ),
  ranking:use_expand_score_list(Rest, Acc1, Acc).


%! ranking:use_dep_use_expand_signal(+UseDep, -Signal) is semidet.
%
% Returns +1 when the USE-dep is satisfied by the profile's USE_EXPAND
% selection, -1 when it conflicts. Fails for non-USE_EXPAND or
% inconclusive directives (treated as 0 by use_expand_score_list).

ranking:use_dep_use_expand_signal(use(enable(Flag), _), Sig) :-
  ranking:flag_is_use_expand(Flag),
  ( preference:global_use(Flag) -> Sig = 1 ; Sig = -1 ).
ranking:use_dep_use_expand_signal(use(optenable(Flag), _), Sig) :-
  ranking:flag_is_use_expand(Flag),
  ( preference:global_use(Flag) -> Sig = 1 ; Sig = -1 ).
ranking:use_dep_use_expand_signal(use(disable(Flag), _), Sig) :-
  ranking:flag_is_use_expand(Flag),
  ( preference:global_use(Flag) -> Sig = -1 ; Sig = 1 ).
ranking:use_dep_use_expand_signal(use(optdisable(Flag), _), Sig) :-
  ranking:flag_is_use_expand(Flag),
  ( preference:global_use(Flag) -> Sig = -1 ; Sig = 1 ).


%! ranking:flag_is_use_expand(+Flag) is semidet.
%
% True if Flag (e.g. python_targets_python3_13) starts with a known
% USE_EXPAND prefix from eapi:use_expand/1.

ranking:flag_is_use_expand(Flag) :-
  atom(Flag),
  preference:use_expand_env(_EnvVar, Prefix),
  atom_concat(Prefix, '_', PrefixUnderscore),
  atom_concat(PrefixUnderscore, _, Flag),
  !.


% -----------------------------------------------------------------------------
%  any_of_group preference helpers (installed satisfaction)
% -----------------------------------------------------------------------------

%! ranking:group_member_preferred(+Context, +PackageDep)
%
% True if a package_dependency member is "preferred" -- i.e. already
% installed or previously selected in the proof. Used by any_of_group
% rules to try installed alternatives first.

ranking:group_member_preferred(Context, package_dependency(Phase,Strength,C,N,O,V,S,U)) :-
  installed_pkg_satisfies_dep(Context, package_dependency(Phase,Strength,C,N,O,V,S,U)),
  !.
ranking:group_member_preferred(Context, use_conditional_group(positive, Use, RepoEntry, Deps)) :-
  is_preferred_dep(Context, use_conditional_group(positive, Use, RepoEntry, Deps)),
  !.
ranking:group_member_preferred(Context, use_conditional_group(negative, Use, RepoEntry, Deps)) :-
  is_preferred_dep(Context, use_conditional_group(negative, Use, RepoEntry, Deps)),
  !.
ranking:group_member_preferred(Context, all_of_group(Deps)) :-
  Deps \= [],
  forall(member(D, Deps), group_member_preferred(Context, D)),
  !.
ranking:group_member_preferred(_Context, _Other) :-
  fail.

%! ranking:installed_pkg_satisfies_dep(+ParentContext, +PackageDep)
%
% True if an installed package satisfies the version and USE requirements
% of the given package_dependency term. ParentContext is the ?{Context}
% list of the parent literal.

ranking:installed_pkg_satisfies_dep(ParentContext,
                             package_dependency(_Phase,_Strength,C,N,O,V,_S,UseReqs)) :-
  knowledgebase:vdb_repository(VdbRepo),
  query:search([name(N),category(C),installed(true)], VdbRepo://InstalledId),
  ( O == none
  ; query:search(select(version, O, V), VdbRepo://InstalledId)
  ),
  use:installed_pkg_satisfies_use_reqs(ParentContext, VdbRepo://InstalledId, UseReqs),
  !.

%! ranking:installed_version_mismatch(+PackageDep) is semidet.
%
% True when the package is installed but no installed version satisfies
% the atom's version constraint, i.e. choosing this arm forces an
% upgrade (the InstalledOk signal of pref/6).

ranking:installed_version_mismatch(package_dependency(_Phase,_Strength,C,N,O,V,_S,_U)) :-
  O \== none,
  knowledgebase:vdb_repository(VdbRepo),
  query:search([name(N),category(C),installed(true)], VdbRepo://_),
  \+ ( query:search([name(N),category(C),installed(true)], VdbRepo://InstalledId),
       query:search(select(version, O, V), VdbRepo://InstalledId)
     ),
  !.


% -----------------------------------------------------------------------------
%  Provider-reuse candidate reordering (Portage-like)
% -----------------------------------------------------------------------------

%! ranking:candidates_prefer_proven_providers(+C, +N, +SlotReq, +Candidates, -Reordered)
%
% For virtual packages: reorders candidates to prefer providers whose
% dependencies have already been proven in the current proof tree.
% Non-virtual packages pass through unchanged. This mirrors Portage's
% behaviour of preferring virtual providers that are already being
% installed as part of the dependency closure.

ranking:candidates_prefer_proven_providers(virtual, _N, SlotReq, Candidates, Reordered) :-
  SlotReq \= [slot(_)|_],
  include(candidate_has_proven_provider, Candidates, Preferred),
  Preferred \== [],
  !,
  subtract(Candidates, Preferred, Rest),
  append(Preferred, Rest, Reordered).
ranking:candidates_prefer_proven_providers(_C, _N, _SlotReq, Candidates, Candidates).

%! ranking:candidate_has_proven_provider(+RepoEntry)
%
% True if the candidate's RDEPEND references a (C,N) that has already
% been selected in the current proof.

ranking:candidate_has_proven_provider(Repo://Entry) :-
  cache:entry_metadata(Repo, Entry, rdepend, Dep),
  dep_references_selected_cn(Dep),
  !.

%! ranking:dep_references_selected_cn(+DepTerm)
%
% True if a dependency term references a (C,N) pair that has been
% selected in the current proof snapshot.

ranking:dep_references_selected_cn(package_dependency(_Phase,_Str,C,N,_O,_V,Ss,_U)) :-
  cnselect:snapshot_selected_cn_candidates(C, N, SelCandidates),
  ( Ss = [slot(ReqSlot0)|_] ->
      slotmeta:canon_slot(ReqSlot0, ReqSlot),
      member(SelRepo://SelEntry, SelCandidates),
      query:search(slot(SelSlotRaw), SelRepo://SelEntry),
      slotmeta:canon_slot(SelSlotRaw, SelSlot),
      ReqSlot == SelSlot
  ; true
  ),
  !.
ranking:dep_references_selected_cn(any_of_group(Deps)) :-
  member(D, Deps),
  dep_references_selected_cn(D),
  !.
