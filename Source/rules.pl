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

:- use_module(library(ordsets)).
:- use_module(unify). % feature_unification:unify/3 (generic feature-term merge)
:- use_module('version.pl').

:- discontiguous rules:rule/2.

:- thread_local rules:effective_use_fact/3.

% -----------------------------------------------------------------------------
%  Prover hook: domain-driven goal enqueueing (single-pass extensions)
% -----------------------------------------------------------------------------
%
% The prover is kept domain-agnostic. It may call this hook after proving a
% literal to request additional goals to enqueue in the same prover run.
%
% Hook contract (called by prover):
%   rules:literal_hook(+Literal, +Model, -HookKey, -ExtraLits)
%
% This implementation provides Portage-like PDEPEND behavior when --pdepend is
% enabled:
% - PDEPEND deps are included in the transaction (proved in the same run),
% - but are NOT prerequisites of the parent merge action (anchored via after_only/1).
%
% IMPORTANT:
% - Must be monotonic and backtracking-safe (no global side effects).
% - Must not depend on Proof structure; HookKey is an opaque term.

% Lightweight perf sampling (used only when --pdepend is enabled).
% We sample 1 in N calls to avoid adding noticeable overhead.
rules:literal_hook_perf_reset :-
  flag(lit_hook_calls, _OldC, 0),
  flag(lit_hook_has_pdepend, _OldHP, 0),
  flag(lit_hook_no_pdepend, _OldNP, 0),
  flag(lit_hook_sample_n, _OldSN, 0),
  flag(lit_hook_sample_ms_sum, _OldSM, 0),
  !.

rules:literal_hook_perf_report :-
  flag(lit_hook_calls, Calls, Calls),
  flag(lit_hook_has_pdepend, HasP, HasP),
  flag(lit_hook_no_pdepend, NoP, NoP),
  flag(lit_hook_sample_n, SN, SN),
  flag(lit_hook_sample_ms_sum, SMs, SMs),
  ( SN =:= 0 ->
      AvgMs = 0,
      EstTotalMs = 0
  ; AvgMs is SMs / SN,
    EstTotalMs is AvgMs * Calls
  ),
  message:scroll_notice(['literal_hook perf: calls=',Calls,
                         ' has_pdepend=',HasP,
                         ' no_pdepend=',NoP,
                         ' sample_n=',SN,
                         ' sample_ms_sum=',SMs,
                         ' avg_ms=',AvgMs,
                         ' est_total_ms=',EstTotalMs]),
  nl,
  !.

rules:lit_hook_sample_rate(1000).

rules:lit_hook_maybe_sample(Goal) :-
  % Increment call count and sample periodically.
  flag(lit_hook_calls, C0, C0+1),
  rules:lit_hook_sample_rate(N),
  ( N =< 1 ->
      statistics(walltime, [T0,_]),
      ( Goal -> Ok = true ; Ok = false ),
      statistics(walltime, [T1,_]),
      Dt is T1 - T0,
      flag(lit_hook_sample_n, SN0, SN0+1),
      flag(lit_hook_sample_ms_sum, SM0, SM0+Dt),
      Ok == true
  ; C1 is C0 + 1,
    ( 0 is C1 mod N ->
        statistics(walltime, [T0,_]),
        ( Goal -> Ok = true ; Ok = false ),
        statistics(walltime, [T1,_]),
        Dt is T1 - T0,
        flag(lit_hook_sample_n, SN0, SN0+1),
        flag(lit_hook_sample_ms_sum, SM0, SM0+Dt),
        Ok == true
    ; Goal
    )
  ).

