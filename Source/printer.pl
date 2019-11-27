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

%! printer:printable(+Literal)
%
% Declares which Literals are printable

printer:printable(_Repository://_Entry:_Action) :- !.
printer:printable(package_dependency(run,_,_,_,_,_,_,_)) :- !.
printer:printable(assumed(_Repository://_Entry:_Action)) :- !.
%printer:printable(assumed(package_dependency(_,_,_,_,_,_,_,_))) :- !.


%! printer:prin(+Printable)
%
% Prints a printable Literal

% simple package, target

printer:print_element(Repository://Entry:Action,rule(Repository://Entry:Action,_)) :-
  !,
  message:color(cyan),
  message:print(Action),
  message:style(bold),
  message:color(green),
  message:column(35,Repository://Entry),
  message:color(normal),
  nl.

% simple package, non target

printer:print_element(_://_:_,rule(Repository://Entry:Action,_)) :-
  message:color(cyan),
  message:print(Action),
  message:color(green),
  message:column(30,Repository://Entry),
  message:color(normal),
  nl.

% verify run

printer:print_element(_,rule(package_dependency(run,_,_C,_N,_,_,_,_),[Repository://Entry:_Action])) :-
  !,
  message:color(cyan),
  message:print('verify'),
  message:color(green),
  message:column(30,Repository://Entry),
  message:color(normal),
  nl.

% a non-existent package

printer:print_element(_,rule(package_dependency(_Action,_,C,N,_,_,_,_),[])) :-
  message:color(red),
  message:print('assumed'),
  atomic_list_concat([C,'/',N],P),
  message:column(30,P),
  message:print([' (not found)']),
  message:color(normal),
  nl.

% an assumed installed package

printer:print_element(_,rule(assumed(Repository://Entry:install),_Body)) :-
  message:color(red),
  message:print('assumed'),
  message:column(30,Repository://Entry),
  message:print(' (assumed installed)'),
  message:color(normal),
  nl.

% an assumed running package

printer:print_element(_,rule(assumed(Repository://Entry:run),_Body)) :-
  message:color(red),
  message:print('assumed'),
  message:column(30,Repository://Entry),
  message:print(' (assumed running)'),
  message:color(normal),
  nl.


% an assumed dependency

printer:print_element(_,rule(assumed(package_dependency(Action,_,C,N,_,_,_,_),_Body))) :-
  message:color(red),
  message:print(Action),
  message:color(green),
  atomic_list_concat([C,'/',N],P),
  message:column(30,P),
  message:color(red),
  message:print(' (assumed) '),
  message:color(normal),
  nl.


%! printer:checkassumptions(+Model)
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


%! printer:printheader(+Target)
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


%! printer:printbody(+Plan,+Model)
%
% Prints the body for a given plan and model

printer:print_body(Target,Plan) :-
  forall(member(E,Plan),
    printer:firststep(Target,E)).


%! printer:printassumptions(+Model)
%
% Print the assumptions taken by the prover

printer:print_assumptions(Model) :-
  printer:check_assumptions(Model),!,
  message:color(red),message:print('Error: '),
  message:print('A circular dependency was detected. The following assumptions were taken:'),nl,nl,
  forall(member(assumed(A),Model),
    (message:print([' - ',A]),nl)),
  nl,
  message:color(normal).

printer:print_assumptions(_Model) :- !.


%! printer:printfooter(+Plan)
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
  nl,nl.

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
  printer:print_debug(Model,Proof,Plan),
  printer:print_body(Target,Plan),
  printer:print_assumptions(Model),
  printer:print_footer(Plan,Model).


%! printer:firststep(+Target,+Step)
%
% Print a step in a plan

printer:firststep(_,[]) :- !.

printer:firststep(Target, [rule(Literal,Body)|L]) :-
  printer:printable(Literal),
  !,
  write(' -  STEP:  | '),
  printer:print_element(Target,rule(Literal,Body)),
  printer:nextstep(Target,L).

printer:firststep(Target,[rule(_,_)|L]) :-
  printer:firststep(Target,L).


%! printer:nextstep(+Step)
%
% Print a step in a plan

printer:nextstep(_,[]) :- nl,!.

printer:nextstep(Target,[rule(Literal,Body)|L]) :-
  printer:printable(Literal),
  !,
  write('           | '),
  printer:print_element(Target,rule(Literal,Body)),
  printer:nextstep(Target,L).

printer:nextstep(Target,[rule(_,_)|L]) :-
  printer:nextstep(Target,L).


%! printer:test(+Repository)
%
% Proves and prints every entry in a given repository

printer:test(Repository) :-
  preference:proving_target(Action),
  time(forall(Repository:entry(E),
 	      ((nl,message:header(["Planning ",Repository://E:Action]),
                prover:prove(Repository://E:Action,[],Proof,[],Model),
                planner:plan(Proof,[],[],Plan),
                printer:print(Repository://E:Action,Model,Proof,Plan));
	       (message:failure(E))))
      ),
  Repository:get_size(S),
  message:inform(['printed plan for ',S,' ',Repository,' entries.']).
