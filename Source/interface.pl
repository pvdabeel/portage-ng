/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> INTERFACE
The interface interpretes command line arguments passed to portage-ng.
*/

:- module(interface, []).

% =============================================================================
%  INTERFACE declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Interface version
% -----------------------------------------------------------------------------

%! interface:version(?Version)
%
% Retrieve the current version

interface:version(V) :-
  script:exec('version',V).


%! interface:status(?Status)
%
% Retrieve the current status (alpha,beta,testing,development,release)

interface:status(S) :-
  S = 'development'.


% -----------------------------------------------------------------------------
%  Interface specifications
% -----------------------------------------------------------------------------

%! interface:spec(?Specification)
%
% Retrieve the interface specification

interface:spec(S) :-
  config:hostname(Hostname),
  S = [[opt(mode),      type(atom),      default('standalone'),                   longflags(['mode'] ),
        help([ '  server:     start as server'
             , '  standalone: start standalone client, not requireing running server'
             , '  client:     start lightweight client, requiring running server'])],
       [opt(verbose),   type(boolean),   default(false),       shortflags(['v']), longflags(['verbose']),   help('Turn on verbose mode')],
       [opt(pretend),   type(boolean),   default(false),       shortflags(['p']), longflags(['pretend']),   help('Turn on pretend mode')],
       [opt(fetchonly), type(boolean),   default(false),       shortflags(['f']), longflags(['fetchonly']), help('Turn on fetchonly mode')],
       [opt(merge),     type(boolean),   default(true),        shortflags(['m']), longflags(['merge']),     help('Merge target package')],
       [opt(update),    type(boolean),   default(false),       shortflags(['u']), longflags(['update']),    help('Update target package')],
       [opt(upgrade),   type(boolean),   default(false),                          longflags(['upgrade']),   help('Upgrade set (default: @world): first compute a fresh plan under --emptytree, then run depclean')],
       [opt(deep),      type(boolean),   default(false),       shortflags(['d']), longflags(['deep']),      help('Also consider dependencies')],
       [opt(pdepend),   type(boolean),   default(false),                          longflags(['pdepend']),   help('Enable PDEPEND dependency handling (development/testing flag)')],
       [opt(delay_triggers), type(boolean), default(false),                        longflags(['delay-triggers']), help('Prover optimization: delay trigger construction (replaces old --deep prover behavior)')],
       [opt(emptytree), type(boolean),   default(false),       shortflags(['e']), longflags(['emptytree']), help('Pretend no other packages are installed')],
       [opt(buildpkg),  type(boolean),   default(false),       shortflags(['b']), longflags(['buildpkg']),  help('Build packages')],
       [opt(resume),    type(boolean),   default(false),       shortflags(['r']), longflags(['resume']),    help('Resume previous command')],
       [opt(newuse),    type(boolean),   default(false),       shortflags(['N']), longflags(['newuse']),    help('Take into account new use flags')],
       [opt(oneshot),   type(boolean),   default(false),       shortflags(['1']), longflags(['oneshot']),   help('Do not add package to world')],
       [opt(prefix),    type(atom),      default('/'),                            longflags(['prefix']),    help('Set the prefix directory')],
       [opt(style),     type(atom),      default('fancy'),                        longflags(['style']),     help('Set the printing style: fancy, column or short')],
       [opt(sync),      type(boolean),   default(false),                          longflags(['sync']),      help('Sync repository')],
       [opt(clear),     type(boolean),   default(false),                          longflags(['clear']),     help('Clear knowledge base')],
       [opt(graph),     type(boolean),   default(false),                          longflags(['graph']),     help('Create graph. Optional arg: "modified" or "full" (overrides config.pl for this run).')],
       [opt(depclean),  type(boolean),   default(false),       shortflags(['c']), longflags(['depclean']),  help('Clean dependencies')],
       [opt(info),      type(boolean),   default(false),       shortflags(['i']), longflags(['info']),      help('Show package version')],
       [opt(bugs),      type(boolean),   default(false),                          longflags(['bugs']),      help('Print bug report drafts (Gentoo Bugzilla) for the given target, without printing a plan')],
       [opt(search),    type(boolean),   default(false),       shortflags(['s']), longflags(['search']),    help('Search for a target')],
       [opt(unmerge),   type(boolean),   default(false),       shortflags(['C']), longflags(['unmerge']),   help('Unmerge target')],
       [opt(usepkg),    type(boolean),   default(false),       shortflags(['k']), longflags(['usepkg']),    help('Use prebuilt packages')],
       [opt(quiet),     type(boolean),   default(false),       shortflags(['q']), longflags(['quiet']),     help('Reduced output')],
       [opt(time_limit),type(integer),   default(0),                               longflags(['time-limit']),help('Abort proving/planning after N seconds (0 = no limit)')],
       [opt(host),      type(atom),      default(Hostname),                       longflags(['host']),      help('Set server hostname (client mode)')],
       [opt(port),      type(integer),   default(4000),                           longflags(['port']),      help('Set Server port (client or server mode)')],
       [opt(shell),     type(boolean),   default(false),                          longflags(['shell']),     help('Go to shell')],
       [opt(save),      type(boolean),   default(false),                          longflags(['save']),      help('Save knowledgebase (only relevant in client mode')],
       [opt(load),      type(boolean),   default(false),                          longflags(['load']),      help('Load knowledgebase (only relevant in client mode)')],
       [opt(version),   type(boolean),   default(false),       shortflags(['V']), longflags(['version']),   help('Show version')],
       [opt(ci),        type(boolean),   default(false),                          longflags(['ci']),        help('CI mode: non-interactive, fail with nonzero exit code on assumptions')]
      ].


