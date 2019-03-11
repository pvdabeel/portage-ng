% Copyright 2005-2017 Pieter Van den Abeele

:- dynamic cache:entry(_,_,_,_,_,_,_).

% **********
% PORTAGE-NG
% **********

:- use_module(library(aggregate)).
:- use_module(library(tty)).

:- ensure_loaded(library('thread')).
:- ensure_loaded(library('apply_macros')).

:- ensure_loaded('Source/context.pl').
:- ensure_loaded('Source/instances.pl').
:- ensure_loaded('Source/message.pl').

:- ensure_loaded('Source/interface.pl').

:- ensure_loaded('Source/config.pl').
:- ensure_loaded('Source/os.pl').
:- ensure_loaded('Source/repository.pl').
:- ensure_loaded('Source/knowledgebase.pl').

:- ensure_loaded('Source/eapi.pl').
:- ensure_loaded('Source/rules.pl').
:- ensure_loaded('Source/ebuild.pl').
:- ensure_loaded('Source/preference.pl').

:- ensure_loaded('Source/reader.pl').
:- ensure_loaded('Source/parser.pl').
:- ensure_loaded('Source/prover.pl').
:- ensure_loaded('Source/planner.pl').
:- ensure_loaded('Source/printer.pl').
:- ensure_loaded('Source/builder.pl').
:- ensure_loaded('Source/grapher.pl').

:- ensure_loaded('Source/script.pl').

% DEBUG
% :- ensure_loaded('Source/test.pl').
% DEBUG

main :- 
    config:installation_dir(Directory),
    working_directory(_,Directory),

    portage:newinstance(repository),
    overlay:newinstance(repository),    

    kb:newinstance(knowledgebase),

    % Example: Portage repository - sync vie web tarball
    % --------------------------------------------------
    % portage:init('/Users/pvdabeel/Repository/portage-web','/Users/pvdabeel/Repository/portage-web/metadata/md5-cache',
    %              'http://distfiles.gentoo.org/releases/snapshots/current/portage-latest.tar.bz2','http','eapi'),
    

    % Example: Portage repository - sync via rsync
    % --------------------------------------------
    % portage:init('/Users/pvdabeel/Repository/portage-rsync','/Users/pvdabeel/Repository/portage-rsync/metadata/md5-cache',
    %             'rsync://rsync.gentoo.org/gentoo-portage','rsync','eapi'),


    % Example: Portage repository - sync via git
    % ------------------------------------------
    portage:init('/Users/pvdabeel/Repository/portage-git','/Users/pvdabeel/Repository/portage-git/metadata/md5-cache',
                  'https://github.com/gentoo-mirror/gentoo','git','eapi'),


    % Example: Overlay repository - local sync
    % ----------------------------------------
    overlay:init('/Users/pvdabeel/Repository/overlay',
                 '/Users/pvdabeel/Repository/overlay/metadata/md5-cache',
                 '/Users/pvdabeel/Desktop/Prolog/Repository/Overlay/','rsync','eapi'),

    kb:register(portage),
    kb:register(overlay),
    kb:load,
    interface:process_requests.
