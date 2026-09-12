/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> PLAN
Build plan rendering.

Handles terminal output for merge/fetchonly plans: element classification,
step-numbered wave display, colored action tags, pre-action sections
(unmask/keyword/USE-change), footer statistics, and variant diff display.

USE flag / config block rendering lives in useflags.pl; depclean removal
rendering lives in removal.pl.
*/

:- module(plan, []).

% =============================================================================
%  PLAN declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Main entry points
% -----------------------------------------------------------------------------

%! plan:print(+Target, +ModelAVL, +ProofAVL, +Plan, +TriggersAVL)
%
% Prints a plan. Triggers are required so the printer can explain assumptions
% (e.g. dependency cycles) when present.

plan:print(Target, ModelAVL, ProofAVL, Plan, TriggersAVL) :-
  plan:print(Target, ModelAVL, ProofAVL, Plan, plan:dry_run, TriggersAVL).


%! plan:print(+Target, +ModelAVL, +ProofAVL, +Plan, +Call, +TriggersAVL)
%
% As plan:print/5, with Call the per-step action goal (plan:dry_run for
% --pretend output).

plan:print(Target, ModelAVL, ProofAVL, Plan, Call, TriggersAVL) :-
  annotation:collect(ProofAVL, Annotations),
  annotation:blocker_notes(Annotations, BlockerNotes),
  plan:resolve_print_target(Target, ProofAVL, TargetPrint, TargetHeader),
  plan:print_header(TargetHeader),
  annotation:pre_actions(Annotations, PreActions),
  plan:print_plan_pre_actions(PreActions, 0, PreSteps),
  plan:inject_cycle_break_verifies(Annotations, Plan, AugmentedPlan),
  plan:print_body(TargetPrint, BlockerNotes, AugmentedPlan, Call, PreSteps, Steps),
  plan:print_footer(AugmentedPlan, ModelAVL, Steps, PreActions),
  warning:print_warnings(Annotations, ProofAVL, TriggersAVL).


%! plan:dry_run(+Step)
%
% Default execution strategy for building steps in a plan.

plan:dry_run(_Step) :- true.


% =============================================================================
%  Target resolution
% =============================================================================

%! plan:resolve_print_target(+Target0, +ProofAVL, -TargetPrint, -TargetHeader)
%
% Since the CLI defers candidate selection to the prover, the root target
% can be target(Q, Arg):run?{Ctx}. This resolves it to the chosen
% candidate's literal for display and highlighting.

plan:resolve_print_target(Target0, ProofAVL, TargetPrint, TargetHeader) :-
  ( is_list(Target0) ->
      findall(P-H,
              ( member(T, Target0),
                plan:resolve_print_target_one(T, ProofAVL, P, H)
              ),
              Pairs),
      findall(P, member(P-_, Pairs), TargetPrint),
      findall(H, member(_-H, Pairs), TargetHeader)
  ; plan:resolve_print_target_one(Target0, ProofAVL, TargetPrint, TargetHeader)
  ),
  !.

plan:resolve_print_target_one(Full0, ProofAVL, Full, HeaderFull) :-
  ( Full0 = target(Q, Arg):Action?{_Ctx0} ->
      ( plan:proof_rule_body_(ProofAVL, target(Q, Arg):Action, Body),
        plan:chosen_candidate_from_body(Action, Body, Repo, Ebuild) ->
          HeaderFull = Repo://(Ebuild:Action?{[]}),
          Full = Repo://(Ebuild:Action?{[]})
      ; HeaderFull = Full0,
        Full = Full0
      )
  ; HeaderFull = Full0,
    Full = Full0
  ),
  !.

plan:proof_rule_body_(ProofAVL, HeadCore, Body) :-
  get_assoc(rule(HeadCore), ProofAVL, dep(_Count, Body)?_Ctx),
  is_list(Body),
  !.

