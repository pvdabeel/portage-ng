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
  S = [[opt(mode),      type(atom),      default('standalone'),                   longflags(['mode'] ),
        help([ '  server:     start as server'
             , '  standalone: start standalone client, not requireing running server'
             , '  client:     start lightweight client, requiring running server'])],
       [opt(verbose),   type(boolean),   default(false),       shortflags(['v']), longflags(['verbose']),   help('Turn on verbose mode')],
       [opt(pretend),   type(boolean),   default(false),       shortflags(['p']), longflags(['pretend']),   help('Turn on pretend mode')],
       [opt(fetchonly), type(boolean),   default(false),       shortflags(['f']), longflags(['fetchonly']), help('Turn on fetchonly mode')],
       [opt(merge),     type(boolean),   default(true),        shortflags(['m']), longflags(['merge']),     help('Merge target package')],
       [opt(update),    type(boolean),   default(false),       shortflags(['u']), longflags(['update']),    help('Update target package')],
       [opt(deep),      type(boolean),   default(false),       shortflags(['d']), longflags(['deep']),      help('Also consider dependencies')],
       [opt(emptytree), type(boolean),   default(false),       shortflags(['e']), longflags(['emptytree']), help('Pretend no other packages are installed')],
       [opt(buildpkg),  type(boolean),   default(false),       shortflags(['b']), longflags(['buildpkg']),  help('Build packages')],
       [opt(resume),    type(boolean),   default(false),       shortflags(['r']), longflags(['resume']),    help('Resume previous command')],
       [opt(newuse),    type(boolean),   default(false),       shortflags(['N']), longflags(['newuse']),    help('Take into account new use flags')],
       [opt(oneshot),   type(boolean),   default(false),       shortflags(['1']), longflags(['oneshot']),   help('Do not add package to world')],
       [opt(prefix),    type(atom),      default('/'),                            longflags(['prefix']),    help('Set the prefix directory')],
       [opt(style),     type(atom),      default('fancy'),                        longflags(['style']),     help('Set the printing style: fancy, column or short')],
       [opt(sync),      type(boolean),   default(false),                          longflags(['sync']),      help('Sync repository')],
       [opt(clear),     type(boolean),   default(false),                          longflags(['clear']),     help('Clear knowledge base')],
       [opt(graph),     type(boolean),   default(false),                          longflags(['graph']),     help('Create graph')],
       [opt(depclean),  type(boolean),   default(false),       shortflags(['c']), longflags(['depclean']),  help('Clean dependencies')],
       [opt(info),      type(boolean),   default(false),       shortflags(['i']), longflags(['info']),      help('Show package version')],
       [opt(search),    type(boolean),   default(false),       shortflags(['s']), longflags(['search']),    help('Search for a target')],
       [opt(unmerge),   type(boolean),   default(false),       shortflags(['C']), longflags(['unmerge']),   help('Unmerge target')],
       [opt(usepkg),    type(boolean),   default(false),       shortflags(['k']), longflags(['usepkg']),    help('Use prebuilt packages')],
       [opt(quiet),     type(boolean),   default(false),       shortflags(['q']), longflags(['quiet']),     help('Reduced output')],
       [opt(server),    type(atom),      default(localhost),                      longflags(['server']),    help('Set Server hostname')],
       [opt(port),      type(integer),   default(4000),                           longflags(['port']),      help('Set Server port')],
       [opt(shell),     type(boolean),   default(false),                          longflags(['shell']),     help('Go to shell')],
       [opt(save),      type(boolean),   default(false),                          longflags(['save']),      help('Save knowledgebase (only relevant in client mode')],
       [opt(load),      type(boolean),   default(false),                          longflags(['load']),      help('Load knowledgebase (only relevant in client mode)')],
       [opt(version),   type(boolean),   default(false),       shortflags(['V']), longflags(['version']),   help('Show version')]
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
  (lists:memberchk(emptytree(true), Options) -> asserta(preference:local_flag(emptytree))       ; true),
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


%! interface:process_server(Host,Port)
%
% Retrieve the host and port from the command line

interface:process_server(Host,Port) :-
  interface:argv(Options,_),
  (lists:memberchk(host(Host),  Options) ; config:server_host(Host)),
  (lists:memberchk(port(Port),  Options) ; config:server_port(Port)).


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
    memberchk(clear(true),Options)    -> (kb:clear, 						    Continue) ;
    memberchk(graph(true),Options)    -> (kb:graph,nl, 				  	            Continue) ;
    memberchk(unmerge(true),Options)  -> (interface:process_action(uninstall,Args,Options), 	    Continue) ;
    memberchk(depclean(true),Options) -> (message:warning('depclean action to be implemented'),     Continue) ;
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
%  Action: MERGE
% -----------------------------------------------------------------------------

interface:process_action(_Action,[],_) :- !.

interface:process_action(Action,ArgsSets,_Options) :-
  interface:process_mode(Mode),
  interface:process_server(Host,Port),
  eapi:substitute_sets(ArgsSets,Args),
  findall(R://E:Action?{[]}, (member(Arg,Args),
                              atom_codes(Arg,Codes),
                              phrase(eapi:qualified_target(Q),Codes),
                              once((kb:query(Q,R://E),
                                    (Action = 'uninstall'
                                    -> kb:query(installed(true),R://E)
                                    ;  true))
                              )),
          Proposal),!,
  message:log(['Proposal:  ',Proposal]),
  (Proposal == []
   -> ( config:llm_support(Prompt),
        atomic_list_concat([Prompt|Args],Message),
        grok(Message),fail )
   ;  true),
  (Mode == 'client' ->
    (client:rpc_execute(Host,Port,
     (oracle:with_q(prover:prove(Proposal,t,ProofAVL,t,ModelAVL,t,_Constraint,t,Triggers)),
      oracle:with_q(planner:plan(ProofAVL,Triggers,t,Plan)),
      printer:print(Proposal,ModelAVL,ProofAVL,Plan,Triggers),
      pkg:sync),
     Output),
     writeln(Output));
    (prover:prove(Proposal,t,ProofAVL,t,ModelAVL,t,_Constraint,t,Triggers),
     planner:plan(ProofAVL,Triggers,t,Plan),
     printer:print(Proposal,ModelAVL,ProofAVL,Plan,Triggers),
     pkg:sync )),
  \+preference:flag(oneshot)
  -> (Action = 'uninstall'
      -> world:unregister(Args)
      ;  world:register(Args)).
