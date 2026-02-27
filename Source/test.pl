/*

  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.

*/


/** <module> TEST
This module implements a few tests
*/

:- module(test, []).

:- multifile test:is_success/5.
:- multifile test:expect/2.
:- multifile test:xfail/2.

:- dynamic failed/1.
:- dynamic test:current_model/1.

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
            overlay://'test55/app-1.0':run?{[]},
            overlay://'test57/web-1.0':run?{[]},
            overlay://'test58/web-1.0':run?{[]},
            overlay://'test59/web-1.0':run?{[]},
            overlay://'test60/web-1.0':run?{[]},
            overlay://'test61/app-1.0':run?{[]},
            overlay://'test62/web-1.0':run?{[]},
            overlay://'test63/app-1.0':run?{[]},
            overlay://'test64/app-1.0':run?{[]},
            overlay://'test65/app-1.0':run?{[]}
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

% Focused regression set: bracketed USE dependencies ([foo], [-foo], [foo=], [!foo=], [foo?], [!foo?])
% Use :install so DEPEND is exercised.
test:bracketed_use([
  overlay://'test33/app-1.0':install?{[]},
  overlay://'test34/app-1.0':install?{[]},
  overlay://'test35/app-1.0':install?{[]},
  overlay://'test36/app-1.0':install?{[]},
  overlay://'test37/app-1.0':install?{[]},
  overlay://'test38/app-1.0':install?{[]},
  overlay://'test39/app-1.0':install?{[]}
]).

