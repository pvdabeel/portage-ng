/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> LOADER
Per-mode module loading.

Module groups are declared as loader:group/2 facts. Operating modes
are declared as loader:mode/2 facts (an ordered group list), with
loader:optional/3 naming the groups a mode loads only when a
condition holds.
load_modules/1 is the single entry point. A module needed by several
modes lives in exactly one shared group, so additions propagate
automatically and the delta between modes (e.g. standalone vs worker)
stays explicit and reviewable.
*/

% =============================================================================
%  LOADER declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Module groups
% -----------------------------------------------------------------------------

%! loader:group(?Group, ?Specs) is nondet.
%
% Declares a named, ordered group of file specs (library/1 or portage/1
% terms). Order within a group is load order; compile-time dependencies
% (operators, goal expansion, OO context declarations) must precede their
% dependents.

loader:group(common_libraries,
   [library('apply_macros'),
    library('optparse'),
    library('lists'),
    library('error'),
    library('option'),
    library('shell'),
    library('tty'),
    library('time'),
    library('readutil'),
    library('ansi_term'),
    library('filesex'),
    library('process'),
    library('thread'),
    library('ordsets'),
    library('socket'),
    library('assoc'),
    library('apply'),
    library('sort'),
    library('pairs'),
    library('uri'),
    library('solution_sequences')]).

loader:group(common_modules,
   [portage('Source/Logic/context.pl'),
    portage('Source/Logic/unify.pl'),
    portage('Source/config'),
    portage('Source/Application/System/os.pl'),
    portage('Source/Application/System/lock.pl'),
    portage('Source/Application/Security/sanitize.pl'),
    portage('Source/Application/Output/message.pl'),
    portage('Source/Application/interface.pl'),
    portage('Source/Application/Interface/action.pl'),
    portage('Source/Application/System/subprocess.pl'),
    portage('Source/Application/System/bonjour.pl'),
    portage('Source/Domain/Gentoo/Preference/profile.pl'),
    portage('Source/Domain/Gentoo/eapi.pl'),
    portage('Source/Pipeline/reader.pl'),
    portage('Source/Domain/Gentoo/set.pl')]).

loader:group(ipc_modules,
   [portage('Source/Application/Client/ipclient.pl'),
    portage('Source/Application/Mode/ipc.pl')]).

loader:group(daemon_modules,
   [portage('Source/Application/Mode/daemon.pl')]).

loader:group(client_libraries,
   [library('socket'),
    library('broadcast'),
    library('pengines'),
    library('http/http_path'),
    library('http/http_open'),
    library('http/http_ssl_plugin'),
    library('http/thread_httpd'),
    library('http/http_digest')]).

loader:group(client_core_modules,
   [portage('Source/Application/Mode/stubs.pl'),
    portage('Source/Knowledge/knowledgebase.pl'),
    portage('Source/Domain/Gentoo/ebuild.pl')]).

loader:group(client_modules,
   [portage('Source/Domain/Gentoo/variant.pl'),
    portage('Source/Pipeline/Builder/snapshot.pl'),
    portage('Source/Application/Output/writer.pl'),
    portage('Source/Domain/Gentoo/Preference/userconfig.pl'),
    portage('Source/Domain/Gentoo/Preference/fallback.pl'),
    portage('Source/Domain/Gentoo/preference'),
    portage('Source/Application/System/script.pl'),
    portage('Source/Application/Mode/client.pl')]).

loader:group(pipeline_libraries,
   [library('aggregate'),
    library('apply_macros'),
    library('crypto'),
    library('socket'),
    library('pengines')]).

loader:group(rpc_libraries,
   [library('broadcast'),
    library('http/http_path'),
    library('http/http_open'),
    library('http/http_ssl_plugin'),
    library('http/thread_httpd'),
    library('http/http_digest')]).

