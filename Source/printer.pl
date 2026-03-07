/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> PRINTER
Hub module that dispatches plan rendering to Printer/ submodules.

Architecture:

  Source/Printer/
    Plan/
      assumption.pl   module assumption  — assumption classification
      warning.pl      module warning     — warnings, suggestions, bugreports
      cycle.pl        module cycle       — cycle explanation + DFS/BFS
    plan.pl           module plan        — build plan rendering
    info.pl           module info        — ebuild metadata + index display
    stats.pl          module stats       — test statistics tables
    state.pl          module state       — prover state debugger display

This hub retains:
- print/5,6          — main entry point, delegates to plan + warning
- print_timing_header/footer — timing output for writer.pl
- resolve_print_target — target(...) resolution for CLI proving
- blocker_note_map   — inline blocker annotation lookup
- action_phase, dry_run, unify — small helpers
- test/1,2, test_latest/1,2 — whole-repo test entry points

File-writing predicates live in Source/writer.pl.
The prove+plan+schedule pipeline lives in Source/pipeline.pl.
*/

:- module(printer, []).

% =============================================================================
%  PRINTER declarations
% =============================================================================


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
    ( printer:resolve_print_target(Target, ProofAVL, TargetPrint, TargetHeader),
      plan:print_header(TargetHeader),
      plan:collect_plan_pre_actions(ProofAVL, PreActions),
      plan:print_plan_pre_actions(PreActions, 0, PreSteps),
      plan:print_body(TargetPrint,Plan,Call,PreSteps,Steps),
      plan:print_footer(Plan,ModelAVL,Steps,PreActions),
      plan:print_scc_decomposition,
      warning:print_warnings(ModelAVL,ProofAVL,TriggersAVL),
      warning:print_use_changes(ProofAVL)
    ),
    nb_delete(printer_blocker_notes)).


% -----------------------------------------------------------------------------
%  Printing helpers: resolve target(...) to chosen candidate
% -----------------------------------------------------------------------------
%
% Since the CLI now defers candidate selection to the prover, the "root target"
% passed into printer:print/6 can be of the form:
%   target(Q, Arg):run?{Ctx}
%
% For UX parity we:
% - display the chosen candidate's :run in the "Emerging" header
% - treat that candidate's :run literal as the root target for highlighting
%   (bold green bubble) within the plan.
%

printer:resolve_print_target(Target0, ProofAVL, TargetPrint, TargetHeader) :-
  ( is_list(Target0) ->
      findall(P-H,
              ( member(T, Target0),
                printer:resolve_print_target_one(T, ProofAVL, P, H)
              ),
              Pairs),
      findall(P, member(P-_, Pairs), TargetPrint),
      findall(H, member(_-H, Pairs), TargetHeader)
  ; printer:resolve_print_target_one(Target0, ProofAVL, TargetPrint, TargetHeader)
  ),
  !.

printer:resolve_print_target_one(Full0, ProofAVL, Full, HeaderFull) :-
  % Only rewrite the new target(...) wrapper. Keep other root goals unchanged.
  ( Full0 = target(Q, Arg):Action?{_Ctx0} ->
      ( printer:proof_rule_body_(ProofAVL, target(Q, Arg):Action, Body),
        printer:chosen_candidate_from_body(Action, Body, Repo, Ebuild) ->
          % Display as the chosen candidate's action (typically :run).
          % Use Repo://(Ebuild:Action) shape to avoid printing parentheses like:
          %   (portage://foo):run
          HeaderFull = Repo://(Ebuild:Action?{[]}),
          % Treat the chosen candidate's action as the plan "target" for
          % green/bold highlighting.
          Full = Repo://(Ebuild:Action?{[]})
      ; HeaderFull = Full0,
        Full = Full0
      )
  ; HeaderFull = Full0,
    Full = Full0
  ),
  !.

printer:proof_rule_body_(ProofAVL, HeadCore, Body) :-
  % Proof stores rules under keys rule(HeadCore).
  get_assoc(rule(HeadCore), ProofAVL, dep(_Count, Body)?_Ctx),
  is_list(Body),
  !.

% Extract the chosen concrete candidate from the body of the target(...) rule.
%
% For :run we have the direct action literal in the body.
printer:chosen_candidate_from_body(run, Body, Repo, Ebuild) :-
  member(Repo://Ebuild:run?{_}, Body),
  !.
printer:chosen_candidate_from_body(fetchonly, Body, Repo, Ebuild) :-
  member(Repo://Ebuild:fetchonly?{_}, Body),
  !.
printer:chosen_candidate_from_body(uninstall, Body, Repo, Ebuild) :-
  member(Repo://Ebuild:uninstall?{_}, Body),
  !.

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


%! printer:print_timing_header(+Label, +T0) is det
%
% Print a "% <Label> started: <epoch> (<human>)" line to current output.

printer:print_timing_header(Label, T0) :-
  Epoch is truncate(T0),
  format_time(string(Human), "%Y-%m-%d %H:%M:%S", T0),
  format("% ~w started: ~w (~w)~n", [Label, Epoch, Human]).


%! printer:print_timing_footer(+Label, +T0) is det
%
% Print ended + wall_time_ms lines matching the emerge format.

printer:print_timing_footer(Label, T0) :-
  get_time(T1),
  Epoch1 is truncate(T1),
  WallMs is truncate((T1 - T0) * 1000),
  format_time(string(Human1), "%Y-%m-%d %H:%M:%S", T1),
  format("% ~w ended: ~w (~w)~n", [Label, Epoch1, Human1]),
  format("% ~w wall_time_ms: ~w~n", [Label, WallMs]).





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
  sampler:test_stats_reset('Printing', ExpectedTotal),
  aggregate_all(count, (Repository:package(_C,_N)), ExpectedPkgs),
  sampler:test_stats_set_expected_unique_packages(ExpectedPkgs),
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
              ( sampler:test_stats_record_entry(Repository://Entry, ModelAVL, ProofAVL, Triggers, false),
                sampler:test_stats_set_current_entry(Repository://Entry),
              printer:print([Repository://Entry:Action?{[]}],ModelAVL,ProofAVL,Plan,Triggers),
                sampler:test_stats_clear_current_entry
              ),
              false),
  stats:test_stats_print.


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
  sampler:test_stats_reset('Printing latest', ExpectedTotal),
  aggregate_all(count, (Repository:package(_C,_N)), ExpectedPkgs),
  sampler:test_stats_set_expected_unique_packages(ExpectedPkgs),
  tester:test(Style,
              'Printing latest',
              Repository://Entry,
              (Repository:package(C,N),once(Repository:ebuild(Entry,C,N,_))),
              ( % --- REFACTORED LOGIC ---
                prover:prove(Repository://Entry:Action?{[]},t,ProofAVL,t,ModelAVL,t,_Constraint,t,Triggers),
                planner:plan(ProofAVL,Triggers,t,Plan0,Remainder0),
                scheduler:schedule(ProofAVL,Triggers,Plan0,Remainder0,Plan,_Remainder)
              ),
              ( sampler:test_stats_record_entry(Repository://Entry, ModelAVL, ProofAVL, Triggers, false),
                sampler:test_stats_set_current_entry(Repository://Entry),
                printer:print([Repository://Entry:Action?{[]}],ModelAVL,ProofAVL,Plan,Triggers),
                sampler:test_stats_clear_current_entry
              ),
              false),
  stats:test_stats_print.


% Depclean output (print_removals, print_linkage_risks, etc.) moved to
% Source/Printer/Plan/plan.pl (module plan).
