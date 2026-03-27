% -----------------------------------------------------------------------------
%  Action: DEPCLEAN
% -----------------------------------------------------------------------------

%! action:process_action(+depclean, +ArgsSets, +Options) is det.
%
% Handles the --depclean CLI flag. Delegates to depclean:run/1.

process_action(depclean, ArgsSets, _Options) :-
  !,
  depclean:run(ArgsSets).


% -----------------------------------------------------------------------------
%  Action: UPGRADE (emptytree + depclean, two-phase)
% -----------------------------------------------------------------------------

%! action:process_upgrade(+ArgsSets, +Options) is det.
%
% Two-phase Portage-like upgrade:
%   Phase A: compute a fresh plan under --emptytree (ignores installed shortcuts)
%   Phase B: run depclean on the real installed graph
%
% Defaults to @world when no positional arguments are given.
% Enforces --oneshot semantics so @world is not modified.

process_upgrade(ArgsSets0, Options) :-
  ( ArgsSets0 == [] -> ArgsSets = [world] ; ArgsSets = ArgsSets0 ),
  setup_call_cleanup(
    ( asserta(preference:local_flag(oneshot)),
      asserta(preference:local_flag(emptytree))
    ),
    process_action(run, ArgsSets, Options),
    ( retractall(preference:local_flag(emptytree)),
      retractall(preference:local_flag(oneshot))
    )
  ),
  process_action(depclean, ArgsSets, Options).