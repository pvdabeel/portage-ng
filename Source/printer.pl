/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> PRINTER
The Printer takes a plan from the Planner and pretty prints it.
*/

:- module(printer, []).

% =============================================================================
%  PRINTER declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Test statistics (cross-test summary)
% -----------------------------------------------------------------------------

:- dynamic printer:test_stats_stat/2.
:- dynamic printer:test_stats_type/3.
:- dynamic printer:test_stats_cycle_mention/3.
:- dynamic printer:test_stats_entry_had_cycle/1.
:- dynamic printer:test_stats_other_head/2.
:- dynamic printer:test_stats_pkg/3.
:- dynamic printer:test_stats_type_entry_mention/3.
:- dynamic printer:test_stats_entry_time/2.
:- dynamic printer:test_stats_pkg_time/5.
:- dynamic printer:test_stats_entry_cost/4.      % RepoEntry, TimeMs, Inferences, RuleCalls
:- dynamic printer:test_stats_pkg_cost/6.        % C, N, SumMs, SumInf, SumRuleCalls, Cnt
:- dynamic printer:test_stats_entry_ctx/5.       % RepoEntry, UnionCalls, UnionCost, MaxCtxLen, UnionMsEst
:- dynamic printer:test_stats_pkg_ctx/6.         % C, N, SumUnionCost, MaxCtxLen, SumUnionMsEst, Cnt
:- dynamic printer:test_stats_ctx_len_bin/2.     % CtxLen, Count (sampled)
:- dynamic printer:test_stats_ctx_cost_model/3.  % SumMul, SumAdd, Samples (sampled)
:- dynamic printer:test_stats_failed_entry/2.    % RepoEntry, Reason
:- dynamic printer:test_stats_blocker_sp/3.      % Strength, Phase, Count
:- dynamic printer:test_stats_blocker_cn/3.      % C, N, Count
:- dynamic printer:test_stats_blocker_example/1. % Example term that failed to parse for breakdown
:- dynamic printer:test_stats_blocker_reason/2.  % Reason, Count
:- dynamic printer:test_stats_blocker_rp/3.      % Reason, Phase, Count

printer:test_stats_reset(Label, ExpectedTotal) :-
  with_mutex(test_stats,
    ( retractall(printer:test_stats_stat(_,_)),
      retractall(printer:test_stats_type(_,_,_)),
      retractall(printer:test_stats_cycle_mention(_,_,_)),
      retractall(printer:test_stats_entry_had_cycle(_)),
      retractall(printer:test_stats_entry_time(_,_)),
      retractall(printer:test_stats_pkg_time(_,_,_,_,_)),
      retractall(printer:test_stats_entry_cost(_,_,_,_)),
      retractall(printer:test_stats_pkg_cost(_,_,_,_,_,_)),
      retractall(printer:test_stats_entry_ctx(_,_,_,_,_)),
      retractall(printer:test_stats_pkg_ctx(_,_,_,_,_,_)),
      retractall(printer:test_stats_ctx_len_bin(_,_)),
      retractall(printer:test_stats_ctx_cost_model(_,_,_)),
      retractall(printer:test_stats_failed_entry(_,_)),
      retractall(printer:test_stats_blocker_sp(_,_,_)),
      retractall(printer:test_stats_blocker_cn(_,_,_)),
      retractall(printer:test_stats_blocker_example(_)),
      retractall(printer:test_stats_blocker_reason(_,_)),
      retractall(printer:test_stats_blocker_rp(_,_,_)),
      retractall(printer:test_stats_other_head(_,_)),
      retractall(printer:test_stats_pkg(_,_,_)),
      retractall(printer:test_stats_type_entry_mention(_,_,_)),
      assertz(printer:test_stats_stat(label, Label)),
      assertz(printer:test_stats_stat(expected_total, ExpectedTotal)),
      assertz(printer:test_stats_stat(expected_unique_packages, 0)),
      assertz(printer:test_stats_stat(processed, 0)),
      assertz(printer:test_stats_stat(entries_failed, 0)),
      assertz(printer:test_stats_stat(entries_failed_blocker, 0)),
      assertz(printer:test_stats_stat(entries_failed_timeout, 0)),
      assertz(printer:test_stats_stat(entries_failed_other, 0)),
      assertz(printer:test_stats_stat(entries_with_assumptions, 0)),
      assertz(printer:test_stats_stat(entries_with_package_assumptions, 0)),
      assertz(printer:test_stats_stat(entries_with_cycles, 0)),
      assertz(printer:test_stats_stat(cycles_found, 0))
    )).

% Record that an entry did not produce a strict proof/plan.
% Reason is one of: blocker | other.
printer:test_stats_record_failed(Reason) :-
  printer:test_stats_inc(entries_failed),
  ( Reason == blocker ->
      printer:test_stats_inc(entries_failed_blocker)
  ; Reason == timeout ->
      printer:test_stats_inc(entries_failed_timeout)
  ; printer:test_stats_inc(entries_failed_other)
  ).

