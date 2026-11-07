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
% Save the live selected-CN snapshot (memo_selected_cn_snap, see
% cnselect.pl) and start the unit from an empty one. Saved is the
% previous store, or `none` when the global was not set.

stash_selected_cn_snap(Saved) :-
  ( nb_current(memo_selected_cn_snap, Saved) -> true ; Saved = none ),
  nbstore:reset(memo_selected_cn_snap).


%! restore_selected_cn_snap(+Saved) is det.

restore_selected_cn_snap(none) :-
  !,
  nb_delete(memo_selected_cn_snap).
restore_selected_cn_snap(Saved) :-
  nb_setval(memo_selected_cn_snap, Saved).
