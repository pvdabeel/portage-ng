/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> IPC
Local IPC façade used inside the full portage-ng process.

Client protocol (connect, status, halt, request streaming) lives in
`Source/Application/Client/ipclient.pl` — the ultralight standalone entry
point. This module:

- delegates those operations to `ipclient`
- keeps in-process daemon/server background forking (`fork_background/1`)
  for `--mode daemon|server --background`, where `os_argv` already carries
  the full swipl flags

Authentication relies on Unix file permissions (socket mode 0600 inside a
0700 owner-verified runtime directory; see daemon:ensure_runtime_dir/0).

@see Source/Application/Client/ipclient.pl
@see daemon.pl
@see config:daemon_socket_path/1
@see config:daemon_pid_path/1
*/


:- module(ipc, []).

:- use_module(library(process)).

% Import nothing: we call ipclient:Pred explicitly. Re-exporting the same
% functor names would warn about overriding weak imports.
:- prolog_load_context(directory, Dir),
   absolute_file_name('../Client/ipclient', Ipclient,
                      [ relative_to(Dir),
                        file_type(prolog),
                        access(read)
                      ]),
   use_module(Ipclient, []).

% =============================================================================
%  IPC declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Client connection (delegates to ipclient)
% -----------------------------------------------------------------------------

%! ipc:connect(-ExitCode) is det.
%
% Connects to the daemon and streams one request. See ipclient:connect/1.

ipc:connect(ExitCode) :-
  ipclient:connect(ExitCode).


%! ipc:status is semidet.
%
% Checks if a daemon is running. See ipclient:status/0.

ipc:status :-
  ipclient:status.


%! ipc:send_command(+Cmd) is det.
%
% halt is delegated to ipclient. relaunch stops via ipclient then forks a
% daemon with this process's full swipl flags (correct inside portage-ng.pl).

ipc:send_command(halt) :-
  !,
  ipclient:send_command(halt).

ipc:send_command(relaunch) :-
  !,
  ipclient:send_command(halt),
  sleep(1),
  config:daemon_socket_path(SocketPath),
  ipclient:wait_for_socket_gone(SocketPath, 50),
  ipc:fork_background(daemon).

ipc:send_command(Cmd) :-
  format(user_error, 'Unknown command: ~w. Use halt or relaunch.~n', [Cmd]).


%! ipc:autostart is det.
%
% If no daemon socket exists and config:daemon_autostart(true), fork a
% background daemon using this process's swipl flags.

ipc:autostart :-
  config:daemon_socket_path(SocketPath),
  \+ access_file(SocketPath, exist),
  config:daemon_autostart(true),
  !,
  ipc:fork_background(daemon).
ipc:autostart.


%! ipc:relaunch is det.
%
% Convenience: stops the current daemon and starts a new one in background.

ipc:relaunch :-
  ipc:send_command(relaunch).


%! ipc:send_term(+SocketPath, +Term) is det.

ipc:send_term(SocketPath, Term) :-
  ipclient:send_term(SocketPath, Term).


% -----------------------------------------------------------------------------
%  Lifecycle management (full-stack process only)
% -----------------------------------------------------------------------------

%! ipc:fork_background(+Mode) is det.
%
% Forks a new detached swipl process running the given Mode (daemon or
% server) without --background. The swipl executable and flags are taken
% from the current process, so they cannot drift from the launcher's.
% The parent polls for readiness then exits.

ipc:fork_background(Mode) :-
  background_command(Mode, Exe, Args),
  process_create(Exe, Args,
    [ process(Pid),
      detached(true),
      stdout(null),
      stderr(null)
    ]),
  format('Starting ~w in background (PID ~w)...~n', [Mode, Pid]),
  wait_for_ready(Mode, Pid).


%! ipc:background_command(+Mode, -Exe, -Args) is det.
%
% Rebuilds the command line of the current process with the application
% arguments (after `--`) replaced by `--mode Mode`. This keeps the swipl
% flags (-O, stack limits, -f, -p, -g main) in a single place — the
% launcher that started the current process — instead of duplicating
% them here.

ipc:background_command(Mode, Exe, Args) :-
  current_prolog_flag(executable, Exe),
  current_prolog_flag(os_argv, [_Argv0|Rest]),
  ( append(SwiplFlags, ['--'|_AppArgs], Rest)
  -> true
  ;  SwiplFlags = Rest
  ),
  append(SwiplFlags, ['--', '--mode', Mode], Args).


%! ipc:wait_for_ready(+Mode, +Pid) is det.
%
% Polls for mode-specific readiness instead of sleeping a fixed amount:
% the daemon is ready once its PID file appears, the server once its
% port accepts TCP connections.

ipc:wait_for_ready(daemon, Pid) :-
  !,
  config:daemon_socket_path(SocketPath),
  ipclient:wait_for_file(SocketPath, 600),
  ( ipclient:socket_connectable(SocketPath)
  -> format('Daemon ready (PID ~w).~n', [Pid])
  ;  format(user_error, 'Warning: daemon may not have started.~n', [])
  ).
ipc:wait_for_ready(server, Pid) :-
  !,
  interface:get_port(Port),
  ( wait_for_port(localhost, Port, 600)
  -> format('Server ready (PID ~w, port ~w).~n', [Pid, Port])
  ;  format(user_error, 'Warning: server may not have started.~n', [])
  ).
ipc:wait_for_ready(_, _).


%! ipc:wait_for_port(+Host, +Port, +Retries) is semidet.
%
% Polls until a TCP connection to Host:Port succeeds, sleeping 100ms
% between retries. Fails when the retries are exhausted.

ipc:wait_for_port(_, _, 0) :- !, fail.
ipc:wait_for_port(Host, Port, N) :-
  ( interface:server_reachable(Host, Port)
  -> true
  ;  sleep(0.1),
     N1 is N - 1,
     wait_for_port(Host, Port, N1)
  ).
