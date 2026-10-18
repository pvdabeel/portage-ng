/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> WORKER
Compute node for distributed proving. A worker advertises its CPU count on
the network, connects to a pinned portage-ng server (config:server_host/1
or --host; Bonjour may resolve only that pin), syncs its local portage
tree to the server's full git snapshot SHA when the object already exists
locally, then polls for prove jobs and posts back results.

Each worker spawns N threads (one per CPU) that independently poll the
server's job queue.
*/

:- module(worker, []).

% =============================================================================
%  Worker configuration
% =============================================================================

%! worker:cpus(-N)
%
% Number of CPUs this worker will contribute. Falls back to config.

worker:cpus(N) :-
  ( config:number_of_cpus(N) -> true ; N = 1 ).


% =============================================================================
%  Lifecycle
% =============================================================================

%! worker:start(+Host, +Port)
%
% Start the worker: sync KB to server snapshot, advertise on the network,
% register with the server, then enter the poll loop with N threads.

worker:start(Host, Port) :-
  worker:cpus(Cpus),
  worker:sync_to_server(Host, Port),
  worker:advertise(Cpus),
  worker:register(Host, Port, Cpus),
  worker:spawn_threads(Host, Port, Cpus),
  message:inform(['Worker running with ', Cpus, ' threads. Polling ', Host, ':', Port]).

%! worker:start
%
% Discover servers via Bonjour, but only connect to a host that matches
% config:server_host/1 (or --host). First-match on a hostile LAN is
% rejected when the pin does not match — set server_host explicitly.

worker:start :-
  config:server_host(Pinned),
  bonjour:discover(Hosts),
  ( member([Host, Port], Hosts),
    worker:host_matches_pin(Host, Pinned)
  -> worker:start(Host, Port)
  ;  message:failure(['No trusted portage-ng server found on the network ',
                      '(pin config:server_host=', Pinned, '). ',
                      'Pass --host explicitly or fix the pin; do not trust ',
                      'unpinned Bonjour advertisements.'])
  ).


%! worker:host_matches_pin(+Host, +Pinned) is semidet.
%
% True when a Bonjour instance name matches the configured server pin
% (exact atom match, or Host equals Pinned with/without a trailing
% `.local` suffix).

worker:host_matches_pin(Host, Pinned) :-
  Host == Pinned,
  !.

worker:host_matches_pin(Host, Pinned) :-
  atom_concat(Pinned, '.local', Host),
  !.

worker:host_matches_pin(Host, Pinned) :-
  atom_concat(Host, '.local', Pinned).


% =============================================================================
%  Snapshot synchronization
% =============================================================================

%! worker:sync_to_server(+Host, +Port)
%
% Query the server for its portage tree snapshot, then sync the local
% portage tree to the same git commit. Checkout only proceeds when the
% full hex object already exists locally (git:checkout/2); there is no
% fetch from the server — sync the tree from your trusted remote first.

worker:sync_to_server(Host, Port) :-
  message:inform(['Querying server snapshot from ', Host, ':', Port, '...']),
  client:rpc_execute(Host, Port, server:snapshot(portage, Commit)),
  !,
  message:inform(['Server snapshot: ', Commit]),
  worker:sync_to_commit(Commit).

worker:sync_to_server(_, _) :-
  message:inform(['Could not query server snapshot; using local KB as-is.']).

%! worker:sync_to_commit(+Commit)
%
% Checkout the given commit in the local portage tree and reload the KB.
% Commit must be a full hex object name already present in the local
% object store (see git:checkout/2).

worker:sync_to_commit(Commit) :-
  portage:get_location(Location),
  git:head_full(Location, LocalHead),
  ( LocalHead == Commit ->
      message:inform(['Local tree already at ', Commit, '.'])
  ; message:inform(['Syncing local tree to ', Commit, '...']),
    git:checkout(Location, Commit),
    kb:load
  ).


% =============================================================================
%  Network advertisement and registration
% =============================================================================

%! worker:advertise(+Cpus)
%
% Advertise this worker on the network via Bonjour.

