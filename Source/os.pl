/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2020, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> OS
This file contains predicates used to interact with the operating system
Goal is to get the same behaviour across different platform.
Eventually this could become a class with different subclasses.
*/

:- module(os, []).

% ***************
% OS declarations
% ***************


%! os:directory_content(+Directory,-Content)
%
% For a given directory, returns an alphabetical list containing the
% content of the directory. Special contents (like '.' and '..') is
% filtered.

os:directory_content(Directory,Content) :-
  system:directory_files(Directory,UnsortedContents),!,
  sort(UnsortedContents,['.','..'|Contents]),
  member(Content,Contents).


%! os:compose_path(+Path,+RelativePath,-NewPath)
%
% Given a path (relative or absolute) and a relative path, composes a
% new path by combining both paths and a separator.

os:compose_path(Path,RelativePath,NewPath) :-
  atomic_list_concat([Path,'/',RelativePath],NewPath).


%! os:make_repository_dirs(+Repository,+Directory)
%
% Given a prolog repository, creates a directory with subdirs
% corresponding to the categories within the prolog repository

os:make_repository_dirs(Repository,Directory) :-
  system:make_directory(Directory),
  forall(Repository:category(C),
    (os:compose_path(Directory,C,Subdir),
     system:make_directory(Subdir))).


%! os:installed_pkg(+Entry)
%
% Retrieves installed packages on the system (cached)

os:installed_pkg(Repository://Entry) :-
  cache:entry_metadata(Repository,Entry,installed,true).


%! os:sync
%
% Syncs the installed packages to prolog metadata

os:sync :-
  retractall(cache:entry_metadata(portage,_,installed,_)),
  forall(os:find_installed_pkg(portage://Entry),
         (asserta(cache:entry_metadata(portage,Entry,installed,true)))).
          %message:scroll([Entry]))),
	  %message:inform(['Updated system package database']).


%! os:installed_pkg(+Entry)
%
% Retrieves installed packages on the system

os:find_installed_pkg(portage://Entry) :-
  config:pkg_directory(Directory),
  os:directory_content(Directory,Category),
  os:compose_path(Directory,Category,CategoryDir),
  os:directory_content(CategoryDir,Package),
  os:compose_path(Category,Package,Entry).


%! os:update_repository_dirs(+Repository,+Directory)
%
% Given a prolog repository, creates a directory with subdirs
% corresponding to the categories within the prolog repository

os:update_repository_dirs(Repository,Directory) :-
  forall(Repository:category(C),
    (os:compose_path(Directory,C,Subdir),
     (system:exists_directory(Subdir);
     system:make_directory(Subdir)))).
