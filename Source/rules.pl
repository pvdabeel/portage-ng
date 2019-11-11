% ******************
% RULES declarations
% ******************


% Skip attempted installation of masked packages without failing

rule(Context://Identifier:install,[]) :- 
  preference:masked(Context://Identifier),!.



% An ebuild can be installed, if its compiletime dependencies are satisfied 

rule(Context://Ebuild:install,Deps) :- 
  ebuild:get(depend,Context://Ebuild,Deps).

% An ebuild can be run, if it is installed and if its runtime dependencies are satisfied  

rule(Context://Ebuild:run,[Context://Ebuild:install|Deps]) :-
  ebuild:get(rdepend,Context://Ebuild,Deps).



% Ignored for now: Conflicting package: EAPI 8.2.6.2: a weak block can be ignored by the package manager

rule(package_dependency(weak,_,_,_,_,_,_),[]) :- !.

% Ignored for now: Conflicting package: EAPI 8.2.6.2: a strong block is satisfied when no suitable candidate is satisfied

rule(package_dependency(strong,_,_,_,_,_,_),[]) :- !.



% Dependencies on the system profile are assumed satisfied

rule(package_dependency(no,'sys-apps','baselayout',_,_,_,_),[]) :- !.
rule(package_dependency(no,'app-arch','bzip2',_,_,_,_),[]) :- !.
rule(package_dependency(no,'app-arch','gzip',_,_,_,_),[]) :- !.
rule(package_dependency(no,'app-arch','tar',_,_,_,_),[]) :- !.
rule(package_dependency(no,'app-arch','xz-utils',_,_,_,_),[]) :- !.
rule(package_dependency(no,'app-shells','bash',_,_,_,_),[]) :- !.
rule(package_dependency(no,'net-misc','iputils',_,_,_,_),[]) :- !.
rule(package_dependency(no,'net-misc','rsync',_,_,_,_),[]) :- !.
rule(package_dependency(no,'net-misc','wget',_,_,_,_),[]) :- !.
rule(package_dependency(no,'sys-apps','coreutils',_,_,_,_),[]) :- !.
rule(package_dependency(no,'sys-apps','diffutils',_,_,_,_),[]) :- !.
rule(package_dependency(no,'sys-apps','file',_,_,_,_),[]) :- !.
rule(package_dependency(no,'sys-apps','findutils',_,_,_,_),[]) :- !.
rule(package_dependency(no,'sys-apps','gawk',_,_,_,_),[]) :- !.
rule(package_dependency(no,'sys-apps','grep',_,_,_,_),[]) :- !.
rule(package_dependency(no,'sys-apps','kbd',_,_,_,_),[]) :- !.
rule(package_dependency(no,'sys-apps','less',_,_,_,_),[]) :- !.
rule(package_dependency(no,'sys-process','procps',_,_,_,_),[]) :- !.
rule(package_dependency(no,'sys-process','psmisc',_,_,_,_),[]) :- !.
rule(package_dependency(no,'sys-apps','sed',_,_,_,_),[]) :- !.
rule(package_dependency(no,'sys-devel','binutils',_,_,_,_),[]) :- !.
rule(package_dependency(no,'sys-devel','gcc',_,_,_,_),[]) :- !.
rule(package_dependency(no,'sys-devel','gnuconfig',_,_,_,_),[]) :- !.
rule(package_dependency(no,'sys-devel','make',_,_,_,_),[]) :- !.
rule(package_dependency(no,'sys-devel','patch',_,_,_,_),[]) :- !.
rule(package_dependency(no,'sys-fs','e2fsprogs',_,_,_,_),[]) :- !.
rule(package_dependency(no,'virtual','dev-manager',_,_,_,_),[]) :- !.
rule(package_dependency(no,'virtual','editor',_,_,_,_),[]) :- !.
rule(package_dependency(no,'virtual','libc',_,_,_,_),[]) :- !.
rule(package_dependency(no,'virtual','man',_,_,_,_),[]) :- !.
rule(package_dependency(no,'virtual','modutils',_,_,_,_),[]) :- !.
rule(package_dependency(no,'virtual','os-headers',_,_,_,_),[]) :- !.
rule(package_dependency(no,'virtual','package-manager',_,_,_,_),[]) :- !.
rule(package_dependency(no,'virtual','pager',_,_,_,_),[]) :- !.
rule(package_dependency(no,'virtual','service-manager',_,_,_,_),[]) :- !.
rule(package_dependency(no,'virtual','shadow',_,_,_,_),[]) :- !.
rule(package_dependency(no,'virtual','ssh',_,_,_,_),[]) :- !.



% A package dependency is satisfied when a suitable candidate is satisfied
rule(package_dependency(no,C,N,_,_,_,_),portage://Choice:install) :-
  cache:entry(_,Choice,_,C,N,_,_). 



% The dependencies in a use conditional group need to be satisfied when the use flag is set
rule(use_conditional_group(positive,U,D),[D]) :- 
  preference:use(Enabled),
  member(U,Enabled),!.

% Ignored for now: Use flag not enabled or non-positive use conditional group
rule(use_conditional_group(_,_,_),[]) :- !.

% One dependency of an any_of_group should be satisfied
rule(any_of_group(Deps),[D]) :- 
  member(D,Deps).   

% All dependencies in an all_of_group should be satisfied
rule(all_of_group(Deps),Deps) :- !. 

