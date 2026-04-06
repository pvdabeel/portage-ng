/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> LOCK
Cross-process filesystem locking for serializing operations like
repository and knowledgebase saves across different portage-ng instances.

Uses atomic mkdir on a lock directory in /tmp. Supports configurable
timeouts and stale-lock detection (dead holder PID or age threshold).
*/

:- module(lock, []).

% =============================================================================
%  LOCK declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Public interface
% -----------------------------------------------------------------------------

:- meta_predicate with_system_lock(+, 0).
:- meta_predicate with_system_lock(+, 0, +).


%! lock:with_system_lock(+Name, :Goal) is det.
%
% Convenience wrapper: acquires system lock Name, runs Goal, releases lock.
% Uses default options (timeout 600s, stale 7200s).

lock:with_system_lock(Name, Goal) :-
  lock:with_system_lock(Name, Goal, []).


%! lock:with_system_lock(+Name, :Goal, +Options) is det.
%
% Acquire a cross-process filesystem lock identified by Name, execute Goal,
% and release the lock on completion (or exception). Options:
%   - `timeout(Seconds)` — max wait to acquire (default 600; -1 = infinite)
%   - `stale(Seconds)` — consider lock stale after this age (default 7200; 0 = disable)

lock:with_system_lock(Name, Goal, Options) :-
  ( memberchk(timeout(Timeout), Options) -> true ; Timeout = 600 ),
  ( memberchk(stale(Stale), Options)     -> true ; Stale   = 7200 ),
  lock:lock_dir(Name, LockDir),
  lock:lock_acquire(LockDir, Name, Timeout, Stale),
  call_cleanup(Goal, lock:lock_release(LockDir)).


% -----------------------------------------------------------------------------
%  Lock directory path
% -----------------------------------------------------------------------------

%! lock:lock_dir(+Name, -LockDir) is det.
%
% Derive the filesystem lock directory path in /tmp from a lock Name term.

lock:lock_dir(Name, LockDir) :-
  term_to_atom(Name, Atom0),
  lock:sanitize_for_filename(Atom0, Atom),
  atomic_list_concat(['/tmp/portage-ng-lock-', Atom, '.lock'], LockDir).


% -----------------------------------------------------------------------------
%  Filename sanitization
% -----------------------------------------------------------------------------

%! lock:sanitize_for_filename(+In, -Out) is det.
%
% Replace characters unsafe for filenames with underscores, keeping
% alphanumerics, dots, hyphens, and underscores.

lock:sanitize_for_filename(In, Out) :-
  atom_codes(In, Codes),
  maplist(lock:sanitize_code, Codes, Codes2),
  atom_codes(Out, Codes2).


%! lock:sanitize_code(+CodeIn, -CodeOut) is det.
%
% Map a character code to itself if safe for filenames, otherwise to underscore.

