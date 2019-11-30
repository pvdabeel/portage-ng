/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2019, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> PRINTER
The Printer takes a plan from the Planner and pretty prints it.
*/

:- module(printer, []).

% ********************
% PRINTER declarations
% ********************

%! printer:printable_element(+Literal)
%
% Declares which Literals are printable

printer:printable_element(rule(_Repository://_Entry:_Action,_)) :- !.
%printer:printable_element(rule(package_dependency(run,_,_,_,_,_,_,_),_)) :- !.
printer:printable_element(assumed(rule(_Repository://_Entry:_Action,_))) :- !.
printer:printable_element(assumed(rule(package_dependency(_,_,_,_,_,_,_,_),_))) :- !.
printer:printable_element(rule(assumed(package_dependency(_,_,_,_,_,_,_,_)),_)) :- !.



%! printer:print_element(+Printable)
%
% Prints a printable Literal

% simple package, is a target of the plan

printer:print_element(Repository://Entry:Action,rule(Repository://Entry:Action,_)) :-
  !,
  message:color(cyan),
  message:print(Action),
  message:style(bold),
  message:color(green),
  message:column(35,Repository://Entry),
  message:color(normal),
  nl.

% simple package, is not a target of the plan

printer:print_element(_://_:_,rule(Repository://Entry:Action,_)) :-
  message:color(cyan),
  message:print(Action),
  message:color(green),
  message:column(30,Repository://Entry),
  message:color(normal),
  nl.

% verify that packages that need to be running are running

printer:print_element(_,rule(package_dependency(run,_,_C,_N,_,_,_,_),[Repository://Entry:_Action])) :-
  !,
  message:color(cyan),
  message:print('verify'),
  message:color(green),
  message:column(30,Repository://Entry),
  message:color(normal),
  nl.

% an assumed dependency on a non-existent installed package

printer:print_element(_,rule(assumed(package_dependency(install,_,C,N,_,_,_,_)),[])) :-
  message:color(red),
  message:print('assumed'),
  atomic_list_concat([C,'/',N],P),
  message:column(25,P),
  message:print([' (non-existent, assumed installed)']),
  message:color(normal),
  nl.

% an assumed dependency on a non-existent running package

printer:print_element(_,rule(assumed(package_dependency(run,_,C,N,_,_,_,_)),[])) :-
  message:color(red),
  message:print('assumed'),
  atomic_list_concat([C,'/',N],P),
  message:column(25,P),
  message:print([' (non-existent, assumed running)']),
  message:color(normal),
  nl.


% an assumed installed package

printer:print_element(_,assumed(rule(Repository://Entry:install,_Body))) :-
  message:color(red),
  message:print('assumed'),
  message:column(25,Repository://Entry),
  message:print(' (assumed installed)'),
  message:color(normal),
  nl.

% an assumed running package

printer:print_element(_,assumed(rule(Repository://Entry:run,_Body))) :-
  message:color(red),
  message:print('assumed'),
  message:column(25,Repository://Entry),
  message:print(' (assumed running)'),
  message:color(normal),
  nl.

% an assumed installed dependency

printer:print_element(_,assumed(rule(package_dependency(install,_,C,N,_,_,_,_),_Body))) :-
  message:color(red),
  message:print('assumed'),
  atomic_list_concat([C,'/',N],P),
  message:column(25,P),
  message:print(' (assumed installed) '),
  message:color(normal),
  nl.


% an assumed running dependency

printer:print_element(_,assumed(rule(package_dependency(run,_,C,N,_,_,_,_),_Body))) :-
  message:color(red),
  message:print('assumed'),
  atomic_list_concat([C,'/',N],P),
  message:column(30,P),
  message:print(' (assumed running) '),
  message:color(normal),
  nl.



%! printer:check_assumptions(+Model)
%
% Checks whether the Model contains assumptions

printer:check_assumptions(Model) :-
  member(assumed(_),Model),!.


%! printer:print_debug(+Model,+Proof,+Plan)
%
% Prints debug info for a given Model, Proof and Plan

printer:print_debug(_Model,_Proof,Plan) :-
  message:color(darkgray),
  % message:inform(['Model : ',Model]),nl,
  % message:inform(['Proof : ',Proof]),nl,
  forall(member(X,Plan),(write(' -> '),writeln(X))),nl,
  message:color(normal).


%! printer:print_header(+Target)
%
% Prints the header for a given target

printer:print_header(Target) :-
  message:header(['Emerging ', Target]),
  nl,
  message:color(green),
  message:print('These are the packages that would be merged, in order:'),nl,
  nl,
  message:color(normal),
  message:print('Calculating dependencies... done!'),nl,
  nl.


%! printer:print_body(+Plan,+Model)
%
% Prints the body for a given plan and model

printer:print_body(Target,Plan) :-
  forall(member(E,Plan),
    printer:firststep(Target,E)).


%! printer:print_warnings(+Model, +Proof)
%
% Print the assumptions taken by the prover

printer:print_warnings(Model,Proof) :-
  printer:check_assumptions(Model),!,
  message:color(red),message:print('Error: '),
  message:print('The proof for your build plan contains assumptions. Please verify:'),nl,nl,
  forall(member(assumed(rule(C,_)),Proof),
    (message:print([' - Circular dependency: ',C]),nl)),
  forall(member(rule(assumed(U),_),Proof),
    (message:print([' - Non-existent ebuild: ',U]),nl)),
  nl,
  message:color(normal),nl.

printer:print_warnings(_Model,_Proof) :- !, nl.


%! printer:print_footer(+Plan)
%
% Print the footer for a given plan

printer:print_footer(Plan,Model) :-
  countlist(assumed(_),Model,_Assumptions),
  countlist(_://_:_,Model,Actions),
  countlist(_://_:run,Model,Runs),
  countlist(_://_:install,Model,Installs),
  countlist(package_dependency(run,_,_,_,_,_,_,_),Model,Verifs),
  Total is Actions + Verifs,
  length(Plan,Steps),
  message:print(['Total: ', Total, ' actions (', Installs,' installs, ', Runs,' runs, ', Verifs,' verifications), grouped into ',Steps,' steps.' ]),nl,
  nl.

unify(A,B) :- unifiable(A,B,_),!.

countlist(Predicate,List,Count) :-
  include(unify(Predicate),List,Sublist),!,
  length(Sublist,Count).

countlist(_,_,0) :- !.


%! printer:print(+Plan)
%
% Print a given plan

printer:print(Target,Model,Proof,Plan) :-
  printer:print_header(Target),
% printer:print_debug(Model,Proof,Plan),
  printer:print_body(Target,Plan),
  printer:print_footer(Plan,Model),
  printer:print_warnings(Model,Proof).


%! printer:firststep(+Target,+Step)
%
% Print a step in a plan

printer:firststep(_,[]) :- !.

printer:firststep(Target, [Rule|L]) :-
  printer:printable_element(Rule),
  !,
  write(' -  STEP:  | '),
  printer:print_element(Target,Rule),
  printer:nextstep(Target,L).

printer:firststep(Target,[_|L]) :-
  printer:firststep(Target,L).


%! printer:nextstep(+Step)
%
% Print a step in a plan

printer:nextstep(_,[]) :- nl,!.

printer:nextstep(Target,[Rule|L]) :-
  printer:printable_element(Rule),
  !,
  write('           | '),
  printer:print_element(Target,Rule),
  printer:nextstep(Target,L).

printer:nextstep(Target,[_|L]) :-
  printer:nextstep(Target,L).


%! printer:test(+Repository)
%
% Proves and prints every entry in a given repository

printer:test(Repository) :-
  preference:proving_target(Action),
  time(forall(Repository:entry(E),
 	      ((nl,message:header(["Planning ",Repository://E:Action]),
                prover:prove(Repository://E:Action,[],Proof,[],Model,[],_Constraints),
                planner:plan(Proof,[],[],Plan),
                printer:print(Repository://E:Action,Model,Proof,Plan));
	       (message:failure(E))))
      ),
  Repository:get_size(S),
  message:inform(['printed plan for ',S,' ',Repository,' entries.']).
