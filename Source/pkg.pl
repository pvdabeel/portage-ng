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


