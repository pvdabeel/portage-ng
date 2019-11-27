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

% ********************
% BUILDER declarations
% ********************


%! builder:execute(+Plan)
%
% Given a Plan from the Planner, execute the plan.
%
% Example: Invoke builder:execute(+Plan) to build or upgrade your operating
% system, kernel, software application, etc... as described in the given Plan.

builder:execute(Plan) :-
  forall(member(E,Plan),
    builder:firststep(E)).


%! builder:build(+Context://Entry:Action)
%
% For a given Entry in a given context, execute Action.
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

builder:build(Context://Entry:_Action) :-
  Context:get_type('eapi'),!,
  Context:get_location(L),
  Context:ebuild(Entry,Category,Package,Version),
  atomic_list_concat(['ebuild ',L,'/',Category,'/',Package,'/',Package,'-',Version,'.ebuild install qmerge clean'],Cmd),
  shell(Cmd),!.

builder:build(Context://_Entry:_Action) :-
  Context:get_type('cmake'),!,
  Context:get_location(Local),
  script:exec(build,['cmake', Local]).


%! builder:firststep(+Steps)
%
% Builds a part of a build plan

builder:firststep([]) :-  !.

builder:firststep([rule(Context://E:Action,_)|L]) :-
  !,
  write(' -  STEP:  | '),
  message:color(green),
  write(Context://E),
  message:color(blue),
  write(' '),
  write(Action),
  message:color(normal),
  builder:build(Context://E:Action),
  nl,
  builder:nextstep(L).

builder:firststep([rule(_,_)|L]) :-
  builder:firststep(L).


%! builder:nextstep(+Steps)
%
% Builds a part of a build plan

builder:nextstep([]) :- nl,!.

builder:nextstep([rule(Context://E:Action,_)|L]) :-
  !,
  write('           | '),
  message:color(green),
  write(Context://E),
  message:color(blue),
  write(' '),
  write(Action),
  message:color(normal),
  builder:build(Context://E:Action),
  nl,
  builder:nextstep(L).

builder:nextstep([rule(_,_)|L]) :-
  builder:nextstep(L).


%! builder:test(+Repository)
%
% For a given Repository, build all entries it contains.
%
% Example: Invoke builder:test(+Repository) to build everything in a repository.
% (E.g. every ebuild in a Gentoo repository, or every release of a given
% application)

builder:test(Repository) :-
  preference:proving_target(Action),
  system:time(system:forall(Repository:entry(E),
 	                    ((nl,message:header(["Building ",Repository://E:Action]),
                              prover:prove(Repository://E:Action,[],Proof,[],_),
			      planner:plan(Proof,[],[],Plan),
                              builder:execute(Plan));
			     (message:failure(E)))
                           )),
  Repository:get_size(S),
  message:inform(['built ',S,' ',Repository,' entries.']).
