/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2024, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> UNIFY
Non-Destructive Feature Unification
*/

:- module(feature_unification, [unify/3]).

% --------------------------------
% FEATURE_UNIFICATION declarations
% --------------------------------


%! feature_unification:unify(+FeatureTerm,+FeatureTerm,-FeatureTerm)
%
% Non-destructive Feature Unification

feature_unification:unify(F1,F2,F3) :-
  feature_unification:hunify(F1,F2,S1,U1),
  feature_unification:hunify(F2,F1,S2,_),
  append(S1,S2,S12),
  append(U1,S12,F3).

% Note: U1 == U2 but S1 != S2


%! feature_unification:hunify(+FeatureTerm,+FeatureTerm,-Skipped,-Unified)
%
% Horizontal Unification
%
% Given two feature terms, exposes each of the Feature-Value pairs
% in the first term to the second term. Two lists are returned.
% One contains the features from the first feature term that
% were feature unified, the other contains the feature
% terms that were skipped.

feature_unification:hunify([Fp|R],F2,S,U) :-
  feature_unification:vunify(Fp,F2,S1,U1),
  feature_unification:hunify(R,F2,S2,U2),
  append(S1,S2,S),
  append(U1,U2,U).

feature_unification:hunify([],_,[],[]).


%! feature_unification:val(+Value,+Value,-Value)
%
% Responsible for unifying the values of two features.
% We rely on prolog unification to bind literals to variables
%
% We extended regular feature logic with multi-valued features and
% open features, complements are implemented using top and bottom.
%
%
% These rules include a number of cuts. I left the code that makes
% them green cuts commented out for efficiency reasons. This
% effectively makes them red, so watch out when changing this rule.


% -----------------------
% CASE 1 : "default" rule
% -----------------------

feature_unification:val(V,V,V) :- !.            	% green cut, all other cases
			          			% should exclude this case

% -------------------------
% CASE 2 : rule {..} x {..}
% -------------------------

feature_unification:val({V1},{V2},{V3}) :-
  % not(V1 == V2),                			% excludes rule 1
  !,			          			% green cut
  intersection(V1,V2,V3),
  not(empty(V3)).                 			% Consistency: {..} cannot be empty


% --------------------------
% CASE 3a : rule [..] x [..]
% --------------------------

feature_unification:val([V1|V1r],[V2|V2r],V3) :-      	% rule 2
  % not([V1|V1r] == [V2|V2r]),    			% rule 1
  !,                              			% green cut
  feature_unification:unify([V1|V1r],[V2|V2r],V3).


% --------------------------
% CASE 4a : rule [..] x {..}
% --------------------------

feature_unification:val([V1|V1r],{V2},{V2}) :- 	  	% rules 1,2 and 3
  !,				  			% green cut
  subset([V1|V1r],V2),
  subset(V2,[V1|V1r]).		  			% V2 cannot be inconsistent


% ------------------------
% CASE 4b : rule [] x {..}	  			% subset of the universe
% ------------------------

feature_unification:val([],{V2},{V2}) :-
  !,
  not(empty(V2)).


% --------------------------
% CASE 5a : rule {..} x [..]
% --------------------------

feature_unification:val({V1},[V2|V2r],{V1}) :-	  	% rules 1,2,3 and 4
  !,				  			% green cut
  subset([V2|V2r],V1),
  subset(V1,[V2|V2r]).		  			% V2 cannot be inconsistent


% ------------------------
% CASE 5b : rule {..} x []
% ------------------------

feature_unification:val({V1},[],{V1}) :- !.		% subset of the universe



% -------------------------
% CASE 6 : rule '..' x [..]
% -------------------------

feature_unification:val(V1,[V2|V2r],V3) :-		% rules 2 and 4
  % not(is_list(V1)),             			% rules 1 and 3
  % not(V1 =.. [ {} | _ ]),       			% rule 5
  !,				  			% green cut
  feature_unification:unify([V1],[V2|V2r],V3).


% -------------------------
% CASE 7 : rule [..] x '..'
% -------------------------

