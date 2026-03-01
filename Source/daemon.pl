/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> DAEMON
Implements a persistent local daemon for ipc mode. The daemon keeps the
full standalone state (modules + kb.qlf + preferences) resident in memory and
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


:- module(daemon, [
       daemon:start/0,
       daemon:connect/1
   ]).


:- use_module(library(socket)).
:- use_module(library(readutil)).


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
  catch(
    ( atom_string(SocketPath, SP),
      process_create(path(chmod), ['600', SP], []) ),
    _, true),
  tcp_listen(Socket, 5),
  daemon_write_pid(PidPath),
  assertz(daemon:running),
  at_halt(daemon_cleanup(SocketPath, PidPath)),
  current_prolog_flag(pid, Pid),
  format('Daemon started (PID ~w), listening on ~w~n', [Pid, SocketPath]),
  daemon_accept_loop(Socket).


%! daemon_write_pid(+PidPath) is det.
%
% Writes the current process PID to the given file.

daemon_write_pid(PidPath) :-
  current_prolog_flag(pid, Pid),
  setup_call_cleanup(
    open(PidPath, write, S),
    format(S, '~w~n', [Pid]),
    close(S)).


%! daemon_cleanup(+SocketPath, +PidPath) is det.
%
% Removes the socket and PID files on daemon exit.

daemon_cleanup(SocketPath, PidPath) :-
  ( access_file(SocketPath, exist) -> delete_file(SocketPath) ; true ),
  ( access_file(PidPath, exist) -> delete_file(PidPath) ; true ).


:- dynamic daemon:inactivity_alarm/1.

%! daemon_reset_timer is det.
%
% Resets the inactivity timer. If timeout is 0, no timer is set.

daemon_reset_timer :-
  ( retract(daemon:inactivity_alarm(OldAlarm))
  -> catch(remove_alarm(OldAlarm), _, true)
  ;  true
  ),
  config:daemon_inactivity_timeout(Timeout),
  ( Timeout > 0
  -> alarm(Timeout, daemon_inactivity_shutdown, Alarm, []),
     assertz(daemon:inactivity_alarm(Alarm))
  ;  true
  ).


%! daemon_inactivity_shutdown is det.
%
% Called when the inactivity timer fires.

daemon_inactivity_shutdown :-
  format(user_error, 'Daemon shutting down due to inactivity~n', []),
  halt(0).


%! daemon_accept_loop(+Socket) is det.
%
% Main accept loop. Accepts connections one at a time (serialized requests).

daemon_accept_loop(Socket) :-
  daemon_reset_timer,
  tcp_accept(Socket, ClientSocket, _Peer),
  tcp_open_socket(ClientSocket, StreamPair),
  stream_pair(StreamPair, In, Out),
  set_stream(In, encoding(utf8)),
  set_stream(Out, encoding(utf8)),
  ( daemon_handle_request(In, Out)
  -> true
  ;  true
  ),
  catch(close(In), _, true),
  catch(close(Out), _, true),
  daemon_accept_loop(Socket).


%! daemon_handle_request(+In, +Out) is det.
%
% Handles a single request from a client connection.
% Reads the request term, isolates state, runs the request with
% output redirected to the socket stream.

daemon_handle_request(In, Out) :-
  catch(
    read_term(In, Term, []),
    _,
    ( format(Out, '~cEXIT:1~n', [0]),
      flush_output(Out),
      fail )
  ),
  !,
  daemon_dispatch(Term, In, Out).

daemon_handle_request(_, _).


%! daemon_dispatch(+Term, +In, +Out) is det.
%
% Dispatches a parsed request term.

daemon_dispatch(shutdown, _In, Out) :-
  !,
  format(Out, 'Daemon shutting down~n', []),
  flush_output(Out),
  halt(0).

daemon_dispatch(request(Args, Cols, Rows), _In, Out) :-
  !,
  daemon_reset_timer,
  daemon_isolate_state(Args, Cols, Rows),
  ExitCode = exit_code(0),
  catch(
    daemon_run_with_output(Out, ExitCode),
    Error,
    ( format(Out, 'Error: ~w~n', [Error]),
      nb_setarg(1, ExitCode, 1) )
  ),
  arg(1, ExitCode, Code),
  format(Out, '~cEXIT:~w~n', [0, Code]),
  flush_output(Out).

