% ********************
% CONTEXT declarations
% ********************

% CONTEXT - Contextual Object Oriented Logic Programming 
% ------------------------------------------------------
%
% CONTEXT implements a declarative contextual logic programming paradigm
% that aims to facilitate Prolog software engineering.
%
% Short description:
%
% 1. We split up the global Prolog namespace into contexts, each having 
%    their own facts and rules.
%
% 2. We create a meta-language allowing you to declare metadata about 
%    facts and rules in a context. 
% 
% 3. We implement Classes and Instances,  Public, Protected and Private 
%    meta-predicates. We implement (Multiple) inheritance and cloning.
%    We implement operators enabling interaction with context.
%
% Programs written using CONTEXT are much smaller, support team development
% and can still be converted easily to traditional prolog code.
 

% Long Description: 
%
% A context groups together clauses of a prolog application. By default, 
% clauses are local to their context i.e. not seen by other contexts, unless 
% properly prefixed with the name of their context. An exception to this rule 
% are clauses corresponding to predicates declared as "exported".
%
% Context rules are evaluated in the context in which they are defined. An
% exception to this rule are clauses declared as "transparent", which inherit
% their context from the predicate that is calling them.
%
% Note that contexts are created ex nihilo. Referencing them is enough to
% create one.
%
% The contextual logic programming paradigm as implemented by CONTEXT, 
% adds a number of features that stem from Object Oriented programming.
% Classes and their instances are contexts.
%
% A class is a special type of context which declares public, protected,
% and private meta-predicates. Predicate properties are interpreted differently 
% for each of the following actions:
%
%  - instantiation
%  - inheritance
%  - calling a predicate
%
% Instances are dynamically created from a class. Predicates declared by 
% the corresponding class as private, public or protected are "guarded" 
% correspondingly in the instance context that is dynamically created 
% and populated with the necessary guarded predicates in order to prevent 
% unauthorized access. 
%
% An instance enables data-member-like behaviour. This functionality is
% achieved through the use of special operators. These operators allow one to
% cache a successful evaluation of a unified context predicate.
%
% This implementation is thread-safe and supports serialization.


% Example:
% 
% See examples/person.pl for an example.



% CONTEXT exports a number of predicates and operator declarations.

