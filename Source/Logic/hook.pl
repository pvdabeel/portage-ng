/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> HOOK
Memoised presence test for optional (hook) predicates.

Many hot paths guard an optional domain hook or configuration fact with
`current_predicate(Module:Name/Arity)` before calling it. That builtin
resolves the module through SWI-Prolog's global module table, which is
protected by one process-wide mutex; with ten prover threads each asking
thousands of times per proof the mutex becomes a serialisation point.

hook:defined/1 gives the same answer as current_predicate/1 for a fully
instantiated `Module:Name/Arity` indicator but remembers every positive
answer in a plain fact. A predicate that is defined stays defined for the
lifetime of the process (nothing in this code base abolishes predicates),
so a positive answer can be cached indefinitely. A negative answer is
never cached: the next call asks current_predicate/1 again, so a hook
that is loaded later is picked up as soon as it exists.
*/

:- module(hook, []).

% =============================================================================
%  HOOK declarations
% =============================================================================

:- dynamic hook:defined_/3.


% -----------------------------------------------------------------------------
%  Presence test
% -----------------------------------------------------------------------------

%! hook:defined(+PredicateIndicator) is semidet.
%
% True when the predicate denoted by `Module:Name/Arity` is defined,
% exactly as current_predicate/1 would report. Positive answers are
% memoised in hook:defined_/3; negative answers fall through to
% current_predicate/1 on every call.

hook:defined(Module:Name/Arity) :-
  ( hook:defined_(Module, Name, Arity) ->
      true
  ; current_predicate(Module:Name/Arity) ->
      hook:remember(Module, Name, Arity)
  ).


%! hook:remember(+Module, +Name, +Arity) is det.
%
% Records a positive presence answer. A concurrent thread may already
% have recorded the same indicator; the duplicate check keeps the table
% free of repeated facts.

hook:remember(Module, Name, Arity) :-
  ( hook:defined_(Module, Name, Arity) ->
      true
  ; assertz(hook:defined_(Module, Name, Arity))
  ).
