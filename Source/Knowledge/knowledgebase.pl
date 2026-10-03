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
:- dpublic(graph_emerge/0).
:- dpublic(graph_pmerge/0).

:- dpublic(entry/1).
:- dpublic(query/2).

% protected interface

:- dprotected(proxy/0).
:- dprotected(rpc_wrapper/1).

% private interface

:- dprivate(repository/1).
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
   true)).


%! knowledgebase:sync(+Name)
%
% Public predicate
%
% Sync a single registered repository by name (e.g. portage, pkg, overlay).

sync(Name) ::-
  proxy,!,
  ( sanitize:safe_path_component(Name) -> true
  ; throw(error(permission_error(sync, repository, Name),
                context(knowledgebase:sync/1, 'Invalid repository name')))
  ),
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
  config:working_dir(Dir),
  os:compose_path(Dir,'Knowledge/kb.raw',Raw),
  os:compose_path(Dir,'Knowledge/kb.qlf',Qlf),
  lock:with_system_lock(kb_save(Dir),
    with_mutex(save,
      (setup_call_cleanup(
         open(Raw,write,Stream),
         (format(Stream,':- module(cache,[]).\n',[]),
          forall(current_predicate(cache:N/A),
                 (functor(H,N,A),
                  format(Stream,':- dynamic ~w/~w.\n',[N,A]),
                  forall(clause(cache:H,_),
                        ( ( ground(H)
                            -> true
                            ;  throw(error(instantiation_error,
                                           context(knowledgebase:save/0,
                                                   nonground_cache_fact(H)))) ),
                          write_canonical(Stream,H),
                          format(Stream,'.\n',[])))))),
         close(Stream)),
       qcompile(Raw),
       sanitize:write_sha256_sidecar(Qlf)))),!.


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
  config:working_dir(Dir),
  os:compose_path(Dir,'Knowledge/kb.qlf',Qlf),
  exists_file(Qlf),!,
  sanitize:ensure_file_integrity(Qlf),
  ensure_loaded(Qlf),
  % Warm the JIT indexes off the critical path: index building is
  % mutex-protected per predicate, so an early query at worst blocks on
  % the build already in progress (same cost as warming synchronously,
  % but overlapped with the remainder of startup).
  knowledgebase:start_metadata_warmer.

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
  exists_file('Knowledge/kb.qlf'),
  delete_file('Knowledge/kb.qlf'),
  fail.

clear ::-
  \+ proxy,
  exists_file('Knowledge/kb.raw'),!,
  delete_file('Knowledge/kb.raw').

clear ::-
  \+ proxy,
  true.


%! knowledgebase:graph
%
% Public predicate
%
% Create svg dependency graphs for entries in the repository named by
% config:graph_repository/1 (default: portage). Invoked by --graph.

graph ::-
  proxy,!,
  ::host(Host),
  ::port(Port),
  client:execute_remotely(Host,Port,'/graph'),!.

graph ::-
  \+ proxy,!,
  config:graph_repository(Repository),
  with_mutex(graph, Repository:graph).


%! knowledgebase:graph_emerge
%
% Public predicate
%
% Generate .emerge files (via emerge-vp) for entries in the repository
% named by config:graph_repository/1. Mirrors knowledgebase:graph/0 but
% writes only the .emerge artefacts. Invoked by --graph emerge.

graph_emerge ::-
  proxy,!,
  ::host(Host),
  ::port(Port),
  client:execute_remotely(Host,Port,'/graph_emerge'),!.

graph_emerge ::-
  \+ proxy,!,
  config:graph_repository(Repository),
  with_mutex(graph, Repository:graph_emerge).


%! knowledgebase:graph_pmerge
%
% Public predicate
%
% Generate .pmerge files (via pmerge --pretend --verbose) for entries in
% the repository named by config:graph_repository/1. Mirrors
% knowledgebase:graph_emerge/0 but writes only the .pmerge artefacts.
% Invoked by --graph pmerge.

graph_pmerge ::-
  proxy,!,
  ::host(Host),
  ::port(Port),
  client:execute_remotely(Host,Port,'/graph_pmerge'),!.

