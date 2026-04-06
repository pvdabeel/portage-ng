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
      timing.pl       module timing      — emerge-compatible timing output
    plan.pl           module plan        — build plan rendering + entry points
    index.pl          module index       — HTML index page rendering
    info.pl           module info        — ebuild metadata display
    stats.pl          module stats       — test statistics tables
    state.pl          module state       — prover state debugger display

This hub retains:
- print/5,6          — thin wrappers delegating to plan:print/5,6
- test/1,2, test_latest/1,2 — whole-repo test entry points

File-writing predicates live in Source/writer.pl.
The prove+plan+schedule pipeline lives in Source/pipeline.pl.
*/

:- module(printer, []).

% =============================================================================
%  PRINTER declarations
% =============================================================================


%! printer:print(+Target, +ModelAVL, +ProofAVL, +Plan, +TriggersAVL)
%
% Thin wrapper — delegates to plan:print/5.

printer:print(Target, ModelAVL, ProofAVL, Plan, TriggersAVL) :-
  plan:print(Target, ModelAVL, ProofAVL, Plan, TriggersAVL).

%! printer:print(+Target, +ModelAVL, +ProofAVL, +Plan, +Call, +TriggersAVL)

printer:print(Target, ModelAVL, ProofAVL, Plan, Call, TriggersAVL) :-
  plan:print(Target, ModelAVL, ProofAVL, Plan, Call, TriggersAVL).


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
  sampler:reset('Printing', ExpectedTotal),
  aggregate_all(count, (Repository:package(_C,_N)), ExpectedPkgs),
  sampler:set_expected_pkgs(ExpectedPkgs),
  tester:test(Style,
              'Printing',
              Repository://Entry,
              (Repository:entry(Entry)),
              ( prover:prove(Repository://Entry:Action?{[]},t,ProofAVL,t,ModelAVL,t,_Constraint,t,Triggers),
                planner:plan(ProofAVL,Triggers,t,Plan0,Remainder0),
                scheduler:schedule(ProofAVL,Triggers,Plan0,Remainder0,Plan,_Remainder)
              ),
              ( sampler:record(entry(Repository://Entry, ModelAVL, ProofAVL, Triggers, false)),
                sampler:set_current_entry(Repository://Entry),
              printer:print([Repository://Entry:Action?{[]}],ModelAVL,ProofAVL,Plan,Triggers),
                sampler:clear_current_entry
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
  sampler:reset('Printing latest', ExpectedTotal),
  aggregate_all(count, (Repository:package(_C,_N)), ExpectedPkgs),
  sampler:set_expected_pkgs(ExpectedPkgs),
  tester:test(Style,
              'Printing latest',
              Repository://Entry,
              (Repository:package(C,N),once(Repository:ebuild(Entry,C,N,_))),
              ( prover:prove(Repository://Entry:Action?{[]},t,ProofAVL,t,ModelAVL,t,_Constraint,t,Triggers),
                planner:plan(ProofAVL,Triggers,t,Plan0,Remainder0),
                scheduler:schedule(ProofAVL,Triggers,Plan0,Remainder0,Plan,_Remainder)
              ),
              ( sampler:record(entry(Repository://Entry, ModelAVL, ProofAVL, Triggers, false)),
                sampler:set_current_entry(Repository://Entry),
                printer:print([Repository://Entry:Action?{[]}],ModelAVL,ProofAVL,Plan,Triggers),
                sampler:clear_current_entry
              ),
              false),
  stats:test_stats_print.