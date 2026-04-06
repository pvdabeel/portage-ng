/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

% -----------------------------------------------------------------------------
%  Action: ROLLBACK (snapshot dispatch)
% -----------------------------------------------------------------------------

%! action:process_rollback(+Id, +Options) is det.
%
% Dispatches rollback: with --pretend shows diff, without executes
% the actual rollback.

action:process_rollback(Id, Options) :-
  ( memberchk(pretend(true), Options)
  -> snapshot:diff(Id)
  ;  snapshot:diff(Id),
     nl,
     format('Proceeding with rollback...~n'),
     nl,
     snapshot:rollback(Id)
  ).