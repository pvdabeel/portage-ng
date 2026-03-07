/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> TEST
Unit and regression test framework for the portage-ng resolver.

Tests are organised around an overlay repository containing synthetic
ebuilds (test01..test65). Each test case targets a specific resolver
feature: basic dependency resolution, version selection, cycle handling,
USE flag propagation, slot requirements, blockers, etc.

The validation layer supports two styles:
- Legacy:     multifile test:is_success/5 clauses with explicit in_model checks
- Expectation DSL:  test:expect/2 + test:xfail/2 with must_have, in_model,
                    not_in_model, one_of_in_model operators
*/

:- module(test, []).

:- multifile test:is_success/5.
:- multifile test:expect/2.
:- multifile test:xfail/2.

:- dynamic failed/1.
:- dynamic test:current_model/1.


% =============================================================================
%  Test case lists
% =============================================================================

%! test:cases(?List)
%
% Master list of all overlay test cases.

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


% =============================================================================
%  Test runner
% =============================================================================

%! test:run(+Atom)
%
% Runs the named test case list and outputs individual results to the
% Tests directory. Collects and reports failures at the end.

test:run(Cases) :-
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


%! test:run(+application)
%
% Runs the full application test suite: reader, parser, prover, planner,
% and builder.

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


%! test:run_single_case(+Target)
%
% Proves, plans, schedules, and validates a single test case. Writes
% full proof/model/constraint/trigger/plan output to a file in the
% Tests directory, then displays results interactively.

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
   ignore(state:wait_for_input),
   !.


% -----------------------------------------------------------------------------
%  Output helpers
% -----------------------------------------------------------------------------

%! test:write_description(+File)
%
% Copies the contents of File to the current output stream.

write_description(File) :-
    setup_call_cleanup(
        open(File, read, In),
        copy_stream_data(In, user_output),
        close(In)
    ).


%! test:write_proof(+Proof)
%
% Writes proof AVL entries to current output.

write_proof(Proof) :-
  message:color(darkgray),
  forall(gen_assoc(Key,Proof,Value),
     (write(Key),write(' - '),write(Value),nl)),nl,
  message:color(cyan).


%! test:write_model(+Model)
%
% Writes model AVL entries to current output.

write_model(Model) :-
  message:color(darkgray),
  forall(gen_assoc(Key,Model,Value),
      (write(Key),write(' - '),write(Value),nl)),nl,
  message:color(cyan).


%! test:write_constraints(+Constraints)
%
% Writes constraint AVL entries to current output.

write_constraints(Constraints) :-
  message:color(darkgray),
  forall(gen_assoc(Key,Constraints,Value),
       (write(Key),write(' - '),write(Value),nl)),nl,
  message:color(cyan).


%! test:write_triggers(+Triggers)
%
% Writes trigger AVL entries to current output.

write_triggers(Triggers) :-
  message:color(darkgray),
  forall(gen_assoc(Key,Triggers,Value),
      (write(Key),write(' - '),write(Value),nl)),nl,
  message:color(cyan).


%! test:write_plan(+Plan)
%
% Writes plan steps to current output.

write_plan(Plan) :-
  message:color(darkgray),
  forall(member(Step,Plan),
      writeln(Step)),nl,nl,
  message:color(normal).


% =============================================================================
%  Model validation
% =============================================================================

%! test:in_model(+Template, +Model)
%
% Succeeds when Template matches an entry in the proof Model.

