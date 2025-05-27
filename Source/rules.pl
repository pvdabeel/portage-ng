/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2025, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> RULES
This file contains domain-specific rules
*/

:- module(rules, [rule/2]).


% ******************
% RULES declarations
% ******************


% ----------------------
% Ruleset: Ebuild states
% ----------------------


% MASKED
%
% If an action on a masked ebuild is explicitely requested, unmasking is needed.

rule(Repository://Ebuild:_Action:Context,[assumed(Repository://Ebuild:unmask:Context)]) :-
  preference:masked(Repository://Ebuild),!.


% DOWNLOAD
%
% Any ebuild can be downloaded.

rule(Repository://Ebuild:download:_Context,[]) :-
  % query:search([ebuild(Ebuild)],Repository://Ebuild),!.
  cache:ordered_entry(Repository,Ebuild,_,_,_),!.


% FETCHONLY
%
% Same as download, but also downloads all dependencies

% 1. Don't perform downloads for already installed packages,
%    unless emptytree is specified.

rule(Repository://Ebuild:fetchonly:_Context,[]) :-
  \+(preference:flag(emptytree)),
  % query:search([installed(true)],Repository://Ebuild),!.
  cache:entry_metadata(Repository,Ebuild,installed,true),!.

% 2. Package is not installed, consider its dependencies,
%    taking into account slot and use restrictions

rule(Repository://Ebuild:fetchonly:Context,Conditions) :-
  % query:search([not(installed(true)),category(C),name(N),slot(S),model(required_use(M)),all(depend(CD)),all(rdepend(RD))],Repository://Ebuild),
  %\+cache:entry_metadata(Repository,Ebuild,installed,true)
  cache:ordered_entry(Repository,Ebuild,C,N,_V),
  cache:entry_metadata(Repository,Ebuild,slot,slot(S)),
  findall(Depend:fetchonly:Context,cache:entry_metadata(Repository,Ebuild,depend,Depend),CD),
  findall(Depend:fetchonly:Context,cache:entry_metadata(Repository,Ebuild,rdepend,Depend),RD),
  append(CD,RD,D),
  M = [],
  ( memberchk(C,['virtual','acct-group','acct-user']) ->
    Conditions = [constraint(use(Repository://Ebuild):{M}),
                  constraint(slot(C,N,S):{[Ebuild]})
                  |D];
    Conditions = [constraint(use(Repository://Ebuild):{M}),
                  Repository://Ebuild:download:Context,
                  constraint(slot(C,N,S):{[Ebuild]})
                  |D] ).


% INSTALL
%
% An ebuild is installed, either:
%
% - The os reports it as installed, and we are not proving emptytree
%
% or, if the following conditions are satisfied:
%
% - Its require_use dependencies are satisfied
% - It is downloaded (Only when it is not a virtual, a group or a user)
% - Its compile-time dependencies are satisfied
% - it can occupy an installation slot

rule(Repository://Ebuild:install:_Context,[]) :-
  \+(preference:flag(emptytree)),
  % query:search([installed(true)],Repository://Ebuild),!.
  cache:entry_metadata(Repository,Ebuild,installed,true),!.

rule(Repository://Ebuild:install:Context,Conditions) :-
  %query:search([category(C),name(N),slot(S),model(required_use(M)),all(depend(D))],Repository://Ebuild),
  query:search([category(C),name(N),slot(S),model(required_use(M))],Repository://Ebuild),
  %cache:ordered_entry(Repository,Ebuild,C,N,_V),
  %cache:entry_metadata(Repository,Ebuild,slot,slot(S)),
  findall(Depend:install:Context,cache:entry_metadata(Repository,Ebuild,depend,Depend),D),
  %M = [],
  ( memberchk(C,['virtual','acct-group','acct-user']) ->
    Conditions = [constraint(use(Repository://Ebuild):{M}),
                  constraint(slot(C,N,S):{[Ebuild]})
                  |D];
    Conditions = [constraint(use(Repository://Ebuild):{M}),
                  Repository://Ebuild:download:Context,
                  constraint(slot(C,N,S):{[Ebuild]})
                  |D] ).

% ?- knowledgebase:query([category('sys-apps'),name('portage'),model(required_use(M))],portage://'sys-apps/portage-3.0.63-r1').
% M = [required(python_targets_pypy3), python_targets_pypy3] ;
% M = [required(python_targets_python3_10), python_targets_python3_10] ;
% M = [required(python_targets_python3_11), python_targets_python3_11] ;
% M = [required(python_targets_python3_12), python_targets_python3_12] ;



% RUN
%
% An ebuild can be run, either:
%
% - The os reports it as runnable, and we are not proving emptytree
%
% or:
%
% - if it is installed and if its runtime dependencies are satisfied

rule(Repository://Ebuild:run:Context,Conditions) :-
  \+(preference:flag(emptytree)),
  % query:search([installed(true)],Repository://Ebuild),!,
  cache:entry_metadata(Repository,Ebuild,installed,true),!,
  (config:avoid_reinstall(true) -> Conditions = [] ; Conditions = [Repository://Ebuild:reinstall:Context]).

rule(Repository://Ebuild:run:Context,[Repository://Ebuild:install:Context|D]) :-
  % query:search([all(rdepend(Depend))],Repository:Ebuild).
  findall(Depend:run:Context,cache:entry_metadata(Repository,Ebuild,rdepend,Depend),D).
  %knowledgebase:query([all(rdepend(D))],Repository://Ebuild).


% REINSTALL
%
% An ebuild can be reinstalled if:
%
% - the OS reports it as runnable, and we are not proving emptyttree

rule(Repository://Ebuild:reinstall:_Context,[]) :-
  \+(preference:flag(emptytree)),
  % query:search([installed(true)],Repository://Ebuild),!.
  cache:entry_metadata(Repository,Ebuild,installed,true),!.


% UNINSTALL
%
% An ebuild can be uninstalled if:
%
% - the OS reports it as installed, and we are not proving emptytree

rule(Repository://Ebuild:uninstall:_Context,[]) :-
  \+(preference:flag(emptytree)),
  % query:search([installed(true)],Repository://Ebuild),!.
  cache:entry_metadata(Repository,Ebuild,installed,true),!.

% Note: this may leave the Model and Proof for the other packages incomplete - todo: implement depclean.


% UPDATE
%
% An ebuild can be updated:
%
% - The os reports it as installed
%   and a higher version in the same slot is available
%   taking into account accept_keywords filter

rule(Repository://Ebuild:update:Context,Conditions) :-
  \+(preference:flag(emptytree)),
  preference:accept_keywords(K),
  % query:search([installed(true),keywords(K),slot(S),version(VersionInstalled),category(Category),name(Name)],Repository://Ebuild),
  cache:entry_metadata(Repository,Ebuild,installed,true),!,
  cache:entry_metadata(Repository,Ebuild,slot,S),
  cache:ordered_entry(Repository,Ebuild,Category,Name,VersionInstalled),
  % query:search([name(Name),category(Category),version(VersionLatest),keywords(K),slot(S)]],Repository://LatestEbuild),
  cache:ordered_entry(Repository,LatestEbuild,Category,Name,VersionLatest),
  cache:entry_metadata(Repository,LatestEbuild,slot,S),
  cache:entry_metadata(Repository,LatestEbuild,keywords,K),!,
  compare(>,VersionLatest,VersionInstalled)
  -> Conditions = [Repository://Ebuild:uninstall:Context,Repository://LatestEbuild:install:Context]
  ;  Conditions = [].

% todo: deep


% UPGRADE
%
% An ebuild can be upgraded:
%
% - The os reports it as installed,
%   and a higher version is available. Slots are disregarded.

rule(Repository://Ebuild:update:Context,Conditions) :-
  \+(preference:flag(emptytree)),
  preference:accept_keywords(K),
  % query:search([installed(true),keywords(K),version(VersionInstalled),category(Category),name(Name)],Repository://Ebuild),
  cache:entry_metadata(Repository,Ebuild,installed,true),!,
  cache:ordered_entry(Repository,Ebuild,Category,Name,VersionInstalled),
  % query:search([name(Name),category(Category),version(VersionLatest),keywords(K)]],Repository://LatestEbuild),
  cache:ordered_entry(Repository,LatestEbuild,Category,Name,VersionLatest),
  cache:entry_metadata(Repository,LatestEbuild,keywords,K),!,
  compare(>,VersionLatest,VersionInstalled)
  -> Conditions = [Repository://Ebuild:uninstall:Context,Repository://Ebuild:install:Context]
  ;  Conditions = [].

% todo: deep



% VERIFY
%
% An ebuild is verified if it can be run and its posttime dependencies are satsified

%rule(Repository://Ebuild:verify,[Repository://Ebuild:run|P]) :-
%  !,
%  findall(Depend,cache:entry_metadata(Repository,Ebuild,pdepend,Depend),P).




% ------------------------------
% Ruleset: Dependency resolution
% ------------------------------

% PACKAGE_DEPENDENCY
%
% Ebuilds use package dependencies to express relations (conflicts or requirements) on
% other ebuilds.


% Conflicting package:
%
% EAPI 8.2.6.2: a weak block can be ignored by the package manager

rule(package_dependency(_,_,weak,_,_,_,_,_,_):_,[]) :- !.


% Conflicting package:
%
% EAPI 8.2.6.2: a strong block is satisfied when no suitable candidate is satisfied

rule(package_dependency(_,_,strong,_,_,_,_,_,_):_,[]) :- !.

% rule(package_dependency(Action,strong,C,N,_,_,_,_),Nafs) :-
%   findall(naf(Repository://Choice:Action),cache:entry(Repository,Choice,_,C,N,_,_),Nafs),!.


% Dependencies on the system profile
%
% These type of dependencies are assumed satisfied. If they are not defined,
% portage-ng will detect a circular dependency (e.g. your compiler needs a compiler)

rule(package_dependency(_,_,no,'app-arch','bzip2',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'app-arch','gzip',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'app-arch','tar',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'app-arch','xz-utils',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'app-shells','bash',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'dev-lang','perl',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'dev-lang','python',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'dev-libs','libpcre',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'net-misc','iputils',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'net-misc','rsync',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'net-misc','wget',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'sys-apps','baselayout',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'sys-apps','coreutils',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'sys-apps','diffutils',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'sys-apps','file',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'sys-apps','findutils',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'sys-apps','gawk',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'sys-apps','grep',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'sys-apps','kbd',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'sys-apps','less',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'sys-apps','sed',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'sys-apps','util-linux',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'sys-devel','automake',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'sys-devel','binutils',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'sys-devel','gcc',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'sys-devel','gnuconfig',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'sys-devel','make',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'sys-devel','patch',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'sys-fs','e2fsprogs',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'sys-libs','libcap',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'sys-libs','ncurses',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'sys-libs','readline',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'sys-process','procps',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'sys-process','psmisc',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'virtual','dev-manager',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'virtual','editor',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'virtual','libc',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'virtual','man',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'virtual','modutils',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'virtual','os-headers',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'virtual','package-manager',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'virtual','pager',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'virtual','service-manager',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'virtual','shadow',_,_,_,_):_,[]) :- !.
rule(package_dependency(_,_,no,'virtual','ssh',_,_,_,_):_,[]) :- !.


% A package dependency is satisfied when a suitable candidate is satisfied,
% a package dependency that has no suitable candidates is "assumed" satisfied
%
% Portage-ng will identify these assumptions in its proof and show them to the
% user prior to continuing to the next stage (i.e. executing the plan).

% Preference: prefer installed packages over new packages, unless 'emptytree' flag
% is used

rule(package_dependency(_R://_E,_T,no,C,N,_O,_V,_S,_U):_Action,Conditions) :-
  \+(preference:flag(emptytree)),
  preference:accept_keywords(K),
  % query:search([installed(true),name(N),category(C),keywords(K)],Repository://Choice),
  cache:ordered_entry(Repository,Choice,C,N,_),
  cache:entry_metadata(Repository,Choice,installed,true),
  cache:entry_metadata(Repository,Choice,keywords,K),!,
  Conditions = [].


rule(package_dependency(_R://_E,_T,no,C,N,_O,_V,_S,_U):Action,Conditions) :-
  %preference:flag(emptytree),
  preference:accept_keywords(K),
  cache:ordered_entry(Repository,Choice,C,N,_),
  cache:entry_metadata(Repository,Choice,keywords,K),
  %knowledgebase:query([name(N),category(C),keywords(K)],Repository://Choice),
  Conditions = [Repository://Choice:Action].

rule(package_dependency(R://E,_T,no,C,N,O,V,S,U):Action,Conditions) :-
  %preference:flag(emptytree)
  preference:accept_keywords(K),
  \+((cache:ordered_entry(Repository,Choice,C,N,_),
  cache:entry_metadata(Repository,Choice,keywords,K))),
  %\+(knowledgebase:query([name(N),category(C),keywords(K)],_)),
  Conditions = [assumed(package_dependency(R://E,Action,no,C,N,O,V,S,U))],!.


% Use conditional dependencies as package dependencies.


% The dependencies in a positive use conditional group need to be satisfied when
% the use flag is positive through required use constraint, preference or ebuild
% default

%rule(use_conditional_group(positive,Use,R://E,Deps):Action,[constraint(use(R://E):Use)|Result]) :-
%  message:color(cyan),write('constraining use:  '),write(Use),write(' - for: '),write(R://E),message:color(normal),nl,
%  findall(D:Action,member(D,Deps),Result).


% 1. The USE is explicitely enabled, either by preference or ebuild -> process deps

rule(use_conditional_group(positive,Use,R://E,Deps):Action,Result) :-
  query:search(iuse(Use,positive:_Reason),R://E),!,
  findall(D:Action,member(D,Deps),Result).
  %(Reason == preference
  % -> findall(D:Action,member(D,Deps),Result)
  % ;  findall(D:Action,member(D,Deps),Temp), Result = [constraint(use(R://E):Use)|Temp]).

% 2. The USE is not enabled -> no deps

rule(use_conditional_group(positive,_Use,_R://_E,_):_Action,[]) :-
  !.


% The dependencies in a negative use conditional group need to be satisfied when
% the use flag is not positive through required use constraint, preference or
% ebuild default

%rule(use_conditional_group(negative,Use,R://E,Deps):Action,[constraint(use(R://E):naf(Use))|Result]) :-
%  findall(D:Action,member(D,Deps),Result).

rule(use_conditional_group(negative,Use,R://E,Deps):Action,Result) :-
  query:search(iuse(Use,negative:_Reason),R://E),!,
  findall(D:Action,member(D,Deps),Result).
  %(Reason == preference
  % -> findall(D:Action,member(D,Deps),Result)
  % ;  findall(D:Action,member(D,Deps),Temp), Result = [constraint(use(R://E):naf(Use))|Temp]).

rule(use_conditional_group(negative,_Use,_R://_E,_):_Action,[]) :-
  !.


% Use conditional dependencies in other metadata

% 1. The USE is explicitely enabled, either by preference or ebuild -> process deps

rule(use_conditional_group(positive,Use,R://E,Deps),Result) :-
  query:search(iuse(Use,positive:preference),R://E),!,
  findall(D,member(D,Deps),Result).
  %(Reason == preference
  % -> findall(D,member(D,Deps),Result)
  % ;  findall(D,member(D,Deps),Temp), writeln(Use:Reason), Result = [constraint(use(R://E):{[assumed(Use)]})|Temp]).

% 2. The USE is not enabled -> no deps

rule(use_conditional_group(positive,_Use,_R://_E,_),[]) :-
  !.


% The dependencies in a negative use conditional group need to be satisfied when
% the use flag is not positive through required use constraint, preference or
% ebuild default

%rule(use_conditional_group(negative,Use,R://E,Deps):Action,[constraint(use(R://E):naf(Use))|Result]) :-
%  findall(D:Action,member(D,Deps),Result).

rule(use_conditional_group(negative,Use,R://E,Deps),Result) :-
  query:search(iuse(Use,negative:preference),R://E),!,
  findall(D,member(D,Deps),Result).
  %(Reason == preference
  % -> findall(D:Action,member(D,Deps),Result)
  % ;  findall(D:Action,member(D,Deps),Temp), Result = [constraint(use(R://E):naf(Use))|Temp]).

rule(use_conditional_group(negative,_Use,_R://_E,_),[]) :-
  !.






% Example: feature:unification:unify([constraint(use(os)):darwin],[constraint(use(os)):{[linux,darwin]}],Result).


% Exactly one of the dependencies in an exactly-one-of-group should be satisfied

rule(exactly_one_of_group(Deps):Action,[D:Action|NafDeps]) :-
  member(D,Deps),
  findall(naf(N:Action),(member(N,Deps), \+(D = N)),NafDeps).

rule(exactly_one_of_group(Deps),[D|NafDeps]) :-
  member(D,Deps),
  findall(naf(N),(member(N,Deps), \+(D = N)),NafDeps).





% One dependency of an any_of_group should be satisfied

rule(any_of_group(Deps):Action,[D:Action]) :-
  member(D,Deps).

rule(any_of_group(Deps),[D]) :-
  member(D,Deps).



% All dependencies in an all_of_group should be satisfied

rule(all_of_group(Deps):Action,Result) :-
  findall(D:Action,member(D,Deps),Result),!.

rule(all_of_group(Deps),Result) :-
  findall(D,member(D,Deps),Result),!.


% ---------------
% Ruleset: Models
% ---------------

% The following can occur within a proof:

% Src_uri:

rule(uri(_,_,_):_,[]) :- !.
rule(uri(_):_,[]) :- !.


% Required use

rule(required(minus(Use)),[minus(Use)]) :-
  \+Use =.. [minus,_],
  preference:use(minus(Use)),!.

rule(required(Use),[Use]) :-
  \+Use =.. [minus,_],
  preference:use(Use),!.

rule(required(Use),[assumed(conflict(required,Use))]) :-
  \+Use =.. [minus,_],
  preference:use(minus(Use)),!.

rule(required(minus(Use)),[assumed(conflict(required,minus(Use)))]) :-
  \+Use =.. [minus,_],
  preference:use(Use),!.

rule(required(minus(Use)),[assumed(minus(Use))]) :-
  \+Use =.. [minus,_],
  \+preference:use(Use),
  \+preference:use(minus(Use)),!.

rule(required(Use),[assumed(Use)]) :-
  \+Use =.. [minus,_],
  \+preference:use(Use),
  \+preference:use(minus(Use)),!.


% Blocking use

rule(blocking(minus(Use)),[Use]) :-
  \+Use =.. [minus,_],
  preference:use(Use),!.

rule(blocking(Use),[minus(Use)]) :-
  \+Use =.. [minus,_],
  preference:use(minus(Use)),!.

rule(blocking(Use),[assumed(conflict(blocking,Use))]) :-
  \+Use =.. [minus,_],
  preference:use(Use),!.

rule(blocking(minus(Use)),[assumed(conflict(blocking,minus(Use)))]) :-
  \+Use =.. [minus,_],
  preference:use(minus(Use)),!.

rule(blocking(minus(Use)),[assumed(minus(Use))]) :-
  \+Use =.. [minus,_],
  \+preference:use(Use),
  \+preference:use(minus(Use)),!.

rule(blocking(Use),[assumed(minus(Use))]) :-
  \+Use =.. [minus,_],
  \+preference:use(Use),
  \+preference:use(minus(Use)),!.


% ----------------------
% Rules needed by prover
% ----------------------

% Assumptions:

rule(assumed(_),[]) :- !.

% Negation as failure:

% We add some conflict resolution information:

rule(naf(Statement),C) :-
  Statement =.. [required,Use],!,
  ( preference:use(Use) -> C = [conflict(Use,naf(required(Use)))] ; C = []).

rule(naf(Statement),C) :-
  Statement =.. [blocking,Use],!,
  ( preference:use(minus(Use)) -> C = [conflict(Use,naf(blocking(Use)))] ; C = [] ).

% Conflicts:

rule(conflict(_,_),[]) :- !,
  fail.

% The default rule, prover takes care of negation

rule(naf(_),[]) :- !.

% Atoms

rule(Literal,[]) :-
  atom(Literal),!.
