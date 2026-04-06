/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

% -----------------------------------------------------------------------------
%  Action: UPSTREAM (version checking)
% -----------------------------------------------------------------------------

%! action:process_upstream(+Args, +Options) is det.
%
% Checks upstream for newer versions of the specified packages.
% Defaults to @world when no arguments are given.

action:process_upstream(Args, _Options) :-
  ( Args == []
  -> upstream:check([world])
  ;  upstream:check(Args)
  ).