/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2024, Pieter Van den Abeele

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
  exists_directory(Directory),
  system:directory_files(Directory,UnsortedContents),!,
  sort(UnsortedContents,['.','..'|Contents]),
  lists:member(Content,Contents).


%! os:compose_path(+Path,+RelativePath,-NewPath)
%
% Given a path (relative or absolute) and a relative path, composes a
% new path by combining both paths and a separator.

os:compose_path(Path,RelativePath,NewPath) :-
  atomic_list_concat([Path,'/',RelativePath],NewPath).


%! os:compose_path(+List,-Path)
%
% Given a list of path components, composes a new path by combining
% path segments using correct OS seperator

os:compose_path(List,Path) :-
  atomic_list_concat(List,'/',Path).
