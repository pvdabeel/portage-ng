/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> CONSTRAINTTEST
Unit tests for the constraint store (Source/Logic/constraint.pl).

Constraint identification, unification and conversion.
*/

:- module(constrainttest, []).

:- use_module(library(plunit)).
:- use_module(library(assoc)).
:- use_module(library(lists)).

% =============================================================================
%  CONSTRAINTTEST declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Constraint module tests
% -----------------------------------------------------------------------------

:- begin_tests(constraint_identification).

test(is_constraint_true) :-
  constraint:is_constraint(constraint(foo)).

test(is_constraint_false, [fail]) :-
  constraint:is_constraint(not_a_constraint).

:- end_tests(constraint_identification).


:- begin_tests(constraint_unification).

test(unify_ordset_new) :-
  empty_assoc(C0),
  constraint:unify_constraints(constraint(k:{ordset([b,a,c])}), C0, C1),
  get_assoc(k, C1, ordset(V)),
  V == [a,b,c].

test(unify_ordset_merge) :-
  empty_assoc(C0),
  put_assoc(k, C0, ordset([a,c]), C1),
  constraint:unify_constraints(constraint(k:{ordset([b,d])}), C1, C2),
  get_assoc(k, C2, ordset(V)),
  V == [a,b,c,d].

test(unify_atom_new) :-
  empty_assoc(C0),
  constraint:unify_constraints(constraint(k:{hello}), C0, C1),
  get_assoc(k, C1, V),
  V == hello.

test(unify_atom_same_existing) :-
  empty_assoc(C0),
  put_assoc(k, C0, hello, C1),
  constraint:unify_constraints(constraint(k:{hello}), C1, C2),
  get_assoc(k, C2, V),
  V == hello.

test(unify_empty_list_new) :-
  empty_assoc(C0),
  constraint:unify_constraints(constraint(k:{[]}), C0, C1),
  get_assoc(k, C1, V),
  is_assoc(V).

test(unify_list_new) :-
  empty_assoc(C0),
  constraint:unify_constraints(constraint(k:{[a:install]}), C0, C1),
  get_assoc(k, C1, V),
  get_assoc(a:install, V, {}).

test(unify_empty_list_into_existing_assoc) :-
  empty_assoc(E),
  constraint:unify_constraint([], E, Out),
  Out == E.

test(unify_list_into_empty_assoc) :-
  empty_assoc(E),
  constraint:unify_constraint([a:install], E, Out),
  get_assoc(a:install, Out, {}).

:- end_tests(constraint_unification).


:- begin_tests(constraint_conversion).

test(empty_to_list, [true(L == [])]) :-
  empty_assoc(A),
  constraint:constraints_to_list(A, L).

test(list_to_constraints_roundtrip, [true(L == [pkg:install?{[flag]}])]) :-
  constraint:list_to_constraints([pkg:install?{[flag]}], A),
  constraint:constraints_to_list(A, L).

:- end_tests(constraint_conversion).


% -----------------------------------------------------------------------------
%  Feature unification (Source/Logic/unify.pl)
% -----------------------------------------------------------------------------

:- begin_tests(feature_unification_unit).

test(normalize_ft_and_negation_helpers) :-
  feature_unification:normalize_ft({}, []),
  feature_unification:normalize_ft([a], [a]),
  feature_unification:normalize_ft(non_list, non_list),
  feature_unification:is_neg_wrapper(minus(x)),
  feature_unification:is_neg_wrapper(naf(x)),
  feature_unification:negates(minus(x), x),
  feature_unification:negates(naf(x), x),
  feature_unification:list_canon_and_check([b, a], [a, b]),
  \+ feature_unification:list_canon_and_check([a, minus(a)], _),
  \+ feature_unification:list_canon_and_check([a, naf(a)], _),
  \+ feature_unification:add_singleton([a, b], [], _).

