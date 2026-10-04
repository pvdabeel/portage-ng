/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> ANNOTATION
Single-pass proof traversal collecting printer annotations.

Printing one plan used to walk the proof AVL roughly ten times (blocker
notes, four pre-action sweeps, cycle-break injection, and the warning
suggestion collectors), each a fresh findall over assoc:gen_assoc, and
builder:build/0 triggered the pre-action sweeps a second time. This
module replaces those independent traversals with a single pass that
classifies every proof entry into a proof_annotations record consumed
by plan.pl, warning.pl and builder.pl.

The record is opaque to consumers; use the accessors below.
*/

:- module(annotation, []).

% =============================================================================
%  ANNOTATION declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Context unwrapping
% -----------------------------------------------------------------------------

%! annotation:unwrap_ctx(+Ctx0, -Ctx) is det.
%
% Extracts a plain list from a proof context (`?{Context}` list) term that
% may be wrapped in {}/1 or be the empty-context atom '{}'.

annotation:unwrap_ctx(Ctx0, Ctx) :-
  ( is_list(Ctx0) -> Ctx = Ctx0
  ; Ctx0 = {Inner}, is_list(Inner) -> Ctx = Inner
  ; Ctx = []
  ).


% -----------------------------------------------------------------------------
%  Single-pass collector
% -----------------------------------------------------------------------------

