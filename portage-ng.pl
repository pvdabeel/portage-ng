/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

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
                       you will need 32G stack space. Only needed in standalone
		                   and server mode. Client mode works fine with default.
  --
  -f /Users/pvdabeel/Desktop/Prolog/portage-ng.pl  -> load the main file
  -p portage=/Users/pvdabeel/Desktop/Prolog        -> set application home
  -g main					                                 -> execute main
  --
*/


% =============================================================================
%  PORTAGE-NG
% =============================================================================

% -----------------------------------------------------------------------------
%  Module loading
% -----------------------------------------------------------------------------

%! load_common_modules
%
% Loads the common modules.

load_common_modules :-

   ensure_loaded(library('apply_macros')),
   ensure_loaded(library('optparse')),
   ensure_loaded(library('lists')),
   ensure_loaded(library('error')),
   ensure_loaded(library('option')),
   ensure_loaded(library('shell')),
   ensure_loaded(library('tty')),
   ensure_loaded(library('time')),
   
   ensure_loaded(library('readutil')),
   ensure_loaded(library('ansi_term')),
   ensure_loaded(library('filesex')),
   ensure_loaded(library('process')),
   ensure_loaded(library('thread')),
   ensure_loaded(library('ordsets')),
   ensure_loaded(library('socket')),
   ensure_loaded(library('assoc')),
   ensure_loaded(library('apply')),
   ensure_loaded(library('sort')),
   ensure_loaded(library('pairs')),
   ensure_loaded(library('uri')),
   ensure_loaded(library('pengines')),
   ensure_loaded(library('solution_sequences')),

   ensure_loaded(portage('Source/context.pl')),
   ensure_loaded(portage('Source/config')),
   ensure_loaded(portage('Source/os.pl')),
   ensure_loaded(portage('Source/profile.pl')),
   ensure_loaded(portage('Source/interface.pl')),
   ensure_loaded(portage('Source/message.pl')),
   ensure_loaded(portage('Source/eapi.pl')),
   ensure_loaded(portage('Source/reader.pl')),
   ensure_loaded(portage('Source/set.pl')),
   ensure_loaded(portage('Source/subprocess.pl')),
   ensure_loaded(portage('Source/bonjour.pl')),
   ensure_loaded(portage('Source/unify.pl')),

   message:log('Loaded common modules...').


%! load_client_modules
%
% Loads the client modules.

load_client_modules :-

   ensure_loaded(library('socket')),
   ensure_loaded(library('broadcast')),
   ensure_loaded(library('http/http_path')),
   ensure_loaded(library('http/http_open')),
   ensure_loaded(library('http/http_ssl_plugin')),
   ensure_loaded(library('http/thread_httpd')),
   ensure_loaded(library('http/http_digest')),

   ensure_loaded(portage('Source/stubs.pl')),
   ensure_loaded(portage('Source/knowledgebase.pl')),
   ensure_loaded(portage('Source/ebuild.pl')),
   ensure_loaded(portage('Source/printer.pl')),
   ensure_loaded(portage('Source/preference')),
   ensure_loaded(portage('Source/script.pl')),
   ensure_loaded(portage('Source/client.pl')),

   message:log('Loaded client modules...').


%! load_standalone_modules
%
% Loads the standalone modules.

load_standalone_modules :-

   ensure_loaded(library('aggregate')),
   ensure_loaded(library('apply_macros')),
   ensure_loaded(library('crypto')),
   ensure_loaded(library('socket')),

   ensure_loaded(portage('Source/stubs.pl')),
   ensure_loaded(portage('Source/context.pl')),
   ensure_loaded(portage('Source/cache.pl')),
   ensure_loaded(portage('Source/repository.pl')),
   ensure_loaded(portage('Source/knowledgebase.pl')),
   ensure_loaded(portage('Source/query.pl')),

   ensure_loaded(portage('Source/eapi.pl')),
   ensure_loaded(portage('Source/version.pl')),
   ensure_loaded(portage('Source/mirror.pl')),
   ensure_loaded(portage('Source/explainer.pl')),
   ensure_loaded(portage('Source/explanation.pl')),
   ensure_loaded(portage('Source/rules.pl')),
   ensure_loaded(portage('Source/ebuild.pl')),
   ensure_loaded(portage('Source/script.pl')),
   ensure_loaded(portage('Source/stat.pl')),
   ensure_loaded(portage('Source/pkg.pl')),
   ensure_loaded(portage('Source/preference')),

   ensure_loaded(portage('Source/sampler.pl')),

   ensure_loaded(portage('Source/reader.pl')),
   ensure_loaded(portage('Source/parser.pl')),
   ensure_loaded(portage('Source/prover.pl')),
   ensure_loaded(portage('Source/planner.pl')),
   ensure_loaded(portage('Source/scheduler.pl')),
   ensure_loaded(portage('Source/printer.pl')),
   ensure_loaded(portage('Source/grapher.pl')),
   ensure_loaded(portage('Source/worker.pl')),
   ensure_loaded(portage('Source/tester.pl')),
   ensure_loaded(portage('Source/cluster.pl')),

   ensure_loaded(portage('Source/test.pl')),

   message:log('Loaded standalone modules...').


