/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> TESTER
Description

Input:

Output:

*/

:- module(tester,[]).

% =============================================================================
%  TESTER declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Helpers
% -----------------------------------------------------------------------------

tester:trace_to_string(Trace, String) :-
  % `message:warning/1` ultimately concatenates "text" pieces; Trace is a list
  % of (potentially deep) terms. Convert it into a bounded string first, so we
  % never hand nested lists/terms to atomic_list_concat/2.
  with_output_to(string(S0),
    write_term(Trace, [quoted(true), portray(true), max_depth(20)])),
  ( string_length(S0, Len),
    Len > 4000
  -> sub_string(S0, 0, 4000, _After, Prefix),
     string_concat(Prefix, '…', String)
  ;  String = S0
  ).

% -----------------------------------------------------------------------------
%  Sequential testing
% -----------------------------------------------------------------------------

tester:test(Style,Name,Repository://Item,Generator,Test) :-
  !,
  tester:test(Style,Name,Repository://Item,Generator,Test,true,true).


tester:test(single_verbose,Name,Repository://Item,Generator,Test,Report,Scroll) :-
  stats:times(Generator,S),
  stats:init(0,S),
  config:time_limit(T),
  message:hc,
  forall(Generator,
         ( catch(
             call_with_time_limit(T,
               ( stats:increase,
                 stats:percentage(P),
                 stats:runningtime(Min,Sec),
                 message:title([Name,' (Single thread): ',P,' processed in ',Min,'m ',Sec,'s']),
                 ( Scroll
                 -> message:scroll_notice(['[',P,'] - ', Name,' - ',Repository,'://',Item])
                 ;  message:topheader(['[',P,'] - ',Name,' - ',Repository,'://',Item])
                 ),
                 Test, !, Report
               )),
             time_limit_exceeded,
             ( message:scroll_failure([Item,' (time limit exceeded)']),
               message:clean,
               message:warning([Item,' (time limit exceeded)']),
               ( current_predicate(printer:test_stats_record_failed/1) ->
                   printer:test_stats_record_failed(timeout)
               ; true
               ),
               ( current_predicate(printer:test_stats_record_failed_entry/2) ->
                   printer:test_stats_record_failed_entry(Repository://Item, timeout)
               ; true
               )
             )
           )
         ; message:clean,
           message:warning([Item,' (failed)']),
           ( current_predicate(printer:test_stats_record_failed/1) ->
               printer:test_stats_record_failed(other)
           ; true
           ),
           ( current_predicate(printer:test_stats_record_failed_entry/2) ->
               printer:test_stats_record_failed_entry(Repository://Item, other)
           ; true
           )
         )),
  !,
  message:sc,
  stats:runningtime(Min,Sec),
  message:title_reset,!,
  message:scroll_notice([Name,' ',S,' ',Repository,' entries took ',Min,'m ',Sec,'s. (single thread)']).


% -----------------------------------------------------------------------------
%  Parallel testing
% -----------------------------------------------------------------------------

tester:test(parallel_verbose,Name,Repository://Item,Generator,Test,Report,Scroll) :-
  stats:times(Generator,S),
  stats:init(0,S),
  config:time_limit(T),
  config:number_of_cpus(Cpus),
  message:hc,
  concurrent_forall(Generator,
                    catch(
                      ( catch(
                          call_with_time_limit(T,
                            ( Test, !,
                              with_mutex(mutex,
                                ( stats:increase,
                                  stats:percentage(P),
                                  stats:runningtime(Min,Sec),
                                  message:title([Name,' (',Cpus,' threads): ',P,' processed in ',Min,'m ',Sec,'s']),
                                  ( Scroll
                                  -> message:scroll_notice(['[',P,'] - ', Name,' - ',Repository,'://',Item])
                                  ;  message:topheader(['[',P,'] - ',Name,' - ',Repository,'://',Item])
                                  ),
                                  Report
                                ))
                            )),
                          time_limit_exceeded,
                          ( message:scroll_failure([Item,' (time limit exceeded)']),
                            with_mutex(mutex,(message:clean,message:warning([Item,' (time limit exceeded)']))),
                            % Best-effort: capture a short trace of what the prover was doing.
                            ( current_predicate(sampler:diagnose_timeout/3),
                              config:proving_target(Action) ->
                                % IMPORTANT: never let diagnostics failure turn a timeout into a "(failed)".
                                % Use ignore/1 so lookup mismatches or other failures don't affect control flow.
                                catch(ignore(
                                  ( atom_concat(Repository,'://',RepoPrefix),
                                    atom_concat(RepoPrefix, Item, _),
                                    Target = (Repository://Item:Action?{[]}),
                                    sampler:diagnose_timeout(Target, 0.25, diagnosis(DeltaInf, RuleCalls, Trace)),
                                    with_mutex(mutex,
                                      ( message:warning([' timeout diag: +',DeltaInf,' inferences, ',RuleCalls,' rule calls']),
                                        ( Trace == [] -> true
                                        ; tester:trace_to_string(Trace, TraceText),
                                          message:warning([' timeout trace (last ~40): ', TraceText])
                                        )
                                      ))
                                  )),
                                  _,
                                  true)
                            ; true
                            ),
                            ( current_predicate(printer:test_stats_record_failed/1) ->
                                printer:test_stats_record_failed(timeout)
                            ; true
                            ),
                            ( current_predicate(printer:test_stats_record_failed_entry/2) ->
                                printer:test_stats_record_failed_entry(Repository://Item, timeout)
                            ; true
                            )
                          )
                        )
                      ; with_mutex(mutex,(message:clean,message:warning([Item,' (failed)']))),
                        % Also print a short trace for non-timeout failures.
                        ( current_predicate(sampler:diagnose_timeout/3),
                          config:proving_target(Action) ->
                            % Best-effort only: diagnostics should never affect classification.
                            catch(ignore(
                              ( Target = (Repository://Item:Action?{[]}),
                                sampler:diagnose_timeout(Target, 0.25, diagnosis(DeltaInfF, RuleCallsF, TraceF)),
                                with_mutex(mutex,
                                  ( message:warning([' fail diag: +',DeltaInfF,' inferences, ',RuleCallsF,' rule calls']),
                                    ( TraceF == [] -> true
                                    ; tester:trace_to_string(TraceF, TraceTextF),
                                      message:warning([' fail trace (last ~40): ', TraceTextF])
                                    )
                                  ))
                              )),
                              _,
                              true)
                        ; true
                        ),
                        ( current_predicate(printer:test_stats_record_failed/1) ->
                            printer:test_stats_record_failed(other)
                        ; true
                        ),
                        ( current_predicate(printer:test_stats_record_failed_entry/2) ->
                            printer:test_stats_record_failed_entry(Repository://Item, other)
                        ; true
                        )
                      ),
                      E,
                      ( % Never let an exception from a worker thread abort the whole test run.
                        with_mutex(mutex, (message:clean, message:warning([Item,' (exception)']), print_message(error, E))),
                        ( current_predicate(printer:test_stats_record_failed/1) ->
                            printer:test_stats_record_failed(exception)
                        ; true
                        ),
                        ( current_predicate(printer:test_stats_record_failed_entry/2) ->
                            printer:test_stats_record_failed_entry(Repository://Item, exception)
                        ; true
                        )
                      )
                    )),
  !,
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
