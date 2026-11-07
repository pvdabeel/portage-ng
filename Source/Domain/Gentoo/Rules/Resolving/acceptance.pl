/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> ACCEPTANCE
Keyword, mask, and license acceptance for the portage-ng resolver.

Split out of candidate.pl (issue #64). Contains license masking
(ACCEPT_LICENSE / package.license), keyword-aware candidate enumeration
(ACCEPT_KEYWORDS / package.accept_keywords, with memoized candidate
lists and slot locks), and the keyword helper predicates used by
eligibility checks and assumption suggestions.
*/

:- module(acceptance, []).

% =============================================================================
%  ACCEPTANCE declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  License masking (ACCEPT_LICENSE)
% -----------------------------------------------------------------------------

%! acceptance:license_masked(+RepoEntry)
%
% True if RepoEntry is masked due to an unaccepted license. Checks
% whether any license string from the entry's LICENSE metadata is
% rejected by `preference:accept_license/2`.

acceptance:license_masked(Repo://Entry) :-
  effective_license(Repo://Entry, Lic),
  \+ preference:license_accepted(Lic),
  \+ acceptance:package_license_accepted(Repo://Entry, Lic),
  !.


%! acceptance:package_license_accepted(+RepoEntry, +License) is semidet.
%
% True if License is accepted for RepoEntry via a per-package override
% in /etc/portage/package.license (loaded into userconfig:package_license_entry/2).

acceptance:package_license_accepted(Repo://Entry, Lic) :-
  hook:defined(userconfig:package_license_entry/2),
  query:search([category(C), name(N)], Repo://Entry),
  atomic_list_concat([C, N], '/', CatPkg),
  userconfig:package_license_entry(CatPkg, Lic).

%! acceptance:effective_license(+RepoEntry, -License)
%
% Enumerates the effective license atoms for an entry, resolving
% USE-conditional license groups against the entry's effective USE.

acceptance:effective_license(Repo://Entry, License) :-
  cache:entry_metadata(Repo, Entry, license, LicTerm),
  effective_license_term_(LicTerm, Repo://Entry, License).

acceptance:effective_license_term_(use_conditional_group(Pol, Use, _Self, Deps), RepoEntry, License) :-
  !,
  candidate:rdepend_self_use_conditional_active(Pol, Use, RepoEntry),
  member(D, Deps),
  effective_license_term_(D, RepoEntry, License).
acceptance:effective_license_term_(License, _RepoEntry, License) :-
  atom(License).

%! acceptance:dep_license_ok(+Dep)
%
% True if at least one visible, license-accepted candidate exists for
% the dependency's (C,N).

acceptance:dep_license_ok(package_dependency(_, _, C, N, _, _, _, _)) :- !,
  cache:ordered_entry(Repo, Entry, C, N, _),
  \+ preference:masked(Repo://Entry),
  \+ license_masked(Repo://Entry).
acceptance:dep_license_ok(grouped_package_dependency(_, C, N, _)) :- !,
  cache:ordered_entry(Repo, Entry, C, N, _),
  \+ preference:masked(Repo://Entry),
  \+ license_masked(Repo://Entry).
acceptance:dep_license_ok(_).


% -----------------------------------------------------------------------------
%  Keyword-aware candidate enumeration (Portage-like)
% -----------------------------------------------------------------------------

%! acceptance:accepted_keyword_candidate(+Action, +C, +N, +SlotReq, +SlotSet, +Context, -RepoEntry)
%
% Enumerates candidates for (C,N) respecting ACCEPT_KEYWORDS, slot locks,
% license masking, and the CN-domain reject map. Candidates are returned
% in keyword-priority order (stable first, then testing, then masked).
% Results are memoized per (Action, C, N, SlotReq, LockKey) in
% memo:keyword_cache_/6 to avoid repeated query/sort overhead.

acceptance:accepted_keyword_candidate(Action, C, N, SlotReq0, Ss0, Context, FoundRepo://Candidate) :-
  accepted_keyword_slot_lock_arg(C, N, SlotReq0, Ss0, Context, SlotReq, Ss, LockKey),
  ( preference:keyword_selection_mode(keyword_order) ->
      ( preference:accept_keywords(K)
      ; acceptance:package_keyword_entry(C, N, K)
      ),
      query_keyword_candidate(Action, C, N, K, Context, FoundRepo://Candidate),
      slotmeta:query_search_slot_constraint(SlotReq, FoundRepo://Candidate, Ss)
  ; ( Action \== run,
      memberchk(self(SelfRepo0://SelfEntry0), Context),
      query:search([category(C),name(N)], SelfRepo0://SelfEntry0)
    ->
      findall(FoundRepo0://Candidate0,
              ( ( preference:accept_keywords(K0)
                ; acceptance:package_keyword_entry(C, N, K0)
                ),
                query_keyword_candidate(Action, C, N, K0, Context, FoundRepo0://Candidate0),
                slotmeta:query_search_slot_constraint(SlotReq, FoundRepo0://Candidate0, Ss)
              ),
              Candidates0),
      Candidates0 \== [],
      sort(Candidates0, Candidates1),
      predsort(acceptance:compare_candidate_version_desc, Candidates1, CandidatesSorted),
      member(FoundRepo://Candidate, CandidatesSorted)
    ;
      accepted_keyword_candidates_cached(Action, C, N, SlotReq, LockKey, CandidatesSorted0),
      ranking:candidates_prefer_proven_providers(C, N, SlotReq, CandidatesSorted0, CandidatesSorted),
      member(FoundRepo://Candidate, CandidatesSorted),
      slotmeta:query_search_slot_constraint(SlotReq, FoundRepo://Candidate, Ss)
    )
  ).

% Fallback: when keyword_acceptance is active, accept candidates with any
% keyword that are not masked. This produces a full resolution (download +
% install + run) rather than a "verify" stub.
acceptance:accepted_keyword_candidate(Action, C, N, SlotReq0, Ss0, Context, FoundRepo://Candidate) :-
  prover:assuming(keyword_acceptance),
  accepted_keyword_slot_lock_arg(C, N, SlotReq0, Ss0, Context, SlotReq, Ss, _LockKey),
  findall(FoundRepo0://Candidate0,
          ( query_keyword_candidate_any(Action, C, N, Context, FoundRepo0://Candidate0),
            slotmeta:query_search_slot_constraint(SlotReq, FoundRepo0://Candidate0, Ss)
          ),
          Candidates0),
  Candidates0 \== [],
  sort(Candidates0, Candidates1),
  predsort(acceptance:compare_candidate_version_desc, Candidates1, CandidatesSorted),
  member(FoundRepo://Candidate, CandidatesSorted).

% Fallback: when unmask is active, accept masked candidates with accepted
% keywords. Produces a full resolution with an unmask suggestion.
acceptance:accepted_keyword_candidate(Action, C, N, SlotReq0, Ss0, Context, FoundRepo://Candidate) :-
  prover:assuming(unmask),
  accepted_keyword_slot_lock_arg(C, N, SlotReq0, Ss0, Context, SlotReq, Ss, _LockKey),
  findall(FoundRepo0://Candidate0,
          ( query_keyword_candidate_masked(Action, C, N, Context, FoundRepo0://Candidate0),
            slotmeta:query_search_slot_constraint(SlotReq, FoundRepo0://Candidate0, Ss)
          ),
          Candidates0),
  Candidates0 \== [],
  sort(Candidates0, Candidates1),
  predsort(acceptance:compare_candidate_version_desc, Candidates1, CandidatesSorted),
  member(FoundRepo://Candidate, CandidatesSorted).

%! acceptance:query_keyword_candidate_any(+Action, +C, +N, +Context, -RepoEntry)
%
% Like query_keyword_candidate but accepts any candidate regardless of
% keywords. Used when keyword_acceptance fallback is active.
%
% Binary-package repository entries are excluded: they carry no
% KEYWORDS (so only these keyword-relaxed clauses could ever surface
% them) and the resolver must not plan direct binpkg:// installs —
% binpkg consumption is the builder's optimization
% (binpkg_exec:available_for/4 substitutes a matching gpkg for a
% source entry at execution time; there is no standalone binpkg build
% strategy script).

acceptance:query_keyword_candidate_any(Action, C, N, Context, FoundRepo://Candidate) :-
  ( Action \== run,
    memberchk(self(SelfRepo0://SelfEntry0), Context),
    query:search([category(C),name(N)], SelfRepo0://SelfEntry0)
  ->
    query:search([name(N),category(C)], FoundRepo://Candidate),
    \+ acceptance:binpkg_repository(FoundRepo),
    \+ preference:masked(FoundRepo://Candidate),
    ( FoundRepo == SelfRepo0,
      Candidate == SelfEntry0
    ->
      \+ preference:flag(emptytree),
      query:search(installed(true), FoundRepo://Candidate)
    ; true
    )
  ; query:search([name(N),category(C)], FoundRepo://Candidate),
    \+ acceptance:binpkg_repository(FoundRepo),
    \+ preference:masked(FoundRepo://Candidate)
  ).

%! acceptance:query_keyword_candidate_masked(+Action, +C, +N, +Context, -RepoEntry)
%
% Accepts masked candidates with any keyword. Used when the unmask
% fallback is active to let masked packages through for full resolution.
% Binary-package repository entries are excluded (see
% query_keyword_candidate_any/5).

acceptance:query_keyword_candidate_masked(Action, C, N, Context, FoundRepo://Candidate) :-
  ( Action \== run,
    memberchk(self(SelfRepo0://SelfEntry0), Context),
    query:search([category(C),name(N)], SelfRepo0://SelfEntry0)
  ->
    query:search([name(N),category(C),keyword(_)], FoundRepo://Candidate),
    \+ acceptance:binpkg_repository(FoundRepo),
    ( FoundRepo == SelfRepo0,
      Candidate == SelfEntry0
    ->
      \+ preference:flag(emptytree),
      query:search(installed(true), FoundRepo://Candidate)
    ; true
    )
  ; query:search([name(N),category(C),keyword(_)], FoundRepo://Candidate),
    \+ acceptance:binpkg_repository(FoundRepo)
  ).

%! acceptance:binpkg_repository(+Repo) is semidet.
%
% True when Repo is the registered binary-package repository.

acceptance:binpkg_repository(binpkg).

%! acceptance:accepted_keyword_slot_lock_arg(+C, +N, +SlotReq0, +Ss0, +Context, -SlotReq, -Ss, -LockKey)
%
% Resolves slot lock arguments for keyword-aware candidate enumeration,
% incorporating context-level slot constraints.

acceptance:accepted_keyword_slot_lock_arg(C, N, SlotReq0, Ss0, Context, SlotReq, Ss, LockKey) :-
  ( memberchk(slot(C,N,SsCtx0):{_}, Context) ->
      slotmeta:canon_any_same_slot_meta(SsCtx0, SsCtx)
  ; SsCtx = _NoCtxLock
  ),
  ( SlotReq0 == [],
    nonvar(SsCtx)
  ->
    SlotReq1 = [any_same_slot]
  ; SlotReq1 = SlotReq0
  ),
  ( SlotReq1 == [any_same_slot] ->
      ( nonvar(Ss0) ->
          slotmeta:canon_any_same_slot_meta(Ss0, Ss1)
      ; nonvar(SsCtx) ->
          Ss1 = SsCtx
      ; Ss1 = _NoSlotLock
      ),
      SlotReq = [any_same_slot],
      Ss = Ss1
  ; SlotReq = SlotReq1,
    Ss = Ss0
  ),
  accepted_keyword_slot_lock_key(SlotReq, Ss, LockKey),
  !.

acceptance:accepted_keyword_slot_lock_key([any_same_slot], Ss, slot(S)) :-
  nonvar(Ss),
  slotmeta:canon_any_same_slot_meta(Ss, [slot(S)|_]),
  !.
acceptance:accepted_keyword_slot_lock_key(_SlotReq, _Ss, any) :-
  !.

acceptance:accepted_keyword_slot_lock_filter([any_same_slot], slot(S), [slot(S)]) :-
  !.
acceptance:accepted_keyword_slot_lock_filter(_SlotReq, _LockKey, _SsFilter) :-
  !.

%! acceptance:accepted_keyword_candidates_cached(+Action, +C, +N, +SlotReq, +LockKey, -CandidatesSorted)
%
% Returns memoized keyword-accepted candidates sorted by version descending.
% Builds and caches the result on first call for each (Action, C, N, SlotReq, LockKey).

acceptance:accepted_keyword_candidates_cached(Action, C, N, SlotReq, LockKey, CandidatesSorted) :-
  ( memo:keyword_cache_(Action, C, N, SlotReq, LockKey, CandidatesSorted) ->
    true
  ;
    accepted_keyword_slot_lock_filter(SlotReq, LockKey, SsFilter),
    findall(FoundRepo0://Candidate0,
            ( ( preference:accept_keywords(K0)
              ; acceptance:package_keyword_entry(C, N, K0)
              ),
              query_keyword_candidate(Action, C, N, K0, [], FoundRepo0://Candidate0),
              slotmeta:query_search_slot_constraint(SlotReq, FoundRepo0://Candidate0, SsFilter)
            ),
            Candidates0),
    Candidates0 \== [],
    sort(Candidates0, Candidates1),
    predsort(acceptance:compare_candidate_version_desc, Candidates1, CandidatesSorted),
    assertz(memo:keyword_cache_(Action, C, N, SlotReq, LockKey, CandidatesSorted))
  ).


%! acceptance:package_keyword_entry(+C, +N, -K) is nondet.
%
% Enumerate keyword terms accepted for C/N via per-package
% /etc/portage/package.accept_keywords overrides.

acceptance:package_keyword_entry(C, N, K) :-
  hook:defined(userconfig:package_keyword/2),
  userconfig:package_keyword(Spec, RawKW),
  acceptance:keyword_spec_matches(Spec, C, N, Repo),
  ( RawKW == '**'
  -> K = any(Repo)
  ; acceptance:raw_kw_to_term_(RawKW, K)
  ).


%! acceptance:keyword_spec_matches(+Spec, +C, +N, -Repo) is semidet.
%
% Splits `atom` or `atom::repo` and succeeds when atom covers C/N.
% Repo is unbound when Spec has no `::repo` suffix.

acceptance:keyword_spec_matches(Spec, C, N, Repo) :-
  (   sub_atom(Spec, B, 2, _, '::')
  ->  sub_atom(Spec, 0, B, _, Atom),
      After is B + 2,
      sub_atom(Spec, After, _, 0, Repo)
  ;   Atom = Spec
  ),
  (   Atom == '*/*'
  ;   atomic_list_concat([C, N], '/', Atom)
  ;   atomic_list_concat([C, '*'], '/', Atom)
  ),
  !.


acceptance:raw_kw_to_term_('**', any(*)) :- !.
acceptance:raw_kw_to_term_(RawKW, K) :-
  atom_codes(RawKW, Codes),
  catch(phrase(eapi:keywords([K]), Codes), _, fail).


%! acceptance:query_keyword_candidate(+Action, +C, +N, +Keyword, +Context, -RepoEntry)
%
% Enumerates unmasked candidates for (C,N) matching keyword K. Handles
% self-reference filtering when the parent is the same (C,N).
% `any(Repo)` comes from package.accept_keywords `**` (optionally
% `::repo`) and matches every unmasked candidate in that repository.

acceptance:query_keyword_candidate(Action, C, N, any(Repo), Context, FoundRepo://Candidate) :-
  !,
  query:search([name(N), category(C)], FoundRepo://Candidate),
  (var(Repo) -> true ; FoundRepo == Repo),
  \+ acceptance:binpkg_repository(FoundRepo),
  \+ preference:masked(FoundRepo://Candidate),
  acceptance:query_keyword_self_ok(Action, C, N, Context, FoundRepo://Candidate).

acceptance:query_keyword_candidate(Action, C, N, K, Context, FoundRepo://Candidate) :-
  ( Action \== run,
    memberchk(self(SelfRepo0://SelfEntry0), Context),
    query:search([category(C),name(N)], SelfRepo0://SelfEntry0)
  ->
    query:search([name(N),category(C),keyword(K)], FoundRepo://Candidate),
    \+ acceptance:binpkg_repository(FoundRepo),
    \+ preference:masked(FoundRepo://Candidate),
    ( FoundRepo == SelfRepo0,
      Candidate == SelfEntry0
    ->
      \+ preference:flag(emptytree),
      query:search(installed(true), FoundRepo://Candidate)
    ; true
    )
  ; query:search([name(N),category(C),keyword(K)], FoundRepo://Candidate),
    \+ acceptance:binpkg_repository(FoundRepo),
    \+ preference:masked(FoundRepo://Candidate)
  ).


%! acceptance:query_keyword_self_ok(+Action, +C, +N, +Context, +RepoEntry)
%
% When the parent of the proof is the same (C,N), only the installed
% copy is allowed (unless --emptytree). Same guard as the keyworded
% query_keyword_candidate clause.

acceptance:query_keyword_self_ok(Action, C, N, Context, FoundRepo://Candidate) :-
  Action \== run,
  memberchk(self(SelfRepo0://SelfEntry0), Context),
  query:search([category(C), name(N)], SelfRepo0://SelfEntry0),
  !,
  (   FoundRepo == SelfRepo0,
      Candidate == SelfEntry0
  ->  \+ preference:flag(emptytree),
      query:search(installed(true), FoundRepo://Candidate)
  ;   true
  ).
acceptance:query_keyword_self_ok(_Action, _C, _N, _Context, _RepoEntry).


%! acceptance:compare_candidate_version_desc(-Delta, +A, +B)
%
% Comparison predicate for predsort/3: orders candidates by version
% descending (newest first). Equal versions prefer the higher
% repository priority (and never compare as `=` across different
% Repo://Id pairs, so predsort/3 does not drop overlay copies).

acceptance:compare_candidate_version_desc(Delta, RepoA://IdA, RepoB://IdB) :-
  cache:ordered_entry(RepoA, IdA, _Ca, _Na, VerA),
  cache:ordered_entry(RepoB, IdB, _Cb, _Nb, VerB),
  ( eapi:version_compare(>, VerA, VerB) -> Delta = (<)
  ; eapi:version_compare(<, VerA, VerB) -> Delta = (>)
  ; acceptance:repository_priority(RepoA, PriA),
    acceptance:repository_priority(RepoB, PriB),
    ( PriA > PriB -> Delta = (<)
    ; PriA < PriB -> Delta = (>)
    ; compare(Delta, RepoA-IdA, RepoB-IdB)
    )
  ).


%! acceptance:repository_priority(+Repo, -Priority) is det.
%
% Portage repos.conf-style priority. Higher wins when two repositories
% provide the same CPV. Unlisted repositories default to 0.

acceptance:repository_priority(Repo, Priority) :-
  hook:defined(config:repository_priority/2),
  config:repository_priority(Repo, Priority),
  !.
acceptance:repository_priority(_Repo, 0).


%! acceptance:candidate_non_accepted_keyword(+RepoEntry, -NonAccKw) is semidet.
%
% Returns the most relevant non-accepted keyword on RepoEntry. Prefers a
% keyword matching the user's architecture (e.g. ~amd64 when the user
% accepts amd64). Falls back to ** when the package has no keyword for
% the user's arch at all, or has no keywords whatsoever.

acceptance:candidate_non_accepted_keyword(Repo://Entry, NonAccKw) :-
  \+ acceptance:entry_has_accepted_keyword(Repo://Entry),
  findall(K, preference:accept_keywords(K), AcceptedKs0),
  sort(AcceptedKs0, AcceptedKs),
  findall(NK,
          ( cache:entry_metadata(Repo, Entry, keywords, NK),
            \+ memberchk(NK, AcceptedKs)
          ),
          NonAccKws0),
  sort(NonAccKws0, NonAccKws),
  candidate_best_keyword_suggestion(AcceptedKs, NonAccKws, NonAccKw),
  !.


%! acceptance:candidate_best_keyword_suggestion(+AcceptedKs, +NonAccKws, -Best)
%
% Selects the most useful keyword suggestion. Prefers a keyword whose
% architecture matches the user's ACCEPT_KEYWORDS (e.g. unstable(amd64)
% for an amd64 user). Returns ** when no arch-relevant keyword exists.

acceptance:candidate_best_keyword_suggestion(AcceptedKs, NonAccKws, Best) :-
  NonAccKws \== [],
  findall(Arch,
          ( member(K, AcceptedKs),
            keyword_arch(K, Arch)
          ),
          Archs0),
  sort(Archs0, Archs),
  ( member(NK, NonAccKws),
    keyword_arch(NK, A),
    memberchk(A, Archs)
  ->
    Best = NK
  ;
    Best = '**'
  ),
  !.
acceptance:candidate_best_keyword_suggestion(_AcceptedKs, [], '**').


%! acceptance:keyword_arch(+Keyword, -Arch)
%
% Extracts the architecture atom from a keyword term.

acceptance:keyword_arch(stable(Arch), Arch).
acceptance:keyword_arch(unstable(Arch), Arch).


% -----------------------------------------------------------------------------
%  Keyword helpers
% -----------------------------------------------------------------------------

%! acceptance:entry_has_keyword(+RepoEntry)
%
% True if the entry has any keyword metadata at all.

acceptance:entry_has_keyword(Repo://Entry) :-
  query:search(keyword(_), Repo://Entry),
  !.


%! acceptance:entry_has_accepted_keyword(+RepoEntry)
%
% True if the entry has at least one keyword in ACCEPT_KEYWORDS or
% is accepted via per-package /etc/portage/package.accept_keywords.
% `**` (optionally `::repo`) accepts live ebuilds with empty KEYWORDS.

acceptance:entry_has_accepted_keyword(Repo://Entry) :-
  preference:accept_keywords(K),
  query:search(keyword(K), Repo://Entry),
  !.
acceptance:entry_has_accepted_keyword(Repo://Entry) :-
  query:search([category(C), name(N)], Repo://Entry),
  cache:entry_metadata(Repo, Entry, keywords, K),
  preference:package_keyword_accepted(C, N, K),
  !.
acceptance:entry_has_accepted_keyword(Repo://Entry) :-
  query:search([category(C), name(N)], Repo://Entry),
  acceptance:package_keyword_entry(C, N, any(RepoK)),
  ( var(RepoK) -> true ; Repo == RepoK ),
  !.


%! acceptance:entry_is_keyword_filtered(+RepoEntry)
%
% True if the entry has keyword metadata but none match ACCEPT_KEYWORDS.

acceptance:entry_is_keyword_filtered(Repo://Entry) :-
  acceptance:entry_has_keyword(Repo://Entry),
  \+ acceptance:entry_has_accepted_keyword(Repo://Entry).


%! acceptance:entry_needs_keyword_acceptance(+RepoEntry)
%
% True if the entry should be rejected in strict mode.

acceptance:entry_needs_keyword_acceptance(Repo://Entry) :-
  acceptance:entry_is_keyword_filtered(Repo://Entry),
  !.
acceptance:entry_needs_keyword_acceptance(Repo://Entry) :-
  \+ acceptance:entry_has_keyword(Repo://Entry),
  \+ query:search(slot(_), Repo://Entry).
