/*
 Author: Pieter Van den Abeele
 E-mail: pvdabeel@mac.com
 Copyright (c) 2005-2026, Pieter Van den Abeele

 Distributed under the terms of the LICENSE file in the root directory of this
 project.
*/

/** <module> DAEMONTEST
Security tests for daemon runtime paths, PID publication and socket binding.
*/

:- module(daemontest, []).

:- use_module(library(plunit)).
:- use_module(library(prolog_wrap)).

:- user:ensure_loaded(portage('Source/Application/Mode/daemon.pl')).
:- user:load_modules(ipc).

% =============================================================================
% DAEMONTEST declarations
% =============================================================================

daemontest:env_ready :-
  catch(load_files(portage('Source/Application/Mode/daemon'),
                   [if(not_loaded)]), _, fail).


daemontest:cpp_client_bin(Bin) :-
  absolute_file_name(portage('Source/Application/Wrapper/ipcclient'), Bin,
                     [access(execute), file_errors(fail)]).


daemontest:with_temp_dir(Goal) :-
  tmp_file(daemontest, Tmp),
  ( exists_file(Tmp) -> delete_file(Tmp) ; true ),
  make_directory(Tmp),
  setup_call_cleanup(true, call(Goal, Tmp),
                     catch(delete_directory_and_contents(Tmp), _, true)).


:- begin_tests(daemon_security).

test(root_ignores_xdg,
     [true(Dir == '/var/run/portage-ng')]) :-
  runtimepath:daemon_runtime_dir_for(0, '/tmp/attacker', Dir).

test(nonroot_uses_xdg_subdir,
     [true(Dir == '/run/user/501/portage-ng')]) :-
  runtimepath:daemon_runtime_dir_for(501, '/run/user/501', Dir).

test(nonroot_fallback_uses_numeric_uid,
     [true(Dir == '/tmp/portage-ng-501')]) :-
  runtimepath:daemon_runtime_dir_for(501, '', Dir).

test(daemon_runtime_dir_returns_atom) :-
  runtimepath:daemon_runtime_dir(Dir),
  atom(Dir).

test(os_make_directory_and_find_files) :-
  daemontest:with_temp_dir(
    [Dir]>>(
      os:compose_path(Dir, sub, SubDir),
      os:make_directory(SubDir),
      os:make_directory(SubDir),
      os:compose_path(SubDir, 'sample.txt', FilePath),
      setup_call_cleanup(open(FilePath, write, S), writeln(S, ok), close(S)),
      findall(F, os:find_files(Dir, '*.txt', F), Found),
      Found == [FilePath]
    )).

test(os_current_load_average_is_nonnegative_number) :-
  os:current_load_average(Load),
  number(Load),
  Load >= 0.0.

test(pid_symlink_target_is_not_followed,
     [condition((daemontest:env_ready,
                 current_predicate(link_file/3))), nondet]) :-
  daemontest:with_temp_dir(
    [Dir]>>(
      os:compose_path(Dir, canary, Canary),
      setup_call_cleanup(open(Canary, write, C), write(C, untouched), close(C)),
      os:compose_path(Dir, 'portage-ng.pid', PidPath),
      link_file(Canary, PidPath, symbolic),
      daemon:write_pid(PidPath),
      sanitize:not_symlink(PidPath),
      read_file_to_string(Canary, CanaryText, []),
      CanaryText == "untouched"
    )).

test(live_socket_is_not_unlinked,
     [condition(daemontest:env_ready),
      throws(error(permission_error(start, daemon, already_running(_)), _))]) :-
  daemontest:with_temp_dir(
    [Dir]>>(
      os:compose_path(Dir, daemon_socket, Path),
      setup_call_cleanup(
        ( unix_domain_socket(Listener),
          tcp_bind(Listener, Path),
          tcp_listen(Listener, 1)
        ),
        setup_call_cleanup(
          unix_domain_socket(Second),
          daemon:bind_socket(Second, Path),
          tcp_close_socket(Second)),
        ( tcp_close_socket(Listener),
          catch(delete_file(Path), _, true)
        ))
    )).

