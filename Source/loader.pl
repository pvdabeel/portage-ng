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
are declared as loader:mode/2 facts (an ordered group list).
loader:ensure/1 loads build, graph, bulk, cluster and language-model
groups when an action needs them.
load_modules/1 is the single entry point. A module needed by several
modes lives in exactly one shared group, so additions propagate
automatically and the delta between modes (e.g. standalone vs worker)
stays explicit and reviewable.

Project files are compiled to .qlf files on their first load and loaded
from those afterwards. The .qlf files live in a directory of their own
(the compiled module cache, Build/qlf in the state directory), never
beside the sources.
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
    portage('Source/Logic/hook.pl'),
    portage('Source/Logic/nbstore.pl'),
    portage('Source/config'),
    portage('Source/Application/Output/console.pl'),
    portage('Source/Application/System/os.pl'),
    portage('Source/Application/System/runtimepath.pl'),
    portage('Source/Application/System/lock.pl'),
    portage('Source/Application/Security/sanitize.pl'),
    portage('Source/Application/Output/message.pl'),
    portage('Source/Application/interface.pl'),
    portage('Source/Application/Interface/action.pl'),
    portage('Source/Application/System/subprocess.pl'),
    portage('Source/Application/System/git.pl'),
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
   [    portage('Source/Application/Mode/stubs.pl'),
    portage('Source/Application/Mode/routes.pl'),
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
    portage('Source/Knowledge/pkgdelta.pl'),
    portage('Source/Application/Mode/routes.pl'),
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
    % stat.pl lives under Source/Test but is production: the progress
    % statistics OO class instantiated at startup (stats:newinstance).
    portage('Source/Test/stat.pl'),
    portage('Source/Domain/Gentoo/vdb.pl'),
    portage('Source/Domain/Gentoo/distfiles.pl'),
    % The Packages parser is what binpkg sync(kb) calls. It has to load
    % with the domain, not with the builder: --sync does not ensure(build).
    portage('Source/Domain/Gentoo/Binpkg/binpkg_index.pl'),
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
    portage('Source/Pipeline/orderer.pl'),
    portage('Source/Application/Mode/jobs.pl')]).

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
   [portage('Source/Pipeline/Builder/buildtime.pl'),
    portage('Source/Domain/Gentoo/variant.pl'),
    portage('Source/Domain/Gentoo/depclean.pl'),
    portage('Source/Application/System/linkage.pl'),
    portage('Source/Application/Output/Report/report.pl'),
    portage('Source/Application/System/httpfetch.pl'),
    portage('Source/Domain/Gentoo/upstream.pl'),
    portage('Source/Domain/Gentoo/bugs.pl')]).

% Build, graph and bulk-test files load through loader:ensure/1 when an
% action needs them. The server mode does not include these groups.

loader:group(builder_modules,
   [portage('Source/Pipeline/Builder/phasestats.pl'),
    portage('Source/Domain/Gentoo/mirror.pl'),
    portage('Source/Domain/Gentoo/Exceptions/fixup.pl'),
    portage('Source/Domain/Gentoo/Exceptions/collision.pl'),
    portage('Source/Domain/Gentoo/Exceptions/ghcabi.pl'),
    portage('Source/Domain/Gentoo/Exceptions/ocamlabi.pl'),
    portage('Source/Domain/Gentoo/Exceptions/missing_provider.pl'),
    portage('Source/Domain/Gentoo/Exceptions/kernelconfig.pl'),
    portage('Source/Domain/Gentoo/Exceptions/useenable.pl'),
    portage('Source/Domain/Gentoo/Exceptions/gitlock.pl'),
    portage('Source/Domain/Gentoo/Binpkg/binpkg_extract.pl'),
    portage('Source/Domain/Gentoo/Binpkg/binpkg_exec.pl'),
    portage('Source/Pipeline/Printer/Build/build.pl'),
    portage('Source/Pipeline/Builder/snapshot.pl'),
    portage('Source/Pipeline/Builder/jobserver.pl'),
    portage('Source/Pipeline/Builder/download.pl'),
    portage('Source/Pipeline/Builder/display.pl'),
    portage('Source/Pipeline/Builder/fetch.pl'),
    portage('Source/Pipeline/Builder/resume.pl'),
    portage('Source/Domain/Gentoo/Ebuild/ebuild_exec.pl'),
    portage('Source/Pipeline/builder.pl')]).

