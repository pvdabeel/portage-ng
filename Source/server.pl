/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2024, Pieter Van den Abeele

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


%! server:start_server
%
% Start a http server on the given port and listens for commands

server:start_server  :-
  config:server_port(P),
  http:http_server(reply,
                   [ port(P),
                     ssl([ certificate_file('/tmp/server-cert.pem'),
                           key_file('/tmp/server-key.pem'),
                           password('apenoot1'),
                           peer_cert(true),
                           cacerts([file('/tmp/cacert.pem')])
                         ])
                   ]).
