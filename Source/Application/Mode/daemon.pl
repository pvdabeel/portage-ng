/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> DAEMON
Implements a persistent local daemon for ipc mode. The daemon keeps the
full standalone state (modules + Knowledge/kb.qlf + preferences) resident in memory and
serves requests over a Unix domain socket.

Two roles:

  - Server (`daemon:start/0`): creates a Unix domain socket, enters an accept
    loop, handles requests by redirecting output to the socket stream, and
    auto-shuts down after a configurable inactivity period.

  - Client (`daemon:connect/1`): connects to the daemon socket, sends CLI
    arguments plus terminal dimensions, streams the output back to stdout,
    and returns the daemon's exit code.

Authentication relies on Unix file permissions (socket created with mode 0600).
Only processes running as the same OS user can connect.

@see config:daemon_socket_path/1
@see config:daemon_pid_path/1
@see config:daemon_inactivity_timeout/1
*/

:- module(daemon, []).

% -----------------------------------------------------------------------------
%  Daemon server
% -----------------------------------------------------------------------------

%! daemon:start is det.
%
% Starts the daemon: creates a Unix domain socket, writes a PID file,
% and enters the accept loop. Registers cleanup for halt.

daemon:start :-
  config:daemon_socket_path(SocketPath),
  config:daemon_pid_path(PidPath),
  ( access_file(SocketPath, exist) -> delete_file(SocketPath) ; true ),
  unix_domain_socket(Socket),
  tcp_bind(Socket, SocketPath),
  atom_string(SocketPath, SP),
  catch(
    ( process_create(path(chmod), ['600', SP], [stdout(null), stderr(null), process(ChPid)]),
      process_wait(ChPid, _)
    ), _, true),
  tcp_listen(Socket, 5),
  write_pid(PidPath),
  assertz(daemon:running),
  at_halt(cleanup(SocketPath, PidPath)),
  current_prolog_flag(pid, Pid),
  format('Daemon started (PID ~w), listening on ~w~n', [Pid, SocketPath]),
  accept_loop(Socket).


%! daemon:write_pid(+PidPath) is det.
%
% Writes the current process PID to the given file.

daemon:write_pid(PidPath) :-
  current_prolog_flag(pid, Pid),
  setup_call_cleanup(
    open(PidPath, write, S),
    format(S, '~w~n', [Pid]),
    close(S)).


%! daemon:cleanup(+SocketPath, +PidPath) is det.
%
% Removes the socket and PID files on daemon exit.

daemon:cleanup(SocketPath, PidPath) :-
  ( access_file(SocketPath, exist) -> delete_file(SocketPath) ; true ),
  ( access_file(PidPath, exist) -> delete_file(PidPath) ; true ).


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

daemon:isolate_state(Args, Cols, Rows, Env) :-
  retractall(interface:argv_(_,_)),
  retractall(preference:local_flag(_)),
  set_prolog_flag(argv, Args),
  interface:argv(_, _),
  retractall(daemon:client_tty_size(_,_)),
  ( integer(Cols), integer(Rows), Cols > 0, Rows > 0
  -> assertz(daemon:client_tty_size(Rows, Cols))
  ;  true
  ),
  retractall(daemon:client_is_tty),
  retractall(config:output_tty_cached(_)),
  ( memberchk('_CLIENT_IS_TTY'-true, Env)
  -> assertz(daemon:client_is_tty)
  ;  true
  ),
  apply_client_env(Env).


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
      interface:process_requests(standalone),
      Error,
      handle_error(Out, Error, ExitCodeTerm)
    ),
    ( set_stream(OldOut, alias(user_output)),
      set_stream(OldErr, alias(user_error)),
      set_output(OldCurr)
    )
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


% -----------------------------------------------------------------------------
%  Daemon client
% -----------------------------------------------------------------------------

%! daemon:connect(-ExitCode) is semidet.
%
% Connects to the daemon, sends the current CLI arguments and terminal
% dimensions, streams the output to current_output, and unifies ExitCode
% with the daemon's exit code. Fails if no daemon is running.

daemon:connect(ExitCode) :-
  config:daemon_socket_path(SocketPath),
  ( \+ access_file(SocketPath, exist)
  -> no_daemon_error,
     ExitCode = 1
  ;  catch(
       do_connect(SocketPath, ExitCode),
       _Error,
       ( no_daemon_error,
         ExitCode = 1 )
     )
  ).


%! daemon:do_connect(+SocketPath, -ExitCode) is det.
%
% Performs the actual connection and I/O with the daemon.

