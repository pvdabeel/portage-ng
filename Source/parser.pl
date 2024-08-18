/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2024, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> PARSER
The parser takes its input from the reader and applies an EAPI-7 compliant DCG
grammar to output a parse tree.

Input:  A nested list of character codes codes.
        Each sublist represents a line.
        Each line in a repository cache entry represents a 'key=value' pair.
        Each line in a manifest file represents a 'key value' pair.

Output: A nested list representing the the result of parsing each line in the
        input.
*/

:- module(parser,[]).

% *******************
% PARSER declarations
% *******************


%! parser:invoke(+Type,+Repository://+Entry,+Contents,-Result)
%
% Type:     An atom indicated Contents is of type 'metadata' or 'manifest'.
%
% Contents: A nested list of character codes.
%
% Result:   A nested list represnting the parse tree.

parser:invoke(_,_,[],[]).

parser:invoke(Type,Repository://Entry,[Line|Lines],[KeyValue|KeyValues]) :-
  phrase(eapi:keyvalue(Type,Repository://Entry,KeyValue),Line),!,
  parser:invoke(Type,Repository://Entry,Lines,KeyValues).


%! parser:test(+Repository)
%
% Predicate tests whether all cache entries belonging to a given repository
% instance can be succesfully parsed.
%
% Repository: The repository instance from which to parse all entries.
%
% Parses a repository using the default reporting style.

parser:test(Repository) :-
  config:test_style(Style),
  parser:test(Repository,Style).


%! parser:test(+Repository,+Style)
%
% Same as parser:test(+Repository), but uses a specified reporting style
% 'single_verbose', 'parallel_verbose' or 'parallel_fast'.

parser:test(Repository,Style) :-
  tester:test(Style,
              'Parsing',
              Repository://Entry,
              (Repository:get_cache_file(Entry,File),reader:invoke(File,Codes)),
              (parser:invoke(metadata,Repository://Entry,Codes,_))),!.
