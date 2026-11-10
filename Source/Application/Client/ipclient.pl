/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> IPCLIENT
Talk to a running portage-ng daemon over its Unix-domain socket.

This is the client side of the daemon protocol. The wrapper loads this
file on its own for `--mode ipc` (swipl -q -F none --no-packs -f ipclient.pl
-g ipclient:main), so that sending a request costs no more than loading
library(socket) and library(uid): neither portage-ng.pl nor the knowledge base
is loaded in this process. library(process) is loaded only when the daemon has
to be started or relaunched, which happens in a child process running
`portage-ng-dev --mode daemon --background`. Source/Application/Mode/ipc.pl
reuses the connect, status and halt predicates from here when the full
application is loaded.

main/0 is not exported on purpose: an exported main/0 would be imported
into user when this file is loaded as part of the full application and
clash with user:main/0 there. Callers name it as ipclient:main.
*/

:- module(ipclient,
          [ connect/1,
            status/0,
            send_command/1,
            send_term/2,
            maybe_autostart/0,
            relaunch/0,
            socket_path/1,
            pid_path/1,
            socket_connectable/1,
            wait_for_file/2,
            wait_for_socket_gone/2
          ]).

:- use_module(library(socket)).
:- use_module('../System/runtimepath', []).

% =============================================================================
%  IPCLIENT declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Entry
% -----------------------------------------------------------------------------

%! ipclient:main is det.
%
% Dispatches --status / --cmd / --shell, otherwise connects directly on the
% fast path (autostarting the daemon only when the initial connect fails) and
% streams one request. Always halts.

ipclient:main :-
  current_prolog_flag(argv, Args),
  ( memberchk('--shell', Args)
  -> format(user_error,
       'Error: --shell is not supported in ipc mode. Use --mode standalone --shell instead.~n',
       []),
     halt(1)
  ;  memberchk('--status', Args)
  -> ( status -> halt(0) ; halt(1) )
  ;  cmd_arg(Args, Cmd)
  -> send_command(Cmd),
     halt(0)
  ;  connect_with_autostart(ExitCode),
     halt(ExitCode)
  ).


%! ipclient:cmd_arg(+Args, -Cmd) is semidet.
%
% True when Args contains `--cmd Cmd` or `--cmd=Cmd`.

ipclient:cmd_arg(['--cmd', Cmd|_], Cmd) :- !.
ipclient:cmd_arg([Arg|Rest], Cmd) :-
  ( sub_atom(Arg, 0, 6, _, '--cmd=')
  -> sub_atom(Arg, 6, _, 0, Cmd)
  ;  cmd_arg(Rest, Cmd)
  ).


% -----------------------------------------------------------------------------
%  Paths (mirrors config:daemon_* without loading config.pl)
% -----------------------------------------------------------------------------

%! ipclient:runtime_dir(-Dir) is det.

ipclient:runtime_dir(Dir) :-
  runtimepath:daemon_runtime_dir(Dir).


%! ipclient:socket_path(-Path) is det.

ipclient:socket_path(Path) :-
  runtime_dir(Dir),
  atom_concat(Dir, '/portage-ng.sock', Path).


%! ipclient:pid_path(-Path) is det.

ipclient:pid_path(Path) :-
  runtime_dir(Dir),
  atom_concat(Dir, '/portage-ng.pid', Path).


%! ipclient:socket_connectable(+Path) is semidet.

ipclient:socket_connectable(Path) :-
  catch(
    setup_call_cleanup(
      unix_domain_socket(Socket),
      tcp_connect(Socket, Path),
      tcp_close_socket(Socket)),
    _,
    fail).


%! ipclient:autostart_enabled is semidet.
%
% Same default as config:daemon_autostart(true). Override with
% PORTAGE_NG_IPC_AUTOSTART=0|false (checked only when connect fails).

