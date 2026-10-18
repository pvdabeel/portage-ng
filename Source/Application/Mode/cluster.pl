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
%  CLUSTER declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Initialization
% -----------------------------------------------------------------------------

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


% ---------------------------------------------------------------------------------
%  Job submission
% ---------------------------------------------------------------------------------

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
  server:submitted_count(Before),
  server:submit_all(portage, Action),
  server:submitted_count(After),
  N is After - Before,
  message:inform(['Submitted ', N, ' jobs to cluster.']).


% ---------------------------------------------------------------------------------
%  Result collection
% ---------------------------------------------------------------------------------

%! cluster:wait(-Results)
%
% Block until one result has been collected for every submitted job, or
% until the global deadline (config:cluster_global_deadline/1) expires.
% Completion is tracked against the submitted counter, not the job
% queue size: an empty job queue only means all jobs are in flight, not
% that all work is done. While waiting, jobs held by workers that have
% stopped responding (config:cluster_worker_timeout/1) are re-queued so
% they can be picked up by surviving workers. Returns a list of result
% terms; warns if the deadline was reached with results still missing.

cluster:wait(Results) :-
  server:submitted_count(Expected),
  config:cluster_result_timeout(Poll),
  config:cluster_global_deadline(MaxWait),
  get_time(Now),
  Deadline is Now + MaxWait,
  empty_assoc(Seen),
  cluster:collect_results(Expected, Seen, Deadline, Poll, [], Results),
  length(Results, Collected),
  ( Collected < Expected ->
      Missing is Expected - Collected,
      message:warning(['Cluster deadline reached: collected ', Collected, '/',
                       Expected, ' results (', Missing, ' missing).'])
  ; true
  ),
  server:reset_progress.

%! cluster:collect_results(+Remaining, +Seen, +Deadline, +Poll, +Acc, -Results)
%
% Collect results until Remaining hits zero or Deadline passes. Seen is
% an assoc of submission ids already counted. A duplicate id does not
% decrement Remaining, so a requeued job that finishes twice cannot
% hide a different job that never returned.

cluster:collect_results(0, _, _, _, Acc, Results) :-
  !,
  reverse(Acc, Results).
cluster:collect_results(Remaining, Seen, Deadline, Poll, Acc, Results) :-
  get_time(Now),
  ( Now >= Deadline ->
      reverse(Acc, Results)
  ; Wait is min(Poll, Deadline - Now),
    ( server:get_result(Id, Target, Result, Wait) ->
        jobs:note_result(Id, Seen, Remaining, Seen1, Remaining1),
        ( Remaining1 < Remaining
        -> cluster:collect_results(Remaining1, Seen1, Deadline, Poll,
                                   [result(Target, Result)|Acc], Results)
        ;  cluster:collect_results(Remaining, Seen1, Deadline, Poll, Acc, Results)
        )
    ; config:cluster_worker_timeout(LivenessTimeout),
      server:requeue_stale_jobs(LivenessTimeout),
      cluster:collect_results(Remaining, Seen, Deadline, Poll, Acc, Results)
    )
  ).


% ---------------------------------------------------------------------------------
%  Worker discovery
% ---------------------------------------------------------------------------------

%! cluster:discover_workers(-Workers)
%
% Discover worker nodes advertising on the network via Bonjour.
% Workers is a list of [Hostname, Port] pairs.

cluster:discover_workers(Workers) :-
  config:bonjour_worker_service(Service),
  bonjour:discover(Service, Workers).


% ---------------------------------------------------------------------------------
%  Status
% ---------------------------------------------------------------------------------

%! cluster:status
%
% Print current cluster status: workers, queue depths, snapshot.

cluster:status :-
  server:workers(Workers),
  server:total_cpus(TotalCpus),
  server:job_count(Jobs),
  server:inflight_count(InFlight),
  server:result_count(ResultCount),
  ( server:snapshot(portage, Commit) -> true ; Commit = unknown ),
  length(Workers, NWorkers),
  nl,
  message:topheader(['Cluster status']),
  format('  Snapshot:        ~w~n', [Commit]),
  format('  Workers:         ~d (~d total CPUs)~n', [NWorkers, TotalCpus]),
  format('  Jobs pending:    ~d~n', [Jobs]),
  format('  Jobs in flight:  ~d~n', [InFlight]),
  format('  Results ready:   ~d~n', [ResultCount]),
  ( Workers \== [] ->
      format('~n  Registered workers:~n'),
      forall(member(H-C, Workers),
             format('    ~w  (~d CPUs)~n', [H, C]))
  ; true
  ),
  nl.


% ---------------------------------------------------------------------------------
%  Convenience: end-to-end distributed prove
% ---------------------------------------------------------------------------------

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