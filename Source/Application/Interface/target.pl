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
  forall((member(Arg, Args), Arg \== '--'),
    ( atom_codes(Arg, Codes),
      ( \+ phrase(eapi:qualified_target(_), Codes)
      -> message:warning(['Cannot parse target: ', Arg])
      ; phrase(eapi:qualified_target(Q), Codes),
        ( Action == uninstall
        -> ( interface:target_query_installed(Q)
           -> true
           ;  message:warning(['Not installed: ', Arg])
           )
        ; ( interface:target_query_exists(Q)
          -> true
          ;  message:warning(['Package not found: ', Arg])
          )
        )
      )
    )).


%! interface:target_query_exists(+Q) is semidet.
%
% True when Q matches at least one knowledge-base entry. Uses a copy
% of Q so an unbound repository slot is not filled in by the first
% hit (the tree is registered before overlays).

interface:target_query_exists(Q) :-
  copy_term(Q, Q0),
  once(kb:query(Q0, _://_)).


%! interface:target_query_installed(+Q) is semidet.
%
% Like target_query_exists/1, but requires an installed (VDB) match.

interface:target_query_installed(Q) :-
  copy_term(Q, Q0),
  once((kb:query(Q0, R://E), kb:query(installed(true), R://E))).


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
  -> atomic_list_concat(Rest, ', ', RestAtom),
     message:inform(['Multiple categories for ', Arg, ': ',
                      Cat, ' (using first). Others: ', RestAtom])
  ; true
  ).