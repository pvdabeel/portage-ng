% -----------------------------------------------------------------------------
%  Action: Build time estimation
% -----------------------------------------------------------------------------

%! action:process_estimate(+Args) is det.
%
% Show estimated build time for the given packages. Accepts
% category/name or bare package name arguments.

process_estimate([]) :-
  message:failure('Usage: portage-ng --estimate category/name ...').

process_estimate(Args) :-
  ( \+ catch(config:buildtime_enabled(true), _, fail)
  -> message:warning(['Build time estimation is disabled.'])
  ; forall(member(Arg, Args),
      ( interface:resolve_pkg_arg(Arg, Cat, Name)
      -> buildtime:print_estimate(Cat, Name)
      ; message:warning(['Package not found: ', Arg])
      )),
    findall(Cat/Name,
      ( member(Arg, Args),
        interface:resolve_pkg_arg(Arg, Cat, Name) ),
      Actions),
    ( Actions \== []
    -> nl, buildtime:print_plan_estimate(Actions)
    ; true
    )
  ).