% -----------------------------------------------------------------------------
%  Command line reading
% -----------------------------------------------------------------------------

%! interface:argv(-Options,-Args)
%
% Retrieve the arguments passed on the command line.

:- dynamic interface:argv_/2.

intarface:argv(Options,Args) :-
  interface:argv_(Options,Args),!.

interface:argv(Options,Args) :-
  interface:spec(S),
  catch(opt_arguments(S,Options,Args),_,true),
  assertz(interface:argv_(Options,Args)).


%! interface:get_env(+Name,-Value)
%
% Retrieve content of environment variable

interface:getenv(Name,Value) :-
  system:getenv(Name,Value).


% -----------------------------------------------------------------------------
%  Option handling
% -----------------------------------------------------------------------------

%! interface:process_flags
%
% Retrieve the flags to be used to start portage-ng

interface:process_flags:-
  interface:argv(Options,_),
  (lists:memberchk(deep(true),      Options) -> asserta(preference:local_flag(deep))            ; true),
  (lists:memberchk(pdepend(true),   Options) -> asserta(preference:local_flag(pdepend))         ; true),
  (lists:memberchk(delay_triggers(true), Options) -> asserta(preference:local_flag(delay_triggers)) ; true),
  (lists:memberchk(emptytree(true), Options) -> asserta(preference:local_flag(emptytree))       ; true),
  (lists:memberchk(depclean(true),  Options) -> asserta(preference:local_flag(depclean))        ; true),
  (lists:memberchk(newuse(true),    Options) -> asserta(preference:local_flag(newuse))          ; true),
  (lists:memberchk(pretend(true),   Options) -> asserta(preference:local_flag(pretend))         ; true),
  (lists:memberchk(oneshot(true),   Options) -> asserta(preference:local_flag(oneshot))         ; true),
  (lists:memberchk(verbose(true),   Options) -> asserta(config:verbose(true))                   ; true),
  (lists:memberchk(style(Style),    Options) -> asserta(config:interface_printing_style(Style)) ; true).


%! interface:process_mode(-Mode)
%
% Retrieve the mode to be used to start portage-ng

