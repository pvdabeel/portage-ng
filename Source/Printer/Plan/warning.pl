/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> WARNING
Warnings, suggestions, blockers, domain assumption display, and bug report drafts.

Renders the post-plan diagnostic sections: domain assumptions, prover
cycle-break assumptions, blocker summaries, keyword/unmask/USE-change
suggestions, and Gentoo Bugzilla bug report drafts.
*/

:- module(warning, []).

% =============================================================================
%  WARNING declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Print warnings
% -----------------------------------------------------------------------------

%! warning:print_warnings(+ModelAVL, +ProofAVL, +TriggersAVL)
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

warning:print_warnings(ModelAVL, ProofAVL, TriggersAVL) :-
  once((assoc:gen_assoc(Key, ModelAVL, _), Key = assumed(_))),
  !,
  nl,
  findall(Content, (assoc:gen_assoc(rule(assumed(Content)), ProofAVL, _)), DomainAssumptions0),
  sort(DomainAssumptions0, DomainAssumptions),
  findall(Content, (assoc:gen_assoc(assumed(rule(Content)), ProofAVL, _)), CycleAssumptions0),
  sort(CycleAssumptions0, CycleAssumptions),
  partition(warning:is_blocker_assumption, DomainAssumptions, BlockerAssumptions, NonBlockerAssumptions),
  % 1. Suggestions/assumptions section first
  warning:print_suggestions_section(NonBlockerAssumptions, BlockerAssumptions, ProofAVL),
  % 2. Blockers second
  warning:print_blockers_section(BlockerAssumptions),
  % 3. Domain assumptions (with Error banner)
  ( NonBlockerAssumptions \= [] ->
      nl,
      message:bubble(red,'Error'),
      message:color(red),
      message:print(' The proof for your build plan contains domain assumptions. Please verify:'), nl, nl,
      message:color(normal),
      nl,
      message:header('Domain assumptions'),
      nl,
      forall(member(Content, NonBlockerAssumptions),
             ( warning:print_assumption_detail(rule(Content, [])),
               nl ))
  ; true
  ),
  % 4. Bug report drafts
  ( NonBlockerAssumptions \= [] ->
      ( config:bugreport_drafts_enabled(true) ->
          ( config:bugreport_drafts_max_assumptions(MaxAss) -> true ; MaxAss = 25 ),
          length(NonBlockerAssumptions, NAss),
          ( NAss =< MaxAss ->
              warning:print_bugreport_drafts(NonBlockerAssumptions)
          ; true
          )
      ; true
      )
  ; true
  ),
  % 5. Cycle breaks last (unless turned off)
  ( CycleAssumptions \= [], \+ config:print_prover_cycles_style(off) ->
      message:header('Cycle breaks (prover)'),
      nl,
      config:print_prover_cycles_max_total(MaxCycleBreaksToPrint),
      length(CycleAssumptions, TotalCycleBreaks),
      ( TotalCycleBreaks =< MaxCycleBreaksToPrint ->
          CycleToPrint = CycleAssumptions,
          Omitted is 0
      ; length(CycleToPrint, MaxCycleBreaksToPrint),
        append(CycleToPrint, _Rest, CycleAssumptions),
        Omitted is TotalCycleBreaks - MaxCycleBreaksToPrint
      ),
      forall(member(Content, CycleToPrint),
             ( ( config:print_prover_cycles_style(detailed),
                 plan:is_run_cycle_break(Content) ->
                     message:color(darkgray),
                     message:print('  (runtime SCC candidate)'), nl,
                     message:color(normal)
                 ; true
               ),
               plan:print_cycle_break_detail(Content),
               ( config:print_prover_cycles(true) ->
                   catch(call_with_time_limit(2.0, cycle:print_cycle_explanation(Content, ProofAVL, TriggersAVL)),
                         time_limit_exceeded,
                         ( message:color(darkgray),
                           message:print('  (cycle explanation omitted: time limit)'),
                           message:color(normal),
                           nl ))
               ; true
               ),
               ( config:print_prover_cycles_style(detailed) -> nl ; true )
             ))
  ,   ( Omitted > 0 ->
          message:color(darkgray),
          format('  (… ~d more cycle breaks omitted)~n', [Omitted]),
          message:color(normal),
          nl
      ; true
      )
  ; true
  ),
  nl,
  message:color(normal),nl.

warning:print_warnings(_, ProofAVL, _) :-
  !,
  warning:print_suggestions_section([], [], ProofAVL),
  nl.


% -----------------------------------------------------------------------------
%  Blocker assumptions (Portage-like summary)
% -----------------------------------------------------------------------------

%! warning:is_blocker_assumption(+Content)
%
% Succeeds if Content is a blocker assumption (with or without context).

warning:is_blocker_assumption(blocker(_Strength, _Phase, _C, _N, _O, _V, _SlotReq)?{_Ctx}) :- !.
warning:is_blocker_assumption(blocker(_Strength, _Phase, _C, _N, _O, _V, _SlotReq)) :- !.
warning:is_blocker_assumption(_) :- fail.

