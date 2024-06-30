/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2024, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> TESTER
Description

Input:

Output:

*/

:- module(tester,[]).

% *******************
% TESTER declarations
% *******************

tester:test(single_verbose,Name,Repository://Item,Generator,Test) :-
  Repository:get_size(S),
  stats:newinstance(stat),
  stats:init(0,S),
  config:time_limit(T),
  time(forall(Generator,
              (catch(call_with_time_limit(T,(stats:increase,
                                             stats:percentage(P),
                                             stats:runningtime(Min,Sec),
                                             message:title([Name,' (Single thread): ',P,' processed in ',Min,'m ',Sec,'s']),
                                             Test,!,
                                             message:success([P,' - ',Item]))),
                     time_limit_exceeded,
                     message:failure([Item,' (time limit exceeded)']));
	       message:failure(Item)))),!,
  stats:runningtime(Min,Sec),
  message:title_reset,!,
  message:inform([Name,' ',S,' ',Repository,' entries took ',Min,'m ',Sec,'s.']).


tester:test(parallel_verbose,Name,Repository://Item,Generator,Test) :-
  Repository:get_size(S),
  stats:newinstance(stat),
  stats:init(0,S),
  config:time_limit(T),
  config:number_of_cpus(Cpus),
  findall((catch(call_with_time_limit(T,(Test,!,
                                         with_mutex(mutex,(stats:increase,
                                                           stats:percentage(P),
                                                           stats:runningtime(Min,Sec),
                                                           message:title([Name,' (',Cpus,' threads): ',P,' processed in ',Min,'m ',Sec,'s']),
                                                           message:success([P,' - ',Item]))))),
                 time_limit_exceeded,
                 message:failure([Item,' (time limit exceeded)']));
           message:failure(Item)),
          Generator,
          Calls),!,
  time(concurrent(Cpus,Calls,[])),
  stats:runningtime(Min,Sec),
  message:title_reset,!,
  message:inform([Name,' ',S,' ',Repository,' entries took ',Min,'m ',Sec,'s.']).


tester:test(parallel_fast,Name,Repository://Item,Generator,Test) :-
  Repository:get_size(S),
  stats:newinstance(stat),
  stats:init(0,S),
  config:number_of_cpus(Cpus),
  findall((Test,!;
           message:failure(Item)),
          Generator,
          Calls),
  time(concurrent(Cpus,Calls,[])),
  stats:runningtime(Min,Sec),!,
  message:inform([Name,' ',S,' ',Repository,' entries took ',Min,'m ',Sec,'s.']).
