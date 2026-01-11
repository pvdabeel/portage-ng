/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> CLIENT
Client interface to portage-ng pengine server. Client is very lightweight
applicaton that processes interface requests and calls the server for
processing. This way we avoid having to load the entire knowledge base
into memory for every request. The server keeps its cache database nicely
indexed, permitting high performant queries. With secure authentication,
and SSL encryption of traffic between client and server,this also allows
for remote administration of one or more servers.

The server maintains an accurate view on the knowledge base. The client can
provide predicates describing local state (e.g. the installed packages on
this operating system, use flags, keywords, etc).

Client requires very little resources, the server is multi-threaded and will
enable calculation of plans very easily. Essentially the server returns a
plan to the client, which the client can then print or execute.
(Think of the plan as a Makefile).
*/

:- module(client, []).

% =============================================================================
%  CLIENT declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Remote predicates
% -----------------------------------------------------------------------------

%! client:remote_predicate(?Predicate)
%
% Declares which predicates need to be injected in the remote pengines context.

remote_predicate_template(preference:local_use(_)).
remote_predicate_template(preference:local_env_use(_)).
remote_predicate_template(preference:local_accept_keywords(_)).
remote_predicate_template(preference:local_flag(_)).

% These are optional, only when client:server are not on the same machine

remote_predicate_template(preference:world(_)).
remote_predicate_template(preference:set(_,_)).

% Installed state is also passed on to the server

% remote_predicate_template(cache:entry_metadata(_,_,installed,true)).
% todo: needs client handling

remote_predicate_instance(config:printing_style(_)).
remote_predicate_instance(config:printing_tty_size(_,_)).


% -----------------------------------------------------------------------------
%  RPC execution
% -----------------------------------------------------------------------------

%! client:rpc_execute(Host,Port,Cmd)
%
% Use pengine_rpc to remotely call a sandboxed predicate in a pengines context.
% Use to run computationally expensive procedures on a server but retrieve the
% result in Prolog Term locally.
%
% Predicates declared as remote_predicate/1 will be injected in the remote
% server pengines context

rpc_execute(Hostname,Port,Cmd) :-
  format(atom(URL), 'https://~w:~d', [Hostname,Port]),
  config:certificate('cacert.pem',CaCert),
  % Client certificate is identified by the *local* hostname, not the remote
  % server host we are connecting to.
  config:hostname(LocalHostname),
  config:certificate(LocalHostname,'client-cert.pem',ClientCert),
  config:certificate(LocalHostname,'client-key.pem',ClientKey),
  config:certificate_password(client,Pass),
  config:digest_password(User,Digestpwd),
  config:server_chunk(ChunkSize),
  client:require_tls_files(LocalHostname, CaCert, ClientCert, ClientKey),
  findall(Template,(remote_predicate_template(Template)),Templates),
  findall(Instance,
          (remote_predicate_instance(Local:Instance),
           call(Local:Instance)),
          Context),
  pengine_rpc(URL,Cmd,
              [ host(Hostname),
                authorization(digest(User,Digestpwd)),
                cacerts([file(CaCert)]),
                certificate_file(ClientCert),
                key_file(ClientKey),
                password(Pass),
                chunk(ChunkSize),
                src_predicates(Templates),
                src_list(Context)
              ]).


%! client:rpc_execute(Host,Port,Command,Output)
%
% Same as rpc_execute/3 but captures output to Terminal in in Output string.

rpc_execute(Hostname,Port,Cmd,Output) :-
  rpc_execute(Hostname,Port,
              streams:with_output_to(string(Output),
                                     Cmd,
                                    [capture([user_output,user_error]),
                                     color(true)])).


%! client:rpc_execute(Host,Port,Command,Output,Srclist)
%
% Same as rpc_execute/4 but pushes a list of predicates to remote server

rpc_execute(Hostname,Port,Cmd,Output,Srclist) :-
  rpc_execute(Hostname,Port,
              streams:with_output_to(string(Output),
                                     Cmd,
                                     [src_list(Srclist),
                                      capture([user_output,user_error]),
                                      color(true)])).


% -----------------------------------------------------------------------------
%  Streaming output of remote execution
% -----------------------------------------------------------------------------

%! client:execute_remotely(Host,Port,Page)
%
% Triggers a pre-defined action remotely. E.g. syncing a repository.
% Output is streamed over https in realtime

execute_remotely(Hostname,Port,Page) :-
    format(atom(URL), 'https://~w:~d~w', [Hostname,Port, Page]),
    config:certificate('cacert.pem',CaCert),
    % Client certificate is identified by the *local* hostname, not the remote
    % server host we are connecting to.
    config:hostname(LocalHostname),
    config:certificate(LocalHostname,'client-cert.pem',ClientCert),
    config:certificate(LocalHostname,'client-key.pem',ClientKey),
    config:certificate_password(client,Pass),
    config:digest_password(User,Digestpwd),
    client:require_tls_files(LocalHostname, CaCert, ClientCert, ClientKey),
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


% -----------------------------------------------------------------------------
% TLS helper predicates
% -----------------------------------------------------------------------------

% Fail with a clear message if TLS material is missing.
% We keep certificate generation out of runtime: use `make certs HOST=<hostname>`.
client:require_tls_files(LocalHostname, CaCert, ClientCert, ClientKey) :-
  findall(File,
          ( member(File, [CaCert, ClientCert, ClientKey]),
            \+ exists_file(File)
          ),
          Missing),
  ( Missing == []
  -> true
  ;  message:failure(['Missing TLS files for client mode: ', Missing, '\n',
                      'Expected CA cert:      ', CaCert, '\n',
                      'Expected client cert:  ', ClientCert, '\n',
                      'Expected client key:   ', ClientKey, '\n\n',
                      'To generate them locally, run:\n',
                      '  make certs HOST=', LocalHostname, '\n',
                      'If your hostname includes a .local suffix, ensure HOST matches `config:hostname/1`.\n'
                     ])
  ).