test:new([%overlay://'test54/app-1.0':run?{[]},
          overlay://'test55/app-1.0':run?{[]}]).
          %overlay://'test56/app-1.0':run?{[]}]).

test:focus([  overlay://'test09/os-1.0':run?{[]} ]).

test:python([ portage://'dev-util/cram-0.7-r2':run?{[]} ]).


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
  ignore(tty_clear),
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
  once(with_output_to(Stream,
       ( ( writeln(Repo://Id:Action?{Context}),
           planner:plan(Proof,Triggers,t,Plan0,Remainder0),
           scheduler:schedule(Proof,Triggers,Plan0,Remainder0,Plan,_Remainder),
           test:validate(Repo://Id:Action?{Context},Proof,Plan,Model,Triggers),
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
           printer:print([Repo://Id:Action?{Context}],Model,Proof,Plan,Triggers)
         )
         -> true
         ;  ( Failure = true,
              message:color(red),
              message:style(bold),
              message:print('false'),nl,
              message:color(normal),
              message:style(normal),
              nl,nl
            )
       ))),
  close(Stream),
  (Failure == true
   -> message:color(red),message:color(bold),
      message:print('false'),nl,
      message:color(normal),message:style(normal),nl,nl,
      fail
   ;  (
       message:header('Description :'),
       nl,
       (exists_file(Description)
        -> test:write_description(Description)
        ;  true),
       message:style(normal),
       nl,
       printer:print([Repo://Id:Action?{Context}],Model,Proof,Plan,Triggers),
       message:header('Legacy emerge output :'),
       (exists_file(EmergeLog)
        -> test:write_description(EmergeLog)
        ;  message:inform('no emerge output available yet')),
       nl,nl,nl,nl)),
   ignore(printer:wait_for_input),
   !.


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


%! test:in_model(Template,Model)
%
% Validates whether a model matches a template

test:in_model(Repo://Entry:Action?{Context},Model) :-
  !, once(gen_assoc(Repo://Entry:Action,Model,Context)).

test:in_model(assumed(Predicate:Action?{Context}),Model) :-
  !, once(gen_assoc(assumed(Predicate:Action),Model,Context)).


%! test:is_success(+Target, +Proof, +Plan, +Model, +Triggers)
%
% Validates the result of a test case.

%! test:validate(+Target, +Proof, +Plan, +Model, +Triggers)
%
% Validates a test case using a small expectation DSL.
%
% - If test:expect/2 exists for a target, it is used.
% - Otherwise, we fall back to test:is_success/5 (legacy).
% - If test:xfail/2 exists for a target, failure is expected:
%   - failing expectations => success (XFAIL)
%   - passing expectations  => failure (XPASS)

test:validate(Target, Proof, Plan, Model, Triggers) :-
  ( test:xfail(Target, Reason) ->
      ( test:validate_must_pass(Target, Proof, Plan, Model, Triggers) ->
          writeln('XPASS: expected failure but validation succeeded'),
          writeln(Reason),
          fail
      ; writeln('XFAIL: expected failure'),
        writeln(Reason),
        true
      )
  ; test:validate_must_pass(Target, Proof, Plan, Model, Triggers)
  ).

test:validate_must_pass(Target, Proof, Plan, Model, Triggers) :-
  ( test:expect(Target, Expectations) ->
      test:check_expectations(Expectations, Target, Proof, Plan, Model, Triggers)
  ; test:is_success(Target, Proof, Plan, Model, Triggers)
  ).

test:check_expectations([], _Target, _Proof, _Plan, _Model, _Triggers) :- !.
test:check_expectations([E|Es], Target, Proof, Plan, Model, Triggers) :-
  ( test:check_expectation(E, Target, Proof, Plan, Model, Triggers) -> true
  ; writeln('Expectation failed:'), writeln(E), fail
  ),
  test:check_expectations(Es, Target, Proof, Plan, Model, Triggers).

% Expectation language
%
% We support two styles:
%
% 1) Goal-style expectations (preferred):
%    - must_have(Template)
%    - \+ must_have(Template)
%
% 2) Structured expectations (legacy in this file):
%    - in_model(Template)
%    - not_in_model(Template)
%    - one_of_in_model([Template,...])

test:check_expectation(in_model(T), _Target, _Proof, _Plan, Model, _Triggers) :-
  test:in_model(T, Model).

test:check_expectation(not_in_model(T), _Target, _Proof, _Plan, Model, _Triggers) :-
  \+ test:in_model(T, Model).

test:check_expectation(one_of_in_model(List), _Target, _Proof, _Plan, Model, _Triggers) :-
  member(T, List),
  test:in_model(T, Model),
  !.

% Goal-style: evaluate arbitrary goals against a "current model".
% This allows tests to write: must_have(X), \+ must_have(Y).
test:check_expectation(Goal, _Target, _Proof, _Plan, Model, _Triggers) :-
  setup_call_cleanup(
    asserta(test:current_model(Model)),
    call(Goal),
    retract(test:current_model(Model))
  ).

%! test:must_have(+Template)
%
% Succeeds iff Template occurs in the current model.
%
% This is intentionally arity-1 so test expectations can use:
%   must_have(X), \+ must_have(Y)
%
test:must_have(Template) :-
  test:current_model(Model),
  test:in_model(Template, Model).

test:is_success(overlay://'test01/web-1.0':run?{[]}, _Proof, _Plan, Model, _Triggers) :-

  % We should see app-1.0, db-1.0, os-1.0 and web-1.0 in the model with empty build_with_use, empty required_use and default slots

  in_model(overlay://'test01/app-1.0':download?{[required_use([]),build_with_use([])]},Model),
  in_model(overlay://'test01/app-1.0':install?{[required_use([]),build_with_use([]),slot(test01,app,[slot('0')]):{'test01/app-1.0'}]},Model),
  in_model(overlay://'test01/app-1.0':run?{[slot(test01,app,[slot('0')]):{'test01/app-1.0'},build_with_use([])]},Model),

  in_model(overlay://'test01/db-1.0':download?{[required_use([]),build_with_use([])]},Model),
  in_model(overlay://'test01/db-1.0':install?{[required_use([]),build_with_use([]),slot(test01,db,[slot('0')]):{'test01/db-1.0'}]},Model),
  in_model(overlay://'test01/db-1.0':run?{[slot(test01,db,[slot('0')]):{'test01/db-1.0'},build_with_use([])]},Model),

  in_model(overlay://'test01/os-1.0':download?{[required_use([]),build_with_use([])]},Model),
  in_model(overlay://'test01/os-1.0':install?{[required_use([]),build_with_use([]),slot(test01,os,[slot('0')]):{'test01/os-1.0'}]},Model),
  in_model(overlay://'test01/os-1.0':run?{[slot(test01,os,[slot('0')]):{'test01/os-1.0'},build_with_use([])]},Model),

  in_model(overlay://'test01/web-1.0':download?{[required_use([]),build_with_use([])]},Model),
  in_model(overlay://'test01/web-1.0':install?{[required_use([]),build_with_use([]),slot(test01,web,[slot('0')]):{'test01/web-1.0'}]},Model),
  in_model(overlay://'test01/web-1.0':run?{[]},Model).


test:is_success(overlay://'test02/web-2.0':run?{[]}, _Proof, _Plan, Model, _Triggers) :-

  % We should see app-2.0, db-2.0, os-2.0 and web-2.0 in the model with empty build_with_use, empty required_use and default slots

  in_model(overlay://'test02/app-2.0':download?{[required_use([]),build_with_use([])]},Model),
  in_model(overlay://'test02/app-2.0':install?{[required_use([]),build_with_use([]),slot(test02,app,[slot('0')]):{'test02/app-2.0'}]},Model),
  in_model(overlay://'test02/app-2.0':run?{[slot(test02,app,[slot('0')]):{'test02/app-2.0'},build_with_use([])]},Model),

  in_model(overlay://'test02/db-2.0':download?{[required_use([]),build_with_use([])]},Model),
  in_model(overlay://'test02/db-2.0':install?{[required_use([]),build_with_use([]),slot(test02,db,[slot('0')]):{'test02/db-2.0'}]},Model),
  in_model(overlay://'test02/db-2.0':run?{[slot(test02,db,[slot('0')]):{'test02/db-2.0'},build_with_use([])]},Model),

  in_model(overlay://'test02/os-2.0':download?{[required_use([]),build_with_use([])]},Model),
  in_model(overlay://'test02/os-2.0':install?{[required_use([]),build_with_use([]),slot(test02,os,[slot('0')]):{'test02/os-2.0'}]},Model),
  in_model(overlay://'test02/os-2.0':run?{[slot(test02,os,[slot('0')]):{'test02/os-2.0'},build_with_use([])]},Model),

  in_model(overlay://'test02/web-2.0':download?{[required_use([]),build_with_use([])]},Model),
  in_model(overlay://'test02/web-2.0':install?{[required_use([]),build_with_use([]),slot(test02,web,[slot('0')]):{'test02/web-2.0'}]},Model),
  in_model(overlay://'test02/web-2.0':run?{[]},Model),

  % we should not see the older versions

  \+in_model(overlay://'test02/app-1.0':_?{_},Model),
  \+in_model(overlay://'test02/db-1.0':_?{_},Model),
  \+in_model(overlay://'test02/os-1.0':_?{_},Model),
  \+in_model(overlay://'test02/web-1.0':_?{_},Model).


test:is_success(overlay://'test03/web-1.0':run?{[]}, _Proof, _Plan, Model, _Triggers) :-

  % We should see app-1.0, db-1.0, os-1.0 and web-1.0 in the model with empty build_with_use, empty required_use and default slots

  in_model(overlay://'test03/app-1.0':download?{[required_use([]),build_with_use([])]},Model),
  in_model(overlay://'test03/app-1.0':install?{[required_use([]),build_with_use([]),slot(test03,app,[slot('0')]):{'test03/app-1.0'}]},Model),
  in_model(overlay://'test03/app-1.0':run?{[slot(test03,app,[slot('0')]):{'test03/app-1.0'},build_with_use([])]},Model),

  in_model(overlay://'test03/db-1.0':download?{[required_use([]),build_with_use([])]},Model),
  in_model(overlay://'test03/db-1.0':install?{[required_use([]),build_with_use([]),slot(test03,db,[slot('0')]):{'test03/db-1.0'}]},Model),
  in_model(overlay://'test03/db-1.0':run?{[slot(test03,db,[slot('0')]):{'test03/db-1.0'},build_with_use([])]},Model),

  in_model(overlay://'test03/os-1.0':download?{[required_use([]),build_with_use([])]},Model),
  in_model(overlay://'test03/os-1.0':install?{[required_use([]),build_with_use([]),slot(test03,os,[slot('0')]):{'test03/os-1.0'}]},Model),
  in_model(overlay://'test03/os-1.0':run?{[slot(test03,os,[slot('0')]):{'test03/os-1.0'},build_with_use([])]},Model),

  in_model(overlay://'test03/web-1.0':download?{[required_use([]),build_with_use([])]},Model),
  in_model(overlay://'test03/web-1.0':install?{[required_use([]),build_with_use([]),slot(test03,web,[slot('0')]):{'test03/web-1.0'}]},Model),
  in_model(overlay://'test03/web-1.0':run?{[]},Model),

  % We should see an assumption taken for the circular install dependency

  in_model(assumed(grouped_package_dependency(no,test03,os,[package_dependency(install,no,test03,os,none,[[],'','','',''],[],[])]):install?{[]}),Model).


test:is_success(overlay://'test04/web-1.0':run?{[]}, _Proof, _Plan, Model, _Triggers) :-

  % We should see app-1.0, db-1.0, os-1.0 and web-1.0 in the model with empty build_with_use, empty required_use and default slots

  in_model(overlay://'test04/app-1.0':download?{[required_use([]),build_with_use([])]},Model),
  in_model(overlay://'test04/app-1.0':install?{[required_use([]),build_with_use([]),slot(test04,app,[slot('0')]):{'test04/app-1.0'}]},Model),
  in_model(overlay://'test04/app-1.0':run?{[slot(test04,app,[slot('0')]):{'test04/app-1.0'},build_with_use([])]},Model),

  in_model(overlay://'test04/db-1.0':download?{[required_use([]),build_with_use([])]},Model),
  in_model(overlay://'test04/db-1.0':install?{[required_use([]),build_with_use([]),slot(test04,db,[slot('0')]):{'test04/db-1.0'}]},Model),
  in_model(overlay://'test04/db-1.0':run?{[slot(test04,db,[slot('0')]):{'test04/db-1.0'},build_with_use([])]},Model),

  in_model(overlay://'test04/os-1.0':download?{[required_use([]),build_with_use([])]},Model),
  in_model(overlay://'test04/os-1.0':install?{[required_use([]),build_with_use([]),slot(test04,os,[slot('0')]):{'test04/os-1.0'}]},Model),
  in_model(overlay://'test04/os-1.0':run?{[slot(test04,os,[slot('0')]):{'test04/os-1.0'},build_with_use([])]},Model),

  in_model(overlay://'test04/web-1.0':download?{[required_use([]),build_with_use([])]},Model),
  in_model(overlay://'test04/web-1.0':install?{[required_use([]),build_with_use([]),slot(test04,web,[slot('0')]):{'test04/web-1.0'}]},Model),
  in_model(overlay://'test04/web-1.0':run?{[]},Model),

  % We should see an assumption taken for the circular install dependency

  in_model(assumed(grouped_package_dependency(no,test04,os,[package_dependency(run,no,test04,os,none,[[],'','','',''],[],[])]):run?{[]}),Model).


test:is_success(overlay://'test05/web-1.0':run?{[]}, _Proof, _Plan, Model, _Triggers) :-

 % We should see app-1.0, db-1.0, os-1.0 and web-1.0 in the model with empty build_with_use, empty required_use and default slots

  in_model(overlay://'test05/app-1.0':download?{[required_use([]),build_with_use([])]},Model),
  in_model(overlay://'test05/app-1.0':install?{[required_use([]),build_with_use([]),slot(test05,app,[slot('0')]):{'test05/app-1.0'}]},Model),
  in_model(overlay://'test05/app-1.0':run?{[slot(test05,app,[slot('0')]):{'test05/app-1.0'},build_with_use([])]},Model),

  in_model(overlay://'test05/db-1.0':download?{[required_use([]),build_with_use([])]},Model),
  in_model(overlay://'test05/db-1.0':install?{[required_use([]),build_with_use([]),slot(test05,db,[slot('0')]):{'test05/db-1.0'}]},Model),
  in_model(overlay://'test05/db-1.0':run?{[slot(test05,db,[slot('0')]):{'test05/db-1.0'},build_with_use([])]},Model),

  in_model(overlay://'test05/os-1.0':download?{[required_use([]),build_with_use([])]},Model),
  in_model(overlay://'test05/os-1.0':install?{[required_use([]),build_with_use([]),slot(test05,os,[slot('0')]):{'test05/os-1.0'}]},Model),
  in_model(overlay://'test05/os-1.0':run?{[slot(test05,os,[slot('0')]):{'test05/os-1.0'},build_with_use([])]},Model),

  in_model(overlay://'test05/web-1.0':download?{[required_use([]),build_with_use([])]},Model),
  in_model(overlay://'test05/web-1.0':install?{[required_use([]),build_with_use([]),slot(test05,web,[slot('0')]):{'test05/web-1.0'}]},Model),
  in_model(overlay://'test05/web-1.0':run?{[]},Model),

  % We should see an assumption taken for the circular install dependency

  in_model(assumed(grouped_package_dependency(no,test05,os,[package_dependency(install,no,test05,os,none,[[],'','','',''],[],[])]):install?{[]}),Model),
  in_model(assumed(grouped_package_dependency(no,test05,os,[package_dependency(run,no,test05,os,none,[[],'','','',''],[],[])]):run?{[]}),Model).




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
test:is_success(_,_,_,_,_) :- true.


% =============================================================================
%  Expectations for new regression cases
% =============================================================================

% test57: virtual-style ebuild must pull its provider
test:expect(overlay://'test57/web-1.0':run?{[]},
            [ test:must_have(overlay://'test57/virtualsdk-1.0':run?{_}),
              test:must_have(overlay://'test57/linux-1.0':run?{_})
            ]).

% test58: PROVIDE-based virtual satisfaction (deprecated PMS)
test:expect(overlay://'test58/web-1.0':run?{[]},
            [ test:must_have(overlay://'test58/linux-1.0':run?{_})
            ]).

% test59: any-of group must select at least one alternative (runtime)
test:xfail(overlay://'test59/web-1.0':run?{[]},
           'Regression: any-of (||) currently does not force selecting one alternative').
test:expect(overlay://'test59/web-1.0':run?{[]},
            [ ( test:must_have(overlay://'test59/data_fast-1.0':run?{_})
              ; test:must_have(overlay://'test59/data_best-1.0':run?{_})
              )
            ]).

% test60: versioned blocker !< must steer selection away from windows-1.0
test:xfail(overlay://'test60/web-1.0':run?{[]},
           'Regression: versioned blocker !< is handled via assumptions, not by steering version choice').
test:expect(overlay://'test60/web-1.0':run?{[]},
            [ test:must_have(overlay://'test60/windows-2.0':run?{_}),
              \+ test:must_have(overlay://'test60/windows-1.0':run?{_})
            ]).

% -----------------------------------------------------------------------------
%  Bracketed USE regression expectations (test33..test39)
% -----------------------------------------------------------------------------

test:expect(overlay://'test33/app-1.0':install?{[]},
            [ test:must_have(overlay://'test33/os-1.0':install?{Ctx}),
              member(build_with_use:use_state(En,_Dis), Ctx),
              memberchk(linux, En),
              \+ test:must_have(assumed(grouped_package_dependency(test33,os,_):install?{_}))
            ]).

test:expect(overlay://'test34/app-1.0':install?{[]},
            [ test:must_have(overlay://'test34/os-1.0':install?{Ctx}),
              member(build_with_use:use_state(_En,Dis), Ctx),
              memberchk(linux, Dis),
              \+ test:must_have(assumed(grouped_package_dependency(test34,os,_):install?{_}))
            ]).

% For the propagation/conditional variants we mostly assert:
% - the dependency is not discharged via unsatisfied_constraints assumptions
% - the os/lib packages are selected
% (the exact polarity depends on the parent linux state, which is environment-driven)
test:expect(overlay://'test35/app-1.0':install?{[]},
            [ test:must_have(overlay://'test35/os-1.0':install?{_}),
              \+ test:must_have(assumed(grouped_package_dependency(test35,os,_):install?{_}))
            ]).

test:expect(overlay://'test36/app-1.0':install?{[]},
            [ test:must_have(overlay://'test36/lib-1.0':install?{_}),
              test:must_have(overlay://'test36/os-1.0':install?{_}),
              \+ test:must_have(assumed(grouped_package_dependency(test36,lib,_):install?{_})),
              \+ test:must_have(assumed(grouped_package_dependency(test36,os,_):install?{_}))
            ]).

test:expect(overlay://'test37/app-1.0':install?{[]},
            [ test:must_have(overlay://'test37/os-1.0':install?{_}),
              \+ test:must_have(assumed(grouped_package_dependency(test37,os,_):install?{_}))
            ]).

test:expect(overlay://'test38/app-1.0':install?{[]},
            [ test:must_have(overlay://'test38/os-1.0':install?{_}),
              \+ test:must_have(assumed(grouped_package_dependency(test38,os,_):install?{_}))
            ]).

test:expect(overlay://'test39/app-1.0':install?{[]},
            [ test:must_have(overlay://'test39/os-1.0':install?{_}),
              \+ test:must_have(assumed(grouped_package_dependency(test39,os,_):install?{_}))
            ]).

% test65: installed entries must satisfy incoming build_with_use
test:expect(overlay://'test65/app-1.0':run?{[]},
            [ ( query:search([repository(pkg),installed(true)], pkg://E),
                query:search([category(C),name(N)], pkg://E),
                % 1) Predicate-level check: installed entry must NOT satisfy an impossible build_with_use.
                \+ rules:installed_entry_satisfies_build_with_use(pkg://E,
                      [build_with_use:[required('__portage_ng_test_flag__')]]),
                % 2) Rule-level check: "keep installed" shortcut must not apply when
                % incoming build_with_use is unsatisfied, so grouped dep must yield work.
                G = grouped_package_dependency(no,C,N,
                      [package_dependency(run,no,C,N,none,[[],'','','',''],[],[])]):run?{
                        [build_with_use:[required('__portage_ng_test_flag__')]]
                      },
                rules:rule(G, Conds),
                Conds \== []
              )
            ]).