test(val_all_cases_and_vunify) :-
  % CASE 2: {..} x {..}
  feature_unification:val({[a, b]}, {[b, c]}, {[b]}),
  \+ feature_unification:val({[a]}, {[b]}, _),
  % CASE 2b: [] x [], [] x [..], [..] x []
  feature_unification:val([], [], []),
  feature_unification:val([], [a], [a]),
  feature_unification:val([a], [], [a]),
  % CASE 3: [..] x [..]
  feature_unification:val([a], [b], [a, b]),
  % CASE 4: [..] x {..} and [] x {..}
  feature_unification:val([a, b], {[a, b]}, {[a, b]}),
  feature_unification:val([], {[a]}, {[a]}),
  % CASE 5: {..} x [..] and {..} x []
  feature_unification:val({[a, b]}, [a, b], {[a, b]}),
  feature_unification:val({[a]}, [], {[a]}),
  % CASE 6 & 7: atom x [..] and [..] x atom
  feature_unification:val(a, [b], [a, b]),
  feature_unification:val([a], b, [a, b]),
  % CASE 8 & 9: atom x {..} and {..} x atom
  feature_unification:val(a, {[a, b]}, a),
  feature_unification:val({[a, b]}, b, b),
  % unify/3 with plain items, naf conflicts, and colon pairs
  feature_unification:unify([k:[a], plain1], [k:[b], plain1, plain2], U),
  memberchk(k:[a, b], U),
  \+ feature_unification:unify([plain1], [naf(plain1)], _),
  \+ feature_unification:unify([naf(plain1)], [plain1], _).

:- end_tests(feature_unification_unit).


% -----------------------------------------------------------------------------
%  Contextual OO programming (Source/Logic/context.pl)
% -----------------------------------------------------------------------------

:- begin_tests(context_oo_unit).

test(class_inheritance_instantiation_and_destruction, [nondet]) :-
  % Base class declaration with all visibility/property types
  ctx_base:class,
  ctx_base:dpublic([ctx_base/0, '~ctx_base'/0, pub_m/1]),
  ctx_base:dprotected([prot_m/1]),
  ctx_base:dprivate([priv_m/1]),
  ctx_base:ddynamic([dyn_m/1]),
  ctx_base:dstatic([stat_m/1]),
  ctx_aux:dmutex([mut_m/1]),
  ctx_base:declare(custom_meta(1)),
  assertz(ctx_base:(ctx_base ::- true)),
  assertz(ctx_base:('~ctx_base' ::- true)),
  assertz(ctx_base:(pub_m(X) ::- ( :prot_m(X), :priv_m(X) ))),
  assertz(ctx_base:(prot_m(ok) ::- true)),
  assertz(ctx_base:(priv_m(ok) ::- true)),
  assertz(ctx_base:(stat_m(s_ok) ::- true)),
  assertz(ctx_base:stat_m(s_ok)),
  % Subclass inheriting from ctx_base
  ctx_sub:class([ctx_base]),
  ctx_sub:dpublic([sub_m/1]),
  assertz(ctx_sub:(sub_m(X) ::- :pub_m(X))),
  % Error on inheriting from non-class
  catch(ctx_bad:inherit(nonexistent_class_xyz),
        error(existence_error(class, nonexistent_class_xyz), _), true),
  % Instantiation and method dispatch
  ctx_inst:newinstance(ctx_base),
  ctx_inst:implemented(pub_m/1),
  ctx_inst:pub_m(ok),
  ctx_inst://pub_m(ok),
  ctx_inst:stat_m(s_ok),
  context:instances(ctx_base, ctx_inst),
  % Private and protected access guards reject unauthenticated external calls
  catch(ctx_inst:priv_m(_), error(permission_error(access, private, _), _), true),
  catch(ctx_inst:prot_m(_), error(permission_error(access, protected, _), _), true),
  % Conflicting fact declarations
  context:conflicting(type(a), type(b)),
  context:conflicting(property(f/1, public), property(f/1, private)),
  % Destruction of static module is rejected; dynamic instance and class succeed
  catch(~set, error(permission_error(destroy, static_context, set), _), true),
  ~ctx_inst,
  ~ctx_sub,
  ~ctx_base.

:- end_tests(context_oo_unit).
