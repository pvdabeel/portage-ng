/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2024, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> CLIENT
Client interface to portage-ng pengine server. Client is very lightweight
applicaton that processes interface requests and calls the server for
processing. This way we avoid having to load the entire knowledge base
into memory for every request. With secure authentication, this also allows
for remote administration of one or more servers.

The server maintains an accurate view on the knowledge base. The client can
provide predicates describing local state (e.g. the installed packages on
this operating system.

Client requires very little resources, server is multi-threaded and will
enable us to calculate plans very easily. Essentially the server returns a
plan to the client, which the client can then execute. (Think of the plan
as a Makefile).

*/

:- module(client, []).

% *******************
% CLIENT declarations
% *******************

%! server(?Url)
%
% Declares the url of the server


query_server(Cmd) :-
  config:server_url(S),
  pengine_rpc(S,Cmd).


https_client(Hostname,Port,Page) :-
    format(atom(URL), 'https://~w:~d~w', [Hostname,Port, Page]),
    config:certificate('cacert.pem',CaCert),
    config:certificate(Hostname,'client-cert.pem',ClientCert),
    config:certificate(Hostname,'client-key.pem',ClientKey),
    config:password(client,Pass),
    http:http_open(URL, In,
              [ host(Hostname),
                cacerts([file(CaCert)]),
                certificate_file(ClientCert),
                key_file(ClientKey),
                password(Pass)
              ]),
    copy_stream_data(In, current_output),
    close(In).
