% -----------------------------------------------------------------------------
%  Action: DESELECT (remove from world)
% -----------------------------------------------------------------------------

%! action:process_deselect(+Args) is det.
%
% Removes each positional argument from the world set file.
% The package remains installed but will no longer be tracked
% for @world updates.

process_deselect(Args) :-
  ( Args == []
  -> message:failure('No targets specified for --deselect.')
  ;  forall(member(Arg, Args),
       ( world:unregister(Arg),
         message:inform(['Removed \'', Arg, '\' from world set.'])
       )),
     world:save,
     message:inform(['World set saved.'])
  ).