daemon:do_connect(SocketPath, ExitCode) :-
  unix_domain_socket(Socket),
  tcp_connect(Socket, SocketPath),
  tcp_open_socket(Socket, StreamPair),
  stream_pair(StreamPair, In, Out),
  set_stream(Out, encoding(utf8)),
  set_stream(In, encoding(utf8)),
  send_request(Out),
  flush_output(Out),
  stream_response(In, ExitCode),
  catch(close(In), _, true),
  catch(close(Out), _, true).


%! daemon:send_request(+Out) is det.
%
% Sends the current CLI arguments, terminal dimensions, and
% portage-relevant environment variables to the daemon.

daemon:send_request(Out) :-
  current_prolog_flag(argv, RawArgs),
  config:printing_tty_size(Rows, Cols),
  collect_env(Env0),
  ( stream_property(user_output, tty(true))
  -> Env = ['_CLIENT_IS_TTY'-true | Env0]
  ;  Env = Env0
  ),
  format(Out, 'request(~q, ~w, ~w, ~q).~n', [RawArgs, Cols, Rows, Env]).


%! daemon:collect_env(-Env:list) is det.
%
% Collects portage-relevant environment variables that are set in the
% client process, as Name-Value pairs.

daemon:collect_env(Env) :-
  findall(Name-Value,
    ( forwarded_env_var(Name),
      system:getenv(Name, Value)
    ),
    Env).


%! daemon:forwarded_env_var(?Name) is nondet.
%
% Environment variables forwarded from IPC client to daemon.

daemon:forwarded_env_var('USE').
daemon:forwarded_env_var('ACCEPT_KEYWORDS').
daemon:forwarded_env_var('PYTHON_TARGETS').
daemon:forwarded_env_var('PYTHON_SINGLE_TARGET').
daemon:forwarded_env_var('RUBY_TARGETS').
daemon:forwarded_env_var('RUBY_SINGLE_TARGET').
daemon:forwarded_env_var('LUA_SINGLE_TARGET').
daemon:forwarded_env_var('PERL_FEATURES').
daemon:forwarded_env_var('LLVM_SLOT').
daemon:forwarded_env_var('VIDEO_CARDS').
daemon:forwarded_env_var('INPUT_DEVICES').
daemon:forwarded_env_var('CPU_FLAGS_X86').
daemon:forwarded_env_var('APACHE2_MODULES').
daemon:forwarded_env_var('APACHE2_MPMS').


%! daemon:stream_response(+In, -ExitCode) is det.
%
% Reads the daemon's output byte by byte, writing to current_output,
% until the EXIT terminator is encountered.

daemon:stream_response(In, ExitCode) :-
  read_string(In, _, FullOutput),
  parse_output(FullOutput, ExitCode).


%! daemon:parse_output(+Output, -ExitCode) is det.
%
% Splits the output at the EXIT terminator, prints the main output,
% and extracts the exit code.