%! load_worker_modules
%
% Loads the worker modules: the full proving pipeline (KB, prover, planner,
% scheduler) plus client RPC for communicating with the server.

load_worker_modules :-

   ensure_loaded(library('aggregate')),
   ensure_loaded(library('apply_macros')),
   ensure_loaded(library('crypto')),
   ensure_loaded(library('socket')),
   ensure_loaded(library('broadcast')),
   ensure_loaded(library('http/http_path')),
   ensure_loaded(library('http/http_open')),
   ensure_loaded(library('http/http_ssl_plugin')),
   ensure_loaded(library('http/thread_httpd')),
   ensure_loaded(library('http/http_digest')),

   ensure_loaded(portage('Source/stubs.pl')),
   ensure_loaded(portage('Source/context.pl')),
   ensure_loaded(portage('Source/cache.pl')),
   ensure_loaded(portage('Source/repository.pl')),
   ensure_loaded(portage('Source/knowledgebase.pl')),
   ensure_loaded(portage('Source/query.pl')),

   ensure_loaded(portage('Source/eapi.pl')),
   ensure_loaded(portage('Source/version.pl')),
   ensure_loaded(portage('Source/rules.pl')),
   ensure_loaded(portage('Source/ebuild.pl')),
   ensure_loaded(portage('Source/script.pl')),
   ensure_loaded(portage('Source/stat.pl')),
   ensure_loaded(portage('Source/pkg.pl')),
   ensure_loaded(portage('Source/preference')),

   ensure_loaded(portage('Source/sampler.pl')),

   ensure_loaded(portage('Source/reader.pl')),
   ensure_loaded(portage('Source/parser.pl')),
   ensure_loaded(portage('Source/prover.pl')),
   ensure_loaded(portage('Source/planner.pl')),
   ensure_loaded(portage('Source/scheduler.pl')),
   ensure_loaded(portage('Source/printer.pl')),

   ensure_loaded(portage('Source/client.pl')),
   ensure_loaded(portage('Source/worker.pl')),
   ensure_loaded(portage('Source/cluster.pl')),

   message:log('Loaded worker modules...').


%! load_server_modules
%
% Loads the server modules.

load_server_modules :-

   ensure_loaded(library('http/http_server')),
   ensure_loaded(library('http/http_open')),
   ensure_loaded(library('http/http_ssl_plugin')),
   ensure_loaded(library('http/http_digest')),
   ensure_loaded(library('http/thread_httpd')),
   ensure_loaded(library('streams')),
   ensure_loaded(library('pengines')),

   ensure_loaded(portage('Source/sandbox.pl')),
   ensure_loaded(portage('Source/server.pl')),

   message:log('Loaded server modules...').


%! load_llm_modules
%
% Loads the LLM modules.

load_llm_modules :-

   ensure_loaded(library(quasi_quotations)),
   ensure_loaded(library(http/http_open)),
   ensure_loaded(library(http/http_json)),
   ensure_loaded(library(edit)),
   ensure_loaded(library(pcre)),
   ensure_loaded(library(sandbox)),

   ensure_loaded(portage('Source/llm.pl')),
   ensure_loaded(portage('Source/Llm/grok.pl')),
   ensure_loaded(portage('Source/Llm/chatgpt.pl')),
   ensure_loaded(portage('Source/Llm/claude.pl')),
   ensure_loaded(portage('Source/Llm/gemini.pl')),
   ensure_loaded(portage('Source/Llm/ollama.pl')),

   message:log('Loaded Generative AI modules...').


% -----------------------------------------------------------------------------
%  Main predicate
% -----------------------------------------------------------------------------

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
% available in this repository)
%
% @see Source/context extends Prolog with a declarative OO programming paradigm
% @see Source/repository defines the repository class

main :-
  load_common_modules,
  interface:process_mode(Mode),
  config:working_dir(Dir),
  cd(Dir),
  config:world_file(File),
  world:newinstance(set(File)),
  world:load,
  interface:init_tty,
  main(Mode).


main(client) :-
  load_client_modules,
  load_llm_modules,
  interface:process_server(Host,Port),
  kb:newinstance(knowledgebase(Host,Port)),
  preference:init,
  interface:process_requests(client).


main(standalone) :-
  load_standalone_modules,
  load_llm_modules,
  stats:newinstance(stat),
  kb:newinstance(knowledgebase),
  config:systemconfig(Config),
  ensure_loaded(Config),
  kb:load,
  preference:init,
  interface:process_requests(standalone).


main(worker) :-
  load_worker_modules,
  load_llm_modules,
  stats:newinstance(stat),
  kb:newinstance(knowledgebase),
  config:systemconfig(Config),
  ensure_loaded(Config),
  kb:load,
  preference:init,
  interface:process_server(Host, Port),
  worker:start(Host, Port),
  interface:process_requests(worker).


main(server) :-
  main(standalone),
  load_server_modules,
  server:start_server,
  at_halt(server:stop_server),
  bonjour:advertise,
  interface:process_requests(server).
