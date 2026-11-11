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

A request is one term on one line, `request(Args, Cols, Rows, Env).`: the
command-line words, the size of the terminal, and the environment variables
the daemon has to know about. The daemon answers with the output of the
command as UTF-8 text and closes with a NUL byte followed by the line
`EXIT:<code>`. The client copies the output and halts with that code.

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
            wait_for_daemon/2,
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
% Handles --status, --cmd and --shell itself. Anything else is sent to the
% daemon as one request, and a daemon is started first when none answers.
% Always halts.

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
% PORTAGE_NG_IPC_AUTOSTART=0|false (looked at only when no daemon answers).

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
% Sends the request of this process to the daemon and gives its exit code.
% The connection is simply tried, without looking at the socket file
% first: a daemon is nearly always running, and then the look would be
% wasted. Only when nobody answers, and autostart is enabled, is a daemon
% started and the connection tried a second time. Without a daemon the
% exit code is 1.

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
%
% Sends the request of this process to the daemon and gives its exit code.
% Does not start a daemon: when none answers, an error is printed and the
% exit code is 1.

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
% Connects to the daemon listening on SocketPath; In and Out are the two
% streams of the connection. Fails, after closing the socket again, when
% nobody is listening. The input stream gets a 64 KB buffer, so that a long
% answer is read in few system calls.

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
%
% Sends the request, copies the answer to the current output and closes
% the connection. An error on the way is printed and gives exit code 1.

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
% Writes the request term `request(Args, Cols, Rows, Env).` to Out. When
% standard output is a terminal its size is sent, and `_CLIENT_IS_TTY` is
% added to Env so the daemon formats its output for a terminal. Otherwise
% the size is 80 rows by 160 columns and the terminal is not asked.

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
%
% Env holds a Name-Value pair for each variable of forwarded_env_vars/1
% that is set in the environment of this process.

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
%
% The environment variables that change what portage-ng computes. They are
% sent with every request because the daemon has its own environment, not
% that of the client. The same list is in ipcclient.cpp.

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
% Copies the answer of the daemon to the current output, up to the closing
% NUL and `EXIT:<code>` line, and gives that code. When the connection ends
% before the closing line, an error is printed and the code is 1.
%
% The answer is UTF-8 text and is passed on byte for byte: both streams are
% set to carry plain bytes while the answer is copied, so nothing is
% decoded and encoded again on the way, and the output gets its own
% encoding back afterwards. The answer is therefore not converted to the
% encoding of the locale; the C++ client passes the bytes on in the same
% way. An output stream that cannot carry plain bytes, such as the one
% with_output_to/2 creates, receives the answer as decoded text instead.

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
% Copies the answer piece by piece. A piece runs up to the next line feed,
% carriage return or NUL. read_string/5 finds that end and returns the
% piece as one string, so the text is never taken apart into a list of
% character codes.
%
% The first character of each piece is looked at before read_string/5 is
% called. read_string/5 drops NUL characters at the start of what it reads
% without reporting them, and the closing NUL normally comes right after a
% line feed, that is, at the start of a piece. Without this look the end of
% the answer would be missed.
%
% Neither that behaviour nor the use of NUL as an end character is
% documented for read_string/5; both were found by testing. The daemon unit
% test sends an answer with a NUL in the middle of a line and one right
% after a line feed, so a change in SWI-Prolog that breaks this loop shows
% up there.

ipclient:stream_segments(In, Out, ExitCode) :-
  peek_code(In, First),
  stream_peeked(First, In, Out, ExitCode).


%! ipclient:stream_peeked(+First, +In, +Out, -ExitCode) is det.
%
% First is the next character of the answer, not yet read. End of input
% means the daemon went away without the closing line. A NUL is read here
% and may start the closing line. Any other character starts a piece of
% output, which is read and written.

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
%
% Sep is the character that ended a piece. A line feed or carriage return
% is passed on. After a carriage return the output is flushed, so that a
% progress line that rewrites itself is shown at once. A NUL may start the
% closing line. End of input means the daemon went away.

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
%
% Called when a NUL has been read. When `EXIT:` follows, the rest of the
% line is the exit code and the answer is complete. Otherwise the NUL was
% part of the output and is passed on.

ipclient:stream_after_nul(In, Out, ExitCode) :-
  peek_string(In, 5, Peek),
  ( Peek == "EXIT:"
  -> read_string(In, 5, _),
     collect_exit_code(In, ExitCode)
  ;  put_code(Out, 0),
     stream_segments(In, Out, ExitCode)
  ).


%! ipclient:collect_exit_code(+In, -ExitCode) is det.
%
% Reads the rest of the closing line and gives the exit code on it.

ipclient:collect_exit_code(In, ExitCode) :-
  read_string(In, "\n\r", "", _, CodeStr),
  parse_exit_code(CodeStr, ExitCode).


%! ipclient:parse_exit_code(+Text, -ExitCode) is det.
%
% ExitCode is the whole number written in Text, or 1 when Text is not a
% whole number.

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
% Stops the daemon, waits until its socket file is gone (six seconds at
% most) and starts a new one.

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
% waits, for at most a minute, until it accepts connections. The knowledge
% base is loaded by that child, not by this process.

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
     ( wait_for_daemon(SocketPath, 6000)
     -> format('Daemon ready.~n', [])
     ;  format(user_error, 'Warning: daemon may not have started.~n', [])
     )
  ;  format(user_error, 'Error: failed to start daemon (~w).~n', [Status]),
     halt(1)
  ).


%! ipclient:wait_for_daemon(+SocketPath, +Retries) is semidet.
%
% True as soon as a daemon accepts a connection on SocketPath. Tries
% Retries times, 10 ms apart, and fails when no daemon has answered by
% then. The test is a connection and not the presence of the socket file:
% a daemon that was killed leaves its socket file behind, and a file that
% nobody listens on must not be taken for a daemon that is ready.

ipclient:wait_for_daemon(SocketPath, _) :-
  socket_connectable(SocketPath),
  !.
ipclient:wait_for_daemon(SocketPath, N) :-
  N > 1,
  sleep(0.01),
  N1 is N - 1,
  wait_for_daemon(SocketPath, N1).


%! ipclient:wait_for_socket_gone(+Path, +Retries) is det.

ipclient:wait_for_socket_gone(_, 0) :- !.
ipclient:wait_for_socket_gone(Path, N) :-
  ( \+ access_file(Path, exist)
  -> true
  ;  sleep(0.01),
     N1 is N - 1,
     wait_for_socket_gone(Path, N1)
  ).