% -----------------------------------------------------------------------------
%  Blocker section (configurable via config:print_blockers/1)
% -----------------------------------------------------------------------------

%! warning:print_blockers_section(+BlockerAssumptions)
%
% Prints the blockers section using the style configured via
% config:print_blockers/1 (off, gentoo, fancy, or default).

warning:print_blockers_section([]) :- !.
warning:print_blockers_section(_) :-
  config:print_blockers(off), !.
warning:print_blockers_section(BlockerAssumptions) :-
  config:print_blockers(gentoo), !,
  findall(line(Strength, Phase, BlockAtom, RequiredBy),
          ( member(Content, BlockerAssumptions),
            warning:blocker_assumption_line(Content, Strength, Phase, BlockAtom, RequiredBy)
          ),
          Lines0),
  sort(Lines0, Lines),
  ( Lines == [] -> true
  ; nl,
    message:header('Blockers added during proving & planning:'),
    nl,
    forall(member(line(Strength, Phase, BlockAtom, RequiredBy), Lines),
           warning:print_blocker_line(Strength, Phase, BlockAtom, RequiredBy)),
    nl
  ).
warning:print_blockers_section(BlockerAssumptions) :-
  config:print_blockers(fancy), !,
  nl,
  message:header('Blockers added during proving & planning:'),
  nl,
  forall(member(Content, BlockerAssumptions),
         ( warning:print_assumption_detail(rule(Content, [])),
           nl )).
warning:print_blockers_section(BlockerAssumptions) :-
  nl,
  message:header('Blockers added during proving & planning:'),
  nl,
  forall(member(Content, BlockerAssumptions),
         ( warning:print_assumption_detail(rule(Content, [])),
           nl )).

%! warning:blocker_assumption_line(+Content, -Strength, -Phase, -BlockAtom, -RequiredBy)
%
% Destructures a blocker assumption into its display components.

warning:blocker_assumption_line(Content, Strength, Phase, BlockAtom, RequiredBy) :-
  ( Content = blocker(Strength, Phase, C, N, O, V, SlotReq)?{Ctx} ->
      true
  ; Content = blocker(Strength, Phase, C, N, O, V, SlotReq),
    Ctx = []
  ),
  warning:blocker_atom(Strength, C, N, O, V, SlotReq, BlockAtom),
  ( memberchk(self(RequiredBy0), Ctx) -> RequiredBy = RequiredBy0 ; RequiredBy = unknown ).

%! warning:blocker_atom(+Strength, +C, +N, +O, +V, +SlotReq, -Atom)
%
% Formats a blocker into a Portage-style atom string (e.g. =!!cat/pkg-1.0:slot).

warning:blocker_atom(Strength, C, N, O, V0, SlotReq, Atom) :-
  ( Strength == strong -> Bang = '!!' ; Bang = '!' ),
  eapi:comparator_symbol(O, Sym),
  ( var(V0) -> V = '' ; warning:version_atom(V0, V) ),
  warning:blocker_slot_suffix(SlotReq, SlotSuf),
  ( V == '' ->
      format(atom(Atom), '~w~w~w/~w~w', [Bang, Sym, C, N, SlotSuf])
  ; format(atom(Atom), '~w~w~w/~w-~w~w', [Bang, Sym, C, N, V, SlotSuf])
  ).

%! warning:blocker_slot_suffix(+SlotReq, -Suffix)
%
% Maps a slot requirement list to its Portage-style suffix string.

warning:blocker_slot_suffix([], '') :- !.
warning:blocker_slot_suffix([slot(S)], Suf) :- !, format(atom(Suf), ':~w', [S]).
warning:blocker_slot_suffix([slot(S),subslot(Ss)], Suf) :- !, format(atom(Suf), ':~w/~w', [S, Ss]).
warning:blocker_slot_suffix([slot(S),equal], Suf) :- !, format(atom(Suf), ':~w', [S]).
warning:blocker_slot_suffix([slot(S),subslot(Ss),equal], Suf) :- !, format(atom(Suf), ':~w/~w', [S, Ss]).
warning:blocker_slot_suffix(_Other, '').

%! warning:print_blocker_line(+Strength, +Phase, +BlockAtom, +RequiredBy)
%
% Prints a single blocker line in gentoo style.

warning:print_blocker_line(Strength, Phase, BlockAtom, RequiredBy) :-
  ( Strength == strong ->
      StrengthLabel = 'hard'
  ; StrengthLabel = 'soft'
  ),
  message:color(darkgray),
  format('  [blocks B] ~w (~w blocker, phase: ~w, required by: ~w)~n',
         [BlockAtom, StrengthLabel, Phase, RequiredBy]),
  message:color(normal).


% -----------------------------------------------------------------------------
%  Suggestions section (actionable output)
% -----------------------------------------------------------------------------

