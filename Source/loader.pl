/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> LOADER
Per-mode module loading. Each predicate loads the libraries and application
modules required by a specific operating mode (standalone, client, server,
worker) or shared subsystem (common, LLM).
*/

% =============================================================================
%  LOADER declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Common modules
% -----------------------------------------------------------------------------

%! load_common_modules is det.
%
% Loads libraries and application modules shared by all modes.

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
   ensure_loaded(portage('Source/sanitize.pl')),
   ensure_loaded(portage('Source/profile.pl')),
   ensure_loaded(portage('Source/message.pl')),
   ensure_loaded(portage('Source/interface.pl')),
   ensure_loaded(portage('Source/eapi.pl')),
   ensure_loaded(portage('Source/reader.pl')),
   ensure_loaded(portage('Source/set.pl')),
   ensure_loaded(portage('Source/subprocess.pl')),
   ensure_loaded(portage('Source/bonjour.pl')),
   ensure_loaded(portage('Source/unify.pl')),
   ensure_loaded(portage('Source/daemon.pl')),

   message:log('Loaded common modules...').


% -----------------------------------------------------------------------------
%  Client modules
% -----------------------------------------------------------------------------

%! load_client_modules is det.
%
% Loads the client modules for remote server communication.

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
   ensure_loaded(portage('Source/Printer/Plan/assumption.pl')),
   ensure_loaded(portage('Source/Printer/Plan/cycle.pl')),
   ensure_loaded(portage('Source/Printer/Plan/warning.pl')),
   ensure_loaded(portage('Source/Printer/Plan/plan.pl')),
   ensure_loaded(portage('Source/Printer/Plan/timing.pl')),
   ensure_loaded(portage('Source/Printer/index.pl')),
   ensure_loaded(portage('Source/Printer/info.pl')),
   ensure_loaded(portage('Source/Printer/News/news.pl')),
   ensure_loaded(portage('Source/Printer/stats.pl')),
   ensure_loaded(portage('Source/Printer/state.pl')),
   ensure_loaded(portage('Source/printer.pl')),
   ensure_loaded(portage('Source/pipeline.pl')),
   ensure_loaded(portage('Source/variant.pl')),
   ensure_loaded(portage('Source/Builder/snapshot.pl')),
   ensure_loaded(portage('Source/writer.pl')),
   ensure_loaded(portage('Source/Config/gentoo.pl')),
   ensure_loaded(portage('Source/preference')),
   ensure_loaded(portage('Source/script.pl')),
   ensure_loaded(portage('Source/client.pl')),

   message:log('Loaded client modules...').


% -----------------------------------------------------------------------------
%  Standalone modules
% -----------------------------------------------------------------------------

%! load_standalone_modules is det.
%
% Loads the full standalone pipeline: KB, prover, planner, scheduler,
% printer, builder, grapher, depclean, and test framework.

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
   ensure_loaded(portage('Source/issue.pl')),
   ensure_loaded(portage('Source/rules.pl')),
   ensure_loaded(portage('Source/Rules/memo.pl')),
   ensure_loaded(portage('Source/Rules/use.pl')),
   ensure_loaded(portage('Source/Rules/candidate.pl')),
   ensure_loaded(portage('Source/Rules/heuristic.pl')),
   ensure_loaded(portage('Source/Rules/dependency.pl')),
   ensure_loaded(portage('Source/Rules/target.pl')),
   ensure_loaded(portage('Source/ebuild.pl')),
   ensure_loaded(portage('Source/script.pl')),
   ensure_loaded(portage('Source/stat.pl')),
   ensure_loaded(portage('Source/vdb.pl')),
   ensure_loaded(portage('Source/buildtime.pl')),
   ensure_loaded(portage('Source/distfiles.pl')),
   ensure_loaded(portage('Source/Config/gentoo.pl')),
   ensure_loaded(portage('Source/preference')),

   ensure_loaded(portage('Source/sampler.pl')),

   ensure_loaded(portage('Source/reader.pl')),
   ensure_loaded(portage('Source/parser.pl')),
   ensure_loaded(portage('Source/prover.pl')),
   ensure_loaded(portage('Source/constraint.pl')),
   ensure_loaded(portage('Source/planner.pl')),
   ensure_loaded(portage('Source/scheduler.pl')),
   ensure_loaded(portage('Source/Printer/Plan/assumption.pl')),
   ensure_loaded(portage('Source/Printer/Plan/cycle.pl')),
   ensure_loaded(portage('Source/Printer/Plan/warning.pl')),
   ensure_loaded(portage('Source/Printer/Plan/plan.pl')),
   ensure_loaded(portage('Source/Printer/Plan/timing.pl')),
   ensure_loaded(portage('Source/Printer/index.pl')),
   ensure_loaded(portage('Source/Printer/info.pl')),
   ensure_loaded(portage('Source/Printer/News/news.pl')),
   ensure_loaded(portage('Source/Printer/stats.pl')),
   ensure_loaded(portage('Source/Printer/state.pl')),
   ensure_loaded(portage('Source/Printer/Build/build.pl')),
   ensure_loaded(portage('Source/printer.pl')),
   ensure_loaded(portage('Source/pipeline.pl')),
   ensure_loaded(portage('Source/variant.pl')),
   ensure_loaded(portage('Source/Builder/snapshot.pl')),
   ensure_loaded(portage('Source/Builder/jobserver.pl')),
   ensure_loaded(portage('Source/Builder/download.pl')),
   ensure_loaded(portage('Source/Builder/ebuild_exec.pl')),
   ensure_loaded(portage('Source/builder.pl')),
   ensure_loaded(portage('Source/writer.pl')),
   ensure_loaded(portage('Source/Grapher/navtheme.pl')),
   ensure_loaded(portage('Source/Grapher/gantt.pl')),
   ensure_loaded(portage('Source/Grapher/deptree.pl')),
   ensure_loaded(portage('Source/Grapher/detail.pl')),
   ensure_loaded(portage('Source/Grapher/terminal.pl')),
   ensure_loaded(portage('Source/Grapher/dot.pl')),
   ensure_loaded(portage('Source/grapher.pl')),
   ensure_loaded(portage('Source/worker.pl')),
   ensure_loaded(portage('Source/tester.pl')),
   ensure_loaded(portage('Source/cluster.pl')),

   ensure_loaded(portage('Source/kahn.pl')),
   ensure_loaded(portage('Source/depclean.pl')),
   ensure_loaded(portage('Source/linkage.pl')),
   ensure_loaded(portage('Source/report.pl')),

   ensure_loaded(library('http/http_open')),
   ensure_loaded(library('http/http_json')),
   ensure_loaded(portage('Source/upstream.pl')),
   ensure_loaded(portage('Source/bugs.pl')),

   ensure_loaded(portage('Source/test.pl')),

   message:log('Loaded standalone modules...').


