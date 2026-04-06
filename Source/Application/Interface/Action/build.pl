/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

% -----------------------------------------------------------------------------
%  Action: RESUME (skip args helper)
% -----------------------------------------------------------------------------

%! action:assert_resume_skip_args(+Args) is det.
%
% Asserts each positional argument as a config:skip_atom/1 fact.
% When --resume is active, positional args name packages to skip.

action:assert_resume_skip_args([]).

action:assert_resume_skip_args([A|Rest]) :-
  asserta(config:skip_atom(A)),
  assert_resume_skip_args(Rest).


% -----------------------------------------------------------------------------
%  Action: BUILD
% -----------------------------------------------------------------------------

%! action:process_build(+Args, +Options) is det.
%
% Handles the --build CLI flag. Resolves targets, proves a plan, then
% builds with live progress output.

action:process_build([], _Options) :-
  !,
  message:failure('No targets specified for --build.').

action:process_build(ArgsSets, _Options) :-
  eapi:substitute_sets(ArgsSets, Args),
  interface:report_unresolvable_targets(run, Args),
  findall(target(Q,Arg):run?{[]},
          ( member(Arg, Args),
            atom_codes(Arg, Codes),
            phrase(eapi:qualified_target(Q), Codes),
            once(kb:query(Q, _R://_E))
          ),
          Proposal),
  !,
  ( Proposal == []
  -> message:failure('No valid targets found.')
  ;  builder:build(Proposal)
  ).