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

% =============================================================================
% DAEMONTEST declarations
% =============================================================================

daemontest:env_ready :-
  catch(load_files(portage('Source/Application/Mode/daemon'),
                   [if(not_loaded)]), _, fail).


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

:- end_tests(daemon_security).