worker:advertise(Cpus) :-
  config:hostname(Host),
  config:bonjour_worker_service(Service),
  bonjour:advertise(Service, Host, Cpus).


%! worker:register(+ServerHost, +ServerPort, +Cpus)
%
% Register this worker with the server.

worker:register(ServerHost, ServerPort, Cpus) :-
  config:hostname(Hostname),
  get_time(Now),
  client:rpc_execute(ServerHost, ServerPort,
                     server:register_worker(Hostname, Cpus, Now)).


% =============================================================================
%  Job polling
% =============================================================================

:- dynamic worker:stopping/0.

%! worker:spawn_threads(+Host, +Port, +N)
%
% Spawn N worker threads, each running the poll loop independently.

worker:spawn_threads(Host, Port, N) :-
  retractall(worker:stopping),
  forall(between(1, N, I),
         ( atom_concat(worker_thread_, I, Alias),
           thread_create(worker:poll_loop(Host, Port), _, [alias(Alias)])
         )).


%! worker:poll_loop(+Host, +Port)
%
% Repeatedly poll the server for a job, execute it locally, and post the
% result back. Runs until the server signals `done` or a sibling thread
% has set the shared worker:stopping flag.
%
% RPC exceptions (connection refused, TLS handshake, server restart) are
% caught and logged; the thread backs off exponentially (capped at 60s)
% and keeps polling instead of dying silently.

worker:poll_loop(Host, Port) :-
  worker:poll_loop(Host, Port, 1).

worker:poll_loop(Host, Port, Backoff) :-
  ( worker:stopping ->
      worker:log_stop
  ; catch(worker:poll_once(Host, Port, Continue),
          Error,
          ( thread_self(Thread),
            message:warning(['Worker ', Thread, ': RPC error: ', Error,
                             '. Retrying in ', Backoff, 's.']),
            Continue = backoff )),
    ( Continue == stop ->
        worker:log_stop
    ; Continue == backoff ->
        sleep(Backoff),
        NextBackoff is min(Backoff * 2, 60),
        worker:poll_loop(Host, Port, NextBackoff)
    ; worker:poll_loop(Host, Port, 1)
    )
  ).


%! worker:log_stop
%
% Log that the current poll thread is shutting down.

worker:log_stop :-
  thread_self(Thread),
  message:inform(['Worker ', Thread, ': stopping.']).


%! worker:poll_once(+Host, +Port, -Continue)
%
% Fetch one job, execute, post result. Continue = continue | stop.
% Identifies itself by hostname so the server can track in-flight job
% ownership and worker liveness (stale jobs get re-queued).
%
% On `done`, the shared worker:stopping flag is set so sibling threads
% stop on their next iteration as well; the server additionally
% broadcasts `done` to every polling thread once server:stop_workers
% has been called, so all threads of all workers wind down.

worker:poll_once(Host, Port, Continue) :-
  config:hostname(Hostname),
  ( client:rpc_execute(Host, Port, server:get_job(Job, 30, Hostname)) ->
      ( Job == done ->
          ( worker:stopping -> true ; assertz(worker:stopping) ),
          Continue = stop
      ; Job = job(Id, Token, Target),
        worker:with_lease_heartbeat(Host, Port, Id, Token,
          worker:execute_job(Target, Result)),
        worker:post_result(Host, Port, Id, Token, Result),
        Continue = continue
      )
  ; Continue = continue
  ).


%! worker:post_result(+Host, +Port, +Id, +Token, +Result)
%
% Post a computed result back to the server, retrying with backoff so a
% transient RPC failure does not discard an already-computed result. If
% all attempts fail, the result is dropped with a warning; the server
% re-queues the job once this worker is presumed dead (stale-job
% re-queueing), so the job is not lost. A repeat post of the same id is
% accepted by the server without publishing a second result.

