/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> REPORT
Displays a summary of potential problems with installed packages. Checks
for packages removed from the tree, masked packages, keyword issues, and
available updates.
*/

:- module(report, []).

% =============================================================================
%  REPORT declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Health check
% -----------------------------------------------------------------------------

%! report:check(-Results) is det.
%
% Scans installed packages and returns a list of issue(Entry, Type, Detail)
% terms describing potential problems.

report:check(Results) :-
  findall(Issue,
    ( vdb:find_installed_pkg(portage://Entry),
      report:check_entry(Entry, Issue)
    ),
    Results).


%! report:check_entry(+Entry, -Issue) is nondet.
%
% Generates issue terms for a single installed package entry.

report:check_entry(Entry, issue(Entry, removed, 'Package no longer in portage tree')) :-
  split_string(Entry, "/", "", [CatS, _PVS]),
  atom_string(Cat, CatS),
  report:extract_name(Entry, Name),
  \+ cache:ordered_entry(portage, _, Cat, Name, _).

report:check_entry(Entry, issue(Entry, masked, 'Package is masked in current tree')) :-
  split_string(Entry, "/", "", [CatS, _PVS]),
  atom_string(Cat, CatS),
  report:extract_name(Entry, Name),
  cache:ordered_entry(portage, _, Cat, Name, _),
  \+ ( cache:ordered_entry(portage, PE, Cat, Name, _),
       \+ cache:entry_metadata(portage, PE, masked, true)
     ).

report:check_entry(Entry, issue(Entry, update, Detail)) :-
  split_string(Entry, "/", "", [CatS, _PVS]),
  atom_string(Cat, CatS),
  report:extract_name(Entry, Name),
  catch(
    ( vdb:outdated(Cat, Name, _, portage://Latest),
      format(atom(Detail), 'Update available: ~w', [Latest])
    ),
    _, fail
  ).


%! report:extract_name(+Entry, -Name) is det.
%
% Extracts the package name from a Category/Name-Version entry by
% finding the installed cache entry.

report:extract_name(Entry, Name) :-
  ( cache:ordered_entry(pkg, Entry, _, Name, _) -> true
  ; split_string(Entry, "/", "", [_, PVS]),
    atom_string(PVAtom, PVS),
    ( sub_atom(PVAtom, B, 1, _, '-'),
      B > 0,
      BA is B + 1,
      sub_atom(PVAtom, BA, 1, _, C),
      char_type(C, digit)
    -> sub_atom(PVAtom, 0, B, _, Name)
    ; Name = PVAtom
    )
  ).


% -----------------------------------------------------------------------------
%  Report printing
% -----------------------------------------------------------------------------

%! report:print_results(+Results) is det.
%
% Formats and prints the health report results.

report:print_results(Results) :-
  message:topheader(['Installed package report']),
  nl,
  ( Results == [] ->
    message:inform('No problems detected.')
  ; report:partition_issues(Results, Removed, Masked, Updates),
    ( Removed \== [] ->
      message:header(['Packages removed from tree']),
      nl,
      forall(member(issue(E, _, _), Removed),
        format('  ~w~n', [E])),
      nl
    ; true
    ),
    ( Masked \== [] ->
      message:header(['Keyword-masked packages']),
      nl,
      forall(member(issue(E, _, D), Masked),
        format('  ~w (~w)~n', [E, D])),
      nl
    ; true
    ),
    ( Updates \== [] ->
      message:header(['Available updates']),
      nl,
      forall(member(issue(E, _, D), Updates),
        format('  ~w - ~w~n', [E, D])),
      nl
    ; true
    ),
    length(Results, Total),
    format('~w issue(s) found.~n', [Total])
  ).


%! report:partition_issues(+Results, -Removed, -Masked, -Updates) is det.
%
% Partitions the list of issues into three lists: Removed, Masked, and Updates.

report:partition_issues([], [], [], []).

report:partition_issues([issue(E,removed,D)|Rest], [issue(E,removed,D)|R], M, U) :-
  report:partition_issues(Rest, R, M, U).

report:partition_issues([issue(E,masked,D)|Rest], R, [issue(E,masked,D)|M], U) :-
  report:partition_issues(Rest, R, M, U).

report:partition_issues([issue(E,update,D)|Rest], R, M, [issue(E,update,D)|U]) :-
  report:partition_issues(Rest, R, M, U).

report:partition_issues([_|Rest], R, M, U) :-
  report:partition_issues(Rest, R, M, U).