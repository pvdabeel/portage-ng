/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> WORKER
Compute node for distributed proving. A worker advertises its CPU count on
the network, discovers a portage-ng server via Bonjour, syncs its local
portage tree to the server's git snapshot, then polls for prove jobs and
posts back results.

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
% Discover a server via Bonjour, then start.

worker:start :-
  bonjour:discover(Hosts),
  ( Hosts = [[Host, Port]|_] ->
      worker:start(Host, Port)
  ; message:failure('No portage-ng server found on the network.')
  ).


% =============================================================================
%  Snapshot synchronization
% =============================================================================

%! worker:sync_to_server(+Host, +Port)
%
% Query the server for its portage tree snapshot, then sync the local
% portage tree to the same git commit.

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

worker:sync_to_commit(Commit) :-
  portage:get_location(Location),
  server:git_head(Location, LocalHead),
  ( LocalHead == Commit ->
      message:inform(['Local tree already at ', Commit, '.'])
  ; message:inform(['Syncing local tree to ', Commit, '...']),
    worker:git_checkout(Location, Commit),
    kb:load
  ).

%! worker:git_checkout(+Dir, +Commit)
%
% Checkout a specific commit in a git repository.

worker:git_checkout(Dir, Commit) :-
  process_create(path(git), ['checkout', Commit],
                 [stdout(null), stderr(null), cwd(Dir), process(Pid)]),
  process_wait(Pid, Status),
  ( Status == exit(0) -> true
  ; message:failure(['git checkout failed for ', Commit, ' in ', Dir])
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

%! worker:spawn_threads(+Host, +Port, +N)
%
% Spawn N worker threads, each running the poll loop independently.

worker:spawn_threads(Host, Port, N) :-
  forall(between(1, N, I),
         ( atom_concat(worker_thread_, I, Alias),
           thread_create(worker:poll_loop(Host, Port), _, [alias(Alias)])
         )).

%! worker:poll_loop(+Host, +Port)
%
% Repeatedly poll the server for a job, execute it locally, and post
% the result back. Runs until the server sends the `done` sentinel.

worker:poll_loop(Host, Port) :-
  repeat,
    worker:poll_once(Host, Port, Continue),
    Continue == stop,
  !.

%! worker:poll_once(+Host, +Port, -Continue)
%
% Fetch one job, execute, post result. Continue = continue | stop.

worker:poll_once(Host, Port, Continue) :-
  ( client:rpc_execute(Host, Port, server:get_job(Job, 30)) ->
      ( Job == done ->
          Continue = stop
      ; worker:execute_job(Job, Result),
        client:rpc_execute(Host, Port, server:post_result(Job, Result)),
        Continue = continue
      )
  ; Continue = continue
  ).


% =============================================================================
%  Job execution
% =============================================================================

%! worker:execute_job(+Job, -Result)
%
% Run the prover + planner + scheduler pipeline for a single target.
% Result = plan(Plan) | error(Error).

worker:execute_job(Job, Result) :-
  ( catch(
      ( prover:prove(Job, [], Proof, [], Model, [], Cons, [], Triggers),
        !,
        planner:plan(Proof, Triggers, [], Plan0, Remainder0),
        scheduler:schedule(Proof, Triggers, Plan0, Remainder0, Plan, _Remainder),
        Result = plan(Job, Proof, Model, Cons, Plan, Triggers)
      ),
      Error,
      Result = error(Job, Error)
    ) -> true
  ; Result = failed(Job)
  ).
