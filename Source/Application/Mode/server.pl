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
    CPU, runs prover/orderer locally, and posts results back.
*/

:- module(server, []).

% =============================================================================
%  SERVER declarations
% =============================================================================

:- pengine_application('portage-ng').

% State-mutating or expensive operations require POST; only informational
% endpoints remain GET (avoids crawlers with credentials triggering e.g. /clear).

% Handlers come from routes:endpoint/3 so the client proxy and the server
% register the same paths.
:- initialization(server:install_handlers, after_load).

:- multifile http:authenticate/3.
:- multifile pengines:authentication_hook/3.


%! server:start_server
%
% Start an HTTPS Pengine server on config:server_bind/1:config:server_port/1.
% Default bind is localhost: mutating POSTs (/sync, /clear, /load, …) stay
% off the public network. mTLS (peer_cert) + HTTP digest remain mandatory;
% with a shared CA, digest is the main credential — keep passwordfile
% private (make passwordfile) and only widen the bind on a trusted VPN.

server:start_server  :-
  sandbox:activate,
  interface:process_server(_,Port),
  config:hostname(Hostname),
  config:certificate('cacert.pem',CaCert),
  config:certificate(Hostname,'server-cert.pem',ServerCert),
  config:certificate(Hostname,'server-key.pem',ServerKey),
  config:certificate_password(server,Pass),
  config:digest_passwordfile(Pwdfile),
  server:require_tls_files(Hostname, CaCert, ServerCert, ServerKey),
  server:require_digest_passwordfile(Pwdfile),
  interface:require_digest_password,
  config:server_workers(Workers),
  config:server_keep_alive_timeout(KeepAlive),
  server:server_address(Port, Address),
  server:ensure_queues,
  nl,
  http:http_server(http_dispatch,
                   [ port(Address),
                     workers(Workers) ,
		     keep_alive_timeout(KeepAlive),
                     ssl([ certificate_file(ServerCert),
                           key_file(ServerKey),
                           password(Pass),
                           peer_cert(true),
                           cacerts([file(CaCert)])
                         ])
                   ]),
  message:datetime(T),
  message:notice([T, ' listening on ', Address]),
  nl.


%! http:authenticate(+Type, +Request, -Fields) is semidet.
%
% Application authentication combines HTTP digest identity with the verified
% mTLS client certificate. Authentication is attached to handlers, not to
% http_server/2.

http:authenticate(portage_ng, Request,
                  [user(Principal), client_certificate_hash(Hash)]) :-
  config:digest_passwordfile(Pwdfile),
  config:digest_realm(Realm),
  http:authenticate(digest(Pwdfile, Realm), Request, DigestFields),
  memberchk(user(DigestUser), DigestFields),
  server:request_certificate_identity(Request, CertificateCN, Hash),
  Principal = tenant(DigestUser, CertificateCN).


%! pengines:authentication_hook(+Request, +Application, -Principal) is semidet.

pengines:authentication_hook(Request, 'portage-ng', Principal) :-
  http:authenticate(portage_ng, Request, Fields),
  memberchk(user(Principal), Fields).


%! server:request_certificate_identity(+Request, -CN, -Hash) is semidet.
%
% Extract and validate the host-specific client certificate identity.

server:request_certificate_identity(Request, CN, Hash) :-
  memberchk(protocol(https), Request),
  memberchk(input(Stream), Request),
  ssl:ssl_peer_certificate(Stream, Certificate),
  server:certificate_identity(Certificate, CN, Hash).


%! server:certificate_identity(+Certificate, -CN, -Hash) is semidet.

server:certificate_identity(Certificate, CN, Hash) :-
  ssl:certificate_field(Certificate, subject(Subject)),
  memberchk('CN'=CN0, Subject),
  memberchk('OU'=OU0, Subject),
  server:certificate_atom(CN0, CN),
  server:certificate_atom(OU0, OU),
  server:valid_hostname(CN),
  format(atom(ExpectedOU), 'Client - ~w', [CN]),
  OU == ExpectedOU,
  ( ssl:certificate_field(Certificate, hash(Hash0))
  -> server:certificate_atom(Hash0, Hash)
  ;  Hash = unknown
  ),
  !.


%! server:certificate_atom(+Value, -Atom) is det.

server:certificate_atom(Value, Atom) :-
  ( atom(Value) -> Atom = Value
  ; string(Value) -> atom_string(Atom, Value)
  ; term_to_atom(Value, Atom)
  ).


%! server:server_address(+Port, -Address) is det.
%
% Build the http_server/2 bind address from config:server_bind/1 and Port.
% `localhost` → localhost:Port; `*` / `0.0.0.0` → Port (all interfaces).

