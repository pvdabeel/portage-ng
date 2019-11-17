/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2019, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> KNOWLEDGE BASE
The Knowledge Base is a concept that enables different repositories to register,
serialize their rules and facts to disk. This is used as a mechanism to maintain
state across application relaunches.
*/

:- module(knowledgebase,[]).

% **************************
% KNOWLEDGEBASE declarations
% **************************

:- class.

% public interface

:- dpublic('knowledgebase'/0).
:- dpublic('~knowledgebase'/0).

:- dpublic(register/1).
:- dpublic(sync/0).
:- dpublic(save/0).
:- dpublic(load/0).
:- dpublic(clear/0).

:- dpublic(query/2).
:- dpublic(entry/1).

% protected interface

:- dprotected(repository/1).
:- dprotected(state/1).


%! Constructor
%
% Public predicate

'knowledgebase' ::-
  true.


%! Destructor
%
% Public predicate

'~knowledgebase' ::-
  true.


%! knowledgebase:register(+Repository)
%
% Public predicate
%
% Register a repository with the knowledge base

register(Repository) ::-
  <+repository(Repository),!.


%! knowledgebase:deregister(+Repository)
%
% Public predicate
%
% Deregister a repository with the knowledge base

deregister(Repository) ::-
  <-repository(Repository),!.


%! knowledgebase:sync
%
% Public predicate
%
% Sync all registered repositories

sync ::-
  forall(::repository(Repository),
	 Repository:sync).


%! knowledgebase:save
%
% Public predicate
%
% Save state to file

save ::-
  tell('kb.raw'),
  writeln(':- module(cache,[]).'),
  writeln(':- dynamic cache:entry(_,_,_,_,_,_,_).'),
  prolog_listing:listing(cache:entry(_,_,_,_,_,_,_)),
  told,
  qcompile('kb.raw'),!.


% knowledgebase:load
%
% Public predicate
%
% Load state from file

load ::-
  exists_file('kb.qlf'),!,
  ensure_loaded('kb.qlf').

load ::-
  true.


% knowledgebase:clear
%
% Public predicate
%
% Clear state file

clear ::-
  exists_file('kb.qlf'),!,
  delete_file('kb.qlf').

clear ::-
  true.


% knowledgebase:state(+File)
%
% Protected predicate
%
% State file

state(File) ::-
  :this(Context),
  atomic_list_concat([Context,'.raw'],File).


% knowledgebase:repository(?Repository)
%
% Protected predicate
%
% Registered repositories

repository(_Repository) ::-
  true.


% knowledgebase:entry(?Entry)
%
% Protected predicate
%
% Knowledgebase entries

entry(_E) ::-
  true.
