/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> VERIFY
Mode flag verification and per-mode early-exit handlers (included into the
INTERFACE module via interface.pl).
*/

% -----------------------------------------------------------------------------
%  Mode flag verification
% -----------------------------------------------------------------------------

%! interface:verify_mode(+Mode) is det.
%
% Verify CLI flags for the given mode. If an early-exit flag is set
% (--help, --background, --status, --cmd, --shell), performs the requested
% action and halts. Succeeds silently when no early-exit flag matches,
% allowing main/1 to continue.

interface:verify_mode(Mode) :-
  interface:argv(Options, _),
  interface:check_flags(Mode, Options).

interface:check_flags(Mode, Options) :-
  interface:early_exit(Mode, Options).

interface:check_flags(_, _).


%! interface:early_exit(+Mode, +Options) is semidet.
%
% Per-mode early-exit handlers. --help is mode-independent and runs
% before the knowledge base is loaded. Each clause matches a specific
% flag, performs its action, and halts. Clauses are tried in definition
% order.

interface:early_exit(_, Options) :-
  memberchk(help(true), Options), !,
  interface:print_help,
  halt(0).

interface:early_exit(ipc, Options) :-
  memberchk(shell(true), Options), !,
  format(user_error,
    'Error: --shell is not supported in ipc mode. Use --mode standalone --shell instead.~n', []),
  halt(1).

interface:early_exit(ipc, Options) :-
  memberchk(status(true), Options), !,
  user:load_modules(ipc),
  ( ipc:status -> halt(0) ; halt(1) ).

interface:early_exit(ipc, Options) :-
  memberchk(cmd(Cmd), Options), Cmd \= none, !,
  user:load_modules(ipc),
  ipc:send_command(Cmd),
  halt(0).

interface:early_exit(daemon, Options) :-
  memberchk(background(true), Options), !,
  user:load_modules(ipc),
  ipc:fork_background(daemon),
  halt(0).

interface:early_exit(client, Options) :-
  memberchk(status(true), Options), !,
  interface:process_server(Host, Port),
  ( interface:server_reachable(Host, Port)
  -> format('Server reachable at ~w:~w~n', [Host, Port]),
     halt(0)
  ;  format('Server not reachable at ~w:~w~n', [Host, Port]),
     halt(1)
  ).

interface:early_exit(client, Options) :-
  memberchk(cmd(Cmd), Options), Cmd \= none, !,
  format(user_error,
    'Error: --cmd is not yet supported for client mode.~n', []),
  halt(1).

interface:early_exit(server, Options) :-
  memberchk(background(true), Options), !,
  user:load_modules(ipc),
  ipc:fork_background(server),
  halt(0).
