/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> JOBSERVER
Local job server for parallel build execution.

Manages a pool of worker threads that pull jobs from a shared queue and
post results back. The builder submits jobs grouped by plan step and
collects results with a display callback.

Transport: in standalone mode, jobs and results flow through SWI-Prolog
message queues (thread_send_message/thread_get_message). The API is
designed so that a future transport layer (IPC or HTTP) can front the
same interface to accept remote workers.
*/

:- module(jobserver, []).

% =============================================================================
%  Queue management
% =============================================================================

:- dynamic jobserver:queue_created/1.

%! jobserver:ensure_queues is det.
%
% Create the job and result message queues (idempotent).

jobserver:ensure_queues :-
  ( jobserver:queue_created(true) -> true
  ; message_queue_create(build_jobs),
    message_queue_create(build_results),
    assertz(jobserver:queue_created(true))
  ).


%! jobserver:post_job(+Job) is det.
%
% Enqueue a build job.

jobserver:post_job(Job) :-
  thread_send_message(build_jobs, Job).


%! jobserver:get_job(-Job) is det.
%
% Dequeue a build job (blocks until one is available).

jobserver:get_job(Job) :-
  thread_get_message(build_jobs, Job).


%! jobserver:post_result(+Job, +Result) is det.
%
% Post a completed job result.

jobserver:post_result(Job, Result) :-
  thread_send_message(build_results, result(Job, Result)).


%! jobserver:get_result(-Job, -Result) is det.
%
% Collect a result (blocks until one is available).

jobserver:get_result(Job, Result) :-
  thread_get_message(build_results, result(Job, Result)).


% =============================================================================
%  Worker pool
% =============================================================================

%! jobserver:init(+NumWorkers, +Executor) is det.
%
% Create queues and spawn NumWorkers threads. Each thread runs a poll
% loop calling Executor for every job it picks up.
% Executor is a goal with signature call(Executor, Job, Slot, Result).

jobserver:init(NumWorkers, Executor) :-
  jobserver:ensure_queues,
  jobserver:spawn_workers(NumWorkers, Executor).


%! jobserver:spawn_workers(+N, +Executor) is det.

jobserver:spawn_workers(N, Executor) :-
  forall(between(1, N, I),
    ( atom_concat(build_worker_, I, Alias),
      thread_create(jobserver:worker_loop(I, Executor), _, [alias(Alias)])
    )).


%! jobserver:worker_loop(+Slot, +Executor) is det.
%
% Poll loop: get a job, execute it, post the result. The Slot index
% identifies this worker for display purposes. Exits when it receives
% the atom 'done'.

jobserver:worker_loop(Slot, Executor) :-
  repeat,
    jobserver:get_job(Job),
    ( Job == done
    -> !
    ; ( catch(
          call(Executor, Job, Slot, Result),
          Error,
          Result = error(Error)
        )
      -> jobserver:post_result(Job, Result)
      ;  jobserver:post_result(Job, failed)
      ),
      fail
    ).


%! jobserver:shutdown(+NumWorkers) is det.
%
% Send a 'done' sentinel for each worker, then join all worker threads.

jobserver:shutdown(NumWorkers) :-
  forall(between(1, NumWorkers, _), jobserver:post_job(done)),
  forall(between(1, NumWorkers, I),
    ( atom_concat(build_worker_, I, Alias),
      ( catch(thread_join(Alias, _), _, true) -> true ; true )
    )).


% =============================================================================
%  Step-oriented helpers
% =============================================================================

%! jobserver:submit(+Jobs) is det.
%
% Post a list of jobs to the queue.

jobserver:submit(Jobs) :-
  forall(member(J, Jobs), jobserver:post_job(J)).


%! jobserver:collect(+Expected, +Callback) is det.
%
% Collect Expected results, calling Callback for each.
% Callback signature: call(Callback, Slot, Result).

jobserver:collect(0, _Callback) :- !.

jobserver:collect(Remaining, Callback) :-
  jobserver:get_result(_Job, Result),
  ( Result = result(Slot, Outcome)
  -> call(Callback, Slot, Outcome)
  ; true
  ),
  R1 is Remaining - 1,
  jobserver:collect(R1, Callback).
