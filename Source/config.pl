/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> CONFIG
Configuration for portage-ng
*/

:- module(config, []).

% =============================================================================
%  CONFIG declarations
% =============================================================================

% -----------------------------------------------------------------------------
% General
% -----------------------------------------------------------------------------

%! config:name(?Name)
%
% Declares the name of this program.

config:name('portage-ng-dev').


%! config:hostname(?Hostname)
%
% Declares the hostname this program is running on.

config:hostname(Hostname) :- socket:gethostname(Hostname).


%! config:installation_dir(?FullPath)
%
% Declaration of the installation directory of the application source code.
% Needs to be a full path. We serialise some Prolog code to this directory.
% Needs to be passed to prolog as a system flag (See portage-ng.pl)

config:installation_dir(Dir) :-
  file_search_path(portage,Dir),!.


%! config:working_dir(+FullPath)
%
% Declares the current working directory

config:working_dir(Dir) :-
  config:installation_dir(Dir).


% -----------------------------------------------------------------------------
% Repository
% -----------------------------------------------------------------------------

%! config:trust_metadata(?Bool)
%
% When set to false, we regenerate locally the cache entries
% after syncing with the remote repository. This is expensive,
% so by default we trust and regenerate only for locally changed
% ebuilds or ebuilds with missing cache.

config:trust_metadata(true).


%! config:write_metadata(?Bool)
%
% When ebuilds are changed locally or new ebuilds are created locally
% this will be detected during syncing, and portage will parse the
% ebuild metadata after running it through ebuild.sh.
%
% Prolog facts are updated with the updated metadata.
% If this variable is set to true, we will also create an on-disk
% cache entry for these ebuilds. This cache entry may be overwritten
% by a sync later on by remotely generated cache.

config:write_metadata(true).


% -----------------------------------------------------------------------------
% Pkg directory
% -----------------------------------------------------------------------------

%! config:pkg_directory(?Hostname,?FullPath)
%
% Declaration of the pkg db directory on a system. This holds metadata
% for all packages installed on a system

config:pkg_directory('imac-pro.local',    '/Volumes/Disk 1/Repository/pkg')  :- !.
config:pkg_directory('mac-pro.local',     '/Volumes/Storage/Repository/pkg') :- !.
config:pkg_directory('macbook-pro.local', '/Users/pvdabeel/Repository/pkg')  :- !.
config:pkg_directory('vm-linux.local',    '/var/db/pkg')                     :- !.


% -----------------------------------------------------------------------------
% World file
% -----------------------------------------------------------------------------

%! config:world_file(Path)
%
% Declaration of the world file path. The world file holds the requirements
% for installed packages.

config:world_file(Filename) :-
  config:installation_dir(Dir),
  config:hostname(Hostname),
  os:compose_path([Dir,'Source/Sets/world',Hostname],Filename).


% -----------------------------------------------------------------------------
% System
% -----------------------------------------------------------------------------

%! config:systemconfig(?Filename)
%
% Declares the systemconfig for the host this program is running. This file
% contains system specific configuration settings. The standard setting
% looks whether <hostname>.pl exists in the Source/Config directory. If not
% then Source/Config/default.pl is used. Typically this is used to define the
% different repositories / overlays per hostname.

config:systemconfig(Filename) :-
  config:installation_dir(Dir),
  config:hostname(Hostname),
  os:compose_path([Dir,'Source/Config','default'],Default),
  os:compose_path([Dir,'Source/Config',Hostname],Configuration),
  system:file_name_extension(Configuration,'pl',ConfigFile),
  ( system:exists_file(ConfigFile)
    -> Filename = ConfigFile
    ;  Filename = Default ).


%! config:number_of_cpus(?Count)
%
% This application parallellizes parsing, proving, planning and building.
% SWI prolog is automatically able to determine the maximum cpu count, but
% sometimes we may want to change this to a value of our choice.

config:number_of_cpus(C) :- current_prolog_flag(cpu_count,C).


%! config:number_of_cpus(?Count)
%
% Different verbosity levels may be configured for printing runtime information

config:verbosity(debug).


% -----------------------------------------------------------------------------
% Passwords
% -----------------------------------------------------------------------------

:- include(portage('Source/Private/passwords')).


% -----------------------------------------------------------------------------
% Network
% -----------------------------------------------------------------------------

%! config:bonjour_service(?Service)
%
% The mDNS service used to advertise and discover hosts on the network

config:bonjour_service('_prolog._tcp.').


%! config:server_host(?Url)
%
% Declares the server url, including protocol (https) and port the client needs
% to connect on. This can be overridden using the --host option in the interface.

config:server_host('mac-pro.local').