%! annotation:collect(+ProofAVL, -Annotations)
%
% Walks the proof AVL once and classifies every entry, producing an opaque
% proof_annotations record with the following (sorted) components:
%
% - Unmasks:           unmask(R, E, C, N) for proof entries tagged
%                      suggestion(unmask, _). Entries also tagged
%                      suggestion(accept_license, _) are excluded here;
%                      they appear under Licenses instead (the two tags
%                      are mutually exclusive per proof context in rules).
% - Licenses:          accept_license(R, E, C, N) for entries tagged
%                      suggestion(accept_license, _)
% - Keywords:          accept_keyword(R, E, C, N, K) for entries tagged
%                      suggestion(accept_keyword, K)
% - UseChanges:        use_change(R, E, C, N, Changes) for entries tagged
%                      suggestion(use_change, _, Changes)
% - BwuChanges:        use_change(R://E, Enables, Disables) — legacy
%                      build_with_use scan over proof-context-bearing keys
% - BlockerNotes:      assoc mapping key(C, N, Phase) -> note(Strength,
%                      Origin) for *effective* blocker domain assumptions
% - CycleBreaks:       cycle_break(Content, Value) for prover cycle-break
%                      assumptions (proof key assumed(rule(Content)))
% - DomainAssumptions: Content for domain assumptions (proof key
%                      rule(assumed(Content))), minus ineffective blockers
%                      and minus entry-level assumed :install/:run whose
%                      CN already has a concrete merge in the proof
%                      (live `9999` self-install leftovers)
%
% Blocker relevance: pass 1 records every weak blocker it walks past as
% `assumed(blocker(Strength, Phase, C, N, O, V, SlotReq))` because, mid
% proof, it cannot know which version of C/N the plan ends up with (that
% candidate may be selected later). The recorded atom is therefore a
% *candidate* assumption; only here, with the whole proof in hand, can it
% be evaluated against the packages it could actually hit. A blocker is
% effective (kept as assumption + inline note) exactly when its atom —
% operator, version, slot and sub-slot — matches a planned merge of C/N,
% or an installed copy of C/N that the plan leaves in place. Anything
% else (e.g. `!dev-ml/findlib:0/0` against a planned findlib 0/1, or
% `!<dev-util/ragel-7.0.3` against a planned 7.0.4) blocks nothing, so it
% is neither reported nor allowed to drive the CI exit code.

annotation:collect(ProofAVL, proof_annotations(Unmasks, Licenses, Keywords,
                                               UseChanges, BwuChanges,
                                               BlockerNotes, CycleBreaks,
                                               DomainAssumptions)) :-
  findall(Type-Term,
          ( assoc:gen_assoc(Key, ProofAVL, Value),
            annotation:proof_entry_tag(Key, Value, Type, Term)
          ),
          Tags),
  annotation:tagged(unmask,     Tags, Unmasks),
  annotation:tagged(license,    Tags, Licenses),
  annotation:tagged(keyword,    Tags, Keywords),
  annotation:tagged(usechange,  Tags, UseChanges),
  annotation:tagged(bwu,        Tags, BwuChanges),
  annotation:tagged(cyclebreak, Tags, CycleBreaks),
  annotation:tagged(domain,     Tags, DomainAssumptions0),
  annotation:tagged(blocker,    Tags, Blockers0),
  annotation:tagged(planned,    Tags, Planned),
  annotation:planned_index(Planned, PlannedIdx),
  partition(annotation:blocker_effective(PlannedIdx), Blockers0,
            Effective, Ineffective),
  findall(Content, member(blk(Content,_,_,_,_,_,_,_,_), Ineffective), Dropped0),
  findall(Content,
          ( member(Content, DomainAssumptions0),
            annotation:assumed_entry_covered(PlannedIdx, Content)
          ),
          Covered0),
  append(Dropped0, Covered0, Dropped1),
  sort(Dropped1, Dropped),
  ord_subtract(DomainAssumptions0, Dropped, DomainAssumptions),
  findall(key(C,N,Phase)-note(Strength,Origin),
          member(blk(_,Strength,Phase,C,N,_,_,_,Origin), Effective),
          BlockerPairs),
  empty_assoc(Empty),
  foldl(annotation:blocker_note_put, BlockerPairs, Empty, BlockerNotes).


%! annotation:tagged(+Type, +Tags, -Sorted)
%
% Extracts all terms of a given tag type from the classified tag list,
% sorted and deduplicated.

annotation:tagged(Type, Tags, Sorted) :-
  findall(Term, member(Type-Term, Tags), Terms),
  sort(Terms, Sorted).


%! annotation:proof_entry_tag(+Key, +Value, -Type, -Term) is nondet.
%
% Classifies a single proof entry. An entry may yield multiple tags
% (e.g. a domain assumption that is also a blocker, or a resolved entry
% carrying both keyword and USE-change suggestions).

% Domain assumptions (proof key rule(assumed(Content))) — also checked
% for blocker shape to feed the blocker note map.
annotation:proof_entry_tag(rule(assumed(Content)), _Value, Type, Term) :-
  !,
  ( Type = domain,
    Term = Content
  ; annotation:blocker_assumption_term(Content, Strength, Phase, C, N,
                                       O, V, SlotReq, Origin),
    Type = blocker,
    Term = blk(Content, Strength, Phase, C, N, O, V, SlotReq, Origin)
  ).
% Prover cycle-break assumptions (proof key assumed(rule(Content))).
annotation:proof_entry_tag(assumed(rule(Content)), Value, cyclebreak,
                           cycle_break(Content, Value)) :- !.
% Fully resolved entries: suggestion tags live in the value context. The
% self-target's own unmask / keyword / license tags ride on its :install
% carrier (:run path) or a synthetic :annotate carrier (:fetchonly path,
% see resolving.pl), so the collector never needs to re-derive them from the
% mask state — it just reads whatever the resolver placed in the context.
% Merge-family and unmerge actions are additionally tagged `planned` so
% blocker atoms can be evaluated against what the plan does to their CN.
annotation:proof_entry_tag(rule(R://E:Action), _?Ctx0, Type, Term) :-
  !,
  ( annotation:unwrap_ctx(Ctx0, Ctx),
    annotation:suggestion_tag(Ctx, R, E, Type, Term)
  ; memberchk(Action, [install, update, downgrade, reinstall, uninstall]),
    cache:ordered_entry(R, E, C, N, _),
    Type = planned,
    Term = planned(C, N, Action, R, E)
  ).
% Legacy build_with_use scan over context-bearing proof keys.
annotation:proof_entry_tag(Key, _Value, bwu, use_change(Entry, Enables, Disables)) :-
  annotation:proof_key_use_changes(Key, Entry, Enables, Disables),
  ( Enables \== [] ; Disables \== [] ).


%! annotation:suggestion_tag(+Ctx, +R, +E, -Type, -Term) is nondet.
%
% Yields one tag per suggestion(...) kind present in a resolved proof
% entry's context.

annotation:suggestion_tag(Ctx, R, E, unmask, unmask(R, E, C, N)) :-
  memberchk(suggestion(unmask, _), Ctx),
  \+ memberchk(suggestion(accept_license, _), Ctx),
  cache:ordered_entry(R, E, C, N, _).
annotation:suggestion_tag(Ctx, R, E, license, accept_license(R, E, C, N)) :-
  memberchk(suggestion(accept_license, _), Ctx),
  cache:ordered_entry(R, E, C, N, _).
annotation:suggestion_tag(Ctx, R, E, keyword, accept_keyword(R, E, C, N, K)) :-
  memberchk(suggestion(accept_keyword, K), Ctx),
  cache:ordered_entry(R, E, C, N, _).
annotation:suggestion_tag(Ctx, R, E, usechange, use_change(R, E, C, N, Changes)) :-
  memberchk(suggestion(use_change, _, Changes), Ctx),
  cache:ordered_entry(R, E, C, N, _).


% -----------------------------------------------------------------------------
%  Blocker note extraction
% -----------------------------------------------------------------------------

%! annotation:blocker_assumption_term(+Content, -Strength, -Phase, -C, -N, -O, -V, -SlotReq, -Origin)
%
% Destructures a blocker domain assumption (with or without proof context)
% into its atom components (operator, version, slot requirement) and the
% origin package that carries the blocker.

annotation:blocker_assumption_term(Content0, Strength, Phase, C, N, O, V, SlotReq, Origin) :-
  ( Content0 = '?'(blocker(Strength, Phase, C, N, O, V, SlotReq), Ctx0),
    annotation:unwrap_ctx(Ctx0, Ctx),
    ( memberchk(self(Origin), Ctx) -> true ; Origin = unknown )
  )
  ;
  ( Content0 = blocker(Strength, Phase, C, N, O, V, SlotReq),
    Origin = unknown
  ),
  ( Strength == weak ; Strength == strong ),
  ( Phase == install ; Phase == run ).


%! annotation:planned_index(+Planned, -Index)
%
% Groups planned(C, N, Action, R, E) tags into an assoc keyed by C-N whose
% values are lists of planned(Action, R, E).

annotation:planned_index(Planned, Index) :-
  findall(C-N, member(planned(C, N, _, _, _), Planned), CNs0),
  sort(CNs0, CNs),
  findall(CN-Actions,
          ( member(CN, CNs),
            CN = C-N,
            findall(planned(A, R, E), member(planned(C, N, A, R, E), Planned), Actions)
          ),
          Pairs),
  list_to_assoc(Pairs, Index).


%! annotation:assumed_entry_covered(+PlannedIndex, +Content) is semidet.
%
% True when Content is an assumed package :install or :run whose CN
% already has a concrete merge in the proof. Those leftovers sit next
% to the keyword-accepted live ebuild they failed to model a second
% time; reporting them would turn a successful plan into exit 2.

annotation:assumed_entry_covered(PlannedIdx, Content) :-
  prover:canon_literal(Content, Repo://Entry:Action, _),
  ( Action == install ; Action == run ),
  cache:ordered_entry(Repo, Entry, C, N, _),
  get_assoc(C-N, PlannedIdx, Planned),
  member(planned(A, _, _), Planned),
  memberchk(A, [install, update, downgrade, reinstall]).


%! annotation:blocker_effective(+PlannedIndex, +Blocker) is semidet.
%
% True when the blocker atom hits something: a planned merge of C/N, or an
% installed copy of C/N that no planned action of the same slot replaces
% or removes. Only such blockers are worth reporting (and only they count
% as domain assumptions for the exit code). Matching reuses the strong
% blocker enforcement core, candidate:blocker_spec_matches_selected/7, so
% both blocker strengths agree on what an atom hits.

annotation:blocker_effective(PlannedIdx, blk(_Content, _Strength, _Phase, C, N, O, V, SlotReq, _Origin)) :-
  ( get_assoc(C-N, PlannedIdx, Planned) -> true ; Planned = [] ),
  ( member(planned(Action, R, E), Planned),
    Action \== uninstall,
    annotation:blocker_matches_entry(R, E, O, V, SlotReq)
  -> true
  ; annotation:blocker_matches_installed(C, N, O, V, SlotReq, Planned)
  ).


%! annotation:blocker_matches_entry(+Repo, +Entry, +O, +V, +SlotReq) is semidet.
%
% True when the blocker atom (O, V, SlotReq) matches the version and slot
% metadata of Repo://Entry.  Errors are deliberately NOT caught here: this
% predicate decides whether a soft blocker counts as a domain assumption
% (exit code 2), so a defect in the matcher must surface rather than
% silently turn into "blocker not effective".

annotation:blocker_matches_entry(R, E, O, V, SlotReq) :-
  cache:ordered_entry(R, E, _, _, Ver),
  query:search(select(slot, constraint([]), SlotMeta), R://E),
  candidate:blocker_spec_matches_selected(Ver, SlotMeta, R, E, O, V, SlotReq),
  !.


%! annotation:blocker_matches_installed(+C, +N, +O, +V, +SlotReq, +Planned) is semidet.
%
% True when an installed copy of C/N matches the blocker atom and the plan
% leaves that copy in place (no merge-family or uninstall action of C/N
% in the same slot). A matching installed copy that the plan replaces
% with a non-matching version is resolved by the plan itself.

annotation:blocker_matches_installed(C, N, O, V, SlotReq, Planned) :-
  knowledgebase:vdb_repository(VdbRepo),
  query:search([name(N), category(C), installed(true)], VdbRepo://Inst),
  annotation:blocker_matches_entry(VdbRepo, Inst, O, V, SlotReq),
  \+ annotation:planned_touches_slot_of(Planned, VdbRepo://Inst),
  !.


%! annotation:planned_touches_slot_of(+Planned, +Installed) is semidet.
%
% True when some planned action of the same CN lives in the slot of the
% installed entry (it replaces or removes that copy).

annotation:planned_touches_slot_of(Planned, VdbRepo://Inst) :-
  annotation:entry_slot(VdbRepo, Inst, Slot),
  member(planned(_Action, R, E), Planned),
  annotation:entry_slot(R, E, Slot),
  !.


%! annotation:entry_slot(+Repo, +Entry, -Slot) is semidet.
%
% Canonical slot atom of Repo://Entry (default '0' when unset).

annotation:entry_slot(R, E, Slot) :-
  ( cache:entry_metadata(R, E, slot, slot(S0)) -> true ; S0 = '0' ),
  slotmeta:canon_slot(S0, Slot).


%! annotation:blocker_note_put(+Pair, +NotesIn, -NotesOut)
%
% Inserts a blocker note pair into the note assoc, keeping the first
% note seen for a given key.

annotation:blocker_note_put(K-V, In, Out) :-
  ( get_assoc(K, In, _) ->
      Out = In
  ; put_assoc(K, In, V, Out)
  ).


% -----------------------------------------------------------------------------
%  Legacy build_with_use key scan
% -----------------------------------------------------------------------------

%! annotation:proof_key_use_changes(+Key, -Entry, -NeedEnable, -NeedDisable)
%
% For a context-bearing proof key with build_with_use state, computes which
% USE flags need enabling or disabling relative to the effective USE set.

annotation:proof_key_use_changes(Repo://Id:_Action?{Ctx0}, Repo://Id,
                                 NeedEnable, NeedDisable) :-
  annotation:unwrap_ctx(Ctx0, Ctx),
  memberchk(build_with_use:use_state(En, Dis), Ctx),
  use:entry_effective_use_set(Repo://Id, EffEnabled),
  findall(U, ( member(U, En), \+ memberchk(U, EffEnabled) ), NeedEnable0),
  findall(U, ( member(U, Dis), memberchk(U, EffEnabled) ), NeedDisable0),
  sort(NeedEnable0, NeedEnable),
  sort(NeedDisable0, NeedDisable).


% -----------------------------------------------------------------------------
%  Accessors
% -----------------------------------------------------------------------------

%! annotation:unmasks(+Annotations, -Unmasks)
%
% Sorted list of unmask(R, E, C, N) terms.

annotation:unmasks(proof_annotations(U,_,_,_,_,_,_,_), U).


%! annotation:licenses(+Annotations, -Licenses)
%
% Sorted list of accept_license(R, E, C, N) terms.

annotation:licenses(proof_annotations(_,L,_,_,_,_,_,_), L).


%! annotation:keywords(+Annotations, -Keywords)
%
% Sorted list of accept_keyword(R, E, C, N, K) terms.

annotation:keywords(proof_annotations(_,_,K,_,_,_,_,_), K).


%! annotation:use_changes(+Annotations, -UseChanges)
%
% Sorted list of use_change(R, E, C, N, Changes) terms.

annotation:use_changes(proof_annotations(_,_,_,UC,_,_,_,_), UC).


%! annotation:bwu_changes(+Annotations, -BwuChanges)
%
% Sorted list of legacy use_change(R://E, Enables, Disables) terms.

annotation:bwu_changes(proof_annotations(_,_,_,_,B,_,_,_), B).


%! annotation:blocker_notes(+Annotations, -Notes)
%
% Assoc mapping key(C, N, Phase) -> note(Strength, Origin).

annotation:blocker_notes(proof_annotations(_,_,_,_,_,N,_,_), N).


%! annotation:domain_assumptions(+Annotations, -DomainAssumptions)
%
% Sorted list of domain assumption contents (proof key rule(assumed(X))).

annotation:domain_assumptions(proof_annotations(_,_,_,_,_,_,_,D), D).


%! annotation:cycle_break_contents(+Annotations, -Contents)
%
% Sorted list of prover cycle-break contents (proof key assumed(rule(X))).

annotation:cycle_break_contents(proof_annotations(_,_,_,_,_,_,CBs,_), Contents) :-
  findall(C, member(cycle_break(C, _), CBs), Contents).


%! annotation:cycle_break_rules(+Annotations, -Rules)
%
% Sorted list of full-format cycle-break rules, as injected into the first
% plan step by plan:inject_cycle_break_verifies/3.

annotation:cycle_break_rules(proof_annotations(_,_,_,_,_,_,CBs,_), Rules) :-
  findall(Rule,
          ( member(cycle_break(Content, Value), CBs),
            prover:canon_rule(Rule, assumed(rule(Content)), Value)
          ),
          Rules0),
  sort(Rules0, Rules).


%! annotation:pre_actions(+Annotations, -PreActions)
%
% Concatenated unmask / license / keyword / USE-change pre-plan actions,
% in the order the plan printer displays them.

annotation:pre_actions(Annotations, PreActions) :-
  annotation:unmasks(Annotations, Unmasks),
  annotation:licenses(Annotations, Licenses),
  annotation:keywords(Annotations, Keywords),
  annotation:use_changes(Annotations, UseChanges),
  append([Unmasks, Licenses, Keywords, UseChanges], PreActions).
