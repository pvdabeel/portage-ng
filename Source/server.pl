/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

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

% =============================================================================
%  SERVER declarations
% =============================================================================

:- pengine_application('portage-ng').

:- http_handler('/',      reply, [id('portage-ng'), methods([get])]).
:- http_handler('/sync',  reply, [id('sync'),       methods([get])]).
:- http_handler('/save',  reply, [id('save'),       methods([get])]).
:- http_handler('/load',  reply, [id('load'),       methods([get])]).
:- http_handler('/clear', reply, [id('clear'),      methods([get])]).
:- http_handler('/graph', reply, [id('graph'),      methods([get])]).
:- http_handler('/prove', reply, [id('prove'),      methods([get])]).
:- http_handler('/info',  reply, [id('info'),       methods([get])]).


%! server:start_server
%
% Start a http server on the given port and listens for commands

server:start_server  :-
  % `interface:process_server/2` returns the client connection override host,
  % which must NOT be used for selecting this server's TLS certificate.
  interface:process_server(_,Port),
  config:hostname(Hostname),
  config:certificate('cacert.pem',CaCert),
  config:certificate(Hostname,'server-cert.pem',ServerCert),
  config:certificate(Hostname,'server-key.pem',ServerKey),
  config:certificate_password(server,Pass),
  config:digest_passwordfile(Pwdfile),
  config:digest_realm(Realm),
  server:ensure_server_tls_files(Hostname, ServerCert, ServerKey, Pass),
  server:ssl_options(CaCert, ServerCert, ServerKey, Pass, SslOptions),
  nl,
  http:http_server(http_dispatch,
                   [ port(Port) ,
 		     authentication(digest(Pwdfile,Realm)),
		     chuncked(true),
                     workers(32) ,
		     keep_alive_timeout(2),
                     ssl(SslOptions)
                   ]),
  message:datetime(T),
  message:notice([T]),
  nl.


% -----------------------------------------------------------------------------
% TLS helper predicates
% -----------------------------------------------------------------------------

% Ensure TLS key/cert exist. If not, generate a self-signed certificate.
server:ensure_server_tls_files(Hostname, ServerCert, ServerKey, Pass) :-
  ( exists_file(ServerCert),
    exists_file(ServerKey)
  ->
    true
  ;
    message:warning('TLS certificate/key missing for ~w; generating self-signed cert (~w, ~w).',
                    [Hostname, ServerCert, ServerKey]),
    server:openssl_generate_selfsigned(Hostname, ServerCert, ServerKey, Pass)
  ).

server:openssl_generate_selfsigned(Hostname, ServerCert, ServerKey, Pass) :-
  % Non-interactive OpenSSL invocation. We encrypt the key using Pass so it works
  % with the existing `password(Pass)` server configuration.
  atomic_list_concat(['/CN=', Hostname], '', CN),
  atomic_list_concat(['Portage-ng self-signed cert for ', Hostname], '', Org),
  atomic_list_concat(['/O=', Org, CN], '', Subject),
  atom_concat('pass:', Pass, PassArg),
  process_create(path(openssl),
                 ['req',
                  '-x509',
                  '-newkey','rsa:2048',
                  '-keyout',ServerKey,
                  '-out',ServerCert,
                  '-days','3650',
                  '-sha256',
                  '-subj',Subject,
                  '-passout',PassArg
                 ],
                 [stdout(null),stderr(null)]),
  !.

% Compute ssl/1 options robustly:
% - If the CA cert exists, request peer certs and use it as CA.
% - If not, still start HTTPS but do not require peer certificates.
server:ssl_options(CaCert, ServerCert, ServerKey, Pass, Options) :-
  ( exists_file(CaCert)
  ->
    Options = [certificate_file(ServerCert),
               key_file(ServerKey),
               password(Pass),
               peer_cert(true),
               cacerts([file(CaCert)])]
  ;
    message:warning('CA cert file missing (~w); starting HTTPS without client certificate verification.', [CaCert]),
    Options = [certificate_file(ServerCert),
               key_file(ServerKey),
               password(Pass),
               peer_cert(false)]
  ).


%! server:stop_server
%
% Stop a http server on the given port and stops listening for commands

server:stop_server :-
  interface:process_server(_Hostname,Port),
  catch(http:http_stop_server(Port,[]),_,true).


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
% Save knowledgebase to file

server:reply(Request) :-
    member(path('/save'), Request),
    !,
    format('Transfer-encoding: chunked~n~n', []),
    current_output(S),
    set_stream(S,buffer(false)),
    kb:save.


%! server:reply(+Request)
%
% Load knowledgebase from file

server:reply(Request) :-
    member(path('/load'), Request),
    !,
    format('Transfer-encoding: chunked~n~n', []),
    current_output(S),
    set_stream(S,buffer(false)),
    kb:load.


%! server:reply(+Request)
%
% Clear knowledgebase files

server:reply(Request) :-
    member(path('/clear'), Request),
    !,
    format('Transfer-encoding: chunked~n~n', []),
    current_output(S),
    set_stream(S,buffer(false)),
    kb:clear.


%! server:reply(+Request)
%
% Clear knowledgebase files

server:reply(Request) :-
    member(path('/graph'), Request),
    !,
    format('Transfer-encoding: chunked~n~n', []),
    current_output(S),
    set_stream(S,buffer(false)),
    kb:graph.


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
    member(path('/info'), Request),
    !,
    config:hostname(Hostname),
    config:number_of_cpus(Cpu),
    format('Transfer-encoding: chunked~n~n', []),
    format('Host ~w has ~w cpu cores available.~n', [Hostname, Cpu]).
