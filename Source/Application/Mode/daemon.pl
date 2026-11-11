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
  tcp_listen(Socket, 64),
  write_pid(PidPath),
  retractall(daemon:running),
  assertz(daemon:running),
  daemon:seed_pref_sig,
  at_halt(cleanup(SocketPath, PidPath)),
  current_prolog_flag(pid, Pid),
  format('Daemon started (PID ~w), listening on ~w~n', [Pid, SocketPath]),
  call_cleanup(
    accept_loop(Socket),
    catch(tcp_close_socket(Socket), _, true)).


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
  setup_call_cleanup(
    ( set_stream(In, encoding(utf8)),
      set_stream(Out, encoding(utf8))
    ),
    ( catch(handle_request(In, Out),
            error(Formal, Context),
            accept_loop_error(error(Formal, Context)))
    -> true
    ;  true
    ),
    ( catch(close(In), _, true),
      catch(close(Out), _, true)
    )),
  accept_loop(Socket).


%! daemon:accept_loop_error(+Error) is det.
%
% Decides what an error that escaped from one connection means for the
% daemon. An I/O or socket error means the client went away before its
% answer was written; that is ordinary and the daemon moves on to the
% next connection without a word. Any other error is a fault in the
% daemon: it is reported as a warning on the daemon's own output, once,
% and the daemon keeps serving.
%
% The accept loop only catches error(_, _) terms. A halt or an abort is
% not one and is not caught, so a shutdown request or the inactivity
% timer still ends the loop.

daemon:accept_loop_error(error(Formal, _)) :-
  daemon:client_gone_error(Formal),
  !.
daemon:accept_loop_error(Err) :-
  message:catch_log_report('daemon request', Err).


%! daemon:client_gone_error(+Formal) is semidet.
%
% True for the errors a write to, or a read from, a closed connection
% produces.

daemon:client_gone_error(io_error(_, _)).
daemon:client_gone_error(socket_error(_, _)).


%! daemon:handle_request(+In, +Out) is det.
%
% Handles a single request from a client connection.
% Reads the request term, isolates state, runs the request with
% output redirected to the socket stream. Silent on immediate EOF
% (e.g. a liveness probe closing without sending a request).

