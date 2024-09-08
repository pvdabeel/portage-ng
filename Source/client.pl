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

%! client:rpc_execute(Host,Port,Cmd)
%
% Use pengine_rpc to remotely call a sandboxed predicate.
% Use to run computationally expensive procedures on a server
% but retrieve the result in Prolog Term locally.

rpc_execute(Hostname,Port,Cmd) :-
  format(atom(URL), 'https://~w:~d', [Hostname,Port]),
  config:certificate('cacert.pem',CaCert),
  config:certificate(Hostname,'client-cert.pem',ClientCert),
  config:certificate(Hostname,'client-key.pem',ClientKey),
  config:certificate_password(client,Pass),
  config:digest_password(User,Digestpwd),
  pengine_rpc(URL,sandbox:Cmd,
              [ host(Hostname),
                authorization(digest(User,Digestpwd)),
                cacerts([file(CaCert)]),
                certificate_file(ClientCert),
                key_file(ClientKey),
                password(Pass)
              ]).


%! client:rpc_execute(Host,Port,Command,Output)
%
% Same as rpc_execute/3 but captures output to Terminal in
% in Output string.

rpc_execute(Hostname,Port,Cmd,Output) :-
  rpc_execute(Hostname,Port,streams:with_output_to(string(Output),Cmd,[capture([user_output,user_error]), color(true)])).


%! client:rpc_execute(Host,Port,Command,Output,Srclist)
%
% Same as rpc_execute/4 but pushes a list of predicates to
% remote server

rpc_execute(Hostname,Port,Cmd,Output,Srclist) :-
  rpc_execute(Hostname,Port,streams:with_output_to(string(Output),Cmd,[src_list(Srclist),capture([user_output,user_error]), color(true)])).


%! client:execute_remotely(Host,Port,Page)
%
% Triggers are pre-defined action remotely and output
% locally. Output is streamed over https in realtime

execute_remotely(Hostname,Port,Page) :-
    format(atom(URL), 'https://~w:~d~w', [Hostname,Port, Page]),
    config:certificate('cacert.pem',CaCert),
    config:certificate(Hostname,'client-cert.pem',ClientCert),
    config:certificate(Hostname,'client-key.pem',ClientKey),
    config:certificate_password(client,Pass),
    config:digest_password(User,Digestpwd),
    http:http_open(URL, In,
              [ host(Hostname),
		authorization(digest(User,Digestpwd)),
                cacerts([file(CaCert)]),
                certificate_file(ClientCert),
                key_file(ClientKey),
                password(Pass),
                chunked
              ]),
    copy_stream_data(In, current_output),
    close(In).