daemon:parse_output(Output, ExitCode) :-
  atom_codes(Sentinel, [0, 0'E, 0'X, 0'I, 0'T, 0':]),
  ( sub_string(Output, Before, _, _, Sentinel)
  -> sub_string(Output, 0, Before, _, MainOutput),
     write(MainOutput),
     flush_output,
     SentLen = 6,
     TermStart is Before + SentLen,
     sub_string(Output, TermStart, _, 0, Tail),
     ( sub_string(Tail, NL, _, _, "\n")
     -> sub_string(Tail, 0, NL, _, CodeStr)
     ;  CodeStr = Tail
     ),
     ( number_string(ExitCode, CodeStr) -> true ; ExitCode = 1 )
  ;  write(Output),
     flush_output,
     ExitCode = 0
  ).


%! daemon:no_daemon_error is det.
%
% Prints an error message when no daemon is running.

daemon:no_daemon_error :-
  config:daemon_socket_path(SocketPath),
  format(user_error,
    'Error: No daemon running (socket ~w not found).~n\c
     Start one with: portage-ng --mode daemon~n',
    [SocketPath]).


% -----------------------------------------------------------------------------
%  Lifecycle management
% -----------------------------------------------------------------------------

%! daemon:fork_background(+Mode) is det.
%
% Forks a new detached swipl process running the given Mode (daemon or
% server) without --background. The parent polls for readiness then exits.

daemon:fork_background(Mode) :-
  config:installation_dir(Dir),
  atomic_list_concat([Dir, '/portage-ng.pl'], MainFile),
  atom_concat('portage=', Dir, PortagePath),
  process_create(
    path(swipl),
    [ '-O',
      '--stack-limit=256G', '--table-space=256G', '--shared-table-space=256G',
      '-f', MainFile,
      '-p', PortagePath,
      '-Dverbose_autoload=false',
      '-g', 'main',
      '--',
      '--mode', Mode
    ],
    [ process(Pid),
      detached(true),
      stdout(null),
      stderr(null)
    ]
  ),
  atom_string(Mode, ModeStr),
  format('Starting ~w in background (PID ~w)...~n', [ModeStr, Pid]),
  ( Mode == daemon
  -> config:daemon_pid_path(PidPath),
     wait_for_file(PidPath, 100),
     ( exists_file(PidPath)
     -> format('Daemon ready (PID ~w).~n', [Pid])
     ;  format(user_error, 'Warning: daemon may not have started.~n', [])
     )
  ;  sleep(2),
     format('Server started in background (PID ~w).~n', [Pid])
  ).


%! daemon:wait_for_file(+Path, +Retries) is det.
%
% Polls for a file to appear, sleeping 100ms between retries.

daemon:wait_for_file(_, 0) :- !.
daemon:wait_for_file(Path, N) :-
  ( access_file(Path, exist)
  -> true
  ;  sleep(0.1),
     N1 is N - 1,
     wait_for_file(Path, N1)
  ).


%! daemon:status is semidet.
%
% Checks if a daemon is running. Prints PID if running, error if not.
% Succeeds if daemon is running, fails otherwise.

daemon:status :-
  config:daemon_socket_path(SocketPath),
  config:daemon_pid_path(PidPath),
  ( access_file(SocketPath, exist)
  -> ( exists_file(PidPath)
     -> setup_call_cleanup(
          open(PidPath, read, S),
          read_string(S, _, PidStr),
          close(S)),
        normalize_space(atom(Pid), PidStr),
        format('Daemon running (PID ~w, socket ~w)~n', [Pid, SocketPath])
     ;  format('Daemon socket exists (~w) but no PID file.~n', [SocketPath])
     )
  ;  format('No daemon running.~n', []),
     fail
  ).


%! daemon:send_command(+Cmd) is det.
%
% Sends a command term to the daemon over the Unix socket.
% Cmd is one of: halt, relaunch.

daemon:send_command(halt) :-
  !,
  config:daemon_socket_path(SocketPath),
  ( \+ access_file(SocketPath, exist)
  -> format(user_error, 'No daemon running.~n', [])
  ;  send_term(SocketPath, shutdown),
     format('Daemon stopped.~n', [])
  ).

daemon:send_command(relaunch) :-
  !,
  daemon:send_command(halt),
  sleep(1),
  config:daemon_socket_path(SocketPath),
  wait_for_socket_gone(SocketPath, 50),
  daemon:fork_background(daemon).

daemon:send_command(Cmd) :-
  format(user_error, 'Unknown command: ~w. Use halt or relaunch.~n', [Cmd]).


%! daemon:autostart is det.
%
% If no daemon socket exists and autostart is configured, fork a
% background daemon. Otherwise succeed silently.

daemon:autostart :-
  config:daemon_socket_path(SocketPath),
  \+ access_file(SocketPath, exist),
  config:daemon_autostart(true),
  !,
  daemon:fork_background(daemon).
daemon:autostart.


%! daemon:relaunch is det.
%
% Convenience: stops the current daemon and starts a new one in background.

daemon:relaunch :-
  daemon:send_command(relaunch).


%! daemon:send_term(+SocketPath, +Term) is det.
%
% Connects to the daemon socket and sends a Prolog term.

daemon:send_term(SocketPath, Term) :-
  catch(
    ( unix_domain_socket(Socket),
      tcp_connect(Socket, SocketPath),
      tcp_open_socket(Socket, StreamPair),
      stream_pair(StreamPair, In, Out),
      set_stream(Out, encoding(utf8)),
      set_stream(In, encoding(utf8)),
      format(Out, '~q.~n', [Term]),
      flush_output(Out),
      catch(read_string(In, _, _Response), _, true),
      catch(close(In), _, true),
      catch(close(Out), _, true)
    ),
    Error,
    format(user_error, 'Connection error: ~w~n', [Error])
  ).


%! daemon:wait_for_socket_gone(+Path, +Retries) is det.
%
% Polls until the socket file disappears, sleeping 100ms between retries.

daemon:wait_for_socket_gone(_, 0) :- !.
daemon:wait_for_socket_gone(Path, N) :-
  ( \+ access_file(Path, exist)
  -> true
  ;  sleep(0.1),
     N1 is N - 1,
     wait_for_socket_gone(Path, N1)
  ).