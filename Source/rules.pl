/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

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
  findall(Ss,cache:entry_metadata(Repository,Ebuild,slot,Ss),S),

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

  % 4. Compute + memoize dependency model, already grouped by package Category & Name.

  query:memoized_search(model(dependency(MergedDeps0,fetchonly)):config?{Model},Repository://Ebuild),
  add_self_to_dep_contexts(Repository://Ebuild, MergedDeps0, MergedDeps),

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
  findall(Ss,cache:entry_metadata(Repository,Ebuild,slot,Ss),S),

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

  % 4. Compute + memoize dependency model, already grouped by package Category & Name.

  query:memoized_search(model(dependency(MergedDeps0,install)):config?{Model},Repository://Ebuild),
  add_self_to_dep_contexts(Repository://Ebuild, MergedDeps0, MergedDeps),

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
  findall(Ss,cache:entry_metadata(Repository,Ebuild,slot,Ss),S),

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

  % 4. Compute + memoize dependency model, already grouped by package Category & Name.

  query:memoized_search(model(dependency(MergedDeps0,run)):config?{Model},Repository://Ebuild),
  add_self_to_dep_contexts(Repository://Ebuild, MergedDeps0, MergedDeps),

  % 5. Pass on relevant package dependencies and constraints to prover

  % If another version is already installed in the same slot, then "merge" should
  % translate into a transactional same-slot replacement (Portage-style), i.e.
  % NewVersion:update (replaces OldVersion), rather than a plain NewVersion:install.
  ( \+ preference:flag(emptytree),
    rules:entry_slot_default(Repository, Ebuild, SlotNew),
    rules:installed_entry_cn(C, N, OldRepo, OldEbuild),
    OldEbuild \== Ebuild,
    % If the installed entry is no longer in the repo set, we may not have its
    % slot metadata. In that case, assume it matches the slot of the replacement
    % entry (this mirrors Portage's ability to read slot from /var/db/pkg).
    ( cache:entry_metadata(OldRepo, OldEbuild, slot, slot(SlotOld0))
      -> rules:canon_slot(SlotOld0, SlotOld)
      ;  SlotOld = SlotNew
    ),
    SlotOld == SlotNew
  ->
    % IMPORTANT: do NOT thread slot(C,N,...) through action contexts. Slot is a
    % prover-level constraint (see constraint(slot(...))) and should not influence
    % grouped dependency candidate selection (it would incorrectly constrain := deps).
    InstallOrUpdate = Repository://Ebuild:update?{[replaces(OldRepo://OldEbuild),required_use(R),build_with_use(B)]}
  ; InstallOrUpdate = Repository://Ebuild:install?{[required_use(R),build_with_use(B)]}
  ),
  Conditions = [constraint(use(Repository://Ebuild):{R}),
                constraint(slot(C,N,S):{Ebuild}),
                InstallOrUpdate
                |MergedDeps].


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

% Wrapper: updating an *installed* entry selects a replacement version (same slot)
% and schedules the actual transactional update on that replacement version.
rule(Repository://Ebuild:update?{Context},Conditions) :-
  \+ memberchk(replaces(_), Context),
  \+(preference:flag(emptytree)),
  preference:accept_keywords(K),
  % Determine the installed version + identity (C/N) from the concrete entry.
  cache:ordered_entry(Repository, Ebuild, Category, Name, VersionInstalled),
  cache:entry_metadata(Repository, Ebuild, installed, true),
  % Find the latest acceptable version for this C/N in the repo set.
  % Update semantics stay within the same slot (upgrade semantics cross slots and
  % will be introduced later).
  ( cache:entry_metadata(Repository, Ebuild, slot, slot(SlotInstalled))
    -> query:search([name(Name),category(Category),keywords(K),slot(SlotInstalled),version(VersionLatest)],LatestRepo://LatestEbuild)
    ;  query:search([name(Name),category(Category),keywords(K),version(VersionLatest)],LatestRepo://LatestEbuild)
  ),
  compare(>,VersionLatest,VersionInstalled),
  !,
  % IMPORTANT: represent the update as a single transactional action on the
  % *new* version, annotated with the old version it replaces.
  Conditions = [LatestRepo://LatestEbuild:update?{[replaces(Repository://Ebuild)|Context]}].

% If the user targets a specific version with :update and it is not installed,
% treat it as a transactional same-slot replacement when an older version is
% installed, otherwise fall back to a plain install.
rule(Repository://Ebuild:update?{Context},Conditions) :-
  \+ memberchk(replaces(_), Context),
  \+(preference:flag(emptytree)),
  cache:ordered_entry(Repository, Ebuild, Category, Name, _VersionNew),
  \+ cache:entry_metadata(Repository, Ebuild, installed, true),
  % Try same-slot replacement first (if slot is known).
  ( rules:entry_slot_default(Repository, Ebuild, SlotNew),
    rules:installed_entry_cn(Category, Name, OldRepo, OldEbuild),
    ( cache:entry_metadata(OldRepo, OldEbuild, slot, slot(SlotOld0))
      -> rules:canon_slot(SlotOld0, SlotOld)
      ;  SlotOld = SlotNew
    ),
    SlotOld == SlotNew
  -> rules:update_txn_conditions(Repository://Ebuild, [replaces(OldRepo://OldEbuild)|Context], Conditions)
  ;  Conditions = [Repository://Ebuild:install?{Context}]
  ),
  !.

% Otherwise, updating an already-installed version is a no-op (already current or
% no acceptable newer version).
rule(Repository://Ebuild:update?{_Context},[]) :-
  cache:entry_metadata(Repository, Ebuild, installed, true),
  !.

% Actual transactional update on a chosen replacement entry. This action is
% responsible for the "remove old + merge new" atomicity inside the same slot.
rule(Repository://Ebuild:update?{Context},Conditions) :-
  memberchk(replaces(_OldRepo://_OldEbuild), Context),
  !,
  rules:update_txn_conditions(Repository://Ebuild, Context, Conditions).


% -----------------------------------------------------------------------------
%  Rule: Upgrade target
% -----------------------------------------------------------------------------
% An ebuild can be upgraded, when:
%
% - it is reportedly installed, and the emptytree flag is not set,
% - a higher version is available,
% - the accept_keywords filter is satisfied.

% Upgrade logic will be introduced later (world/set upgrades + --deep).

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
%  Rule: Dependencies on the system profile / core packages
% -----------------------------------------------------------------------------

% In emptytree mode, we treat a small set of "core" packages as provided by the
% system profile / baseline and *do not* force model construction to resolve them.
% This keeps emptytree proofs from exploding into "build the whole OS" graphs.
%
% Note: core package handling during actual dependency *resolution* happens in
% the grouped dependency rule below (`grouped_package_dependency/4`), not here.
rule(package_dependency(_Phase,no,C,N,_O,_V,_S,_U):config?{_Context}, []) :-
    preference:flag(emptytree),
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

% In config-phase dependency model construction, package deps normally do not
% generate further conditions. However, for self-hosting dependencies (a package
% depending on itself to build/install), we must ensure the dependency is actually
% satisfiable *without* selecting the current ebuild (unless already installed).
% This allows any_of_group to backtrack to bootstrap alternatives (e.g. go vs
% go-bootstrap) during model construction, before the model is memoized.
rule(package_dependency(Phase,no,C,N,O,V,S,_U):config?{Context},[]) :-
  ( memberchk(self(SelfRepo://SelfEntry), Context),
    cache:ordered_entry(SelfRepo, SelfEntry, C, N, _),
    Phase \== run,
    \+ preference:flag(emptytree)
  ->
    preference:accept_keywords(K),
    ( memberchk(slot(C,N,Ss):{_}, Context) -> true ; Ss = _ ),
    query:search([name(N),category(C),keyword(K),installed(true),
                  select(version,O,V),select(slot,constraint(S),Ss)],
                 _FoundRepo//Candidate),
    Candidate = Candidate
  ; true
  ),
  !.
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
  % Self-dependency at runtime is trivially satisfied: once the package is built,
  % it provides itself. Treat this generically to avoid hard failures on packages
  % that (redundantly) list themselves in RDEPEND.
  ( Action == run,
    memberchk(self(SelfRepo://SelfEntry), Context),
    cache:ordered_entry(SelfRepo, SelfEntry, C, N, _)
  ->
    Conditions = []
  ; preference:flag(emptytree),
    core_pkg(C,N)
  ->
    Conditions = []
  ; \+ preference:flag(emptytree),
    \+ preference:flag(deep),
    merge_slot_restriction(Action, C, N, PackageDeps, SlotReq),
    once(query:search([repository(pkg),category(C),name(N),installed(true),
                       select(slot,constraint(SlotReq),_)],
                      pkg://InstalledEntry)),
    forall(member(package_dependency(Action,no,C,N,O,V,_,_), PackageDeps),
           query:search(select(version,O,V), pkg://InstalledEntry))
  ->
    Conditions = []
  ;
    ( preference:accept_keywords(K),
      (memberchk(slot(C,N,Ss):{_}, Context) -> true ; true),
      merge_slot_restriction(Action, C, N, PackageDeps, SlotReq),

      % Candidate selection (portage / overlays)
      ( Action \== run,
        memberchk(self(SelfRepo0://SelfEntry0), Context),
        cache:ordered_entry(SelfRepo0, SelfEntry0, C, N, _)
      ->
        \+ preference:flag(emptytree),
        query:search([name(N),category(C),keyword(K),installed(true),
                      select(slot,constraint(SlotReq),Ss)], FoundRepo://Candidate)
      ; query:search([name(N),category(C),keyword(K),
                      select(slot,constraint(SlotReq),Ss)], FoundRepo://Candidate)
      ),

      % Avoid resolving a dep to self unless candidate is already installed
      ( ( memberchk(self(_SelfRepo://SelfEntry1), Context)
        ; memberchk(slot(C,N,_SelfSlot):{SelfEntry1}, Context)
        ),
        Candidate == SelfEntry1
      ->
        \+ preference:flag(emptytree),
        cache:entry_metadata(FoundRepo, Candidate, installed, true)
      ; true
      ),

      forall(member(package_dependency(Action,no,C,N,O,V,_,_), PackageDeps),
             query:search(select(version,O,V), FoundRepo://Candidate)),

      findall(U, member(package_dependency(Action,no,C,N,_O,_V,_,U),PackageDeps), MergedUse),
      process_build_with_use(MergedUse,Context,NewContext,Constraints,FoundRepo://Candidate),
      process_slot(SlotReq,Ss,C,N,FoundRepo://Candidate,NewContext,NewerContext),

      % Prefer expressing as update when a pkg-installed entry exists and the chosen
      % candidate is newer.
      ( \+ preference:flag(emptytree),
        once(query:search([repository(pkg),category(C),name(N),installed(true),
                           select(slot,constraint(SlotReq),_)],
                          pkg://InstalledEntry2)),
        InstalledEntry2 \== Candidate,
        cache:ordered_entry(pkg, InstalledEntry2, C, N, OldVer),
        cache:ordered_entry(FoundRepo, Candidate, C, N, NewVer),
        compare(>, NewVer, OldVer)
      ->
        ActionGoal = FoundRepo://Candidate:update?{[replaces(pkg://InstalledEntry2)|NewerContext]}
      ; ActionGoal = FoundRepo://Candidate:Action?{NewerContext}
      ),

      append(Constraints, [ActionGoal], Conditions)
    ; % In --deep mode we *prefer* upgrades, but we should not create domain
      % assumptions when the dependency is already installed in the vdb (`pkg`)
      % and satisfies constraints. Instead, fall back to "keep installed".
      ( preference:flag(deep),
        merge_slot_restriction(Action, C, N, PackageDeps, SlotReq2),
        once(query:search([repository(pkg),category(C),name(N),installed(true),
                           select(slot,constraint(SlotReq2),_)],
                          pkg://InstalledEntryFallback)),
        forall(member(package_dependency(Action,no,C,N,O2,V2,_,_), PackageDeps),
               query:search(select(version,O2,V2), pkg://InstalledEntryFallback))
      ->
        Conditions = []
      ; explanation:assumption_reason_for_grouped_dep(Action, C, N, PackageDeps, Context, Reason),
        Conditions = [assumed(grouped_package_dependency(C,N,PackageDeps):Action?{[assumption_reason(Reason)|Context]})]
      )
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
  prioritize_deps(Deps, SortedDeps),
  member(D, SortedDeps),
  findall(naf(N),(member(N,Deps), \+(D = N)),NafDeps).

rule(exactly_one_of_group(Deps),[D|NafDeps]) :-
  prioritize_deps(Deps, SortedDeps),
  member(D, SortedDeps),
  findall(naf(N),(member(N,Deps), \+(D = N)),NafDeps).


% -----------------------------------------------------------------------------
%  Rule: At most one of group
% -----------------------------------------------------------------------------
% At most one of the dependencies in an at-most-one-of-group should be satisfied

rule(at_most_one_of_group(Deps):Action?{Context},[D:Action?{Context}|NafDeps]) :-
  prioritize_deps(Deps, SortedDeps),
  member(D, SortedDeps),
  findall(naf(N),(member(N,Deps), \+(D = N)),NafDeps).

rule(at_most_one_of_group(Deps),[D|NafDeps]) :-
  prioritize_deps(Deps, SortedDeps),
  member(D, SortedDeps),
  findall(naf(N),(member(N,Deps), \+(D = N)),NafDeps).


% -----------------------------------------------------------------------------
%  Rule: Any of group
% -----------------------------------------------------------------------------
% One dependency of an any_of_group should be satisfied

rule(any_of_group(Deps):Action?{Context}, Conditions) :-
  prioritize_deps(Deps, SortedDeps),
  member(D, SortedDeps),
  rule(D:Action?{Context}, Conditions),
  !.

rule(any_of_group(Deps), Conditions) :-
  prioritize_deps(Deps, SortedDeps),
  member(D, SortedDeps),
  rule(D, Conditions),
  !.


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

% Domain-level assumption: rules can emit `assumed(X)` in a body to represent an
% unprovable domain fact (e.g. missing dependency or conflict resolution).
% The prover will prove such literals via this rule, and store them in the proof
% as `rule(assumed(X))` (distinct from prover cycle-break keys `assumed(rule(X))`).
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
%  Helper: merge_slot_restriction
% -----------------------------------------------------------------------------
% Derive the (single) slot restriction to apply when selecting a candidate for a
% grouped dependency. If no slot restriction is present, return [].
% If multiple distinct slot restrictions are present, fail (no candidate can satisfy all).

merge_slot_restriction(Action, C, N, PackageDeps, SlotReq) :-
  % Performance note: this predicate is called very frequently during proving.
  % Avoid findall/3 + sort/2 and instead scan once, ensuring all non-empty slot
  % restrictions are identical.
  merge_slot_restriction_(PackageDeps, Action, C, N, none, Slot0),
  ( Slot0 == none -> SlotReq = []
  ; SlotReq = Slot0
  ).

merge_slot_restriction_([], _Action, _C, _N, Acc, Acc) :- !.
merge_slot_restriction_([package_dependency(Action,no,C,N,_O,_V,S,_U)|Rest], Action, C, N, Acc0, Acc) :-
  !,
  ( S == []      -> Acc1 = Acc0
  ; Acc0 == none -> Acc1 = S
  ; Acc0 == S    -> Acc1 = Acc0
  ; fail
  ),
  merge_slot_restriction_(Rest, Action, C, N, Acc1, Acc).
merge_slot_restriction_([_|Rest], Action, C, N, Acc0, Acc) :-
  merge_slot_restriction_(Rest, Action, C, N, Acc0, Acc).


% =============================================================================
%  Ruleset: Dependency group helpers
% =============================================================================

% -----------------------------------------------------------------------------
%  Helper: prioritize_deps
% -----------------------------------------------------------------------------
% Sorts dependencies by prioritizing those that match user preferences, to
% reduce the number of assumptions in the proof.

prioritize_deps(Deps, SortedDeps) :-
  partition(is_preferred_dep, Deps, Preferred, Others),
  append(Preferred, Others, SortedDeps).

is_preferred_dep(required(Use)) :-
  Use \= minus(_),
  preference:use(Use).
is_preferred_dep(required(minus(Use))) :-
  preference:use(minus(Use)).

% -----------------------------------------------------------------------------
%  Helper: add_self_to_dep_contexts
% -----------------------------------------------------------------------------
% Annotate dependency literals with provenance of the "current ebuild" so that
% downstream dependency-resolution rules can make safe choices (e.g. avoid
% resolving a dependency to the current ebuild unless it is already installed),
% without polluting memoized model keys.

add_self_to_dep_contexts(_Self, [], []) :- !.
add_self_to_dep_contexts(Self, [D0|Rest0], [D|Rest]) :-
  ( D0 = Term:Action?{Ctx} ->
      ( memberchk(self(Self), Ctx) ->
          D = D0
      ; D = Term:Action?{[self(Self)|Ctx]}
      )
  ; D = D0
  ),
  add_self_to_dep_contexts(Self, Rest0, Rest).

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
% Do not "lock" explicit slot requirements into the shared context.
% Many ecosystems (notably Ruby) legitimately require multiple slots to coexist
% in the same plan (e.g. dev-lang/ruby:3.2 and dev-lang/ruby:3.3). If we store a
% single chosen slot in the context, later deps for a different explicit slot
% will fail to resolve and get misreported as "non-existent".
process_slot([slot(_)], _SlotMeta, _C, _N, _Repository://_Candidate, Context, Context) :- !.
process_slot(_, Slot, C, N, _Repository://Candidate, Context, [slot(C, N, Slot):{Candidate}|Context]).

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



% Shared implementation of transactional update prerequisites for Repository://Ebuild.
% Context MUST contain replaces(OldRepo://OldEbuild).
rules:update_txn_conditions(Repository://Ebuild, Context, Conditions) :-
  % 1. Compute required_use stable model for the *new* version, extend with build_with_use
  (findall(Item,
          (member(build_with_use(InnerList), Context),
           member(Item,InnerList)),
          B)),
  (memberchk(required_use(R),Context) -> true ; R = []),
  query:search(model(Model,required_use(R),build_with_use(B)),Repository://Ebuild),

  % 2. Compute + memoize dependency model (grouped), for the *new* version.
  query:memoized_search(model(dependency(MergedDeps0,install)):config?{Model},Repository://Ebuild),
  add_self_to_dep_contexts(Repository://Ebuild, MergedDeps0, MergedDeps),

  % Optional: deep update means "also update dependency packages".
  % We model this by scheduling update goals for any installed dependency package
  % that appears in the dependency model.
  ( preference:flag(deep)
  -> rules:deep_update_goals(Repository://Ebuild, MergedDeps, DeepUpdates)
  ;  DeepUpdates = []
  ),

  % 3. Pass on relevant package dependencies and constraints to prover.
  cache:ordered_entry(Repository, Ebuild, CNew, NNew, _),
  findall(Ss,cache:entry_metadata(Repository,Ebuild,slot,Ss),SAll),
  ( memberchk(CNew,['virtual','acct-group','acct-user'])
    -> Base = [ constraint(use(Repository://Ebuild):{R}),
                constraint(slot(CNew,NNew,SAll):{Ebuild})
                |DeepUpdates],
       append(Base, MergedDeps, Conditions)
    ;  Base = [ constraint(use(Repository://Ebuild):{R}),
                constraint(slot(CNew,NNew,SAll):{Ebuild}),
                Repository://Ebuild:download?{[required_use(R),build_with_use(B)]}
                |DeepUpdates],
       append(Base, MergedDeps, Conditions)
  ).

% Collect update goals for installed dependency packages from a grouped dependency model.
rules:deep_update_goals(Self, MergedDeps, DeepUpdates) :-
  ( preference:accept_keywords(K)
    -> KeywordQ = [keywords(K)]
    ;  KeywordQ = []
  ),
  findall(C-N, (member(Dep, MergedDeps), rules:dep_cn(Dep, C, N)), CN0),
  sort(CN0, CN),
  findall(NewRepo://NewEntry:update?{[replaces(OldRepo://OldEntry)]},
          ( member(C-N, CN),
            % For each dependency package, look at installed instances (possibly multiple slots).
            query:search([category(C),name(N),installed(true)], OldRepo://OldEntry),
            OldRepo://OldEntry \== Self,
            cache:ordered_entry(OldRepo, OldEntry, C, N, OldVer),
            % Only deep-update within the same slot if we can determine it.
            cache:entry_metadata(OldRepo, OldEntry, slot, slot(Slot)),
            % Pick the newest acceptable candidate in that slot.
            ( KeywordQ == []
              -> Query = [category(C),name(N),slot(Slot),version(NewVer)]
              ;  Query = [category(C),name(N),slot(Slot),keywords(K),version(NewVer)]
            ),
            query:search(Query, NewRepo://NewEntry),
            compare(>, NewVer, OldVer)
          ),
          Updates0),
  sort(Updates0, DeepUpdates).

rules:dep_cn(grouped_package_dependency(_,C,N,_):_Action?{_Ctx}, C, N) :- !.
rules:dep_cn(grouped_package_dependency(C,N,_):_Action?{_Ctx}, C, N) :- !.
% Concrete dependency literals (already resolved to a specific entry):
%   Repo://Entry:install?{...}
%   Repo://Entry:run?{...}
%   Repo://Entry:config?{...}
% etc.
rules:dep_cn(Repo://Entry:_Action?{_Ctx}, C, N) :-
  cache:ordered_entry(Repo, Entry, C, N, _),
  !.
rules:dep_cn(Repo://Entry:_Action, C, N) :-
  cache:ordered_entry(Repo, Entry, C, N, _),
  !.


% Determine a package slot for planning decisions.
% If explicit slot metadata exists, use it; otherwise treat it as slot 0.
rules:entry_slot_default(Repo, Entry, Slot) :-
  ( cache:entry_metadata(Repo, Entry, slot, slot(Slot0))
    -> rules:canon_slot(Slot0, Slot)
    ;  Slot = '0'
  ).

% Normalize slot values so comparisons work even when some facts use numbers and
% others use atoms.
rules:canon_slot(S0, S) :-
  ( atom(S0)   -> S = S0
  ; integer(S0) -> number_atom(S0, S)
  ; number(S0)  -> number_atom(S0, S)
  ; S = S0
  ),
  !.

% Find an installed entry for the given category/name, even if it isn't present
% as an ordered_entry (e.g. when the installed version no longer exists in the
% active repository set).
rules:installed_entry_cn(C, N, pkg, Entry) :-
  % The installed package database is represented by the VDB repository instance
  % named `pkg`. Prefer using its structured facts instead of parsing Entry IDs
  % with atom_concat/sub_atom (which is extremely expensive at scale).
  cache:ordered_entry(pkg, Entry, C, N, _),
  cache:entry_metadata(pkg, Entry, installed, true),
  !.