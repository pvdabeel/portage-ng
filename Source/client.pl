/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> CLIENT
Lightweight client for the portage-ng Pengine server. Delegates query
evaluation and dependency resolution to a remote server, avoiding the
need to load the full knowledge base locally. The server keeps its cache
indexed for fast queries and supports concurrent plan computation across
multiple threads.

Communication uses SSL-encrypted HTTP with digest authentication,
enabling secure remote administration of one or more servers.

The client supplies local state (installed packages, USE flags, keywords,
etc.) while the server provides the repository knowledge base. The server
returns a dependency plan that the client can print or execute.
*/

:- module(client, []).

% =============================================================================
%  CLIENT declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Declare remote predicates
% -----------------------------------------------------------------------------

%! client:remote_predicate_template(?Predicate)
%
% Predicates whose full clause set is shipped to the remote Pengine context.
% This is a list of predicates that are declared as remote in the server.
% The client will ship these predicates to the server and the server will
% evaluate them in its pengines context.

% Global USE, keywords, flags
client:remote_predicate_template(preference:local_use(_)).
client:remote_predicate_template(preference:local_env_use(_)).
client:remote_predicate_template(preference:local_accept_keywords(_)).
client:remote_predicate_template(preference:local_flag(_)).

% Per-package USE overrides (/etc/portage/package.use + profile)
client:remote_predicate_template(preference:package_use_override(_,_,_,_)).
client:remote_predicate_template(preference:gentoo_package_use_soft(_,_,_)).
client:remote_predicate_template(preference:profile_package_use_soft(_,_,_)).
client:remote_predicate_template(preference:profile_package_use_masked(_,_)).
client:remote_predicate_template(preference:profile_package_use_forced(_,_)).

% Package masking (profiles + /etc/portage/package.mask)
remote_predicate_template(preference:masked(_)).

% License acceptance
client:remote_predicate_template(preference:accepted_license(_)).
client:remote_predicate_template(preference:denied_license(_)).
client:remote_predicate_template(preference:license_group_raw(_,_)).

% Profile USE display markers
client:remote_predicate_template(preference:profile_masked_use_flag(_)).
client:remote_predicate_template(preference:profile_forced_use_flag(_)).

% World and sets (optional, only when client/server are on different machines)
client:remote_predicate_template(preference:world(_)).
client:remote_predicate_template(preference:set(_,_)).

% Installed state (todo: needs client-side VDB handling)
% remote_predicate_template(cache:entry_metadata(_,_,installed,true)).

%! client:remote_predicate_instance(?Predicate)
%
% Predicates whose ground instances (matching facts) are shipped individually.

client:remote_predicate_instance(config:printing_style(_)).
client:remote_predicate_instance(config:printing_tty_size(_,_)).
client:remote_predicate_instance(preference:accept_license_wildcard).
client:remote_predicate_instance(preference:use_expand_env(_,_)).
client:remote_predicate_instance(preference:use_expand_hidden(_)).
client:remote_predicate_instance(preference:keyword_selection_mode(_)).


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

client:rpc_execute(Hostname,Port,Cmd) :-
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

client:rpc_execute(Hostname,Port,Cmd,Output) :-
  rpc_execute(Hostname,Port,
              streams:with_output_to(string(Output),
                                     Cmd,
                                    [capture([user_output,user_error]),
                                     color(true)])).


%! client:rpc_execute(Host,Port,Command,Output,Srclist)
%
% Same as rpc_execute/4 but pushes a list of predicates to remote server

client:rpc_execute(Hostname,Port,Cmd,Output,Srclist) :-
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

client:execute_remotely(Hostname,Port,Page) :-
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