%! warning:print_suggestions_section(+NonBlockerAssumptions, +BlockerAssumptions, +ProofAVL)
%
% Collects all suggestion(...) tags from both domain assumptions and
% fully resolved proof entries, then prints an actionable summary.

warning:print_suggestions_section(NonBlockerAssumptions, _BlockerAssumptions, ProofAVL) :-
  warning:collect_keyword_suggestions(NonBlockerAssumptions, ProofAVL, KwSuggestions),
  warning:collect_unmask_suggestions(NonBlockerAssumptions, ProofAVL, UnmaskSuggestions),
  warning:collect_use_change_suggestions(ProofAVL, UseSuggestions),
  ( KwSuggestions == [], UnmaskSuggestions == [], UseSuggestions == [] -> true
  ; nl,
    message:header('Assumptions taken during proving & planning:'),
    nl,
    warning:print_keyword_suggestions(KwSuggestions),
    warning:print_unmask_suggestions(UnmaskSuggestions),
    warning:print_use_change_suggestions(UseSuggestions)
  ).

%! warning:collect_keyword_suggestions(+Assumptions, +ProofAVL, -Suggestions)
%
% Gathers keyword acceptance suggestions from both domain assumptions
% and fully resolved proof entries tagged with suggestion(accept_keyword, _).

