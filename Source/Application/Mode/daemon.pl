/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> DAEMON
Server side of the persistent local daemon for ipc mode. The daemon keeps the
full standalone state (modules + Knowledge/kb.qlf + preferences) resident in
memory and serves requests over a Unix domain socket: it creates the socket,
enters an accept loop, handles each request by redirecting output to the socket
stream, and auto-shuts down after a configurable inactivity period
(`daemon:start/0`).

The client side -- connecting to the socket, forwarding CLI arguments and
environment, and daemon lifecycle control -- lives in ipc.pl. The bridge
dynamics populated here per request (`client_env/2`, `client_is_tty/0`,
`client_tty_size/2`) and `running/0` are read by interface.pl/config.pl in
every mode; their declarations are mirrored in stubs.pl so non-daemon modes
resolve them without loading this module.

Authentication relies on Unix file permissions: the runtime directory is
created (or verified) with mode 0700 and owner-checked before the socket is
bound inside it, and the socket itself is chmod'ed to 0600 in-process. The
0700 directory means there is no window in which another local user can
connect. Only processes running as the same OS user can connect.

@see ipc.pl
@see config:daemon_runtime_dir/1
@see config:daemon_socket_path/1
@see config:daemon_pid_path/1
@see config:daemon_inactivity_timeout/1
*/

:- module(daemon, []).

% =============================================================================
%  DAEMON declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Daemon server
% -----------------------------------------------------------------------------

%! daemon:start is det.
%
% Starts the daemon: creates a Unix domain socket, writes a PID file,
% and enters the accept loop. Registers cleanup for halt.

daemon:start :-
  ensure_runtime_dir,
  config:daemon_socket_path(SocketPath),
  config:daemon_pid_path(PidPath),
  unix_domain_socket(Socket),
  daemon:bind_socket(Socket, SocketPath),
  secure_socket_file(SocketPath),
  tcp_listen(Socket, 5),
  write_pid(PidPath),
  assertz(daemon:running),
  at_halt(cleanup(SocketPath, PidPath)),
  current_prolog_flag(pid, Pid),
  format('Daemon started (PID ~w), listening on ~w~n', [Pid, SocketPath]),
  accept_loop(Socket).


%! daemon:bind_socket(+Socket, +SocketPath) is det.
%
% Bind first. On failure, preserve a live daemon; reclaim one stale,
% non-symlink socket entry inside the verified private runtime directory and
% retry once.

daemon:bind_socket(Socket, SocketPath) :-
  catch(tcp_bind(Socket, SocketPath),
        Error,
        daemon:bind_socket_retry(Socket, SocketPath, Error)).


%! daemon:bind_socket_retry(+Socket, +SocketPath, +OriginalError) is det.

daemon:bind_socket_retry(_Socket, SocketPath, _OriginalError) :-
  daemon:socket_live(SocketPath),
  !,
  throw(error(permission_error(start, daemon, already_running(SocketPath)), _)).
daemon:bind_socket_retry(Socket, SocketPath, _OriginalError) :-
  access_file(SocketPath, exist),
  !,
  ( sanitize:not_symlink(SocketPath)
  -> delete_file(SocketPath),
     catch(tcp_bind(Socket, SocketPath), RetryError, throw(RetryError))
  ;  daemon:insecure_runtime_error(SocketPath, 'is a symlink')
  ).
daemon:bind_socket_retry(_Socket, _SocketPath, OriginalError) :-
  throw(OriginalError).


%! daemon:socket_live(+SocketPath) is semidet.
%
% True when a process accepts a connection at SocketPath.

daemon:socket_live(SocketPath) :-
  catch(
    setup_call_cleanup(
      unix_domain_socket(Probe),
      tcp_connect(Probe, SocketPath),
      tcp_close_socket(Probe)),
    _,
    fail).


