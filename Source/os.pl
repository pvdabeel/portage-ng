/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> OS
This file contains predicates used to interact with the operating system
Goal is to get the same behaviour across different platform.
Eventually this could become a class with different subclasses.
*/

:- module(os, []).

% =============================================================================
%  OS declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Path operations
% -----------------------------------------------------------------------------

%! os:compose_path(+Path,+RelativePath,-NewPath)
%
% Given a path (relative or absolute) and a relative path, composes a
% new path by combining both paths and a separator.

os:compose_path(Path,RelativePath,NewPath) :-
  atomic_list_concat([Path,'/',RelativePath],NewPath).


%! os:compose_path(+List,-Path)
%
% Given a list of path components, composes a new path by combining
% path segments using correct OS seperator

os:compose_path(List,Path) :-
  atomic_list_concat(List,'/',Path).


% -----------------------------------------------------------------------------
%  Directory operations
% -----------------------------------------------------------------------------

%! os:make_directory(+Directory)
%
% Makes a directory if it doesn't exist already

os:make_directory(Directory) :-
  catch(system:make_directory(Directory),
        _,
        true).

%! os:ensure_directory_path(+Directory)
%
% Create Directory and missing parents (mkdir -p).
% Wrapper around library(filesex):make_directory_path/1.

os:ensure_directory_path(Directory) :-
  catch(filesex:make_directory_path(Directory), _, true).


%! os:contains(+File,+Directory)
%
% Check whether a given directory contains a file

os:contains(File,Directory) :-
  catch((exists_directory(Directory),
         os:compose_path(Directory,File,Path),
         exists_file(Path)),
        _,
        false).


%! os:directory_content(+Directory,-Content)
%
% For a given directory, returns an alphabetical list containing the
% content of the directory. Special contents (like '.' and '..') is
% filtered.

os:directory_content(Directory,Content) :-
  exists_directory(Directory),
  system:directory_files(Directory,UnsortedContents),!,
  sort(UnsortedContents,['.','..'|Contents]),
  lists:member(Content,Contents).


% -----------------------------------------------------------------------------
%  Finding files
% -----------------------------------------------------------------------------

%! os:find_files(+Dir, +Pattern, -File) is nondet.
%
% Non-deterministically unify File with regular files under Dir whose
% names match the glob Pattern. Follows no symlinks.

find_files(Dir, Pattern, File) :-
  directory_member(Dir, File,
                   [ recursive(true),
                     follow_links(false),
                     file_type(regular),
                     matches(Pattern)
                   ]).


% -----------------------------------------------------------------------------
%  System-wide locking
% -----------------------------------------------------------------------------

% Provides a simple cross-process lock (Darwin + Linux) using an atomic mkdir on
% a lock directory in /tmp.
%
% This is intended to serialize operations like repository/knowledgebase saves
% across *different portage-ng instances* (not just threads).
%
% Options:
% - timeout(Seconds): wait up to Seconds to acquire the lock (default 600). Use -1 for infinite.
% - stale(Seconds): consider lock stale after Seconds and remove it (default 7200). Use 0 to disable.


% Meta-predicate declarations:
% Ensure the Goal executes in the *caller* context/module, not in module `os`.
% This is crucial when the Goal uses instance-method syntax (`::`) or relies on
% caller-local predicates.

:- meta_predicate with_system_lock(+, 0).
:- meta_predicate with_system_lock(+, 0, +).


%! os:with_system_lock(+Name, :Goal) is det.
%
% Convenience wrapper: acquires system lock Name, runs Goal, releases lock.
% Uses default options (timeout 600s, stale 7200s).

with_system_lock(Name, Goal) :-
  with_system_lock(Name, Goal, []).


%! os:with_system_lock(+Name, :Goal, +Options) is det.
%
% Acquire a cross-process filesystem lock identified by Name, execute Goal,
% and release the lock on completion (or exception). Options:
%   - `timeout(Seconds)` — max wait to acquire (default 600; -1 = infinite)
%   - `stale(Seconds)` — consider lock stale after this age (default 7200; 0 = disable)

with_system_lock(Name, Goal, Options) :-
  ( memberchk(timeout(Timeout), Options) -> true ; Timeout = 600 ),
  ( memberchk(stale(Stale), Options)     -> true ; Stale   = 7200 ),
  os:system_lock_dir(Name, LockDir),
  os:system_lock_acquire(LockDir, Name, Timeout, Stale),
  call_cleanup(Goal, os:system_lock_release(LockDir)).


%! os:system_lock_dir(+Name, -LockDir) is det.
%
% Derive the filesystem lock directory path in /tmp from a lock Name term.

system_lock_dir(Name, LockDir) :-
  term_to_atom(Name, Atom0),
  os:sanitize_for_filename(Atom0, Atom),
  atomic_list_concat(['/tmp/portage-ng-lock-', Atom, '.lock'], LockDir).


%! os:sanitize_for_filename(+In, -Out) is det.
%
% Replace characters unsafe for filenames with underscores, keeping
% alphanumerics, dots, hyphens, and underscores.

sanitize_for_filename(In, Out) :-
  atom_codes(In, Codes),
  maplist(os:sanitize_code, Codes, Codes2),
  atom_codes(Out, Codes2).