worker:post_result(Host, Port, Id, Token, Result) :-
  between(1, 5, Attempt),
  ( catch(client:rpc_execute(Host, Port, server:post_result(Id, Token, Result)),
          Error,
          ( message:warning(['Posting result for job ', Id, ' failed (attempt ',
                             Attempt, '): ', Error]),
            fail ))
  -> !
  ; ( Attempt =:= 5 ->
        message:warning(['Dropping result for job ', Id,
                         '; server will re-queue the job.'])
    ; Wait is 2 ** Attempt,
      sleep(Wait),
      fail
    )
  ).


%! worker:with_lease_heartbeat(+Host, +Port, +Id, +Token, :Goal)
%
% Run Goal while a side thread renews the lease. The heartbeat stops
% when Goal finishes, succeeds or throws.

worker:with_lease_heartbeat(Host, Port, Id, Token, Goal) :-
  thread_create(worker:heartbeat_loop(Host, Port, Id, Token), Tid, []),
  setup_call_cleanup(true, call(Goal), worker:stop_heartbeat(Tid)).


%! worker:stop_heartbeat(+Tid) is det.

worker:stop_heartbeat(Tid) :-
  catch(thread_send_message(Tid, stop), _, true),
  catch(thread_join(Tid, _), _, true).


%! worker:heartbeat_loop(+Host, +Port, +Id, +Token) is det.
%
% Renew Id's lease until this thread receives stop.

worker:heartbeat_loop(Host, Port, Id, Token) :-
  thread_self(Me),
  worker:heartbeat_interval(Seconds),
  repeat,
  ( thread_get_message(Me, stop, [timeout(Seconds)])
  -> !
  ; catch(client:rpc_execute(Host, Port, server:renew_lease(Id, Token)), _, true),
    fail
  ).


%! worker:heartbeat_interval(-Seconds) is det.
%
% How often a live proof renews its lease. Short enough that
% config:cluster_worker_timeout/1 measures liveness rather than the
% length of the proof, and at least five seconds.

worker:heartbeat_interval(Seconds) :-
  config:cluster_worker_timeout(Timeout),
  Step is Timeout // 3,
  Seconds is max(5, min(30, Step)).


% =============================================================================
%  Job execution
% =============================================================================

%! worker:execute_job(+Job, -Result)
%
% Run the canonical pipeline (prover + orderer) for a single
% target through pipeline:prove_plan_with_fallback/6, so workers use the
% same 5-tier committed-choice fallback chain (strict, keyword_acceptance,
% blockers, unmask, keyword_unmask) as standalone mode.
%
% Returns a compact result — plan steps, relaxation tier and assumption
% summary — rather than the full Proof/Model/Constraints/Triggers AVLs,
% keeping the Pengine RPC payload small.
%
% Result = plan(Job, Plan, Tier, assumptions(DomainCount, CycleBreakCount))
%        | failed(Job)
%        | error(Job, Error)

worker:execute_job(Job, Result) :-
  worker:job_goals(Job, Goals),
  ( catch(
      ( pipeline:prove_plan_with_fallback(Goals, ProofAVL, _ModelAVL, Plan,
                                          _TriggersAVL, Tier),
        worker:assumption_summary(ProofAVL, Summary),
        Result = plan(Job, Plan, Tier, Summary)
      ),
      Error,
      Result = error(Job, Error)
    ) -> true
  ; Result = failed(Job)
  ).


%! worker:job_goals(+Job, -Goals)
%
% Wrap a job target in a goal list, attaching an empty `?{Context}` list
% unless the job already carries one.

worker:job_goals(Job, [Job]) :-
  Job = _?{_}, !.

worker:job_goals(Job, [Job?{[]}]).


%! worker:assumption_summary(+ProofAVL, -Summary)
%
% Compact assumption summary for RPC transport:
% assumptions(DomainCount, CycleBreakCount). Domain assumptions use the
% proof key rule(assumed(_)); prover cycle breaks use assumed(rule(_)).

worker:assumption_summary(ProofAVL, assumptions(Domain, CycleBreaks)) :-
  aggregate_all(count, assoc:gen_assoc(rule(assumed(_)), ProofAVL, _), Domain),
  aggregate_all(count, assoc:gen_assoc(assumed(rule(_)), ProofAVL, _), CycleBreaks).