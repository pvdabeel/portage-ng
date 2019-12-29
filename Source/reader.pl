/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2020, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> READER
The reader reads:

- repository cache metadata
- repository manifest metadata

Input:  An antry in a repository cache or a full path to a manifest file..
Output: A nested list of character codes, each sublist represents a line.
*/

:- module(reader, []).

% *******************
% READER declarations
% *******************


%! reader:invoke(+Cache, +Entry, -Contents)
%
% Cache: The full path of the cache.
% Entry: The cache entry to read.
%
% Contents: A nested list of character codes, each sublist represents a line of
%           the cache entry

reader:invoke(Cache,Entry,Contents) :-
  os:compose_path(Cache,Entry,File),
  exists_file(File),
  open(File,read,Stream,[lock(none)]),
  reader:read_lines(Stream,Contents),
  close(Stream).


%! reader:invoke(+Manifest, -Contents)
%
% Manifest: The full path to a manifest file.
%
% Contents: A nested list of character codes, each sublist represents a line of
%           the manifest file

reader:invoke(Manifest,Contents) :-
  exists_file(Manifest),!,
  open(Manifest,read,Stream,[lock(none)]),
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


%! reader:read_timestamp(+File, -Time)
%
% Given a timestamp file, reads the timestamp inside this file.

reader:read_timestamp(File,Time) :-
  exists_file(File),
  open(File,read,Stream,[lock(none)]),
  reader:read_lines(Stream,[Line|_]),
  phrase(eapi:timestamp(Codes),Line,_),
  close(Stream),
  number_codes(Time,Codes).


%! reader:test(+Repository)
%
% Predicate tests whether all cache entries belonging to a given repository
% instance can be read correctly.
%
% Repository: The repository instance from which to read all cache entries.

reader:test(Repository) :-
  Repository:get_cache(C),
  time(forall(Repository:entry(E),
               (reader:invoke(C,E,_);(message:failure(E)))
	     )),
  Repository:get_size(S),!,
  message:inform(['read ',S,' ',Repository,' entries.']).
