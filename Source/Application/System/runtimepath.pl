/*
 Author: Pieter Van den Abeele
 E-mail: pvdabeel@mac.com
 Copyright (c) 2005-2026, Pieter Van den Abeele

 Distributed under the terms of the LICENSE file in the root directory of this
 project.
*/

/** <module> RUNTIMEPATH
Secure, UID-derived runtime paths shared by daemon clients and servers.
*/

:- module(runtimepath, []).

:- use_module(library(uid), [geteuid/1]).

% =============================================================================
% RUNTIMEPATH declarations
% =============================================================================

%! runtimepath:daemon_runtime_dir(-Dir) is det.
%
% Runtime directory for the effective user. Root ignores environment-controlled
% paths and uses a fixed directory below the trusted /var/run parent.

runtimepath:daemon_runtime_dir(Dir) :-
  geteuid(Euid),
  ( Euid =:= 0
  -> Xdg = ''
  ;  ( getenv('XDG_RUNTIME_DIR', Xdg0) -> Xdg = Xdg0 ; Xdg = '' )
  ),
  runtimepath:daemon_runtime_dir_for(Euid, Xdg, Dir).


%! runtimepath:daemon_runtime_dir_for(+Euid, +Xdg, -Dir) is det.
%
% Pure path selection used by the Prolog and native-client conformance tests.

runtimepath:daemon_runtime_dir_for(0, _Xdg, '/var/run/portage-ng') :-
  !.
runtimepath:daemon_runtime_dir_for(_Euid, Xdg, Dir) :-
  atom(Xdg),
  Xdg \== '',
  sub_atom(Xdg, 0, 1, _, '/'),
  !,
  os:compose_path(Xdg, 'portage-ng', Dir).
runtimepath:daemon_runtime_dir_for(Euid, _Xdg, Dir) :-
  format(atom(Dir), '/tmp/portage-ng-~d', [Euid]).
