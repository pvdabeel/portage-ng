/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2024, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> KNOWLEDGE BASE
The Knowledge Base is a class that enables different repositories to register,
serialize their rules and facts to disk. This is used as a mechanism to maintain
state across application relaunches.

The knowledge base can be instantiated as a local proxy for a remotely running
knowledge base, using pengine rpc and 2-way SSL (https) communication.

The knowledge base query mechanism for local cache  is implemented by in the
Query module.
*/

:- module(knowledgebase,[]).

% **************************
% KNOWLEDGEBASE declarations
% **************************

:- class.

% public interface

:- dpublic('knowledgebase'/3).
:- dpublic('knowledgebase'/0).
:- dpublic('~knowledgebase'/0).

:- dpublic(register/1).
:- dpublic(sync/0).
:- dpublic(save/0).
:- dpublic(load/0).
:- dpublic(compile/0).
:- dpublic(clear/0).
:- dpublic(query/2).

% protected interface

:- dprotected(repository/1).
:- dprotected(state/1).

% private interface

:- dprivate(host/1).
:- dprivate(port/1).
:- dprivate(proxy/1).


%! Constructor(Server,Port,Name)
%
% Public predicate
%
% Creates a local proxy for a remotely running
% knowledge base with a given Name.
% Running at Server:Port

'knowledgebase'(Server,Port,Name) ::-
  <=server(Server),
  <=port(Port),
  <=proxy(Name).


%! Constructor
%
% Public predicate
%
% Creates a local knowledge base.

'knowledgebase' ::-
  true.


%! Destructor
%
% Public predicate
%
% Destructs knowledge base.

'~knowledgebase' ::-
  true.


%! knowledgebase:register(+Repository)
%
% Public predicate
%
% Register a local repository with the knowledge base

register(Repository) ::-
  \+ ::proxy(false),
  <+repository(Repository),!.


%! knowledgebase:deregister(+Repository)
%
% Public predicate
%
% Deregister a local repository with the knowledge base

deregister(Repository) ::-
  \+ ::proxy(false),
  <-repository(Repository),!.


%! knowledgebase:sync
%
% Public predicate
%
% Sync all registered repositories

sync ::-
  ::proxy(Name),!,
  ::host(Host),
  ::port(Port),
  client:execute_remotely(Host,Port,Name:sync).


sync ::-
  aggregate_all(count, ::repository(_), Count),
  (Count == 1 ->
   message:topheader(['Syncing ',Count,' registered repository']);
   message:topheader(['Syncing ',Count,' registered repositories'])),
  forall(::repository(Repository),
	 (message:header(['Syncing repository \"',Repository,'\"']),nl,
          Repository:sync)),!,
  pkg:sync.



%! knowledgebase:save
%
% Public predicate
%
% Save state to file

save ::-
  ::proxy(Name),!,
  ::host(Host),
  ::port(Port),
  client:execute_remotely(Host,Port,Name:save).


save ::-
  tell('kb.raw'),
  writeln(':- module(cache,[]).'),
  prolog_listing:listing(cache:_),
  told,
  qcompile('kb.raw'),!.


%! knowledgebase:compile
%
% Public predicate
%
% Save state to stand-alone program

compile ::-
  ::proxy(Name),!,
  ::host(Host),
  ::port(Port),
  client:execute_remotely(Host,Port,Name:compile).


compile ::-
  qsave_program('portage-ng',[stand_alone(true),goal(prolog)]).


%! knowledgebase:load
%
% Public predicate
%
% Load state from file

load ::-
  ::proxy(Name),!,
  ::host(Host),
  ::port(Port),
  client:execute_remotely(Host,Port,Name:load).

load ::-
  exists_file('kb.qlf'),!,
  ensure_loaded('kb.qlf').

load ::-
  true.


%! knowledgebase:clear
%
% Public predicate
%
% Clear state file

clear ::-
  ::proxy(Name),!,
  ::host(Host),
  ::port(Port),
  client:execute_remotely(Host,Port,Name:clear).

clear ::-
  exists_file('kb.qlf'),
  delete_file('kb.qlf'),
  fail.

clear ::-
  exists_file('kb.raw'),!,
  delete_file('kb.raw').

clear ::-
  true.


%! knowledgebase:query(+Query,-Result)
%
% Public predicate
%
% Retrieves metadata cache ebuild that satisfies
% a given query

query(Query,Repository://Result) ::-
  ::proxy(Name),!,
  ::host(Host),
  ::port(Port),
  client:rpc_execute(Host,Port,Name:query(Query,Repository://Result)).

query(Query,Repository://Result) ::-
  query:search(Query,Repository://Result).


%! knowledgebase:entry(?Repository://?Entry)
%
% Protected predicate
%
% Knowledgebase entries

entry(Repository://Entry) ::-
  ::proxy(Name),!,
  ::host(Host),
  ::port(Port),
  client:rpc_execute(Host,Port,Name:entry(Repository://Result)).

entry(Repository://Entry) ::-
  cache:ordered_entry(Repository,Entry,_,_,_).


%! knowledgebase:state(+File)
%
% Protected predicate
%
% State file

state(File) ::-
  ::proxy(Name),!,
  ::host(Host),
  ::port(Port),
  client:rpc_execute(Host,Port,Name:state(File)).

state(File) ::-
  :this(Context),
  atomic_list_concat([Context,'.raw'],File).


%! knowledgebase:repository(?Repository)
%
% Protected predicate
%
% Registered repositories

repository(_Repository) ::-
  true.


%! knowledgebase:host(+Host)
%
% Private predicate
%
% Hostname of remote knowledge base

host(Host) ::-
  atom(Host).


%! knowledgebase:port(+Port)
%
% Private predicate
%
% Port at which remote knowledge base is running

port(_Port) ::-
  integer(Port).


%! knowledgebase:proxy(+Name)
%
% Private predicate
%
% Name of remote knowledge base

proxy(Name) ::-
  atom(Name).

