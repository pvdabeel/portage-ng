/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> OS
This file contains predicates used to interact with the operating system
Goal is to get the same behaviour across different platform.
Eventually this could become a class with different subclasses.
*/

:- module(os, []).

% =============================================================================
%  OS declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Path operations
% -----------------------------------------------------------------------------

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


% -----------------------------------------------------------------------------
%  Directory operations
% -----------------------------------------------------------------------------

%! os:make_directory(+Directory)
%
% Makes a directory if it doesn't exist already

os:make_directory(Directory) :-
  catch(system:make_directory(Directory),
        _,
        true).


%! os:contains(+File,+Directory)
%
% Check whether a given directory contains a file

os:contains(File,Directory) :-
  catch((exists_directory(Directory),
         os:compose_path(Directory,File,Path),
         exists_file(Path)),
        _,
        false).


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


% -----------------------------------------------------------------------------
%  Finding files
% -----------------------------------------------------------------------------

find_files(Dir, Pattern, File) :-
  directory_member(Dir, File,
                   [ recursive(true),
                     follow_links(false),
                     file_type(regular),
                     matches(Pattern)
                   ]).

% -----------------------------------------------------------------------------
%  Bash wrappers
% -----------------------------------------------------------------------------

%! os:bash_dns_sd(+ArgList,-Lines)
%
% Calls dns-sd command in bash with given ArgList
% Returns lines of strings (output of the command)

os:bash_dns_sd(ArgList, Lines) :-
  atomic_list_concat(['dns-sd'|ArgList],' ',Cmd),
  os:bash_lines(Cmd,Lines).


%! os:bash_lines(+Cmd,-Lines)
%
% Runs a given command in bash
% Returns lines of strings (output of the command)

os:bash_lines(Cmd, Lines) :-
  process_create(path(bash),['-c',Cmd],[stdout(pipe(Out)),process(Pid)]),
  call_cleanup(reader:read_lines_to_strings(Out,Lines),(close(Out),process_wait(Pid,_))).
