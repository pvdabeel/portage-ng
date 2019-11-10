% ********************
% PLANNER declarations
% ********************

% Given a proof, consider it as graph, apply the following algorithm,
% based on topological sort:
%
% 1. For each rule, determine weight
% 2. Filter out rules with zero weight
% 3. Continue weighting until there are no more edges in the graph

planner:notpart(ListA,ListB,El) :-
	member(El,ListA),
	not(member(El,ListB)).

planner:zeroweight(ListA,ListB) :-
	findall(El,planner:notpart(ListA,ListB,El),[]).

planner:zerorules([],Weights,Weights,[],[]) :- !.
planner:zerorules([rule(Head,Body)|Rest],ZeroWeights,[Head|TempZeroWeights],[rule(Head,Body)|ZeroRules],NonZeroRules) :-
	planner:zeroweight(Body,ZeroWeights),!,
	planner:zerorules(Rest,ZeroWeights,TempZeroWeights,ZeroRules,NonZeroRules).
planner:zerorules([rule(Head,Body)|Rest],ZeroWeights,TempZeroWeights,ZeroRules,[rule(Head,Body)|NonZeroRules]) :-
	planner:zerorules(Rest,ZeroWeights,TempZeroWeights,ZeroRules,NonZeroRules).


planner:plan([],_,OldPlan,OldPlan) :- !.

planner:plan(Rules,InitialWeights,OldPlan,[ZeroRules|TempPlan]) :-
	planner:zerorules(Rules,InitialWeights,NewWeights,ZeroRules,NonZeroRules),
	planner:plan(NonZeroRules,NewWeights,OldPlan,TempPlan).


planner:test(Repository) :-
  system:time(
              system:forall(cache:entry(Repository,E,_,_,_,_,_),
 	                    ((message:success(E),
                              prover:prove(Repository://E:install,[],Proof,[],_),
			      planner:plan(Proof,[],[],_));
			     (message:failure(E)))
                           )
             ),
  system:findall(E,Repository:entry(E),L),
  system:length(L,H),
  system:write('% created plan for '),system:write(H),system:write(' cache entries.\n').
