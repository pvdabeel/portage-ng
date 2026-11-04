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
:- dynamic phasestats:cn_entry/3.
:- dynamic phasestats:cn_index_ready/0.
:- dynamic phasestats:forecast_cache/4.

:- mutex_create(phase_stats_io).


% -----------------------------------------------------------------------------
%  Phase log stats (persisted across builds for progress estimates)
% -----------------------------------------------------------------------------

%! phasestats:phase_stats_file(-Path) is det.
%
% On-disk location of the persisted phase statistics.

phasestats:phase_stats_file(Path) :-
  config:state_dir(Dir),
  os:compose_path(Dir, 'Knowledge/phase_stats.pl', Path).


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
  retractall(phasestats:cn_entry(_, _, _)),
  retractall(phasestats:cn_index_ready),
  retractall(phasestats:forecast_cache(_, _, _, _)),
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
  retractall(phasestats:forecast_cache(Entry, Phase, _, _)),
  assertz(phasestats:phase_bytes(Entry, Phase, Bytes)),
  assertz(phasestats:phase_seconds(Entry, Phase, Seconds)),
  phasestats:note_cn(Entry).


%! phasestats:expected_phase_stats(+Entry, +Phase, -ExpBytes, -ExpSeconds) is semidet.
%
% Historical byte count and wall-clock seconds for a phase. An exact
% Entry hit wins. Otherwise both signals are the mean of other versions
% of the same category/name. Succeeds when at least one signal is positive.

phasestats:expected_phase_stats(Entry, Phase, ExpBytes, ExpSeconds) :-
  phasestats:forecast(Entry, Phase, ExpBytes, ExpSeconds),
  ( ExpBytes > 0 ; ExpSeconds > 0.0 ),
  !.


%! phasestats:expected_seconds(+Entry, +Phase, -Seconds) is semidet.
%
% Positive forecast seconds for Entry and Phase. Same lookup as
% expected_phase_stats/4, ignoring the byte signal.

phasestats:expected_seconds(Entry, Phase, Seconds) :-
  phasestats:forecast(Entry, Phase, _, Seconds),
  Seconds > 0,
  !.


% -----------------------------------------------------------------------------
%  Forecast lookup
% -----------------------------------------------------------------------------

%! phasestats:forecast(+Entry, +Phase, -Bytes, -Seconds) is det.
%
% Cached forecast. Bytes and Seconds are 0 when neither this Entry nor
% another version of the same package has a positive measurement.

phasestats:forecast(Entry, Phase, Bytes, Seconds) :-
  phasestats:forecast_cache(Entry, Phase, Bytes, Seconds), !.
phasestats:forecast(Entry, Phase, Bytes, Seconds) :-
  with_mutex(phase_stats_io,
    phasestats:forecast_locked(Entry, Phase, Bytes, Seconds)).


%! phasestats:forecast_locked(+Entry, +Phase, -Bytes, -Seconds) is det.
%
% forecast/4 body. Caller holds phase_stats_io.

phasestats:forecast_locked(Entry, Phase, Bytes, Seconds) :-
  phasestats:forecast_cache(Entry, Phase, Bytes, Seconds), !.
phasestats:forecast_locked(Entry, Phase, Bytes, Seconds) :-
  phasestats:compute_forecast(Entry, Phase, Bytes, Seconds),
  assertz(phasestats:forecast_cache(Entry, Phase, Bytes, Seconds)).


%! phasestats:compute_forecast(+Entry, +Phase, -Bytes, -Seconds) is det.
%
% Exact positive signals win. A missing signal is filled from the
% same-category/name mean when that mean exists.

phasestats:compute_forecast(Entry, Phase, Bytes, Seconds) :-
  phasestats:exact_signal(bytes, Entry, Phase, Bytes0),
  phasestats:exact_signal(seconds, Entry, Phase, Seconds0),
  ( Bytes0 > 0, Seconds0 > 0
  -> Bytes = Bytes0, Seconds = Seconds0
  ;  phasestats:cn_forecast(Entry, Phase, CNBytes, CNSeconds)
  -> ( Bytes0 > 0 -> Bytes = Bytes0 ; Bytes = CNBytes ),
     ( Seconds0 > 0 -> Seconds = Seconds0 ; Seconds = CNSeconds )
  ;  Bytes = Bytes0, Seconds = Seconds0
  ).


