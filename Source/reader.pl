/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2021, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> READER
The reader reads lines from a file.
Input:  An full path to a file
Output: A nested list of character codes, each sublist represents a line.
*/

:- module(reader, []).

% *******************
% READER declarations
% *******************


%! reader:invoke(+File, -Contents)
%
% File: The full path of the cache.
%
% Contents: A nested list of character codes, each sublist represents a line

reader:invoke(File,Contents) :-
  exists_file(File),!,
  open(File,read,Stream,[lock(none)]),
  reader:read_lines(Stream,Contents),
  close(Stream).

reader:invoke(_,[]) :-
  !.


%! reader:read_lines(+Stream, -Lines)
%
% Given a stream, reads all lines from the stream.

reader:read_lines(Stream,[]) :-
  at_end_of_stream(Stream),
  !.

reader:read_lines(Stream,[L|R]) :-
  % not(at_end_of_stream(Stream)),
  !,
  read_line_to_codes(Stream,L),
  reader:read_lines(Stream,R).


%! reader:test(+Repository)
%
% Predicate tests whether all cache entries belonging to a given repository
% instance can be read correctly.
%
% Repository: The repository instance from which to read all cache entries.

reader:test(Repository) :-
  time(forall(Repository:get_cache_file(E,C),
               (reader:invoke(C,_);(message:failure(E)))
	     )),
  Repository:get_size(S),!,
  message:inform(['read ',S,' ',Repository,' entries.']).
