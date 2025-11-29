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

:- multifile test:is_success/5.

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
            overlay://'test13/web-2.0':run?{[]},
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
            overlay://'test54/app-1.0':run?{[]},
            overlay://'test55/app-1.0':run?{[]}
            ]).

test:slotreq([overlay://'test41/app-1.0':run?{[]},
              overlay://'test42/app-1.0':run?{[]},
              overlay://'test43/app-1.0':run?{[]},
              overlay://'test44/app-1.0':run?{[]}]).

test:diamond([overlay://'test45/app-1.0':run?{[]}]).

test:doublediamond([overlay://'test46/app-1.0':run?{[]}]).

test:softuse([overlay://'test49/app-1.0':run?{[]}]).

test:pms([overlay://'test50/app-1.0':run?{[]}]).

test:simple([overlay://'test51/app-1.0':install?{[]}]).

test:new([%overlay://'test54/app-1.0':run?{[]},
          overlay://'test55/app-1.0':run?{[]}]).
          %overlay://'test56/app-1.0':run?{[]}]).

test:focus([  overlay://'test05/web-1.0':run?{[]} ]).



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
  tty_clear,
  message:hl,
  nl,
  message:topheader(['Test case : ',Repo://Id:Action?{Context}]),
  message:hl,
  nl,
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
         (   test:is_success(Repo://Id:Action?{Context},Proof,Plan,Model,Triggers)
         ->  true
         ;   (writeln('Validation failed: is_success/5 returned false'), fail)
         ),
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
   ;  (
       message:header('Description :'),
       nl,
       (exists_file(Description)
        -> test:write_description(Description)
        ;  true),
       message:style(normal),
       nl,
       printer:print([Repo://Id:Action?{Context}],Model,Proof,Plan),
       message:header('Legacy emerge output :'),
       (exists_file(EmergeLog)
        -> test:write_description(EmergeLog)
        ;  message:inform('no emerge output available yet')),
       nl,nl,nl,nl;true)),
   printer:wait_for_input.


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

%! test:must_have(+Type, +Content, +Element)
%
% Checks if Content contains Element based on Type.

test:must_have(plan, Plan, Element) :-
    member(Element, Plan).

test:must_have(proof, Proof, Key-Value) :-
    get_assoc(Key, Proof, Value).

test:must_have(model, Model, Key-Value) :-
    get_assoc(Key, Model, Value).

test:must_have(triggers, Triggers, Key-Value) :-
    get_assoc(Key, Triggers, Value).

%! test:is_success(+Target, +Proof, +Plan, +Model, +Triggers)
%
% Validates the result of a test case.

test:is_success(overlay://'test01/web-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test02/web-2.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test03/web-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test04/web-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test05/web-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test06/web-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test07/web-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test08/web-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test09/os-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test10/os-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test11/os-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test12/web-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test13/web-2.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test14/web-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test15/web-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test16/web-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test17/web-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test18/web-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test19/web-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test20/web-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test21/web-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test22/web-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test23/web-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test24/web-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test25/web-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test26/web-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test27/web-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test28/web-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test29/web-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test30/web-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test31/web-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test32/os-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test33/app-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test34/app-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test35/app-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test36/app-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test37/app-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test38/app-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test39/app-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test40/os-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test41/app-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test42/app-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test43/app-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test44/app-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test45/app-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test46/app-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test47/api-docs-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test48/app-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test49/app-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test50/app-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test51/app-1.0':install?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test52/app-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test53/app-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test54/app-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
test:is_success(overlay://'test55/app-1.0':run?{[]}, _Proof, _Plan, _Model, _Triggers) :- true.
