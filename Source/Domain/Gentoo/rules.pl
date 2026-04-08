/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> RULES
Domain rules for the Gentoo package resolver.

Each clause of rules:rule(+Literal, -Conditions) defines when a literal
holds and what sub-goals must be proved for it.  The prover drives proof
search by calling rule/2; this file supplies the domain knowledge that
tells the prover what "installing a package" or "satisfying a dependency"
actually means in a Gentoo context.

Helper predicates used by these rules live in the Rules/ submodules.

== Submodules ==

| Module        | Responsibility                                          |
|---------------|---------------------------------------------------------|
| candidate.pl  | Candidate selection, slot merging, CN-consistency,      |
|               | blocker matching, keyword helpers, any_of validation    |
| featureterm.pl| Proof-context list helpers (module: featureterm)        |
| dependency.pl | Self-entry injection, USE-requirement collection,       |
|               | slot/build-with-use propagation in ?{Context} lists     |
| heuristic.pl  | Prover hooks: constraint guard, cycle classification,   |
|               | proof obligations (PDEPEND), reprove state, debugging   |
| memo.pl       | Thread-local caching declarations, clear_caches/0       |
| target.pl     | Target resolution, update/downgrade transactions,       |
|               | depclean rewriting, --exclude / --rebuild-if-* helpers  |
| use.pl        | USE flag evaluation, conditionals, build_with_use,      |
|               | newuse, REQUIRED_USE, BWU cross-dep conflict detection  |

== Rule sections ==

  1. *Ebuild targets* -- target resolution, download, fetchonly,
     install, run, reinstall, uninstall, update, downgrade.
  2. *Dependency resolution* -- package_dependency/8 (weak/strong
     blockers), grouped_package_dependency/4, depclean traversal.
  3. *USE conditionals* -- use_conditional_group/4 (positive/negative).
  4. *Choice groups* -- exactly_one_of, at_most_one_of, any_of, all_of.
  5. *Required USE / blocking / prover primitives* -- naf, conflict, assumed.
*/

:- module(rules, [rule/2]).