ipclient:autostart_enabled :-
  ( getenv('PORTAGE_NG_IPC_AUTOSTART', V)
  -> V \== '0', V \== 'false'
  ;  true
  ).


%! ipclient:daemon_wrapper(-Wrapper) is semidet.
%
% Absolute path to portage-ng-dev, the wrapper used to start or relaunch
% the daemon in a child process.

ipclient:daemon_wrapper(Wrapper) :-
  getenv('PORTAGE_NG_DEV', W),
  !,
  exists_file(W),
  Wrapper = W.
ipclient:daemon_wrapper(Wrapper) :-
  source_file(ipclient:main, File),
  file_directory_name(File, Dir),
  atomic_list_concat([Dir, '/../Wrapper/portage-ng-dev'], Rel),
  absolute_file_name(Rel, Wrapper, [access(exist)]).


% -----------------------------------------------------------------------------
%  Connect + request
% -----------------------------------------------------------------------------

%! ipclient:connect_with_autostart(-ExitCode) is det.
%
% Attempts a single Unix-socket connect immediately; falls back to background
% daemon autostart only when no live listener accepts the connection.

ipclient:connect_with_autostart(ExitCode) :-
  socket_path(SocketPath),
  ( try_connect_socket(SocketPath, In, Out)
  -> exchange(In, Out, ExitCode)
  ;  autostart_enabled
  -> start_daemon_background,
     connect_at(SocketPath, ExitCode)
  ;  no_daemon_error(SocketPath),
     ExitCode = 1
  ).


%! ipclient:connect(-ExitCode) is det.

ipclient:connect(ExitCode) :-
  socket_path(SocketPath),
  connect_at(SocketPath, ExitCode).


%! ipclient:connect_at(+SocketPath, -ExitCode) is det.

ipclient:connect_at(SocketPath, ExitCode) :-
  ( try_connect_socket(SocketPath, In, Out)
  -> exchange(In, Out, ExitCode)
  ;  no_daemon_error(SocketPath),
     ExitCode = 1
  ).


%! ipclient:try_connect_socket(+SocketPath, -In, -Out) is semidet.
%
% Opens a Unix-domain connection to SocketPath with a 64 KB input buffer.
% Closes the raw socket descriptor cleanly if tcp_connect/2 fails.

ipclient:try_connect_socket(SocketPath, In, Out) :-
  unix_domain_socket(Socket),
  catch(
    ( tcp_connect(Socket, SocketPath),
      tcp_open_socket(Socket, StreamPair)
    ),
    _,
    ( catch(tcp_close_socket(Socket), _, true),
      fail )
  ),
  stream_pair(StreamPair, In, Out),
  set_stream(Out, encoding(utf8)),
  set_stream(In, buffer_size(65536)).


%! ipclient:exchange(+In, +Out, -ExitCode) is det.

ipclient:exchange(In, Out, ExitCode) :-
  catch(
    ( send_request(Out),
      flush_output(Out),
      stream_response(In, ExitCode)
    ),
    Error,
    ( flush_output,
      print_message(error, Error),
      ExitCode = 1 )
  ),
  catch(close(In), _, true),
  catch(close(Out), _, true).


%! ipclient:send_request(+Out) is det.
%
% Encodes `request(Args, Cols, Rows, Env).` onto Out. Checks tty(true) before
% tty_size/2 so non-interactive runs never construct and catch an exception.

ipclient:send_request(Out) :-
  current_prolog_flag(argv, RawArgs),
  collect_env(Env0),
  ( stream_property(user_output, tty(true))
  -> local_tty_size(Rows, Cols),
     Env = ['_CLIENT_IS_TTY'-true | Env0]
  ;  Rows = 80,
     Cols = 160,
     Env = Env0
  ),
  format(Out, 'request(~q, ~w, ~w, ~q).~n', [RawArgs, Cols, Rows, Env]).


