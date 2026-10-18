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

:- http_handler('/',           reply, [id('portage-ng'), methods([get])]).
:- http_handler('/sync',       reply, [id('sync'),       methods([post]), time_limit(infinite)]).
:- http_handler('/save',       reply, [id('save'),       methods([post])]).
:- http_handler('/load',       reply, [id('load'),       methods([post])]).
:- http_handler('/clear',      reply, [id('clear'),      methods([post])]).
:- http_handler('/graph',      reply, [id('graph'),      methods([post]), time_limit(infinite)]).
:- http_handler('/prove',      reply, [id('prove'),      methods([post]), time_limit(infinite)]).
:- http_handler('/import-vdb', reply, [id('importvdb'),  methods([post]), time_limit(300)]).
:- http_handler('/info',       reply, [id('info'),       methods([get])]).


%! server:start_server
%
% Start an HTTPS Pengine server on config:server_bind/1:config:server_port/1.
% Default bind is localhost: mutating POSTs (/sync, /clear, /load, …) stay
% off the public network. mTLS (peer_cert) + HTTP digest remain mandatory;
% with a shared CA, digest is the main credential — keep passwordfile
% private (make passwordfile) and only widen the bind on a trusted VPN.

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
  server:require_digest_passwordfile(Pwdfile),
  interface:require_digest_password,
  config:server_workers(Workers),
  config:server_keep_alive_timeout(KeepAlive),
  server:server_address(Port, Address),
  server:ensure_queues,
  nl,
  http:http_server(http_dispatch,
                   [ port(Address),
 		     authentication(digest(Pwdfile,Realm)),
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

server:reply(Request) :-
    member(path('/sync'), Request),
    !,
    server:chunked_reply('/sync', kb:sync).

server:reply(Request) :-
    member(path('/save'), Request),
    !,
    server:chunked_reply('/save', kb:save).

server:reply(Request) :-
    member(path('/load'), Request),
    !,
    server:chunked_reply('/load', kb:load).

server:reply(Request) :-
    member(path('/clear'), Request),
    !,
    server:chunked_reply('/clear', kb:clear).

server:reply(Request) :-
    member(path('/graph'), Request),
    !,
    server:chunked_reply('/graph', kb:graph).

server:reply(Request) :-
    member(path('/prove'), Request),
    !,
    server:chunked_reply('/prove', resolver:test_latest(portage,parallel_verbose)).

server:reply(Request) :-
    member(path('/import-vdb'), Request),
    !,
    % Read the POST body before switching the reply to chunked mode.
    http_client:http_read_data(Request, Payload, [to(string)]),
    server:chunked_reply('/import-vdb', server:import_vdb(Payload)).

server:reply(Request) :-
    member(path('/info'), Request),
    !,
    server:chunked_reply('/info', server:info).


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
:- dynamic server:submitted_counter/1.
:- dynamic server:inflight_job/3.
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

%! server:post_job(+Job)
%
% Enqueue a prove target. Job = Repo://Entry:Action.
% Increments the submitted counter so collectors know how many results
% to expect, independently of the job queue size (jobs leave the queue
% the moment a worker dequeues them).

server:post_job(Job) :-
  server:ensure_queues,
  with_mutex(server_progress,
    ( ( retract(server:submitted_counter(N0)) -> true ; N0 = 0 ),
      N is N0 + 1,
      assertz(server:submitted_counter(N))
    )),
  thread_send_message(server_jobs, Job).

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
% timeout. Records the job as in flight for Worker and refreshes the
% worker's liveness timestamp, so stale jobs can be re-queued if the
% worker dies.

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
  ( Timeout == infinite ->
      thread_get_message(server_jobs, Job)
  ; thread_get_message(server_jobs, Job, [timeout(Timeout)])
  ),
  server:worker_heartbeat(Worker),
  ( Job == done -> true
  ; get_time(Now),
    assertz(server:inflight_job(Job, Worker, Now))
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


%! server:post_result(+Job, +Result)
%
% Post a completed proof/plan result back to the server. Succeeds only
% when Job is currently in flight (was dequeued via get_job); clears that
% record. Rejects forged results for jobs the caller never took.

server:post_result(Job, Result) :-
  server:ensure_queues,
  ( retract(server:inflight_job(Job, _Worker, _))
  -> thread_send_message(server_results, result(Job, Result))
  ;  message:warning(['Ignoring post_result for non-inflight job: ', Job]),
     fail
  ).


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


%! server:submitted_count(-N)
%
% Number of jobs submitted since the last progress reset. Unlike
% job_count/1 this does not drop when workers dequeue jobs, so it is
% the authoritative number of results to wait for.

server:submitted_count(N) :-
  ( server:submitted_counter(N0) -> N = N0 ; N = 0 ).


%! server:inflight_count(-N)
%
% Number of jobs currently dequeued by workers but not yet resulted.

server:inflight_count(N) :-
  aggregate_all(count, server:inflight_job(_, _, _), N).


%! server:reset_progress
%
% Reset the submitted counter and in-flight records, and drain both
% queues. Called after a collection cycle completes so the next batch
% starts from a clean state (late stragglers from a previous batch are
% discarded rather than counted against the new batch).

server:reset_progress :-
  server:ensure_queues,
  with_mutex(server_progress,
    ( retractall(server:submitted_counter(_)),
      retractall(server:inflight_job(_, _, _))
    )),
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
  findall(Job-Worker,
          ( server:inflight_job(Job, Worker, Since),
            server:job_is_stale(Worker, Since, Now, Timeout) ),
          Stale),
  forall(member(Job-Worker, Stale),
         server:requeue_job(Job, Worker)).


%! server:job_is_stale(+Worker, +Since, +Now, +Timeout)
%
% True when the worker holding a job is presumed dead.

server:job_is_stale(Worker, _Since, Now, Timeout) :-
  server:registered_worker(Worker, _, LastSeen), !,
  Now - LastSeen > Timeout.

server:job_is_stale(_Worker, Since, Now, Timeout) :-
  Now - Since > Timeout.


%! server:requeue_job(+Job, +Worker)
%
% Put a presumed-lost job back on the job queue.

server:requeue_job(Job, Worker) :-
  retractall(server:inflight_job(Job, _, _)),
  thread_send_message(server_jobs, Job),
  message:warning(['Re-queued job from unresponsive worker ', Worker, ': ', Job]).


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
    server:parse_vdb_import(Stream, Hostname, Stamp, Entries, Metadata),
    close(Stream)),
  atom_concat('pkg@', Hostname, Repo),
  server:assert_client_vdb(Repo, Stamp, Entries, Metadata),
  length(Entries, EntryCount),
  length(Metadata, MdCount),
  format('vdb-import: ok ~w (~d entries, ~d metadata facts)~n',
         [Repo, EntryCount, MdCount]),
  flush_output.


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
  ( Stamp = stamp(Count, Sha), integer(Count), atom(Sha) ->
      true
  ;   throw(error(type_error(vdb_import_stamp, Stamp), server:import_vdb/1))
  ),
  server:read_vdb_facts(Stream, 0, 0, Entries, Metadata, Trailer),
  ( Trailer = end_of_vdb_import(EntryCount, MdCount),
    length(Entries, EntryCount),
    length(Metadata, MdCount),
    EntryCount =:= Count ->
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
  ( atom(Id), atom(C), atom(N),
    ( V == version_none ; compound(V), functor(V, version, 7) ) ->
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


%! server:assert_client_vdb(+Repo, +Stamp, +Entries, +Metadata) is det.
%
% Atomically replace the cache facts for the per-client repository:
% retract any previous import, assert the new ordered entries (preserving
% the client's version-descending order), derive category/package facts,
% and register the import stamp with the knowledgebase.

server:assert_client_vdb(Repo, Stamp, Entries, Metadata) :-
  with_mutex(server_vdb_import,
    ( retractall(cache:repository(Repo)),
      retractall(cache:category(Repo, _)),
      retractall(cache:package(Repo, _, _)),
      retractall(cache:ordered_entry(Repo, _, _, _, _)),
      retractall(cache:entry_metadata(Repo, _, _, _)),
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
      knowledgebase:register_client_vdb(Repo, Stamp)
    )).


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