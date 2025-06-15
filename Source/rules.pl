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

%rule(Repository://Ebuild:_Action?{Context},[assumed(Repository://Ebuild:unmask?{Context})]) :-
%  preference:masked(Repository://Ebuild),!.


% DOWNLOAD
%
% Any ebuild can be downloaded.

rule(Repository://Ebuild:download?{_},[]) :-
  !,
  query:search(ebuild(Ebuild),Repository://Ebuild).


% FETCHONLY
%
% Same as download, but also considers downloading all dependencies

% 1. Don't perform downloads for already installed packages,
%    unless emptytree is specified.
%
% 2. Package is not installed, consider its dependencies,
%    taking into account slot and use restrictions. We consider
%    both runtime as well as compile time dependencies at the same
%    time.
%
% We don't trigger downloads for virtual, acct-group or acct-user.

%rule(Repository://Ebuild:fetchonly?{_},[]) :-
%  (preference:flag(emptytree)
%   -> fail
%   ; cache:entry_metadata(Repository,Ebuild,installed,true)),!.

rule(Repository://Ebuild:fetchonly?{_Context},Conditions) :-
  !,
  query:search(masked(true),   Repository://Ebuild) -> Conditions = [] ;
  query:search(installed(true),Repository://Ebuild) -> \+preference:flag(emptytree), Conditions = [] ;

  % 1. Get some metadata we need further down

  cache:ordered_entry(Repository,Ebuild,C,N,_),
  cache:entry_metadata(Repository,Ebuild,slot,S),

  % 2. Compute required_use stable model
  query:search(model(required_use(R)),Repository://Ebuild),

  % 3. Pass use model onto dependencies to calculate corresponding dependency  model,
  %    We pass using config action to avoid package_dependency from generating choices.
  %    The config action triggers use_conditional, any_of_group, exactly_one_of_group,
  %    all_of_group ... choice point generation

  %feature_unification:unify(Context,R,ForwardContext),
  %ForwardContext = R,
  query:search(model(dependency(D,fetchonly)):config?{R},Repository://Ebuild),

  % 4. Pass on relevant package dependencies and constraints to prover

  ( memberchk(C,['virtual','acct-group','acct-user']) ->
    Conditions = [constraint(use(Repository://Ebuild):{R}),
                  constraint(slot(C,N,S):{Ebuild})
                  |D];
    Conditions = [constraint(use(Repository://Ebuild):{R}),
                  Repository://Ebuild:download?{R},
                  constraint(slot(C,N,S):{Ebuild})
                  |D] ).


% INSTALL
%
% An ebuild is installed, either:
%
% - Metadata indicates it is installed, and we are not proving emptytree
%
% or, if the following conditions are satisfied:
%
% - Its require_use dependencies are satisfied
% - It is downloaded (Only when it is not a virtual, a group or a user)
% - Its compile-time dependencies are satisfied
% - it can occupy an installation slot
%
% We don't trigger downloads for virtual, acct-group or acct-user.

%rule(Repository://Ebuild:install?{_},[]) :-
%  \+(preference:flag(emptytree)),
%  cache:entry_metadata(Repository,Ebuild,installed,true),!.

rule(Repository://Ebuild:install?{R},Conditions) :-
  !,
  query:search(masked(true),   Repository://Ebuild) -> Conditions = [] ;
  query:search(installed(true),Repository://Ebuild), \+preference:flag(emptytree) -> Conditions = [] ;

  % 1. Get some metadata we need further down

  cache:ordered_entry(Repository,Ebuild,C,N,_),
  cache:entry_metadata(Repository,Ebuild,slot,S),

  % 2. Compute required_use stable model, if not already passed on by run

  %(Context == []
  % -> query:search(model(required_use(R)),Repository://Ebuild)
  % ;  R = Context ),

  % 3. Pass use model onto dependencies to calculate corresponding dependency  model,
  %    We pass using config action to avoid package_dependency from generating choices.
  %    The config action triggers use_conditional, any_of_group, exactly_one_of_group,
  %    all_of_group ... choice point generation

  %feature_unification:unify(Context,R,ForwardContext),
  %ForwardContext = R,
  query:search(model(dependency(D,install)):config?{R},Repository://Ebuild),

  %message:color(orange),
  %write(Repository://Ebuild),write('  -->  '),write(R),nl,
  %write(Repository://Ebuild),write('  -->  '),write(D),nl,
  %message:color(normal),

  % 4. Pass on relevant package dependencies and constraints to prover

  ( memberchk(C,['virtual','acct-group','acct-user'])
    -> Conditions = [ constraint(use(Repository://Ebuild):{R}),
                      constraint(slot(C,N,S):{Ebuild})
                      |D]
    ;  Conditions = [constraint(use(Repository://Ebuild):{R}),
                     Repository://Ebuild:download?{R},
                     constraint(slot(C,N,S):{Ebuild})
                     |D] ).


% RUN
%
% An ebuild can be run, either:
%
% - it is reportedly installed, and we are not proving emptytree
%
% or:
%
% - if it is installed and if its runtime dependencies are satisfied

%rule(Repository://Ebuild:run?{Context},Conditions) :-
%  \+(preference:flag(emptytree)),
%  cache:entry_metadata(Repository,Ebuild,installed,true),!,
%  (config:avoid_reinstall(true) -> Conditions = [] ; Conditions = [Repository://Ebuild:reinstall?{Context}]).

rule(Repository://Ebuild:run?{Context},Conditions) :-
  !,
  query:search(masked(true),   Repository://Ebuild) -> Conditions = [] ;
  query:search(installed(true),Repository://Ebuild), \+preference:flag(emptytree) -> (config:avoid_reinstall(true) -> Conditions = [] ; Conditions = [Repository://Ebuild:reinstall?{Context}]) ;

  % 1. Get some metadata we need further down

  % cache:ordered_entry(Repository,Ebuild,C,N,_),
  % cache:entry_metadata(Repository,Ebuild,slot,S),

  % 2. Compute required_use stable model

  query:search(model(required_use(R)),Repository://Ebuild),

  % 3. Pass use model onto dependencies to calculate corresponding dependency  model,
  %    We pass using config action to avoid package_dependency from generating choices.
  %    The config action triggers use_conditional, any_of_group, exactly_one_of_group,
  %    all_of_group ... choice point generation

  %feature_unification:unify(Context,R,ForwardContext),
  %ForwardContext = R,
  query:search(model(dependency(D,run)):config?{R},Repository://Ebuild),

  Conditions = [Repository://Ebuild:install?{R}|D].


% REINSTALL
%
% An ebuild can be reinstalled if:
%
% - it is reportedly installed, and we are not proving emptyttree

rule(Repository://Ebuild:reinstall?{_},[]) :-
  \+(preference:flag(emptytree)),
  query:search(installed(true),Repository://Ebuild),!. % todo: retrieve installation context


% UNINSTALL
%
% An ebuild can be uninstalled if:
%
% - it is reportedly installed, and we are not proving emptytree

rule(Repository://Ebuild:uninstall?{_},[]) :-
  \+(preference:flag(emptytree)),
  query:search(installed(true),Repository://Ebuild),!.

% Note: this may leave the Model and Proof for the other packages incomplete - todo: implement depclean.


% UPDATE
%
% An ebuild can be updated:
%
% - it is reportedly installed
%   and a higher version in the same slot is available
%   taking into account accept_keywords filter

rule(Repository://Ebuild:update?{Context},Conditions) :-
  \+(preference:flag(emptytree)),
  preference:accept_keywords(K),
  query:search([name(Name),category(Category),keywords(K),slot(S),installed(true),version(VersionInstalled)],Repository://Ebuild),
  query:search([name(Name),category(Category),keywords(K),slot(S),version(VersionLatest)],Repository://LatestEbuild),!, % todo: check cut
  compare(>,VersionLatest,VersionInstalled)
  -> Conditions = [Repository://Ebuild:uninstall?{Context},Repository://LatestEbuild:install?{Context}]
  ;  Conditions = [].

% todo: deep


% UPGRADE
%
% An ebuild can be upgraded:
%
% - The os reports it as installed,
%   and a higher version is available. Slots are disregarded.

rule(Repository://Ebuild:update?{Context},Conditions) :-
  \+(preference:flag(emptytree)),
  preference:accept_keywords(K),
  query:search([name(Name),category(Category),keywords(K),installed(true),version(VersionInstalled)],Repository://Ebuild),
  query:search([name(Name),category(Category),keywords(K),version(VersionLatest)],Repository://LatestEbuild),!, % todo: check cut
  compare(>,VersionLatest,VersionInstalled)
  -> Conditions = [Repository://Ebuild:uninstall?{Context},Repository://LatestEbuild:install?{Context}]
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

rule(package_dependency(_,_,weak,_,_,_,_,_,_):_?{_},[]) :- !.


% Conflicting package:
%
% EAPI 8.2.6.2: a strong block is satisfied when no suitable candidate is satisfied

rule(package_dependency(_,_,strong,_,_,_,_,_,_):_?{_},[]) :- !.

% rule(package_dependency(Action,strong,C,N,_,_,_,_),Nafs) :-
%   findall(naf(Repository://Choice:Action),cache:entry(Repository,Choice,_,C,N,_,_),Nafs),!.


% Dependencies on the system profile

rule(package_dependency(_,_,no,C,N,_,_,_,_):_?{_}, []) :-
    core_pkg(C,N), !.


% A package dependency is satisfied when a suitable candidate is satisfied,
% a package dependency that has no suitable candidates is "assumed" satisfied
%
% Portage-ng will identify these assumptions in its proof and show them to the
% user prior to continuing to the next stage (i.e. executing the plan).

% Preference: prefer installed packages over new packages, unless 'emptytree' flag
% is used

rule(package_dependency(_://_,_,_,_,_,_,_,_,_):config?{_},[]) :- !.

rule(package_dependency(_://_,_,no,_,_,_,_,_,_),[]) :- !.

rule(package_dependency(_://_,_,no,C,N,_,_,_,_):Action?{_},Conditions) :-
  \+(Action == config),
  \+(preference:flag(emptytree)),
  preference:accept_keywords(K),
  cache:ordered_entry(Repository,Choice,C,N,_),
  cache:entry_metadata(Repository,Choice,installed,true),					% todo: if build-with-use-dependency triggers a new use in chosen and installed ebuild, then reinstall with new use
  cache:entry_metadata(Repository,Choice,keywords,K),!,
  Conditions = [].

rule(package_dependency(_://_,_,no,C,N,_,_,_,U):Action?{Context},Conditions) :-			% todo: some more fine-grained behaviour w.r.t. slots is needed
  \+(Action == config),
  preference:accept_keywords(K),
  cache:ordered_entry(Repository,Choice,C,N,_),
  cache:entry_metadata(Repository,Choice,keywords,K),
  process_build_with_use(U,Context,NewContext),
  /*message:color(cyan),
  (\+ NewContext == []
   -> (write(R://E),write(': Pushing '),write(NewContext),write(' to: '),write(Repository://Choice),nl)
   ;  true),
  message:color(normal),*/
  Conditions = [Repository://Choice:Action?{NewContext}].

rule(package_dependency(R://E,T,no,C,N,O,V,S,U):Action?{Context},Conditions) :-
  \+(Action == config),
  \+(cache:ordered_entry(_Repository,_Choice,C,N,_)),
  Conditions = [assumed(package_dependency(R://E,T,no,C,N,O,V,S,U):Action?{Context})].

rule(package_dependency(R://E,T,no,C,N,O,V,S,U):Action?{Context},Conditions) :-
  \+(Action == config),
  findall(K,preference:accept_keywords(K),Ks),
  \+((cache:ordered_entry(Repository,Choice,C,N,_),
     cache:entry_metadata(Repository,Choice,keywords,I),
     member(I,Ks))),
  Conditions = [assumed(package_dependency(R://E,T,no,C,N,O,V,S,U):Action?{Context})].



% Use conditional dependencies as package dependencies.


% The dependencies in a positive use conditional group need to be satisfied when
% the use flag is positive through required use constraint, preference or ebuild
% default

% 1. The USE is enabled in the context (dependency induced, or required_use)

rule(use_conditional_group(positive,Use,_R://_E,Deps):Action?{Context},Conditions) :-
  memberchk(assumed(Use),Context),!,
  %write('Context use found: '),write(Use),nl,
  findall(D:Action?{Context},member(D,Deps),Conditions).


% 2. The USE is explicitely enabled, either by preference or ebuild -> process deps

rule(use_conditional_group(positive,Use,R://E,Deps):Action?{Context},Conditions) :-
  query:search(iuse(Use,positive:_Reason),R://E),!,
  %write('Use preference found: '),write(Use),nl,
  findall(D:Action?{Context},member(D,Deps),Result),
  %write(' - Result: '),write(Result),nl,
  Conditions = Result.

%  (Reason == preference
%   -> Conditions = Result
%   ;  Conditions = [constraint(use(R://E):{[Use]})|Result] ).


% 3. The USE is not enabled -> no deps

rule(use_conditional_group(positive,_Use,_R://_E,_):_?{_},[]) :-
  %write('Use not enabled: '),write(Use),nl,
  !.


% The dependencies in a negative use conditional group need to be satisfied when
% the use flag is not positive through required use constraint, preference or
% ebuild default

% 1. The USE is enabled in the context (dependency induced, or required_use)

rule(use_conditional_group(negative,Use,_R://_E,Deps):Action?{Context},Conditions) :-
  memberchk(naf(use(Use)),Context),!,
  findall(D:Action?{Context},member(D,Deps),Conditions).

% 2. The USE is explicitely enabled, either by preference or ebuild -> process deps

rule(use_conditional_group(negative,Use,R://E,Deps):Action?{Context},Conditions) :-
  query:search(iuse(Use,negative:_Reason),R://E),!,
  findall(D:Action?{Context},member(D,Deps),Result),
  Conditions = Result.
  %(Reason == preference
  % -> Conditions = Result
  % ;  Conditions = [constraint(use(R://E):{[naf(Use)]})|Result] ).

% 3. The USE is not enabled -> no deps

rule(use_conditional_group(negative,_Use,_R://_E,_):_?{_},[]) :-
  !.


% Dependency model (contextless)


rule(use_conditional_group(positive,Use,_://_,Deps),Conditions) :-
  preference:use(Use),!,
  findall(D,member(D,Deps),Conditions).

rule(use_conditional_group(positive,_,_://_,_),[]) :- !.

rule(use_conditional_group(negative,Use,_://_,Deps),Conditions) :-
  preference:use(minus(Use)),!,
  findall(D,member(D,Deps),Conditions).

rule(use_conditional_group(negative,_,_://_,_),[]) :- !.


% Exactly one of the dependencies in an exactly-one-of-group should be satisfied

rule(exactly_one_of_group(Deps):Action?{Context},[D:Action?{Context}|NafDeps]) :-
  member(D,Deps),
  findall(naf(N),(member(N,Deps), \+(D = N)),NafDeps).

rule(exactly_one_of_group(Deps),[D|NafDeps]) :-
  member(D,Deps),
  findall(naf(N),(member(N,Deps), \+(D = N)),NafDeps).


% One dependency of an any_of_group should be satisfied

rule(any_of_group(Deps):Action?{Context},[D:Action?{Context}]) :-
  member(D,Deps).

rule(any_of_group(Deps),[D]) :-
  member(D,Deps).


% All dependencies in an all_of_group should be satisfied

rule(all_of_group(Deps):Action?{Context},Result) :-
  findall(D:Action?{Context},member(D,Deps),Result),!.

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

% Constraints:

rule(constraint(_),[]) :- !.

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

core_pkg('app-arch','bzip2').
core_pkg('app-arch','gzip').
core_pkg('app-arch','tar').
core_pkg('app-arch','xz-utils').
core_pkg('app-shells','bash').
core_pkg('dev-build','cmake').
core_pkg('dev-lang','perl').
core_pkg('dev-lang','python').
core_pkg('dev-libs','libpcre').
core_pkg('net-misc','iputils').
core_pkg('net-misc','rsync').
core_pkg('net-misc','wget').
core_pkg('sys-apps','baselayout').
core_pkg('sys-apps','coreutils').
core_pkg('sys-apps','diffutils').
core_pkg('sys-apps','file').
core_pkg('sys-apps','findutils').
core_pkg('sys-apps','gawk').
core_pkg('sys-apps','grep').
core_pkg('sys-apps','kbd').
core_pkg('sys-apps','less').
core_pkg('sys-apps','sed').
core_pkg('sys-apps','util-linux').
core_pkg('sys-devel','automake').
core_pkg('sys-devel','binutils').
core_pkg('sys-devel','gcc').
core_pkg('sys-devel','gnuconfig').
core_pkg('sys-devel','make').
core_pkg('sys-devel','patch').
core_pkg('sys-fs','e2fsprogs').
core_pkg('sys-libs','libcap').
core_pkg('sys-libs','ncurses').
core_pkg('sys-libs','readline').
core_pkg('sys-process','procps').
core_pkg('sys-process','psmisc').
core_pkg('virtual','dev-manager').
core_pkg('virtual','editor').
core_pkg('virtual','libc').
core_pkg('virtual','man').
core_pkg('virtual','modutils').
core_pkg('virtual','os-headers').
core_pkg('virtual','package-manager').
core_pkg('virtual','pager').
core_pkg('virtual','service-manager').
core_pkg('virtual','shadow').
core_pkg('virtual','ssh').
core_pkg('sys-libs','pam').
core_pkg('dev-lang','pypy').


% Main predicate using foldl/3
process_build_with_use(Directives, Context, Result) :-
    foldl(process_use(Context), Directives, [], Result).
/*
% Helper predicate for foldl/3
process_use(_Context, use(enable(Use), _), Acc, [required(Use), assumed(Use)|Acc]).
process_use(_Context, use(disable(Use), _), Acc, [naf(required(Use)), assumed(minus(Use))|Acc]).

process_use(Context,  use(equal(Use), _), Acc, [required(Use), assumed(Use)|Acc]) :-
    memberchk(assumed(Use), Context), !.
process_use(_Context, use(equal(_Use), none), Acc, Acc).
process_use(_Context, use(equal(Use), positive), Acc, [required(Use), assumed(Use)|Acc]).
process_use(_Context, use(equal(Use), negative), Acc, [naf(required(Use)), assumed(minus(Use))|Acc]).

process_use(Context,  use(inverse(Use), _), Acc, [naf(required(Use)), assumed(minus(Use))|Acc]) :-
    (memberchk(assumed(Use), Context); preference:use(Use)), !.
process_use(_Context, use(inverse(_Use), none), Acc, Acc).
process_use(_Context, use(inverse(Use), positive), Acc, [required(Use), assumed(Use)|Acc]).
process_use(_Context, use(inverse(Use), negative), Acc, [naf(required(Use)), assumed(minus(Use))|Acc]).

process_use(Context,  use(optenable(Use), _), Acc, [required(Use), assumed(Use)|Acc]) :-
    (memberchk(assumed(Use), Context); preference:use(Use)), !.
process_use(_Context, use(optenable(_Use), none), Acc, Acc).
process_use(_Context, use(optenable(Use), positive), Acc, [required(Use), assumed(Use)|Acc]).
process_use(_Context, use(optenable(Use), negative), Acc, [naf(required(Use)), assumed(minus(Use))|Acc]).

process_use(Context,  use(optdisable(Use), _), Acc, [naf(required(Use)), assumed(minus(Use))|Acc]) :-
    memberchk(assumed(minus(Use)), Context), !.
process_use(_Context, use(optdisable(_Use), none), Acc, Acc).
process_use(_Context, use(optdisable(Use), positive), Acc, [required(Use), assumed(Use)|Acc]).
process_use(_Context, use(optdisable(Use), negative), Acc, [naf(required(Use)), assumed(minus(Use))|Acc]).
*/
% Catch-all for unrecognized directives
process_use(_Context, _, Acc, Acc).



/*

% Predicates used within rules

%! process_build_with_use(List,CurrentContext,NewContext)
%
% Given a list of build_with_use requirements from a package dependency, the context of the current Ebuild,
% processes the requirements and produces a context to be passed on to the chosen ebuild

% 1. no (further) requirements for target

process_build_with_use([],_Context,[]) :- !.


% 2. use should be enabled for target

process_build_with_use([use(enable(Use),_)|Rest],Context,[required(Use),assumed(Use)|Others]) :-
  !,process_build_with_use(Rest,Context,Others).

% 3. use should be disabled for target

process_build_with_use([use(disable(Use),_)|Rest],Context,[naf(required(Use)),assumed(minus(Use))|Others]) :-
  !,process_build_with_use(Rest,Context,Others).


% 4. use should set equal in target as in current ebuild

process_build_with_use([use(equal(Use),_)|Rest],Context,[required(Use),assumed(Use)|Others]) :-
  memberchk(assumed(Use),Context),
  !,process_build_with_use(Rest,Context,Others).

% 4.1 use should be set equal in target, but isn't set in current, follow indicated default (none)

process_build_with_use([use(equal(_Use),none)|Rest],Context,Others) :-
  !,process_build_with_use(Rest,Context,Others).

% 4.2 use should be set equal in target, but isn't set in current, follow indicated default (positive)

process_build_with_use([use(equal(Use),positive)|Rest],Context,[required(Use),assumed(Use)|Others]) :-
  !,process_build_with_use(Rest,Context,Others).

% 4.3 use should be set equal in target, but isn't set in current, follow indicated default (negative)

process_build_with_use([use(equal(Use),negative)|Rest],Context,[naf(required(Use)),assumed(minus(Use))|Others]) :-
  !,process_build_with_use(Rest,Context,Others).


% 5. use should set in target to the inverse of current ebuild

process_build_with_use([use(inverse(Use),_)|Rest],Context,[naf(required(Use)),assumed(minus(Use))|Others]) :-
  (memberchk(assumed(Use),Context);preference:use(Use)),
  !,process_build_with_use(Rest,Context,Others).

% 5.1. use should be set inverse in target, but isn't set in current, following indicated default (none)

process_build_with_use([use(inverse(_Use),none)|Rest],Context,Others) :-
  !,process_build_with_use(Rest,Context,Others).

% 5.2. use should be set inverse in target, but isn't set in current, following indicated default (positive)

process_build_with_use([use(inverse(Use),positive)|Rest],Context,[required(Use),assumed(Use)|Others]) :-
  !,process_build_with_use(Rest,Context,Others).

% 5.3. use should be set inverse in target, but isn't set in current, following indicated default (negative)

process_build_with_use([use(inverse(Use),negative)|Rest],Context,[naf(required(Use)),assumed(minus(Use))|Others]) :-
  !,process_build_with_use(Rest,Context,Others).


% 6. use should be enabled in target if enabled in current ebuild

process_build_with_use([use(optenable(Use),_)|Rest],Context,[required(Use),assumed(Use)|Others]) :-
  (memberchk(assumed(Use),Context);preference:use(Use)),
  !,process_build_with_use(Rest,Context,Others).

% 6.1 use should be enabled in target if enabled in current ebuild, but isn't set in current, following indicated default (none)

process_build_with_use([use(optenable(_Use),none)|Rest],Context,Others) :-
  !,process_build_with_use(Rest,Context,Others).

% 6.2 use should be enabled in target if enabled in current ebuild, but isn't set in current, following indicated default (positive)

process_build_with_use([use(optenable(Use),positive)|Rest],Context,[required(Use),assumed(Use)|Others]) :-
  !,process_build_with_use(Rest,Context,Others).

% 6.3 use should be enabled in target if enabled in current ebuild, but isn't set in current, following indicated default (negative)

process_build_with_use([use(optenable(Use),negative)|Rest],Context,[naf(required(Use)),assumed(minus(Use))|Others]) :-
  !,process_build_with_use(Rest,Context,Others).


% 7. use should be disabled in target if disabled in current ebuild

process_build_with_use([use(optdisable(Use),_)|Rest],Context,[naf(required(Use)),assumed(minus(Use))|Others]) :-
  memberchk(assumed(minus(Use)),Context),
  !,process_build_with_use(Rest,Context,Others).

% 7.1 use should be disabled in target if disabled in current ebuild, but isn't set in current, following indicated default (none)

process_build_with_use([use(optdisable(_Use),none)|Rest],Context,Others) :-
  !,process_build_with_use(Rest,Context,Others).

% 7.2 use should be disabled in target if disabled in current ebuild, but isn't set in current, following indicated default (positive)

process_build_with_use([use(optdisable(Use),positive)|Rest],Context,[required(Use),assumed(Use)|Others]) :-
  !,process_build_with_use(Rest,Context,Others).

% 7.3 use should be disabled in target if disabled in current ebuild, but isn't set in current, following indicated default (negative)

process_build_with_use([use(optdisable(Use),negative)|Rest],Context,[naf(required(Use)),assumed(minus(Use))|Others]) :-
  !,process_build_with_use(Rest,Context,Others).


process_build_with_use([_|Rest],Context,Others) :-
  !,
  process_build_with_use(Rest,Context,Others).

*/
