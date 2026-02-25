/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> VDB
This module is reponsible for tracking installed packages on the system.
*/

:- module(vdb, []).

% message.pl is part of the main load graph; we call it via module qualification
% (message:warning/1) without importing here to avoid path issues.

% =============================================================================
%  PKG declarations
% =============================================================================


%! vdb:installed_pkg(+Entry)
%
% Retrieves installed packages on the system (cached)

os:installed_pkg(Repository://Entry) :-
  query:search(installed(true),Repository://Entry).

os:installed_pkgs(L) :-
  findall(R://E,os:installed_pkg(R://E),L).


%! vdb:sync
%
% Syncs the installed packages to prolog metadata

vdb:sync :-
  retractall(cache:entry_metadata(portage,_,installed,_)),
  forall(vdb:find_installed_pkg(portage://Entry),
         (asserta(cache:entry_metadata(portage,Entry,installed,true)))).
          %message:scroll([Entry]))),
	  %message:inform(['Updated system package database']).


%! vdb:find_installed_pkg(+Entry)
%
% Retrieves installed packages on the system

vdb:find_installed_pkg(portage://Entry) :-
  config:hostname(Hostname),
  config:pkg_directory(Hostname,Directory),
  os:directory_content(Directory,Category),
  os:compose_path(Directory,Category,CategoryDir),
  os:directory_content(CategoryDir,Package),
  os:compose_path(Category,Package,Entry).


% NEEDS REWORK -> move to another location (repository?)

%! vdb:create_repository_dirs(+Repository,+Directory)
%
% Given a prolog repository, creates a directory with subdirs
% corresponding to the categories within the prolog repository

vdb:create_repository_dirs(Repository,Directory) :-
  forall(Repository:category(C),
    (os:compose_path(Directory,C,Subdir),
     (system:exists_directory(Subdir);
      system:make_directory(Subdir)))).


%! vdb:make_repository_dirs(+Repository,+Directory)
%
% Given a prolog repository, creates a directory with subdirs
% corresponding to the categories within the prolog repository

vdb:make_repository_dirs(Repository,Directory) :-
  system:make_directory(Directory),
  forall(Repository:category(C),
    (os:compose_path(Directory,C,Subdir),
     system:make_directory(Subdir))).


% -----------------------------------------------------------------------------
%  Graph directory helpers
% -----------------------------------------------------------------------------
%
% Copy static assets into the repository graph directory.
% Targets are fixed names: .index.css, .proof.css, .meslo.ttf
%
vdb:copy_graph_assets(Directory) :-
  vdb:copy_graph_asset(index_css, '.index.css', Directory),
  vdb:copy_graph_asset(proof_css, '.proof.css', Directory),
  vdb:copy_graph_asset(meslo_ttf, '.meslo.ttf', Directory),
  !.

vdb:copy_graph_asset(Key, TargetName, Directory) :-
  ( current_predicate(config:graph_asset_source/2),
    config:graph_asset_source(Key, Source),
    exists_file(Source)
  ->
    atomic_list_concat([Directory,'/',TargetName], Target),
    % Overwrite to keep assets in sync when updating a graph directory.
    ( exists_file(Target) -> catch(delete_file(Target), _, true) ; true ),
    catch(copy_file(Source, Target), E,
          message:warning(['Failed to copy graph asset ', Source, ' -> ', Target, ' (', E, ')']))
  ; message:warning(['Missing graph asset source for ', Key, ' (or file not found)'])
  ).


% -----------------------------------------------------------------------------
%  VDB helpers (diagnostics)
% -----------------------------------------------------------------------------

%! vdb:outdated(+Category, +Name, -Installed, -Latest)
%
% True when the installed vdb repository (`pkg`) contains Category/Name at an
% older version than the newest acceptable candidate in the portage repository.
%
% This is meant as a small diagnostic to help validate --deep behaviour.
%
% Example:
%   ?- vdb:outdated('dev-libs',openssl, Installed, Latest).
%   Installed = pkg://'dev-libs/openssl-3.5.0',
%   Latest    = portage://'dev-libs/openssl-3.5.4'.
%
vdb:outdated(Category, Name, pkg://InstalledEntry, portage://LatestEntry) :-
  cache:ordered_entry(pkg, InstalledEntry, Category, Name, InstalledVer),
  preference:accept_keywords(K),
  once(query:search([repository(portage),category(Category),name(Name),keywords(K),version(LatestVer)],
                    portage://LatestEntry)),
  compare(>, LatestVer, InstalledVer).

