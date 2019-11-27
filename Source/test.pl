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

test:cases([overlay://'test01/web-1.0':run,
            overlay://'test02/web-2.0':run,
            overlay://'test03/os-1.0':install,
            overlay://'test04/web-1.0':run,
            overlay://'test05/web-1.0':run,
            overlay://'test06/web-1.0':run,
            overlay://'test07/web-1.0':run,
            overlay://'test08/web-1.0':run,
            overlay://'test09/os-1.0':run,
            overlay://'test10/os-1.0':run,
            overlay://'test11/os-1.0':run]).


%! test:run(+Atom)
%
% Runs specific test cases

test:run(cases) :-
  test:cases(Cases),
  forall(member(Case,Cases),
         (
          (prover:prove(Case,[],Proof,[],Model),
           planner:plan(Proof,[],[],Plan),
           printer:print(Case,Model,Proof,Plan));
          (message:color(red),
           message:style(bold),
           message:print('false'),nl,
           message:color(normal),
           message:style(normal),
           nl,nl)
         )).


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