loader:group(knowledge_modules,
   [portage('Source/Application/Mode/stubs.pl'),
    portage('Source/Logic/context.pl'),
    portage('Source/Logic/components.pl'),
    portage('Source/Knowledge/cache.pl'),
    portage('Source/Knowledge/feedback.pl'),
    portage('Source/Knowledge/repository.pl'),
    portage('Source/Knowledge/knowledgebase.pl'),
    portage('Source/Knowledge/query.pl')]).

loader:group(domain_modules,
   [portage('Source/Application/Performance/choicelog.pl'),
    portage('Source/Domain/Gentoo/eapi.pl'),
    portage('Source/Domain/Gentoo/version.pl'),
    portage('Source/Pipeline/Prover/explainer.pl'),
    portage('Source/Pipeline/Prover/explanation.pl'),
    portage('Source/Domain/Gentoo/issue.pl'),
    portage('Source/Domain/Gentoo/Rules/resolving.pl'),
    portage('Source/Domain/Gentoo/Rules/ordering.pl'),
    portage('Source/Domain/Gentoo/Rules/unmerging.pl'),
    portage('Source/Domain/Gentoo/Rules/Resolving/memo.pl'),
    portage('Source/Domain/Gentoo/Rules/Resolving/use.pl'),
    portage('Source/Domain/Gentoo/Rules/Resolving/slotmeta.pl'),
    portage('Source/Domain/Gentoo/Rules/Resolving/cnselect.pl'),
    portage('Source/Domain/Gentoo/Rules/Resolving/acceptance.pl'),
    portage('Source/Domain/Gentoo/Rules/Resolving/ranking.pl'),
    portage('Source/Domain/Gentoo/Rules/Resolving/candidate.pl'),
    portage('Source/Domain/Gentoo/Rules/Resolving/abirebuild.pl'),
    portage('Source/Domain/Gentoo/Rules/Resolving/heuristic.pl'),
    portage('Source/Domain/Gentoo/Rules/Resolving/dependency.pl'),
    portage('Source/Domain/Gentoo/Rules/Resolving/target.pl'),
    portage('Source/Domain/Gentoo/Rules/Resolving/featureterm.pl'),
    portage('Source/Domain/Gentoo/ebuild.pl'),
    portage('Source/Application/System/script.pl'),
    portage('Source/Test/stat.pl'),
    portage('Source/Domain/Gentoo/vdb.pl'),
    portage('Source/Domain/Gentoo/distfiles.pl'),
    portage('Source/Domain/Gentoo/Preference/userconfig.pl'),
    portage('Source/Domain/Gentoo/Preference/fallback.pl'),
    portage('Source/Domain/Gentoo/preference'),
    portage('Source/Domain/Gentoo/glsa.pl'),
    portage('Source/Domain/Gentoo/pkgmoves.pl'),
    portage('Source/Domain/Gentoo/Preference/sets.pl')]).

loader:group(pipeline_modules,
   [portage('Source/Application/Performance/sampler.pl'),
    portage('Source/Pipeline/reader.pl'),
    portage('Source/Pipeline/parser.pl'),
    portage('Source/Pipeline/prover.pl'),
    portage('Source/Logic/constraint.pl'),
    portage('Source/Pipeline/resolver.pl'),
    portage('Source/Pipeline/orderer.pl')]).

loader:group(printer_modules,
   [portage('Source/Pipeline/Printer/Plan/assumption.pl'),
    portage('Source/Pipeline/Printer/Plan/annotation.pl'),
    portage('Source/Pipeline/Printer/Plan/cycle.pl'),
    portage('Source/Pipeline/Printer/Plan/warning.pl'),
    portage('Source/Pipeline/Printer/Plan/useflags.pl'),
    portage('Source/Pipeline/Printer/Plan/removal.pl'),
    portage('Source/Pipeline/Printer/Plan/plan.pl'),
    portage('Source/Pipeline/Printer/Plan/timing.pl'),
    portage('Source/Pipeline/Printer/index.pl'),
    portage('Source/Pipeline/Printer/info.pl'),
    portage('Source/Pipeline/Printer/News/news.pl'),
    portage('Source/Pipeline/Printer/stats.pl'),
    portage('Source/Pipeline/Printer/state.pl'),
    portage('Source/Pipeline/printer.pl'),
    portage('Source/Pipeline/pipeline.pl')]).

