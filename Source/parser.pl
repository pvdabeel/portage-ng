/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2021, Pieter Van den Abeele

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

parser:invoke(Type,Repository://Entry,[X|XX],[Y|YY]) :-
  eapi:parse(Type,Repository://Entry,X,Y),!,
  parser:invoke(Type,Repository://Entry,XX,YY).


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

parser:test(Repository,single_verbose) :-
  Repository:get_size(S),
  Repository:get_cache(C),
  stats:newinstance(stat),
  stats:init(0,S),
  config:time_limit(T),
  time(forall(Repository:entry(E),
              (catch(call_with_time_limit(T,(stats:increase,
                                             stats:percentage(P),
                                             stats:runningtime(Min,Sec),
                                             message:title(['Parsing (Single thread): ',P,' processed in ',Min,'m ',Sec,'s']),
                                             reader:invoke(C,E,R),
                                             parser:invoke(metadata,Repository://E,R,_),
                                             message:success([P,' - ',E]))),
                     time_limit_exceeded,
                     message:failure([E,' (time limit exceeded)']));
               message:failure(E)))),!,
  stats:runningtime(Min,Sec),
  message:title_reset,
  message:inform(['parsed ',S,' ',Repository,' entries in ',Min,'m ',Sec,'s.']).

parser:test(Repository,parallel_verbose) :-
  Repository:get_size(S),
  Repository:get_cache(C),
  stats:newinstance(stat),
  stats:init(0,S),
  config:time_limit(T),
  config:number_of_cpus(Cpus),
  findall((catch(call_with_time_limit(T,(parser:invoke(metadata,Repository://E,R,_),!,
                                         with_mutex(mutex,(stats:increase,
                                                           stats:percentage(P),
                                                           stats:runningtime(Min,Sec),
                                                           message:title(['Parsing (',Cpus,' threads): ',P,' processed in ',Min,'m ',Sec,'s']),
                                                           message:success([P,' - ',E]))))),
                 time_limit_exceeded,
                 message:failure([E,' (time limit exceeded)']));
           message:failure(E)),
          (Repository:entry(E),reader:invoke(C,E,R)),
          Calls),!,
  time(concurrent(Cpus,Calls,[])),
  stats:runningtime(Min,Sec),
  message:title_reset,!,
  message:inform(['parsed ',S,' ',Repository,' entries in ',Min,'m ',Sec,'s.']).

parser:test(Repository,parallel_fast) :-
  Repository:get_size(S),
  Repository:get_cache(C),
  stats:newinstance(stat),
  stats:init(0,S),
  config:number_of_cpus(Cpus),
  findall((parser:invoke(metadata,Repository://E,R,_),!;
           message:failure(E)),
          (Repository:entry(E),reader:invoke(C,E,R)),
          Calls),
  time(concurrent(Cpus,Calls,[])),
  stats:runningtime(Min,Sec),!,
  message:inform(['parsed ',S,' ',Repository,' entries in ',Min,'m ',Sec,'s.']).
