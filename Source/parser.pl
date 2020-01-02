/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2020, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> PARSER
The parser provided takes its input from the reader and applies an EAPI-7
compliant DCG grammar to output a parse tree.

Input:  A nested list of character codes codes.
        Each sublist represents a line.
        Each line in a repository cache entry represents a key=value pair.
        Each line in a manifest file represents a key value pair.

Output: A nested list representing the the result of parsing each line in the
        input.
*/

:- module(parser,[]).

% *******************
% PARSER declarations
% *******************


%! parser:invoke(+Type,+Context://+Entry,+Contents,-Result)
%
% Type:     An atom indicated Contents is of type 'metadata' or 'manifest'
% Contents: A nested list of character codes.
%
% Result:   A nested list represnting the parse tree.

parser:invoke(_,_,[], []).
parser:invoke(Type,Context://Entry,[X|XX], [Y|YY]) :-
  eapi:parse(Type,Context://Entry,X,Y),!,
  parser:invoke(Type,Context://Entry,XX, YY).


%! parser:test(+Repository)
%
% Predicate tests whether all cache entries belonging to a given repository
% instance can be succesfully parsed.
%
% Repository: The repository instance from which to parse all entries.
%
% Parses a repository using the default reporting style

parser:test(Repository) :-
  config:test_style(Style),
  parser:test(Repository,Style).


%! parser:test(+Repository,+Style)
%
% Same as parser:test(+Repository), but uses a specified reporting style
% 'single_verbose', 'parallel_verbose' or 'parallel_fast'

parser:test(Repository,single_verbose) :-
  Repository:get_size(S),
  Repository:get_cache(C),
  count:newinstance(counter),
  count:init(0,S),
  config:time_limit(T),
  time(forall(Repository:entry(E),
              (catch(call_with_time_limit(T,(count:increase,
                                             count:percentage(P),
                                             message:title(['Parsing (Single thread): ',P,' complete']),
                                             reader:invoke(C,E,R),
                                             parser:invoke(metadata,Repository://E,R,_),
                                             message:success([P,' - ',E]))),
                     time_limit_exceeded,
                     message:failure([E,' (time limit exceeded)']));
               message:failure(E)))),!,
  message:title_reset,
  message:inform(['parsed ',S,' ',Repository,' entries.']).

parser:test(Repository,parallel_verbose) :-
  Repository:get_size(S),
  Repository:get_cache(C),
  count:newinstance(counter),
  count:init(0,S),
  config:time_limit(T),
  config:number_of_cpus(Cpus),
  findall((catch(call_with_time_limit(T,(parser:invoke(metadata,Repository://E,R,_),!,
                                         with_mutex(mutex,(count:increase,
                                                           count:percentage(P),
                                                           message:title(['Parsing (',Cpus,' threads): ',P,' complete']),
                                                           message:success([P,' - ',E]))))),
                 time_limit_exceeded,
                 message:failure([E,' (time limit exceeded)']))),
          (Repository:entry(E),reader:invoke(C,E,R)),
          Calls),
  time(concurrent(Cpus,Calls,[])),!,
  message:title_reset,
  message:inform(['parsed ',S,' ',Repository,' entries.']).

parser:test(Repository,parallel_fast) :-
  Repository:get_size(S),
  Repository:get_cache(C),
  config:number_of_cpus(Cpus),
  findall((parser:invoke(metadata,Repository://E,R,_),!),
          (Repository:entry(E),reader:invoke(C,E,R)),
          Calls),
  time(concurrent(Cpus,Calls,[])),!,
  message:inform(['parsed ',S,' ',Repository,' entries.']).