%! phasestats:exact_signal(+Kind, +Entry, +Phase, -Value) is det.
%
% Positive recorded bytes or seconds, or 0 when this Entry has none.

phasestats:exact_signal(bytes, Entry, Phase, Bytes) :-
  !,
  ( phasestats:phase_bytes(Entry, Phase, B), B > 0 -> Bytes = B ; Bytes = 0 ).
phasestats:exact_signal(seconds, Entry, Phase, Seconds) :-
  ( phasestats:phase_seconds(Entry, Phase, S), S > 0 -> Seconds = S ; Seconds = 0.0 ).


%! phasestats:cn_forecast(+Entry, +Phase, -Bytes, -Seconds) is semidet.
%
% Mean positive bytes and seconds of Phase across other versions of
% Entry's category/name. Fails when Entry does not parse or no sibling
% has a positive signal.

phasestats:cn_forecast(Entry, Phase, Bytes, Seconds) :-
  phasestats:ensure_cn_index_locked,
  phasestats:entry_cn(Entry, Cat, Name),
  findall(S,
          ( phasestats:cn_entry(Cat, Name, Other),
            Other \== Entry,
            phasestats:phase_seconds(Other, Phase, S),
            S > 0
          ),
          Ss),
  findall(B,
          ( phasestats:cn_entry(Cat, Name, Other),
            Other \== Entry,
            phasestats:phase_bytes(Other, Phase, B),
            B > 0
          ),
          Bs),
  ( phasestats:average(Ss, Seconds) -> true ; Seconds = 0.0 ),
  ( phasestats:average(Bs, Bytes0) -> Bytes is round(Bytes0) ; Bytes = 0 ),
  ( Seconds > 0 ; Bytes > 0 ),
  !.


%! phasestats:average(+List, -Average) is semidet.
%
% Arithmetic mean of a non-empty list of numbers.

phasestats:average(List, Average) :-
  List \== [],
  sum_list(List, Sum),
  length(List, N),
  Average is Sum / N.


%! phasestats:entry_cn(+Entry, -Cat, -Name) is semidet.
%
% Split `cat/name-ver` into category and package name.

phasestats:entry_cn(Entry, Cat, Name) :-
  atomic_list_concat([Cat, PV], '/', Entry),
  eapi:packageversion(PV, Name, _).


%! phasestats:ensure_cn_index_locked is det.
%
% Build the category/name index if it is missing. Caller holds
% phase_stats_io. Does not read the stats file; the caller loads first.

phasestats:ensure_cn_index_locked :-
  ( phasestats:cn_index_ready -> true ; phasestats:build_cn_index ).


%! phasestats:build_cn_index is det.
%
% Replace the category/name index from the phase stats already in memory.
% Caller holds phase_stats_io.

phasestats:build_cn_index :-
  retractall(phasestats:cn_entry(_, _, _)),
  findall(E,
          ( phasestats:phase_seconds(E, _, _)
          ; phasestats:phase_bytes(E, _, _)
          ),
          Es0),
  sort(Es0, Es),
  forall(member(E, Es),
         ( phasestats:entry_cn(E, C, N)
         -> assertz(phasestats:cn_entry(C, N, E))
         ;  true
         )),
  assertz(phasestats:cn_index_ready).


%! phasestats:note_cn(+Entry) is det.
%
% Add Entry to a ready category/name index. A missing index is left
% for the next forecast to build from the whole table.

phasestats:note_cn(_Entry) :-
  \+ phasestats:cn_index_ready, !.
phasestats:note_cn(Entry) :-
  phasestats:entry_cn(Entry, Cat, Name),
  \+ phasestats:cn_entry(Cat, Name, Entry),
  !,
  assertz(phasestats:cn_entry(Cat, Name, Entry)).
phasestats:note_cn(_Entry).
