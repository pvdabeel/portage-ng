/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> SERVER
Pengine-based HTTP server for portage-ng with support for distributed proving.

Three roles interact in the portage-ng architecture:

  * **Server** — Holds the full repository knowledge base, serves it over
    SSL-authenticated Pengine RPC, and coordinates distributed proving via
    job/result queues. Advertises itself and its portage tree git snapshot
    on the network via Bonjour so that clients and workers can discover it.

  * **Client** — Lightweight process that delegates dependency resolution
    to the server. Ships local state (installed packages, USE flags,
    keywords, masks) with each RPC call; the server evaluates queries
    against its KB and returns a dependency plan the client can execute.

  * **Worker** — Compute node that contributes CPU power to distributed
    tasks like proving. Discovers the server via Bonjour, syncs its local 
    portage tree to the server's advertised git snapshot, then polls the 
    server's job queue for prove targets. Each worker spawns one thread per 
    CPU, runs prover/planner/scheduler locally, and posts results back.
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
  interface:process_server(_,Port),
  config:hostname(Hostname),
  config:certificate('cacert.pem',CaCert),
  config:certificate(Hostname,'server-cert.pem',ServerCert),
  config:certificate(Hostname,'server-key.pem',ServerKey),
  config:certificate_password(server,Pass),
  config:digest_passwordfile(Pwdfile),
  config:digest_realm(Realm),
  server:require_tls_files(Hostname, CaCert, ServerCert, ServerKey),
  nl,
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
                   ]),
  message:datetime(T),
  message:notice([T]),
  nl.


%! server:stop_server
%
% Stop a http server on the given port and stops listening for commands

server:stop_server :-
  interface:process_server(_Hostname,Port),
  catch(http:http_stop_server(Port,[]),_,true).


% -----------------------------------------------------------------------------
% TLS helper predicates
% -----------------------------------------------------------------------------

server:require_tls_files(Hostname, CaCert, ServerCert, ServerKey) :-
  findall(File,
          ( member(File, [CaCert, ServerCert, ServerKey]),
            \+ exists_file(File)
          ),
          Missing),
  ( Missing == []
  -> true
  ;  message:failure(['Missing TLS files for server mode: ', Missing, '\n',
                      'Expected CA cert:      ', CaCert, '\n',
                      'Expected server cert:  ', ServerCert, '\n',
                      'Expected server key:   ', ServerKey, '\n\n',
                      'To generate them locally, run:\n',
                      '  make certs HOST=', Hostname, '\n',
                      'If your hostname includes a .local suffix, ensure HOST matches `config:hostname/1`.\n'
                     ])
  ).


% =============================================================================
%  HTTP request handlers
% =============================================================================

server:reply(Request) :-
    member(path('/sync'), Request),
    !,
    format('Transfer-encoding: chunked~n~n', []),
    current_output(S),
    set_stream(S,buffer(false)),
    kb:sync.

server:reply(Request) :-
    member(path('/save'), Request),
    !,
    format('Transfer-encoding: chunked~n~n', []),
    current_output(S),
    set_stream(S,buffer(false)),
    kb:save.

server:reply(Request) :-
    member(path('/load'), Request),
    !,
    format('Transfer-encoding: chunked~n~n', []),
    current_output(S),
    set_stream(S,buffer(false)),
    kb:load.

server:reply(Request) :-
    member(path('/clear'), Request),
    !,
    format('Transfer-encoding: chunked~n~n', []),
    current_output(S),
    set_stream(S,buffer(false)),
    kb:clear.

server:reply(Request) :-
    member(path('/graph'), Request),
    !,
    format('Transfer-encoding: chunked~n~n', []),
    current_output(S),
    set_stream(S,buffer(false)),
    kb:graph.

server:reply(Request) :-
    member(path('/prove'), Request),
    !,
    format('Transfer-encoding: chunked~n~n', []),
    current_output(S),
    set_stream(S,buffer(false)),
    prover:test_latest(portage,parallel_verbose).

server:reply(Request) :-
    member(path('/info'), Request),
    !,
    config:hostname(Hostname),
    config:number_of_cpus(Cpu),
    format('Transfer-encoding: chunked~n~n', []),
    format('Host ~w has ~w cpu cores available.~n', [Hostname, Cpu]).


% =============================================================================
%  Job queue management
% =============================================================================

:- dynamic server:queue_created/1.

server:ensure_queues :-
  ( server:queue_created(true) -> true
  ; message_queue_create(server_jobs),
    message_queue_create(server_results),
    assertz(server:queue_created(true))
  ).

%! server:post_job(+Job)
%
% Enqueue a prove target. Job = Repo://Entry:Action.

