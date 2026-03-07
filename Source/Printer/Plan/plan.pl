/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> PLAN
Build plan rendering.

Handles all terminal output for merge/fetchonly plans: element classification,
step-numbered wave display, colored action tags, USE flag diffs, config items,
pre-action sections (unmask/keyword/USE-change), footer statistics, and
SCC decomposition display.
*/

:- module(plan, []).


% -----------------------------------------------------------------------------
%  Plan printing
% -----------------------------------------------------------------------------

%! plan:printable_element(+Literal)
%
% Declares which Literals are printable

plan:printable_element(rule(uri(_,_,_),_)) :- !.
plan:printable_element(rule(uri(_),_)) :- !.
plan:printable_element(rule(_Repository://_Entry:run?_,_)) :- !.
plan:printable_element(rule(_Repository://_Entry:run?_,_)) :- !.
plan:printable_element(rule(_Repository://_Entry:download?_,_)) :- !.
plan:printable_element(rule(_Repository://_Entry:install?_,_)) :- !.
plan:printable_element(rule(_Repository://_Entry:reinstall?_,_)) :- !.
plan:printable_element(rule(_Repository://_Entry:uninstall?_,_)) :- !.

% Suppress printing the "wrapper" update/downgrade target when it schedules the
% actual transactional update/downgrade on a chosen replacement version.
plan:printable_element(rule(_Repository://_Entry:update?{_Context},Body)) :-
  member(_NewRepo://_NewEntry:update?{_}, Body),
  !,
  fail.
plan:printable_element(rule(_Repository://_Entry:downgrade?{_Context},Body)) :-
  member(_NewRepo://_NewEntry:downgrade?{_}, Body),
  !,
  fail.

plan:printable_element(rule(_Repository://_Entry:update?_,_)) :- !.
plan:printable_element(rule(_Repository://_Entry:downgrade?_,_)) :- !.
plan:printable_element(rule(_Repository://_Entry:upgrade?_,_)) :- !.
% Prover cycle-break rules (`assumed(rule(...))`) are printed in the warnings
% section with cycle explanations. Do not print them as "verify" steps.
plan:printable_element(assumed(rule(_,_))) :- !, fail.
plan:printable_element(rule(assumed(_Repository://_Entry:_?_,_))) :- !.
plan:printable_element(assumed(rule(package_dependency(_,_,_,_,_,_,_,_):install?_,_))) :- !.
plan:printable_element(assumed(rule(package_dependency(_,_,_,_,_,_,_,_):run?_,_))) :- !.
plan:printable_element(rule(assumed(package_dependency(_,_,_,_,_,_,_,_):install?_,_))) :- !.
plan:printable_element(rule(assumed(package_dependency(_,_,_,_,_,_,_,_):run?_,_))) :- !.
plan:printable_element(assumed(rule(grouped_package_dependency(_,_,_,_):install?_,_))) :- !. % todo: phase out
plan:printable_element(assumed(rule(grouped_package_dependency(_,_,_,_):run?_,_))) :- !. % todo: phase out
plan:printable_element(assumed(rule(grouped_package_dependency(_,_,_):install?_,_))) :- !.
plan:printable_element(assumed(rule(grouped_package_dependency(_,_,_):run?_,_))) :- !.
plan:printable_element(rule(assumed(grouped_package_dependency(_,_,_):install?_),_)) :- !.
plan:printable_element(rule(assumed(grouped_package_dependency(_,_,_):run?_),_)) :- !.

% Suppress assumed dependency verifies when a concrete ebuild for the same
% package is already scheduled in the plan.
plan:printable_element(rule(assumed(grouped_package_dependency(C,N,_Deps):install?{_Context}),[])) :-
  plan:planned_pkg(install, C, N),
  !,
  fail.
plan:printable_element(rule(assumed(package_dependency(install,no,C,N,_,_,_,_):install?{_Context}),[])) :-
  plan:planned_pkg(install, C, N),
  !,
  fail.
plan:printable_element(rule(assumed(grouped_package_dependency(C,N,_Deps):run?{_Context}),[])) :-
  plan:planned_pkg(run, C, N),
  !,
  fail.
plan:printable_element(rule(assumed(package_dependency(run,no,C,N,_,_,_,_):run?{_Context}),[])) :-
  plan:planned_pkg(run, C, N),
  !,
  fail.


% Uncomment if you want 'confirm' steps shown in the plan:
% plan:printable_element(rule(package_dependency(run,_,_,_,_,_,_,_),_)) :- !.


%! plan:element_weight(+Literal)
%
% Declares a weight for ordering elements of a step in a plan

plan:element_weight(assumed(_),                                      0) :- !. % assumed
plan:element_weight(rule(assumed(_),_),                              0) :- !. % assumed
plan:element_weight(rule(uri(_),_),                                  0) :- !. % provide
plan:element_weight(rule(uri(_,_,_),_),                              1) :- !. % fetch
plan:element_weight(rule(package_dependency(_,_,_,_,_,_,_,_),_),     1) :- !. % confirm
plan:element_weight(rule(_Repository://_Entry:verify?_,_),           2) :- !. % verify
% Run should come after install within a step.
plan:element_weight(rule(_Repository://_Entry:run?_,_),              6) :- !. % run
plan:element_weight(rule(_Repository://_Entry:download?_,_),         4) :- !. % download
plan:element_weight(rule(_Repository://_Entry:fetchonly?_,_),        5) :- !. % fetchonly
plan:element_weight(rule(_Repository://_Entry:install?_,_),          5) :- !. % install
plan:element_weight(rule(_Repository://_Entry:reinstall?_,_),        6) :- !. % reinstall
plan:element_weight(rule(_Repository://_Entry:uninstall?_,_),        6) :- !. % uninstall
plan:element_weight(rule(_Repository://_Entry:update?_,_),           6) :- !. % update
plan:element_weight(rule(_Repository://_Entry:downgrade?_,_),        6) :- !. % downgrade
plan:element_weight(rule(_Repository://_Entry:upgrade?_,_),          6) :- !. % upgrade
plan:element_weight(_,                                               7) :- !. % everything else


%! plan:sort_by_weight(+Comparator,+Literal,+Literal)
%
% Sorts elements in a plan by weight

plan:sort_by_weight(C,L1,L2) :-
  plan:element_weight(L1,W1),
  plan:element_weight(L2,W2),
  compare(C,W1:L1,W2:L2).

%! plan:stable_sort_by_weight(+Step, -Sorted)
%
% Sort by element_weight, preserving the scheduler's within-weight ordering
% (which reflects merge-order bias / refcount priority).
plan:stable_sort_by_weight(Step, Sorted) :-
  plan:tag_with_weight_index(Step, 0, Tagged),
  keysort(Tagged, SortedTagged),
  findall(Rule, member(_-Rule, SortedTagged), Sorted).

plan:tag_with_weight_index([], _, []) :- !.
plan:tag_with_weight_index([R|Rs], I, [(W-I)-R|Rest]) :-
  plan:element_weight(R, W),
  I1 is I + 1,
  plan:tag_with_weight_index(Rs, I1, Rest).


%! plan:print_element(+Printable)
%
% Prints a printable Literal

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

plan:print_element(Target,rule(Repository://Entry:Action?{Context},_Body)) :-
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
  printer:print_blocker_note_if_any(Action, Repository, Entry),
  printer:print_newuse_note_if_any(Action, Context),
  message:color(normal),
  plan:print_config(Repository://Entry:Action?{Context}).


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
  plan:print_config(Repository://Entry:Action?{Context}).


% -----------------------------------------------------------
% CASE: package resolved via unmask fallback (suggestion)
% -----------------------------------------------------------

plan:print_element(_,rule(Repository://Entry:Action?{Context},_Body)) :-
  is_list(Context),
  memberchk(suggestion(unmask, _), Context),
  !,
  message:color(cyan),
  message:print(Action),
  message:color(green),
  message:column(24,Repository://Entry),
  message:color(darkgray),
  message:print(' (unmasked)'),
  message:color(normal),
  plan:print_config(Repository://Entry:Action?{Context}).


% -----------------------------------------------------------
% CASE: package resolved via USE change (build_with_use)
% -----------------------------------------------------------

plan:print_element(_,rule(Repository://Entry:Action?{Context},_Body)) :-
  is_list(Context),
  memberchk(suggestion(use_change, _, _Changes), Context),
  \+ memberchk(suggestion(unmask, _), Context),
  \+ memberchk(suggestion(accept_keyword, _), Context),
  !,
  message:color(cyan),
  message:print(Action),
  message:color(green),
  message:column(24,Repository://Entry),
  message:color(darkgray),
  message:print(' (USE modified)'),
  message:color(normal),
  plan:print_config(Repository://Entry:Action?{Context}).


% -------------------------------------------------
% CASE: simple package, is not a target of the plan
% -------------------------------------------------

plan:print_element(_,rule(Repository://Entry:Action?{Context},_)) :-
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
  printer:print_blocker_note_if_any(Action, Repository, Entry),
  printer:print_newuse_note_if_any(Action, Context),
  message:color(normal),
  plan:print_config(Repository://Entry:Action?{Context}).


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


% ---------------------------------------------------------------
% CASE: an assumed dependency on a keyword-filtered installed package
% ---------------------------------------------------------------

plan:print_element(_,rule(assumed(grouped_package_dependency(C,N,_Deps):install?{Context}),[])) :-
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


% ---------------------------------------------------------------
% CASE: an assumed dependency on a masked installed package
% ---------------------------------------------------------------

plan:print_element(_,rule(assumed(grouped_package_dependency(C,N,_Deps):install?{Context}),[])) :-
  is_list(Context),
  memberchk(assumption_reason(masked), Context),
  !,
  message:bubble(red,'verify'),
  message:color(green),
  atomic_list_concat([C,'/',N],P),
  message:column(24,P),
  message:color(darkgray),
  message:print(' (masked, requires unmask)'),
  message:color(normal).


% ---------------------------------------------------------------
% CASE: an assumed dependency with version conflict (install)
% ---------------------------------------------------------------

plan:print_element(_,rule(assumed(grouped_package_dependency(C,N,_Deps):install?{Context}),[])) :-
  is_list(Context),
  memberchk(assumption_reason(Reason), Context),
  ( Reason = version_conflict ; Reason = version_conflict(_) ),
  !,
  message:bubble(yellow,'verify'),
  message:color(yellow),
  atomic_list_concat([C,'/',N],P),
  message:column(24,P),
  message:color(darkgray),
  message:print(' (version conflict, assumed installed)'),
  message:color(normal).


% ---------------------------------------------------------------
% CASE: an assumed dependency with no version candidate (install)
% ---------------------------------------------------------------

plan:print_element(_,rule(assumed(grouped_package_dependency(C,N,_Deps):install?{Context}),[])) :-
  is_list(Context),
  memberchk(assumption_reason(Reason), Context),
  ( Reason = version_no_candidate ; Reason = version_no_candidate(_,_) ),
  !,
  message:bubble(yellow,'verify'),
  message:color(yellow),
  atomic_list_concat([C,'/',N],P),
  message:column(24,P),
  message:color(darkgray),
  message:print(' (version unavailable, assumed installed)'),
  message:color(normal).


% ---------------------------------------------------------------
% CASE: an assumed dependency with slot unsatisfied (install)
% ---------------------------------------------------------------

plan:print_element(_,rule(assumed(grouped_package_dependency(C,N,_Deps):install?{Context}),[])) :-
  is_list(Context),
  memberchk(assumption_reason(slot_unsatisfied), Context),
  !,
  message:bubble(yellow,'verify'),
  message:color(yellow),
  atomic_list_concat([C,'/',N],P),
  message:column(24,P),
  message:color(darkgray),
  message:print(' (slot unavailable, assumed installed)'),
  message:color(normal).


% ---------------------------------------------------------------
% CASE: an assumed dependency requiring installed candidate (install)
% ---------------------------------------------------------------

plan:print_element(_,rule(assumed(grouped_package_dependency(C,N,_Deps):install?{Context}),[])) :-
  is_list(Context),
  memberchk(assumption_reason(installed_required), Context),
  !,
  message:bubble(yellow,'verify'),
  message:color(yellow),
  atomic_list_concat([C,'/',N],P),
  message:column(24,P),
  message:color(darkgray),
  message:print(' (requires installed, assumed installed)'),
  message:color(normal).


% ---------------------------------------------------------------
% CASE: an assumed dependency with unsatisfied constraints (install)
% ---------------------------------------------------------------

plan:print_element(_,rule(assumed(grouped_package_dependency(C,N,_Deps):install?{Context}),[])) :-
  is_list(Context),
  memberchk(assumption_reason(unsatisfied_constraints), Context),
  !,
  message:bubble(yellow,'verify'),
  message:color(yellow),
  atomic_list_concat([C,'/',N],P),
  message:column(24,P),
  message:color(darkgray),
  message:print(' (unsatisfied constraints, assumed installed)'),
  message:color(normal).


% ---------------------------------------------------------------
% CASE: an assumed dependency on a non-existent installed package
% ---------------------------------------------------------------

plan:print_element(_,rule(assumed(grouped_package_dependency(C,N,_Deps):install?{_Context}),[])) :-
  message:bubble(red,'verify'),
  message:color(red),
  atomic_list_concat([C,'/',N],P),
  message:column(24,P),
  message:print(' (non-existent, assumed installed)'),
  message:color(normal).


plan:print_element(_,rule(assumed(package_dependency(install,no,C,N,_,_,_,_):install?{_Context}),[])) :-
  message:bubble(red,'verify'),
  message:color(red),
  atomic_list_concat([C,'/',N],P),
  message:column(24,P),
  message:print(' (non-existent, assumed installed)'),
  message:color(normal).


% -----------------------------------------------------------
% CASE: an assumed dependency on a keyword-filtered running package
% -----------------------------------------------------------

plan:print_element(_,rule(assumed(grouped_package_dependency(C,N,_Deps):run?{Context}),[])) :-
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


% -----------------------------------------------------------
% CASE: an assumed dependency on a masked running package
% -----------------------------------------------------------

plan:print_element(_,rule(assumed(grouped_package_dependency(C,N,_Deps):run?{Context}),[])) :-
  is_list(Context),
  memberchk(assumption_reason(masked), Context),
  !,
  message:bubble(red,'verify'),
  message:color(green),
  atomic_list_concat([C,'/',N],P),
  message:column(24,P),
  message:color(darkgray),
  message:print(' (masked, requires unmask)'),
  message:color(normal).


% -----------------------------------------------------------
% CASE: an assumed dependency with version conflict (run)
% -----------------------------------------------------------

plan:print_element(_,rule(assumed(grouped_package_dependency(C,N,_Deps):run?{Context}),[])) :-
  is_list(Context),
  memberchk(assumption_reason(Reason), Context),
  ( Reason = version_conflict ; Reason = version_conflict(_) ),
  !,
  message:bubble(yellow,'verify'),
  message:color(yellow),
  atomic_list_concat([C,'/',N],P),
  message:column(24,P),
  message:color(darkgray),
  message:print(' (version conflict, assumed running)'),
  message:color(normal).


% -----------------------------------------------------------
% CASE: an assumed dependency with no version candidate (run)
% -----------------------------------------------------------

plan:print_element(_,rule(assumed(grouped_package_dependency(C,N,_Deps):run?{Context}),[])) :-
  is_list(Context),
  memberchk(assumption_reason(Reason), Context),
  ( Reason = version_no_candidate ; Reason = version_no_candidate(_,_) ),
  !,
  message:bubble(yellow,'verify'),
  message:color(yellow),
  atomic_list_concat([C,'/',N],P),
  message:column(24,P),
  message:color(darkgray),
  message:print(' (version unavailable, assumed running)'),
  message:color(normal).


% -----------------------------------------------------------
% CASE: an assumed dependency with slot unsatisfied (run)
% -----------------------------------------------------------

plan:print_element(_,rule(assumed(grouped_package_dependency(C,N,_Deps):run?{Context}),[])) :-
  is_list(Context),
  memberchk(assumption_reason(slot_unsatisfied), Context),
  !,
  message:bubble(yellow,'verify'),
  message:color(yellow),
  atomic_list_concat([C,'/',N],P),
  message:column(24,P),
  message:color(darkgray),
  message:print(' (slot unavailable, assumed running)'),
  message:color(normal).


% -----------------------------------------------------------
% CASE: an assumed dependency requiring installed candidate (run)
% -----------------------------------------------------------

plan:print_element(_,rule(assumed(grouped_package_dependency(C,N,_Deps):run?{Context}),[])) :-
  is_list(Context),
  memberchk(assumption_reason(installed_required), Context),
  !,
  message:bubble(yellow,'verify'),
  message:color(yellow),
  atomic_list_concat([C,'/',N],P),
  message:column(24,P),
  message:color(darkgray),
  message:print(' (requires installed, assumed running)'),
  message:color(normal).


% -----------------------------------------------------------
% CASE: an assumed dependency with unsatisfied constraints (run)
% -----------------------------------------------------------

plan:print_element(_,rule(assumed(grouped_package_dependency(C,N,_Deps):run?{Context}),[])) :-
  is_list(Context),
  memberchk(assumption_reason(unsatisfied_constraints), Context),
  !,
  message:bubble(yellow,'verify'),
  message:color(yellow),
  atomic_list_concat([C,'/',N],P),
  message:column(24,P),
  message:color(darkgray),
  message:print(' (unsatisfied constraints, assumed running)'),
  message:color(normal).


% -------------------------------------------------------------
% CASE: an assumed dependency on a non-existent running package
% -------------------------------------------------------------

plan:print_element(_,rule(assumed(grouped_package_dependency(C,N,_Deps):run?{_Context}),[])) :-
  message:bubble(red,'verify'),
  message:color(red),
  atomic_list_concat([C,'/',N],P),
  message:column(24,P),
  message:print(' (non-existent, assumed running)'),
  message:color(normal).


plan:print_element(_,rule(assumed(package_dependency(run,no,C,N,_,_,_,_):run?{_Context}),[])) :-
  message:bubble(red,'verify'),
  message:color(red),
  atomic_list_concat([C,'/',N],P),
  message:column(24,P),
  message:print(' (non-existent, assumed running)'),
  message:color(normal).


% ---------------------------------
% CASE: an assumed unmasked package
% ---------------------------------

plan:print_element(_,rule(assumed(Repository://Entry:unmask?{_Context}),_Body)) :-
  message:bubble(red,'verify'),
  message:color(red),
  message:column(24,Repository://Entry),
  message:print(' (masked, assumed unmasked)'),
  message:color(normal).


% ----------------------------------
% CASE: an assumed installed package
% ----------------------------------

plan:print_element(_,assumed(rule(Repository://Entry:install?{_Context},_Body))) :-
  message:bubble(red,'verify'),
  message:color(red),
  message:column(24,Repository://Entry),
  message:print(' (assumed installed)'),
  message:color(normal).


% --------------------------------
% CASE: an assumed running package
% --------------------------------

plan:print_element(_,assumed(rule(Repository://Entry:run?{_Context},_Body))) :-
  message:bubble(red,'verify'),
  message:color(red),
  message:column(24,Repository://Entry),
  message:print(' (assumed running) '),
  message:color(normal).


% --------------------------------
% CASE: an assumed fetched package
% --------------------------------

plan:print_element(_,assumed(rule(Repository://Entry:fetchonly?{_Context},_Body))) :-
  message:bubble(red,'verify'),
  message:color(red),
  message:column(24,Repository://Entry),
  message:print(' (assumed fetched) '),
  message:color(normal).


% -------------------------------------
% CASE: an assumed installed dependency
% -------------------------------------

plan:print_element(_,assumed(rule(package_dependency(install,_,C,N,_,_,_,_):_Action?{_Context},_Body))) :-
  message:bubble(red,'verify'),
  message:color(red),
  atomic_list_concat([C,'/',N],P),
  message:column(24,P),
  message:print(' (assumed installed) '),
  message:color(normal).


% -----------------------------------
% CASE: an assumed running dependency
% -----------------------------------

plan:print_element(_,assumed(rule(package_dependency(run,_,C,N,_,_,_,_):_Action?{_Context},_Body))) :-
  message:bubble(red,'verify'),
  message:color(red),
  atomic_list_concat([C,'/',N],P),
  message:column(24,P),
  message:print(' (assumed running) '),
  message:color(normal).


% -------------------------------------------------------------
% CASE: an assumed circular dependency
% -------------------------------------------------------------

plan:print_element(_,assumed(rule(grouped_package_dependency(_X,C,N,_Deps):install?{_Context},_Body))) :-
  !,
  message:bubble(red,'verify'),
  message:color(red),
  atomic_list_concat([C,'/',N],P),
  message:column(24,P),
  message:print(' (assumed installed) '),
  message:color(normal).

plan:print_element(_,assumed(rule(grouped_package_dependency(_X,C,N,_Deps):run?{_Context},_Body))) :-
  !,
  message:bubble(red,'verify'),
  message:color(red),
  atomic_list_concat([C,'/',N],P),
  message:column(24,P),
  message:print(' (assumed running) '),
  message:color(normal).


%! plan:print_config_prefix(+Word)
%
% prints the prefix for a config item

% -------------------------------
% CASE: Fancy build plan printing
% -------------------------------

plan:print_config_prefix(Word) :-
  config:printing_style('fancy'),!,
  nl,write('             │           '),
  message:color(darkgray),
  message:print('└─ '),
  message:print(Word),
  message:print(' ─┤ '),
  message:color(normal).

% -------------------------------
% CASE: Short build plan printing
% -------------------------------

plan:print_config_prefix(_Word) :-
  config:printing_style('short'),!,
  nl,write('             │           ').

% --------------------------------
% CASE: Column build plan printing
% --------------------------------

plan:print_config_prefix(file) :-
  config:printing_style('column'),!,
  message:column(104,' ').

plan:print_config_prefix(live) :-
  config:printing_style('column'),!,
  message:column(104,' ').

plan:print_config_prefix('conf') :-
  config:printing_style('column'), !,
  message:column(104,' ').


%! plan:print_config_prefix
%
% prints the prefix for a config item

plan:print_config_prefix :-
  config:printing_style('fancy'),!,
  nl,write('             │          '),
  message:color(darkgray),
  message:print('          │ '),
  message:color(normal).

plan:print_config_prefix :-
  config:printing_style('short'),!,
  nl,write('             │           ').

plan:print_config_prefix :-
  config:printing_style('column'),!,
  nl,write('             │ '),
  message:column(104,' ').


%! plan:print_config(+Repository://+Entry:+Action:+Context)
%
% Prints the configuration for a given repository entry (USE flags, USE expand, ...)

% ----------------------
% CASE: fetchonly action
% ----------------------

% iuse empty

plan:print_config(Repository://Entry:fetchonly?{_Context}) :-
  \+(kb:query(iuse(_),Repository://Entry)),!.

% use flags to show - to rework: performance

plan:print_config(Repository://Entry:fetchonly?{Context}) :-
 !,
 findall(Use,
         (member(Term,Context),
          (Term = required_use(Uses) ; Term = build_with_use(Uses)),
           member(assumed(Use),Uses)),
         Assumed0),
 plan:use_changes_to_assumed(Context, SuggAssumed),
 append(Assumed0, SuggAssumed, Assumed),
 findall([Reason,Group], group_by(Reason, Use, kb:query(iuse_filtered(Use,Reason),Repository://Entry), Group), Useflags),

 (Useflags == [] ;
   (plan:print_config_prefix('conf'),	                  % Use flags not empty
    plan:print_config_item('use',Useflags,Assumed))).    % Use flags not empty



% ---------------------
% CASE: download action
% ---------------------

% live downloads

plan:print_config(Repository://Ebuild:download?{_Context}) :-
  ebuild:is_live(Repository://Ebuild),!,
  plan:print_config_prefix('live'),
  plan:print_config_item('download','git repository','live').


% no downloads

plan:print_config(Repository://Ebuild:download?{_Context}) :-
  \+(kb:query(manifest(preference,_,_,_),Repository://Ebuild)),!.


% at least one download

plan:print_config(Repository://Ebuild:download?{_Context}) :-
  !,
  findall([File,Size],kb:query(manifest(preference,_,File,Size),Repository://Ebuild),Downloads),
  sort(Downloads,[[FirstFile,FirstSize]|Rest]),
  plan:print_config_prefix('file'),
  plan:print_config_item('download',FirstFile,FirstSize),
  forall(member([RestFile,RestSize],Rest),
         (plan:print_config_prefix,
          plan:print_config_item('download',RestFile,RestSize))).


% --------------------
% CASE: Install action
% --------------------

% iuse empty

plan:print_config(Repository://Entry:install?{Context}) :-
  \+(kb:query(iuse(_),Repository://Entry)),!,
  (memberchk(slot(_,_,Slot):{Repository://Entry},Context)
  -> (Slot \== [slot('0')] ->
        plan:print_config_prefix('conf'),
        plan:print_config_item('slot',Slot)
      ; true)
  ;  true).

% use flags to show

plan:print_config(Repository://Entry:install?{Context}) :-
  !,
  findall(Use,
         (member(Term,Context),
          (Term = required_use(Uses) ; Term = build_with_use(Uses)),
           member(assumed(Use),Uses)),
         Assumed0),
  plan:use_changes_to_assumed(Context, SuggAssumed),
  append(Assumed0, SuggAssumed, Assumed),

  % Get regular USE flags (filtered, excluding USE_EXPAND)
  findall([Reason,Group], group_by(Reason, Use, kb:query(iuse_filtered(Use,Reason),Repository://Entry), Group), Useflags),

  % Get all USE flags (including USE_EXPAND ones) for USE_EXPAND processing
  findall(Use, kb:query(iuse(Use, _Reason), Repository://Entry), AllUseFlags),

  % Separate regular USE flags from USE_EXPAND flags
  partition(plan:is_use_expand_flag, AllUseFlags, UseExpandFlags, _RegularUseFlags),

  % Group USE_EXPAND flags by expand key and reason
  findall([ExpandKey, ExpandFlags],
          plan:group_use_expand_flags(UseExpandFlags, ExpandKey, ExpandFlags, Repository://Entry),
          UseExpandVariables),

  % Filter out empty USE_EXPAND variables
  include(plan:valid_use_expand, UseExpandVariables, ValidUseExpandVariables),

  % Check if a slot is present in the context
  (memberchk(slot(_,_,Slot):{Repository://Entry},Context)
  -> % Check if slot is relevant to print
     (Slot \== [slot('0')]
     -> % Case 1: Use flags and Expanded Use flags empty
         (Useflags == [], ValidUseExpandVariables == []
          -> % print just the slot
             plan:print_config_prefix('conf'),
             plan:print_config_item('slot',Slot)
          ;  % print algined configuration
           plan:print_config_prefix('conf'),
           plan:print_config_items_aligned(Useflags, ValidUseExpandVariables, Assumed, Slot)
        )
     ; (Useflags == [], ValidUseExpandVariables == [] ;
          (plan:print_config_prefix('conf'),
           plan:print_config_items_aligned(Useflags, ValidUseExpandVariables, Assumed, []))))
  ;  (Useflags == [], ValidUseExpandVariables == [] ;
       (plan:print_config_prefix('conf'),
        plan:print_config_items_aligned(Useflags, ValidUseExpandVariables, Assumed, [])))),!.


% --------------------
% CASE: Update action
% --------------------
%
% Print the same configuration block as for installs (USE flags, USE_EXPAND, slot).
% Update actions are transactional same-slot replacements, so the config shown is
% for the *new* version being merged.

plan:print_config(Repository://Entry:update?{Context}) :-
  !,
  plan:print_config(Repository://Entry:install?{Context}).

plan:print_config(Repository://Entry:downgrade?{Context}) :-
  !,
  plan:print_config(Repository://Entry:install?{Context}).


% ----------------
% CASE: Run action
% ----------------

plan:print_config(_://_:run?{_Context}) :- !.


% -------------------
% CASE: Other actions
% -------------------

plan:print_config(_://_:_?_) :- !.



%! plan:is_use_expand_flag(+UseFlag)
%
% True when UseFlag is prefixed by a known USE_EXPAND key.

plan:is_use_expand_flag(UseFlag) :-
  eapi:use_expand(ExpandKey),
  eapi:check_prefix_atom(ExpandKey, UseFlag).

%! plan:group_use_expand_flags(+UseExpandFlags, -ExpandKey, -ExpandFlags, +Repository://Entry)
%
% Group UseExpandFlags by their USE_EXPAND key, stripping the prefix and
% looking up each flag's reason (positive/negative:source) via IUSE metadata.
% Skips hidden expand keys.

plan:group_use_expand_flags(UseExpandFlags, ExpandKey, ExpandFlags, Repository://Entry) :-
  eapi:use_expand(ExpandKey),
  \+ preference:use_expand_hidden(ExpandKey),
  findall(UseFlag,
          (member(UseFlag, UseExpandFlags),
           eapi:check_prefix_atom(ExpandKey, UseFlag)),
          MatchingFlags),
  MatchingFlags \== [],
  % Group by reason and extract suffix
  findall([Reason, Group],
          group_by(Reason, Suffix,
                   (member(UseFlag, MatchingFlags),
                    eapi:strip_prefix_atom(ExpandKey, UseFlag, Suffix),
                    kb:query(iuse(UseFlag, Reason), Repository://Entry)),
                   Group),
          ExpandFlags).

%! plan:valid_use_expand(+KeyFlagsPair)
%
% True when the USE_EXPAND variable has at least one flag.

plan:valid_use_expand([_Key, Flags]) :-
  Flags \== [].



%! plan:collect_expand_flags(+Keyflags, -AllFlags)
%
% Collect USE_EXPAND flags from all reason categories (positive/negative ×
% ebuild/preference/package_use/profile) into a flat list of flag terms.

plan:collect_expand_flags(Keyflags, AllFlags) :-
  plan:collect_expand_flags(Keyflags, [], AllFlags).

plan:collect_expand_flags(Keyflags, Assumed, AllFlags) :-
  (memberchk([negative:default,NegDefa],Keyflags);    NegDefa=[]),
  (memberchk([negative:ebuild,NegEbui],Keyflags);     NegEbui=[]),
  (memberchk([negative:preference,NegPref],Keyflags); NegPref=[]),
  (memberchk([negative:package_use,NegPkgUse],Keyflags); NegPkgUse=[]),
  (memberchk([negative:profile_package_use_mask,NegProfileMask],Keyflags); NegProfileMask=[]),
  (memberchk([positive:ebuild,PosEbui],Keyflags);     PosEbui=[]),
  (memberchk([positive:preference,PosPref],Keyflags); PosPref=[]),
  (memberchk([positive:package_use,PosPkgUse],Keyflags); PosPkgUse=[]),
  (memberchk([positive:profile_package_use_force,PosProfileForce],Keyflags); PosProfileForce=[]),
  sort(PosPref, OPosPref),
  sort(PosEbui, OPosEbui),
  sort(PosPkgUse, OPosPkgUse),
  sort(PosProfileForce, OPosProfileForce),
  sort(NegPref, ONegPref),
  sort(NegEbui, ONegEbui),
  sort(NegPkgUse, ONegPkgUse),
  sort(NegProfileMask, ONegProfileMask),
  sort(NegDefa, ONegDefa),
  maplist(plan:to_flag_term(positive:preference, Assumed), OPosPref, FlagsPosPref),
  maplist(plan:to_flag_term(positive:package_use, Assumed), OPosPkgUse, FlagsPosPkgUse),
  maplist(plan:to_flag_term(positive:profile_package_use_force, Assumed), OPosProfileForce, FlagsPosProfileForce),
  maplist(plan:to_flag_term(positive:ebuild, Assumed), OPosEbui, FlagsPosEbui),
  maplist(plan:to_flag_term(negative:preference, Assumed), ONegPref, FlagsNegPref),
  maplist(plan:to_flag_term(negative:package_use, Assumed), ONegPkgUse, FlagsNegPkgUse),
  maplist(plan:to_flag_term(negative:profile_package_use_mask, Assumed), ONegProfileMask, FlagsNegProfileMask),
  maplist(plan:to_flag_term(negative:ebuild, Assumed), ONegEbui, FlagsNegEbui),
  maplist(plan:to_flag_term(negative:default, Assumed), ONegDefa, FlagsNegDefa),
  append([FlagsPosPref, FlagsPosPkgUse, FlagsPosProfileForce, FlagsPosEbui,
          FlagsNegPref, FlagsNegPkgUse, FlagsNegProfileMask, FlagsNegEbui, FlagsNegDefa],
         AllFlags).


%! plan:print_config_items_aligned(+Useflags, +ValidUseExpandVariables, +Assumed, +Slot)
%
% Print USE flags, USE_EXPAND variables, and SLOT with aligned formatting.

plan:print_config_items_aligned(Useflags, ValidUseExpandVariables, Assumed, Slot) :-

  % 1. First print USE flags with proper formatting and alignment
  plan:print_config_item_aligned('use', Useflags, Assumed),

  % 2. Second print USE_EXPAND variables with proper formatting and alignment
  (ValidUseExpandVariables == [] -> true ;
   forall(member([Key, Keyflags], ValidUseExpandVariables),
          (plan:print_config_prefix,
           plan:print_config_item_aligned(Key, Keyflags, Assumed)))),

  % 3. Lastly print SLOT with proper formatting and alignment
  (Slot == [] -> true ;
   (plan:print_config_prefix,
    plan:print_config_item_aligned('slot', Slot, []))).



%! plan:collect_config_items(+Useflags, +ValidUseExpandVariables, +Assumed, +Slot, -ConfigItems)
%
% Collect all non-empty configuration items into a list of config_item/3 terms.

plan:collect_config_items(Useflags, ValidUseExpandVariables, Assumed, Slot, ConfigItems) :-
  findall(Item, plan:collect_single_config_item(Useflags, ValidUseExpandVariables, Assumed, Slot, Item), ConfigItems).

%! plan:collect_single_config_item(+Useflags, +ValidUseExpand, +Assumed, +Slot, -Item)
%
% Non-deterministically yield individual config_item/3 terms for USE flags,
% USE_EXPAND variables, and SLOT.

plan:collect_single_config_item(Useflags, _, Assumed, _, config_item('use', Useflags, Assumed)) :-
  Useflags \== [].
plan:collect_single_config_item(_, ValidUseExpandVariables, _, _, config_item(Key, Keyflags, [])) :-
  member([Key, Keyflags], ValidUseExpandVariables).
plan:collect_single_config_item(_, _, _, Slot, config_item('slot', Slot, [])) :-
  Slot \== [].


%! plan:print_aligned_config_items(+ConfigItems)
%
% Recursively print a list of config_item/3 terms with aligned formatting.

plan:print_aligned_config_items([]).
plan:print_aligned_config_items([config_item(Key, Value, Assumed)|Rest]) :-
  plan:print_aligned_config_item(Key, Value, Assumed),
  plan:print_aligned_config_items(Rest).

%! plan:print_aligned_config_item(+Key, +Value, +Assumed)
%
% Print a single KEY = "value" configuration line with bubble formatting.

plan:print_aligned_config_item(Key, Value, Assumed) :-
  upcase_atom(Key, KeyU),
  message:bubble(darkgray,KeyU),
  message:print(' = "'),
  plan:print_config_value(Key, Value, Assumed),
  message:print('"').


% Helper predicate: Print Use flags
plan:print_config_item_aligned('use', List, Assumed) :-
  !,
  upcase_atom('use', KeyU),
  message:bubble(darkgray,KeyU),
  message:print(' = "'),
  catch(
      ( config:printing_tty_size(_, TermWidth),
        line_position(current_output, StartCol),
	plan:collect_all_flags(List, Assumed, AllFlags),
        plan:print_flags_wrapped(AllFlags, StartCol, TermWidth)
      ),
      error(io_error(check, stream(_)), _),
      ( plan:collect_all_flags(List, Assumed, AllFlags),
        plan:print_flags_unwrapped(AllFlags)
      )
  ),
  message:print('"').


plan:print_config_item_aligned('slot', Slot, _) :-
  !,
  upcase_atom('slot', KeyU),
  message:bubble(darkgray,KeyU),
  message:print(' = "'),
  message:color(darkgray),
  plan:print_slot_value(Slot),
  message:color(normal),
  message:print('"').

plan:print_config_item_aligned(Key, Keyflags, Assumed) :-
  eapi:use_expand(Key),
  !,
  upcase_atom(Key, KeyU),
  message:bubble(darkgray,KeyU),
  message:print(' = "'),
  config:printing_tty_size(_, TermWidth),
  line_position(current_output, StartCol),
  plan:collect_expand_flags(Keyflags, Assumed, AllFlags),
  plan:print_flags_wrapped(AllFlags,StartCol,TermWidth),
  message:print('"').

% Helper predicate: Print configuration value based on type
plan:print_config_value('use', List, Assumed) :-
  !,
  plan:collect_all_flags(List, Assumed, AllFlags),
  plan:print_flags_unwrapped(AllFlags).
plan:print_config_value('slot', Slot, _) :-
  !,
  plan:print_slot_value(Slot).
plan:print_config_value(Key, Keyflags, Assumed) :-
  eapi:use_expand(Key),
  !,
  plan:collect_expand_flags(Keyflags, Assumed, AllFlags),
  plan:print_flags_unwrapped(AllFlags).



%! plan:print_config_item(+Key,+Value)
%
% Prints a configuration item for a given repository entry

plan:print_config_item('download',File,'live') :-
  !,
  message:color(magenta),
  message:print_bytes('live'),
  message:color(normal),
  message:print(' '),
  message:print(File).

plan:print_config_item('download',File,Size) :-
  !,
  message:color(magenta),
  message:print_bytes(Size),
  message:color(normal),
  message:print(' '),
  message:print(File).

plan:print_config_item('use',List,Assumed) :- !,
  upcase_atom('use',KeyU),
  message:print(KeyU),
  message:print('="'),
  catch(
      ( config:printing_tty_size(_, TermWidth),
        line_position(current_output, StartCol),
        collect_all_flags(List, Assumed, AllFlags),
        print_flags_wrapped(AllFlags, StartCol, TermWidth, StartCol, 0)
      ),
      error(io_error(check, stream(_)), _),
      ( collect_all_flags(List, Assumed, AllFlags),
        print_flags_unwrapped(AllFlags)
      )
  ),
  message:print('"').

plan:print_config_item('slot',Slot) :- !,
  upcase_atom('slot',KeyS),
  message:bubble(darkgray,KeyS),
  message:print(' = "'),
  message:color(darkgray),
  plan:print_slot_value(Slot),
  message:color(normal),
  message:print('"').


% New print_config_item for USE_EXPAND variables
plan:print_config_item(Key, Keyflags) :-
  eapi:use_expand(Key),
  !,
  upcase_atom(Key, KeyU),
  message:print(KeyU),
  message:print('="'),
  plan:collect_expand_flags(Keyflags, AllFlags),
  plan:print_flags_unwrapped(AllFlags),
  message:print('"').


%! plan:print_slot_value(+Slot)
%
% Prints the slot value in a readable format

plan:print_slot_value([slot(Slot)]) :-
  !,
  message:print(Slot).

plan:print_slot_value([slot(Slot),subslot(Subslot)]) :-
  !,
  message:print(Slot),
  message:print('/'),
  message:print(Subslot).

plan:print_slot_value([slot(Slot),subslot(Subslot),equal]) :-
  !,
  message:print(Slot),
  message:print('/'),
  message:print(Subslot),
  message:print('=').

plan:print_slot_value([slot(Slot),equal]) :-
  !,
  message:print(Slot),
  message:print('=').

plan:print_slot_value(Slot) :-
  message:print(Slot).


%! plan:print_flags_wrapped(+AllFlags, +StartCol, +TermWidth, +IndentForWrap, +SpacesNeeded)
%
% Prints a list of flags wrapped to the terminal width.

plan:print_flags_wrapped([], _, _, _, _) :- !.
plan:print_flags_wrapped(AllFlags, StartCol, TermWidth) :-
    foldl(plan:print_one_flag_wrapped(StartCol,TermWidth),
          AllFlags,
          [StartCol, true],
          _).


%! plan:print_one_flag_wrapped(+TermWidth, +IndentForWrap, +SpacesNeeded, +FlagTerm, +StateIn, -StateOut)
%
% Prints a single flag wrapped to the terminal width.

plan:print_one_flag_wrapped(StartCol, TermWidth, flag(Type, Flag, Assumed), [ColIn, IsFirst], [ColOut, false]) :-
    plan:get_flag_length(Type, Flag, Assumed, FlagLen),
    (IsFirst -> SpaceLen = 0 ; SpaceLen = 1),
    (
        ( ColIn + SpaceLen + FlagLen > TermWidth )
    ->  % Wrap
        (
            plan:print_continuation_prefix(StartCol),      % go to next line, print prefix, jump to start position
            plan:print_use_flag(Type, Flag, Assumed),      % print flag
            ColOut is StartCol + FlagLen
        )
    ;   % No wrap
        (
            (IsFirst -> true ; write(' ')),
            plan:print_use_flag(Type, Flag, Assumed),
            ColOut is ColIn + SpaceLen + FlagLen
        )
    ).


%! plan:print_continuation_prefix(+IndentColumn)
%
% Prints the continuation prefix for wrapped flags.

plan:print_continuation_prefix(StartColumn) :-
    nl,

    ( config:printing_style('short')  ->
        write('             │ '),
        NewStartColumn is StartColumn - 1,
        message:column(NewStartColumn,'')
    );

    ( config:printing_style('column') ->
        write('             │ '),
        NewStartColumn is StartColumn - 1,
        message:column(NewStartColumn,'')
    );
    ( config:printing_style('fancy')  ->
        write('             │                    '),
        message:color(darkgray),
        write('│ '),
        NewStartColumn is StartColumn - 1,
        message:column(NewStartColumn,'')
    );
    true.


%! plan:collect_all_flags(+List, +Assumed, -AllFlags)
%
% Collects all flags from the list and assumed flags.

plan:collect_all_flags(List, Assumed, AllFlags) :-
    (memberchk([negative:default,NegDefa],List);    NegDefa=[]),
    (memberchk([negative:ebuild,NegEbui],List);     NegEbui=[]),
    (memberchk([negative:preference,NegPref],List); NegPref=[]),
    (memberchk([negative:package_use,NegPkgUse],List); NegPkgUse=[]),
    (memberchk([negative:profile_package_use_mask,NegProfileMask],List); NegProfileMask=[]),
    (memberchk([positive:ebuild,PosEbui],List);     PosEbui=[]),
    (memberchk([positive:preference,PosPref],List); PosPref=[]),
    (memberchk([positive:package_use,PosPkgUse],List); PosPkgUse=[]),
    (memberchk([positive:profile_package_use_force,PosProfileForce],List); PosProfileForce=[]),
    sort(PosPref, OPosPref),
    sort(PosEbui, OPosEbui),
    sort(PosPkgUse, OPosPkgUse),
    sort(PosProfileForce, OPosProfileForce),
    sort(NegPref, ONegPref),
    sort(NegEbui, ONegEbui),
    sort(NegPkgUse, ONegPkgUse),
    sort(NegProfileMask, ONegProfileMask),
    sort(NegDefa, ONegDefa),
    maplist(to_flag_term(positive:preference, Assumed), OPosPref, FlagsPosPref),
    maplist(to_flag_term(positive:package_use, Assumed), OPosPkgUse, FlagsPosPkgUse),
    maplist(to_flag_term(positive:profile_package_use_force, Assumed), OPosProfileForce, FlagsPosProfileForce),
    maplist(to_flag_term(positive:ebuild, Assumed), OPosEbui, FlagsPosEbui),
    maplist(to_flag_term(negative:preference, Assumed), ONegPref, FlagsNegPref),
    maplist(to_flag_term(negative:package_use, Assumed), ONegPkgUse, FlagsNegPkgUse),
    maplist(to_flag_term(negative:profile_package_use_mask, Assumed), ONegProfileMask, FlagsNegProfileMask),
    maplist(to_flag_term(negative:ebuild, Assumed), ONegEbui, FlagsNegEbui),
    maplist(to_flag_term(negative:default, Assumed), ONegDefa, FlagsNegDefa),
    append([FlagsPosPref, FlagsPosPkgUse, FlagsPosProfileForce, FlagsPosEbui,
            FlagsNegPref, FlagsNegPkgUse, FlagsNegProfileMask, FlagsNegEbui, FlagsNegDefa],
           AllFlags).


%! plan:to_flag_term(+Type, +Assumed, +Flag, -FlagTerm)
%
% Converts a flag to a flag term.

plan:to_flag_term(Type, Assumed, Flag, flag(Type, Flag, Assumed)).


%! plan:use_changes_to_assumed(+Context, -Assumed)
%
% Extract USE flag changes from suggestion(use_change, ...) in the Context
% and convert them to the Assumed list format used by print_use_flag.
% For USE_EXPAND flags, both the full prefixed name and the stripped suffix
% are included so matching works in both regular USE and USE_EXPAND displays.

plan:use_changes_to_assumed(Context, Assumed) :-
  ( is_list(Context),
    memberchk(suggestion(use_change, _, Changes), Context),
    is_list(Changes)
  ->
    findall(A,
            ( member(Change, Changes),
              plan:use_change_to_assumed_atom(Change, A)
            ),
            Assumed)
  ; Assumed = []
  ).

plan:use_change_to_assumed_atom(use_change(F, enable), F).
plan:use_change_to_assumed_atom(use_change(F, enable), Stripped) :-
  eapi:use_expand(Key),
  eapi:strip_prefix_atom(Key, F, Stripped).
plan:use_change_to_assumed_atom(use_change(F, disable), minus(F)).
plan:use_change_to_assumed_atom(use_change(F, disable), minus(Stripped)) :-
  eapi:use_expand(Key),
  eapi:strip_prefix_atom(Key, F, Stripped).


%! plan:print_flags_unwrapped(+AllFlags)
%
% Prints a list of flags unwrapped.

plan:print_flags_unwrapped([]) :- !.
plan:print_flags_unwrapped([flag(Type, Flag, Assumed)|Rest]) :-
    plan:print_use_flag(Type, Flag, Assumed),
    (Rest == [] -> true ; write(' ')),
    plan:print_flags_unwrapped(Rest).


%! plan:get_flag_length(+Type, +Flag, +Assumed, -Length)
%
% Gets the length of a flag.

plan:get_flag_length(Type, Flag, Assumed, Length) :-
    (   memberchk(minus(Flag), Assumed) -> atom_length(Flag, L), Length is L + 1
    ;   memberchk(Flag, Assumed) -> atom_length(Flag, Length)
    ;   plan:get_flag_length_typed(Type, Flag, Length)
    ).

plan:get_flag_length_typed(positive:preference, Flag, Length) :-
    atom_length(Flag, L),
    ( preference:use(Flag,env) -> EnvExtra = 1 ; EnvExtra = 0),
    ( preference:profile_forced_use_flag(Flag) -> ProfileExtra = 1 ; ProfileExtra = 0),
    Length is L + EnvExtra + ProfileExtra.

plan:get_flag_length_typed(positive:package_use, Flag, Length) :-
    atom_length(Flag, Length).

plan:get_flag_length_typed(positive:profile_package_use_force, Flag, Length) :-
    atom_length(Flag, L),
    Length is L + 2. % parentheses

plan:get_flag_length_typed(positive:ebuild, Flag, Length) :-
    atom_length(Flag, Length).

plan:get_flag_length_typed(negative:preference, Flag, Length) :-
    atom_length(Flag, L),
    ( preference:use(minus(Flag),env) -> EnvExtra = 1 ; EnvExtra = 0), % '*' marker
    ( preference:profile_masked_use_flag(Flag) -> ProfileExtra = 1 ; ProfileExtra = 0), % '%' marker
    Length is L + 1 + EnvExtra + ProfileExtra.

plan:get_flag_length_typed(negative:package_use, Flag, Length) :-
    atom_length(Flag, L),
    Length is L + 1.

plan:get_flag_length_typed(negative:profile_package_use_mask, Flag, Length) :-
    atom_length(Flag, L),
    Length is L + 3. % (-flag)

plan:get_flag_length_typed(negative:ebuild, Flag, Length) :-
    atom_length(Flag, L),
    Length is L + 1.

plan:get_flag_length_typed(negative:default, Flag, Length) :-
    atom_length(Flag, L),
    Length is L + 1.


%! plan:print_use_flag(+Reason,+Flag,Assumed)
%
% Prints a single flag.

plan:print_use_flag(_Reason, Flag, Assumed) :-
  memberchk(minus(Flag), Assumed), !,
  message:color(orange),
  %message:style(bold),
  message:print('-'),
  message:print(Flag),
  message:color(normal).

plan:print_use_flag(_Reason, Flag, Assumed) :-
  memberchk(Flag, Assumed), !,
  message:color(orange),
  %message:style(bold),
  message:print(Flag),
  message:color(normal).

plan:print_use_flag(positive:preference, Flag, _Assumed) :-
  preference:use(Flag,env), !,
  message:color(green),
  message:style(bold),
  message:print(Flag),
  message:color(normal),
  ( preference:profile_forced_use_flag(Flag) -> message:print('%') ; true ),
  message:print('*').

plan:print_use_flag(positive:profile_package_use_force, Flag, _Assumed) :-
  !,
  message:color(green),
  message:style(bold),
  message:print('('),
  message:print(Flag),
  message:print(')'),
  message:color(normal).

plan:print_use_flag(positive:preference, Flag, _Assumed) :-
  !,
  message:color(red),
  message:style(bold),
  message:print(Flag),
  message:color(normal),
  ( preference:profile_forced_use_flag(Flag) -> message:print('%') ; true ).

plan:print_use_flag(positive:package_use, Flag, _Assumed) :-
  !,
  message:color(red),
  message:style(bold),
  message:print(Flag),
  message:color(normal).

plan:print_use_flag(positive:ebuild, Flag, _Assumed) :-
  !,
  message:color(red),
  message:style(italic),
  message:print(Flag),
  message:color(normal).

plan:print_use_flag(negative:preference, Flag, _Assumed) :-
  preference:use(minus(Flag),env), !,
  message:color(green),
  message:style(bold),
  message:print('-'),
  message:print(Flag),
  message:color(normal),
  ( preference:profile_masked_use_flag(Flag) -> message:print('%') ; true ),
  message:print('*').

plan:print_use_flag(negative:profile_package_use_mask, Flag, _Assumed) :-
  !,
  message:color(green),
  message:style(bold),
  message:print('('),
  message:print('-'),
  message:print(Flag),
  message:print(')'),
  message:color(normal).

plan:print_use_flag(negative:preference, Flag, _Assumed) :-
  !,
  message:color(blue),
  message:style(bold),
  message:print('-'),
  message:print(Flag),
  message:color(normal),
  ( preference:profile_masked_use_flag(Flag) -> message:print('%') ; true ).

plan:print_use_flag(negative:package_use, Flag, _Assumed) :-
  !,
  message:color(blue),
  message:style(bold),
  message:print('-'),
  message:print(Flag),
  message:color(normal).

plan:print_use_flag(negative:ebuild, Flag, _Assumed) :-
  !,
  message:color(lightblue),
  message:style(italic),
  message:print('-'),
  message:print(Flag),
  message:color(normal).

plan:print_use_flag(negative:default, Flag, _Assumed) :-
  !,
  message:color(darkgray),
  message:style(italic),
  message:print('-'),
  message:print(Flag),
  message:color(normal).


%! plan:check_assumptions(+Model)
%
% Checks whether the Model contains assumptions

plan:check_assumptions(Model) :-
  member(assumed(_),Model),!.


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


%! plan:print_body(+Target,+Plan,+Call,+StartStep,-Steps)
%
% Prints the body for a given plan, starting step count from StartStep.
plan:print_body(Target, Plan, Call, StartStep, Steps) :-
  plan:build_planned_pkg_set(Plan, PlannedSet),
  setup_call_cleanup(
    nb_setval(printer_planned_pkg_set, PlannedSet),
    plan:print_steps_in_plan(Target, Plan, Call, StartStep, Steps),
    ( nb_current(printer_planned_pkg_set, _) -> nb_delete(printer_planned_pkg_set) ; true )
  ).

% -----------------------------------------------------------------------------
%  Pre-actions: unmask / keyword acceptance actions shown before the plan
% -----------------------------------------------------------------------------

%! plan:collect_plan_pre_actions(+ProofAVL, -PreActions)
%
% Collects unmask and keyword acceptance actions from the proof that
% should be shown as pre-plan steps.

plan:collect_plan_pre_actions(ProofAVL, PreActions) :-
  findall(unmask(R, E, C, N),
          ( assoc:gen_assoc(rule(R://E:_A), ProofAVL, _?Ctx),
            is_list(Ctx),
            memberchk(suggestion(unmask, _), Ctx),
            cache:ordered_entry(R, E, C, N, _)
          ),
          Unmasks0),
  sort(Unmasks0, Unmasks),
  findall(accept_keyword(R, E, C, N, K),
          ( assoc:gen_assoc(rule(R://E:_A2), ProofAVL, _?Ctx2),
            is_list(Ctx2),
            memberchk(suggestion(accept_keyword, K), Ctx2),
            cache:ordered_entry(R, E, C, N, _)
          ),
          Keywords0),
  sort(Keywords0, Keywords),
  findall(use_change(R, E, C, N, Changes),
          ( assoc:gen_assoc(rule(R://E:_A3), ProofAVL, _?Ctx3),
            is_list(Ctx3),
            memberchk(suggestion(use_change, _, Changes), Ctx3),
            cache:ordered_entry(R, E, C, N, _)
          ),
          UseChanges0),
  sort(UseChanges0, UseChanges),
  append(Unmasks, Keywords, PreActions0),
  append(PreActions0, UseChanges, PreActions).

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

plan:print_pre_action(unmask(R, E, _C, _N)) :-
  message:bubble(orange, unmask),
  message:color(green),
  message:column(24, R://E),
  message:color(normal).

plan:print_pre_action(accept_keyword(R, E, _C, _N, K)) :-
  warning:keyword_atom(K, KAtom),
  message:bubble(orange, keyword),
  message:color(green),
  message:column(24, R://E),
  message:color(darkgray),
  format(atom(Msg), ' (~w)', [KAtom]),
  message:print(Msg),
  message:color(normal).

plan:print_pre_action(use_change(R, E, _C, _N, Changes)) :-
  message:bubble(orange, useflag),
  message:color(green),
  message:column(24, R://E),
  message:color(darkgray),
  plan:print_use_change_flags_wrapped(Changes),
  message:color(normal).

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

plan:planned_pkg(Action, C, N) :-
  nb_current(printer_planned_pkg_set, Set),
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


%! plan:print_steps_in_plan(+Target,+Plan,+Call,+Count,-NewCount)
%
% Print the steps in a plan.

plan:print_steps_in_plan(_, [], _, Count, Count) :- !.

plan:print_steps_in_plan(Target, [Step|Rest], Call, Count, CountFinal) :-
  plan:stable_sort_by_weight(Step, SortedRules),
  plan:print_first_in_step(Target, SortedRules, Count, CountNew),
  call(Call, SortedRules), !,
  plan:print_steps_in_plan(Target, Rest, Call, CountNew, CountFinal).


%! plan:print_first_in_step(+Target,+Step,+Count,-NewCount)
%
% Print a step in a plan
plan:print_first_in_step(_,[],Count,Count) :- !.

plan:print_first_in_step(Target,[Rule|Rest],Count,NewCount) :-
  plan:printable_element(Rule),
  NewCount is Count + 1,
  format(atom(AtomNewCount),'~t~0f~2|',[NewCount]),
  format(atom(StepNewCount),'step ~a',[AtomNewCount]),
  !,
  write(' └─'),
  message:bubble(darkgray,StepNewCount),
  write('─┤ '),
  plan:print_element(Target,Rule),
  plan:print_next_in_step(Target,Rest).

plan:print_first_in_step(Target,[_|Rest],Count,NewCount) :-
  plan:print_first_in_step(Target,Rest,Count,NewCount).


%! plan:print_next_in_step(+Target,+Step)
%
% Print a step in a plan
plan:print_next_in_step(_,[]) :- nl,nl,!.

plan:print_next_in_step(Target,[Rule|Rest]) :-
  plan:printable_element(Rule),
  !,
  nl,
  write('             │ '),
  plan:print_element(Target,Rule),
  plan:print_next_in_step(Target,Rest).

plan:print_next_in_step(Target,[_|Rest]) :-
  !,
  plan:print_next_in_step(Target,Rest).


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
  message:convert_bytes(S.total_dl, BytesStr),
  format('~7|~w to be downloaded.~n~n', [BytesStr]).

plan:footer_add_pre_actions([], S, S) :- !.
plan:footer_add_pre_actions(PreActions, S0, S) :-
  include([A]>>(A = unmask(_,_,_,_)), PreActions, UnmaskActions),
  include([A]>>(A = accept_keyword(_,_,_,_,_)), PreActions, KeywordActions),
  include([A]>>(A = use_change(_,_,_,_,_)), PreActions, UseChangeActions),
  length(UnmaskActions, NUnmask),
  length(KeywordActions, NKeyword),
  length(UseChangeActions, NUseChange),
  NewActions is S0.actions + NUnmask + NKeyword + NUseChange,
  S = S0.put(_{actions:NewActions, unmasks:NUnmask, keywords:NKeyword, usechanges:NUseChange}).

% Build the "(...)" part of the footer, omitting zero-count categories.
plan:footer_action_breakdown(S, Breakdown) :-
  ( get_dict(unmasks,    S, UnmaskCount)    -> true ; UnmaskCount    = 0 ),
  ( get_dict(keywords,   S, KeywordCount)   -> true ; KeywordCount   = 0 ),
  ( get_dict(usechanges, S, UseChangeCount) -> true ; UseChangeCount = 0 ),
  findall(Part,
          ( plan:footer_action_part(unmasks,     UnmaskCount,     unmask,      unmasks,     Part)
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


%! plan:footer_stats(+ModelAVL, -Stats)
%
% Calculates statistics by iterating over the ModelAVL using gen_assoc.

plan:footer_stats(ModelAVL, Stats) :-
   StatsInitial = stats{ass:0, con:0, naf:0, actions:0, fetches:0,
                        downloads:0, runs:0, installs:0, updates:0, downgrades:0, reinstalls:0, total_dl:0},
   findall(Key, assoc:gen_assoc(Key, ModelAVL, _), Keys),
   foldl(plan:update_stats, Keys, StatsInitial, Stats).


%! plan:footer_stats_from_plan(+Plan, -Stats)
%
% Plan-based footer stats (preferred for CLI output).
%
% The plan contains rules (and assumed rules) that are actually scheduled.
% We only count concrete actions shown in the plan (download/install/update/
% reinstall/run), matching the footer breakdown.
%
plan:footer_stats_from_plan(Plan, Stats) :-
  Stats0 = stats{actions:0, downloads:0, runs:0, installs:0, updates:0, downgrades:0, reinstalls:0, total_dl:0},
  foldl(plan:footer_stats_from_step, Plan, Stats0, Stats).

plan:footer_stats_from_step(Step, S0, S) :-
  foldl(plan:footer_stats_from_rule, Step, S0, S).

plan:footer_stats_from_rule(Rule0, S0, S) :-
  ( Rule0 = rule(HeadWithCtx, _Body)
  ; Rule0 = rule(assumed(HeadWithCtx), _Body)
  ; Rule0 = assumed(rule(HeadWithCtx, _Body))
  ),
  !,
  prover:canon_literal(HeadWithCtx, Head, _Ctx),
  plan:footer_stats_from_head(Head, S0, S).
plan:footer_stats_from_rule(_Other, S, S).

plan:footer_stats_from_head(R://E:download, S0, S) :-
  !,
  ( ebuild:download_size(preference, R://E, Bytes) -> true ; Bytes = 0 ),
  NewDownloads is S0.downloads + 1,
  NewTotalDl is S0.total_dl + Bytes,
  NewActions is S0.actions + 1,
  S = S0.put(_{downloads:NewDownloads, total_dl:NewTotalDl, actions:NewActions}).
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

%! plan:update_stats(+Key, +StatsIn, -StatsOut)
%
% Foldl helper to update stats

plan:update_stats(Key, S0, S) :-
  plan:update_stats_clauses(Key, S0, S).


%! plan:update_stats_clauses(+Key, +StatsIn, -StatsOut)
%
% The logic for updating stats based on a key.

plan:update_stats_clauses(assumed(_), S0, S) :-
  NewAss is S0.ass + 1, S = S0.put(ass, NewAss).
plan:update_stats_clauses(constraint(_), S0, S) :-
  NewCon is S0.con + 1, S = S0.put(con, NewCon).
plan:update_stats_clauses(naf(_), S0, S) :-
  NewNaf is S0.naf + 1, S = S0.put(naf, NewNaf).
plan:update_stats_clauses(_://_:fetchonly, S0, S) :-
  NewFetches is S0.fetches + 1, % NewActions is S0.actions + 1,
  S = S0.put(_{fetches:NewFetches}). %, actions:NewActions}).
plan:update_stats_clauses(R://E:download, S0, S) :-
  (ebuild:download_size(preference, R://E, Bytes) -> true ; Bytes = 0),
  NewDownloads is S0.downloads + 1, NewTotalDl is S0.total_dl + Bytes, NewActions is S0.actions + 1,
  S = S0.put(_{downloads:NewDownloads, total_dl:NewTotalDl, actions:NewActions}).
plan:update_stats_clauses(_://_:run, S0, S) :-
  NewRuns is S0.runs + 1, NewActions is S0.actions + 1,
  S = S0.put(_{runs:NewRuns, actions:NewActions}).
plan:update_stats_clauses(_://_:install, S0, S) :-
  NewInstalls is S0.installs + 1, NewActions is S0.actions + 1,
  S = S0.put(_{installs:NewInstalls, actions:NewActions}).
plan:update_stats_clauses(_://_:update, S0, S) :-
  NewUpdates is S0.updates + 1, NewActions is S0.actions + 1,
  S = S0.put(_{updates:NewUpdates, actions:NewActions}).
plan:update_stats_clauses(_://_:downgrade, S0, S) :-
  NewDowngrades is S0.downgrades + 1, NewActions is S0.actions + 1,
  S = S0.put(_{downgrades:NewDowngrades, actions:NewActions}).
plan:update_stats_clauses(_://_:reinstall, S0, S) :-
  NewReinstalls is S0.reinstalls + 1, NewActions is S0.actions + 1,
  S = S0.put(_{reinstalls:NewReinstalls, actions:NewActions}).
plan:update_stats_clauses(_://_:_, S0, S) :-
  NewActions is S0.actions + 1, S = S0.put(actions, NewActions).
plan:update_stats_clauses(_, S, S).


% -----------------------------------------------------------------------------
%  SCC decomposition display
% -----------------------------------------------------------------------------
%
% Shows the scheduler's Kosaraju SCC decomposition: which packages form
% cyclic merge-sets and the linearization order the scheduler chose.
% Controlled by config:print_scc/1.

plan:print_scc_decomposition :-
  \+ config:print_scc(true),
  !.
plan:print_scc_decomposition :-
  findall(scc(Id, Kind, Members),
          scheduler:scc_info_(Id, Kind, Members),
          SCCs0),
  ( SCCs0 == [] -> true
  ; sort(SCCs0, SCCs),
    nl,
    message:header('Scheduler SCC decomposition'),
    nl,
    config:print_scc_max_members(MaxMembers),
    forall(member(scc(Id, Kind, Members), SCCs),
           plan:print_scc_component(Id, Kind, Members, MaxMembers)),
    nl
  ).

plan:print_scc_component(Id, Kind, Members, MaxMembers) :-
  length(Members, N),
  ( Kind == merge_set ->
      message:color(orange),
      format('  SCC #~w (merge-set, ~w members):~n', [Id, N])
  ; message:color(red),
    format('  SCC #~w (~w, ~w members):~n', [Id, Kind, N])
  ),
  message:color(normal),
  ( N =< MaxMembers ->
      DisplayMembers = Members,
      Omitted = 0
  ; length(DisplayMembers, MaxMembers),
    append(DisplayMembers, _, Members),
    Omitted is N - MaxMembers
  ),
  forall(member(M, DisplayMembers),
         plan:print_scc_member(M)),
  ( Omitted > 0 ->
      message:color(darkgray),
      format('    (… ~w more members omitted)~n', [Omitted]),
      message:color(normal)
  ; true
  ),
  nl.

plan:print_scc_member(Head) :-
  ( Head = _Repo://Entry:Action ->
      message:color(darkgray),
      message:print('    '),
      message:color(normal),
      message:bubble(darkgray, Action),
      message:color(darkgray),
      message:print(' '),
      message:color(normal),
      message:print(Entry),
      nl
  ; Head = _Repo://Entry ->
      message:print('    '),
      message:print(Entry),
      nl
  ; format('    ~w~n', [Head])
  ).
