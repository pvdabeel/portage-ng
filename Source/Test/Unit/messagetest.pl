/*
 Author: Pieter Van den Abeele
 E-mail: pvdabeel@mac.com
 Copyright (c) 2005-2026, Pieter Van den Abeele

 Distributed under the terms of the LICENSE file in the root directory of this
 project.
*/

/** <module> MESSAGETEST
Unit tests for the message module's best-effort execution helper
(Source/Application/Output/message.pl).

message:catch_log/2 always succeeds: failure of the goal is normal
control flow, an exception is reported once per label.
*/

:- module(messagetest, []).

:- use_module(library(plunit)).

% =============================================================================
%  MESSAGETEST declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  catch_log tests
% -----------------------------------------------------------------------------

:- begin_tests(message_catch_log).

test(succeeding_goal_runs) :-
  message:catch_log('messagetest:ok', true).

test(failing_goal_is_swallowed) :-
  message:catch_log('messagetest:fail', fail).

test(throwing_goal_is_swallowed) :-
  message:catch_log('messagetest:throw',
                    throw(error(test_error, messagetest))).

test(report_once_per_label) :-
  retractall(message:catch_log_warned('messagetest:once')),
  message:catch_log('messagetest:once',
                    throw(error(first, messagetest))),
  message:catch_log_warned('messagetest:once'),
  % Second throw under the same label stays silent but still succeeds.
  message:catch_log('messagetest:once',
                    throw(error(second, messagetest))),
  retractall(message:catch_log_warned('messagetest:once')).

:- end_tests(message_catch_log).