% =============================================================================
%  Rule declarations
% =============================================================================
%
%  Each rule/2 clause maps a literal to a list of proof conditions.
%  The prover calls rules:rule(+Literal, -Conditions) to expand the proof
%  tree.  Conditions may include sub-goals (proved recursively),
%  constraint/1 terms (merged into the constraint store), and assumed/1
%  terms (domain assumptions recorded in the proof).
%
%  == Delegation protocol ==
%
%  Ebuild-level rules delegate to two predicates:
%
%    candidate:eligible(R://E:Action?{Context})
%        Guard. Succeeds when the candidate exists and passes all
%        visibility filters (keyword acceptance, masking, license).
%        Produces no conditions; failure causes the prover to backtrack
%        to the next candidate.
%
%    candidate:resolve(Literal, Conditions)
%        Worker. Computes the proof conditions for the given literal.
%        What comes back in Conditions depends on the literal kind:
%
%        Ebuild actions (R://E:Action?{Ctx}):
%          - constraint(selected_cn(C,N):{...})   candidate selection
%          - constraint(cn_domain(C,N,Slot):{...})  version domain (per-slot)
%          - constraint(selected_slot(C,N):{...})  slot occupancy
%          - R://E:download?{...}                  download sub-goal
%          - grouped_package_dependency(...)        dependency sub-goals
%          - R://Old:Action?{[replaces(...),...]}   replacement sub-goals
%
%        Blockers (weak_blocker / strong_blocker):
%          - constraint(blocked_cn_source(C,N):{...})  provenance tracking
%          - constraint(blocked_cn(C,N):{...})         hard block (strong only)
%          - assumed(blocker(...))                      soft assumption
%
%        Grouped deps (grouped_dep(C,N,Deps):Action?{Ctx}):
%          - []                                        self-satisfied / keep-installed
%          - constraint(selected_cn(C,N):{...}) + ...  candidate selection + deps
%          - assumed(non_existent(...))                 assumption fallback
%
%  See Documentation/Diagrams/rules_dispatch.dot for a visual overview.


% =============================================================================
%  Ruleset: TARGET
% =============================================================================

% -----------------------------------------------------------------------------
%  Rule: Target candidate (defer selection to prover)
% -----------------------------------------------------------------------------
%
% An unresolved target literal has the form:
%
%   target(Q, Arg):Action?{Ctx}
%
% where:
% - Query     is a parsed `qualified_target/6` term (see `eapi:qualified_target//1`)
% - WorldAtom is the original CLI atom (used for @world registration)
%
% Candidate selection happens inside the proof via `query:search/2`, so the
% prover can backtrack through alternatives under conflicts/constraints.
%
%
% Note on target candidate selection: 
% 
% Candidate selection is by default version-descending.
%   
% When the target specifies only category/name visible candidates 
% (i.e. not masked, keyword-accepted, not license-masked) are tried first.
% This avoids needlessly unmasking a live ebuild when another release
% that satisfies the request is available.  

% When an explicit version is given, all candidates are tried 
% in standard order because the user intentionally picked that version.
% This may result in the prover unmasking the specifically requested version.


% 1. Fetchonly target: resolve query to a candidate and prove the fetchonly action.
% 
% Portage-style fetchonly semantics for a requested target:
% - resolve query to a candidate
% - prove the fetchonly action
% 
% Fetchonly does not register the original atom in @world.

rule(target(Q, _Arg):fetchonly?{Context}, Conditions) :-
  !,
  target:resolve_candidate(Q, Repository://Ebuild),
  Conditions = [Repository://Ebuild:fetchonly?{Context}].


% 2. Uninstall target: resolve query to an installed candidate and prove the uninstall action.
%
% Portage-style uninstall semantics for a requested target:
% - resolve query to an installed candidate
% - prove the uninstall action
% - then unregister the original atom from @world (unless --oneshot)

rule(target(Q, Arg):uninstall?{Context}, Conditions) :-
  !,
  target:resolve_installed_candidate(Q, Repository://Ebuild),
  ( preference:flag(oneshot) 
    -> WorldConds = []
    ;  WorldConds = [world(Arg):unregister?{[after(Repository://Ebuild:uninstall)]}]
  ),
  Conditions = [Repository://Ebuild:uninstall?{Context}|WorldConds].


% 3. Run target: resolve the candidate and prove the run action.
%
% Portage-style merge semantics for a requested target:
% - prove the run action
% - then register the original atom in @world (unless --oneshot)
%
% Cases to consider: 
% --exclude:  skip atoms matching config:excluded_atom/1.
% --nodeps:   resolve target without proving dependencies.
% --onlydeps: prove deps only, exclude the target from the plan.
% --oneshot:  prove the run action, but do not register the original atom in @world.

rule(target(Q, Arg):run?{Context}, Conditions) :-
  !,
  target:resolve_candidate(Q, Repository://Ebuild),

  ( target:is_excluded(Repository://Ebuild) ->
      Conditions = []

  ; preference:flag(nodeps) ->
      Conditions = [Repository://Ebuild:install?{Context}]

  ; preference:flag(onlydeps) ->
      Conditions = [Repository://Ebuild:run?{[onlydeps_target|Context]}]

  ; preference:flag(oneshot) ->
      Conditions = [Repository://Ebuild:run?{Context}]

  ;   Conditions = [Repository://Ebuild:run?{Context},
                    world(Arg):register?{[after(Repository://Ebuild:run)]}]
  ).


% =============================================================================
%  Ruleset: WORLD
% =============================================================================

% -----------------------------------------------------------------------------
%  Rule: World registration & unregistration
% -----------------------------------------------------------------------------
%
% We encode @world modifications as proof/plan actions so they can be scheduled
% relative to other actions (e.g. after a merge).
%
% A world literal has the form world(Atom):Action?{Context}, where Action
% is `register` or `unregister` and Atom is the original CLI atom.

rule(world(_Arg):_Action?{Context}, Conditions) :-
  !,
  featureterm:get(after, Context, Conditions).


% =============================================================================
%  Ruleset: EBUILD TARGET
% =============================================================================

% -----------------------------------------------------------------------------
%  Rule: Ebuild fetchonly
% -----------------------------------------------------------------------------
%
% Fetchonly schedules the download of an ebuild and its dependency tree.
% Virtual & acct packages skip the actual download since they have no distfiles.
%
% eligible: candidate exists, keyword-accepted
% resolve : download sub-goal + install dependency sub-goals

rule(Repository://Ebuild:fetchonly?{Context}, Conditions) :-
  !,
  candidate:eligible(Repository://Ebuild:fetchonly?{Context}),
  ( candidate:installed(Repository://Ebuild),
    \+ preference:flag(emptytree) ->
      Conditions = []
  ; candidate:resolve(Repository://Ebuild:fetchonly?{Context}, Conditions)
  ).


% -----------------------------------------------------------------------------
%  Rule: Ebuild download
% -----------------------------------------------------------------------------
%
% Any ebuild can be downloaded.
%
% eligible: candidate exists
% resolve : constraint(download_url(...))

rule(Repository://Ebuild:download?{Context}, Conditions) :-
  !,
  candidate:eligible(Repository://Ebuild:download?{Context}),
  candidate:resolve(Repository://Ebuild:download?{Context}, Conditions).


% -----------------------------------------------------------------------------
%  Rule: Ebuild install
% -----------------------------------------------------------------------------
%
% An ebuild is installed when either already present (VDB) or all build
% prerequisites are met.
%
% eligible: candidate exists, keyword-accepted
% resolve : REQUIRED_USE constraints
%         + download sub-goal (unless virtual/acct-*)
%         + compile-time dependency sub-goals
%         + slot occupancy constraint

rule(Repository://Ebuild:install?{Context}, Conditions) :-
  !,
  candidate:eligible(Repository://Ebuild:install?{Context}),
  ( candidate:installed(Repository://Ebuild),
    \+ preference:flag(emptytree) ->
      Conditions = []
  ; preference:flag(nodeps) ->
      Conditions = []
  ; candidate:resolve(Repository://Ebuild:install?{Context}, Conditions)
  ).


% -----------------------------------------------------------------------------
%  Rule: Ebuild run
% -----------------------------------------------------------------------------
%
% An ebuild can be run when already installed (VDB) or when it is installed
% and all runtime dependencies are satisfied.
%
% eligible: candidate exists, keyword-accepted
% resolve : install sub-goal + runtime dependency sub-goals

rule(Repository://Ebuild:run?{Context}, Conditions) :-
  !,
  candidate:eligible(Repository://Ebuild:run?{Context}),
  ( candidate:installed(Repository://Ebuild),
    \+ preference:flag(emptytree) ->
      ( config:avoid_reinstall(true) ->
          Conditions = []
      ; featureterm:set(reinstall, Repository://Ebuild, Context, Conditions)
      )
  ; candidate:resolve(Repository://Ebuild:run?{Context}, Conditions)
  ).


% -----------------------------------------------------------------------------
%  Rule: Ebuild reinstall
% -----------------------------------------------------------------------------
%
% An ebuild can be reinstalled, when:
%
% - it is reportedly installed, and the emptytree flag is not set.

rule(Repository://Ebuild:reinstall?{_},[]) :-
  \+(preference:flag(emptytree)),
  candidate:installed(Repository://Ebuild),!.


% -----------------------------------------------------------------------------
%  Rule: Ebuild uninstall
% -----------------------------------------------------------------------------
%
% An ebuild can be uninstalled, when:
%
% - it is reportedly installed, and we are not proving emptytree

rule(Repository://Ebuild:uninstall?{_},[]) :-
  \+(preference:flag(emptytree)),
  candidate:installed(Repository://Ebuild),!.


% -----------------------------------------------------------------------------
%  Rule: Ebuild update
% -----------------------------------------------------------------------------
%
% Same-slot replacement with a higher version.
%
% eligible: candidate exists, keyword-accepted, installed entry present
% resolve : R://Old:run?{[replaces(...),...]} replacement sub-goal

rule(Repository://Ebuild:update?{Context}, Conditions) :-
  !,
  candidate:eligible(Repository://Ebuild:update?{Context}),
  candidate:resolve(Repository://Ebuild:update?{Context}, Conditions).


% -----------------------------------------------------------------------------
%  Rule: Ebuild downgrade
% -----------------------------------------------------------------------------
%
% Same-slot replacement with a lower version.
%
% eligible: candidate exists, keyword-accepted, installed entry present
% resolve : R://Old:run?{[replaces(...),...]} replacement sub-goal

rule(Repository://Ebuild:downgrade?{Context}, Conditions) :-
  !,
  candidate:eligible(Repository://Ebuild:downgrade?{Context}),
  candidate:resolve(Repository://Ebuild:downgrade?{Context}, Conditions).


% -----------------------------------------------------------------------------
%  Rule: Ebuild upgrade
% -----------------------------------------------------------------------------
%
% Cross-slot transition: replace an installed entry in one slot with a
% newer entry in a different (higher) slot.
%
% eligible: candidate exists, keyword-accepted, installed entry in different slot
% resolve : R://Old:run?{[replaces(...),...]} replacement sub-goal

rule(Repository://Ebuild:upgrade?{Context}, Conditions) :-
  !,
  candidate:eligible(Repository://Ebuild:upgrade?{Context}),
  candidate:resolve(Repository://Ebuild:upgrade?{Context}, Conditions).


% -----------------------------------------------------------------------------
%  Rule: Ebuild depclean
% -----------------------------------------------------------------------------
%
% Walks the runtime dependency graph of an installed ebuild to compute
% the "kept" closure (reachable installed packages).
%
% resolve : runtime dependency sub-goals rewritten as :depclean
%         | [] when model cannot be computed

rule(Repository://Ebuild:depclean?{Context}, Conditions) :-
  candidate:resolve(Repository://Ebuild:depclean?{Context}, Conditions).


% =============================================================================
%  Ruleset: DEPENDENCIES
% =============================================================================
%
% Ebuilds declare their dependencies as package_dependency terms, produced
% by the EAPI grammar when parsing the ebuild's DEPEND/RDEPEND/BDEPEND fields.
%
% The prover first runs a :config phase to determine which dependencies are 
% active, taking into account USE conditionals and other constraints.
% During this phase no package_dependencies are resolved, it is only checked 
% whether they are active or not, given the current context.
%
% After the :config phase, all surviving package_dependency terms for the same 
% category/name package are grouped into a single grouped_package_dependency.
% This grouping allows the resolver to consider all version constraints
% at once (e.g. ">=foo-1.0" and "<foo-3.0" become one selection problem)
% and pick the best candidate satisfying all of them at once.


% -----------------------------------------------------------------------------
%  Rule: package_dependency
% -----------------------------------------------------------------------------

% The config-phase does not generate proof conditions for package dependencies.
%
% If this is a self-dependency, we need to check if it is satisfiable.
% If it is not satisfiable, we need to backtrack and pick e.g. a bootstrap 
% alternative in an any_of_group.

rule(package_dependency(Phase,no,C,N,O,V,S,_U):config?{Context},[]) :-
  candidate:is_self_dep(C, N, Phase, Context),
  !,
  candidate:self_dep_satisfiable(C, N, O, V, S, Context).

rule(package_dependency(_,_,_,_,_,_,_,_):config?{_},[]) :- !.


% -----------------------------------------------------------------------------
%  Rule: grouped_package_dependency
% -----------------------------------------------------------------------------

% Grouped package dependencies are used to resolve blockers and regular dependencies.


% Case 1: a weak blocker — assumed, never enforced as a hard constraint.
%
% resolve : constraint(blocked_cn_source) + assumed(blocker(...))

rule(grouped_package_dependency(weak,C,N,PackageDeps):_Action?{Context}, Conditions) :-
  !,
  candidate:resolve(weak_blocker(C,N,PackageDeps)?{Context}, Conditions).


% Case 2: a strong blocker — enforced when unconditional, assumed otherwise.
%
% resolve : constraint(blocked_cn) + constraint(blocked_cn_source) for unconditional
%         + assumed(blocker(...)) for USE-conditional

rule(grouped_package_dependency(strong,C,N,PackageDeps):_Action?{Context}, Conditions) :-
  !,
  candidate:resolve(strong_blocker(C,N,PackageDeps)?{Context}, Conditions).


% Case 3: regular grouped dependencies
%
% resolve : [] when self-satisfied or already installed (keep-installed)
%         : constraint(selected_cn) + constraint(cn_domain) + dep sub-goals
%         : assumed(non_existent(...)) as fallback

rule(grouped_package_dependency(no,C,N,PackageDeps):Action?{Context},Conditions) :-
  !,
  candidate:resolve(grouped_dep(C,N,PackageDeps):Action?{Context}, Conditions).


% -----------------------------------------------------------------------------
%  Depclean traversal rules
% -----------------------------------------------------------------------------
%
% depclean computes a closure over installed packages to find removable
% orphans. These rules walk the runtime dependency graph of each
% installed ebuild, following only packages that are themselves installed.

rule(grouped_package_dependency(no,C,N,PackageDeps):depclean?{_}, Conditions) :-
  !,
  candidate:resolve(grouped_dep(C,N,PackageDeps):depclean?{[]}, Conditions).

rule(grouped_package_dependency(_,_,_,_):depclean?{_}, []) :- !.


% =============================================================================
%  Ruleset: USE CONDITIONALS
% =============================================================================

% -----------------------------------------------------------------------------
%  Rule: Positive use conditional dependencies
% -----------------------------------------------------------------------------
%
% A positive use conditional group activates its deps when the USE flag
% is enabled — via context assumption, global profile, or ebuild IUSE.
%
% eligible: USE flag is active (context-assumed, global non-IUSE, or effective)
% resolve : dependency sub-goals annotated with the current action

rule(use_conditional_group(positive,Use,R://E,Deps):Action?{Context}, Conditions) :-
  candidate:eligible(use_conditional(positive, Use, R://E):Action?{Context}),
  !,
  candidate:resolve(use_conditional(Deps):Action?{Context}, Conditions).

rule(use_conditional_group(positive,_,_://_,_):_?{_},[]) :- !.


% -----------------------------------------------------------------------------
%  Rule: Negative use conditional dependencies
% -----------------------------------------------------------------------------
%
% A negative use conditional group activates its deps when the USE flag
% is disabled — via context assumption, global profile, or ebuild IUSE.
%
% eligible: USE flag is inactive (context-assumed minus, global minus/unset non-IUSE, or effective)
% resolve : dependency sub-goals annotated with the current action

rule(use_conditional_group(negative,Use,R://E,Deps):Action?{Context}, Conditions) :-
  candidate:eligible(use_conditional(negative, Use, R://E):Action?{Context}),
  !,
  candidate:resolve(use_conditional(Deps):Action?{Context}, Conditions).

rule(use_conditional_group(negative,_,_://_,_):_?{_},[]) :- !.


% -----------------------------------------------------------------------------
%  Rule: Bare use conditional fallback (global profile)
% -----------------------------------------------------------------------------
%
% When a bare use_conditional_group appears outside :validate (e.g. inside
% a bare any_of_group chain), fall back to global profile USE flags.

rule(use_conditional_group(positive,Use,_://_,Deps), Conditions) :-
  preference:global_use(Use), !,
  findall(D, member(D, Deps), Conditions).

rule(use_conditional_group(positive,_,_://_,_),[]) :- !.

rule(use_conditional_group(negative,Use,_://_,Deps), Conditions) :-
  preference:global_use(minus(Use)), !,
  findall(D, member(D, Deps), Conditions).

rule(use_conditional_group(negative,_,_://_,_),[]) :- !.


% =============================================================================
%  Ruleset: CHOICE GROUPS
% =============================================================================
%
% Choice groups pick one or more alternatives from a list of deps.
%
% They are evaluated in three situations:
%
%   1. :validate — REQUIRED_USE: check whether the ebuild's effective USE
%      flags satisfy the constraint (e.g. exactly one enabled). No proving.
%   2. :config — Config phase: choose an alternative and record it in the
%      dependency model so it survives into the resolve phase.
%   3. :Action — Resolve phase: choose an alternative, prove it, and reject
%      any choice that would degrade into a domain assumption.
%
% at_most_one_of and all_of allow choosing none; extra fallback
% clauses handle that case.


% -----------------------------------------------------------------------------
%  Rule: Exactly one of (^^)
% -----------------------------------------------------------------------------
%
% :validate : exactly one dep must be satisfied
% :config   : pick one alternative, record in model
% :Action   : prove the chosen alternative

rule(exactly_one_of_group(Deps):validate?{Context}, Conditions) :-
  !,
  candidate:resolve(required_use(exactly_one_of, Deps):validate?{Context}, Conditions).

rule(exactly_one_of_group(Deps):Action?{Context}, Conditions) :-
  !,
  candidate:resolve(choice_group(Deps):Action?{Context}, Conditions).


% -----------------------------------------------------------------------------
%  Rule: At most one of (??)
% -----------------------------------------------------------------------------
%
% :validate : at most one dep must be satisfied
% :config   : pick one alternative or none, record in model
% :Action   : prove the chosen alternative or negate all

rule(at_most_one_of_group(Deps):validate?{Context}, Conditions) :-
  !,
  candidate:resolve(required_use(at_most_one_of, Deps):validate?{Context}, Conditions).

rule(at_most_one_of_group(Deps):Action?{Context}, Conditions) :-
  candidate:resolve(choice_group(Deps):Action?{Context}, Conditions),
  !.
rule(at_most_one_of_group(Deps):_?{_}, NafDeps) :-
  findall(naf(N), member(N, Deps), NafDeps).


% -----------------------------------------------------------------------------
%  Rule: Any of (||)
% -----------------------------------------------------------------------------
%
% :validate : at least one dep must be satisfied
% :config   : pick one alternative, record in model
% :Action   : prove the chosen alternative

rule(any_of_group(Deps):validate?{Context}, Conditions) :-
  !,
  candidate:resolve(required_use(any_of, Deps):validate?{Context}, Conditions).

rule(any_of_group(Deps):Action?{Context}, Conditions) :-
  !,
  candidate:resolve(choice_group(Deps):Action?{Context}, Conditions).


% -----------------------------------------------------------------------------
%  Rule: All of
% -----------------------------------------------------------------------------
%
% resolve : all dependency sub-goals

rule(all_of_group(Deps):Action?{Context}, Conditions) :-
  findall(D:Action?{Context}, member(D, Deps), Conditions), !.

rule(all_of_group(Deps), Conditions) :-
  findall(D, member(D, Deps), Conditions), !.


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

% During :validate, the current ebuild is available via self(...) in the
% context. Requirements satisfied by effective USE (IUSE defaults +
% profile/env/package.use) become non-assumptions. This prevents choice
% groups from arbitrarily enabling the first alternative.

rule(required(Use):_?{Context},[]) :-
  \+Use =.. [minus,_],
  use:effective_use_in_context(Context, Use, positive),
  !.

rule(required(minus(Use)):_?{Context},[]) :-
  \+Use =.. [minus,_],
  use:effective_use_in_context(Context, Use, negative),
  !.

% Context-aware fallback: when not satisfied by effective USE, delegate
% to bare rules for assumption/conflict handling.

rule(required(Use):_?{_}, Conditions) :-
  rule(required(Use), Conditions).

rule(required(minus(Use)):_?{_}, Conditions) :-
  rule(required(minus(Use)), Conditions).

rule(required(minus(Use)),[minus(Use)]) :-
  \+Use =.. [minus,_],
  preference:global_use(minus(Use)),!.

rule(required(Use),[Use]) :-
  \+Use =.. [minus,_],
  preference:global_use(Use),!.

rule(required(Use),[assumed(conflict(required,Use))]) :-
  \+Use =.. [minus,_],
  preference:global_use(minus(Use)),!.

rule(required(minus(Use)),[assumed(conflict(required,minus(Use)))]) :-
  \+Use =.. [minus,_],
  preference:global_use(Use),!.

rule(required(minus(Use)),[assumed(minus(Use))]) :-
  \+Use =.. [minus,_],
  \+preference:global_use(Use),
  \+preference:global_use(minus(Use)),!.

rule(required(Use),[assumed(Use)]) :-
  \+Use =.. [minus,_],
  \+preference:global_use(Use),
  \+preference:global_use(minus(Use)),!.


% -----------------------------------------------------------------------------
%  Rule: Blocking use
% -----------------------------------------------------------------------------

% Context-aware: when self/1 is available (e.g. during :validate),
% use effective USE for the ebuild.

rule(blocking(Use):_?{Context},[]) :-
  \+Use =.. [minus,_],
  use:effective_use_in_context(Context, Use, negative),
  !.

rule(blocking(minus(Use)):_?{Context},[]) :-
  \+Use =.. [minus,_],
  use:effective_use_in_context(Context, Use, positive),
  !.

% Context-aware fallback: when not satisfied by effective USE, delegate
% to bare rules for assumption/conflict handling.

rule(blocking(Use):_?{_}, Conditions) :-
  \+Use =.. [minus,_],
  rule(blocking(Use), Conditions).

rule(blocking(minus(Use)):_?{_}, Conditions) :-
  \+Use =.. [minus,_],
  rule(blocking(minus(Use)), Conditions).

% Global profile fallback (bare literals, no context).

rule(blocking(minus(Use)),[Use]) :-
  \+Use =.. [minus,_],
  preference:global_use(Use),!.

rule(blocking(Use),[minus(Use)]) :-
  \+Use =.. [minus,_],
  preference:global_use(minus(Use)),!.

rule(blocking(Use),[assumed(conflict(blocking,Use))]) :-
  \+Use =.. [minus,_],
  preference:global_use(Use),!.

rule(blocking(minus(Use)),[assumed(conflict(blocking,minus(Use)))]) :- % test needed
  \+Use =.. [minus,_],
  preference:global_use(minus(Use)),!.

rule(blocking(minus(Use)),[assumed(minus(Use)),naf(required(Use))]) :- % this doesnet make sense I think)
  \+Use =.. [minus,_],
  \+preference:global_use(Use),
  \+preference:global_use(minus(Use)),!.

rule(blocking(Use),[assumed(minus(Use)),naf(required(Use))]) :-
  \+Use =.. [minus,_],
  \+preference:global_use(Use),
  \+preference:global_use(minus(Use)),!.


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
  ( preference:global_use(Use) -> C = [conflict(Use,naf(required(Use)))] ; C = []).

rule(naf(Statement),C) :-
  Statement =.. [blocking,Use],!,
  ( preference:global_use(minus(Use)) -> C = [conflict(Use,naf(blocking(Use)))] ; C = [] ).

% Conflicts:

rule(conflict(A,B),[assumed(conflict(A,B))]) :-
  candidate:assume_conflicts,
  !.
rule(conflict(_,_),[]) :- !,
  fail.

% The default rule, prover takes care of negation

rule(naf(_),[]) :- !.

% Atoms

rule(Literal,[]) :-
  atom(Literal),!.