server:server_address(Port, Address) :-
  ( current_predicate(config:server_bind/1),
    config:server_bind(Bind)
  -> true
  ;  Bind = localhost
  ),
  ( memberchk(Bind, [*, '0.0.0.0', any])
  -> Address = Port
  ;  Address = Bind:Port
  ).


%! server:require_digest_passwordfile(+Pwdfile) is det.
%
% Fail clearly when Certificates/passwordfile is missing. Set
% Source/Config/Private/passwords.pl then run `make passwordfile`.

server:require_digest_passwordfile(Pwdfile) :-
  ( exists_file(Pwdfile)
  -> true
  ;  message:failure(['Missing HTTP digest password file: ', Pwdfile, '\n',
                      'Set Source/Config/Private/passwords.pl then:\n',
                      '  make passwordfile\n',
                      '(see Certificates/README.md).\n'])
  ).


%! server:stop_server
%
% Stop a http server on the given port and stops listening for commands

server:stop_server :-
  interface:process_server(_Hostname,Port),
  catch(http:http_stop_server(Port,[]),_,true),
  server:destroy_queues.


% -----------------------------------------------------------------------------
% TLS helper predicates
% -----------------------------------------------------------------------------

server:require_tls_files(Hostname, CaCert, ServerCert, ServerKey) :-
  interface:require_tls_files(server, Hostname, CaCert, ServerCert, ServerKey).


% =============================================================================
%  HTTP request handlers
% =============================================================================

%! server:install_handlers is det.
%
% Register every routes:endpoint/3 on the HTTP dispatch table.

server:install_handlers :-
  forall(routes:endpoint(Name, Path, Method),
         ( routes:handler_options(Name, Extra),
           ( Name == sync_named -> Location = root(sync) ; Location = Path ),
           http_handler(Location, reply,
                        [id(Name), methods([Method]), authentication(portage_ng)|Extra])
         )).


%! server:reply(+Request) is det.
%
% Dispatch one authenticated request. /sync/<repository> is the named
% sync prefix; every other path is a routes:endpoint/3 name.

server:reply(Request) :-
  member(path(Path), Request),
  server:reply_path(Path, Request),
  !.

server:reply_path(Path, _Request) :-
  atom_concat('/sync/', Name, Path),
  Name \== '',
  !,
  server:chunked_reply(Path, kb:sync(Name)).

server:reply_path(Path, Request) :-
  routes:endpoint(Name, Path, _),
  server:dispatch(Name, Request).


%! server:dispatch(+Name, +Request) is det.
%
% Run the body for an endpoint name. Import reads its body before the
% chunked response starts. Graph and prove load their capability groups
% in this process first.

server:dispatch(import_vdb, Request) :-
  !,
  server:import_vdb_request(Request, Result),
  server:chunked_reply('/import-vdb', server:print_vdb_import_result(Result)).

server:dispatch(vdb_status, Request) :-
  !,
  server:chunked_reply('/vdb-status', server:vdb_status(Request)).

server:dispatch(Name, _Request) :-
  routes:endpoint(Name, Path, _),
  server:endpoint_goal(Name, Goal),
  server:chunked_reply(Path, Goal).


%! server:endpoint_goal(+Name, -Goal) is det.

server:endpoint_goal(root, server:info) :- !.
server:endpoint_goal(sync, kb:sync) :- !.
server:endpoint_goal(save, kb:save) :- !.
server:endpoint_goal(load, kb:load) :- !.
server:endpoint_goal(clear, kb:clear) :- !.
server:endpoint_goal(info, server:info) :- !.
server:endpoint_goal(graph, (loader:ensure(graph), loader:ensure(bulk), kb:graph)) :- !.
server:endpoint_goal(graph_emerge, (loader:ensure(graph), kb:graph_emerge)) :- !.
server:endpoint_goal(graph_pmerge, (loader:ensure(graph), kb:graph_pmerge)) :- !.
server:endpoint_goal(prove, (loader:ensure(bulk), resolver:test_latest(portage, parallel_verbose))) :- !.
server:endpoint_goal(Name, true) :-
  throw(error(existence_error(endpoint, Name), context(server:endpoint_goal/2, _))).


%! server:chunked_reply(+Path, +Goal)
%
% Shared handler body: switch the reply to chunked transfer encoding,
% unbuffer the output stream so progress is streamed to the client in
% realtime, then run Goal. Exceptions and failure are caught, reported
% to the client in-band and logged server-side, so a failing handler
% never truncates the response mid-chunk or escapes to thread_httpd.

server:chunked_reply(Path, Goal) :-
    format('Transfer-encoding: chunked~n~n', []),
    current_output(S),
    set_stream(S,buffer(false)),
    ( catch(Goal, Error, server:handler_error(Path, Error))
    -> true
    ;  server:handler_failed(Path)
    ).


%! server:handler_error(+Path, +Error)
%
% Report an exception escaping a request handler: log server-side and
% inform the client in-band on the chunked stream.

