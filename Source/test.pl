/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2020, Pieter Van den Abeele

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
            overlay://'test03/web-1.0':run,
            overlay://'test04/web-1.0':run,
            overlay://'test05/web-1.0':run,
            overlay://'test06/web-1.0':run,
            overlay://'test07/web-1.0':run,
            overlay://'test08/web-1.0':run,
            overlay://'test09/os-1.0':run,
            overlay://'test10/os-1.0':run,
            overlay://'test11/os-1.0':run,
            overlay://'test12/web-1.0':run,
            overlay://'test13/web-1.0':run,
            overlay://'test14/web-1.0':run,
            overlay://'test15/web-1.0':run,
            overlay://'test16/web-1.0':run,
            overlay://'test17/web-1.0':run,
            overlay://'test18/web-1.0':run,
            overlay://'test19/web-1.0':run,
            overlay://'test20/web-1.0':run,
            overlay://'test21/web-1.0':run,
            overlay://'test22/web-1.0':run,
            overlay://'test23/web-1.0':run,
            overlay://'test24/web-1.0':run,
            overlay://'test25/web-1.0':run,
            overlay://'test26/web-1.0':run,
            overlay://'test27/web-1.0':run,
            overlay://'test28/web-1.0':run,
            overlay://'test29/web-1.0':run,
            overlay://'test30/web-1.0':run,
            overlay://'test31/web-1.0':run]).


%! test:run(+Atom)
%
% Runs specific test cases

test:run(cases) :-
  test:cases(Cases),
  forall(member(Case,Cases),
         (
          (prover:prove(Case,[],Proof,[],Model,[],_Constraints),
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
  parser:test(portage),nl,
  message:header(['Testing prover: ']),
  prover:test(portage),nl,
  message:header(['Testing planner: ']),
  planner:test(portage),nl,
  message:header(['Testing builder: ']),
  builder:test(portage).
