/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2024, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> PORTAGE-NG
This application is written in Prolog, a language that lends itself for
declarative programming. We extend this language to support a declarative
object oriented programming paradigm (CONTEXT) and implement a system to reason
about large scale software configuration. E.g. operating systems, programming
languages, kernels, etc.

We show that our application can retrieve, read, parse, reason, prove, plan,
and even build large scale software configrations.

This file is the main source file in the repository. It loads all other files.

Launch using

swipl
  -O                -> turns on Prolog performance optimizations
  --stack_limit=32G -> if you want to prove the all packages in the portage tree
                       you will need 32G stack space
  --
  -f /Users/pvdabeel/Desktop/Prolog/portage-ng.pl  -> load the main file
  -p portage=/Users/pvdabeel/Desktop/Prolog        -> set application home
  -g main					   -> execute main
  --
*/


% **********
% PORTAGE-NG
% **********

load_common_modules :-
   writeln('Loading common modules...'),

   ensure_loaded(library('optparse')),
   ensure_loaded(library('tty')),
   ensure_loaded(library('time')),
   ensure_loaded(library('thread')),

   ensure_loaded(portage('Source/os.pl')),
   ensure_loaded(portage('Source/config')),
   ensure_loaded(portage('Source/interface.pl')),
   ensure_loaded(portage('Source/message.pl')).


load_client_modules :-
   writeln('Loading client modules...'),

   ensure_loaded(library('http/http_open')),
   ensure_loaded(library('http/http_ssl_plugin')),
   ensure_loaded(library('http/thread_httpd')),
   ensure_loaded(library('pengines')),

   %ensure_loaded(portage('Source/pkg.pl')),
   ensure_loaded(portage('Source/client.pl')).


load_standalone_modules :-
   writeln('Loading standalone modules...'),

   ensure_loaded(library('aggregate')),
   ensure_loaded(library('apply_macros')),
   ensure_loaded(library('gensym')),
   ensure_loaded(library('socket')),	% gethostname

   ensure_loaded(portage('Source/context.pl')),
   ensure_loaded(portage('Source/instances.pl')),
   ensure_loaded(portage('Source/cache.pl')),
   ensure_loaded(portage('Source/repository.pl')),
   ensure_loaded(portage('Source/knowledgebase.pl')),
   ensure_loaded(portage('Source/query.pl')),

   ensure_loaded(portage('Source/eapi.pl')),
   ensure_loaded(portage('Source/rules.pl')),
   ensure_loaded(portage('Source/ebuild.pl')),
   ensure_loaded(portage('Source/preference.pl')),
   ensure_loaded(portage('Source/unify.pl')),
   ensure_loaded(portage('Source/script.pl')),
   ensure_loaded(portage('Source/stat.pl')),
   ensure_loaded(portage('Source/pkg.pl')),

   ensure_loaded(portage('Source/reader.pl')),
   ensure_loaded(portage('Source/parser.pl')),
   ensure_loaded(portage('Source/prover.pl')),
   ensure_loaded(portage('Source/planner.pl')),
   ensure_loaded(portage('Source/printer.pl')),
   ensure_loaded(portage('Source/builder.pl')),
   ensure_loaded(portage('Source/grapher.pl')),
   ensure_loaded(portage('Source/worker.pl')),
   ensure_loaded(portage('Source/tester.pl')),

   ensure_loaded(portage('Source/test.pl')).


load_server_modules :-
   writeln('Loading server modules...'),

   ensure_loaded(library('http/http_server')),
   ensure_loaded(library('http/http_open')),
   ensure_loaded(library('http/http_ssl_plugin')),
   ensure_loaded(library('http/thread_httpd')),
   ensure_loaded(library('pengines')),

   ensure_loaded(portage('Source/sandbox.pl')),
   ensure_loaded(portage('Source/server.pl')).


%! main(+Mode).
%
% The main predicate.
%
% Mode is one of standalone, client or server
%
% We declare (as an example) the following repositories:
%
% - Gentoo Portage github repository
% - SWI-prolog source code github repository
% - Linus Torvalds, Linux source code Github repository
%
% These repositories are instantiated as Prolog classes.
%
% The instances have several public/protected/private methods available. For
% example: you can sync the remote repository to a local repository, retrieve
% metadata (like releases available) from the repository, query the metadata
% available oin this repository)
%
% @see Source/context extends Prolog with a declarative OO programming paradigm
% @see Source/repository defines the repository class

main :-
  time(
    (load_common_modules,
     interface:process_mode(Mode),
     message:title_reset,
     config:working_dir(Dir),
     cd(Dir),
     main(Mode))).


main(client) :-
  load_client_modules.


main(standalone) :-
  load_standalone_modules,
  kb:newinstance(knowledgebase),
  config:systemconfig(Config),
  ensure_loaded(Config),
  kb:load,
  interface:process_requests(standalone).


main(server) :-
  main(standalone),
  load_server_modules,
  server:start_server,
  interface:process_requests(server).


%emerge(R://E,Plan) :-
%  prover:prove(R://E:run,[],Proof,[],Model,[],_Constraints),planner:plan(Proof,[],[],Plan),printer:print(R://E:run,Model,Proof,Plan).