%! daemon:ensure_runtime_dir is det.
%
% Creates (if needed) and security-checks the runtime directory holding
% the daemon socket and PID file. The directory must not be a symlink,
% must be a real directory, and is set to mode 0700 in-process. Since
% chmod(2) only succeeds for the owner (or root), a successful chmod also
% verifies ownership: a directory pre-created by another user (which the
% sticky bit on /tmp permits) makes the daemon fail hard instead of
% silently serving requests through an attacker-owned directory.

daemon:ensure_runtime_dir :-
  config:daemon_runtime_dir(Dir),
  ( exists_directory(Dir) -> true ; catch(make_directory(Dir), _, true) ),
  ( read_link(Dir, _, _)
  -> insecure_runtime_error(Dir, 'is a symlink')
  ;  true
  ),
  ( exists_directory(Dir)
  -> true
  ;  insecure_runtime_error(Dir, 'could not be created or is not a directory')
  ),
  catch(filesex:chmod(Dir, 0o700), _,
        insecure_runtime_error(Dir, 'not owned by current user or mode 0700 could not be set')).


%! daemon:secure_socket_file(+SocketPath) is det.
%
% Restricts the freshly bound socket to mode 0600 in-process (no chmod
% subprocess). Runs before tcp_listen and while the socket lives inside
% the 0700 runtime directory, so there is no window in which another
% local user can connect. Fails hard if permissions cannot be set.

daemon:secure_socket_file(SocketPath) :-
  catch(filesex:chmod(SocketPath, 0o600), _,
        insecure_runtime_error(SocketPath, 'mode 0600 could not be set on socket')).


%! daemon:insecure_runtime_error(+Path, +Reason) is det.
%
% Reports a runtime directory / socket security violation and aborts
% daemon startup.

daemon:insecure_runtime_error(Path, Reason) :-
  format(user_error, 'Error: refusing to start daemon: ~w ~w~n', [Path, Reason]),
  halt(1).


%! daemon:write_pid(+PidPath) is det.
%
% Writes the current process PID to the given file.

daemon:write_pid(PidPath) :-
  current_prolog_flag(pid, Pid),
  format(atom(TmpPath), '~w.~w.tmp', [PidPath, Pid]),
  setup_call_cleanup(
    open(TmpPath, write, S),
    ( format(S, '~w~n', [Pid]),
      flush_output(S)
    ),
    close(S)),
  filesex:chmod(TmpPath, 0o600),
  rename_file(TmpPath, PidPath).


%! daemon:cleanup(+SocketPath, +PidPath) is det.
%
% Removes the socket and PID files on daemon exit.

daemon:cleanup(SocketPath, PidPath) :-
  ( access_file(SocketPath, exist),
    sanitize:not_symlink(SocketPath)
  -> catch(delete_file(SocketPath), _, true)
  ;  true
  ),
  ( daemon:pid_file_is_current(PidPath)
  -> catch(delete_file(PidPath), _, true)
  ;  true
  ).


%! daemon:pid_file_is_current(+PidPath) is semidet.

daemon:pid_file_is_current(PidPath) :-
  access_file(PidPath, exist),
  sanitize:not_symlink(PidPath),
  setup_call_cleanup(
    open(PidPath, read, S),
    read_string(S, _, Raw),
    close(S)),
  normalize_space(atom(PidAtom), Raw),
  atom_number(PidAtom, StoredPid),
  current_prolog_flag(pid, StoredPid).


:- dynamic daemon:inactivity_alarm/1.

%! daemon:reset_timer is det.
%
% Resets the inactivity timer. If timeout is 0, no timer is set.

daemon:reset_timer :-
  ( retract(daemon:inactivity_alarm(OldAlarm))
  -> catch(remove_alarm(OldAlarm), _, true)
  ;  true
  ),
  config:daemon_inactivity_timeout(Timeout),
  ( Timeout > 0
  -> alarm(Timeout, inactivity_shutdown, Alarm, []),
     assertz(daemon:inactivity_alarm(Alarm))
  ;  true
  ).


%! daemon:inactivity_shutdown is det.
%
% Called when the inactivity timer fires.

daemon:inactivity_shutdown :-
  format(user_error, 'Daemon shutting down due to inactivity~n', []),
  halt(0).


