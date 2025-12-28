/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> READER
The reader reads lines from a file.
Input:  A full path to a file
Output: A list of strings, each string represents a line.
*/

:- module(reader, []).

% =============================================================================
%  READER declarations
% =============================================================================

%! reader:invoke(+File, -Contents)
%
% File: The full path of the cache.
%
% Contents: A list of strings, each string represents a line

reader:invoke(Stream, Contents) :-
  is_stream(Stream), !,
  reader:read_lines_to_strings(Stream, Contents),
  close(Stream).

reader:invoke(File, Contents) :-
  exists_file(File), !,
  open(File, read, Stream, [lock(none)]),
  reader:read_lines_to_strings(Stream, Contents),
  close(Stream).

reader:invoke(_, []) :-
  !.


%! reader:read_lines_to_strings(+Stream, -Lines)
%
% Given a stream, reads all lines from the stream and returns them as a list of 
%strings

reader:read_lines_to_strings(Stream, Lines) :-
  system:read_line_to_string(Stream, L),
  ( L == end_of_file
    ->  Lines = []
    ;   Lines = [L|Rest],
        reader:read_lines_to_strings(Stream, Rest) ).

%! reader:read_lines_to_codes(+Stream, -Lines)
%
% Retained for compatibility with code expecting character codes
% Given a stream, reads all lines from the stream and returns as a list of codes

reader:read_lines_to_codes(Stream, Lines) :-
  system:read_line_to_codes(Stream, L),
  ( L == end_of_file
    ->  Lines = []
    ;   Lines = [L|Rest],
        reader:read_lines_to_codes(Stream, Rest)
    ).

%! reader:test(+Repository)
%
% Predicate tests whether all cache entries belonging to a given repository
% instance can be read correctly.
%
% Repository: The repository instance from which to read all cache entries.

reader:test(Repository) :-
  time(forall(Repository:get_cache_file(E, C),
              (reader:invoke(C, _); (message:failure(E)))
            )),
  Repository:get_size(S), !,
  message:inform(['read ', S, ' ', Repository, ' entries.']).