test(daemon_ipc_ipclient_full_coverage) :-
  daemontest:env_ready,
  user:load_modules(ipc),
  redefine_system_predicate(daemon:halt(_)),
  redefine_system_predicate(ipclient:halt(_)),
  redefine_system_predicate(interface:halt(_)),
  redefine_system_predicate(interface:prolog),
  findall(O-A, interface:argv_(O, A), SavedArgv),
  current_prolog_flag(argv, OrigRawArgv),
  daemontest:with_temp_dir(
    [Dir]>>(
      os:compose_path(Dir, 'portage-ng.sock', SockPath),
      os:compose_path(Dir, 'portage-ng.pid', PidPath),
      setup_call_cleanup(
        ( asserta((daemon:halt(C) :- throw(daemon_halt(C)))),
          asserta((ipclient:halt(C) :- throw(ipclient_halt(C)))),
          asserta((interface:halt(C) :- throw(halt(C)))),
          asserta((interface:prolog :- true)),
          assertz(daemon:running),
          setenv('PORTAGE_NG_STATE', Dir),
          wrap_predicate(config:daemon_runtime_dir(D), test_cov, _, D = Dir),
          wrap_predicate(config:daemon_socket_path(SP), test_cov, _, SP = SockPath),
          wrap_predicate(config:daemon_pid_path(PP), test_cov, _, PP = PidPath),
          wrap_predicate(runtimepath:daemon_runtime_dir(RD), test_cov, _, RD = Dir)
        ),
        with_output_to(string(_),
          ( % daemon.pl
            daemon:ensure_runtime_dir,
            catch(daemon:insecure_runtime_error('/bad', 'reason'), daemon_halt(1), true),
            catch(daemon:inactivity_shutdown, daemon_halt(0), true),
            daemon:write_pid(PidPath),
            daemon:secure_socket_file(PidPath),
            catch(daemon:secure_socket_file('/nonexistent_sock_xyz'), daemon_halt(1), true),
            daemon:pid_file_is_current(PidPath),
            daemon:cleanup(SockPath, PidPath),
            wrap_predicate(config:daemon_inactivity_timeout(Tmo1), test_cov, _, Tmo1 = 60),
            daemon:reset_timer,
            unwrap_predicate(config:daemon_inactivity_timeout/1, test_cov),
            wrap_predicate(config:daemon_inactivity_timeout(Tmo0), test_cov, _, Tmo0 = 0),
            daemon:reset_timer,
            unwrap_predicate(config:daemon_inactivity_timeout/1, test_cov),
            % bind_socket_retry branches: stale file, symlink, non-existent
            setup_call_cleanup(open(SockPath, write, SS), write(SS, 'stale'), close(SS)),
            setup_call_cleanup(
              unix_domain_socket(S1),
              daemon:bind_socket(S1, SockPath),
              ( tcp_close_socket(S1), catch(delete_file(SockPath), _, true) )),
            os:compose_path(Dir, 'sym_target', SymTarget),
            setup_call_cleanup(open(SymTarget, write, ST), write(ST, 'x'), close(ST)),
            link_file(SymTarget, SockPath, symbolic),
            catch(daemon:bind_socket_retry(none, SockPath, orig_err), daemon_halt(1), true),
            catch(delete_file(SockPath), _, true),
            catch(daemon:bind_socket_retry(none, SockPath, orig_err), orig_err, true),
            % handle_request, dispatch, isolate_state, rewrite_ipc_mode_args, run_with_output, handle_error
            daemon:rewrite_ipc_mode_args(['--mode', 'ipc', '--info'], ['--mode', 'standalone', '--info']),
            daemon:rewrite_ipc_mode_args(['--mode=ipc', '--info'], ['--mode=standalone', '--info']),
            daemon:rewrite_ipc_mode_args(['--info'], ['--info']),
            open_null_stream(NullOut),
            call_cleanup(
              (                 open_string("invalid syntax (((\n", BadIn),
                call_cleanup(daemon:handle_request(BadIn, NullOut), close(BadIn)),
                open_string("", EofIn),
                call_cleanup(daemon:handle_request(EofIn, NullOut), close(EofIn)),
                open_string("malformed_req.\n", MalIn),
                call_cleanup(daemon:handle_request(MalIn, NullOut), close(MalIn)),
                open_string("request(['--version'], 80, 24, ['_CLIENT_IS_TTY'-true, 'USE'-'foo']).\n", GoodIn),
                call_cleanup(daemon:handle_request(GoodIn, NullOut), close(GoodIn)),
                daemon:dispatch(request(['--version'], 80, 24), NullOut, NullOut),
                daemon:dispatch(unknown_term_xyz, NullOut, NullOut),
                catch(daemon:dispatch(shutdown, NullOut, NullOut), daemon_halt(0), true),
                wrap_predicate(interface:process_requests(_), test_cov, _, throw(boom_req)),
                daemon:dispatch(request(['--version'], 0, 0, []), NullOut, NullOut),
                daemon:dispatch(request(['--sync'], 0, 0, []), NullOut, NullOut),
                unwrap_predicate(interface:process_requests/1, test_cov),
                daemon:accept_loop_error(ignored_socket_err),
                catch(daemon:accept_loop_error(daemon_halt(0)), daemon_halt(0), true),
                EC1 = exit_code(0),
                daemon:handle_error(NullOut, halt(2), EC1),
                EC2 = exit_code(0),
                daemon:handle_error(NullOut, other_err, EC2),
                daemon:refresh_binpkg_index
              ),
              close(NullOut)),
            % daemon:start + accept_loop via real Unix domain socket + client thread
            thread_create(
              ( ipclient:wait_for_file(SockPath, 500),
                system:sleep(0.05),
                ipclient:socket_connectable(SockPath),
                ipclient:send_term(SockPath, malformed_req),
                ipclient:send_term(SockPath, shutdown)
              ),
              ClientTid, []),
            catch(daemon:start, daemon_halt(0), true),
            catch(thread_join(ClientTid, _), _, true),
            retractall(daemon:running),
            daemon:cleanup(SockPath, PidPath),
            % ipclient.pl + ipc.pl
            ipclient:cmd_arg(['--cmd', halt], halt),
            ipclient:cmd_arg(['--other', '--cmd=relaunch'], relaunch),
            setenv('PORTAGE_NG_IPC_AUTOSTART', '1'),
            ipclient:autostart_enabled,
            unsetenv('PORTAGE_NG_IPC_AUTOSTART'),
            ipclient:daemon_wrapper(WrapperPath),
            setenv('PORTAGE_NG_DEV', WrapperPath),
            ipclient:daemon_wrapper(WrapperPath),
            unsetenv('PORTAGE_NG_DEV'),
            ipclient:local_tty_size(_, _),
            setenv('USE', 'test_use'),
            ipclient:collect_env(_),
            unsetenv('USE'),
            forall(ipclient:forwarded_env_var(_), true),
            ipclient:parse_exit_code("0", 0),
            ipclient:parse_exit_code("bad", 1),
            ipclient:connection_lost_error,
            \+ ipclient:status,
            \+ ipc:status,
            ipc:send_command(unknown_cmd),
            ipclient:connect(1),
            ipclient:send_term(SockPath, shutdown),
            ipclient:send_command("unknown_cmd"),
            ipclient:send_command(halt),
            % Live socket tests for ipclient:status, connect, stream_response, send_command
            daemon:write_pid(PidPath),
            setup_call_cleanup(
              ( unix_domain_socket(SrvSock),
                tcp_bind(SrvSock, SockPath),
                tcp_listen(SrvSock, 5)
              ),
              ( ipclient:status,
                thread_create(
                  ( tcp_accept(SrvSock, CSA, _),
                    tcp_close_socket(CSA)
                  ),
                  TA, []),
                ipclient:maybe_autostart,
                thread_join(TA, _),
                catch(delete_file(PidPath), _, true),
                ipclient:status,
                % Test ipclient:connect with LF, CR, embedded NUL, partial sentinel, and EXIT:0
                thread_create(
                  ( tcp_accept(SrvSock, CS1, _),
                    tcp_open_socket(CS1, SP1),
                    stream_pair(SP1, SIn1, SOut1),
                    read_line_to_string(SIn1, _),
                    format(SOut1, 'line1~nspin\rhello~cNOT_SENTINEL~cEX~cEXIT:0~n', [0, 0, 0]),
                    flush_output(SOut1),
                    close(SIn1), close(SOut1)
                  ),
                  T1, []),
                ipc:connect(0),
                thread_join(T1, _),
                % Test octet stream path against real OS file stream
                tmp_file(ipc_oct, OctTmp),
                setup_call_cleanup(
                  open(OctTmp, write, OctOut, [encoding(utf8)]),
                  ( current_output(PrevOut),
                    setup_call_cleanup(
                      set_output(OctOut),
                      ( thread_create(
                          ( tcp_accept(SrvSock, CS1b, _),
                            tcp_open_socket(CS1b, SP1b),
                            stream_pair(SP1b, SIn1b, SOut1b),
                            read_line_to_string(SIn1b, _),
                            format(SOut1b, 'octet_line~n~cEXIT:0~n', [0]),
                            flush_output(SOut1b),
                            close(SIn1b), close(SOut1b)
                          ),
                          T1b, []),
                        set_prolog_flag(argv, ['--info']),
                        catch(ipclient:main, ipclient_halt(0), true),
                        thread_join(T1b, _)
                      ),
                      set_output(PrevOut))
                  ),
                  ( close(OctOut), catch(delete_file(OctTmp), _, true) )),
                % Test ipclient:connect when server closes without sentinel (empty + mid-line)
                thread_create(
                  ( tcp_accept(SrvSock, CS2, _),
                    tcp_open_socket(CS2, SP2),
                    stream_pair(SP2, SIn2, SOut2),
                    read_line_to_string(SIn2, _),
                    close(SIn2), close(SOut2)
                  ),
                  T2, []),
                ipclient:connect(1),
                thread_join(T2, _),
                thread_create(
                  ( tcp_accept(SrvSock, CS2b, _),
                    tcp_open_socket(CS2b, SP2b),
                    stream_pair(SP2b, SIn2b, SOut2b),
                    read_line_to_string(SIn2b, _),
                    write(SOut2b, "partial"),
                    flush_output(SOut2b),
                    close(SIn2b), close(SOut2b)
                  ),
                  T2b, []),
                ipclient:connect(1),
                thread_join(T2b, _),
                % Test ipc:send_command(halt) and ipc:send_term against live socket
                thread_create(
                  ( tcp_accept(SrvSock, CS3, _),
                    tcp_open_socket(CS3, SP3),
                    stream_pair(SP3, SIn3, SOut3),
                    read_line_to_string(SIn3, _),
                    close(SIn3), close(SOut3)
                  ),
                  T3, []),
                ipc:send_command(halt),
                thread_join(T3, _),
                thread_create(
                  ( tcp_accept(SrvSock, CS4, _),
                    tcp_open_socket(CS4, SP4),
                    stream_pair(SP4, SIn4, SOut4),
                    read_line_to_string(SIn4, _),
                    close(SIn4), close(SOut4)
                  ),
                  T4, []),
                ipc:send_term(SockPath, ping),
                thread_join(T4, _)
              ),
              ( tcp_close_socket(SrvSock),
                catch(delete_file(SockPath), _, true)
              )),
            % Test ipclient:collect_exit_code on EOF and newline-terminated strings
            open_string("0", SCodeEof),
            call_cleanup(ipclient:collect_exit_code(SCodeEof, 0), close(SCodeEof)),
            open_string("2\n", SCodeMore),
            call_cleanup(ipclient:collect_exit_code(SCodeMore, 2), close(SCodeMore)),
            % Test ipclient:connect when socket file exists (plain file) but is not connectable
            setup_call_cleanup(open(SockPath, write, PlainS), write(PlainS, 'x'), close(PlainS)),
            ipclient:connect(1),
            ipclient:wait_for_file(SockPath, 1),
            catch(delete_file(SockPath), _, true),
            ipclient:wait_for_file(SockPath, 1),
            ipclient:wait_for_socket_gone(SockPath, 1),
            setup_call_cleanup(open(SockPath, write, PlainS2), write(PlainS2, 'x'), close(PlainS2)),
            ipclient:wait_for_socket_gone(SockPath, 1),
            catch(delete_file(SockPath), _, true),
            % Test ipclient:start_daemon_background, maybe_autostart, connect_with_autostart, relaunch, main
            redefine_system_predicate(ipclient:sleep(_)),
            redefine_system_predicate(ipc:sleep(_)),
            asserta((ipclient:sleep(_) :- true)),
            asserta((ipc:sleep(_) :- true)),
            wrap_predicate(process:process_create(_, _, Opts), test_cov, _,
                           ( memberchk(process(P), Opts) -> P = 99999 ; true )),
            wrap_predicate(process:process_wait(_, Status), test_cov, _, Status = exit(0)),
            ipclient:maybe_autostart,
            ipclient:connect_with_autostart(1),
            setenv('PORTAGE_NG_IPC_AUTOSTART', '0'),
            ipclient:maybe_autostart,
            unsetenv('PORTAGE_NG_IPC_AUTOSTART'),
            setup_call_cleanup(open(SockPath, write, PlainS3), write(PlainS3, 'x'), close(PlainS3)),
            ipclient:start_daemon_background,
            catch(delete_file(SockPath), _, true),
            ipclient:send_command(relaunch),
            unwrap_predicate(process:process_wait/2, test_cov),
            wrap_predicate(process:process_wait(_, StatusFail), test_cov, _, StatusFail = exit(1)),
            catch(ipclient:start_daemon_background, ipclient_halt(1), true),
            unwrap_predicate(process:process_wait/2, test_cov),
            unwrap_predicate(process:process_create/3, test_cov),
            setenv('PORTAGE_NG_DEV', '/nonexistent_wrapper_xyz'),
            catch(ipclient:start_daemon_background, ipclient_halt(1), true),
            unsetenv('PORTAGE_NG_DEV'),
            % ipclient:main branches
            set_prolog_flag(argv, ['--shell']),
            catch(ipclient:main, ipclient_halt(1), true),
            set_prolog_flag(argv, ['--status']),
            catch(ipclient:main, ipclient_halt(1), true),
            set_prolog_flag(argv, ['--cmd', 'halt']),
            catch(ipclient:main, ipclient_halt(0), true),
            setenv('PORTAGE_NG_IPC_AUTOSTART', '0'),
            set_prolog_flag(argv, ['--info']),
            catch(ipclient:main, ipclient_halt(1), true),
            unsetenv('PORTAGE_NG_IPC_AUTOSTART'),
            % ipc.pl remaining clauses: autostart, relaunch, fork_background, background_command, wait_for_ready, wait_for_port
            wrap_predicate(process:process_create(_, _, OptsIpc), test_cov, _,
                           ( memberchk(process(PIpc), OptsIpc) -> PIpc = 88888 ; true )),
            ipc:autostart,
            setup_call_cleanup(open(SockPath, write, PlainS4), write(PlainS4, 'x'), close(PlainS4)),
            ipc:autostart,
            catch(delete_file(SockPath), _, true),
            ipc:relaunch,
            wrap_predicate(interface:server_reachable(_, _), test_cov, _, fail),
            ipc:fork_background(server),
            \+ ipc:wait_for_port(localhost, 1, 1),
            unwrap_predicate(interface:server_reachable/2, test_cov),
            wrap_predicate(interface:server_reachable(_, _), test_cov, _, true),
            ipc:fork_background(server),
            ipc:wait_for_ready(other_mode, 123),
            ipc:wait_for_port(localhost, 4000, 2),
            unwrap_predicate(interface:server_reachable/2, test_cov),
            retractall(ipclient:sleep(_)),
            retractall(ipc:sleep(_)),
            asserta((ipclient:sleep(T) :- system:sleep(T))),
            asserta((ipc:sleep(T) :- system:sleep(T))),
            unwrap_predicate(process:process_create/3, test_cov)
          )),
        ( unwrap_predicate(config:daemon_runtime_dir/1, test_cov),
          unwrap_predicate(config:daemon_socket_path/1, test_cov),
          unwrap_predicate(config:daemon_pid_path/1, test_cov),
          unwrap_predicate(runtimepath:daemon_runtime_dir/1, test_cov),
          unsetenv('PORTAGE_NG_STATE'),
          retractall(daemon:running),
          retractall(daemon:halt(_)),
          retractall(ipclient:halt(_)),
          retractall(interface:halt(_)),
          retractall(interface:prolog),
          asserta((daemon:halt(C) :- system:halt(C))),
          asserta((ipclient:halt(C) :- system:halt(C))),
          asserta((interface:halt(C) :- system:halt(C))),
          asserta((interface:prolog :- system:prolog)),
          set_prolog_flag(argv, OrigRawArgv),
          retractall(interface:argv_(_, _)),
          forall(member(O-A, SavedArgv), assertz(interface:argv_(O, A)))
        ))
    )).

