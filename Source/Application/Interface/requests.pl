/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> REQUESTS
Main request dispatch: maps recognised CLI flags onto the corresponding action
predicates (included into the INTERFACE module via interface.pl).

Dispatch is table-driven: request_handler/5 declares one fact per recognised
flag (in dispatch priority order), request_matches/3 decides whether a handler
is triggered by the parsed Options/Args, and request_select/5 picks the first
triggered handler. This keeps interface:spec/1 and the dispatch co-verifiable
and allows per-flag behaviour to be unit-tested (see
Source/Test/Unit/interfacetest.pl).
*/

% -----------------------------------------------------------------------------
%  Request dispatch table
% -----------------------------------------------------------------------------

%! interface:request_handler(?Flag, ?Mode, ?Args, ?Options, ?Goal) is nondet.
%
% Dispatch table mapping each recognised CLI flag onto the goal that
% implements it. These are non-ground facts: Mode, Args and Options are
% template variables that request_select/5 binds when a handler is selected.
%
% Clause order is the dispatch priority order: the first handler whose
% request_matches/3 guard succeeds wins. Order is load-bearing at the end of
% the table: 'shellrun' and 'shell' must precede 'merge', because merge(true)
% is the optparse default (spec.pl) and therefore matches almost any command
% line — it acts as the final catch-all.
%
% Flag is normally the option name exactly as declared in interface:spec/1.
% Handlers with a dedicated guard in request_matches/3: 'rollback' (atom
% value, triggers when not 'none'), 'llm' (atom value, optional service
% name) and the pseudo-flag 'shellrun' (--shell with target arguments).
%
% 'update' is a plain :run merge: for a single target Portage's --update
% resolves the full runtime closure and replaces where needed, which is
% exactly what proving :run does.
%
% 'fetchonly' / 'fetchall' prove the same :run plan as --merge. The
% preference flag then restricts print and execute to downloads plus
% configuration pre-actions (unmask / keyword / USE / license). 'fetchall'
% (--fetch-all-uri) additionally widens distfile scope to every SRC_URI
% (ebuild:distfile_scope/1). 'build' precedes both so `--build --fetchonly`
% executes that filtered plan rather than only printing it.

interface:request_handler(snapshots,       _,    _,    _,       snapshot:list).
interface:request_handler(rollback,        _,    _,    Options, (memberchk(rollback(Id), Options),
                                                                 action:process_rollback(Id, Options))).
interface:request_handler(version,         _,    _,    _,       (interface:version(Version),
                                                                 message:logo(['::- portage-ng ', Version]),
                                                                 info:print_repositories)).
interface:request_handler(info,            _,    Args, Options, action:process_action(info, Args, Options)).
interface:request_handler(bugs,            _,    Args, Options, action:process_bugs(Args, Options)).
interface:request_handler(clear,           _,    _,    _,       kb:clear).
interface:request_handler(graph,           _,    Args, _,       (action:process_graph(Args), nl)).
interface:request_handler(deselect,        _,    Args, _,       action:process_deselect(Args)).
interface:request_handler(unmerge,         _,    Args, Options, action:process_action(uninstall, Args, Options)).
interface:request_handler(depclean,        _,    Args, Options, action:process_action(depclean, Args, Options)).
interface:request_handler(upgrade,         _,    Args, Options, action:process_upgrade(Args, Options)).
interface:request_handler(update,          _,    Args, Options, action:process_action(run, Args, Options)).
interface:request_handler(search,          _,    Args, Options, action:process_action(search, Args, Options)).
interface:request_handler(listsets,        _,    _,    _,       action:process_list_sets).
interface:request_handler(checknews,       _,    _,    _,       news:check).
interface:request_handler(readnews,        _,    _,    _,       news:check).
interface:request_handler(regen,           Mode, Args, _,       action:process_regen(Mode, Args)).
interface:request_handler(metadata,        Mode, Args, _,       action:process_regen(Mode, Args)).
interface:request_handler(sync,            Mode, Args, _,       action:process_sync(Mode, Args)).
interface:request_handler(save,            _,    _,    _,       kb:save).
interface:request_handler(load,            _,    _,    _,       kb:load).
interface:request_handler(resume,          _,    Args, Options, (action:assert_resume_skip_args(Args),
                                                                 builder:build_resume,
                                                                 action:maybe_ci_exit_on_build_failure(Options))).
interface:request_handler(build,           _,    Args, Options, action:process_build(Args, Options)).
interface:request_handler(fetchonly,       _,    Args, Options, action:process_action(run, Args, Options)).
interface:request_handler(fetchall,        _,    Args, Options, action:process_action(run, Args, Options)).
interface:request_handler(contents,        _,    Args, _,       action:process_vdb_query(contents, Args)).
interface:request_handler(owner,           _,    Args, _,       action:process_vdb_query(owner, Args)).
interface:request_handler(pkgsize,         _,    Args, _,       action:process_vdb_query(size, Args)).
interface:request_handler(verify,          _,    Args, _,       action:process_vdb_query(verify, Args)).
interface:request_handler(executables,     _,    Args, _,       action:process_vdb_query(executables, Args)).
interface:request_handler(fixlinkage,      _,    Args, Options, action:process_fix_linkage(Args, Options)).
interface:request_handler(report,          _,    _,    Options, action:process_report(Options)).
interface:request_handler(rdeps,           _,    Args, _,       action:process_rdeps(Args)).
interface:request_handler(unuseddistfiles, _,    _,    Options, action:process_unused_distfiles(Options)).
interface:request_handler(import,          _,    Args, Options, action:process_import(Args, Options)).
interface:request_handler(importvdb,       Mode, _,    _,       action:process_import_vdb(Mode)).
interface:request_handler(unmanagedfiles,  _,    Args, _,       action:process_unmanaged_files(Args)).
interface:request_handler(upstream,        _,    Args, Options, action:process_upstream(Args, Options)).
interface:request_handler(searchbugs,      _,    Args, Options, action:process_search_bugs(Args, Options)).
interface:request_handler(trainmodel,      _,    _,    _,       action:process_train_model).
interface:request_handler(similar,         _,    Args, _,       action:process_similar(Args)).
interface:request_handler(estimate,        _,    Args, _,       action:process_estimate(Args)).
interface:request_handler(llm,             _,    _,    Options, (action:extract_llm_opt(Options, LlmOpt),
                                                                 action:process_llm_chat(LlmOpt))).
