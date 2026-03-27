/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> PORTAGE-NG
A declarative reasoning engine for software configuration, applied to Gentoo
Linux. 

portage-ng uses inductive proof search to reason about package
dependencies. Every build plan it produces is a formal proof. It fully 
implements PMS 9 / EAPI 9 (USE-conditional dependencies, slot operators, 
sub-slots, blockers, PDEPEND) and reads the same Portage tree, VDB, profiles, 
and /etc/portage configuration as traditional Portage.

This file is the main entry point.

Launch using

swipl
  -O                                               -> turns on Prolog optimizations
  --stack_limit=32G                                -> 32G stack space
  --
  -f /Users/pvdabeel/Desktop/Prolog/portage-ng.pl  -> load the main file
  -p portage=/Users/pvdabeel/Desktop/Prolog        -> set application home
  -g main                                          -> execute main
  --
*/


% =============================================================================
%  PORTAGE-NG
% =============================================================================

% -----------------------------------------------------------------------------
% Load modules
% -----------------------------------------------------------------------------

% loader.pl takes care of loading the appropriate modules for a given mode.
% Mode can be standalone, ipc, daemon, client, worker, or server.

:- include(portage('Source/loader')).


% -----------------------------------------------------------------------------
%  Per-mode initialization
% -----------------------------------------------------------------------------

%! main(+Mode) is det.
%
% Mode-specific startup. Verifies CLI flags, loads the appropriate
% modules, initializes the system, starts mode-specific services,
% and enters the request loop.

main(standalone) :-
  load_standalone_modules,
  load_llm_modules,
  init_knowledgebase,
  interface:process_requests(standalone).

main(ipc) :-
  interface:verify(ipc),
  daemon:autostart,
  daemon:connect(ExitCode),
  halt(ExitCode).

main(daemon) :-
  interface:verify(daemon),
  load_standalone_modules,
  load_llm_modules,
  init_knowledgebase,
  daemon:start,
  interface:process_requests(daemon).

main(client) :-
  interface:verify(client),
  load_client_modules,
  load_llm_modules,
  interface:process_server(Host, Port),
  kb:newinstance(knowledgebase(Host, Port)),
  preference:init,
  interface:process_requests(client).

main(worker) :-
  load_worker_modules,
  load_llm_modules,
  init_knowledgebase,
  interface:process_server(Host, Port),
  worker:start(Host, Port),
  interface:process_requests(worker).

main(server) :-
  interface:verify(server),
  main(standalone),
  load_server_modules,
  server:start_server,
  at_halt(server:stop_server),
  bonjour:advertise,
  interface:process_requests(server).


%! init_knowledgebase is det.
%
% Common knowledge base bootstrap shared by standalone, daemon,
% and worker modes.

init_knowledgebase :-
  stats:newinstance(stat),
  kb:newinstance(knowledgebase),
  config:systemconfig(Config),
  ensure_loaded(Config),
  kb:load,
  preference:init.


% -----------------------------------------------------------------------------
%  Main predicate
% -----------------------------------------------------------------------------

%! main is det.
%
% Entry point. Loads common modules, determines the operating mode
% from command-line arguments, and calls main/1 for mode-specific
% initialization and request processing.
%
% @see Source/loader.pl for module loading
% @see interface:verify/1 for CLI flag verification

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
