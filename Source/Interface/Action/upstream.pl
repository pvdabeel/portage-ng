% -----------------------------------------------------------------------------
%  Action: UPSTREAM (version checking)
% -----------------------------------------------------------------------------

%! action:process_upstream(+Args, +Options) is det.
%
% Checks upstream for newer versions of the specified packages.
% Defaults to @world when no arguments are given.

process_upstream(Args, _Options) :-
  ( Args == []
  -> upstream:check([world])
  ;  upstream:check(Args)
  ).