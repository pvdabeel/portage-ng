/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2025, Pieter Van den Abeele

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

tester:test(Style,Name,Repository://Item,Generator,Test) :-
  !,
  tester:test(Style,Name,Repository://Item,Generator,Test,true,true).


tester:test(single_verbose,Name,Repository://Item,Generator,Test,Report,Scroll) :-
  stats:times(Generator,S),
  stats:init(0,S),
  config:time_limit(T),
  message:hc,
  forall(Generator,
              (catch(call_with_time_limit(T,(stats:increase,
                                             stats:percentage(P),
                                             stats:runningtime(Min,Sec),
                                             message:title([Name,' (Single thread): ',P,' processed in ',Min,'m ',Sec,'s']),
                                             (Scroll
 				              -> message:scroll_notice(['[',P,'] - ', Name,' ',Repository,'://',Item])
                                              ;  message:topheader(['[',P,'] - ',Name,' ',Repository,'://',Item])),
					     Test,!,Report)),
                     time_limit_exceeded,
                     message:scroll_failure([Item,' (time limit exceeded)']));
	       (message:clean,message:failure(Item)))),!,
  message:sc,
  stats:runningtime(Min,Sec),
  message:title_reset,!,
  message:scroll_notice([Name,' ',S,' ',Repository,' entries took ',Min,'m ',Sec,'s. (single thread)']).


tester:test(parallel_verbose,Name,Repository://Item,Generator,Test,Report,Scroll) :-
  stats:times(Generator,S),
  stats:init(0,S),
  config:time_limit(T),
  config:number_of_cpus(Cpus),
  message:hc,
  concurrent_forall(Generator,
                        (catch(call_with_time_limit(T,(Test,!,
                                         with_mutex(mutex,(stats:increase,
                                                           stats:percentage(P),
                                                           stats:runningtime(Min,Sec),
                                                           message:title([Name,' (',Cpus,' threads): ',P,' processed in ',Min,'m ',Sec,'s']),
                                                           (Scroll
 							    -> message:scroll_notice(['[',P,'] - ', Name,' ',Repository,'://',Item])
                                                            ;  message:topheader(['[',P,'] - ',Name,' ',Repository,'://',Item])),
  							   Report
                                                          )))),
                 time_limit_exceeded,
                 message:scroll_failure([Item,' (time limit exceeded)']));
           (sleep(1),message:clean,message:failure(Item)))),!,
  message:sc,
  stats:runningtime(Min,Sec),
  message:title_reset,!,
  message:clean,
  message:scroll_notice([Name,' ',S,' ',Repository,' entries took ',Min,'m ',Sec,'s. (',Cpus,' threads)']).


tester:test(parallel_fast,Name,Repository://Item,Generator,Test,Result,_) :-
  stats:times(Generator,S),
  stats:init(0,S),
  config:number_of_cpus(Cpus),
  message:title([Name,' (',Cpus,' threads) - No intermediate output']),
  flush_output,
  message:hc,
  concurrent_forall(Generator,(Test,!,Result;message:failure(Item))),
  message:sc,
  stats:runningtime(Min,Sec),!,
  message:title_reset,!,
  message:scroll_notice([Name,' ',S,' ',Repository,' entries took ',Min,'m ',Sec,'s. (',Cpus,' threads)']).


