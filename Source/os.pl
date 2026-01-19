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

:- module(os, [
  with_system_lock/2,
  with_system_lock/3
]).

:- use_module(library(filesex)).
:- use_module(library(readutil)).
:- use_module(library(process)).

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

find_files(Dir, Pattern, File) :-
  directory_member(Dir, File,
                   [ recursive(true),
                     follow_links(false),
                     file_type(regular),
                     matches(Pattern)
                   ]).

% -----------------------------------------------------------------------------
%  Bash wrappers
% -----------------------------------------------------------------------------

%! os:bash_dns_sd(+ArgList,-Lines)
%
% Calls dns-sd command in bash with given ArgList
% Returns lines of strings (output of the command)

os:bash_dns_sd(ArgList, Lines) :-
  atomic_list_concat(['dns-sd'|ArgList],' ',Cmd),
  os:bash_lines(Cmd,Lines).


%! os:bash_lines(+Cmd,-Lines)
%
% Runs a given command in bash
% Returns lines of strings (output of the command)

os:bash_lines(Cmd, Lines) :-
  process_create(path(bash),['-c',Cmd],[stdout(pipe(Out)),process(Pid)]),
  call_cleanup(reader:read_lines_to_strings(Out,Lines),(close(Out),process_wait(Pid,_))).


% -----------------------------------------------------------------------------
%  System-wide locking
% -----------------------------------------------------------------------------
%
% Provides a simple cross-process lock (Darwin + Linux) using an atomic mkdir on
% a lock directory in /tmp.
%
% This is intended to serialize operations like repository/knowledgebase saves
% across *different portage-ng instances* (not just threads).
%
% Options:
% - timeout(Seconds): wait up to Seconds to acquire the lock (default 600). Use -1 for infinite.
% - stale(Seconds): consider lock stale after Seconds and remove it (default 7200). Use 0 to disable.
%

with_system_lock(Name, Goal) :-
  with_system_lock(Name, Goal, []).

with_system_lock(Name, Goal, Options) :-
  ( memberchk(timeout(Timeout), Options) -> true ; Timeout = 600 ),
  ( memberchk(stale(Stale), Options)     -> true ; Stale   = 7200 ),
  os:system_lock_dir(Name, LockDir),
  os:system_lock_acquire(LockDir, Name, Timeout, Stale),
  call_cleanup(Goal, os:system_lock_release(LockDir)).

system_lock_dir(Name, LockDir) :-
  term_to_atom(Name, Atom0),
  os:sanitize_for_filename(Atom0, Atom),
  atomic_list_concat(['/tmp/portage-ng-lock-', Atom, '.lock'], LockDir).

sanitize_for_filename(In, Out) :-
  atom_codes(In, Codes),
  maplist(os:sanitize_code, Codes, Codes2),
  atom_codes(Out, Codes2).

sanitize_code(C, C) :-
  ( C >= 0'a, C =< 0'z
  ; C >= 0'A, C =< 0'Z
  ; C >= 0'0, C =< 0'9
  ; memberchk(C, [0'., 0'_, 0'-])
  ),
  !.
sanitize_code(_C, 0'_).

system_lock_acquire(LockDir, Name, Timeout, Stale) :-
  os:system_lock_meta_path(LockDir, Meta),
  os:system_lock_wait_loop(LockDir, Meta, Name, Timeout, Stale, 0).

system_lock_release(LockDir) :-
  catch(delete_directory_and_contents(LockDir), _Any, true).

system_lock_meta_path(LockDir, Meta) :-
  atomic_list_concat([LockDir, '/meta'], Meta).

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

system_lock_read_kv(Meta, Pid, CreatedAt) :-
  catch(read_file_to_string(Meta, Str, []), _Any, fail),
  split_string(Str, "\n", "\r", Lines),
  os:kv_value(Lines, "pid", PidStr),
  os:kv_value(Lines, "created_at", TsStr),
  number_string(Pid, PidStr),
  number_string(CreatedAt, TsStr).

kv_value(Lines, Key, Value) :-
  atom_concat(Key, "=", Prefix),
  member(Line, Lines),
  sub_string(Line, 0, _, _, Prefix),
  sub_string(Line, _, _, 0, Value),
  !.

system_lock_pid_alive(Pid) :-
  catch(process_kill(Pid, 0), _Any, fail).

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

system_lock_sleep_or_timeout(LockDir, Meta, Name, Timeout, Stale, Waited) :-
  ( Timeout >= 0, Waited >= Timeout ->
      throw(error(resource_error(system_lock_timeout(Name, LockDir)), _))
  ; sleep(1),
    Waited2 is Waited + 1,
    os:system_lock_wait_loop(LockDir, Meta, Name, Timeout, Stale, Waited2)
  ).
