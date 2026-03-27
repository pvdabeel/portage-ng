% -----------------------------------------------------------------------------
%  Action: ROLLBACK (snapshot dispatch)
% -----------------------------------------------------------------------------

%! action:process_rollback(+Id, +Options) is det.
%
% Dispatches rollback: with --pretend shows diff, without executes
% the actual rollback.

process_rollback(Id, Options) :-
  ( memberchk(pretend(true), Options)
  -> snapshot:diff(Id)
  ;  snapshot:diff(Id),
     nl,
     format('Proceeding with rollback...~n'),
     nl,
     snapshot:rollback(Id)
  ).