interface:process_mode(Mode) :-
  interface:argv(Options,_),
  lists:memberchk(mode(Mode),Options).


%! interface:process_continue(-Continue)
%
% Defines what needs to happen after executing a command.
% We either launch prolog, or we halt, depending on
% option passed via the command line.

interface:process_continue(Continue) :-
  !,
  interface:argv(Options,_),
  interface:version(Version),
  lists:memberchk(mode(Mode),Options),


  (lists:memberchk(mode(server),Options)
   ->  message:logo(['::- portage-ng ',Version],Mode),
       Continue = true
   ;   (lists:memberchk(shell(true),Options)
        -> message:logo(['::- portage-ng ',Version],Mode),
           Continue = prolog
        ;  Continue = halt)).


%! interface:get_port(-Port)
%
% Retrieve the port from the command line or config

interface:get_port(Port) :-
  interface:argv(Options,_),
  ( lists:memberchk(port(Port), Options) -> true
  ; config:server_port(Port)
  ),
  !.

%! interface:process_server(Host,Port)
%
% Retrieve the host and port from the command line

interface:process_server(Host,Port) :-
  interface:argv(Options,_),
  (lists:memberchk(host(Host),  Options) ; config:server_host(Host)),
  interface:get_port(Port),
  !.


%! interface:process_requests(+Mode)
%
% Processes the options passed on the command line.
% Maps the options declared in interface:specs(S) onto actions defined as
% a set of predicates to be called.

interface:process_requests(server) :-
  !, prolog.

interface:process_requests(Mode) :-
  interface:version(Version),

  interface:process_flags,
  interface:process_continue(Continue),
  interface:argv(Options,Args),

  message:log(['Args:      ',Args]),
  message:log(['Options:   ',Options]),

  set_prolog_flag(toplevel_prompt,'~m~d~l?- '),

  ( memberchk(version(true),Options)  -> (message:logo(['::- portage-ng ',Version]),                Continue) ;
    memberchk(info(true),Options)     -> (interface:process_action(info,Args,Options),              Continue) ;
    memberchk(bugs(true),Options)     -> (interface:process_bugs(Args,Options),                     Continue) ;
    memberchk(clear(true),Options)    -> (kb:clear, 						    Continue) ;
    memberchk(graph(true),Options)    -> (interface:process_graph(Args), nl, 				  	    Continue) ;
    memberchk(unmerge(true),Options)  -> (interface:process_action(uninstall,Args,Options), 	    Continue) ;
    memberchk(depclean(true),Options) -> (interface:process_action(depclean,Args,Options),         Continue) ;
    memberchk(upgrade(true),Options)  -> (interface:process_upgrade(Args,Options),                 Continue) ;
    % For a single target, Portage-style update behaves like a normal merge:
    % resolve full runtime closure and perform a transactional replace if needed.
    % In portage-ng the "full closure" corresponds to proving :run.
    memberchk(update(true),Options)   -> (interface:process_action(run,Args,Options),               Continue) ;
    memberchk(search(true),Options)   -> (interface:process_action(search,Args,Options),            Continue) ;
    memberchk(sync(true),Options)     -> ((Mode == standalone
                                           -> (kb:sync, kb:save)
                                           ;  (kb:sync)),!, 					    Continue) ;
    memberchk(save(true),Options)     -> (kb:save,!, 						    Continue) ;
    memberchk(load(true),Options)     -> (kb:load,!, 						    Continue) ;
    memberchk(fetchonly(true),Options)-> (interface:process_action(fetchonly,Args,Options),         Continue) ;
    memberchk(merge(true),Options)    -> (interface:process_action(run,Args,Options),               Continue) ;
    memberchk(shell(true),Options)    -> (message:logo(['::- portage-ng shell - ',Version]),	    prolog)),

  Continue.

