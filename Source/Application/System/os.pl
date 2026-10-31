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
% new path by combining both with exactly one separator, whether or not
% Path already ends in one. This is the single filesystem path join of
% the code base.

os:compose_path(Path,RelativePath,NewPath) :-
  directory_file_path(Path,RelativePath,NewPath).


%! os:compose_path(+List,-Path)
%
% Given a non-empty list of path components, composes a new path by
% joining the components left to right.

os:compose_path([First|Rest],Path) :-
  foldl(os:append_path_component,Rest,First,Path).


%! os:append_path_component(+Component,+Path,-NewPath)
%
% foldl/4 step for os:compose_path/2.

os:append_path_component(Component,Path,NewPath) :-
  directory_file_path(Path,Component,NewPath).


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
% /proc/loadavg on Linux. Returns 0.0 on failure (or when the raw value
% cannot be parsed).

os:current_load_average(Load) :-
  catch(
    ( os:load_average_raw(S),
      split_string(S, " ", "{ }\n", [LoadStr|_]),
      number_string(Load, LoadStr)
    ),
    _,
    Load = 0.0
  ).


%! os:load_average_raw(-String) is det.
%
% Fetches the raw load-average line from the platform source: sysctl
% vm.loadavg on macOS, /proc/loadavg on Linux. The 1-minute average is
% the first whitespace-delimited field of the returned string.

:- if(current_prolog_flag(apple, true)).

os:load_average_raw(S) :-
  setup_call_cleanup(
    process_create(path(sysctl), ['-n', 'vm.loadavg'], [stdout(pipe(Out))]),
    read_string(Out, _, S),
    close(Out)
  ).

:- else.

os:load_average_raw(S) :-
  setup_call_cleanup(
    open('/proc/loadavg', read, In),
    read_string(In, _, S),
    close(In)
  ).

:- endif.
