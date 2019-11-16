/*                                                                              
  Author:   Pieter Van den Abeele                                               
  E-mail:   pvdabeel@mac.com                                                    
  Copyright (c) 2005-2019, Pieter Van den Abeele                                
                                                                                
  Distributed under the terms of the LICENSE file in the root directory of this 
  project.                                                                      
*/                                                                              
                                                                                
                                                                                
/** <module> PRINTER                                                          
The Printer takes a plan from the Planner and pretty prints it.                      
*/     

:- module(printer, []).

% ********************
% PRINTER declarations
% ********************


%! printer:print(+Plan)
%
% Print a given plan

printer:print(Plan) :-
  forall(member(E,Plan),
    (write(' -  STEP:  | '),printer:firststep(E))).


%! printer:firststep(+Step)
%
% Print a step in a plan

printer:firststep([]) :-  nl, !.

printer:firststep([rule(Context://E:Action,_)|L]) :-
  !,
  message:color(green),
  write(Context://E),
  message:color(blue),
  write(' '),
  write(Action),
  message:color(normal),
  nl,
  printer:nextstep(L).

printer:firststep([rule(_,_)|L]) :-
  printer:firststep(L).


%! printer:nextstep(+Step)
%
% Print a step in a plan

printer:nextstep([]) :- nl,!.

printer:nextstep([rule(Context://E:Action,_)|L]) :- 
  !,
  write('           | '),
  message:color(green),
  write(Context://E),
  message:color(blue),
  write(' '),
  write(Action),
  message:color(normal),
  nl,
  printer:nextstep(L).

printer:nextstep([rule(_,_)|L]) :- 
  printer:nextstep(L).


%! printer:test(+Repository)
%
% Proves and prints every entry in a given repository

printer:test(Repository) :-
  system:time(
              system:forall(cache:entry(Repository,E,_,_,_,_,_),
 	                    ((nl,message:header(["Planning ",Repository://E]),
                              prover:prove(Repository://E:install,[],Proof,[],_),
			      planner:plan(Proof,[],[],Plan),
                              printer:print(Plan));
			     (message:failure(E)))
                           )
             ),
  system:findall(E,Repository:entry(E),L),
  system:length(L,H),
  system:write('% printed plan for '),system:write(H),system:write(' cache entries.\n').