server:handler_error(Path, Error) :-
    format(user_error, 'portage-ng server: error in ~w handler: ~w~n', [Path, Error]),
    format('% Server error in ~w: ~w~n', [Path, Error]),
    flush_output.


%! server:handler_failed(+Path)
%
% Report a request handler that failed without raising an exception.

server:handler_failed(Path) :-
    format(user_error, 'portage-ng server: ~w handler failed~n', [Path]),
    format('% Server request ~w failed~n', [Path]),
    flush_output.


%! server:info
%
% Print basic host information.

server:info :-
    config:hostname(Hostname),
    config:number_of_cpus(Cpu),
    format('Host ~w has ~w cpu cores available.~n', [Hostname, Cpu]).


% =============================================================================
%  Job queue management
% =============================================================================

:- dynamic server:queue_created/1.
:- dynamic server:workers_done/0.

%! server:ensure_queues
%
% Create the job/result queues if they don't exist yet. Guarded by a
% mutex: queue accessors run on many concurrent HTTP worker threads, so
% an unguarded check-then-act would let two threads race past the check
% and the loser would throw permission_error on message_queue_create/1.
% Also called eagerly from start_server.

server:ensure_queues :-
  with_mutex(server_queues,
    ( server:queue_created(true)
      -> true
      ;  message_queue_create(server_jobs),
         message_queue_create(server_results),
         assertz(server:queue_created(true))
    )).

%! server:destroy_queues
%
% Tear down the job/result queues (called from stop_server) so they
% don't persist after the server is stopped.

server:destroy_queues :-
  with_mutex(server_queues,
    ( server:queue_created(true)
      -> catch(message_queue_destroy(server_jobs),_,true),
         catch(message_queue_destroy(server_results),_,true),
         retractall(server:queue_created(_))
      ;  true
    )).

%! server:post_job(+Target)
%
% Enqueue a prove target. The queued envelope is
% job(Id, Token, Batch, Target). Id stays stable across requeues; Token
% is the lease. The submitted counter counts expected results, not
% queue length.

server:post_job(Target) :-
  server:ensure_queues,
  jobs:enqueue(Target, Envelope),
  thread_send_message(server_jobs, Envelope).

%! server:get_job(-Job)
%
% Dequeue a prove target (blocks until one is available).

server:get_job(Job) :-
  server:get_job_for(Job, infinite, unknown).

%! server:get_job(-Job, +Timeout)
%
% Dequeue a prove target with timeout (seconds). Fails on timeout.

server:get_job(Job, Timeout) :-
  server:get_job_for(Job, Timeout, unknown).

%! server:get_job(-Job, +Timeout, +Worker)
%
% Dequeue a prove target with timeout on behalf of Worker. Fails on
% timeout. Job is job(Id, Token, Target). The token is that worker's
% lease. Envelopes from a previous batch are discarded.

server:get_job(Job, Timeout, Worker) :-
  server:get_job_for(Job, Timeout, Worker).

%! server:get_job_for(-Job, +Timeout, +Worker)
%
% Shared implementation behind get_job/1,2,3.
%
% When server:stop_workers has been called, `done` is returned to every
% polling thread without consuming anything from the queue, so the stop
% signal is broadcast to all threads of all workers instead of being a
% single-consumer sentinel.

server:get_job_for(Job, _Timeout, Worker) :-
  server:workers_done,
  !,
  server:worker_heartbeat(Worker),
  Job = done.
server:get_job_for(Job, Timeout, Worker) :-
  server:ensure_queues,
  server:dequeue_envelope(Timeout, Envelope),
  server:worker_heartbeat(Worker),
  get_time(Now),
  jobs:accept(Envelope, Worker, Now, Job).


%! server:dequeue_envelope(+Timeout, -Envelope) is semidet.
%
% Next queue message that belongs to the current batch. A previous
% batch's envelope is dropped and the dequeue continues.

server:dequeue_envelope(Timeout, Envelope) :-
  ( Timeout == infinite
  -> thread_get_message(server_jobs, Next)
  ;  thread_get_message(server_jobs, Next, [timeout(Timeout)])
  ),
  ( jobs:current_envelope(Next)
  -> Envelope = Next
  ;  server:dequeue_envelope(Timeout, Envelope)
  ).

%! server:stop_workers
%
% Signal all polling worker threads to stop. Every subsequent get_job
% poll (from any thread of any worker) receives the `done` sentinel.
% Call server:resume_workers before submitting a new batch of jobs.

server:stop_workers :-
  ( server:workers_done -> true ; assertz(server:workers_done) ).


%! server:resume_workers
%
% Clear the stop signal so workers receive jobs again.

server:resume_workers :-
  retractall(server:workers_done).


