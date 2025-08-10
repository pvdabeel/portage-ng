/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2025, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> TEST
This module implements a few tests
*/

:- module(test, []).

% =============================================================================
%  TEST declarations
% =============================================================================

%! test:cases(?List)
%
% Declares a list of cases

test:cases([overlay://'test01/os-1.0':download?{[]},
            overlay://'test01/os-1.0':install?{[]},
            overlay://'test01/os-1.0':run?{[]},
            overlay://'test01/app-1.0':download?{[]},
            overlay://'test01/app-1.0':install?{[]},
            overlay://'test01/web-1.0':run?{[]},
            overlay://'test02/web-2.0':run?{[]},
            overlay://'test03/web-1.0':run?{[]},
            overlay://'test04/web-1.0':run?{[]},
            overlay://'test05/web-1.0':run?{[]},
            overlay://'test06/web-1.0':run?{[]},
            overlay://'test07/web-1.0':run?{[]},
            overlay://'test08/web-1.0':run?{[]},
            overlay://'test09/os-1.0':run?{[]},
            overlay://'test10/os-1.0':run?{[]},
            overlay://'test11/os-1.0':run?{[]},
            overlay://'test12/web-1.0':run?{[]},
            overlay://'test13/web-1.0':run?{[]},
            overlay://'test14/web-1.0':run?{[]},
            overlay://'test15/web-1.0':run?{[]},
            overlay://'test16/web-1.0':run?{[]},
            overlay://'test17/web-1.0':run?{[]},
            overlay://'test18/web-1.0':run?{[]},
            overlay://'test19/web-1.0':run?{[]},
            overlay://'test20/web-1.0':run?{[]},
            overlay://'test21/web-1.0':run?{[]},
            overlay://'test22/web-1.0':run?{[]},
            overlay://'test23/web-1.0':run?{[]},
            overlay://'test24/web-1.0':run?{[]},
            overlay://'test25/web-1.0':run?{[]},
            overlay://'test26/web-1.0':run?{[]},
            overlay://'test27/web-1.0':run?{[]},
            overlay://'test28/web-1.0':run?{[]},
            overlay://'test29/web-1.0':run?{[]},
            overlay://'test30/web-1.0':run?{[]},
            overlay://'test31/web-1.0':run?{[]},
            overlay://'test32/os-1.0':run?{[]},
            overlay://'test33/app-1.0':run?{[]},
            overlay://'test34/app-1.0':run?{[]},
            overlay://'test35/app-1.0':run?{[]},
            overlay://'test36/app-1.0':run?{[]},
            overlay://'test37/app-1.0':run?{[]},
            overlay://'test38/app-1.0':run?{[]},
            overlay://'test39/app-1.0':run?{[]},
            overlay://'test40/os-1.0':run?{[]},
            overlay://'test41/app-1.0':run?{[]},
            overlay://'test42/app-1.0':run?{[]},
            overlay://'test43/app-1.0':run?{[]},
            overlay://'test44/app-1.0':run?{[]},
            overlay://'test45/app-1.0':run?{[]},
            overlay://'test46/app-1.0':run?{[]},
            overlay://'test47/api-docs-1.0':run?{[]},
            overlay://'test48/app-1.0':run?{[]},
            overlay://'test49/app-1.0':run?{[]}
            ]).

%test:problem([overlay://'test43/app-1.0':run?{[]}]).

%test:problem([portage://'app-containers/apptainer-1.4.1':run?{[]}]).

%test:problem([overlay://'test09/os-1.0':run?{[]},
%              overlay://'test10/os-1.0':run?{[]},
%              overlay://'test11/os-1.0':run?{[]}]).

test:problem([portage://'app-backup/backuppc-4.4.0-r3':run?{[]},
              portage://'dev-libs/glib-2.84.0':run?{[]},
              portage://'dev-haskell/cabal-3.4.1.0-r1':run?{[]}]).

test:slotreq([overlay://'test41/app-1.0':run?{[]},
              overlay://'test42/app-1.0':run?{[]},
              overlay://'test43/app-1.0':run?{[]},
              overlay://'test44/app-1.0':run?{[]}]).

test:diamond([overlay://'test45/app-1.0':run?{[]}]).

%test:slow([portage://'dev-erlang/p1_pgsql-1.1.32':run?{[]}]).
%           portage://'dev-erlang/xmpp-1.10.1':run?{[]}]).

%test:cow([portage://'kde-frameworks/kglobalaccel-5.116.0-r2':run?{[]}]).

%! test:run(+Atom)
%
% Runs specific test cases

test:run(Cases) :-
  Inner =.. [Cases,List],
  Outer =.. [:, test, Inner],
  call(Outer),
  forall(member(Case,List),
         ((
           writeln(Case),
           prover:prove(Case,t,Proof,t,Model,t,Constraints,t,Triggers),
           planner:plan(Proof,Triggers,t,Plan),
	   message:color(cyan),
           writeln('Proof:'),
           message:color(darkgray),forall(gen_assoc(Key,Proof,Value),(write(Key),write(' - '),write(Value),nl)),nl,
           message:color(cyan),
           writeln('Model:'),
           message:color(darkgray),forall(gen_assoc(Key,Model,Value),(write(Key),write(' - '),write(Value),nl)),nl,
           message:color(cyan),
           writeln('Constraints:'),
           message:color(darkgray),forall(gen_assoc(Key,Constraints,Value),(write(Key),write(' - '),write(Value),nl)),nl,
           message:color(cyan),
           writeln('Triggers:'),
           message:color(darkgray),forall(gen_assoc(Key,Triggers,Value),(write(Key),write(' - '),write(Value),nl)),nl,
           message:color(cyan),
           writeln('Plan:'),
           message:color(darkgray),forall(member(Step,Plan),writeln(Step)),nl,nl,
           message:color(normal),
           printer:print([Case],Model,Proof,Plan))
 ;
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