%! ipclient:local_tty_size(-Rows, -Cols) is det.
%
% Same defaults as console:local_tty_size/2 (80 rows, 160 cols when not a tty).

ipclient:local_tty_size(Rows, Cols) :-
  ( catch(tty_size(Rows, Cols), _, fail)
  -> true
  ;  Rows = 80,
     Cols = 160
  ).


%! ipclient:collect_env(-Env) is det.

ipclient:collect_env(Env) :-
  forwarded_env_vars(Names),
  collect_env_pairs(Names, Env).


%! ipclient:collect_env_pairs(+Names, -Env) is det.

ipclient:collect_env_pairs([], []).
ipclient:collect_env_pairs([Name|Rest], Env) :-
  ( getenv(Name, Value)
  -> Env = [Name-Value|More]
  ;  Env = More
  ),
  collect_env_pairs(Rest, More).


%! ipclient:forwarded_env_vars(-Names) is det.

ipclient:forwarded_env_vars(
  [ 'USE',
    'ACCEPT_KEYWORDS',
    'ACCEPT_LICENSE',
    'PYTHON_TARGETS',
    'PYTHON_SINGLE_TARGET',
    'RUBY_TARGETS',
    'RUBY_SINGLE_TARGET',
    'LUA_SINGLE_TARGET',
    'PERL_FEATURES',
    'LLVM_SLOT',
    'VIDEO_CARDS',
    'INPUT_DEVICES',
    'CPU_FLAGS_X86',
    'APACHE2_MODULES',
    'APACHE2_MPMS'
  ]).


%! ipclient:forwarded_env_var(?Name) is nondet.

ipclient:forwarded_env_var(Name) :-
  forwarded_env_vars(Names),
  member(Name, Names).


% -----------------------------------------------------------------------------
%  Stream response (NUL EXIT:<code> sentinel)
% -----------------------------------------------------------------------------

%! ipclient:stream_response(+In, -ExitCode) is det.
%
% Streams daemon output to current_output until a NUL-prefixed `EXIT:<code>\n`
% sentinel. Switches OS streams to octet encoding so bytes pass through C
% buffers without UTF-8 decode/re-encode; falls back to UTF-8 on in-memory
% capture streams (such as with_output_to/2 in unit tests).

ipclient:stream_response(In, ExitCode) :-
  current_output(Out),
  ( stream_property(Out, encoding(OrigEnc)),
    catch(set_stream(Out, encoding(octet)), _, fail)
  -> set_stream(In, encoding(octet)),
     stream_segments(In, Out, ExitCode),
     flush_output(Out),
     catch(set_stream(Out, encoding(OrigEnc)), _, true)
  ;  set_stream(In, encoding(utf8)),
     stream_segments(In, Out, ExitCode),
     flush_output(Out)
  ).


%! ipclient:stream_segments(+In, +Out, -ExitCode) is det.
%
% C-level delimiter scan up to LF, CR, or NUL without cons-cell list allocation.
% Guards leading NUL / EOF with peek_code/2 first so a NUL sentinel immediately
% following a newline (or at byte 0) never enters read_string/5 as a leading NUL.

ipclient:stream_segments(In, Out, ExitCode) :-
  peek_code(In, First),
  stream_peeked(First, In, Out, ExitCode).


%! ipclient:stream_peeked(+First, +In, +Out, -ExitCode) is det.

ipclient:stream_peeked(-1, _In, Out, 1) :-
  !,
  flush_output(Out),
  connection_lost_error.
ipclient:stream_peeked(0, In, Out, ExitCode) :-
  !,
  get_code(In, _),
  stream_after_nul(In, Out, ExitCode).