% -----------------------------------------------------------------------------
%  Worker modules
% -----------------------------------------------------------------------------

%! load_worker_modules is det.
%
% Loads the full proving pipeline plus client RPC for communicating
% with the server.

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
   ensure_loaded(portage('Source/Rules/memo.pl')),
   ensure_loaded(portage('Source/Rules/use.pl')),
   ensure_loaded(portage('Source/Rules/candidate.pl')),
   ensure_loaded(portage('Source/Rules/heuristic.pl')),
   ensure_loaded(portage('Source/Rules/dependency.pl')),
   ensure_loaded(portage('Source/Rules/target.pl')),
   ensure_loaded(portage('Source/ebuild.pl')),
   ensure_loaded(portage('Source/script.pl')),
   ensure_loaded(portage('Source/stat.pl')),
   ensure_loaded(portage('Source/vdb.pl')),
   ensure_loaded(portage('Source/distfiles.pl')),
   ensure_loaded(portage('Source/Config/gentoo.pl')),
   ensure_loaded(portage('Source/preference')),

   ensure_loaded(portage('Source/sampler.pl')),

   ensure_loaded(portage('Source/reader.pl')),
   ensure_loaded(portage('Source/parser.pl')),
   ensure_loaded(portage('Source/prover.pl')),
   ensure_loaded(portage('Source/constraint.pl')),
   ensure_loaded(portage('Source/planner.pl')),
   ensure_loaded(portage('Source/scheduler.pl')),
   ensure_loaded(portage('Source/Printer/Plan/assumption.pl')),
   ensure_loaded(portage('Source/Printer/Plan/cycle.pl')),
   ensure_loaded(portage('Source/Printer/Plan/warning.pl')),
   ensure_loaded(portage('Source/Printer/Plan/plan.pl')),
   ensure_loaded(portage('Source/Printer/Plan/timing.pl')),
   ensure_loaded(portage('Source/Printer/index.pl')),
   ensure_loaded(portage('Source/Printer/info.pl')),
   ensure_loaded(portage('Source/Printer/News/news.pl')),
   ensure_loaded(portage('Source/Printer/stats.pl')),
   ensure_loaded(portage('Source/Printer/state.pl')),
   ensure_loaded(portage('Source/printer.pl')),
   ensure_loaded(portage('Source/pipeline.pl')),
   ensure_loaded(portage('Source/writer.pl')),

   ensure_loaded(portage('Source/client.pl')),
   ensure_loaded(portage('Source/worker.pl')),
   ensure_loaded(portage('Source/cluster.pl')),

   message:log('Loaded worker modules...').


% -----------------------------------------------------------------------------
%  Server modules
% -----------------------------------------------------------------------------

%! load_server_modules is det.
%
% Loads the HTTP server, Pengines, and sandbox modules.

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


% -----------------------------------------------------------------------------
%  LLM modules
% -----------------------------------------------------------------------------

%! load_llm_modules is det.
%
% Loads the Generative AI / LLM integration modules.

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
   ensure_loaded(portage('Source/Llm/explain.pl')),
   ensure_loaded(portage('Source/semantic.pl')),

   message:log('Loaded Generative AI modules...').