server:post_job(Job) :-
  server:ensure_queues,
  thread_send_message(server_jobs, Job).

%! server:get_job(-Job)
%
% Dequeue a prove target (blocks until one is available).

server:get_job(Job) :-
  server:ensure_queues,
  thread_get_message(server_jobs, Job).

%! server:get_job(-Job, +Timeout)
%
% Dequeue a prove target with timeout (seconds). Fails on timeout.

server:get_job(Job, Timeout) :-
  server:ensure_queues,
  thread_get_message(server_jobs, Job, [timeout(Timeout)]).

%! server:post_result(+Job, +Result)
%
% Post a completed proof/plan result back to the server.

server:post_result(Job, Result) :-
  server:ensure_queues,
  thread_send_message(server_results, result(Job, Result)).

%! server:get_result(-Job, -Result)
%
% Collect a result (blocks until one is available).

server:get_result(Job, Result) :-
  server:ensure_queues,
  thread_get_message(server_results, result(Job, Result)).

%! server:get_result(-Job, -Result, +Timeout)
%
% Collect a result with timeout. Fails on timeout.

server:get_result(Job, Result, Timeout) :-
  server:ensure_queues,
  thread_get_message(server_results, result(Job, Result), [timeout(Timeout)]).

%! server:job_count(-N)

server:job_count(N) :-
  server:ensure_queues,
  message_queue_property(server_jobs, size(N)).

%! server:result_count(-N)

server:result_count(N) :-
  server:ensure_queues,
  message_queue_property(server_results, size(N)).


% =============================================================================
%  Job submission
% =============================================================================

%! server:submit_all(+Repository, +Action)
%
% Enqueue all ordered entries from Repository as prove jobs.

server:submit_all(Repository, Action) :-
  server:ensure_queues,
  forall(cache:ordered_entry(Repository, Id, _, _, _),
         server:post_job(Repository://Id:Action)).

%! server:submit_targets(+Targets)
%
% Enqueue a list of explicit targets.

server:submit_targets(Targets) :-
  server:ensure_queues,
  forall(member(T, Targets), server:post_job(T)).


% =============================================================================
%  Worker registry
% =============================================================================

:- dynamic server:registered_worker/3.

%! server:register_worker(+Hostname, +Cpus, +Timestamp)
%
% Register or update a worker. Called when a worker announces itself.

server:register_worker(Hostname, Cpus, Timestamp) :-
  retractall(server:registered_worker(Hostname, _, _)),
  assertz(server:registered_worker(Hostname, Cpus, Timestamp)),
  message:inform(['Worker registered: ', Hostname, ' (', Cpus, ' CPUs)']).

%! server:unregister_worker(+Hostname)

server:unregister_worker(Hostname) :-
  retractall(server:registered_worker(Hostname, _, _)).

%! server:workers(-Workers)
%
% List of registered workers as Hostname-Cpus pairs.

server:workers(Workers) :-
  findall(Hostname-Cpus,
          server:registered_worker(Hostname, Cpus, _),
          Workers).

%! server:total_cpus(-N)
%
% Total CPU count across all registered workers.

server:total_cpus(N) :-
  aggregate_all(sum(Cpus),
                server:registered_worker(_, Cpus, _),
                N).


% =============================================================================
%  Snapshot identification
% =============================================================================

%! server:snapshot(+Repository, -Commit)
%
% Returns the git HEAD commit hash for the portage tree backing Repository.

server:snapshot(portage, Commit) :-
  portage:get_location(Location),
  server:git_head(Location, Commit).

%! server:git_head(+Dir, -Commit)
%
% Read the short git HEAD commit hash of a directory.

server:git_head(Dir, Commit) :-
  process_create(path(git), ['rev-parse', '--short', 'HEAD'],
                 [stdout(pipe(Out)), cwd(Dir), process(Pid)]),
  call_cleanup(
    ( read_string(Out, _, Raw),
      split_string(Raw, "\n", "\n \t", [CommitStr|_]),
      atom_string(Commit, CommitStr)
    ),
    ( close(Out), process_wait(Pid, _) )
  ).

%! server:git_head_full(+Dir, -Commit)
%
% Read the full git HEAD commit hash of a directory.

server:git_head_full(Dir, Commit) :-
  process_create(path(git), ['rev-parse', 'HEAD'],
                 [stdout(pipe(Out)), cwd(Dir), process(Pid)]),
  call_cleanup(
    ( read_string(Out, _, Raw),
      split_string(Raw, "\n", "\n \t", [CommitStr|_]),
      atom_string(Commit, CommitStr)
    ),
    ( close(Out), process_wait(Pid, _) )
  ).
