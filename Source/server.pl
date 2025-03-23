/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2025, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> SERVER
Server sets up a portage-ng pengine server.

Client is very lightweight applicaton that processes interface requests and
calls the server for processing. This way we avoid having to load the entire
knowledge base into memory for every request. With secure authentication, this
also allows for remote administration of one or more servers.

The server maintains an accurate view on the knowledge base. The client can
provide predicates describing local state (e.g. the installed packages on
this operating system.

Client requires very little resources, server is multi-threaded and will
enable us to calculate plans very easily. Essentially the server returns a
plan to the client, which the client can then execute. (Think of the plan
as a Makefile).

*/

:- module(server, []).

% *******************
% SERVER declarations
% *******************

:- http_handler('/',reply,[id('portage-ng'),methods([get])]).
:- http_handler('/info',reply,[id('info'),methods([get])]).
:- http_handler('/sync',reply,[id('sync'),methods([get])]).
:- http_handler('/prove',reply,[id('prove'),methods([get])]).


%! server:start_server
%
% Start a http server on the given port and listens for commands

server:start_server  :-
  interface:process_server(Hostname,Port),
  config:certificate('cacert.pem',CaCert),
  config:certificate(Hostname,'server-cert.pem',ServerCert),
  config:certificate(Hostname,'server-key.pem',ServerKey),
  config:certificate_password(server,Pass),
  config:digest_passwordfile(Pwdfile),
  config:digest_realm(Realm),
  http:http_server(http_dispatch,
                   [ port(Port) ,
 		     authentication(digest(Pwdfile,Realm)),
		     chuncked(true),
                     workers(32) ,
		     keep_alive_timeout(2),
                     ssl([ certificate_file(ServerCert),
                           key_file(ServerKey),
                           password(Pass),
                           peer_cert(true),
                           cacerts([file(CaCert)])
                         ])
                   ]).


%! server:stop_server
%
% Stop a http server on the given port and stops listening for commands

server:stop_server :-
  interface:process_server(_Hostname,Port),
  catch(http:http_stop_server(Port,[]),_,true).


%! server:reply(+Request)
%
% Run a test prove run

server:reply(Request) :-
    member(path('/prove'), Request),
    !,
    format('Transfer-encoding: chunked~n~n', []),
    current_output(S),
    set_stream(S,buffer(false)),
    prover:test_latest(portage,parallel_verbose).


%! server:reply(+Request)
%
% Sync server repositories. Warning: needs locking

server:reply(Request) :-
    member(path('/sync'), Request),
    !,
    format('Transfer-encoding: chunked~n~n', []),
    current_output(S),
    set_stream(S,buffer(false)),
    kb:sync.


%! server:reply(+Request)
%
% Sync server repositories. Warning: needs locking

server:reply(Request) :-
    member(path('/info'), Request),
    !,
    config:hostname(Hostname),
    config:number_of_cpus(Cpu),
    format('Transfer-encoding: chunked~n~n', []),
    format('Host ~w has ~w cpu cores available.~n', [Hostname, Cpu]).
