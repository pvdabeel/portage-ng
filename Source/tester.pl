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
  stats:newinstance(stat),
  stats:count(Generator,S),
  stats:init(0,S),
  config:time_limit(T),
  forall(Generator,
              (catch(call_with_time_limit(T,(stats:increase,
                                             stats:percentage(P),
                                             stats:runningtime(Min,Sec),
                                             message:title([Name,' (Single thread): ',P,' processed in ',Min,'m ',Sec,'s']),
                                             Test,!,
                                             message:scroll_notice([Name,' at:',P,' - Ebuild: ',Item]))),
                     time_limit_exceeded,
                     message:scroll_failure([Item,' (time limit exceeded)']));
	       (message:clean,message:failure(Item)))),!,
  stats:runningtime(Min,Sec),
  message:title_reset,!,
  message:scroll_notice([Name,' ',S,' ',Repository,' entries took ',Min,'m ',Sec,'s. (single thread)']).


tester:test(parallel_verbose,Name,Repository://Item,Generator,Test) :-
  stats:newinstance(stat),
  stats:count(Generator,S),
  stats:init(0,S),
  config:time_limit(T),
  config:number_of_cpus(Cpus),
  findall((catch(call_with_time_limit(T,(Test,!,
                                         with_mutex(mutex,(stats:increase,
                                                           stats:percentage(P),
                                                           stats:runningtime(Min,Sec),
                                                           message:title([Name,' (',Cpus,' threads): ',P,' processed in ',Min,'m ',Sec,'s']),
                                                           message:scroll_notice([Name,' at:',P,' - Ebuild: ',Item])
                                                          )))),
                 time_limit_exceeded,
                 message:scroll_failure([Item,' (time limit exceeded)']));
           (sleep(1),message:clean,message:failure(Item))),
          Generator,
          Calls),!,
  concurrent(Cpus,Calls,[]),
  stats:runningtime(Min,Sec),
  message:title_reset,!,
  message:clean,
  message:scroll_notice([Name,' ',S,' ',Repository,' entries took ',Min,'m ',Sec,'s. (',Cpus,' threads)']).


tester:test(parallel_fast,Name,Repository://Item,Generator,Test) :-
  stats:newinstance(stat),
  stats:count(Generator,S),
  stats:init(0,S),
  config:number_of_cpus(Cpus),
  message:title([Name,' (',Cpus,' threads) - No intermediate output']),
  flush_output,
  findall((Test,!;
           message:failure(Item)),
          Generator,
          Calls),
  concurrent(Cpus,Calls,[]),
  stats:runningtime(Min,Sec),!,
  message:title_reset,!,
  message:scroll_notice([Name,' ',S,' ',Repository,' entries took ',Min,'m ',Sec,'s. (',Cpus,' threads)']).
