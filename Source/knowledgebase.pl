/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

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
Query module. The knowledge base is typically initialized as a singleton instance.
*/

:- module(knowledgebase,[]).

% =============================================================================
%  KNOWLEDGEBASE declarations
% =============================================================================

:- class.

% public interface

:- dpublic('knowledgebase'/2).
:- dpublic('knowledgebase'/0).
:- dpublic('~knowledgebase'/0).

:- dpublic(register/1).
:- dpublic(deregister/1).
:- dpublic(sync/0).
:- dpublic(sync/1).
:- dpublic(save/0).
:- dpublic(load/0).
:- dpublic(clear/0).
:- dpublic(compile/0).
:- dpublic(graph/0).

:- dpublic(entry/1).
:- dpublic(query/2).

% protected interface

:- dprotected(proxy/0).
:- dprotected(rpc_wrapper/1).

% private interface

:- dprivate(repository/1).
:- dprivate(state/1).
:- dprivate(host/1).
:- dprivate(port/1).


%! Constructor(Host,Port)
%
% Public predicate
%
% Creates a local proxy for a remotely running
% knowledge base with a given Name.
% Running at Server:Port

'knowledgebase'(Host,Port) ::-
  <=host(Host),
  <=port(Port).


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
  \+ proxy,
  <+repository(Repository),!.


%! knowledgebase:deregister(+Repository)
%
% Public predicate
%
% Deregister a local repository with the knowledge base

deregister(Repository) ::-
  \+ proxy,
  <-repository(Repository),!.


%! knowledgebase:sync
%
% Public predicate
%
% Sync all registered repositories

sync ::-
  proxy,!,
  ::host(Host),
  ::port(Port),
  client:execute_remotely(Host,Port,'/sync'),!.

sync ::-
  \+ proxy,!,
  with_mutex(sync,
  (aggregate_all(count, ::repository(_), Count),
   (Count == 1 ->
    message:topheader(['Syncing ',Count,' registered repository']);
    message:topheader(['Syncing ',Count,' registered repositories'])),
   forall(::repository(Repository),
 	 (message:header(['Syncing repository \"',Repository,'\"']),nl,
         Repository:sync)),!,
   vdb:sync,
   true)).


%! knowledgebase:sync(+Name)
%
% Public predicate
%
% Sync a single registered repository by name (e.g. portage, pkg, overlay).

sync(Name) ::-
  proxy,!,
  ::host(Host),
  ::port(Port),
  atom_concat('/sync/', Name, Path),
  client:execute_remotely(Host,Port,Path),!.

sync(Name) ::-
  \+ proxy,!,
  ( ::repository(Name) ->
      with_mutex(sync,
        (message:topheader(['Syncing repository \"',Name,'\"']),
         message:header(['Syncing repository \"',Name,'\"']),nl,
         Name:sync,!,
         true))
  ; message:failure(['Unknown repository: ', Name, '. Registered: ']),
    forall(::repository(R),
           (message:print('  '), message:print(R), nl)),
    fail
  ).


%! knowledgebase:save
%
% Public predicate
%
% Save state to file

save ::-
  proxy,!,
  ::host(Host),
  ::port(Port),
  client:execute_remotely(Host,Port,'/save'),!.

save ::-
  \+ proxy,!,
  working_directory(Cwd, Cwd),
  os:with_system_lock(kb_save(Cwd),
    with_mutex(save,
      (tell('kb.raw'),
       format(':- module(cache,[]).\n'),
       forall(current_predicate(cache:N/A),
              (functor(H,N,A),
               format(':- dynamic ~w/~w.\n',[N,A]),
               forall(clause(cache:H,_),
                     ( write_canonical(H),
		       format('.\n'))))),
       told,
       qcompile('kb.raw')))),!.


%! knowledgebase:load
%
% Public predicate
%
% Load state from file

load ::-
  proxy,!,
  ::host(Host),
  ::port(Port),
  client:execute_remotely(Host,Port,'/load'),!.

load ::-
  \+ proxy,
  exists_file('kb.qlf'),!,
  ensure_loaded('kb.qlf').

load ::-
  \+ proxy,
  true.


%! knowledgebase:clear
%
% Public predicate
%
% Clear state file

clear ::-
  proxy,!,
  ::host(Host),
  ::port(Port),
  client:execute_remotely(Host,Port,'/clear'),!.

clear ::-
  \+ proxy,
  exists_file('kb.qlf'),
  delete_file('kb.qlf'),
  fail.

clear ::-
  \+ proxy,
  exists_file('kb.raw'),!,
  delete_file('kb.raw').

clear ::-
  \+ proxy,
  true.


%! knowledgebase:graph
%
% Public predicate
%
% Create svg dependency graphs for all entries

graph ::-
  proxy,!,
  ::host(Host),
  ::port(Port),
  client:execute_remotely(Host,Port,'/graph'),!.

graph ::-
  \+ proxy,!,
  with_mutex(graph, % todo: this should interate over all registered repositories
    (portage:graph)).


%! knowledgebase:compile
%
% Public predicate
%
% Save state to stand-alone program

compile ::-
  \+ proxy,
  with_mutex(compile,
   qsave_program('portage-ng',[stand_alone(true),goal(prolog)])).


%! knowledgebase:entry(?Repository://?Entry)
%
% Public predicate
%
% Knowledgebase entries

entry(Repository://Entry) ::-
  rpc_wrapper(cache:ordered_entry(Repository,Entry,_,_,_)).


%! knowledgebase:query(+Query,-Result)
%
% Public predicate
%
% Retrieves metadata cache ebuild that satisfies
% a given query

query(Query,Repository://Result) ::-
  rpc_wrapper(query:search(Query,Repository://Result)).


%! knowledgebase:proxy
%
% Protected predicate
%
% Checks whether the repository is a proxy to a knowledge base
% running on a remote server

proxy ::-
  ::host(_).


%! knowledgebase:rpc_wrapper(Term)
%
% Protected predicate
%
% Wrap predicates into a remote procedure call if host,
% port and proxy are set.

rpc_wrapper(Context:Term) ::-
  ::host(Host),!,
  ::port(Port),
  client:rpc_execute(Host,Port,Context:Term).

rpc_wrapper(Context:Term) ::-
  \+ proxy,!,
  once(goal_expansion(Term,Expanded)),
  Context:Expanded.


%! knowledgebase:repository(?Repository)
%
% Private predicate
%
% Registered repositories

repository(_Repository) ::-
  true.


%! knowledgebase:state(+File)
%
% Private predicate
%
% State file

state(File) ::-
  :this(Context),
  atomic_list_concat([Context,'.raw'],File).


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

port(Port) ::-
  integer(Port).
