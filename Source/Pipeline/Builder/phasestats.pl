/*
 Author: Pieter Van den Abeele
 E-mail: pvdabeel@mac.com
 Copyright (c) 2005-2026, Pieter Van den Abeele

 Distributed under the terms of the LICENSE file in the root directory of this
 project.
*/

/** <module> PHASESTATS
Persisted per-phase build statistics (Knowledge/phase_stats.pl).

Owns the phase_bytes/3 and phase_seconds/3 store: the builder side
(ebuild_exec) records and saves it during builds, and readers such as
the Gantt grapher load it for duration estimates. Kept apart from
ebuild_exec on purpose: the graph capability loads the grapher
without the builder capability, and the Gantt page must still see
recorded durations there (the standalone `--graph` run reaches this
module without ebuild_exec ever being loaded).
*/

:- module(phasestats, []).

% =============================================================================
%  PHASESTATS declarations
% =============================================================================

:- dynamic phasestats:phase_bytes/3.
:- dynamic phasestats:phase_seconds/3.
:- dynamic phasestats:phase_stats_loaded/0.

:- mutex_create(phase_stats_io).


% -----------------------------------------------------------------------------
%  Phase log stats (persisted across builds for progress estimates)
% -----------------------------------------------------------------------------

%! phasestats:phase_stats_file(-Path) is det.
%
% On-disk location of the persisted phase statistics.

phasestats:phase_stats_file(Path) :-
  working_directory(Cwd, Cwd),
  os:compose_path(Cwd, 'Knowledge/phase_stats.pl', Path).


%! phasestats:load_phase_stats is det.
%
% Load Knowledge/phase_stats.pl once per process. The loaded flag is
% asserted only after the file has been read, and the read holds
% `phase_stats_io`, so a concurrent caller waits for that read or
% observes a complete table. `--graph full` runs one worker per CPU;
% publishing the flag first let those workers index an empty table.

phasestats:load_phase_stats :-
  phasestats:phase_stats_loaded, !.
phasestats:load_phase_stats :-
  with_mutex(phase_stats_io,
    ( phasestats:phase_stats_loaded -> true
    ;  phasestats:load_phase_stats_file,
       assertz(phasestats:phase_stats_loaded)
    )).


%! phasestats:load_phase_stats_file is det.
%
% Read the on-disk phase stats into the dynamic store. A missing file
% is a completed empty load. A failed read drops the facts it already
% asserted so the next attempt does not duplicate them.

phasestats:load_phase_stats_file :-
  phasestats:phase_stats_file(Path),
  ( exists_file(Path)
  -> catch(phasestats:read_phase_stats_file(Path),
           E,
           ( retractall(phasestats:phase_bytes(_, _, _)),
             retractall(phasestats:phase_seconds(_, _, _)),
             throw(E)))
  ;  true
  ).


%! phasestats:read_phase_stats_file(+Path) is det.
%
% Open Path and assert every phase_bytes/3 and phase_seconds/3 term.

phasestats:read_phase_stats_file(Path) :-
  setup_call_cleanup(
    open(Path, read, S),
    phasestats:read_phase_stats(S),
    close(S)).


%! phasestats:read_phase_stats(+Stream) is det.
%
% Read phase_bytes/3 and phase_seconds/3 terms from Stream to EOF.

phasestats:read_phase_stats(S) :-
  read_term(S, Term, []),
  ( Term == end_of_file -> true
  ;  ( Term = phase_bytes(Entry, Phase, Bytes)
     -> assertz(phasestats:phase_bytes(Entry, Phase, Bytes))
     ;  Term = phase_seconds(Entry, Phase, Secs)
     -> assertz(phasestats:phase_seconds(Entry, Phase, Secs))
     ;  true
     ),
     phasestats:read_phase_stats(S)
  ).


%! phasestats:save_phase_stats is det.
%
% Writes all phase_bytes/3 and phase_seconds/3 facts to disk.

phasestats:save_phase_stats :-
  with_mutex(phase_stats_io,
    ( phasestats:phase_stats_file(Path),
      setup_call_cleanup(
        open(Path, write, S),
        ( forall(
            phasestats:phase_bytes(Entry, Phase, Bytes),
            format(S, 'phase_bytes(~q, ~q, ~d).~n', [Entry, Phase, Bytes])
          ),
          forall(
            phasestats:phase_seconds(Entry, Phase, Secs),
            format(S, 'phase_seconds(~q, ~q, ~f).~n', [Entry, Phase, Secs])
          )
        ),
        close(S))
    )).


%! phasestats:record_phase_stats(+Entry, +Phase, +Bytes, +Seconds) is det.
%
% Record (or update) both log byte count and wall-clock seconds
% for a completed phase.

phasestats:record_phase_stats(Entry, Phase, Bytes, Seconds) :-
  retractall(phasestats:phase_bytes(Entry, Phase, _)),
  retractall(phasestats:phase_seconds(Entry, Phase, _)),
  assertz(phasestats:phase_bytes(Entry, Phase, Bytes)),
  assertz(phasestats:phase_seconds(Entry, Phase, Seconds)).


%! phasestats:expected_phase_stats(+Entry, +Phase, -ExpBytes, -ExpSeconds) is semidet.
%
% Look up historical byte count and wall-clock seconds for a phase.
% Succeeds only when at least one signal (bytes or seconds) is available.

phasestats:expected_phase_stats(Entry, Phase, ExpBytes, ExpSeconds) :-
  ( phasestats:phase_bytes(Entry, Phase, ExpBytes) -> true ; ExpBytes = 0 ),
  ( phasestats:phase_seconds(Entry, Phase, ExpSeconds) -> true ; ExpSeconds = 0.0 ),
  ( ExpBytes > 0 ; ExpSeconds > 0.0 ),
  !.