interface:request_handler(diagnose,        _,    Args, Options, action:process_diagnose(Args, Options)).
interface:request_handler(shellrun,        _,    Args, Options, action:process_action(run, Args, Options)).
interface:request_handler(shell,           _,    _,    _,       true).
interface:request_handler(merge,           _,    Args, Options, action:process_action(run, Args, Options)).


%! interface:request_matches(+Flag, +Args, +Options) is semidet.
%
% Succeeds when the handler keyed by Flag is triggered by the parsed
% Options/Args. Specialised guards come first; the final clause implements
% the default guard: a boolean flag set to true in Options.

interface:request_matches(rollback, _, Options) :-
  !,
  memberchk(rollback(Id), Options),
  Id \== none.
interface:request_matches(llm, _, Options) :-
  !,
  action:extract_llm_opt(Options, _).
interface:request_matches(shellrun, Args, Options) :-
  !,
  memberchk(shell(true), Options),
  Args \== [].
interface:request_matches(Flag, _, Options) :-
  Opt =.. [Flag, true],
  memberchk(Opt, Options).


%! interface:request_select(+Mode, +Args, +Options, -Flag, -Goal) is semidet.
%
% Walks the request_handler/5 table in declaration order and unifies Flag
% and Goal with the first handler triggered by Options/Args. Fails when no
% handler matches. Pure selection (no side effects), so per-flag dispatch
% is unit-testable.

interface:request_select(Mode, Args, Options, Flag, Goal) :-
  interface:request_handler(Flag, Mode, Args, Options, Goal),
  interface:request_matches(Flag, Args, Options),
  !.


%! interface:dispatch_request(+Mode, +Args, +Options) is semidet.
%
% Executes the goal of the first matching handler. When no handler matches,
% reports the unrecognised options and fails (message:failure/1 prints and
% then fails by design), so the caller falls through to the catch-all
% clause of process_requests/1. A failing handler goal also fails this
% predicate, but silently: actions signal their own errors.

interface:dispatch_request(Mode, Args, Options) :-
  interface:request_select(Mode, Args, Options, Flag, Goal),
  !,
  interface:ensure_for_request(Flag, Options),
  Goal.
interface:dispatch_request(_, _, Options) :-
  format(atom(Msg), 'No action recognised for options: ~w', [Options]),
  message:failure([Msg]).


%! interface:ensure_for_request(+Flag, +Options) is det.
%
% Load the capability groups the selected action needs. Pretend and
% merge stay on the resolver. Build, graph and the shell load the
% groups that used to start with every standalone process. Explain
% loads the language-model groups only when an explain mode is set.

interface:ensure_for_request(shell, _) :-
  !,
  loader:ensure(build),
  loader:ensure(graph),
  loader:ensure(bulk),
  loader:ensure(cluster),
  ( config:load_llm_modules(true) -> loader:ensure(llm) ; true ).
interface:ensure_for_request(Flag, _) :-
  memberchk(Flag, [build, resume, snapshots, rollback]),
  !,
  loader:ensure(build).
interface:ensure_for_request(graph, _) :-
  !,
  loader:ensure(graph),
  loader:ensure(bulk).
interface:ensure_for_request(Flag, _) :-
  memberchk(Flag, [llm, diagnose, trainmodel, similar]),
  !,
  loader:ensure(llm).
interface:ensure_for_request(Flag, Options) :-
  memberchk(Flag, [merge, update, fetchonly, fetchall, shellrun, upgrade]),
  memberchk(explain(Explain), Options),
  Explain \== none,
  !,
  loader:ensure(llm).
interface:ensure_for_request(_, _).


% -----------------------------------------------------------------------------
%  Request processing
% -----------------------------------------------------------------------------

%! interface:process_requests(+Mode) is det.
%
% Main dispatch. Processes the parsed command-line options and maps each
% recognised flag (--sync, --graph, --merge, etc.) onto the corresponding
% action predicate via the request_handler/5 table. Falls through to the
% catch-all clause (halt(1)) if no handler matches or the action fails.
% ipc is a no-op: main(ipc) already connects and halt/1s. server, daemon
% and worker drop into the Prolog toplevel.

interface:process_requests(ipc) :-
  !.
interface:process_requests(server) :-
  !, prolog.
interface:process_requests(daemon) :-
  !, prolog.
interface:process_requests(worker) :-
  !, prolog.
interface:process_requests(Mode) :-
  interface:process_flags,
  interface:process_continue(Continue),
  interface:argv(Options, Args),

  message:log(['Args:      ', Args]),
  message:log(['Options:   ', Options]),

  set_prolog_flag(toplevel_prompt, '~m~d~l?- '),

  interface:dispatch_request(Mode, Args, Options),

  Continue.
interface:process_requests(_) :-
  ( catch(daemon:running, _, fail)
  -> true
  ;  halt(1)
  ).