% Record a failed entry (Repo://Entry) with a reason, so we can do per-package
% analysis like "failed entry but another version of same package succeeded".
printer:test_stats_record_failed_entry(RepoEntry, Reason) :-
  with_mutex(test_stats,
    ( assertz(printer:test_stats_failed_entry(RepoEntry, Reason))
    )).

printer:test_stats_set_expected_unique_packages(N) :-
  with_mutex(test_stats,
    ( retractall(printer:test_stats_stat(expected_unique_packages,_)),
      assertz(printer:test_stats_stat(expected_unique_packages, N))
    )).

printer:test_stats_add_pkg(Bucket, Repo, Entry) :-
  ( cache:ordered_entry(Repo, Entry, C, N, _) ->
      with_mutex(test_stats,
        ( printer:test_stats_pkg(Bucket, C, N) -> true
        ; assertz(printer:test_stats_pkg(Bucket, C, N))
        ))
  ; true
  ).

printer:test_stats_unique_pkg_count(Bucket, Count) :-
  findall(C-N, printer:test_stats_pkg(Bucket, C, N), Pairs0),
  sort(Pairs0, Pairs),
  length(Pairs, Count).

printer:test_stats_set_current_entry(RepositoryEntry) :-
  nb_setval(test_stats_current_entry, RepositoryEntry).

printer:test_stats_clear_current_entry :-
  ( nb_current(test_stats_current_entry, _) ->
      nb_delete(test_stats_current_entry)
  ; true
  ).

printer:test_stats_inc(Key) :-
  with_mutex(test_stats,
    ( ( retract(printer:test_stats_stat(Key, N0)) -> true ; N0 = 0 ),
      N is N0 + 1,
      assertz(printer:test_stats_stat(Key, N))
    )).

printer:test_stats_inc_type(Type, Metric, Delta) :-
  with_mutex(test_stats,
    ( ( retract(printer:test_stats_type(Type, Metric, N0)) -> true ; N0 = 0 ),
      N is N0 + Delta,
      assertz(printer:test_stats_type(Type, Metric, N))
    )).

printer:test_stats_inc_cycle_mention(Action, RepoEntry) :-
  with_mutex(test_stats,
    ( ( retract(printer:test_stats_cycle_mention(Action, RepoEntry, N0)) -> true ; N0 = 0 ),
      N is N0 + 1,
      assertz(printer:test_stats_cycle_mention(Action, RepoEntry, N))
    )).

% Record elapsed walltime (ms) for a processed entry.
printer:test_stats_record_time(RepoEntry, TimeMs) :-
  integer(TimeMs),
  TimeMs >= 0,
  ( RepoEntry = Repo0://Entry0,
    cache:ordered_entry(Repo0, Entry0, C, N, _)
  -> true
  ; C = _, N = _
  ),
  with_mutex(test_stats,
    ( % Per-entry timing (keep max if recorded twice)
      ( retract(printer:test_stats_entry_time(RepoEntry, OldMs)) ->
          EntryMaxMs is max(OldMs, TimeMs)
      ;   EntryMaxMs = TimeMs
      ),
      assertz(printer:test_stats_entry_time(RepoEntry, EntryMaxMs)),

      % Per-package timing (C/N), only if we could extract C/N
      ( nonvar(C), nonvar(N) ->
          ( retract(printer:test_stats_pkg_time(C, N, Sum0, Max0, Cnt0)) ->
              true
          ;   Sum0 = 0, Max0 = 0, Cnt0 = 0
          ),
          Sum is Sum0 + TimeMs,
          Max is max(Max0, TimeMs),
          Cnt is Cnt0 + 1,
          assertz(printer:test_stats_pkg_time(C, N, Sum, Max, Cnt))
      ; true
      )
    )).

% Record elapsed walltime (ms) as well as cheap per-proof counters for a processed entry.
printer:test_stats_record_costs(RepoEntry, TimeMs, Inferences, RuleCalls) :-
  printer:test_stats_record_time(RepoEntry, TimeMs),
  integer(Inferences),
  Inferences >= 0,
  integer(RuleCalls),
  RuleCalls >= 0,
  ( RepoEntry = Repo0://Entry0,
    cache:ordered_entry(Repo0, Entry0, C, N, _)
  -> true
  ; C = _, N = _
  ),
  with_mutex(test_stats,
    ( % Per-entry cost snapshot (keep max of each)
      ( retract(printer:test_stats_entry_cost(RepoEntry, OldMs, OldInf, OldRule)) ->
          KeepMs is max(OldMs, TimeMs),
          KeepInf is max(OldInf, Inferences),
          KeepRule is max(OldRule, RuleCalls)
      ;   KeepMs = TimeMs,
          KeepInf = Inferences,
          KeepRule = RuleCalls
      ),
      assertz(printer:test_stats_entry_cost(RepoEntry, KeepMs, KeepInf, KeepRule)),

      % Per-package cost aggregation (sum counters)
      ( nonvar(C), nonvar(N) ->
          ( retract(printer:test_stats_pkg_cost(C, N, Ms0, Inf0, Rule0, Cnt0)) ->
              true
          ;   Ms0 = 0, Inf0 = 0, Rule0 = 0, Cnt0 = 0
          ),
          Ms1 is Ms0 + TimeMs,
          Inf1 is Inf0 + Inferences,
          Rule1 is Rule0 + RuleCalls,
          Cnt1 is Cnt0 + 1,
          assertz(printer:test_stats_pkg_cost(C, N, Ms1, Inf1, Rule1, Cnt1))
      ; true
      )
    )).

% Record context-list costs for a processed entry.
% Backwards-compatible wrapper (older callers)
printer:test_stats_record_context_costs(RepoEntry, UnionCalls, UnionCost, MaxCtxLen) :-
  printer:test_stats_record_context_costs(RepoEntry, UnionCalls, UnionCost, MaxCtxLen, 0).

printer:test_stats_record_context_costs(RepoEntry, UnionCalls, UnionCost, MaxCtxLen, UnionMsEst) :-
  integer(UnionCalls),
  UnionCalls >= 0,
  integer(UnionCost),
  UnionCost >= 0,
  integer(MaxCtxLen),
  MaxCtxLen >= 0,
  integer(UnionMsEst),
  UnionMsEst >= 0,
  ( RepoEntry = Repo0://Entry0,
    cache:ordered_entry(Repo0, Entry0, C, N, _)
  -> true
  ; C = _, N = _
  ),
  with_mutex(test_stats,
    ( ( retract(printer:test_stats_entry_ctx(RepoEntry, OldCalls, OldCost, OldMax, OldMs)) ->
          Calls1 is max(OldCalls, UnionCalls),
          Cost1 is max(OldCost, UnionCost),
          Max1 is max(OldMax, MaxCtxLen),
          Ms1 is max(OldMs, UnionMsEst)
      ;   Calls1 = UnionCalls,
          Cost1 = UnionCost,
          Max1 = MaxCtxLen,
          Ms1 = UnionMsEst
      ),
      assertz(printer:test_stats_entry_ctx(RepoEntry, Calls1, Cost1, Max1, Ms1)),
      ( nonvar(C), nonvar(N) ->
          ( retract(printer:test_stats_pkg_ctx(C, N, Sum0, Max0, SumMs0, Cnt0)) -> true
          ; Sum0 = 0, Max0 = 0, SumMs0 = 0, Cnt0 = 0
          ),
          Sum1 is Sum0 + UnionCost,
          Max2 is max(Max0, MaxCtxLen),
          SumMs1 is SumMs0 + UnionMsEst,
          Cnt1 is Cnt0 + 1,
          assertz(printer:test_stats_pkg_ctx(C, N, Sum1, Max2, SumMs1, Cnt1))
      ; true
      )
    )).

% Record global (run-wide) histogram of context lengths (sampled) and
% cost-model inputs for estimating ordset gains.
%
% HistPairs: list of Len-Count for this entry (sampled unions only).
% SumMul:    sum(L0*L1) across sampled unions for this entry.
% SumAdd:    sum(L0+L1) across sampled unions for this entry.
% Samples:   number of sampled unions (same sampling as union walltime).
printer:test_stats_record_ctx_len_distribution(HistPairs, SumMul, SumAdd, Samples) :-
  with_mutex(test_stats,
    ( forall(member(Len-Cnt, HistPairs),
             ( integer(Len), Len >= 0,
               integer(Cnt), Cnt >= 0,
               ( retract(printer:test_stats_ctx_len_bin(Len, Old)) ->
                   New is Old + Cnt
               ; New is Cnt
               ),
               assertz(printer:test_stats_ctx_len_bin(Len, New))
             )),
      ( integer(SumMul), SumMul >= 0,
        integer(SumAdd), SumAdd >= 0,
        integer(Samples), Samples >= 0 ->
          ( retract(printer:test_stats_ctx_cost_model(M0, A0, S0)) ->
              true
          ; M0 = 0, A0 = 0, S0 = 0
          ),
          M1 is M0 + SumMul,
          A1 is A0 + SumAdd,
          S1 is S0 + Samples,
          assertz(printer:test_stats_ctx_cost_model(M1, A1, S1))
      ; true
      )
    )).

printer:test_stats_inc_type_entry_mention(Type, RepoEntry) :-
  with_mutex(test_stats,
    ( ( retract(printer:test_stats_type_entry_mention(Type, RepoEntry, N0)) -> true ; N0 = 0 ),
      N is N0 + 1,
      assertz(printer:test_stats_type_entry_mention(Type, RepoEntry, N))
    )).

printer:test_stats_note_cycle_for_current_entry :-
  ( nb_current(test_stats_current_entry, RepoEntry) ->
      with_mutex(test_stats,
        ( printer:test_stats_entry_had_cycle(RepoEntry) ->
            true
        ; assertz(printer:test_stats_entry_had_cycle(RepoEntry)),
          ( retract(printer:test_stats_stat(entries_with_cycles, N0)) -> true ; N0 = 0 ),
          N is N0 + 1,
          assertz(printer:test_stats_stat(entries_with_cycles, N))
        ))
      ,
      ( RepoEntry = Repo://Entry -> printer:test_stats_add_pkg(with_cycles, Repo, Entry) ; true )
  ; true
  ).

% (moved to explainer.pl) assumption_content_from_proof_key/2
% (moved to explainer.pl) assumption_normalize/2

% Stats classification: distinguish real domain "non-existent" from prover cycle breaks.
% Unwrap Action?{Ctx} wrappers early so classification can match the underlying term.
printer:assumption_type('?'(Inner, _Ctx), Type) :-
  !,
  printer:assumption_type(Inner, Type).
printer:assumption_type(cycle_break(_), cycle_break) :- !.
% If we have a reason tag, use it (more specific than the legacy taxonomy).
printer:assumption_type(domain(X), Type) :-
  printer:assumption_reason_from_term(X, Reason),
  printer:assumption_reason_type(Reason, Type),
  !.
% Otherwise preserve existing assumption taxonomy by delegating domain(...) to
% the original classifier (masked/assumed_installed/assumed_running/etc.).
printer:assumption_type(domain(X), Type) :-
  printer:assumption_type(X, Type),
  !.
printer:assumption_type(domain(X), Type) :-
  % classify "no candidate found" reasons when present
  ( printer:assumption_reason_from_term(X, Reason) ->
      printer:assumption_reason_type(Reason, Type),
      !
  ; fail
  ).

printer:assumption_type(package_dependency(_,_,_,_,_,_,_,_):_, non_existent_dependency) :- !.
printer:assumption_type(grouped_package_dependency(_,_,_):_,              non_existent_dependency) :- !.
printer:assumption_type(grouped_package_dependency(_,_,_,_):_,            non_existent_dependency) :- !.
printer:assumption_type(_://_:unmask,                                      masked) :- !.
printer:assumption_type(_://_:install,                                     assumed_installed) :- !.
printer:assumption_type(_://_:run,                                         assumed_running) :- !.
printer:assumption_type(grouped_package_dependency(_,_,_,_):install?{_},   assumed_installed) :- !.
printer:assumption_type(grouped_package_dependency(_,_,_,_):run?{_},       assumed_running) :- !.
printer:assumption_type(grouped_package_dependency(_,_,_,_):install,       assumed_installed) :- !.
printer:assumption_type(grouped_package_dependency(_,_,_,_):run,           assumed_running) :- !.
% Blockers are domain assumptions (in fallback mode and/or for weak blockers).
printer:assumption_type(blocker(_Strength,_Phase,_C,_N,_O,_V,_SlotReq),     blocker_assumption) :- !.
% When a rule explicitly emits an "issue_with_model(...)" marker into its context,
% bucket this separately so it doesn't drown in "other".
printer:assumption_type(Term, issue_with_model) :-
  explainer:term_ctx(Term, Ctx),
  memberchk(issue_with_model(_), Ctx),
  !.
printer:assumption_type(required(_),                                        use_requirement_cycle) :- !.
printer:assumption_type(blocking(_),                                        use_requirement_cycle) :- !.
printer:assumption_type(use_conditional_group(_,_,_,_),                     use_conditional_cycle) :- !.
printer:assumption_type(any_of_group(_),                                    dependency_group_cycle) :- !.
printer:assumption_type(all_of_group(_),                                    dependency_group_cycle) :- !.
printer:assumption_type(exactly_one_of_group(_),                            dependency_group_cycle) :- !.
printer:assumption_type(at_most_one_of_group(_),                            dependency_group_cycle) :- !.
printer:assumption_type(naf(_),                                             naf_cycle) :- !.
printer:assumption_type(_,                                                 other).

printer:assumption_reason_from_term(Term, Reason) :-
  explainer:term_ctx(Term, Ctx),
  memberchk(assumption_reason(Reason), Ctx),
  !.

printer:assumption_reason_type(missing,                 missing_dependency).
printer:assumption_reason_type(masked,                  masked_dependency).
printer:assumption_reason_type(keyword_filtered,        keyword_filtered_dependency).
printer:assumption_reason_type(installed_required,      installed_required_dependency).
printer:assumption_reason_type(slot_unsatisfied,        slot_unsatisfied_dependency).
printer:assumption_reason_type(version_no_candidate(_,_), version_no_candidate_dependency).
printer:assumption_reason_type(version_conflict(_),       version_conflict_dependency).
printer:assumption_reason_type(version_no_candidate,    version_no_candidate_dependency).
printer:assumption_reason_type(version_conflict,        version_conflict_dependency).
% Backwards compatibility (older runs / saved contexts):
printer:assumption_reason_type(version_unsatisfied,     version_no_candidate_dependency).
printer:assumption_reason_type(unsatisfied_constraints, unsatisfied_constraints_dependency).

printer:assumption_is_package_level(_://_:install) :- !.
printer:assumption_is_package_level(_://_:run) :- !.
printer:assumption_is_package_level(_://_:fetchonly) :- !.
printer:assumption_is_package_level(_://_:unmask) :- !.
printer:assumption_is_package_level(grouped_package_dependency(_,_,_,_):_) :- !.
printer:assumption_is_package_level(package_dependency(_,_,_,_,_,_,_,_):_) :- !.

% Generate a stable "head key" for an assumption term, avoiding syntactic wrappers.
% This is used for the "Top other assumption heads" table.
printer:assumption_head_key(Content, Key) :-
  printer:assumption_head_term(Content, Head),
  ( atomic(Head) ->
      Key = Head
  ; Head =.. [F|Args],
    length(Args, A),
    format(atom(Key), '~w/~d', [F, A])
  ).

% Strip common wrappers:
% - Action?{Ctx} parses as '?'(ActionTerm, CtxTerm)
% - Module:Goal parses as ':'(Module, Goal)
% - Repo://Entry parses as '://'(Repo, Entry) and often appears under ':'(Repo://Entry, Action)
printer:assumption_head_term(Term0, Term) :-
  ( var(Term0) ->
      Term = Term0
  ; Term0 = '?'(Inner, _Ctx) ->
      printer:assumption_head_term(Inner, Term)
  ; Term0 = ':'(_M, Goal) ->
      printer:assumption_head_term(Goal, Term)
  ; Term0 = '://'(_Repo, Entry) ->
      printer:assumption_head_term(Entry, Term)
  ; Term0 =.. [_F, A] ->
      % Unwrap single-argument shells like domain(X), cycle_break(X) when they leak through.
      ( Term0 = domain(X)      -> printer:assumption_head_term(X, Term)
      ; Term0 = cycle_break(X) -> printer:assumption_head_term(X, Term)
      ; Term = Term0
      ),
      A = A
  ; Term = Term0
  ).

printer:test_stats_inc_other_head(Content) :-
  % Avoid counting wrapper functors (domain/1, cycle_break/1) as "other heads".
  ( Content = domain(X)      -> C1 = X
  ; Content = cycle_break(X) -> C1 = X
  ; C1 = Content
  ),
  printer:assumption_head_key(C1, Key),
  with_mutex(test_stats,
    ( ( retract(printer:test_stats_other_head(Key, N0)) -> true ; N0 = 0 ),
      N is N0 + 1,
      assertz(printer:test_stats_other_head(Key, N))
    )).

% Record detailed stats for a single blocker assumption (per-occurrence).
printer:test_stats_record_blocker_assumption(Content) :-
  % Assumptions are typically wrapped as domain(X) by the proof key normalization.
  ( Content = domain(X)      -> Content1 = X
  ; Content = cycle_break(X) -> Content1 = X
  ; Content1 = Content
  ),
  printer:collect_ctx_tags(Content1, Tags),
  printer:unwrap_ctx_wrappers(Content1, Core),
  % Blockers may appear as blocker(...)?{Ctx} or as blocker(...) (legacy/no ctx).
  ( Core = blocker(Strength, Phase, C, N, _O2, _V2, _SlotReq2) ->
      ( printer:test_stats_record_blocker_breakdown(Strength, Phase, C, N),
        ( memberchk(assumption_reason(Reason), Tags) -> true ; Reason = unknown ),
        printer:test_stats_inc_blocker_reason(Reason, Phase)
      )
  ; with_mutex(test_stats,
      ( printer:test_stats_blocker_example(_) ->
          true
      ; assertz(printer:test_stats_blocker_example(Content1))
      ))
  ).

% Some normalized assumptions can end up as nested ?/2 wrappers like:
%   (blocker(...)?{Ctx1})?{Ctx2}
% We only care about the core literal for breakdown purposes.
printer:unwrap_ctx_wrappers('?'(Inner, _Ctx), Core) :-
  !,
  printer:unwrap_ctx_wrappers(Inner, Core).
printer:unwrap_ctx_wrappers(Core, Core).

printer:test_stats_record_blocker_breakdown(Strength, Phase, C, N) :-
  with_mutex(test_stats,
    ( ( retract(printer:test_stats_blocker_sp(Strength, Phase, Nsp0)) -> true ; Nsp0 = 0 ),
      Nsp is Nsp0 + 1,
      assertz(printer:test_stats_blocker_sp(Strength, Phase, Nsp)),
      ( retract(printer:test_stats_blocker_cn(C, N, Ncn0)) -> true ; Ncn0 = 0 ),
      Ncn is Ncn0 + 1,
      assertz(printer:test_stats_blocker_cn(C, N, Ncn))
    )).

% Collect context tags from nested ?/2 wrappers.
% Some normalized assumptions look like: (blocker(...)?{Ctx1})?{{}}
printer:collect_ctx_tags('?'(Inner, Ctx0), Tags) :-
  !,
  printer:ctx_term_to_list(Ctx0, Tags0),
  printer:collect_ctx_tags(Inner, Tags1),
  append(Tags0, Tags1, Tags).
printer:collect_ctx_tags(_Other, []).

printer:ctx_term_to_list(Ctx0, Tags) :-
  ( is_list(Ctx0) ->
      Tags = Ctx0
  ; Ctx0 =.. ['{}'|Tags] ->
      true
  ; Tags = []
  ).

printer:test_stats_inc_blocker_reason(Reason, Phase) :-
  with_mutex(test_stats,
    ( ( retract(printer:test_stats_blocker_reason(Reason, N0)) -> true ; N0 = 0 ),
      N is N0 + 1,
      assertz(printer:test_stats_blocker_reason(Reason, N)),
      ( retract(printer:test_stats_blocker_rp(Reason, Phase, M0)) -> true ; M0 = 0 ),
      M is M0 + 1,
      assertz(printer:test_stats_blocker_rp(Reason, Phase, M))
    )).

printer:test_stats_record_entry(RepositoryEntry, _ModelAVL, ProofAVL, TriggersAVL, DoCycles) :-
  printer:test_stats_inc(processed),
  ( RepositoryEntry = Repo://Entry -> printer:test_stats_add_pkg(processed, Repo, Entry) ; true ),
  findall(ContentN,
          ( assoc:gen_assoc(ProofKey, ProofAVL, _),
            explainer:assumption_content_from_proof_key(ProofKey, Content0),
            explainer:assumption_normalize(Content0, ContentN)
          ),
          Contents0),
  ( Contents0 == [] ->
      true
  ; printer:test_stats_inc(entries_with_assumptions),
    ( RepositoryEntry = Repo://Entry -> printer:test_stats_add_pkg(with_assumptions, Repo, Entry) ; true ),
    ( once((member(C0, Contents0), printer:assumption_is_package_level(C0))) ->
        printer:test_stats_inc(entries_with_package_assumptions),
        ( RepositoryEntry = Repo://Entry -> printer:test_stats_add_pkg(with_package_assumptions, Repo, Entry) ; true )
    ; true
    ),
    findall(Type,
            ( member(Content, Contents0),
              printer:assumption_type(Content, Type),
              printer:test_stats_inc_type(Type, occurrences, 1),
              printer:test_stats_inc_type_entry_mention(Type, RepositoryEntry),
              ( Type == blocker_assumption ->
                  printer:test_stats_record_blocker_assumption(Content)
              ; true
              )
            ),
            TypesAll),
    forall((member(Content, Contents0), printer:assumption_type(Content, other)),
           printer:test_stats_inc_other_head(Content)),
    sort(TypesAll, TypesUnique),
    forall(member(T, TypesUnique),
           printer:test_stats_inc_type(T, entries, 1))
  ),
  ( DoCycles == true ->
      printer:test_stats_set_current_entry(RepositoryEntry),
      forall(member(Content, Contents0),
             ( printer:cycle_for_assumption(Content, TriggersAVL, CyclePath0, CyclePath) ->
                 printer:test_stats_record_cycle(CyclePath0, CyclePath)
             ; true
             )),
      printer:test_stats_clear_current_entry
  ; true
  ).

% Compute a cycle path (if any) for an assumption key.
printer:cycle_for_assumption(StartKey0, TriggersAVL, CyclePath0, CyclePath) :-
  ( StartKey0 = cycle_break(X) -> StartKey1 = X ; StartKey1 = StartKey0 ),
  ( prover:canon_literal(StartKey1, StartKey, _) -> true ; StartKey = StartKey1 ),
  ( StartKey = _://_:install ; StartKey = _://_:run ; StartKey = _://_:fetchonly
  ; StartKey = _:install     ; StartKey = _:run     ; StartKey = _:fetchonly
  ),
  printer:find_cycle_via_triggers(StartKey, TriggersAVL, CyclePath0),
  printer:cycle_display_path(CyclePath0, CyclePath),
  CyclePath = [_|_].

% Record cycle statistics: overall cycle count + per-ebuild mention counts.
printer:test_stats_record_cycle(_CyclePath0, CyclePath) :-
  printer:test_stats_inc(cycles_found),
  printer:test_stats_note_cycle_for_current_entry,
  findall(Action-RepoEntry,
          ( member(Node, CyclePath),
            printer:cycle_pkg_repo_entry(Node, RepoEntry, Action),
            ( Action == run ; Action == install )
          ),
          Mentions0),
  sort(Mentions0, Mentions),
  forall(member(Action-RepoEntry, Mentions),
         printer:test_stats_inc_cycle_mention(Action, RepoEntry)).

printer:test_stats_value(Key, Value) :-
  ( printer:test_stats_stat(Key, Value) -> true ; Value = 0 ).

printer:test_stats_percent(_, 0, 0.0) :- !.
printer:test_stats_percent(Part, Total, Percent) :-
  Percent is (100.0 * Part) / Total.

% -----------------------------------------------------------------------------
%  Test stats table formatting helpers
% -----------------------------------------------------------------------------

printer:test_stats_table_width(80).

% Fixed widths so all tables share the same right edge (80 cols including indent).
printer:test_stats_label_col_width(34).
printer:test_stats_pct_col_width(10).

printer:test_stats_rank_col_width(4).
% Align with the percent columns in the other tables (10-wide).
printer:test_stats_count_col_width(10).

printer:test_stats_item_col_width(W) :-
  printer:test_stats_table_width(TW),
  printer:test_stats_rank_col_width(RW),
  printer:test_stats_count_col_width(CW),
  % "  " + rank(RW) + "  " + item + " " + count(CW)
  W is max(10, TW - 2 - RW - 2 - 1 - CW).

printer:test_stats_to_atom(Term, Atom) :-
  ( atom(Term) -> Atom = Term
  ; with_output_to(atom(Atom),
                   write_term(Term, [quoted(false), numbervars(true)]))
  ).

printer:test_stats_fit_atom(Atom0, Width, Atom) :-
  ( atom_length(Atom0, L), L =< Width ->
      Atom = Atom0
  ; Width =< 1 ->
      Atom = '…'
  ; Width =:= 2 ->
      Atom = '…'
  ; Width1 is Width - 1,
    sub_atom(Atom0, 0, Width1, _After, Prefix),
    atom_concat(Prefix, '…', Atom)
  ).

printer:test_stats_pad_right(Atom0, Width, Atom) :-
  atom_length(Atom0, L),
  ( L >= Width ->
      Atom = Atom0
  ; Pad is Width - L,
    length(Cs, Pad),
    maplist(=(' '), Cs),
    atom_chars(PadAtom, Cs),
    atom_concat(Atom0, PadAtom, Atom)
  ).

printer:test_stats_pad_left(Atom0, Width, Atom) :-
  atom_length(Atom0, L),
  ( L >= Width ->
      Atom = Atom0
  ; Pad is Width - L,
    length(Cs, Pad),
    maplist(=(' '), Cs),
    atom_chars(PadAtom, Cs),
    atom_concat(PadAtom, Atom0, Atom)
  ).

printer:test_stats_int_atom(Int, Atom) :-
  format(atom(Atom), '~d', [Int]).

printer:test_stats_print_sep :-
  printer:test_stats_table_width(W),
  % Use * as "tab stop from argument" (avoid printing W).
  format('  ~`-t~*|~n', [W]).

printer:test_stats_print_kv_int(Label, Value) :-
  format('  ~w~t~30|: ~d~n', [Label, Value]).

printer:test_stats_print_kv_int_percent(Label, Count, Total) :-
  printer:test_stats_percent(Count, Total, P),
  format('  ~w~t~30|: ~d (~2f%)~n', [Label, Count, P]).

printer:test_stats_print_table_header :-
  printer:test_stats_label_col_width(LW),
  printer:test_stats_count_col_width(CW),
  printer:test_stats_pct_col_width(PW),
  printer:test_stats_pad_right('Metric', LW, MetricHdr),
  printer:test_stats_pad_left('Ebuilds', CW, EbuildsHdr),
  printer:test_stats_pad_left('Ebuild %', PW, EbuildPctHdr),
  printer:test_stats_pad_left('Pkgs', CW, PkgsHdr),
  printer:test_stats_pad_left('Pkg %', PW, PkgPctHdr),
  format('  ~w ~w ~w ~w ~w~n',
         [MetricHdr, EbuildsHdr, EbuildPctHdr, PkgsHdr, PkgPctHdr]),
  printer:test_stats_print_sep.

printer:test_stats_print_table_row(Label, ECount, ETotal, PCount, PTotal) :-
  printer:test_stats_percent(ECount, ETotal, EP),
  printer:test_stats_percent(PCount, PTotal, PP),
  format(atom(EPAtom), '~2f %', [EP]),
  format(atom(PPAtom), '~2f %', [PP]),
  printer:test_stats_label_col_width(LW),
  printer:test_stats_count_col_width(CW),
  printer:test_stats_pct_col_width(PW),
  printer:test_stats_pad_right(Label, LW, Lbl),
  printer:test_stats_int_atom(ECount, EC0),
  printer:test_stats_int_atom(PCount, PC0),
  printer:test_stats_pad_left(EC0, CW, EC),
  printer:test_stats_pad_left(EPAtom, PW, EPR),
  printer:test_stats_pad_left(PC0, CW, PC),
  printer:test_stats_pad_left(PPAtom, PW, PPR),
  format('  ~w ~w ~w ~w ~w~n',
         [Lbl, EC, EPR, PC, PPR]).

printer:test_stats_print_assumption_types_table_header :-
  printer:test_stats_label_col_width(LW),
  printer:test_stats_count_col_width(CW),
  printer:test_stats_pct_col_width(PW),
  printer:test_stats_pad_right('Type', LW, TypeHdr),
  printer:test_stats_pad_left('Ebuilds', CW, EbuildsHdr),
  printer:test_stats_pad_left('Ebuild %', PW, EbuildPctHdr),
  printer:test_stats_pad_left('Occ', CW, OccHdr),
  printer:test_stats_pad_left('Occ %', PW, OccPctHdr),
  format('  ~w ~w ~w ~w ~w~n',
         [TypeHdr, EbuildsHdr, EbuildPctHdr, OccHdr, OccPctHdr]),
  printer:test_stats_print_sep.

printer:test_stats_print_assumption_types_row(Type, ECount, ETotal, OCount, OTotal) :-
  printer:test_stats_percent(ECount, ETotal, EP),
  printer:test_stats_percent(OCount, OTotal, OP),
  format(atom(EPAtom), '~2f %', [EP]),
  format(atom(OPAtom), '~2f %', [OP]),
  printer:test_stats_label_col_width(LW),
  printer:test_stats_count_col_width(CW),
  printer:test_stats_pct_col_width(PW),
  printer:test_stats_pad_right(Type, LW, TypeLbl),
  printer:test_stats_int_atom(ECount, EC0),
  printer:test_stats_int_atom(OCount, OC0),
  printer:test_stats_pad_left(EC0, CW, EC),
  printer:test_stats_pad_left(EPAtom, PW, EPR),
  printer:test_stats_pad_left(OC0, CW, OC),
  printer:test_stats_pad_left(OPAtom, PW, OPR),
  format('  ~w ~w ~w ~w ~w~n',
         [TypeLbl, EC, EPR, OC, OPR]).

printer:test_stats_print_ranked_table_header(Title, RightHeader) :-
  nl,
  message:header(Title),
  nl,
  printer:test_stats_item_col_width(ItemW),
  printer:test_stats_count_col_width(CountW),
  printer:test_stats_rank_col_width(RankW),
  printer:test_stats_pad_left('Rank', RankW, RankHdr),
  printer:test_stats_pad_right('Item', ItemW, ItemHdr),
  printer:test_stats_pad_left(RightHeader, CountW, RHdr),
  format('  ~w  ~w ~w~n', [RankHdr, ItemHdr, RHdr]),
  printer:test_stats_print_sep.

printer:test_stats_print_ranked_table_rows([], _Limit, _I, _W) :- !.
printer:test_stats_print_ranked_table_rows(_, 0, _I, _W) :- !.
printer:test_stats_print_ranked_table_rows([N-Item|Rest], Limit, I, W) :-
  printer:test_stats_item_col_width(ItemW),
  printer:test_stats_to_atom(Item, ItemAtom0),
  printer:test_stats_fit_atom(ItemAtom0, ItemW, ItemAtom1),
  printer:test_stats_pad_right(ItemAtom1, ItemW, ItemAtom),
  printer:test_stats_rank_col_width(RankW),
  format(atom(RankAtom0), '~d', [I]),
  printer:test_stats_pad_left(RankAtom0, RankW, RankAtom),
  printer:test_stats_count_col_width(CountW),
  format(atom(NAtom0), '~d', [N]),
  printer:test_stats_pad_left(NAtom0, CountW, NAtom),
  format('  ~w  ~w ~w~n', [RankAtom, ItemAtom, NAtom]),
  I1 is I + 1,
  Limit1 is Limit - 1,
  printer:test_stats_print_ranked_table_rows(Rest, Limit1, I1, W).

printer:test_stats_print :-
  ( config:test_stats_top_n(TopN) -> true ; TopN = 10 ),
  printer:test_stats_print(TopN).

%! printer:test_stats_print(+TopN)
%
% Print the accumulated test_stats summary, showing top lists up to TopN.
printer:test_stats_print(TopN) :-
  printer:test_stats_value(label, Label),
  printer:test_stats_value(expected_total, Expected),
  printer:test_stats_value(expected_unique_packages, ExpectedPkgs),
  printer:test_stats_value(processed, Processed),
  printer:test_stats_value(entries_with_assumptions, WithAss),
  printer:test_stats_value(entries_with_package_assumptions, WithPkgAss),
  printer:test_stats_value(entries_with_cycles, WithCycles),
  printer:test_stats_value(cycles_found, CyclesFound),
  printer:test_stats_unique_pkg_count(processed, ProcessedPkgs),
  printer:test_stats_unique_pkg_count(with_assumptions, WithAssPkgs),
  printer:test_stats_unique_pkg_count(with_package_assumptions, WithPkgAssPkgs),
  printer:test_stats_unique_pkg_count(with_cycles, WithCyclesPkgs),
  nl,
  message:header(['Test statistics (',Label,')']),
  nl,
  printer:test_stats_print_table_header,
  printer:test_stats_print_table_row('Total', Expected, Expected, ExpectedPkgs, ExpectedPkgs),
  printer:test_stats_print_table_row('Processed', Processed, Expected, ProcessedPkgs, ExpectedPkgs),
  ( Processed > 0 ->
      printer:test_stats_print_table_row('With assumptions', WithAss, Processed, WithAssPkgs, ProcessedPkgs),
      printer:test_stats_print_table_row('With package assumptions', WithPkgAss, Processed, WithPkgAssPkgs, ProcessedPkgs),
      printer:test_stats_print_table_row('With cycles', WithCycles, Processed, WithCyclesPkgs, ProcessedPkgs),
      nl,
      format('  ~w~t~30|: ~d total~n', ['Cycles found', CyclesFound]),
      format('  ~w~t~30|: ~2f cycles per processed entry~n', ['Cycles per entry', CyclesFound/Processed])
  ; true
  ),
  ( Expected =\= Processed ->
      printer:test_stats_value(entries_failed_blocker, FailedBlocker),
      printer:test_stats_value(entries_failed_timeout, FailedTimeout),
      printer:test_stats_value(entries_failed_other, FailedOther),
      FailedTotal is Expected - Processed,
      Unknown0 is FailedTotal - FailedBlocker - FailedTimeout - FailedOther,
      Unknown is max(0, Unknown0),
      format('  ~w~t~30|: ~d entries did not produce a plan/proof (failed/timeout).~n',
             ['Note', FailedTotal]),
      ( FailedBlocker > 0 ->
          format('  ~w~t~30|: ~d failed due to blockers (detected).~n',
                 ['Blocker failures', FailedBlocker])
      ; true
      ),
      ( FailedTimeout > 0 ->
          format('  ~w~t~30|: ~d timed out (detected).~n',
                 ['Timeout failures', FailedTimeout])
      ; true
      ),
      ( FailedOther > 0 ->
          format('  ~w~t~30|: ~d failed for other reasons (detected).~n',
                 ['Other failures', FailedOther])
      ; true
      ),
      ( Unknown > 0 ->
          format('  ~w~t~30|: ~d failed/timeout with unknown reason (not classified).~n',
                 ['Unknown', Unknown])
      ; true
      )
  , % Extra context: many "failed entries" are older versions of a package that
    % has at least one other version that proved successfully in the same run.
    findall(C-N,
            ( printer:test_stats_failed_entry(Repo0://Entry0, _R),
              cache:ordered_entry(Repo0, Entry0, C, N, _)
            ),
            FailedCNs0),
    sort(FailedCNs0, FailedCNs),
    length(FailedCNs, FailedPkgsTotal),
    findall(C-N,
            ( member(C-N, FailedCNs),
              printer:test_stats_pkg(processed, C, N)
            ),
            MixedCNs0),
    sort(MixedCNs0, MixedCNs),
    length(MixedCNs, FailedPkgsWithSomeSuccess),
    FailedPkgsAllFail is FailedPkgsTotal - FailedPkgsWithSomeSuccess,
    ( FailedPkgsTotal > 0 ->
        format('  ~w~t~30|: ~d unique packages had at least one failing entry.~n',
               ['Note', FailedPkgsTotal])
    ; true
    ),
    ( FailedPkgsWithSomeSuccess > 0 ->
        format('  ~w~t~30|: ~d failing packages have another version that proved OK.~n',
               ['Note', FailedPkgsWithSomeSuccess])
    ; true
    ),
    ( FailedPkgsAllFail > 0 ->
        format('  ~w~t~30|: ~d failing packages have no version that proved OK.~n',
               ['Note', FailedPkgsAllFail])
    ; true
    ),
    ( MixedCNs \== [] ->
        format('  ~w~t~30|: ~w~n', ['Mixed (sample)', MixedCNs])
    ; true
    )
  ; true
  ),
  nl,
  message:header('Assumption types'),
  nl,
  findall(O, printer:test_stats_type(_, occurrences, O), Occs),
  sum_list(Occs, TotalOccs),
  findall(Type,
          ( printer:test_stats_type(Type, _, _) ),
          Types0),
  sort(Types0, Types),
  ( Types == [] ->
      writeln('  (none)')
  ; printer:test_stats_print_assumption_types_table_header,
    forall(member(Type, Types),
           ( ( printer:test_stats_type(Type, entries, E) -> true ; E = 0 ),
             ( printer:test_stats_type(Type, occurrences, O) -> true ; O = 0 ),
             printer:test_stats_print_assumption_types_row(Type, E, Processed, O, TotalOccs)
           ))
  ),

  % Top-N slowest processed entries (by walltime in ms).
  nl,
  message:header(['Top ',TopN,' slowest proofs']),
  nl,
  findall(Ms-RepoEntry, printer:test_stats_entry_time(RepoEntry, Ms), Times0),
  keysort(Times0, TimesAsc),
  reverse(TimesAsc, TimesSorted),
  ( TimesSorted == [] ->
      writeln('  (none)')
  ; printer:test_stats_print_ranked_table_header('Slowest entries', 'ms'),
    printer:test_stats_table_width(Wt),
    printer:test_stats_print_ranked_table_rows(TimesSorted, TopN, 1, Wt)
  ),

  % Top-N slowest packages (Category/Name), by total time spent proving all entries.
  nl,
  message:header(['Top ',TopN,' slowest packages (total)']),
  nl,
  findall(SumMs-C-N, printer:test_stats_pkg_time(C, N, SumMs, _MaxMs, _Cnt), PkgTimes0),
  keysort(PkgTimes0, PkgAsc0),
  reverse(PkgAsc0, PkgSorted0),
  findall(SumMs-PkgAtom,
          ( member(SumMs-C-N, PkgSorted0),
            atomic_list_concat([C,N], '/', PkgAtom)
          ),
          PkgSorted),
  ( PkgSorted == [] ->
      writeln('  (none)')
  ; printer:test_stats_print_ranked_table_header('Slowest packages', 'ms'),
    printer:test_stats_table_width(Wp),
    printer:test_stats_print_ranked_table_rows(PkgSorted, TopN, 1, Wp)
  ),

  % Top-N packages by total inferences (proxy for "how much work did we do").
  nl,
  message:header(['Top ',TopN,' most expensive packages (inferences)']),
  nl,
  findall(SumInf-PkgAtomInf,
          ( printer:test_stats_pkg_cost(Ci, Ni, _MsI, SumInf, _RuleI, _CntI),
            atomic_list_concat([Ci,Ni], '/', PkgAtomInf)
          ),
          PkgInf0),
  keysort(PkgInf0, PkgInfAsc),
  reverse(PkgInfAsc, PkgInfSorted),
  ( PkgInfSorted == [] ->
      writeln('  (none)')
  ; printer:test_stats_print_ranked_table_header('Costly packages', 'inferences'),
    printer:test_stats_table_width(Wi),
    printer:test_stats_print_ranked_table_rows(PkgInfSorted, TopN, 1, Wi)
  ),

  % Top-N packages by context "union cost" (proxy for list-processing overhead in contexts).
  nl,
  message:header(['Top ',TopN,' most expensive packages (context unions)']),
  nl,
  findall(SumCtxCost-PkgAtomCtx,
          ( printer:test_stats_pkg_ctx(Cc, Nc, SumCtxCost, _MaxLenC, _SumMsC, _CntC),
            atomic_list_concat([Cc,Nc], '/', PkgAtomCtx)
          ),
          PkgCtx0),
  keysort(PkgCtx0, PkgCtxAsc),
  reverse(PkgCtxAsc, PkgCtxSorted),
  ( PkgCtxSorted == [] ->
      writeln('  (none)')
  ; printer:test_stats_print_ranked_table_header('Costly packages', 'ctx-union-cost'),
    printer:test_stats_table_width(Wctx),
    printer:test_stats_print_ranked_table_rows(PkgCtxSorted, TopN, 1, Wctx)
  ),

  % Top-N packages by estimated walltime spent in ctx unions (sampled).
  nl,
  message:header(['Top ',TopN,' most expensive packages (context unions walltime, est)']),
  nl,
  findall(UnionMs-CcMs-NcMs,
          printer:test_stats_pkg_ctx(CcMs, NcMs, _SumCtxCostMs, _MaxLenMs, UnionMs, _CntMs),
          PkgCtxMsCN0),
  keysort(PkgCtxMsCN0, PkgCtxMsAscCN),
  reverse(PkgCtxMsAscCN, PkgCtxMsSortedCN),
  findall(UnionMs-PkgAtomCtxMs,
          ( member(UnionMs-CcMs-NcMs, PkgCtxMsSortedCN),
            atomic_list_concat([CcMs,NcMs], '/', PkgAtomCtxMs)
          ),
          PkgCtxMsSorted),
  ( PkgCtxMsSorted == [] ->
      writeln('  (none)')
  ; printer:test_stats_print_ranked_table_header('Costly packages', 'ctx-union-ms'),
    printer:test_stats_table_width(Wctxms),
    printer:test_stats_print_ranked_table_rows(PkgCtxMsSorted, TopN, 1, Wctxms)
  ),

  % For the same ranking, show how much of total package time this represents.
  nl,
  message:header(['Top ',TopN,' packages by context union time share (est)']),
  nl,
  printer:test_stats_ctx_share_rows(ShareRowsSorted),
  ( ShareRowsSorted == [] ->
      writeln('  (none)')
  ; printer:test_stats_print_ranked_table_header('Packages', 'ctx%*10'),
    printer:test_stats_table_width(Wshare),
    printer:test_stats_print_ranked_table_rows(ShareRowsSorted, TopN, 1, Wshare)
  ),

  % Context length distribution (sampled from ctx_union/3 output lengths).
  nl,
  message:header('Context length distribution (sampled, ctx_union output)'),
  nl,
  findall(Len-Cnt, printer:test_stats_ctx_len_bin(Len, Cnt), LenBins0),
  keysort(LenBins0, LenBins),
  ( LenBins == [] ->
      writeln('  (none)')
  ; findall(C, member(_L-C, LenBins), LenCnts),
    sum_list(LenCnts, LenTotal),
    format('  Samples: ~d~n', [LenTotal]),
    % Buckets: 0-3, 4-5, 6-10, 11+
    printer:test_stats_ctx_len_bucket(LenBins, 3,  Le3),
    printer:test_stats_ctx_len_bucket(LenBins, 5,  Le5),
    printer:test_stats_ctx_len_bucket(LenBins, 10, Le10),
    B0_3 is Le3,
    B4_5 is max(0, Le5 - Le3),
    B6_10 is max(0, Le10 - Le5),
    B11 is max(0, LenTotal - Le10),
    ( LenTotal =:= 0 ->
        true
    ; format('  0-3:   ~d (~2f%%)~n', [B0_3, 100*B0_3/LenTotal]),
      format('  4-5:   ~d (~2f%%)~n', [B4_5, 100*B4_5/LenTotal]),
      format('  6-10:  ~d (~2f%%)~n', [B6_10, 100*B6_10/LenTotal]),
      format('  11+:   ~d (~2f%%)~n', [B11,  100*B11/LenTotal])
    ),
    nl,
    printer:test_stats_print_ranked_table_header('ctx-len', 'samples'),
    printer:test_stats_table_width(Wlenhist),
    % show the most common lengths (by count)
    findall(Cnt-LenAtom,
            ( member(Len-Cnt, LenBins),
              format(atom(LenAtom), '~d', [Len])
            ),
            LenByCount0),
    keysort(LenByCount0, LenByCountAsc),
    reverse(LenByCountAsc, LenByCount),
    printer:test_stats_print_ranked_table_rows(LenByCount, min(TopN, 25), 1, Wlenhist)
  ),

  % Ordset gain estimate (very rough): compare a quadratic proxy vs linear proxy.
  ( printer:test_stats_ctx_cost_model(SumMul, SumAdd, SamplesModel),
    SamplesModel > 0,
    SumMul > 0,
    SumAdd > 0 ->
      Speedup is SumMul / SumAdd,
      findall(SumMs0, printer:test_stats_pkg_ctx(_Ccm,_Ncm,_Costcm,_Maxcm,SumMs0,_Cntcm), Ms0s),
      sum_list(Ms0s, TotalCtxMsEst),
      OrdMsEst0 is TotalCtxMsEst / Speedup,
      OrdMsEst is round(OrdMsEst0),
      SavedMs is max(0, TotalCtxMsEst - OrdMsEst),
      nl,
      message:header('Estimated ordset impact (from sampled ctx_union sizes)'),
      nl,
      format('  ~w~t~30|: ~d~n',   ['Samples used', SamplesModel]),
      format('  ~w~t~30|: ~d~n',   ['Cost proxy (list)  sum L0*L1', SumMul]),
      format('  ~w~t~30|: ~d~n',   ['Cost proxy (ord)   sum L0+L1', SumAdd]),
      format('  ~w~t~30|: ~2f×~n', ['Estimated speedup factor', Speedup]),
      format('  ~w~t~30|: ~d ms~n',['Total ctx-union-ms (est)', TotalCtxMsEst]),
      format('  ~w~t~30|: ~d ms~n',['Est ctx-union-ms w/ ordsets', OrdMsEst]),
      format('  ~w~t~30|: ~d ms~n',['Est savings', SavedMs])
  ; true
  ),

  % Top-N packages by max context size observed.
  nl,
  message:header(['Top ',TopN,' largest contexts observed']),
  nl,
  findall(MaxLen-PkgAtomLen,
          ( printer:test_stats_pkg_ctx(Cc2, Nc2, _SumCtxCost2, MaxLen, _SumCtxMs2, _CntC2),
            atomic_list_concat([Cc2,Nc2], '/', PkgAtomLen)
          ),
          PkgLen0),
  keysort(PkgLen0, PkgLenAsc),
  reverse(PkgLenAsc, PkgLenSorted),
  ( PkgLenSorted == [] ->
      writeln('  (none)')
  ; printer:test_stats_print_ranked_table_header('Packages', 'max-ctx-len'),
    printer:test_stats_table_width(Wlen),
    printer:test_stats_print_ranked_table_rows(PkgLenSorted, TopN, 1, Wlen)
  ),

  % Top-N slowest packages (Category/Name), by max single-entry time.
  nl,
  message:header(['Top ',TopN,' slowest packages (max)']),
  nl,
  findall(MaxMs-C-N, printer:test_stats_pkg_time(C, N, _SumTotalMs2, MaxMs, _Cnt2), PkgMax0),
  keysort(PkgMax0, PkgMaxAsc0),
  reverse(PkgMaxAsc0, PkgMaxSorted0),
  findall(MaxMs-PkgAtom2,
          ( member(MaxMs-C2-N2, PkgMaxSorted0),
            atomic_list_concat([C2,N2], '/', PkgAtom2)
          ),
          PkgMaxSorted),
  ( PkgMaxSorted == [] ->
      writeln('  (none)')
  ; printer:test_stats_print_ranked_table_header('Slowest packages', 'ms'),
    printer:test_stats_table_width(Wp2),
    printer:test_stats_print_ranked_table_rows(PkgMaxSorted, TopN, 1, Wp2)
  ),

  % Top-N entries per assumption type (by occurrence count).
  forall(member(Type, Types),
         ( findall(N-RepoEntry, printer:test_stats_type_entry_mention(Type, RepoEntry, N), P0),
           keysort(P0, PAsc),
           reverse(PAsc, PSorted),
           ( PSorted == [] ->
               true
           ; atomic_list_concat(['Top ',TopN,' entries for ',Type], TypeHeader),
             printer:test_stats_print_ranked_table_header(TypeHeader, 'Occ'),
             printer:test_stats_table_width(W),
             printer:test_stats_print_ranked_table_rows(PSorted, TopN, 1, W)
           )
         )),
  % Detailed breakdown for blocker assumptions (if present).
  ( printer:test_stats_type(blocker_assumption, occurrences, BlockOcc),
    BlockOcc > 0 ->
      nl,
      message:header('Blocker assumptions (breakdown)'),
      nl,
      printer:test_stats_print_ranked_table_header('Strength/phase', 'Occ'),
      printer:test_stats_blocker_sp_rows(SpSorted),
      ( SpSorted == [] ->
          writeln('  (none)'),
          ( printer:test_stats_blocker_example(Ex) ->
              format('  Note: could not parse blocker term for breakdown; example: ~q~n', [Ex])
          ; true
          )
      ; printer:test_stats_table_width(Wsp),
        printer:test_stats_print_ranked_table_rows(SpSorted, 10, 1, Wsp)
      ),
      nl,
      message:header(['Top ',TopN,' blocker reasons']),
      nl,
      printer:test_stats_print_ranked_table_header('Reasons', 'Occ'),
      printer:test_stats_blocker_reason_rows(ReasonRows),
      ( ReasonRows == [] ->
          writeln('  (none)')
      ; printer:test_stats_table_width(Wbr),
        printer:test_stats_print_ranked_table_rows(ReasonRows, TopN, 1, Wbr)
      ),
      nl,
      message:header(['Top ',TopN,' blocker reasons (install)']),
      nl,
      printer:test_stats_print_ranked_table_header('Reasons', 'Occ'),
      printer:test_stats_blocker_reason_phase_rows(install, RInstRows),
      ( RInstRows == [] ->
          writeln('  (none)')
      ; printer:test_stats_table_width(Wbri),
        printer:test_stats_print_ranked_table_rows(RInstRows, TopN, 1, Wbri)
      ),
      nl,
      message:header(['Top ',TopN,' blocker reasons (run)']),
      nl,
      printer:test_stats_print_ranked_table_header('Reasons', 'Occ'),
      printer:test_stats_blocker_reason_phase_rows(run, RRunRows),
      ( RRunRows == [] ->
          writeln('  (none)')
      ; printer:test_stats_table_width(Wbrr),
        printer:test_stats_print_ranked_table_rows(RRunRows, TopN, 1, Wbrr)
      ),
      nl,
      message:header(['Top ',TopN,' most-blocking packages (C/N)']),
      nl,
      printer:test_stats_print_ranked_table_header('Packages', 'Occ'),
      findall(OccCN-CN,
              ( printer:test_stats_blocker_cn(Cb, Nb, OccCN),
                atomic_list_concat([Cb,Nb], '/', CN)
              ),
              Cn0),
      keysort(Cn0, CnAsc),
      reverse(CnAsc, CnSorted),
      ( CnSorted == [] ->
          writeln('  (none)')
      ; printer:test_stats_table_width(Wcn),
        printer:test_stats_print_ranked_table_rows(CnSorted, TopN, 1, Wcn)
      )
  ; true
  ),
  ( ( printer:test_stats_type(other, occurrences, OtherOcc), OtherOcc > 0 ) ->
      nl,
      findall(N-Key, printer:test_stats_other_head(Key, N), H0),
      keysort(H0, HAsc),
      reverse(HAsc, HSorted),
      printer:test_stats_print_ranked_table_header('Top 15 other assumption heads', 'Count'),
      printer:test_stats_table_width(W),
      printer:test_stats_print_ranked_table_rows(HSorted, 15, 1, W)
  ; true
  ),
  nl,
  atomic_list_concat(['Top ',TopN,' cycle mentions (run)'], HeaderRun),
  findall(N-RepoEntry, printer:test_stats_cycle_mention(run, RepoEntry, N), RunPairs0),
  keysort(RunPairs0, RunSortedAsc),
  reverse(RunSortedAsc, RunSorted),
  ( RunSorted == [] ->
      true
  ; printer:test_stats_print_ranked_table_header(HeaderRun, 'Mentions'),
    printer:test_stats_table_width(W1),
    printer:test_stats_print_ranked_table_rows(RunSorted, TopN, 1, W1)
  ),
  atomic_list_concat(['Top ',TopN,' cycle mentions (install)'], HeaderInstall),
  findall(N-RepoEntry, printer:test_stats_cycle_mention(install, RepoEntry, N), InstallPairs0),
  keysort(InstallPairs0, InstallSortedAsc),
  reverse(InstallSortedAsc, InstallSorted),
  ( InstallSorted == [] ->
      true
  ; printer:test_stats_print_ranked_table_header(HeaderInstall, 'Mentions'),
    printer:test_stats_table_width(W2),
    printer:test_stats_print_ranked_table_rows(InstallSorted, TopN, 1, W2)
  ).

printer:test_stats_print_top_cycle_mentions([], _Limit, I) :- !,
  ( I =:= 1 -> writeln('  (none)') ; true ).
printer:test_stats_print_top_cycle_mentions(_, 0, _I) :- !.
printer:test_stats_print_top_cycle_mentions([N-RepoEntry|Rest], Limit, I) :-
  format('  ~t~d~3+. ~w (~d)~n', [I, RepoEntry, N]),
  I1 is I + 1,
  Limit1 is Limit - 1,
  printer:test_stats_print_top_cycle_mentions(Rest, Limit1, I1).

% Count how many samples fall in <= Threshold.
printer:test_stats_ctx_len_bucket(LenBins, Threshold, CountLe) :-
  findall(Cnt,
          ( member(Len-Cnt, LenBins),
            Len =< Threshold
          ),
          Cnts),
  sum_list(Cnts, CountLe).

printer:test_stats_blocker_sp_rows(SpSorted) :-
  findall(Occ-Label,
          ( printer:test_stats_blocker_sp(S, P, Occ),
            format(atom(Label), '~w/~w', [S, P])
          ),
          Sp0),
  keysort(Sp0, SpAsc),
  reverse(SpAsc, SpSorted).

printer:test_stats_blocker_reason_rows(RowsSorted) :-
  findall(Occ-ReasonAtom,
          ( printer:test_stats_blocker_reason(Reason, Occ),
            format(atom(ReasonAtom), '~w', [Reason])
          ),
          R0),
  keysort(R0, RAsc),
  reverse(RAsc, RowsSorted).

printer:test_stats_blocker_reason_phase_rows(Phase, RowsSorted) :-
  findall(Occ-ReasonAtom,
          ( printer:test_stats_blocker_rp(Reason, Phase, Occ),
            format(atom(ReasonAtom), '~w', [Reason])
          ),
          R0),
  keysort(R0, RAsc),
  reverse(RAsc, RowsSorted).

% Build rows for the ctx% share table.
% Rows are keyed by percent*10 (integer) so the generic ranked-table printer can sort them.
printer:test_stats_ctx_share_rows(ShareRowsSorted) :-
  findall(Pct10-Label,
          ( printer:test_stats_pkg_ctx(C, N, _SumCost, _MaxLen, UnionMs, _CntCtx),
            UnionMs > 0,
            printer:test_stats_pkg_time(C, N, TotalMs, _MaxMs, _CntTime),
            TotalMs > 0,
            Pct10 is round(UnionMs * 1000 / TotalMs),
            Pct1 is Pct10 / 10,
            atomic_list_concat([C,N], '/', PkgAtomShare),
            format(atom(Label), '~w (~1f%%)', [PkgAtomShare, Pct1])
          ),
          ShareRows0),
  keysort(ShareRows0, ShareRowsAsc),
  reverse(ShareRowsAsc, ShareRowsSorted).

% -----------------------------------------------------------------------------
%  PROVER state printing
% -----------------------------------------------------------------------------

printer:display_state([],_,_,_) :- !.
printer:display_state(Target, Proof, Model, Constraints) :-

    % prepare aguments

    ( Target = [ Current | Queue ]
      -> true
      ;  Current = Target, Queue = [] ),

    prover:proof_to_list(Proof,ProofList),
    prover:model_to_list(Model,ModelList),
    prover:constraints_to_list(Constraints,ConstraintList),

    message:hl,

    %tty_clear,

    % proving subtitle

    message:color(orange), message:style(bold),
    format('--- Proving ---~n'),
    message:color(normal), message:style(normal),
    format('  ~w~n~n', [Current]),

    % proving stack subtitle

    message:color(magenta), message:style(bold),
    format('--- Proving Stack (In Progress) ---~n'),
    message:color(normal), message:style(normal),
    ( ProofList == [] -> writeln('  (empty)') ;
      ( reverse(ProofList, Tmp),
        forall(member(rule(P,_), Tmp), format('  ~w~n', [P]))
      )
    ),
    nl,

    % to be proven queue subtitle

    message:color(cyan), message:style(bold),
    format('--- Proving Queue (To Do) ---~n'),
    message:color(normal), message:style(normal),
    ( Queue == [] -> writeln('  (empty)') ; forall(member(Q, Queue), format('  ~w~n', [Q])) ),
    nl,

    % model subtitle

    message:color(green), message:style(bold),
    format('--- Model (Completed) ---~n'),
    message:color(normal), message:style(normal),

    ( ModelList  == [] -> writeln('  (empty)')
    ; forall(member(M, ModelList), ( format('  ~w~n', [M]) ))),
    nl,

    % constraints subtitle

    message:color(green), message:style(bold),
    format('--- Constraints (Completed) ---~n'),
    message:color(normal), message:style(normal),

    ( ConstraintList  == [] -> writeln('  (empty)')
    ; forall(member(M, ConstraintList), ( format('  ~w~n', [M]) ))).

    %wait_for_input.


% Helper to wait for the user to press Enter.
printer:wait_for_input :-
    % In non-interactive runs (e.g. here-doc piping), user_input is not a TTY and
    % `get_char/1` can throw on EOF. Only prompt when we can actually read.
    ( stream_property(user_input, tty(true)),
      \+ at_end_of_stream(user_input) ->
        format('~nPress Enter to continue...'),
        flush_output,
        catch(get_char(_), _E, true)
    ; true
    ).


% -----------------------------------------------------------------------------
%  INDEX printing
% -----------------------------------------------------------------------------

%! printer:print_index(Generator)
%
% Print an index for a given Generator (repository:category, repository:package)

printer:print_index(Type,Title,TitleHtml,Generator,Template,Stylesheet) :-
  print_index_header(Title,TitleHtml,Stylesheet),
  forall(Generator,print_index_element(Type,Template)),
  print_index_footer.


%! printer:print_index_header(Name,Stylesheet)
%
% Print an index header with a given Name and Stylesheet

printer:print_index_header(Title,TitleHtml,Stylesheet) :-
  writeln('<?xml version=\"1.0\" encoding=\"UTF-8\" ?>'),
  writeln('<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd\">'),
  writeln('<html xmlns=\"http://www.w3.org/1999/xhtml\">'),
  writeln('<head>'),
  writeln('<meta http-equiv=\"Content-Type\" content=\"application/xml+xhtml; charset=UTF-8\"/>'),
  write('<title>'),write(Title),write('</title>'),nl,
  write('<link rel=\"stylesheet\" href=\"'),write(Stylesheet),write('"/>'),
  writeln('</head>'),
  writeln('<body>'),
  write('<h1>'),write(TitleHtml),write('</h1>'),nl,
  writeln('<ul>').


%! printer:print_index_footer
%
% Print an index footer

printer:print_index_footer :-
  writeln('</ul>'),
  writeln('</body>'),
  writeln('</html>').


%! printer:print_index_element(E,Relpath)
%
% Print an element in the index

printer:print_index_element(repository,E) :-
  write('<li class=\"element\"><a href=\"./'),
  write(E),
  write('/index.html\">'),
  write(E),
  write('</a></li>'),
  nl.

printer:print_index_element(category,E) :-
  write('<li class=\"element\"><a href=\"./'),
  write(E),
  write('.html\">'),
  write(E),
  write('</a></li>'),
  nl.

printer:print_index_element(package,[E,V]) :-
  write('<li class=\"element\"><a href=\"./'),
  write(E),write('-'),write(V),
  write('.svg\">'),
  write(V),
  write('</a></li>'),
  nl.


% -----------------------------------------------------------------------------
%  Ebuild INFO printing
% -----------------------------------------------------------------------------

%! printer:print_entry(Repository://Entry)
%
% Prints information an a repository entry

printer:print_entry(Repository://Entry) :-
  !,
  nl,
  message:header(['Printing information for: ',Repository://Entry]),
  printer:print_metadata(Repository://Entry).


%! printer:print_metadata(Repository://Entry)
%
% Prints information an a repository entry metadata

printer:print_metadata(Repository://Entry) :-
  config:printable_metadata(List),
  forall(member(I,List),printer:print_metadata_item(I,Repository://Entry)).


%! printer:print_metadata_item(Item,Repository://Entry)
%
% Prints specific metadata item

printer:print_metadata_item(blank,_) :-
  !,
  nl.

printer:print_metadata_item(hl,_) :-
  !,
  message:hl.

printer:print_metadata_item(Item,Repository://Entry) :-
  message:style(bold),
  message:color(darkgray),
  write(Item),write(' : '),
  message:style(normal),
  nl,
  Query =.. [Item,Value],
  findall(Value,kb:query(Query,Repository://Entry),Values),
  printer:print_metadata_item_details(Item,Values).


%! printer:print_metadata_item_details(Item,List)
%
% Prints specific metadata item detail list

printer:print_metadata_item_details(_Item,[]) :-
  !,
  Prefix = '   ',
  message:style(italic),
  message:color(lightgray),
  write(Prefix),
  write('[not set]'),
  message:style(normal),
  message:color(normal),
  nl.

printer:print_metadata_item_details(Item,List) :-
  Prefix = '   ',
  forall(member(Value,List),(printer:print_metadata_item_detail(Item,Prefix,Value),nl)).


%! printer:print_metadata_item_detail(Item,Prefix,Value)
%
% Prints specific metadata item detail

printer:print_metadata_item_detail(eapi,Prefix,[_,_,_,Value]) :-
  write(Prefix),
  write(Value).

printer:print_metadata_item_detail(src_uri,Prefix,uri(_,_,Value)) :-
  !,
  write(Prefix),
  write(Value).

printer:print_metadata_item_detail(Item,Prefix,use_conditional_group(Type,Use,_Id,Values)) :-
  !,
  write(Prefix),
  message:bubble(darkgray,use),
  write(' '),
  (Type == negative
   -> (message:color(red),write('-'))
   ;   message:color(green)),
  write(Use),
  message:color(lightgray),
  message:color(normal),
  atom_concat('   ',Prefix,NewPrefix),
  forall(member(V,Values),(nl,message:color(darkgray),message:color(normal),printer:print_metadata_item_detail(Item,NewPrefix,V))).

printer:print_metadata_item_detail(Item,Prefix,any_of_group(Values)) :-
  !,
  write(Prefix),
  message:bubble(darkgray,any),
  write(' '),
  message:color(normal),
  atom_concat('   ',Prefix,NewPrefix),
  forall(member(V,Values),(nl,message:color(darkgray),message:color(normal),printer:print_metadata_item_detail(Item,NewPrefix,V))).

printer:print_metadata_item_detail(Item,Prefix,all_of_group(Values)) :-
  !,
  write(Prefix),
  message:bubble(darkgray,all),
  write(' '),
  message:color(normal),
  atom_concat('   ',Prefix,NewPrefix),
  forall(member(V,Values),(nl,message:color(darkgray),message:color(normal),printer:print_metadata_item_detail(Item,NewPrefix,V))).

printer:print_metadata_item_detail(Item,Prefix,exactly_one_of_group(Values)) :-
  !,
  write(Prefix),
  message:bubble(darkgray,one),
  write(' '),
  message:color(normal),
  atom_concat('   ',Prefix,NewPrefix),
  forall(member(V,Values),(nl,message:color(darkgray),message:color(normal),printer:print_metadata_item_detail(Item,NewPrefix,V))).

printer:print_metadata_item_detail(Item,Prefix,at_most_one_of_group(Values)) :-
  !,
  write(Prefix),
  message:bubble(darkgray,one),
  write('[one] '),
  message:color(normal),
  atom_concat('   ',Prefix,NewPrefix),
  forall(member(V,Values),(nl,message:color(darkgray),message:color(normal),printer:print_metadata_item_detail(Item,NewPrefix,V))).

printer:print_metadata_item_detail(_,Prefix,package_dependency(_,Blocking,Category,Name,none,[[],_,_,_,_],Slot,Use)) :-
  !,
  write(Prefix),
  printer:print_blocking(Blocking),
  write(Category),
  write('/'),
  write(Name),
  printer:print_slot_restriction(Slot),
  printer:print_use_dependencies(Use).

printer:print_metadata_item_detail(_,Prefix,package_dependency(_,Blocking,Category,Name,Comparator,[_,_,_,Version],Slot,Use)) :-
  !,
  write(Prefix),
  printer:print_blocking(Blocking),
  printer:print_comparator(Comparator),
  write(Category),
  write('/'),
  write(Name),
  write('-'),
  write(Version),
  printer:print_slot_restriction(Slot),
  printer:print_use_dependencies(Use).

printer:print_metadata_item_detail(_,Prefix,grouped_package_dependency(_C,_N,List)) :-
  !,
  forall(member(V,List),(
    printer:print_metadata_item_detail(_,Prefix,V),
    nl
  )).

printer:print_metadata_item_detail(_,Prefix,grouped_package_dependency(_X,_C,_N,List)) :-
  !,
  forall(member(V,List),(
    printer:print_metadata_item_detail(_,Prefix,V),
    nl
  )).

printer:print_metadata_item_detail(_,Prefix,Value) :-
  write(Prefix),
  write(Value).


%! printer:print_blocking(Type)
%
% Prints metadata for a blocking dependency

printer:print_blocking(no) :- !.

printer:print_blocking(weak) :-
  message:color(lightgray),
  message:style(italic),
  write('[weak block] '),
  message:style(normal),
  message:color(normal).

printer:print_blocking(strong) :-
  message:color(lightgray),
  message:style(italic),
  write('[strong block] '),
  message:style(normal),
  message:color(normal).


%! printer:print_comparator(Type)
%
% Prints short version of comparator

printer:print_comparator(greaterequal) :- write('>=').
printer:print_comparator(greater)      :- write('>').
printer:print_comparator(smallerequal) :- write('<=').
printer:print_comparator(smaller)      :- write('<').
printer:print_comparator(equal)        :- write('=').
printer:print_comparator(tilde)        :- write('~').
printer:print_comparator(none)         :- write('').


%! printer:print_use_dependencies(Use)
%
% Prints use dependencies

printer:print_use_dependencies([]) :- !.

printer:print_use_dependencies(Use) :-
  message:color(cyan),
  write(' [ '),
  forall(member(D,Use),(printer:print_use_dependency(D),write(' '))),
  write(']'),
  message:color(normal).


%! printer:print_use_dependency(Use)
%
% Print use dependency

printer:print_use_dependency(use(inverse(U),D)) :-
  write('!'),
  write(U),
  print_use_default(D).

printer:print_use_dependency(use(equal(U),D)) :-
  write(U),
  print_use_default(D),
  write('=').

printer:print_use_dependency(use(optdisable(U),D)) :-
  write('!'),
  write(U),
  print_use_default(D),
  write('?').

printer:print_use_dependency(use(optenable(U),D)) :-
  write(U),
  print_use_default(D),
  write('?').

printer:print_use_dependency(use(disable(U),D)) :-
  write('-'),
  write(U),
  print_use_default(D).

printer:print_use_dependency(use(enable(U),D)) :-
  write(U),
  print_use_default(D).


%! printer:print_use_default(D)
%
% Prints use default for a use dependency

printer:print_use_default(positive) :-
  write('(+)').

printer:print_use_default(negative) :-
  write('(-)').

printer:print_use_default(none) :- !.


%! printer:print_slot_restriction(S)
%
% Prints slot restriction for a package dependency

printer:print_slot_restriction([]) :- !.

printer:print_slot_restriction([any_different_slot]) :-
  message:color(lightgray),
  write(':*'),
  message:color(normal).

printer:print_slot_restriction([any_same_slot]) :-
  message:color(lightgray),
  write(':='),
  message:color(normal).

printer:print_slot_restriction([slot(Slot)]) :-
  message:color(lightgray),
  write(':'),
  write(Slot),
  message:color(normal).

printer:print_slot_restriction([slot(Slot),equal]) :-
  message:color(lightgray),
  write(':'),
  write(Slot),
  write('='),
  message:color(normal).

printer:print_slot_restriction([slot(Slot),subslot(Subslot)]) :-
  message:color(lightgray),
  write(':'),
  write(Slot),
  write('/'),
  write(Subslot),
  message:color(normal).

printer:print_slot_restriction([slot(Slot),subslot(Subslot),equal]) :-
  message:color(lightgray),
  write(':'),
  write(Slot),
  write('/'),
  write(Subslot),
  write('='),
  message:color(normal).


% -----------------------------------------------------------------------------
%  Plan printing
% -----------------------------------------------------------------------------

%! printer:printable_element(+Literal)
%
% Declares which Literals are printable

printer:printable_element(rule(uri(_,_,_),_)) :- !.
printer:printable_element(rule(uri(_),_)) :- !.
printer:printable_element(rule(_Repository://_Entry:run?_,_)) :- !.
printer:printable_element(rule(_Repository://_Entry:run?_,_)) :- !.
printer:printable_element(rule(_Repository://_Entry:download?_,_)) :- !.
printer:printable_element(rule(_Repository://_Entry:install?_,_)) :- !.
printer:printable_element(rule(_Repository://_Entry:reinstall?_,_)) :- !.
printer:printable_element(rule(_Repository://_Entry:uninstall?_,_)) :- !.

% Suppress printing the "wrapper" update target when it schedules the actual
% transactional update on a chosen replacement version.
printer:printable_element(rule(_Repository://_Entry:update?{_Context},Body)) :-
  member(_NewRepo://_NewEntry:update?{_}, Body),
  !,
  fail.

printer:printable_element(rule(_Repository://_Entry:update?_,_)) :- !.
printer:printable_element(rule(_Repository://_Entry:upgrade?_,_)) :- !.
% Prover cycle-break rules (`assumed(rule(...))`) are printed in the warnings
% section with cycle explanations. Do not print them as "verify" steps.
printer:printable_element(assumed(rule(_,_))) :- !, fail.
printer:printable_element(rule(assumed(_Repository://_Entry:_?_,_))) :- !.
printer:printable_element(assumed(rule(package_dependency(_,_,_,_,_,_,_,_):install?_,_))) :- !.
printer:printable_element(assumed(rule(package_dependency(_,_,_,_,_,_,_,_):run?_,_))) :- !.
printer:printable_element(rule(assumed(package_dependency(_,_,_,_,_,_,_,_):install?_,_))) :- !.
printer:printable_element(rule(assumed(package_dependency(_,_,_,_,_,_,_,_):run?_,_))) :- !.
printer:printable_element(assumed(rule(grouped_package_dependency(_,_,_,_):install?_,_))) :- !. % todo: phase out
printer:printable_element(assumed(rule(grouped_package_dependency(_,_,_,_):run?_,_))) :- !. % todo: phase out
printer:printable_element(assumed(rule(grouped_package_dependency(_,_,_):install?_,_))) :- !.
printer:printable_element(assumed(rule(grouped_package_dependency(_,_,_):run?_,_))) :- !.
printer:printable_element(rule(assumed(grouped_package_dependency(_,_,_):install?_),_)) :- !.
printer:printable_element(rule(assumed(grouped_package_dependency(_,_,_):run?_),_)) :- !.

% Suppress assumed dependency verifies when a concrete ebuild for the same
% package is already scheduled in the plan.
printer:printable_element(rule(assumed(grouped_package_dependency(C,N,_Deps):install?{_Context}),[])) :-
  printer:planned_pkg(install, C, N),
  !,
  fail.
printer:printable_element(rule(assumed(package_dependency(install,no,C,N,_,_,_,_):install?{_Context}),[])) :-
  printer:planned_pkg(install, C, N),
  !,
  fail.
printer:printable_element(rule(assumed(grouped_package_dependency(C,N,_Deps):run?{_Context}),[])) :-
  printer:planned_pkg(run, C, N),
  !,
  fail.
printer:printable_element(rule(assumed(package_dependency(run,no,C,N,_,_,_,_):run?{_Context}),[])) :-
  printer:planned_pkg(run, C, N),
  !,
  fail.


% Uncomment if you want 'confirm' steps shown in the plan:
% printer:printable_element(rule(package_dependency(run,_,_,_,_,_,_,_),_)) :- !.


%! printer:element_weight(+Literal)
%
% Declares a weight for ordering elements of a step in a plan

printer:element_weight(assumed(_),                                      0) :- !. % assumed
printer:element_weight(rule(assumed(_),_),                              0) :- !. % assumed
printer:element_weight(rule(uri(_),_),                                  0) :- !. % provide
printer:element_weight(rule(uri(_,_,_),_),                              1) :- !. % fetch
printer:element_weight(rule(package_dependency(_,_,_,_,_,_,_,_),_),     1) :- !. % confirm
printer:element_weight(rule(_Repository://_Entry:verify?_,_),           2) :- !. % verify
% Run should come after install within a step.
printer:element_weight(rule(_Repository://_Entry:run?_,_),              6) :- !. % run
printer:element_weight(rule(_Repository://_Entry:download?_,_),         4) :- !. % download
printer:element_weight(rule(_Repository://_Entry:fetchonly?_,_),        5) :- !. % fetchonly
printer:element_weight(rule(_Repository://_Entry:install?_,_),          5) :- !. % install
printer:element_weight(rule(_Repository://_Entry:reinstall?_,_),        6) :- !. % reinstall
printer:element_weight(rule(_Repository://_Entry:uninstall?_,_),        6) :- !. % uninstall
printer:element_weight(rule(_Repository://_Entry:update?_,_),           6) :- !. % update
printer:element_weight(rule(_Repository://_Entry:upgrade?_,_),          6) :- !. % upgrade
printer:element_weight(_,                                               7) :- !. % everything else


%! printer:sort_by_weight(+Comparator,+Literal,+Literal)
%
% Sorts elements in a plan by weight

printer:sort_by_weight(C,L1,L2) :-
  printer:element_weight(L1,W1),
  printer:element_weight(L2,W2),
  compare(C,W1:L1,W2:L2).


%! printer:print_element(+Printable)
%
% Prints a printable Literal

printer:print_element(_,rule(package_dependency(run_post,_,_C,_N,_,_,_,_),[Repository://Entry:_Action?{_Context}])) :-
  !,
  message:color(cyan),
  message:print('confirm'),
  message:color(green),
  message:column(24,Repository://Entry),
  message:color(normal).



% ---------------------------------------------
% CASE: simple package, is a target of the plan
% ---------------------------------------------

printer:print_element(Target,rule(Repository://Entry:Action?{Context},_Body)) :-
  ( member(Repository://Entry:Action?_,Target)
  ; Action == update,
    memberchk(replaces(OldRepo://OldEntry), Context),
    member(OldRepo://OldEntry:update?_, Target)
  ),
  !,
  %message:color(cyan),
  message:bubble(green,Action),
  message:style(bold),
  message:color(green),
  message:column(24,Repository://Entry),
  ( Action == update,
    memberchk(replaces(OldRepo2://OldEntry2), Context)
  -> message:color(lightgray),
     message:print(' (replaces '),
     message:color(green),
     message:print(OldRepo2://OldEntry2),
     message:color(lightgray),
     message:print(')'),
     message:color(normal)
  ; true
  ),
  % Ensure inline notes (e.g. blocker annotations) don't inherit the bold style
  % used for target entries.
  message:style(normal),
  printer:print_blocker_note_if_any(Action, Repository, Entry),
  printer:print_newuse_note_if_any(Action, Context),
  message:color(normal),
  printer:print_config(Repository://Entry:Action?{Context}).


% -------------------------------------------------
% CASE: simple package, is not a target of the plan
% -------------------------------------------------

printer:print_element(_,rule(Repository://Entry:Action?{Context},_)) :-
  message:color(cyan),
  message:print(Action),
  message:color(green),
  message:column(24,Repository://Entry),
  ( Action == update,
    memberchk(replaces(OldRepo://OldEntry), Context)
  -> message:color(lightgray),
     message:print(' (replaces '),
     message:color(green),
     message:print(OldRepo://OldEntry),
     message:color(lightgray),
     message:print(')'),
     message:color(normal)
  ; true
  ),
  printer:print_blocker_note_if_any(Action, Repository, Entry),
  printer:print_newuse_note_if_any(Action, Context),
  message:color(normal),
  printer:print_config(Repository://Entry:Action?{Context}).


% --------------------------------------------------------------
% CASE: verify that packages that need to be running are running
% --------------------------------------------------------------

printer:print_element(_,rule(package_dependency(run,_,_C,_N,_,_,_,_),[Repository://Entry:_Action?{_Context}])) :-
  !,
  message:color(cyan),
  message:print('confirm'),
  message:color(green),
  message:column(24,Repository://Entry),
  message:color(normal).


% ----------------
% CASE: a download
% ----------------

printer:print_element(_,rule(uri(Protocol,Remote,_Local),_)) :-
  !,
  message:color(cyan),
  message:print('fetch'),
  message:color(green),
  message:column(24,Protocol://Remote),
  message:color(normal).

printer:print_element(_,rule(uri(Local),_)) :-
  !,
  message:color(cyan),
  message:print('provide'),
  message:color(green),
  message:column(24,Local),
  message:color(normal).


% ---------------------------------------------------------------
% CASE: an assumed dependency on a non-existent installed package
% ---------------------------------------------------------------

printer:print_element(_,rule(assumed(grouped_package_dependency(C,N,_Deps):install?{_Context}),[])) :-
  message:bubble(red,'verify'),
  message:color(red),
  atomic_list_concat([C,'/',N],P),
  message:column(24,P),
  message:print(' (non-existent, assumed installed)'),
  message:color(normal).


printer:print_element(_,rule(assumed(package_dependency(install,no,C,N,_,_,_,_):install?{_Context}),[])) :-
  message:bubble(red,'verify'),
  message:color(red),
  atomic_list_concat([C,'/',N],P),
  message:column(24,P),
  message:print(' (non-existent, assumed installed)'),
  message:color(normal).


% -------------------------------------------------------------
% CASE: an assumed dependency on a non-existent running package
% -------------------------------------------------------------

printer:print_element(_,rule(assumed(grouped_package_dependency(C,N,_Deps):run?{_Context}),[])) :-
  message:bubble(red,'verify'),
  message:color(red),
  atomic_list_concat([C,'/',N],P),
  message:column(24,P),
  message:print([' (non-existent, assumed running)']),
  message:color(normal).


printer:print_element(_,rule(assumed(package_dependency(run,no,C,N,_,_,_,_):run?{_Context}),[])) :-
  message:bubble(red,'verify'),
  message:color(red),
  atomic_list_concat([C,'/',N],P),
  message:column(24,P),
  message:print([' (non-existent, assumed running)']),
  message:color(normal).


% ---------------------------------
% CASE: an assumed unmasked package
% ---------------------------------

printer:print_element(_,rule(assumed(Repository://Entry:unmask?{_Context}),_Body)) :-
  message:bubble(red,'verify'),
  message:color(red),
  message:column(24,Repository://Entry),
  message:print(' (masked)'),
  message:color(normal).


% ----------------------------------
% CASE: an assumed installed package
% ----------------------------------

printer:print_element(_,assumed(rule(Repository://Entry:install?{_Context},_Body))) :-
  message:bubble(red,'verify'),
  message:color(red),
  message:column(24,Repository://Entry),
  message:print(' (assumed installed)'),
  message:color(normal).


% --------------------------------
% CASE: an assumed running package
% --------------------------------

printer:print_element(_,assumed(rule(Repository://Entry:run?{_Context},_Body))) :-
  message:bubble(red,'verify'),
  message:color(red),
  message:column(24,Repository://Entry),
  message:print(' (assumed running) '),
  message:color(normal).


% --------------------------------
% CASE: an assumed fetched package
% --------------------------------

printer:print_element(_,assumed(rule(Repository://Entry:fetchonly?{_Context},_Body))) :-
  message:bubble(red,'verify'),
  message:color(red),
  message:column(24,Repository://Entry),
  message:print(' (assumed fetched) '),
  message:color(normal).


% -------------------------------------
% CASE: an assumed installed dependency
% -------------------------------------

printer:print_element(_,assumed(rule(package_dependency(install,_,C,N,_,_,_,_):_Action?{_Context},_Body))) :-
  message:bubble(red,'verify'),
  message:color(red),
  atomic_list_concat([C,'/',N],P),
  message:column(24,P),
  message:print(' (assumed installed) '),
  message:color(normal).


% -----------------------------------
% CASE: an assumed running dependency
% -----------------------------------

printer:print_element(_,assumed(rule(package_dependency(run,_,C,N,_,_,_,_):_Action?{_Context},_Body))) :-
  message:bubble(red,'verify'),
  message:color(red),
  atomic_list_concat([C,'/',N],P),
  message:column(24,P),
  message:print(' (assumed running) '),
  message:color(normal).


% -------------------------------------------------------------
% CASE: an assumed circular dependency
% -------------------------------------------------------------

printer:print_element(_,assumed(rule(grouped_package_dependency(_X,C,N,_Deps):install?{_Context},_Body))) :-
  !,
  message:bubble(red,'verify'),
  message:color(red),
  atomic_list_concat([C,'/',N],P),
  message:column(24,P),
  message:print(' (assumed installed) '),
  message:color(normal).

printer:print_element(_,assumed(rule(grouped_package_dependency(_X,C,N,_Deps):run?{_Context},_Body))) :-
  !,
  message:bubble(red,'verify'),
  message:color(red),
  atomic_list_concat([C,'/',N],P),
  message:column(24,P),
  message:print(' (assumed running) '),
  message:color(normal).


%! printer:print_config_prefix(+Word)
%
% prints the prefix for a config item

% -------------------------------
% CASE: Fancy build plan printing
% -------------------------------

printer:print_config_prefix(Word) :-
  config:printing_style('fancy'),!,
  nl,write('             │           '),
  message:color(darkgray),
  message:print('└─ '),
  message:print(Word),
  message:print(' ─┤ '),
  message:color(normal).

% -------------------------------
% CASE: Short build plan printing
% -------------------------------

printer:print_config_prefix(_Word) :-
  config:printing_style('short'),!,
  nl,write('             │           ').

% --------------------------------
% CASE: Column build plan printing
% --------------------------------

printer:print_config_prefix(file) :-
  config:printing_style('column'),!,
  message:column(104,' ').

printer:print_config_prefix(live) :-
  config:printing_style('column'),!,
  message:column(104,' ').

printer:print_config_prefix('conf') :-
  config:printing_style('column'), !,
  message:column(104,' ').


%! printer:print_config_prefix
%
% prints the prefix for a config item

printer:print_config_prefix :-
  config:printing_style('fancy'),!,
  nl,write('             │          '),
  message:color(darkgray),
  message:print('          │ '),
  message:color(normal).

printer:print_config_prefix :-
  config:printing_style('short'),!,
  nl,write('             │           ').

printer:print_config_prefix :-
  config:printing_style('column'),!,
  nl,write('             │ '),
  message:column(104,' ').


%! printer:print_config(+Repository://+Entry:+Action:+Context)
%
% Prints the configuration for a given repository entry (USE flags, USE expand, ...)

% ----------------------
% CASE: fetchonly action
% ----------------------

% iuse empty

printer:print_config(Repository://Entry:fetchonly?{_Context}) :-
  \+(kb:query(iuse(_),Repository://Entry)),!.

% use flags to show - to rework: performance

printer:print_config(Repository://Entry:fetchonly?{Context}) :-
 !,
 findall(Use,
         (member(Term,Context),
          (Term = required_use(Uses) ; Term = build_with_use(Uses)),
           member(assumed(Use),Uses)),
         Assumed),
 findall([Reason,Group], group_by(Reason, Use, kb:query(iuse_filtered(Use,Reason),Repository://Entry), Group), Useflags),

 (Useflags == [] ;
   (printer:print_config_prefix('conf'),	                  % Use flags not empty
    printer:print_config_item('use',Useflags,Assumed))).    % Use flags not empty



% ---------------------
% CASE: download action
% ---------------------

% live downloads

printer:print_config(Repository://Ebuild:download?{_Context}) :-
  ebuild:is_live(Repository://Ebuild),!,
  printer:print_config_prefix('live'),
  printer:print_config_item('download','git repository','live').


% no downloads

printer:print_config(Repository://Ebuild:download?{_Context}) :-
  \+(kb:query(manifest(preference,_,_,_),Repository://Ebuild)),!.


% at least one download

printer:print_config(Repository://Ebuild:download?{_Context}) :-
  !,
  findall([File,Size],kb:query(manifest(preference,_,File,Size),Repository://Ebuild),Downloads),
  sort(Downloads,[[FirstFile,FirstSize]|Rest]),
  printer:print_config_prefix('file'),
  printer:print_config_item('download',FirstFile,FirstSize),
  forall(member([RestFile,RestSize],Rest),
         (printer:print_config_prefix,
          printer:print_config_item('download',RestFile,RestSize))).


% --------------------
% CASE: Install action
% --------------------

% iuse empty

printer:print_config(Repository://Entry:install?{Context}) :-
  \+(kb:query(iuse(_),Repository://Entry)),!,
  (memberchk(slot(_,_,Slot):{Repository://Entry},Context)
  -> (Slot \== [slot('0')] ->
        printer:print_config_prefix('conf'),
        printer:print_config_item('slot',Slot)
      ; true)
  ;  true).

% use flags to show

printer:print_config(Repository://Entry:install?{Context}) :-
  !,
  findall(Use,
         (member(Term,Context),
          (Term = required_use(Uses) ; Term = build_with_use(Uses)),
           member(assumed(Use),Uses)),
         Assumed),

  % Get regular USE flags (filtered, excluding USE_EXPAND)
  findall([Reason,Group], group_by(Reason, Use, kb:query(iuse_filtered(Use,Reason),Repository://Entry), Group), Useflags),

  % Get all USE flags (including USE_EXPAND ones) for USE_EXPAND processing
  findall(Use, kb:query(iuse(Use, _Reason), Repository://Entry), AllUseFlags),

  % Separate regular USE flags from USE_EXPAND flags
  partition(printer:is_use_expand_flag, AllUseFlags, UseExpandFlags, _RegularUseFlags),

  % Group USE_EXPAND flags by expand key and reason
  findall([ExpandKey, ExpandFlags],
          printer:group_use_expand_flags(UseExpandFlags, ExpandKey, ExpandFlags, Repository://Entry),
          UseExpandVariables),

  % Filter out empty USE_EXPAND variables
  include(printer:valid_use_expand, UseExpandVariables, ValidUseExpandVariables),

  % Check if a slot is present in the context
  (memberchk(slot(_,_,Slot):{Repository://Entry},Context)
  -> % Check if slot is relevant to print
     (Slot \== [slot('0')]
     -> % Case 1: Use flags and Expanded Use flags empty
         (Useflags == [], ValidUseExpandVariables == []
          -> % print just the slot
             printer:print_config_prefix('conf'),
             printer:print_config_item('slot',Slot)
          ;  % print algined configuration
           printer:print_config_prefix('conf'),
           printer:print_config_items_aligned(Useflags, ValidUseExpandVariables, Assumed, Slot)
        )
     ; (Useflags == [], ValidUseExpandVariables == [] ;
          (printer:print_config_prefix('conf'),
           printer:print_config_items_aligned(Useflags, ValidUseExpandVariables, Assumed, []))))
  ;  (Useflags == [], ValidUseExpandVariables == [] ;
       (printer:print_config_prefix('conf'),
        printer:print_config_items_aligned(Useflags, ValidUseExpandVariables, Assumed, [])))),!.


% --------------------
% CASE: Update action
% --------------------
%
% Print the same configuration block as for installs (USE flags, USE_EXPAND, slot).
% Update actions are transactional same-slot replacements, so the config shown is
% for the *new* version being merged.

printer:print_config(Repository://Entry:update?{Context}) :-
  !,
  printer:print_config(Repository://Entry:install?{Context}).


% ----------------
% CASE: Run action
% ----------------

printer:print_config(_://_:run?{_Context}) :- !.


% -------------------
% CASE: Other actions
% -------------------

printer:print_config(_://_:_?_) :- !.



% Helper predicate: Check if a USE flag is a USE_EXPAND flag
printer:is_use_expand_flag(UseFlag) :-
  eapi:use_expand(ExpandKey),
  eapi:check_prefix_atom(ExpandKey, UseFlag).

% Helper predicate: Group USE_EXPAND flags by expand key
printer:group_use_expand_flags(UseExpandFlags, ExpandKey, ExpandFlags, Repository://Entry) :-
  eapi:use_expand(ExpandKey),
  \+ preference:use_expand_hidden(ExpandKey),
  findall(UseFlag,
          (member(UseFlag, UseExpandFlags),
           eapi:check_prefix_atom(ExpandKey, UseFlag)),
          MatchingFlags),
  MatchingFlags \== [],
  % Group by reason and extract suffix
  findall([Reason, Group],
          group_by(Reason, Suffix,
                   (member(UseFlag, MatchingFlags),
                    eapi:strip_prefix_atom(ExpandKey, UseFlag, Suffix),
                    kb:query(iuse(UseFlag, Reason), Repository://Entry)),
                   Group),
          ExpandFlags).

% Helper predicate: Check if USE_EXPAND variable is valid (not empty)
printer:valid_use_expand([_Key, Flags]) :-
  Flags \== [].



% Helper predicate: Collect flags for USE_EXPAND variables
printer:collect_expand_flags(Keyflags, AllFlags) :-
  (memberchk([negative:default,NegDefa],Keyflags);    NegDefa=[]),
  (memberchk([negative:ebuild,NegEbui],Keyflags);     NegEbui=[]),
  (memberchk([negative:preference,NegPref],Keyflags); NegPref=[]),
  (memberchk([positive:ebuild,PosEbui],Keyflags);     PosEbui=[]),
  (memberchk([positive:preference,PosPref],Keyflags); PosPref=[]),
  sort(PosPref, OPosPref),
  sort(PosEbui, OPosEbui),
  sort(NegPref, ONegPref),
  sort(NegEbui, ONegEbui),
  sort(NegDefa, ONegDefa),
  maplist(printer:to_flag_term(positive:preference, []), OPosPref, FlagsPosPref),
  maplist(printer:to_flag_term(positive:ebuild, []), OPosEbui, FlagsPosEbui),
  maplist(printer:to_flag_term(negative:preference, []), ONegPref, FlagsNegPref),
  maplist(printer:to_flag_term(negative:ebuild, []), ONegEbui, FlagsNegEbui),
  maplist(printer:to_flag_term(negative:default, []), ONegDefa, FlagsNegDefa),
  append([FlagsPosPref, FlagsPosEbui, FlagsNegPref, FlagsNegEbui, FlagsNegDefa], AllFlags).


% Helper predicate: Print configuration items with aligned equals signs
printer:print_config_items_aligned(Useflags, ValidUseExpandVariables, Assumed, Slot) :-

  % 1. First print USE flags with proper formatting and alignment
  printer:print_config_item_aligned('use', Useflags, Assumed),

  % 2. Second print USE_EXPAND variables with proper formatting and alignment
  (ValidUseExpandVariables == [] -> true ;
   forall(member([Key, Keyflags], ValidUseExpandVariables),
          (printer:print_config_prefix,
           printer:print_config_item_aligned(Key, Keyflags, [])))),

  % 3. Lastly print SLOT with proper formatting and alignment
  (Slot == [] -> true ;
   (printer:print_config_prefix,
    printer:print_config_item_aligned('slot', Slot, []))).



% Helper predicate: Collect all configuration items
printer:collect_config_items(Useflags, ValidUseExpandVariables, Assumed, Slot, ConfigItems) :-
  findall(Item, printer:collect_single_config_item(Useflags, ValidUseExpandVariables, Assumed, Slot, Item), ConfigItems).

% Helper predicate: Collect individual configuration items
printer:collect_single_config_item(Useflags, _, Assumed, _, config_item('use', Useflags, Assumed)) :-
  Useflags \== [].
printer:collect_single_config_item(_, ValidUseExpandVariables, _, _, config_item(Key, Keyflags, [])) :-
  member([Key, Keyflags], ValidUseExpandVariables).
printer:collect_single_config_item(_, _, _, Slot, config_item('slot', Slot, [])) :-
  Slot \== [].


% Helper predicate: Print aligned configuration items
printer:print_aligned_config_items([]).
printer:print_aligned_config_items([config_item(Key, Value, Assumed)|Rest]) :-
  printer:print_aligned_config_item(Key, Value, Assumed),
  printer:print_aligned_config_items(Rest).

% Helper predicate: Print a single aligned configuration item
printer:print_aligned_config_item(Key, Value, Assumed) :-
  upcase_atom(Key, KeyU),
  message:bubble(darkgray,KeyU),
  message:print(' = "'),
  printer:print_config_value(Key, Value, Assumed),
  message:print('"').


% Helper predicate: Print Use flags
printer:print_config_item_aligned('use', List, Assumed) :-
  !,
  upcase_atom('use', KeyU),
  message:bubble(darkgray,KeyU),
  message:print(' = "'),
  catch(
      ( config:printing_tty_size(_, TermWidth),
        line_position(current_output, StartCol),
	printer:collect_all_flags(List, Assumed, AllFlags),
        printer:print_flags_wrapped(AllFlags, StartCol, TermWidth)
      ),
      error(io_error(check, stream(_)), _),
      ( printer:collect_all_flags(List, Assumed, AllFlags),
        printer:print_flags_unwrapped(AllFlags)
      )
  ),
  message:print('"').


printer:print_config_item_aligned('slot', Slot, _) :-
  !,
  upcase_atom('slot', KeyU),
  message:bubble(darkgray,KeyU),
  message:print(' = "'),
  message:color(darkgray),
  printer:print_slot_value(Slot),
  message:color(normal),
  message:print('"').

printer:print_config_item_aligned(Key, Keyflags, _) :-
  eapi:use_expand(Key),
  !,
  upcase_atom(Key, KeyU),
  message:bubble(darkgray,KeyU),
  message:print(' = "'),
  config:printing_tty_size(_, TermWidth),
  line_position(current_output, StartCol),
  printer:collect_expand_flags(Keyflags, AllFlags),
  printer:print_flags_wrapped(AllFlags,StartCol,TermWidth),
  message:print('"').

% Helper predicate: Print configuration value based on type
printer:print_config_value('use', List, Assumed) :-
  !,
  printer:collect_all_flags(List, Assumed, AllFlags),
  printer:print_flags_unwrapped(AllFlags).
printer:print_config_value('slot', Slot, _) :-
  !,
  printer:print_slot_value(Slot).
printer:print_config_value(Key, Keyflags, _) :-
  eapi:use_expand(Key),
  !,
  printer:collect_expand_flags(Keyflags, AllFlags),
  printer:print_flags_unwrapped(AllFlags).



%! printer:print_config_item(+Key,+Value)
%
% Prints a configuration item for a given repository entry

printer:print_config_item('download',File,'live') :-
  !,
  message:color(magenta),
  message:print_bytes('live'),
  message:color(normal),
  message:print(' '),
  message:print(File).

printer:print_config_item('download',File,Size) :-
  !,
  message:color(magenta),
  message:print_bytes(Size),
  message:color(normal),
  message:print(' '),
  message:print(File).

printer:print_config_item('use',List,Assumed) :- !,
  upcase_atom('use',KeyU),
  message:print(KeyU),
  message:print('="'),
  catch(
      ( config:printing_tty_size(_, TermWidth),
        line_position(current_output, StartCol),
        collect_all_flags(List, Assumed, AllFlags),
        print_flags_wrapped(AllFlags, StartCol, TermWidth, StartCol, 0)
      ),
      error(io_error(check, stream(_)), _),
      ( collect_all_flags(List, Assumed, AllFlags),
        print_flags_unwrapped(AllFlags)
      )
  ),
  message:print('"').

printer:print_config_item('slot',Slot) :- !,
  upcase_atom('slot',KeyS),
  message:bubble(darkgray,KeyS),
  message:print(' = "'),
  message:color(darkgray),
  printer:print_slot_value(Slot),
  message:color(normal),
  message:print('"').


% New print_config_item for USE_EXPAND variables
printer:print_config_item(Key, Keyflags) :-
  eapi:use_expand(Key),
  !,
  upcase_atom(Key, KeyU),
  message:print(KeyU),
  message:print('="'),
  printer:collect_expand_flags(Keyflags, AllFlags),
  printer:print_flags_unwrapped(AllFlags),
  message:print('"').


%! printer:print_slot_value(+Slot)
%
% Prints the slot value in a readable format

printer:print_slot_value([slot(Slot)]) :-
  !,
  message:print(Slot).

printer:print_slot_value([slot(Slot),subslot(Subslot)]) :-
  !,
  message:print(Slot),
  message:print('/'),
  message:print(Subslot).

printer:print_slot_value([slot(Slot),subslot(Subslot),equal]) :-
  !,
  message:print(Slot),
  message:print('/'),
  message:print(Subslot),
  message:print('=').

printer:print_slot_value([slot(Slot),equal]) :-
  !,
  message:print(Slot),
  message:print('=').

printer:print_slot_value(Slot) :-
  message:print(Slot).


%! printer:print_flags_wrapped(+AllFlags, +StartCol, +TermWidth, +IndentForWrap, +SpacesNeeded)
%
% Prints a list of flags wrapped to the terminal width.

printer:print_flags_wrapped([], _, _, _, _) :- !.
printer:print_flags_wrapped(AllFlags, StartCol, TermWidth) :-
    foldl(printer:print_one_flag_wrapped(StartCol,TermWidth),
          AllFlags,
          [StartCol, true],
          _).


%! printer:print_one_flag_wrapped(+TermWidth, +IndentForWrap, +SpacesNeeded, +FlagTerm, +StateIn, -StateOut)
%
% Prints a single flag wrapped to the terminal width.

printer:print_one_flag_wrapped(StartCol, TermWidth, flag(Type, Flag, Assumed), [ColIn, IsFirst], [ColOut, false]) :-
    printer:get_flag_length(Type, Flag, Assumed, FlagLen),
    (IsFirst -> SpaceLen = 0 ; SpaceLen = 1),
    (
        ( ColIn + SpaceLen + FlagLen > TermWidth )
    ->  % Wrap
        (
            printer:print_continuation_prefix(StartCol),      % go to next line, print prefix, jump to start position
            printer:print_use_flag(Type, Flag, Assumed),      % print flag
            ColOut is StartCol + FlagLen
        )
    ;   % No wrap
        (
            (IsFirst -> true ; write(' ')),
            printer:print_use_flag(Type, Flag, Assumed),
            ColOut is ColIn + SpaceLen + FlagLen
        )
    ).


%! printer:print_continuation_prefix(+IndentColumn)
%
% Prints the continuation prefix for wrapped flags.

printer:print_continuation_prefix(StartColumn) :-
    nl,

    ( config:printing_style('short')  ->
        write('             │ '),
        NewStartColumn is StartColumn - 1,
        message:column(NewStartColumn,'')
    );

    ( config:printing_style('column') ->
        write('             │ '),
        NewStartColumn is StartColumn - 1,
        message:column(NewStartColumn,'')
    );
    ( config:printing_style('fancy')  ->
        write('             │                    '),
        message:color(darkgray),
        write('│ '),
        NewStartColumn is StartColumn - 1,
        message:column(NewStartColumn,'')
    );
    true.


%! printer:collect_all_flags(+List, +Assumed, -AllFlags)
%
% Collects all flags from the list and assumed flags.

printer:collect_all_flags(List, Assumed, AllFlags) :-
    (memberchk([negative:default,NegDefa],List);    NegDefa=[]),
    (memberchk([negative:ebuild,NegEbui],List);     NegEbui=[]),
    (memberchk([negative:preference,NegPref],List); NegPref=[]),
    (memberchk([positive:ebuild,PosEbui],List);     PosEbui=[]),
    (memberchk([positive:preference,PosPref],List); PosPref=[]),
    sort(PosPref, OPosPref),
    sort(PosEbui, OPosEbui),
    sort(NegPref, ONegPref),
    sort(NegEbui, ONegEbui),
    sort(NegDefa, ONegDefa),
    maplist(to_flag_term(positive:preference, Assumed), OPosPref, FlagsPosPref),
    maplist(to_flag_term(positive:ebuild, Assumed), OPosEbui, FlagsPosEbui),
    maplist(to_flag_term(negative:preference, Assumed), ONegPref, FlagsNegPref),
    maplist(to_flag_term(negative:ebuild, Assumed), ONegEbui, FlagsNegEbui),
    maplist(to_flag_term(negative:default, Assumed), ONegDefa, FlagsNegDefa),
    append([FlagsPosPref, FlagsPosEbui, FlagsNegPref, FlagsNegEbui, FlagsNegDefa], AllFlags).


%! printer:to_flag_term(+Type, +Assumed, +Flag, -FlagTerm)
%
% Converts a flag to a flag term.

printer:to_flag_term(Type, Assumed, Flag, flag(Type, Flag, Assumed)).


%! printer:print_flags_unwrapped(+AllFlags)
%
% Prints a list of flags unwrapped.

printer:print_flags_unwrapped([]) :- !.
printer:print_flags_unwrapped([flag(Type, Flag, Assumed)|Rest]) :-
    printer:print_use_flag(Type, Flag, Assumed),
    (Rest == [] -> true ; write(' ')),
    printer:print_flags_unwrapped(Rest).


%! printer:get_flag_length(+Type, +Flag, +Assumed, -Length)
%
% Gets the length of a flag.

printer:get_flag_length(Type, Flag, Assumed, Length) :-
    (   memberchk(minus(Flag), Assumed) -> atom_length(Flag, L), Length is L + 1
    ;   memberchk(Flag, Assumed) -> atom_length(Flag, Length)
    ;   printer:get_flag_length_typed(Type, Flag, Length)
    ).

printer:get_flag_length_typed(positive:preference, Flag, Length) :-
    atom_length(Flag, L),
    ( preference:use(Flag,env) -> Length is L + 1 ; Length is L).

printer:get_flag_length_typed(positive:ebuild, Flag, Length) :-
    atom_length(Flag, Length).

printer:get_flag_length_typed(negative:preference, Flag, Length) :-
    atom_length(Flag, L),
    ( preference:use(minus(Flag),env) -> Length is L + 2 ; Length is L + 1).

printer:get_flag_length_typed(negative:ebuild, Flag, Length) :-
    atom_length(Flag, L),
    Length is L + 1.

printer:get_flag_length_typed(negative:default, Flag, Length) :-
    atom_length(Flag, L),
    Length is L + 1.


%! printer:print_use_flag(+Reason,+Flag,Assumed)
%
% Prints a single flag.

printer:print_use_flag(_Reason, Flag, Assumed) :-
  memberchk(minus(Flag), Assumed), !,
  message:color(orange),
  %message:style(bold),
  message:print('-'),
  message:print(Flag),
  message:color(normal).

printer:print_use_flag(_Reason, Flag, Assumed) :-
  memberchk(Flag, Assumed), !,
  message:color(orange),
  %message:style(bold),
  message:print(Flag),
  message:color(normal).

printer:print_use_flag(positive:preference, Flag, _Assumed) :-
  preference:use(Flag,env), !,
  message:color(green),
  message:style(bold),
  message:print(Flag),
  message:color(normal),
  message:print('*').

printer:print_use_flag(positive:preference, Flag, _Assumed) :-
  !,
  message:color(red),
  message:style(bold),
  message:print(Flag),
  message:color(normal).

printer:print_use_flag(positive:ebuild, Flag, _Assumed) :-
  !,
  message:color(red),
  message:style(italic),
  message:print(Flag),
  message:color(normal).

printer:print_use_flag(negative:preference, Flag, _Assumed) :-
  preference:use(minus(Flag),env), !,
  message:color(green),
  message:style(bold),
  message:print('-'),
  message:print(Flag),
  message:color(normal),
  message:print('*').

printer:print_use_flag(negative:preference, Flag, _Assumed) :-
  !,
  message:color(blue),
  message:style(bold),
  message:print('-'),
  message:print(Flag),
  message:color(normal).

printer:print_use_flag(negative:ebuild, Flag, _Assumed) :-
  !,
  message:color(lightblue),
  message:style(italic),
  message:print('-'),
  message:print(Flag),
  message:color(normal).

printer:print_use_flag(negative:default, Flag, _Assumed) :-
  !,
  message:color(darkgray),
  message:style(italic),
  message:print('-'),
  message:print(Flag),
  message:color(normal).


%! printer:check_assumptions(+Model)
%
% Checks whether the Model contains assumptions

printer:check_assumptions(Model) :-
  member(assumed(_),Model),!.


%! printer:print_header(+Target)
%
% Prints the header for a given target

printer:print_header(Target) :-
  nl,
  message:header('Emerging ',Target),
  message:color(green),
  message:print('These are the packages that would be merged, in order:'),nl,
  nl,
  message:color(normal),
  message:print('Calculating dependencies... done!'),nl,
  nl.


%! printer:print_body(+Target,+Plan,+Call,-Steps)
%
% Prints the body for a given plan.
printer:print_body(Target, Plan, Call, Steps) :-
  printer:build_planned_pkg_set(Plan, PlannedSet),
  setup_call_cleanup(
    nb_setval(printer_planned_pkg_set, PlannedSet),
    printer:print_steps_in_plan(Target, Plan, Call, 0, Steps),
    ( nb_current(printer_planned_pkg_set, _) -> nb_delete(printer_planned_pkg_set) ; true )
  ).

% Build a set of planned packages (category/name) for actions install/run.
% This allows suppressing "assumed dependency verify" lines when a concrete
% ebuild for the same package is already scheduled in the plan.
printer:build_planned_pkg_set(Plan, Set) :-
  empty_assoc(Empty),
  foldl(printer:build_planned_pkg_set_step, Plan, Empty, Set).

printer:build_planned_pkg_set_step(Step, In, Out) :-
  foldl(printer:build_planned_pkg_set_rule, Step, In, Out).

printer:build_planned_pkg_set_rule(Rule, In, Out) :-
  ( Rule = rule(HeadWithCtx, _Body)
  ; Rule = rule(assumed(HeadWithCtx), _Body)
  ),
  prover:canon_literal(HeadWithCtx, Head, _),
  ( Head = Repo://Entry:Action,
    ( Action == run ; Action == install ),
    cache:ordered_entry(Repo, Entry, C, N, _),
    Key = Action-C-N,
    ( get_assoc(Key, In, true) -> Out = In ; put_assoc(Key, In, true, Out) )
  ; Out = In
  ),
  !.
printer:build_planned_pkg_set_rule(_Other, Set, Set).

printer:planned_pkg(Action, C, N) :-
  nb_current(printer_planned_pkg_set, Set),
  get_assoc(Action-C-N, Set, true).

printer:is_run_cycle_break(Content) :-
  ( prover:canon_literal(Content, Core, _Ctx) -> true ; Core = Content ),
  Core = _ : run.

printer:print_cycle_break_detail(Content) :-
  ( prover:canon_literal(Content, Core, _Ctx) -> true ; Core = Content ),
  message:color(lightred),
  message:style(bold),
  message:print('- Cycle break: '),
  message:style(normal),
  message:color(normal),
  nl,
  message:print('  '),
  message:print(Core),
  nl.


%! printer:print_steps_in_plan(+Target,+Plan,+Call,+Count,-NewCount)
%
% Print the steps in a plan.

printer:print_steps_in_plan(_, [], _, Count, Count) :- !.

printer:print_steps_in_plan(Target, [Step|Rest], Call, Count, CountFinal) :-
  predsort(printer:sort_by_weight, Step, SortedRules),
  printer:print_first_in_step(Target, SortedRules, Count, CountNew),
  call(Call, SortedRules), !,
  printer:print_steps_in_plan(Target, Rest, Call, CountNew, CountFinal).


%! printer:print_first_in_step(+Target,+Step,+Count,-NewCount)
%
% Print a step in a plan
printer:print_first_in_step(_,[],Count,Count) :- !.

printer:print_first_in_step(Target,[Rule|Rest],Count,NewCount) :-
  printer:printable_element(Rule),
  NewCount is Count + 1,
  format(atom(AtomNewCount),'~t~0f~2|',[NewCount]),
  format(atom(StepNewCount),'step ~a',[AtomNewCount]),
  !,
  write(' └─'),
  message:bubble(darkgray,StepNewCount),
  write('─┤ '),
  printer:print_element(Target,Rule),
  printer:print_next_in_step(Target,Rest).

printer:print_first_in_step(Target,[_|Rest],Count,NewCount) :-
  printer:print_first_in_step(Target,Rest,Count,NewCount).


%! printer:print_next_in_step(+Target,+Step)
%
% Print a step in a plan
printer:print_next_in_step(_,[]) :- nl,nl,!.

printer:print_next_in_step(Target,[Rule|Rest]) :-
  printer:printable_element(Rule),
  !,
  nl,
  write('             │ '),
  printer:print_element(Target,Rule),
  printer:print_next_in_step(Target,Rest).

printer:print_next_in_step(Target,[_|Rest]) :-
  !,
  printer:print_next_in_step(Target,Rest).


%! printer:print_footer(+Plan, +ModelAVL, +PrintedSteps)
%
% Prints the footer for a given plan.

printer:print_footer(_Plan, ModelAVL, PrintedSteps) :-
  printer:footer_stats(ModelAVL, S),
  printer:pluralize(S.actions, action, actions, TotalStr),
  printer:pluralize(PrintedSteps, step, steps, PStr),
  printer:footer_action_breakdown(S, Breakdown),
  format('Total: ~d ~w (~w), grouped into ~d ~w.~n',
         [S.actions, TotalStr, Breakdown, PrintedSteps, PStr]),
  message:convert_bytes(S.total_dl, BytesStr),
  format('~7|~w to be downloaded.~n~n', [BytesStr]).

% Build the "(...)" part of the footer, omitting zero-count categories.
printer:footer_action_breakdown(S, Breakdown) :-
  findall(Part,
          ( printer:footer_action_part(downloads,  S.downloads,  download,  downloads,  Part)
          ; printer:footer_action_part(installs,   S.installs,   install,   installs,   Part)
          ; printer:footer_action_part(updates,    S.updates,    update,    updates,    Part)
          ; printer:footer_action_part(reinstalls, S.reinstalls, reinstall, reinstalls, Part)
          ; printer:footer_action_part(runs,       S.runs,       run,       runs,       Part)
          ),
          Parts0),
  ( Parts0 == [] ->
      Breakdown = none
  ; atomic_list_concat(Parts0, ', ', Breakdown)
  ).

printer:footer_action_part(_Key, Count, _Singular, _Plural, _Part) :-
  Count =:= 0,
  !,
  fail.
printer:footer_action_part(_Key, Count, Singular, Plural, Part) :-
  printer:pluralize(Count, Singular, Plural, Word),
  format(atom(Part), '~d ~w', [Count, Word]).


%! printer:pluralize(+Count, +Singular, +Plural, -Result)
%
% Pluralizes a word based on a count.

printer:pluralize(1, Singular, _, Singular) :- !.
printer:pluralize(_, _, Plural, Plural).


%! printer:footer_stats(+ModelAVL, -Stats)
%
% Calculates statistics by iterating over the ModelAVL using gen_assoc.

printer:footer_stats(ModelAVL, Stats) :-
   StatsInitial = stats{ass:0, con:0, naf:0, actions:0, fetches:0,
                        downloads:0, runs:0, installs:0, updates:0, reinstalls:0, total_dl:0},
   findall(Key, assoc:gen_assoc(Key, ModelAVL, _), Keys),
   foldl(printer:update_stats, Keys, StatsInitial, Stats).

%! printer:update_stats(+Key, +StatsIn, -StatsOut)
%
% Foldl helper to update stats

printer:update_stats(Key, S0, S) :-
  printer:update_stats_clauses(Key, S0, S).


%! printer:update_stats_clauses(+Key, +StatsIn, -StatsOut)
%
% The logic for updating stats based on a key.

printer:update_stats_clauses(assumed(_), S0, S) :-
  NewAss is S0.ass + 1, S = S0.put(ass, NewAss).
printer:update_stats_clauses(constraint(_), S0, S) :-
  NewCon is S0.con + 1, S = S0.put(con, NewCon).
printer:update_stats_clauses(naf(_), S0, S) :-
  NewNaf is S0.naf + 1, S = S0.put(naf, NewNaf).
printer:update_stats_clauses(_://_:fetchonly, S0, S) :-
  NewFetches is S0.fetches + 1, % NewActions is S0.actions + 1,
  S = S0.put(_{fetches:NewFetches}). %, actions:NewActions}).
printer:update_stats_clauses(R://E:download, S0, S) :-
  (ebuild:download_size(preference, R://E, Bytes) -> true ; Bytes = 0),
  NewDownloads is S0.downloads + 1, NewTotalDl is S0.total_dl + Bytes, NewActions is S0.actions + 1,
  S = S0.put(_{downloads:NewDownloads, total_dl:NewTotalDl, actions:NewActions}).
printer:update_stats_clauses(_://_:run, S0, S) :-
  NewRuns is S0.runs + 1, NewActions is S0.actions + 1,
  S = S0.put(_{runs:NewRuns, actions:NewActions}).
printer:update_stats_clauses(_://_:install, S0, S) :-
  NewInstalls is S0.installs + 1, NewActions is S0.actions + 1,
  S = S0.put(_{installs:NewInstalls, actions:NewActions}).
printer:update_stats_clauses(_://_:update, S0, S) :-
  NewUpdates is S0.updates + 1, NewActions is S0.actions + 1,
  S = S0.put(_{updates:NewUpdates, actions:NewActions}).
printer:update_stats_clauses(_://_:reinstall, S0, S) :-
  NewReinstalls is S0.reinstalls + 1, NewActions is S0.actions + 1,
  S = S0.put(_{reinstalls:NewReinstalls, actions:NewActions}).
printer:update_stats_clauses(_://_:_, S0, S) :-
  NewActions is S0.actions + 1, S = S0.put(actions, NewActions).
printer:update_stats_clauses(_, S, S).


%! printer:print_warnings(+ModelAVL, +ProofAVL, +TriggersAVL)
%
% Prints assumptions found in the proof/model.
%
% There are two distinct assumption mechanisms in this codebase:
%
% - Domain (rules.pl) assumptions:
%   A rule body may contain an `assumed(X)` literal to represent an unprovable
%   domain fact (e.g. missing dependency). The prover then proves `assumed(X)`
%   via `rule(assumed(_), [])`, resulting in a proof key of the shape:
%     - `rule(assumed(X))`
%
% - Prover cycle-break assumptions:
%   When the prover detects a circular proof, it breaks the loop by recording a
%   special proof key of the shape:
%     - `assumed(rule(X))`
%   These are "cycle breaks" (not domain facts). The printer explains them using
%   the Triggers graph to show a cycle path.

printer:print_warnings(ModelAVL, ProofAVL, TriggersAVL) :-
  once((assoc:gen_assoc(Key, ModelAVL, _), Key = assumed(_))),
  !,
  nl,
  findall(Content, (assoc:gen_assoc(rule(assumed(Content)), ProofAVL, _)), DomainAssumptions0),
  sort(DomainAssumptions0, DomainAssumptions),
  findall(Content, (assoc:gen_assoc(assumed(rule(Content)), ProofAVL, _)), CycleAssumptions0),
  sort(CycleAssumptions0, CycleAssumptions),
  ( DomainAssumptions \= [] ->
      ( printer:domain_assumptions_only_blockers(DomainAssumptions) ->
          message:bubble(orange,'Warning'),
          message:color(orange),
          message:print(' The proof for your build plan contains blocker assumptions. Please verify:'), nl, nl,
          message:color(orange)
      ; message:bubble(red,'Error'),
        message:color(red),
        message:print(' The proof for your build plan contains domain assumptions. Please verify:'), nl, nl,
        message:color(red)
      )
  ; CycleAssumptions \= [] ->
      message:bubble(orange,'Warning'),
      message:color(orange),
      message:print(' The proof for your build plan contains cycle breaks. Please verify:'), nl, nl,
      message:color(orange)
  ; message:bubble(red,'Error'),
  message:color(red),
    message:print(' The proof for your build plan contains assumptions. Please verify:'), nl, nl,
    message:color(red)
  ),
  ( DomainAssumptions \= [] ->
      message:header('Domain assumptions'),
      nl,
      forall(member(Content, DomainAssumptions),
             ( printer:print_assumption_detail(rule(Content, [])),
               nl ))
  ,   printer:print_blockers_portage_like(DomainAssumptions)
  ; true
  ),
  % Optional: print simple Gentoo Bugzilla bug report drafts when domain assumptions
  % are few (avoid overwhelming output for bulk runs like prover:test_stats/1).
  ( DomainAssumptions \= [] ->
      ( config:bugreport_drafts_enabled(true) ->
          ( config:bugreport_drafts_max_assumptions(MaxAss) -> true ; MaxAss = 25 ),
          length(DomainAssumptions, NAss),
          ( NAss =< MaxAss ->
              printer:print_bugreport_drafts(DomainAssumptions)
          ; true
          )
      ; true
      )
  ; true
  ),
  ( CycleAssumptions \= [] ->
      message:header('Cycle breaks (prover)'),
      nl,
      forall(member(Content, CycleAssumptions),
             ( ( printer:is_run_cycle_break(Content) ->
                     message:color(darkgray),
                     message:print('  (runtime SCC candidate)'), nl,
                     message:color(normal)
                 ; true
               ),
               printer:print_cycle_break_detail(Content),
               printer:print_cycle_explanation(Content, TriggersAVL),
               nl
             ))
  ; true
  ),
  nl,
  message:color(normal),nl.

printer:print_warnings(_,_,_) :- !, nl.


% -----------------------------------------------------------------------------
%  Blocker assumptions (Portage-like summary)
% -----------------------------------------------------------------------------

printer:domain_assumptions_only_blockers([]) :- !, fail.
printer:domain_assumptions_only_blockers(DomainAssumptions) :-
  \+ ( member(C, DomainAssumptions),
       \+ printer:is_blocker_assumption(C)
     ).

printer:is_blocker_assumption(blocker(_Strength, _Phase, _C, _N, _O, _V, _SlotReq)?{_Ctx}) :- !.
printer:is_blocker_assumption(blocker(_Strength, _Phase, _C, _N, _O, _V, _SlotReq)) :- !.
printer:is_blocker_assumption(_) :- fail.

printer:print_blockers_portage_like(DomainAssumptions) :-
  findall(line(Strength, Phase, BlockAtom, RequiredBy),
          ( member(Content, DomainAssumptions),
            printer:blocker_assumption_line(Content, Strength, Phase, BlockAtom, RequiredBy)
          ),
          Lines0),
  sort(Lines0, Lines),
  ( Lines == [] ->
      true
  ; nl,
    message:header('Blockers (Portage-like, assumed)'),
    nl,
    forall(member(line(Strength, Phase, BlockAtom, RequiredBy), Lines),
           printer:print_blocker_line(Strength, Phase, BlockAtom, RequiredBy)),
    nl
  ).

printer:blocker_assumption_line(Content, Strength, Phase, BlockAtom, RequiredBy) :-
  ( Content = blocker(Strength, Phase, C, N, O, V, SlotReq)?{Ctx} ->
      true
  ; Content = blocker(Strength, Phase, C, N, O, V, SlotReq),
    Ctx = []
  ),
  printer:blocker_atom(Strength, C, N, O, V, SlotReq, BlockAtom),
  ( memberchk(self(RequiredBy0), Ctx) -> RequiredBy = RequiredBy0 ; RequiredBy = unknown ).

printer:blocker_atom(Strength, C, N, O, V0, SlotReq, Atom) :-
  ( Strength == strong -> Bang = '!!' ; Bang = '!' ),
  printer:comparator_symbol(O, Sym),
  ( var(V0) -> V = '' ; printer:version_atom(V0, V) ),
  printer:blocker_slot_suffix(SlotReq, SlotSuf),
  ( V == '' ->
      format(atom(Atom), '~w~w~w/~w~w', [Bang, Sym, C, N, SlotSuf])
  ; format(atom(Atom), '~w~w~w/~w-~w~w', [Bang, Sym, C, N, V, SlotSuf])
  ).

printer:blocker_slot_suffix([], '') :- !.
printer:blocker_slot_suffix([slot(S)], Suf) :- !, format(atom(Suf), ':~w', [S]).
printer:blocker_slot_suffix([slot(S),subslot(Ss)], Suf) :- !, format(atom(Suf), ':~w/~w', [S, Ss]).
printer:blocker_slot_suffix([slot(S),equal], Suf) :- !, format(atom(Suf), ':~w', [S]).
printer:blocker_slot_suffix([slot(S),subslot(Ss),equal], Suf) :- !, format(atom(Suf), ':~w/~w', [S, Ss]).
printer:blocker_slot_suffix(_Other, '').

printer:print_blocker_line(Strength, Phase, BlockAtom, RequiredBy) :-
  ( Strength == strong ->
      StrengthLabel = 'hard'
  ; StrengthLabel = 'soft'
  ),
  message:color(darkgray),
  format('  [blocks B] ~w (~w blocker, phase: ~w, required by: ~w)~n',
         [BlockAtom, StrengthLabel, Phase, RequiredBy]),
  message:color(normal).


% -----------------------------------------------------------------------------
%  Bug report drafts (domain assumptions)
% -----------------------------------------------------------------------------

printer:print_bugreport_drafts(DomainAssumptions) :-
  printer:bugreport_groups(DomainAssumptions, Groups),
  ( Groups == [] ->
      true
  ; nl,
    message:header('Bug report drafts (Gentoo Bugzilla)'),
    nl,
    forall(member(G, Groups),
           ( printer:print_bugreport_group(G),
             nl ))
  ).

% Group per (Reason, C/N, Constraints, RequiredBy), merging run/install variants.
printer:bugreport_groups(DomainAssumptions, Groups) :-
  findall(Key-Issue,
          ( member(Content, DomainAssumptions),
            printer:bugreport_issue(Content, Key, Issue)
          ),
          Pairs0),
  keysort(Pairs0, Pairs),
  group_pairs_by_key(Pairs, Grouped),
  findall(Group,
          ( member(_Key-Issues, Grouped),
            printer:merge_bugreport_issues(Issues, Group)
          ),
          Groups).

printer:bugreport_issue(Content, Key, issue(Reason, RequiredBy, C, N, Constraints, Actions)) :-
  % Only handle grouped_package_dependency assumptions for now (these dominate).
  Content = grouped_package_dependency(C,N,PackageDeps):Action?{Ctx},
  !,
  % Extract reason from context if present; otherwise keep a stable placeholder.
  ( explainer:term_ctx(Content, CtxList),
    memberchk(assumption_reason(Reason0), CtxList)
  -> true
  ; Reason0 = unknown
  ),
  ( Reason0 == none -> Reason = unsatisfied_constraints ; Reason = Reason0 ),
  ( memberchk(self(RequiredBy), Ctx) -> true ; RequiredBy = unknown ),
  printer:extract_constraints_from_packagedeps(C, N, PackageDeps, Constraints),
  Actions = [Action],
  Key = Reason-RequiredBy-C-N-Constraints.
printer:bugreport_issue(_Other, _Key, _Issue) :-
  fail.

printer:merge_bugreport_issues(Issues, group(Reason, RequiredBy, C, N, Constraints, ActionsU)) :-
  Issues = [issue(Reason, RequiredBy, C, N, Constraints, Actions0)|Rest],
  findall(A,
          ( member(issue(_,_,_,_,_,As), [issue(Reason, RequiredBy, C, N, Constraints, Actions0)|Rest]),
            member(A, As)
          ),
          ActionsAll),
  sort(ActionsAll, ActionsU).

printer:extract_constraints_from_packagedeps(C, N, PackageDeps, Constraints) :-
  findall(constraint(O,V,S),
          ( member(package_dependency(_Action,no,C,N,O,Ver,S,_U), PackageDeps),
            printer:version_atom(Ver, V)
          ),
          Cs0),
  sort(Cs0, Constraints).

printer:version_atom([_,_,_,A], A) :- !.
printer:version_atom([_,_,_,_,A], A) :- !.
printer:version_atom(A, A).

printer:print_bugreport_group(group(Reason, RequiredBy, C, N, Constraints, Actions)) :-
  printer:bugreport_summary(Reason, RequiredBy, C, N, Summary),
  message:color(darkgray),
  message:print('---'), nl,
  message:color(normal),
  message:style(bold),
  message:print('Summary: '),
  message:style(normal),
  message:print(Summary),
  nl, nl,
  message:style(bold),
  message:print('Affected package: '),
  message:style(normal),
  message:color(darkgray),
  message:print(RequiredBy),
  message:color(normal),
  nl,
  message:style(bold),
  message:print('Dependency: '),
  message:style(normal),
  message:color(darkgray),
  format('~w/~w', [C, N]),
  message:color(normal),
  nl,
  message:style(bold),
  message:print('Phases: '),
  message:style(normal),
  message:color(darkgray),
  format('~w', [Actions]),
  message:color(normal),
  nl, nl,
  message:style(bold),
  message:print('Unsatisfiable constraint(s):'),
  message:style(normal),
  nl,
  forall(member(constraint(O,V,S), Constraints),
         ( message:color(darkgray),
           write('  '),
           printer:print_bugreport_constraint(O, C, N, V, S),
           message:color(normal),
           nl
         )),
  nl,
  message:style(bold),
  message:print('Observed:'),
  message:style(normal),
  nl,
  message:color(darkgray),
  format('  portage-ng reports no available candidate satisfies the above constraint(s).~n', []),
  ( printer:available_versions(C, N, Vs),
    Vs \= [],
    printer:available_version_count_unique(C, N, CountU)
  -> length(Vs, SampleN),
     format('  Available versions in repo set (sample, first ~d of ~d): ~w~n', [SampleN, CountU, Vs])
  ; true
  ),
  message:color(normal),
  nl,
  message:style(bold),
  message:print('Potential fix (suggestion):'),
  message:style(normal),
  nl,
  message:color(darkgray),
  printer:bugreport_potential_fix(Reason, C, N, Constraints, RequiredBy),
  message:color(normal).

printer:bugreport_summary(Reason, RequiredBy0, C0, N0, Summary) :-
  printer:bugreport_safe_atom(RequiredBy0, unknown_depender, RequiredBy),
  printer:bugreport_safe_atom(C0, unknown_category, C),
  printer:bugreport_safe_atom(N0, unknown_package, N),
  printer:bugreport_reason_label(Reason, ReasonLabel),
  % Always bind Summary to an atom (even if inputs are variables).
  format(atom(Summary), '~w: ~w dependency on ~w/~w', [RequiredBy, ReasonLabel, C, N]).

printer:bugreport_safe_atom(X, Default, Out) :-
  ( atom(X) -> Out = X
  ; X = Repo://Entry, atom(Repo), atom(Entry) -> Out = (Repo://Entry)
  ; Out = Default
  ).

printer:bugreport_reason_label(Reason, 'unsatisfied dependency') :-
  var(Reason),
  !.
printer:bugreport_reason_label(Reason, 'unsatisfiable version constraint') :-
  ( Reason = version_no_candidate(_,_) ; Reason = version_no_candidate ),
  !.
printer:bugreport_reason_label(Reason, 'conflicting version constraints') :-
  ( Reason = version_conflict ; Reason = version_conflict(_) ),
  !.
printer:bugreport_reason_label(slot_unsatisfied,   'unsatisfiable slot constraint') :- !.
printer:bugreport_reason_label(keyword_filtered,   'keyword-filtered') :- !.
printer:bugreport_reason_label(masked,             'masked') :- !.
printer:bugreport_reason_label(installed_required, 'installed-only requirement') :- !.
printer:bugreport_reason_label(Reason, Reason).

printer:print_bugreport_constraint(O, C, N, V, S) :-
  printer:print_comparator(O),
  write(C), write('/'), write(N), write('-'), write(V),
  printer:print_slot_restriction(S).

printer:available_versions(C, N, Sample) :-
  findall(V,
          ( cache:ordered_entry(_Repo, _Id, C, N, Ver),
            printer:version_atom(Ver, V)
          ),
          Vs0),
  sort(Vs0, Vs),
  % Take up to 8 to keep output short.
  printer:take_first_n(Vs, 8, Sample).
printer:available_versions(_C, _N, []).

printer:bugreport_potential_fix(Reason, C, N, Constraints, RequiredBy) :-
  ( Reason = version_no_candidate(Op, Ver) ->
      printer:bugreport_constraint_short(Op, Ver, Short),
      format('  One constraint has zero matches: ~w. Consider relaxing/removing that bound after verifying compatibility.~n',
             [Short])
    ,
    ( printer:available_version_range(C, N, MinV, MaxV, Count) ->
        format('  Available versions for ~w/~w: ~w .. ~w (~d total).~n', [C, N, MinV, MaxV, Count])
    ; true
    )
  ; Reason = version_no_candidate ->
      format('  At least one version bound has zero matches. Consider relaxing/removing the tightest bound after verifying compatibility.~n', [])
  ; Reason = version_conflict ; Reason = version_conflict(_) ->
      format('  Constraints conflict. Consider adjusting bounds so at least one version satisfies all constraints.~n', [])
  ; Reason = slot_unsatisfied ->
      format('  Slot restriction filters all candidates. Consider adjusting slot operator/restriction if appropriate.~n', [])
  ; Reason = keyword_filtered ->
      format('  Candidates exist but none match ACCEPT_KEYWORDS. Consider keywording or adjusting KEYWORDS/ACCEPT_KEYWORDS as appropriate.~n', [])
  ; Reason = masked ->
      format('  Candidates exist but are masked. Consider unmasking or adjusting mask rules if appropriate.~n', [])
  ; Reason = installed_required ->
      format('  This appears to be a self-hosting/installed-only constraint. Consider ensuring a suitable installed candidate exists or adjusting bootstrap logic.~n', [])
  ; format('  Review dependency metadata in ~w; constraint set: ~w.~n', [RequiredBy, Constraints])
  ).

% Compute a human-readable (min..max) version range for a package in the current repo set.
printer:available_version_range(C, N, MinAtom, MaxAtom, Count) :-
  findall(Ver, cache:ordered_entry(_Repo, _Id, C, N, Ver), Vers0Raw),
  Vers0Raw \= [],
  sort(Vers0Raw, Vers0), % unique (may include multiple repos, but dedup by term)
  length(Vers0, Count),
  predsort(printer:compare_versions, Vers0, VersSorted),
  VersSorted = [Min|_],
  last(VersSorted, Max),
  printer:version_atom(Min, MinAtom),
  printer:version_atom(Max, MaxAtom).

printer:available_version_count_unique(C, N, Count) :-
  findall(Ver, cache:ordered_entry(_Repo, _Id, C, N, Ver), Vers0Raw),
  sort(Vers0Raw, Vers0),
  length(Vers0, Count).

printer:compare_versions(Delta, A, B) :-
  ( system:compare(<, A, B) -> Delta = (<)
  ; system:compare(>, A, B) -> Delta = (>)
  ; Delta = (=)
  ).

printer:take_first_n(_, 0, []) :- !.
printer:take_first_n([], _N, []) :- !.
printer:take_first_n([X|Xs], N, [X|Ys]) :-
  N > 0,
  N1 is N - 1,
  printer:take_first_n(Xs, N1, Ys).

printer:bugreport_constraint_short(Op, Ver0, Short) :-
  printer:comparator_symbol(Op, Sym),
  printer:version_atom(Ver0, Ver),
  format(atom(Short), '~w~w', [Sym, Ver]).

printer:comparator_symbol(greaterequal, '>=') :- !.
printer:comparator_symbol(greater,      '>')  :- !.
printer:comparator_symbol(smallerequal, '<=') :- !.
printer:comparator_symbol(smaller,      '<')  :- !.
printer:comparator_symbol(equal,        '=')  :- !.
printer:comparator_symbol(tilde,        '~')  :- !.
printer:comparator_symbol(none,         '')   :- !.
printer:comparator_symbol(Op,           Op).


%! printer:handle_assumption(+ProofKey)
%
% Helper to print details for both domain driven and prover driven assumption formats.

printer:handle_assumption(ProofKey) :-
  % Case 1: key format: rule(assumed(...)) % domain driven assumption
  (   ProofKey = rule(assumed(Content)) ->
      printer:print_assumption_detail(rule(Content, [])),
      nl
  % Case 2: key format: assumed(rule(...)) % prover driven assumption
  ;   ProofKey = assumed(rule(Content)) ->
      printer:print_assumption_detail(rule(Content, [])),
      nl
  ;
      true
  ).


%! printer:handle_assumption(+ProofKey,+ProofAVL,+TriggersAVL)
%
% Extended assumption printer that can use proof and triggers for explanations.
printer:handle_assumption(ProofKey, _ProofAVL, TriggersAVL) :-
  % Case 1: key format: rule(assumed(...)) % domain driven assumption
  (   ProofKey = rule(assumed(Content)) ->
      printer:print_assumption_detail(rule(Content, [])),
      nl
  % Case 2: key format: assumed(rule(...)) % prover driven assumption
  ;   ProofKey = assumed(rule(Content)) ->
      printer:print_assumption_detail(rule(Content, [])),
      printer:print_cycle_explanation(Content, TriggersAVL),
      nl
  ;
      true
  ).


% -----------------------------------------------------------------------------
%  Cycle explanation (minimal "works now" implementation)
% -----------------------------------------------------------------------------

%! printer:print_cycle_explanation(+StartKey,+TriggersAVL)
printer:print_cycle_explanation(StartKey, TriggersAVL) :-
  % Accept both package keys (R://E:install) and non-package keys (X:install),
  % so cycles can still be found even when the assumption is a grouped dep term.
  ( StartKey = _://_:install ; StartKey = _://_:run ; StartKey = _://_:fetchonly
  ; StartKey = _:install     ; StartKey = _:run     ; StartKey = _:fetchonly
  ),
  printer:find_cycle_via_triggers(StartKey, TriggersAVL, CyclePath0),
  printer:cycle_display_path(CyclePath0, CyclePath),
  CyclePath = [_|_],
  !,
  % Record stats (if enabled) before printing, so "cycle mention" counts match what we show.
  printer:test_stats_record_cycle(CyclePath0, CyclePath),
  nl,
  message:color(darkgray),
  message:print('  Reason : Dependency cycle :'), nl,
  message:color(normal),
  nl,
  printer:cycle_edge_guard_map(CyclePath0, GuardMap),
  printer:print_cycle_tree(CyclePath, GuardMap).
printer:print_cycle_explanation(_, _) :-
  true.

% -----------------------------------------------------------------------------
%  On-demand USE-guard extraction for cycle edges
% -----------------------------------------------------------------------------

% Build a map ToPkgKey -> GuardText (e.g. "-expat +python") for the cycle edges
% found in the raw trigger cycle path. This is computed on-demand at print time
% and does not affect proving performance.
printer:cycle_edge_guard_map(CyclePath0, GuardMap) :-
  printer:cycle_edges_from_raw(CyclePath0, Edges),
  empty_assoc(Empty),
  foldl(printer:edge_guard_put, Edges, Empty, GuardMap).

printer:edge_guard_put(edge(From, Dep, To), In, Out) :-
  ( printer:edge_guard_text(From, Dep, To, Text),
    Text \== ''
  -> put_assoc(To, In, Text, Out)
  ;  Out = In
  ).

% Extract the minimal USE guards that enabled this dependency edge.
% We anchor on the concrete package_dependency leaf inside the grouped dep node,
% and then locate that leaf inside the cached dependency metadata tree under
% use_conditional_group/4 nodes.
% Note: the cycle path is a *reverse dependency* path. An edge:
%   FromPkg -> DepNode -> ToPkg
% means: ToPkg depends on FromPkg (potentially under USE conditions).
% Therefore we must look up the dependency leaf (which matches FromPkg) in
% ToPkg's metadata tree.
printer:edge_guard_text(FromPkg, DepNode, ToPkg, Text) :-
  printer:cycle_dep_leaf(DepNode, FromPkg, LeafDep),
  printer:cycle_pkg_repo_entry(ToPkg, Repo://Entry, _Action),
  printer:metadata_use_guards_for_leaf(Repo://Entry, LeafDep, Guards),
  printer:guards_to_text(Guards, Text).

printer:cycle_pkg_repo_entry(Repo://Entry:Action, Repo://Entry, Action) :- !.
printer:cycle_pkg_repo_entry(Repo://Entry,        Repo://Entry, unknown) :- !.

printer:cycle_dep_leaf(DepNode, FromPkg, Leaf) :-
  % Prefer a leaf that matches the dependency package (FromPkg).
  ( printer:cycle_pkg_cat_name(FromPkg, FromC, FromN) -> true ; FromC = _, FromN = _ ),
  ( DepNode = grouped_package_dependency(_C,_N,List):_Action
  ; DepNode = grouped_package_dependency(_X,_C,_N,List):_Action
  ),
  !,
  ( member(Leaf, List),
    Leaf = package_dependency(_,_,FromC,FromN,_,_,_,_)
  -> true
  ; member(Leaf, List),
    Leaf = package_dependency(_,_,_,_,_,_,_,_)
  ).
printer:cycle_dep_leaf(package_dependency(_,_,_,_,_,_,_,_):_Action, _FromPkg, Leaf) :-
  !,
  Leaf = package_dependency(_,_,_,_,_,_,_,_).
printer:cycle_dep_leaf(package_dependency(_,_,_,_,_,_,_,_), _FromPkg, Leaf) :-
  !,
  Leaf = package_dependency(_,_,_,_,_,_,_,_).

% Best-effort category/name extraction for a package key in the cycle.
% Uses cache metadata (fast indexed lookup) and falls back to parsing.
printer:cycle_pkg_cat_name(Repo://Entry:_Action, C, N) :-
  !,
  ( cache:ordered_entry(Repo, Entry, C, N, _) -> true
  ; atom(Entry),
    atomic_list_concat([C, Rest], '/', Entry),
    sub_atom(Rest, 0, _, _, N)
  ).
printer:cycle_pkg_cat_name(Repo://Entry, C, N) :-
  !,
  ( cache:ordered_entry(Repo, Entry, C, N, _) -> true
  ; atom(Entry),
    atomic_list_concat([C, Rest], '/', Entry),
    sub_atom(Rest, 0, _, _, N)
  ).

printer:cycle_edges_from_raw([], []) :- !.
printer:cycle_edges_from_raw([_], []) :- !.
printer:cycle_edges_from_raw([_,_], []) :- !.
printer:cycle_edges_from_raw([A,Dep,B|Rest], [edge(A,Dep,B)|Edges]) :-
  printer:is_pkg_key(A),
  \+ printer:is_pkg_key(Dep),
  printer:is_pkg_key(B),
  !,
  printer:cycle_edges_from_raw([B|Rest], Edges).
printer:cycle_edges_from_raw([_|Rest], Edges) :-
  printer:cycle_edges_from_raw(Rest, Edges).

printer:is_pkg_key(_://_:_) :- !.

% Retrieve the cached dependency metadata trees for an ebuild.
% We search all relevant dependency variables to avoid any fuzzy mapping.
printer:metadata_dep_trees(Repo://Entry, Trees) :-
  findall(T, kb:query(depend(T),  Repo://Entry), T1),
  findall(T, kb:query(bdepend(T), Repo://Entry), T2),
  findall(T, kb:query(rdepend(T), Repo://Entry), T3),
  findall(T, kb:query(pdepend(T), Repo://Entry), T4),
  append([T1,T2,T3,T4], Trees0),
  Trees = Trees0.

% Find a minimal guard list by iterative deepening on the number of USE guards.
printer:metadata_use_guards_for_leaf(Repo://Entry, LeafDep, Guards) :-
  printer:metadata_dep_trees(Repo://Entry, Trees),
  between(0, 6, MaxGuards),
  once((
    member(Tree, Trees),
    printer:metadata_find_leaf_guards(Tree, LeafDep, [], Rev, MaxGuards)
  )),
  !,
  reverse(Rev, Guards).
printer:metadata_use_guards_for_leaf(_Repo://_Entry, _LeafDep, []).

% Walk only the metadata dependency tree; this is not a dependency-graph DFS and
% cannot loop back into itself unless the term is cyclic (which would be unusual).
% The MaxGuards bound keeps this search minimal and fast.
% Unwrap context/action decorations like X:install?{...} or X:config, so we can
% match against the underlying metadata terms.
printer:metadata_find_leaf_guards(Full, Leaf, Acc, Out, Max) :-
  Full = (Inner ? {_Ctx}),
  !,
  printer:metadata_find_leaf_guards(Inner, Leaf, Acc, Out, Max).
printer:metadata_find_leaf_guards(Full, Leaf, Acc, Out, Max) :-
  Full = (Inner : _Action),
  !,
  printer:metadata_find_leaf_guards(Inner, Leaf, Acc, Out, Max).

printer:metadata_find_leaf_guards(use_conditional_group(Type,Use,_Id,Values), Leaf, Acc, Out, Max) :-
  ( Type == positive -> G = guard(positive,Use) ; G = guard(negative,Use) ),
  length(Acc, L),
  L1 is L + 1,
  L1 =< Max,
  !,
  printer:metadata_find_leaf_guards_list(Values, Leaf, [G|Acc], Out, Max).
printer:metadata_find_leaf_guards(any_of_group(Vals), Leaf, Acc, Out, Max) :-
  !, printer:metadata_find_leaf_guards_list(Vals, Leaf, Acc, Out, Max).
printer:metadata_find_leaf_guards(all_of_group(Vals), Leaf, Acc, Out, Max) :-
  !, printer:metadata_find_leaf_guards_list(Vals, Leaf, Acc, Out, Max).
printer:metadata_find_leaf_guards(exactly_one_of_group(Vals), Leaf, Acc, Out, Max) :-
  !, printer:metadata_find_leaf_guards_list(Vals, Leaf, Acc, Out, Max).
printer:metadata_find_leaf_guards(at_most_one_of_group(Vals), Leaf, Acc, Out, Max) :-
  !, printer:metadata_find_leaf_guards_list(Vals, Leaf, Acc, Out, Max).
printer:metadata_find_leaf_guards(grouped_package_dependency(_C,_N,List), Leaf, Acc, Out, Max) :-
  !, printer:metadata_find_leaf_guards_list(List, Leaf, Acc, Out, Max).
printer:metadata_find_leaf_guards(grouped_package_dependency(_X,_C,_N,List), Leaf, Acc, Out, Max) :-
  !, printer:metadata_find_leaf_guards_list(List, Leaf, Acc, Out, Max).
printer:metadata_find_leaf_guards(package_dependency(_A,_B,C,N,_O,_V,_S,_U),
                                 package_dependency(_A2,_B2,C2,N2,_O2,_V2,_S2,_U2),
                                 Acc, Acc, _Max) :-
  % Leaf match (minimal + robust for printing):
  % compare only category/name so we can reliably recover USE guards even if the
  % dependency model normalized version/slot details differently.
  % (If you want to tighten this later, re-add comparator/version/slot matching.)
  C == C2, N == N2,
  !.
printer:metadata_find_leaf_guards(_Other, _Leaf, _Acc, _Out, _Max) :-
  fail.

printer:metadata_find_leaf_guards_list([X|Xs], Leaf, Acc, Out, Max) :-
  ( printer:metadata_find_leaf_guards(X, Leaf, Acc, Out, Max)
  ; printer:metadata_find_leaf_guards_list(Xs, Leaf, Acc, Out, Max)
  ).

printer:guards_to_text([], '') :- !.
printer:guards_to_text(Guards, Text) :-
  findall(A,
          ( member(guard(Type,Use), Guards),
            ( Type == positive -> A = Use ; atom_concat('-', Use, A) )
          ),
          Atoms0),
  sort(Atoms0, Atoms),
  atomic_list_concat(Atoms, ' ', Text).

% Print a cycle path with a "box + return arrow" on the right side:
% - first line gets a left-pointing arrow to the right-side vertical bar (◄───┐)
% - middle lines show a vertical bar (│)
% - last line closes the box (───┘)
% This visually indicates the last node loops back to the first.
printer:print_cycle_tree([]) :- !.
printer:print_cycle_tree(CyclePath) :-
  empty_assoc(Empty),
  printer:print_cycle_tree(CyclePath, Empty).

printer:print_cycle_tree(CyclePath, GuardMap) :-
  printer:cycle_tree_parts(CyclePath, GuardMap, Parts0),
  printer:cycle_tree_trim_repeat(Parts0, Parts1),
  printer:cycle_tree_apply_closing_guard(CyclePath, GuardMap, Parts1, Parts),
  length(Parts, N),
  ( N < 2 ->
      % Degenerate case; just print the single node.
      Parts = [part(Indent, Entry, Action, GuardInText, GuardBackText, _LineWidth)],
      printer:print_cycle_tree_main(Indent, Entry, Action, GuardInText, GuardBackText), nl
  ;
      printer:cycle_tree_right_width(Parts, RightWidth),
      printer:print_cycle_tree_parts(Parts, 1, N, RightWidth)
  ).

% If the cycle path ends with the same node it starts with, drop the last one.
% This keeps the visual cycle closure without printing the start node twice.
printer:cycle_tree_trim_repeat([First|Rest], Parts) :-
  Rest \= [],
  append(Mid, [Last], Rest),
  First = part(_, Entry, Action, _GuardIn, _GuardBack, _),
  Last  = part(_, Entry, Action, _GuardIn2, _GuardBack2, _),
  Mid \= [],
  !,
  Parts = [First|Mid].
printer:cycle_tree_trim_repeat(Parts, Parts).

% Per-edge labeling: the guard for the closing edge (last -> first) is attached
% to the last printed line as "↩ USE: ...", instead of being shown on the first
% node line (which can be confusing in a cycle).
printer:cycle_tree_apply_closing_guard(CyclePath, GuardMap, PartsIn, PartsOut) :-
  ( CyclePath = [FirstNode|_],
    get_assoc(FirstNode, GuardMap, ClosingGuard),
    ClosingGuard \== '',
    PartsIn = [part(FIndent, FEntry, FAction, _FirstGuardIn, FBack, _FW0)|Tail0],
    append(Front, [part(Indent, Entry, Action, GuardIn, _OldBack, _W0)], Tail0)
  ->
    % Remove the confusing "incoming guard" on the first node line; it actually
    % corresponds to the closing edge (last -> first), which we render on the
    % last line as "↩ USE: ...".
    printer:cycle_tree_line_width(FIndent, FEntry, FAction, '', FBack, FW1),
    FirstPart = part(FIndent, FEntry, FAction, '', FBack, FW1),
    printer:cycle_tree_line_width(Indent, Entry, Action, GuardIn, ClosingGuard, W1),
    append([FirstPart|Front], [part(Indent, Entry, Action, GuardIn, ClosingGuard, W1)], PartsOut)
  ;
    PartsOut = PartsIn
  ).

printer:cycle_tree_parts(CyclePath, Parts) :-
  % Backwards-compatible wrapper; no guards.
  BaseIndent = 4,
  printer:cycle_tree_parts_(CyclePath, BaseIndent, Parts).

printer:cycle_tree_parts(CyclePath, GuardMap, Parts) :-
  BaseIndent = 4,
  printer:cycle_tree_parts_(CyclePath, GuardMap, BaseIndent, Parts).

printer:cycle_tree_parts_([], _Indent, []) :- !.
printer:cycle_tree_parts_([Node|Rest], Indent, [part(Indent, Entry, Action, '', '', LineWidth)|Parts]) :-
  printer:cycle_node_parts(Node, Entry, Action),
  printer:cycle_tree_line_width(Indent, Entry, Action, '', '', LineWidth),
  Indent1 is Indent + 4,
  printer:cycle_tree_parts_(Rest, Indent1, Parts).

printer:cycle_tree_parts_([], _GuardMap, _Indent, []) :- !.
printer:cycle_tree_parts_([Node|Rest], GuardMap, Indent, [part(Indent, Entry, Action, GuardText, '', LineWidth)|Parts]) :-
  printer:cycle_node_parts(Node, Entry, Action),
  ( get_assoc(Node, GuardMap, GuardText0) -> GuardText = GuardText0 ; GuardText = '' ),
  printer:cycle_tree_line_width(Indent, Entry, Action, GuardText, '', LineWidth),
  Indent1 is Indent + 4,
  printer:cycle_tree_parts_(Rest, GuardMap, Indent1, Parts).

printer:cycle_tree_right_width(Parts, RightWidth) :-
  findall(W, member(part(_,_,_,_,_,W), Parts), Ws),
  max_list(Ws, MaxW),
  ( config:printing_tty_size(_, TermW) -> true ; TermW = 120 ),
  % Place the right-side cycle box close to the longest line to avoid huge tails.
  % (Dynamic: still respects terminal width.)
  TargetW is MaxW + 6,
  CapW is max(0, TermW - 2),
  RightWidth0 is min(CapW, TargetW),
  ( RightWidth0 >= MaxW + 6 -> RightWidth = RightWidth0 ; RightWidth = MaxW + 6 ).

printer:print_cycle_tree_parts([], _I, _N, _RightWidth) :- !.
printer:print_cycle_tree_parts([part(Indent, Entry, Action, GuardInText, GuardBackText, LineWidth)|Rest], I, N, RightWidth) :-
  printer:print_cycle_tree_main(Indent, Entry, Action, GuardInText, GuardBackText),
  printer:print_cycle_tree_right(I, N, RightWidth, LineWidth),
  nl,
  ( I < N ->
      % Spacer line between dependencies: keep the right vertical bar continuous.
      printer:print_cycle_tree_spacer(RightWidth),
      nl
  ;
      true
  ),
  I1 is I + 1,
  printer:print_cycle_tree_parts(Rest, I1, N, RightWidth).

printer:print_cycle_tree_main(Indent, Entry, Action, GuardInText, GuardBackText) :-
  printer:print_n(' ', Indent),
  message:color(darkgray),
  message:print('└─'),
  message:color(normal),
  message:bubble(darkgray,Action),
  message:color(darkgray),
  message:print('─> '),
  message:color(normal),
  message:print(Entry),
  printer:print_cycle_tree_guard_suffix(GuardInText),
  printer:print_cycle_tree_back_guard_suffix(GuardBackText).

printer:print_cycle_tree_guard_suffix('') :- !.
printer:print_cycle_tree_guard_suffix(GuardText) :-
  message:color(darkgray),
  message:print(' [USE: '),
  message:print(GuardText),
  message:print(']'),
  message:color(normal).

printer:print_cycle_tree_back_guard_suffix('') :- !.
printer:print_cycle_tree_back_guard_suffix(GuardText) :-
  message:color(darkgray),
  message:print(' [↩ USE: '),
  message:print(GuardText),
  message:print(']'),
  message:color(normal).

printer:print_cycle_tree_right(I, N, RightWidth, LineWidth) :-
  Pad0 is RightWidth - LineWidth,
  Pad is max(2, Pad0),
  % Always leave at least one space between the end of the CPV and the cycle box/arrow.
  message:print(' '),
  Pad1 is max(1, Pad - 1),
  % Entire right-side cycle box/arrow should be red.
  message:color(lightred),
  ( I =:= 1 ->
      % Top: draw left-pointing arrow to the corner.
      message:print('<'),
      Dashes is max(0, Pad1 - 2),
      printer:print_n('─', Dashes),
      message:print('┐')
  ; I =:= N ->
      % Bottom: close the box.
      % Close the box with a short horizontal segment (no blank spaces).
      Dashes is max(1, Pad1 - 1),
      printer:print_n('─', Dashes),
      message:print('┘')
  ;
      % Middle: just the vertical bar.
      Spaces is max(0, Pad1 - 1),
      printer:print_n(' ', Spaces),
      message:print('│')
  ),
  message:color(normal).

printer:print_cycle_tree_spacer(RightWidth) :-
  message:color(lightred),
  printer:print_n(' ', max(0, RightWidth - 1)),
  message:print('│'),
  message:color(normal).

printer:cycle_tree_line_width(Indent, Entry, Action, GuardText, BackGuardText, Width) :-
  printer:term_visible_length(Entry, EntryLen),
  printer:term_visible_length(Action, ActionLen),
  printer:term_visible_length(GuardText, GuardLen),
  printer:term_visible_length(BackGuardText, BackGuardLen),
  % Indent + "└─" + bubble(Action) + "─> " + Entry
  % bubble(Action) displays as 2 glyphs + Action text.
  ( GuardLen =:= 0
    -> GuardExtra = 0
    ;  GuardExtra is 7 + GuardLen + 1
  ),
  ( BackGuardLen =:= 0
    -> BackExtra = 0
    ;  BackExtra is 9 + BackGuardLen + 1
  ),
  Width is Indent + 2 + (ActionLen + 2) + 3 + EntryLen + GuardExtra + BackExtra.

printer:term_visible_length(Term, Len) :-
  ( atomic(Term) ->
      atom_length(Term, Len)
  ;
      term_to_atom(Term, Atom),
      atom_length(Atom, Len)
  ).

printer:print_n(_Char, N) :-
  N =< 0,
  !.
printer:print_n(Char, N) :-
  message:print(Char),
  N1 is N - 1,
  printer:print_n(Char, N1).

% Extract Entry and Action from a cycle node (already filtered to package keys).
% Examples:
%   portage://dev-libs/libxml2-2.15.1:install  -> Entry=dev-libs/libxml2-2.15.1, Action=install
%   portage://dev-libs/libxml2-2.15.1          -> Entry=dev-libs/libxml2-2.15.1, Action=unknown
printer:cycle_node_parts(_Repo://Entry:Action, Entry, Action) :- !.
printer:cycle_node_parts(_Repo://Entry,        Entry, unknown) :- !.
printer:cycle_node_parts(Entry:Action,         Entry, Action) :- !.
printer:cycle_node_parts(Entry,               Entry, unknown).

% Keep only the human-meaningful nodes: package keys (R://E or R://E:Action).
printer:cycle_display_path(CyclePath0, CyclePath) :-
  findall(P,
          ( member(N, CyclePath0),
            printer:cycle_node_package_key(N, P)
          ),
          P0),
  printer:dedup_consecutive(P0, CyclePath).

printer:cycle_node_package_key(R://E:A, R://E:A) :- !.
printer:cycle_node_package_key(R://E,   R://E)   :- !.

% Special case: keep a 2-element [X,X] list intact so a direct self-cycle can
% still be rendered as a cycle (instead of collapsing to a single node).
printer:dedup_consecutive([X,X], [X,X]) :- !.
printer:dedup_consecutive([], []).
printer:dedup_consecutive([X|Xs], [X|Ys]) :-
  printer:dedup_consecutive_(Xs, X, Ys).

printer:dedup_consecutive_([], _Prev, []).
printer:dedup_consecutive_([X|Xs], Prev, Ys) :-
  ( X == Prev ->
      printer:dedup_consecutive_(Xs, Prev, Ys)
  ;
      Ys = [X|Rest],
      printer:dedup_consecutive_(Xs, X, Rest)
  ).


%! printer:find_cycle_via_triggers(+StartKey,+TriggersAVL,-CyclePath)
printer:find_cycle_via_triggers(StartKey, TriggersAVL, CyclePath) :-
  MaxDepth = 25,
  printer:dfs_cycle(StartKey, StartKey, TriggersAVL, [StartKey], 0, MaxDepth, [StartKey], RevPath),
  reverse(RevPath, CyclePath),
  CyclePath = [StartKey|_].


%! printer:dfs_cycle(+Start,+Node,+Triggers,+Visited,+Depth,+MaxDepth,+Acc,-Out)
printer:dfs_cycle(Start, Node, TriggersAVL, _Visited, Depth, _MaxDepth, Acc, [Start|Acc]) :-
  Depth > 0,
  printer:trigger_neighbors(Node, TriggersAVL, Neigh),
  member(Start, Neigh),
  !.
printer:dfs_cycle(Start, Node, TriggersAVL, Visited, Depth, MaxDepth, Acc, Out) :-
  Depth < MaxDepth,
  printer:trigger_neighbors(Node, TriggersAVL, Neigh),
  member(Next, Neigh),
  \+ memberchk(Next, Visited),
  Depth1 is Depth + 1,
  printer:dfs_cycle(Start, Next, TriggersAVL, [Next|Visited], Depth1, MaxDepth, [Next|Acc], Out).


%! printer:trigger_neighbors(+Key,+TriggersAVL,-NeighborKeys)
%
% Neighbors are dependents of Key in the triggers graph, canonicalized to keys
% (dropping context) to keep the search space manageable.
printer:trigger_neighbors(Key, TriggersAVL, NeighborKeys) :-
  ( get_assoc(Key, TriggersAVL, Dependents) -> true ; Dependents = [] ),
  findall(K,
          ( member(Dep, Dependents),
            prover:canon_literal(Dep, K, _)
          ),
          Ks),
  sort(Ks, NeighborKeys).


%! printer:print_assumption_detail(+RuleTerm)
%
% Prints formatted, non-garbled assumption details.

printer:print_assumption_detail(rule(package_dependency(T,A,C,N,X,Y,Z,XX):_YY?{Ctx},_)) :- !,
    message:color(lightred),
    message:style(bold),
    printer:assumption_reason_label(Ctx, Label),
    message:print('- '),
    message:print(Label),
    message:print(' '),
    message:print(T),
    message:print(' dependency: '),
    message:style(normal),
    nl,
    message:color(normal),
    printer:print_metadata_item_detail(_,'  ',package_dependency(T,A,C,N,X,Y,Z,XX)),nl,
    printer:print_assumption_provenance(Ctx).

printer:print_assumption_detail(rule(grouped_package_dependency(C,N,R):T?{Ctx},_)) :- !,
    message:color(lightred),
    message:style(bold),
    printer:assumption_reason_label(Ctx, Label),
    message:print('- '),
    message:print(Label),
    message:print(' '),
    message:print(T),
    message:print(' dependency: '),
    message:style(normal),
    nl,
    message:color(normal),
    printer:print_metadata_item_detail(_,'  ',grouped_package_dependency(C,N,R)),nl,
    printer:print_assumption_provenance(Ctx).

printer:print_assumption_detail(rule(grouped_package_dependency(X,C,N,R):install,_)) :- !,
    message:color(lightred),
    message:style(bold),
    message:print('- Assumed installed: '),
    message:style(normal),
    message:color(normal),
    nl,
    printer:print_metadata_item_detail(_,'  ',grouped_package_dependency(X,C,N,R)),nl.

printer:print_assumption_detail(rule(grouped_package_dependency(X,C,N,R):run,_)) :- !,
    message:color(lightred),
    message:style(bold),
    message:print('- Assumed running: '),
    message:style(normal),
    message:color(normal),
    nl,
    printer:print_metadata_item_detail(_,'  ',grouped_package_dependency(X,C,N,R)),nl.

printer:print_assumption_detail(rule(R://E:install,_)) :- !,
    message:color(lightred),
    message:style(bold),
    message:print('- Assumed installed: '),
    message:style(normal),
    message:color(normal),nl,
    message:print('  '),
    message:print(R://E), nl.

printer:print_assumption_detail(rule(R://E:run,_)) :- !,
    message:color(lightred),
    message:style(bold),
    message:print('- Assumed running: '),
    message:style(normal),
    message:color(normal),nl,
    message:print('  '),
    message:print(R://E), nl.

printer:print_assumption_detail(rule(R://E:unmask,_)) :- !,
    message:color(lightred),
    message:style(bold),
    message:print('- Masked: '),
    message:style(normal),
    message:color(normal),nl,
    message:print('  '),
    message:print(R://E), nl.

% Blocker assumptions (introduced by rules.pl when we print a "plan with blocker
% assumptions" after a failed strict solve).
printer:print_assumption_detail(rule(blocker(Strength, Phase, C, N, _O, _V, _SlotReq)?{Ctx}, _)) :- !,
    message:color(lightred),
    message:style(bold),
    message:print('- Blocked packages ('),
    ( Strength == strong -> message:print('hard'); message:print('soft') ),
    message:print(' blocker): '),
    message:style(normal),
    message:color(normal), nl,
    message:print('  '),
    message:print(C),
    message:print('/'),
    message:print(N),
    message:print(' (phase: '),
    message:print(Phase),
    message:print(')'),
    nl,
    printer:print_assumption_provenance(Ctx).

printer:print_assumption_detail(rule(blocker(Strength, Phase, C, N, O, V, SlotReq), Body)) :- !,
    printer:print_assumption_detail(rule(blocker(Strength, Phase, C, N, O, V, SlotReq)?{[]}, Body)).

printer:print_assumption_detail(rule(C,_)) :-
    message:color(lightred),
    message:style(bold),
    message:print('- Other: '),
    message:style(normal),
    message:color(normal),nl,
    message:print('  '),
    message:print(C), nl.

% Print a small provenance hint for domain assumptions when available.
% Context is expected to be a list (most callers), but we stay defensive.
printer:print_assumption_provenance(Ctx0) :-
  ( is_list(Ctx0) ->
      ( memberchk(self(Repo://Entry), Ctx0) ->
          message:color(darkgray),
          message:print('  required by: '),
          message:print(Repo://Entry),
          nl,
          message:color(normal)
      ; true
      )
  ; true
  ).

printer:assumption_reason_label(CtxLike, Label) :-
  explainer:term_ctx(_:_?{CtxLike}, Ctx),
  ( memberchk(assumption_reason(Reason), Ctx)
  -> printer:assumption_reason_label_(Reason, Label)
  ; Label = 'Non-existent'
  ).

printer:assumption_reason_label_(missing,                 'Missing').
printer:assumption_reason_label_(masked,                  'Masked').
printer:assumption_reason_label_(keyword_filtered,        'Keyword filtered').
printer:assumption_reason_label_(installed_required,      'Requires installed candidate for').
printer:assumption_reason_label_(slot_unsatisfied,        'Unsatisfied slot constraint for').
printer:assumption_reason_label_(version_no_candidate(_,_), 'Unsatisfied version constraint for').
printer:assumption_reason_label_(version_conflict(_),       'Conflicting version constraints for').
printer:assumption_reason_label_(version_no_candidate,    'Unsatisfied version constraint for').
printer:assumption_reason_label_(version_conflict,        'Conflicting version constraints for').
printer:assumption_reason_label_(unsatisfied_constraints, 'Unsatisfied constraints for').


%! printer:print(+Target,+ModelAVL,+ProofAVL,+Plan,+TriggersAVL)
%
% Prints a plan. Triggers are required so the printer can explain assumptions
% (e.g. dependency cycles) when present.
printer:print(Target,ModelAVL,ProofAVL,Plan,TriggersAVL) :-
  printer:print(Target,ModelAVL,ProofAVL,Plan,printer:dry_run,TriggersAVL).

%! printer:print(+Target,+ModelAVL,+ProofAVL,+Plan,+Call,+TriggersAVL)
printer:print(Target,ModelAVL,ProofAVL,Plan,Call,TriggersAVL) :-
  printer:blocker_note_map(ProofAVL, BlockerNotes),
  setup_call_cleanup(nb_setval(printer_blocker_notes, BlockerNotes),
    ( printer:print_header(Target),
      printer:print_body(Target,Plan,Call,Steps),
      printer:print_footer(Plan,ModelAVL,Steps),
      printer:print_warnings(ModelAVL,ProofAVL,TriggersAVL)
    ),
    nb_delete(printer_blocker_notes)).

% Build a lookup map from (C,N,Phase) -> note(Strength, OriginRepoEntryOrUnknown).
printer:blocker_note_map(ProofAVL, Notes) :-
  empty_assoc(Empty),
  findall(K-V,
          ( assoc:gen_assoc(rule(assumed(Content0)), ProofAVL, _),
            printer:blocker_assumption_term(Content0, Strength, Phase, C, N, Origin),
            K = key(C,N,Phase),
            V = note(Strength, Origin)
          ),
          Pairs0),
  sort(Pairs0, Pairs),
  foldl(printer:blocker_note_put, Pairs, Empty, Notes).

printer:blocker_note_put(K-V, In, Out) :-
  ( get_assoc(K, In, _) ->
      Out = In
  ; put_assoc(K, In, V, Out)
  ).

printer:blocker_assumption_term(Content0, Strength, Phase, C, N, Origin) :-
  % With provenance context:
  ( Content0 = '?'(blocker(Strength, Phase, C, N, _O, _V, _SlotReq), Ctx0),
    ( is_list(Ctx0) ->
        Ctx = Ctx0
    ; Ctx0 =.. ['{}'|Ctx] ->
        true
    ; Ctx = []
    ),
    ( memberchk(self(Origin), Ctx) -> true ; Origin = unknown )
  )
  ;
  % Legacy/no-context:
  ( Content0 = blocker(Strength, Phase, C, N, _O2, _V2, _SlotReq2),
    Origin = unknown
  ),
  ( Strength == weak ; Strength == strong ),
  ( Phase == install ; Phase == run ).

% Add an inline marker for --newuse-triggered rebuilds.
% We represent these as update actions carrying rebuild_reason(newuse).
printer:print_newuse_note_if_any(update, Context) :-
  memberchk(rebuild_reason(newuse), Context),
  !,
  message:color(orange),
  message:print(' (newuse)'),
  message:color(normal).
printer:print_newuse_note_if_any(_Action, _Context).

printer:print_blocker_note_if_any(Action, Repository, Entry) :-
  ( ( Action == install ; Action == run ),
    nb_current(printer_blocker_notes, Notes),
    printer:action_phase(Action, Phase),
    ( cache:ordered_entry(Repository, Entry, C, N, _) ->
        true
    ; query:search([category(C),name(N)], Repository://Entry)
    ),
    get_assoc(key(C,N,Phase), Notes, note(Strength, Origin))
  ->
    message:color(lightgray),
    message:print(' ('),
    message:color(lightred),
    message:print('blocked'),
    message:color(lightgray),
    message:print(': '),
    message:color(lightred),
    ( Strength == strong -> message:print('hard') ; message:print('soft') ),
    message:color(lightgray),
    message:print(' by '),
    ( Origin == unknown ->
        message:print('unknown')
    ; message:color(green),
      message:print(Origin),
      message:color(lightgray)
    ),
    message:print(')'),
    message:color(normal)
  ; true
  ).

printer:action_phase(run, run) :- !.
printer:action_phase(install, install) :- !.
printer:action_phase(reinstall, install) :- !.
printer:action_phase(update, install) :- !.
printer:action_phase(download, other) :- !.
printer:action_phase(fetchonly, other) :- !.
printer:action_phase(_Other, other).


%! printer:dry_run(+Step)
%
% Default execution strategy for building steps in a plan

printer:dry_run(_Step) :-
  true.
  %message:color(darkgray),
  %message:print(['building step : ',Step]),nl,
  %message:color(normal).


%! printer:write_repository_index_file(+Directory,+Repository)
%
% Write the index file for a given repository, listing all categories.

printer:write_repository_index_file(Directory,Repository) :-
  atomic_list_concat(['Repository: ',Repository],Title),
  atomic_list_concat([Directory,'/index.html'],File),
  tell(File),
  print_index(repository,Title,Title,cache:category(Repository,Category),Category,'./.index.css'),
  told.


%! printer:write_category_index_file(+Directory,+Repository,+Category)
%
% Write the index file for a given category, listing all packages.

printer:write_category_index_file(Directory,Repository,Category) :-
  atomic_list_concat(['Category: ',Repository,'://',Category],Title),
  atomic_list_concat(['Category: <a href=\"../index.html\">',Repository,'</a>://',Category],TitleHtml),
  atomic_list_concat([Directory,'/',Category,'/index.html'],File),
  tell(File),
  print_index(category,Title,TitleHtml,cache:package(Repository,Category,Name),Name,'../.index.css'),
  told.


%! printer:write_package_index_file(+Directory,+Repository,+Category,+Name)
%
% Write the index file for a given package, listing all entries

printer:write_package_index_file(Directory,Repository,Category,Name) :-
  atomic_list_concat(['Package: ',Repository,'://',Category,'/',Name],Title),
  atomic_list_concat(['Package: <a href=\"../index.html\">',Repository,'</a>://<a href=\"./index.html\">',Category,'</a>/',Name],TitleHtml),
  atomic_list_concat([Directory,'/',Category,'/',Name,'.html'],File),
  tell(File),
  print_index(package,Title,TitleHtml,cache:ordered_entry(Repository,_,Category,Name,[_,_,_,Version]),[Name,Version],'../.index.css'),
  told.


%! printer:write_merge_file(+Directory,+Repository://Entry)
%
% Print merge plan to file for an entry in a repository
% Assumes directory exists. (See repository:prepare_directory)

printer:write_merge_file(Directory,Repository://Entry) :-
  Action = run,
  Extension = '.merge',
  (prover:prove(Repository://Entry:Action?{[]},t,Proof,t,Model,t,_Constraints,t,Triggers),
   planner:plan(Proof,Triggers,t,Plan0,Remainder0),
   scheduler:schedule(Proof,Triggers,Plan0,Remainder0,Plan,_Remainder),
   atomic_list_concat([Directory,'/',Entry,Extension],File)),
  (tell(File),
   set_stream(current_output,tty(true)), % otherwise we lose color
   printer:print([Repository://Entry:Action?{[]}],Model,Proof,Plan,Triggers)
   -> told
   ; (told,with_mutex(mutex,message:warning([Repository,'://',Entry,' ',Action])))).


%! printer:write_fetchonly_file(+Directory,+Repository://Entry)
%
% Print fetchonly plan to file for an entry in a repository
% Assumes directory exists. (See repository:prepare_directory)

printer:write_fetchonly_file(Directory,Repository://Entry) :-
  Action = fetchonly,
  Extension = '.fetchonly',
  (prover:prove(Repository://Entry:Action?{[]},t,Proof,t,Model,t,_Constraints,t,Triggers),
   planner:plan(Proof,Triggers,t,Plan0,Remainder0),
   scheduler:schedule(Proof,Triggers,Plan0,Remainder0,Plan,_Remainder),
   atomic_list_concat([Directory,'/',Entry,Extension],File)),
  (tell(File),
   set_stream(current_output,tty(true)), % otherwise we lose color
   printer:print([Repository://Entry:Action?{[]}],Model,Proof,Plan,Triggers)
   -> told
   ;  (told,with_mutex(mutex,message:warning([Repository,'://',Entry,' ',Action])))).


%! printer:write_info_file(+Directory,+Repository://Entry)
%
% Print info to file for an entry in a repository
% Assumes directory exists. (See repository:prepare_directory)

printer:write_info_file(Directory,Repository://Entry) :-
  (atomic_list_concat([Directory,'/',Entry,'.info'],File)),
  (tell(File),
   set_stream(current_output,tty(true)), % otherwise we lose color
   printer:print_entry(Repository://Entry)
   -> told
   ;  (told,with_mutex(mutex,message:warning([Repository,'://',Entry,' ',info])))).


%! printer:write_index_files(+Directory,+Repository)
%
% Print index files for repository, its categories and packages.
% Assumes directory exists. (See repository:prepare_directory)

printer:write_index_files(Directory,Repository) :-

  printer:write_repository_index_file(Directory,Repository),

  tester:test(parallel_verbose,
              'Writing index files',
              Repository://Category,
              cache:category(Repository,Category),
              printer:write_category_index_file(Directory,Repository,Category)),

  tester:test(parallel_verbose,
              'Writing index files',
              Repository://CategoryName,
              (cache:package(Repository,Category,Name),
               atomic_list_concat([Category,'/',Name],CategoryName)),
              printer:write_package_index_file(Directory,Repository,Category,Name)).


%! printer:write_proof_files(+Directory,+Repository)
%
% Print merge, fetchonly & info to file for all entries in a repository
% Assumes directory exists. (See repository:prepare_directory)

printer:write_proof_files(Directory,Repository) :-
  tester:test(parallel_verbose,
              'Writing proof files',
              Repository://Entry,
              (Repository:entry(Entry),
               (config:graph_modified_only(true)
                -> Repository:entry(Entry,Time),
                   Repository:get_ebuild_file(Entry,Ebuild),
                   system:exists_file(Ebuild),
                   system:time_file(Ebuild,Modified),
                   Modified > Time
                ;  true)),
	      ((printer:write_merge_file(Directory,Repository://Entry);true),
	       (printer:write_fetchonly_file(Directory,Repository://Entry);true),
               (printer:write_info_file(Directory,Repository://Entry);true))).


%! printer:produce_html(+Directory)
%
% For a given directory with proof files, convert the files into html.

printer:produce_html(Directory) :-
  message:scroll_notice(['Now running Aha ...']),
  message:hc,
  script:exec(print,['aha',Directory]),
  message:sc.


%! unify(+A,+B)
%
% Helper predicate to check if two terms are unifiable.

unify(A,B) :- unifiable(A,B,_),!.


% -----------------------------------------------------------------------------
%  Testing
% -----------------------------------------------------------------------------

%! printer:test(+Repository)
%
% Proves and prints every entry in a given repository, reports using the default reporting style

printer:test(Repository) :-
  config:test_style(Style),
  printer:test(Repository,Style).


%! printer:test(+Repository,+Style)
%
% Proves and prints every entry in a given repository, reports using a given reporting style

printer:test(Repository,parallel_fast) :-
  !,
  printer:test(Repository,parallel_verbose).

printer:test(Repository,Style) :-
  config:proving_target(Action),
  aggregate_all(count, (Repository:entry(_E)), ExpectedTotal),
  printer:test_stats_reset('Printing', ExpectedTotal),
  aggregate_all(count, (Repository:package(_C,_N)), ExpectedPkgs),
  printer:test_stats_set_expected_unique_packages(ExpectedPkgs),
  tester:test(Style,
              'Printing',
              Repository://Entry,
              (Repository:entry(Entry)),
              ( % --- REFACTORED LOGIC ---
                % 1. Call prover and planner.
                prover:prove(Repository://Entry:Action?{[]},t,ProofAVL,t,ModelAVL,t,_Constraint,t,Triggers),
                planner:plan(ProofAVL,Triggers,t,Plan0,Remainder0),
                scheduler:schedule(ProofAVL,Triggers,Plan0,Remainder0,Plan,_Remainder)
                % No conversion here! AVLs are kept as-is.
              ),
              % 2. Call the newly refactored print predicate.
              ( printer:test_stats_record_entry(Repository://Entry, ModelAVL, ProofAVL, Triggers, false),
                printer:test_stats_set_current_entry(Repository://Entry),
              printer:print([Repository://Entry:Action?{[]}],ModelAVL,ProofAVL,Plan,Triggers),
                printer:test_stats_clear_current_entry
              ),
              false),
  printer:test_stats_print.


%! printer:test_latest(+Repository)
%
% Same as printer:test(+Repository), but only tests highest version of every package

printer:test_latest(Repository) :-
  !,
  printer:test_latest(Repository,parallel_verbose).

printer:test_latest(Repository,Style) :-
  config:proving_target(Action),
  aggregate_all(count,
                (Repository:package(C,N),once(Repository:ebuild(_Entry,C,N,_))),
                ExpectedTotal),
  printer:test_stats_reset('Printing latest', ExpectedTotal),
  aggregate_all(count, (Repository:package(_C,_N)), ExpectedPkgs),
  printer:test_stats_set_expected_unique_packages(ExpectedPkgs),
  tester:test(Style,
              'Printing latest',
              Repository://Entry,
              (Repository:package(C,N),once(Repository:ebuild(Entry,C,N,_))),
              ( % --- REFACTORED LOGIC ---
                prover:prove(Repository://Entry:Action?{[]},t,ProofAVL,t,ModelAVL,t,_Constraint,t,Triggers),
                planner:plan(ProofAVL,Triggers,t,Plan0,Remainder0),
                scheduler:schedule(ProofAVL,Triggers,Plan0,Remainder0,Plan,_Remainder)
              ),
              ( printer:test_stats_record_entry(Repository://Entry, ModelAVL, ProofAVL, Triggers, false),
                printer:test_stats_set_current_entry(Repository://Entry),
                printer:print([Repository://Entry:Action?{[]}],ModelAVL,ProofAVL,Plan,Triggers),
                printer:test_stats_clear_current_entry
              ),
              false),
  printer:test_stats_print.