%! config:server_port(?Number)
%
% Declares the port on which the server needs to be launched.
% Always launches on localhost, using https/ssl. This can be overridden
% using the --port option in the interface.

config:server_port(4000).


%! config:server_chunck(?Chunksize)
%
% When set to false, when working in client-server mode, one % RPC call is
% performed per solution. When generating large number of solutions, such as
% backtracking over a goal, it is best to transfer multiple solutions in one
% chunck over one rpc call.

% Setting this to a higher value speeds up searching in client-server mode.
% Shouldn't be higher than the total number of entries in your repositories.

config:server_chunk(50000).


% -----------------------------------------------------------------------------
% Certificates
% -----------------------------------------------------------------------------

%! config:initialize_cacert
%
% Initializes the certificate authority. We use certificates in our
% client-server communication.

config:initialize_cacert :-
  config:certificate('cacert.pem',Fullpath),
  create_prolog_flag(system_cacert_filename,Fullpath,[access(read_only)]).


%! config:certificate(+Certificate,-Fullpath)
%
% Returns an absolute path for a given certificate name

config:certificate(Certificate,Fullpath) :-
  config:installation_dir(Dir),
  os:compose_path([Dir,'Source/Certificates',Certificate],Fullpath).


%! config:certificate(+Hostname,+Certificate,-Fullpath)
%
% Return an absolute path for a given hostname certificate name

config:certificate(Hostname,Certificate,FullPath) :-
  atomic_list_concat([Hostname,Certificate],'.',HostCertificate),
  config:certificate(HostCertificate,FullPath).


%! config:digest_passwordfile(?File)
%
% Declares the password file for http(s) digest user authentication

config:digest_passwordfile(Filename) :-
  config:installation_dir(Dir),
  os:compose_path([Dir,'Source/Certificates/passwordfile'],Filename).


 % -----------------------------------------------------------------------------
 % Graphing
 % -----------------------------------------------------------------------------
 
 % Interface can dynamically override graphing behavior for a single run.
 % (Used by CLI flags like --graph-modified / --graph-full.)
 :- dynamic config:interface_graph_modified_only/1.
 
 %! config:graph_directory(?Hostname,?FullPath)
%
% This application is capable of writing Graphviz dot files and will turn
% them into interactive scalable vector graphics (svg) to enable you to
% browse through a dependency graph.
%
% Directory doesn't need a trailing '/'.
%
% We store the generated dot and svg files in the following directory.

config:graph_directory('imac-pro.local',    '/Volumes/Disk 1/Graph')  :- !.
config:graph_directory('mac-pro.local',     '/Volumes/Storage/Graph') :- !.
config:graph_directory('macbook-pro.local', '/Users/pvdabeel/Graph')  :- !.
config:graph_directory('vm-linux.local',    '/root/Graph')            :- !.


 %! config:graph_modified_only(?Bool)
 %
 % Set when you want Graphviz dot file to be created for new ebuilds only
 
 config:graph_modified_only(Bool) :-
   config:interface_graph_modified_only(Bool),
   !.
 config:graph_modified_only(true).


%! config:graph_dependency_type(?List)
%
% Defines the dependency types for which you want a full graph

config:graph_dependency_type([detail,
                              bdepend,
                              cdepend,
                              depend,
                              idepend,
                              rdepend,
                              pdepend]).


%! config:graph_proof_type(?List)
%
% Defines the proof types for which you want to create svg

config:graph_proof_type([merge,fetchonly,info]).


%! config:graph_legacy_type(?List)
%
% Defines the legacy types for which you want to create svg

config:graph_legacy_type([emerge]).


% -----------------------------------------------------------------------------
% Graphing: static assets
% -----------------------------------------------------------------------------
%

