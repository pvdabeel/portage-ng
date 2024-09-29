/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2024, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> CONTEXT
Context is an object-oriented programming paradigm for Prolog. It implements
contexts (namespaces), classes and instances. It supports various inheritance
mechanisms. Access to member predicates is regulated through public/protected
& private meta-predicates. We enable declarative static typing of class data
members.

In short, a clever mechanism to enable:

- Working with more than one person on the same application
- Better readability of code
- Better conrol of dynamic facts and rules
- Better performance by evaluating rules in the right context

Contexts can be unified and can serve as powerfull Feature Terms describing
Software Configurations. (A. Zeller - Unified Versioning through Feature Logic)


CONTEXT - Contextual Object Oriented Logic Programming
------------------------------------------------------

CONTEXT implements a declarative contextual logic programming paradigm
that aims to facilitate Prolog software engineering.

Short description:

 1. We split up the global Prolog namespace into contexts, each having
    their own facts and rules.

 2. We create a meta-language allowing you to declare metadata about
    facts and rules in a context.

 3. We implement Classes and Instances,  Public, Protected and Private
    meta-predicates. We implement (Multiple) inheritance and cloning.
    We implement operators enabling interaction with context.

Programs written using CONTEXT are much smaller, support team development
and can still be converted easily to traditional prolog code.

Long description:

A context groups together clauses of a prolog application. By default,
clauses are local to their context i.e. not seen by other contexts, unless
properly prefixed with the name of their context. An exception to this rule
are clauses corresponding to predicates declared as "exported".

Context rules are evaluated in the context in which they are defined. An
exception to this rule are clauses declared as "transparent", which inherit
their context from the predicate that is calling them.

Note that contexts are created ex nihilo. Referencing them is enough to
create one.

The contextual logic programming paradigm as implemented by CONTEXT,
adds a number of features that stem from Object Oriented programming.
Classes and their instances are contexts.

A class is a special type of context which declares public, protected,
and private meta-predicates. Predicate properties are interpreted differently
for each of the following actions:

  - instantiation
  - inheritance
  - calling a predicate

Instances are dynamically created from a class. Predicates declared by
the corresponding class as private, public or protected are "guarded"
correspondingly in the instance context that is dynamically created
and populated with the necessary guarded predicates in order to prevent
unauthorized access.

An instance enables data-member-like behaviour. This functionality is
achieved through the use of special operators. These operators allow one to
cache a successful evaluation of a unified context predicate.

This implementation is thread-safe and supports serialization.


Examples:

@see examples/person.pl for an example 'person' class.
*/


% ********************
% CONTEXT declarations
% ********************


% CONTEXT exports a number of predicates and operator declarations.

