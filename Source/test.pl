/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2019, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> TEST
This module implements a few tests
*/

:- module(test, []).

% *****************
% TEST declarations
% *****************

%! test:cases(?List)
%
% Declares a list of cases

test:cases([overlay://'test1/web-1.0':run,
            overlay://'test2/web-2.0':run,
            overlay://'test3/web-2.0':run,
            overlay://'test4/web-2.0':run,
            overlay://'test5/web-2.0':run,
            overlay://'test6/web-2.0':run,
            overlay://'test7/web-2.0':run,
            overlay://'test8/web-2.0':run]).


%! test:run(+Atom)
%
% Runs specific test cases

test:run(cases) :-
  test:cases(Cases),
  forall(member(Case,Cases),
         (message:header(['Test case: ',Case]),
          prover:prove(Case,[],Proof,[],_Model),
          planner:plan(Proof,[],[],Plan),
          nl,
          %message:inform([' - Model : ',Model]),
          %message:inform([' - Proof : ',Proof]),
          printer:print(Plan),nl)).

test:run(application) :-
  message:header(['Testing reader: ']),
  reader:test(portage),nl,
  message:header(['Testing parser: ']),
  parser:testparallel(portage),nl,
  message:header(['Testing prover: ']),
  prover:testparallel(portage),nl,
  message:header(['Testing planner: ']),
  planner:testparallel(portage),nl,
  message:header(['Testing builder: ']),
  builder:test(portage).
