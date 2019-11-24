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
            overlay://'test03/web-2.0':run,
            overlay://'test04/web-2.0':run,
            overlay://'test05/web-2.0':run,
            overlay://'test06/web-2.0':run,
            overlay://'test07/web-2.0':run,
            overlay://'test08/web-2.0':run,
            overlay://'test09/web-2.0':run,
            overlay://'test10/web-2.0':run,
            overlay://'test11/web-2.0':run]).


%! test:run(+Atom)
%
% Runs specific test cases

test:run(cases) :-
  test:cases(Cases),
  forall(member(Case,Cases),
         (message:header(['Emerging ',Case]),
          nl,
          message:color(green),
          message:print('These are the packages that would be merged, in order:'),nl,
          nl,
          message:color(normal),
          message:print('Calculating dependencies... done!'),nl,
          nl,
          (prover:prove(Case,[],Proof,[],_Model),
           planner:plan(Proof,[],[],Plan),
           %message:inform([' - Model : ',Model]),
           %message:inform([' - Proof : ',Proof]),
           printer:print(Plan),
           message:color(normal),
           length(Plan,Numberofsteps),
           message:print(['Total: ', Numberofsteps,' steps, ', Numberofsteps, ' actions (', Numberofsteps,' runs, ',Numberofsteps,' installs)']),nl,
           nl,nl);
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
