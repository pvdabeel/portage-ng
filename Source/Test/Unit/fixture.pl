/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> FIXTURE
Fixtures shared by more than one unit test file.

Process-global state a unit must start from empty is stashed here and
put back afterwards, so a unit test never leaks into the session that
loaded it.
*/

:- module(fixture, [stash_selected_cn_snap/1,
                   restore_selected_cn_snap/1]).

:- use_module(library(assoc)).
:- use_module(library(lists)).

% =============================================================================
%  FIXTURE declarations
% =============================================================================

%! stash_selected_cn_snap(-Saved) is det.
%
% Save the live selected-CN / blocked-CN-source snapshot stores (see
% cnselect:save_cn_snapshots/1) and start the unit from empty ones.

stash_selected_cn_snap(Saved) :-
  cnselect:save_cn_snapshots(Saved),
  cnselect:clear_cn_snapshots.


%! restore_selected_cn_snap(+Saved) is det.

restore_selected_cn_snap(Saved) :-
  cnselect:restore_cn_snapshots(Saved).