loader:group(standalone_libraries,
   [library('http/http_open'),
    library('http/http_json')]).

loader:group(standalone_modules,
   [portage('Source/Domain/Gentoo/mirror.pl'),
    portage('Source/Pipeline/Builder/buildtime.pl'),
    portage('Source/Domain/Gentoo/Exceptions/fixup.pl'),
    portage('Source/Domain/Gentoo/Exceptions/collision.pl'),
    portage('Source/Domain/Gentoo/Exceptions/ghcabi.pl'),
    portage('Source/Domain/Gentoo/Exceptions/ocamlabi.pl'),
    portage('Source/Domain/Gentoo/Exceptions/missing_provider.pl'),
    portage('Source/Domain/Gentoo/Exceptions/kernelconfig.pl'),
    portage('Source/Domain/Gentoo/Exceptions/useenable.pl'),
    portage('Source/Domain/Gentoo/Exceptions/gitlock.pl'),
    portage('Source/Domain/Gentoo/Binpkg/binpkg_index.pl'),
    portage('Source/Domain/Gentoo/Binpkg/binpkg_extract.pl'),
    portage('Source/Domain/Gentoo/Binpkg/binpkg_exec.pl'),
    portage('Source/Pipeline/Printer/Build/build.pl'),
    portage('Source/Domain/Gentoo/variant.pl'),
    portage('Source/Pipeline/Builder/snapshot.pl'),
    portage('Source/Pipeline/Builder/jobserver.pl'),
    portage('Source/Pipeline/Builder/download.pl'),
    portage('Source/Pipeline/Builder/display.pl'),
    portage('Source/Pipeline/Builder/fetch.pl'),
    portage('Source/Pipeline/Builder/resume.pl'),
    portage('Source/Domain/Gentoo/Ebuild/ebuild_exec.pl'),
    portage('Source/Pipeline/builder.pl'),
    portage('Source/Application/Output/writer.pl'),
    portage('Source/Application/Output/Grapher/navtheme.pl'),
    portage('Source/Application/Output/Grapher/gantt.pl'),
    portage('Source/Application/Output/Grapher/deptree.pl'),
    portage('Source/Application/Output/Grapher/detail.pl'),
    portage('Source/Application/Output/Grapher/terminal.pl'),
    portage('Source/Application/Output/Grapher/security.pl'),
    portage('Source/Application/Output/Grapher/tracker.pl'),
    portage('Source/Application/Output/Grapher/dot.pl'),
    portage('Source/Application/Output/Grapher/sitefiles.pl'),
    portage('Source/Application/Output/grapher.pl'),
    portage('Source/Application/Mode/worker.pl'),
    portage('Source/Test/tester.pl'),
    portage('Source/Application/Mode/cluster.pl'),
    portage('Source/Domain/Gentoo/depclean.pl'),
    portage('Source/Application/System/linkage.pl'),
    portage('Source/Application/Output/Report/report.pl'),
    portage('Source/Domain/Gentoo/upstream.pl'),
    portage('Source/Domain/Gentoo/bugs.pl'),
    portage('Source/Test/test.pl')]).

loader:group(worker_modules,
   [portage('Source/Application/Output/writer.pl'),
    portage('Source/Application/Mode/client.pl'),
    portage('Source/Application/Mode/worker.pl'),
    portage('Source/Application/Mode/cluster.pl')]).

loader:group(server_libraries,
   [library('http/http_server'),
    library('http/http_open'),
    library('http/http_client'),
    library('http/http_ssl_plugin'),
    library('http/http_digest'),
    library('http/thread_httpd'),
    library('streams'),
    library('pengines')]).

loader:group(server_modules,
   [portage('Source/Application/Mode/server.pl'),
    portage('Source/Application/Security/sandbox.pl')]).