daemon:handle_request(In, Out) :-
  catch(
    read_term(In, Term, [
      max_term_length(100000),
      dotlists(false)
    ]),
    _,
    ( catch((format(Out, '~cEXIT:1~n', [0]), flush_output(Out)), _, true),
      fail )
  ),
  !,
  ( Term == end_of_file ->
    true
  ; sanitize:safe_daemon_request(Term) ->
    dispatch(Term, In, Out)
  ; catch(
      ( format(Out, 'Error: malformed request~n', []),
        format(Out, '~cEXIT:1~n', [0]),
        flush_output(Out)
      ),
      _,
      true)
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
  ExitCode = exit_code(0),
  catch(
    run_with_output(Out, request(Args, Cols, Rows, Env), ExitCode),
    Error,
    ( format(Out, 'Error: ~w~n', [Error]),
      nb_setarg(1, ExitCode, 1) )
  ),
  maybe_invalidate_pref_sig(Args),
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
%
% The arguments are parsed first and nothing else is touched until that
% has succeeded. A command line that cannot be parsed throws from here
% and leaves the state of the previous request in place, so the daemon
% is never left holding arguments it cannot read.

daemon:isolate_state(Args0, Cols, Rows, Env) :-
  rewrite_ipc_mode_args(Args0, Args),
  interface:load_argv(Args),
  set_prolog_flag(argv, Args),
  retractall(preference:local_flag(_)),
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
% Makes the environment variables the client sent the ones this request
% sees (interface:getenv/2 looks at daemon:client_env/2 first), and brings
% the preferences up to date: USE flags, accepted keywords and licenses,
% masks, sets and the world file.
%
% Building the preferences takes longer than answering a small request, so
% they are rebuilt only when something they are built from has changed.
% That is decided by comparing a signature of those inputs with the
% signature taken when the preferences were last built; see
% daemon:current_pref_sig/2. When the two are equal the preferences in
% memory are kept. That is safe because a request does not change them.
% The only preference facts a request writes are the
% preference:local_flag/1 facts of its own command line, and
% daemon:isolate_state/4 clears those for every request.
%
% The signature is used only when the preference cache is enabled for the
% mode of the request (config:preference_cache/2). With the cache disabled
% the configuration asks for the files to be read every time, and then
% they are read for every request.

daemon:apply_client_env(Env) :-
  retractall(daemon:client_env(_,_)),
  forall(member(Name-Value, Env),
    assertz(daemon:client_env(Name, Value))),
  ( preference:cache_enabled,
    daemon:current_pref_sig(Env, Sig),
    daemon:active_pref_sig(PrevSig),
    PrevSig =@= Sig
  -> true
  ;  retractall(daemon:active_pref_sig(_)),
     retractall(preference:local_env_use(_)),
     retractall(preference:local_use(_)),
     retractall(preference:local_accept_keywords(_)),
     preference:init,
     ( daemon:current_pref_sig(Env, NewSig)
     -> assertz(daemon:active_pref_sig(NewSig))
     ;  true
     )
  ).


%! daemon:seed_pref_sig is det.
%
% Records the signature of the preferences the daemon built while it
% started. The first request that sends no environment variables of its
% own then finds the signature unchanged and uses those preferences.

daemon:seed_pref_sig :-
  retractall(daemon:active_pref_sig(_)),
  ( daemon:current_pref_sig([], Sig)
  -> assertz(daemon:active_pref_sig(Sig))
  ;  true
  ).


%! daemon:current_pref_sig(+Env, -Sig) is semidet.
%
% Sig describes everything the preferences are built from, as it is now.
% It has two parts. The first is the list of environment variables the
% client sent, sorted, without the two that only describe its terminal.
% The second is the stamp of the preference cache
% (preference:cache_current_stamp/1): the modification times of the
% knowledge base, the profile cache, the world file, the set files and
% the files in the configuration directory, together with the values of
% the environment variables the preferences read.
%
% Because that stamp is used, the daemon notices a change exactly when a
% standalone run would.

daemon:current_pref_sig(Env, pref_sig(PrefEnv, Stamp)) :-
  findall(K-V,
          ( member(K-V, Env),
            K \== '_CLIENT_IS_TTY',
            K \== 'TERM'
          ),
          Pairs),
  msort(Pairs, PrefEnv),
  preference:cache_current_stamp(Stamp).


%! daemon:maybe_invalidate_pref_sig(+Args) is det.
%
% Forgets the recorded signature after a request that changes the
% knowledge base or the world file, so that the next request rebuilds the
% preferences whatever the modification times say.

daemon:maybe_invalidate_pref_sig(Args) :-
  ( member(Flag, ['--sync', '--clear', '--load', '--regen', '--metadata', '--deselect']),
    memberchk(Flag, Args)
  -> retractall(daemon:active_pref_sig(_))
  ;  true
  ).

:- dynamic daemon:active_pref_sig/1.
:- dynamic daemon:client_tty_size/2.
:- dynamic daemon:client_is_tty/0.
:- dynamic daemon:client_env/2.
:- dynamic daemon:running/0.


%! daemon:run_with_output(+Out, +Request, +ExitCodeTerm) is det.
%
% Serves one request with standard output and standard error redirected
% to the socket stream Out: prepares the per-request state from the
% client's arguments and environment, then runs
% interface:process_requests(standalone).
%
% The state is prepared after the redirection, not before it, so that an
% error while reading the client's arguments (an unknown option, a value
% of the wrong type) is handled like any other error of the request:
% daemon:handle_error/3 writes the explanation to the client and sets the
% exit status, and the daemon goes on to the next connection.

daemon:run_with_output(Out, request(Args, Cols, Rows, Env), ExitCodeTerm) :-
  stream_property(OldOut, alias(user_output)),
  stream_property(OldErr, alias(user_error)),
  current_output(OldCurr),
  setup_call_cleanup(
    ( set_stream(Out, alias(user_output)),
      set_stream(Out, alias(user_error)),
      set_output(Out)
    ),
    catch(
      ( daemon:isolate_state(Args, Cols, Rows, Env),
        daemon:refresh_binpkg_index,
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
% requester rather than the daemon console when --verbose is set.
% Always succeeds.

daemon:refresh_binpkg_index :-
  ( current_predicate(binpkg_exec:ensure_index_fresh/0)
  -> message:catch_log('binpkg_exec:ensure_index_fresh', binpkg_exec:ensure_index_fresh)
  ;  true
  ).


%! daemon:handle_error(+Out, +Error, +ExitCodeTerm) is det.
%
% Interprets exceptions thrown during request processing.
% halt/1 throws unwind(halt(Code)) in SWI-Prolog.
%
% A command line that cannot be parsed is answered with the explanation
% and the exit status a standalone run gives for the same mistake
% (interface:argv_error_text/3). Nothing halts, so the daemon keeps
% running.

daemon:handle_error(_Out, Error, ExitCodeTerm) :-
  ( Error = unwind(halt(Code)) ; Error = halt(Code) ),
  integer(Code), !,
  nb_setarg(1, ExitCodeTerm, Code).

daemon:handle_error(Out, Error, ExitCodeTerm) :-
  interface:argv_error_text(Error, Status, Lines), !,
  forall(member(Line, Lines),
         format(Out, '~w~n', [Line])),
  nb_setarg(1, ExitCodeTerm, Status).

daemon:handle_error(Out, Error, ExitCodeTerm) :-
  format(Out, 'Daemon error: ~w~n', [Error]),
  nb_setarg(1, ExitCodeTerm, 1).
