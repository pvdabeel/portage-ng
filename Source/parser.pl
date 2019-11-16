/*                                                                              
  Author:   Pieter Van den Abeele                                               
  E-mail:   pvdabeel@mac.com                                                    
  Copyright (c) 2005-2019, Pieter Van den Abeele                                
                                                                                
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


%! parser:invoke(+Contents,-Result)
%
% Contents: A nested list of codes. 
% Result: A prolog predicate representing the metadata.

% parser:invoke(Contents,Metadata) :-
   % maplist(eapi:parse,Contents,Metadata).

parser:invoke([], []). 
parser:invoke([X|XX], [Y|YY]) :- 
  eapi:parse(X,Y),
  parser:invoke(XX, YY). 


%! parser:test(+Repository)
%
% Predicate tests whether all repository entries can be succesfully parsed.
% Repository: The repository from which to parse all entries.

parser:test(Repository) :-
  Repository:get_cache(C),
  findall(parser:invoke(R,_),(Repository:entry(E),reader:invoke(C,E,R)),Calls),
  current_prolog_flag(cpu_count,Cpus),
  time(concurrent(Cpus,Calls,[])),
  %time(forall(Repository:entry(E),
  %            (%writeln(E),
  %            reader:invoke(C,E,R),parser:invoke(R,_);message:failure(E),true))
  %    ),
  Repository:get_size(S), 
  message:inform(['parsed ',S,' cache entries.']).

