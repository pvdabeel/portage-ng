/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2025, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> WORKER
A proof of concept: use a message queue to send finished plans for
printing to the printer
*/

:- module(worker, []).

% *******************
% WORKER declarations
% *******************

worker:master :-
  message_queue_create('worker:jobqueue'),
  thread_create(worker:create_jobs,_,[detached(true)]),
  worker:execute_jobs.

worker:create_jobs :-
  portage:get_size(S),
  stats:init(0,S),
  config:proving_target(Action),
  config:number_of_cpus(Cpus),
  findall((prover:prove(portage://E:Action,[],Proof,[],Model,[],_Constraints),!,
           planner:plan(Proof,[],[],Plan),
           thread_send_message('worker:jobqueue',
                               (stats:increase,
                                stats:percentage(P),
                                stats:runningtime(Min,Sec),
                                message:title(['Printing plan (',Cpus,' threads): ',P,' processed in ',Min,'m ',Sec,'s']),
                                nl,message:topheader(['[',P,'] - Printing plan for ',portage://E:Action]),
                                printer:print(portage://E:Action,Model,Proof,Plan)),
                               [timeout(60)])),
          portage:entry(E),
          Calls),
  concurrent(Cpus,Calls,[]),!,
  thread_send_message('worker:jobqueue',
                      (stats:runningtime(Min,Sec),
                       message:title_reset,
                       message:inform(['printed plan for ',S,' portage entries in ',Min,'m ',Sec,'s.'])),
                      [timeout(60)]).

worker:execute_jobs :-
  repeat,
    thread_get_message('worker:jobqueue', Job),
    Job,
  fail.

