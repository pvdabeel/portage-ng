/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> CLUSTER
High-level orchestration for distributed proving across a cluster of workers.
The server side creates job and result queues, advertises its portage tree
snapshot via Bonjour, submits prove targets, and collects results from workers.
*/

:- module(cluster, []).

% =============================================================================
%  Initialization
% =============================================================================

%! cluster:init
%
% Initialize the cluster on the server side: create queues, advertise the
% server and its portage snapshot on the network.

cluster:init :-
  server:ensure_queues,
  bonjour:advertise,
  ( server:snapshot(portage, Commit) ->
      message:inform(['Cluster initialized. Portage snapshot: ', Commit])
  ; message:inform(['Cluster initialized. (snapshot not available)'])
  ).


% =============================================================================
%  Job submission
% =============================================================================

%! cluster:submit(+Targets)
%
% Submit a list of prove targets to the job queue.

cluster:submit(Targets) :-
  length(Targets, N),
  server:submit_targets(Targets),
  message:inform(['Submitted ', N, ' jobs to cluster.']).

%! cluster:submit_all(+Action)
%
% Submit all portage entries with the given Action (e.g. run).

cluster:submit_all(Action) :-
  server:submit_all(portage, Action),
  server:job_count(N),
  message:inform(['Submitted ', N, ' jobs to cluster.']).


% =============================================================================
%  Result collection
% =============================================================================

%! cluster:wait(-Results)
%
% Block until the job queue is drained and all results are collected.
% Returns a list of result terms.

cluster:wait(Results) :-
  cluster:collect_results([], Results).

cluster:collect_results(Acc, Results) :-
  ( server:get_result(Job, Result, 60) ->
      cluster:collect_results([result(Job, Result)|Acc], Results)
  ; server:job_count(Remaining),
    ( Remaining > 0 ->
        cluster:collect_results(Acc, Results)
    ; reverse(Acc, Results)
    )
  ).


% =============================================================================
%  Worker discovery
% =============================================================================

%! cluster:discover_workers(-Workers)
%
% Discover worker nodes advertising on the network via Bonjour.
% Workers is a list of [Hostname, Port] pairs.

cluster:discover_workers(Workers) :-
  config:bonjour_worker_service(Service),
  bonjour:discover(Service, Workers).


% =============================================================================
%  Status
% =============================================================================

%! cluster:status
%
% Print current cluster status: workers, queue depths, snapshot.

cluster:status :-
  server:workers(Workers),
  server:total_cpus(TotalCpus),
  server:job_count(Jobs),
  server:result_count(ResultCount),
  ( server:snapshot(portage, Commit) -> true ; Commit = unknown ),
  length(Workers, NWorkers),
  nl,
  message:topheader(['Cluster status']),
  format('  Snapshot:        ~w~n', [Commit]),
  format('  Workers:         ~d (~d total CPUs)~n', [NWorkers, TotalCpus]),
  format('  Jobs pending:    ~d~n', [Jobs]),
  format('  Results ready:   ~d~n', [ResultCount]),
  ( Workers \== [] ->
      format('~n  Registered workers:~n'),
      forall(member(H-C, Workers),
             format('    ~w  (~d CPUs)~n', [H, C]))
  ; true
  ),
  nl.


% =============================================================================
%  Convenience: end-to-end distributed prove
% =============================================================================

%! cluster:prove_all(+Action, -Results)
%
% Submit all portage entries, wait for results. Assumes cluster:init
% has been called and workers are connected.

cluster:prove_all(Action, Results) :-
  cluster:submit_all(Action),
  cluster:wait(Results).

%! cluster:prove_targets(+Targets, -Results)
%
% Submit specific targets, wait for results.

cluster:prove_targets(Targets, Results) :-
  cluster:submit(Targets),
  cluster:wait(Results).