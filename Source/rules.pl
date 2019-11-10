% ******************
% RULES declarations
% ******************

% Work in progress

% Transition rules...

% An ebuild can be installed, if its compiletime dependencies are satisfied 

rule(_Context://Ebuild:install,Deps) :- 
  ebuild:get(depend,Ebuild,Deps).

% An ebuild can be run, if its runtime dependencies are satisfied 

rule(Ebuild:run,Deps) :-
  ebuild:get(rdepend,Ebuild,Deps).


% Conflicting package: EAPI 8.2.6.2: a weak block can be ignored by the package manager
rule(package_dependency(weak,_,_,_,_,_,_),[]) :- !.

% Conflicting package: EAPI 8.2.6.2: a strong block is satisfied when no suitable candidate is satisfied
rule(package_dependency(strong,_,_,_,_,_,_),[]) :- !.


% DEBUG: for now skip virtual dependencies
rule(package_dependency(_,'virtual',_,_,_,_,_),[]) :- !.


% DEBUG: what if a package doesn't have a cache entry defined? 
% rule(package_dependency(_,C,N,_,_,_,_),_) :- 
%   not(cache:entry(_,_,_,C,N,_,_)),
%   fail.

% DEBUG: We start with NO, weak and strong are implemented later

% A package dependency is satisfied when a suitable candidate is satisfied
rule(package_dependency(no,C,N,_,_,_,_),Choice:install) :-
  cache:entry(_,Choice,_,C,N,_,_).% write(Choice),nl. %DEBUG: no backtracking over versions




% The dependencies in a use conditional group need to be satisfied when the use flag is set
%rule(use_conditional_group(_,Use,Deps),Deps) :- 
%  mypreferences:use(Use),!.

% The dependencies in a use conditional group need not to be satisfied when the use flag is not set
rule(use_conditional_group(_,_,_),[]) :- !.

% One dependency of an any_of_group should be satisfied
rule(any_of_group(_Deps),[]) :- !.   % DEBUG: Deps
  %member(Dep,Deps).

% All dependencies in an all_of_group should be satisfied
rule(all_of_group(_Deps),[]) :- !. %DEBUG: Deps