feature_unification:val([V1|V1r],V2,V3) :-		% rules 2 and 5
  % not(is_list(V2)),		  			% rules 1, 3 and 6
  % not(V1 =.. [ {} | _ ]),       			% rule 4
  !,				  			% green cut
  feature_unification:unify([V1|V1r],[V2],V3).


% -------------------------
% CASE 8 : rule '..' x {..}
% -------------------------

feature_unification:val(V1,{V2},V3) :-          	% rules 3, 5 and 6
  % not(V1 =.. [ {} | _ ]),       			% rules 1 and 2
  % not(is_list(V1)),		  			% rules 4 and 7
  !,                              			% green cut
  intersection([V1],V2,[V3]),
  not(empty(V3)).		  			% Consistency: {..} cannot be empty


% -------------------------
% CASE 9 : rule {..} x '..'
% -------------------------

feature_unification:val({V1},V2,V3) :-		  	% rules 3, 4 and 7
  % not(V2 =.. [ {} | _ ]),       			% rules 1, 2 and 4
  % not(is_list(V2)),		  			% rules 5 and 6
  !,				  			% green cut
  intersection(V1,[V2],[V3]),
  not(empty(V3)).		  			% Consistency: {..} cannot be empty

empty([]) :-!.

%! vunify(-FeaturePair,-FeatureTerm,Skipped,Unified)
%
% Vertical Unification
%
% A feature pair is exposed to each feature pair in a feature term
% and categorized as skipped or unified (but not both once). If the pair unified
% with at least one other feature pair then then pair with its new value is
% returned as 'unified'. Otherwise it is returned as 'skipped'.
% Skipped and Unified are either an empty list or a singleton.
%
% Code that makes the cuts green has been uncommented for efficiency, watch
% out when changing this rule.

% -------------------------------------------------
% CASE 1a : feature:value pair requires unification
% -------------------------------------------------

feature_unification:vunify(F:V1,[F:V2|R],[],U) :-
  !,				  			% green cut
  feature_unification:val(V1,V2,Vu),
  feature_unification:vunify(F:Vu,R,[],U).	  	% From now on Skipped shall be empty because we have
			 	  			% detected at least one unification so far.

% ---------------------------------------------------------
% CASE 1b : feature:value pair does not require unification
% ---------------------------------------------------------

feature_unification:vunify(F1:V1,[_:_|R],S,U) :-
  % not( F1 == F2 ),		  			% rule 1a
  !,				  			% green cut
  feature_unification:vunify(F1:V1,R,S,U).	  	% Skipped remains unchanged


% -----------------------------------------------------------------
% CASE 2a : not a feature:value pair, but would require unification
% -----------------------------------------------------------------

feature_unification:vunify(Nocolon,[Nocolon|R],[],U) :-
  % not( Nocolon =.. [ ':' | _ ] ),			% rules 1a and 1b
  !,							% green cut
  feature_unification:vunify(Nocolon,R,[],U).		% cfr. 1a


% -----------------------------------------------------------------
% CASE 2b : not a feature:value pair, would not require unification
% -----------------------------------------------------------------

feature_unification:vunify(Nocolon,[_|R],S,U) :-
  % not( Nocolon == Nocolon2 ),				% rules 1a, 1b and 2a
  !,							% green cut
  feature_unification:vunify(Nocolon,R,S,U).		% cfr. 2a


% -----------------------------------------------------------
% CASE 3a : Nothing to unify against, no earlier unifications
% -----------------------------------------------------------

feature_unification:vunify(F,[],[F],[]) :- !.


% -----------------------------------------------------------------
% CASE 3b : Nothing to unify against, earlier unifications detected
% -----------------------------------------------------------------

feature_unification:vunify(F,[],[],[F]) :- !.



% TESTS

feature_unification:unify_test1 :- feature_unification:unify([],[],Result),
  Result == [].

feature_unification:unify_test2 :- feature_unification:unify([a:foo],[],Result),
  Result == [a:foo].

feature_unification:unify_test3 :- feature_unification:unify([],[a:foo],Result),
  Result == [a:foo].

feature_unification:unify_test4 :- feature_unification:unify([a:foo],[a:foo],Result),
  Result == [a:foo].