% -----------------------------------------------------------------------------
%  Action: GRAPH (optional mode argument)
% -----------------------------------------------------------------------------
%
% Usage:
%   --graph            (uses config.pl)
%   --graph modified   (override to modified-only for this run)
%   --graph full       (override to graph everything for this run)
%
interface:process_graph([]) :-
  kb:graph,
  !.
interface:process_graph([modified]) :-
  setup_call_cleanup(
    asserta(config:interface_graph_modified_only(true)),
    kb:graph,
    retractall(config:interface_graph_modified_only(_))
  ),
  !.
interface:process_graph([full]) :-
  setup_call_cleanup(
    asserta(config:interface_graph_modified_only(false)),
    kb:graph,
    retractall(config:interface_graph_modified_only(_))
  ),
  !.
interface:process_graph(Args) :-
  message:warning(['--graph: ignoring unexpected args: ', Args]),
  kb:graph.


% -----------------------------------------------------------------------------
%  Action: UPGRADE (emptytree + depclean, two-phase)
% -----------------------------------------------------------------------------
%
% Minimal Portage-like "upgrade then depclean":
% - Phase A: compute a fresh plan under emptytree (ignore installed shortcuts)
% - Phase B: run depclean on the real installed graph (no emptytree)
%
% Note: upgrade should not modify @world; we enforce oneshot semantics here.
%
interface:process_upgrade(ArgsSets0, Options) :-
  % Default roots: @world when no args are provided (Portage-like)
  ( ArgsSets0 == [] -> ArgsSets = [world] ; ArgsSets = ArgsSets0 ),
  setup_call_cleanup(
    ( asserta(preference:local_flag(oneshot)),
      asserta(preference:local_flag(emptytree))
    ),
    interface:process_action(run, ArgsSets, Options),
    ( retractall(preference:local_flag(emptytree)),
      retractall(preference:local_flag(oneshot))
    )
  ),
  % Cleanup phase on the real VDB graph (depclean internally asserts local_flag(depclean))
  interface:process_action(depclean, ArgsSets, Options).


% -----------------------------------------------------------------------------
%  Action: BUG REPORT DRAFTS
% -----------------------------------------------------------------------------
%
% Prints only the suggested bug report drafts for a target, without printing the
% full plan.
%
% Example:
%   portage-ng-dev --mode standalone --bugs ghc
%

interface:process_bugs([], _Options) :-
  !,
  message:inform('Need more arguments').