%! server:post_result(+Id, +Token, +Result)
%
% Publish Result when Token is still the lease for Id. A second post of
% an id that was already published succeeds and does not enqueue again.
% A token that lost its lease is rejected.

server:post_result(Id, Token, Result) :-
  server:ensure_queues,
  jobs:complete(Id, Token, Result, Outcome),
  ( Outcome = publish(Target, Result)
  -> thread_send_message(server_results, result(Id, Target, Result))
  ; Outcome == duplicate
  -> true
  ; message:warning(['Ignoring post_result for job ', Id]),
    fail
  ).


%! server:renew_lease(+Id, +Token) is semidet.
%
% A worker's heartbeat while it is still proving Id. Fails when the
% lease has moved to another token.

server:renew_lease(Id, Token) :-
  get_time(Now),
  jobs:renew(Id, Token, Now).


%! server:get_result(-Target, -Result)
%
% Collect a result (blocks until one is available).

server:get_result(Target, Result) :-
  server:get_result(_Id, Target, Result, infinite).


%! server:get_result(-Target, -Result, +Timeout)
%
% Collect a result with timeout. Fails on timeout.

server:get_result(Target, Result, Timeout) :-
  server:get_result(_Id, Target, Result, Timeout).


%! server:get_result(-Id, -Target, -Result, +Timeout)
%
% Collect one published result. Id is the submission id used to ignore
% duplicates. Timeout `infinite` waits until a result arrives.

server:get_result(Id, Target, Result, infinite) :-
  !,
  server:ensure_queues,
  thread_get_message(server_results, result(Id, Target, Result)).
server:get_result(Id, Target, Result, Timeout) :-
  server:ensure_queues,
  thread_get_message(server_results, result(Id, Target, Result), [timeout(Timeout)]).


%! server:job_count(-N)

server:job_count(N) :-
  server:ensure_queues,
  message_queue_property(server_jobs, size(N)).


%! server:result_count(-N)

server:result_count(N) :-
  server:ensure_queues,
  message_queue_property(server_results, size(N)).


%! server:submitted_count(-N)
%
% Number of jobs submitted since the last progress reset. Unlike
% job_count/1 this does not drop when workers dequeue jobs, so it is
% the authoritative number of results to wait for.

server:submitted_count(N) :-
  jobs:submitted_count(N).


%! server:inflight_count(-N)
%
% Number of jobs currently dequeued by workers but not yet resulted.

server:inflight_count(N) :-
  jobs:inflight_count(N).


%! server:reset_progress
%
% Open a new batch, drop leases and the submitted counter, and drain
% both queues. Envelopes and results from the previous batch no longer
% match, so a late worker cannot publish into the next collection.

server:reset_progress :-
  server:ensure_queues,
  jobs:reset,
  server:drain_queue(server_jobs),
  server:drain_queue(server_results).


%! server:drain_queue(+Queue)
%
% Remove all pending messages from Queue without blocking.

server:drain_queue(Queue) :-
  ( thread_get_message(Queue, _, [timeout(0)])
  -> server:drain_queue(Queue)
  ;  true ).


%! server:requeue_stale_jobs(+Timeout)
%
% Re-queue in-flight jobs whose worker has not been seen for more than
% Timeout seconds. For jobs dequeued by an unidentified worker (legacy
% get_job/1,2 callers) the in-flight age itself is used instead. A
% re-queued job does not increment the submitted counter: it is the
% same logical job, handed to another worker.

server:requeue_stale_jobs(Timeout) :-
  get_time(Now),
  findall(Id-Token-Worker,
          ( jobs:held(Id, Token, Worker, Since),
            server:job_is_stale(Worker, Since, Now, Timeout) ),
          Stale),
  forall(member(Id-Token-Worker, Stale),
         server:requeue_job(Id, Token, Worker)).


%! server:job_is_stale(+Worker, +Since, +Now, +Timeout)
%
% True when the worker holding a job is presumed dead.

server:job_is_stale(Worker, _Since, Now, Timeout) :-
  server:registered_worker(Worker, _, LastSeen), !,
  Now - LastSeen > Timeout.

server:job_is_stale(_Worker, Since, Now, Timeout) :-
  Now - Since > Timeout.


%! server:requeue_job(+Id, +Token, +Worker)
%
% Put a presumed-lost lease back on the job queue when Token is still
% current. The id does not change and the submitted counter does not
% increase. A result that won the race leaves this call with nothing
% to queue.

server:requeue_job(Id, Token, Worker) :-
  ( jobs:requeue(Id, Token, Envelope)
  -> thread_send_message(server_jobs, Envelope),
     message:warning(['Re-queued job ', Id, ' from unresponsive worker ', Worker])
  ;  true
  ).


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