feature_unification:unify_test5 :- feature_unification:unify([a:{[1,2,5]}],[a:{[1,4,3,5]}],Result),
  Result == [a:{[1,5]}].

feature_unification:unify_test6 :- feature_unification:unify([a:[1,2,3]],[a:[4,5,6]],Result),
  Result == [a:[1,2,3,4,5,6]].

feature_unification:unify_test7 :- feature_unification:unify([a:foo],[a:X],Result),
  Result == [a:foo], X == foo.

feature_unification:unify_test8 :- feature_unification:unify([a:X],[a:foo],Result),
  Result == [a:foo], X == foo.

feature_unification:unify_test9 :- feature_unification:unify([a:X],[a:X],Result),
  Result == [a:X],var(X).

feature_unification:unify_test10 :- feature_unification:unify([a:X],[a:{[1,2,3]}],Result),
  Result == [a:{[1,2,3]}], X == {[1,2,3]}.

feature_unification:unify_test11 :- feature_unification:unify([a:X],[a:[1,2,3]],Result),
  Result == [a:[1,2,3]], X == [1,2,3].

feature_unification:unify_test12 :- feature_unification:unify([a:foo],[a:{[foo,bar]}],Result),
  Result == [a:foo].

feature_unification:unify_test13 :- feature_unification:unify([a:foo],[a:[cow,bar]],Result),
  Result == [a:[foo,cow,bar]].

feature_unification:unify_test14 :- feature_unification:unify([object:[kde],arts:{[true,false]},exists(qt):[object:[qt],mt:false]],[object:[kmail],exists(qt):[object:[qt],specialpatch:true]],Result),
  Result == [object:[kde, kmail], exists(qt):[object:[qt], mt:false, specialpatch:true], arts:{[true, false]}].

feature_unification:unify_test15 :- feature_unification:unify([a:foo,b:bar,c:cow,d:dow,e:eew,f:foo],[d:dow,g:gow,m:mom,c:cow,z:zoo,a:foo],Result),
  Result == [a:foo, c:cow, d:dow, b:bar, e:eew, f:foo, g:gow, m:mom, z:zoo].

feature_unification:unify_test16 :- feature_unification:unify([a:[foo:[],bar={[]}]],[a:[foo:[]]],Result),
  Result == [a:[foo:[],bar={[]}]].

feature_unification:unify_test17 :- feature_unification:unify([a:[]],[a:{[foo]}],Result),
  Result == [a:{[foo]}].

feature_unification:unify_test18 :- feature_unification:unify([kde:[], exists(qt):[ qt:[], mt:{[true,false]}], alsa:true],[alsa:true,exists(qt):[ mt:true ]],Result),
  Result == [exists(qt):[mt:true, qt:[]], alsa:true, kde:[]].

feature_unification:unify_test19 :- feature_unification:unify([a:{[foo:[],bar:{[]}]}],[a:{[bar:[],foo:[]]}],Result),
  Result == [a:{[foo:[]]}].


% some performance tests

buildsystem(0,_).
buildsystem(Number,X) :- Number > 0, Number1 is Number - 1, genterm(X,Component), Components is Number * X,  genterm(Components,Plan), unify(Component,Plan,_),!, buildsystem(Number1,X).

% Generate a Feature term of a given length

genterm(0,[]).
genterm(N,[N:N|R]) :- N > 0, N1 is N - 1, genterm(N1,R).


unify_failtest1 :- not(unify([a:foo],[a:bar],_)).

unify_failtest2 :- not(unify([a:{[foo]}],[a:{[bar]}],_)).

unify_failtest3 :- not(unify([a:{[foo]}],[a:bar],_)).

unify_failtest4 :- not(unify([a:foo],[a:foo,a:{[bar,cow]}],_)).

unify_failtest5 :- not(unify([a:{foo}],[a:[bar]],_)). % syntax error

unify_failtest6 :- not(unify([a:foo],[a:{[foo,bar]},a:bar],_)).

unify_failtest7 :- not(unify([a:{[]}],[a:[]],_)).