daemon_dispatch(_, _In, Out) :-
  format(Out, 'Error: unknown request~n', []),
  format(Out, '~cEXIT:1~n', [0]),
  flush_output(Out).


%! daemon_isolate_state(+Args, +Cols, +Rows) is det.
%
% Prepares clean state for a new request: clears memoized CLI args
% and per-request preference flags, then injects the new arguments.

daemon_isolate_state(Args, Cols, Rows) :-
  retractall(interface:argv_(_,_)),
  retractall(preference:local_flag(_)),
  set_prolog_flag(argv, Args),
  interface:argv(_, _),
  retractall(daemon:client_tty_size(_,_)),
  ( integer(Cols), integer(Rows), Cols > 0, Rows > 0
  -> assertz(daemon:client_tty_size(Rows, Cols))
  ;  true
  ).

:- dynamic daemon:client_tty_size/2.
:- dynamic daemon:running/0.


%! daemon_run_with_output(+Out, +ExitCodeTerm) is det.
%
% Runs interface:process_requests(standalone) with current_output
% and current_error redirected to the socket stream Out.

daemon_run_with_output(Out, ExitCodeTerm) :-
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
      daemon_handle_error(Out, Error, ExitCodeTerm)
    ),
    ( set_stream(OldOut, alias(user_output)),
      set_stream(OldErr, alias(user_error)),
      set_output(OldCurr)
    )
  ).


%! daemon_handle_error(+Out, +Error, +ExitCodeTerm) is det.
%
% Interprets exceptions thrown during request processing.
% halt/1 throws unwind(halt(Code)) in SWI-Prolog.

daemon_handle_error(_Out, unwind(halt(Code)), ExitCodeTerm) :-
  integer(Code), !,
  nb_setarg(1, ExitCodeTerm, Code).
daemon_handle_error(_Out, halt(Code), ExitCodeTerm) :-
  integer(Code), !,
  nb_setarg(1, ExitCodeTerm, Code).
daemon_handle_error(Out, Error, ExitCodeTerm) :-
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
  -> daemon_no_daemon_error,
     ExitCode = 1
  ;  catch(
       daemon_do_connect(SocketPath, ExitCode),
       _Error,
       ( daemon_no_daemon_error,
         ExitCode = 1 )
     )
  ).


%! daemon_do_connect(+SocketPath, -ExitCode) is det.
%
% Performs the actual connection and I/O with the daemon.

daemon_do_connect(SocketPath, ExitCode) :-
  unix_domain_socket(Socket),
  tcp_connect(Socket, SocketPath),
  tcp_open_socket(Socket, StreamPair),
  stream_pair(StreamPair, In, Out),
  set_stream(Out, encoding(utf8)),
  set_stream(In, encoding(utf8)),
  daemon_send_request(Out),
  flush_output(Out),
  daemon_stream_response(In, ExitCode),
  catch(close(In), _, true),
  catch(close(Out), _, true).


%! daemon_send_request(+Out) is det.
%
% Sends the current CLI arguments and terminal dimensions to the daemon.

daemon_send_request(Out) :-
  current_prolog_flag(argv, RawArgs),
  config:printing_tty_size(Rows, Cols),
  format(Out, 'request(~q, ~w, ~w).~n', [RawArgs, Cols, Rows]).


%! daemon_stream_response(+In, -ExitCode) is det.
%
% Reads the daemon's output byte by byte, writing to current_output,
% until the EXIT terminator is encountered.

daemon_stream_response(In, ExitCode) :-
  read_string(In, _, FullOutput),
  daemon_parse_output(FullOutput, ExitCode).


%! daemon_parse_output(+Output, -ExitCode) is det.
%
% Splits the output at the EXIT terminator, prints the main output,
% and extracts the exit code.

daemon_parse_output(Output, ExitCode) :-
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


%! daemon_no_daemon_error is det.
%
% Prints an error message when no daemon is running.

daemon_no_daemon_error :-
  config:daemon_socket_path(SocketPath),
  format(user_error,
    'Error: No daemon running (socket ~w not found).~n\c
     Start one with: portage-ng --mode daemon~n',
    [SocketPath]).


