/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2025, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> BUILDER
The Builder takes a plan from the Planner and executes it.
*/

:- module(builder, []).

:- dynamic builder:broken/1.

% ********************
% BUILDER declarations
% ********************


%! builder:build(+Plan)
%
% For a given Plan, prints and executes the plan. The printer is called with
% builder:buildstep as a strategy for realizing the step in the plan.

builder:build(Target,Model,Proof,Plan) :-
  printer:print(Target,Model,Proof,Plan,builder:build_step).


%! builder:build_step(+Step)
%
% For a given Step from a Plan, executes the elements in the step.

builder:build_step(Step) :-
  config:number_of_cpus(Cpus),
  findall(call(builder:build_element,Element),
          (member(Element,Step),builder:buildable_element(Element)),
          Calls),
  concurrent(Cpus,Calls,[]),!.


%! builder:buildable_element(+Literal)
%
% Declares which Literals are buildable

builder:buildable_element(rule(uri(_,_,_),_)) :- !.
builder:buildable_element(rule(uri(_),_)) :- !.
builder:buildable_element(rule(_Repository://_Entry:run,_)) :- !.
builder:buildable_element(rule(_Repository://_Entry:download,_)) :- !.
builder:buildable_element(rule(_Repository://_Entry:install,_)) :- !.
builder:buildable_element(assumed(rule(_Repository://_Entry:_Action,_))) :- !.
builder:buildable_element(assumed(rule(package_dependency(_,_,_,_,_,_,_,_,_),_))) :- !.
builder:buildable_element(rule(assumed(package_dependency(_,_,_,_,_,_,_,_,_)),_)) :- !.


%! builder:build_element(+Printable)
%
% Executes a build plan step element

% --------------------
% CASE: simple package
% --------------------

% Example: Invoke builder:build(portage://myebuild:install to install the
% given ebuild in the portage repository in your live system
% Portage is an example repository of type 'eapi'
%
% Example: Invoke builder:build(linux://torvalds/linux-2.4.2:install to install
% the given Linux kernel release in your live system
% Linux is an example repository of type 'make' (see portage-ng.pl main))
%
% Example: Invoke builder:build(swipl://swi-prolog/swipl-8.1.5:install to
% install the given SWI-Prolog release in your live system
% Swipl is an example respository of type 'cmake' (see portage-ng.pl main)

builder:build_element(rule(Repository://Entry:install,_)) :-
  Repository:get_type('eapi'),!,
  Repository:get_location(L),
  Repository:ebuild(Entry,Category,Package,Version),
  atomic_list_concat(['FEATURES="noauto" ebuild ',L,'/',Category,'/',Package,'/',Package,'-',Version,'.ebuild unpack prepare configure compile preinst install instprep postinst qmerge clean'],Cmd),
  message:color(red),
  message:print(Cmd),nl,
  message:color(normal),!,
  shell(Cmd),!.

builder:build_element(rule(_Repository://_Entry:run,_)) :-
  !.
  %Repository:get_type('eapi'),!,
  %Repository:get_location(L),
  %Repository:ebuild(Entry,Category,Package,Version),
  %atomic_list_concat(['ebuild ',L,'/',Category,'/',Package,'/',Package,'-',Version,'.ebuild run'],Cmd),
  %message:color(red),
  %message:print(Cmd),nl,
  %message:color(normal),!.
  %shell(Cmd),!.

builder:build_element(rule(Repository://Entry:download,_)) :-
  Repository:get_type('eapi'),!,
  Repository:get_location(L),
  Repository:ebuild(Entry,Category,Package,Version),
  atomic_list_concat(['FEATURES="noauto" ebuild ',L,'/',Category,'/',Package,'/',Package,'-',Version,'.ebuild fetch'],Cmd),
  message:color(red),
  message:print(Cmd),nl,
  message:color(normal),!,
  shell(Cmd),!.


builder:build_element(rule(Repository://_Entry:_Action,_)) :-
  Repository:get_type('cmake'),!,
  Repository:get_location(Local),
  script:exec(build,['cmake', Local]).


% --------------------------------------------------------------
% CASE: verify that packages that need to be running are running
% --------------------------------------------------------------

builder:build_element(rule(package_dependency(_,run,_,_C,_N,_,_,_,_),[_Repository://_Entry:_Action])) :-
  true,!.
  %message:print('confirm')


% ----------------
% CASE: a download
% ----------------

builder:build_element(rule(uri(Protocol,Remote,Local),_)) :-
  !,
  atomic_list_concat(['download ',Protocol,'://',Remote,' -> ',Local],Cmd),
  message:color(yellow),
  message:print(Cmd),nl,
  message:color(normal),!.
  %shell(Cmd),!.


builder:build_element(rule(uri(Local),_)) :-
  !,
  atomic_list_concat(['provide ',Local],Cmd),
  message:color(yellow),
  message:print(Cmd),nl,
  message:color(normal),!.
  %shell(Cmd),!.


% ---------------------------------------------------------------
% CASE: an assumed dependency on a non-existent installed package
% ---------------------------------------------------------------

builder:build_element(rule(assumed(package_dependency(_,install,_,_C,_N,_,_,_,_)),[])) :-
  !.
  %message:print('verify'),
  %message:print([' (non-existent, assumed installed)']).

% -------------------------------------------------------------
% CASE: an assumed dependency on a non-existent running package
% -------------------------------------------------------------

builder:build_element(rule(assumed(package_dependency(_,run,_,_C,_N,_,_,_,_)),[])) :-
  !.
  %message:print('verify'),
  %message:print([' (non-existent, assumed running)']).

% ----------------------------------
% CASE: an assumed installed package
% ----------------------------------

builder:build_element(assumed(rule(_Repository://_Entry:install,_Body))) :-
  !.
  %message:print('verify'),
  %message:print(' (assumed installed)').

% --------------------------------
% CASE: an assumed running package
% --------------------------------

builder:build_element(assumed(rule(_Repository://_Entry:run,_Body))) :-
  !.
  %message:print('verify'),
  %message:print(' (assumed running) ').

% -------------------------------------
% CASE: an assumed installed dependency
% -------------------------------------

builder:build_element(assumed(rule(package_dependency(_,install,_,_C,_N,_,_,_,_),_Body))) :-
  !.
  %message:print('verify'),
  %message:print(' (assumed installed) ').

% -----------------------------------
% CASE: an assumed running dependency
% -----------------------------------

builder:build_element(assumed(rule(package_dependency(_,run,_,_C,_N,_,_,_,_),_Body))) :-
  !.
  %message:print('verify'),
  %message:print(' (assumed running) ').


%! builder:test(+Repository)
%
% For a given Repository, build all entries it contains.
%
% Example: Invoke builder:test(+Repository) to build everything in a repository.
% (E.g. every ebuild in a Gentoo repository, or every release of a given
% application)

builder:test(Repository) :-
  Repository:get_size(S),
  stats:init(0,S),
  config:time_limit_build(T),
  config:proving_target(Action),
  time(forall(Repository:entry(E),
              (catch(call_with_time_limit(T,(stats:increase,
                                             stats:percentage(P),
 	                                     nl,message:topheader(['[',P,'] - Executing plan for ',Repository://E:Action]),
                                             prover:prove(Repository://E:Action,[],Proof,[],Model,[],_Constraints),
			                     planner:plan(Proof,[],[],Plan),!,
                                             builder:execute(Repository://E:Action,Model,Proof,Plan))),
                     time_limit_exceeded,
                     assert(builder:broken(Repository://E)));
	       message:failure(E)))),
  stats:runningtime(Min,Sec),!,
  message:inform(['executed plan for ',S,' ',Repository,' entries in ',Min,'m ',Sec,'s.']).


%! builder:test(+Repository,+Style)
%
% For a given Repository, build all entries it contains.

builder:test(Repository,_) :-
  builder:test(Repository).
