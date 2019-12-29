/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2020, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> PARSER
The DCG parser provided is capable of parsing EAPI-6.0 compliant
information about ebuilds. This information is found in the cache
of a portage repository, which is read by the provided reader
and presented to the parser for parsing.

Input:  Contents is a nested list of codes.
        Each sublist represents a line.
        Each line represents a specific cache element.
        (Cfr. eapi for the key-value structure of these elements.)

Output: A nested list containing the result of parsing each
        corresponding element from the input.
*/

:- module(parser,[]).

% *******************
% PARSER declarations
% *******************


%! parser:invoke(+Type,+Contents,-Result)
%
% Type: metadata or manifest
% Contents: A nested list of codes.
% Result: A prolog predicate representing the metadata.

% parser:invoke(Contents,Metadata) :-
   % maplist(eapi:parse,Contents,Metadata).

parser:invoke(_,[], []).
parser:invoke(Type,[X|XX], [Y|YY]) :-
  eapi:parse(Type,X,Y),
  parser:invoke(Type,XX, YY).


%! parser:test(+Repository)
%
% Parses a repository using the default reporting style

parser:test(Repository) :-
  config:test_style(Style),
  parser:test(Repository,Style).


%! parser:test(+Repository,+Style)
%
% Predicate tests whether all repository entries can be succesfully parsed.
% Repository: The repository from which to parse all entries.

parser:test(Repository,single_verbose) :-
  Repository:get_size(S),
  Repository:get_cache(C),
  count:newinstance(counter),
  count:init(0,S),
  config:time_limit(T),
  time(forall(Repository:entry(E),
              (catch(call_with_time_limit(T,(count:increase,
                                             count:percentage(P),
                                             reader:invoke(C,E,R),
                                             parser:invoke(metadata,R,_),
                                             message:success([P,' - ',E]))),
                     time_limit_exceeded,
                     message:failure([E,' (time limit exceeded)']));
               message:failure(E)))),!,
  message:inform(['parsed ',S,' ',Repository,' entries.']).


parser:test(Repository,parallel_verbose) :-
  Repository:get_size(S),
  Repository:get_cache(C),
  count:newinstance(counter),
  count:init(0,S),
  config:time_limit(T),
  config:number_of_cpus(Cpus),
  findall((catch(call_with_time_limit(T,(parser:invoke(metadata,R,_),!,
                                         with_mutex(mutex,(count:increase,
                                                           count:percentage(P),
                                                           message:success([P,' - ',E]))))),
                 time_limit_exceeded,
                 message:failure([E,' (time limit exceeded)']))),
          (Repository:entry(E),reader:invoke(C,E,R)),
          Calls),
  time(concurrent(Cpus,Calls,[])),!,
  message:inform(['parsed ',S,' ',Repository,' entries.']).


parser:test(Repository,parallel_fast) :-
  Repository:get_size(S),
  Repository:get_cache(C),
  config:number_of_cpus(Cpus),
  findall((parser:invoke(metadata,R,_),!),
          (Repository:entry(E),reader:invoke(C,E,R)),
          Calls),
  time(concurrent(Cpus,Calls,[])),!,
  message:inform(['parsed ',S,' ',Repository,' entries.']).