%! server:worker_heartbeat(+Hostname)
%
% Refresh the liveness timestamp of a registered worker. A no-op for
% unregistered or unidentified (unknown) workers.

server:worker_heartbeat(Hostname) :-
  with_mutex(server_progress,
    ( retract(server:registered_worker(Hostname, Cpus, _)) ->
        get_time(Now),
        assertz(server:registered_worker(Hostname, Cpus, Now))
    ; true
    )).


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
%  Client VDB import (issue #78)
% =============================================================================

% Hard caps on the number of facts a single client may import. A typical
% VDB holds 0.5-2k entries and 40-80k metadata facts; the caps only guard
% against malformed or hostile payloads.
server:vdb_import_max_entries(200000).
server:vdb_import_max_metadata(5000000).

% Caps on the payload size and on each individual wire term, enforced
% before / while parsing: the count caps above only fire after a term
% has been fully read, so without these a single huge md/3 value could
% exhaust server memory first. The per-term cap mirrors the daemon's
% max_term_length (Mode/daemon.pl). The handler time limit is 300s.
server:vdb_import_max_payload_bytes(67108864).
server:vdb_import_max_term_length(100000).

:- dynamic server:vdb_import_reservation/2.


%! server:import_vdb_request(+Request, -Result) is det.
%
% Authenticate-derived, Content-Length-bounded import path used by HTTP.

server:import_vdb_request(Request, Result) :-
  memberchk(user(Principal), Request),
  ( memberchk(content_length(Bytes), Request)
  -> true
  ;  throw(http_reply(length_required))
  ),
  server:vdb_import_max_payload_bytes(MaxBytes),
  ( integer(Bytes), Bytes >= 0, Bytes =< MaxBytes
  -> true
  ;  throw(http_reply(payload_too_large))
  ),
  memberchk(input(Input), Request),
  setup_call_cleanup(
    server:reserve_vdb_import(Principal, Bytes),
    setup_call_cleanup(
      http_stream:stream_range_open(Input, Body, [size(Bytes)]),
      ( set_stream(Body, encoding(utf8)),
        server:parse_vdb_import(Body, Hostname, Stamp, Entries, Metadata),
        server:require_vdb_stream_end(Body),
        byte_count(Body, Consumed),
        ( Consumed =:= Bytes
        -> true
        ;  throw(error(syntax_error(vdb_import_byte_count(Bytes, Consumed)),
                       server:import_vdb_request/2))
        ),
        server:principal_hostname(Principal, Hostname),
        atom_concat('pkg@', Hostname, Repo),
        length(Entries, EntryCount),
        length(Metadata, MdCount),
        server:assert_client_vdb(Principal, Repo, Stamp, Bytes,
                                 Entries, Metadata),
        Result = vdb_import_ok(Repo, Stamp, EntryCount, MdCount)
      ),
      close(Body)),
    server:release_vdb_import(Principal)).


%! server:principal_hostname(+Principal, ?Hostname) is semidet.

server:principal_hostname(tenant(_DigestUser, CertificateCN), Hostname) :-
  ( Hostname == CertificateCN
  -> true
  ;  throw(error(permission_error(import, hostname, Hostname),
                  context(server:import_vdb_request/2,
                          certificate_cn(CertificateCN))))
  ).


%! server:reserve_vdb_import(+Principal, +Bytes) is det.

server:reserve_vdb_import(Principal, Bytes) :-
  with_mutex(server_vdb_import,
    ( server:prune_expired_vdbs_locked,
      ( server:vdb_import_reservation(Principal, _)
      -> throw(error(permission_error(import, client_vdb, already_in_progress),
                     server:reserve_vdb_import/2))
      ;  true
      ),
      server:check_vdb_tenant_quota(Principal, Bytes),
      assertz(server:vdb_import_reservation(Principal, Bytes))
    )).


%! server:release_vdb_import(+Principal) is det.

server:release_vdb_import(Principal) :-
  with_mutex(server_vdb_import,
             retractall(server:vdb_import_reservation(Principal, _))).


%! server:check_vdb_tenant_quota(+Principal, +Bytes) is det.

server:check_vdb_tenant_quota(Principal, Bytes) :-
  server:vdb_quota(max_tenants, MaxTenants),
  findall(P, knowledgebase:client_vdb_import(P, _, _, _, _, _, _), Ps0),
  sort(Ps0, Principals),
  ( memberchk(Principal, Principals) -> AddedTenant = 0 ; AddedTenant = 1 ),
  length(Principals, TenantCount),
  TenantCount + AddedTenant =< MaxTenants,
  server:vdb_quota(max_bytes, MaxBytes),
  aggregate_all(sum(B),
                knowledgebase:client_vdb_import(_, _, _, B, _, _, _),
                StoredBytes0),
  ( knowledgebase:client_vdb_import(Principal, _, _, OldBytes, _, _, _)
  -> StoredBytes is StoredBytes0 - OldBytes
  ;  StoredBytes = StoredBytes0
  ),
  aggregate_all(sum(R), server:vdb_import_reservation(_, R), Reserved),
  StoredBytes + Reserved + Bytes =< MaxBytes,
  !.
server:check_vdb_tenant_quota(_, _) :-
  throw(error(resource_error(vdb_import_quota),
              server:reserve_vdb_import/2)).


%! server:vdb_quota(+Name, -Value) is det.

server:vdb_quota(max_tenants, Value) :-
  ( config:client_vdb_max_tenants(Value) -> true ; Value = 32 ).
server:vdb_quota(max_bytes, Value) :-
  ( config:client_vdb_max_total_bytes(Value) -> true ; Value = 268435456 ).
server:vdb_quota(max_entries, Value) :-
  ( config:client_vdb_max_total_entries(Value) -> true ; Value = 100000 ).
server:vdb_quota(max_metadata, Value) :-
  ( config:client_vdb_max_total_metadata(Value) -> true ; Value = 2000000 ).
server:vdb_quota(idle_ttl, Value) :-
  ( config:client_vdb_idle_ttl(Value) -> true ; Value = 86400 ).


%! server:prune_expired_vdbs_locked is det.
%
% Called only while server_vdb_import is held.

server:prune_expired_vdbs_locked :-
  server:vdb_quota(idle_ttl, TTL),
  get_time(Now),
  findall(Principal-Repo,
          ( knowledgebase:client_vdb_import(Principal, Repo, _, _, _, _, Seen),
            Now - Seen > TTL
          ),
          Expired),
  forall(member(Principal-Repo, Expired),
         transaction(
           ( server:retract_client_vdb_facts(Repo),
             knowledgebase:remove_client_vdb(Principal, Repo)
           ))).


%! server:require_vdb_stream_end(+Stream) is det.

server:require_vdb_stream_end(Stream) :-
  server:vdb_import_max_term_length(MaxLength),
  read_term(Stream, Tail, [max_term_length(MaxLength)]),
  ( Tail == end_of_file
  -> true
  ;  throw(error(syntax_error(vdb_import_trailing_term(Tail)),
                  server:parse_vdb_import/5))
  ).


%! server:print_vdb_import_result(+Result) is det.

server:print_vdb_import_result(Result) :-
  format('~q.~n', [Result]),
  flush_output.


%! server:vdb_status(+Request) is det.

server:vdb_status(Request) :-
  memberchk(user(Principal), Request),
  with_mutex(server_vdb_import,
    ( server:prune_expired_vdbs_locked,
      ( knowledgebase:client_vdb_import(Principal, Repo, Stamp,
                                         _Bytes, _Entries, _Metadata, _Seen)
      -> knowledgebase:touch_client_vdb(Principal, Repo),
         Status = vdb_status(current, Repo, Stamp)
      ;  Status = vdb_status(missing)
      )
    )),
  format('~q.~n', [Status]).


%! server:import_vdb(+Payload) is det.
%
% Handle a /import-vdb POST: parse and validate the term-stream payload
% produced by client:vdb_payload/3, then atomically register the facts as
% the per-client repository pkg@<clienthost>. The client hostname is taken
% from the (digest + client-cert authenticated) payload and sanitized; the
% repository name is always derived server-side, never trusted from the
% wire. Fact shapes are whitelisted and counts are capped.

server:import_vdb(Payload) :-
  server:vdb_import_max_payload_bytes(MaxBytes),
  server:check_vdb_payload_size(Payload, MaxBytes),
  setup_call_cleanup(
    open_string(Payload, Stream),
    ( server:parse_vdb_import(Stream, Hostname, Stamp, Entries, Metadata),
      server:require_vdb_stream_end(Stream)
    ),
    close(Stream)),
  Principal = tenant(legacy, Hostname),
  atom_concat('pkg@', Hostname, Repo),
  string_length(Payload, Bytes),
  server:assert_client_vdb(Principal, Repo, Stamp, Bytes, Entries, Metadata),
  length(Entries, EntryCount),
  length(Metadata, MdCount),
  server:print_vdb_import_result(
    vdb_import_ok(Repo, Stamp, EntryCount, MdCount)).


%! server:parse_vdb_import(+Stream, -Hostname, -Stamp, -Entries, -Metadata) is det.
%
% Parse and validate the wire format:
%
%   vdb_import_v1.
%   hostname(<atom>).
%   stamp(stamp(Count, Sha)).
%   oe(Id, C, N, V).        (repeated; order = version-descending)
%   md(Id, Key, Value).     (repeated)
%   end_of_vdb_import(EntryCount, MdCount).
%
% Throws permission_error/type_error on any violation.

server:parse_vdb_import(Stream, Hostname, Stamp, Entries, Metadata) :-
  server:read_vdb_term(Stream, First),
  ( First == vdb_import_v1 ->
      true
  ;   throw(error(type_error(vdb_import_v1, First), server:import_vdb/1))
  ),
  server:read_vdb_term(Stream, hostname(Hostname)),
  ( server:valid_hostname(Hostname) ->
      true
  ;   throw(error(permission_error(import, hostname, Hostname),
                  server:import_vdb/1))
  ),
  server:read_vdb_term(Stream, stamp(Stamp)),
  ( Stamp = stamp(Count, Sha),
    integer(Count), Count >= 0,
    server:valid_sha1(Sha) ->
      true
  ;   throw(error(type_error(vdb_import_stamp, Stamp), server:import_vdb/1))
  ),
  server:read_vdb_facts(Stream, 0, 0, Entries, Metadata, Trailer),
  ( Trailer = end_of_vdb_import(EntryCount, MdCount),
    length(Entries, EntryCount),
    length(Metadata, MdCount),
    EntryCount =:= Count,
    findall(Id, member(oe(Id, _, _, _), Entries), EntryIds0),
    sort(EntryIds0, EntryIds),
    length(EntryIds, EntryCount),
    forall(member(md(MdId, _, _), Metadata),
           ord_memberchk(MdId, EntryIds)) ->
      true
  ;   throw(error(type_error(vdb_import_trailer, Trailer), server:import_vdb/1))
  ).


%! server:read_vdb_facts(+Stream, +NE, +NM, -Entries, -Metadata, -Trailer) is det.
%
% Read oe/4 and md/3 facts (preserving order) up to the trailer term,
% validating each fact shape and enforcing the count caps.

server:read_vdb_facts(Stream, NE, NM, Entries, Metadata, Trailer) :-
  server:read_vdb_term(Stream, Term),
  ( Term = end_of_vdb_import(_, _) ->
      Entries = [],
      Metadata = [],
      Trailer = Term
  ; Term = oe(Id, C, N, V) ->
      server:validate_vdb_entry(Id, C, N, V),
      NE1 is NE + 1,
      server:vdb_import_max_entries(MaxE),
      ( NE1 =< MaxE ->
          true
      ;   throw(error(resource_error(vdb_import_entries), server:import_vdb/1))
      ),
      Entries = [Term|RestE],
      server:read_vdb_facts(Stream, NE1, NM, RestE, Metadata, Trailer)
  ; Term = md(Id, Key, Value) ->
      server:validate_vdb_metadata(Id, Key, Value),
      NM1 is NM + 1,
      server:vdb_import_max_metadata(MaxM),
      ( NM1 =< MaxM ->
          true
      ;   throw(error(resource_error(vdb_import_metadata), server:import_vdb/1))
      ),
      Metadata = [Term|RestM],
      server:read_vdb_facts(Stream, NE, NM1, Entries, RestM, Trailer)
  ;   throw(error(type_error(vdb_import_fact, Term), server:import_vdb/1))
  ).


%! server:check_vdb_payload_size(+Payload, +MaxBytes) is det.
%
% Throw a resource error when the payload exceeds MaxBytes, before any
% term is read from it.

server:check_vdb_payload_size(Payload, MaxBytes) :-
  ( string(Payload)
  -> string_length(Payload, Len)
  ;  atom_length(Payload, Len)
  ),
  ( Len =< MaxBytes
  -> true
  ;  throw(error(resource_error(vdb_import_payload), server:import_vdb/1))
  ).


%! server:read_vdb_term(+Stream, -Term) is det.
%
% Read one term from the payload stream, bounded by
% server:vdb_import_max_term_length/1 so a single term cannot exhaust
% memory before the fact-count caps fire. end_of_file is a protocol
% error (the trailer terminates a well-formed payload first).

server:read_vdb_term(Stream, Term) :-
  server:vdb_import_max_term_length(MaxLength),
  read_term(Stream, Term0, [max_term_length(MaxLength)]),
  ( Term0 == end_of_file ->
      throw(error(type_error(vdb_import_term, end_of_file), server:import_vdb/1))
  ;   Term = Term0
  ).


%! server:validate_vdb_entry(+Id, +C, +N, +V) is det.

server:validate_vdb_entry(Id, C, N, V) :-
  ( atom(Id), atom(C), atom(N), ground(V),
    compound(V), functor(V, version, 7),
    atomic_list_concat([C, Pf], '/', Id),
    eapi:packageversion(Pf, ParsedName, ParsedVersion),
    ParsedName == N,
    ParsedVersion == V ->
      true
  ;   throw(error(type_error(vdb_import_entry, oe(Id, C, N, V)),
                  server:import_vdb/1))
  ).


%! server:validate_vdb_metadata(+Id, +Key, +Value) is det.

server:validate_vdb_metadata(Id, Key, Value) :-
  ( atom(Id), atom(Key), ground(Value) ->
      true
  ;   throw(error(type_error(vdb_import_metadata, md(Id, Key, Value)),
                  server:import_vdb/1))
  ).


%! server:valid_sha1(+Sha) is semidet.

server:valid_sha1(Sha) :-
  atom(Sha),
  atom_length(Sha, 40),
  atom_codes(Sha, Codes),
  forall(member(Code, Codes), server:hex_code(Code)).


server:hex_code(Code) :-
  ( between(0'0, 0'9, Code)
  ; between(0'a, 0'f, Code)
  ; between(0'A, 0'F, Code)
  ).


%! server:valid_hostname(+Hostname) is semidet.
%
% Restrictive hostname check: non-empty, max 253 chars, alphanumerics
% plus '.' and '-', not starting with '.' or '-'.

server:valid_hostname(Hostname) :-
  atom(Hostname),
  atom_length(Hostname, Len),
  Len > 0,
  Len =< 253,
  atom_chars(Hostname, Chars),
  Chars = [First|_],
  First \== '.',
  First \== '-',
  forall(member(Ch, Chars),
         ( char_type(Ch, alnum) ; Ch == '.' ; Ch == '-' )).


%! server:assert_client_vdb(+Principal, +Repo, +Stamp, +Bytes, +Entries, +Metadata) is det.
%
% Atomically replace the cache facts for the per-client repository:
% retract any previous import, assert the new ordered entries (preserving
% the client's version-descending order), derive category/package facts,
% and register the import stamp with the knowledgebase.

server:assert_client_vdb(Principal, Repo, Stamp, Bytes, Entries, Metadata) :-
  length(Entries, EntryCount),
  length(Metadata, MetadataCount),
  with_mutex(server_vdb_import,
    ( server:check_vdb_fact_quota(Principal, EntryCount, MetadataCount),
      transaction(
        ( server:retract_client_vdb_facts(Repo),
          forall(member(oe(Id, C, N, V), Entries),
                 assertz(cache:ordered_entry(Repo, Id, C, N, V))),
          forall(member(md(Id, Key, Value), Metadata),
                 assertz(cache:entry_metadata(Repo, Id, Key, Value))),
          findall(C, member(oe(_, C, _, _), Entries), Cs0),
          sort(Cs0, Cs),
          forall(member(C, Cs), assertz(cache:category(Repo, C))),
          findall(C-N, member(oe(_, C, N, _), Entries), CNs0),
          sort(CNs0, CNs),
          forall(member(C-N, CNs), assertz(cache:package(Repo, C, N))),
          assertz(cache:repository(Repo)),
          knowledgebase:register_client_vdb(Principal, Repo, Stamp, Bytes,
                                             EntryCount, MetadataCount)
        ))
    )).


%! server:check_vdb_fact_quota(+Principal, +Entries, +Metadata) is det.

server:check_vdb_fact_quota(Principal, Entries, Metadata) :-
  server:vdb_quota(max_entries, MaxEntries),
  server:vdb_quota(max_metadata, MaxMetadata),
  aggregate_all(sum(E),
                knowledgebase:client_vdb_import(_, _, _, _, E, _, _),
                StoredEntries0),
  aggregate_all(sum(M),
                knowledgebase:client_vdb_import(_, _, _, _, _, M, _),
                StoredMetadata0),
  ( knowledgebase:client_vdb_import(Principal, _, _, _, OldE, OldM, _)
  -> StoredEntries is StoredEntries0 - OldE,
     StoredMetadata is StoredMetadata0 - OldM
  ;  StoredEntries = StoredEntries0,
     StoredMetadata = StoredMetadata0
  ),
  StoredEntries + Entries =< MaxEntries,
  StoredMetadata + Metadata =< MaxMetadata,
  !.
server:check_vdb_fact_quota(_, _, _) :-
  throw(error(resource_error(vdb_import_fact_quota),
              server:assert_client_vdb/6)).


%! server:retract_client_vdb_facts(+Repo) is det.

server:retract_client_vdb_facts(Repo) :-
  retractall(cache:repository(Repo)),
  retractall(cache:category(Repo, _)),
  retractall(cache:package(Repo, _, _)),
  retractall(cache:ordered_entry(Repo, _, _, _, _)),
  retractall(cache:entry_metadata(Repo, _, _, _)).


% =============================================================================
%  Snapshot identification
% =============================================================================

%! server:snapshot(+Repository, -Commit)
%
% Returns the git HEAD commit hash for the portage tree backing Repository.
% Git plumbing lives in the shared Source/Application/System/git.pl module.

server:snapshot(portage, Commit) :-
  portage:get_location(Location),
  git:head_full(Location, Commit).