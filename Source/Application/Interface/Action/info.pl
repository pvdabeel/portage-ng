% -----------------------------------------------------------------------------
%  Action: INFO
% -----------------------------------------------------------------------------

%! action:process_action(+info, +Args, +Options) is det.
%
% Handles the --info CLI flag. With no arguments, prints system info.
% With arguments, prints detailed information for each matching package.

process_action(info,[],_) :-
  !,
  interface:print_system_info.

process_action(info,Args,_Options) :-
  !,
  forall(member(Arg, Args),
    ( atom_codes(Arg, Codes),
      ( phrase(eapi:qualified_target(Q), Codes),
        once(kb:query(Q, R://E))
      -> info:print_entry(R://E)
      ; message:warning(['Package not found: ', Arg])
      )
    )).