% Fast path for the prover: compute HookKey only (no dependency-model work).
% This lets the prover skip calling literal_hook/4 entirely when that key is
% already marked done in the evolving Proof.
%
% Extended fast path:
% `rules:literal_hook_key/4` also tells the prover whether the full hook can
% produce any extra literals at all (`NeedsFullHook=false`).
rules:literal_hook_key(Repo://Entry:Action?{_Ctx}, Model, HookKey) :-
  preference:flag(pdepend),
  ( Action == install ; Action == update ; Action == reinstall ),
  !,
  AnchorCore = (Repo://Entry:Action),
  % Fast path: most entries have no PDEPEND; avoid inspecting build_with_use.
  ( cache:entry_metadata(Repo, Entry, pdepend, _) ->
      ( get_assoc(AnchorCore, Model, AnchorCtx) -> true ; AnchorCtx = [] ),
      rules:context_build_with_use_state(AnchorCtx, B),
      HookKey = pdepend(AnchorCore, B)
  ; HookKey = pdepend_none(AnchorCore)
  ).
rules:literal_hook_key(Repo://Entry:Action, Model, HookKey) :-
  preference:flag(pdepend),
  ( Action == install ; Action == update ; Action == reinstall ),
  !,
  AnchorCore = (Repo://Entry:Action),
  ( cache:entry_metadata(Repo, Entry, pdepend, _) ->
      ( get_assoc(AnchorCore, Model, AnchorCtx) -> true ; AnchorCtx = [] ),
      rules:context_build_with_use_state(AnchorCtx, B),
      HookKey = pdepend(AnchorCore, B)
  ; HookKey = pdepend_none(AnchorCore)
  ).

rules:literal_hook_key(Repo://Entry:Action?{_Ctx}, Model, HookKey, NeedsFullHook) :-
  preference:flag(pdepend),
  ( Action == install ; Action == update ; Action == reinstall ),
  !,
  AnchorCore = (Repo://Entry:Action),
  % If this action will not result in a merge transaction, do not expand PDEPEND.
  % (E.g. `:install` can be satisfied by already-installed packages when not emptytree.)
  ( rules:literal_hook_will_merge(Repo://Entry:Action) ->
      ( cache:entry_metadata(Repo, Entry, pdepend, _) ->
          NeedsFullHook = true,
          ( get_assoc(AnchorCore, Model, AnchorCtx) -> true ; AnchorCtx = [] ),
          rules:context_build_with_use_state(AnchorCtx, B),
          HookKey = pdepend(AnchorCore, B)
      ; NeedsFullHook = false,
        HookKey = pdepend_none(AnchorCore)
      )
  ; NeedsFullHook = false,
    HookKey = pdepend_none(AnchorCore)
  ).
rules:literal_hook_key(Repo://Entry:Action, Model, HookKey, NeedsFullHook) :-
  preference:flag(pdepend),
  ( Action == install ; Action == update ; Action == reinstall ),
  !,
  AnchorCore = (Repo://Entry:Action),
  ( rules:literal_hook_will_merge(Repo://Entry:Action) ->
      ( cache:entry_metadata(Repo, Entry, pdepend, _) ->
          NeedsFullHook = true,
          ( get_assoc(AnchorCore, Model, AnchorCtx) -> true ; AnchorCtx = [] ),
          rules:context_build_with_use_state(AnchorCtx, B),
          HookKey = pdepend(AnchorCore, B)
      ; NeedsFullHook = false,
        HookKey = pdepend_none(AnchorCore)
      )
  ; NeedsFullHook = false,
    HookKey = pdepend_none(AnchorCore)
  ).

% Decide whether an action literal represents an actual merge transaction.
% For install actions, already-installed entries (when not emptytree) are no-ops.
rules:literal_hook_will_merge(_Repo://_Entry:reinstall) :- !, true.
rules:literal_hook_will_merge(_Repo://_Entry:update) :- !, true.
rules:literal_hook_will_merge(Repo://Entry:install) :-
  ( preference:flag(emptytree) ->
      true
  ; \+ query:search(installed(true), Repo://Entry) ->
      true
  ; false
  ),
  !.

rules:literal_hook(Repo://Entry:Action?{_Ctx}, Model, HookKey, ExtraLits) :-
  preference:flag(pdepend),
  ( Action == install ; Action == update ; Action == reinstall ),
  !,
  rules:lit_hook_maybe_sample(
    ( AnchorCore = (Repo://Entry:Action),
      ( cache:entry_metadata(Repo, Entry, pdepend, _) ->
          flag(lit_hook_has_pdepend, HP0, HP0+1),
          % Determine current build_with_use state from the anchor's model context.
          ( get_assoc(AnchorCore, Model, AnchorCtx) -> true ; AnchorCtx = [] ),
          rules:context_build_with_use_state(AnchorCtx, B),
          HookKey = pdepend(AnchorCore, B),
          ModelKey = [build_with_use:B],
          query:memoized_search(model(dependency(Pdeps0, pdepend)):config?{ModelKey}, Repo://Entry),
          rules:add_self_to_dep_contexts(Repo://Entry, Pdeps0, Pdeps1),
          rules:drop_build_with_use_from_dep_contexts(Pdeps1, Pdeps2),
          rules:add_after_only_to_dep_contexts(AnchorCore, Pdeps2, ExtraLits)
      ; flag(lit_hook_no_pdepend, NP0, NP0+1),
        HookKey = pdepend_none(AnchorCore),
        ExtraLits = []
      )
    )
  ).
rules:literal_hook(Repo://Entry:Action, Model, HookKey, ExtraLits) :-
  preference:flag(pdepend),
  ( Action == install ; Action == update ; Action == reinstall ),
  !,
  rules:lit_hook_maybe_sample(
    ( AnchorCore = (Repo://Entry:Action),
      ( cache:entry_metadata(Repo, Entry, pdepend, _) ->
          flag(lit_hook_has_pdepend, HP0, HP0+1),
          ( get_assoc(AnchorCore, Model, AnchorCtx) -> true ; AnchorCtx = [] ),
          rules:context_build_with_use_state(AnchorCtx, B),
          HookKey = pdepend(AnchorCore, B),
          ModelKey = [build_with_use:B],
          query:memoized_search(model(dependency(Pdeps0, pdepend)):config?{ModelKey}, Repo://Entry),
          rules:add_self_to_dep_contexts(Repo://Entry, Pdeps0, Pdeps1),
          rules:drop_build_with_use_from_dep_contexts(Pdeps1, Pdeps2),
          rules:add_after_only_to_dep_contexts(AnchorCore, Pdeps2, ExtraLits)
      ; flag(lit_hook_no_pdepend, NP0, NP0+1),
        HookKey = pdepend_none(AnchorCore),
        ExtraLits = []
      )
    )
  ).


% =============================================================================
%  RULES declarations
% =============================================================================

% =============================================================================
%  Ruleset: Ebuild targets
% =============================================================================

% -----------------------------------------------------------------------------
%  Rule: Target candidate (defer selection to prover)
% -----------------------------------------------------------------------------
%
% The CLI used to resolve a concrete candidate (Repo://Ebuild) up-front and then
% prove `Repo://Ebuild:run?{[]}`.
%
% For richer proof/plan integration (notably rule-driven "world" side effects),
% we also allow proving *unresolved* targets
% of the form:
%
%   target(Q, Arg):Action?{Ctx}
%
% where:
% - Q   is a parsed `qualified_target/6` term (see `eapi:qualified_target//1`)
% - Arg is the original CLI atom (used for world registration)
%
% Candidate selection happens inside the proof via `kb:query/2`, so it can
% backtrack under conflicts/constraints.
%

rule(target(Q, _Arg):fetchonly?{Context}, Conditions) :-
  !,
  kb:query(Q, Repository://Ebuild),
  Conditions = [Repository://Ebuild:fetchonly?{Context}].

rule(target(Q, Arg):uninstall?{Context}, Conditions) :-
  !,
  kb:query(Q, Repository://Ebuild),
  kb:query(installed(true), Repository://Ebuild),
  ( preference:flag(oneshot) ->
      WorldConds = []
  ; WorldConds = [world_action(unregister, Arg):world?{[after(Repository://Ebuild:uninstall)]}]
  ),
  Conditions = [Repository://Ebuild:uninstall?{Context}|WorldConds].

% Portage-style merge semantics for a requested target:
% - prove the merge (run)
% - then register the original atom in @world (unless --oneshot)
rule(target(Q, Arg):run?{Context}, Conditions) :-
  !,
  kb:query(Q, Repository://Ebuild),
  Conditions0 = [Repository://Ebuild:run?{Context}],
  ( preference:flag(oneshot) ->
      Conditions = Conditions0
  ; Conditions = [Repository://Ebuild:run?{Context},
                  world_action(register, Arg):world?{[after(Repository://Ebuild:run)]}]
  ).


% -----------------------------------------------------------------------------
%  Rule: Download target
% -----------------------------------------------------------------------------
% Any ebuild can be downloaded.

rule(Repository://Ebuild:download?{Context},Conditions) :-
  !,
  rules:ctx_take_after(Context, After, _CtxNoAfter),
  query:search(ebuild(Ebuild),Repository://Ebuild),
  ( After == none -> Conditions = [] ; Conditions = [After] ).


% -----------------------------------------------------------------------------
%  Rule: World action (side-effectful, executed by interface/builder)
% -----------------------------------------------------------------------------
%
% We encode @world modifications as proof/plan actions so they can be scheduled
% relative to other actions (e.g. after a merge).
%
% Execution is performed outside the prover (currently by interface code), but
% the *decision* to perform a world action is now rule-driven.
%

rule(world_action(_Op,_Arg):world?{Context}, Conditions) :-
  !,
  rules:ctx_take_after(Context, After, _CtxNoAfter),
  ( After == none -> Conditions = [] ; Conditions = [After] ).


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

  query:search([category(C),name(N),select(slot,constraint([]),S)], Repository://Ebuild),

  % 2. Compute required_use stable model (thread per-package USE constraints).
  rules:context_build_with_use_state(Context, B),

  (memberchk(required_use:R,Context) -> true ; true),

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
   ; rules:assume_conflicts,
     feature_unification:unify([issue_with_model(explanation)], Context, Ctx1),
     Conditions = [assumed(Repository://Ebuild:install?{Ctx1})].


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
  ( query:search(masked(true),   Repository://Ebuild) ->
      Conditions = []
  ; query:search(installed(true),Repository://Ebuild),
    \+ preference:flag(emptytree) ->
      Conditions = []  % todo check new build_with_use requirements
  ; rules:ctx_take_after_with_mode(Context, After, AfterForDeps, Context1),

    % 1. Get some metadata we need further down

    ( % Normal install proof
      query:search([category(C),name(N),select(slot,constraint([]),S)], Repository://Ebuild),
      query:search(version(Ver), Repository://Ebuild),
      Selected = constraint(selected_cn(C,N):{ordset([selected(Repository,Ebuild,install,Ver,S)])}),

      % 2. Compute required_use stable model, if not already passed on by run.
      %    Thread per-package USE constraints from build_with_use.
      rules:context_build_with_use_state(Context1, B),
      ( memberchk(required_use:R,Context1) -> true ; true ),
      query:search(model(Model,required_use(R),build_with_use(B)),Repository://Ebuild),

      % 3. Pass use model onto dependencies to calculate corresponding dependency model,
      %    We pass using config action to avoid package_dependency from generating choices.
      %    The config action triggers use_conditional, any_of_group, exactly_one_of_group,
      %    all_of_group ... choice point generation

      % 4. Compute + memoize dependency model, already grouped by package Category & Name.
      query:memoized_search(model(dependency(MergedDeps0,install)):config?{Model},Repository://Ebuild),
      add_self_to_dep_contexts(Repository://Ebuild, MergedDeps0, MergedDeps),
      rules:add_after_to_dep_contexts(AfterForDeps, MergedDeps, MergedDepsAfter),
      % Heuristic (parity): prove explicit slot/subslot deps early.
      % Some stacks (notably OCaml Jane Street) rely on a "release series" encoded
      % in SUBSLOT. If we first satisfy a loose dependency (e.g. := / any_same_slot),
      % we can lock selected_cn(C,N) to the newest series and later degrade an
      % explicit :0/0.16 requirement into a bogus "non-existent assumed".
      %
      % Ordering explicit slot/subslot requirements first avoids this class of
      % conflict without changing solver semantics.
      rules:order_deps_for_proof(install, MergedDepsAfter, MergedDepsOrdered),

      % 5. Pass on relevant package dependencies and constraints to prover
      ( memberchk(C,['virtual','acct-group','acct-user']) ->
          Prefix0 = [ Selected,
                      constraint(use(Repository://Ebuild):{R}),
                      constraint(slot(C,N,S):{Ebuild})
                    ],
          append(Prefix0, MergedDepsOrdered, Conditions0)
      ; ( AfterForDeps == none ->
            DownloadCtx0 = [required_use:R,build_with_use:B]
        ; DownloadCtx0 = [after(AfterForDeps),required_use:R,build_with_use:B]
        ),
        Prefix0 = [ Selected,
                    constraint(use(Repository://Ebuild):{R}),
                    constraint(slot(C,N,S):{Ebuild}),
                    Repository://Ebuild:download?{DownloadCtx0}
                  ],
        append(Prefix0, MergedDepsOrdered, Conditions0)
      ),
      rules:ctx_add_after_condition(After, AfterForDeps, Conditions0, Conditions)
    ; % Conflict fallback
      rules:assume_conflicts,
      feature_unification:unify([issue_with_model(explanation)], Context1, Ctx1),
      Conditions = [assumed(Repository://Ebuild:install?{Ctx1})]
    )
  ).


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
  query:search(installed(true),Repository://Ebuild), \+preference:flag(emptytree) ->
    ( config:avoid_reinstall(true) ->
        Conditions = []
    ; rules:ctx_take_after_with_mode(Context, After0, AfterForDeps0, Context10),
      Cond0 = [Repository://Ebuild:reinstall?{Context10}],
      rules:ctx_add_after_condition(After0, AfterForDeps0, Cond0, Conditions)
    )
  ; % todo check new build_with_use requirements

  rules:ctx_take_after_with_mode(Context, After, AfterForDeps, Context1),

  % 1. Get some metadata we need further down

  query:search([category(C),name(N),select(slot,constraint([]),S)], Repository://Ebuild),
  query:search(version(Ver), Repository://Ebuild),
  Selected = constraint(selected_cn(C,N):{ordset([selected(Repository,Ebuild,run,Ver,S)])}),

  % 2. Compute required_use stable model, extend with build_with_use requirements.
  rules:context_build_with_use_state(Context1, B),

  % (memberchk(build_with_use(B),Context) -> true ; B = []),

  query:search(model(Model,required_use(R),build_with_use(B)),Repository://Ebuild),

  % 3. Pass use model onto dependencies to calculate corresponding dependency  model,
  %    We pass using config action to avoid package_dependency from generating choices.
  %    The config action triggers use_conditional, any_of_group, exactly_one_of_group,
  %    all_of_group ... choice point generation

  % 4. Compute + memoize dependency model, already grouped by package Category & Name.

  query:memoized_search(model(dependency(MergedDeps0,run)):config?{Model},Repository://Ebuild),
  add_self_to_dep_contexts(Repository://Ebuild, MergedDeps0, MergedDeps),
  rules:add_after_to_dep_contexts(AfterForDeps, MergedDeps, MergedDepsAfter),
  rules:order_deps_for_proof(run, MergedDepsAfter, MergedDepsOrdered),

  % 5. Pass on relevant package dependencies and constraints to prover

  % If another version is already installed in the same slot, then "merge" should
  % translate into a transactional same-slot replacement (Portage-style), i.e.
  % NewVersion:update (replaces OldVersion), rather than a plain NewVersion:install.
  ( \+ preference:flag(emptytree),
    rules:entry_slot_default(Repository, Ebuild, SlotNew),
    % Fast guard: if nothing for C/N is installed in the VDB repo, don't even
    % attempt update detection. This avoids lots of failing work when proving
    % arbitrary/uninstalled packages (e.g. in `test_latest/2`).
    query:search(package(C,N), pkg://_),
    rules:installed_entry_cn(C, N, OldRepo, OldEbuild),
    OldEbuild \== Ebuild,
    % If the installed entry is no longer in the repo set, we may not have its
    % slot metadata. In that case, assume it matches the slot of the replacement
    % entry (this mirrors Portage's ability to read slot from /var/db/pkg).
    ( query:search(slot(SlotOld0), OldRepo://OldEbuild)
      -> rules:canon_slot(SlotOld0, SlotOld)
      ;  SlotOld = SlotNew
    ),
    SlotOld == SlotNew
  ->
    % IMPORTANT: do NOT thread slot(C,N,...) through action contexts. Slot is a
    % prover-level constraint (see constraint(slot(...))) and should not influence
    % grouped dependency candidate selection (it would incorrectly constrain := deps).
    InstallOrUpdate = Repository://Ebuild:update?{[replaces(OldRepo://OldEbuild),required_use:R,build_with_use:B]}
  ; InstallOrUpdate = Repository://Ebuild:install?{[required_use:R,build_with_use:B]}
  ),
  Prefix0 = [Selected,
             constraint(use(Repository://Ebuild):{R}),
             constraint(slot(C,N,S):{Ebuild}),
             InstallOrUpdate],
  append(Prefix0, MergedDepsOrdered, Conditions0),
  rules:ctx_add_after_condition(After, AfterForDeps, Conditions0, Conditions).

% -----------------------------------------------------------------------------
%  Dependency ordering heuristic
% -----------------------------------------------------------------------------
%
% Prefer proving dependencies with explicit slot/subslot restrictions early.
% This helps avoid selected_cn conflicts where a loose dep picks a newer series
% (e.g. SUBSLOT 0.17) and later strict deps (SUBSLOT 0.16) get assumed.
%
rules:order_deps_for_proof(_Action, Deps, Ordered) :-
  maplist(rules:dep_priority_kv, Deps, KVs),
  keysort(KVs, Sorted),
  findall(D, member(_K-D, Sorted), Ordered),
  !.

rules:dep_priority_kv(Dep, K-Dep) :-
  rules:dep_priority(Dep, K),
  !.

rules:dep_priority(grouped_package_dependency(_T,C,N,PackageDeps):Action?{_Context}, K) :-
  !,
  ( merge_slot_restriction(Action, C, N, PackageDeps, SlotReq) ->
      % Prefer satisfying tight constraints early:
      % - explicit slot/subslot restrictions,
      % - version upper bounds (< ...),
      % - explicit versioned deps over unconstrained ones,
      % - and among upper-bounded deps, process the tightest upper bound first.
      ( rules:dep_tightest_upper_bound(C, N, PackageDeps, TightUpper) ->
          UpperK0 = 1
      ; C == 'dev-ml',
        rules:dep_has_equal_wildcard_constraint(C, N, PackageDeps) ->
          UpperK0 = 8,
          TightUpper = none
      ; UpperK0 = 999,
        TightUpper = none
      ),
      rules:slotreq_priority(SlotReq, SlotK0),
      BaseK is min(UpperK0, SlotK0),
      K = key(BaseK, TightUpper, C, N)
  ; K = key(50, none, C, N)
  ).
rules:dep_priority(_Other, key(90, none, zz, zz)) :- !.

rules:slotreq_priority([slot(_),subslot(_)|_], 0) :- !.
rules:slotreq_priority([slot(_)|_],             5) :- !.
rules:slotreq_priority([any_same_slot],        10) :- !.
rules:slotreq_priority([any_different_slot],   15) :- !.
rules:slotreq_priority([],                     20) :- !.
rules:slotreq_priority(_Other,                 30) :- !.

% Tightest upper-bound version (smallest `<` / `<=` bound) for grouped deps.
rules:dep_tightest_upper_bound(C, N, PackageDeps, Tightest) :-
  findall(Vn,
          ( member(package_dependency(_Phase, no, C, N, Op, V0, _S, _U), PackageDeps),
            ( Op == smaller ; Op == smallerorequal ),
            rules:coerce_version_term(V0, Vn)
          ),
          Bounds0),
  Bounds0 = [First|Rest],
  foldl(rules:min_version_bound_, Rest, First, Tightest),
  !.

rules:min_version_bound_(V, Best0, Best) :-
  ( eapi:version_compare(<, V, Best0) ->
      Best = V
  ; Best = Best0
  ),
  !.


% -----------------------------------------------------------------------------
%  Helper: planning-only context markers
% -----------------------------------------------------------------------------

% Extract an optional "after(Literal)" marker from a context list.
% Keeps at most one marker to prevent context growth.
rules:ctx_take_after(Context0, After, Context) :-
  ( is_list(Context0),
    memberchk(after(After1), Context0) ->
      After = After1,
      findall(X, (member(X, Context0), \+ X = after(_)), Context)
  ; After = none,
    Context = Context0
  ),
  !.

% Extract an optional "after/1" or "after_only/1" marker from a context list.
% For after_only/1 we return AfterForDeps = none, so ordering does not propagate
% into the dependency closure of the goal.
rules:ctx_take_after_with_mode(Context0, After, AfterForDeps, Context) :-
  ( is_list(Context0),
    memberchk(after_only(After1), Context0) ->
      After = After1,
      AfterForDeps = none,
      findall(X, (member(X, Context0), \+ X = after(_), \+ X = after_only(_)), Context)
  ; is_list(Context0),
    memberchk(after(After1), Context0) ->
      After = After1,
      AfterForDeps = After1,
      findall(X, (member(X, Context0), \+ X = after(_), \+ X = after_only(_)), Context)
  ; After = none,
    AfterForDeps = none,
    Context = Context0
  ),
  !.

% Add an ordering marker extracted by ctx_take_after_with_mode/4.
% - For after/1: add the literal as a real dependency.
% - For after_only/1: add an ordering-only constraint (planner ignores it).
rules:ctx_add_after_condition(none, _AfterForDeps, Conditions, Conditions) :- !.
rules:ctx_add_after_condition(After, none, Conditions0, [constraint(order_after(After):{[]} )|Conditions0]) :-
  After \== none,
  !.
rules:ctx_add_after_condition(After, _AfterForDeps, Conditions0, [After|Conditions0]) :-
  !.

% Strip planning-only markers that should not affect dependency-model memoization.
rules:ctx_strip_planning(Context0, Context) :-
  ( is_list(Context0) ->
      findall(X,
              ( member(X, Context0),
                \+ X = after(_),
                \+ X = world_atom(_)
              ),
              Context)
  ; Context = Context0
  ),
  !.

% Thread an "after/1" marker into dependency contexts (and keep it stable).
rules:add_after_to_dep_contexts(none, Deps, Deps) :- !.
rules:add_after_to_dep_contexts(After, Deps0, Deps) :-
  is_list(Deps0),
  !,
  findall(D,
          ( member(D0, Deps0),
            ( D0 = Term:Action?{Ctx0} ->
                rules:ctx_add_after(Ctx0, After, Ctx),
                D = Term:Action?{Ctx}
            ; D = D0
            )
          ),
          Deps).
rules:add_after_to_dep_contexts(_After, Deps, Deps).

rules:ctx_add_after(Ctx0, After, Ctx) :-
  ( is_list(Ctx0) ->
      % Keep only one after/1 marker.
      findall(X, (member(X, Ctx0), \+ X = after(_)), Ctx1),
      Ctx = [after(After)|Ctx1]
  ; Ctx = [after(After)]
  ),
  !.

% Thread an "after_only/1" marker into dependency contexts (and keep it stable).
% This enforces ordering for the goal itself, without propagating the ordering
% marker into its own dependency closure.
rules:add_after_only_to_dep_contexts(_After, [], []) :- !.
rules:add_after_only_to_dep_contexts(After, Deps0, Deps) :-
  is_list(Deps0),
  !,
  findall(D,
          ( member(D0, Deps0),
            ( D0 = Term:Action?{Ctx0} ->
                rules:ctx_add_after_only(Ctx0, After, Ctx),
                D = Term:Action?{Ctx}
            ; D = D0
            )
          ),
          Deps).
rules:add_after_only_to_dep_contexts(_After, Deps, Deps).

% Drop `build_with_use` from dependency contexts.
% For PDEPEND expansion we use build_with_use only as a memoization key, not as
% a semantic constraint on the PDEPEND targets themselves.
rules:drop_build_with_use_from_dep_contexts([], []) :- !.
rules:drop_build_with_use_from_dep_contexts([D0|Rest0], [D|Rest]) :-
  !,
  rules:drop_build_with_use_from_dep_context(D0, D),
  rules:drop_build_with_use_from_dep_contexts(Rest0, Rest).
rules:drop_build_with_use_from_dep_contexts(Deps, Deps).

rules:drop_build_with_use_from_dep_context(Dep0:Act?{Ctx0}, Dep:Act?{Ctx}) :-
  !,
  Dep = Dep0,
  rules:ctx_drop_build_with_use(Ctx0, Ctx).
rules:drop_build_with_use_from_dep_context(Other, Other).

rules:ctx_add_after_only(Ctx0, After, Ctx) :-
  ( is_list(Ctx0) ->
      % Keep only one planning marker (after/1 or after_only/1).
      findall(X, (member(X, Ctx0), \+ X = after(_), \+ X = after_only(_)), Ctx1),
      Ctx = [after_only(After)|Ctx1]
  ; Ctx = [after_only(After)]
  ),
  !.


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
  query:search([category(Category),name(Name),version(VersionInstalled),installed(true)],
              Repository://Ebuild),
  % Find the latest acceptable version for this C/N in the repo set.
  % Update semantics stay within the same slot (upgrade semantics cross slots and
  % will be introduced later).
  ( query:search(slot(SlotInstalled), Repository://Ebuild)
    -> query:search(latest([name(Name),category(Category),keywords(K),slot(SlotInstalled),
                            select(version,greater,VersionInstalled)]),
                    LatestRepo://LatestEbuild)
    ;  query:search(latest([name(Name),category(Category),keywords(K),
                            select(version,greater,VersionInstalled)]),
                    LatestRepo://LatestEbuild)
  ),
  !,
  % IMPORTANT: represent the update as a single transactional action on the
  % *new* version, annotated with the old version it replaces.
  feature_unification:unify([replaces(Repository://Ebuild)], Context, Ctx1),
  Conditions = [LatestRepo://LatestEbuild:update?{Ctx1}].

% If the user targets a specific version with :update and it is not installed,
% treat it as a transactional same-slot replacement when an older version is
% installed, otherwise fall back to a plain install.
rule(Repository://Ebuild:update?{Context},Conditions) :-
  \+ memberchk(replaces(_), Context),
  \+(preference:flag(emptytree)),
  query:search([category(Category),name(Name)], Repository://Ebuild),
  \+ query:search(installed(true), Repository://Ebuild),
  % Try same-slot replacement first (if slot is known).
  ( rules:entry_slot_default(Repository, Ebuild, SlotNew),
    rules:installed_entry_cn(Category, Name, OldRepo, OldEbuild),
    ( query:search(slot(SlotOld0), OldRepo://OldEbuild)
      -> rules:canon_slot(SlotOld0, SlotOld)
      ;  SlotOld = SlotNew
    ),
    SlotOld == SlotNew
  -> feature_unification:unify([replaces(OldRepo://OldEbuild)], Context, UpdCtx),
     rules:update_txn_conditions(Repository://Ebuild, UpdCtx, Conditions)
  ;  Conditions = [Repository://Ebuild:install?{Context}]
  ),
  !.

% Otherwise, updating an already-installed version is a no-op (already current or
% no acceptable newer version).
rule(Repository://Ebuild:update?{_Context},[]) :-
  query:search(installed(true), Repository://Ebuild),
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
%
% Efficient semantics: record the blocker as a global side-condition (constraint).
% Enforcement is done in the prover (so it can backtrack to alternative candidates)
% and can consider both "future" (later selections) and "past" (already selected).
rule(package_dependency(Phase,weak,C,N,O,V,S,_U):_Action?{Context},
     Conditions) :-
  % Weak blockers are extremely common (esp. in system sets like systemd/udev),
  % and enforcing them as hard constraints during proving can cause massive
  % backtracking explosions. We record them as domain assumptions so the plan
  % can still be computed, while the printer can warn the user.
  BlockedSpecs = [blocked(weak,Phase,O,V,S)],
  rules:blocker_source_constraints(C, N, BlockedSpecs, Context, SourceConds),
  rules:blocker_assumption_ctx(Context, AssCtx),
  append(SourceConds,
         [assumed(blocker(weak, Phase, C, N, O, V, S)?{AssCtx})],
         Conditions),
  !.


% -----------------------------------------------------------------------------
%  Rule: Conflicting package
% -----------------------------------------------------------------------------
% EAPI 8.2.6.2: a strong block is satisfied when no suitable candidate is satisfied
%
% In portage-ng we implement strong blockers as "remove if installed" (harder
% semantics like "forbid co-installation in the same plan" can be layered in
% the planner/printer using the planned package set).
rule(package_dependency(Phase,strong,C,N,O,V,S,U):_Action?{Context},
     Conditions) :-
  ( rules:assume_blockers ->
      rules:blocker_assumption_ctx(Context, AssCtx),
      Conditions = [assumed(blocker(strong, Phase, C, N, O, V, S)?{AssCtx})]
  ; % IMPORTANT (Portage-like blockers with USE deps):
    % Many strong blockers are conditional on bracketed USE requirements, e.g.
    %   !!x11-drivers/nvidia-drivers[-libglvnd]
    %
    % Our blocker constraint store (`blocked_cn/2`) currently tracks only C/N, Op, Ver, SlotReq
    % and does NOT record the dependency USE condition. Enforcing such blockers as hard
    % constraints therefore over-approximates (treats them as unconditional) and can
    % cause massive backtracking / false conflicts (e.g. primus wants nvidia-drivers[libglvnd]).
    %
    % To keep proving correct and performant, we enforce ONLY unconditional strong blockers
    % (those without bracketed USE constraints). Conditional strong blockers are recorded
    % as domain assumptions in strict mode.
    ( U == [] ->
        BlockedSpecs = [blocked(strong,Phase,O,V,S)],
        rules:blocker_source_constraints(C, N, BlockedSpecs, Context, SourceConds),
        Conditions = [constraint(blocked_cn(C,N):{ordset(BlockedSpecs)})|SourceConds]
    ; rules:blocker_assumption_ctx(Context, AssCtx),
      Conditions = [assumed(blocker(strong, Phase, C, N, O, V, S)?{AssCtx})]
    )
  ),
  !.


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
    query:search([category(C),name(N)], SelfRepo://SelfEntry),
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

rule(grouped_package_dependency(weak,C,N,PackageDeps):Action?{Context},
     Conditions) :-
  !,
  rules:grouped_blocker_specs(weak, Action, C, N, PackageDeps, Specs),
  rules:blocker_source_constraints(C, N, Specs, Context, SourceConds),
  rules:blocker_assumption_ctx(Context, AssCtx),
  findall(assumed(blocker(Strength, Phase, C, N, O, V, SlotReq)?{AssCtx}),
          member(blocked(Strength, Phase, O, V, SlotReq), Specs),
          AssumeConds),
  append(SourceConds, AssumeConds, Conditions).


% -----------------------------------------------------------------------------
%  Rule: Conflicting package
% -----------------------------------------------------------------------------
% EAPI 8.2.6.2: a strong block is satisfied when no suitable candidate is satisfied

rule(grouped_package_dependency(strong,C,N,PackageDeps):Action?{Context},
     Conditions) :-
  !,
  rules:grouped_blocker_specs_partition(strong, Action, C, N, PackageDeps, EnforceSpecs, AssumeSpecs),
  ( rules:assume_blockers ->
      append(EnforceSpecs, AssumeSpecs, AllSpecs),
      rules:blocker_source_constraints(C, N, AllSpecs, Context, SourceConds),
      rules:blocker_assumption_ctx(Context, AssCtx),
      findall(assumed(blocker(Strength, Phase, C, N, O, V, SlotReq)?{AssCtx}),
              ( member(blocked(Strength, Phase, O, V, SlotReq), EnforceSpecs)
              ; member(blocked(Strength, Phase, O, V, SlotReq), AssumeSpecs)
              ),
              AssumeConds),
      append(SourceConds, AssumeConds, Conditions)
  ;
    rules:blocker_assumption_ctx(Context, AssCtx),
    findall(assumed(blocker(Strength, Phase, C, N, O, V, SlotReq)?{AssCtx}),
            member(blocked(Strength, Phase, O, V, SlotReq), AssumeSpecs),
            AssumeConds),
    ( EnforceSpecs == [] ->
        Conditions = AssumeConds
    ; rules:blocker_source_constraints(C, N, EnforceSpecs, Context, SourceConds),
      append([constraint(blocked_cn(C,N):{ordset(EnforceSpecs)})|SourceConds], AssumeConds, Conditions)
    )
  ).

% Context tags for blocker assumptions, so the printer can show provenance
% (who pulled in the blocker) and test_stats can classify them.
rules:blocker_assumption_ctx(Ctx0, AssCtx) :-
  ( is_list(Ctx0),
    memberchk(self(Repo://Entry), Ctx0) ->
      AssCtx = [assumption_reason(blocker_conflict), self(Repo://Entry)]
  ; AssCtx = [assumption_reason(blocker_conflict)]
  ).

rules:blocker_source_constraints(_C, _N, Specs, _Context, []) :-
  Specs == [],
  !.
rules:blocker_source_constraints(C, N, Specs, Context, [constraint(blocked_cn_source(C,N):{ordset(Sources)})]) :-
  is_list(Context),
  memberchk(self(SelfRepo://SelfEntry), Context),
  findall(source(SelfRepo,SelfEntry,Phase,O,V,SlotReq),
          member(blocked(_Strength,Phase,O,V,SlotReq), Specs),
          Sources0),
  sort(Sources0, Sources),
  Sources \== [],
  !.
rules:blocker_source_constraints(_C, _N, _Specs, _Context, []) :-
  !.

% -----------------------------------------------------------------------------
%  Internal override: assume blockers
% -----------------------------------------------------------------------------
%
% Used for developer UX: when a plan cannot be proven due to blockers, we can
% re-run in a mode that turns blockers into domain assumptions, so the printer
% can show "this would be the plan if you verify/override these blockers".

rules:assume_blockers :-
  nb_current(rules_assume_blockers, true).

rules:with_assume_blockers(Goal) :-
  ( nb_current(rules_assume_blockers, Old) -> true ; Old = unset ),
  nb_setval(rules_assume_blockers, true),
  setup_call_cleanup(true,
                     Goal,
                     ( Old == unset -> nb_delete(rules_assume_blockers)
                     ; nb_setval(rules_assume_blockers, Old)
                     )).

% -----------------------------------------------------------------------------
%  Internal override: assume conflicts
% -----------------------------------------------------------------------------
%
% When proving REQUIRED_USE-like boolean constraints, we sometimes want the proof
% to *complete* even if the current USE environment makes the constraints
% unsatisfiable, so we can report the conflicts as assumptions (debugging/stats).
%
% Default behavior remains strict: conflicts fail (they are correctness bugs).
%
rules:assume_conflicts :-
  nb_current(rules_assume_conflicts, true).

rules:with_assume_conflicts(Goal) :-
  ( nb_current(rules_assume_conflicts, Old) -> true ; Old = unset ),
  nb_setval(rules_assume_conflicts, true),
  setup_call_cleanup(true,
                     Goal,
                     ( Old == unset -> nb_delete(rules_assume_conflicts)
                     ; nb_setval(rules_assume_conflicts, Old)
                     )).


% =============================================================================
%  Rule: Package dependencies
% =============================================================================

% IMPORTANT (Portage-like multi-slot deps):
%
% Some packages depend on *multiple* versions of the same cat/pkg simultaneously.
% Portage can satisfy this when the package is multi-slot (versions live in
% different SLOTs), e.g. `dev-dotnet/dotnet-runtime-nugets` where dotnet SDK
% depends on several ~cat/pkg-ver constraints at once.
%
% Our dependency model groups deps by (C,N) which would otherwise attempt to pick
% a *single* candidate satisfying all version constraints. When those constraints
% are meant to be satisfied side-by-side (multi-slot), that is impossible and
% degrades into "non-existent, assumed running".
%
% Split such grouped deps into independent requirements.
rule(grouped_package_dependency(no,C,N,PackageDeps):Action?{Context},Conditions) :-
  rules:should_split_grouped_dep(PackageDeps),
  !,
  findall(grouped_package_dependency(no, C, N, [D]):Action?{Context},
          member(D, PackageDeps),
          Conditions0),
  sort([constraint(selected_cn_allow_multislot(C,N):{true})|Conditions0], Conditions).

rule(grouped_package_dependency(no,C,N,PackageDeps):Action?{Context},Conditions) :-
  !,
  % Lazy + guarded propagation of self-RDEPEND *version bounds* into build/install
  % dependency selection. This helps avoid selecting an inconsistent toolchain/lib
  % version (e.g. picking OCaml 5.x for DEPEND when the current package's RDEPEND
  % requires <dev-lang/ocaml-5), but avoids the timeout-prone "build a full map per
  % package" approach by only looking up bounds for the current (C,N) and caching
  % per (SelfId,C,N).
  rules:augment_package_deps_with_self_rdepend(Action, C, N, Context, PackageDeps, PackageDeps1),
  % Self-dependency at runtime is trivially satisfied: once the package is built,
  % it provides itself. Treat this generically to avoid hard failures on packages
  % that (redundantly) list themselves in RDEPEND.
  ( Action == run,
    memberchk(self(SelfRepo://SelfEntry), Context),
    query:search([category(C),name(N)], SelfRepo://SelfEntry)
  ->
    Conditions = []
  ; preference:flag(emptytree),
    core_pkg(C,N)
  ->
    Conditions = []
  ; \+ preference:flag(emptytree),
    \+ preference:flag(deep),
    merge_slot_restriction(Action, C, N, PackageDeps1, SlotReq),
    % If an installed instance exists in the same slot, and it satisfies all
    % version constraints, treat the grouped dependency as satisfied.
    %
    % Performance note:
    % Avoid `select(version,O,V)` with variable Op, and `select(slot,constraint(SlotReq),_)`
    % with variable SlotReq, because those prevent compile-time query macro expansion.
    query:search([name(N),category(C),installed(true)],
                 pkg://InstalledEntry),
    rules:query_search_slot_constraint(SlotReq, pkg://InstalledEntry, _),
    rules:installed_entry_satisfies_package_deps(Action, C, N, PackageDeps1, pkg://InstalledEntry),
    % IMPORTANT (Portage-like rebuilds):
    % The "keep installed" fast-path must also respect bracketed USE requirements
    % expressed by this dependency (e.g. xmlto[text], glib[introspection]).
    % These are carried as per-package `build_with_use` constraints, so we must
    % derive them from this grouped dep's PackageDeps before deciding the installed
    % instance satisfies the dependency.
    findall(U0, member(package_dependency(_P0,no,C,N,_O,_V,_,U0),PackageDeps1), MergedUse0),
    append(MergedUse0, MergedUse),
    process_build_with_use(MergedUse, Context, ContextWU, _BWUCons, pkg://InstalledEntry),
    % Portage does not rebuild virtuals based on USE deps: virtuals are satisfied
    % by their provider packages; rebuilding the virtual itself is a no-op.
    ( C == 'virtual'
    -> true
    ; rules:installed_entry_satisfies_build_with_use(pkg://InstalledEntry, ContextWU)
    ),
    % --newuse: do not "keep installed" if USE/IUSE has changed since the installed
    % package was built (Portage-like -N behavior).
    ( preference:flag(newuse) ->
        \+ rules:newuse_mismatch(pkg://InstalledEntry)
    ; true
    ),
    !   % commit to the first installed entry that satisfies constraints
  ->
    Conditions = []
  ;
    ( merge_slot_restriction(Action, C, N, PackageDeps1, SlotReq),

      % Candidate selection (portage / overlays)
      %
      % CN-consistency: reuse an already-selected concrete entry when possible.
      %
      % IMPORTANT (:= / any_same_slot correctness):
      % The Context may contain multiple `slot(C,N,...)` facts (multi-slot).
      % If we bind Ss *before* choosing Candidate, we might bind to an unrelated
      % slot constraint and incorrectly render the dependency "unsatisfiable".
      %
      % Therefore:
      % - first choose Candidate (prefer reusing selected_cn when present),
      % - then (optionally) bind Ss from the matching slot(C,N,...) entry for that
      %   exact Candidate, and only use Ss as a lock when enumerating further.
      % If the context already carries a slot lock for this (C,N) (typically via :=),
      % reuse it to restrict candidate choice. This is how we enforce Portage-like
      % `:=` behavior (same slot/subslot as the previously chosen instance).
      %
      % IMPORTANT: do NOT apply this to explicit slot deps [slot(_)] — those are
      % validated via query_search_slot_constraint/3 and must allow multi-slot.
      ( SlotReq == [any_same_slot],
        memberchk(slot(C,N,SsLock0):{_}, Context),
        rules:canon_any_same_slot_meta(SsLock0, SsLock)
      ->
        true
      ; SsLock = _Unbound
      ),

      % Candidate selection must respect slot constraints.
      %
      % IMPORTANT:
      % - For explicit slot/subslot deps (cat/pkg:0/0.16, :=0/0.16, etc.), we must NOT
      %   blindly reuse an existing selected_cn(C,N) choice that may point at a
      %   different slot/subslot (otherwise the dep degrades into a bogus
      %   "non-existent, assumed ..." domain assumption).
      % - We therefore only reuse selected_cn when it satisfies SlotReq.
      % - Also, only reuse when it is compatible with the effective domain for
      %   this dependency; otherwise, fall back to fresh candidate enumeration.
      ( SlotReq = [slot(_)|_] ->
          rules:accepted_keyword_candidate(Action, C, N, SlotReq, _Ss0, Context, FoundRepo://Candidate),
          CandPreVerified = false
      ; rules:selected_cn_candidate_compatible(Action, C, N, SlotReq, PackageDeps1, Context, FoundRepo://Candidate) ->
          CandPreVerified = true
      ; rules:selected_cn_rejected_candidates(Action, C, N, SlotReq, PackageDeps1, Context, RejectedSelected),
        rules:accepted_keyword_candidate(Action, C, N, SlotReq, SsLock, Context, FoundRepo://Candidate),
        \+ memberchk(FoundRepo://Candidate, RejectedSelected),
        CandPreVerified = false
      ),

      % Avoid resolving a dep to self unless candidate is already installed
      ( ( memberchk(self(_SelfRepo://SelfEntry1), Context)
        ; memberchk(slot(C,N,_SelfSlot):{SelfEntry1}, Context)
        ),
        Candidate == SelfEntry1
      ->
        \+ preference:flag(emptytree),
        query:search(installed(true), FoundRepo://Candidate)
      ; true
      ),

      ( CandPreVerified == true ->
          true
      ; forall(member(package_dependency(_P1,no,C,N,O,V,_,_), PackageDeps1),
               rules:query_search_version_select(O, V, FoundRepo://Candidate)),
        rules:grouped_dep_candidate_satisfies_effective_domain(Action, C, N, PackageDeps1, Context, FoundRepo://Candidate)
      ),
      rules:candidate_reverse_deps_compatible_with_parent(Context, FoundRepo://Candidate),

      % For PDEPEND edges, we treat the dependency as runtime-soft (cycle-breakable),
      % but we should not propagate or enforce `build_with_use` from the parent.
      % Otherwise large USE_EXPAND sets (llvm_targets_*, python_targets_*) explode
      % the dependency context and can prevent resolution (and cause mismatches).
      % PDEPEND edges also must not inherit the parent's `build_with_use` context.
      ( member(package_dependency(pdepend,_,C,N,_,_,_,_), PackageDeps1) ->
          MergedUse = [],
          rules:ctx_drop_build_with_use_and_assumption_reason(Context, ContextDep)
      ; findall(U0, member(package_dependency(_P2,no,C,N,_O,_V,_,U0),PackageDeps1), MergedUse0),
        append(MergedUse0, MergedUse),
        ContextDep = Context
      ),
      % Enforce bracketed USE constraints (e.g. sys-devel/gcc[objc], python[xml(+)], foo[bar?]).
      rules:candidate_satisfies_use_deps(ContextDep, FoundRepo://Candidate, MergedUse),
      process_build_with_use(MergedUse,ContextDep,NewContext,Constraints,FoundRepo://Candidate),
      rules:query_search_slot_constraint(SlotReq, FoundRepo://Candidate, SlotMeta),
      process_slot(SlotReq, SlotMeta, C, N, FoundRepo://Candidate, NewContext, NewerContext),

      % Prefer expressing as update when a pkg-installed entry exists in the same
      % slot and the chosen candidate has a different version (upgrade OR downgrade).
      ( \+ preference:flag(emptytree),
        % Update/reinstall semantics must be per-slot: only treat this as an update
        % when there is an installed instance of (C,N) in the SAME SLOT as the
        % chosen candidate. Otherwise we'd incorrectly "update" one slot while
        % actually installing another (Portage would call that a new-slot install).
        rules:selected_cn_slot_key_(SlotMeta, SlotChosen),
        query:search([name(N),category(C),installed(true)],
                     pkg://InstalledEntry2),
        ( query:search(slot(SlotInstalled0), pkg://InstalledEntry2)
          -> rules:canon_slot(SlotInstalled0, SlotInstalled)
          ;  SlotInstalled = SlotChosen
        ),
        SlotInstalled == SlotChosen,
        !,
        ( % Standard transactional version change in same slot:
          % candidate differs from installed (upgrade or downgrade).
          InstalledEntry2 \== Candidate,
          query:search(version(OldVer), pkg://InstalledEntry2),
          query:search(version(CandVer0), FoundRepo://Candidate),
          OldVer \== CandVer0 ->
            feature_unification:unify([replaces(pkg://InstalledEntry2)], NewerContext, UpdateCtx)
        ; % Incoming bracketed USE constraints require a rebuild of the installed instance.
          ( current_predicate(config:avoid_reinstall/1),
            config:avoid_reinstall(true) ->
              fail
          ; C \== 'virtual',
            \+ rules:installed_entry_satisfies_build_with_use(pkg://InstalledEntry2, NewerContext)
          ) ->
            feature_unification:unify([replaces(pkg://InstalledEntry2),rebuild_reason(build_with_use)], NewerContext, UpdateCtx)
        ; % --newuse: force a transactional rebuild even if version is the same,
          % when USE/IUSE differs.
          preference:flag(newuse),
          rules:newuse_mismatch(pkg://InstalledEntry2, FoundRepo://Candidate) ->
            feature_unification:unify([replaces(pkg://InstalledEntry2),rebuild_reason(newuse)], NewerContext, UpdateCtx)
        )
      ->
        ActionGoal = FoundRepo://Candidate:update?{UpdateCtx}
      ; % Portage-like: even for runtime (RDEPEND) edges, the solver should
        % schedule the dependency to be installed (not "run") when it is not
        % already present. Otherwise we create widespread `assumed(...running)`
        % domain assumptions (and miss merge actions) for normal libraries.
        ( Action == run ->
            DepAction = install
        ; DepAction = Action
        ),
        ActionGoal = FoundRepo://Candidate:DepAction?{NewerContext}
      ),
      % IMPORTANT for performance + correctness:
      % Record the concrete choice as a selection constraint *before* proving
      % ActionGoal, so the blocker guard can prune blocked candidates early
      % and backtrack within `query:search/2` enumeration (instead of exploring
      % deep proof paths for an invalid choice).
      ( ActionGoal = _://_:ActSel?{_} -> true
      ; ActionGoal = _://_:ActSel     -> true
      ; ActSel = Action
      ),
      query:search(version(CandVer), FoundRepo://Candidate),
      Selected = constraint(selected_cn(C,N):{ordset([selected(FoundRepo,Candidate,ActSel,CandVer,SlotMeta)])}),
      rules:selected_cn_allow_multislot_constraints(C, N, SlotReq, PackageDeps1, AllowMultiSlotCons),
      rules:cn_domain_constraints(Action, C, N, PackageDeps1, Context, DomainCons0, _DomainReasonTags),
      rules:domain_constraints_for_any_different_slot(SlotReq, DomainCons0, DomainCons),
      append(DomainCons, AllowMultiSlotCons, DomainAndAllow),
      append(DomainAndAllow, [Selected|Constraints], Conditions0),
      append(Conditions0, [ActionGoal], Conditions)
    ; % In --deep mode we *prefer* upgrades, but we should not create domain
      % assumptions when the dependency is already installed in the vdb (`pkg`)
      % and satisfies constraints. Instead, fall back to "keep installed".
      ( preference:flag(deep),
        merge_slot_restriction(Action, C, N, PackageDeps, SlotReq2),
        query:search([name(N),category(C),installed(true)],
                     pkg://InstalledEntryFallback),
        rules:query_search_slot_constraint(SlotReq2, pkg://InstalledEntryFallback, _),
        !,
        rules:installed_entry_satisfies_package_deps(Action, C, N, PackageDeps, pkg://InstalledEntryFallback)
      ->
        Conditions = []
      ; % Before reprove, check if the parent should be narrowed — the parent
        % introduced a dep that made (C,N) unsatisfiable (wrong-level fix).
        rules:maybe_learn_parent_narrowing(C, N, PackageDeps1, Context),
        fail
      ; rules:maybe_request_grouped_dep_reprove(Action, C, N, PackageDeps1, Context),
        fail
      ; explanation:assumption_reason_for_grouped_dep(Action, C, N, PackageDeps, Context, _Reason),
        % Keep assumption_reason out of dependency-context unification:
        % it is diagnostic metadata for the printer/stats, not part of the domain
        % feature lattice. Unifying it into Context can prevent later refinement
        % of the same dependency (and can also bloat contexts via propagation).
        feature_unification:unify([], Context, Ctx1),
        version_domain:domain_reason_terms(Action, C, N, PackageDeps1, Context, DomainReasonTags),
        rules:add_domain_reason_context(C, N, DomainReasonTags, Ctx1, Ctx2),
        Conditions = [assumed(grouped_package_dependency(C,N,PackageDeps1):Action?{Ctx2})]
      )
    )
  ).

rules:cn_domain_constraints(Action, C, N, PackageDeps, Context, DomainCons, DomainReasonTags) :-
  version_domain:domain_from_packagedeps(Action, C, N, PackageDeps, Domain),
  version_domain:domain_reason_terms(Action, C, N, PackageDeps, Context, DomainReasonTags),
  ( DomainReasonTags == [] ->
      ReasonCons = []
  ; ReasonCons = [constraint(cn_domain_reason(C,N):{ordset(DomainReasonTags)})]
  ),
  ( Domain == none ->
      DomainCons = ReasonCons
  ; DomainCons = [constraint(cn_domain(C,N):{Domain})|ReasonCons]
  ),
  !.

% `any_different_slot` deps (slot operator `:*`) are side-by-side by nature.
% Merging them into one global cn_domain(C,N) can create false slot intersections
% across independent edges. Keep their slot/version checks local to the edge.
rules:domain_constraints_for_any_different_slot([any_different_slot], _DomainCons0, []) :-
  !.
rules:domain_constraints_for_any_different_slot(_SlotReq, DomainCons, DomainCons) :-
  !.

rules:add_domain_reason_context(_C, _N, [], Ctx, Ctx) :-
  !.
rules:add_domain_reason_context(C, N, ReasonTags, Ctx0, Ctx) :-
  feature_unification:unify([domain_reason(cn_domain(C,N,ReasonTags))], Ctx0, Ctx),
  !.

% True iff PackageDeps contains an explicit upper bound for (C,N), i.e. < or <=.
rules:dep_has_upper_version_bound(C, N, PackageDeps) :-
  member(package_dependency(_Phase, no, C, N, Op, _V, _S, _U), PackageDeps),
  ( Op == smaller
  ; Op == smallerorequal
  ),
  !.

rules:dep_has_version_constraint(C, N, PackageDeps) :-
  member(package_dependency(_Phase, no, C, N, Op, _V, _S, _U), PackageDeps),
  nonvar(Op),
  Op \== none,
  !.

% True iff PackageDeps carries an explicit slot/subslot restriction for (C,N).
% Excludes generic slot operators (:= / :*) which are handled separately.
rules:dep_has_explicit_slot_constraint(C, N, PackageDeps) :-
  member(package_dependency(_Phase, no, C, N, _Op, _V, SlotReq, _U), PackageDeps),
  rules:slot_req_explicit_slot_key(SlotReq, _S),
  !.

rules:dep_has_equal_wildcard_constraint(C, N, PackageDeps) :-
  member(package_dependency(_Phase, no, C, N, equal, V0, _S, _U), PackageDeps),
  rules:version_term_has_wildcard_(V0),
  !.

rules:version_term_has_wildcard_(V0) :-
  ( atom(V0) ->
      A = V0
  ; V0 = [_Nums,_Letter,_Rev,A],
    atom(A)
  ),
  sub_atom(A, _Start, _Len, _After, '*'),
  !.

% -----------------------------------------------------------------------------
%  Reverse-dep candidate pre-filter (RDEPEND only)
% -----------------------------------------------------------------------------
%
% Before committing to a candidate for a grouped_package_dependency, verify
% that the candidate's RDEPEND metadata does not contain a version constraint
% on the parent (self) that the parent cannot satisfy.
%
% Only RDEPEND is checked (not PDEPEND). PDEPEND conflicts are weaker: the
% prover handles them via cycle-breaking. Checking PDEPEND would reject ALL
% candidates when every version has an incompatible PDEPEND on the parent
% (e.g. every ruby:3.2 requires >=minitest-5.16.3 but the target is 5.15.0),
% turning a targeted PDEPEND assumption into a worse "non-existent" one.
%
% Example:
%   - www-apps/airdcpp-webui-2.14.0 has RDEPEND =net-p2p/airdcpp-webclient-2.14*
%     When resolving webclient-2.13.3's PDEPEND on webui, webui-2.14.0 is rejected
%     because webclient-2.13.3 does not satisfy =2.14*. Solver picks webui-2.13.1.

rules:candidate_reverse_deps_compatible_with_parent(Context, FoundRepo://Candidate) :-
  ( memberchk(self(SelfRepo://SelfEntry), Context),
    cache:ordered_entry(SelfRepo, SelfEntry, ParC, ParN, _)
  ->
    \+ rules:candidate_has_incompatible_reverse_dep(FoundRepo, Candidate, ParC, ParN, SelfRepo://SelfEntry)
  ; true
  ).

rules:candidate_has_incompatible_reverse_dep(FoundRepo, Candidate, ParC, ParN, SelfRepo://SelfEntry) :-
  cache:entry_metadata(FoundRepo, Candidate, rdepend, Dep),
  rules:dep_contains_pkg_dep_on(Dep, ParC, ParN, Op, V, SlotReq),
  Op \== none,
  rules:reverse_dep_slot_matches_parent(SlotReq, SelfRepo://SelfEntry),
  \+ query:search(select(version, Op, V), SelfRepo://SelfEntry).

% Only reject when the dep targets the same slot as the parent.
% If the dep specifies a different slot, it's about a different instance.
rules:reverse_dep_slot_matches_parent([], _) :- !.
rules:reverse_dep_slot_matches_parent([slot(DepSlot)|_], SelfRepo://SelfEntry) :-
  !,
  query:search(slot(ParSlot), SelfRepo://SelfEntry),
  rules:canon_slot(ParSlot, ParSlotC),
  rules:canon_slot(DepSlot, DepSlotC),
  ParSlotC == DepSlotC.
rules:reverse_dep_slot_matches_parent([any_same_slot|_], _) :- !.
rules:reverse_dep_slot_matches_parent([any_different_slot|_], _) :- !, fail.
rules:reverse_dep_slot_matches_parent(_, _).

rules:dep_contains_pkg_dep_on(package_dependency(_, no, C, N, Op, V, SlotReq, _), C, N, Op, V, SlotReq).
rules:dep_contains_pkg_dep_on(use_conditional_group(_, _, _, SubDeps), C, N, Op, V, SlotReq) :-
  member(D, SubDeps),
  rules:dep_contains_pkg_dep_on(D, C, N, Op, V, SlotReq).
rules:dep_contains_pkg_dep_on(all_of_group(SubDeps), C, N, Op, V, SlotReq) :-
  member(D, SubDeps),
  rules:dep_contains_pkg_dep_on(D, C, N, Op, V, SlotReq).


rules:all_deps_have_explicit_slot([]) :- !, fail.
rules:all_deps_have_explicit_slot(Deps) :-
  forall(member(package_dependency(_P,_Strength,_C,_N,_O,_V,SlotReq,_U), Deps),
         rules:slot_req_explicit_slot_key(SlotReq, _S)),
  !.

rules:multiple_distinct_slots(Deps) :-
  member(package_dependency(_,_,_,_,_,_,SR1,_), Deps),
  rules:slot_req_explicit_slot_key(SR1, S1), !,
  member(package_dependency(_,_,_,_,_,_,SR2,_), Deps),
  rules:slot_req_explicit_slot_key(SR2, S2),
  S2 \== S1, !.

% Explicit slot request shapes that should participate in grouped-dep split
% decisions. Treat :slot and :slot= (and subslot-qualified variants) as
% belonging to the same slot key for split-by-distinct-slot checks.
rules:slot_req_explicit_slot_key([slot(S0)], S) :-
  rules:canon_slot(S0, S),
  !.
rules:slot_req_explicit_slot_key([slot(S0),equal], S) :-
  rules:canon_slot(S0, S),
  !.
rules:slot_req_explicit_slot_key([slot(S0),subslot(_Ss)], S) :-
  rules:canon_slot(S0, S),
  !.
rules:slot_req_explicit_slot_key([slot(S0),subslot(_Ss),equal], S) :-
  rules:canon_slot(S0, S),
  !.

rules:all_deps_exactish_versioned([]) :- !, fail.
rules:all_deps_exactish_versioned(Deps) :-
  forall(member(package_dependency(_P,_Strength,_C,_N,Op,Ver,SlotReq,_U), Deps),
         ( SlotReq == [],
           ( Op == tilde ; Op == equal ),
           nonvar(Ver)
         )),
  !.

rules:multiple_distinct_exactish_versions(Deps) :-
  findall(Full,
          ( member(package_dependency(_P,_Strength,_C,_N,_Op,Ver,_SlotReq,_U), Deps),
            ( Ver = [_Nums,_A,_S,Full] -> true ; Full = Ver )
          ),
          Vs0),
  sort(Vs0, Vs),
  Vs = [_|Rest],
  Rest \== [],
  !.

rules:should_split_grouped_dep(PackageDeps) :-
  ( rules:all_deps_have_explicit_slot(PackageDeps),
    rules:multiple_distinct_slots(PackageDeps)
  ; rules:all_deps_exactish_versioned(PackageDeps),
    rules:multiple_distinct_exactish_versions(PackageDeps)
  ),
  !.

% -----------------------------------------------------------------------------
%  Context helpers: drop diagnostic / per-package USE constraints
% -----------------------------------------------------------------------------

rules:ctx_drop_build_with_use(Ctx0, Ctx) :-
  ( is_list(Ctx0) ->
      exclude(rules:ctx_is_build_with_use_term, Ctx0, Ctx)
  ; Ctx = Ctx0
  ),
  !.

rules:ctx_is_build_with_use_term(build_with_use:_) :- !.

rules:ctx_drop_assumption_reason(Ctx0, Ctx) :-
  ( is_list(Ctx0) ->
      exclude(rules:ctx_is_assumption_reason_term, Ctx0, Ctx)
  ; Ctx = Ctx0
  ),
  !.

rules:ctx_is_assumption_reason_term(assumption_reason(_)) :- !.

rules:ctx_drop_build_with_use_and_assumption_reason(Ctx0, Ctx) :-
  ( is_list(Ctx0) ->
      exclude(rules:ctx_is_bwu_or_assumption_reason, Ctx0, Ctx)
  ; Ctx = Ctx0
  ),
  !.

rules:ctx_is_bwu_or_assumption_reason(build_with_use:_) :- !.
rules:ctx_is_bwu_or_assumption_reason(assumption_reason(_)) :- !.

% -----------------------------------------------------------------------------
%  Lazy self-RDEPEND version-bound propagation (timeout-safe variant)
% -----------------------------------------------------------------------------
%
% Some packages impose runtime version bounds on a dependency that is also used
% at build/install time. If we ignore those bounds during candidate selection for
% install deps, we can pick an inconsistent version and diverge from Portage.
%
% Naively scanning the full RDEPEND tree for every package during proof search is
% extremely expensive at repository scale. We therefore:
% - only apply this for Action == install (build/install dependency resolution),
% - only apply it when Context includes self(Repo://SelfId),
% - only apply it when the current dep (C,N) has no version constraint already,
% - cache the derived bounds per (Repo,SelfId,C,N).
%
% We only propagate version/slot constraints here; USE deps from RDEPEND are not
% merged into PackageDeps (to avoid unintended build_with_use pollution).
rules:augment_package_deps_with_self_rdepend(install, C, N, Context, PackageDeps0, PackageDeps) :-
  ( memberchk(self(RepoEntry0), Context) ->
      ( RepoEntry0 = Repo://SelfId -> true
      ; RepoEntry0 = Repo//SelfId  -> true
      )
  ; fail
  ),
  % If the dependency already carries a version constraint, don't add more.
  ( rules:dep_has_version_constraints(C, N, PackageDeps0) ->
      PackageDeps = PackageDeps0
  ; rules:self_rdepend_vbounds_for_cn(Repo, SelfId, C, N, Extra0),
    % Keep self-RDEPEND propagation bounded by explicit slot intent of the
    % current grouped dependency. Without this, we can incorrectly merge
    % incompatible slot-bounded runtime constraints into an explicit-slot DEPEND
    % edge (e.g. :3.5 with :4), creating impossible CN domains.
    ( merge_slot_restriction(install, C, N, PackageDeps0, BaseSlotReq) ->
        true
    ; BaseSlotReq = []
    ),
    findall(ExtraDep,
            ( member(ExtraDep, Extra0),
              rules:self_rdepend_extra_slot_compatible(BaseSlotReq, ExtraDep)
            ),
            Extra),
    ( Extra == [] ->
        PackageDeps = PackageDeps0
    ; append(PackageDeps0, Extra, PackageDeps)
    )
  ),
  !.
rules:augment_package_deps_with_self_rdepend(_OtherAction, _C, _N, _Context, PackageDeps, PackageDeps) :-
  !.

% True iff PackageDeps contains at least one non-trivial version comparator for (C,N).
rules:dep_has_version_constraints(C, N, PackageDeps) :-
  member(package_dependency(_Phase, no, C, N, Op, _V, _S, _U), PackageDeps),
  Op \== none,
  !.

% For explicit-slot grouped deps, keep only self-RDEPEND propagated bounds that
% are either unslotted or in that same explicit slot. For non-explicit base slot
% requests ([], any_same_slot, any_different_slot), preserve previous behavior.
rules:self_rdepend_extra_slot_compatible([], _ExtraDep) :-
  !.
rules:self_rdepend_extra_slot_compatible([slot(S0)|_],
                                         package_dependency(_P,_Strength,_C,_N,_Op,_V,SlotReq,_U)) :-
  !,
  rules:canon_slot(S0, S),
  ( SlotReq == []
  ; SlotReq = [slot(S1)|_],
    rules:canon_slot(S1, S)
  ).
rules:self_rdepend_extra_slot_compatible(_BaseSlotReq, _ExtraDep) :-
  !.

% Lookup extra version-bound deps from Self's RDEPEND for a specific (C,N).
% Cached per (Repo,SelfId,C,N). Negative results are cached as [].
rules:self_rdepend_vbounds_for_cn(Repo, SelfId, C, N, Extra) :-
  ( nb_current(rules_self_rdepend_vbounds_cn_cache, Cache),
    get_assoc(key(Repo,SelfId,C,N), Cache, Extra0)
  ->
    Extra = Extra0
  ;
    rules:build_self_rdepend_vbounds_for_cn(Repo, SelfId, C, N, Extra1),
    ( nb_current(rules_self_rdepend_vbounds_cn_cache, Cache0) -> true ; empty_assoc(Cache0) ),
    put_assoc(key(Repo,SelfId,C,N), Cache0, Extra1, Cache1),
    nb_setval(rules_self_rdepend_vbounds_cn_cache, Cache1),
    Extra = Extra1
  ),
  !.

rules:build_self_rdepend_vbounds_for_cn(Repo, SelfId, C, N, Extra) :-
  SelfRepoEntry = Repo://SelfId,
  findall(Term, cache:entry_metadata(Repo, SelfId, rdepend, Term), Terms),
  findall(Dep,
          ( member(Term, Terms),
            rules:rdepend_collect_vbounds_for_cn(Term, C, N, SelfRepoEntry, Deps0),
            member(Dep, Deps0)
          ),
          Extra0),
  sort(Extra0, Extra),
  !.

% Collect version-bounded leaves for (C,N) from an RDEPEND term.
% We traverse the dependency AST explicitly (faster + more selective than sub_term/2).
% IMPORTANT: only propagate regular deps (Strength=no). Weak/strong blockers
% must not become hard CN-domain bounds during self-RDEPEND augmentation.
rules:rdepend_collect_vbounds_for_cn(package_dependency(_P, no, C, N, Op, V, SlotReq, _UseDeps),
                                    C, N, _SelfRepoEntry,
                                    [package_dependency(run, no, C, N, Op, V, SlotReq, [])]) :-
  Op \== none,
  !.
rules:rdepend_collect_vbounds_for_cn(package_dependency(_P, _Strength, _C, _N, _Op, _V, _SlotReq, _UseDeps),
                                    _C0, _N0, _SelfRepoEntry, []) :-
  !.
rules:rdepend_collect_vbounds_for_cn(use_conditional_group(Pol, Use, _Self, Deps0), C, N, SelfRepoEntry, Deps) :-
  !,
  ( rules:rdepend_self_use_conditional_active(Pol, Use, SelfRepoEntry) ->
      rules:rdepend_collect_vbounds_for_cn_list(Deps0, C, N, SelfRepoEntry, Deps)
  ; Deps = []
  ).
rules:rdepend_collect_vbounds_for_cn(any_of_group(Deps0), C, N, SelfRepoEntry, Deps) :-
  !,
  rules:rdepend_collect_vbounds_for_cn_choice_intersection(Deps0, C, N, SelfRepoEntry, Deps).
rules:rdepend_collect_vbounds_for_cn(all_of_group(Deps0), C, N, SelfRepoEntry, Deps) :-
  !,
  rules:rdepend_collect_vbounds_for_cn_list(Deps0, C, N, SelfRepoEntry, Deps).
rules:rdepend_collect_vbounds_for_cn(exactly_one_of_group(Deps0), C, N, SelfRepoEntry, Deps) :-
  !,
  rules:rdepend_collect_vbounds_for_cn_choice_intersection(Deps0, C, N, SelfRepoEntry, Deps).
rules:rdepend_collect_vbounds_for_cn(at_most_one_of_group(Deps0), C, N, SelfRepoEntry, Deps) :-
  !,
  rules:rdepend_collect_vbounds_for_cn_choice_intersection(Deps0, C, N, SelfRepoEntry, Deps).
rules:rdepend_collect_vbounds_for_cn(_Other, _C, _N, _SelfRepoEntry, []) :-
  !.

rules:rdepend_collect_vbounds_for_cn_list([], _C, _N, _SelfRepoEntry, []) :- !.
rules:rdepend_collect_vbounds_for_cn_list([T|Ts], C, N, SelfRepoEntry, Deps) :-
  rules:rdepend_collect_vbounds_for_cn(T, C, N, SelfRepoEntry, D0),
  rules:rdepend_collect_vbounds_for_cn_list(Ts, C, N, SelfRepoEntry, D1),
  append(D0, D1, Deps),
  !.

% A USE-conditional branch contributes only when it is active for the current
% self package's effective USE. For non-IUSE flags, mirror the same fallback
% semantics used by use_conditional_group rules (profile/env driven).
rules:rdepend_self_use_conditional_active(positive, Use, SelfRepoEntry) :-
  ( rules:effective_use_for_entry(SelfRepoEntry, Use, positive) ->
      true
  ; \+ rules:rdepend_self_entry_has_iuse_flag(SelfRepoEntry, Use),
    preference:use(Use)
  ),
  !.
rules:rdepend_self_use_conditional_active(negative, Use, SelfRepoEntry) :-
  ( rules:effective_use_for_entry(SelfRepoEntry, Use, negative) ->
      true
  ; \+ rules:rdepend_self_entry_has_iuse_flag(SelfRepoEntry, Use),
    preference:use(minus(Use))
  ; \+ rules:rdepend_self_entry_has_iuse_flag(SelfRepoEntry, Use),
    \+ preference:use(Use),
    \+ preference:use(minus(Use))
  ),
  !.
rules:rdepend_self_use_conditional_active(_Pol, _Use, _SelfRepoEntry) :-
  fail.

rules:rdepend_self_entry_has_iuse_flag(Repo://Entry, Use) :-
  rules:entry_iuse_info(Repo://Entry, iuse_info(IuseSet, _PlusSet)),
  memberchk(Use, IuseSet),
  !.
rules:rdepend_self_entry_has_iuse_flag(_RepoEntry, _Use) :-
  fail.

% For choice groups (||, exactly-one, at-most-one), only constraints that are
% common to all alternatives are guaranteed and safe to propagate.
rules:rdepend_collect_vbounds_for_cn_choice_intersection([], _C, _N, _SelfRepoEntry, []) :-
  !.
rules:rdepend_collect_vbounds_for_cn_choice_intersection([Dep|Deps], C, N, SelfRepoEntry, Common) :-
  rules:rdepend_collect_vbounds_for_cn(Dep, C, N, SelfRepoEntry, First0),
  sort(First0, First),
  rules:rdepend_collect_vbounds_for_cn_choice_intersection_(Deps, C, N, SelfRepoEntry, First, Common),
  !.

rules:rdepend_collect_vbounds_for_cn_choice_intersection_([], _C, _N, _SelfRepoEntry, Acc, Acc) :-
  !.
rules:rdepend_collect_vbounds_for_cn_choice_intersection_([Dep|Deps], C, N, SelfRepoEntry, Acc0, Common) :-
  rules:rdepend_collect_vbounds_for_cn(Dep, C, N, SelfRepoEntry, Next0),
  sort(Next0, Next),
  ord_intersection(Acc0, Next, Acc1),
  rules:rdepend_collect_vbounds_for_cn_choice_intersection_(Deps, C, N, SelfRepoEntry, Acc1, Common),
  !.


% -----------------------------------------------------------------------------
%  License masking (ACCEPT_LICENSE)
% -----------------------------------------------------------------------------
%
% A candidate is license-masked when its effective licenses (after evaluating
% USE conditionals against the package's IUSE defaults + active USE) include
% any license not covered by ACCEPT_LICENSE.  Such candidates are excluded
% from dependency resolution, mirroring Portage's behavior.

%! rules:license_masked(+Repo://Entry) is semidet.
%
% True when at least one effective license of Entry is not accepted.

rules:license_masked(Repo://Entry) :-
  rules:effective_license(Repo://Entry, Lic),
  \+ preference:license_accepted(Lic),
  !.

%! rules:effective_license(+Repo://Entry, -License:atom) is nondet.
%
% Enumerates the effective (active) license atoms for an entry,
% evaluating USE-conditional groups against the entry's effective USE.

rules:effective_license(Repo://Entry, License) :-
  cache:entry_metadata(Repo, Entry, license, LicTerm),
  rules:effective_license_term_(LicTerm, Repo://Entry, License).

rules:effective_license_term_(use_conditional_group(Pol, Use, _Self, Deps), RepoEntry, License) :-
  !,
  rules:rdepend_self_use_conditional_active(Pol, Use, RepoEntry),
  member(D, Deps),
  rules:effective_license_term_(D, RepoEntry, License).
rules:effective_license_term_(License, _RepoEntry, License) :-
  atom(License).


%! rules:dep_license_ok(+Dep) is semidet.
%
% True when the best candidate for Dep is not license-masked.
% Used by prioritize_deps_keep_all to deprioritize license-masked
% alternatives in || groups.

rules:dep_license_ok(package_dependency(_, _, C, N, _, _, _, _)) :- !,
  cache:ordered_entry(Repo, Entry, C, N, _),
  \+ preference:masked(Repo://Entry),
  \+ rules:license_masked(Repo://Entry).
rules:dep_license_ok(grouped_package_dependency(_, C, N, _)) :- !,
  cache:ordered_entry(Repo, Entry, C, N, _),
  \+ preference:masked(Repo://Entry),
  \+ rules:license_masked(Repo://Entry).
rules:dep_license_ok(_).


% -----------------------------------------------------------------------------
%  Keyword-aware candidate enumeration (Portage-like)
% -----------------------------------------------------------------------------
%
% Enumerate candidates that match any accepted keyword, in descending version
% order, so the solver tries the best versions first but can backtrack to
% older alternatives.

rules:accepted_keyword_candidate(Action, C, N, SlotReq0, Ss0, Context, FoundRepo://Candidate) :-
  rules:accepted_keyword_slot_lock_arg(C, N, SlotReq0, Ss0, Context, SlotReq, Ss, LockKey),
  ( preference:keyword_selection_mode(keyword_order) ->
      % Legacy behavior: accept_keywords enumeration order is a preference.
      preference:accept_keywords(K),
      rules:query_keyword_candidate(Action, C, N, K, Context, FoundRepo://Candidate),
      rules:query_search_slot_constraint(SlotReq, FoundRepo://Candidate, Ss)
  ; % Portage-like: union of accepted keywords, then choose max version first.
    % Avoid caching in the rare "self-dependency" case, because Context affects
    % candidate enumeration (we only accept installed self for non-run actions).
    ( Action \== run,
      memberchk(self(SelfRepo0://SelfEntry0), Context),
      query:search([category(C),name(N)], SelfRepo0://SelfEntry0)
    ->
      findall(FoundRepo0://Candidate0,
              ( preference:accept_keywords(K0),
                rules:query_keyword_candidate(Action, C, N, K0, Context, FoundRepo0://Candidate0),
                rules:query_search_slot_constraint(SlotReq, FoundRepo0://Candidate0, Ss)
              ),
              Candidates0),
      Candidates0 \== [],
      sort(Candidates0, Candidates1),
      predsort(rules:compare_candidate_version_desc, Candidates1, CandidatesSorted),
      member(FoundRepo://Candidate, CandidatesSorted)
    ;
      rules:accepted_keyword_candidates_cached(Action, C, N, SlotReq, LockKey, CandidatesSorted0),
      rules:candidates_prefer_proven_providers(C, N, SlotReq, CandidatesSorted0, CandidatesSorted),
      ( rules:greedy_candidate_package(C, N) ->
          member(FoundRepo://Candidate, CandidatesSorted),
          rules:query_search_slot_constraint(SlotReq, FoundRepo://Candidate, Ss)
      ; member(FoundRepo://Candidate, CandidatesSorted),
        rules:query_search_slot_constraint(SlotReq, FoundRepo://Candidate, Ss)
      )
    )
  ).

rules:accepted_keyword_slot_lock_arg(C, N, SlotReq0, Ss0, Context, SlotReq, Ss, LockKey) :-
  ( memberchk(slot(C,N,SsCtx0):{_}, Context) ->
      rules:canon_any_same_slot_meta(SsCtx0, SsCtx)
  ; SsCtx = _NoCtxLock
  ),
  ( SlotReq0 == [],
    nonvar(SsCtx)
  ->
    SlotReq1 = [any_same_slot]
  ; SlotReq1 = SlotReq0
  ),
  ( SlotReq1 == [any_same_slot] ->
      ( nonvar(Ss0) ->
          rules:canon_any_same_slot_meta(Ss0, Ss1)
      ; nonvar(SsCtx) ->
          Ss1 = SsCtx
      ; Ss1 = _NoSlotLock
      ),
      SlotReq = [any_same_slot],
      Ss = Ss1
  ; SlotReq = SlotReq1,
    Ss = Ss0
  ),
  rules:accepted_keyword_slot_lock_key(SlotReq, Ss, LockKey),
  !.

rules:accepted_keyword_slot_lock_key([any_same_slot], Ss, slot(S)) :-
  nonvar(Ss),
  rules:canon_any_same_slot_meta(Ss, [slot(S)|_]),
  !.
rules:accepted_keyword_slot_lock_key(_SlotReq, _Ss, any) :-
  !.

rules:accepted_keyword_slot_lock_filter([any_same_slot], slot(S), [slot(S)]) :-
  !.
rules:accepted_keyword_slot_lock_filter(_SlotReq, _LockKey, _SsFilter) :-
  !.

% -----------------------------------------------------------------------------
%  Candidate backtracking policy (Portage-like)
% -----------------------------------------------------------------------------
%
% Portage typically selects the best (max) version and does limited backtracking.
% Some packages (toolchains / core libs) are extremely common and can dominate
% proof search when we backtrack across many acceptable versions.
%
% We therefore treat a small, curated set as "greedy": pick the max version and
% do not enumerate alternatives.
rules:greedy_candidate_package('dev-lang', ocaml) :- !.
rules:greedy_candidate_package('dev-ml', findlib) :- !.
rules:greedy_candidate_package('dev-ml', ocamlbuild) :- !.

% -----------------------------------------------------------------------------
%  Memoization: accepted_keyword_candidate/7 (performance)
% -----------------------------------------------------------------------------
%
% Whole-tree proofs repeatedly resolve the same (Category,Name) dependencies with
% the same slot restriction, across thousands of parents. Building the candidate
% union list each time (findall/sort/predsort) becomes a dominant cost for large
% stacks (llvm, gstreamer, ...).
%
% We memoize the *sorted* candidate list per (Action,C,N,SlotReq). Context is
% ignored on purpose (except for the self-case handled above), because it does
% not affect keyword/mask/version enumeration.

rules:accepted_keyword_candidates_cached(Action, C, N, SlotReq, LockKey, CandidatesSorted) :-
  ( nb_current(rules_accepted_keyword_cache, Cache),
    get_assoc(key(Action,C,N,SlotReq,LockKey), Cache, CandidatesSorted)
  ->
    true
  ;
    rules:accepted_keyword_slot_lock_filter(SlotReq, LockKey, SsFilter),
    findall(FoundRepo0://Candidate0,
            ( preference:accept_keywords(K0),
              rules:query_keyword_candidate(Action, C, N, K0, [], FoundRepo0://Candidate0),
              rules:query_search_slot_constraint(SlotReq, FoundRepo0://Candidate0, SsFilter)
            ),
            Candidates0),
    Candidates0 \== [],
    sort(Candidates0, Candidates1),
    predsort(rules:compare_candidate_version_desc, Candidates1, CandidatesSorted),
    ( nb_current(rules_accepted_keyword_cache, Cache0) -> true ; empty_assoc(Cache0) ),
    put_assoc(key(Action,C,N,SlotReq,LockKey), Cache0, CandidatesSorted, Cache1),
    nb_setval(rules_accepted_keyword_cache, Cache1)
  ).

rules:query_keyword_candidate(Action, C, N, K, Context, FoundRepo://Candidate) :-
  ( Action \== run,
    memberchk(self(SelfRepo0://SelfEntry0), Context),
    query:search([category(C),name(N)], SelfRepo0://SelfEntry0)
  ->
    query:search([name(N),category(C),keyword(K)], FoundRepo://Candidate),
    \+ preference:masked(FoundRepo://Candidate),
    ( FoundRepo == SelfRepo0,
      Candidate == SelfEntry0
    ->
      \+ preference:flag(emptytree),
      query:search(installed(true), FoundRepo://Candidate)
    ; true
    )
  ; query:search([name(N),category(C),keyword(K)], FoundRepo://Candidate),
    \+ preference:masked(FoundRepo://Candidate)
  ).

rules:compare_candidate_version_desc(Delta, RepoA://IdA, RepoB://IdB) :-
  cache:ordered_entry(RepoA, IdA, _Ca, _Na, VerA),
  cache:ordered_entry(RepoB, IdB, _Cb, _Nb, VerB),
  ( eapi:version_compare(>, VerA, VerB) -> Delta = (<)
  ; eapi:version_compare(<, VerA, VerB) -> Delta = (>)
  ; Delta = (=)
  ).


% -----------------------------------------------------------------------------
%  Provider-reuse candidate reordering (Portage-like)
% -----------------------------------------------------------------------------
%
% Portage minimises the dependency graph: when resolving >=virtual/jre-1.8:*
% and virtual/jdk:21 is already selected, it prefers virtual/jre:21 (whose
% provider jdk:21 is already in the graph) over jre:25 (which would pull a
% fresh jdk:25 + openjdk-bin:25).
%
% We approximate this by doing a single-depth lookahead into each candidate's
% RDEPEND: if a provider (C',N') in slot S is already present in the global
% selected_cn snapshot, the candidate is promoted ahead of candidates that
% would introduce new providers.  Only fires for virtual/* packages with
% unconstrained slot deps (any_different_slot / [] / any_same_slot).

rules:candidates_prefer_proven_providers(virtual, _N, SlotReq, Candidates, Reordered) :-
  SlotReq \= [slot(_)|_],
  include(rules:candidate_has_proven_provider, Candidates, Preferred),
  Preferred \== [],
  !,
  subtract(Candidates, Preferred, Rest),
  append(Preferred, Rest, Reordered).
rules:candidates_prefer_proven_providers(_C, _N, _SlotReq, Candidates, Candidates).

rules:candidate_has_proven_provider(Repo://Entry) :-
  cache:entry_metadata(Repo, Entry, rdepend, Dep),
  rules:dep_references_selected_cn(Dep),
  !.

rules:dep_references_selected_cn(package_dependency(_Phase,_Str,C,N,_O,_V,Ss,_U)) :-
  rules:snapshot_selected_cn_candidates(C, N, SelCandidates),
  ( Ss = [slot(ReqSlot0)|_] ->
      rules:canon_slot(ReqSlot0, ReqSlot),
      member(SelRepo://SelEntry, SelCandidates),
      query:search(slot(SelSlotRaw), SelRepo://SelEntry),
      rules:canon_slot(SelSlotRaw, SelSlot),
      ReqSlot == SelSlot
  ; true
  ),
  !.
rules:dep_references_selected_cn(any_of_group(Deps)) :-
  member(D, Deps),
  rules:dep_references_selected_cn(D),
  !.


% -----------------------------------------------------------------------------
%  build_with_use satisfaction for installed packages
% -----------------------------------------------------------------------------
%
% When a dependency is already installed (VDB repo `pkg`), it is only safe to
% treat it as "satisfying" the dependency if its *built USE* satisfies any
% incoming bracketed USE constraints carried via build_with_use:List in Context.
%
% Otherwise, we must schedule a rebuild/reinstall.

rules:context_build_with_use_list(Context, List) :-
  % Backwards-compatible helper: if the context stores a use_state/2, expose it
  % as a flat list of assumed/1 terms.
  ( memberchk(build_with_use:use_state(En, Dis), Context) ->
      findall(assumed(U), member(U, En), Pos),
      findall(assumed(minus(U)), member(U, Dis), Neg),
      append(Pos, Neg, List0),
      sort(List0, List)
  ; memberchk(build_with_use:List0, Context) ->
      List = List0
  ; List = []
  ).

rules:build_with_use_requirements(use_state(En, Dis), MustEnable, MustDisable) :-
  !,
  sort(En, MustEnable),
  sort(Dis, MustDisable).
rules:build_with_use_requirements(BuildWithUse, MustEnable, MustDisable) :-
  findall(U,
          ( member(required(U), BuildWithUse),
            \+ U =.. [minus,_]
          ),
          En0),
  findall(U,
          ( ( member(naf(required(U)), BuildWithUse)
            ; member(assumed(minus(U)), BuildWithUse)
            ),
            \+ U =.. [minus,_]
          ),
          Dis0),
  sort(En0, MustEnable),
  sort(Dis0, MustDisable).

rules:installed_entry_satisfies_build_with_use(pkg://InstalledEntry, Context) :-
  rules:context_build_with_use_state(Context, State),
  rules:build_with_use_requirements(State, MustEnable, MustDisable),
  rules:vdb_enabled_use_set(pkg://InstalledEntry, BuiltUse),
  % If a bracketed USE requirement names a flag that is not in the package's IUSE,
  % Portage only accepts it when a default marker (+)/(-) is present (EAPI 8).
  % In that case the flag's state is not configurable and should not force a
  % rebuild based on VDB USE contents.
  rules:vdb_iuse_set(pkg://InstalledEntry, BuiltIuse),
  forall(member(U, MustEnable),
         ( memberchk(U, BuiltIuse) -> memberchk(U, BuiltUse)
         ; true
         )),
  forall(member(U, MustDisable),
         ( memberchk(U, BuiltIuse) -> \+ memberchk(U, BuiltUse)
         ; true
         )).

% -----------------------------------------------------------------------------
%  --newuse support (Portage-like -N)
% -----------------------------------------------------------------------------
%
% Minimal implementation:
% - Compare installed VDB USE (what the package was built with) against the
%   currently effective USE for the same version (when available in repo set).
% - Also compare installed VDB IUSE against current IUSE to detect added/removed
%   flags (if VDB provides IUSE; we parse it when present).
%
% If we cannot locate the same version in the current repo set, we conservatively
% do not force a rebuild.

rules:newuse_mismatch(pkg://InstalledEntry) :-
  % Find the same version in the active repo set (excluding VDB repo `pkg`).
  query:search([category(C),name(N),version(V)], pkg://InstalledEntry),
  preference:accept_keywords(K),
  ( query:search([select(repository,notequal,pkg),category(C),name(N),keywords(K),version(V)],
                 CurRepo//CurEntry)
  -> rules:newuse_mismatch(pkg://InstalledEntry, CurRepo//CurEntry)
  ;  fail
  ).

rules:newuse_mismatch(pkg://InstalledEntry, CurRepo//CurEntry) :-
  rules:vdb_enabled_use_set(pkg://InstalledEntry, BuiltUse),
  rules:entry_enabled_use_set(CurRepo//CurEntry, CurUse),
  ( rules:symmetric_diff_nonempty(BuiltUse, CurUse)
  ; rules:vdb_iuse_set(pkg://InstalledEntry, BuiltIuse),
    rules:entry_iuse_set(CurRepo//CurEntry, CurIuse),
    BuiltIuse \== [],
    CurIuse \== [],
    rules:symmetric_diff_nonempty(BuiltIuse, CurIuse)
  ),
  !.

rules:vdb_enabled_use_set(RepoEntry, UseSet) :-
  findall(U, query:search(use(U), RepoEntry), Us0),
  sort(Us0, UseSet).

rules:entry_iuse_set(RepoEntry, IuseSet) :-
  findall(U,
          ( query:search(iuse(Value), RepoEntry),
            eapi:strip_use_default(Value, U)
          ),
          Us0),
  sort(Us0, IuseSet).

rules:vdb_iuse_set(RepoEntry, IuseSet) :-
  rules:entry_iuse_set(RepoEntry, IuseSet).

% Current effective enabled USE set for an ebuild entry:
% gather IUSE flags that evaluate to positive under current preference/profile.
rules:entry_enabled_use_set(RepoEntry, UseSet) :-
  findall(U,
          ( query:search(iuse(Value), RepoEntry),
            eapi:categorize_use(Value, positive, _Reason),
            eapi:strip_use_default(Value, U)
          ),
          Us0),
  sort(Us0, UseSet).

rules:symmetric_diff_nonempty(A, B) :-
  ( member(X, A), \+ memberchk(X, B) -> true
  ; member(X, B), \+ memberchk(X, A) -> true
  ).


% -----------------------------------------------------------------------------
%  Depclean traversal rules
% -----------------------------------------------------------------------------
%
% These are used by depclean:run/1 to compute a "kept" closure over *installed*
% packages only, using repository metadata for dependency structure.

rule(Repository://Ebuild:depclean?{Context}, Conditions) :-
  % Use current preference/profile to evaluate USE conditionals.
  ( query:search(model(Model,required_use(_),build_with_use(_)), Repository://Ebuild),
    % Compute runtime dependency model in config phase (no candidate choices here).
    query:memoized_search(model(dependency(MergedDeps0,run)):config?{Model}, Repository://Ebuild),
    add_self_to_dep_contexts(Repository://Ebuild, MergedDeps0, MergedDeps),
    % Rewrite all dependency literals to the depclean action.
    rules:depclean_rewrite_deps(MergedDeps, Context, Conditions)
  -> true
  ; Conditions = []
  ).

rules:depclean_rewrite_deps([], _ParentCtx, []) :- !.
rules:depclean_rewrite_deps([D0|Rest0], ParentCtx, [D|Rest]) :-
  rules:depclean_rewrite_dep(D0, ParentCtx, D),
  rules:depclean_rewrite_deps(Rest0, ParentCtx, Rest).

rules:depclean_rewrite_dep(Term:Action?{Ctx0}, _ParentCtx, Term:depclean?{Ctx0}) :-
  nonvar(Action),
  !.
rules:depclean_rewrite_dep(Term:Action, _ParentCtx, Term:depclean?{[]}) :-
  nonvar(Action),
  !.
rules:depclean_rewrite_dep(Term, _ParentCtx, Term:depclean?{[]}) :-
  !.

% Depclean: grouped package dependency – follow only installed packages.
rule(grouped_package_dependency(no,C,N,PackageDeps):depclean?{_Context}, Conditions) :-
  !,
  merge_slot_restriction(run, C, N, PackageDeps, SlotReq),
  ( query:search([name(N),category(C),installed(true)], pkg://InstalledEntry),
    rules:query_search_slot_constraint(SlotReq, pkg://InstalledEntry, _),
    rules:installed_entry_satisfies_package_deps(run, C, N, PackageDeps, pkg://InstalledEntry),
    % Find same-version repo entry (exclude pkg).
    query:search(version(V), pkg://InstalledEntry),
    preference:accept_keywords(K),
    query:search([select(repository,notequal,pkg),category(C),name(N),keywords(K),version(V)],
                 Repo//InstalledEntry)
  ->
    Conditions = [Repo//InstalledEntry:depclean?{[]}]
  ; Conditions = []
  ).

% Depclean: ignore blockers (they do not decide whether something is "needed").
rule(grouped_package_dependency(_Strength,_C,_N,_PackageDeps):depclean?{_Context}, []) :-
  !.



% -----------------------------------------------------------------------------
%  Rule: Positive use conditional dependencies
% -----------------------------------------------------------------------------
% The dependencies in a positive use conditional group need to be satisfied when
% the use flag is positive through required use constraint, preference or ebuild
% default

% 1. The USE is enabled in the context (dependency induced, or required_use)

rule(use_conditional_group(positive,Use,_R://_E,Deps):Action?{Context},Conditions) :-
  rules:ctx_assumed(Context, Use),
  !,
  findall(D:Action?{Context},member(D,Deps),Conditions0),
  sort(Conditions0, Conditions).

% 1b. The USE is enabled globally (profile/env), but it is *not* an IUSE flag of
% this ebuild (e.g. kernel_linux, elibc_glibc, userland_GNU). Gentoo allows such
% conditionals; they are profile-driven, not package-driven.
rule(use_conditional_group(positive,Use,R://E,Deps):Action?{Context},Conditions) :-
  \+ Use =.. [minus,_],
  preference:use(Use),
  \+ ( query:search(iuse(Value), R://E),
       eapi:strip_use_default(Value, Use) ),
  !,
  findall(D:Action?{Context}, member(D,Deps), Conditions0),
  sort(Conditions0, Conditions).

% 2. The USE is explicitely enabled, either by preference or ebuild -> process deps

rule(use_conditional_group(positive,Use,R://E,Deps):Action?{Context},Conditions) :-
  % Fast check: avoid scanning all IUSE entries (clang/llvm has huge IUSE lists).
  rules:effective_use_for_entry(R://E, Use, positive),
  !,
  findall(D:Action?{Context}, member(D, Deps), Result0),
  sort(Result0, Conditions).

% 3. The USE is not enabled -> no deps

rule(use_conditional_group(positive,_Use,_R://_E,_):_?{_},[]) :-
  !.


% -----------------------------------------------------------------------------
%  Rule: Negative use conditional dependencies
% -----------------------------------------------------------------------------
% The dependencies in a negative use conditional group need to be satisfied when
% the use flag is not positive through required use constraint, preference or
% ebuild default

% 1. The USE is disabled in the context (dependency induced, or required_use)

rule(use_conditional_group(negative,Use,_R://_E,Deps):Action?{Context},Conditions) :-
  % Context propagation uses per-package USE state under build_with_use.
  rules:ctx_assumed_minus(Context, Use),
  !,
  findall(D:Action?{Context},member(D,Deps),Conditions0),
  sort(Conditions0, Conditions).

% 1b. Explicitly disabled globally (profile/env), but not an IUSE flag.
rule(use_conditional_group(negative,Use,R://E,Deps):Action?{Context},Conditions) :-
  preference:use(minus(Use)),
  \+ ( query:search(iuse(Value), R://E),
       eapi:strip_use_default(Value, Use) ),
  !,
  findall(D:Action?{Context}, member(D,Deps), Conditions0),
  sort(Conditions0, Conditions).

% 1c. Default-off globally (not set), but not an IUSE flag.
rule(use_conditional_group(negative,Use,R://E,Deps):Action?{Context},Conditions) :-
  \+ preference:use(Use),
  \+ preference:use(minus(Use)),
  \+ ( query:search(iuse(Value), R://E),
       eapi:strip_use_default(Value, Use) ),
  !,
  findall(D:Action?{Context}, member(D,Deps), Conditions0),
  sort(Conditions0, Conditions).

% 2. The USE is explicitely enabled, either by preference or ebuild -> process deps

rule(use_conditional_group(negative,Use,R://E,Deps):Action?{Context},Conditions) :-
  % Fast check: avoid scanning all IUSE entries (clang/llvm has huge IUSE lists).
  rules:effective_use_for_entry(R://E, Use, negative),
  !,
  findall(D:Action?{Context}, member(D, Deps), Result0),
  sort(Result0, Conditions).

% 3. The USE is not enabled -> no deps

rule(use_conditional_group(negative,_Use,_R://_E,_):_?{_},[]) :-
  !.


% -----------------------------------------------------------------------------
%  Rule: Contextless use conditionals
% -----------------------------------------------------------------------------
% Contextless use conditionals are found in for example required_use constraints.

% In REQUIRED_USE evaluation, interpret conditionals against the current ebuild's
% *effective USE* (IUSE defaults + profile/env/package.use), not just global USE.
rule(use_conditional_group(positive,Use,Self,_Deps),[]) :-
  nb_current(query_required_use_self, Self),
  \+ Use =.. [minus,_],
  \+ rules:effective_use_in_context([], Use, positive),
  !.
rule(use_conditional_group(positive,Use,Self,Deps),Conditions) :-
  nb_current(query_required_use_self, Self),
  \+ Use =.. [minus,_],
  rules:effective_use_in_context([], Use, positive),
  !,
  findall(D, member(D,Deps), Conditions0),
  sort(Conditions0, Conditions).

rule(use_conditional_group(positive,Use,_://_,Deps),Conditions) :-
  preference:use(Use),!,
  findall(D,member(D,Deps),Conditions0),
  sort(Conditions0, Conditions).

rule(use_conditional_group(positive,_,_://_,_),[]) :- !.

rule(use_conditional_group(negative,Use,Self,_Deps),[]) :-
  nb_current(query_required_use_self, Self),
  \+ Use =.. [minus,_],
  \+ rules:effective_use_in_context([], Use, negative),
  !.
rule(use_conditional_group(negative,Use,Self,Deps),Conditions) :-
  nb_current(query_required_use_self, Self),
  \+ Use =.. [minus,_],
  rules:effective_use_in_context([], Use, negative),
  !,
  findall(D, member(D,Deps), Conditions0),
  sort(Conditions0, Conditions).

rule(use_conditional_group(negative,Use,_://_,Deps),Conditions) :-
  preference:use(minus(Use)),!,
  findall(D,member(D,Deps),Conditions0),
  sort(Conditions0, Conditions).

rule(use_conditional_group(negative,_,_://_,_),[]) :- !.


% -----------------------------------------------------------------------------
%  Rule: Exactly one of group
% -----------------------------------------------------------------------------
% Exactly one of the dependencies in an exactly-one-of-group should be satisfied

% REQUIRED_USE evaluation: check, don't search.
rule(exactly_one_of_group(Deps),[]) :-
  nb_current(query_required_use_self, _Self),
  findall(1, (member(D, Deps), rules:required_use_term_satisfied(D)), Ones),
  length(Ones, 1),
  !.
rule(exactly_one_of_group(Deps),[assumed(conflict(required_use,exactly_one_of_group(Deps)))]) :-
  nb_current(query_required_use_self, _Self),
  !.

rule(exactly_one_of_group(Deps):Action?{Context},[D:Action?{Context}|NafDeps]) :-
  prioritize_deps(Deps, Context, SortedDeps),
  member(D0, SortedDeps),
  rules:group_choice_dep(D0, D),
  findall(naf(N),(member(N,Deps), \+(D = N)),NafDeps).

rule(exactly_one_of_group(Deps),[D|NafDeps]) :-
  prioritize_deps(Deps, SortedDeps),
  member(D, SortedDeps),
  findall(naf(N),(member(N,Deps), \+(D = N)),NafDeps).


% -----------------------------------------------------------------------------
%  Rule: At most one of group
% -----------------------------------------------------------------------------
% At most one of the dependencies in an at-most-one-of-group should be satisfied

% REQUIRED_USE evaluation: check, don't search.
rule(at_most_one_of_group(Deps),[]) :-
  nb_current(query_required_use_self, _Self),
  findall(1, (member(D, Deps), rules:required_use_term_satisfied(D)), Ones),
  length(Ones, N),
  N =< 1,
  !.
rule(at_most_one_of_group(Deps),[assumed(conflict(required_use,at_most_one_of_group(Deps)))]) :-
  nb_current(query_required_use_self, _Self),
  !.

rule(at_most_one_of_group(Deps):Action?{Context},[D:Action?{Context}|NafDeps]) :-
  prioritize_deps(Deps, Context, SortedDeps),
  member(D0, SortedDeps),
  rules:group_choice_dep(D0, D),
  findall(naf(N),(member(N,Deps), \+(D = N)),NafDeps).

% Allow choosing none (all negated) — Portage REQUIRED_USE '?? ( ... )' does NOT
% require any of the flags to be enabled. Put this *after* the choice clause so
% we first try to satisfy already-enabled / preferred flags before negating all.
rule(at_most_one_of_group(Deps):_Action?{_Context}, NafDeps) :-
  findall(naf(N),(member(N,Deps)),NafDeps).

% Contextless variant: allow choosing none.
rule(at_most_one_of_group(Deps),[D|NafDeps]) :-
  prioritize_deps(Deps, SortedDeps),
  member(D, SortedDeps),
  findall(naf(N),(member(N,Deps), \+(D = N)),NafDeps).

% Contextless variant: allow choosing none (after attempting a choice).
rule(at_most_one_of_group(Deps), NafDeps) :-
  findall(naf(N),(member(N,Deps)),NafDeps).


% -----------------------------------------------------------------------------
%  Rule: Any of group
% -----------------------------------------------------------------------------
% One dependency of an any_of_group should be satisfied

% REQUIRED_USE evaluation: check, don't search.
rule(any_of_group(Deps),[]) :-
  nb_current(query_required_use_self, _Self),
  member(D, Deps),
  rules:required_use_term_satisfied(D),
  !.
rule(any_of_group(Deps),[assumed(conflict(required_use,any_of_group(Deps)))]) :-
  nb_current(query_required_use_self, _Self),
  !.

% When resolving dependency groups at Action time, group choices that are plain
% package_dependency/8 terms must be lifted into grouped_package_dependency/4,
% because the actual resolution logic lives in grouped_package_dependency rules.
rules:group_choice_dep(package_dependency(Phase,Strength,C,N,O,V,S,U),
                       grouped_package_dependency(Strength,C,N,
                           [package_dependency(Phase,Strength,C,N,O,V,S,U)])) :- !.
rules:group_choice_dep(D, D).

% During model construction (`config` phase), we must *prove* the chosen literal
% so it becomes part of the memoized model. Calling `rule/2` directly (as in the
% runtime clause below) does not record the chosen package_dependency/8 in the
% model, which makes || ( ... ) disappear from dependency models.
rule(any_of_group(Deps):config?{Context}, [D:config?{Context}]) :-
  rules:prioritize_deps_keep_all(Deps, Context, SortedDeps),
  member(D0, SortedDeps),
  rules:any_of_config_dep_ok(Context, D0),
  % In config phase we must prove the *package_dependency/8* term so it is
  % recorded in the model (AvlModel) and later extracted by query:model/2.
  D = D0,
  !.

rule(any_of_group(Deps):Action?{Context}, Conditions) :-
  rules:prioritize_deps_keep_all(Deps, Context, SortedDeps),
  member(D0, SortedDeps),
  rules:group_choice_dep(D0, D),
  rule(D:Action?{Context}, Conditions0),
  % IMPORTANT (Portage-like || semantics):
  % If a choice "succeeds" only by degrading into a domain assumption, treat it
  % as an unsatisfied option and try the next alternative.
  %
  % Example: || ( sys-devel/gcc[objc] llvm-core/clang )
  % If gcc[objc] cannot be satisfied under the effective USE configuration, we
  % must fall back to clang rather than assuming gcc.
  ( rules:any_of_reject_assumed_choice(D, Conditions0) ->
      fail
  ; Conditions = Conditions0
  ),
  !.

rule(any_of_group(Deps), Conditions) :-
  rules:prioritize_deps_keep_all(Deps, [], SortedDeps),
  member(D, SortedDeps),
  rule(D, Conditions),
  !.

% Reject any_of_group choices that are satisfied only by domain assumptions.
rules:any_of_reject_assumed_choice(grouped_package_dependency(_Strength, C, N, _PackageDeps),
                                   [assumed(grouped_package_dependency(C, N, _Deps):_Act?{_Ctx})]) :-
  !.

% Config-phase guard: avoid locking in an unsatisfiable bracketed-USE option as the
% chosen member of a || group, because that discards the other alternatives from
% the memoized dependency model.
%
% We still keep this reasonably narrow for performance, but we must avoid
% locking in an any-of branch that has no concrete candidate at all
% (e.g. virtual/perl-* branches with stale ~perl-core versions).
%
% IMPORTANT:
% During config phase, any_of members can be composite terms (all_of_group,
% use_conditional_group, nested any_of_group). Treating those as automatically
% satisfiable will lock unsatisfiable branches into the memoized model and drop
% valid alternatives. We must recurse and validate leaves.
rules:any_of_config_dep_ok(Context, all_of_group(Deps)) :-
  !,
  rules:any_of_config_deps_all_ok(Context, Deps).
rules:any_of_config_dep_ok(Context, any_of_group(Deps)) :-
  !,
  rules:any_of_config_deps_any_ok(Context, Deps).
rules:any_of_config_dep_ok(Context, use_conditional_group(Pol, Use, RepoEntry, Deps)) :-
  !,
  % Reuse established USE-conditional activation semantics from rule/2. If this
  % branch is inactive, it must not satisfy an enclosing any_of_group.
  rule(use_conditional_group(Pol, Use, RepoEntry, Deps):config?{Context}, Conditions),
  Conditions \== [],
  rules:any_of_config_conditions_all_ok(Context, Conditions).

rules:any_of_config_dep_ok(Context, package_dependency(Phase, _Strength, C, N, O, V, SlotReq, U)) :-
  % Test USE-dep satisfiability against concrete candidates that match the
  % dependency's own version/slot constraints. Using a single arbitrary
  % representative entry can produce false negatives and make model
  % construction fail at the root `entry(...:run)` literal.
  findall(Repo://Id,
          ( rules:accepted_keyword_candidate(Phase, C, N, SlotReq, _Ss, Context, Repo://Id),
            rules:query_search_version_select(O, V, Repo://Id)
          ),
          Candidates0),
  sort(Candidates0, Candidates),
  Candidates \== [],
  ( U == []
  -> true
  ; member(Candidate, Candidates),
    rules:candidate_satisfies_use_deps(Context, Candidate, U)
  ),
  !.
% If the USE-deps are not satisfiable, reject this option.
rules:any_of_config_dep_ok(_Context, package_dependency(_Phase, _Strength, _C, _N, _O, _V, _S, _U)) :-
  rules:assume_conflicts,
  !.
rules:any_of_config_dep_ok(_Context, package_dependency(_Phase, _Strength, _C, _N, _O, _V, _S, _U)) :-
  !,
  fail.
rules:any_of_config_dep_ok(_Context, _Other) :-
  true.

rules:any_of_config_deps_all_ok(_Context, []) :- !.
rules:any_of_config_deps_all_ok(Context, [Dep|Rest]) :-
  rules:any_of_config_dep_ok(Context, Dep),
  rules:any_of_config_deps_all_ok(Context, Rest).

rules:any_of_config_deps_any_ok(Context, Deps) :-
  member(Dep, Deps),
  rules:any_of_config_dep_ok(Context, Dep),
  !.

rules:any_of_config_conditions_all_ok(_Context, []) :- !.
rules:any_of_config_conditions_all_ok(Context, [Cond|Rest]) :-
  rules:any_of_config_condition_dep(Cond, Dep),
  rules:any_of_config_dep_ok(Context, Dep),
  rules:any_of_config_conditions_all_ok(Context, Rest).

rules:any_of_config_condition_dep(Dep:config?{_Ctx}, Dep) :- !.
rules:any_of_config_condition_dep(Dep, Dep).

% -----------------------------------------------------------------------------
%  REQUIRED_USE helpers
% -----------------------------------------------------------------------------
%
% These are used only while evaluating REQUIRED_USE (when query_required_use_self
% is set). They interpret the boolean grammar against the current ebuild's
% effective USE, without searching for alternative assignments.
%
rules:required_use_term_satisfied(required(Use)) :-
  \+ Use =.. [minus,_],
  rules:effective_use_in_context([], Use, positive),
  !.
rules:required_use_term_satisfied(required(minus(Use))) :-
  \+ Use =.. [minus,_],
  rules:effective_use_in_context([], Use, negative),
  !.
rules:required_use_term_satisfied(use_conditional_group(positive, Use, Self, Deps)) :-
  nb_current(query_required_use_self, Self),
  ( rules:effective_use_in_context([], Use, positive) ->
      forall(member(D, Deps), rules:required_use_term_satisfied(D))
  ; true
  ),
  !.
rules:required_use_term_satisfied(use_conditional_group(negative, Use, Self, Deps)) :-
  nb_current(query_required_use_self, Self),
  ( rules:effective_use_in_context([], Use, negative) ->
      forall(member(D, Deps), rules:required_use_term_satisfied(D))
  ; true
  ),
  !.
rules:required_use_term_satisfied(any_of_group(Deps)) :-
  member(D, Deps),
  rules:required_use_term_satisfied(D),
  !.
rules:required_use_term_satisfied(exactly_one_of_group(Deps)) :-
  findall(1, (member(D, Deps), rules:required_use_term_satisfied(D)), Ones),
  length(Ones, 1),
  !.
rules:required_use_term_satisfied(at_most_one_of_group(Deps)) :-
  findall(1, (member(D, Deps), rules:required_use_term_satisfied(D)), Ones),
  length(Ones, N),
  N =< 1,
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

% Context-aware REQUIRED_USE evaluation:
% When the "current ebuild" is available via self(...) in the context (passed
% from query:model(required_use(...))), treat requirements that are already
% satisfied by effective USE (IUSE defaults + profile/env/package.use) as
% non-assumptions. This prevents any_of_group/^^ groups from arbitrarily
% enabling the first alternative.
rule(required(Use):_?{Context},[]) :-
  \+Use =.. [minus,_],
  rules:effective_use_in_context(Context, Use, positive),
  !.
rule(required(minus(Use)):_?{Context},[]) :-
  \+Use =.. [minus,_],
  rules:effective_use_in_context(Context, Use, negative),
  !.

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

rule(conflict(A,B),[assumed(conflict(A,B))]) :-
  rules:assume_conflicts,
  !.
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
merge_slot_restriction_([package_dependency(_Phase,no,C,N,_O,_V,S,_U)|Rest], Action, C, N, Acc0, Acc) :-
  !,
  ( S == []      -> Acc1 = Acc0
  ; Acc0 == none -> Acc1 = S
  ; Acc0 == S    -> Acc1 = Acc0
  ; rules:merge_slot_restriction_pair(Acc0, S, Acc1) -> true
  ; fail
  ),
  merge_slot_restriction_(Rest, Action, C, N, Acc1, Acc).
merge_slot_restriction_([_|Rest], Action, C, N, Acc0, Acc) :-
  merge_slot_restriction_(Rest, Action, C, N, Acc0, Acc).

% Compatibility rule for merged grouped deps:
% treat :slot and :slot= as compatible, keeping the stricter :slot= restriction.
rules:merge_slot_restriction_pair([slot(S0)], [slot(S1),equal], [slot(S),equal]) :-
  rules:canon_slot(S0, S),
  rules:canon_slot(S1, S),
  !.
rules:merge_slot_restriction_pair([slot(S0),equal], [slot(S1)], [slot(S),equal]) :-
  rules:canon_slot(S0, S),
  rules:canon_slot(S1, S),
  !.
% Treat :slot and :slot/subslot (with or without '=') as compatible and keep
% the stricter subslot-qualified shape.
rules:merge_slot_restriction_pair([slot(S0)], [slot(S1),subslot(Ss0)], [slot(S),subslot(Ss)]) :-
  rules:canon_slot(S0, S),
  rules:canon_slot(S1, S),
  rules:canon_slot(Ss0, Ss),
  !.
rules:merge_slot_restriction_pair([slot(S0),subslot(Ss0)], [slot(S1)], [slot(S),subslot(Ss)]) :-
  rules:canon_slot(S0, S),
  rules:canon_slot(S1, S),
  rules:canon_slot(Ss0, Ss),
  !.
rules:merge_slot_restriction_pair([slot(S0)], [slot(S1),subslot(Ss0),equal], [slot(S),subslot(Ss),equal]) :-
  rules:canon_slot(S0, S),
  rules:canon_slot(S1, S),
  rules:canon_slot(Ss0, Ss),
  !.
rules:merge_slot_restriction_pair([slot(S0),subslot(Ss0),equal], [slot(S1)], [slot(S),subslot(Ss),equal]) :-
  rules:canon_slot(S0, S),
  rules:canon_slot(S1, S),
  rules:canon_slot(Ss0, Ss),
  !.
rules:merge_slot_restriction_pair([slot(S0),equal], [slot(S1),subslot(Ss0)], [slot(S),subslot(Ss),equal]) :-
  rules:canon_slot(S0, S),
  rules:canon_slot(S1, S),
  rules:canon_slot(Ss0, Ss),
  !.
rules:merge_slot_restriction_pair([slot(S0),subslot(Ss0)], [slot(S1),equal], [slot(S),subslot(Ss),equal]) :-
  rules:canon_slot(S0, S),
  rules:canon_slot(S1, S),
  rules:canon_slot(Ss0, Ss),
  !.
rules:merge_slot_restriction_pair([slot(S0),equal], [slot(S1),subslot(Ss0),equal], [slot(S),subslot(Ss),equal]) :-
  rules:canon_slot(S0, S),
  rules:canon_slot(S1, S),
  rules:canon_slot(Ss0, Ss),
  !.
rules:merge_slot_restriction_pair([slot(S0),subslot(Ss0),equal], [slot(S1),equal], [slot(S),subslot(Ss),equal]) :-
  rules:canon_slot(S0, S),
  rules:canon_slot(S1, S),
  rules:canon_slot(Ss0, Ss),
  !.

% -----------------------------------------------------------------------------
%  Helper: query_search_slot_constraint
% -----------------------------------------------------------------------------
% Execute a slot constraint query in a way that preserves compile-time query macro
% expansion (i.e. avoid passing a variable SlotReq into select(slot,constraint/2)).

query_search_slot_constraint(SlotReq, RepoEntry, SlotMeta) :-
  % IMPORTANT: keep the second argument of query:search/2 syntactically in the
  % form Repo://Id so goal-expansion does not bind a variable during compilation.
  RepoEntry = Repo://Id,
  ( SlotReq == [] ->
      query:search(select(slot,constraint([]),SlotMeta), Repo://Id)
  ; SlotReq = [slot(S0)] ->
      rules:canon_slot(S0, S),
      query:search(select(slot,constraint([slot(S)]),SlotMeta), Repo://Id)
  ; SlotReq = [slot(S0),subslot(Ss)] ->
      rules:canon_slot(S0, S),
      ( query:search(select(slot,constraint([slot(S),subslot(Ss)]),SlotMeta), Repo://Id)
      -> true
      ; % Some cache entries don't record subslot explicitly (it is effectively
        % the same as slot). Accept slot/subslot constraints in that case.
        rules:canon_slot(Ss, Ss1),
        Ss1 == S,
        \+ cache:entry_metadata(Repo, Id, subslot, _),
        query:search(select(slot,constraint([slot(S)]),_SlotMeta0), Repo://Id),
        SlotMeta = [slot(S),subslot(Ss1)]
      )
  ; SlotReq = [slot(S0),equal] ->
      rules:canon_slot(S0, S),
      query:search(select(slot,constraint([slot(S),equal]),SlotMeta), Repo://Id)
  ; SlotReq = [slot(S0),subslot(Ss),equal] ->
      rules:canon_slot(S0, S),
      ( query:search(select(slot,constraint([slot(S),subslot(Ss),equal]),SlotMeta), Repo://Id)
      -> true
      ; rules:canon_slot(Ss, Ss1),
        Ss1 == S,
        \+ cache:entry_metadata(Repo, Id, subslot, _),
        query:search(select(slot,constraint([slot(S)]),_SlotMeta0), Repo://Id),
        SlotMeta = [slot(S),subslot(Ss1),equal]
      )
  ; SlotReq = [any_same_slot] ->
      query:search(select(slot,constraint([any_same_slot]),SlotMeta0), Repo://Id),
      rules:canon_any_same_slot_meta(SlotMeta0, SlotMeta)
  ; SlotReq = [any_different_slot] ->
      query:search(select(slot,constraint([any_different_slot]),SlotMeta0), Repo://Id),
      SlotMeta = SlotMeta0
  ; % Fallback (should be rare; may be slower due to missing macro)
    query:search(select(slot,constraint(SlotReq),SlotMeta), Repo://Id)
  ).

% -----------------------------------------------------------------------------
%  Helper: installed_entry_satisfies_package_deps
% -----------------------------------------------------------------------------
% Check that an installed entry satisfies all version constraints expressed in
% the grouped package dependency list, while preserving query macro expansion.

installed_entry_satisfies_package_deps(_Action, _C, _N, [], _Installed) :- !.
installed_entry_satisfies_package_deps(Action, C, N,
                                       [package_dependency(_Phase,no,C,N,O,V,_,_)|Rest],
                                       Installed) :-
  !,
  rules:query_search_version_select(O, V, Installed),
  rules:installed_entry_satisfies_package_deps(Action, C, N, Rest, Installed).
installed_entry_satisfies_package_deps(Action, C, N, [_|Rest], Installed) :-
  rules:installed_entry_satisfies_package_deps(Action, C, N, Rest, Installed).

% Map runtime operator to a compile-time-friendly `select(version,<op>,...)` goal.
% Special-case wildcard equality (=...-5.42*). This pattern is very common in
% virtual/perl-* and similar versioned virtuals. Using `query:search/2` here can
% fail to benefit from wildcard handling when called from compiled code paths,
% so we match directly against the cached full version atom.
query_search_version_select(equal, Ver0, RepoEntry) :-
  RepoEntry = Repo://Id,
  rules:coerce_version_term(Ver0, Ver1),
  Ver1 = [_Nums,_A,_S,Pattern],
  atom(Pattern),
  sub_atom(Pattern, _, 1, 0, '*'),
  !,
  cache:ordered_entry(Repo, Id, _C, _N, [_Nums2,_A2,_S2,ProposedVersion]),
  wildcard_match(Pattern, ProposedVersion).
query_search_version_select(equal, Ver, RepoEntry) :- !,
  RepoEntry = Repo://Id,
  rules:coerce_version_term(Ver, Ver1),
  % Avoid `query:search/2` here: the compile-time macro historically treated all
  % 4-tuples as wildcard-equality candidates (see query.pl), which could make
  % exact equality constraints fail and degrade into domain assumptions.
  cache:ordered_entry(Repo, Id, _C, _N, Ver1).
query_search_version_select(none, _Ver, _RepoEntry) :- !.
query_search_version_select(smaller, Ver, RepoEntry) :- !,
  RepoEntry = Repo://Id,
  rules:coerce_version_term(Ver, Ver1),
  query:search(select(version,smaller,Ver1), Repo://Id).
query_search_version_select(greater, Ver, RepoEntry) :- !,
  RepoEntry = Repo://Id,
  rules:coerce_version_term(Ver, Ver1),
  query:search(select(version,greater,Ver1), Repo://Id).
query_search_version_select(smallerequal, Ver, RepoEntry) :- !,
  RepoEntry = Repo://Id,
  rules:coerce_version_term(Ver, Ver1),
  query:search(select(version,smallerequal,Ver1), Repo://Id).
query_search_version_select(greaterequal, Ver, RepoEntry) :- !,
  RepoEntry = Repo://Id,
  rules:coerce_version_term(Ver, Ver1),
  query:search(select(version,greaterequal,Ver1), Repo://Id).
query_search_version_select(notequal, Ver, RepoEntry) :- !,
  RepoEntry = Repo://Id,
  rules:coerce_version_term(Ver, Ver1),
  query:search(select(version,notequal,Ver1), Repo://Id).
query_search_version_select(wildcard, Ver, RepoEntry) :- !,
  RepoEntry = Repo://Id,
  rules:coerce_version_term(Ver, Ver1),
  query:search(select(version,wildcard,Ver1), Repo://Id).
query_search_version_select(tilde, Ver, RepoEntry) :- !,
  RepoEntry = Repo://Id,
  rules:coerce_version_term(Ver, Ver1),
  query:search(select(version,tilde,Ver1), Repo://Id).
query_search_version_select(Op, Ver, RepoEntry) :-
  % Fallback: keep semantics even if slower / not macro-expanded.
  RepoEntry = Repo://Id,
  rules:coerce_version_term(Ver, Ver1),
  query:search(select(version,Op,Ver1), Repo://Id).

% Coerce a version value into the canonical version term used in cache facts:
%   [NumberList, AlphaPartAtom, SuffixPartAtom, FullVersionAtom]
%
% Some dependency/mask paths historically passed only the FullVersion atom (e.g.
% 20250127.0). For non-equality comparators, the query engine expects the full
% structure so it can use eapi:version_compare/3.
rules:coerce_version_term(Ver0, Ver) :-
  var(Ver0),
  !,
  Ver = Ver0.
rules:coerce_version_term([_Nums,_A,_S,_Full]=Ver, Ver) :- !.
rules:coerce_version_term(Full, Ver) :-
  atom(Full),
  sub_atom(Full, _, 1, 0, '*'),
  !,
  % Wildcard equality pattern: represent as a 4-tuple so query.pl can apply
  % wildcard_match/2 to the Full string.
  Ver = [[], '', '', Full].
rules:coerce_version_term(Full, [Nums, '', '', Full]) :-
  atom(Full),
  % Parse numeric dotted versions (common in profiles/deps like 20250127.0).
  eapi:version2numberlist(Full, Nums),
  Nums \== [],
  !.
rules:coerce_version_term(Num, Ver) :-
  number(Num),
  % Some dependency atoms are stored as numbers (e.g. 20250127.0). Normalize by
  % converting back to an atom so we can parse dotted components consistently.
  number_string(Num, S),
  atom_string(Full, S),
  !,
  rules:coerce_version_term(Full, Ver).
rules:coerce_version_term(Other, Other).


% =============================================================================
%  Ruleset: Dependency group helpers
% =============================================================================

% -----------------------------------------------------------------------------
%  Helper: prioritize_deps
% -----------------------------------------------------------------------------
% Sorts dependencies by prioritizing those that match user preferences, to
% reduce the number of assumptions in the proof.

prioritize_deps(Deps, SortedDeps) :-
  prioritize_deps(Deps, [], SortedDeps).

prioritize_deps(Deps, Context, SortedDeps) :-
  predsort(rules:compare_dep_rank(Context), Deps, SortedDeps).

% Like prioritize_deps/3, but preserves alternatives with identical rank.
% predsort/3 can drop equal-ranked members (comparator returns (=)); this is
% undesirable for disjunctions where all alternatives must remain available.
%
% Sort key: NegLicOk > NegRank > NegOverlap > NegSnap > I (original order).
%   - NegLicOk: license-masked candidates sort last so non-masked alternatives
%     are tried first (mirrors Portage ACCEPT_LICENSE filtering in || groups).
%   - NegOverlap: Portage-like DNF optimisation — prefer packages that appear
%     in multiple active || groups within the same ebuild, so that a single
%     package can satisfy several groups at once (see bug #632026).
rules:prioritize_deps_keep_all(Deps, Context, SortedDeps) :-
  findall(NegLicOk-NegRank-NegOverlap-NegSnap-I-Dep,
          ( nth1(I, Deps, Dep),
            rules:dep_rank(Context, Dep, Rank),
            rules:dep_overlap_group_count(Context, Dep, OvRaw),
            ( OvRaw > 1 -> Overlap = OvRaw ; Overlap = 0 ),
            ( rules:dep_snapshot_selected(Dep) -> Snap = 1 ; Snap = 0 ),
            ( rules:dep_license_ok(Dep) -> LicOk = 1 ; LicOk = 0 ),
            NegLicOk is -LicOk,
            NegRank is -Rank,
            NegOverlap is -Overlap,
            NegSnap is -Snap
          ),
          Ranked),
  keysort(Ranked, RankedSorted),
  findall(Dep, member(_-_-_-_-_-Dep, RankedSorted), SortedDeps),
  !.

rules:dep_snapshot_selected(package_dependency(_Phase,_Strength,C,N,_O,_V,_S,_U)) :-
  rules:snapshot_selected_cn_candidates(C, N, _),
  !.
rules:dep_snapshot_selected(_) :- fail.

% ---------------------------------------------------------------------------
%  Overlap-group count (Portage DNF approximation)
% ---------------------------------------------------------------------------
% Count how many *active* any_of_group entries in the same ebuild contain a
% package with the given Category/Name. A count > 1 means the package is a
% "common satisfier" — picking it reduces the total number of new packages.

rules:dep_overlap_group_count(Context, package_dependency(_,_,C,N,_,_,_,_), Count) :-
  memberchk(self(Repo://Ebuild), Context),
  !,
  aggregate_all(count, (
    member(DepKey, [rdepend, depend, bdepend, pdepend, cdepend, idepend]),
    cache:entry_metadata(Repo, Ebuild, DepKey, DepEntry),
    rules:dep_entry_active_any_of_with_cn(DepEntry, Repo://Ebuild, C, N)
  ), Count).
rules:dep_overlap_group_count(_, _, 0).

rules:dep_entry_active_any_of_with_cn(any_of_group(Deps), _, C, N) :-
  member(package_dependency(_, _, C, N, _, _, _, _), Deps), !.
rules:dep_entry_active_any_of_with_cn(use_conditional_group(Pol, Use, RepoEntry, Deps), _, C, N) :-
  rules:rdepend_self_use_conditional_active(Pol, Use, RepoEntry),
  member(D, Deps),
  rules:dep_entry_active_any_of_with_cn(D, RepoEntry, C, N), !.
rules:dep_entry_active_any_of_with_cn(all_of_group(Deps), RepoEntry, C, N) :-
  member(D, Deps),
  rules:dep_entry_active_any_of_with_cn(D, RepoEntry, C, N), !.

% Rank dependencies for deterministic group choice.
% Primary signal: prefer deps that are already satisfied by effective USE /
% preferences / installed packages.
% Secondary signal: for selector-style flags, choose highest version/slot.
rules:compare_dep_rank(Context, Delta, A, B) :-
  rules:dep_rank(Context, A, Ra),
  rules:dep_rank(Context, B, Rb),
  compare(C, Rb, Ra), % descending
  ( C == (<) -> Delta = (<)
  ; C == (>) -> Delta = (>)
  ; Delta = (=)
  ).

rules:dep_rank(Context, Dep, Rank) :-
  % Specialized ranking for package_dependency/8 is defined below; avoid
  % accidentally taking this generic clause first (which would ignore the extra
  % signals like self-avoidance and installed mismatch penalties).
  Dep \= package_dependency(_,_,_,_,_,_,_,_),
  ( is_preferred_dep(Context, Dep) -> Pref = 1 ; Pref = 0 ),
  rules:dep_intrinsic_rank(Dep, Base),
  Rank is Pref*1000000000 + Base,
  !.

% De-prioritize dependencies that resolve to the current ebuild's own CN.
% This matters for BDEPEND like:
%   || ( >=dev-lang/go-... >=dev-lang/go-bootstrap-... )
% where choosing `dev-lang/go` would force bootstrapping from itself.
rules:dep_rank(Context, package_dependency(Phase,Strength,C,N,O,V,S,U), Rank) :-
  ( rules:self_cn(Context, C, N) -> Base0 = -100000000 ; Base0 = 0 ),
  rules:installed_version_mismatch_penalty(package_dependency(Phase,Strength,C,N,O,V,S,U), BaseInst),
  ( is_preferred_dep(Context, package_dependency(Phase,Strength,C,N,O,V,S,U)) -> Pref = 1 ; Pref = 0 ),
  rules:dep_intrinsic_rank(package_dependency(Phase,Strength,C,N,O,V,S,U), Base1),
  Rank is Pref*1000000000 + Base0 + BaseInst + Base1,
  !.

rules:self_cn(Context, C, N) :-
  memberchk(self(Repo://Id), Context),
  query:search([category(C),name(N)], Repo://Id),
  !.

rules:dep_intrinsic_rank(required(Use), Rank) :-
  rules:use_rank(Use, Rank),
  !.
rules:dep_intrinsic_rank(required(minus(Use)), Rank) :-
  rules:use_rank(Use, Rank),
  !.
rules:dep_intrinsic_rank(package_dependency(_Phase,_Strength,_C,N,_O,_V,_S,_U), Rank) :-
  % Prefer bootstrap providers (e.g. go-bootstrap) over non-bootstrap alternatives.
  ( atom_concat(_, '-bootstrap', N) -> Rank = 50000
  ; Rank = 0
  ),
  !.
rules:dep_intrinsic_rank(_, 0).

rules:use_rank(Use, Rank) :-
  atom(Use),
  ( rules:llvm_slot_rank(Use, Rank)
  ; rules:lua_single_target_rank(Use, Rank)
  ),
  !.
rules:use_rank(_, 0).

rules:llvm_slot_rank(Use, Rank) :-
  atom_concat('llvm_slot_', Suffix, Use),
  catch(atom_number(Suffix, N), _, fail),
  Rank is 100000 + N.

rules:lua_single_target_rank(Use, Rank) :-
  % lua-single flags show up as e.g. lua_single_target_lua5-4
  atom_concat('lua_single_target_lua5-', Suffix, Use),
  catch(atom_number(Suffix, N), _, fail),
  Rank is 90000 + N.

% Prefer use-conditional branches that are already active under the current
% effective USE of the referenced ebuild.
%
% This is crucial for patterns like:
%   || ( pyqt6? ( ... ) pyside6? ( ... ) )
% where Portage will naturally follow the currently-enabled branch; exploring the
% disabled branch first leads to a large amount of pointless search.
is_preferred_dep(_Context, use_conditional_group(positive, Use, RepoEntry, _Deps)) :-
  \+ Use =.. [minus,_],
  ( RepoEntry = _Repo://_Id ; RepoEntry = _Repo//_Id ),
  rules:effective_use_for_entry(RepoEntry, Use, positive),
  !.
is_preferred_dep(_Context, use_conditional_group(negative, Use, RepoEntry, _Deps)) :-
  \+ Use =.. [minus,_],
  ( RepoEntry = _Repo://_Id ; RepoEntry = _Repo//_Id ),
  rules:effective_use_for_entry(RepoEntry, Use, negative),
  !.

is_preferred_dep(Context, required(Use)) :-
  Use \= minus(_),
  ( preference:use(Use)
  ; rules:effective_use_in_context(Context, Use, positive)
  ),
  !.
is_preferred_dep(Context, required(minus(Use))) :-
  ( preference:use(minus(Use))
  ; rules:effective_use_in_context(Context, Use, negative)
  ),
  !.

% Prefer any-of alternatives that are already satisfied by installed packages.
%
% Portage-like note:
% Portage's dep_zapdeps ignores bracketed USE deps while ranking || alternatives.
% Do not promote a branch solely because pkg[flag] happens to match global USE.
% Keep preference signal limited to "already satisfied" style checks.
is_preferred_dep(Context, all_of_group(Deps)) :-
  Deps \= [],
  forall(member(D, Deps), rules:group_member_preferred(Context, D)),
  !.

% Prefer any-of alternatives that are already installed.
% This helps align Portage-like behavior for || groups that include a heavy
% build-time tool (e.g. dev-lang/vala) versus a lighter already-installed
% alternative (e.g. gobject-introspection).
is_preferred_dep(_Context, package_dependency(_Phase,_Strength,C,N,O,V,_S,_U)) :-
  query:search([name(N),category(C),installed(true)], pkg://Installed),
  ( O == none ; rules:query_search_version_select(O, V, pkg://Installed) ),
  !.

% -----------------------------------------------------------------------------
%  any_of_group preference helpers (installed satisfaction)
% -----------------------------------------------------------------------------

% Recursively decide whether a group member is satisfied by the current system.
rules:group_member_preferred(Context, package_dependency(Phase,Strength,C,N,O,V,S,U)) :-
  rules:installed_pkg_satisfies_dep(Context, package_dependency(Phase,Strength,C,N,O,V,S,U)),
  !.
rules:group_member_preferred(Context, use_conditional_group(positive, Use, RepoEntry, Deps)) :-
  is_preferred_dep(Context, use_conditional_group(positive, Use, RepoEntry, Deps)),
  !.
rules:group_member_preferred(Context, use_conditional_group(negative, Use, RepoEntry, Deps)) :-
  is_preferred_dep(Context, use_conditional_group(negative, Use, RepoEntry, Deps)),
  !.
rules:group_member_preferred(Context, all_of_group(Deps)) :-
  Deps \= [],
  forall(member(D, Deps), rules:group_member_preferred(Context, D)),
  !.
rules:group_member_preferred(_Context, _Other) :-
  % Unknown/complex members (any_of_group, blockers, ...) are not treated as
  % "already satisfied" for preference ranking.
  fail.

rules:installed_pkg_satisfies_dep(ParentContext,
                                 package_dependency(_Phase,_Strength,C,N,O,V,_S,UseReqs)) :-
  query:search([name(N),category(C),installed(true)], pkg://InstalledId),
  ( O == none
  ; rules:query_search_version_select(O, V, pkg://InstalledId)
  ),
  rules:installed_pkg_satisfies_use_reqs(ParentContext, pkg://InstalledId, UseReqs),
  !.

rules:installed_pkg_satisfies_use_reqs(_ParentContext, _Installed, []) :- !.
rules:installed_pkg_satisfies_use_reqs(ParentContext, pkg://InstalledId,
                                      [use(Directive, Default)|Rest]) :-
  !,
  rules:use_dep_requirement(ParentContext, Directive, Default, Req),
  rules:installed_pkg_satisfies_use_requirement(pkg://InstalledId, Req),
  rules:installed_pkg_satisfies_use_reqs(ParentContext, pkg://InstalledId, Rest).
rules:installed_pkg_satisfies_use_reqs(ParentContext, Installed, [_|Rest]) :-
  rules:installed_pkg_satisfies_use_reqs(ParentContext, Installed, Rest).

rules:installed_pkg_satisfies_use_requirement(_Installed, none) :- !.
rules:installed_pkg_satisfies_use_requirement(pkg://InstalledId, requirement(enable, Use, _Default)) :-
  query:search(use(Use), pkg://InstalledId),
  !.
rules:installed_pkg_satisfies_use_requirement(pkg://InstalledId, requirement(disable, Use, _Default)) :-
  \+ query:search(use(Use), pkg://InstalledId),
  !.

% Penalize deps that would force changing an already-installed C/N due to a
% version constraint mismatch.
%
% This is used for stable, deterministic selection in `|| ( ... )` groups.
% Example:
%   || ( =dev-lang/perl-5.40* ~perl-core/Foo-1.2.3 )
% If perl is installed but not 5.40.*, prefer the perl-core branch to avoid a
% downgrade/upgrade chain.
rules:installed_version_mismatch_penalty(package_dependency(_Phase,_Strength,C,N,O,V,_S,_U), Penalty) :-
  O \== none,
  % At least one installed instance exists...
  query:search([name(N),category(C),installed(true)], pkg://_),
  % ...but none satisfy the requested version operator.
  \+ ( query:search([name(N),category(C),installed(true)], pkg://InstalledId),
       rules:query_search_version_select(O, V, pkg://InstalledId)
     ),
  Penalty is -50000000,
  !.
rules:installed_version_mismatch_penalty(_Dep, 0).

% Effective USE for the current ebuild (when we have `self(...)` in Context).
% Helps REQUIRED_USE group choice: prefer alternatives already satisfied by the
% current effective USE (profile/env/package.use), rather than forcing new flags.
rules:effective_use_in_context(Context, Use, State) :-
  ( memberchk(self(RepoEntry0), Context) ->
      ( RepoEntry0 = Repo://Id -> true
      ; RepoEntry0 = Repo//Id  -> true
      )
  ; nb_current(query_required_use_self, Repo://Id)
  ),
  % Fast-path: avoid scanning all iuse/1 facts each time.
  % Most conditionals only need the boolean state of a single flag, and whole-tree
  % proofs hit this path millions of times (notably in gstreamer/llvm stacks).
  \+ Use =.. [minus,_],
  rules:entry_iuse_default(Repo://Id, Use, Default),
  cache:ordered_entry(Repo, Id, C, N, _),
  ( % Profile-enforced per-package constraints (package.use.mask/force) win over
    % /etc/portage/package.use and global USE.
    preference:profile_package_use_override_for_entry(Repo://Id, Use, Eff, _Reason0) ->
      true
  ; preference:package_use_override(C, N, Use, positive) ->
      Eff = positive
  ; preference:package_use_override(C, N, Use, negative) ->
      Eff = negative
  ; preference:gentoo_package_use_override_for_entry_soft(Repo://Id, Use, Eff0) ->
      Eff = Eff0
  ; preference:profile_package_use_override_for_entry_soft(Repo://Id, Use, Eff0) ->
      Eff = Eff0
  ; preference:use(Use) ->
      Eff = positive
  ; preference:use(minus(Use)) ->
      Eff = negative
  ; Eff = Default
  ),
  Eff = State,
  !.

% Effective USE state for a specific entry.
% This is the same logic as effective_use_in_context/3, but without the overhead
% of extracting `self(...)` from a Context.
rules:effective_use_for_entry(RepoEntry0, Use, State) :-
  ( RepoEntry0 = Repo://Id -> true
  ; RepoEntry0 = Repo//Id  -> true
  ),
  \+ Use =.. [minus,_],
  rules:entry_iuse_default(Repo://Id, Use, Default),
  cache:ordered_entry(Repo, Id, C, N, _),
  ( % Profile-enforced per-package constraints (package.use.mask/force) win over
    % /etc/portage/package.use and global USE.
    preference:profile_package_use_override_for_entry(Repo://Id, Use, Eff, _Reason0) ->
      true
  ; preference:package_use_override(C, N, Use, positive) ->
      Eff = positive
  ; preference:package_use_override(C, N, Use, negative) ->
      Eff = negative
  ; preference:gentoo_package_use_override_for_entry_soft(Repo://Id, Use, Eff0) ->
      Eff = Eff0
  ; preference:profile_package_use_override_for_entry_soft(Repo://Id, Use, Eff0) ->
      Eff = Eff0
  ; preference:use(Use) ->
      Eff = positive
  ; preference:use(minus(Use)) ->
      Eff = negative
  ; Eff = Default
  ),
  Eff = State,
  !.

% -----------------------------------------------------------------------------
%  Per-entry IUSE default map (performance)
% -----------------------------------------------------------------------------
%
% Many packages have very large IUSE sets (notably llvm-core/* with llvm_targets_*).
% Resolving USE conditionals for such packages is hot and must avoid O(n) scans.
%
% We memoize, per (Repo,Entry), an assoc mapping Use -> DefaultState (positive if
% +flag, otherwise negative). Lookup is O(log n).

rules:entry_iuse_default(Repo://Entry, Use, Default) :-
  ( nb_current(rules_entry_iuse_default_cache, Cache),
    get_assoc(key(Repo,Entry), Cache, Map)
  ->
    get_assoc(Use, Map, Default),
    !
  ;
    findall(Raw, query:search(iuse(Raw), Repo://Entry), RawIuse0),
    sort(RawIuse0, RawIuse),
    findall(U-Def,
            ( member(Raw, RawIuse),
              ( Raw = plus(U)  -> Def = positive
              ; Raw = minus(U) -> Def = negative
              ; eapi:strip_use_default(Raw, U),
                Def = negative
              )
            ),
            Pairs0),
    sort(Pairs0, Pairs),
    rules:iuse_default_pairs_to_assoc(Pairs, Map),
    ( nb_current(rules_entry_iuse_default_cache, Cache0) -> true ; empty_assoc(Cache0) ),
    put_assoc(key(Repo,Entry), Cache0, Map, Cache1),
    nb_setval(rules_entry_iuse_default_cache, Cache1),
    get_assoc(Use, Map, Default),
    !
  ).

% Build a Use->Default assoc from possibly-duplicated pairs.
% If the same flag appears multiple times, prefer `positive` over `negative`.
rules:iuse_default_pairs_to_assoc(Pairs, Map) :-
  empty_assoc(M0),
  rules:iuse_default_pairs_to_assoc_(Pairs, M0, Map).

rules:iuse_default_pairs_to_assoc_([], M, M) :- !.
rules:iuse_default_pairs_to_assoc_([U-Def|Rest], M0, M) :-
  ( get_assoc(U, M0, Existing) ->
      ( Existing == positive -> M1 = M0
      ; Def == positive -> put_assoc(U, M0, positive, M1)
      ; M1 = M0
      )
  ; put_assoc(U, M0, Def, M1)
  ),
  rules:iuse_default_pairs_to_assoc_(Rest, M1, M).

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
      rules:ctx_set_self(Ctx, Self, Ctx1),
      D = Term:Action?{Ctx1}
  ; D = D0
  ),
  add_self_to_dep_contexts(Self, Rest0, Rest).

% Keep at most ONE self/1 term in contexts.
% This preserves the semantics needed for self-dependency guards while preventing
% context growth (and memoization misses) along deep dependency chains.
rules:ctx_set_self(Ctx0, Self, Ctx) :-
  ( is_list(Ctx0) ->
      findall(X, (member(X, Ctx0), \+ X = self(_)), Ctx1),
      Ctx = [self(Self)|Ctx1]
  ; Ctx = [self(Self)]
  ),
  !.

% -----------------------------------------------------------------------------
%  Debugging: profile an entry rule step-by-step
% -----------------------------------------------------------------------------
%
% This is meant for answering: "where do those 300s go?" on a single package.
% It times the major sub-steps of the `:run` rule without needing full tracing.
%
% Usage example:
%   ?- rules:profile_run_entry(portage://'dev-python/qtpy-2.4.3-r1', [], Report),
%      writeln(Report).
%
rules:profile_run_entry(RepoEntry, Context, report(RepoEntry, Steps)) :-
  rules:step_time(mask_check,
                  ( query:search(masked(true), RepoEntry) -> true ; true ),
                  S1),
  rules:step_time(required_use_model,
                  ( findall(Item,(member(build_with_use:Inner, Context), member(Item,Inner)), B),
                    ( memberchk(required_use:R, Context) -> true ; true ),
                    query:search(model(_Model,required_use(R),build_with_use(B)), RepoEntry)
                  ),
                  S2),
  rules:step_time(dep_model_run_config,
                  ( query:memoized_search(model(dependency(_MergedDeps0,run)):config?{[]}, RepoEntry) ),
                  S3),
  Steps = [S1,S2,S3].

rules:step_time(Label, Goal, step(Label, ms(TimeMs), inferences(Inf), result(Result))) :-
  statistics(walltime, [T0,_]),
  statistics(inferences, I0),
  ( catch(call_with_time_limit(10, (Goal -> Result = ok ; Result = fail)),
          time_limit_exceeded,
          Result = timeout)
  ),
  statistics(walltime, [T1,_]),
  statistics(inferences, I1),
  TimeMs is T1 - T0,
  Inf is I1 - I0.

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
% This applies to all explicit-slot forms, including :slot, :slot= and
% :slot/subslot[=].
process_slot([slot(_)|_], _SlotMeta, _C, _N, _Repository://_Candidate, Context, Context) :- !.
process_slot(_, Slot, C, N, _Repository://Candidate, Context0, Context) :-
  feature_unification:unify([slot(C, N, Slot):{Candidate}], Context0, Context).

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
%
% IMPORTANT (performance + termination):
% Do not keep stacking `build_with_use/1` terms into Context.
% In the presence of dependency cycles, that makes the goal context grow on each
% recursive visit, which can defeat cycle detection/memoization and lead to
% effectively-infinite backtracking until timeout.
%
% Instead, keep at most ONE `build_with_use/1` term in the context and merge
% new directives into it.
process_build_with_use(Directives, Context0, Context, Conditions, Candidate) :-
    % IMPORTANT (correctness):
    % `build_with_use` is *per-package* USE state/constraints. When we descend from a
    % parent package into a dependency, the child's build_with_use must NOT inherit
    % the parent's build_with_use. Otherwise the parent's USE state (e.g. gui/widgets,
    % abi_x86_*) incorrectly becomes a constraint on the dependency, which triggers
    % Portage-divergent rebuilds (same-version "updates") and inflates plans.
    %
    % So: remove any build_with_use term from the incoming (parent) context and
    % seed the child state from empty, then apply only the directives for *this*
    % dependency edge.
    ( select(build_with_use:_, Context0, Context1) -> true ; Context1 = Context0 ),
    rules:empty_use_state(PrevState),
    foldl(rules:process_bwu_directive(Context0), Directives, PrevState, State0),
    rules:normalize_build_with_use(State0, State),
    ( State = use_state([], []) ->
        Context = Context1
    ; feature_unification:unify([build_with_use:State], Context1, Context)
    ),
    build_with_use_constraints(Directives, Conditions, Candidate).

% Monotone per-package USE state:
% - use_state(Enabled, Disabled) where both are ordsets of flag atoms (no minus/1 wrapper)
rules:empty_use_state(use_state([],[])).

rules:normalize_build_with_use(use_state(En0, Dis0), use_state(En, Dis)) :-
  !,
  sort(En0, En),
  sort(Dis0, Dis).
rules:normalize_build_with_use(BWU0, use_state(En, Dis)) :-
  is_list(BWU0),
  !,
  rules:build_with_use_requirements(BWU0, En, Dis).
rules:normalize_build_with_use(_Other, use_state([],[])) :-
  % Be conservative for unexpected shapes.
  !.

rules:context_build_with_use_state(Context, State) :-
  ( memberchk(build_with_use:BWU, Context) ->
      rules:normalize_build_with_use(BWU, State)
  ; rules:empty_use_state(State)
  ),
  !.

rules:process_bwu_directive(ParentContext, use(Directive, Default), use_state(En0, Dis0), use_state(En, Dis)) :-
  !,
  rules:use_dep_requirement(ParentContext, Directive, Default, Requirement),
  ( Requirement = requirement(enable, Use, _D) ->
      % Conflict: both enabled and disabled.
      \+ memberchk(Use, Dis0),
      sort([Use|En0], En),
      Dis = Dis0
  ; Requirement = requirement(disable, Use, _D) ->
      \+ memberchk(Use, En0),
      sort([Use|Dis0], Dis),
      En = En0
  ; % none / unhandled
    En = En0,
    Dis = Dis0
  ).
rules:process_bwu_directive(_ParentContext, _Other, State, State) :- !.

% Helper predicate to generate build_with_use constraints
% Collects all USE requirements into a single list to avoid data duplication
%
% NOTE:
% Portage-style USE dependencies like `[foo]` or `[foo(+)]` are constraints on the
% *child package's* USE state, not on the global profile/make.conf USE.
%
% At the moment, `portage-ng` models these by pushing `assumed(foo)` /
% `naf(required(foo))` into the dependency context (see `process_use/4`) so that
% downstream `use_conditional_group/4` can resolve correctly.
%
% Emitting global `constraint(use(Candidate))` entries here incorrectly ties these
% requirements to `preference:use/1` (global USE), which causes false
% "unsatisfiable dependency" errors (e.g. xdg-utils -> xmlto[text(+)]), even when
% the child package has that flag enabled by default.
%
% Until we implement per-package USE evaluation, we keep these as context only.
build_with_use_constraints(_, [], _) :- !.

% -----------------------------------------------------------------------------
%  Candidate USE-dependency enforcement (deps like pkg[foo], pkg[foo?], pkg[foo(+)])
% -----------------------------------------------------------------------------
%
% The dependency atom USE-dependencies apply to the *child package* USE state,
% not the global USE. We therefore verify that the chosen candidate's effective
% USE satisfies these constraints.

rules:candidate_satisfies_use_deps(_ParentContext, _Repo://_Entry, []) :- !.
rules:candidate_satisfies_use_deps(ParentContext, Repo://Entry, [use(Directive, Default)|Rest]) :-
  rules:use_dep_requirement(ParentContext, Directive, Default, Requirement),
  rules:candidate_satisfies_use_requirement_opt(Directive, Repo://Entry, Requirement),
  rules:candidate_satisfies_use_deps(ParentContext, Repo://Entry, Rest).

% For optenable/optdisable (EAPI [flag?]/[!flag?] syntax), when the target
% package does not have the flag in IUSE, the constraint is irrelevant —
% the package simply does not support that flag. Portage does not reject
% candidates on this basis. Only enforce when the flag is actually in IUSE.
rules:candidate_satisfies_use_requirement_opt(optenable(Use), Repo://Entry, Requirement) :-
  !,
  ( rules:candidate_iuse_present(Repo://Entry, Use) ->
      rules:candidate_satisfies_use_requirement(Repo://Entry, Requirement)
  ; true
  ).
rules:candidate_satisfies_use_requirement_opt(optdisable(Use), Repo://Entry, Requirement) :-
  !,
  ( rules:candidate_iuse_present(Repo://Entry, Use) ->
      rules:candidate_satisfies_use_requirement(Repo://Entry, Requirement)
  ; true
  ).
rules:candidate_satisfies_use_requirement_opt(_, Repo://Entry, Requirement) :-
  rules:candidate_satisfies_use_requirement(Repo://Entry, Requirement).

% -----------------------------------------------------------------------------
%  Context helpers for per-package USE (build_with_use)
% -----------------------------------------------------------------------------
%
% We represent per-package USE requirements in the context as:
%   build_with_use:[ ... assumed(foo) ... assumed(minus(bar)) ... ]
%
% Some older code paths also used top-level assumed/1 terms. Support both.
rules:ctx_assumed(Ctx, Use) :-
  memberchk(assumed(Use), Ctx),
  !.
rules:ctx_assumed(Ctx, Use) :-
  memberchk(build_with_use:BU, Ctx),
  BU = use_state(En, _Dis),
  memberchk(Use, En),
  !.
rules:ctx_assumed(Ctx, Use) :-
  memberchk(build_with_use:BU, Ctx),
  is_list(BU),
  memberchk(assumed(Use), BU),
  !.

rules:ctx_assumed_minus(Ctx, Use) :-
  memberchk(assumed(minus(Use)), Ctx),
  !.
rules:ctx_assumed_minus(Ctx, Use) :-
  memberchk(build_with_use:BU, Ctx),
  BU = use_state(_En, Dis),
  memberchk(Use, Dis),
  !.
rules:ctx_assumed_minus(Ctx, Use) :-
  memberchk(build_with_use:BU, Ctx),
  is_list(BU),
  memberchk(assumed(minus(Use)), BU),
  !.

% Derive USE state from the concrete parent package in context.
% Only succeeds for flags that are present in the parent's IUSE.
rules:self_context_use_state(Ctx, Use, State) :-
  memberchk(self(RepoEntry0), Ctx),
  ( RepoEntry0 = Repo://Id -> true
  ; RepoEntry0 = Repo//Id  -> true
  ),
  rules:entry_iuse_info(Repo://Id, iuse_info(IuseSet, _PlusSet)),
  memberchk(Use, IuseSet),
  ( % Effective state must honor profile/package overrides.
    % query:search(use/1) reads raw enabled flags only and can diverge.
    \+ eapi:check_use_expand_atom(Use),
    query:search(iuse_filtered(Use, State:_), Repo://Id)
  ; eapi:use_expand(Prefix),
    eapi:check_prefix_atom(Prefix, Use),
    eapi:strip_prefix_atom(Prefix, Use, Value),
    Q =.. [Prefix, Value, State:_],
    query:search(Q, Repo://Id)
  ),
  !.

% Determine whether a USE-dependency imposes a concrete requirement.
rules:use_dep_requirement(_Ctx, enable(Use), Default, requirement(enable, Use, Default)) :- !.
rules:use_dep_requirement(_Ctx, disable(Use), Default, requirement(disable, Use, Default)) :- !.

% [foo=] / [!foo=] depend on parent foo state; if unknown, fall back to default.
rules:use_dep_requirement(Ctx, equal(Use), Default, requirement(enable, Use, Default)) :-
  rules:ctx_assumed(Ctx, Use), !.
rules:use_dep_requirement(Ctx, equal(Use), Default, requirement(disable, Use, Default)) :-
  rules:ctx_assumed_minus(Ctx, Use), !.
rules:use_dep_requirement(Ctx, equal(Use), Default, requirement(enable, Use, Default)) :-
  rules:effective_use_in_context(Ctx, Use, positive), !.
rules:use_dep_requirement(Ctx, equal(Use), Default, requirement(disable, Use, Default)) :-
  rules:effective_use_in_context(Ctx, Use, negative), !.
rules:use_dep_requirement(_Ctx, equal(Use), Default, Requirement) :-
  % Parent state unknown (typically because Use is not in parent's IUSE).
  % EAPI 8: only (+)/(-) defaults impose a requirement; no default means no constraint.
  ( Default == positive -> Requirement = requirement(enable, Use, Default)
  ; Default == negative -> Requirement = requirement(disable, Use, Default)
  ; Requirement = none
  ),
  !.

rules:use_dep_requirement(Ctx, inverse(Use), Default, requirement(disable, Use, Default)) :-
  rules:ctx_assumed(Ctx, Use), !.
rules:use_dep_requirement(Ctx, inverse(Use), Default, requirement(enable, Use, Default)) :-
  rules:ctx_assumed_minus(Ctx, Use), !.
rules:use_dep_requirement(Ctx, inverse(Use), Default, requirement(disable, Use, Default)) :-
  rules:effective_use_in_context(Ctx, Use, positive), !.
rules:use_dep_requirement(Ctx, inverse(Use), Default, requirement(enable, Use, Default)) :-
  rules:effective_use_in_context(Ctx, Use, negative), !.
rules:use_dep_requirement(_Ctx, inverse(Use), Default, Requirement) :-
  % Parent state unknown, use default and invert.
  ( Default == positive -> Requirement = requirement(disable, Use, Default)
  ; Default == negative -> Requirement = requirement(enable, Use, Default)
  ; Requirement = none
  ),
  !.

% [foo?] / [!foo?] only constrain the child if the *parent* has a known state.
%
% IMPORTANT:
% Do NOT blindly fall back to global `preference:use/1` here. The meaning is:
%   "if the parent has foo enabled/disabled"
% not:
%   "if foo is enabled globally".
%
% Falling back to global USE causes massive, incorrect constraint propagation for
% USE_EXPAND flags (notably python_targets_*), leading to widespread
% unsatisfied_constraints and timeouts.
%
rules:use_dep_requirement(Ctx, optenable(Use), Default, requirement(enable, Use, Default)) :-
  ( rules:ctx_assumed(Ctx, Use)
  ; rules:self_context_use_state(Ctx, Use, positive)
  ; \+ memberchk(self(_), Ctx),
    rules:effective_use_in_context(Ctx, Use, positive)
  ),
  !.
rules:use_dep_requirement(_Ctx, optenable(_Use), _Default, none) :- !.

rules:use_dep_requirement(Ctx, optdisable(Use), Default, requirement(disable, Use, Default)) :-
  ( rules:ctx_assumed_minus(Ctx, Use)
  ; rules:self_context_use_state(Ctx, Use, negative)
  ; \+ memberchk(self(_), Ctx),
    rules:effective_use_in_context(Ctx, Use, negative)
  ),
  !.
rules:use_dep_requirement(_Ctx, optdisable(_Use), _Default, none) :- !.

% Anything else we currently ignore.
rules:use_dep_requirement(_Ctx, _Directive, _Default, none).

rules:candidate_satisfies_use_requirement(_Repo://_Entry, none) :- !.
rules:candidate_satisfies_use_requirement(Repo://Entry, requirement(Mode, Use, Default)) :-
  % Semantics:
  % - If the flag is in IUSE, enforce it against the candidate's *effective* USE
  %   (Portage semantics for deps like pkg[foo], pkg[-bar], pkg[foo?], pkg[foo=]).
  %
  %   IMPORTANT: we must NOT treat `pkg[foo]` as "always solvable by rebuilding
  %   with foo enabled", because Portage does not auto-toggle USE flags to satisfy
  %   a dependency. The requirement must match the USE that the system would
  %   actually build the child with (profile/make.conf/package.use + IUSE defaults).
  % - If the flag is NOT in IUSE, only allow the dependency when it provides an
  %   explicit default marker (+)/(-), which defines the assumed state.
  ( rules:candidate_iuse_present(Repo://Entry, Use)
  -> ( Mode == enable
     -> rules:candidate_effective_use_enabled_in_iuse(Repo://Entry, Use)
     ; Mode == disable
     -> \+ rules:candidate_effective_use_enabled_in_iuse(Repo://Entry, Use)
     )
  ; rules:use_dep_default_satisfies_absent_iuse(Default, Mode)
  ).

% True iff Use appears in IUSE (with or without default prefix).
rules:candidate_iuse_present(Repo://Entry, Use) :-
  rules:entry_iuse_info(Repo://Entry, iuse_info(IuseSet, _PlusSet)),
  memberchk(Use, IuseSet),
  !.

% If a USE-dep names a flag that is not in IUSE, only (+)/(-) defaults make it valid.
rules:use_dep_default_satisfies_absent_iuse(positive, enable) :- !.
rules:use_dep_default_satisfies_absent_iuse(negative, disable) :- !.
rules:use_dep_default_satisfies_absent_iuse(_Default, _Mode) :- fail.

% Determine whether a flag is effectively enabled for a candidate *when the flag is in IUSE*.
%
% Cached per (Repo, Entry): on first access, computes the full enabled USE set
% for the entry and caches it. Subsequent calls for the same entry are O(1) memberchk.
rules:candidate_effective_use_enabled_in_iuse(Repo://Entry, Use) :-
  rules:entry_effective_use_set(Repo://Entry, EnabledSet),
  memberchk(Use, EnabledSet).

rules:entry_effective_use_set(Repo://Entry, EnabledSet) :-
  ( rules:effective_use_fact(Repo, Entry, EnabledSet) ->
    true
  ;
    rules:entry_iuse_info(Repo://Entry, iuse_info(IuseSet, _PlusSet)),
    findall(U,
            ( member(U, IuseSet),
              rules:candidate_effective_use_enabled_raw(Repo://Entry, U)
            ),
            Enabled0),
    sort(Enabled0, EnabledSet),
    assertz(rules:effective_use_fact(Repo, Entry, EnabledSet))
  ).

% Priority:
% 1. Per-package overrides from /etc/portage/package.use (modeled in preference.pl)
% 2. Global USE from profile/make.conf (preference:use/1)
% 3. IUSE default (+foo) enables; otherwise default is disabled
rules:candidate_effective_use_enabled_raw(Repo://Entry, Use) :-
  cache:ordered_entry(Repo, Entry, C, N, _),
  ( preference:profile_package_use_override_for_entry(Repo://Entry, Use, positive, _Reason0) ->
      true
  ; preference:profile_package_use_override_for_entry(Repo://Entry, Use, negative, _Reason0) ->
      fail
  ; preference:package_use_override(C, N, Use, positive) ->
      true
  ; preference:package_use_override(C, N, Use, negative) ->
      fail
  ; preference:gentoo_package_use_override_for_entry_soft(Repo://Entry, Use, positive) ->
      true
  ; preference:gentoo_package_use_override_for_entry_soft(Repo://Entry, Use, negative) ->
      fail
  ; preference:profile_package_use_override_for_entry_soft(Repo://Entry, Use, positive) ->
      true
  ; preference:profile_package_use_override_for_entry_soft(Repo://Entry, Use, negative) ->
      fail
  ; preference:use(Use) ->
      true
  ; rules:use_expand_selector_flag_unset(Use) ->
      fail
  ; preference:use(minus(Use)),
    \+ rules:is_abi_x86_flag(Use) ->
      fail
  ; rules:entry_iuse_info(Repo://Entry, iuse_info(_IuseSet, PlusSet)),
    memberchk(Use, PlusSet) ->
      true
  ; fail
  ).

rules:use_expand_selector_flag_unset(Use) :-
  atom(Use),
  preference:use_expand_env(_EnvVar, Prefix),
  atom_concat(Prefix, '_', PrefixUnderscore),
  atom_concat(PrefixUnderscore, _, Use),
  rules:use_expand_prefix_has_explicit_selection(Prefix),
  \+ preference:use(Use),
  \+ preference:use(minus(Use)),
  !.

rules:use_expand_prefix_has_explicit_selection(Prefix) :-
  atom_concat(Prefix, '_', PrefixUnderscore),
  ( preference:use(Use0)
  ; preference:use(minus(Use0))
  ),
  atom(Use0),
  atom_concat(PrefixUnderscore, _, Use0),
  !.

rules:is_abi_x86_flag(Use) :-
  atom(Use),
  sub_atom(Use, 0, _, _, abi_x86_),
  !.

% -----------------------------------------------------------------------------
%  Per-entry IUSE memoization (performance)
% -----------------------------------------------------------------------------
%
% Bracketed USE dependencies (very common: abi_x86_64, static-libs, ... ) can
% occur on a large fraction of dependency edges. Querying IUSE metadata repeatedly
% for the same entry becomes expensive at whole-tree scale.
%
% We memoize, per (Repo,Entry), both:
% - the set of USE flags present in IUSE (regardless of defaults)
% - the subset that are enabled by default (+flag)

rules:entry_iuse_info(Repo://Entry, Info) :-
  ( nb_current(rules_entry_iuse_info_cache, Cache),
    get_assoc(key(Repo,Entry), Cache, Info)
  ->
    true
  ;
    findall(Raw, query:search(iuse(Raw), Repo://Entry), RawIuse0),
    sort(RawIuse0, RawIuse),
    findall(U,
            ( member(Raw, RawIuse),
              eapi:strip_use_default(Raw, U)
            ),
            Iuse0),
    sort(Iuse0, IuseSet),
    findall(U,
            member(plus(U), RawIuse),
            Plus0),
    sort(Plus0, PlusSet),
    Info = iuse_info(IuseSet, PlusSet),
    ( nb_current(rules_entry_iuse_info_cache, Cache0) -> true ; empty_assoc(Cache0) ),
    put_assoc(key(Repo,Entry), Cache0, Info, Cache1),
    nb_setval(rules_entry_iuse_info_cache, Cache1)
  ).

% -----------------------------------------------------------------------------
%  CN-consistency reuse: pick already-selected entry when possible
% -----------------------------------------------------------------------------

rules:selected_cn_candidate(Action, C, N, Context, FoundRepo://Candidate) :-
  memberchk(constraint(selected_cn(C,N):{ordset(SelectedSet)}), Context),
  member(selected(FoundRepo, Candidate, ActSel, _CandVer, SelSlotMeta), SelectedSet),
  % CN-consistency should be global across actions/phases: once we've chosen a
  % concrete (C,N) entry, reuse it for both install+run obligations.
  % Otherwise we can end up scheduling two different versions for the same (C,N)
  % when the run-dep is encountered before the install-dep (or vice versa),
  % e.g. wrk -> luajit installs two luajit versions.
  ( (Action == install ; Action == run),
    (ActSel == install ; ActSel == run)
  -> true
  ; ActSel == Action
  ),
  % Multi-slot awareness: if the context carries a slot lock for this (C,N)
  % (typically via := / any_same_slot), only reuse a selection in that slot.
  ( memberchk(slot(C,N,SsLock0):{_}, Context) ->
      rules:canon_any_same_slot_meta(SsLock0, SsLock),
      rules:canon_any_same_slot_meta(SelSlotMeta, SsSel),
      SsSel == SsLock
  ; true
  ),
  cache:ordered_entry(FoundRepo, Candidate, C, N, _),
  \+ preference:masked(FoundRepo://Candidate).

% Reuse an already-selected CN candidate only when it remains compatible with
% this grouped dependency's slot/version/domain requirements.
rules:selected_cn_candidate_compatible(Action, C, N, SlotReq, PackageDeps, Context, FoundRepo://Candidate) :-
  rules:selected_cn_candidate(Action, C, N, Context, FoundRepo://Candidate),
  rules:query_search_slot_constraint(SlotReq, FoundRepo://Candidate, _),
  rules:grouped_dep_candidate_satisfies_constraints(Action, C, N, PackageDeps, Context, FoundRepo://Candidate).

% Collect selected candidates that match slot requirements but violate current
% grouped dependency constraints. These are excluded from the "fresh candidate"
% fallback path for this dependency literal.
rules:selected_cn_rejected_candidates(Action, C, N, SlotReq, PackageDeps, Context, Rejected) :-
  rules:grouped_dep_effective_domain_precomputed(Action, C, N, PackageDeps, Context, EffDom, RejectDom),
  findall(Repo://Entry,
          ( rules:selected_cn_candidate(Action, C, N, Context, Repo://Entry),
            rules:query_search_slot_constraint(SlotReq, Repo://Entry, _),
            \+ rules:grouped_dep_candidate_satisfies_constraints_precomputed(
                    C, N, PackageDeps, EffDom, RejectDom, Repo://Entry)
          ),
          Rejected0),
  sort(Rejected0, Rejected),
  !.

rules:grouped_dep_candidate_satisfies_constraints(Action, C, N, PackageDeps, Context, RepoEntry) :-
  forall(member(package_dependency(_Phase,no,C,N,O,V,_SlotReq,_Use), PackageDeps),
         rules:query_search_version_select(O, V, RepoEntry)),
  rules:grouped_dep_candidate_satisfies_effective_domain(Action, C, N, PackageDeps, Context, RepoEntry),
  !.

rules:grouped_dep_candidate_satisfies_constraints_precomputed(C, N, PackageDeps, EffDom, RejectDom, RepoEntry) :-
  forall(member(package_dependency(_Phase,no,C,N,O,V,_SlotReq,_Use), PackageDeps),
         rules:query_search_version_select(O, V, RepoEntry)),
  rules:grouped_dep_candidate_satisfies_effective_domain_precomputed(EffDom, RejectDom, C, N, RepoEntry),
  !.

rules:grouped_dep_effective_domain_precomputed(Action, C, N, PackageDeps, Context, EffectiveDomain, RejectDomain) :-
  rules:grouped_dep_effective_domain(Action, C, N, PackageDeps, Context, EffectiveDomain),
  rules:context_cn_reject_scope(C, N, Context, EffectiveDomain, RejectScope),
  rules:cn_reject_scoped_domain(RejectScope, EffectiveDomain, RejectDomain),
  !.

rules:grouped_dep_candidate_satisfies_effective_domain(Action, C, N, PackageDeps, Context, RepoEntry) :-
  rules:grouped_dep_effective_domain_precomputed(Action, C, N, PackageDeps, Context, EffectiveDomain, RejectDomain),
  rules:grouped_dep_candidate_satisfies_effective_domain_precomputed(EffectiveDomain, RejectDomain, C, N, RepoEntry),
  !.

rules:grouped_dep_candidate_satisfies_effective_domain_precomputed(EffectiveDomain, RejectDomain, C, N, RepoEntry) :-
  \+ version_domain:domain_inconsistent(EffectiveDomain),
  \+ rules:cn_domain_candidate_rejected(C, N, RejectDomain, RepoEntry),
  version_domain:domain_allows_candidate(EffectiveDomain, RepoEntry),
  !.

rules:grouped_dep_effective_domain(Action, C, N, PackageDeps, Context, EffectiveDomain) :-
  version_domain:domain_from_packagedeps(Action, C, N, PackageDeps, DepDomain0),
  ( rules:context_cn_domain_constraint(C, N, Context, CtxDomain0) ->
      ( version_domain:domain_meet(CtxDomain0, DepDomain0, D1) -> true
      ; D1 = version_domain(slots([]), [])
      )
  ; D1 = DepDomain0
  ),
  rules:apply_learned_domain(C, N, PackageDeps, D1, EffectiveDomain),
  !.

% Apply any learned domain constraints for (C,N). Checks slot-specific
% first, then any-slot fallback.
rules:apply_learned_domain(C, N, PackageDeps, D0, D) :-
  rules:dep_slot_key(PackageDeps, Slot),
  ( Slot \== any, prover:learned(cn_domain(C,N,Slot), L1) -> true ; L1 = none ),
  ( prover:learned(cn_domain(C,N,any), L2) -> true ; L2 = none ),
  ( L1 \== none, L2 \== none ->
      version_domain:domain_meet(L1, L2, Learned),
      ( version_domain:domain_meet(D0, Learned, D) -> true ; D = D0 )
  ; L1 \== none ->
      ( version_domain:domain_meet(D0, L1, D) -> true ; D = D0 )
  ; L2 \== none ->
      ( version_domain:domain_meet(D0, L2, D) -> true ; D = D0 )
  ; D = D0
  ), !.

rules:dep_slot_key(PackageDeps, Slot) :-
  member(package_dependency(_, _, _, _, _, _, SlotReq, _), PackageDeps),
  SlotReq = [slot(S)|_], rules:canon_slot(S, Slot), !.
rules:dep_slot_key(_, any).

rules:context_cn_domain_constraint(C, N, Context, Domain) :-
  is_list(Context),
  memberchk(constraint(cn_domain(C,N):{Domain}), Context),
  !.

rules:context_cn_domain_reason(C, N, Context, Reasons) :-
  is_list(Context),
  ( memberchk(constraint(cn_domain_reason(C,N):{ordset(Reasons0)}), Context) ->
      Reasons = Reasons0
  ; memberchk(domain_reason(cn_domain(C,N,Reasons0)), Context) ->
      Reasons = Reasons0
  ; Reasons = []
  ),
  !.

rules:context_selected_cn_candidates(C, N, Context, Candidates) :-
  is_list(Context),
  memberchk(constraint(selected_cn(C,N):{ordset(SelectedSet)}), Context),
  findall(Repo://Entry,
          member(selected(Repo,Entry,_Act,_SelVer,_SelSlotMeta), SelectedSet),
          Candidates0),
  sort(Candidates0, Candidates),
  Candidates \== [],
  !.

% Slot-scoped reject scope from proving context:
% - when a slot lock is present in context, scope rejects to that slot;
% - otherwise derive scope from the effective domain (explicit slot deps).
rules:context_cn_reject_scope(C, N, Context, Domain, Scope) :-
  ( rules:context_slot_scope(C, N, Context, Scope0) ->
      Scope = Scope0
  ; rules:domain_slot_scope(Domain, Scope)
  ),
  !.

rules:context_slot_scope(C, N, Context, slot(Slot)) :-
  is_list(Context),
  memberchk(slot(C,N,Ss0):{_}, Context),
  rules:canon_any_same_slot_meta(Ss0, [slot(Slot)]),
  !.

rules:domain_slot_scope(version_domain(slots([S0]), _Bounds), slot(S)) :-
  rules:canon_slot(S0, S),
  !.
rules:domain_slot_scope(_Domain, any) :-
  !.

rules:cn_reject_scope_canon(slot(S0), slot(S)) :-
  rules:canon_slot(S0, S),
  !.
rules:cn_reject_scope_canon(any, any) :-
  !.
rules:cn_reject_scope_canon(_Other, any) :-
  !.

rules:cn_reject_scoped_domain(any, Domain, Domain) :-
  !.
rules:cn_reject_scoped_domain(Scope0, Domain, scoped(Scope, Domain)) :-
  rules:cn_reject_scope_canon(Scope0, Scope),
  !.

rules:snapshot_selected_cn_candidates(C, N, Candidates) :-
  nb_current(rules_selected_cn_snapshot, Snapshots),
  get_assoc(key(C,N), Snapshots, ordset(Candidates)),
  Candidates \== [],
  !.

rules:record_selected_cn_snapshot(C, N, SelectedSet) :-
  findall(Repo://Entry,
          member(selected(Repo,Entry,_Act,_SelVer,_SelSlotMeta), SelectedSet),
          Candidates0),
  sort(Candidates0, Candidates),
  ( nb_current(rules_selected_cn_snapshot, Snap0) -> true ; empty_assoc(Snap0) ),
  put_assoc(key(C,N), Snap0, ordset(Candidates), Snap1),
  nb_setval(rules_selected_cn_snapshot, Snap1),
  !.

rules:snapshot_blocked_cn_sources(C, N, Sources) :-
  nb_current(rules_blocked_cn_source_snapshot, Snapshots),
  get_assoc(key(C,N), Snapshots, ordset(Sources)),
  Sources \== [],
  !.

rules:record_blocked_cn_source_snapshot(C, N, Sources0) :-
  sort(Sources0, Sources),
  Sources \== [],
  ( nb_current(rules_blocked_cn_source_snapshot, Snap0) -> true ; empty_assoc(Snap0) ),
  ( get_assoc(key(C,N), Snap0, ordset(OldSources), Snap1, ordset(OldSources)) -> true
  ; OldSources = [],
    Snap1 = Snap0
  ),
  ord_union(OldSources, Sources, MergedSources),
  put_assoc(key(C,N), Snap1, ordset(MergedSources), SnapOut),
  nb_setval(rules_blocked_cn_source_snapshot, SnapOut),
  !.
rules:record_blocked_cn_source_snapshot(_C, _N, _Sources) :-
  !.

rules:reason_linked_selected_reprove_target(Reasons, SourceC, SourceN, [SourceRepo://SourceEntry]) :-
  is_list(Reasons),
  member(introduced_by(OriginRepo://OriginEntry, _ReasonAction, _ReasonWhat), Reasons),
  query:search([category(OriginC),name(OriginN)], OriginRepo://OriginEntry),
  rules:snapshot_blocked_cn_sources(OriginC, OriginN, Sources),
  member(source(SourceRepo,SourceEntry,_Phase,_O,_V,_SlotReq), Sources),
  query:search([category(SourceC),name(SourceN)], SourceRepo://SourceEntry),
  rules:snapshot_selected_cn_candidates(SourceC, SourceN, SelectedSourceCandidates),
  memberchk(SourceRepo://SourceEntry, SelectedSourceCandidates),
  !.

rules:domain_conflicting_candidates(_Domain, [], []) :-
  !.
rules:domain_conflicting_candidates(Domain, Candidates, Conflicting) :-
  findall(RepoEntry,
          ( member(RepoEntry, Candidates),
            \+ version_domain:domain_allows_candidate(Domain, RepoEntry)
          ),
          Conflicting0),
  sort(Conflicting0, Conflicting),
  !.

% Find selected candidates that violate the *full* grouped dependency constraints
% (version operator semantics, USE deps, effective domain/reject map), not just
% the normalized version-domain approximation.
rules:constraint_conflicting_candidates(_Action, _C, _N, _PackageDeps, _Context, [], []) :-
  !.
rules:constraint_conflicting_candidates(Action, C, N, PackageDeps, Context, Candidates, Conflicting) :-
  findall(RepoEntry,
          ( member(RepoEntry, Candidates),
            \+ rules:grouped_dep_candidate_satisfies_constraints(Action, C, N, PackageDeps, Context, RepoEntry)
          ),
          Conflicting0),
  sort(Conflicting0, Conflicting),
  !.

% When grouped dependency proving drifts toward assumption fallback, request a
% bounded CN-domain reprove retry using conflicting selected candidates and
% collected domain provenance reasons.
rules:maybe_request_grouped_dep_reprove(Action, C, N, PackageDeps, Context) :-
  rules:cn_domain_reprove_enabled,
  ( rules:context_selected_cn_candidates(C, N, Context, SelectedCandidatesRaw) ->
      true
  ; rules:snapshot_selected_cn_candidates(C, N, SelectedCandidates0) ->
      SelectedCandidatesRaw = SelectedCandidates0
  ; SelectedCandidatesRaw = []
  ),
  rules:grouped_dep_effective_domain(Action, C, N, PackageDeps, Context, EffectiveDomain),
  rules:context_cn_reject_scope(C, N, Context, EffectiveDomain, RejectScope),
  rules:cn_reject_scoped_domain(RejectScope, EffectiveDomain, RejectDomain),
  rules:domain_conflicting_candidates(EffectiveDomain, SelectedCandidatesRaw, DomainConflicting),
  rules:constraint_conflicting_candidates(Action, C, N, PackageDeps, Context, SelectedCandidatesRaw, ConstraintConflicting),
  ord_union(DomainConflicting, ConstraintConflicting, SelectedCandidates),
  version_domain:domain_reason_terms(Action, C, N, PackageDeps, Context, Reasons),
  ( SelectedCandidates \== []
  ; Reasons \== []
  ),
  ( version_domain:domain_inconsistent(EffectiveDomain)
  ; SelectedCandidates \== []
  ; rules:dep_has_version_constraint(C, N, PackageDeps)
  ; rules:dep_has_explicit_slot_constraint(C, N, PackageDeps)
  ),
  ( SelectedCandidates == [],
    rules:reason_linked_selected_reprove_target(Reasons, SourceC, SourceN, SourceCandidates)
  ->
    throw(rules_reprove_cn_domain(SourceC, SourceN, none, SourceCandidates, Reasons))
  ; throw(rules_reprove_cn_domain(C, N, RejectDomain, SelectedCandidates, Reasons))
  ).
rules:maybe_request_grouped_dep_reprove(_Action, _C, _N, _PackageDeps, _Context) :-
  fail.

% -----------------------------------------------------------------------------
%  Scoped CN-domain reject map (used by bounded reprove retries)
% -----------------------------------------------------------------------------
%
% This map stores candidate no-goods keyed by (C,N,Domain), so retries can avoid
% repeatedly selecting the same candidate under the same effective domain.
% Scope is per top-level prover call (managed by prover:prove/9).

rules:cn_domain_reject_key(C, N, scoped(Scope0, Domain0), key(C,N,Scope,Domain)) :-
  rules:cn_reject_scope_canon(Scope0, Scope),
  version_domain:domain_normalize(Domain0, Domain),
  !.
rules:cn_domain_reject_key(C, N, Domain0, key(C,N,Scope,Domain)) :-
  version_domain:domain_normalize(Domain0, Domain),
  rules:domain_slot_scope(Domain, Scope),
  !.

rules:cn_domain_candidate_rejected(C, N, Domain0, RepoEntry) :-
  nb_current(rules_cn_domain_rejects, Rejects),
  rules:cn_domain_reject_key(C, N, Domain0, key(C,N,Scope,Domain)),
  ( get_assoc(key(C,N,Scope,Domain), Rejects, ordset(Set)),
    memberchk(RepoEntry, Set)
  ; get_assoc(key(C,N,Scope,none), Rejects, ordset(ScopeGlobalSet)),
    memberchk(RepoEntry, ScopeGlobalSet)
  ; Scope \== any,
    get_assoc(key(C,N,any,Domain), Rejects, ordset(AnyDomainSet)),
    memberchk(RepoEntry, AnyDomainSet)
  ; get_assoc(key(C,N,any,none), Rejects, ordset(GlobalSet)),
    memberchk(RepoEntry, GlobalSet)
  ),
  !.

rules:add_cn_domain_rejects(C, N, Domain0, Candidates0, Added) :-
  rules:cn_domain_reject_key(C, N, Domain0, Key),
  sort(Candidates0, Candidates),
  ( nb_current(rules_cn_domain_rejects, Rejects0) -> true ; empty_assoc(Rejects0) ),
  ( get_assoc(Key, Rejects0, ordset(OldSet), Rejects1, ordset(OldSet)) -> true
  ; OldSet = [],
    Rejects1 = Rejects0
  ),
  ord_union(OldSet, Candidates, NewSet),
  ( NewSet == OldSet ->
      Added = false,
      RejectsOut = Rejects1
  ; Added = true,
    put_assoc(Key, Rejects1, ordset(NewSet), RejectsOut)
  ),
  nb_setval(rules_cn_domain_rejects, RejectsOut),
  !.

rules:add_cn_domain_origin_rejects(Reasons, Added) :-
  is_list(Reasons),
  findall(C0-N0-Repo://Entry,
          ( member(introduced_by(Repo://Entry, _Action, _Why), Reasons),
            query:search([category(C0),name(N0)], Repo://Entry)
          ),
          Origins0),
  sort(Origins0, Origins),
  rules:add_cn_domain_origin_rejects_(Origins, false, Added),
  !.
rules:add_cn_domain_origin_rejects(_Reasons, false) :-
  !.

rules:add_cn_domain_origin_rejects_([], Added, Added) :-
  !.
rules:add_cn_domain_origin_rejects_([C-N-Repo://Entry|Rest], Added0, Added) :-
  rules:add_cn_domain_rejects(C, N, none, [Repo://Entry], Added1),
  ( Added0 == true ->
      Added2 = true
  ; Added1 == true ->
      Added2 = true
  ; Added2 = false
  ),
  rules:add_cn_domain_origin_rejects_(Rest, Added2, Added).

rules:cn_domain_reprove_enabled :-
  nb_current(rules_cn_domain_reprove_enabled, true),
  !.

rules:maybe_request_cn_domain_reprove(C, N, Domain, Selected) :-
  rules:maybe_request_cn_domain_reprove(C, N, Domain, Selected, []).

rules:maybe_request_cn_domain_reprove(C, N, Domain, Selected, Reasons) :-
  rules:cn_domain_reprove_enabled,
  findall(Repo://Entry,
          member(selected(Repo,Entry,_Act,_SelVer,_SelSlotMeta), Selected),
          Candidates0),
  sort(Candidates0, Candidates),
  Candidates \== [],
  throw(rules_reprove_cn_domain(C, N, Domain, Candidates, Reasons)).
rules:maybe_request_cn_domain_reprove(_C, _N, _Domain, _Selected, _Reasons) :-
  true.

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
% It processes a single USE dependency directive.
%
% CRITICAL (termination/performance):
% This predicate MUST be deterministic. Non-determinism here can cause massive
% backtracking explosions when build-with-use context is propagated through
% dependency cycles.
%
% We reuse the same normalization logic as `candidate_satisfies_use_deps/3`:
% first map (Directive,Default) to a concrete requirement (or none), then add
% the corresponding context assumptions.
process_use(ParentContext, use(Directive, Default), Acc, AccOut) :-
    !,
    rules:use_dep_requirement(ParentContext, Directive, Default, Requirement),
    ( Requirement = requirement(enable, Use, _Default) ->
        AccOut = [required(Use), assumed(Use)|Acc]
    ; Requirement = requirement(disable, Use, _Default) ->
        AccOut = [naf(required(Use)), assumed(minus(Use))|Acc]
    ; % none / unhandled
      AccOut = Acc
    ).

% Catch-all for any other directives
process_use(_ParentContext, _Other, Acc, Acc) :- !.



% Shared implementation of transactional update prerequisites for Repository://Ebuild.
% Context MUST contain replaces(OldRepo://OldEbuild).
rules:update_txn_conditions(Repository://Ebuild, Context, Conditions) :-
  % 1. Compute required_use stable model for the *new* version, extend with build_with_use
  rules:context_build_with_use_state(Context, B),
  (memberchk(required_use:R,Context) -> true ; R = []),
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
  query:search([category(CNew),name(NNew),select(slot,constraint([]),SAll)], Repository://Ebuild),
  ( memberchk(CNew,['virtual','acct-group','acct-user'])
    -> Base0 = [ constraint(use(Repository://Ebuild):{R}),
                 constraint(slot(CNew,NNew,SAll):{Ebuild})
                 |DeepUpdates],
       append(Base0, MergedDeps, Conditions)
    ;  Base0 = [ constraint(use(Repository://Ebuild):{R}),
                 constraint(slot(CNew,NNew,SAll):{Ebuild}),
                 Repository://Ebuild:download?{[required_use:R,build_with_use:B]}
                 |DeepUpdates],
       append(Base0, MergedDeps, Conditions)
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
            % For each dependency package, look at installed instances in the VDB repo (`pkg`)
            % (possibly multiple slots). Restricting to `pkg` avoids scanning all repos.
            query:search([name(N),category(C),installed(true)], pkg://OldEntry),
            OldRepo = pkg,
            pkg://OldEntry \== Self,
            query:search(version(OldVer), pkg://OldEntry),
            % Only deep-update within the same slot if we can determine it.
            query:search(slot(Slot0), pkg://OldEntry),
            rules:canon_slot(Slot0, Slot),
            % Pick the newest acceptable candidate in that slot.
            ( KeywordQ == []
              -> query:search(latest([select(repository,notequal,pkg),
                                      category(C),name(N),slot(Slot),
                                      select(version,greater,OldVer)]),
                              NewRepo://NewEntry)
              ;  query:search(latest([select(repository,notequal,pkg),
                                      category(C),name(N),slot(Slot),keywords(K),
                                      select(version,greater,OldVer)]),
                              NewRepo://NewEntry)
            )
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
  query:search([category(C),name(N)], Repo://Entry),
  !.
rules:dep_cn(Repo://Entry:_Action, C, N) :-
  query:search([category(C),name(N)], Repo://Entry),
  !.


% Determine a package slot for planning decisions.
% If explicit slot metadata exists, use it; otherwise treat it as slot 0.
rules:entry_slot_default(Repo, Entry, Slot) :-
  ( query:search(slot(Slot0), Repo://Entry)
    -> rules:canon_slot(Slot0, Slot)
    ;  Slot = '0'
  ).

% Normalize slot values so comparisons work even when some facts use numbers and
% others use atoms.
rules:canon_slot(S0, S) :-
  ( atom(S0)   -> S = S0
  ; integer(S0) -> atom_number(S, S0)
  ; number(S0)  -> atom_number(S, S0)
  ; S = S0
  ),
  !.

% Normalize slot metadata lists so `:=`/any_same_slot compares by SLOT only.
% Some contexts store full metadata [slot(S),subslot(Ss)], but any_same_slot
% queries now return [slot(S)]. Ensure we can unify reliably.
rules:canon_any_same_slot_meta(Meta0, [slot(S)]) :-
  is_list(Meta0),
  member(slot(S0), Meta0),
  rules:canon_slot(S0, S),
  !.

% -----------------------------------------------------------------------------
%  Constraint guard (domain hook called by prover)
% -----------------------------------------------------------------------------
%
% This predicate is called by the prover after merging any constraint literal.
% It must succeed for consistent constraint stores and fail to force backtracking
% when constraints become inconsistent.
%
% We use it for enforcing strong blockers against already-selected candidates,
% while keeping the prover itself domain-agnostic.
%
rules:constraint_guard(constraint(cn_domain(C,N):{Domain0}), Constraints) :-
  !,
  ( get_assoc(cn_domain(C,N), Constraints, Domain) -> true ; Domain = Domain0 ),
  ( version_domain:domain_inconsistent(Domain) ->
      % Multi-slot mode can intentionally accumulate disjoint slot domains
      % (e.g. ruby:3.2 and ruby:3.3). In that case the merged intersection is
      % globally inconsistent by construction, but each slot-constrained edge is
      % still validated locally during candidate selection.
      get_assoc(selected_cn_allow_multislot(C,N), Constraints, _AllowMultiSlot)
  ; ( get_assoc(selected_cn(C,N), Constraints, ordset(Selected)) ->
          rules:selected_cn_domain_compatible_or_reprove(C, N, Domain, Selected, Constraints)
    ; true
    )
  ).
rules:constraint_guard(constraint(blocked_cn(C,N):{ordset(Specs)}), Constraints) :-
  !,
  ( get_assoc(selected_cn(C,N), Constraints, ordset(Selected)) ->
      rules:selected_cn_not_blocked_or_reprove(C, N, Specs, Selected, Constraints)
  ; true
  ).
rules:constraint_guard(constraint(blocked_cn_source(C,N):{ordset(Sources)}), _Constraints) :-
  !,
  rules:record_blocked_cn_source_snapshot(C, N, Sources).
rules:constraint_guard(constraint(selected_cn_allow_multislot(_C,_N):{_}), _Constraints) :-
  !.
rules:constraint_guard(constraint(selected_cn(C,N):{ordset(_SelectedNew)}), Constraints) :-
  !,
  % Enforce CN-consistency:
  % - default: one concrete entry per (C,N),
  % - opt-in: allow one concrete entry per SLOT when multislot was explicitly
  %   requested (slot-qualified deps or split grouped deps).
  get_assoc(selected_cn(C,N), Constraints, ordset(SelectedMerged)),
  rules:record_selected_cn_snapshot(C, N, SelectedMerged),
  ( get_assoc(cn_domain(C,N), Constraints, Domain) ->
      rules:selected_cn_domain_compatible_or_reprove(C, N, Domain, SelectedMerged, Constraints)
  ; true
  ),
  rules:selected_cn_unique_or_reprove(C, N, SelectedMerged, Constraints),
  ( get_assoc(blocked_cn(C,N), Constraints, ordset(Specs)) ->
      rules:selected_cn_not_blocked_or_reprove(C, N, Specs, SelectedMerged, Constraints)
  ; true
  ).
rules:constraint_guard(_Other, _Constraints).

% Enforce uniqueness, but when enabled allow a bounded reprove retry if a stale
% selected candidate conflicts with an active CN domain while another candidate
% in the merged set still satisfies that domain.
rules:selected_cn_unique_or_reprove(C, N, SelectedMerged, Constraints) :-
  rules:selected_cn_unique(C, N, SelectedMerged, Constraints),
  !.
rules:selected_cn_unique_or_reprove(C, N, SelectedMerged, Constraints) :-
  rules:cn_domain_reprove_enabled,
  get_assoc(cn_domain(C,N), Constraints, Domain),
  % Keep same-slot multiversion edge-cases unchanged (ocaml/ppx transition).
  \+ rules:selected_cn_requires_same_slot_multiversion(C, N, Constraints),
  rules:selected_cn_partition_by_domain(Domain, SelectedMerged, Allowed, Conflicting),
  Allowed \== [],
  Conflicting \== [],
  ( Conflicting = [selected(_,_,_,_,SM0)|_],
    rules:selected_cn_slot_key_(SM0, Slot) -> true ; Slot = any ),
  prover:learn(cn_domain(C,N,Slot), Domain, _),
  ( Slot \== any -> prover:learn(cn_domain(C,N,any), Domain, _) ; true ),
  rules:maybe_request_cn_domain_reprove(C, N, none, Conflicting, [unique_conflict_with_domain]),
  fail.
% Inconsistent domain with identifiable origin: learn a narrowing
% constraint for the origin package (Vermeir: lower-priority yields).
rules:selected_cn_unique_or_reprove(C, N, _SelectedMerged, Constraints) :-
  rules:cn_domain_reprove_enabled,
  get_assoc(cn_domain(C,N), Constraints, _Domain),
  rules:selected_cn_requires_same_slot_multiversion(C, N, Constraints),
  ( get_assoc(cn_domain_reason(C,N), Constraints, ordset(Reasons)) -> true ; Reasons = [] ),
  Reasons \== [],
  rules:find_adjustable_origin(Reasons, OriginC, OriginN, OriginRepo://OriginEntry),
  query:search(version(OriginVer), OriginRepo://OriginEntry),
  ExcludeDomain = version_domain(any, [bound(smaller, OriginVer)]),
  prover:learn(cn_domain(OriginC, OriginN, any), ExcludeDomain, Added),
  Added == true,
  rules:maybe_request_cn_domain_reprove(OriginC, OriginN, none, [OriginRepo://OriginEntry], [inconsistency_driven]),
  fail.
rules:selected_cn_unique_or_reprove(_C, _N, _SelectedMerged, _Constraints) :-
  fail.

% Find an origin that already has a learned constraint — that's the
% adjustable package whose version needs further narrowing.
rules:find_adjustable_origin(Reasons, OriginC, OriginN, Repo://Entry) :-
  member(introduced_by(Repo://Entry, _Action, _Why), Reasons),
  cache:ordered_entry(Repo, Entry, OriginC, OriginN, _),
  prover:learned(cn_domain(OriginC, OriginN, _), _), !.

% When a dep on (C,N) can't be satisfied, the parent (self) likely
% selected the wrong version. Learn to exclude the parent's current
% version so the next retry picks an older one.
% Do NOT fire for multi-slot deps (explicit slot different from selected) —
% those need the missing slot to be added, not the parent narrowed.
% Do NOT fire for PDEPEND failures — post-dependencies are soft requirements
% that should not invalidate the parent's installability.
rules:maybe_learn_parent_narrowing(C, N, PackageDeps, Context) :-
  nb_current(prover_learned_constraints, _),
  \+ rules:is_pdepend_failure(PackageDeps, Context),
  \+ rules:is_multislot_miss(C, N, PackageDeps, Context),
  is_list(Context),
  memberchk(self(ParentRepo://ParentEntry), Context),
  cache:ordered_entry(ParentRepo, ParentEntry, ParentC, ParentN, _),
  query:search(version(ParentVer), ParentRepo://ParentEntry),
  ExcludeDomain = version_domain(any, [bound(smaller, ParentVer)]),
  prover:learn(cn_domain(ParentC, ParentN, any), ExcludeDomain, Added),
  Added == true,
  rules:cn_domain_reprove_enabled,
  throw(rules_reprove_cn_domain(ParentC, ParentN, none, [ParentRepo://ParentEntry], [parent_narrowing])).

% A PDEPEND failure should not cause parent narrowing. PDEPENDs are
% post-dependencies: their unsatisfiability does not mean the parent
% version is wrong, only that a post-install integration is missing.
rules:is_pdepend_failure(PackageDeps, _Context) :-
  member(package_dependency(pdepend, _, _, _, _, _, _, _), PackageDeps),
  !.
rules:is_pdepend_failure(_, Context) :-
  is_list(Context),
  memberchk(after_only(_), Context),
  !.

% A dep on (C,N) with an explicit slot that doesn't match any selected_cn
% entry is a multi-slot miss — the solver needs to ADD the new slot, not
% narrow the parent.
rules:is_multislot_miss(C, N, PackageDeps, Context) :-
  member(package_dependency(_, _, C, N, _, _, [slot(DepSlot0)|_], _), PackageDeps),
  rules:canon_slot(DepSlot0, DepSlot),
  is_list(Context),
  memberchk(constraint(selected_cn(C,N):{ordset(Selected)}), Context),
  \+ ( member(selected(_, _, _, _, SlotMeta), Selected),
       rules:selected_cn_slot_key_(SlotMeta, DepSlot) ),
  !.

rules:selected_cn_partition_by_domain(_Domain, [], [], []) :-
  !.
rules:selected_cn_partition_by_domain(Domain, [Sel|Rest], [Sel|AllowedRest], ConflictingRest) :-
  Sel = selected(Repo,Entry,_Act,_SelVer,_SelSlotMeta),
  version_domain:domain_allows_candidate(Domain, Repo://Entry),
  !,
  rules:selected_cn_partition_by_domain(Domain, Rest, AllowedRest, ConflictingRest).
rules:selected_cn_partition_by_domain(Domain, [Sel|Rest], AllowedRest, [Sel|ConflictingRest]) :-
  rules:selected_cn_partition_by_domain(Domain, Rest, AllowedRest, ConflictingRest).

rules:selected_cn_not_blocked_or_reprove(_C, _N, Specs, Selected, _Constraints) :-
  \+ rules:specs_violate_selected(Specs, Selected),
  !.
rules:selected_cn_not_blocked_or_reprove(C, N, _Specs, _Selected, Constraints) :-
  rules:cn_domain_reprove_enabled,
  rules:blocked_cn_source_reprove_target(C, N, Constraints, SourceC, SourceN, Candidates),
  Candidates \== [],
  throw(rules_reprove_cn_domain(SourceC, SourceN, none, Candidates, [])).
rules:selected_cn_not_blocked_or_reprove(_C, _N, _Specs, _Selected, _Constraints) :-
  fail.

rules:blocked_cn_source_reprove_target(C, N, Constraints, SourceC, SourceN, [Repo://Entry]) :-
  get_assoc(blocked_cn_source(C,N), Constraints, ordset(Sources)),
  member(source(Repo,Entry,_Phase,_O,_V,_SlotReq), Sources),
  query:search([category(SourceC),name(SourceN)], Repo://Entry),
  !.

rules:selected_cn_domain_compatible_or_reprove(C, N, Domain, Selected, Constraints) :-
  ( once(( member(selected(Repo, Entry, _Act, _SelVer, _SelSlotMeta), Selected),
           version_domain:domain_allows_candidate(Domain, Repo://Entry)
         )) ->
      true
  ; % Learn the domain constraint so the next proof attempt can narrow
    % candidates before the wrong version is ever selected.
    ( \+ version_domain:domain_inconsistent(Domain) ->
        % Consistent domain: learn it for future narrowing
        ( ( Selected = [selected(_,_,_,_,SM0)|_],
            rules:selected_cn_slot_key_(SM0, SelSlot) -> true ; SelSlot = any ),
          prover:learn(cn_domain(C,N,SelSlot), Domain, _),
          ( SelSlot \== any -> prover:learn(cn_domain(C,N,any), Domain, _) ; true )
        -> true ; true )
    ; % Inconsistent domain: find the adjustable origin (Vermeir) and
      % learn a narrowing constraint for IT rather than blaming (C,N).
      ( get_assoc(cn_domain_reason(C,N), Constraints, ordset(Reasons0)) -> true ; Reasons0 = [] ),
      ( Reasons0 \== [],
        rules:find_adjustable_origin(Reasons0, OriginC, OriginN, OriginRepo://OriginEntry),
        query:search(version(OriginVer), OriginRepo://OriginEntry),
        ExcludeDomain = version_domain(any, [bound(smaller, OriginVer)]),
        prover:learn(cn_domain(OriginC, OriginN, any), ExcludeDomain, OriginAdded),
        OriginAdded == true
      ->
        rules:maybe_request_cn_domain_reprove(OriginC, OriginN, none, [OriginRepo://OriginEntry], [inconsistency_driven]),
        fail
      ; true )
    ),
    ( get_assoc(cn_domain_reason(C,N), Constraints, ordset(Reasons)) -> true ; Reasons = [] ),
    ( rules:prefer_global_selected_reject_from_domain(C, N, Domain, Selected, Constraints) ->
        DomainForReprove = none
    ; DomainForReprove = Domain
    ),
    rules:maybe_request_cn_domain_reprove(C, N, DomainForReprove, Selected, Reasons),
    fail
  ),
  !.

rules:prefer_global_selected_reject_from_domain(C, _N, Domain, Selected, _Constraints) :-
  C == 'dev-haskell',
  Selected \== [],
  rules:domain_has_upper_bound(Domain),
  !.
rules:prefer_global_selected_reject_from_domain(C, N, Domain, Selected, Constraints) :-
  C == 'dev-lang',
  N == ghc,
  Selected \== [],
  rules:domain_has_upper_bound(Domain),
  \+ rules:selected_cn_requires_same_slot_multiversion(C, N, Constraints),
  !.
rules:prefer_global_selected_reject_from_domain(C, N, Domain, Selected, Constraints) :-
  C == 'dev-ml',
  N == cmdliner,
  Selected \== [],
  rules:domain_has_upper_bound(Domain),
  \+ rules:selected_cn_requires_same_slot_multiversion(C, N, Constraints),
  !.
rules:prefer_global_selected_reject_from_domain(C, N, Domain, Selected, Constraints) :-
  Selected \== [],
  rules:domain_has_equal_bound(Domain),
  \+ rules:selected_cn_requires_same_slot_multiversion(C, N, Constraints),
  !.

rules:domain_has_upper_bound(version_domain(_Slots, Bounds)) :-
  member(bound(Op, _Req), Bounds),
  ( Op == smaller
  ; Op == smallerequal
  ),
  !.

rules:domain_has_equal_bound(version_domain(_Slots, Bounds)) :-
  member(bound(equal, _Req), Bounds),
  !.

% Allow multi-slot selections only when explicitly requested.
rules:selected_cn_allow_multislot_constraints(C, N, SlotReq, PackageDeps, [constraint(selected_cn_allow_multislot(C,N):{true})]) :-
  ( SlotReq = [slot(_)|_]
  ; SlotReq == [any_same_slot]
  ; SlotReq == [any_different_slot]
  ; rules:all_deps_exactish_versioned(PackageDeps)
  ; rules:dep_has_version_constraint(C, N, PackageDeps)
  ),
  !.
rules:selected_cn_allow_multislot_constraints(_C, _N, _SlotReq, _PackageDeps, []).

rules:selected_cn_unique(C, N, SelectedMerged, Constraints) :-
  ( get_assoc(selected_cn_allow_multislot(C,N), Constraints, _AllowFlag) ->
      ( rules:selected_cn_requires_same_slot_multiversion(C, N, Constraints) ->
          rules:selected_cn_unique_per_slot_or_subslot(SelectedMerged)
      ; rules:selected_cn_unique_per_slot(SelectedMerged)
      )
  ; rules:selected_cn_unique_strict(SelectedMerged)
  ).

% Strict mode: all selected/5 terms must refer to the same Repo+Entry.
rules:selected_cn_unique_strict([]) :- !.
rules:selected_cn_unique_strict([selected(Repo,Entry,_Act,_Ver,_SlotMeta)|Rest]) :-
  forall(member(selected(Repo2,Entry2,_A2,_V2,_SlotMeta2), Rest),
         ( Repo2 == Repo,
           Entry2 == Entry
         )),
  rules:selected_cn_unique_strict(Rest).

% Multi-slot mode: one concrete entry per SLOT.
rules:selected_cn_unique_per_slot([]) :- !.
rules:selected_cn_unique_per_slot([selected(Repo,Entry,_Act,_Ver,SlotMeta)|Rest]) :-
  rules:selected_cn_slot_key_(SlotMeta, Slot),
  forall(member(selected(Repo2,Entry2,_A2,_V2,SlotMeta2), Rest),
         ( rules:selected_cn_slot_key_(SlotMeta2, Slot2),
           ( Slot2 \== Slot -> true
           ; Repo2 == Repo, Entry2 == Entry
           )
         )),
  rules:selected_cn_unique_per_slot(Rest).

% OCaml/PPX transition stacks can require two versions in the same SLOT, but
% they occupy different SUBSLOTs. Keep uniqueness at one concrete selection per
% (slot,subslot) pair to avoid over-broad side-by-side version allowance.
rules:selected_cn_unique_per_slot_or_subslot([]) :- !.
rules:selected_cn_unique_per_slot_or_subslot([selected(Repo,Entry,_Act,_Ver,SlotMeta)|Rest]) :-
  rules:selected_cn_slot_subslot_key_(Repo, Entry, SlotMeta, SlotSubslot),
  forall(member(selected(Repo2,Entry2,_A2,_Ver2,SlotMeta2), Rest),
         ( rules:selected_cn_slot_subslot_key_(Repo2, Entry2, SlotMeta2, SlotSubslot2),
           ( SlotSubslot2 \== SlotSubslot ->
               true
           ; Repo2 == Repo,
             Entry2 == Entry
           )
         )),
  rules:selected_cn_unique_per_slot_or_subslot(Rest).

% Generic same-slot multiversion gate:
% allow coexistence of distinct subslots only when merged CN-domain
% constraints are mutually inconsistent (no single version can satisfy all).
rules:selected_cn_requires_same_slot_multiversion(C, N, Constraints) :-
  get_assoc(cn_domain(C,N), Constraints, Domain),
  version_domain:domain_inconsistent(Domain),
  !.

% Extract a canonical (slot,subslot) key from selection metadata.
% If subslot is not present, use 'none' to keep keying stable.
rules:selected_cn_slot_subslot_key_(Repo, Entry, SlotMeta0, slot_subslot(Slot, SubSlot)) :-
  rules:canon_any_same_slot_meta(SlotMeta0, [slot(S0)]),
  rules:canon_slot(S0, Slot),
  ( is_list(SlotMeta0),
    memberchk(subslot(Ss0), SlotMeta0) ->
      rules:canon_slot(Ss0, SubSlot)
  ; query:search(subslot(Ss1), Repo://Entry) ->
      rules:canon_slot(Ss1, SubSlot)
  ; SubSlot = none
  ),
  !.

% Extract a canonical slot key from selection metadata.
% We only key on SLOT (not subslot) because multi-slot correctness is about
% concurrently installed slots, while subslot is about rebuild triggers.
rules:selected_cn_slot_key_(SlotMeta0, Slot) :-
  rules:canon_any_same_slot_meta(SlotMeta0, [slot(S0)]),
  rules:canon_slot(S0, Slot),
  !.

% True iff any blocker spec in Specs violates any selected instance.
%
% Current semantics:
% - strong (!!) blockers are enforced as hard conflicts (force backtracking)
% - weak (!) blockers are tracked as domain assumptions (warning), not enforced
%   during proving (to avoid search explosions).
rules:specs_violate_selected(Specs, Selected) :-
  member(blocked(Strength, Phase, O, V, SlotReq), Specs),
  Strength == strong,
  member(selected(Repo, Entry, Act, SelVer, SelSlotMeta), Selected),
  rules:action_phase(Act, Phase),
  rules:blocker_spec_matches_selected(SelVer, SelSlotMeta, Repo, Entry, O, V, SlotReq),
  !.

rules:action_phase(run, run) :- !.
rules:action_phase(install, install) :- !.
rules:action_phase(reinstall, install) :- !.
rules:action_phase(update, install) :- !.
rules:action_phase(download, install) :- !.
rules:action_phase(_Other, run).

rules:blocker_spec_matches_selected(SelVer, SelSlotMeta, Repo, Entry, O, V, SlotReq) :-
  rules:blocker_version_matches(O, V, SelVer, Repo, Entry),
  rules:blocker_slot_matches(SlotReq, SelSlotMeta, Repo, Entry).

rules:blocker_version_matches(none, _Req, _SelVer, _Repo, _Entry) :- !.
rules:blocker_version_matches(equal, Req, SelVer, _Repo, _Entry) :- !, SelVer == Req.
rules:blocker_version_matches(notequal, Req, SelVer, _Repo, _Entry) :- !, SelVer \== Req.
rules:blocker_version_matches(smaller, Req, SelVer, _Repo, _Entry) :- !, system:compare(<, SelVer, Req).
rules:blocker_version_matches(greater, Req, SelVer, _Repo, _Entry) :- !, system:compare(>, SelVer, Req).
rules:blocker_version_matches(smallerequal, Req, SelVer, _Repo, _Entry) :- !,
  ( system:compare(<, SelVer, Req) ; system:compare(=, SelVer, Req) ).
rules:blocker_version_matches(greaterequal, Req, SelVer, _Repo, _Entry) :- !,
  ( system:compare(>, SelVer, Req) ; system:compare(=, SelVer, Req) ).
rules:blocker_version_matches(Op, Req, _SelVer, Repo, Entry) :-
  % Fallback for wildcard/tilde/complex patterns: reuse query semantics.
  query:search(select(version,Op,Req), Repo://Entry).

rules:blocker_slot_matches([], _SelSlotMeta, _Repo, _Entry) :- !.
rules:blocker_slot_matches([slot(S)], SelSlotMeta, _Repo, _Entry) :- !,
  memberchk(slot(S), SelSlotMeta).
rules:blocker_slot_matches([slot(S),subslot(Ss)], SelSlotMeta, _Repo, _Entry) :- !,
  memberchk(slot(S), SelSlotMeta),
  memberchk(subslot(Ss), SelSlotMeta).
rules:blocker_slot_matches([slot(S),equal], SelSlotMeta, _Repo, _Entry) :- !,
  memberchk(slot(S), SelSlotMeta).
rules:blocker_slot_matches([slot(S),subslot(Ss),equal], SelSlotMeta, _Repo, _Entry) :- !,
  memberchk(slot(S), SelSlotMeta),
  memberchk(subslot(Ss), SelSlotMeta).
rules:blocker_slot_matches(SlotReq, _SelSlotMeta, Repo, Entry) :-
  % Fallback for any_same_slot/any_different_slot or future extensions.
  query:search(select(slot,constraint(SlotReq), _), Repo://Entry).

% -----------------------------------------------------------------------------
%  Helper: blocker uninstall goals
% -----------------------------------------------------------------------------
%
% Implement weak/strong blockers efficiently by querying the installed VDB repo
% (`pkg`) for matching instances and scheduling uninstall actions for them.
%
% Notes:
% - This enforces "not installed at end of transaction" for installed packages.
% - Co-installation prevention (strong blockers vs planned installs) can be
%   validated later using the planned package set without adding prover overhead.

% Extract blocker specs from a grouped dependency list.
% Specs is an ordset of blocked(Strength,Phase,O,V,SlotReq) terms.
rules:grouped_blocker_specs(Strength, Phase, C, N, PackageDeps, Specs) :-
  findall(blocked(Strength, Phase, O, V, SlotReq),
          ( member(package_dependency(Phase, Strength, C, N, O, V, SlotReq, _U), PackageDeps) ),
          Specs0),
  sort(Specs0, Specs).

% Partition grouped blocker specs into:
% - EnforceSpecs: unconditional blockers (no bracketed USE constraints)
% - AssumeSpecs:  conditional blockers (with USE constraints) that we do NOT enforce
%                as hard constraints during proving (see note in strong blocker rule).
rules:grouped_blocker_specs_partition(Strength, Phase, C, N, PackageDeps, EnforceSpecs, AssumeSpecs) :-
  findall(blocked(Strength, Phase, O, V, SlotReq),
          ( member(package_dependency(Phase, Strength, C, N, O, V, SlotReq, U), PackageDeps),
            U == []
          ),
          Enforce0),
  sort(Enforce0, EnforceSpecs),
  findall(blocked(Strength, Phase, O, V, SlotReq),
          ( member(package_dependency(Phase, Strength, C, N, O, V, SlotReq, U), PackageDeps),
            U \== []
          ),
          Assume0),
  sort(Assume0, AssumeSpecs),
  !.

% Find an installed entry for the given category/name, even if it isn't present
% as an ordered_entry (e.g. when the installed version no longer exists in the
% active repository set).
rules:installed_entry_cn(C, N, pkg, Entry) :-
  % The installed package database is represented by the VDB repository instance
  % named `pkg`. Prefer using its structured facts instead of parsing Entry IDs
  % with atom_concat/sub_atom (which is extremely expensive at scale).
  query:search([name(N),category(C),installed(true)], pkg://Entry),
  !.