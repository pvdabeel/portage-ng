/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2021, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> PERSON
This file contains a CONTEXT example.
*/

% The first line of a file is a module statement. A module is a namespace for
% rules.

:- module(person, []).


% What follows is a declaration this module is a class. A class contains
% rules of type 'head ::- body' that will be converted on instantiation
% into guarded predicates in the instance namespace

:- class.

% We continue by declaring what predicates are part of the public, private
% and protected interface for this context.


% A Public predicate can be called by anyone. A protected predicate can be
% called by the class itself or any class inheriting the class. A private
% predicate can only be called by the class and not by any of its children,
% nor anyone else.

% Constructor and destructor

:- dpublic('person'/1).
:- dpublic('person'/0).
:- dpublic('~person'/0).


% public interface

:- dpublic([get_name/1,set_name/1]).
%:- dpublic(set_name/1).
:- dpublic(get_age/1).
:- dpublic(set_age/1).
:- dpublic(get_title/1).
:- dpublic(add_title/1).
:- dpublic(remove_title/1).
:- dpublic(verify_name/1).
:- dpublic(verify_age/1).
:- dpublic(verify_title/1).

% protected interface

:- dprotected(name/1).
:- dprotected(get_name2/1).

% private interface

:- dprivate(age/1).
:- dprivate(title/1).

% static interface

:- dstatic(classmethod/0).



% Now that we have declared metadata about our class, we can continue to
% implement it by providing clauses for each of the predicates we declared
% in the interface

person(Name) ::-
  %:this(Context),!,
  :set_name(Name).

'person' ::-
  :this(Context),
  write('Person constructor - '), write(Context), nl.

'~person' ::-
  :this(Context),
  write('Person destructor - '), write(Context), nl.


get_name(Name) ::-
  :get_name2(Name).

get_name2(Name) ::-
  ::name(Name).

get_age(Age) ::-
  ::age(Age).

get_title(Title) ::-
  ::title(Title).

verify_name(Name) ::-
  :name(Name).

verify_age(Age) ::-
  :age(Age).

verify_title(Title) ::-
  :title(Title).


set_name(Name) ::-
  <=name(Name).

set_age(Age) ::-
  <=age(Age).


add_title(Title) ::-
  <+title(Title).

remove_title(Title) ::-
  <-title(Title).


name(Name) ::-
  atom(Name).

age(Age) ::-
  number(Age),
  Age > 0.

title(Title) ::-
  atom(Title).


% Example of a class method.
%
% This method does not use ::-
% When this class is instanciated, the instance method calls the
% class method. Everything is unguarded and executed in context
% of the class. So no access to instance state.

classmethod :-
  writeln('This is a class method').
