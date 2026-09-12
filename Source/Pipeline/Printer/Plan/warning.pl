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
%  Context unwrapping
% -----------------------------------------------------------------------------

%! warning:unwrap_ctx(+Ctx0, -Ctx) is det.
%
% Extracts a plain list from a context term that may be wrapped in {}/1.

warning:unwrap_ctx(Ctx0, Ctx) :-
  ( is_list(Ctx0) -> Ctx = Ctx0
  ; Ctx0 = {Inner}, is_list(Inner) -> Ctx = Inner
  ; Ctx = []
  ).


% -----------------------------------------------------------------------------
%  Print warnings
% -----------------------------------------------------------------------------

%! warning:print_warnings(+Annotations, +ProofAVL, +TriggersAVL)
%
% Prints assumptions found in the proof. Annotations is the
% proof_annotations record produced by annotation:collect/2 (single-pass
% proof traversal); ProofAVL is still needed for cycle explanations.
%
% There are two distinct assumption mechanisms in this codebase:
%
% - Domain (resolving.pl) assumptions:
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

warning:print_warnings(Annotations, ProofAVL, TriggersAVL) :-
  annotation:domain_assumptions(Annotations, DomainAssumptions),
  annotation:cycle_break_contents(Annotations, CycleAssumptions),
  % annotation:collect/2 already filtered out the assumed(...) records that
  % hit nothing (soft blockers); when nothing effective remains, the plain
  % suggestions clause below applies.
  ( DomainAssumptions \== [] ; CycleAssumptions \== [] ),
  !,
  nl,
  partition(warning:is_blocker_assumption, DomainAssumptions, BlockerAssumptions, NonBlockerAssumptions),
  % 1. Suggestions/assumptions section first
  warning:print_suggestions_section(NonBlockerAssumptions, BlockerAssumptions, Annotations),
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
                     message:print('  (runtime-only cycle)'), nl,
                     message:color(normal)
                 ; true
               ),
               plan:print_cycle_break_detail(Content),
               ( config:print_prover_cycles(true) ->
                   cycle:print_cycle_explanation(Content, ProofAVL, TriggersAVL)
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

warning:print_warnings(Annotations, _, _) :-
  !,
  warning:print_suggestions_section([], [], Annotations),
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
  ( Content = blocker(Strength, Phase, C, N, O, V, SlotReq)?{Ctx0} ->
      warning:unwrap_ctx(Ctx0, Ctx)
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
  ( var(V0) -> V = '' ; version_domain:display_atom(V0, V) ),
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

%! warning:print_suggestions_section(+NonBlockerAssumptions, +BlockerAssumptions, +Annotations)
%
% Collects all suggestion(...) tags from both domain assumptions and
% the proof annotations record, then prints an actionable summary.

warning:print_suggestions_section(NonBlockerAssumptions, _BlockerAssumptions, Annotations) :-
  warning:collect_keyword_suggestions(NonBlockerAssumptions, Annotations, KwSuggestions),
  warning:collect_unmask_suggestions(NonBlockerAssumptions, Annotations, UnmaskSuggestions),
  warning:collect_license_suggestions(Annotations, LicenseSuggestions),
  warning:collect_use_change_suggestions(Annotations, UseSuggestions),
  ( KwSuggestions == [], UnmaskSuggestions == [], LicenseSuggestions == [],
    UseSuggestions == [] ->
      true
  ; nl,
    message:header('Assumptions taken during proving & planning:'),
    nl,
    warning:print_keyword_suggestions(KwSuggestions),
    warning:print_unmask_suggestions(UnmaskSuggestions),
    warning:print_license_suggestions(LicenseSuggestions),
    warning:print_use_change_suggestions(UseSuggestions)
  ).

%! warning:collect_keyword_suggestions(+Assumptions, +Annotations, -Suggestions)
%
% Gathers keyword acceptance suggestions from both domain assumptions
% and fully resolved proof entries tagged with suggestion(accept_keyword, _).

warning:collect_keyword_suggestions(Assumptions, Annotations, Suggestions) :-
  % From domain assumptions (legacy fallback)
  findall(kw(C, N, K),
          ( member(Content, Assumptions),
            warning:assumption_has_keyword_suggestion(Content, C, N, K)
          ),
          Suggestions1),
  % From fully resolved proof entries (keyword_acceptance fallback)
  annotation:keywords(Annotations, ProofKeywords),
  findall(kw(C, N, K),
          member(accept_keyword(_R, _E, C, N, K), ProofKeywords),
          Suggestions2),
  append(Suggestions1, Suggestions2, Suggestions0),
  sort(Suggestions0, Suggestions).

%! warning:assumption_has_keyword_suggestion(+Content, -C, -N, -K)
%
% Extracts keyword suggestion details from a domain assumption context.

warning:assumption_has_keyword_suggestion(Content, C, N, K) :-
  Content = grouped_package_dependency(C, N, _):_?{Ctx0},
  warning:unwrap_ctx(Ctx0, Ctx),
  memberchk(suggestion(accept_keyword, K), Ctx),
  !.

%! warning:collect_unmask_suggestions(+Assumptions, +Annotations, -Suggestions)
%
% Gathers package unmask suggestions from both domain assumptions
% and fully resolved proof entries tagged with suggestion(unmask, _).

warning:collect_unmask_suggestions(Assumptions, Annotations, Suggestions) :-
  % From domain assumptions (legacy fallback)
  findall(unmask(R, E, C, N),
          ( member(Content, Assumptions),
            warning:assumption_has_unmask_suggestion(Content, R, E, C, N)
          ),
          Suggestions1),
  % From fully resolved proof entries (package.mask / unmask fallback only)
  annotation:unmasks(Annotations, Suggestions2),
  append(Suggestions1, Suggestions2, Suggestions0),
  sort(Suggestions0, Suggestions).


%! warning:collect_license_suggestions(+Annotations, -Suggestions)
%
% Gathers license acceptance suggestions from proof entries tagged with
% suggestion(accept_license, _).

warning:collect_license_suggestions(Annotations, Suggestions) :-
  annotation:licenses(Annotations, Suggestions).


%! warning:print_license_suggestions(+Suggestions)
%
% Prints license acceptance hints with package.license instructions.

warning:print_license_suggestions([]) :- !.
warning:print_license_suggestions(LicenseSuggestions) :-
  length(LicenseSuggestions, Count),
  ( Count =:= 1 -> Suf = '' ; Suf = 's' ),
  message:color(yellow),
  format('  License acceptance (~d package~w):~n', [Count, Suf]),
  message:color(normal),
  message:color(darkgray),
  message:print('  Add to /etc/portage/package.license:'), nl,
  forall(member(accept_license(R, E, _C, _N), LicenseSuggestions),
         warning:print_license_suggestion_line(R, E)),
  message:color(normal),
  nl.


%! warning:print_license_suggestion_line(+Repo, +Entry)
%
% One package.license line: =cat/pkg-version followed by required licenses.

warning:print_license_suggestion_line(R, E) :-
  ( builder:atom_for_entry(R, E, Atom) -> true ; Atom = E ),
  findall(Lic, acceptance:effective_license(R://E, Lic), Lics0),
  sort(Lics0, Lics),
  ( Lics == [] ->
      format('    =~w~n', [Atom])
  ; atomic_list_concat(Lics, ' ', LicAtom),
    format('    =~w ~w~n', [Atom, LicAtom])
  ).

%! warning:assumption_has_unmask_suggestion(+Content, -R, -E, -C, -N)
%
% Extracts unmask suggestion details from a domain assumption context.

warning:assumption_has_unmask_suggestion(R://E:unmask?{Ctx0}, R, E, C, N) :-
  warning:unwrap_ctx(Ctx0, Ctx),
  memberchk(suggestion(unmask), Ctx),
  memberchk(masked_cn(C, N), Ctx),
  !.
warning:assumption_has_unmask_suggestion(Content, _R, _E, C, N) :-
  Content = grouped_package_dependency(C, N, _):_?{Ctx0},
  warning:unwrap_ctx(Ctx0, Ctx),
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

%! warning:collect_use_change_suggestions(+Annotations, -Suggestions)
%
% Collects USE change suggestions from the proof annotations: both from
% suggestion(use_change, ...) tags and from build_with_use contexts
% where the effective USE differs from the requested state.

warning:collect_use_change_suggestions(Annotations, Suggestions) :-
  annotation:use_changes(Annotations, ProofUseChanges),
  findall(use_sugg(C, N, R://E, Changes),
          member(use_change(R, E, C, N, Changes), ProofUseChanges),
          Suggestions1),
  annotation:bwu_changes(Annotations, BWUChanges),
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
%  Bug report drafts (domain assumptions)
% -----------------------------------------------------------------------------

%! warning:print_proof_bugreport_drafts(+ProofAVL)
%
% The --bugs output: bug report drafts for the effective domain
% assumptions of a proof (collected the same way as for the plan
% printout, so soft blocker records that hit nothing are not drafted),
% or "(none)" under the header when the proof is clean.

warning:print_proof_bugreport_drafts(ProofAVL) :-
  annotation:collect(ProofAVL, Annotations),
  annotation:domain_assumptions(Annotations, DomainAssumptions),
  ( DomainAssumptions == [] ->
      message:header('Bug report drafts (Gentoo Bugzilla)'),
      nl,
      writeln('  (none)')
  ; warning:print_bugreport_drafts(DomainAssumptions)
  ).


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
  Content = grouped_package_dependency(C,N,PackageDeps):Action?{Ctx0},
  !,
  warning:unwrap_ctx(Ctx0, Ctx),
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
            version_domain:display_atom(Ver, V)
          ),
          Cs0),
  sort(Cs0, Constraints).


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

% -----------------------------------------------------------------------------
%  Discovered-dependency bug report drafts (portage-ng#102)
% -----------------------------------------------------------------------------

%! warning:print_discovered_bugreport_drafts is det.
%
% Renders a Gentoo Bugzilla bug report draft for every build dependency
% discovered (and worked around) this session by the missing-provider
% feedback mechanism (feedback:session_discovery/4). Gated by
% config:bugreport_drafts_enabled/1. Each draft doubles as an upstream
% ebuild/eclass bug report: the metadata was missing a BDEPEND that a
% build proved was needed.

warning:print_discovered_bugreport_drafts :-
  ( catch(config:bugreport_drafts_enabled(true), _, fail),
    feedback:session_discoveries(Discoveries),
    Discoveries \== []
  -> nl,
     message:header('Missing build dependencies discovered (bug report drafts)'),
     nl,
     forall(member(discovery(Target, Provider, Kind, Evidence), Discoveries),
            ( warning:print_discovered_bugreport(Target, Provider, Kind, Evidence),
              nl ))
  ;  true
  ).


%! warning:print_discovered_bugreport(+Target, +Provider, +Kind, +Evidence) is det.
%
% Prints one discovered-dependency draft: summary, affected package,
% missing dependency, observed evidence (symbol/phase/exit/log line), and
% the suggested fix (add the provider to BDEPEND).

warning:print_discovered_bugreport(Target, Provider, _Kind, Evidence) :-
  warning:discovered_evidence_fields(Evidence, SymKind, SymName, Phase, Exit, LogLine),
  ( Target = _Repo://Entry -> true ; Entry = Target ),
  message:color(darkgray),
  message:print('---'), nl,
  message:color(normal),
  message:style(bold),
  message:print('Summary: '),
  message:style(normal),
  format('~w: missing BDEPEND=~w (~w ~w not found)~n', [Entry, Provider, SymKind, SymName]),
  nl,
  message:style(bold),
  message:print('Affected package: '),
  message:style(normal),
  message:color(darkgray),
  message:print(Target),
  message:color(normal),
  nl,
  message:style(bold),
  message:print('Missing dependency: '),
  message:style(normal),
  message:color(darkgray),
  format('~w (build-time / BDEPEND)~n', [Provider]),
  message:color(normal),
  message:style(bold),
  message:print('Observed:'),
  message:style(normal),
  nl,
  message:color(darkgray),
  format('  ~w ~w not found during the ~w phase (exit ~w):~n', [SymKind, SymName, Phase, Exit]),
  ( LogLine == '' -> true ; format('    ~w~n', [LogLine]) ),
  message:color(normal),
  message:style(bold),
  message:print('Potential fix (suggestion):'),
  message:style(normal),
  nl,
  message:color(darkgray),
  format('  Add BDEPEND="~w" to the ebuild or the responsible inherited eclass.~n', [Provider]),
  format('  (discovered by portage-ng missing-provider feedback, portage-ng#102)~n', []),
  message:color(normal).


%! warning:discovered_evidence_fields(+Evidence, -Kind, -Name, -Phase, -Exit, -LogLine) is det.
%
% Destructures the structured Evidence term recorded by
% missing_provider:handle_symbol/6, tolerating a missing/odd shape.

warning:discovered_evidence_fields(Evidence, Kind, Name, Phase, Exit, LogLine) :-
  ( Evidence = evidence(symbol(Kind0, Name0), phase(Phase0), exit(Exit0), resolver(_), log(Log0))
  -> Kind = Kind0, Name = Name0, Phase = Phase0, Exit = Exit0,
     warning:evidence_log_atom(Log0, LogLine)
  ;  Kind = unknown, Name = unknown, Phase = unknown, Exit = unknown, LogLine = ''
  ).


%! warning:evidence_log_atom(+Log, -Atom) is det.
%
% Normalizes a recorded log excerpt (string or atom) to a trimmed atom.

warning:evidence_log_atom(Log, Atom) :-
  ( string(Log) -> atom_string(Atom0, Log) ; Atom0 = Log ),
  ( atom(Atom0) -> Atom = Atom0 ; Atom = '' ).


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

%! warning:available_version_terms(+C, +N, -Versions) is det.
%
% All distinct version terms of C/N across the repositories, in version
% order.  Versions are version/7 terms whose standard order IS the PMS
% version order, so sort/2 both deduplicates and orders them.  Bug-report
% drafts deliberately list every version in the tree (not the resolver's
% mask/keyword-filtered candidate set), which is why this reads the
% cache directly instead of the proof.

warning:available_version_terms(C, N, Versions) :-
  findall(Ver, cache:ordered_entry(_Repo, _Id, C, N, Ver), Vers0),
  sort(Vers0, Versions).


%! warning:available_versions_sample_size(-N) is det.
%
% How many versions a bug-report draft lists before eliding the rest.

warning:available_versions_sample_size(8).


%! warning:available_versions(+C, +N, -Sample) is det.
%
% Up to available_versions_sample_size/1 version atoms for C/N, sorted as
% atoms (the historical draft layout).

warning:available_versions(C, N, Sample) :-
  warning:available_version_terms(C, N, Versions),
  findall(A, ( member(Ver, Versions), version_domain:display_atom(Ver, A) ), Atoms0),
  sort(Atoms0, Atoms),
  warning:available_versions_sample_size(Max),
  length(Atoms, Len),
  Take is min(Len, Max),
  length(Sample, Take),
  append(Sample, _, Atoms).

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

%! warning:available_version_range(+C, +N, -MinAtom, -MaxAtom, -Count) is semidet.
%
% Human-readable (min..max) version range for C/N across repositories.
% Fails when the tree has no version of C/N at all.

warning:available_version_range(C, N, MinAtom, MaxAtom, Count) :-
  warning:available_version_terms(C, N, Versions),
  Versions = [Min|_],
  last(Versions, Max),
  length(Versions, Count),
  version_domain:display_atom(Min, MinAtom),
  version_domain:display_atom(Max, MaxAtom).


%! warning:available_version_count_unique(+C, +N, -Count) is det.
%
% Number of distinct versions of C/N in the tree.

warning:available_version_count_unique(C, N, Count) :-
  warning:available_version_terms(C, N, Versions),
  length(Versions, Count).


%! warning:bugreport_constraint_short(+Op, +Ver, -Short)
%
% Formats a version constraint as a compact atom (e.g. ">=1.2.3").

warning:bugreport_constraint_short(Op, Ver0, Short) :-
  eapi:comparator_symbol(Op, Sym),
  version_domain:display_atom(Ver0, Ver),
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
    warning:print_assumption_provenance(Ctx),
    warning:print_known_bugs(C, N, version_none).

warning:print_assumption_detail(rule(grouped_package_dependency(C,N,_R):_T?{Ctx0},_)) :-
    warning:unwrap_ctx(Ctx0, Ctx),
    memberchk(required_use_violation(ViolDesc), Ctx),
    !,
    message:color(lightred),
    message:style(bold),
    message:print('- REQUIRED_USE violation: '),
    message:style(normal),
    message:color(normal),
    nl,
    format('  ~w/~w~n', [C, N]),
    warning:print_requse_violation_detail(ViolDesc),
    warning:print_assumption_provenance(Ctx),
    warning:print_known_bugs(C, N, version_none).

warning:print_assumption_detail(rule(grouped_package_dependency(C,N,_R):_T?{Ctx0},_)) :-
    warning:unwrap_ctx(Ctx0, Ctx),
    memberchk(slot_conflict(SlotConflictDesc), Ctx),
    !,
    message:color(lightred),
    message:style(bold),
    message:print('- Slot conflict: '),
    message:style(normal),
    message:color(normal),
    nl,
    format('  ~w/~w~n', [C, N]),
    warning:print_slot_conflict_detail(SlotConflictDesc),
    warning:print_assumption_provenance(Ctx),
    warning:print_known_bugs(C, N, version_none).

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
    warning:print_tree_issue_note(C, N, R),
    warning:print_known_bugs(C, N, version_none).

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
    message:print(R://E), nl,
    warning:print_entry_known_bugs(R://E).

warning:print_assumption_detail(rule(R://E:unmask,_)) :- !,
    message:color(lightred),
    message:style(bold),
    message:print('- Masked (assumed unmasked): '),
    message:style(normal),
    message:color(normal),nl,
    message:print('  '),
    message:print(R://E), nl,
    warning:print_entry_known_bugs(R://E).

% Blocker assumptions (introduced by resolving.pl when we print a "plan with blocker
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
    warning:print_assumption_provenance(Ctx),
    warning:print_known_bugs(C, N, version_none).

warning:print_assumption_detail(rule(blocker(Strength, Phase, C, N, O, V, SlotReq), Body)) :- !,
    warning:print_assumption_detail(rule(blocker(Strength, Phase, C, N, O, V, SlotReq)?{[]}, Body)).

warning:print_assumption_detail(rule(R://E:_Action?{Ctx0}, _Body)) :-
    warning:unwrap_ctx(Ctx0, Ctx),
    memberchk(required_use_violation(ViolDesc), Ctx),
    !,
    query:search([category(C), name(N)], R://E),
    message:color(lightred),
    message:style(bold),
    message:print('- REQUIRED_USE violation: '),
    message:style(normal),
    message:color(normal),
    nl,
    format('  ~w/~w~n', [C, N]),
    warning:print_requse_violation_detail(ViolDesc),
    warning:print_assumption_provenance(Ctx).

warning:print_assumption_detail(rule(R://E:_Action?{Ctx0}, _Body)) :-
    warning:unwrap_ctx(Ctx0, Ctx),
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
  warning:unwrap_ctx(Ctx0, Ctx),
  ( memberchk(self(Repo://Entry), Ctx) ->
      message:color(darkgray),
      message:print('  required by: '),
      message:print(Repo://Entry),
      nl,
      message:color(normal)
  ; true
  ).


%! warning:print_requse_violation_detail(+ViolationDescriptor)
%
% Renders a structured REQUIRED_USE violation produced by
% use:describe_required_use_violation/3.

warning:print_requse_violation_detail(
        required_use_violation(_RepoEntry, Enable, Disable, Violated)) :- !,
    ( Enable \== [] ->
        format('  USE deps force:   ~w~n', [Enable])
    ; true
    ),
    ( Disable \== [] ->
        format('  USE deps disable: ~w~n', [Disable])
    ; true
    ),
    ( Violated \== [] ->
        forall(member(V, Violated),
               ( warning:requse_term_to_text(V, Text),
                 format('  violates: ~w~n', [Text])
               ))
    ; format('  (REQUIRED_USE constraint violated)~n', [])
    ).
warning:print_requse_violation_detail(
        use_dep_unsat(RepoEntry, use_state(Enable, Disable), Why)) :- !,
    format('  No ebuild satisfies USE deps for ~w (use_dep_unsat)~n', [RepoEntry]),
    ( Enable \== [] ->
        format('  USE deps force:   ~w~n', [Enable])
    ; true
    ),
    ( Disable \== [] ->
        format('  USE deps disable: ~w~n', [Disable])
    ; true
    ),
    ( Why == profile_hard_conflict ->
        format('  conflicts with profile use.mask / use.force~n', [])
    ; warning:print_requse_violation_detail(Why)
    ).
warning:print_requse_violation_detail(
        use_flag_conflict(Conflicts, Enable, Disable)) :- !,
    format('  Conflicting USE flags: ~w~n', [Conflicts]),
    format('  Required enabled by:  ~w~n', [Enable]),
    format('  Required disabled by: ~w~n', [Disable]),
    format('  (cannot satisfy both enable and disable for the same flag)~n', []).
warning:print_requse_violation_detail(_) :-
    format('  (REQUIRED_USE constraint violated)~n', []).


%! warning:print_slot_conflict_detail(+SlotConflictDesc)
%
% Renders slot conflict details showing which versions of a package were
% pulled into the same slot by different dependencies.

warning:print_slot_conflict_detail(
        slot_conflict_info(ConflictC, ConflictN, domain_conflict(Domain1, Domain2))) :- !,
    format('  ~w/~w has conflicting version requirements:~n',
           [ConflictC, ConflictN]),
    warning:print_domain_bound(Domain1),
    warning:print_domain_bound(Domain2),
    format('  These constraints cannot be satisfied simultaneously.~n', []).
warning:print_slot_conflict_detail(
        slot_conflict_info(ConflictC, ConflictN, Entries)) :-
    is_list(Entries), !,
    format('  Multiple versions of ~w/~w pulled into the same slot:~n',
           [ConflictC, ConflictN]),
    forall(member(slot_entry(Repo, Entry, Ver, SlotKey), Entries),
           format('    ~w/~w-~w (slot ~w, repo ~w)~n',
                  [ConflictC, Entry, Ver, SlotKey, Repo])).
warning:print_slot_conflict_detail(_) :-
    format('  (slot conflict detected)~n', []).


%! warning:print_domain_bound(+Domain)
%
% Renders a version domain's bounds as human-readable constraints.

warning:print_domain_bound(version_domain(_Slots, Bounds)) :- !,
    forall(member(bound(Op, Ver), Bounds),
           ( eapi:comparator_symbol(Op, OpSym),
             version_domain:display_atom(Ver, VerStr),
             format('    ~w~w~n', [OpSym, VerStr])
           )).
warning:print_domain_bound(Domain) :-
    format('    ~w~n', [Domain]).


%! warning:requse_term_to_text(+ReqUseTerm, -Text)
%
% Converts a parsed REQUIRED_USE term back into human-readable PMS notation.

warning:requse_term_to_text(required(Use), Text) :- !,
    atom_string(Use, Text).
warning:requse_term_to_text(required(minus(Use)), Text) :- !,
    format(atom(Text), '-~w', [Use]).
warning:requse_term_to_text(blocking(Use), Text) :- !,
    format(atom(Text), '!~w', [Use]).
warning:requse_term_to_text(exactly_one_of_group(Deps), Text) :- !,
    maplist(warning:requse_term_to_text, Deps, Texts),
    atomic_list_concat(Texts, ' ', Inner),
    format(atom(Text), '^^ ( ~w )', [Inner]).
warning:requse_term_to_text(at_most_one_of_group(Deps), Text) :- !,
    maplist(warning:requse_term_to_text, Deps, Texts),
    atomic_list_concat(Texts, ' ', Inner),
    format(atom(Text), '?? ( ~w )', [Inner]).
warning:requse_term_to_text(any_of_group(Deps), Text) :- !,
    maplist(warning:requse_term_to_text, Deps, Texts),
    atomic_list_concat(Texts, ' ', Inner),
    format(atom(Text), '|| ( ~w )', [Inner]).
warning:requse_term_to_text(use_conditional_group(positive, Use, _, Deps), Text) :- !,
    maplist(warning:requse_term_to_text, Deps, Texts),
    atomic_list_concat(Texts, ' ', Inner),
    format(atom(Text), '~w? ( ~w )', [Use, Inner]).
warning:requse_term_to_text(use_conditional_group(negative, Use, _, Deps), Text) :- !,
    maplist(warning:requse_term_to_text, Deps, Texts),
    atomic_list_concat(Texts, ' ', Inner),
    format(atom(Text), '!~w? ( ~w )', [Use, Inner]).
warning:requse_term_to_text(Term, Text) :-
    format(atom(Text), '~w', [Term]).


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


%! warning:print_entry_known_bugs(+Repo://+Entry)
%
% print_known_bugs/3 for a tree entry (category, name and exact version
% taken from the cache).

warning:print_entry_known_bugs(Repo://Entry) :-
  ( cache:ordered_entry(Repo, Entry, C, N, Ver) ->
      warning:print_known_bugs(C, N, Ver)
  ; true
  ).


%! warning:print_known_bugs(+C, +N, +Ver)
%
% Lists up to three open Bugzilla bugs naming package C/N from the local
% bug store (`Source/Domain/Gentoo/bugs.pl`), bugs naming exactly Ver
% first, each with its URL. Gated by config:bugzilla_annotate/1 and the
% presence of a synced store; silent otherwise. Purely informational: it
% does not change the assumption, its polarity or the exit code.

warning:print_known_bugs(C, N, Ver) :-
  ( config:bugzilla_annotate(true),
    catch(bugs:cache_available, _, fail),
    catch(bugs:open_package_bugs(C, N, Ids), _, fail),
    Ids \== [] ->
      warning:rank_known_bugs(Ids, C, N, Ver, Ranked),
      warning:known_bugs_prefix(3, Ranked, Shown),
      length(Ids, Total),
      message:color(darkgray),
      ( Total =:= 1 ->
          format('  Known open bug:~n', [])
      ; format('  Known open bugs (~w, showing ~w):~n', [Total, 3])
      ),
      forall(member(Id, Shown),
             ( bugs:bug(Id, _, _, _, Summary),
               bugs:bug_url(Id, Url),
               format('    #~w  ~w~n', [Id, Summary]),
               format('           ~w~n', [Url]) )),
      message:color(normal)
  ; true
  ).


%! warning:rank_known_bugs(+Ids, +C, +N, +Ver, -Ranked)
%
% Bugs whose atom index names C/N at exactly Ver come first (each group
% keeps its newest-first order).

warning:rank_known_bugs(Ids, _, _, version_none, Ids) :- !.
warning:rank_known_bugs(Ids, C, N, Ver, Ranked) :-
  ( catch(bugs:atom_version_bugs(C, N, Ver, Exact0), _, fail) -> Exact = Exact0 ; Exact = [] ),
  findall(Id, ( member(Id, Ids), memberchk(Id, Exact) ), First),
  findall(Id, ( member(Id, Ids), \+ memberchk(Id, Exact) ), Rest),
  append(First, Rest, Ranked).


%! warning:known_bugs_prefix(+N, +List, -Prefix)
%
% First N elements of List (all of it when shorter).

warning:known_bugs_prefix(N, List, Prefix) :-
  length(List, Len),
  ( Len =< N -> Prefix = List
  ; length(Prefix, N), append(Prefix, _, List)
  ).

%! warning:assumption_reason_label(+CtxLike, -Label)
%
% Extracts the assumption reason from a context-like term and maps it
% to a human-readable label via assumption_reason_label_/2.

warning:assumption_reason_label(CtxLike, Label) :-
  warning:unwrap_ctx(CtxLike, Ctx),
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