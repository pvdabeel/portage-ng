/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2019, Pieter Van den Abeele

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


%! builder:execute(+Plan)
%
% For a given Plan, prints and executes the plan. The printer is called with
% builder:buildstep as a strategy for realizing the step in the plan.
%
% Example: Invoke builder:execute(+Plan) to build or upgrade your operating
% system, kernel, software application, etc... as described in the given Plan.

builder:execute(Target,Model,Proof,Plan) :-
  printer:print(Target,Model,Proof,Plan,builder:execute_step).


%! builder:execute_step(+Step)
%
% For a given Step from a Plan, executes the actions in the step.

builder:execute_step(Step) :-
  config:number_of_cpus(Cpus),
  findall(call(builder:build,Action),
          member(Action,Step),
          Calls),
  concurrent(Cpus,Calls,[]),!.


%! builder:build(+Repository://Entry:Action)
%
% For a given Entry in a given repository, execute Action.
%
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

builder:build(_) :-
  config:dry_run_build(true), !.

builder:build(rule(Repository://Entry:_Action,_)) :-
  Repository:get_type('eapi'),!,
  Repository:get_location(L),
  Repository:ebuild(Entry,Category,Package,Version),
  atomic_list_concat(['ebuild ',L,'/',Category,'/',Package,'/',Package,'-',Version,'.ebuild install qmerge clean'],Cmd),
  shell(Cmd),!.

builder:build(rule(Repository://_Entry:_Action,_)) :-
  Repository:get_type('cmake'),!,
  Repository:get_location(Local),
  script:exec(build,['cmake', Local]).

builder:build(assumed(rule(_Repository://_Entry:_Action,_))) :-
  % Verify dependency cycle assumptions
  true, !.

builder:build(rule(assumed(_Repository://_Entry:_Action,_))) :-
  % Verify non-existent package assumptions
  true, !.


%! builder:test(+Repository)
%
% For a given Repository, build all entries it contains.
%
% Example: Invoke builder:test(+Repository) to build everything in a repository.
% (E.g. every ebuild in a Gentoo repository, or every release of a given
% application)

builder:test(Repository) :-
  Repository:get_size(S),
  count:newinstance(counter),
  count:init(0,S),
  config:time_limit_build(T),
  config:proving_target(Action),
  time(forall(Repository:entry(E),
              (catch(call_with_time_limit(T,(count:increase,
                                             count:percentage(P),
 	                                     nl,message:topheader(['[',P,'] - Executing plan for ',Repository://E:Action]),
                                             prover:prove(Repository://E:Action,[],Proof,[],Model,[],_Constraints),
			                     planner:plan(Proof,[],[],Plan),!,
                                             builder:execute(Repository://E:Action,Model,Proof,Plan))),
                     time_limit_exceeded,
                     assert(builder:broken(Repository://E)));
	       message:failure(E)))),!,
  message:inform(['executed plan ',S,' ',Repository,' entries.']).


%! builder:test(+Repository,+Style)
%
% For a given Repository, build all entries it contains.

builder:test(Repository,_) :-
  builder:test(Repository).