%! os:sanitize_code(+CodeIn, -CodeOut) is det.
%
% Map a character code to itself if safe for filenames, otherwise to underscore.

sanitize_code(C, C) :-
  ( C >= 0'a, C =< 0'z
  ; C >= 0'A, C =< 0'Z
  ; C >= 0'0, C =< 0'9
  ; memberchk(C, [0'., 0'_, 0'-])
  ),
  !.

sanitize_code(_C, 0'_).


%! os:system_lock_acquire(+LockDir, +Name, +Timeout, +Stale) is det.
%
% Acquire the lock by creating LockDir atomically (mkdir). Blocks with
% retry polling until the lock is obtained or Timeout is exceeded.

system_lock_acquire(LockDir, Name, Timeout, Stale) :-
  os:system_lock_meta_path(LockDir, Meta),
  os:system_lock_wait_loop(LockDir, Meta, Name, Timeout, Stale, 0).


%! os:system_lock_release(+LockDir) is det.
%
% Release the lock by removing LockDir and its contents.

system_lock_release(LockDir) :-
  catch(delete_directory_and_contents(LockDir), _Any, true).


%! os:system_lock_meta_path(+LockDir, -Meta) is det.
%
% Path to the metadata file inside the lock directory.

system_lock_meta_path(LockDir, Meta) :-
  atomic_list_concat([LockDir, '/meta'], Meta).


%! os:system_lock_write_meta(+Meta, +Name) is det.
%
% Write lock holder metadata (PID, timestamp, working directory, lock name)
% to the meta file for diagnostics and stale-lock detection.

system_lock_write_meta(Meta, Name) :-
  get_time(NowF),
  Now is integer(floor(NowF)),
  current_prolog_flag(pid, Pid),
  working_directory(Cwd, Cwd),
  setup_call_cleanup(
    open(Meta, write, S, [encoding(utf8)]),
    format(S, 'pid=~w~ncreated_at=~w~ncwd=~w~nname=~q~n', [Pid, Now, Cwd, Name]),
    close(S)
  ).


%! os:system_lock_read_kv(+Meta, -Pid, -CreatedAt) is semidet.
%
% Read the lock holder's PID and creation timestamp from the meta file.
% Fails if the file cannot be read or parsed.

system_lock_read_kv(Meta, Pid, CreatedAt) :-
  catch(read_file_to_string(Meta, Str, []), _Any, fail),
  split_string(Str, "\n", "\r", Lines),
  os:kv_value(Lines, "pid", PidStr),
  os:kv_value(Lines, "created_at", TsStr),
  number_string(Pid, PidStr),
  number_string(CreatedAt, TsStr).


%! os:kv_value(+Lines, +Key, -Value) is semidet.
%
% Extract the value for a "Key=Value" line from a list of strings.

kv_value(Lines, Key, Value) :-
  atom_concat(Key, "=", Prefix),
  member(Line, Lines),
  sub_string(Line, 0, _, _, Prefix),
  sub_string(Line, _, _, 0, Value),
  !.


%! os:system_lock_pid_alive(+Pid) is semidet.
%
% True if the process with Pid is still running (signal 0 probe).

system_lock_pid_alive(Pid) :-
  catch(process_kill(Pid, 0), _Any, fail).


%! os:system_lock_wait_loop(+LockDir, +Meta, +Name, +Timeout, +Stale, +Waited) is det.
%
% Core lock-acquisition loop. Attempts atomic mkdir; on failure checks
% whether the existing lock is stale or held by a dead process, and
% either reclaims it or sleeps and retries.

system_lock_wait_loop(LockDir, Meta, Name, Timeout, Stale, Waited) :-
  ( catch(make_directory(LockDir), _Any, fail) ->
      os:system_lock_write_meta(Meta, Name)
  ; % lock exists; check for stale/dead holder
    ( os:system_lock_read_kv(Meta, Pid, CreatedAt) ->
        get_time(NowF),
        Now is integer(floor(NowF)),
        ( ( \+ os:system_lock_pid_alive(Pid) )
        -> os:system_lock_release(LockDir),
           os:system_lock_wait_loop(LockDir, Meta, Name, Timeout, Stale, Waited)
        ; ( Stale > 0, Now - CreatedAt >= Stale )
        -> os:system_lock_release(LockDir),
           os:system_lock_wait_loop(LockDir, Meta, Name, Timeout, Stale, Waited)
        ; os:system_lock_sleep_or_timeout(LockDir, Meta, Name, Timeout, Stale, Waited)
        )
    ; os:system_lock_sleep_or_timeout(LockDir, Meta, Name, Timeout, Stale, Waited)
    )
  ).


%! os:system_lock_sleep_or_timeout(+LockDir, +Meta, +Name, +Timeout, +Stale, +Waited) is det.
%
% Sleep 1 second and retry, or throw `system_lock_timeout` if the timeout
% has been reached.

system_lock_sleep_or_timeout(LockDir, Meta, Name, Timeout, Stale, Waited) :-
  ( Timeout >= 0, Waited >= Timeout ->
      throw(error(resource_error(system_lock_timeout(Name, LockDir)), _))
  ; sleep(1),
    Waited2 is Waited + 1,
    os:system_lock_wait_loop(LockDir, Meta, Name, Timeout, Stale, Waited2)
  ).