/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> ISSUE
Known tree issues and dependency resolution notes.

This module documents known issues in the Portage tree that cause
domain assumptions during proof search. When the prover encounters
an unsatisfiable dependency, the printer can check this module to
provide supplementary information to the end user.

Issue categories:
  - version_range_gap : version constraints define a range with no
    available candidate in the tree
  - missing_package   : package does not exist in any repository
  - slot_mismatch     : dependency requires a slot that no candidate provides

@see Source/explanation.pl for assumption reason classification
@see Source/printer.pl for rendering domain assumptions with notes
*/

:- module(issue, []).


% =============================================================================
%  Known tree issues
% =============================================================================

%! issue:known_tree_issue(+Category, +Name, -Description) is nondet.
%
% Documents a known tree issue for category/name pair.
% Description is a human-readable atom explaining the issue.

issue:known_tree_issue('dev-php', 'composer',
    'Package dev-php/composer does not exist in the Portage tree.').

issue:known_tree_issue('dev-python', 'cryptography',
    'Version range gap: some consumers require >=45.0.7 <46 but only 45.0.6 and 46.x are available.').


% =============================================================================
%  Runtime tree issue detection
% =============================================================================

%! issue:detect_version_range_gap(+C, +N, +PackageDeps) is semidet.
%
% Succeeds when PackageDeps define a version range (lower + upper bound)
% for which no candidate exists in the tree. This is a common tree issue
% where an ebuild specifies a narrow version range that falls between
% available releases.

issue:detect_version_range_gap(C, N, PackageDeps) :-
  member(package_dependency(_,no,C,N,OpLo,VLo,_,_), PackageDeps),
  member(package_dependency(_,no,C,N,OpHi,VHi,_,_), PackageDeps),
  OpLo \== OpHi,
  memberchk(OpLo, [greaterequal, greater]),
  memberchk(OpHi, [smallerequal, smaller]),
  \+ ( query:search([category(C), name(N)], Repo://Entry),
       query:search(select(version, OpLo, VLo), Repo://Entry),
       query:search(select(version, OpHi, VHi), Repo://Entry)
     ).


%! issue:tree_issue_context(+C, +N, +PackageDeps, -Note) is semidet.
%
% Provides a supplementary note for the user when a domain assumption
% matches a known tree issue or a detectable pattern.

issue:tree_issue_context(C, N, _PackageDeps, Note) :-
  issue:known_tree_issue(C, N, Note),
  !.
issue:tree_issue_context(C, N, PackageDeps, Note) :-
  issue:detect_version_range_gap(C, N, PackageDeps),
  !,
  format(atom(Note),
         'Tree issue: version range gap for ~w/~w — no candidate satisfies the combined version constraints.',
         [C, N]).