graph_pmerge ::-
  \+ proxy,!,
  config:graph_repository(Repository),
  with_mutex(graph, Repository:graph_pmerge).


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
%
% kb:query/2 is the client-safe entry point: when this knowledge base
% instance is a proxy (client mode), the query is shipped to the remote
% server via pengine RPC. Use it only in code that may execute on a
% proxy client — i.e. the interface layer that resolves user targets
% before shipping work to the server (target.pl, Action/*.pl,
% Printer/info.pl). Code that only ever runs where the KB is local
% (prover, orderer, printer plan rendering, builder) should call
% query:search/2 directly so the compile-time goal-expansion macros
% inline the cache lookups instead of paying instance dispatch +
% runtime expansion + meta-call on every query (issue #57).

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


%! knowledgebase:rpc_wrapper(Module:Term)
%
% Protected predicate
%
% Wrap predicates into a remote procedure call if host,
% port and proxy are set. Module is the target module atom
% (e.g. cache, query). In the local case the query macro
% (goal_expansion) is applied when one exists; otherwise the
% goal is executed directly.

rpc_wrapper(Module:Term) ::-
  ::host(Host),!,
  ::port(Port),
  client:rpc_execute(Host,Port,Module:Term).

rpc_wrapper(Module:Term) ::-
  \+ proxy,!,
  ( goal_expansion(Term,Expanded)
    -> Module:Expanded
    ;  Module:Term ).


%! knowledgebase:repository(?Repository)
%
% Private predicate
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

port(Port) ::-
  integer(Port).


%! knowledgebase:kb_warm_metadata_index is det.
%
% Prime the JIT indexes used by preference:init and the resolver after
% kb.qlf load.  SWI-Prolog builds a JIT index *completely* on the first
% call that needs it, so one bound probe per access pattern suffices:
%
%   1. cache:ordered_entry/5 with all args unbound (binds a witness entry)
%   2. cache:entry_metadata/4 with Repo+Id+key bound — forces the
%      (Id, Key) hash index over all metadata facts
%   3. cache:ordered_entry/5 with category/name bound — forces the
%      (C, N) index used by per-package iteration
%
% The probes are for their index-building side effect only; the soft-fail
% wrappers keep this predicate from failing when the witness entry has no
% slot metadata.

kb_warm_metadata_index :-
  once(cache:ordered_entry(Repo, Id, C, N, _)),
  ( cache:entry_metadata(Repo, Id, slot, slot(_)) -> true ; true ),
  ( cache:ordered_entry(Repo, _, C, N, _) -> true ; true ).


% -----------------------------------------------------------------------------
% Metadata index warmer lifecycle
% -----------------------------------------------------------------------------

% Thread id of the most recently spawned (joinable) JIT-index warmer. Recorded
% so the at_halt hook can wait for it to finish before the process exits,
% avoiding SWI-Prolog's "threads wouldn't die" warning when a fast command
% (e.g. a quick --search) reaches halt while warming is still in progress.

:- dynamic knowledgebase:warmer_thread/1.

:- at_halt(knowledgebase:join_metadata_warmer).


%! knowledgebase:start_metadata_warmer is det.
%
% Spawn kb_warm_metadata_index in a joinable background thread and record its
% id in warmer_thread/1. The thread is joinable (not detached) so join_metadata_warmer/0
% can reap it cleanly at halt instead of leaving SWI-Prolog to forcibly kill it.

start_metadata_warmer :-
  thread_create(ignore(catch(knowledgebase:kb_warm_metadata_index, _, true)),
                Id, []),
  retractall(knowledgebase:warmer_thread(_)),
  assertz(knowledgebase:warmer_thread(Id)).


%! knowledgebase:join_metadata_warmer is det.
%
% at_halt hook: wait for the background metadata warmer to finish (up to a
% short bound) and join it, so the process exits without the "threads wouldn't
% die" warning. The warmer is bounded, one-shot work, so the wait is brief in
% practice; the timeout only guards against a pathological hang.

join_metadata_warmer :-
  ( retract(knowledgebase:warmer_thread(Id))
  -> catch(join_thread_timeout(Id, 10), _, true)
  ;  true ).


%! knowledgebase:join_thread_timeout(+Id, +Timeout) is det.
%
% Wait up to Timeout seconds for thread Id to leave the `running` state, then
% join it to release its resources. If it is still running after Timeout we
% give up waiting (the process is exiting anyway); the join is skipped so halt
% is never blocked indefinitely.

join_thread_timeout(Id, Timeout) :-
  get_time(T0),
  ( wait_thread_done(Id, T0, Timeout)
  -> catch(thread_join(Id, _), _, true)
  ;  true ).


%! knowledgebase:wait_thread_done(+Id, +T0, +Timeout) is semidet.
%
% Poll thread Id until it is no longer `running`. Succeeds once the thread has
% completed (or thrown); fails if Timeout seconds elapse first.

wait_thread_done(Id, _, _) :-
  \+ thread_property(Id, status(running)), !.

wait_thread_done(Id, T0, Timeout) :-
  get_time(Now),
  Now - T0 < Timeout,
  sleep(0.02),
  wait_thread_done(Id, T0, Timeout).


% -----------------------------------------------------------------------------
% Active VDB repository selection
% -----------------------------------------------------------------------------

% Registered client VDB imports: repository name (e.g. 'pkg@laptop.local')
% with the snapshot stamp the client shipped at import time. Asserted by
% server:import_vdb/1 and consulted by vdb_repository/1 to detect stale
% imports.
:- dynamic knowledgebase:client_vdb_stamp/2.


%! knowledgebase:vdb_repository(-Repository) is det.
%
% Unifies Repository with the repository name holding the installed-package
% (VDB) facts for the current execution context:
%
%   * Standalone / daemon / worker: always `pkg` (the local VDB snapshot).
%   * Pengines sandbox context (client-server mode): the per-client
%     repository (`pkg@<clienthost>`) when the client has shipped a valid
%     `vdb_repository/1` instance fact after a successful `--import-vdb`,
%     otherwise `pkg` (the server VDB) with a loud warning.
%
% The result is memoized in a per-thread global variable: the accessor is
% called from resolver hot paths (installed(true) query macros), so it must
% cost a single nb_current/2 lookup after the first call. Memoization is
% safe because a thread is either a pengine thread (one request) or a
% regular thread for its entire lifetime.

knowledgebase:vdb_repository(Repository) :-
  ( nb_current(kb_vdb_repository, R0) ->
      Repository = R0
  ;   knowledgebase:resolve_vdb_repository(R1),
      nb_setval(kb_vdb_repository, R1),
      Repository = R1
  ).


%! knowledgebase:resolve_vdb_repository(-Repository) is det.
%
% Uncached resolution behind vdb_repository/1. In a Pengines sandbox
% context, consults the client-shipped `vdb_repository/1` instance fact
% and validates it against the registered import stamp; outside a pengine
% the answer is always `pkg`.

knowledgebase:resolve_vdb_repository(Repository) :-
  ( preference:pengine_module(M) ->
      knowledgebase:pengine_vdb_repository(M, Repository)
  ;   Repository = pkg
  ).


%! knowledgebase:pengine_vdb_repository(+Module, -Repository) is det.
%
% Pengines sandbox context resolution: missing or stale client imports are
% reported loudly (never a silent fallback to the server VDB), as required
% by the --import-vdb design (issue #78). The warnings fire once per
% pengine request: each pengine runs on a fresh thread, and vdb_repository/1
% memoizes the resolution per thread.

knowledgebase:pengine_vdb_repository(M, Repository) :-
  ( catch(M:vdb_repository(R), _, fail) ->
      ( knowledgebase:client_vdb_valid(M, R) ->
          Repository = R
      ;   message:warning(
            ['Client VDB import \'', R, '\' is missing or stale on this ',
             'server. Falling back to the server VDB - re-run --import-vdb.']),
          Repository = pkg
      )
  ;   message:warning(
        ['No client VDB imported - this plan reflects the server\'s ',
         'installed packages. Run --import-vdb to ship your local VDB.']),
      Repository = pkg
  ).


%! knowledgebase:client_vdb_valid(+Module, +Repository) is semidet.
%
% True when the client-shipped repository name corresponds to a registered
% import whose facts are resident and whose stamp matches the stamp the
% client shipped alongside it.

knowledgebase:client_vdb_valid(M, Repository) :-
  atom(Repository),
  cache:repository(Repository),
  knowledgebase:client_vdb_stamp(Repository, Stamp),
  catch(M:vdb_import_stamp(Stamp0), _, fail),
  Stamp0 == Stamp.


%! knowledgebase:is_vdb_repository(?Repository) is semidet.
%
% True when Repository is a VDB-typed repository name: the local `pkg`
% repository or any per-client import (`pkg@<clienthost>`). Used by query
% filters that must exclude installed-package repositories from portage
% tree searches regardless of which VDB repository is active.

knowledgebase:is_vdb_repository(pkg) :- !.
knowledgebase:is_vdb_repository(Repository) :-
  atom(Repository),
  sub_atom(Repository, 0, _, _, 'pkg@').


%! knowledgebase:register_client_vdb(+Repository, +Stamp) is det.
%
% Record (or refresh) the snapshot stamp for an imported client VDB
% repository. Called by the server-side import handler after the facts
% have been asserted.

knowledgebase:register_client_vdb(Repository, Stamp) :-
  retractall(knowledgebase:client_vdb_stamp(Repository, _)),
  assertz(knowledgebase:client_vdb_stamp(Repository, Stamp)).