warning:collect_keyword_suggestions(Assumptions, ProofAVL, Suggestions) :-
  % From domain assumptions (legacy fallback)
  findall(kw(C, N, K),
          ( member(Content, Assumptions),
            warning:assumption_has_keyword_suggestion(Content, C, N, K)
          ),
          Suggestions1),
  % From fully resolved proof entries (keyword_acceptance fallback)
  findall(kw(C, N, K),
          ( assoc:gen_assoc(rule(Repo://Entry:_Action), ProofAVL, _?Ctx),
            is_list(Ctx),
            memberchk(suggestion(accept_keyword, K), Ctx),
            cache:ordered_entry(Repo, Entry, C, N, _)
          ),
          Suggestions2),
  append(Suggestions1, Suggestions2, Suggestions0),
  sort(Suggestions0, Suggestions).

%! warning:assumption_has_keyword_suggestion(+Content, -C, -N, -K)
%
% Extracts keyword suggestion details from a domain assumption context.

warning:assumption_has_keyword_suggestion(Content, C, N, K) :-
  Content = grouped_package_dependency(C, N, _):_?{Ctx},
  is_list(Ctx),
  memberchk(suggestion(accept_keyword, K), Ctx),
  !.

%! warning:collect_unmask_suggestions(+Assumptions, +ProofAVL, -Suggestions)
%
% Gathers package unmask suggestions from both domain assumptions
% and fully resolved proof entries tagged with suggestion(unmask, _).

warning:collect_unmask_suggestions(Assumptions, ProofAVL, Suggestions) :-
  % From domain assumptions (legacy fallback)
  findall(unmask(R, E, C, N),
          ( member(Content, Assumptions),
            warning:assumption_has_unmask_suggestion(Content, R, E, C, N)
          ),
          Suggestions1),
  % From fully resolved proof entries (unmask fallback)
  findall(unmask(Repo, Entry, C, N),
          ( assoc:gen_assoc(rule(Repo://Entry:_Action), ProofAVL, _?Ctx),
            is_list(Ctx),
            memberchk(suggestion(unmask, _), Ctx),
            cache:ordered_entry(Repo, Entry, C, N, _)
          ),
          Suggestions2),
  append(Suggestions1, Suggestions2, Suggestions0),
  sort(Suggestions0, Suggestions).

%! warning:assumption_has_unmask_suggestion(+Content, -R, -E, -C, -N)
%
% Extracts unmask suggestion details from a domain assumption context.

warning:assumption_has_unmask_suggestion(R://E:unmask?{Ctx}, R, E, C, N) :-
  is_list(Ctx),
  memberchk(suggestion(unmask), Ctx),
  memberchk(masked_cn(C, N), Ctx),
  !.
warning:assumption_has_unmask_suggestion(Content, _R, _E, C, N) :-
  Content = grouped_package_dependency(C, N, _):_?{Ctx},
  is_list(Ctx),
  memberchk(suggestion(unmask), Ctx),
  !.

%! warning:print_keyword_suggestions(+Suggestions)
%
% Prints keyword acceptance suggestions with package.accept_keywords instructions.

warning:print_keyword_suggestions([]) :- !.
warning:print_keyword_suggestions(KwSuggestions) :-
  length(KwSuggestions, Count),
  ( Count =:= 1 -> Suf = '' ; Suf = 's' ),
  message:color(yellow),
  format('  Keyword acceptance (~d package~w):~n', [Count, Suf]),
  message:color(normal),
  message:color(darkgray),
  message:print('  Add to /etc/portage/package.accept_keywords:'), nl,
  ( Count =< 20 ->
      forall(member(kw(C, N, K), KwSuggestions),
             ( warning:keyword_atom(K, KAtom),
               format('    ~w/~w ~w~n', [C, N, KAtom])
             ))
  ; KwSuggestions = [kw(C1,N1,K1)|_],
    warning:keyword_atom(K1, KAtom1),
    format('    ~w/~w ~w~n', [C1, N1, KAtom1]),
    Remaining is Count - 1,
    format('    ... (~d more)~n', [Remaining])
  ),
  message:color(normal),
  nl.

%! warning:print_unmask_suggestions(+Suggestions)
%
% Prints package unmask suggestions with package.unmask instructions.

warning:print_unmask_suggestions([]) :- !.
warning:print_unmask_suggestions(UnmaskSuggestions) :-
  length(UnmaskSuggestions, Count),
  ( Count =:= 1 -> Suf = '' ; Suf = 's' ),
  message:color(yellow),
  format('  Package unmask (~d package~w):~n', [Count, Suf]),
  message:color(normal),
  message:color(darkgray),
  message:print('  Add to /etc/portage/package.unmask:'), nl,
  forall(member(unmask(_R, E, C, N), UnmaskSuggestions),
         ( ( nonvar(E) ->
               format('    =~w~n', [E])
           ; format('    ~w/~w~n', [C, N])
           )
         )),
  message:color(normal),
  nl.

%! warning:keyword_atom(+Keyword, -Atom)
%
% Converts a keyword term to its printable atom (e.g. stable(arm64) -> arm64,
% unstable(arm64) -> ~arm64).

warning:keyword_atom(stable(Arch), Arch) :- !.
warning:keyword_atom(unstable(Arch), Atom) :- !, format(atom(Atom), '~~~w', [Arch]).
warning:keyword_atom(K, K).


% -----------------------------------------------------------------------------
%  USE change suggestions (autounmask-use)
% -----------------------------------------------------------------------------

%! warning:collect_use_change_suggestions(+ProofAVL, -Suggestions)
%
% Collects USE change suggestions from the proof: both from
% suggestion(use_change, ...) tags and from build_with_use contexts
% where the effective USE differs from the requested state.

warning:collect_use_change_suggestions(ProofAVL, Suggestions) :-
  findall(use_sugg(C, N, Entry, Changes),
          ( assoc:gen_assoc(rule(R://E:_A), ProofAVL, _?Ctx),
            is_list(Ctx),
            memberchk(suggestion(use_change, _, Changes), Ctx),
            cache:ordered_entry(R, E, C, N, _),
            Entry = R://E
          ),
          Suggestions1),
  warning:collect_use_changes(ProofAVL, BWUChanges),
  findall(use_sugg(C2, N2, Entry2, Changes2),
          ( member(use_change(Entry2, Enables, Disables), BWUChanges),
            Entry2 = R2://E2,
            cache:ordered_entry(R2, E2, C2, N2, _),
            findall(use_change(F, enable), member(F, Enables), EC),
            findall(use_change(F, disable), member(F, Disables), DC),
            append(EC, DC, Changes2),
            Changes2 \== []
          ),
          Suggestions2),
  append(Suggestions1, Suggestions2, Suggestions0),
  sort(Suggestions0, Suggestions).

%! warning:print_use_change_suggestions(+Suggestions)
%
% Prints USE change suggestions in the "Assumptions taken" section.

warning:print_use_change_suggestions([]) :- !.
warning:print_use_change_suggestions(UseSuggestions) :-
  length(UseSuggestions, Count),
  ( Count =:= 1 -> Suf = '' ; Suf = 's' ),
  message:color(yellow),
  format('  USE flag change (~d package~w):~n', [Count, Suf]),
  message:color(normal),
  message:color(darkgray),
  message:print('  Add to /etc/portage/package.use:'), nl,
  forall(member(use_sugg(C, N, _Entry, Changes), UseSuggestions),
         ( plan:format_use_change_flags(Changes, FlagsStr),
           format('    ~w/~w ~w~n', [C, N, FlagsStr])
         )),
  message:color(normal),
  nl.


% -----------------------------------------------------------------------------
%  USE changes (legacy build_with_use scan)
% -----------------------------------------------------------------------------

%! warning:print_use_changes(+ProofAVL)
%
% Walks the proof and reports packages where the build_with_use context
% requires USE flag changes that differ from the current effective USE.
% Now integrated into the Assumptions section; this predicate is kept
% for backward compatibility but delegates to the suggestions section.

warning:print_use_changes(_ProofAVL).

%! warning:collect_use_changes(+ProofAVL, -UseChanges)
%
% Walks the proof for build_with_use contexts and collects entries
% where the effective USE differs from the requested state.

warning:collect_use_changes(ProofAVL, UseChanges) :-
  findall(use_change(Entry, Enables, Disables),
          ( assoc:gen_assoc(Key, ProofAVL, _),
            warning:proof_key_use_changes(Key, Entry, Enables, Disables),
            ( Enables \== [] ; Disables \== [] )
          ),
          Changes0),
  sort(Changes0, UseChanges).

%! warning:proof_key_use_changes(+Key, -Entry, -NeedEnable, -NeedDisable)
%
% For a proof key with build_with_use context, computes which USE flags
% need enabling or disabling relative to the effective USE set.

warning:proof_key_use_changes(Key, Entry, NeedEnable, NeedDisable) :-
  warning:proof_key_bwu_context(Key, Repo, Id, En, Dis),
  Entry = Repo://Id,
  use:entry_effective_use_set(Repo://Id, EffEnabled),
  findall(U, ( member(U, En), \+ memberchk(U, EffEnabled) ), NeedEnable0),
  findall(U, ( member(U, Dis), memberchk(U, EffEnabled) ), NeedDisable0),
  sort(NeedEnable0, NeedEnable),
  sort(NeedDisable0, NeedDisable).

%! warning:proof_key_bwu_context(+Key, -Repo, -Id, -Enable, -Disable)
%
% Extracts build_with_use enable/disable lists from a proof key context.

warning:proof_key_bwu_context(Repo://Id:_Action?{Ctx}, Repo, Id, En, Dis) :-
  is_list(Ctx),
  memberchk(build_with_use:use_state(En, Dis), Ctx),
  !.

%! warning:print_use_change_lines(+Changes)
%
% Prints USE change lines in package.use format (=entry flag1 -flag2 ...).

warning:print_use_change_lines([]) :- !.
warning:print_use_change_lines([use_change(Entry, Enables, Disables)|Rest]) :-
  findall(A, ( member(U, Enables), atom_string(U, A) ), PosAtoms),
  findall(A, ( member(U, Disables), format(atom(A), '-~w', [U]) ), NegAtoms),
  append(PosAtoms, NegAtoms, AllFlags),
  atomic_list_concat(AllFlags, ' ', FlagsStr),
  format('    =~w ~w~n', [Entry, FlagsStr]),
  warning:print_use_change_lines(Rest).


% -----------------------------------------------------------------------------
%  Bug report drafts (domain assumptions)
% -----------------------------------------------------------------------------

%! warning:print_bugreport_drafts(+DomainAssumptions)
%
% Groups domain assumptions into bug report drafts and prints them
% under the "Bug report drafts (Gentoo Bugzilla)" header.

warning:print_bugreport_drafts(DomainAssumptions) :-
  warning:bugreport_groups(DomainAssumptions, Groups),
  ( Groups == [] ->
      true
  ; nl,
    message:header('Bug report drafts (Gentoo Bugzilla)'),
    nl,
    forall(member(G, Groups),
           ( warning:print_bugreport_group(G),
             nl ))
  ).

%! warning:bugreport_groups(+DomainAssumptions, -Groups)
%
% Groups domain assumptions per (Reason, C/N, Constraints, RequiredBy),
% merging run/install variants into unified report groups.

warning:bugreport_groups(DomainAssumptions, Groups) :-
  findall(Key-Issue,
          ( member(Content, DomainAssumptions),
            warning:bugreport_issue(Content, Key, Issue)
          ),
          Pairs0),
  keysort(Pairs0, Pairs),
  group_pairs_by_key(Pairs, Grouped),
  findall(Group,
          ( member(_Key-Issues, Grouped),
            warning:merge_bugreport_issues(Issues, Group)
          ),
          Groups).

%! warning:bugreport_issue(+Content, -Key, -Issue)
%
% Extracts a structured bug report issue from a grouped_package_dependency
% assumption, including reason, provenance, and constraints.

warning:bugreport_issue(Content, Key, issue(Reason, RequiredBy, C, N, Constraints, Actions)) :-
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
  warning:extract_constraints_from_packagedeps(C, N, PackageDeps, Constraints),
  Actions = [Action],
  Key = Reason-RequiredBy-C-N-Constraints.
warning:bugreport_issue(_Other, _Key, _Issue) :-
  fail.

%! warning:merge_bugreport_issues(+Issues, -Group)
%
% Merges multiple issues sharing the same key into a single group
% with a unified action set.

warning:merge_bugreport_issues(Issues, group(Reason, RequiredBy, C, N, Constraints, ActionsU)) :-
  Issues = [issue(Reason, RequiredBy, C, N, Constraints, Actions0)|Rest],
  findall(A,
          ( member(issue(_,_,_,_,_,As), [issue(Reason, RequiredBy, C, N, Constraints, Actions0)|Rest]),
            member(A, As)
          ),
          ActionsAll),
  sort(ActionsAll, ActionsU).

%! warning:extract_constraints_from_packagedeps(+C, +N, +PackageDeps, -Constraints)
%
% Extracts version/slot constraint triples from a list of package dependencies.

warning:extract_constraints_from_packagedeps(C, N, PackageDeps, Constraints) :-
  findall(constraint(O,V,S),
          ( member(package_dependency(_Action,no,C,N,O,Ver,S,_U), PackageDeps),
            warning:version_atom(Ver, V)
          ),
          Cs0),
  sort(Cs0, Constraints).

%! warning:version_atom(+Version, -Atom)
%
% Extracts the human-readable atom from a version/7 term or version_none.

warning:version_atom(version(_,_,_,_,_,_,A), A) :- !.
warning:version_atom(version_none, '') :- !.
warning:version_atom(A, A).

%! warning:print_bugreport_group(+Group)
%
% Prints a single bug report draft: summary, affected package, dependency,
% phases, unsatisfiable constraints, observed state, and potential fix.

warning:print_bugreport_group(group(Reason, RequiredBy, C, N, Constraints, Actions)) :-
  warning:bugreport_summary(Reason, RequiredBy, C, N, Summary),
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
           warning:print_bugreport_constraint(O, C, N, V, S),
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
  ( warning:available_versions(C, N, Vs),
    Vs \= [],
    warning:available_version_count_unique(C, N, CountU)
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
  warning:bugreport_potential_fix(Reason, C, N, Constraints, RequiredBy),
  message:color(normal).

%! warning:bugreport_summary(+Reason, +RequiredBy, +C, +N, -Summary)
%
% Builds a one-line summary atom for a bug report title.

warning:bugreport_summary(Reason, RequiredBy0, C0, N0, Summary) :-
  warning:bugreport_safe_atom(RequiredBy0, unknown_depender, RequiredBy),
  warning:bugreport_safe_atom(C0, unknown_category, C),
  warning:bugreport_safe_atom(N0, unknown_package, N),
  warning:bugreport_reason_label(Reason, ReasonLabel),
  % Always bind Summary to an atom (even if inputs are variables).
  format(atom(Summary), '~w: ~w dependency on ~w/~w', [RequiredBy, ReasonLabel, C, N]).

%! warning:bugreport_safe_atom(+X, +Default, -Out)
%
% Safely converts X to a printable atom, falling back to Default if X
% is unbound or not a recognized term.

warning:bugreport_safe_atom(X, Default, Out) :-
  ( atom(X) -> Out = X
  ; X = Repo://Entry, atom(Repo), atom(Entry) -> Out = (Repo://Entry)
  ; Out = Default
  ).

%! warning:bugreport_reason_label(+Reason, -Label)
%
% Maps an assumption reason atom to a human-readable label for bug report titles.

warning:bugreport_reason_label(Reason, 'unsatisfied dependency') :-
  var(Reason),
  !.
warning:bugreport_reason_label(Reason, 'unsatisfiable version constraint') :-
  ( Reason = version_no_candidate(_,_) ; Reason = version_no_candidate ),
  !.
warning:bugreport_reason_label(Reason, 'conflicting version constraints') :-
  ( Reason = version_conflict ; Reason = version_conflict(_) ),
  !.
warning:bugreport_reason_label(slot_unsatisfied,   'unsatisfiable slot constraint') :- !.
warning:bugreport_reason_label(keyword_filtered,   'keyword-filtered') :- !.
warning:bugreport_reason_label(masked,             'masked') :- !.
warning:bugreport_reason_label(installed_required, 'installed-only requirement') :- !.
warning:bugreport_reason_label(Reason, Reason).

%! warning:print_bugreport_constraint(+O, +C, +N, +V, +S)
%
% Prints a single constraint line (e.g. >=cat/pkg-1.0:slot) for a bug report.

warning:print_bugreport_constraint(O, C, N, V, S) :-
  info:print_comparator(O),
  write(C), write('/'), write(N), write('-'), write(V),
  info:print_slot_restriction(S).

%! warning:available_versions(+C, +N, -Sample)
%
% Returns up to 8 available version atoms for C/N across all repositories.

warning:available_versions(C, N, Sample) :-
  findall(V,
          ( cache:ordered_entry(_Repo, _Id, C, N, Ver),
            warning:version_atom(Ver, V)
          ),
          Vs0),
  sort(Vs0, Vs),
  % Take up to 8 to keep output short.
  warning:take_first_n(Vs, 8, Sample).
warning:available_versions(_C, _N, []).

%! warning:bugreport_potential_fix(+Reason, +C, +N, +Constraints, +RequiredBy)
%
% Prints a context-sensitive fix suggestion based on the assumption reason.

warning:bugreport_potential_fix(Reason, C, N, Constraints, RequiredBy) :-
  ( Reason = version_no_candidate(Op, Ver) ->
      warning:bugreport_constraint_short(Op, Ver, Short),
      format('  One constraint has zero matches: ~w. Consider relaxing/removing that bound after verifying compatibility.~n',
             [Short])
    ,
    ( warning:available_version_range(C, N, MinV, MaxV, Count) ->
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

%! warning:available_version_range(+C, +N, -MinAtom, -MaxAtom, -Count)
%
% Computes a human-readable (min..max) version range for C/N across repositories.

warning:available_version_range(C, N, MinAtom, MaxAtom, Count) :-
  findall(Ver, cache:ordered_entry(_Repo, _Id, C, N, Ver), Vers0Raw),
  Vers0Raw \= [],
  sort(Vers0Raw, Vers0), % unique (may include multiple repos, but dedup by term)
  length(Vers0, Count),
  predsort(warning:compare_versions, Vers0, VersSorted),
  VersSorted = [Min|_],
  last(VersSorted, Max),
  warning:version_atom(Min, MinAtom),
  warning:version_atom(Max, MaxAtom).

%! warning:available_version_count_unique(+C, +N, -Count)
%
% Counts the number of unique versions available for C/N.

warning:available_version_count_unique(C, N, Count) :-
  findall(Ver, cache:ordered_entry(_Repo, _Id, C, N, Ver), Vers0Raw),
  sort(Vers0Raw, Vers0),
  length(Vers0, Count).

%! warning:compare_versions(-Delta, +A, +B)
%
% Version comparison callback for predsort/3.

warning:compare_versions(Delta, A, B) :-
  ( system:compare(<, A, B) -> Delta = (<)
  ; system:compare(>, A, B) -> Delta = (>)
  ; Delta = (=)
  ).

%! warning:take_first_n(+List, +N, -Prefix)
%
% Takes the first N elements from List, or all if fewer than N.

warning:take_first_n(_, 0, []) :- !.
warning:take_first_n([], _N, []) :- !.
warning:take_first_n([X|Xs], N, [X|Ys]) :-
  N > 0,
  N1 is N - 1,
  warning:take_first_n(Xs, N1, Ys).


%! warning:bugreport_constraint_short(+Op, +Ver, -Short)
%
% Formats a version constraint as a compact atom (e.g. ">=1.2.3").

warning:bugreport_constraint_short(Op, Ver0, Short) :-
  eapi:comparator_symbol(Op, Sym),
  warning:version_atom(Ver0, Ver),
  format(atom(Short), '~w~w', [Sym, Ver]).



% -----------------------------------------------------------------------------
%  Assumption handling and detail printing
% -----------------------------------------------------------------------------

%! warning:handle_assumption(+ProofKey)
%
% Helper to print details for both domain driven and prover driven assumption formats.

warning:handle_assumption(ProofKey) :-
  % Case 1: key format: rule(assumed(...)) % domain driven assumption
  (   ProofKey = rule(assumed(Content)) ->
      warning:print_assumption_detail(rule(Content, [])),
      nl
  % Case 2: key format: assumed(rule(...)) % prover driven assumption
  ;   ProofKey = assumed(rule(Content)) ->
      warning:print_assumption_detail(rule(Content, [])),
      nl
  ;
      true
  ).


%! warning:handle_assumption(+ProofKey,+ProofAVL,+TriggersAVL)
%
% Extended assumption printer that can use proof and triggers for explanations.
warning:handle_assumption(ProofKey, ProofAVL, TriggersAVL) :-
  % Case 1: key format: rule(assumed(...)) % domain driven assumption
  (   ProofKey = rule(assumed(Content)) ->
      warning:print_assumption_detail(rule(Content, [])),
      nl
  % Case 2: key format: assumed(rule(...)) % prover driven assumption
  ;   ProofKey = assumed(rule(Content)) ->
      warning:print_assumption_detail(rule(Content, [])),
      cycle:print_cycle_explanation(Content, ProofAVL, TriggersAVL),
      nl
  ;
      true
  ).



%! warning:print_assumption_detail(+RuleTerm)
%
% Prints formatted, non-garbled assumption details.

warning:print_assumption_detail(rule(package_dependency(T,A,C,N,X,Y,Z,XX):_YY?{Ctx},_)) :- !,
    message:color(lightred),
    message:style(bold),
    warning:assumption_reason_label(Ctx, Label),
    message:print('- '),
    message:print(Label),
    message:print(' '),
    message:print(T),
    message:print(' dependency: '),
    message:style(normal),
    nl,
    message:color(normal),
    info:print_metadata_item_detail(_,'  ',package_dependency(T,A,C,N,X,Y,Z,XX)),nl,
    warning:print_assumption_provenance(Ctx).

warning:print_assumption_detail(rule(grouped_package_dependency(C,N,R):T?{Ctx},_)) :- !,
    message:color(lightred),
    message:style(bold),
    warning:assumption_reason_label(Ctx, Label),
    message:print('- '),
    message:print(Label),
    message:print(' '),
    message:print(T),
    message:print(' dependency: '),
    message:style(normal),
    nl,
    message:color(normal),
    info:print_metadata_item_detail(_,'  ',grouped_package_dependency(C,N,R)),nl,
    warning:print_assumption_provenance(Ctx),
    warning:print_tree_issue_note(C, N, R).

warning:print_assumption_detail(rule(grouped_package_dependency(X,C,N,R):install,_)) :- !,
    message:color(lightred),
    message:style(bold),
    message:print('- Assumed installed: '),
    message:style(normal),
    message:color(normal),
    nl,
    info:print_metadata_item_detail(_,'  ',grouped_package_dependency(X,C,N,R)),nl.

warning:print_assumption_detail(rule(grouped_package_dependency(X,C,N,R):run,_)) :- !,
    message:color(lightred),
    message:style(bold),
    message:print('- Assumed running: '),
    message:style(normal),
    message:color(normal),
    nl,
    info:print_metadata_item_detail(_,'  ',grouped_package_dependency(X,C,N,R)),nl.

warning:print_assumption_detail(rule(R://E:install,_)) :- !,
    message:color(lightred),
    message:style(bold),
    message:print('- Assumed installed: '),
    message:style(normal),
    message:color(normal),nl,
    message:print('  '),
    message:print(R://E), nl.

warning:print_assumption_detail(rule(R://E:run,_)) :- !,
    message:color(lightred),
    message:style(bold),
    message:print('- Assumed running: '),
    message:style(normal),
    message:color(normal),nl,
    message:print('  '),
    message:print(R://E), nl.

warning:print_assumption_detail(rule(R://E:unmask?{_Ctx},_)) :- !,
    message:color(lightred),
    message:style(bold),
    message:print('- Masked (assumed unmasked): '),
    message:style(normal),
    message:color(normal),nl,
    message:print('  '),
    message:print(R://E), nl.

warning:print_assumption_detail(rule(R://E:unmask,_)) :- !,
    message:color(lightred),
    message:style(bold),
    message:print('- Masked (assumed unmasked): '),
    message:style(normal),
    message:color(normal),nl,
    message:print('  '),
    message:print(R://E), nl.

% Blocker assumptions (introduced by rules.pl when we print a "plan with blocker
% assumptions" after a failed strict solve).
warning:print_assumption_detail(rule(blocker(Strength, Phase, C, N, _O, _V, _SlotReq)?{Ctx}, _)) :- !,
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
    warning:print_assumption_provenance(Ctx).

warning:print_assumption_detail(rule(blocker(Strength, Phase, C, N, O, V, SlotReq), Body)) :- !,
    warning:print_assumption_detail(rule(blocker(Strength, Phase, C, N, O, V, SlotReq)?{[]}, Body)).

warning:print_assumption_detail(rule(R://E:_Action?{Ctx}, _Body)) :-
    is_list(Ctx),
    memberchk(issue_with_model(explanation), Ctx),
    !,
    query:search([category(C), name(N)], R://E),
    message:color(lightred),
    message:style(bold),
    message:print('- Model unavailable: '),
    message:style(normal),
    message:color(normal),
    nl,
    format('  ~w/~w — dependency model could not be built~n', [C, N]),
    format('  (some dependencies may be missing from the tree or keyword-filtered)~n', []),
    warning:print_assumption_provenance(Ctx).

warning:print_assumption_detail(rule(C,_)) :-
    message:color(lightred),
    message:style(bold),
    message:print('- Other: '),
    message:style(normal),
    message:color(normal),nl,
    message:print('  '),
    message:print(C), nl.

%! warning:print_assumption_provenance(+Ctx)
%
% Prints a provenance hint ("required by: ...") for domain assumptions
% when a self/1 tag is present in the context list.

warning:print_assumption_provenance(Ctx0) :-
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

%! warning:print_tree_issue_note(+C, +N, +PackageDeps)
%
% Prints a contextual note if a known tree issue matches this dependency.

warning:print_tree_issue_note(C, N, PackageDeps) :-
  ( issue:tree_issue_context(C, N, PackageDeps, Note) ->
      message:color(darkgray),
      message:print('  Note: '),
      message:print(Note),
      nl,
      message:color(normal)
  ; true
  ).

%! warning:assumption_reason_label(+CtxLike, -Label)
%
% Extracts the assumption reason from a context-like term and maps it
% to a human-readable label via assumption_reason_label_/2.

warning:assumption_reason_label(CtxLike, Label) :-
  explainer:term_ctx(_:_?{CtxLike}, Ctx),
  ( memberchk(assumption_reason(Reason), Ctx)
  -> warning:assumption_reason_label_(Reason, Label)
  ; Label = 'Non-existent'
  ).

%! warning:assumption_reason_label_(+Reason, -Label)
%
% Maps an internal assumption reason atom to its display label.

warning:assumption_reason_label_(missing,                 'Missing').
warning:assumption_reason_label_(masked,                  'Masked').
warning:assumption_reason_label_(keyword_filtered,        'Keyword filtered (assumed accepted)').
warning:assumption_reason_label_(installed_required,      'Requires installed candidate for').
warning:assumption_reason_label_(slot_unsatisfied,        'Unsatisfied slot constraint for').
warning:assumption_reason_label_(version_no_candidate(_,_), 'Unsatisfied version constraint for').
warning:assumption_reason_label_(version_conflict(_),       'Conflicting version constraints for').
warning:assumption_reason_label_(version_no_candidate,    'Unsatisfied version constraint for').
warning:assumption_reason_label_(version_conflict,        'Conflicting version constraints for').
warning:assumption_reason_label_(unsatisfied_constraints, 'Unsatisfied constraints for').