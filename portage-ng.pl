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
*/


% **********
% PORTAGE-NG
% **********

create_prolog_flag(system_cacert_filename,'/tmp/cacert.pem',[access(read_only)]).

load_common :-
   writeln('Loading common modules...'),

   ensure_loaded(library('optparse')),
   ensure_loaded(library('tty')),
   ensure_loaded(library('time')),
   ensure_loaded(library('thread')),

   ensure_loaded('Source/config.pl'),
   ensure_loaded('Source/interface.pl'),
   ensure_loaded('Source/message.pl').

load_client :-
   writeln('Loading client modules...'),
   ensure_loaded(library('http/http_open')),
   ensure_loaded(library('http/http_ssl_plugin')),
   ensure_loaded(library('http/thread_httpd')),
   use_module(swi(doc/packages/examples/http/demo_body)),
   ensure_loaded('Source/client.pl').


load_standalone :-
   writeln('Loading standalone modules...'),
   ensure_loaded(library('aggregate')),
   ensure_loaded(library('apply_macros')),
   ensure_loaded(library('gensym')),

   ensure_loaded('Source/context.pl'),
   ensure_loaded('Source/instances.pl'),
   ensure_loaded('Source/cache.pl'),
   ensure_loaded('Source/repository.pl'),
   ensure_loaded('Source/knowledgebase.pl'),
   ensure_loaded('Source/query.pl'),

   ensure_loaded('Source/eapi.pl'),
   ensure_loaded('Source/rules.pl'),
   ensure_loaded('Source/ebuild.pl'),
   ensure_loaded('Source/preference.pl'),
   ensure_loaded('Source/unify.pl'),
   ensure_loaded('Source/script.pl'),
   ensure_loaded('Source/stat.pl'),
   ensure_loaded('Source/os.pl'),

   ensure_loaded('Source/reader.pl'),
   ensure_loaded('Source/parser.pl'),
   ensure_loaded('Source/prover.pl'),
   ensure_loaded('Source/planner.pl'),
   ensure_loaded('Source/printer.pl'),
   ensure_loaded('Source/builder.pl'),
   ensure_loaded('Source/grapher.pl'),
   ensure_loaded('Source/worker.pl'),
   ensure_loaded('Source/tester.pl'),

   ensure_loaded('Source/test.pl').


load_server :-
   writeln('Loading server modules...'),
   ensure_loaded(library('http/http_server')),
   ensure_loaded(library('http/http_open')),
   ensure_loaded(library('http/http_ssl_plugin')),
   ensure_loaded(library('http/thread_httpd')),

   %ensure_loaded(library('pengines')),
   ensure_loaded('Source/server.pl').


%! main.
%
% The main predicate.
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
    (load_common,
     interface:process_mode(Mode),
     message:title_reset,
     main(Mode))).


main(client) :-
  load_client.


main(standalone) :-
  load_standalone,

  config:installation_dir(Directory),
  system:working_directory(_,Directory),

  kb:newinstance(knowledgebase),

  % Example: Portage repository - sync vie web tarball
  % --------------------------------------------------
  % portage:newinstance(repository),
  % portage:init('/Users/pvdabeel/Repository/portage-web','/Users/pvdabeel/Repository/portage-web/metadata/md5-cache',
  %              'http://distfiles.gentoo.org/releases/snapshots/current/portage-latest.tar.bz2','http','eapi'),


  % Example: Portage repository - sync via rsync
  % --------------------------------------------
  % portage:newinstance(repository),
  % portage:init('/Users/pvdabeel/Repository/portage-rsync','/Users/pvdabeel/Repository/portage-rsync/metadata/md5-cache',
  %             'rsync://rsync.gentoo.org/gentoo-portage','rsync','eapi'),


  % Example: Portage repository - sync via git
  % ------------------------------------------
  portage:newinstance(repository),
  portage:init('/Users/pvdabeel/Repository/portage-git','/Users/pvdabeel/Repository/portage-git/metadata/md5-cache',
                'https://github.com/gentoo-mirror/gentoo','git','eapi'),
  kb:register(portage),


  % Example: Overlay repository - local sync
  % ----------------------------------------
  % overlay:newinstance(repository),
  % overlay:init('/Volumes/Disk 1/Repository/overlay',
  %             '/Volumes/Disk 1/Repository/overlay/metadata/md5-cache',
  %             '/Users/pvdabeel/Desktop/Prolog/Repository/overlay/','rsync','eapi'),
  % kb:register(overlay),


  % Example: Github code repository - sync via git
  % ----------------------------------------------
  % swipl:newinstance(repository),
  % swipl:init('/Volumes/Disk 1/Repository/swipl-devel',
  %            '/Volumes/Disk 1/Repository/swipl-devel/metadata',
  %            'https://github.com/swi-prolog/swipl-devel','git','cmake'),
  % kb:register(swipl),


  % Example: Github code repository - sync via git
  % ----------------------------------------------
  % linux:newinstance(repository),
  % linux:init('/Volumes/Disk 1/Repository/linux',
  %            '/Volumes/Disk 1/Repository/linux/metadata',
  %            'https://github.com/torvalds/linux','git','cmake'),
  % kb:register(linux),

  kb:load,
  interface:process_requests(standalone).


main(server) :-
  main(standalone),
  load_server,
  server:start_server,
  interface:process_requests(server).

