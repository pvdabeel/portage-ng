/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

% -----------------------------------------------------------------------------
%  Action: INFO
% -----------------------------------------------------------------------------

%! action:process_action(+info, +Args, +Options) is det.
%
% Handles the --info CLI flag. With no arguments, prints system info.
% With arguments, prints detailed information for each matching package.

action:process_action(info,[],_) :-
  !,
  interface:print_system_info.

action:process_action(info,Args,_Options) :-
  !,
  forall(member(Arg, Args),
    ( atom_codes(Arg, Codes),
      ( phrase(eapi:qualified_target(Q), Codes),
        once(kb:query(Q, R://E))
      -> info:print_entry(R://E)
      ; message:warning(['Package not found: ', Arg])
      )
    )).