loader:group(llm_libraries,
   [library('quasi_quotations'),
    library('http/http_open'),
    library('http/http_json'),
    library('edit'),
    library('pcre'),
    library('sandbox')]).

loader:group(llm_modules,
   [portage('Source/Application/llm.pl'),
    portage('Source/Application/Llm/grok.pl'),
    portage('Source/Application/Llm/chatgpt.pl'),
    portage('Source/Application/Llm/claude.pl'),
    portage('Source/Application/Llm/gemini.pl'),
    portage('Source/Application/Llm/ollama.pl'),
    portage('Source/Application/Llm/explain.pl'),
    portage('Source/Application/Llm/knowledge.pl'),
    portage('Source/Application/Llm/metacircular.pl'),
    portage('Source/Application/Llm/semantic.pl')]).


% -----------------------------------------------------------------------------
%  Mode table
% -----------------------------------------------------------------------------

%! loader:mode(?Mode, ?Groups) is nondet.
%
% Declares the module groups of an operating mode. Groups is an ordered
% list of loader:group/2 names.
%
% common is a prerequisite loaded before mode dispatch. daemon and
% server extend standalone so pipeline additions propagate.

loader:mode(common,
   [common_libraries,
    common_modules]).

loader:mode(ipc,
   [ipc_modules]).

loader:mode(client,
   [client_libraries,
    client_core_modules,
    printer_modules,
    client_modules]).

loader:mode(standalone,
   [pipeline_libraries,
    standalone_libraries,
    knowledge_modules,
    domain_modules,
    pipeline_modules,
    printer_modules,
    standalone_modules]).

loader:mode(worker,
   [pipeline_libraries,
    rpc_libraries,
    knowledge_modules,
    domain_modules,
    pipeline_modules,
    printer_modules,
    worker_modules]).

loader:mode(daemon, [daemon_modules|Groups]) :-
   loader:mode(standalone, Groups).

loader:mode(server, Groups) :-
   loader:mode(standalone, Standalone),
   append(Standalone, [server_libraries, server_modules], Groups).


%! loader:optional(?Mode, ?Groups, :Condition) is nondet.
%
% Declares module groups that Mode loads after its loader:mode/2 groups,
% only when Condition holds. The Generative AI groups are gated by
% config:load_llm_modules/1; when false the builder / CLI continue
% without LLM backends, and call sites must tolerate that (stubs + soft
% call_llm). daemon and server inherit standalone's optional groups.

loader:optional(client,     [llm_libraries, llm_modules], config:load_llm_modules(true)).
loader:optional(standalone, [llm_libraries, llm_modules], config:load_llm_modules(true)).
loader:optional(worker,     [llm_libraries, llm_modules], config:load_llm_modules(true)).

loader:optional(daemon, Groups, Condition) :-
   loader:optional(standalone, Groups, Condition).

loader:optional(server, Groups, Condition) :-
   loader:optional(standalone, Groups, Condition).


% -----------------------------------------------------------------------------
%  Group loading
% -----------------------------------------------------------------------------

%! loader:load_group(+Group) is det.
%
% Loads every file spec in a module group, in declaration order. Files are
% loaded into the user module, matching the load context of load_modules/1.

loader:load_group(Group) :-
   loader:group(Group, Specs),
   forall(member(Spec, Specs), user:ensure_loaded(Spec)).


%! loader:load_groups(+Groups) is det.
%
% Loads a list of module groups in order.

loader:load_groups(Groups) :-
   forall(member(Group, Groups), loader:load_group(Group)).


% -----------------------------------------------------------------------------
%  Mode loading
% -----------------------------------------------------------------------------

%! load_modules(+Mode) is det.
%
% Loads the module groups declared for Mode, then its optional groups
% whose condition holds.

load_modules(Mode) :-
   loader:mode(Mode, Groups),
   loader:load_groups(Groups),
   forall(( loader:optional(Mode, Optional, Condition),
            call(Condition) ),
          loader:load_groups(Optional)),
   format(atom(Msg), 'Loaded ~w modules...', [Mode]),
   message:log(Msg).