plan:chosen_candidate_from_body(run, Body, Repo, Ebuild) :-
  member(Repo://Ebuild:run?{_}, Body),
  !.
plan:chosen_candidate_from_body(fetchonly, Body, Repo, Ebuild) :-
  member(Repo://Ebuild:fetchonly?{_}, Body),
  !.
plan:chosen_candidate_from_body(uninstall, Body, Repo, Ebuild) :-
  member(Repo://Ebuild:uninstall?{_}, Body),
  !.


% =============================================================================
%  Blocker note annotations
% =============================================================================
%
% The blocker note map itself is built by annotation:collect/2 (single-pass
% proof traversal) and threaded to the step renderers inside the ps/3
% print-state term built by plan:print_body/6.

%! plan:format_blocker_origin(+Origin)
%
% Prints a blocker origin in a human-readable format (Category/Name).

plan:format_blocker_origin(Repo://Entry) :-
  ( cache:ordered_entry(Repo, Entry, C, N, _)
  -> message:print(C), message:print('/'), message:print(N)
  ;  message:print(Repo://Entry)
  ),
  !.
plan:format_blocker_origin(Origin) :-
  message:print(Origin).


plan:print_newuse_note_if_any(update, Context) :-
  memberchk(rebuild_reason(newuse), Context),
  !,
  message:color(orange),
  message:print(' (newuse)'),
  message:color(normal).
plan:print_newuse_note_if_any(update, Context) :-
  memberchk(rebuild_reason(changeduse), Context),
  !,
  message:color(orange),
  message:print(' (changed-use)'),
  message:color(normal).
plan:print_newuse_note_if_any(update, Context) :-
  memberchk(rebuild_reason(changedslot), Context),
  !,
  message:color(orange),
  message:print(' (changed-slot)'),
  message:color(normal).
plan:print_newuse_note_if_any(update, Context) :-
  memberchk(rebuild_reason(rebuilt_binary), Context),
  !,
  message:color(orange),
  message:print(' (rebuilt-binary)'),
  message:color(normal).
plan:print_newuse_note_if_any(update, Context) :-
  memberchk(rebuild_reason(subslot_change(Provider, _Old, _New)), Context),
  !,
  message:color(orange),
  message:print(' (abi-rebuild: '),
  plan:format_blocker_origin(Provider),
  message:print(')'),
  message:color(normal).
plan:print_newuse_note_if_any(update, Context) :-
  memberchk(rebuild_reason(rebuild_if_unbuilt(Provider)), Context),
  !,
  message:color(orange),
  message:print(' (rebuild-if-unbuilt: '),
  plan:format_blocker_origin(Provider),
  message:print(')'),
  message:color(normal).
plan:print_newuse_note_if_any(_Action, _Context).

plan:print_blocker_note_if_any(ps(_, Notes, _), Action, Repository, Entry) :-
  ( ( Action == install ; Action == run ),
    plan:action_phase(Action, Phase),
    ( cache:ordered_entry(Repository, Entry, C, N, _) ->
        true
    ; query:search([category(C),name(N)], Repository://Entry)
    ),
    get_assoc(key(C,N,Phase), Notes, note(Strength, Origin))
  ->
    message:color(lightgray),
    message:print(' ('),
    message:color(lightred),
    message:print('blocked'),
    message:color(lightgray),
    message:print(': '),
    message:color(lightred),
    ( Strength == strong -> message:print('hard') ; message:print('soft') ),
    message:color(lightgray),
    message:print(' by '),
    ( Origin == unknown ->
        message:print('unknown')
    ; message:color(green),
      plan:format_blocker_origin(Origin),
      message:color(lightgray)
    ),
    message:print(')'),
    message:color(normal)
  ; true
  ).

plan:action_phase(run, run) :- !.
plan:action_phase(install, install) :- !.
plan:action_phase(reinstall, install) :- !.
plan:action_phase(update, install) :- !.
plan:action_phase(download, other) :- !.
plan:action_phase(fetchonly, other) :- !.
plan:action_phase(_Other, other).


% -----------------------------------------------------------------------------
%  Plan printing
% -----------------------------------------------------------------------------

%! plan:printable_element(+State, +Literal)
%
% Declares which Literals are printable. State is the ps/3 print-state term
% (see plan:print_body/6); only the planned-package suppression clauses
% consult it. `--fetchonly` keeps downloads (and uri/verify/assumptions)
% and hides merge-phase actions; pre-actions are printed separately.
%
% Package-action matching goes through prover:rule_parts/4 and
% prover:canon_literal/3 — the same path the footer and Gantt chart use —
% so context-free heads (`Repo://Entry:install`) and parenthesized /
% double-wrapped `?{Ctx}` forms stay visible. Rigid `Action?{Ctx}`
% unification dropped those shapes, which is what produced the
% docker-29.8.0 merge page: 57 actions counted, 2 steps rendered.

plan:printable_element(_, Rule) :-
  plan:fetchonly_hidden_element(Rule),
  !,
  fail.
plan:printable_element(_,rule(uri(_,_,_),_)) :- !.
plan:printable_element(_,rule(uri(_),_)) :- !.
plan:printable_element(State, Rule) :-
  plan:rule_pkg_info(Rule, Action, Body, Kind, Core),
  plan:printable_kind_action(Kind, Core, Action),
  ( Kind == regular,
    memberchk(Action, [update, downgrade]),
    plan:wrapper_update_body(Body, Action)
  -> fail
  ; Kind == domain_assumption,
    plan:suppress_assumed_planned(State, Core)
  -> fail
  ; true
  ),
  !.
% Suppress any remaining cycle-break types from plan display
% (including grouped_package_dependency — always benign via heuristic:cycle_benign/2).
plan:printable_element(_,assumed(rule(_,_))) :- !, fail.


%! plan:fetchonly_hidden_element(+Literal) is semidet.
%
% True when Literal is a concrete merge-phase plan rule that `--fetchonly`
% must not print. Head shape is normalised via rule_pkg_info/5 so
% context-free and double-wrapped actions hide the same way as `?{Ctx}`.

plan:fetchonly_hidden_element(Rule) :-
  plan:rule_pkg_info(Rule, Action, _Body, regular, _Repo://_Entry:_),
  preference:fetchonly_skips_action(Action).


%! plan:rule_pkg_info(+Rule, -Action, -Body, -Kind, -Core) is semidet.
%
% Destructure a plan rule into its action, body, kind and canonical core
% when the head is a package or dependency action (`Repo://Entry:Action`
% or `grouped_package_dependency(...):Phase` / `package_dependency(...):Phase`).

plan:rule_pkg_info(Rule, Action, Body, Kind, Core) :-
  prover:rule_parts(Rule, Head0, Body, Kind),
  prover:canon_literal(Head0, Core, _),
  ( Core = _Repo://_Entry:Action
  ; Core = grouped_package_dependency(_,_,_,_):Action
  ; Core = grouped_package_dependency(_,_,_):Action
  ; Core = package_dependency(_,_,_,_,_,_,_,_):Action
  ).


%! plan:printable_kind_action(+Kind, +Core, +Action) is semidet.
%
% Which (kind, core, action) triples belong on the merge list.

plan:printable_kind_action(cycle_break, _Repo://_Entry:Action, Action) :-
  memberchk(Action, [install, run, fetchonly]),
  !.
plan:printable_kind_action(cycle_break, package_dependency(_,_,_,_,_,_,_,_):Action, Action) :-
  memberchk(Action, [install, run]),
  !.
plan:printable_kind_action(cycle_break, _, _) :-
  !,
  fail.
plan:printable_kind_action(domain_assumption, _Repo://_Entry:_, _) :-
  !.
plan:printable_kind_action(domain_assumption, grouped_package_dependency(_,_,_,_):Action, Action) :-
  memberchk(Action, [install, run]),
  !.
plan:printable_kind_action(domain_assumption, grouped_package_dependency(_,_,_):Action, Action) :-
  memberchk(Action, [install, run]),
  !.
plan:printable_kind_action(domain_assumption, package_dependency(_,_,_,_,_,_,_,_):Action, Action) :-
  memberchk(Action, [install, run]),
  !.
plan:printable_kind_action(domain_assumption, _, _) :-
  !,
  fail.
plan:printable_kind_action(regular, _Core, Action) :-
  plan:printable_pkg_action(Action).


%! plan:printable_pkg_action(+Action) is semidet.
%
% Concrete merge-list package actions the printer will show.

plan:printable_pkg_action(Action) :-
  memberchk(Action, [run, download, fetchonly, install, reinstall,
                     uninstall, update, downgrade, upgrade]).


%! plan:wrapper_update_body(+Body, +Action) is semidet.
%
% True when Body already schedules the transactional update/downgrade on a
% chosen replacement version, so the wrapper target should be hidden.

plan:wrapper_update_body(Body, Action) :-
  member(Dep, Body),
  prover:canon_literal(Dep, _NewRepo://_NewEntry:Action, _).


%! plan:suppress_assumed_planned(+State, +Core) is semidet.
%
% Hide an assumed dependency verify when a concrete ebuild for the same
% package is already scheduled in the plan.

plan:suppress_assumed_planned(State, grouped_package_dependency(_, C, N, _):Phase) :-
  ( Phase == install ; Phase == run ),
  plan:planned_pkg(State, Phase, C, N).
plan:suppress_assumed_planned(State, grouped_package_dependency(C, N, _):Phase) :-
  ( Phase == install ; Phase == run ),
  plan:planned_pkg(State, Phase, C, N).
plan:suppress_assumed_planned(State, package_dependency(Phase, no, C, N, _, _, _, _):Phase) :-
  ( Phase == install ; Phase == run ),
  plan:planned_pkg(State, Phase, C, N).


%! plan:ctx_list(+Ctx0, -Ctx) is det.
%
% Normalise canon_literal's `{}` (no proof context) to `[]` so renderers
% that expect a list (`memberchk/2`, `is_list/1`) keep working.

plan:ctx_list({}, []) :- !.
plan:ctx_list(Ctx, Ctx) :- is_list(Ctx), !.
plan:ctx_list(_, []).


%! plan:canonicalize_print_rule(+Rule, -Canon) is semidet.
%
% Rewrite a package/dependency rule whose head is a canon_literal variant
% (context-free, parenthesized, or double-wrapped `?{Ctx}`) into the
% `Repo://(Entry:Action?{Ctx})` form the print_element clauses already
% handle (dependency cores stay `Core?{Ctx}`).

plan:canonicalize_print_rule(Rule, Canon) :-
  prover:rule_parts(Rule, Head0, Body, Kind),
  prover:canon_literal(Head0, Core, Ctx0),
  plan:canonical_print_core(Core),
  plan:ctx_list(Ctx0, Ctx),
  plan:canonical_print_head(Core, Ctx, CanonicalHead),
  Head0 \== CanonicalHead,
  plan:rebuild_print_rule(Kind, CanonicalHead, Body, Canon).


%! plan:canonical_print_head(+Core, +Ctx, -Head) is det.
%
% Rebuild the print-element head. Package actions must be
% `Repo://(Entry:Action?{Ctx})` — the form the print_element clauses
% match. `(Repo://Entry:Action)?{Ctx}` looks equivalent but is a
% different principal functor (`?` outside `://`).

plan:canonical_print_head(Repo://Entry:Action, Ctx, Repo://(Entry:Action?{Ctx})) :-
  !.
plan:canonical_print_head(Core, Ctx, Core?{Ctx}).


%! plan:canonical_print_core(+Core) is semidet.
%
% Heads the merge printer can rewrite into `Core?{Ctx}`.

plan:canonical_print_core(_Repo://_Entry:_Action).
plan:canonical_print_core(grouped_package_dependency(_,_,_,_):_Phase).
plan:canonical_print_core(grouped_package_dependency(_,_,_):_Phase).
plan:canonical_print_core(package_dependency(_,_,_,_,_,_,_,_):_Phase).


%! plan:rebuild_print_rule(+Kind, +Head, +Body, -Rule) is det.
%
% Rebuild a full-format rule from a canonical head and the original body.

plan:rebuild_print_rule(regular, Head, Body, rule(Head, Body)).
plan:rebuild_print_rule(domain_assumption, Head, Body, rule(assumed(Head), Body)).
plan:rebuild_print_rule(cycle_break, Head, Body, assumed(rule(Head, Body))).


% Uncomment if you want 'confirm' steps shown in the plan:
% plan:printable_element(_,rule(package_dependency(run,_,_,_,_,_,_,_),_)) :- !.


%! plan:display_order(-Groups)
%
% Display order of the elements within one plan step, first group
% printed first. Elements whose kinds share a group keep the orderer's
% relative order (merge-order bias / refcount priority). The position of
% a group in this list is the sort key; nothing else encodes the order.
% Run comes after install within a step.

plan:display_order([[assumed, provide],
                    [fetch, confirm],
                    [verify],
                    [download],
                    [fetchonly, install],
                    [run, reinstall, uninstall, update, downgrade, upgrade],
                    [other]]).


%! plan:element_kind(+Literal, -Kind) is det.
%
% Kind of a plan element, as named in display_order/1.

plan:element_kind(assumed(_),                                     assumed)   :- !.
plan:element_kind(rule(assumed(_),_),                             assumed)   :- !.
plan:element_kind(rule(uri(_),_),                                 provide)   :- !.
plan:element_kind(rule(uri(_,_,_),_),                             fetch)     :- !.
plan:element_kind(rule(package_dependency(_,_,_,_,_,_,_,_),_),    confirm)   :- !.
plan:element_kind(Rule, Kind) :-
  plan:rule_pkg_info(Rule, Action, _Body, _RKind, _Repo://_Entry:_),
  memberchk(Action, [verify, run, download, fetchonly, install,
                     reinstall, uninstall, update, downgrade, upgrade]),
  Kind = Action,
  !.
plan:element_kind(_,                                              other).


%! plan:element_position(+Literal, -Pos) is det.
%
% Position of the element's display group in display_order/1.

plan:element_position(Literal, Pos) :-
  plan:element_kind(Literal, Kind),
  plan:display_order(Groups),
  nth0(Pos, Groups, Group),
  memberchk(Kind, Group),
  !.


%! plan:sort_by_display_order(+Step, -Sorted)
%
% Sort a step's elements by display_order/1, preserving the orderer's
% relative order within a display group.

plan:sort_by_display_order(Step, Sorted) :-
  plan:tag_with_position_index(Step, 0, Tagged),
  keysort(Tagged, SortedTagged),
  findall(Rule, member(_-Rule, SortedTagged), Sorted).

plan:tag_with_position_index([], _, []) :- !.
plan:tag_with_position_index([R|Rs], I, [(P-I)-R|Rest]) :-
  plan:element_position(R, P),
  I1 is I + 1,
  plan:tag_with_position_index(Rs, I1, Rest).


%! plan:print_element(+State, +Printable)
%
% Prints a printable Literal. State is the ps/3 print-state term carrying
% the resolved print target, blocker notes and planned-package set.

plan:print_element(State, Rule) :-
  plan:canonicalize_print_rule(Rule, Canon),
  !,
  plan:print_element(State, Canon).

plan:print_element(_,rule(package_dependency(run_post,_,_C,_N,_,_,_,_),[Repository://Entry:_Action?{_Context}])) :-
  !,
  message:color(cyan),
  message:print('confirm'),
  message:color(green),
  message:column(24,Repository://Entry),
  message:color(normal).



% ---------------------------------------------
% CASE: simple package, is a target of the plan
% ---------------------------------------------

plan:print_element(State,rule(Repository://Entry:Action?{Context},_Body)) :-
  State = ps(Target, _, _),
  ( member(Repository://Entry:Action?_,Target)
  ; memberchk(Action, [update,downgrade]),
    memberchk(replaces(OldRepo://OldEntry), Context),
    ( member(OldRepo://OldEntry:update?_, Target)
    ; member(OldRepo://OldEntry:downgrade?_, Target)
    )
  ),
  !,
  %message:color(cyan),
  message:bubble(green,Action),
  message:style(bold),
  message:color(green),
  message:column(24,Repository://Entry),
  ( memberchk(Action, [update,downgrade]),
    memberchk(replaces(OldRepo2://OldEntry2), Context)
  -> message:color(lightgray),
     message:print(' (replaces '),
     message:color(green),
     message:print(OldRepo2://OldEntry2),
     message:color(lightgray),
     message:print(')'),
     message:color(normal)
  ; true
  ),
  % Ensure inline notes (e.g. blocker annotations) don't inherit the bold style
  % used for target entries.
  message:style(normal),
  plan:print_blocker_note_if_any(State, Action, Repository, Entry),
  plan:print_newuse_note_if_any(Action, Context),
  message:color(normal),
  useflags:print_config(Repository://Entry:Action?{Context}).


% -------------------------------------------------------------------
% CASE: package resolved via keyword_acceptance fallback (suggestion)
% -------------------------------------------------------------------

plan:print_element(_,rule(Repository://Entry:Action?{Context},_Body)) :-
  is_list(Context),
  memberchk(suggestion(accept_keyword, K), Context),
  !,
  warning:keyword_atom(K, KAtom),
  message:color(cyan),
  message:print(Action),
  message:color(green),
  message:column(24,Repository://Entry),
  message:color(darkgray),
  format(atom(Msg), ' (~w)', [KAtom]),
  message:print(Msg),
  message:color(normal),
  useflags:print_config(Repository://Entry:Action?{Context}).


% -----------------------------------------------------------
% CASE: package resolved via license acceptance suggestion
% -----------------------------------------------------------

plan:print_element(_,rule(Repository://Entry:Action?{Context},_Body)) :-
  is_list(Context),
  memberchk(suggestion(accept_license, _), Context),
  !,
  message:color(cyan),
  message:print(Action),
  message:color(green),
  message:column(24,Repository://Entry),
  message:color(darkgray),
  message:print(' (license)'),
  message:color(normal),
  useflags:print_config(Repository://Entry:Action?{Context}).


% -----------------------------------------------------------
% CASE: package resolved via unmask fallback (suggestion)
% -----------------------------------------------------------

plan:print_element(_,rule(Repository://Entry:Action?{Context},_Body)) :-
  is_list(Context),
  memberchk(suggestion(unmask, _), Context),
  \+ memberchk(suggestion(accept_license, _), Context),
  !,
  message:color(cyan),
  message:print(Action),
  message:color(green),
  message:column(24,Repository://Entry),
  message:color(darkgray),
  message:print(' (unmasked)'),
  message:color(normal),
  useflags:print_config(Repository://Entry:Action?{Context}).


% -----------------------------------------------------------
% CASE: package resolved via USE change (build_with_use)
% -----------------------------------------------------------

plan:print_element(_,rule(Repository://Entry:Action?{Context},_Body)) :-
  is_list(Context),
  memberchk(suggestion(use_change, _, _Changes), Context),
  \+ memberchk(suggestion(unmask, _), Context),
  \+ memberchk(suggestion(accept_license, _), Context),
  \+ memberchk(suggestion(accept_keyword, _), Context),
  !,
  message:color(cyan),
  message:print(Action),
  message:color(green),
  message:column(24,Repository://Entry),
  message:color(darkgray),
  message:print(' (USE modified)'),
  message:color(normal),
  useflags:print_config(Repository://Entry:Action?{Context}).


% -------------------------------------------------
% CASE: simple package, is not a target of the plan
% -------------------------------------------------

plan:print_element(State,rule(Repository://Entry:Action?{Context},_)) :-
  message:color(cyan),
  message:print(Action),
  message:color(green),
  message:column(24,Repository://Entry),
  ( memberchk(Action, [update,downgrade]),
    memberchk(replaces(OldRepo://OldEntry), Context)
  -> message:color(lightgray),
     message:print(' (replaces '),
     message:color(green),
     message:print(OldRepo://OldEntry),
     message:color(lightgray),
     message:print(')'),
     message:color(normal)
  ; true
  ),
  plan:print_blocker_note_if_any(State, Action, Repository, Entry),
  plan:print_newuse_note_if_any(Action, Context),
  message:color(normal),
  useflags:print_config(Repository://Entry:Action?{Context}),
  !.


% --------------------------------------------------------------
% CASE: verify that packages that need to be running are running
% --------------------------------------------------------------

plan:print_element(_,rule(package_dependency(run,_,_C,_N,_,_,_,_),[Repository://Entry:_Action?{_Context}])) :-
  !,
  message:color(cyan),
  message:print('confirm'),
  message:color(green),
  message:column(24,Repository://Entry),
  message:color(normal).


% ----------------
% CASE: a download
% ----------------

plan:print_element(_,rule(uri(Protocol,Remote,_Local),_)) :-
  !,
  message:color(cyan),
  message:print('fetch'),
  message:color(green),
  message:column(24,Protocol://Remote),
  message:color(normal).

plan:print_element(_,rule(uri(Local),_)) :-
  !,
  message:color(cyan),
  message:print('provide'),
  message:color(green),
  message:column(24,Local),
  message:color(normal).


% -----------------------------------------------------------------------------
% CASE: assumed dependencies (domain assumptions) — table-driven
% -----------------------------------------------------------------------------
%
% One parametric clause per head shape; the assumption_reason -> display
% mapping lives in plan:assumption_display/5 below (one row per reason),
% mirroring the taxonomy in Printer/Plan/assumption.pl.

% keyword_filtered is special-cased: it shows the keyword carried by the
% context suggestion when available, and prints its note in yellow.

plan:print_element(_,rule(assumed(grouped_package_dependency(C,N,_Deps):_Phase?{Context}),[])) :-
  is_list(Context),
  memberchk(assumption_reason(keyword_filtered), Context),
  !,
  message:bubble(yellow,'verify'),
  message:color(yellow),
  atomic_list_concat([C,'/',N],P),
  message:column(24,P),
  ( memberchk(suggestion(accept_keyword, K), Context) ->
      warning:keyword_atom(K, KAtom),
      format(atom(Msg), ' (requires ~w)', [KAtom]),
      message:print(Msg)
  ; message:print(' (keyword filtered, assumed accepted)')
  ),
  message:color(normal).

% Any reason covered by the display table.

plan:print_element(_,rule(assumed(grouped_package_dependency(C,N,_Deps):Phase?{Context}),[])) :-
  is_list(Context),
  memberchk(assumption_reason(Reason), Context),
  plan:assumption_display(Reason, Phase, Bubble, NameColor, Text),
  !,
  plan:print_assumed_dep_verify(Bubble, NameColor, darkgray, C, N, Text).

% Fallback: a dependency on a non-existent package.

plan:print_element(_,rule(assumed(grouped_package_dependency(C,N,_Deps):Phase?{_Context}),[])) :-
  plan:assumed_phase_word(Phase, Word),
  format(atom(Text), 'non-existent, assumed ~w', [Word]),
  plan:print_assumed_dep_verify(red, red, red, C, N, Text).

plan:print_element(_,rule(assumed(package_dependency(Phase,no,C,N,_,_,_,_):Phase?{_Context}),[])) :- % legacy form
  plan:assumed_phase_word(Phase, Word),
  format(atom(Text), 'non-existent, assumed ~w', [Word]),
  plan:print_assumed_dep_verify(red, red, red, C, N, Text).


% -----------------------------------------------------------------------------
% CASE: assumed entry-level actions (domain assumptions)
% -----------------------------------------------------------------------------

plan:print_element(_,rule(assumed(Repository://Entry:unmask?{_Context}),_Body)) :-
  !,
  plan:print_assumed_entry_verify(Repository://Entry, 'masked, assumed unmasked').

plan:print_element(_,rule(assumed(Repository://Entry:Action?{_Context}),_Body)) :-
  ( plan:assumed_phase_word(Action, Word) -> true ; Word = Action ),
  format(atom(Text), 'assumed ~w', [Word]),
  plan:print_assumed_entry_verify(Repository://Entry, Text).


% -----------------------------------------------------------------------------
% CASE: prover cycle-break assumptions (assumed(rule(...)))
% -----------------------------------------------------------------------------

plan:print_element(_,assumed(rule(Repository://Entry:Action?{_Context},_Body))) :-
  plan:assumed_phase_word(Action, Word),
  !,
  format(atom(Text), 'assumed ~w', [Word]),
  plan:print_assumed_entry_verify(Repository://Entry, Text).

plan:print_element(_,assumed(rule(package_dependency(Phase,_,C,N,_,_,_,_):_Action?{_Context},_Body))) :-
  plan:assumed_phase_word(Phase, Word),
  !,
  format(atom(Text), 'assumed ~w', [Word]),
  plan:print_assumed_dep_verify(red, red, red, C, N, Text).


% -----------------------------------------------------------------------------
% Assumption display table and shared verify-line renderers
% -----------------------------------------------------------------------------

%! plan:assumption_display(+Reason, +Phase, -Bubble, -NameColor, -Text)
%
% Display table for assumed-dependency verify lines: maps an
% assumption_reason (as found in the literal context) and the dependency
% phase (install/run) to the bubble colour, package-name colour, and note
% text. Adding a new reason means adding one row here (and, for statistics
% bucketing, one row in assumption:assumption_reason_type/2).

plan:assumption_display(masked, _Phase, red, green, 'masked, requires unmask') :- !.
plan:assumption_display(Reason, Phase, yellow, yellow, Text) :-
  plan:assumption_reason_note(Reason, Note),
  plan:assumed_phase_word(Phase, Word),
  format(atom(Text), '~w, assumed ~w', [Note, Word]).


%! plan:assumption_reason_note(+Reason, -Note)
%
% Short cause text per assumption reason; the phase word is appended by
% plan:assumption_display/5.

plan:assumption_reason_note(version_conflict,         'version conflict').
plan:assumption_reason_note(version_conflict(_),      'version conflict').
plan:assumption_reason_note(version_no_candidate,     'version unavailable').
plan:assumption_reason_note(version_no_candidate(_,_),'version unavailable').
plan:assumption_reason_note(slot_unsatisfied,         'slot unavailable').
plan:assumption_reason_note(installed_required,       'requires installed').
plan:assumption_reason_note(unsatisfied_constraints,  'unsatisfied constraints').


%! plan:assumed_phase_word(+Phase, -Word)
%
% Past-tense word for an assumed action/phase.

plan:assumed_phase_word(install,   installed).
plan:assumed_phase_word(run,       running).
plan:assumed_phase_word(fetchonly, fetched).


%! plan:print_assumed_dep_verify(+Bubble, +NameColor, +TextColor, +C, +N, +Text)
%
% Render a verify line for an assumed dependency: coloured bubble,
% category/name column, and a parenthesised note.

plan:print_assumed_dep_verify(Bubble, NameColor, TextColor, C, N, Text) :-
  plan:verify_bubble(Bubble),
  plan:verify_color(NameColor),
  atomic_list_concat([C,'/',N],P),
  message:column(24,P),
  plan:verify_color(TextColor),
  format(atom(Msg), ' (~w)', [Text]),
  message:print(Msg),
  message:color(normal).


%! plan:verify_bubble(+Color)
%
% Runtime colour dispatch for the 'verify' bubble. The message:bubble/2
% and message:color/1 macros are expanded at compile time
% (user:goal_expansion in Output/message.pl) and must be called with a
% constant colour atom, so each colour gets its own clause here.

plan:verify_bubble(red)    :- message:bubble(red,'verify').
plan:verify_bubble(yellow) :- message:bubble(yellow,'verify').


%! plan:verify_color(+Color)
%
% Runtime colour dispatch for verify-line text (see plan:verify_bubble/1).

plan:verify_color(red)      :- message:color(red).
plan:verify_color(green)    :- message:color(green).
plan:verify_color(yellow)   :- message:color(yellow).
plan:verify_color(darkgray) :- message:color(darkgray).


%! plan:print_assumed_entry_verify(+RepositoryEntry, +Text)
%
% Render a verify line for an assumed entry-level action (red bubble,
% red entry column, parenthesised note).

plan:print_assumed_entry_verify(RepositoryEntry, Text) :-
  message:bubble(red,'verify'),
  message:color(red),
  message:column(24,RepositoryEntry),
  format(atom(Msg), ' (~w)', [Text]),
  message:print(Msg),
  message:color(normal).


%! plan:print_header(+Target)
%
% Prints the header for a given target

plan:print_header(Target) :-
  nl,
  message:header('Emerging ',Target),
  message:color(green),
  message:print('These are the packages that would be merged, in order:'),nl,
  nl,
  message:color(normal),
  message:print('Calculating dependencies... done!'),nl,
  nl.


%! plan:print_body(+Target,+BlockerNotes,+Plan,+Call,+StartStep,-Steps)
%
% Prints the body for a given plan, starting step count from StartStep.
% Bundles the resolved print target, blocker notes and planned-package set
% into a single ps/3 print-state term threaded through the step renderers
% (no global variables involved).
plan:print_body(Target, BlockerNotes, Plan, Call, StartStep, Steps) :-
  plan:build_planned_pkg_set(Plan, PlannedSet),
  State = ps(Target, BlockerNotes, PlannedSet),
  plan:print_steps_in_plan(State, Plan, Call, StartStep, Steps).

% -----------------------------------------------------------------------------
%  Pre-actions: unmask / license / keyword / USE-change before the plan
% -----------------------------------------------------------------------------
%
% Pre-actions are collected by annotation:collect/2 (single-pass proof
% traversal) and exposed via annotation:pre_actions/2.

%! plan:inject_cycle_break_verifies(+Annotations, +Plan, -AugmentedPlan)
%
% Takes the prover cycle-break assumptions collected by annotation:collect/2
% and injects synthetic verify elements into the first plan step.

plan:inject_cycle_break_verifies(Annotations, Plan, AugmentedPlan) :-
  annotation:cycle_break_rules(Annotations, CycleBreaks),
  ( CycleBreaks == []
  -> AugmentedPlan = Plan
  ; Plan = [FirstStep|RestSteps]
  -> append(CycleBreaks, FirstStep, NewFirstStep),
     AugmentedPlan = [NewFirstStep|RestSteps]
  ; AugmentedPlan = [CycleBreaks|Plan]
  ).


%! plan:print_plan_pre_actions(+PreActions, +StepIn, -StepOut)
%
% Prints pre-plan actions (unmask, keyword acceptance) as steps.

plan:print_plan_pre_actions([], S, S) :- !.
plan:print_plan_pre_actions(PreActions, StepIn, StepOut) :-
  StepNum is StepIn + 1,
  format(atom(AtomStepNum), '~t~0f~2|', [StepNum]),
  format(atom(StepLabel), 'step ~a', [AtomStepNum]),
  write(' └─'),
  message:bubble(darkgray, StepLabel),
  write('─┤ '),
  plan:print_pre_action_first(PreActions),
  nl, nl,
  StepOut = StepNum.

plan:print_pre_action_first([Action|Rest]) :-
  plan:print_pre_action(Action),
  forall(member(A, Rest),
         ( nl,
           write('             │ '),
           plan:print_pre_action(A)
         )).

plan:print_pre_action(Action) :-
  plan:print_pre_action_core(Action, true).


%! plan:print_pre_action_core(+PreAction, +ShowUseFlags) is det.
%
% Render a single pre-action (unmask / accept_license / accept_keyword /
% use_change) as a coloured bubble + target column. Shared by the plan
% printer and the build display (display:print_pre_action/1). When
% ShowUseFlags is true the use_change flags are wrapped inline (plan
% output); the build display passes false to keep its right-edge layout.

plan:print_pre_action_core(unmask(R, E, _C, _N), _ShowUseFlags) :-
  message:bubble(orange, unmask),
  message:color(green),
  message:column(24, R://E),
  message:color(normal).

plan:print_pre_action_core(accept_license(R, E, _C, _N), _ShowUseFlags) :-
  message:bubble(orange, license),
  message:color(green),
  message:column(24, R://E),
  message:color(normal).

plan:print_pre_action_core(accept_keyword(R, E, _C, _N, K), _ShowUseFlags) :-
  warning:keyword_atom(K, KAtom),
  message:bubble(orange, keyword),
  message:color(green),
  message:column(24, R://E),
  message:color(darkgray),
  format(atom(Msg), ' (~w)', [KAtom]),
  message:print(Msg),
  message:color(normal).

plan:print_pre_action_core(use_change(R, E, _C, _N, Changes), ShowUseFlags) :-
  message:bubble(orange, useflag),
  message:color(green),
  message:column(24, R://E),
  ( ShowUseFlags == true
  -> message:color(darkgray),
     plan:print_use_change_flags_wrapped(Changes),
     message:color(normal)
  ;  message:color(normal)
  ).

plan:print_pre_action_core(kernel_config(Options, _Evidence), _ShowUseFlags) :-
  plan:kernel_config_atom(Options, OptAtom),
  message:bubble(orange, kernel),
  message:color(green),
  message:column(24, OptAtom),
  message:color(normal).


%! plan:kernel_config_atom(+Options, -Atom) is det.
%
% Human-readable rendering of a learned kernel-config option list, e.g.
% "CONFIG_SECURITY_APPARMOR=y CONFIG_FOO=n" (portage-ng#105).

plan:kernel_config_atom(Options, Atom) :-
  findall(Tok,
          ( member(config(Name, State), Options),
            format(atom(Tok), '~w=~w', [Name, State]) ),
          Toks),
  atomic_list_concat(Toks, ' ', Atom).


plan:format_use_change_flags(Changes, FlagsStr) :-
  findall(A, ( member(use_change(F, enable), Changes), atom_string(F, A) ), PosAtoms),
  findall(A, ( member(use_change(F, disable), Changes), format(atom(A), '-~w', [F]) ), NegAtoms),
  append(PosAtoms, NegAtoms, AllFlags),
  atomic_list_concat(AllFlags, ' ', FlagsStr).


%! plan:print_use_change_flags_wrapped(+Changes)
%
% Prints USE change flags with tty-width-aware wrapping inside parentheses.
% On wrap, continues with the style-appropriate │ prefix aligned to the
% opening parenthesis column.

plan:print_use_change_flags_wrapped(Changes) :-
  plan:use_change_flag_atoms(Changes, FlagAtoms),
  ( FlagAtoms == []
  -> true
  ;  write(' ('),
     catch(
       ( config:printing_tty_size(_, TermWidth),
         line_position(current_output, StartCol),
         plan:print_flag_atoms_wrapped(FlagAtoms, StartCol, TermWidth, StartCol, true)
       ),
       _,
       ( plan:print_flag_atoms_unwrapped(FlagAtoms) )
     ),
     write(')')
  ).

plan:use_change_flag_atoms(Changes, FlagAtoms) :-
  findall(A, ( member(use_change(F, enable), Changes), atom_string(F, A) ), PosAtoms),
  findall(A, ( member(use_change(F, disable), Changes), format(atom(A), '-~w', [F]) ), NegAtoms),
  append(PosAtoms, NegAtoms, FlagAtoms).

plan:print_flag_atoms_unwrapped([]) :- !.
plan:print_flag_atoms_unwrapped([F]) :- !, write(F).
plan:print_flag_atoms_unwrapped([F|Rest]) :-
  write(F), write(' '),
  plan:print_flag_atoms_unwrapped(Rest).

plan:print_flag_atoms_wrapped([], _, _, _, _) :- !.
plan:print_flag_atoms_wrapped([F|Rest], StartCol, TermWidth, ColIn, IsFirst) :-
  atom_length(F, FLen),
  ( IsFirst -> SpaceLen = 0 ; SpaceLen = 1 ),
  ( ColIn + SpaceLen + FLen > TermWidth
  -> plan:print_pre_action_continuation(StartCol),
     write(F),
     ColOut is StartCol + FLen
  ;  ( IsFirst -> true ; write(' ') ),
     write(F),
     ColOut is ColIn + SpaceLen + FLen
  ),
  plan:print_flag_atoms_wrapped(Rest, StartCol, TermWidth, ColOut, false).

plan:print_pre_action_continuation(StartColumn) :-
  nl,
  ( config:printing_style('short')  ->
      write('             │ '),
      Indent is StartColumn - 1,
      message:column(Indent, '')
  ; config:printing_style('column') ->
      write('             │ '),
      Indent is StartColumn - 1,
      message:column(Indent, '')
  ; config:printing_style('fancy')  ->
      write('             │                    '),
      message:color(darkgray),
      write('│ '),
      Indent is StartColumn - 1,
      message:column(Indent, '')
  ; true
  ).


% Build a set of planned packages (category/name) for actions install/run.
% This allows suppressing "assumed dependency verify" lines when a concrete
% ebuild for the same package is already scheduled in the plan.
plan:build_planned_pkg_set(Plan, Set) :-
  empty_assoc(Empty),
  foldl(plan:build_planned_pkg_set_step, Plan, Empty, Set).

plan:build_planned_pkg_set_step(Step, In, Out) :-
  foldl(plan:build_planned_pkg_set_rule, Step, In, Out).

plan:build_planned_pkg_set_rule(Rule, In, Out) :-
  ( Rule = rule(HeadWithCtx, _Body)
  ; Rule = rule(assumed(HeadWithCtx), _Body)
  ),
  prover:canon_literal(HeadWithCtx, Head, _),
  ( Head = Repo://Entry:Action,
    ( Action == run ; Action == install ),
    cache:ordered_entry(Repo, Entry, C, N, _),
    Key = Action-C-N,
    ( get_assoc(Key, In, true) -> Out = In ; put_assoc(Key, In, true, Out) )
  ; Out = In
  ),
  !.
plan:build_planned_pkg_set_rule(_Other, Set, Set).

plan:planned_pkg(ps(_, _, Set), Action, C, N) :-
  get_assoc(Action-C-N, Set, true).

plan:is_run_cycle_break(Content) :-
  ( prover:canon_literal(Content, Core, _Ctx) -> true ; Core = Content ),
  Core = _ : run.

plan:print_cycle_break_detail(Content) :-
  ( prover:canon_literal(Content, Core, _Ctx) -> true ; Core = Content ),
  ( config:print_prover_cycles_style(flat) ->
      message:color(darkgray),
      message:print('  '),
      message:print(Core),
      message:color(normal),
      nl
  ; message:color(lightred),
    message:style(bold),
    message:print('- Cycle break: '),
    message:style(normal),
    message:color(normal),
    nl,
    message:print('  '),
    message:print(Core),
    nl
  ).


%! plan:print_steps_in_plan(+State,+Plan,+Call,+Count,-NewCount)
%
% Print the steps in a plan.

plan:print_steps_in_plan(_, [], _, Count, Count) :- !.

plan:print_steps_in_plan(State, [Step|Rest], Call, Count, CountFinal) :-
  plan:sort_by_display_order(Step, SortedRules),
  plan:print_first_in_step(State, SortedRules, Count, CountNew),
  call(Call, SortedRules), !,
  plan:print_steps_in_plan(State, Rest, Call, CountNew, CountFinal).


%! plan:print_first_in_step(+State,+Step,+Count,-NewCount)
%
% Print a step in a plan
plan:print_first_in_step(_,[],Count,Count) :- !.

plan:print_first_in_step(State,[Rule|Rest],Count,NewCount) :-
  plan:printable_element(State,Rule),
  NewCount is Count + 1,
  format(atom(AtomNewCount),'~t~0f~2|',[NewCount]),
  format(atom(StepNewCount),'step ~a',[AtomNewCount]),
  !,
  write(' └─'),
  message:bubble(darkgray,StepNewCount),
  write('─┤ '),
  plan:print_element_safe(State,Rule),
  plan:print_next_in_step(State,Rest).

plan:print_first_in_step(State,[_|Rest],Count,NewCount) :-
  plan:print_first_in_step(State,Rest,Count,NewCount).


%! plan:print_next_in_step(+State,+Step)
%
% Print a step in a plan
plan:print_next_in_step(_,[]) :- nl,nl,!.

plan:print_next_in_step(State,[Rule|Rest]) :-
  plan:printable_element(State,Rule),
  !,
  nl,
  write('             │ '),
  plan:print_element_safe(State,Rule),
  plan:print_next_in_step(State,Rest).

plan:print_next_in_step(State,[_|Rest]) :-
  !,
  plan:print_next_in_step(State,Rest).


%! plan:print_element_safe(+State, +Rule) is det.
%
% Print one plan element. A failure or exception in print_element/2
% must not abort the rest of the step (or the footer): --graph writes
% plans through tell/1, where line_position/2 can throw, and a single
% bad config line used to drop every later action from the page.

plan:print_element_safe(State, Rule) :-
  catch(plan:print_element(State, Rule), _, fail),
  !.
plan:print_element_safe(_, _).


%! plan:print_footer(+Plan, +ModelAVL, +PrintedSteps, +PreActions)
%
% Prints the footer for a given plan, including pre-action counts.

plan:print_footer(Plan, _ModelAVL, PrintedSteps, PreActions) :-
  plan:footer_stats_from_plan(Plan, S0),
  plan:footer_add_pre_actions(PreActions, S0, S),
  plan:pluralize(S.actions, action, actions, TotalStr),
  plan:pluralize(PrintedSteps, step, steps, PStr),
  plan:footer_action_breakdown(S, Breakdown),
  format('Total: ~d ~w (~w), grouped into ~d ~w.~n',
         [S.actions, TotalStr, Breakdown, PrintedSteps, PStr]),
  AlreadyDl = S.already_dl,
  RemainingDl is S.total_dl - AlreadyDl,
  ( AlreadyDl > 0
  -> message:convert_bytes(RemainingDl, RemStr),
     message:convert_bytes(AlreadyDl, AlrStr),
     format('~7|~w to be downloaded, ~w already downloaded.~n~n', [RemStr, AlrStr])
  ;  message:convert_bytes(S.total_dl, BytesStr),
     format('~7|~w to be downloaded.~n~n', [BytesStr])
  ).

plan:footer_add_pre_actions([], S, S) :- !.
plan:footer_add_pre_actions(PreActions, S0, S) :-
  include([A]>>(A = unmask(_,_,_,_)), PreActions, UnmaskActions),
  include([A]>>(A = accept_license(_,_,_,_)), PreActions, LicenseActions),
  include([A]>>(A = accept_keyword(_,_,_,_,_)), PreActions, KeywordActions),
  include([A]>>(A = use_change(_,_,_,_,_)), PreActions, UseChangeActions),
  length(UnmaskActions, NUnmask),
  length(LicenseActions, NLicenses),
  length(KeywordActions, NKeyword),
  length(UseChangeActions, NUseChange),
  NewActions is S0.actions + NUnmask + NLicenses + NKeyword + NUseChange,
  S = S0.put(_{actions:NewActions, unmasks:NUnmask, licenses:NLicenses,
                keywords:NKeyword, usechanges:NUseChange}).

% Build the "(...)" part of the footer, omitting zero-count categories.
plan:footer_action_breakdown(S, Breakdown) :-
  ( get_dict(unmasks,    S, UnmaskCount)    -> true ; UnmaskCount    = 0 ),
  ( get_dict(licenses,   S, LicenseCount)   -> true ; LicenseCount   = 0 ),
  ( get_dict(keywords,   S, KeywordCount)   -> true ; KeywordCount   = 0 ),
  ( get_dict(usechanges, S, UseChangeCount) -> true ; UseChangeCount = 0 ),
  findall(Part,
          ( plan:footer_action_part(unmasks,     UnmaskCount,     unmask,      unmasks,     Part)
          ; plan:footer_action_part(licenses,    LicenseCount,    license,     licenses,    Part)
          ; plan:footer_action_part(keywords,    KeywordCount,    keyword,     keywords,    Part)
          ; plan:footer_action_part(usechanges,  UseChangeCount,  useflag,     useflags,    Part)
          ; plan:footer_action_part(downloads,   S.downloads,     download,    downloads,   Part)
          ; plan:footer_action_part(installs,    S.installs,      install,     installs,    Part)
          ; plan:footer_action_part(updates,     S.updates,       update,      updates,     Part)
          ; plan:footer_action_part(downgrades,  S.downgrades,    downgrade,   downgrades,  Part)
          ; plan:footer_action_part(reinstalls,  S.reinstalls,    reinstall,   reinstalls,  Part)
          ; plan:footer_action_part(runs,        S.runs,          run,         runs,        Part)
          ),
          Parts0),
  ( Parts0 == [] ->
      Breakdown = none
  ; atomic_list_concat(Parts0, ', ', Breakdown)
  ).

plan:footer_action_part(_Key, Count, _Singular, _Plural, _Part) :-
  Count =:= 0,
  !,
  fail.
plan:footer_action_part(_Key, Count, Singular, Plural, Part) :-
  plan:pluralize(Count, Singular, Plural, Word),
  format(atom(Part), '~d ~w', [Count, Word]).


%! plan:pluralize(+Count, +Singular, +Plural, -Result)
%
% Pluralizes a word based on a count.

plan:pluralize(1, Singular, _, Singular) :- !.
plan:pluralize(_, _, Plural, Plural).


%! plan:footer_stats_from_plan(+Plan, -Stats)
%
% Plan-based footer stats (preferred for CLI output).
%
% The plan contains rules (and assumed rules) that are actually scheduled.
% We only count concrete actions shown in the plan (download/install/update/
% reinstall/run), matching the footer breakdown.
%
plan:footer_stats_from_plan(Plan, Stats) :-
  Stats0 = stats{actions:0, downloads:0, runs:0, installs:0, updates:0, downgrades:0, reinstalls:0, total_dl:0, already_dl:0},
  foldl(plan:footer_stats_from_step, Plan, Stats0, Stats).

plan:footer_stats_from_step(Step, S0, S) :-
  foldl(plan:footer_stats_from_rule, Step, S0, S).

plan:footer_stats_from_rule(Rule0, S0, S) :-
  prover:rule_parts(Rule0, HeadWithCtx, _Body, Kind),
  Kind \== cycle_break,
  !,
  prover:canon_literal(HeadWithCtx, Head, _Ctx),
  plan:footer_stats_from_head(Head, S0, S).
plan:footer_stats_from_rule(_Other, S, S).

plan:footer_stats_from_head(_://_:Action, S0, S) :-
  preference:fetchonly_skips_action(Action),
  !,
  S = S0.
plan:footer_stats_from_head(R://E:download, S0, S) :-
  !,
  ebuild:distfile_scope(Scope),
  ( ebuild:download_size(Scope, R://E, Bytes) -> true ; Bytes = 0 ),
  plan:already_downloaded_size(R, E, AlreadyBytes),
  NewDownloads is S0.downloads + 1,
  NewTotalDl is S0.total_dl + Bytes,
  NewAlreadyDl is S0.already_dl + AlreadyBytes,
  NewActions is S0.actions + 1,
  S = S0.put(_{downloads:NewDownloads, total_dl:NewTotalDl, already_dl:NewAlreadyDl, actions:NewActions}).
plan:footer_stats_from_head(_://_:run, S0, S) :-
  !,
  NewRuns is S0.runs + 1,
  NewActions is S0.actions + 1,
  S = S0.put(_{runs:NewRuns, actions:NewActions}).
plan:footer_stats_from_head(_://_:install, S0, S) :-
  !,
  NewInstalls is S0.installs + 1,
  NewActions is S0.actions + 1,
  S = S0.put(_{installs:NewInstalls, actions:NewActions}).
plan:footer_stats_from_head(_://_:update, S0, S) :-
  !,
  NewUpdates is S0.updates + 1,
  NewActions is S0.actions + 1,
  S = S0.put(_{updates:NewUpdates, actions:NewActions}).
plan:footer_stats_from_head(_://_:downgrade, S0, S) :-
  !,
  NewDowngrades is S0.downgrades + 1,
  NewActions is S0.actions + 1,
  S = S0.put(_{downgrades:NewDowngrades, actions:NewActions}).
plan:footer_stats_from_head(_://_:reinstall, S0, S) :-
  !,
  NewReinstalls is S0.reinstalls + 1,
  NewActions is S0.actions + 1,
  S = S0.put(_{reinstalls:NewReinstalls, actions:NewActions}).
plan:footer_stats_from_head(_Other, S, S).


%! plan:already_downloaded_size(+Repository, +Entry, -Bytes) is det.
%
% Sum the sizes of distfiles for this entry that are already present
% in the local distfiles directory.

plan:already_downloaded_size(Repository, Entry, Bytes) :-
  ebuild:distfile_scope(Scope),
  aggregate_all(sum(Size), File,
    ( query:search(manifest(Scope, _, File, Size), Repository://Entry),
      distfiles:present(File)
    ),
    Bytes), !.

plan:already_downloaded_size(_, _, 0).


% -----------------------------------------------------------------------------
%  Variant display
% -----------------------------------------------------------------------------

%! plan:print_variants(+Results, +BasePlan) is det.
%
% Prints each variant_result/2,5 in turn, numbered from 1: a header, the
% plan size and the diff against the baseline plan, or a warning for a
% variant whose proof failed.

plan:print_variants(Results, BasePlan) :-
  variant:plan_entries(BasePlan, BaseEntries),
  plan:print_variants(Results, BaseEntries, 1).


%! plan:print_variants(+Results, +BaseEntries, +N) is det.

plan:print_variants([], _, _).
plan:print_variants([variant_result(variant(_, _, _, _, Label), failed)|Rest], BaseEntries, N) :-
  !,
  plan:print_variant_header(N, Label),
  message:warning(['Variant proof failed.']),
  N1 is N + 1,
  plan:print_variants(Rest, BaseEntries, N1).
plan:print_variants([variant_result(variant(_, _, _, _, Label), _Proof, _Model, Plan, _Triggers)|Rest], BaseEntries, N) :-
  plan:print_variant_header(N, Label),
  variant:plan_entries(Plan, VarEntries),
  length(VarEntries, VarCount),
  variant:plan_diff(BaseEntries, VarEntries, Diff),
  format('  Plan size: ~w actions~n', [VarCount]),
  plan:print_variant_diff(Diff),
  N1 is N + 1,
  plan:print_variants(Rest, BaseEntries, N1).


%! plan:print_variant_header(+N, +Label) is det.
%
% Prints a prominent header for a variant plan.

plan:print_variant_header(N, Label) :-
  message:color(cyan),
  message:style(bold),
  format('~n=== Variant ~w: ~w ===~n', [N, Label]),
  message:style(normal),
  message:color(normal).


%! plan:print_variant_diff(+Diff) is det.
%
% Prints a compact diff summary between the baseline and variant plan.

plan:print_variant_diff(diff(Added, Removed, Changed)) :-
  length(Added, NA), length(Removed, NR), length(Changed, NC),
  ( NA =:= 0, NR =:= 0, NC =:= 0
  -> message:color(darkgray),
     format('  (identical to baseline)~n'),
     message:color(normal)
  ;  ( NA > 0
     -> message:color(green),
        format('~n  Added (~w):~n', [NA]),
        forall(member(entry(C, N, Ver, _), Added),
          ( version_domain:display_atom(Ver, VS),
            format('    + ~w/~w-~w~n', [C, N, VS]) )),
        message:color(normal)
     ;  true
     ),
     ( NR > 0
     -> message:color(red),
        format('~n  Removed (~w):~n', [NR]),
        forall(member(entry(C, N, Ver, _), Removed),
          ( version_domain:display_atom(Ver, VS),
            format('    - ~w/~w-~w~n', [C, N, VS]) )),
        message:color(normal)
     ;  true
     ),
     ( NC > 0
     -> message:color(orange),
        format('~n  Version changed (~w):~n', [NC]),
        forall(member(changed(C, N, BaseVer, VarVer), Changed),
          ( version_domain:display_atom(BaseVer, BVS),
            version_domain:display_atom(VarVer, VVS),
            format('    ~~ ~w/~w  ~w -> ~w~n', [C, N, BVS, VVS]) )),
        message:color(normal)
     ;  true
     ),
     format('~n  Summary: +~w -~w ~~~w~n', [NA, NR, NC])
  ).