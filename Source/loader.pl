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

   ensure_loaded(portage('Source/Logic/context.pl')),
   ensure_loaded(portage('Source/config')),
   ensure_loaded(portage('Source/Application/System/os.pl')),
   ensure_loaded(portage('Source/Application/Security/sanitize.pl')),
   ensure_loaded(portage('Source/Domain/Gentoo/profile.pl')),
   ensure_loaded(portage('Source/Application/Output/message.pl')),
   ensure_loaded(portage('Source/Application/interface.pl')),
   ensure_loaded(portage('Source/Application/Interface/action.pl')),
   ensure_loaded(portage('Source/Domain/Gentoo/eapi.pl')),
   ensure_loaded(portage('Source/Pipeline/reader.pl')),
   ensure_loaded(portage('Source/Domain/Gentoo/set.pl')),
   ensure_loaded(portage('Source/Application/System/subprocess.pl')),
   ensure_loaded(portage('Source/Application/System/bonjour.pl')),
   ensure_loaded(portage('Source/Logic/unify.pl')),
   ensure_loaded(portage('Source/Application/Mode/daemon.pl')),

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

   ensure_loaded(portage('Source/Application/Mode/stubs.pl')),
   ensure_loaded(portage('Source/Knowledge/knowledgebase.pl')),
   ensure_loaded(portage('Source/Domain/Gentoo/ebuild.pl')),
   ensure_loaded(portage('Source/Pipeline/Printer/Plan/assumption.pl')),
   ensure_loaded(portage('Source/Pipeline/Printer/Plan/cycle.pl')),
   ensure_loaded(portage('Source/Pipeline/Printer/Plan/warning.pl')),
   ensure_loaded(portage('Source/Pipeline/Printer/Plan/plan.pl')),
   ensure_loaded(portage('Source/Pipeline/Printer/Plan/timing.pl')),
   ensure_loaded(portage('Source/Pipeline/Printer/index.pl')),
   ensure_loaded(portage('Source/Pipeline/Printer/info.pl')),
   ensure_loaded(portage('Source/Pipeline/Printer/News/news.pl')),
   ensure_loaded(portage('Source/Pipeline/Printer/stats.pl')),
   ensure_loaded(portage('Source/Pipeline/Printer/state.pl')),
   ensure_loaded(portage('Source/Pipeline/printer.pl')),
   ensure_loaded(portage('Source/Pipeline/pipeline.pl')),
   ensure_loaded(portage('Source/Domain/Gentoo/variant.pl')),
   ensure_loaded(portage('Source/Pipeline/Builder/snapshot.pl')),
   ensure_loaded(portage('Source/Application/Output/writer.pl')),
   ensure_loaded(portage('Source/Config/gentoo.pl')),
   ensure_loaded(portage('Source/Domain/Gentoo/preference')),
   ensure_loaded(portage('Source/Application/System/script.pl')),
   ensure_loaded(portage('Source/Application/Mode/client.pl')),

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

   ensure_loaded(portage('Source/Application/Mode/stubs.pl')),
   ensure_loaded(portage('Source/Logic/context.pl')),
   ensure_loaded(portage('Source/Knowledge/cache.pl')),
   ensure_loaded(portage('Source/Knowledge/repository.pl')),
   ensure_loaded(portage('Source/Knowledge/knowledgebase.pl')),
   ensure_loaded(portage('Source/Knowledge/query.pl')),

   ensure_loaded(portage('Source/Domain/Gentoo/eapi.pl')),
   ensure_loaded(portage('Source/Domain/Gentoo/version.pl')),
   ensure_loaded(portage('Source/Domain/Gentoo/mirror.pl')),
   ensure_loaded(portage('Source/Pipeline/Prover/explainer.pl')),
   ensure_loaded(portage('Source/Pipeline/Prover/explanation.pl')),
   ensure_loaded(portage('Source/Domain/Gentoo/issue.pl')),
   ensure_loaded(portage('Source/Domain/Gentoo/rules.pl')),
   ensure_loaded(portage('Source/Domain/Gentoo/Rules/memo.pl')),
   ensure_loaded(portage('Source/Domain/Gentoo/Rules/use.pl')),
   ensure_loaded(portage('Source/Domain/Gentoo/Rules/candidate.pl')),
   ensure_loaded(portage('Source/Domain/Gentoo/Rules/heuristic.pl')),
   ensure_loaded(portage('Source/Domain/Gentoo/Rules/dependency.pl')),
   ensure_loaded(portage('Source/Domain/Gentoo/Rules/target.pl')),
   ensure_loaded(portage('Source/Domain/Gentoo/ebuild.pl')),
   ensure_loaded(portage('Source/Application/System/script.pl')),
   ensure_loaded(portage('Source/Knowledge/stat.pl')),
   ensure_loaded(portage('Source/Domain/Gentoo/vdb.pl')),
   ensure_loaded(portage('Source/Pipeline/Builder/buildtime.pl')),
   ensure_loaded(portage('Source/Domain/Gentoo/distfiles.pl')),
   ensure_loaded(portage('Source/Config/gentoo.pl')),
   ensure_loaded(portage('Source/Domain/Gentoo/preference')),

   ensure_loaded(portage('Source/Application/Performance/sampler.pl')),

   ensure_loaded(portage('Source/Pipeline/reader.pl')),
   ensure_loaded(portage('Source/Pipeline/parser.pl')),
   ensure_loaded(portage('Source/Pipeline/prover.pl')),
   ensure_loaded(portage('Source/Logic/constraint.pl')),
   ensure_loaded(portage('Source/Pipeline/planner.pl')),
   ensure_loaded(portage('Source/Pipeline/scheduler.pl')),
   ensure_loaded(portage('Source/Pipeline/Printer/Plan/assumption.pl')),
   ensure_loaded(portage('Source/Pipeline/Printer/Plan/cycle.pl')),
   ensure_loaded(portage('Source/Pipeline/Printer/Plan/warning.pl')),
   ensure_loaded(portage('Source/Pipeline/Printer/Plan/plan.pl')),
   ensure_loaded(portage('Source/Pipeline/Printer/Plan/timing.pl')),
   ensure_loaded(portage('Source/Pipeline/Printer/index.pl')),
   ensure_loaded(portage('Source/Pipeline/Printer/info.pl')),
   ensure_loaded(portage('Source/Pipeline/Printer/News/news.pl')),
   ensure_loaded(portage('Source/Pipeline/Printer/stats.pl')),
   ensure_loaded(portage('Source/Pipeline/Printer/state.pl')),
   ensure_loaded(portage('Source/Pipeline/Printer/Build/build.pl')),
   ensure_loaded(portage('Source/Pipeline/printer.pl')),
   ensure_loaded(portage('Source/Pipeline/pipeline.pl')),
   ensure_loaded(portage('Source/Domain/Gentoo/variant.pl')),
   ensure_loaded(portage('Source/Pipeline/Builder/snapshot.pl')),
   ensure_loaded(portage('Source/Pipeline/Builder/jobserver.pl')),
   ensure_loaded(portage('Source/Pipeline/Builder/download.pl')),
   ensure_loaded(portage('Source/Domain/Gentoo/Ebuild/ebuild_exec.pl')),
   ensure_loaded(portage('Source/Pipeline/builder.pl')),
   ensure_loaded(portage('Source/Application/Output/writer.pl')),
   ensure_loaded(portage('Source/Application/Output/Grapher/navtheme.pl')),
   ensure_loaded(portage('Source/Application/Output/Grapher/gantt.pl')),
   ensure_loaded(portage('Source/Application/Output/Grapher/deptree.pl')),
   ensure_loaded(portage('Source/Application/Output/Grapher/detail.pl')),
   ensure_loaded(portage('Source/Application/Output/Grapher/terminal.pl')),
   ensure_loaded(portage('Source/Application/Output/Grapher/dot.pl')),
   ensure_loaded(portage('Source/Application/Output/grapher.pl')),
   ensure_loaded(portage('Source/Application/Mode/worker.pl')),
   ensure_loaded(portage('Source/Test/tester.pl')),
   ensure_loaded(portage('Source/Application/Mode/cluster.pl')),

   ensure_loaded(portage('Source/Pipeline/Planner/kahn.pl')),
   ensure_loaded(portage('Source/Domain/Gentoo/depclean.pl')),
   ensure_loaded(portage('Source/Application/System/linkage.pl')),
   ensure_loaded(portage('Source/Application/Output/Report/report.pl')),

   ensure_loaded(library('http/http_open')),
   ensure_loaded(library('http/http_json')),
   ensure_loaded(portage('Source/Domain/Gentoo/upstream.pl')),
   ensure_loaded(portage('Source/Domain/Gentoo/bugs.pl')),

   ensure_loaded(portage('Source/Test/test.pl')),

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

   ensure_loaded(portage('Source/Application/Mode/stubs.pl')),
   ensure_loaded(portage('Source/Logic/context.pl')),
   ensure_loaded(portage('Source/Knowledge/cache.pl')),
   ensure_loaded(portage('Source/Knowledge/repository.pl')),
   ensure_loaded(portage('Source/Knowledge/knowledgebase.pl')),
   ensure_loaded(portage('Source/Knowledge/query.pl')),

   ensure_loaded(portage('Source/Domain/Gentoo/eapi.pl')),
   ensure_loaded(portage('Source/Domain/Gentoo/version.pl')),
   ensure_loaded(portage('Source/Domain/Gentoo/rules.pl')),
   ensure_loaded(portage('Source/Domain/Gentoo/Rules/memo.pl')),
   ensure_loaded(portage('Source/Domain/Gentoo/Rules/use.pl')),
   ensure_loaded(portage('Source/Domain/Gentoo/Rules/candidate.pl')),
   ensure_loaded(portage('Source/Domain/Gentoo/Rules/heuristic.pl')),
   ensure_loaded(portage('Source/Domain/Gentoo/Rules/dependency.pl')),
   ensure_loaded(portage('Source/Domain/Gentoo/Rules/target.pl')),
   ensure_loaded(portage('Source/Domain/Gentoo/ebuild.pl')),
   ensure_loaded(portage('Source/Application/System/script.pl')),
   ensure_loaded(portage('Source/Knowledge/stat.pl')),
   ensure_loaded(portage('Source/Domain/Gentoo/vdb.pl')),
   ensure_loaded(portage('Source/Domain/Gentoo/distfiles.pl')),
   ensure_loaded(portage('Source/Config/gentoo.pl')),
   ensure_loaded(portage('Source/Domain/Gentoo/preference')),

   ensure_loaded(portage('Source/Application/Performance/sampler.pl')),

   ensure_loaded(portage('Source/Pipeline/reader.pl')),
   ensure_loaded(portage('Source/Pipeline/parser.pl')),
   ensure_loaded(portage('Source/Pipeline/prover.pl')),
   ensure_loaded(portage('Source/Logic/constraint.pl')),
   ensure_loaded(portage('Source/Pipeline/planner.pl')),
   ensure_loaded(portage('Source/Pipeline/scheduler.pl')),
   ensure_loaded(portage('Source/Pipeline/Printer/Plan/assumption.pl')),
   ensure_loaded(portage('Source/Pipeline/Printer/Plan/cycle.pl')),
   ensure_loaded(portage('Source/Pipeline/Printer/Plan/warning.pl')),
   ensure_loaded(portage('Source/Pipeline/Printer/Plan/plan.pl')),
   ensure_loaded(portage('Source/Pipeline/Printer/Plan/timing.pl')),
   ensure_loaded(portage('Source/Pipeline/Printer/index.pl')),
   ensure_loaded(portage('Source/Pipeline/Printer/info.pl')),
   ensure_loaded(portage('Source/Pipeline/Printer/News/news.pl')),
   ensure_loaded(portage('Source/Pipeline/Printer/stats.pl')),
   ensure_loaded(portage('Source/Pipeline/Printer/state.pl')),
   ensure_loaded(portage('Source/Pipeline/printer.pl')),
   ensure_loaded(portage('Source/Pipeline/pipeline.pl')),
   ensure_loaded(portage('Source/Application/Output/writer.pl')),

   ensure_loaded(portage('Source/Application/Mode/client.pl')),
   ensure_loaded(portage('Source/Application/Mode/worker.pl')),
   ensure_loaded(portage('Source/Application/Mode/cluster.pl')),

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

   ensure_loaded(portage('Source/Application/Security/sandbox.pl')),
   ensure_loaded(portage('Source/Application/Mode/server.pl')),

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

   ensure_loaded(portage('Source/Application/llm.pl')),
   ensure_loaded(portage('Source/Application/Llm/grok.pl')),
   ensure_loaded(portage('Source/Application/Llm/chatgpt.pl')),
   ensure_loaded(portage('Source/Application/Llm/claude.pl')),
   ensure_loaded(portage('Source/Application/Llm/gemini.pl')),
   ensure_loaded(portage('Source/Application/Llm/ollama.pl')),
   ensure_loaded(portage('Source/Application/Llm/explain.pl')),
   ensure_loaded(portage('Source/Application/Llm/semantic.pl')),

   message:log('Loaded Generative AI modules...').
