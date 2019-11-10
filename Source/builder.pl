% ********************
% BUILDER declarations
% ********************


builder:execute(Plan) :-
  forall(member(E,Plan),
    (write(' -  STEP:  | '),builder:firststep(E))).

builder:firststep([]) :-  nl, !.

builder:firststep([rule(Context://E:Action,_)|L]) :-
  !,
  message:color(green),
  write(Context://E),
  message:color(blue),
  write(' '),
  write(Action),
  message:color(normal),
  builder:build(Context://E:Action),
  nl,
  builder:nextstep(L).

builder:firststep([rule(_,_)|L]) :-
  builder:firststep(L).


builder:nextstep([]) :- nl,!.

builder:nextstep([rule(Context://E:Action,_)|L]) :- 
  !,
  write('           | '),
  message:color(green),
  write(Context://E),
  message:color(blue),
  write(' '),
  write(Action),
  message:color(normal),
  builder:build(Context://E:Action),
  nl,
  builder:nextstep(L).

builder:nextstep([rule(_,_)|L]) :- 
  builder:nextstep(L).


builder:build(Context://Entry:_Action) :-
  Context:get_type('eapi'),!,
  portage:get_location(L),
  portage:ebuild(Entry,Category,Package,Version),
  atomic_list_concat(['ebuild ',L,'/',Category,'/',Package,'/',Package,'-',Version,'.ebuild install qmerge clean'],Cmd),
  shell(Cmd),!.


builder:build(Context://_Entry:_Action) :-
  Context:get_type('cmake'),!,
  Context:get_location(Local),
  script:exec(build,[Local]).


builder:test(Repository) :-
  system:time(
              system:forall(cache:entry(Repository,E,_,_,_,_,_),
 	                    ((nl,message:header(["Building ",Repository://E]),
                              prover:prove(Repository://E:install,[],Proof,[],_),
			      planner:plan(Proof,[],[],Plan),
                              builder:execute(Plan));
			     (message:failure(E)))
                           )
             ),
  system:findall(E,Repository:entry(E),L),
  system:length(L,H),
  system:write('% built plan for '),system:write(H),system:write(' cache entries.\n').
