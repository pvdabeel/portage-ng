/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> EBUILD_EXEC
Interface to Portage's `ebuild` CLI for executing build phases.

Shells out to the `ebuild` command to run individual phases (setup,
unpack, compile, install, merge, etc.) on a per-package basis. The
builder resolves dependencies and controls ordering; this module handles
the per-package phase execution via Portage's infrastructure.

The `ebuild` command is part of sys-apps/portage and invokes ebuild.sh
with the full Portage helper stack (sandbox, econf, emake, doins, etc.).
This avoids reimplementing ~7,400 lines of bash + ~6,700 lines of Python
merge/VDB code.
*/

:- module(ebuild_exec, []).

:- dynamic ebuild_exec:phase_bytes/3.
:- dynamic ebuild_exec:phase_seconds/3.
:- dynamic ebuild_exec:phase_stats_loaded/0.


% =============================================================================
%  Action-to-phase mapping
% =============================================================================

%! ebuild_exec:action_phases(+Action, +Ctx, -Phases) is semidet.
%
% Maps a portage-ng plan action to the sequence of ebuild CLI phases.
% The `ebuild` command accepts multiple phase arguments and runs them
% in order. `merge` is a composite phase (preinst + qmerge + postinst).
%
% For update/downgrade, the old package must be unmerged first; the
% caller handles that via ebuild_exec:unmerge_old/2.

ebuild_exec:action_phases(install,   _Ctx, [clean, setup, unpack, prepare, configure, compile, install, merge]).
ebuild_exec:action_phases(run,       _Ctx, [clean, setup, unpack, prepare, configure, compile, install, merge]).
ebuild_exec:action_phases(reinstall, _Ctx, [clean, setup, unpack, prepare, configure, compile, install, merge]).
ebuild_exec:action_phases(update,    _Ctx, [clean, setup, unpack, prepare, configure, compile, install, merge]).
ebuild_exec:action_phases(downgrade, _Ctx, [clean, setup, unpack, prepare, configure, compile, install, merge]).
ebuild_exec:action_phases(uninstall, _Ctx, [unmerge]).


% =============================================================================
%  Ebuild path resolution
% =============================================================================

%! ebuild_exec:ebuild_path(+Repo, +Entry, -EbuildPath) is semidet.
%
% Resolves a Repo://Entry to the on-disk .ebuild file path by querying
% the repository's location and entry metadata.

ebuild_exec:ebuild_path(Repo, Entry, EbuildPath) :-
  Repo:get_ebuild_file(Entry, EbuildPath).


% =============================================================================
%  DEFINED_PHASES querying
% =============================================================================

%! ebuild_exec:defined_phases(+Repo, +Entry, -Phases) is det.
%
% Retrieves the DEFINED_PHASES for an ebuild from the knowledge base.
% Returns a list of atoms (e.g. [compile, configure, install, setup]).
% Falls back to an empty list if metadata is unavailable.

