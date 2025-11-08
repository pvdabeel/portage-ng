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


% =============================================================================
%  RULES declarations
% =============================================================================

% =============================================================================
%  Ruleset: Ebuild targets
% =============================================================================

% -----------------------------------------------------------------------------
%  Rule: Download target
% -----------------------------------------------------------------------------
% Any ebuild can be downloaded.

rule(Repository://Ebuild:download?{_},[]) :-
  !,
  query:search(ebuild(Ebuild),Repository://Ebuild).


% -----------------------------------------------------------------------------
%  Rule: Fetchonly target
% -----------------------------------------------------------------------------
% Fetchonly downloads the ebuild and its dependency tree.
%
% The dependency tree is computed by passing the use model onto the dependencies
% to calculate the corresponding dependency model.
%
% 1. Don't perform downloads for already installed packages, unless the emptytree
%    flag is specified.
%
% 2. When a package is not installed, consider its dependencies, taking into
%    account slot and use restrictions. We consider both runtime as well as
%    compile time dependencies at the same time, since downloading doesn't impose
%    a specific order on handling the dependencies.
%
% We don't trigger downloads for virtual, acct-group or acct-user, since they
% don't have any downloads.

rule(Repository://Ebuild:fetchonly?{Context},Conditions) :- % todo: to update in line with new :install and :run rules
  !,
  query:search(masked(true),   Repository://Ebuild) -> Conditions = [] ;
  query:search(installed(true),Repository://Ebuild), \+preference:flag(emptytree) -> Conditions = [] ;

  % 1. Get some metadata we need further down

  cache:ordered_entry(Repository,Ebuild,C,N,_),
  cache:entry_metadata(Repository,Ebuild,slot,S),

  % 2. Compute required_use stable model

  (findall(Item,
          (member(build_with_use(InnerList), Context),
           member(Item,InnerList)),
          B)),

  (memberchk(required_use(R),Context) -> true ; true),

  query:search(model(Model,required_use(R),build_with_use(B)),Repository://Ebuild),

  % 3. Pass use model onto dependencies to calculate corresponding dependency  model,
  %    We pass using config action to avoid package_dependency from generating choices.
  %    The config action triggers use_conditional, any_of_group, exactly_one_of_group,
  %    all_of_group ... choice point generation

  query:memoized_search(model(dependency(D,fetchonly)):config?{Model},Repository://Ebuild),

  % 4. Group packagedependencies by package Category & Name. We want to deal with all
  %    dependencies regarding the same package in one go.

  query:group_dependencies(D,MergedDeps),

  % 5. Pass on relevant package dependencies and constraints to prover

  ( memberchk(C,['virtual','acct-group','acct-user'])
    -> Conditions = [constraint(use(Repository://Ebuild):{R}),
                     constraint(slot(C,N,S):{Ebuild})
                     |MergedDeps]
    ;  Conditions = [constraint(use(Repository://Ebuild):{R}),
                     constraint(slot(C,N,S):{Ebuild}),
                     Repository://Ebuild:download?{R}
                     |MergedDeps] )
   ; Conditions = [assumed(Repository://Ebuild:install?{[issue_with_model(explanation)|Context]})].


% -----------------------------------------------------------------------------
%  Rule: Install target
% -----------------------------------------------------------------------------
% An ebuild is installed, when either:
%
% - Metadata indicates it is installed, and the emptytree flag is not set
%
% or, if the following conditions are satisfied:
%
% - Its require_use dependencies are satisfied,
% - It is downloaded (Only when it is not a virtual, a group or a user),
% - Its compile-time dependencies are satisfied,
% - it can occupy an installation slot.
%
% We don't trigger downloads for virtual, acct-group or acct-user.

rule(Repository://Ebuild:install?{Context},Conditions) :-
  !,
  query:search(masked(true),   Repository://Ebuild) -> Conditions = [] ;
  query:search(installed(true),Repository://Ebuild), \+preference:flag(emptytree) -> Conditions = [] ; % todo check new build_with_use requirements


  % 1. Get some metadata we need further down

  cache:ordered_entry(Repository,Ebuild,C,N,_),
  cache:entry_metadata(Repository,Ebuild,slot,S),

  % 2. Compute required_use stable model, if not already passed on by run
  %    Extend with build_with_use requirements

  (findall(Item,
          (member(build_with_use(InnerList), Context),
           member(Item,InnerList)),
          B)),

  % (memberchk(build_with_use(B),Context) -> true ; B = []),
  (memberchk(required_use(R),Context) -> true ; true),

  query:search(model(Model,required_use(R),build_with_use(B)),Repository://Ebuild),

  % 3. Pass use model onto dependencies to calculate corresponding dependency  model,
  %    We pass using config action to avoid package_dependency from generating choices.
  %    The config action triggers use_conditional, any_of_group, exactly_one_of_group,
  %    all_of_group ... choice point generation

  query:memoized_search(model(dependency(D,install)):config?{Model},Repository://Ebuild),

 % 4. Group packagedependencies by package Category & Name. We want to deal with all
  %    dependencies regarding the same package in one go.

  query:group_dependencies(D,MergedDeps),

  % 5. Pass on relevant package dependencies and constraints to prover

  ( memberchk(C,['virtual','acct-group','acct-user'])
    -> Conditions = [ constraint(use(Repository://Ebuild):{R}),
                    constraint(slot(C,N,S):{Ebuild})
                    |MergedDeps]
    ;  Conditions = [ constraint(use(Repository://Ebuild):{R}),
                    constraint(slot(C,N,S):{Ebuild}),
                    Repository://Ebuild:download?{[required_use(R),build_with_use(B)]}
                    |MergedDeps] )
  ; Conditions = [assumed(Repository://Ebuild:install?{[issue_with_model(explanation)|Context]})].


% -----------------------------------------------------------------------------
%  Rule: Run target
% -----------------------------------------------------------------------------
% An ebuild can be run, either:
%
% - it is reportedly installed, and the emptytree flag is not set,
%
% or:
%
% - if it is installed and if its runtime dependencies are satisfied
%
% Accepted in context:
%
% - build_with_use(B)

rule(Repository://Ebuild:run?{Context},Conditions) :-
  !,
  % 0. Check if the ebuild is masked or installed
  query:search(masked(true),   Repository://Ebuild) -> Conditions = [] ;
  query:search(installed(true),Repository://Ebuild), \+preference:flag(emptytree) -> (config:avoid_reinstall(true) -> Conditions = [] ; Conditions = [Repository://Ebuild:reinstall?{Context}]) ; % todo check new build_with_use requirements

  % 1. Get some metadata we need further down

  cache:ordered_entry(Repository,Ebuild,C,N,_),
  cache:entry_metadata(Repository,Ebuild,slot,S),

  % 2. Compute required_use stable model, extend with build_with_use requirements

  (findall(Item,
          (member(build_with_use(InnerList), Context),
           member(Item,InnerList)),
          B)),

  % (memberchk(build_with_use(B),Context) -> true ; B = []),

  query:search(model(Model,required_use(R),build_with_use(B)),Repository://Ebuild),

  % 3. Pass use model onto dependencies to calculate corresponding dependency  model,
  %    We pass using config action to avoid package_dependency from generating choices.
  %    The config action triggers use_conditional, any_of_group, exactly_one_of_group,
  %    all_of_group ... choice point generation

  query:memoized_search(model(dependency(D,run)):config?{Model},Repository://Ebuild),

  % 4. Group packagedependencies by package Category & Name. We want to deal with all
  %    dependencies regarding the same package in one go.

  query:group_dependencies(D,MergedDeps),

  % 5. Pass on relevant package dependencies and constraints to prover

  Conditions = [constraint(use(Repository://Ebuild):{R}),
                constraint(slot(C,N,S):{Ebuild}),
                Repository://Ebuild:install?{[required_use(R),build_with_use(B),slot(C,N,S):{Ebuild}]}|MergedDeps].


% -----------------------------------------------------------------------------
%  Rule: Reinstall target
% -----------------------------------------------------------------------------
% An ebuild can be reinstalled, when:
%
% - it is reportedly installed, and the emptytree flag is not set.

rule(Repository://Ebuild:reinstall?{_},[]) :-
  \+(preference:flag(emptytree)),
  query:search(installed(true),Repository://Ebuild),!. % todo: retrieve installation context


% -----------------------------------------------------------------------------
%  Rule: Uninstall target
% -----------------------------------------------------------------------------
% An ebuild can be uninstalled, when:
%
% - it is reportedly installed, and we are not proving emptytree

rule(Repository://Ebuild:uninstall?{_},[]) :-
  \+(preference:flag(emptytree)),
  query:search(installed(true),Repository://Ebuild),!.

% Note: this may leave the Model and Proof for the other packages incomplete - todo: implement depclean.


% -----------------------------------------------------------------------------
%  Rule: Update target
% -----------------------------------------------------------------------------
% An ebuild can be updated, when:
%
% - it is reportedly installed, and the emptytree flag is not set,
% - a higher version is available,
% - the accept_keywords filter is satisfied.

rule(Repository://Ebuild:update?{Context},Conditions) :-
  \+(preference:flag(emptytree)),
  preference:accept_keywords(K),
  query:search([name(Name),category(Category),keywords(K),slot(S),installed(true),version(VersionInstalled)],Repository://Ebuild),
  query:search([name(Name),category(Category),keywords(K),slot(S),version(VersionLatest)],Repository://LatestEbuild),!, % todo: check cut
  compare(>,VersionLatest,VersionInstalled)
  -> Conditions = [Repository://Ebuild:uninstall?{Context},Repository://LatestEbuild:install?{Context}]
  ;  Conditions = [].

% todo: deep


% -----------------------------------------------------------------------------
%  Rule: Upgrade target
% -----------------------------------------------------------------------------
% An ebuild can be upgraded, when:
%
% - it is reportedly installed, and the emptytree flag is not set,
% - a higher version is available,
% - the accept_keywords filter is satisfied.

rule(Repository://Ebuild:update?{Context},Conditions) :-
  \+(preference:flag(emptytree)),
  preference:accept_keywords(K),
  query:search([name(Name),category(Category),keywords(K),installed(true),version(VersionInstalled)],Repository://Ebuild),
  query:search([name(Name),category(Category),keywords(K),version(VersionLatest)],Repository://LatestEbuild),!, % todo: check cut
  compare(>,VersionLatest,VersionInstalled)
  -> Conditions = [Repository://Ebuild:uninstall?{Context},Repository://LatestEbuild:install?{Context}]
  ;  Conditions = [].

% todo: deep


% =============================================================================
%  Ruleset: Dependency resolution
% =============================================================================
%
% Ebuilds use package dependencies to express relations (conflicts or requirements)
% on other ebuilds.
%
% Ebuilds use package dependencies to express relations (conflicts or requirements) on
% other ebuilds.


% -----------------------------------------------------------------------------
%  Rule: Conflicting package
% -----------------------------------------------------------------------------
% EAPI 8.2.6.2: a weak block can be ignored by the package manager

rule(package_dependency(_,weak,_,_,_,_,_,_):_?{_},[]) :- !.


% -----------------------------------------------------------------------------
%  Rule: Conflicting package
% -----------------------------------------------------------------------------
% EAPI 8.2.6.2: a strong block is satisfied when no suitable candidate is satisfied

rule(package_dependency(_,strong,_,_,_,_,_,_):_?{_},[]) :- !.


% -----------------------------------------------------------------------------
%  Rule: Dependencies on the system profile
% -----------------------------------------------------------------------------

rule(package_dependency(_,no,C,N,_,_,_,_):_?{_}, []) :-
    core_pkg(C,N), !.


% -----------------------------------------------------------------------------
%  Rule: Package dependencies
% -----------------------------------------------------------------------------
% A package dependency is satisfied when a suitable candidate is satisfied,
% a package dependency that has no suitable candidates is "assumed" satisfied
%
% Portage-ng will identify these assumptions in its proof and show them to the
% user prior to continuing to the next stage (i.e. executing the plan).

% Preference: prefer installed packages over new packages, unless 'emptytree' flag
% is used


% package dependency rules for dependency model creation

rule(package_dependency(_,_,_,_,_,_,_,_):config?{_},[]) :- !.
rule(package_dependency(_,no,_,_,_,_,_,_),[]) :- !.


% -----------------------------------------------------------------------------
%  Rule: Conflicting package
% -----------------------------------------------------------------------------
% EAPI 8.2.6.2: a weak block can be ignored by the package manager

rule(grouped_package_dependency(weak,_,_,_):_?{_},[]) :- !.


% -----------------------------------------------------------------------------
%  Rule: Conflicting package
% -----------------------------------------------------------------------------
% EAPI 8.2.6.2: a strong block is satisfied when no suitable candidate is satisfied

rule(grouped_package_dependency(strong,_,_,_):_?{_},[]) :- !.


% =============================================================================
%  Rule: Package dependencies
% =============================================================================

rule(grouped_package_dependency(no,C,N,PackageDeps):Action?{Context},Conditions) :-
  !,
  ( % IF: The package is already installed and we are not doing a full tree build...
    (\+(preference:flag(emptytree)),
     cache:ordered_entry(Repository, Ebuild, C, N, _),
     cache:entry_metadata(Repository, Ebuild, installed, true));
    % OR : We are doing a full tree build and the package is a core package
    (preference:flag(emptytree),
     core_pkg(C,N))
  ->
    % THEN: Succeed immediately with no further conditions.
    !,
    Conditions = [] % todo: check build_with_use requirements here

  ; % ELSE: Proceed with the general resolution logic.
    % package_dependency(_,no,C,N,O,V,S,U):Action?{Context}

    (
      ( preference:accept_keywords(K),
        (memberchk(slot(C,N,Ss):{_}, Context) -> true ; true),

        findall(Query,(member(package_dependency(Action,no,C,N,O,V,S,U),PackageDeps),
                       Query = select(version,O,V)),
                      MergedQuery),

        query:search([name(N),category(C),keyword(K),select(slot,constraint(S),Ss)], FoundRepo://Candidate), % macro-expanded
        query:search(MergedQuery,FoundRepo://Candidate), % runtime

        findall(U,    (member(package_dependency(Action,no,C,N,O,V,S,U),PackageDeps)),
                      MergedUse),

        process_build_with_use(MergedUse,Context,NewContext,Constraints,FoundRepo://Candidate), % todo: check we look at combined use requirements here
        process_slot(S,Ss,C,N,FoundRepo://Candidate,NewContext,NewerContext),

        % Add build_with_use constraints to Conditions
        append(Constraints, [FoundRepo://Candidate:Action?{NewerContext}], AllConditions),
        Conditions = AllConditions )

    ; % ELSE: If no candidate can be found, assume it's non-existent.
      Conditions = [assumed(grouped_package_dependency(C,N,PackageDeps):Action?{Context})] % todo: fail
    )
  ).


% -----------------------------------------------------------------------------
%  Rule: Positive use conditional dependencies
% -----------------------------------------------------------------------------
% The dependencies in a positive use conditional group need to be satisfied when
% the use flag is positive through required use constraint, preference or ebuild
% default

% 1. The USE is enabled in the context (dependency induced, or required_use)

rule(use_conditional_group(positive,Use,_R://_E,Deps):Action?{Context},Conditions) :-
  memberchk(assumed(Use),Context),!,
  findall(D:Action?{Context},member(D,Deps),Conditions).

% 2. The USE is explicitely enabled, either by preference or ebuild -> process deps

rule(use_conditional_group(positive,Use,R://E,Deps):Action?{Context},Conditions) :-
  query:search(iuse(Use,positive:_Reason),R://E),!,
  findall(D:Action?{Context},member(D,Deps),Result),
  Conditions = Result.

% 3. The USE is not enabled -> no deps

rule(use_conditional_group(positive,_Use,_R://_E,_):_?{_},[]) :-
  !.


% -----------------------------------------------------------------------------
%  Rule: Negative use conditional dependencies
% -----------------------------------------------------------------------------
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

% 3. The USE is not enabled -> no deps

rule(use_conditional_group(negative,_Use,_R://_E,_):_?{_},[]) :-
  !.


% -----------------------------------------------------------------------------
%  Rule: Contextless use conditionals
% -----------------------------------------------------------------------------
% Contextless use conditionals are found in for example required_use constraints.

rule(use_conditional_group(positive,Use,_://_,Deps),Conditions) :-
  preference:use(Use),!,
  findall(D,member(D,Deps),Conditions).

rule(use_conditional_group(positive,_,_://_,_),[]) :- !.

rule(use_conditional_group(negative,Use,_://_,Deps),Conditions) :-
  preference:use(minus(Use)),!,
  findall(D,member(D,Deps),Conditions).

rule(use_conditional_group(negative,_,_://_,_),[]) :- !.


% -----------------------------------------------------------------------------
%  Rule: Exactly one of group
% -----------------------------------------------------------------------------
% Exactly one of the dependencies in an exactly-one-of-group should be satisfied

rule(exactly_one_of_group(Deps):Action?{Context},[D:Action?{Context}|NafDeps]) :-
  member(D,Deps),
  findall(naf(N),(member(N,Deps), \+(D = N)),NafDeps).

rule(exactly_one_of_group(Deps),[D|NafDeps]) :-
  member(D,Deps),
  findall(naf(N),(member(N,Deps), \+(D = N)),NafDeps).


% -----------------------------------------------------------------------------
%  Rule: At most one of group
% -----------------------------------------------------------------------------
% At most one of the dependencies in an at-most-one-of-group should be satisfied

rule(at_most_one_of_group(Deps):Action?{Context},[D:Action?{Context}|NafDeps]) :-
  member(D,Deps),
  findall(naf(N),(member(N,Deps), \+(D = N)),NafDeps).

rule(at_most_one_of_group(Deps),[D|NafDeps]) :-
  member(D,Deps),
  findall(naf(N),(member(N,Deps), \+(D = N)),NafDeps).


% -----------------------------------------------------------------------------
%  Rule: Any of group
% -----------------------------------------------------------------------------
% One dependency of an any_of_group should be satisfied

rule(any_of_group(Deps):Action?{Context},[D:Action?{Context}]) :-
  member(D,Deps).

rule(any_of_group(Deps),[D]) :-
  member(D,Deps).


% -----------------------------------------------------------------------------
%  Rule: All of group
% -----------------------------------------------------------------------------
% All dependencies in an all_of_group should be satisfied

rule(all_of_group(Deps):Action?{Context},Result) :-
  findall(D:Action?{Context},member(D,Deps),Result),!.

rule(all_of_group(Deps),Result) :-
  findall(D,member(D,Deps),Result),!.


% -----------------------------------------------------------------------------
%  Rule: Uri
% -----------------------------------------------------------------------------
% It is possible to put uri's in the proof, and verify at proof time whether
% downloads exists, are valid, etc. This makes the proofs unnecessarily large.
% In practice it is better to verify downloadability of a uri at proof execution
% time.

rule(uri(_,_,_):_,[]) :- !.
rule(uri(_):_,[]) :- !.


% -----------------------------------------------------------------------------
%  Rule: Required use
% -----------------------------------------------------------------------------

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


% -----------------------------------------------------------------------------
%  Rule: Blocking use
% -----------------------------------------------------------------------------

rule(blocking(minus(Use)),[Use]) :-
  \+Use =.. [minus,_],
  preference:use(Use),!.

rule(blocking(Use),[minus(Use)]) :-
  \+Use =.. [minus,_],
  preference:use(minus(Use)),!.

rule(blocking(Use),[assumed(conflict(blocking,Use))]) :-
  \+Use =.. [minus,_],
  preference:use(Use),!.

rule(blocking(minus(Use)),[assumed(conflict(blocking,minus(Use)))]) :- % test needed
  \+Use =.. [minus,_],
  preference:use(minus(Use)),!.

rule(blocking(minus(Use)),[assumed(minus(Use)),naf(required(Use))]) :- % this doesnet make sense I think)
  \+Use =.. [minus,_],
  \+preference:use(Use),
  \+preference:use(minus(Use)),!.

rule(blocking(Use),[assumed(minus(Use)),naf(required(Use))]) :-
  \+Use =.. [minus,_],
  \+preference:use(Use),
  \+preference:use(minus(Use)),!.



% -----------------------------------------------------------------------------
%  Rules needed by prover
% -----------------------------------------------------------------------------

% Assumptions:

rule(assumed(_),[]) :- !.


% Negation as failure:

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


% -----------------------------------------------------------------------------
%  Rule: Core packages
% -----------------------------------------------------------------------------
% Core packages are used to resolve dependencies on the system profile. This way
% we avoid unnecessary assumptions in the proof, since we know the system profile
% is always installed.

core_pkg('app-admin','eselect').
core_pkg('app-alternatives','awk').
core_pkg('app-alternatives','bzip2').
core_pkg('app-alternatives','gzip').
core_pkg('app-alternatives','sh').
core_pkg('app-alternatives','tar').
core_pkg('app-arch','bzip2').
core_pkg('app-arch','gzip').
core_pkg('app-arch','tar').
core_pkg('app-arch','xz-utils').
core_pkg('app-shells','bash').
core_pkg('dev-build','make').
core_pkg('net-mail','mailbase').
core_pkg('net-misc','iputils').
core_pkg('net-misc','rsync').
core_pkg('net-misc','wget').
core_pkg('sec-keys','openpgp-keys-gentoo-release').
core_pkg('sys-apps','baselayout').
core_pkg('sys-apps','coreutils').
core_pkg('sys-apps','diffutils').
core_pkg('sys-apps','file').
core_pkg('sys-apps','findutils').
core_pkg('sys-apps','gawk').
core_pkg('sys-apps','grep').
core_pkg('sys-apps','iproute2').
core_pkg('sys-apps','kbd').
core_pkg('sys-apps','kmod').
core_pkg('sys-apps','less').
core_pkg('sys-apps','man-pages').
core_pkg('sys-apps','net-tools').
core_pkg('sys-apps','sed').
core_pkg('sys-apps','shadow').
core_pkg('sys-apps','util-linux').
core_pkg('sys-apps','which').
core_pkg('sys-devel','binutils').
core_pkg('sys-devel','gcc').
core_pkg('sys-devel','gnuconfig').
core_pkg('sys-devel','patch').
core_pkg('sys-fs','e2fsprogs').
core_pkg('sys-process','procps').
core_pkg('sys-process','psmisc').
core_pkg('virtual','dev-manager').
core_pkg('virtual','editor').
core_pkg('virtual','libc').
core_pkg('virtual','man').
core_pkg('virtual','os-headers').
core_pkg('virtual','package-manager').
core_pkg('virtual','pager').
core_pkg('virtual','service-manager').
core_pkg('virtual','ssh').


% -----------------------------------------------------------------------------
%  Helper for process_slot
% -----------------------------------------------------------------------------

process_slot([any_different_slot], _, _, _, _, Context, Context) :- !.
process_slot(_, Slot, C, N, Candidate, Context, [slot(C, N, Slot):{Candidate}|Context]).

%process_slot([any_same_slot],Slot,Context,[slot(Slot)|Context]) :- !.
%process_slot([slot(X),equal],[slot(X)],Context,[slot([slot(X)])|Context]) :- !.
%process_slot(_,_,Context,Context).



% -----------------------------------------------------------------------------
%  Helper for process_build_with_use
% -----------------------------------------------------------------------------
% When processing build with use directives, we are given the current context
% as well as the directives. We extend the current context with the directives
% prior to passing it on to the child dependencies. We also return build_with_use
% constraints that should be added to the global constraint list.

% Main predicate using foldl/4 to process USE directives.
process_build_with_use(Directives, Context, [build_with_use(Result)|Context], Conditions, Candidate) :-
    foldl(process_use(Context), Directives, [], Result),
    build_with_use_constraints(Directives, Conditions, Candidate).

% Helper predicate to generate build_with_use constraints
% Collects all USE requirements into a single list to avoid data duplication
build_with_use_constraints([], [], _) :- !.
build_with_use_constraints(Directives, [constraint(use(Candidate):{UseRequirements})], Candidate) :-
    collect_use_requirements(Directives, UseRequirements).

% Helper predicate to collect all USE requirements into a single list
collect_use_requirements([], []).
collect_use_requirements([use(enable(Use), _)|Rest], [required(Use)|RestRequirements]) :-
    !,
    collect_use_requirements(Rest, RestRequirements).
collect_use_requirements([use(disable(Use), _)|Rest], [naf(required(Use))|RestRequirements]) :-
    !,
    collect_use_requirements(Rest, RestRequirements).
collect_use_requirements([use(equal(Use), _)|Rest], [required(Use)|RestRequirements]) :-
    !,
    collect_use_requirements(Rest, RestRequirements).
collect_use_requirements([use(inverse(Use), _)|Rest], [naf(required(Use))|RestRequirements]) :-
    !,
    collect_use_requirements(Rest, RestRequirements).
collect_use_requirements([use(optenable(Use), _)|Rest], [required(Use)|RestRequirements]) :-
    !,
    collect_use_requirements(Rest, RestRequirements).
collect_use_requirements([use(optdisable(Use), _)|Rest], [naf(required(Use))|RestRequirements]) :-
    !,
    collect_use_requirements(Rest, RestRequirements).
collect_use_requirements([_|Rest], RestRequirements) :-
    !,
    collect_use_requirements(Rest, RestRequirements).


% Helper predicate for foldl/4.
% It processes a single USE directive.

% Handles [opt] - The flag must be enabled.
process_use(_Context, use(enable(Use), _), Acc, [required(Use), assumed(Use)|Acc]).

% Handles [-opt] - The flag must be disabled.
process_use(_Context, use(disable(Use), _), Acc, [naf(required(Use)), assumed(minus(Use))|Acc]).

% Handles [opt=] - The flag must be enabled if enabled in the parent, disabled otherwise.
process_use(Context, use(equal(Use), _), Acc, [required(Use), assumed(Use)|Acc]) :-
    memberchk(assumed(Use), Context), !.								% this is broken, there is parent use info (i think)?
process_use(Context, use(equal(Use), _), Acc, [naf(required(Use)), assumed(minus(Use))|Acc]) :-
    \+ memberchk(assumed(Use), Context).								% item

% Handles [!opt=] - The flag must be disabled if enabled in the parent, enabled otherwise.
process_use(Context, use(inverse(Use), _), Acc, [naf(required(Use)), assumed(minus(Use))|Acc]) :-
    memberchk(assumed(Use), Context), !.								% idem
process_use(Context, use(inverse(Use), _), Acc, [required(Use), assumed(Use)|Acc]) :-
    \+ memberchk(assumed(Use), Context).

% Handles [opt?] - The flag must be enabled if enabled in the parent.
process_use(Context, use(optenable(Use), _), Acc, [required(Use), assumed(Use)|Acc]) :-
    (memberchk(assumed(Use), Context); preference:use(Use)), !.						% idem
process_use(_Context, use(optenable(_Use), _), Acc, Acc).

% Handles [!opt?] - The flag must be disabled if disabled in the parent.
process_use(Context, use(optdisable(Use), _), Acc, [naf(required(Use)), assumed(minus(Use))|Acc]) :-
    (memberchk(assumed(minus(Use)), Context); preference:use(minus(Use))), !.				% idem
process_use(_Context, use(optdisable(_Use), _), Acc, Acc).

% 4-style USE dependency defaults
% These are consulted when the conditional dependency is on a flag not in the parent's context.

% todo: this seems duplicate?

% For [opt=](+) or [!opt=](+)
process_use(_Context, use(equal(Use), positive), Acc, [required(Use), assumed(Use)|Acc]).
process_use(_Context, use(inverse(Use), positive), Acc, [required(Use), assumed(Use)|Acc]).
process_use(_Context, use(optenable(Use), positive), Acc, [required(Use), assumed(Use)|Acc]).
process_use(_Context, use(optdisable(Use), positive), Acc, [required(Use), assumed(Use)|Acc]).


% For [opt=](-) or [!opt=](-)
process_use(_Context, use(equal(Use), negative), Acc, [naf(required(Use)), assumed(minus(Use))|Acc]).
process_use(_Context, use(inverse(Use), negative), Acc, [naf(required(Use)), assumed(minus(Use))|Acc]).
process_use(_Context, use(optenable(Use), negative), Acc, [naf(required(Use)), assumed(minus(Use))|Acc]).
process_use(_Context, use(optdisable(Use), negative), Acc, [naf(required(Use)), assumed(minus(Use))|Acc]).

% For [opt=](none) or no default specified
process_use(_Context, use(equal(_Use), none), Acc, Acc).
process_use(_Context, use(inverse(_Use), none), Acc, Acc).
process_use(_Context, use(optenable(_Use), none), Acc, Acc).
process_use(_Context, use(optdisable(_Use), none), Acc, Acc).


% Catch-all for any other directives
process_use(_Context, _, Acc, Acc).
