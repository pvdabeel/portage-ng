/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

% -----------------------------------------------------------------------------
%  Action: DESELECT (remove from world)
% -----------------------------------------------------------------------------

%! action:process_deselect(+Args) is det.
%
% Removes each positional argument from the world set file.
% The package remains installed but will no longer be tracked
% for @world updates.

action:process_deselect(Args) :-
  ( Args == []
  -> message:failure('No targets specified for --deselect.')
  ;  forall(member(Arg, Args),
       ( world:unregister(Arg),
         message:inform(['Removed \'', Arg, '\' from world set.'])
       )),
     world:save,
     message:inform(['World set saved.'])
  ).