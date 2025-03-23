/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2025, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> CLUSTER
Allows to create a cluster that uses several nodes in a cluster to prove entries.
*/

:- module(cluster, []).

% ********************
% CLUSTER declarations
% ********************

create_result_queue :-
  message_queue_create('result').

create_job_queue :-
  message_queue_create('job').


post_job(Job) :-
  thread_send_message('job',Job).

get_job(Job) :-
  client:rpc_execute('imac-pro.local',4000,thread_get_message('job',Job),_).


post_result(Result) :-
  client:rpc_execute('imac-pro.local',4000,thread_send_message('result',Result),_).

get_result(Result) :-
  client:rpc_execute('imac-pro.local',4000,thead_get_message('result',Result),_).


create_workers(N) :-
  forall(between(1, N, _),
    thread_create(do_work, _, [])).

init_work :-
  forall(cache:ordered_entry(R,I,_,_,_),post_job(R://I:run)).

do_work :-
  repeat,
   get_job(Job),
   ( catch((prover:prove(Job,[],Proof,[],_,[],_),
            post_result([Job,Proof])),
           E, print_message(error, E))
      ->  true
      ;   print_message(error, goal_failed(Job, worker('job')))
   ),
   fail.


