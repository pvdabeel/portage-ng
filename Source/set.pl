/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2025, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> SET
This class enables creation of set instances. A set instance is essentially a
group of requirements. For example the portage 'world' file is a set of requirements
representing the packages installed on a system.

Sets can be referenced on the command line using @ syntax.
*/

:- module(set,[]).

% ****************
% SET declarations
% ****************


:- class.

% public interface

:- dpublic('set'/1).
:- dpublic('set'/0).
:- dpublic('~set'/0).

:- dpublic(init/1).

:- dpublic(load/0).
:- dpublic(save/0).

:- dpublic(register/1).
:- dpublic(unregister/1).

:- dpublic(entry/1).
:- dpublic(file/1).


%! Constructor
%
% Public predicate

'set'(File) ::-
  <=file(File),!.

%! Constructor
%
% Public predicate


'set' ::-
  true,!.


%! Destructor
%
% Public predicate

'~set' ::-
  true,!.


%! set:init(+File)
%
% Public predicate

init(File) ::-
  <=file(File),!.


%! set:load
%
% Public predicate

load ::-
  ::file(File),
  \+ exists_file(File),!.


load ::-
  ::file(File),
  <-entry(_),
  see(File),
  current_input(Stream),
  reader:read_lines_to_string(Stream,Result),
  seen,
  forall(member(E,Result),
         <+entry(E)),!.


%! set:save
%
% Public predicate

save ::-
  ::file(File),
  tell(File),
  forall(::entry(E),
         writeln(E)),
  told,!.


%! set:register(+Entry)
%
% Public predicate

register(Entry) ::-
  <+entry(Entry),!.


%! set:unregister(+Entry)
%
% Public predicate

unregister(Entry) ::-
  <-entry(Entry),!.


%! set:entry(?Entry)
%
% Public predicate

entry(_Entry) ::-
  true.


%! set:file(?Entry)
%
% Public predicate

file(File) ::-
  atom(File).