:- module(context, [ class/0,
                     class/1,
                     newinstance/1,
                     dpublic/1,
                     dprotected/1,
                     dprivate/1,
                     ddynamic/1,
                     dstatic/1,
                     mutex/1,
                     declare/1,
                     declared/1,
                     implemented/1,
                     inherit/1,
                     this/1,
                     (~)/1,
                     (:)/1,
                     (::)/1,
                     (<-)/1,
                     (<=)/1,
                     (<+)/1,
                     (::)/2,
                     (<-)/2,
                     (<=)/2,
                     (<+)/2,
                     (://)/2,
                     op(600, fx, '~'),
                     op(600, fx, ':'),
                     op(600, fx, '::'),
                     op(600, fx, '<-'),
                     op(600, fx, '<='),
                     op(600, fx, '<+'),
                     op(601, xfx, '::'),
                     op(600, xfx, '<-'),
                     op(600, xfx, '<='),
                     op(600, xfx, '<+'),
                     op(602, xfx, '://'),
                     op(1200, xfx, '::-')
                    ]).


% CONTEXT declares a number of rules as module transparent. The
% clauses corresponding with these predicates require access to the context
% in which they are used instead of the context in which they are declared.

:- module_transparent class/0,
                      class/1,
                      newinstance/1,
                      dpublic/1,
                      dprotected/1,
                      dprivate/1,
                      ddynamic/1,
                      dstatic/1,
                      mutex/1,
                      declare/1,
                      declared/1,
                      implemented/1,
                      inherit/1,
                      this/1,
                      % no destructor since destructor cannot be called directly. e.g. ~pieter(foo). vs pieter:'~'(foo)
                      (:)/1,
                      (::)/1,
                      (<-)/1,
                      (<=)/1,
                      (<+)/1,
                      (::)/2,
                      (<-)/2,
                      (<=)/2,
                      (<+)/2,
                      (://)/2.



% CONTEXT is thread-aware. The idea is that a context, class or instance
% can be used by different threads at the same time. Tokens are issued by a
% class to verify access and invocation methods. They need to be local to
% the thread using the class, otherwise access could be granted to a thread
% which should not have had access to a particular clause.

:- thread_local '$_token'/1.


% CONTEXT uses a dynamic predicate called meta.

:- dynamic '$__meta'/1.


% CONTEXT operator declarations.

:- op(600, fx, '~').
:- op(600, fx, ':').
:- op(600, fx, '<-').
:- op(600, fx, '<=').
:- op(600, fx, '<+').
:- op(601, xfx, '::').
:- op(600, xfx, '<-').
:- op(600, xfx, '<=').
:- op(600, xfx, '<+').
%:- op(602, xfx, '://').
:- op(1200, xfx, '::-').


%! this(?Context)
%
% Exported, transparant predicate
%
% Retrieves the current context.

this(Context) :-
  context_module(Context).


%! class
%
% Exported, transparent predicate
%
% Declare a class.

class :-
  class([]).


%! class(+Parents)
%
% Exported, transparent predicate
%
% Declare a class.

class(Parents) :-
  this(Context),
  context:declare(Context,type(class)),
  inherit(Parents).


%! dpublic(+Functor/+Arity)
%
% Exported, transparent predicate
%
% Declare a public predicate.

dpublic(Functor/Arity) :-
  !,
  declare(property(Functor/Arity, public)).

dpublic(List) :-
  !,
  maplist(dpublic,List).

%! dprotected(+Functor/+Arity)
%
% Exported, transparent predicate
%
% Declare a protected predicate.

dprotected(Functor/Arity) :-
  !,
  declare(property(Functor/Arity, protected)).

dprotected(List) :-
  !,
  maplist(dprotected,List).


%! dprivate(+Functor/+Arity)
%
% Exported, transparent predicate
%
% Declare a private predicate.

dprivate(Functor/Arity) :-
  !,
  declare(property(Functor/Arity, private)).

dprivate(List) :-
  !,
  maplist(dprivate,List).


%! ddynamic(+Functor/+Arity)
%
% Exported, transparent predicate
%
% Declare a dynamic predicate.

ddynamic(_Functor/_Arity) :-
  !,
  true.

ddynamic(List) :-
  !,
  maplist(ddynamic,List).

%! ddynamic(+Functor/+Arity)
%
% Exported, transparent predicate
%
% Declare a dynamic predicate.

dstatic(Functor/Arity) :-
  !,
  declare(property(Functor/Arity, static)).

dstatic(List) :-
  !,
  maplist(dstatic,List).


%! mutex(+Functor/+Arity)
%
% Exported, transparent predicate
%
% Declare a mutexed predicate.

mutex(Functor/Arity) :-
  !,
  declare(property(Functor/Arity, mutex)).

mutex(List) :-
  !,
  maplist(mutex,List).


%! declare(+Fact)
%
% Exported, transparent
%
% Declare a fact.

declare(Fact) :-
  this(Context),
  context:declare(Context, Fact).


% context:declare(+Context, +Fact)
%
% local
%
% Declare a fact. Throws an exception on conflicting declaration.

% context:declare(Context, Fact) :-
%   clause(Context:'$__meta'(Fact), true).

% context:declare(Context, Fact) :-
%   context:conflicting(Fact, OtherFact),
%   clause(Context:'$__meta'(OtherFact), true),
%   OtherFact =.. [Key|Args],
%   throw(error(permission_error(modify, Key, Args), context(Context, _))).


%! context:declare(+Context, +Fact)
%
% Local predicate
%
% Declare a fact.

context:declare(Context, Fact) :-
  assert(Context:'$__meta'(Fact)).


%! context:undeclare(+Context, +Fact)
%
% Local predicate
%
% Undeclares a fact.

context:undeclare(Context, Fact) :-
  retractall(Context:'$__meta'(Fact)).


%! context:conflicting(+Fact,-OtherFact)
%
% Local predicate
%
% Declares a conflict between facts:
%
%  - A context can only be of one type.
%  - A predicate can only have one property.

context:conflicting(type(_), type(_)) :- !.

context:conflicting(property(Functor/Arity, _), property(Functor/Arity, _)) :- !.


%! declared(?Fact)
%
% Exported, transparent predicate
%
% Check whether a fact is declared.

declared(Fact) :-
  this(Context),
  clause(Context:'$__meta'(Fact), true).


%! implemented(+Functor/+Arity)
%
% Exported, transparent predicate
%
% Check whether a fact is implemented.

implemented(Functor/Arity) :-
  this(Context),
  functor(Head,Functor,Arity),
  Context:implemented(Head).


%! implemented(+Head)
%
% Exported, transparent predicate
%
% Check whether a fact is implemented.

implemented(Head) :-
  this(Context),
  context:translate_call(Head,GuardedHead),
  clause(Context:GuardedHead,_).


%! inherit(+Parents)
%
% Exported, transparent predicate
%
% Inherit predicates from a number of parent contexts.
% Throws an error if parent context does not exist.

inherit([Parent|Parents]) :-
  inherit(Parent),
  inherit(Parents).

inherit([]) :- !.


%! inherit(+Parent)
%
% Exported, transparent predicate
%
% Inherit predicates from a parent context.
% Throws an error if parent context does not exist.

inherit(Parent) :-
  not(Parent:declared(type(class))),
  this(Context),
  throw(error(existence_error(class, Parent), context(Context, inherit))).

inherit(Parent) :-
  findall(Functor/Arity, Parent:declared(property(Functor/Arity,_)), List),
  this(Context),
  Context:declare(parent(Parent)),
  context:inherit_predicates(class, Context, Parent, List).


%! inherit_predicates(+Relation, +Context, +Parent, +List)
%
% Local predicate
%
% Inherits predicates in List from Parent Context.

context:inherit_predicates(Relation, Context, Parent, [Functor/Arity|Tail]) :-
  context:inherit_predicate(Relation, Context, Parent, Functor/Arity),
  context:inherit_predicates(Relation, Context, Parent, Tail).

context:inherit_predicates(_Relation, _Context, _Parent, []).


%! inherit_predicate(+Relation, +Context, +Parent, +Functor/+Arity)
%
% Local predicate
%
% Inherit predicate from parent context. Inherits the predicate  properties,
% corresponding clause and cache.

context:inherit_predicate(Relation, Context, Parent, Functor/Arity) :-
  context:inherit_predicate_property(Relation, Context, Parent, Functor/Arity),
  context:inherit_predicate_clauses(Relation, Context, Parent, Functor/Arity).


%! inherit_predicate_property(+Relation, +Context, +Parent, +Functor/Arity)
%
% Local predicate
%
% Assert property of inherited predicate.

context:inherit_predicate_property(Relation, Context, Parent, Functor/Arity) :-
  Parent:declared(property(Functor/Arity, Property)),
  context:inherit_predicate_property(Relation, Property, Context, Parent, Functor/Arity).


%! inherit_predicate_property(+Relation, +Property, +Context, +Parent, +Predicate)
%
% Local predicate
%
% Assert property of inherited predicate, depending on relationship.

context:inherit_predicate_property(class, private, _Context, _Parent, _Predicate) :-
  !,
  true.

context:inherit_predicate_property(_Relation, Property, Context, _Parent, Predicate) :-
  context:declare(Context, property(Predicate, Property)).


%! inherit_predicate_clauses(+Relation, +Context, +Parent, +Functor/+Arity)
%
% Local predicate
%
% Inherit clauses corresponding with Functor/Arity, guard them if required.

context:inherit_predicate_clauses(Relation, Context, Parent, Functor/Arity) :-
  Parent:declared(property(Functor/Arity, Property)),
  functor(Head, Functor, Arity),
  context:inherit_predicate__metaclause(Relation, Parent, Context, Head, Functor/Arity),
  findall([Head, Body], clause(Parent:'::-'(Head, Body), true), Clauses),
  context:inherit_predicate_clauses(Relation, Property, Context, Parent, Clauses).


%! inherit_predicate__metaclause(+Relation, +Parent, +Context, +Head, +Functor/+Arity)
%
% Local predicate
%
% Create a guarded metaclause calling guarded clauses.

context:inherit_predicate__metaclause(class, _Parent, _Context, _Head, _Functor/_Arity) :-
  !,
  true.

context:inherit_predicate__metaclause(instance, Parent, Context, MetaHead, Functor/Arity) :-
  Parent:declared(property(Functor/Arity,Property)),
  context:gen_check_invocation(Context, Parent, Property, MetaHead, MetaBody),
  context:assert_predicate_clause(instance, Context, MetaHead, MetaBody).


%! gen_check_invocation(+Context, +Property, +Head, -Code)
%
% Local predicate
%
% Code generator for invocation check.

context:gen_check_invocation(Context, _Parent, public, MetaHead, Code) :-
  context:translate_call(MetaHead,Head),
  Code = (
           call_cleanup(Head, retract(Context:'$_token'(thread_access)))
         ).

context:gen_check_invocation(_Context, _Parent, protected, MetaHead, Code) :-
  context:translate_call(MetaHead,Head),
  Code = (
           Head
         ).

context:gen_check_invocation(_Context, _Parent, private, MetaHead, Code) :-
  context:translate_call(MetaHead,Head),
  Code = (
           Head
         ).

context:gen_check_invocation(_Context, Parent, static, Head, Code) :-
  Code = (
	   Parent:Head
         ).


%! translate_call(?MetaCall, ?Call)
%
% Local predicate
% Translate between call and metacall representation.

context:translate_call(MetaCall, Call) :-
  MetaCall =.. [MetaFunctor|Args],
  Call =.. ['$__meta',guarded_implementation(MetaFunctor,Args)].


%! inherit_predicate_clauses(+Relation, +Property, +Context, +Parent, +Clauses)
%
% Local predicate
%
% Inherit clauses, guard them if required.

context:inherit_predicate_clauses(Relation, Property, Context, Parent, [[Head,Body]|Clauses]) :-
  context:inherit_predicate_clause(Relation, Property, Context, Parent, Head, Body),
  context:inherit_predicate_clauses(Relation, Property, Context, Parent, Clauses).

context:inherit_predicate_clauses(_Relation, _Property, _Context, _Parent, []).


%! inherit_preidcate_clause(+Relation, +Property, +Context, +Parent, +Head, +Body)
%
% Local predicate
%
% Rewrites clause body on inherit, depending on whether a class or an instance
% is inheriting a clause.

context:inherit_predicate_clause(class, private, _Context, _Parent, _Head, _Body) :-
  !,
  true.

context:inherit_predicate_clause(class, _Property, Context, _Parent, Head, Body) :-
  context:assert_predicate_clause(class, Context, Head, Body).

context:inherit_predicate_clause(instance, Property, Context, Parent, MetaHead, Body) :-
  context:guard_predicate_clause(Property, Context, Parent, MetaHead, GuardedHead, Body, GuardedBody),
  context:assert_predicate_clause(instance, Context, GuardedHead, GuardedBody).


%! guard_predicate_clause(+Property, +Context, +Parent, +Head, +Body, -HeadNew, -BodyNew)
%
% Local predicate
%
% Given a clause, produces a guarded clause.

context:guard_predicate_clause(Property, Context, _Parent, Head, GuardedHead, Body, GuardedBody) :-
  context:translate_call(Head, GuardedHead),
  context:gen_check_access(Property, Context, Head, Body, GuardedBody).


%! gen_check_access(+Property, +Context, +Head, -Code)
%
% Local predicate
%
% Code generator for access check.

context:gen_check_access(private, Context, Head, Body, Code) :-
  Code = (
            clause(Context:'$_token'(thread_access), true)
            ->	( % assert(Context:'$_token'(thread_access)), % reasoning: only public functions can call protected or private functions
                  Body )
            ;   ( functor(Head,H,A),
                  throw(error(permission_error(access, private, H/A), context(Context, _))) )
         ).

context:gen_check_access(protected, Context, Head, Body, Code) :-
  Code = (
            clause(Context:'$_token'(thread_access), true)
            ->	( % assert(Context:'$_token'(thread_access)), % reasoning: only public functions can call protected or private functions
                  Body )
            ;     ( functor(Head,H,A),
                    throw(error(permission_error(access, protected, H/A), context(Context, _))) )
         ).

context:gen_check_access(static, _Context, _Head, Body, Code) :-
  Code = (
            Body
         ).

context:gen_check_access(_Property, Context, _Head, Body, Code) :-
  Code = (
            assert(Context:'$_token'(thread_access)),
            Body
         ).


%! assert_predicate_clause(+Relation, +Context, +Head, +Body)
%
% Local predicate
%
% Assert predicate clause

context:assert_predicate_clause(instance, Context, Head, Body) :-
  assert(Context:(Head :- Body)).

context:assert_predicate_clause(class, Context, Head, Body) :-
  assert(Context:(Head ::- Body)).


%! newinstance(+class)
%
% Exported, transparent predicate
%
% Create an instance from a class.

newinstance(Class) :-
  this(Context),
  context:newinstance(Context, Class).


%! newinstance(+class, +constructor)
%
% Local predicate
% Create an instance from a class.

context:newinstance(Context, _Constructor) :-
  not(atom(Context)),
  throw(error(type_error(atom, Context), context(instance, _))).

context:newinstance(Context, Constructor) :-
  Constructor =.. [Parent|_],
  not(Parent:declared(type(class))),
  throw(error(existence_error(class, Parent), context(Context, instance))).

context:newinstance(Context, Constructor) :-
  Constructor =.. [Parent|Arguments],
  thread_local(Context:'$_token'/1),
  context:declare(Context, type(instance(Parent))),
  findall(Predicate, Parent:declared(property(Predicate,_)), List),
  context:inherit_predicates(instance, Context, Parent, List),
  length(Arguments, Arity),
  !,
  ( Context:declared(property(Parent/Arity, _)) -> Context:Constructor ; true ).


%! '~'(+Destructor)
%
% Exported predicate
%
% Destroy context, calling destructor.

'~'(DestructorCall) :-
  DestructorCall =.. [Context|_Arguments],
  current_module(Context,_),
  throw(error(permission_error(destroy, static_context, Context), context(destroy, _))).

'~'(DestructorCall) :-
  DestructorCall =.. [Context|_Arguments],
  Context:declared(type(class)),
  context:destroy(Context).

'~'(DestructorCall) :-
  DestructorCall =.. [Context|Arguments],
  Context:declared(type(instance(Parent))),
  length(Arguments, Arity),
  atom_concat('~', Parent, DFunctor),
  Destructor =.. [DFunctor|Arguments],
  ( Context:declared(property(DFunctor/Arity, _)) -> Context:Destructor ; true ),
  !,
  context:destroy(Context).


%! ':'(+Predicate)
%
% Exported, transparent predicate
%
% Extension of (:)/2 as a reference to 'this', no-cache.

':'(Predicate) :-
  this(Context),
  Context:Predicate.


%! ':'(-Instance, +Meta)
%
% Exported, transparent predicate
%
% Extension of (:)/2 as a reference to 'this', no-cache.

% contextcall(Instance,declared(Meta)) :-
%   %current_module(Instance),
%   write('debug ::> '),write(Instance),write(' ::> '),write(Meta),nl,
%   Instance:clause(Instance:'$__meta'(Meta),true).


%! '::'(+Predicate)
%
% Exported, transparent predicate
%
% Extension of (::)/2 as a reference to 'this', cache-only.

'::'(Predicate) :-
  this(Context),
  Context::Predicate.


%! '<-'(+Predicate)
%
% Exported, transparent predicate
%
% Extension of <-/2 as a reference to 'this'.

'<-'(Predicate) :-
  this(Context),
  Context<-Predicate.


%! '<='(+Predicate)
%
% Exported, transparent predicate
%
% Extension of <=/2 as a reference to 'this'.

'<='(Predicate) :-
  this(Context),
  Context<=Predicate.


%! '<+'(+Predicate)
%
% Exported, transparent predicate
%
% Extension of <+/2 as a reference to 'this'.

'<+'(Predicate) :-
  this(Context),
  Context<+Predicate.


% '::'(+Context, +Predicate)
%
% Exported, transparent predicate
%
% Call a guarded context predicate.

'::'(Context, Predicate) :-
  Context:declared(cache(Predicate)),
  Context:Predicate.


%! '://'(+Context, +Predicate)
%
% Exported, transparent predicate
%
% Evaluate predicate within a given context

'://'(Context, Predicate) :-
 Context:Predicate.


%! '<-'(+Context, +Predicate)
%
% Exported, transparent predicate
%
% Retract predicate cache matching Predicate.

'<-'(Context, Predicate) :-
  context:undeclare(Context, cache(Predicate)).


%! '<='(+Context, +Predicate)
%
% Exported, transparent predicate
%
% Assert predicate cache, destroying existing cache.
% Algorithm:
%
%  -Use Functor/Arity to create query
%  -Execute
%  -Retract existing cache
%  -Assert new cache

'<='(Context, Predicate) :-
  functor(Predicate, Functor, Arity),
  functor(Head, Functor, Arity),
  Context:Predicate,
  context:undeclare(Context, cache(Head)),
  context:declare(Context, cache(Predicate)).


%! '<+'(+Context, +Predicate)
%
% Exported, transparent predicate
%
% Assert predicate cache.
% Algorithm:
%
%  -Use Functor/Arity to create query
%  -Execute
%  -Assert new cache if not exists

'<+'(Context, Predicate) :-
  Context:Predicate,
  context:declare(Context, cache(Predicate)).


%! destroy(+Context)
%
% Local predicate
%
% Destroy a context.

context:destroy(Context) :-
  findall(Functor/Arity, current_predicate(Context:Functor/Arity), List),
  context:destroy_context_clauses(Context, List).


%! destroy_context_clauses(+Context, +List)
%
% Local predicate
%
% Destroy a list of contextual clauses

context:destroy_context_clauses(Context, [Functor/Arity|Preds]) :-
  functor(Head, Functor, Arity),
  predicate_property(Context:Head,dynamic),!,
  ignore(catch(abolish(Context:Functor/Arity), _, true)),
  context:destroy_context_clauses(Context, Preds).

context:destroy_context_clauses(Context, [_Functor/_Arity|Preds]) :-
  !,
  context:destroy_context_clauses(Context, Preds).

context:destroy_context_clauses(_, []) :- !.