lock:sanitize_code(C, C) :-
  ( C >= 0'a, C =< 0'z
  ; C >= 0'A, C =< 0'Z
  ; C >= 0'0, C =< 0'9
  ; memberchk(C, [0'., 0'_, 0'-])
  ),
  !.

lock:sanitize_code(_C, 0'_).


% -----------------------------------------------------------------------------
%  Lock acquire / release
% -----------------------------------------------------------------------------

%! lock:lock_acquire(+LockDir, +Name, +Timeout, +Stale) is det.
%
% Acquire the lock by creating LockDir atomically (mkdir). Blocks with
% retry polling until the lock is obtained or Timeout is exceeded.

lock:lock_acquire(LockDir, Name, Timeout, Stale) :-
  lock:lock_meta_path(LockDir, Meta),
  lock:lock_wait_loop(LockDir, Meta, Name, Timeout, Stale, 0).


%! lock:lock_release(+LockDir) is det.
%
% Release the lock by removing LockDir and its contents.

lock:lock_release(LockDir) :-
  catch(delete_directory_and_contents(LockDir), _Any, true).


% -----------------------------------------------------------------------------
%  Metadata file operations
% -----------------------------------------------------------------------------

%! lock:lock_meta_path(+LockDir, -Meta) is det.
%
% Path to the metadata file inside the lock directory.

lock:lock_meta_path(LockDir, Meta) :-
  atomic_list_concat([LockDir, '/meta'], Meta).


%! lock:lock_write_meta(+Meta, +Name) is det.
%
% Write lock holder metadata (PID, timestamp, working directory, lock name)
% to the meta file for diagnostics and stale-lock detection.

lock:lock_write_meta(Meta, Name) :-
  get_time(NowF),
  Now is integer(floor(NowF)),
  current_prolog_flag(pid, Pid),
  working_directory(Cwd, Cwd),
  setup_call_cleanup(
    open(Meta, write, S, [encoding(utf8)]),
    format(S, 'pid=~w~ncreated_at=~w~ncwd=~w~nname=~q~n', [Pid, Now, Cwd, Name]),
    close(S)
  ).


%! lock:lock_read_kv(+Meta, -Pid, -CreatedAt) is semidet.
%
% Read the lock holder's PID and creation timestamp from the meta file.
% Fails if the file cannot be read or parsed.

lock:lock_read_kv(Meta, Pid, CreatedAt) :-
  catch(read_file_to_string(Meta, Str, []), _Any, fail),
  split_string(Str, "\n", "\r", Lines),
  lock:kv_value(Lines, "pid", PidStr),
  lock:kv_value(Lines, "created_at", TsStr),
  number_string(Pid, PidStr),
  number_string(CreatedAt, TsStr).


%! lock:kv_value(+Lines, +Key, -Value) is semidet.
%
% Extract the value for a "Key=Value" line from a list of strings.

lock:kv_value(Lines, Key, Value) :-
  atom_concat(Key, "=", Prefix),
  member(Line, Lines),
  sub_string(Line, 0, _, _, Prefix),
  sub_string(Line, _, _, 0, Value),
  !.


% -----------------------------------------------------------------------------
%  Process liveness check
% -----------------------------------------------------------------------------

%! lock:lock_pid_alive(+Pid) is semidet.
%
% True if the process with Pid is still running (signal 0 probe).

lock:lock_pid_alive(Pid) :-
  catch(process_kill(Pid, 0), _Any, fail).


% -----------------------------------------------------------------------------
%  Wait loop
% -----------------------------------------------------------------------------

%! lock:lock_wait_loop(+LockDir, +Meta, +Name, +Timeout, +Stale, +Waited) is det.
%
% Core lock-acquisition loop. Attempts atomic mkdir; on failure checks
% whether the existing lock is stale or held by a dead process, and
% either reclaims it or sleeps and retries.

lock:lock_wait_loop(LockDir, Meta, Name, Timeout, Stale, Waited) :-
  ( catch(make_directory(LockDir), _Any, fail) ->
      lock:lock_write_meta(Meta, Name)
  ;
    ( lock:lock_read_kv(Meta, Pid, CreatedAt) ->
        get_time(NowF),
        Now is integer(floor(NowF)),
        ( ( \+ lock:lock_pid_alive(Pid) )
        -> lock:lock_release(LockDir),
           lock:lock_wait_loop(LockDir, Meta, Name, Timeout, Stale, Waited)
        ; ( Stale > 0, Now - CreatedAt >= Stale )
        -> lock:lock_release(LockDir),
           lock:lock_wait_loop(LockDir, Meta, Name, Timeout, Stale, Waited)
        ; lock:lock_sleep_or_timeout(LockDir, Meta, Name, Timeout, Stale, Waited)
        )
    ; lock:lock_sleep_or_timeout(LockDir, Meta, Name, Timeout, Stale, Waited)
    )
  ).


%! lock:lock_sleep_or_timeout(+LockDir, +Meta, +Name, +Timeout, +Stale, +Waited) is det.
%
% Sleep 1 second and retry, or throw `system_lock_timeout` if the timeout
% has been reached.

lock:lock_sleep_or_timeout(LockDir, Meta, Name, Timeout, Stale, Waited) :-
  ( Timeout >= 0, Waited >= Timeout ->
      throw(error(resource_error(system_lock_timeout(Name, LockDir)), _))
  ; sleep(1),
    Waited2 is Waited + 1,
    lock:lock_wait_loop(LockDir, Meta, Name, Timeout, Stale, Waited2)
  ).