ipclient:stream_peeked(_, In, Out, ExitCode) :-
  read_string(In, "\n\r\x00\", "", Sep, Part),
  ( Part == "" -> true ; write(Out, Part) ),
  stream_after_sep(Sep, In, Out, ExitCode).


%! ipclient:stream_after_sep(+Sep, +In, +Out, -ExitCode) is det.

ipclient:stream_after_sep(10, In, Out, ExitCode) :-
  !,
  put_code(Out, 10),
  stream_segments(In, Out, ExitCode).
ipclient:stream_after_sep(13, In, Out, ExitCode) :-
  !,
  put_code(Out, 13),
  flush_output(Out),
  stream_segments(In, Out, ExitCode).
ipclient:stream_after_sep(0, In, Out, ExitCode) :-
  !,
  stream_after_nul(In, Out, ExitCode).
ipclient:stream_after_sep(-1, _In, Out, 1) :-
  flush_output(Out),
  connection_lost_error.


%! ipclient:stream_after_nul(+In, +Out, -ExitCode) is det.

ipclient:stream_after_nul(In, Out, ExitCode) :-
  peek_string(In, 5, Peek),
  ( Peek == "EXIT:"
  -> read_string(In, 5, _),
     collect_exit_code(In, ExitCode)
  ;  put_code(Out, 0),
     stream_segments(In, Out, ExitCode)
  ).


%! ipclient:collect_exit_code(+In, -ExitCode) is det.

ipclient:collect_exit_code(In, ExitCode) :-
  read_string(In, "\n\r", "", _, CodeStr),
  parse_exit_code(CodeStr, ExitCode).


%! ipclient:parse_exit_code(+Text, -ExitCode) is det.

ipclient:parse_exit_code(Text, ExitCode) :-
  ( catch(number_string(Number, Text), _, fail),
    integer(Number)
  -> ExitCode = Number
  ;  ExitCode = 1
  ).


%! ipclient:no_daemon_error(+SocketPath) is det.

ipclient:no_daemon_error(SocketPath) :-
  format(user_error,
    'Error: No daemon running (socket ~w not found).~n\c
     Start one with: portage-ng --mode daemon~n',
    [SocketPath]).


%! ipclient:connection_lost_error is det.

ipclient:connection_lost_error :-
  format(user_error,
    'Error: daemon closed the connection without an exit status.~n', []).


% -----------------------------------------------------------------------------
%  Status / commands / autostart
% -----------------------------------------------------------------------------

%! ipclient:status is semidet.

ipclient:status :-
  socket_path(SocketPath),
  pid_path(PidPath),
  ( access_file(SocketPath, exist)
  -> ( exists_file(PidPath)
     -> setup_call_cleanup(
          open(PidPath, read, S),
          read_string(S, _, PidStr),
          close(S)),
        split_string(PidStr, "", " \t\r\n", [Pid|_]),
        format('Daemon running (PID ~s, socket ~w)~n', [Pid, SocketPath])
     ;  format('Daemon socket exists (~w) but no PID file.~n', [SocketPath])
     )
  ;  format('No daemon running.~n', []),
     fail
  ).


%! ipclient:send_command(+Cmd) is det.
%
% Cmd is halt or relaunch (atoms or strings).

ipclient:send_command(Cmd0) :-
  to_cmd_atom(Cmd0, Cmd),
  send_command_(Cmd).


%! ipclient:to_cmd_atom(+Cmd0, -Cmd) is det.

ipclient:to_cmd_atom(Cmd, Cmd) :-
  atom(Cmd), !.
ipclient:to_cmd_atom(Cmd0, Cmd) :-
  atom_string(Cmd, Cmd0).


%! ipclient:send_command_(+Cmd) is det.

ipclient:send_command_(halt) :-
  !,
  socket_path(SocketPath),
  ( \+ access_file(SocketPath, exist)
  -> format(user_error, 'No daemon running.~n', [])
  ;  send_term(SocketPath, shutdown),
     format('Daemon stopped.~n', [])
  ).
ipclient:send_command_(relaunch) :-
  !,
  relaunch.
ipclient:send_command_(Cmd) :-
  format(user_error, 'Unknown command: ~w. Use halt or relaunch.~n', [Cmd]).


%! ipclient:relaunch is det.
%
% Stops the daemon and starts a new one as soon as the socket disappears.

ipclient:relaunch :-
  send_command_(halt),
  socket_path(SocketPath),
  wait_for_socket_gone(SocketPath, 600),
  start_daemon_background.


%! ipclient:send_term(+SocketPath, +Term) is det.

ipclient:send_term(SocketPath, Term) :-
  catch(
    ( unix_domain_socket(Socket),
      catch(
        ( tcp_connect(Socket, SocketPath),
          tcp_open_socket(Socket, StreamPair)
        ),
        ConnectErr,
        ( catch(tcp_close_socket(Socket), _, true),
          throw(ConnectErr) )
      ),
      stream_pair(StreamPair, In, Out),
      set_stream(Out, encoding(utf8)),
      set_stream(In, encoding(utf8)),
      format(Out, '~q.~n', [Term]),
      flush_output(Out),
      catch(read_string(In, _, _), _, true),
      catch(close(In), _, true),
      catch(close(Out), _, true)
    ),
    Error,
    format(user_error, 'Connection error: ~w~n', [Error])
  ).


%! ipclient:maybe_autostart is det.
%
% Starts a daemon in a child process when no daemon socket accepts a
% connection and autostart is enabled. When the daemon is up nothing is loaded.

ipclient:maybe_autostart :-
  socket_path(SocketPath),
  \+ socket_connectable(SocketPath),
  autostart_enabled,
  !,
  start_daemon_background.
ipclient:maybe_autostart.


%! ipclient:ensure_process_lib is det.
%
% Loads library(process) the first time the daemon has to be started or
% relaunched; use_module/1 does nothing when it is already loaded.

ipclient:ensure_process_lib :-
  use_module(library(process)).


%! ipclient:start_daemon_background is det.
%
% Starts the daemon with portage-ng-dev --mode daemon --background and
% waits for its socket to appear. The knowledge base is loaded by that
% child, not by this process.

ipclient:start_daemon_background :-
  ensure_process_lib,
  ( daemon_wrapper(Wrapper)
  -> true
  ;  format(user_error,
       'Error: cannot locate portage-ng-dev to start the daemon.~n\c
        Set PORTAGE_NG_DEV or start one with: portage-ng --mode daemon~n',
       []),
     halt(1)
  ),
  % stdout/stderr must be null (not pipes): the --background child prints
  % status while we wait on process_wait/2; piping both invites deadlock
  % when the pipe buffer fills before we drain.
  format('Starting daemon in background...~n', []),
  process_create(Wrapper, ['--mode', 'daemon', '--background'],
    [ process(Pid),
      stdout(null),
      stderr(null)
    ]),
  process_wait(Pid, Status),
  ( Status == exit(0)
  -> socket_path(SocketPath),
     wait_for_file(SocketPath, 6000),
     ( access_file(SocketPath, exist)
     -> format('Daemon ready.~n', [])
     ;  format(user_error, 'Warning: daemon may not have started.~n', [])
     )
  ;  format(user_error, 'Error: failed to start daemon (~w).~n', [Status]),
     halt(1)
  ).


%! ipclient:wait_for_file(+Path, +Retries) is det.

ipclient:wait_for_file(_, 0) :- !.
ipclient:wait_for_file(Path, N) :-
  ( access_file(Path, exist)
  -> true
  ;  sleep(0.01),
     N1 is N - 1,
     wait_for_file(Path, N1)
  ).


%! ipclient:wait_for_socket_gone(+Path, +Retries) is det.

ipclient:wait_for_socket_gone(_, 0) :- !.
ipclient:wait_for_socket_gone(Path, N) :-
  ( \+ access_file(Path, exist)
  -> true
  ;  sleep(0.01),
     N1 is N - 1,
     wait_for_socket_gone(Path, N1)
  ).