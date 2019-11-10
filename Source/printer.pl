% ********************
% PRINTER declarations
% ********************

% Pretty print a build plan

printer:print(Plan) :-
  forall(member(E,Plan),
    (write(' -  STEP:  | '),printer:firststep(E))).

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

