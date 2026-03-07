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

This hub retains:
- print/5,6          — main entry point, delegates to plan + warning
- display_state/4    — interactive prover debugger display
- wait_for_input/0   — TTY pause helper
- print_timing_header/footer — timing output for writer.pl
- resolve_print_target — target(...) resolution for CLI proving
- blocker_note_map   — inline blocker annotation lookup
- action_phase, dry_run, unify — small helpers
- test/1,2, test_latest/1,2 — whole-repo test entry points
- Depclean output    — removal lists, uninstall order, linkage risks

File-writing predicates live in Source/writer.pl.
The prove+plan+schedule pipeline lives in Source/pipeline.pl.
*/

:- module(printer, []).


% -----------------------------------------------------------------------------
%  PROVER state printing
% -----------------------------------------------------------------------------

%! printer:display_state(+Target, +Proof, +Model, +Constraints)
%
% Interactive debugger display: prints the current prover state including
% the literal being proved, the proof stack, the to-do queue, the completed
% model, and the active constraints.

printer:display_state([],_,_,_) :- !.
printer:display_state(Target, Proof, Model, Constraints) :-

    % prepare aguments

    ( Target = [ Current | Queue ]
      -> true
      ;  Current = Target, Queue = [] ),

    prover:proof_to_list(Proof,ProofList),
    prover:model_to_list(Model,ModelList),
    constraint:constraints_to_list(Constraints,ConstraintList),

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


%! printer:wait_for_input
%
% Block until the user presses Enter. No-op when stdin is not a TTY
% (e.g. here-doc piping, CI).

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


% -----------------------------------------------------------------------------
%  Depclean output
% -----------------------------------------------------------------------------


%! printer:print_removals(+RequiredInstalled)
%
% Compute the set of removable packages (installed minus required) and
% print the removal list, uninstall order, and linkage risk report.

printer:print_removals(RequiredInstalled) :-
  findall(pkg://E,
          query:search([installed(true)], pkg://E),
          Installed0),
  sort(Installed0, Installed),
  subtract(Installed, RequiredInstalled, Removable),
  nl,
  message:header('Depclean (proposed removals)'),
  nl,
  ( Removable == [] ->
      writeln('  (none)')
  ; forall(member(pkg://E, Removable),
           ( query:search([category(C),name(N),version(V)], pkg://E),
             format('  ~w/~w-~w~n', [C, N, V])
           ))
  ),
  depclean:print_uninstall_order(Removable),
  printer:print_linkage_risks(Installed, Removable),
  nl.


%! printer:print_uninstall_order(+Removable)
%
% Compute and print a topologically sorted uninstall order for the
% removable packages. Warns when cycles are detected.

printer:print_uninstall_order([]) :- !.
printer:print_uninstall_order(Removable) :-
  depclean:uninstall_order(Removable, Order, Cyclic),
  nl,
  message:header('Depclean (uninstall order)'),
  nl,
  ( Cyclic == true ->
      message:warning('cycle detected in uninstall graph; order is best-effort')
  ; true
  ),
  printer:print_pkg_list_numbered(1, Order),
  nl.


%! printer:print_pkg_list_numbered(+Index, +Packages)
%
% Print a numbered list of pkg://Entry terms with category/name-version.

printer:print_pkg_list_numbered(_, []) :- !.
printer:print_pkg_list_numbered(I, [pkg://E|Es]) :-
  ( query:search([category(C),name(N),version(V)], pkg://E) ->
      format('  ~d. ~w/~w-~w~n', [I, C, N, V])
  ; format('  ~d. ~w~n', [I, pkg://E])
  ),
  I2 is I + 1,
  printer:print_pkg_list_numbered(I2, Es).


%! printer:print_linkage_risks(+Installed, +Removable)
%
% Best-effort approximation of Portage preserved-libs behavior. Uses VDB
% metadata (NEEDED.ELF.2 / PROVIDES.ELF.2) to identify kept packages
% whose ELF dependencies would lose all providers if the removable set
% is unmerged.

printer:print_linkage_risks(_Installed, Removable) :-
  Removable == [],
  !.
printer:print_linkage_risks(Installed, Removable) :-
  sort(Removable, RemovableSorted),
  list_to_ord_set(RemovableSorted, RemovableSet),
  subtract(Installed, RemovableSorted, Kept),
  list_to_ord_set(Kept, KeptSet),
  depclean:build_provides_map(Installed, ProvidesMap),
  depclean:collect_broken_needed(Kept, KeptSet, RemovableSet, ProvidesMap, BrokenPairs),
  nl,
  message:header('Depclean (linkage risks, VDB ELF metadata)'),
  nl,
  ( BrokenPairs == [] ->
      writeln('  (none detected)')
  ; forall(member(broken(Consumer, NeededTok, RemovedProviders), BrokenPairs),
           printer:print_broken_needed(Consumer, NeededTok, RemovedProviders))
  ),
  nl.


%! printer:print_broken_needed(+Consumer, +Token, +RemovedProviders)
%
% Print a single broken-linkage warning: the consumer package, the ELF
% token it needs, and the removable packages that were its only providers.

printer:print_broken_needed(pkg://E, Tok, RemovedProviders) :-
  ( query:search([category(C),name(N),version(V)], pkg://E) ->
      format('  ~w/~w-~w needs ~w~n', [C, N, V, Tok])
  ; format('  ~w needs ~w~n', [pkg://E, Tok])
  ),
  forall(member(pkg://P, RemovedProviders),
         ( ( query:search([category(CP),name(NP),version(VP)], pkg://P) ->
               format('    - would lose provider: ~w/~w-~w~n', [CP, NP, VP])
           ; format('    - would lose provider: ~w~n', [pkg://P])
           )
         )).
