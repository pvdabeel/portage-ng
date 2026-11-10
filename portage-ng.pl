/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> PORTAGE-NG
A declarative reasoning engine for software configuration management, applied 
to Gentoo Linux. 

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

% loader.pl declares groups and modes; load_modules/1 is the entry point.
% Mode can be standalone, ipc, daemon, client, worker, or server.

:- include(portage('Source/loader')).


% -----------------------------------------------------------------------------
%  Per-mode initialization
% -----------------------------------------------------------------------------

%! main(+Mode) is det.
%
% Mode-specific startup. Modules for Mode are already loaded by
% main/0. Initializes the system and starts mode-specific services.
% The request loop is entered by main/0 afterwards.

main(standalone) :-
  init_world,
  init_knowledgebase(local).

main(ipc) :-
  ipc:autostart,
  ipc:connect(ExitCode),
  halt(ExitCode).

main(daemon) :-
  init_world,
  init_knowledgebase(local),
  daemon:start.

main(client) :-
  init_world,
  init_knowledgebase(remote).

main(worker) :-
  init_world,
  init_knowledgebase(local),
  interface:process_server(Host, Port),
  worker:start(Host, Port).

main(server) :-
  init_world,
  init_knowledgebase(local),
  server:start_server,
  at_halt(server:stop_server),
  bonjour:advertise.


%! init_knowledgebase(+Kind) is det.
%
% Kind is `local` (on-disk knowledge base) or `remote` (server
% proxy). Both run preference:init, so the caller loads the world set
% first. ipc calls neither. The local variant returns only once the
% metadata index warm-up started by kb:load has finished, so the first
% request finds the index in place instead of building one of its own.

init_knowledgebase(local) :-
  stats:newinstance(stat),
  kb:newinstance(knowledgebase),
  config:systemconfig(Config),
  ensure_loaded(Config),
  kb:load,
  feedback:load,
  preference:init,
  knowledgebase:join_metadata_warmer.

init_knowledgebase(remote) :-
  interface:process_server(Host, Port),
  kb:newinstance(knowledgebase(Host, Port)),
  preference:init.


%! init_world is det.
%
% Loads the host world set. Called before init_knowledgebase/1 so
% preference:init can snapshot the loaded set.

init_world :-
  config:world_file(File),
  world:newinstance(set(File)),
  world:load.


% -----------------------------------------------------------------------------
%  Main predicate
% -----------------------------------------------------------------------------

%! main is det.
%
% Entry point. Loads common modules, determines the operating mode
% from command-line arguments, sets the working directory, loads that
% mode's modules, runs mode-specific startup, and enters the request
% loop.
%
% @see Source/loader.pl for module loading
% @see interface:verify_mode/1 for CLI flag verification

main :-
  load_modules(common),
  interface:get_mode(Mode),
  interface:init_tty,
  interface:verify_mode(Mode),
  interface:init_working_dir,
  load_modules(Mode),
  main(Mode),
  interface:process_requests(Mode).