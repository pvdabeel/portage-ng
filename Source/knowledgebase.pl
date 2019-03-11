% **************************
% KNOWLEDGEBASE declarations
% **************************

:- module(knowledgebase,[]).

:- class.

:- dpublic('knowledgebase'/0).
:- dpublic('~knowledgebase'/0).


:- dpublic(register/1).
:- dpublic(sync/0).
:- dpublic(save/0).
:- dpublic(load/0).
:- dpublic(clear/0).

:- dpublic(query/2).

:- dprotected(repository/1).
:- dpublic(entry/1).
:- dprotected(state/1).


% Constructor
%
% public predicate

'knowledgebase' ::-
  true.


% Destructor
%
% public predicate

'~knowledgebase' ::-
  true.


% knowledgebase:register(-Repository)
%
% Register a repository with the knowledge base
%
% public predicate

register(Repository) ::-
  <+repository(Repository),!.


% knowledgebase:deregister(-Repository)
%
% Deregister a repository with the knowledge base
%
% public predicate

deregister(Repository) ::-
  <-repository(Repository),!.


% knowledgebase:sync
%
% Sync all registered repositories 
%
% public predicate

sync ::-  
  forall(::repository(Repository),
	 Repository:sync).


% knowledgebase:save
%
% Save state to file 
%
% public predicate

save ::-
  tell('kb.raw'),
  writeln(':- module(cache,[]).'),
  writeln(':- dynamic cache:entry(_,_,_,_,_,_,_).'),
  prolog_listing:listing(cache:entry(_,_,_,_,_,_,_)),
  told,
  qcompile('kb.raw'),!.


% knowledgebase:load
%
% Load state from file
%
% public predicate

load ::-
  exists_file('kb.qlf'),!,
  ensure_loaded('kb.qlf').

load ::-
  true.


% knowledgebase:clear
%
% Clear state file
%
% public predicate

clear ::-
  exists_file('kb.qlf'),!,
  delete_file('kb.qlf'). 

clear ::-
  true.


% knowledgebase:state
%
% State file
%
% protected predicate

state(File) ::-
  :this(Context),
  atomic_list_concat([Context,'.raw'],File).


% knowledgebase:repository
%
% Registered repositories
%
% protected predicate

repository(_Repository) ::-
  true.


% knowledgebase:repository
%
% cache entries
%
% protected predicate

entry(_E) ::-
  true.