% When generating HTML (index pages + proofs) we copy a few static assets into the
% repository graph directory (the dir created by repository:prepare_directory/1).
%
% Targets (fixed names in output directory):
%
% - .index.css   (used by printer:write_index_files/2 HTML)
% - .proof.css   (used by Scripts/*/print-aha to render proof output)
% - .meslo.ttf   (font used by proof rendering)
%
% Sources are configurable here (defaults are in Documentation/).

%! config:graph_asset_source(+Key, -SourcePath)
%
% Returns the source path for a given asset key

config:graph_asset_source(index_css, Source) :-
  config:installation_dir(Dir),
  os:compose_path([Dir,'Documentation/.index.css'], Source).

config:graph_asset_source(proof_css, Source) :-
  config:installation_dir(Dir),
  os:compose_path([Dir,'Documentation/.proof.css'], Source).

config:graph_asset_source(meslo_ttf, Source) :-
  config:installation_dir(Dir),
  os:compose_path([Dir,'Documentation/.meslo.ttf'], Source).


% -----------------------------------------------------------------------------
% Distfiles / mirrors (analysis + future downloader)
% -----------------------------------------------------------------------------


%! config:mirror_root(?Path)
%
% Default paths used by mirror:test_stats/1 and related tooling.
% These can be overridden at call-site (mirror:test_stats/2), but having a single
% source of truth here makes behavior consistent across CLI and scripts.
%
% - mirror_root/1: hashed distfiles mirror root (GLEP 75 layout.conf aware)
% - distdir/1: local flat distfiles directory (typical Gentoo: /var/cache/distfiles)

config:mirror_root('/Volumes/Storage/Distfiles/distfiles').

%! config:distdir(?Path)
%
% Gentoo default is usually /var/cache/distfiles. If you use /usr/portage/distfiles,
% override here.

config:distdir('/var/cache/distfiles').

%! config:mirror_verify_hashes_default(?Policy)
%
% Default hash verification policy for mirror:test_stats:
%
% - none: only check existence + size
% - sample(N): verify hashes for the first N unique distfiles (fast sanity)
% - all: verify hashes for all unique distfiles (expensive)

config:mirror_verify_hashes_default(none).


% -----------------------------------------------------------------------------
% Proving
% -----------------------------------------------------------------------------

%! config:time_limit(?Limit)
%
% When parsing, proving or planning, use the specified time limit to
% automatically stop computation if it takes too long.
%In seconds.

config:time_limit(60).


%! config:proving_target(?Target)
%
% Fact which controls the test target for prover, planner, printer and builder
% Set to either:
%
%  - 'install' : Proof using compile-time dependencies only
%  - 'run': Proof using compile- and run-time dependencies

config:proving_target(run).


%! config:avoid_reinstall(?Bool)
%
% If a package is already installed, when this config item is set to true,
% we will verify installation, rather than reinstall the package.

config:avoid_reinstall(false).


% -----------------------------------------------------------------------------
% Printing
% -----------------------------------------------------------------------------

% Interface can dynamically adjust the verbosity

:- dynamic config:verbose/1.

config:verbose(false).


% Interface can dynamically set the printing style

:- dynamic config:interface_printing_style/1.

% The default printing style

config:default_printing_style('fancy').


%! confg:printing_style(?Setting)
%
% Retrieves the printing style ('short', 'column' or 'fancy')
%
% 1. Running as a server, use client style

config:printing_style(Style) :-
  pengine_self(M),
  !,
  M:printing_style(Style).

% 2. Not running as a server, use interface style when specified,
%    otherwise default

config:printing_style(Style) :-
  config:interface_printing_style(Style),!.

config:printing_style(Style) :-
  \+(config:interface_printing_style(_)),
  config:default_printing_style(Style).


%! config:printing_tty_size(?H,?W)
%
% Retrieves the tty_size to use for printing
%
% 1. Running as a server, use client tty_size

config:printing_tty_size(H,W) :-
  pengine_self(M),
  !,
  M:printing_tty_size(H,W).

% 2. Otherwise use actual tty_size

config:printing_tty_size(H,W) :-
  catch(tty_size(H,W), _, fail),
  !.

% 3. Fallback in case actual tty_size cannot be retrieved

config:printing_tty_size(80,160).


%! config:print_expand_use(?Bool)
%
% Defines whether we print information that is normally not printed

config:print_expand_use(false).


%! config:printable_metadata(?List)
%
% Defines which elements in which order to print out when printing ebuild
% information. Use 'blank' to put blank lines in output. Use 'hl' to output
% a horizontal line.

config:printable_metadata([blank,
                           hl, % -------------
                           description,
                           homepage,
                           license,
                           eapi,
                           slot,
  		                     subslot,
                           hl, % -------------
                           iuse,
                           required_use,
                           keywords,
                           properties,
                           eclasses,
                           defined_phases,
                           installed,
                           hl, % -------------
                           src_uri,
                           hl, % -------------
                           bdepend,
                           blank,
                           depend,
                           blank,
                           idepend,
                           blank,
                           rdepend,
                           blank,
                           pdepend
                          ]).


% -----------------------------------------------------------------------------
% Testing
% -----------------------------------------------------------------------------

%! config:test_style(?Style)
%
% Sets the default test style for executing tests. Can be either:
% - single_verbose
% - parallel_verbose
% - parallel_fast

config:test_style(parallel_verbose).


%! config:test_stats_top_n(?N)
%
% How many items to show in "Top cycle mentions" in test statistics output.
%
% Note: must be a non-negative integer.

config:test_stats_top_n(25).


%! config:bugreport_drafts_enabled(?Bool)
%
% Whether to print "Bug report drafts (Gentoo Bugzilla)" in the warnings section
% when domain assumptions are present.
%
config:bugreport_drafts_enabled(true).


%! config:bugreport_drafts_max_assumptions(?N)
%
% Only print bug report drafts when the number of domain assumptions is small,
% to avoid overwhelming output for bulk runs.
%
% Note: must be a non-negative integer.
%
config:bugreport_drafts_max_assumptions(25).


%! config:failsilenton(?Key)
%
% Fails silently (i.e. without messaging failure on the termimal.
% Key can be:
% - version : fails silently when trying to parse versions from git repositories

config:failsilenton(version).


% -----------------------------------------------------------------------------
% Building
% -----------------------------------------------------------------------------

%! config:dry_run_build(?Bool)
%
% Declare config:dry_run_build to avoid actually building software.

config:dry_run_build(true).


%! config:time_limit_build(?Limit)
%
% When executing a plan (i.e. building) use the specified time limit to
% automatically stop the build process if it takes too long. Note this limit
% applies to an entire step in a plan.
% In seconds.

config:time_limit_build(6000).


% ---------------------
% Large Language Models
% ---------------------

%! config:llm_api_key(?LLM,?Key)
%
% Declares the private API key for each large language model.

:- include(portage('Source/Private/api_key')).


%! config:llm_capability(+Name,-Capability)
%
% Declares prompts to be passed to the LLM

config:llm_capability(chat,Capability) :-
  Description="When formulating a response, you may optionally enclose a message
               (e.g., a question) in <call:chatgpt>, <call:gemini>, <call:ollama>,
               or <call:claude> tags to send it to the respective LLM. The response
               is automatically returned to you, with each LLM maintaining its own
               history of your queries.",
  normalize_space(string(Capability),Description).

config:llm_capability(code,Capability) :-
  Description="When asked to write SWI-Prolog code, you may optionally enclose the
               code in <call:swi_prolog> XML tags. Any code within these tags will
               be executed locally in a temporary module, with the output
               automatically returned to you. Do not mention the XML tags unless
               you include SWI-Prolog code between them. Write the code as if it
               were loaded from a separate source file, including triggering
               execution of your main function using a :- directive, such as
               :- main. The temporary module is destroyed after execution.",
  normalize_space(string(Capability),Description).


%! config:llm_support(-Prompt)
%
% Declares prompts to be passed to the LLM in case of merge failure

config:llm_support(Capability) :-
  Description="I get no result trying to emerge the following ebuilds, please find
               me the correct one, or propose to write one. Give me a short answer
               now, until I tell you to write an ebuild. Here is what I was trying
               to do: ",
  normalize_space(string(Capability),Description).


%! config:llm_use_tools(?Bool)
%
% Declares whether or not to enable to code execution integration

config:llm_use_tools(true).


%! config:llm_max_tokens(?Max)
%
% Declares the maximum tokens returned by an LLM

config:llm_max_tokens(4096).


%! config:llm_temperature(?Temperature)
%
% Declares how creative or predictable the LLM should be

config:llm_temperature(0.7).


%! config:llm_sandboxed_execution(?Bool)
%
% Declares whether to turn on or turn off the LLM code execution sandbox

config:llm_sandboxed_execution(false).


%! config:llm_model(?LLM,?Key)
%
% Declares which version of each large language model to use.

config:llm_model(grok,       'grok-4-1-fast-reasoning').
config:llm_model(chatgpt,    'gpt-4o').
config:llm_model(claude,     'claude-sonnet-4-5').
config:llm_model(gemini ,    'gemini-3-pro-preview').
config:llm_model(llama ,     'Llama-4-Maverick-17B-128E-Instruct-FP8').
config:llm_model(ollama ,    'llama3.2').


%! config:llm_endpoint(?LLM,?Endpoint)
%
% Declares the https endpoint url for each large language model.

config:llm_endpoint(grok,    'https://api.x.ai/v1/chat/completions').
config:llm_endpoint(chatgpt, 'https://api.openai.com/v1/chat/completions').
config:llm_endpoint(claude,  'https://api.anthropic.com/v1/messages').
config:llm_endpoint(gemini,  'https://generativelanguage.googleapis.com/v1beta/chat/completions').
config:llm_endpoint(llama,   'https://api.llama.com/v1/chat/completions').
config:llm_endpoint(ollama,  'http://localhost:11434/v1/chat/completions').


% -----------------------------------------------------------------------------
% Debugging
% -----------------------------------------------------------------------------

%! config:q_enabled(?Bool)
%
% The Q oracle caches proofs and plans. This is useful when you are working on
% the printer or the builder, and don't want to wait for the prover or planner
% to reproduce the same proof or plan over and over again.

config:q_enabled(false).