%! daemon:accept_loop(+Socket) is det.
%
% Main accept loop. Accepts connections one at a time (serialized requests).

daemon:accept_loop(Socket) :-
  reset_timer,
  tcp_accept(Socket, ClientSocket, _Peer),
  tcp_open_socket(ClientSocket, StreamPair),
  stream_pair(StreamPair, In, Out),
  set_stream(In, encoding(utf8)),
  set_stream(Out, encoding(utf8)),
  ( handle_request(In, Out)
  -> true
  ;  true
  ),
  catch(close(In), _, true),
  catch(close(Out), _, true),
  accept_loop(Socket).


%! daemon:handle_request(+In, +Out) is det.
%
% Handles a single request from a client connection.
% Reads the request term, isolates state, runs the request with
% output redirected to the socket stream.

daemon:handle_request(In, Out) :-
  catch(
    read_term(In, Term, [
      max_term_length(100000),
      dotlists(false)
    ]),
    _,
    ( format(Out, '~cEXIT:1~n', [0]),
      flush_output(Out),
      fail )
  ),
  !,
  ( sanitize:safe_daemon_request(Term) ->
    dispatch(Term, In, Out)
  ; format(Out, 'Error: malformed request~n', []),
    format(Out, '~cEXIT:1~n', [0]),
    flush_output(Out)
  ).

daemon:handle_request(_, _).


%! daemon:dispatch(+Term, +In, +Out) is det.
%
% Dispatches a parsed request term.

daemon:dispatch(shutdown, _In, Out) :-
  !,
  format(Out, 'Daemon shutting down~n', []),
  flush_output(Out),
  halt(0).

daemon:dispatch(request(Args, Cols, Rows, Env), _In, Out) :-
  !,
  reset_timer,
  isolate_state(Args, Cols, Rows, Env),
  ExitCode = exit_code(0),
  catch(
    run_with_output(Out, ExitCode),
    Error,
    ( format(Out, 'Error: ~w~n', [Error]),
      nb_setarg(1, ExitCode, 1) )
  ),
  arg(1, ExitCode, Code),
  format(Out, '~cEXIT:~w~n', [0, Code]),
  flush_output(Out).

daemon:dispatch(request(Args, Cols, Rows), In, Out) :-
  !,
  dispatch(request(Args, Cols, Rows, []), In, Out).

daemon:dispatch(_, _In, Out) :-
  format(Out, 'Error: unknown request~n', []),
  format(Out, '~cEXIT:1~n', [0]),
  flush_output(Out).


%! daemon:isolate_state(+Args, +Cols, +Rows, +Env) is det.
%
% Prepares clean state for a new request: clears memoized CLI args
% and per-request preference flags, injects the new arguments,
% applies client environment overrides, and re-initializes preferences.
%
% Client `--mode ipc` is rewritten to `--mode standalone` before argv
% parsing: ipc is only a client transport, while preference/profile
% caches and other mode-keyed config are defined for standalone/daemon.
% Leaving mode=ipc would skip Knowledge/profile.qlf (license groups)
% and Knowledge/preference.qlf, so ACCEPT_LICENSE="@FREE" expands to
% nothing and every package spuriously looks license-masked.

daemon:isolate_state(Args0, Cols, Rows, Env) :-
  retractall(interface:argv_(_,_)),
  retractall(preference:local_flag(_)),
  rewrite_ipc_mode_args(Args0, Args),
  set_prolog_flag(argv, Args),
  interface:argv(_, _),
  retractall(daemon:client_tty_size(_,_)),
  ( integer(Cols), integer(Rows), Cols > 0, Rows > 0
  -> assertz(daemon:client_tty_size(Rows, Cols))
  ;  true
  ),
  retractall(daemon:client_is_tty),
  retractall(console:output_tty_cached(_)),
  retractall(console:powerline_bubbles_cached(_)),
  ( memberchk('_CLIENT_IS_TTY'-true, Env)
  -> assertz(daemon:client_is_tty)
  ;  true
  ),
  apply_client_env(Env).