test:in_model(Repo://Entry:Action?{Context},Model) :-
  !, once(gen_assoc(Repo://Entry:Action,Model,Context)).

test:in_model(assumed(Predicate:Action?{Context}),Model) :-
  !, once(gen_assoc(assumed(Predicate:Action),Model,Context)).


% =============================================================================
%  Validation framework
% =============================================================================

%! test:is_success(+Target, +Proof, +Plan, +Model, +Triggers)
%
% Legacy multifile hook for per-case validation. Override with
% test:expect/2 for new tests.

%! test:validate(+Target, +Proof, +Plan, +Model, +Triggers)
%
% Validates a test case using the expectation DSL. If test:xfail/2
% exists for Target, failure is expected (XFAIL); unexpected success
% is reported as XPASS and fails.

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


%! test:validate_must_pass(+Target, +Proof, +Plan, +Model, +Triggers)
%
% Dispatches to test:expect/2 if available, otherwise falls back to
% the legacy test:is_success/5 hook.

test:validate_must_pass(Target, Proof, Plan, Model, Triggers) :-
  ( test:expect(Target, Expectations) ->
      test:check_expectations(Expectations, Target, Proof, Plan, Model, Triggers)
  ; test:is_success(Target, Proof, Plan, Model, Triggers)
  ).


%! test:check_expectations(+Expectations, +Target, +Proof, +Plan, +Model, +Triggers)
%
% Iterates a list of expectation terms and checks each one in turn.
% Reports the first failing expectation and fails.

test:check_expectations([], _Target, _Proof, _Plan, _Model, _Triggers) :- !.
test:check_expectations([E|Es], Target, Proof, Plan, Model, Triggers) :-
  ( test:check_expectation(E, Target, Proof, Plan, Model, Triggers) -> true
  ; writeln('Expectation failed:'), writeln(E), fail
  ),
  test:check_expectations(Es, Target, Proof, Plan, Model, Triggers).


%! test:check_expectation(+Expectation, +Target, +Proof, +Plan, +Model, +Triggers)
%
% Evaluates a single expectation. Supports in_model, not_in_model,
% one_of_in_model, and arbitrary goal-style expectations evaluated
% against a temporarily asserted current model.

test:check_expectation(in_model(T), _Target, _Proof, _Plan, Model, _Triggers) :-
  test:in_model(T, Model).

test:check_expectation(not_in_model(T), _Target, _Proof, _Plan, Model, _Triggers) :-
  \+ test:in_model(T, Model).

test:check_expectation(one_of_in_model(List), _Target, _Proof, _Plan, Model, _Triggers) :-
  member(T, List),
  test:in_model(T, Model),
  !.

test:check_expectation(Goal, _Target, _Proof, _Plan, Model, _Triggers) :-
  setup_call_cleanup(
    asserta(test:current_model(Model)),
    call(Goal),
    retract(test:current_model(Model))
  ).


%! test:must_have(+Template)
%
% Succeeds when Template occurs in the current model. Intended for use
% inside test:expect/2 expectation lists.

test:must_have(Template) :-
  test:current_model(Model),
  test:in_model(Template, Model).



% =============================================================================
%  Test expectations
% =============================================================================

% -----------------------------------------------------------------------------
%  Basic dependency resolution (test01, test02, test16)
% -----------------------------------------------------------------------------

% test01: simple dependency tree (web -> app -> db -> os)
test:expect(overlay://'test01/web-1.0':run?{[]},
            [ test:must_have(overlay://'test01/web-1.0':run?{_}),
              test:must_have(overlay://'test01/app-1.0':run?{_}),
              test:must_have(overlay://'test01/db-1.0':run?{_}),
              test:must_have(overlay://'test01/os-1.0':run?{_})
            ]).

% test02: version selection (2.0 preferred over 1.0)
test:expect(overlay://'test02/web-2.0':run?{[]},
            [ test:must_have(overlay://'test02/web-2.0':run?{_}),
              test:must_have(overlay://'test02/app-2.0':run?{_}),
              test:must_have(overlay://'test02/db-2.0':run?{_}),
              test:must_have(overlay://'test02/os-2.0':run?{_}),
              \+ test:must_have(overlay://'test02/app-1.0':_?{_}),
              \+ test:must_have(overlay://'test02/db-1.0':_?{_}),
              \+ test:must_have(overlay://'test02/os-1.0':_?{_}),
              \+ test:must_have(overlay://'test02/web-1.0':_?{_})
            ]).

% test16: basic sanity check (structurally identical to test01)
test:expect(overlay://'test16/web-1.0':run?{[]},
            [ test:must_have(overlay://'test16/web-1.0':run?{_}),
              test:must_have(overlay://'test16/app-1.0':run?{_}),
              test:must_have(overlay://'test16/db-1.0':run?{_}),
              test:must_have(overlay://'test16/os-1.0':run?{_})
            ]).

% -----------------------------------------------------------------------------
%  Circular dependencies (test03..test08)
% -----------------------------------------------------------------------------

% test03: os depends on itself (compile) -- cycle-break assumption expected
test:expect(overlay://'test03/web-1.0':run?{[]},
            [ test:must_have(overlay://'test03/web-1.0':run?{_}),
              test:must_have(overlay://'test03/os-1.0':run?{_}),
              test:must_have(assumed(_:install?{_}))
            ]).

% test04: os depends on itself (runtime) -- cycle-break assumption expected
test:expect(overlay://'test04/web-1.0':run?{[]},
            [ test:must_have(overlay://'test04/web-1.0':run?{_}),
              test:must_have(overlay://'test04/os-1.0':run?{_}),
              test:must_have(assumed(_:run?{_}))
            ]).

% test05: os depends on itself (compile + runtime) -- two assumptions expected
test:expect(overlay://'test05/web-1.0':run?{[]},
            [ test:must_have(overlay://'test05/web-1.0':run?{_}),
              test:must_have(overlay://'test05/os-1.0':run?{_}),
              test:must_have(assumed(_:install?{_})),
              test:must_have(assumed(_:run?{_}))
            ]).

% test06: indirect cycle (os -> web compile, web -> os)
test:expect(overlay://'test06/web-1.0':run?{[]},
            [ test:must_have(overlay://'test06/web-1.0':run?{_}),
              test:must_have(overlay://'test06/os-1.0':run?{_}),
              test:must_have(assumed(_:_?{_}))
            ]).

% test07: indirect cycle (os -> web runtime, web -> os)
test:expect(overlay://'test07/web-1.0':run?{[]},
            [ test:must_have(overlay://'test07/web-1.0':run?{_}),
              test:must_have(overlay://'test07/os-1.0':run?{_}),
              test:must_have(assumed(_:_?{_}))
            ]).

% test08: indirect cycle (os -> web compile+runtime, web -> os)
test:expect(overlay://'test08/web-1.0':run?{[]},
            [ test:must_have(overlay://'test08/web-1.0':run?{_}),
              test:must_have(overlay://'test08/os-1.0':run?{_}),
              test:must_have(assumed(_:_?{_}))
            ]).

% -----------------------------------------------------------------------------
%  Missing dependencies (test09..test11)
% -----------------------------------------------------------------------------

% test09: os -> test09/notexists (compile) -- domain assumption expected
test:expect(overlay://'test09/os-1.0':run?{[]},
            [ test:must_have(overlay://'test09/os-1.0':run?{_}),
              test:must_have(assumed(_:_?{_}))
            ]).

% test10: os -> test10/notexists (runtime) -- domain assumption expected
test:expect(overlay://'test10/os-1.0':run?{[]},
            [ test:must_have(overlay://'test10/os-1.0':run?{_}),
              test:must_have(assumed(_:_?{_}))
            ]).

% test11: os -> test11/notexists (compile + runtime) -- domain assumption expected
test:expect(overlay://'test11/os-1.0':run?{[]},
            [ test:must_have(overlay://'test11/os-1.0':run?{_}),
              test:must_have(assumed(_:_?{_}))
            ]).

% -----------------------------------------------------------------------------
%  Keywords and version constraints (test12, test13)
% -----------------------------------------------------------------------------

% test12: 2.0 versions are unstable (~amd64), only 1.0 should be selected
test:expect(overlay://'test12/web-1.0':run?{[]},
            [ test:must_have(overlay://'test12/web-1.0':run?{_}),
              test:must_have(overlay://'test12/os-1.0':run?{_}),
              \+ test:must_have(overlay://'test12/web-2.0':_?{_}),
              \+ test:must_have(overlay://'test12/os-2.0':_?{_})
            ]).

% test13: app-2.0 requires =db-2.0, should resolve to 2.0 versions
test:expect(overlay://'test13/web-2.0':run?{[]},
            [ test:must_have(overlay://'test13/web-2.0':run?{_}),
              test:must_have(overlay://'test13/app-2.0':run?{_}),
              test:must_have(overlay://'test13/db-2.0':run?{_}),
              test:must_have(overlay://'test13/os-2.0':run?{_})
            ]).

% -----------------------------------------------------------------------------
%  USE conditional dependencies (test14, test15)
% -----------------------------------------------------------------------------

% test14: app DEPEND="os lib? ( lib )" -- lib selected based on USE=lib
test:expect(overlay://'test14/web-1.0':run?{[]},
            [ test:must_have(overlay://'test14/web-1.0':run?{_}),
              test:must_have(overlay://'test14/app-1.0':run?{_}),
              test:must_have(overlay://'test14/os-1.0':run?{_})
            ]).

% test15: app DEPEND="os !nolib? ( lib )" -- negative USE conditional
test:expect(overlay://'test15/web-1.0':run?{[]},
            [ test:must_have(overlay://'test15/web-1.0':run?{_}),
              test:must_have(overlay://'test15/app-1.0':run?{_}),
              test:must_have(overlay://'test15/os-1.0':run?{_})
            ]).

% -----------------------------------------------------------------------------
%  Exactly-one-of groups ^^ (test17..test19)
% -----------------------------------------------------------------------------

% test17: os -> ^^ ( linux bsd windows ) (compile)
test:expect(overlay://'test17/web-1.0':run?{[]},
            [ test:must_have(overlay://'test17/os-1.0':run?{_}),
              ( test:must_have(overlay://'test17/linux-1.0':run?{_})
              ; test:must_have(overlay://'test17/bsd-1.0':run?{_})
              ; test:must_have(overlay://'test17/windows-1.0':run?{_})
              )
            ]).

% test18: os -> ^^ ( linux bsd windows ) (runtime)
test:expect(overlay://'test18/web-1.0':run?{[]},
            [ test:must_have(overlay://'test18/os-1.0':run?{_}),
              ( test:must_have(overlay://'test18/linux-1.0':run?{_})
              ; test:must_have(overlay://'test18/bsd-1.0':run?{_})
              ; test:must_have(overlay://'test18/windows-1.0':run?{_})
              )
            ]).

% test19: os -> ^^ ( linux bsd windows ) (compile + runtime)
test:expect(overlay://'test19/web-1.0':run?{[]},
            [ test:must_have(overlay://'test19/os-1.0':run?{_}),
              ( test:must_have(overlay://'test19/linux-1.0':run?{_})
              ; test:must_have(overlay://'test19/bsd-1.0':run?{_})
              ; test:must_have(overlay://'test19/windows-1.0':run?{_})
              )
            ]).

% -----------------------------------------------------------------------------
%  Any-of groups || (test20..test22, test26..test31)
% -----------------------------------------------------------------------------

% test20: os -> || ( linux bsd windows ) (compile)
test:expect(overlay://'test20/web-1.0':run?{[]},
            [ test:must_have(overlay://'test20/os-1.0':run?{_}),
              ( test:must_have(overlay://'test20/linux-1.0':run?{_})
              ; test:must_have(overlay://'test20/bsd-1.0':run?{_})
              ; test:must_have(overlay://'test20/windows-1.0':run?{_})
              )
            ]).

% test21: os -> || ( linux bsd windows ) (runtime)
test:expect(overlay://'test21/web-1.0':run?{[]},
            [ test:must_have(overlay://'test21/os-1.0':run?{_}),
              ( test:must_have(overlay://'test21/linux-1.0':run?{_})
              ; test:must_have(overlay://'test21/bsd-1.0':run?{_})
              ; test:must_have(overlay://'test21/windows-1.0':run?{_})
              )
            ]).

% test22: os -> || ( linux bsd windows ) (compile + runtime)
test:expect(overlay://'test22/web-1.0':run?{[]},
            [ test:must_have(overlay://'test22/os-1.0':run?{_}),
              ( test:must_have(overlay://'test22/linux-1.0':run?{_})
              ; test:must_have(overlay://'test22/bsd-1.0':run?{_})
              ; test:must_have(overlay://'test22/windows-1.0':run?{_})
              )
            ]).

% test26..test31: any-of variants (same structure as test20)
test:expect(overlay://'test26/web-1.0':run?{[]},
            [ test:must_have(overlay://'test26/os-1.0':run?{_}) ]).
test:expect(overlay://'test27/web-1.0':run?{[]},
            [ test:must_have(overlay://'test27/os-1.0':run?{_}) ]).
test:expect(overlay://'test28/web-1.0':run?{[]},
            [ test:must_have(overlay://'test28/os-1.0':run?{_}) ]).
test:expect(overlay://'test29/web-1.0':run?{[]},
            [ test:must_have(overlay://'test29/os-1.0':run?{_}) ]).
test:expect(overlay://'test30/web-1.0':run?{[]},
            [ test:must_have(overlay://'test30/os-1.0':run?{_}) ]).
test:expect(overlay://'test31/web-1.0':run?{[]},
            [ test:must_have(overlay://'test31/os-1.0':run?{_}) ]).

% -----------------------------------------------------------------------------
%  At-most-one-of groups ?? (test23..test25)
% -----------------------------------------------------------------------------

% test23: os -> ?? ( linux bsd windows ) (compile) -- none required
test:expect(overlay://'test23/web-1.0':run?{[]},
            [ test:must_have(overlay://'test23/os-1.0':run?{_}) ]).

% test24: os -> ?? ( linux bsd windows ) (runtime) -- none required
test:expect(overlay://'test24/web-1.0':run?{[]},
            [ test:must_have(overlay://'test24/os-1.0':run?{_}) ]).

% test25: os -> ?? ( linux bsd windows ) (compile + runtime) -- none required
test:expect(overlay://'test25/web-1.0':run?{[]},
            [ test:must_have(overlay://'test25/os-1.0':run?{_}) ]).

% -----------------------------------------------------------------------------
%  REQUIRED_USE (test32, test40)
% -----------------------------------------------------------------------------

% test32: REQUIRED_USE ^^ (linux darwin) + conditional deps
test:expect(overlay://'test32/os-1.0':run?{[]},
            [ test:must_have(overlay://'test32/os-1.0':run?{_}),
              ( test:must_have(overlay://'test32/linux-1.0':run?{_})
              ; test:must_have(overlay://'test32/darwin-1.0':run?{_})
              )
            ]).

% test40: REQUIRED_USE || (linux darwin) on standalone os
test:expect(overlay://'test40/os-1.0':run?{[]},
            [ test:must_have(overlay://'test40/os-1.0':run?{_}) ]).

% -----------------------------------------------------------------------------
%  USE flag propagation (test33..test39)
% -----------------------------------------------------------------------------

% test33: app -> os[linux] -- os must be selected
test:expect(overlay://'test33/app-1.0':run?{[]},
            [ test:must_have(overlay://'test33/app-1.0':run?{_}),
              test:must_have(overlay://'test33/os-1.0':run?{_})
            ]).

% test34: app -> os[-linux] -- os must be selected
test:expect(overlay://'test34/app-1.0':run?{[]},
            [ test:must_have(overlay://'test34/app-1.0':run?{_}),
              test:must_have(overlay://'test34/os-1.0':run?{_})
            ]).

% test35: app -> os[linux=] -- USE propagation
test:expect(overlay://'test35/app-1.0':run?{[]},
            [ test:must_have(overlay://'test35/app-1.0':run?{_}),
              test:must_have(overlay://'test35/os-1.0':run?{_})
            ]).

% test36: app -> lib[linux=] -> os[linux=] -- chained USE propagation
test:expect(overlay://'test36/app-1.0':run?{[]},
            [ test:must_have(overlay://'test36/app-1.0':run?{_}),
              test:must_have(overlay://'test36/lib-1.0':run?{_}),
              test:must_have(overlay://'test36/os-1.0':run?{_})
            ]).

% test37: app -> os[!linux=] -- inverse USE conditional
test:expect(overlay://'test37/app-1.0':run?{[]},
            [ test:must_have(overlay://'test37/app-1.0':run?{_}),
              test:must_have(overlay://'test37/os-1.0':run?{_})
            ]).

% test38: app -> os[linux?] -- weak conditional
test:expect(overlay://'test38/app-1.0':run?{[]},
            [ test:must_have(overlay://'test38/app-1.0':run?{_}),
              test:must_have(overlay://'test38/os-1.0':run?{_})
            ]).

% test39: app -> os[-linux?] -- negative weak conditional
test:expect(overlay://'test39/app-1.0':run?{[]},
            [ test:must_have(overlay://'test39/app-1.0':run?{_}),
              test:must_have(overlay://'test39/os-1.0':run?{_})
            ]).

% Bracketed USE install expectations (for test:bracketed_use subset)
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

% -----------------------------------------------------------------------------
%  Slot dependencies (test41..test44)
% -----------------------------------------------------------------------------

% test41: app -> lib:1
test:expect(overlay://'test41/app-1.0':run?{[]},
            [ test:must_have(overlay://'test41/app-1.0':run?{_}),
              test:must_have(overlay://'test41/lib-1.0':run?{_})
            ]).

% test42: app -> lib:*
test:expect(overlay://'test42/app-1.0':run?{[]},
            [ test:must_have(overlay://'test42/app-1.0':run?{_}),
              ( test:must_have(overlay://'test42/lib-1.0':run?{_})
              ; test:must_have(overlay://'test42/lib-2.0':run?{_})
              )
            ]).

% test43: app -> lib:= (slot equality)
test:expect(overlay://'test43/app-1.0':run?{[]},
            [ test:must_have(overlay://'test43/app-1.0':run?{_}),
              ( test:must_have(overlay://'test43/lib-1.0':run?{_})
              ; test:must_have(overlay://'test43/lib-2.0':run?{_})
              )
            ]).

% test44: app -> lib:1/A (sub-slot)
test:expect(overlay://'test44/app-1.0':run?{[]},
            [ test:must_have(overlay://'test44/app-1.0':run?{_}),
              test:must_have(overlay://'test44/lib-1.0':run?{_})
            ]).

% -----------------------------------------------------------------------------
%  Conflicts and unsolvable cases (test45, test46, test47, test48, test49, test51)
% -----------------------------------------------------------------------------

% test45: USE conflict: liba->os[linux], libb->os[darwin], os has ^^ (linux darwin)
test:expect(overlay://'test45/app-1.0':run?{[]},
            [ test:must_have(overlay://'test45/app-1.0':run?{_}),
              test:must_have(assumed(_:_?{_}))
            ]).

% test46: double diamond USE conflict on core-utils feature_x
test:expect(overlay://'test46/app-1.0':run?{[]},
            [ test:must_have(overlay://'test46/app-1.0':run?{_}),
              test:must_have(assumed(_:_?{_}))
            ]).

% test47: three-way cycle: app-client -> api-docs -> app-server -> app-client
test:expect(overlay://'test47/api-docs-1.0':run?{[]},
            [ test:must_have(overlay://'test47/api-docs-1.0':run?{_}),
              test:must_have(assumed(_:_?{_}))
            ]).

% test48: slotting conflict: libgraphics and libphysics need different libmatrix versions
test:expect(overlay://'test48/app-1.0':run?{[]},
            [ test:must_have(overlay://'test48/app-1.0':run?{_}),
              test:must_have(assumed(_:_?{_}))
            ]).

% test49: USE default vs REQUIRED_USE conflict
test:expect(overlay://'test49/app-1.0':run?{[]},
            [ test:must_have(overlay://'test49/app-1.0':run?{_}),
              test:must_have(assumed(_:_?{_}))
            ]).

% test51: app -> os[linux], os has REQUIRED_USE="!linux"
test:expect(overlay://'test51/app-1.0':install?{[]},
            [ test:must_have(assumed(_:_?{_}))
            ]).

% -----------------------------------------------------------------------------
%  Transitive and multi-USE (test50, test52, test53)
% -----------------------------------------------------------------------------

% test50: transitive deps: app -> foo -> bar
test:expect(overlay://'test50/app-1.0':run?{[]},
            [ test:must_have(overlay://'test50/app-1.0':run?{_}),
              test:must_have(overlay://'test50/foo-1.0':run?{_}),
              test:must_have(overlay://'test50/bar-1.0':run?{_})
            ]).

% test52: multiple USE flags: liba->os[threads], libb->os[hardened]
test:expect(overlay://'test52/app-1.0':run?{[]},
            [ test:must_have(overlay://'test52/app-1.0':run?{_}),
              test:must_have(overlay://'test52/os-1.0':run?{_})
            ]).

% test53: like test52 + os->libhardened when hardened enabled
test:expect(overlay://'test53/app-1.0':run?{[]},
            [ test:must_have(overlay://'test53/app-1.0':run?{_}),
              test:must_have(overlay://'test53/os-1.0':run?{_})
            ]).

% -----------------------------------------------------------------------------
%  Misc (test54, test55)
% -----------------------------------------------------------------------------

% test54: expanding USE flags output
test:expect(overlay://'test54/app-1.0':run?{[]},
            [ test:must_have(overlay://'test54/app-1.0':run?{_}) ]).

% test55: version constraints: lib>3.0 and lib<6.0
test:expect(overlay://'test55/app-1.0':run?{[]},
            [ test:must_have(overlay://'test55/app-1.0':run?{_}) ]).

% -----------------------------------------------------------------------------
%  Virtuals and PROVIDE (test57, test58)
% -----------------------------------------------------------------------------

% test57: virtual-style ebuild must pull its provider
test:expect(overlay://'test57/web-1.0':run?{[]},
            [ test:must_have(overlay://'test57/virtualsdk-1.0':run?{_}),
              test:must_have(overlay://'test57/linux-1.0':run?{_})
            ]).

% test58: PROVIDE-based virtual satisfaction (deprecated PMS)
test:expect(overlay://'test58/web-1.0':run?{[]},
            [ test:must_have(overlay://'test58/linux-1.0':run?{_})
            ]).

% -----------------------------------------------------------------------------
%  Any-of and blocker regressions (test59, test60)
% -----------------------------------------------------------------------------

% test59: any-of group must select at least one alternative
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
%  Cycle regression tests (test61..test64)
% -----------------------------------------------------------------------------

% test61: mutual recursion with bracketed USE: app -> a -> b[foo] -> a[foo]
test:expect(overlay://'test61/app-1.0':run?{[]},
            [ test:must_have(overlay://'test61/app-1.0':run?{_}) ]).

% test62: simple mutual cycle: web -> a -> b -> a
test:expect(overlay://'test62/web-1.0':run?{[]},
            [ test:must_have(overlay://'test62/web-1.0':run?{_}),
              test:must_have(assumed(_:_?{_}))
            ]).

% test63: REQUIRED_USE use-conditional loop (openmpi-style)
test:expect(overlay://'test63/app-1.0':run?{[]},
            [ test:must_have(overlay://'test63/app-1.0':run?{_}) ]).

% test64: OpenMP-style USE-conditional churn
test:expect(overlay://'test64/app-1.0':run?{[]},
            [ test:must_have(overlay://'test64/app-1.0':run?{_}) ]).

% -----------------------------------------------------------------------------
%  Build-with-use reinstall regression (test65)
% -----------------------------------------------------------------------------

% test65: installed entries must satisfy incoming build_with_use
test:expect(overlay://'test65/app-1.0':run?{[]},
            [ ( query:search([repository(pkg),installed(true)], pkg://E),
                query:search([category(C),name(N)], pkg://E),
                \+ use:installed_entry_satisfies_build_with_use(pkg://E,
                      [build_with_use:[required('__portage_ng_test_flag__')]]),
                G = grouped_package_dependency(no,C,N,
                      [package_dependency(run,no,C,N,none,[[],'','','',''],[],[])]):run?{
                        [build_with_use:[required('__portage_ng_test_flag__')]]
                      },
                rules:rule(G, Conds),
                Conds \== []
              )
            ]).
