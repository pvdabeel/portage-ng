/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> STUBS
This file contains stub predicates for functions that are only available in
specific modes (e.g., client or server). This allows the application to be
compiled in standalone mode without generating warnings about undefined
predicates.
*/

% =============================================================================
%  STUBS declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Stubs for client calls.
% -----------------------------------------------------------------------------

:- dynamic client:rpc_execute/3.
:- dynamic client:rpc_execute/4.
:- dynamic client:execute_remotely/3.

:- if(\+ current_module(client)).

:- multifile client:rpc_execute/3.
:- multifile client:rpc_execute/4.
:- multifile client:execute_remotely/3.

client:rpc_execute(_,_,_) :-
    print_message(error,"Client module not loaded, cannot execute RPC call").

client:rpc_execute(_,_,_,_) :-
    print_message(error,"Client module not loaded, cannot execute RPC call").

client:execute_remotely(_,_,_) :-
    print_message(error,"Client module not loaded, cannot execute remotely").

:- endif.


% -----------------------------------------------------------------------------
%  Stubs for server calls.
% -----------------------------------------------------------------------------

:- dynamic server:start_server/0.
:- dynamic server:stop_server/0.

:- if(\+ current_module(server)).

:- multifile server:start_server/0.
:- multifile server:stop_server/0.

server:start_server :-
    print_message(error, "Server module not loaded, cannot start server").

server:stop_server :-
    print_message(error, "Server module not loaded, cannot stop server").

:- endif.