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
% in order. `merge` is a composite phase that internally handles
% pkg_preinst, merging files to the live filesystem, unmerging the
% old version (for update/downgrade/reinstall), and pkg_postinst.
% The phase sequence is therefore identical for all build actions.
% When --buildpkg is active, the `package` phase is inserted after
% `install` to create a binary package before merging.

ebuild_exec:action_phases(install,   _Ctx, Phases) :- ebuild_exec:build_phases(Phases).
ebuild_exec:action_phases(run,       _Ctx, []).
ebuild_exec:action_phases(reinstall, _Ctx, Phases) :- ebuild_exec:build_phases(Phases).
ebuild_exec:action_phases(update,    _Ctx, Phases) :- ebuild_exec:build_phases(Phases).
ebuild_exec:action_phases(downgrade, _Ctx, Phases) :- ebuild_exec:build_phases(Phases).
ebuild_exec:action_phases(uninstall, _Ctx, [unmerge]).


%! ebuild_exec:build_phases(-Phases) is det.
%
% Returns the build phase sequence. When --buildpkg is active,
% the `package` phase is included after `install` to create a
% binary package from the build output before merging to the
% live filesystem.

ebuild_exec:build_phases(Phases) :-
  ( preference:flag(buildpkg)
  -> Phases = [clean, setup, unpack, prepare, configure, compile, test, install, package, merge]
  ;  Phases = [clean, setup, unpack, prepare, configure, compile, test, install, merge]
  ).


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
% Returns the full phase lifecycle for the action. Every phase runs
% regardless of DEFINED_PHASES (Portage uses defaults for undefined ones).

ebuild_exec:display_phases(Action, _Repo, _Entry, Ctx, DisplayPhases) :-
  ebuild_exec:action_phases(Action, Ctx, DisplayPhases).


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
%  USE flag collection for ebuild environment
% =============================================================================

%! ebuild_exec:collect_use_string(+Repo, +Entry, +Ctx, -UseString) is det.
%
% Builds the USE environment variable value from the knowledge base,
% then applies overrides from the proof context:
%   - build_with_use(Uses) / required_use(Uses): assumed(Flag) or assumed(minus(Flag))
%   - suggestion(use_change, _, Changes): use_change(Flag, enable/disable)
% The context overrides take precedence over KB defaults.

