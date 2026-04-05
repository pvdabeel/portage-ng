/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> TARGET
Target validation and resolution for CLI commands.
*/

% -----------------------------------------------------------------------------
%  Target validation helper
% -----------------------------------------------------------------------------

%! interface:report_unresolvable_targets(+Action, +Args) is det.
%
% Prints a warning for each target argument that cannot be parsed
% or has no matching entry in the knowledge base.

interface:report_unresolvable_targets(Action, Args) :-
  forall(member(Arg, Args),
    ( atom_codes(Arg, Codes),
      ( \+ phrase(eapi:qualified_target(_), Codes)
      -> message:warning(['Cannot parse target: ', Arg])
      ; phrase(eapi:qualified_target(Q), Codes),
        ( Action == uninstall
        -> ( once((kb:query(Q, R0://E0), kb:query(installed(true), R0://E0)))
           -> true
           ;  message:warning(['Not installed: ', Arg])
           )
        ; ( once(kb:query(Q, _R://_E))
          -> true
          ;  message:warning(['Package not found: ', Arg])
          )
        )
      )
    )).


% -----------------------------------------------------------------------------
%  Resolve package argument
% -----------------------------------------------------------------------------

%! interface:resolve_pkg_arg(+Arg, -Cat, -Name) is semidet.
%
% Resolve a package argument to Category and Name. Accepts both
% category/name (e.g. sys-devel/gcc) and bare name (e.g. gcc).
% For bare names, looks up the knowledge base for a matching package.
% When multiple categories match, picks the first one and informs
% the user.

interface:resolve_pkg_arg(Arg, Cat, Name) :-
  atomic_list_concat([Cat, Name], '/', Arg), !.

interface:resolve_pkg_arg(Arg, Cat, Arg) :-
  findall(C, cache:package(_, C, Arg), Cats0),
  sort(Cats0, Cats),
  Cats = [Cat|Rest],
  ( Rest \== []
  -> message:inform(['Multiple categories for ', Arg, ': ',
                      Cat, ' (using first). Others: ', Rest])
  ; true
  ).