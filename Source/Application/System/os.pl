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

%! os:ensure_directory_path(+Directory)
%
% Create Directory and missing parents (mkdir -p).
% Wrapper around library(filesex):make_directory_path/1.

os:ensure_directory_path(Directory) :-
  catch(filesex:make_directory_path(Directory), _, true).


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

%! os:find_files(+Dir, +Pattern, -File) is nondet.
%
% Non-deterministically unify File with regular files under Dir whose
% names match the glob Pattern. Follows no symlinks.

os:find_files(Dir, Pattern, File) :-
  directory_member(Dir, File,
                   [ recursive(true),
                     follow_links(false),
                     file_type(regular),
                     matches(Pattern)
                   ]).


% -----------------------------------------------------------------------------
%  System load average
% -----------------------------------------------------------------------------

%! os:current_load_average(-Load) is det.
%
% Reads the 1-minute system load average. Uses sysctl on macOS,
% /proc/loadavg on Linux. Returns 0.0 on failure.

os:current_load_average(Load) :-
  ( current_prolog_flag(apple, true)
  -> os:load_average_darwin(Load)
  ;  os:load_average_linux(Load)
  ).


%! os:load_average_darwin(-Load) is det.
%
% Reads the 1-minute load average on macOS via sysctl.

os:load_average_darwin(Load) :-
  catch(
    ( setup_call_cleanup(
        process_create(path(sysctl), ['-n', 'vm.loadavg'],
                       [stdout(pipe(Out))]),
        read_string(Out, _, S),
        close(Out)
      ),
      split_string(S, " ", "{ }\n", Parts),
      Parts = [LoadStr|_],
      number_codes(Load, LoadStr)
    ),
    _,
    Load = 0.0
  ).


%! os:load_average_linux(-Load) is det.
%
% Reads the 1-minute load average on Linux from /proc/loadavg.

os:load_average_linux(Load) :-
  catch(
    ( setup_call_cleanup(
        open('/proc/loadavg', read, In),
        read_string(In, _, S),
        close(In)
      ),
      split_string(S, " ", "\n", Parts),
      Parts = [LoadStr|_],
      number_codes(Load, LoadStr)
    ),
    _,
    Load = 0.0
  ).