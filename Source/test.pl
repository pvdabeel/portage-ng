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

:- dynamic failed/1.

% =============================================================================
%  TEST declarations
% =============================================================================

%! test:cases(?List)
%
% Declares a list of cases

test:cases([overlay://'test01/web-1.0':run?{[]},
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
            overlay://'test49/app-1.0':run?{[]},
            overlay://'test50/app-1.0':run?{[]},
            overlay://'test51/app-1.0':install?{[]},
            overlay://'test52/app-1.0':run?{[]},
            overlay://'test53/app-1.0':run?{[]},
            overlay://'test54/app-1.0':run?{[]}
            ]).

test:basics([overlay://'test01/os-1.0':download?{[]},
             overlay://'test01/os-1.0':install?{[]},
             overlay://'test01/os-1.0':run?{[]},
             overlay://'test01/app-1.0':download?{[]},
             overlay://'test01/app-1.0':install?{[]}]).


test:problem([portage://'app-backup/backuppc-4.4.0-r3':run?{[]},
              portage://'dev-libs/glib-2.84.0':run?{[]},
              portage://'dev-haskell/cabal-3.4.1.0-r1':run?{[]}]).

test:slotreq([overlay://'test41/app-1.0':run?{[]},
              overlay://'test42/app-1.0':run?{[]},
              overlay://'test43/app-1.0':run?{[]},
              overlay://'test44/app-1.0':run?{[]}]).

test:diamond([overlay://'test45/app-1.0':run?{[]}]).

test:doublediamond([overlay://'test46/app-1.0':run?{[]}]).

test:softuse([overlay://'test49/app-1.0':run?{[]}]).

test:pms([overlay://'test50/app-1.0':run?{[]}]).

test:simple([overlay://'test51/app-1.0':install?{[]}]).

test:new([%overlay://'test52/app-1.0':run?{[]},
          overlay://'test54/app-1.0':run?{[]}]).

test:failures([overlay://'test46/app-1.0':run?{[]},
             overlay://'test49/app-1.0':run?{[]}]).

%test:slow([portage://'dev-erlang/p1_pgsql-1.1.32':run?{[]}]).
%           portage://'dev-erlang/xmpp-1.10.1':run?{[]}]).



%! test:run(+Atom)
%
% Runs specific test cases and outputs individual results to files in Tests directory

test:run(Cases) :-
  % Ensure Tests directory exists
  retractall(test:failed(_)),
  config:working_dir(Dir),
  atomic_list_concat([Dir, '/Source/Tests'], TestsDir),
  (exists_directory(TestsDir) -> true ; make_directory(TestsDir)),
  Inner =.. [Cases,List],
  Outer =.. [:, test, Inner],
  call(Outer),
  forall(member(Case,List),
         (test:run_single_case(Case);
          assertz(test:failed(Case)),
          message:color(red),message:color(bold),
          message:print('false'),nl,
          message:color(normal),message:style(normal),nl,nl)),
  nl,nl,
  (test:failed(_)
   -> (message:color(lightred),message:color(bold),
       message:print('The following test cases failed:'),nl,nl,
       message:color(red),
       forall(test:failed(Case),
              (write(' * '),writeln(Case))),
       message:color(normal),message:style(normal),nl,nl)
   ;  true).


%! test:run(application)
%
% Runs application tests

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


%! test:run_single_case(+Atom)
%
% Runs a single test case and outputs result to file with proper error handling

test:run_single_case(Repo://Id:Action?{Context}) :-
  writeln(Repo://Id:Action?{Context}),
  config:working_dir(Dir),
  split_string(Id,'/','',[Category,Package]),
  Repo:get_location(RepoLoc),
  atomic_list_concat([RepoLoc,'/',Category,'/description.txt'],Description),
  atomic_list_concat([RepoLoc,'/',Category,'/emerge-',Category,'.log'],EmergeLog),
  atomic_list_concat([Repo, Category,Package, Action], '_', TestName),
  atomic_list_concat([Dir, '/Source/Tests/', TestName, '.txt'], FilePath),
  open(FilePath, write, Stream),
  prover:prove(Repo://Id:Action?{Context},t,Proof,t,Model,t,Constraints,t,Triggers),
  with_output_to(Stream,
       ((writeln(Repo://Id:Action?{Context}),
         planner:plan(Proof,Triggers,t,Plan),
         nl,
         message:color(cyan),
         writeln('Proof:'),
         message:color(normal),
         write_proof(Proof),
         nl,
         message:color(cyan),
         writeln('Model:'),
         message:color(normal),
         write_model(Model),
         nl,
         message:color(cyan),
         writeln('Constraints:'),
         message:color(normal),
         write_constraints(Constraints),
         nl,
         message:color(cyan),
         writeln('Triggers:'),
         message:color(normal),
         write_triggers(Triggers),
         nl,
         message:color(cyan),
         writeln('Plan:'),
         message:color(normal),
         write_plan(Plan),
         nl,
         printer:print([Repo://Id:Action?{Context}],Model,Proof,Plan));
        (Failure = true,
         message:color(red),
         message:style(bold),
         message:print('false'),nl,
         message:color(normal),
         message:style(normal),
         nl,nl))),
  close(Stream),
  (Failure == true
   -> message:color(red),message:color(bold),
      message:print('false'),nl,
      message:color(normal),message:style(normal),nl,nl,true
   ;  (message:hl,message:color(cyan),
       test:write_description(Description),
       message:color(normal),message:hl,
       printer:print([Repo://Id:Action?{Context}],Model,Proof,Plan),
       %nl,nl)).
       message:header('Gentoo emerge output:'),
       test:write_description(EmergeLog),nl,nl;true)).


%! write_description(+File)
%
% Writes description to current output

write_description(File) :-
    setup_call_cleanup(
        open(File, read, In),
        copy_stream_data(In, user_output),
        close(In)
    ).

%! write_proof(+Proof)
%
% Writes proof information to current output

write_proof(Proof) :-
  message:color(darkgray),
  forall(gen_assoc(Key,Proof,Value),
     (write(Key),write(' - '),write(Value),nl)),nl,
  message:color(cyan).


%! write_model(+Model)
%
% Writes model information to current output

write_model(Model) :-
  message:color(darkgray),
  forall(gen_assoc(Key,Model,Value),
      (write(Key),write(' - '),write(Value),nl)),nl,
  message:color(cyan).


%! write_constraints(+Constraints)
%
% Writes constraints information to current output

write_constraints(Constraints) :-
  message:color(darkgray),
  forall(gen_assoc(Key,Constraints,Value),
       (write(Key),write(' - '),write(Value),nl)),nl,
  message:color(cyan).

%! write_triggers(+Triggers)
%
% Writes triggers information to current output

write_triggers(Triggers) :-
  message:color(darkgray),
  forall(gen_assoc(Key,Triggers,Value),
      (write(Key),write(' - '),write(Value),nl)),nl,
  message:color(cyan).


%! write_plan(+Plan)
%
% Writes plan information to current output

write_plan(Plan) :-
  message:color(darkgray),
  forall(member(Step,Plan),
      writeln(Step)),nl,nl,
  message:color(normal).
