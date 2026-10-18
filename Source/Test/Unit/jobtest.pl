/*
 Author: Pieter Van den Abeele
 E-mail: pvdabeel@mac.com
 Copyright (c) 2005-2026, Pieter Van den Abeele

 Distributed under the terms of the LICENSE file in the root directory of this
 project.
*/

/** <module> JOBTEST
Lease and route-table tests for distributed proving.
*/

:- module(jobtest, []).

:- use_module(library(plunit)).

% =============================================================================
% JOBTEST declarations
% =============================================================================

:- begin_tests(job_leases).

test(publish_once) :-
  jobs:reset,
  jobs:enqueue(target, job(Id, Token, _Batch, target)),
  jobs:accept(job(Id, Token, 1, target), worker, 1, _),
  jobs:complete(Id, Token, ok, publish(target, ok)),
  jobs:complete(Id, Token, ok, duplicate).

test(stale_token_rejected) :-
  jobs:reset,
  jobs:enqueue(target, job(Id, Token, Batch, target)),
  jobs:accept(job(Id, Token, Batch, target), worker, 1, _),
  jobs:requeue(Id, Token, job(Id, Token2, Batch, target)),
  Token2 \== Token,
  jobs:complete(Id, Token, ok, reject).

test(requeue_keeps_id) :-
  jobs:reset,
  jobs:enqueue(target, job(Id, Token, Batch, target)),
  jobs:accept(job(Id, Token, Batch, target), worker, 1, _),
  jobs:requeue(Id, Token, job(Id, _Token2, Batch, target)).

test(note_result_counts_once) :-
  empty_assoc(Seen),
  jobs:note_result(a, Seen, 2, Seen1, 1),
  jobs:note_result(a, Seen1, 1, _Seen2, 1).

test(routes_cover_proxy_paths) :-
  routes:endpoint(graph_emerge, '/graph_emerge', post),
  routes:endpoint(graph_pmerge, '/graph_pmerge', post),
  routes:endpoint(sync, '/sync', post),
  routes:endpoint(sync_named, '/sync/', post).

:- end_tests(job_leases).