ebuild_exec:defined_phases(Repo, Entry, Phases) :-
  ( query:search(defined_phases(P), Repo://Entry)
  -> ( is_list(P) -> Phases = P ; Phases = [P] )
  ;  Phases = []
  ).


%! ebuild_exec:display_phases(+Action, +Repo, +Entry, +Ctx, -DisplayPhases) is det.
%
% Computes the phases to show as sub-lines in the build display.
% Intersects the action's phase sequence with the ebuild's
% DEFINED_PHASES. Maps ebuild CLI phase names to DEFINED_PHASES
% names (e.g., unpack -> unpack, compile -> compile).

ebuild_exec:display_phases(Action, Repo, Entry, Ctx, DisplayPhases) :-
  ebuild_exec:action_phases(Action, Ctx, AllPhases),
  ebuild_exec:defined_phases(Repo, Entry, Defined),
  ( config:build_live_phases(Live), Live \= []
  -> include(ebuild_exec:phase_in_live_or_defined(Live, Defined), AllPhases, DisplayPhases)
  ;  include(ebuild_exec:phase_in_defined(Defined), AllPhases, DisplayPhases)
  ).

ebuild_exec:phase_in_defined(Defined, Phase) :-
  memberchk(Phase, Defined).

ebuild_exec:phase_in_live_or_defined(Live, Defined, Phase) :-
  ( memberchk(Phase, Live) -> true ; memberchk(Phase, Defined) ).


% =============================================================================
%  Build log path
% =============================================================================

%! ebuild_exec:build_log_path(+Entry, -LogPath) is det.
%
% Computes the log file path for a build action. Slashes in the
% entry name are replaced with `--` to produce a safe filename.

ebuild_exec:build_log_path(Entry, LogPath) :-
  config:build_log_dir(LogDir),
  format(atom(RawName), '~w', [Entry]),
  atomic_list_concat(Parts, '/', RawName),
  atomic_list_concat(Parts, '--', SafeName),
  atomic_list_concat([LogDir, '/', SafeName, '.log'], LogPath).


%! ebuild_exec:ensure_log_dir is det.

ebuild_exec:ensure_log_dir :-
  config:build_log_dir(LogDir),
  ( exists_directory(LogDir) -> true ; make_directory_path(LogDir) ).


% =============================================================================
%  Phase log stats (persisted across builds for progress estimates)
% =============================================================================

%! ebuild_exec:phase_stats_file(-Path) is det.

ebuild_exec:phase_stats_file(Path) :-
  working_directory(Cwd, Cwd),
  directory_file_path(Cwd, 'Knowledge/phase_stats.pl', Path).


%! ebuild_exec:load_phase_stats is det.
%
% Loads historical phase log byte counts from disk (once per session).

ebuild_exec:load_phase_stats :-
  ebuild_exec:phase_stats_loaded, !.

ebuild_exec:load_phase_stats :-
  with_mutex(phase_stats_io,
    ( ebuild_exec:phase_stats_loaded -> true
    ;  assertz(ebuild_exec:phase_stats_loaded),
       ebuild_exec:phase_stats_file(Path),
       ( exists_file(Path)
       -> setup_call_cleanup(
            open(Path, read, S),
            ebuild_exec:read_phase_stats(S),
            close(S))
       ;  true
       )
    )).

ebuild_exec:read_phase_stats(S) :-
  read_term(S, Term, []),
  ( Term == end_of_file -> true
  ;  ( Term = phase_bytes(Entry, Phase, Bytes)
     -> assertz(ebuild_exec:phase_bytes(Entry, Phase, Bytes))
     ;  Term = phase_seconds(Entry, Phase, Secs)
     -> assertz(ebuild_exec:phase_seconds(Entry, Phase, Secs))
     ;  true
     ),
     ebuild_exec:read_phase_stats(S)
  ).


%! ebuild_exec:save_phase_stats is det.
%
% Writes all phase_bytes/3 and phase_seconds/3 facts to disk.

ebuild_exec:save_phase_stats :-
  with_mutex(phase_stats_io,
    ( ebuild_exec:phase_stats_file(Path),
      setup_call_cleanup(
        open(Path, write, S),
        ( forall(
            ebuild_exec:phase_bytes(Entry, Phase, Bytes),
            format(S, 'phase_bytes(~q, ~q, ~d).~n', [Entry, Phase, Bytes])
          ),
          forall(
            ebuild_exec:phase_seconds(Entry, Phase, Secs),
            format(S, 'phase_seconds(~q, ~q, ~f).~n', [Entry, Phase, Secs])
          )
        ),
        close(S))
    )).


%! ebuild_exec:record_phase_stats(+Entry, +Phase, +Bytes, +Seconds) is det.
%
% Record (or update) both log byte count and wall-clock seconds
% for a completed phase.

ebuild_exec:record_phase_stats(Entry, Phase, Bytes, Seconds) :-
  retractall(ebuild_exec:phase_bytes(Entry, Phase, _)),
  retractall(ebuild_exec:phase_seconds(Entry, Phase, _)),
  assertz(ebuild_exec:phase_bytes(Entry, Phase, Bytes)),
  assertz(ebuild_exec:phase_seconds(Entry, Phase, Seconds)).


%! ebuild_exec:expected_phase_stats(+Entry, +Phase, -ExpBytes, -ExpSeconds) is semidet.
%
% Look up historical byte count and wall-clock seconds for a phase.
% Succeeds only when at least one signal (bytes or seconds) is available.

ebuild_exec:expected_phase_stats(Entry, Phase, ExpBytes, ExpSeconds) :-
  ( ebuild_exec:phase_bytes(Entry, Phase, ExpBytes) -> true ; ExpBytes = 0 ),
  ( ebuild_exec:phase_seconds(Entry, Phase, ExpSeconds) -> true ; ExpSeconds = 0.0 ),
  ( ExpBytes > 0 ; ExpSeconds > 0.0 ),
  !.


% =============================================================================
%  Log file helpers
% =============================================================================

%! ebuild_exec:log_file_size(+Path, -Size) is det.

ebuild_exec:log_file_size(Path, Size) :-
  ( exists_file(Path) -> size_file(Path, Size) ; Size = 0 ).


% =============================================================================
%  Async phase execution (for progress polling)
% =============================================================================

%! ebuild_exec:start_phase_async(+EbuildPath, +Phase, +LogPath, -Pid) is det.
%
% Starts a single phase without blocking, appending output to LogPath.

ebuild_exec:start_phase_async(EbuildPath, Phase, LogPath, Pid) :-
  config:ebuild_command(EbuildCmd),
  atom_string(Phase, PhaseStr),
  process_create(
    path(sh),
    ['-c', '"$1" --skip-manifest "$2" "$3" >>"$4" 2>&1', '_', EbuildCmd, EbuildPath, PhaseStr, LogPath],
    [process(Pid)]).


%! ebuild_exec:check_phase_done(+Pid, -ExitCode) is semidet.
%
% Non-blocking check. Succeeds with exit code if the process finished.

ebuild_exec:check_phase_done(Pid, ExitCode) :-
  catch(process_wait(Pid, exit(ExitCode), [timeout(0)]), _, fail).


%! ebuild_exec:poll_phase_progress(+Pid, +Phase, +LogPath, +SizeBefore, +T0, +ExpBytes, +ExpSeconds, :Callback, -ExitCode) is det.
%
% Polls a running phase process, computing progress from the max of
% two signals: log byte growth and elapsed wall-clock time.
% Calls Callback(Phase, progress(Pct)) on each tick until the process
% exits. Percentage is capped at 99 to avoid implying completion.

ebuild_exec:poll_phase_progress(Pid, Phase, LogPath, SizeBefore, T0, ExpBytes, ExpSeconds, Callback, ExitCode) :-
  ( ebuild_exec:check_phase_done(Pid, EC)
  -> ExitCode = EC
  ;  ebuild_exec:log_file_size(LogPath, CurrentSize),
     BytesSoFar is CurrentSize - SizeBefore,
     get_time(Now),
     Elapsed is Now - T0,
     ebuild_exec:dual_progress(BytesSoFar, ExpBytes, Elapsed, ExpSeconds, Pct),
     call(Callback, Phase, progress(Pct)),
     sleep(0.5),
     ebuild_exec:poll_phase_progress(Pid, Phase, LogPath, SizeBefore, T0, ExpBytes, ExpSeconds, Callback, ExitCode)
  ).


%! ebuild_exec:dual_progress(+BytesSoFar, +ExpBytes, +Elapsed, +ExpSeconds, -Pct) is det.
%
% Computes progress percentage from the max of bytes-based and
% time-based estimates. Each is capped at 99 individually before
% taking the max, so the display never implies completion.

ebuild_exec:dual_progress(BytesSoFar, ExpBytes, Elapsed, ExpSeconds, Pct) :-
  ( ExpBytes > 0
  -> BytesPct is min(99, max(0, (BytesSoFar * 100) // ExpBytes))
  ;  BytesPct = 0
  ),
  ( ExpSeconds > 0.0
  -> TimePct is min(99, max(0, round((Elapsed / ExpSeconds) * 100)))
  ;  TimePct = 0
  ),
  Pct is max(BytesPct, TimePct).


% =============================================================================
%  Phase execution
% =============================================================================

%! ebuild_exec:run_phase(+EbuildPath, +Phase, -ExitCode) is det.
%
% Invokes the `ebuild` CLI for a single phase. Output is suppressed
% (redirected to null) so it doesn't interfere with the display.

ebuild_exec:run_phase(EbuildPath, Phase, ExitCode) :-
  config:ebuild_command(EbuildCmd),
  atom_string(Phase, PhaseStr),
  process_create(
    path(EbuildCmd),
    ['--skip-manifest', EbuildPath, PhaseStr],
    [stdout(null), stderr(null), process(Pid)]),
  process_wait(Pid, exit(ExitCode)).


%! ebuild_exec:run_phase_logged(+EbuildPath, +Phase, +LogPath, -ExitCode) is det.
%
% Invokes the `ebuild` CLI for a single phase, appending all
% stdout/stderr output to LogPath via shell redirection.

ebuild_exec:run_phase_logged(EbuildPath, Phase, LogPath, ExitCode) :-
  config:ebuild_command(EbuildCmd),
  atom_string(Phase, PhaseStr),
  process_create(
    path(sh),
    ['-c', '"$1" --skip-manifest "$2" "$3" >>"$4" 2>&1', '_', EbuildCmd, EbuildPath, PhaseStr, LogPath],
    [process(Pid)]),
  process_wait(Pid, exit(ExitCode)).


%! ebuild_exec:log_phase_header(+LogPath, +Phase) is det.
%
% Writes a phase separator line to the log file before each phase runs.

ebuild_exec:log_phase_header(LogPath, Phase) :-
  catch(
    ( open(LogPath, append, S),
      format(S, '~n=== ~w ===~n', [Phase]),
      close(S)
    ), _, true).


%! ebuild_exec:run_phases(+EbuildPath, +Phases, -ExitCode) is det.
%
% Invokes the `ebuild` CLI with all phase arguments at once.
% Used for bulk execution without per-phase progress tracking.

ebuild_exec:run_phases(EbuildPath, Phases, ExitCode) :-
  config:ebuild_command(EbuildCmd),
  maplist(atom_string, Phases, PhaseStrs),
  process_create(
    path(EbuildCmd),
    ['--skip-manifest', EbuildPath | PhaseStrs],
    [stdout(null), stderr(null), process(Pid)]),
  process_wait(Pid, exit(ExitCode)).


% =============================================================================
%  Live/stub phase splitting
% =============================================================================

%! ebuild_exec:compute_live_prefix(+AllPhases, +LiveConfig, -LivePrefix, -StubTail) is det.
%
% Splits AllPhases into a leading "live prefix" (phases that appear in
% LiveConfig) and a "stub tail" (the rest). Stops at the first phase
% NOT in LiveConfig -- you can't skip a phase in the middle.

ebuild_exec:compute_live_prefix([], _, [], []).

ebuild_exec:compute_live_prefix([Phase|Rest], LiveConfig, LivePrefix, StubTail) :-
  ( memberchk(Phase, LiveConfig)
  -> LivePrefix = [Phase|MoreLive],
     ebuild_exec:compute_live_prefix(Rest, LiveConfig, MoreLive, StubTail)
  ;  LivePrefix = [],
     StubTail = [Phase|Rest]
  ).


% =============================================================================
%  Multi-phase execution (single ebuild invocation)
% =============================================================================

%! ebuild_exec:start_phases_async_multi(+EbuildPath, +Phases, +LogPath, -Pid) is det.
%
% Starts a single ebuild invocation with multiple phases, appending
% all output to LogPath. Returns the process Pid for polling.

ebuild_exec:start_phases_async_multi(EbuildPath, Phases, LogPath, Pid) :-
  config:ebuild_command(EbuildCmd),
  maplist(atom_string, Phases, PhaseStrs),
  atomic_list_concat(PhaseStrs, ' ', PhasesStr),
  format(atom(CmdStr), '"~w" --skip-manifest "~w" ~w >>"~w" 2>&1', [EbuildCmd, EbuildPath, PhasesStr, LogPath]),
  process_create(path(sh), ['-c', CmdStr], [process(Pid)]).


%! ebuild_exec:run_phases_logged_multi(+EbuildPath, +Phases, +LogPath, -ExitCode) is det.
%
% Blocking single-invocation with multiple phases, output to LogPath.

ebuild_exec:run_phases_logged_multi(EbuildPath, Phases, LogPath, ExitCode) :-
  ebuild_exec:start_phases_async_multi(EbuildPath, Phases, LogPath, Pid),
  process_wait(Pid, exit(ExitCode)).


%! ebuild_exec:aggregate_expected_stats(+Entry, +Phases, -TotalExpBytes, -TotalExpSecs) is det.
%
% Sums historical byte counts and seconds across multiple phases.

ebuild_exec:aggregate_expected_stats(Entry, Phases, TotalExpBytes, TotalExpSecs) :-
  aggregate_all(sum(B),
    (member(P, Phases), ebuild_exec:phase_bytes(Entry, P, B)),
    TotalExpBytes),
  aggregate_all(sum(S),
    (member(P, Phases), ebuild_exec:phase_seconds(Entry, P, S)),
    TotalExpSecs).


%! ebuild_exec:poll_live_progress(+Pid, +ProgressPhase, +LogPath, +SizeBefore, +T0, +ExpBytes, +ExpSecs, :Callback, -ExitCode) is det.
%
% Polls a running multi-phase process using aggregate byte/time stats
% for progress estimation. Shows progress on ProgressPhase.

ebuild_exec:poll_live_progress(Pid, ProgressPhase, LogPath, SizeBefore, T0, ExpBytes, ExpSecs, Callback, ExitCode) :-
  ( ebuild_exec:check_phase_done(Pid, EC)
  -> ExitCode = EC
  ;  ebuild_exec:log_file_size(LogPath, CurrentSize),
     BytesSoFar is CurrentSize - SizeBefore,
     get_time(Now),
     Elapsed is Now - T0,
     ebuild_exec:dual_progress(BytesSoFar, ExpBytes, Elapsed, ExpSecs, Pct),
     call(Callback, ProgressPhase, progress(Pct)),
     sleep(0.5),
     ebuild_exec:poll_live_progress(Pid, ProgressPhase, LogPath, SizeBefore, T0, ExpBytes, ExpSecs, Callback, ExitCode)
  ).


% =============================================================================
%  Phase execution with live config
% =============================================================================

%! ebuild_exec:run_phases_with_config(+EbuildPath, +Entry, +AllPhases, +DisplayPhases, +LogPath, :PhaseCallback, -Outcome) is det.
%
% Splits AllPhases into a live prefix (executed as a single ebuild
% invocation) and a stub tail (marked as stub in the display).
% Live display phases show as active during execution, then done/failed.
% Uses aggregate byte/time stats for progress when available.

:- meta_predicate ebuild_exec:run_phases_with_config(+, +, +, +, +, 2, -).

ebuild_exec:run_phases_with_config(EbuildPath, Entry, AllPhases, DisplayPhases, LogPath, Callback, Outcome) :-
  config:build_live_phases(LiveConfig),
  ebuild_exec:compute_live_prefix(AllPhases, LiveConfig, LivePrefix, StubTail),
  ( LivePrefix \= []
  -> ebuild_exec:run_live_prefix(EbuildPath, Entry, LivePrefix, DisplayPhases, LogPath, Callback, LiveOutcome)
  ;  LiveOutcome = done
  ),
  ( LiveOutcome == done
  -> forall(
       (member(P, StubTail), memberchk(P, DisplayPhases)),
       call(Callback, P, stub)
     ),
     Outcome = done
  ;  Outcome = LiveOutcome
  ).


%! ebuild_exec:run_live_prefix(+EbuildPath, +Entry, +LivePrefix, +DisplayPhases, +LogPath, :Callback, -Outcome) is det.
%
% Executes all phases in LivePrefix as a single ebuild invocation.
% Display phases are marked active, then done/failed on completion.

ebuild_exec:run_live_prefix(EbuildPath, Entry, LivePrefix, DisplayPhases, LogPath, Callback, Outcome) :-
  forall(
    (member(P, LivePrefix), memberchk(P, DisplayPhases)),
    call(Callback, P, active)
  ),
  ebuild_exec:log_file_size(LogPath, SizeBefore),
  get_time(T0),
  ebuild_exec:aggregate_expected_stats(Entry, LivePrefix, ExpBytes, ExpSecs),
  ( (ExpBytes > 0 ; ExpSecs > 0.0),
    member(ProgressPhase, LivePrefix),
    memberchk(ProgressPhase, DisplayPhases)
  -> ebuild_exec:start_phases_async_multi(EbuildPath, LivePrefix, LogPath, Pid),
     last(LivePrefix, LastLive),
     ( memberchk(LastLive, DisplayPhases) -> PPhase = LastLive ; PPhase = ProgressPhase ),
     ebuild_exec:poll_live_progress(Pid, PPhase, LogPath, SizeBefore, T0, ExpBytes, ExpSecs, Callback, ExitCode)
  ;  ebuild_exec:run_phases_logged_multi(EbuildPath, LivePrefix, LogPath, ExitCode)
  ),
  get_time(T1),
  TotalSecs is T1 - T0,
  ebuild_exec:log_file_size(LogPath, SizeAfter),
  TotalBytes is SizeAfter - SizeBefore,
  ebuild_exec:record_phase_stats(Entry, live_prefix, TotalBytes, TotalSecs),
  ( ExitCode =:= 0
  -> forall(
       (member(P, LivePrefix), memberchk(P, DisplayPhases)),
       call(Callback, P, done)
     ),
     Outcome = done
  ;  ebuild_exec:scan_log_entered_phases(LogPath, EnteredPhases),
     ebuild_exec:mark_phases_on_failure(LivePrefix, DisplayPhases, EnteredPhases, ExitCode, LogPath, Callback),
     Outcome = failed(ExitCode)
  ).


% -----------------------------------------------------------------------------
%  Failure diagnosis: scan log for entered phases
% -----------------------------------------------------------------------------

%! ebuild_exec:scan_log_entered_phases(+LogPath, -EnteredPhases) is det.
%
% Scans the build log for Portage's phase markers (">>> Running phase: ...")
% to determine which phases were actually entered. Returns a list of
% phase atoms in execution order. Returns [] if log is empty/absent.

ebuild_exec:scan_log_entered_phases(LogPath, EnteredPhases) :-
  ( exists_file(LogPath)
  -> catch(
       ( read_file_to_string(LogPath, Content, []),
         ebuild_exec:extract_phase_markers(Content, EnteredPhases)
       ),
       _, EnteredPhases = [])
  ;  EnteredPhases = []
  ).


%! ebuild_exec:extract_phase_markers(+Content, -Phases) is det.
%
% Extracts phase names from Portage log lines matching
% ">>> Running phase: src_unpack" or ">>> Running phase: pkg_setup".

ebuild_exec:extract_phase_markers(Content, Phases) :-
  split_string(Content, "\n", "", Lines),
  findall(Phase,
    ( member(Line, Lines),
      sub_string(Line, _, _, _, ">>> Running phase:"),
      ebuild_exec:parse_phase_line(Line, Phase)
    ),
    Phases).

ebuild_exec:parse_phase_line(Line, Phase) :-
  split_string(Line, ":", "", Parts),
  last(Parts, PhasePart),
  split_string(PhasePart, " \t", " \t", [PhaseStr|_]),
  ebuild_exec:portage_phase_to_atom(PhaseStr, Phase).


%! ebuild_exec:portage_phase_to_atom(+PhaseStr, -Phase) is semidet.
%
% Maps Portage's phase function names (src_unpack, pkg_setup, etc.)
% to the short phase atoms used in our display (unpack, setup, etc.).

ebuild_exec:portage_phase_to_atom("src_unpack",    unpack).
ebuild_exec:portage_phase_to_atom("src_prepare",   prepare).
ebuild_exec:portage_phase_to_atom("src_configure",  configure).
ebuild_exec:portage_phase_to_atom("src_compile",   compile).
ebuild_exec:portage_phase_to_atom("src_install",   install).
ebuild_exec:portage_phase_to_atom("src_test",      test).
ebuild_exec:portage_phase_to_atom("pkg_setup",     setup).
ebuild_exec:portage_phase_to_atom("pkg_preinst",   preinst).
ebuild_exec:portage_phase_to_atom("pkg_postinst",  postinst).
ebuild_exec:portage_phase_to_atom("pkg_prerm",     prerm).
ebuild_exec:portage_phase_to_atom("pkg_postrm",    postrm).
ebuild_exec:portage_phase_to_atom("pkg_nofetch",   nofetch).


%! ebuild_exec:mark_phases_on_failure(+LivePrefix, +DisplayPhases, +EnteredPhases, +ExitCode, +LogPath, :Callback) is det.
%
% On failure, determines per-phase status:
%   - Phases entered and not the last: completed successfully (done)
%   - Last entered phase: the one that failed (failed)
%   - Phases never entered: skipped (not attempted)
% If no phases were entered (e.g., ebuild not found), the first
% display phase is marked as failed and the rest as skipped.

:- meta_predicate ebuild_exec:mark_phases_on_failure(+, +, +, +, +, 2).

ebuild_exec:mark_phases_on_failure(LivePrefix, DisplayPhases, EnteredPhases, ExitCode, LogPath, Callback) :-
  ( EnteredPhases == []
  -> ( LivePrefix = [First|RestLive]
     -> ( memberchk(First, DisplayPhases)
        -> call(Callback, First, failed(ExitCode, LogPath))
        ;  true
        ),
        forall(
          (member(P, RestLive), memberchk(P, DisplayPhases)),
          call(Callback, P, skipped)
        )
     ;  true
     )
  ;  last(EnteredPhases, FailedPhase),
     forall(
       (member(P, LivePrefix), memberchk(P, DisplayPhases)),
       ( memberchk(P, EnteredPhases)
       -> ( P == FailedPhase
          -> call(Callback, P, failed(ExitCode, LogPath))
          ;  call(Callback, P, done)
          )
       ;  call(Callback, P, skipped)
       )
     )
  ).


% =============================================================================
%  Composite action execution
% =============================================================================

%! ebuild_exec:execute(+Action, +Repo, +Entry, +Ctx, -Outcome) is det.
%
% Execute a plan action end-to-end (bulk, no per-phase progress).
% For update/downgrade, unmerges the old version first.

ebuild_exec:execute(Action, Repo, Entry, Ctx, Outcome) :-
  memberchk(Action, [update, downgrade]),
  !,
  ( ebuild_exec:unmerge_old(Repo, Ctx)
  -> ebuild_exec:execute_phases(Action, Repo, Entry, Ctx, Outcome)
  ;  Outcome = failed(unmerge_old)
  ).

ebuild_exec:execute(uninstall, Repo, Entry, Ctx, Outcome) :-
  !,
  ebuild_exec:execute_phases(uninstall, Repo, Entry, Ctx, Outcome).

ebuild_exec:execute(Action, Repo, Entry, Ctx, Outcome) :-
  ebuild_exec:execute_phases(Action, Repo, Entry, Ctx, Outcome).


%! ebuild_exec:execute_phases(+Action, +Repo, +Entry, +Ctx, -Outcome) is det.

ebuild_exec:execute_phases(Action, Repo, Entry, Ctx, Outcome) :-
  ( ebuild_exec:action_phases(Action, Ctx, Phases),
    ebuild_exec:ebuild_path(Repo, Entry, EbuildPath)
  -> ebuild_exec:run_phases(EbuildPath, Phases, ExitCode),
     ( ExitCode =:= 0
     -> Outcome = done
     ;  Outcome = failed(ExitCode)
     )
  ;  Outcome = failed(no_ebuild)
  ).


%! ebuild_exec:execute_with_progress(+Action, +Repo, +Entry, +Ctx, :PhaseCallback, -Outcome) is det.
%
% Execute a plan action with per-phase progress callbacks.
% For update/downgrade, unmerges the old version first.

:- meta_predicate ebuild_exec:execute_with_progress(+, +, +, +, 2, -).

ebuild_exec:execute_with_progress(Action, Repo, Entry, Ctx, PhaseCallback, Outcome) :-
  memberchk(Action, [update, downgrade]),
  !,
  ( ebuild_exec:unmerge_old(Repo, Ctx)
  -> ebuild_exec:execute_phases_sequential(Action, Repo, Entry, Ctx, PhaseCallback, Outcome)
  ;  Outcome = failed(unmerge_old)
  ).

ebuild_exec:execute_with_progress(Action, Repo, Entry, Ctx, PhaseCallback, Outcome) :-
  ebuild_exec:execute_phases_sequential(Action, Repo, Entry, Ctx, PhaseCallback, Outcome).


%! ebuild_exec:execute_phases_sequential(+Action, +Repo, +Entry, +Ctx, :PhaseCallback, -Outcome) is det.

ebuild_exec:execute_phases_sequential(Action, Repo, Entry, Ctx, PhaseCallback, Outcome) :-
  ( ebuild_exec:action_phases(Action, Ctx, AllPhases),
    ebuild_exec:ebuild_path(Repo, Entry, EbuildPath)
  -> ebuild_exec:display_phases(Action, Repo, Entry, Ctx, DisplayPhases),
     ebuild_exec:ensure_log_dir,
     ebuild_exec:build_log_path(Entry, LogPath),
     ebuild_exec:load_phase_stats,
     ebuild_exec:run_phases_with_config(EbuildPath, Entry, AllPhases, DisplayPhases, LogPath, PhaseCallback, Outcome),
     ebuild_exec:save_phase_stats
  ;  Outcome = failed(no_ebuild)
  ).


% =============================================================================
%  Update/downgrade: unmerge old version
% =============================================================================

%! ebuild_exec:unmerge_old(+Repo, +Ctx) is semidet.
%
% Extracts the replaces(OldRepo://OldEntry) term from the context and
% unmerges the old version. Succeeds if the unmerge exits with code 0.

ebuild_exec:unmerge_old(_Repo, Ctx) :-
  memberchk(replaces(OldRepo://OldEntry), Ctx),
  !,
  ebuild_exec:ebuild_path(OldRepo, OldEntry, OldEbuildPath),
  ebuild_exec:run_phases(OldEbuildPath, [unmerge], ExitCode),
  ExitCode =:= 0.

ebuild_exec:unmerge_old(_, _).
