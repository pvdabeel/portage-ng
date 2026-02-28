/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> CONSTRAINT
Constraint unification and management for the prover.

Provides the constraint data type, incremental constraint unification
(merging new constraint values into the accumulated constraint AVL),
and conversion utilities between constraint AVL trees and lists.

Domain-specific merge logic can be injected via the
=rules:constraint_unify_hook/4= hook; the generic fallback handles
ordsets, atoms, lists, and AVL-to-AVL merging.
*/

:- module(constraint, []).

% =============================================================================
%  CONSTRAINT declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Identification
% -----------------------------------------------------------------------------

%! constraint:is_constraint(+Literal)
%
% Check if a literal is a constraint.

constraint:is_constraint(constraint(_)).


% -----------------------------------------------------------------------------
%  Unification
% -----------------------------------------------------------------------------


%! constraint:unify_constraints(+Constraint, +Constraints, -NewConstraints)
%
% Unify a constraint with the current constraints.  Domain-specific
% merge logic is delegated to =rules:constraint_unify_hook/4=.

constraint:unify_constraints(constraint(Key:{Value}), Constraints, NewConstraints) :-
  current_predicate(rules:constraint_unify_hook/4),
  rules:constraint_unify_hook(Key, Value, Constraints, NewConstraints),
  !.

constraint:unify_constraints(constraint(Key:{Value}),Constraints,NewConstraints) :-
  Value = ordset(List),
  is_list(List),
  !,
  sort(List, NewSet),
  ( get_assoc(Key, Constraints, ordset(CurSet0), Constraints1, ordset(CurSet0)) ->
      ord_union(CurSet0, NewSet, CurSet),
      put_assoc(Key, Constraints1, ordset(CurSet), NewConstraints)
  ; put_assoc(Key, Constraints, ordset(NewSet), NewConstraints)
  ).

constraint:unify_constraints(constraint(Key:{Value}),Constraints,NewConstraints) :-
  get_assoc(Key,Constraints,CurrentValue,NewConstraints,NewValue),!,
  constraint:unify_constraint(Value,CurrentValue,NewValue).

constraint:unify_constraints(constraint(Key:{Value}),Constraints,NewConstraints) :-
  constraint:unify_constraint(Value,{},NewValue),
  put_assoc(Key,Constraints,NewValue,NewConstraints).


%! constraint:unify_constraint(+Value, +Current, -Merged) is det
%
% Merge a new constraint value with the current stored value.
% Dispatches on type: empty (`{}`), atom, list, or existing AVL.
% When the current value is an AVL and the new value is a list,
% the list elements are proved into the existing AVL via
% prover:prove_recursive/9.

constraint:unify_constraint([],{},Assoc) :-
  empty_assoc(Assoc),!.

constraint:unify_constraint(Atom,{},Atom) :-
  is_of_type(atom,Atom),!.

constraint:unify_constraint(List,{},Assoc) :-
  is_list(List),!, prover:list_to_assoc(List,Assoc).

constraint:unify_constraint([],Assoc,Assoc) :-
  is_assoc(Assoc),!.

constraint:unify_constraint(Atom,Atom,Atom) :-
  is_of_type(atom,Atom),!.

constraint:unify_constraint(List,E,Assoc) :-
  is_list(List), empty_assoc(E),!,
  prover:list_to_assoc(List,Assoc).

constraint:unify_constraint(List,M,Assoc) :-
  is_of_type(list,List), is_assoc(M),!,
  prover:prove_recursive(List,t,_,M,Assoc,t,_,t,_).


% -----------------------------------------------------------------------------
%  Conversion utilities
% -----------------------------------------------------------------------------

%! constraint:constraints_to_list(+Assoc, -List)
%
% Convert an AVL constraints tree to a list.

constraint:constraints_to_list(Assoc, List) :-
  findall(Full,
          (gen_assoc(Key,Assoc,Value),
           prover:canon_literal(Full,Key,Value)),
          List).


%! constraint:list_to_constraints(+List, -Assoc)
%
% Convert a list to an AVL constraints tree.

constraint:list_to_constraints(List, Assoc) :-
  empty_assoc(Empty),
  foldl(constraint:add_to_constraints, List, Empty, Assoc).


%! constraint:add_to_constraints(+Full, +InAssoc, -OutAssoc) is det

constraint:add_to_constraints(Full, InAssoc, OutAssoc) :-
  prover:canon_literal(Full, Key, Value),
  put_assoc(Key, InAssoc, Value, OutAssoc).