test(ipcclient_cpp_conformance,
     [condition(daemontest:cpp_client_bin(_))]) :-
  daemontest:cpp_client_bin(Bin),
  daemontest:with_temp_dir(
    [XdgDir]>>(
      atom_concat(XdgDir, '/', XdgTrailing),
      os:compose_path(XdgDir, 'portage-ng', PDir),
      os:make_directory(PDir),
      os:compose_path(PDir, 'portage-ng.sock', SockPath),
      os:compose_path(PDir, 'portage-ng.pid', PidPath),
      Env = [ 'XDG_RUNTIME_DIR'=XdgTrailing,
              'PORTAGE_NG_IPC_AUTOSTART'='0',
              'USE'='wayland -X'
            ],
      % --help, --shell, missing --cmd, --status when down
      process_create(Bin, ['--help'],
                     [env(Env), stdout(null), stderr(pipe(HelpErr)), process(HP)]),
      read_string(HelpErr, _, HelpTxt), close(HelpErr),
      process_wait(HP, exit(0)),
      once(sub_string(HelpTxt, _, _, _, "Usage:")),
      process_create(Bin, ['--shell'],
                     [env(Env), stdout(null), stderr(null), process(ShP)]),
      process_wait(ShP, exit(1)),
      process_create(Bin, ['--cmd'],
                     [env(Env), stdout(null), stderr(null), process(McP)]),
      process_wait(McP, exit(1)),
      process_create(Bin, ['--status'],
                     [env(Env), stdout(null), stderr(null), process(StDown)]),
      process_wait(StDown, exit(1)),
      process_create(Bin, ['--mode', 'ipc', '--pretend', 'foo'],
                     [env(Env), stdout(null), stderr(null), process(NoD)]),
      process_wait(NoD, exit(1)),
      % Live server tests: single connect (zero phantom accepts), embedded NUL,
      % split sentinel, env + quote escaping, --status, and --cmd halt
      daemon:write_pid(PidPath),
      setup_call_cleanup(
        ( unix_domain_socket(Srv),
          tcp_bind(Srv, SockPath),
          tcp_listen(Srv, 5)
        ),
        ( % 1. Request with single-quote arg + embedded NUL + split sentinel + exit 2
          thread_create(
            ( tcp_accept(Srv, C1, _),
              tcp_open_socket(C1, SP1),
              stream_pair(SP1, In1, Out1),
              set_stream(In1, encoding(utf8)),
              set_stream(Out1, encoding(octet)),
              read_term(In1, ReqTerm, []),
              assertion(ReqTerm = request(['--pretend', 'a''b'], _, _, ReqEnv)),
              assertion(memberchk('USE'-'wayland -X', ReqEnv)),
              format(Out1, 'ok~cNOT~cEX', [0, 0]),
              flush_output(Out1),
              sleep(0.01),
              format(Out1, '~cEXIT:', [0]),
              flush_output(Out1),
              sleep(0.01),
              format(Out1, '2~n', []),
              flush_output(Out1),
              close(In1), close(Out1)
            ),
            T1, []),
          process_create(Bin, ['--pretend', 'a''b'],
                         [env(Env), stdout(pipe(R1Out)), stderr(null), process(P1)]),
          set_stream(R1Out, encoding(octet)),
          read_string(R1Out, _, Out1Str), close(R1Out),
          process_wait(P1, exit(2)),
          thread_join(T1, _),
          string_codes(Out1Str, [0'o, 0'k, 0, 0'N, 0'O, 0'T, 0, 0'E, 0'X]),
          % 2. Truncated stream without sentinel -> exit 1
          thread_create(
            ( tcp_accept(Srv, C2, _),
              tcp_open_socket(C2, SP2),
              stream_pair(SP2, In2, Out2),
              read_line_to_string(In2, _),
              write(Out2, "partial"),
              flush_output(Out2),
              close(In2), close(Out2)
            ),
            T2, []),
          process_create(Bin, ['--pretend', 'foo'],
                         [env(Env), stdout(pipe(R2Out)), stderr(null), process(P2)]),
          read_string(R2Out, _, Out2Str), close(R2Out),
          process_wait(P2, exit(1)),
          thread_join(T2, _),
          Out2Str == "partial",
          % 3. --status (consumes one probe accept)
          thread_create(
            ( tcp_accept(Srv, C3, _),
              tcp_close_socket(C3)
            ),
            T3, []),
          process_create(Bin, ['--status'],
                         [env(Env), stdout(pipe(StOut)), stderr(null), process(P3)]),
          read_string(StOut, _, StTxt), close(StOut),
          process_wait(P3, exit(0)),
          thread_join(T3, _),
          once(sub_string(StTxt, _, _, _, "Daemon running")),
          % 4. --cmd=halt sends shutdown.
          thread_create(
            ( tcp_accept(Srv, C4, _),
              tcp_open_socket(C4, SP4),
              stream_pair(SP4, In4, Out4),
              read_term(In4, HaltTerm, []),
              assertion(HaltTerm == shutdown),
              close(In4), close(Out4)
            ),
            T4, []),
          process_create(Bin, ['--cmd=halt'],
                         [env(Env), stdout(null), stderr(null), process(P4)]),
          process_wait(P4, exit(0)),
          thread_join(T4, _)
        ),
        ( tcp_close_socket(Srv),
          catch(delete_file(SockPath), _, true),
          catch(delete_file(PidPath), _, true)
        ))
    )).

:- end_tests(daemon_security).