ebuild_exec:collect_use_string(Repo, Entry, Ctx, UseString) :-
  findall(Flag-State,
    ( kb:query(iuse(Flag, State0:_Reason), Repo://Entry),
      ( State0 == positive -> State = positive ; State = negative )
    ),
    BasePairs),
  list_to_assoc(BasePairs, BaseAssoc),
  ebuild_exec:apply_ctx_use_overrides(Ctx, BaseAssoc, MergedAssoc),
  assoc_to_keys(MergedAssoc, AllFlags),
  findall(Token,
    ( member(F, AllFlags),
      get_assoc(F, MergedAssoc, S),
      ( S == positive -> Token = F
      ; atom_concat('-', F, Token)
      )
    ),
    Tokens0),
  sort(Tokens0, Tokens),
  ( Tokens == []
  -> UseString = ''
  ;  atomic_list_concat(Tokens, ' ', UseString)
  ).


%! ebuild_exec:apply_ctx_use_overrides(+Ctx, +AssocIn, -AssocOut) is det.
%
% Applies USE flag overrides from the proof context on top of the
% KB-derived base flags. Handles build_with_use, required_use, and
% suggestion(use_change, ...) terms.

ebuild_exec:apply_ctx_use_overrides(Ctx, AssocIn, AssocOut) :-
  ( is_list(Ctx) -> CtxList = Ctx ; CtxList = [] ),
  findall(Flag-State,
    ( member(Term, CtxList),
      ( Term = build_with_use(Uses) ; Term = required_use(Uses) ),
      member(assumed(Raw), Uses),
      ( Raw = minus(F) -> Flag = F, State = negative
      ; Flag = Raw, State = positive
      )
    ),
    DepOverrides),
  findall(Flag-State,
    ( member(suggestion(use_change, _, Changes), CtxList),
      is_list(Changes),
      member(use_change(Flag, Dir), Changes),
      ( Dir == enable -> State = positive ; State = negative )
    ),
    SuggOverrides),
  append(DepOverrides, SuggOverrides, AllOverrides),
  foldl(ebuild_exec:apply_use_override, AllOverrides, AssocIn, AssocOut).


%! ebuild_exec:apply_use_override(+FlagState, +AssocIn, -AssocOut) is det.

ebuild_exec:apply_use_override(Flag-State, AssocIn, AssocOut) :-
  put_assoc(Flag, AssocIn, State, AssocOut).


% =============================================================================
%  Async phase execution (for progress polling)
% =============================================================================

%! ebuild_exec:start_phase_async(+EbuildPath, +Phase, +LogPath, +UseString, -Pid) is det.
%
% Starts a single phase without blocking, appending output to LogPath.
% Passes the resolved USE flags as an environment variable.

ebuild_exec:start_phase_async(EbuildPath, Phase, LogPath, UseString, Pid) :-
  config:ebuild_command(EbuildCmd),
  atom_string(Phase, PhaseStr),
  process_create(
    path(sh),
    ['-c', '"$1" --skip-manifest "$2" "$3" >>"$4" 2>&1', '_', EbuildCmd, EbuildPath, PhaseStr, LogPath],
    [process(Pid), environment(['USE'=UseString])]).


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

%! ebuild_exec:run_phase(+EbuildPath, +Phase, +UseString, -ExitCode) is det.
%
% Invokes the `ebuild` CLI for a single phase. Output is suppressed
% (redirected to null) so it doesn't interfere with the display.

ebuild_exec:run_phase(EbuildPath, Phase, UseString, ExitCode) :-
  config:ebuild_command(EbuildCmd),
  atom_string(Phase, PhaseStr),
  process_create(
    path(EbuildCmd),
    ['--skip-manifest', EbuildPath, PhaseStr],
    [stdout(null), stderr(null), process(Pid), environment(['USE'=UseString])]),
  process_wait(Pid, exit(ExitCode)).


%! ebuild_exec:run_phase_logged(+EbuildPath, +Phase, +LogPath, +UseString, -ExitCode) is det.
%
% Invokes the `ebuild` CLI for a single phase, appending all
% stdout/stderr output to LogPath via shell redirection.

ebuild_exec:run_phase_logged(EbuildPath, Phase, LogPath, UseString, ExitCode) :-
  config:ebuild_command(EbuildCmd),
  atom_string(Phase, PhaseStr),
  process_create(
    path(sh),
    ['-c', '"$1" --skip-manifest "$2" "$3" >>"$4" 2>&1', '_', EbuildCmd, EbuildPath, PhaseStr, LogPath],
    [process(Pid), environment(['USE'=UseString])]),
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


%! ebuild_exec:run_phases(+EbuildPath, +Phases, +UseString, -ExitCode) is det.
%
% Invokes the `ebuild` CLI with all phase arguments at once.
% Used for bulk execution without per-phase progress tracking.

ebuild_exec:run_phases(EbuildPath, Phases, UseString, ExitCode) :-
  config:ebuild_command(EbuildCmd),
  maplist(atom_string, Phases, PhaseStrs),
  process_create(
    path(EbuildCmd),
    ['--skip-manifest', EbuildPath | PhaseStrs],
    [stdout(null), stderr(null), process(Pid), environment(['USE'=UseString])]),
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
%  Phase execution with live config
% =============================================================================

%! ebuild_exec:run_phases_with_config(+EbuildPath, +Entry, +AllPhases, +DisplayPhases, +LogPath, +UseString, :PhaseCallback, -Outcome) is det.
%
% Splits AllPhases into a live prefix (phases to actually execute) and
% a stub tail (phases beyond current config). Executes each live phase
% individually, using exit codes for success/failure. Log file size
% is used only for progress estimation, never for phase detection.
% UseString carries the resolved USE flags for the ebuild environment.

:- meta_predicate ebuild_exec:run_phases_with_config(+, +, +, +, +, +, 2, -).

ebuild_exec:run_phases_with_config(EbuildPath, Entry, AllPhases, DisplayPhases, LogPath, UseString, Callback, Outcome) :-
  config:build_live_phases(LiveConfig),
  ebuild_exec:compute_live_prefix(AllPhases, LiveConfig, LivePrefix, StubTail),
  ( LivePrefix \= []
  -> ebuild_exec:run_phases_sequential(EbuildPath, Entry, LivePrefix, DisplayPhases, LogPath, UseString, Callback, LiveOutcome)
  ;  LiveOutcome = done
  ),
  ( LiveOutcome == done
  -> forall(
       (member(P, StubTail), memberchk(P, DisplayPhases)),
       call(Callback, P, stub)
     ),
     Outcome = done
  ;  forall(
       (member(P, StubTail), memberchk(P, DisplayPhases)),
       call(Callback, P, skipped)
     ),
     Outcome = LiveOutcome
  ).


%! ebuild_exec:run_phases_sequential(+EbuildPath, +Entry, +Phases, +DisplayPhases, +LogPath, +UseString, :Callback, -Outcome) is det.
%
% Executes each phase as a separate ebuild invocation. On success,
% moves to the next phase. On failure, marks remaining phases as
% skipped. Uses log file size growth for progress estimation only.
% UseString is passed to each ebuild invocation as the USE env var.

ebuild_exec:run_phases_sequential(_, _, [], _, _, _, _, done).

ebuild_exec:run_phases_sequential(EbuildPath, Entry, [Phase|Rest], DisplayPhases, LogPath, UseString, Callback, Outcome) :-
  ( memberchk(Phase, DisplayPhases)
  -> call(Callback, Phase, active)
  ;  true
  ),
  ebuild_exec:log_phase_header(LogPath, Phase),
  ebuild_exec:log_file_size(LogPath, SizeBefore),
  get_time(T0),
  ebuild_exec:expected_phase_stats(Entry, Phase, ExpBytes, ExpSecs),
  !,
  ebuild_exec:start_phase_async(EbuildPath, Phase, LogPath, UseString, Pid),
  ebuild_exec:poll_phase_progress(Pid, Phase, LogPath, SizeBefore, T0, ExpBytes, ExpSecs, Callback, ExitCode),
  get_time(T1),
  TotalSecs is T1 - T0,
  ebuild_exec:log_file_size(LogPath, SizeAfter),
  TotalBytes is SizeAfter - SizeBefore,
  ebuild_exec:record_phase_stats(Entry, Phase, TotalBytes, TotalSecs),
  ( ExitCode =:= 0
  -> ( memberchk(Phase, DisplayPhases)
     -> call(Callback, Phase, done)
     ;  true
     ),
     ebuild_exec:run_phases_sequential(EbuildPath, Entry, Rest, DisplayPhases, LogPath, UseString, Callback, Outcome)
  ;  ( memberchk(Phase, DisplayPhases)
     -> call(Callback, Phase, failed(ExitCode, LogPath))
     ;  true
     ),
     forall(
       (member(P, Rest), memberchk(P, DisplayPhases)),
       call(Callback, P, skipped)
     ),
     Outcome = failed(ExitCode)
  ).

ebuild_exec:run_phases_sequential(EbuildPath, Entry, [Phase|Rest], DisplayPhases, LogPath, UseString, Callback, Outcome) :-
  ( memberchk(Phase, DisplayPhases)
  -> call(Callback, Phase, active)
  ;  true
  ),
  ebuild_exec:log_phase_header(LogPath, Phase),
  ebuild_exec:log_file_size(LogPath, SizeBefore),
  get_time(T0),
  ebuild_exec:start_phase_async(EbuildPath, Phase, LogPath, UseString, Pid),
  ebuild_exec:poll_phase_spinning(Pid, Phase, Callback, ExitCode),
  get_time(T1),
  TotalSecs is T1 - T0,
  ebuild_exec:log_file_size(LogPath, SizeAfter),
  TotalBytes is SizeAfter - SizeBefore,
  ebuild_exec:record_phase_stats(Entry, Phase, TotalBytes, TotalSecs),
  ( ExitCode =:= 0
  -> ( memberchk(Phase, DisplayPhases)
     -> call(Callback, Phase, done)
     ;  true
     ),
     ebuild_exec:run_phases_sequential(EbuildPath, Entry, Rest, DisplayPhases, LogPath, UseString, Callback, Outcome)
  ;  ( memberchk(Phase, DisplayPhases)
     -> call(Callback, Phase, failed(ExitCode, LogPath))
     ;  true
     ),
     forall(
       (member(P, Rest), memberchk(P, DisplayPhases)),
       call(Callback, P, skipped)
     ),
     Outcome = failed(ExitCode)
  ).


%! ebuild_exec:poll_phase_spinning(+Pid, +Phase, :Callback, -ExitCode) is det.
%
% Polls a running phase without historical stats. Sends progress(0)
% ticks to keep the spinner alive until the process exits.

ebuild_exec:poll_phase_spinning(Pid, Phase, Callback, ExitCode) :-
  ( ebuild_exec:check_phase_done(Pid, EC)
  -> ExitCode = EC
  ;  call(Callback, Phase, progress(0)),
     sleep(0.5),
     ebuild_exec:poll_phase_spinning(Pid, Phase, Callback, ExitCode)
  ).


% =============================================================================
%  Composite action execution
% =============================================================================

%! ebuild_exec:execute(+Action, +Repo, +Entry, +Ctx, -Outcome) is det.
%
% Execute a plan action end-to-end (bulk, no per-phase progress).
% The merge phase handles replacement of old versions internally
% (pkg_preinst, merge files, unmerge old, pkg_postinst), so
% update/downgrade/reinstall use the same phase sequence as install.

% Disabled: explicit unmerge before build is unnecessary and harmful.
% The merge phase already handles old version replacement via the VDB.
% Removing files before building can break builds that depend on the
% old version's files at compile time.
%
% ebuild_exec:execute(Action, Repo, Entry, Ctx, Outcome) :-
%   memberchk(Action, [update, downgrade]),
%   !,
%   ( ebuild_exec:unmerge_old(Repo, Ctx)
%   -> ebuild_exec:execute_phases(Action, Repo, Entry, Ctx, Outcome)
%   ;  Outcome = failed(unmerge_old)
%   ).

ebuild_exec:execute(uninstall, Repo, Entry, Ctx, Outcome) :-
  !,
  ebuild_exec:execute_phases(uninstall, Repo, Entry, Ctx, Outcome).

ebuild_exec:execute(run, _Repo, _Entry, _Ctx, done) :- !.

ebuild_exec:execute(Action, Repo, Entry, Ctx, Outcome) :-
  ebuild_exec:execute_phases(Action, Repo, Entry, Ctx, Outcome).


%! ebuild_exec:execute_phases(+Action, +Repo, +Entry, +Ctx, -Outcome) is det.

ebuild_exec:execute_phases(Action, Repo, Entry, Ctx, Outcome) :-
  ( ebuild_exec:action_phases(Action, Ctx, Phases),
    ebuild_exec:ebuild_path(Repo, Entry, EbuildPath)
  -> ebuild_exec:collect_use_string(Repo, Entry, Ctx, UseString),
     ebuild_exec:run_phases(EbuildPath, Phases, UseString, ExitCode),
     ( ExitCode =:= 0
     -> Outcome = done
     ;  Outcome = failed(ExitCode)
     )
  ;  Outcome = failed(no_ebuild)
  ).


%! ebuild_exec:execute_with_progress(+Action, +Repo, +Entry, +Ctx, :PhaseCallback, -Outcome) is det.
%
% Execute a plan action with per-phase progress callbacks.
% The merge phase handles replacement of old versions internally.

:- meta_predicate ebuild_exec:execute_with_progress(+, +, +, +, 2, -).

% Disabled: see execute/5 comment above.
%
% ebuild_exec:execute_with_progress(Action, Repo, Entry, Ctx, PhaseCallback, Outcome) :-
%   memberchk(Action, [update, downgrade]),
%   !,
%   ( ebuild_exec:unmerge_old(Repo, Ctx)
%   -> ebuild_exec:execute_phases_sequential(Action, Repo, Entry, Ctx, PhaseCallback, Outcome)
%   ;  Outcome = failed(unmerge_old)
%   ).

ebuild_exec:execute_with_progress(Action, Repo, Entry, Ctx, PhaseCallback, Outcome) :-
  ebuild_exec:execute_phases_sequential(Action, Repo, Entry, Ctx, PhaseCallback, Outcome).


%! ebuild_exec:execute_phases_sequential(+Action, +Repo, +Entry, +Ctx, :PhaseCallback, -Outcome) is det.

ebuild_exec:execute_phases_sequential(Action, Repo, Entry, Ctx, PhaseCallback, Outcome) :-
  ( ebuild_exec:action_phases(Action, Ctx, AllPhases),
    ebuild_exec:ebuild_path(Repo, Entry, EbuildPath)
  -> ebuild_exec:display_phases(Action, Repo, Entry, Ctx, DisplayPhases),
     ebuild_exec:collect_use_string(Repo, Entry, Ctx, UseString),
     ebuild_exec:ensure_log_dir,
     ebuild_exec:build_log_path(Entry, LogPath),
     ebuild_exec:load_phase_stats,
     ebuild_exec:run_phases_with_config(EbuildPath, Entry, AllPhases, DisplayPhases, LogPath, UseString, PhaseCallback, Outcome),
     ebuild_exec:save_phase_stats
  ;  Outcome = failed(no_ebuild)
  ).


% =============================================================================
%  Update/downgrade: unmerge old version
% =============================================================================

% Disabled: the merge phase handles old version replacement internally
% via the VDB (pkg_preinst → merge files → unmerge old → pkg_postinst).
% Explicit pre-build unmerge is unnecessary and can break builds that
% depend on the old version's files at compile time.
%
% ebuild_exec:unmerge_old(_Repo, Ctx) :-
%   memberchk(replaces(OldRepo://OldEntry), Ctx),
%   !,
%   ebuild_exec:ebuild_path(OldRepo, OldEntry, OldEbuildPath),
%   ebuild_exec:collect_use_string(OldRepo, OldEntry, [], UseString),
%   ebuild_exec:run_phases(OldEbuildPath, [unmerge], UseString, ExitCode),
%   ExitCode =:= 0.
%
% ebuild_exec:unmerge_old(_, _).