%! daemon:rewrite_ipc_mode_args(+ArgsIn, -ArgsOut) is det.
%
% Maps client transport mode `ipc` to execution mode `standalone` in
% the raw argv list forwarded over the daemon socket.

daemon:rewrite_ipc_mode_args(ArgsIn, ArgsOut) :-
  ( append(Before, ['--mode', 'ipc'|Rest], ArgsIn)
  -> append(Before, ['--mode', 'standalone'|Rest], ArgsOut)
  ; append(Before, ['--mode=ipc'|Rest], ArgsIn)
  -> append(Before, ['--mode=standalone'|Rest], ArgsOut)
  ; ArgsOut = ArgsIn
  ).


%! daemon:apply_client_env(+Env:list) is det.
%
% Applies client environment overrides for this request and
% re-initializes preferences so USE/ACCEPT_KEYWORDS take effect.

daemon:apply_client_env(Env) :-
  retractall(daemon:client_env(_,_)),
  forall(member(Name-Value, Env),
    assertz(daemon:client_env(Name, Value))),
  retractall(preference:local_env_use(_)),
  retractall(preference:local_use(_)),
  retractall(preference:local_accept_keywords(_)),
  preference:init.

:- dynamic daemon:client_tty_size/2.
:- dynamic daemon:client_is_tty/0.
:- dynamic daemon:client_env/2.
:- dynamic daemon:running/0.


%! daemon:run_with_output(+Out, +ExitCodeTerm) is det.
%
% Runs interface:process_requests(standalone) with current_output
% and current_error redirected to the socket stream Out.

daemon:run_with_output(Out, ExitCodeTerm) :-
  stream_property(OldOut, alias(user_output)),
  stream_property(OldErr, alias(user_error)),
  current_output(OldCurr),
  setup_call_cleanup(
    ( set_stream(Out, alias(user_output)),
      set_stream(Out, alias(user_error)),
      set_output(Out)
    ),
    catch(
      ( daemon:refresh_binpkg_index,
        interface:process_requests(standalone)
      ),
      Error,
      handle_error(Out, Error, ExitCodeTerm)
    ),
    ( set_stream(OldOut, alias(user_output)),
      set_stream(OldErr, alias(user_error)),
      set_output(OldCurr)
    )
  ).


%! daemon:refresh_binpkg_index is det.
%
% Keep the resident binpkg index fresh on a long-lived daemon. The daemon
% holds the parsed `Packages` cache in memory across requests, so without
% this a binpkg dropped by a concurrent producer after startup would stay
% invisible until the daemon restarted. Delegating to
% `binpkg_exec:ensure_index_fresh/0` turns the daemon into a shared binpkg
% index service (portage-ng#80, item D): it is mtime-gated (one cheap stat
% per request, a full re-sync only when `Packages` actually changed) and
% atomic (a concurrent build's `available_for/4` probe never sees an empty
% index during the swap). Runs with output redirected to the client, so
% the one-line "Updated prolog knowledgebase" summary surfaces to the
% requester rather than the daemon console. Always succeeds.

daemon:refresh_binpkg_index :-
  ( current_predicate(binpkg_exec:ensure_index_fresh/0)
  -> message:catch_log('binpkg_exec:ensure_index_fresh', binpkg_exec:ensure_index_fresh)
  ;  true
  ).


%! daemon:handle_error(+Out, +Error, +ExitCodeTerm) is det.
%
% Interprets exceptions thrown during request processing.
% halt/1 throws unwind(halt(Code)) in SWI-Prolog.

daemon:handle_error(_Out, unwind(halt(Code)), ExitCodeTerm) :-
  integer(Code), !,
  nb_setarg(1, ExitCodeTerm, Code).

daemon:handle_error(_Out, halt(Code), ExitCodeTerm) :-
  integer(Code), !,
  nb_setarg(1, ExitCodeTerm, Code).

daemon:handle_error(Out, Error, ExitCodeTerm) :-
  format(Out, 'Daemon error: ~w~n', [Error]),
  nb_setarg(1, ExitCodeTerm, 1).