:- module(context, [ class/0,
                     class/1,
                     %endclass/0,
                     newinstance/1,
                     dpublic/1,
                     dprotected/1,
                     dprivate/1,
                     ddynamic/1,
                     mutex/1,
                     declare/1,  
                     declared/1,
                     implemented/1,
                     inherit/1,
                     this/1,
                     (~)/1,
                     (:)/1, 
                     (::)/1,
                     (://)/2, 
                     (<-)/1, 
                     (<=)/1, 
                     (<+)/1, 
                     (::)/2, 
                     (<-)/2,
                     (<=)/2,
                     (<+)/2,
                     op(600, fx, '~'), 
                     op(600, fx, ':'), 
                     op(600, fx, '::'), 
                     op(600, fx, '<-'), 
                     op(600, fx, '<='), 
                     op(600, fx, '<+'), 
                     op(600, xfx, '::'),
                     op(600, xfx, '<-'),
                     op(600, xfx, '<='),
                     op(600, xfx, '<+'),
                     op(601, xfx, '://'),
                     op(1200, xfx, '::-')
                    ]).

 
% CONTEXT declares a number of rules as module transparent. The 
% clauses corresponding with these predicates require access to the context 
% in which they are used instead of the context in which they are declared.

:- module_transparent class/0,
                      class/1,
                      endclass/0, 
                      newinstance/1,
                      dpublic/1, 
                      dprotected/1, 
                      dprivate/1,
                      ddynamic/1,
                      mutex/1, 
                      declare/1,
                      declared/1,
                      implemented/1,
                      inherit/1,
                      this/1,
                      % no destructor since destructor cannot be called directly. e.g. ~pieter(foo). vs pieter:'~'(foo)
                      (:)/1,
                      (::)/1, 
                      (://)/2, 
                      (<-)/1, 
                      (<=)/1, 
                      (<+)/1, 
                      (::)/2,
                      (<-)/2, 
                      (<=)/2, 
                      (<+)/2.


% CONTEXT is thread-aware. The idea is that a context, class or instance
% can be used by different threads at the same time. Tokens are issued by a
% class to verify access and invocation methods. They need to be local to
% the thread using the class, otherwise access could be granted to a thread
% which should not have had access to a particular clause.

:- thread_local '$__token'/1.



% CONTEXT uses a dynamic predicate called meta. 

:- dynamic '$__meta'/1.


% CONTEXT operator declarations.

:- op(600, fx, '~').
:- op(600, fx, ':').
:- op(600, fx, '<-').
:- op(600, fx, '<=').
:- op(600, fx, '<+').
:- op(600, xfx, '::').
:- op(600, xfx, '<-').
:- op(600, xfx, '<=').
:- op(600, xfx, '<+').
:- op(601, xfx, '://').
:- op(1200, xfx, '::-').


% @form         context:this(:Context)
% @descr        retrieves the current context.
% @property     exported, transparent

this(Context) :-
  context_module(Context).

% @form         context:class
% @descr        declare a class.
% @property     exported, transparent

class :-
  class([]).


% @form         context:class(+Parents) 
% @descr        declare a class. 
% @property     exported, transparent

class(Parents) :-
  this(Context),
  context:declare(Context,type(class)),
  inherit(Parents).


% @form         context:endclass
% @descr        compiles a class.
% @property     exported, transparent

% endclass :-				       % To be removed
%   this(Context),
%   compile_predicates([Context:'$__meta'/1]).  



% @form         context:dpublic(+Functor/+Arity)
% @descr        declare a public predicate.
% @property     property exported, transparent

dpublic(Functor/Arity) :-
  declare(property(Functor/Arity, public)).


 
% @form         context:dprotected(+Functor/+Arity)
% @descr        declare a protected predicate. 
% @property     exported, transparent

dprotected(Functor/Arity) :-
  declare(property(Functor/Arity, protected)).



% @form         context:dprivate(+Functor/+Arity)
% @descr        declare a private predicate.
% @property     exported, transparent

dprivate(Functor/Arity) :-
  declare(property(Functor/Arity, private)).


% @form         context:ddynamic(+Functor/+Arity)
% @descr        declare a dynamic predicate.
% @property     exported, transparent

ddynamic(_Functor/_Arity) :-				
  true.


% @form         context:mutex(+Functor/+Arity)
% @descr        declare a mutexed predicate.
% @property     exported, transparent

mutex(Functor/Arity) :-
  declare(property(Functor/Arity, mutex)).


% @form         context:declare(+Fact)
% @descr        declare a fact.
% @property     exported, transparent

declare(Fact) :-
  this(Context),
  context:declare(Context, Fact).


% @form         context:declare(+Context, +Fact)
% @descr        declare a fact.
% @exception    throws an exception on conflicting declaration.
% @property     local

% context:declare(Context, Fact) :-
%   clause(Context:'$__meta'(Fact), true).

% context:declare(Context, Fact) :- 
%   context:conflicting(Fact, OtherFact),
%   clause(Context:'$__meta'(OtherFact), true),
%   OtherFact =.. [Key|Args],
%   throw(error(permission_error(modify, Key, Args), context(Context, _))).

context:declare(Context, Fact) :-
  assert(Context:'$__meta'(Fact)).



% @form         context:undeclare(+Context, +Fact)
% @descr        undeclares a fact.
% @property     local

context:undeclare(Context, Fact) :-
  retractall(Context:'$__meta'(Fact)).



% @form         context:conflicting(+Fact, -OtherFact)
% @descr        declares a conflict between facts:
%              
%               - A context can only be of one type.
%               - A predicate can only have one property.
%              
% @property     local

context:conflicting(type(_), type(_)) :- !.

context:conflicting(property(Functor/Arity, _), property(Functor/Arity, _)) :- !.



% @form         context:declared(:Fact)
% @descr        check whether a fact is declared.
% @property     exported, transparent

declared(Fact) :-
  this(Context),
  clause(Context:'$__meta'(Fact), true).



% @form         context:implemented(+Functor/Arity)
% @descr        check whether a fact is implemented.
% @property     exported, transparent

implemented(Functor/Arity) :-
  this(Context),
  functor(Head,Functor,Arity),
  Context:implemented(Head).



% @form         context:implemented(+Head)
% @descr        check whether a fact is implemented.
% @property     exported, transparent

implemented(Head) :-
  this(Context),
  context:translate_call(Head,GuardedHead),
  clause(Context:GuardedHead,_).
 


% @form         inherit(+Parents)
% @descr        inherit predicates from a number of parent contexts.
% @property     exported, transparent

inherit([Parent|Parents]) :-
  inherit(Parent),
  inherit(Parents).

inherit([]) :- !.



% @form         inherit(+Parent)
% @descr        inherit predicates from a parent context.
% @exception    throws an error if parent context does not exist.
% @property     exported, transparent

inherit(Parent) :-
  not(Parent:declared(type(class))),
  this(Context),
  throw(error(existence_error(class, Parent), context(Context, inherit))).

inherit(Parent) :-
  findall(Functor/Arity, Parent:declared(property(Functor/Arity,_)), List),
  this(Context),
  Context:declare(parent(Parent)),
  context:inherit_predicates(class, Context, Parent, List).



% @form         context:inherit_predicates(+Relation, +Context, +Parent, +List)
% @descr        inherits predicates in List from Parent Context.
% @property     local 

context:inherit_predicates(Relation, Context, Parent, [Functor/Arity|Tail]) :-
  context:inherit_predicate(Relation, Context, Parent, Functor/Arity),
  context:inherit_predicates(Relation, Context, Parent, Tail).

context:inherit_predicates(_Relation, _Context, _Parent, []).



% @form         context:inherit_predicate(+Relation, +Context, +Parent, +Functor/+Arity) 
% @descr        inherit predicate from parent context. Inherits the predicate 
%               properties, corresponding clause and cache.
% @property     local

context:inherit_predicate(Relation, Context, Parent, Functor/Arity) :-
  context:inherit_predicate_property(Relation, Context, Parent, Functor/Arity),
  context:inherit_predicate_clauses(Relation, Context, Parent, Functor/Arity).



% @form         context:inherit_predicate_property(+Relation, +Context, +Parent, +Functor/+Arity) 
% @descr        assert property of inherited predicate.
% @property     local

context:inherit_predicate_property(Relation, Context, Parent, Functor/Arity) :-
  Parent:declared(property(Functor/Arity, Property)),
  context:inherit_predicate_property(Relation, Property, Context, Parent, Functor/Arity).


% @form         context:inherit_predicate_property(+Relation, +Property, +Context, +Parent, +Predicate)
% @descr        assert property of inherited predicate, depending on relationship. 
% @property     local 

context:inherit_predicate_property(class, private, _Context, _Parent, _Predicate) :-
  !,
  true.

context:inherit_predicate_property(_Relation, Property, Context, _Parent, Predicate) :-
  context:declare(Context, property(Predicate, Property)).


% @form         context:inherit_predicate_clauses(+Relation, +Context, +Parent, +Functor/+Arity)
% @descr        inherit clauses corresponding with Functor/Arity, guard them if required. 
% @property     local

context:inherit_predicate_clauses(Relation, Context, Parent, Functor/Arity) :-
  Parent:declared(property(Functor/Arity, Property)),
  functor(Head, Functor, Arity),
  context:inherit_predicate__metaclause(Relation, Parent, Context, Head, Functor/Arity),
  findall([Head, Body], clause(Parent:'::-'(Head, Body), true), Clauses),
  context:inherit_predicate_clauses(Relation, Property, Context, Parent, Clauses). 



% @form         context:inherit_predicate__metaclause(+Relation, +Parent, +Context, +Head, +Functor/+Arity)
% @descr        create a guarded metaclause calling guarded clauses.
% @property     local

context:inherit_predicate__metaclause(class, _Parent, _Context, _Head, _Functor/_Arity) :- 
  !, 
  true.

context:inherit_predicate__metaclause(instance, Parent, Context, MetaHead, Functor/Arity) :-
  Parent:declared(property(Functor/Arity,Property)),
  context:gen_check_invocation(Context, Property, MetaHead, MetaBody),
  context:assert_predicate_clause(instance, Context, MetaHead, MetaBody).



% @form         context:gen_check_invocation(+Context, +Property, +Head, -Code) 
% @descr        code generator for invocation check.
% @property     local

context:gen_check_invocation(Context, public, MetaHead, Code) :-
  context:translate_call(MetaHead,Head),
  Code = ( 
           call_cleanup(Head, retract(Context:'$_token'(thread_access)))
         ).

context:gen_check_invocation(_Context, protected, MetaHead, Code) :-
  context:translate_call(MetaHead,Head),
  Code = ( 
           Head
         ).

context:gen_check_invocation(_Context, private, MetaHead, Code) :-
  context:translate_call(MetaHead,Head),
  Code = ( 
           Head
         ).



% @form         context:translate_call(:MetaCall,:Call) 
% @descr        translate between call and metacall representation.
% @property     local

context:translate_call(MetaCall, Call) :-
  MetaCall =.. [MetaFunctor|Args],
  Call =.. ['$__meta',guarded_implementation(MetaFunctor,Args)]. 


% @form         context:inherit_predicate_clauses(+Relation, +Property, +Context, +Parent, +Clauses)
% @descr        inherit clauses, guard them if required.
% @property     local

context:inherit_predicate_clauses(Relation, Property, Context, Parent, [[Head,Body]|Clauses]) :-
  context:inherit_predicate_clause(Relation, Property, Context, Parent, Head, Body),
  context:inherit_predicate_clauses(Relation, Property, Context, Parent, Clauses).

context:inherit_predicate_clauses(_Relation, _Property, _Context, _Parent, []).



% @form         context:inherit_predicate_clause(+Relation, +Property, +Context, +Parent, +Head, +Body) 
% @descr        rewrites clause body on inherit, depending on whether a class
%               or an instance is inheriting a clause.
% @property     local

context:inherit_predicate_clause(class, private, _Context, _Parent, _Head, _Body) :-
  !,
  true.

context:inherit_predicate_clause(class, _Property, Context, _Parent, Head, Body) :-
  context:assert_predicate_clause(class, Context, Head, Body). 

context:inherit_predicate_clause(instance, Property, Context, Parent, MetaHead, Body) :- 
  context:guard_predicate_clause(Property, Context, Parent, MetaHead, GuardedHead, Body, GuardedBody),
  context:assert_predicate_clause(instance, Context, GuardedHead, GuardedBody).



% @form         context:guard_predicate_clause(+Property, +Context, +Parent, +Head, +Body, -HeadNew, -BodyNew)
% @descr        given a clause, produces a guarded clause.
% @property     local

context:guard_predicate_clause(Property, Context, _Parent, Head, GuardedHead, Body, GuardedBody) :-
  context:translate_call(Head, GuardedHead),
  context:gen_check_access(Property, Context, Head, Body, GuardedBody).



% @form         context:gen_check_access(+Property, +Context, +Head, -Code)
% @descr        code generator for access check.
% @property     local

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

context:gen_check_access(_Property, Context, _Head, Body, Code) :-
  Code = ( 
            assert(Context:'$_token'(thread_access)), 
            Body 
         ).



% @form         context:assert_predicate_clause(+Relation, +Context, +Head, +Body) 
% @descr        assert predicate clause
% @property     local

context:assert_predicate_clause(instance, Context, Head, Body) :-
  assert(Context:(Head :- Body)).

context:assert_predicate_clause(class, Context, Head, Body) :-
  assert(Context:(Head ::- Body)).



% @form         context:newinstance(+Constructor)
% @descr        create an instance from a class.
% @property     exported, transparent

newinstance(Class) :-
  this(Context),
  context:newinstance(Context, Class). 



% @form         context:newinstance(+Context, +Constructor)
% @descr        create an instance from a class.
% @property     local

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



% @form         context:'~'(+Destructor)
% @descr        destroy context, calling destructor.
% @property     exported

'~'(DestructorCall) :-
  DestructorCall =.. [Context|_Arguments],
  current_module(Context,_),
  throw(error(permission_error(destroy, static_context, Context), context(destroy, _))).

'~'(DestructorCall) :-
  DestructorCall =.. [Context|_Arguments],
  Context:declared(type(class)),
  context:destroy(Context).

% TODO: verify whether destructor exists. Throw exeption if non-existing destructor is called.
% TODO: public, private, protected, mutexed destructors???

'~'(DestructorCall) :-
  DestructorCall =.. [Context|Arguments],
  Context:declared(type(instance(Parent))),
  length(Arguments, Arity),
  atom_concat('~', Parent, DFunctor),
  Destructor =.. [DFunctor|Arguments],
  ( Context:declared(property(DFunctor/Arity, _)) -> Context:Destructor ; true ),
  !,
  context:destroy(Context).



% @form         context:':'(+Predicate)
% @descr        extension of (:)/2 as a reference to 'this', no-cache.
% @property     exported, transparent

':'(Predicate) :-
  this(Context),
  Context:Predicate.
 


% @form         context:':'(-Instance,+Meta)
% @descr        extension of (:)/2 as a reference to 'this', no-cache.
% @property     exported, transparent

% contextcall(Instance,declared(Meta)) :-
%   %current_module(Instance), ?????
%   write('debug ::> '),write(Instance),write(' ::> '),write(Meta),nl,
%   Instance:clause(Instance:'$__meta'(Meta),true). 



% @form         context:'::'(+Predicate)
% @descr        extension of (::)/2 as a reference to 'this', cache-only.
% @property     exported, transparent

'::'(Predicate) :-
  this(Context),
  Context::Predicate.



% @form         context:'<-'(+Predicate)
% @descr        extension of <-/2 as a reference to 'this'.
% @property     exported, transparent

'<-'(Predicate) :-
  this(Context),
  Context<-Predicate.



% @form         context:'<='(+Predicate)
% @descr        extension of <=/2 as a reference to 'this'.
% @property     exported, transparent

'<='(Predicate) :-
  this(Context),
  Context<=Predicate.



% @form         context:'<+'(+Predicate)
% @descr        extension of <+/2 as a reference to 'this'.
% @property     exported, transparent

'<+'(Predicate) :-
  this(Context),
  Context<+Predicate.



% @form         context:'::'(+Context, +Predicate)
% @descr        call a guarded context predicate.
% @property     exported, transparent

'::'(Context, Predicate) :-
  Context:declared(cache(Predicate)),
  Context:Predicate.


'://'(Context, Predicate) :-
  Context://Predicate.

% @form         context:'<-'(+Context, +Predicate)
% @descr        retract predicate cache matching Predicate.
% @property     exported, transparent

'<-'(Context, Predicate) :-
  context:undeclare(Context, cache(Predicate)).



% @form         context:'<='(+Context, +Predicate)
% @descr        Assert predicate cache, destroying existing cache.
%               Algorithm: 
%              
%                -Use Functor/Arity to create query
%                -Execute
%                -Retract existing cache
%                -Assert new cache
%              
% @property     exported, transparent

'<='(Context, Predicate) :-
  functor(Predicate, Functor, Arity),	
  functor(Head, Functor, Arity),
  Context:Predicate,
  context:undeclare(Context, cache(Head)),
  context:declare(Context, cache(Predicate)).



% @form         context:'<+'(+Context, +Predicate)
% @descr        Assert predicate cache. 
%              Algorithm: 
%              
%                -Use Functor/Arity to create query
%                -Execute<
%                -Assert new cache if not exists
%              
% @property     exported, transparent

'<+'(Context, Predicate) :-
  Context:Predicate,
  context:declare(Context, cache(Predicate)). 




% @form         context:destroy(+Context)
% @descr        destroy a context.
% @property     local

context:destroy(Context) :-
  findall(Functor/Arity, current_predicate(Context:Functor/Arity), List),
  context:destroy_context_clauses(Context, List).



% @form         context:destroy_context_clauses(+Context, +List)
% @descr        destroy a list of contextual clauses
% @property     local

context:destroy_context_clauses(Context, [Functor/Arity|Preds]) :-
  functor(Head, Functor, Arity),
  predicate_property(Context:Head,dynamic),!,  
  ignore(catch(abolish(Context:Functor/Arity), _, true)),
  context:destroy_context_clauses(Context, Preds).


context:destroy_context_clauses(Context, [_Functor/_Arity|Preds]) :-
  !,
  context:destroy_context_clauses(Context, Preds).


context:destroy_context_clauses(_, []) :- !.