loader:group(graph_modules,
   [portage('Source/Pipeline/Builder/phasestats.pl'),
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
    portage('Source/Application/Output/grapher.pl')]).

% tester.pl lives under Source/Test but is production: it is the
% bulk-iteration harness behind --graph, index/proof file writing
% and the resolver/pipeline/printer test_stats entry points.
loader:group(bulk_modules,
   [portage('Source/Test/tester.pl')]).

loader:group(cluster_modules,
   [portage('Source/Application/Mode/worker.pl'),
    portage('Source/Application/Mode/cluster.pl')]).

% The overlay regression harness (module test, Source/Test/test.pl) is
% NOT part of any operating mode: no production predicate calls it, so
% standalone/daemon/server no longer pay its load (or ship its surface
% in `make build`). Entry points load it on demand via
% loader:load_test_modules/0 (Makefile test-overlay, CI, handbook).
loader:group(test_modules,
   [portage('Source/Test/test.pl')]).

loader:group(worker_modules,
   [portage('Source/Application/Output/writer.pl'),
    portage('Source/Application/Mode/client.pl'),
    portage('Source/Application/Mode/worker.pl'),
    portage('Source/Application/Mode/cluster.pl')]).

loader:group(server_libraries,
   [library('http/http_server'),
    library('http/http_open'),
    library('http/http_client'),
    library('http/http_stream'),
    library('http/http_ssl_plugin'),
    library('http/http_digest'),
    library('http/thread_httpd'),
    library('ssl'),
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
% common is a prerequisite loaded before mode dispatch. daemon extends
% standalone. server is the resolver, queue and HTTP surface: build,
% graph, bulk-test and LLM modules load only through loader:ensure/1.

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

loader:mode(server,
   [pipeline_libraries,
    knowledge_modules,
    domain_modules,
    pipeline_modules,
    printer_modules,
    standalone_modules,
    server_libraries,
    server_modules]).


% Startup groups are unconditional. build, graph, bulk, cluster and llm
% load through loader:ensure/1.


% -----------------------------------------------------------------------------
%  Group loading
% -----------------------------------------------------------------------------

%! loader:capability(?Name, ?Groups) is nondet.
%
% Groups loaded by loader:ensure/1. build, graph and bulk stay out of
% the server process until a request needs them.

loader:capability(build, [builder_modules]).
loader:capability(graph, [graph_modules]).
loader:capability(bulk, [bulk_modules]).
loader:capability(cluster, [cluster_modules]).
loader:capability(llm, [llm_libraries, llm_modules]).

:- dynamic loader:capability_loaded/1.

%! loader:ensure(+Name) is det.
%
% Load Name's groups once. llm is a no-op when
% config:load_llm_modules(false).

loader:ensure(Name) :-
  with_mutex(loader_capabilities, loader:ensure_locked(Name)).

loader:ensure_locked(llm) :-
  \+ config:load_llm_modules(true),
  !.
loader:ensure_locked(Name) :-
  loader:capability_loaded(Name),
  !.
loader:ensure_locked(Name) :-
  loader:capability(Name, Groups),
  loader:load_groups(Groups),
  assertz(loader:capability_loaded(Name)),
  ( current_predicate(sandbox:activate/0) -> sandbox:activate ; true ).


%! loader:load_group(+Group) is det.
%
% Loads every file spec in a module group, in declaration order. Files are
% loaded into the user module, matching the load context of load_modules/1.

loader:load_group(Group) :-
   loader:group(Group, Specs),
   forall(member(Spec, Specs), loader:load_spec(Spec)).


%! loader:load_groups(+Groups) is det.
%
% Loads a list of module groups in order.

loader:load_groups(Groups) :-
   forall(member(Group, Groups), loader:load_group(Group)).


%! loader:load_test_modules is det.
%
% Load the overlay regression harness (loader:group(test_modules))
% on demand. Idempotent (ensure_loaded semantics), so test entry
% points can call it unconditionally before test:run/1,2.

loader:load_test_modules :-
   loader:load_group(test_modules).


% -----------------------------------------------------------------------------
%  Compiled module cache
% -----------------------------------------------------------------------------

% A portage/1 file is compiled to a .qlf file on its first load and loaded
% from that file afterwards. The .qlf files mirror the source tree in a
% directory of their own:
%
%   <state>/Build/qlf/<arch>-<prolog build>/<mode>/Source/.../<file>.qlf
%
% SWI-Prolog decides whether a .qlf file is still valid. It records the
% source, the files the source includes and the files named by
% prolog:qlf_dependency/2, and compares their content when a time stamp
% says one may have changed. What it cannot see is either part of the
% directory name (platform, SWI-Prolog build, operating mode) or switches
% the cache off (loader:cache_enabled/0).

%! loader:compile_time_source(?Spec) is nondet.
%
% Declares a file whose operators or goal expansions are compiled into
% other files. Every cached file is recompiled when one of these changes.
% A new file that defines operators or goal expansions for other files
% must be added here: without it, its dependents keep the old expansion
% until they are edited themselves.

loader:compile_time_source(portage('Source/Logic/context.pl')).
loader:compile_time_source(portage('Source/Application/Output/message.pl')).
loader:compile_time_source(portage('Source/Application/Performance/choicelog.pl')).
loader:compile_time_source(portage('Source/Application/Performance/sampler.pl')).
loader:compile_time_source(portage('Source/Knowledge/query.pl')).
loader:compile_time_source(portage('Source/Domain/Gentoo/version.pl')).
loader:compile_time_source(portage('Source/Pipeline/prover.pl')).


%! loader:source_only(?Spec) is nondet.
%
% Declares a file that is always loaded from source. Spec is written
% without the .pl extension.
%
% config.pl includes the private password and key files when they exist.
% Their content does not belong in the cache, and a .qlf file would keep
% serving it after the files are removed. ipc.pl locates ipclient.pl
% relative to the directory it is loaded from, which for a cached file is
% the cache directory.

loader:source_only(portage('Source/config')).
loader:source_only(portage('Source/Application/Mode/ipc')).


:- dynamic loader:cache_directory/1.
:- dynamic loader:compiling/1.


%! loader:cache_enabled is semidet.
%
% True when files may be loaded from, and compiled into, the cache. The
% cache holds code compiled with -O and with the debug, instrumentation
% and choice-log expansions compiled away, so a run without -O and a run
% with -Ddebug, --profile or --choice-log load from source, as does a run
% with PORTAGE_NG_SOURCE=1. So does a SWI-Prolog without the two system
% predicates the cache relies on.

loader:cache_enabled :-
   current_prolog_flag(optimise, true),
   \+ current_prolog_flag(debug, true),
   \+ current_prolog_flag(instrumentation, true),
   \+ current_prolog_flag(choice_log, true),
   \+ getenv('PORTAGE_NG_SOURCE', '1'),
   predicate_property(system:'$qlf_out_of_date'(_, _, _), defined),
   predicate_property(system:'$qlf_dependency'(_), defined).


%! loader:select_cache(+Mode) is det.
%
% Selects the cache directory of Mode for the files loaded from here on,
% or none when the cache is off. Mode is part of the path because the
% modes differ in what is loaded before a shared file, and so in the
% expansions that file is compiled with.

loader:select_cache(Mode) :-
   retractall(loader:cache_directory(_)),
   (   loader:cache_enabled
   ->  loader:cache_root(Root),
       current_prolog_flag(arch, Arch),
       loader:prolog_build(Build),
       atomic_list_concat([Root, '/', Arch, '-', Build, '/', Mode], Directory),
       assertz(loader:cache_directory(Directory))
   ;   true
   ).


%! loader:cache_root(-Root) is det.
%
% Root of the cache: Build/qlf in the state directory. The state directory
% follows the rule of config:state_dir/1, restated here because the cache
% is selected before config.pl is loaded.

loader:cache_root(Root) :-
   loader:state_directory(State),
   directory_file_path(State, 'Build/qlf', Root).

loader:state_directory(State) :-
   getenv('PORTAGE_NG_STATE', State),
   State \== '',
   !.
loader:state_directory(State) :-
   absolute_file_name(portage('Knowledge'), Knowledge,
                      [file_type(directory), file_errors(fail)]),
   !,
   file_directory_name(Knowledge, State).
loader:state_directory('/var/lib/portage-ng').


%! loader:prolog_build(-Build) is det.
%
% Identifies the SWI-Prolog build: the git description when it was built
% from git, the version number otherwise.

loader:prolog_build(Build) :-
   current_prolog_flag(version_git, Build),
   !.
loader:prolog_build(Build) :-
   current_prolog_flag(version, Build).


%! loader:load_spec(+Spec) is det.
%
% Loads one file spec into the user module: through the cache when Spec
% has a place in it, as a plain ensure_loaded/1 otherwise.

loader:load_spec(Spec) :-
   loader:cached_source(Spec, Source, Qlf),
   !,
   loader:load_cached(Source, Qlf).
loader:load_spec(Spec) :-
   user:ensure_loaded(Spec).


%! loader:cached_source(+Spec, -Source, -Qlf) is semidet.
%
% Source is the source file of the portage/1 term Spec and Qlf its place
% in the selected cache directory. Fails for a library, for a source-only
% file and when no cache directory is selected.

loader:cached_source(portage(Path), Source, Qlf) :-
   loader:cache_directory(Directory),
   (   file_name_extension(Base, pl, Path)
   ->  true
   ;   Base = Path
   ),
   \+ loader:source_only(portage(Base)),
   absolute_file_name(portage(Path), Source,
                      [file_type(prolog), access(read), file_errors(fail)]),
   atomic_list_concat([Directory, '/', Base, '.qlf'], Qlf).


%! loader:load_cached(+Source, +Qlf) is det.
%
% Loads Source once: from Qlf when that is up to date, else from source
% while writing Qlf, else (cache not writable) from source alone.

loader:load_cached(Source, _Qlf) :-
   source_file(Source),
   !.
loader:load_cached(Source, Qlf) :-
   exists_file(Qlf),
   \+ '$qlf_out_of_date'(Source, Qlf, _),
   !,
   user:load_files(Qlf, []).
loader:load_cached(Source, Qlf) :-
   loader:writable_cache_file(Qlf),
   !,
   setup_call_cleanup(
       assertz(loader:compiling(Source), Ref),
       user:load_files(Source, ['$qlf'(Qlf)]),
       erase(Ref)).
loader:load_cached(Source, _Qlf) :-
   user:ensure_loaded(Source).


%! loader:writable_cache_file(+Qlf) is semidet.
%
% Creates the directory of Qlf and succeeds when Qlf can be written.

loader:writable_cache_file(Qlf) :-
   file_directory_name(Qlf, Directory),
   catch(make_directory_path(Directory), error(_, _), fail),
   access_file(Qlf, write).


%! prolog:qlf_dependency(+File, -Dependency) is nondet.
%
% SWI-Prolog hook: Dependency is recorded in the .qlf file of File, which
% is recompiled when Dependency changes. Every file this loader compiles
% depends on the compile-time sources. Limited to those files, so the
% knowledge base .qlf files stay free of dependencies.

:- multifile prolog:qlf_dependency/2.

prolog:qlf_dependency(File, Dependency) :-
   loader:compiling(File),
   loader:compile_time_source(Spec),
   absolute_file_name(Spec, Dependency,
                      [file_type(prolog), access(read), file_errors(fail)]),
   Dependency \== File.


% -----------------------------------------------------------------------------
%  Mode loading
% -----------------------------------------------------------------------------

%! load_modules(+Mode) is det.
%
% Selects the compiled module cache of Mode, then loads the module groups
% declared for Mode. Groups loaded later through loader:ensure/1 use the
% cache of the mode loaded last.

load_modules(Mode) :-
   loader:select_cache(Mode),
   loader:mode(Mode, Groups),
   loader:load_groups(Groups),
   format(atom(Msg), 'Loaded ~w modules...', [Mode]),
   message:log(Msg).