interface:process_bugs(ArgsSets, Options) :-
  interface:process_mode(Mode),
  interface:process_server(Host,Port),
  eapi:substitute_sets(ArgsSets,Args),
  % Use Action=run to match normal merge planning semantics (install+run deps).
  findall(R://E:run?{[]}, ( member(Arg,Args),
                           atom_codes(Arg,Codes),
                           phrase(eapi:qualified_target(Q),Codes),
                           once(kb:query(Q,R://E))
                         ),
          Proposal),!,
  message:log(['Proposal:  ',Proposal]),
  ( Proposal == [] ->
      message:inform('No matching target found'),
      !
  ; true
  ),
  ( Mode == 'client' ->
      client:rpc_execute(Host,Port,
        ( prover:prove(Proposal,t,ProofAVL,t,_ModelAVL,t,_Constraint,t,_Triggers),
          interface:print_bugreport_drafts_from_proof(ProofAVL)
        ),
        Output),
      writeln(Output)
  ; % standalone / server-side execution
    prover:prove(Proposal,t,ProofAVL,t,_ModelAVL,t,_Constraint,t,_Triggers),
    interface:print_bugreport_drafts_from_proof(ProofAVL),
    % In --bugs mode we do not sync and we do not touch world.
    ( memberchk(ci(true), Options) ->
        halt(0)
    ; true
    )
  ).

interface:print_bugreport_drafts_from_proof(ProofAVL) :-
  findall(Content, assoc:gen_assoc(rule(assumed(Content)), ProofAVL, _), DomainAssumptions0),
  sort(DomainAssumptions0, DomainAssumptions),
  ( DomainAssumptions == [] ->
      message:header('Bug report drafts (Gentoo Bugzilla)'),
      nl,
      writeln('  (none)')
  ; printer:print_bugreport_drafts(DomainAssumptions)
  ).


% -----------------------------------------------------------------------------
%  Action processing
% -----------------------------------------------------------------------------

%! interface:process_action(+Action,+Args,+Options)
%
% Processes a specific action.

% -----------------------------------------------------------------------------
%  Action: INFO
% -----------------------------------------------------------------------------

interface:process_action(info,[],_) :-
  !,
  % todo: display general information
  message:inform('General information placeholder').

interface:process_action(info,Args,_Options) :-
  !,
  forall(member(Arg,Args),(atom_codes(Arg,Codes),
                           phrase(eapi:qualified_target(Q),Codes),
			   once(kb:query(Q,R://E)),
                           printer:print_entry(R://E))).


% -----------------------------------------------------------------------------
%  Action: SEARCH
% -----------------------------------------------------------------------------

interface:process_action(search,[],_) :-
  !,
  message:inform('Need more arguments').

interface:process_action(search,Args,_Options) :-
  !,
  phrase(eapi:query(Q),Args),
  message:log(['Query:   ',Q]),
  forall(kb:query(Q,R://E), writeln(R://E)).

% -----------------------------------------------------------------------------
%  Action: DEPCLEAN
% -----------------------------------------------------------------------------
%
% Proof-based depclean: compute installed packages not required by @world.
%
interface:process_action(depclean, ArgsSets, _Options) :-
  !,
  ensure_loaded(portage('Source/depclean.pl')),
  depclean:run(ArgsSets).


% -----------------------------------------------------------------------------
%  Action: MERGE
% -----------------------------------------------------------------------------

interface:process_action(_Action,[],_) :- !.

interface:process_action(Action,ArgsSets,Options) :-
  interface:process_mode(Mode),
  interface:process_server(Host,Port),
  ( memberchk(pretend(true), Options) -> PretendMode = true ; PretendMode = false ),
  eapi:substitute_sets(ArgsSets,Args),
  % IMPORTANT:
  % Do NOT resolve a concrete candidate here. We only check that the target has
  % at least one candidate, then defer actual candidate selection to the prover
  % via rules:rule/2 (target(Q,Arg):Action).
  findall(target(Q,Arg):Action?{[]},
          ( member(Arg,Args),
            atom_codes(Arg,Codes),
            phrase(eapi:qualified_target(Q),Codes),
            ( Action == uninstall
              -> once((kb:query(Q, R0://E0), kb:query(installed(true), R0://E0)))
              ;  once(kb:query(Q, _R://_E))
            )
          ),
          Proposal),!,
  message:log(['Proposal:  ',Proposal]),
  (Proposal == []
   -> ( config:llm_support(Prompt),
        atomic_list_concat([Prompt|Args],Message),
        grok(Message),fail )
   ;  true),
  (Mode == 'client' ->
    (client:rpc_execute(Host,Port,
     (printer:prove_plan(Proposal, ProofAVL, ModelAVL, Plan, Triggers),
      printer:print(Proposal,ModelAVL,ProofAVL,Plan,Triggers),
      ( PretendMode == false -> vdb:sync ; true )),
     Output),
     writeln(Output));
    ( ( memberchk(time_limit(TimeLimitSec), Options) -> true ; TimeLimitSec = 0 ),
      ( TimeLimitSec =< 0 ->
          ( ( printer:prove_plan(Proposal, ProofAVL, ModelAVL, Plan, Triggers) ->
                FallbackUsed = false
            ; % Fallback UX: show the plan under the assumption that blockers are satisfied.
              message:bubble(orange,'Warning'),
              message:color(orange),
              message:print(' No valid plan found due to blockers/conflicts. Showing a plan with blocker assumptions; please verify.'), nl,
              message:color(normal),
              rules:with_assume_blockers(
                printer:prove_plan(Proposal, ProofAVL, ModelAVL, Plan, Triggers)
              ),
              FallbackUsed = true
            ),
            printer:print(Proposal,ModelAVL,ProofAVL,Plan,Triggers)
          )
      ; catch(
          call_with_time_limit(TimeLimitSec,
            ( ( printer:prove_plan(Proposal, ProofAVL, ModelAVL, Plan, Triggers) ->
                  FallbackUsed = false
              ; message:bubble(orange,'Warning'),
                message:color(orange),
                message:print(' No valid plan found due to blockers/conflicts. Showing a plan with blocker assumptions; please verify.'), nl,
                message:color(normal),
                rules:with_assume_blockers(
                  printer:prove_plan(Proposal, ProofAVL, ModelAVL, Plan, Triggers)
                ),
                FallbackUsed = true
              ),
              printer:print(Proposal,ModelAVL,ProofAVL,Plan,Triggers)
            )),
          time_limit_exceeded,
          ( message:bubble(red,'Error'),
            message:color(red),
            message:print(' Time limit exceeded while proving/planning. Try increasing --time-limit or narrowing the target.'), nl,
            message:color(normal),
            flush_output,
            halt(1)
          )
        )
      ),
      ( memberchk(ci(true), Options) ->
          interface:ci_exit_code(ModelAVL, ProofAVL, ExitCode),
          halt(ExitCode)
      ; FallbackUsed == false,
        PretendMode == false ->
          vdb:sync
      ; true
      ),
      % Apply any world actions that were produced by the proof/plan.
      % (This keeps "world update" rule-driven, but still executed by the CLI.)
      ( FallbackUsed == false,
        PretendMode == false ->
            interface:execute_world_actions_from_plan(Plan),
            world:save
        ; true
        )
    )).


% -----------------------------------------------------------------------------
%  Side effects: execute planned world actions
% -----------------------------------------------------------------------------

interface:execute_world_actions_from_plan([]) :- !.
interface:execute_world_actions_from_plan([Step|Rest]) :-
  interface:execute_world_actions_step(Step),
  interface:execute_world_actions_from_plan(Rest).

interface:execute_world_actions_step([]) :- !.
interface:execute_world_actions_step([Rule|Rest]) :-
  ( Rule = rule(Head,_Body),
    prover:canon_literal(Head, Core, _Ctx),
    Core = world_action(Op, Arg):world ->
      ( Op == register ->
          world:register(Arg)
      ; Op == unregister ->
          world:unregister(Arg)
      ; true
      )
  ; true
  ),
  interface:execute_world_actions_step(Rest).


% -----------------------------------------------------------------------------
%  CI helpers
% -----------------------------------------------------------------------------

% Exit code policy:
% - 0: no assumptions
% - 1: only prover cycle-break assumptions
% - 2: any domain assumptions (missing/non-existent deps etc.)
interface:ci_exit_code(ModelAVL, ProofAVL, ExitCode) :-
  ( interface:has_any_assumption(ModelAVL) ->
      ( interface:has_domain_assumptions(ProofAVL) -> ExitCode = 2
      ; interface:has_cycle_breaks(ProofAVL)       -> ExitCode = 1
      ; ExitCode = 1
      )
  ; ExitCode = 0
  ).

interface:has_any_assumption(ModelAVL) :-
  assoc:gen_assoc(Key, ModelAVL, _),
  Key = assumed(_),
  !.

interface:has_domain_assumptions(ProofAVL) :-
  assoc:gen_assoc(rule(assumed(_)), ProofAVL, _),
  !.

interface:has_cycle_breaks(ProofAVL) :-
  assoc:gen_assoc(assumed(rule(_)), ProofAVL, _),
  !.
