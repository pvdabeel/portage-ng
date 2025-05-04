/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2025, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> INTERFACE
The interface interpretes command line arguments passed to portage-ng.
*/

:- module(interface, []).

% **********************
% INTERFACE declarations
% **********************


%! interface:version(?Version)
%
% Retrieve the current version

interface:version(V) :-
  V = '2025.05.04'.


%! interface:status(?Status)
%
% Retrieve the current status (alpha,beta,testing,development,release)

interface:status(S) :-
  S = 'development'.


%! interface:spec(?Specification)
%
% Retrieve the interface specification

interface:spec(S) :-
  S = [[opt(mode),     type(atom),    default('standalone'),                  longflags(['mode'] ),
        help([ '  server:     start as server'
             , '  standalone: start standalone client, not requireing running server'
             , '  client:     start lightweight client, requiring running server'])],
       [opt(verbose),  type(boolean),   default(false),       shortflags(['v']), longflags(['verbose']),   help('Turn on verbose mode')],
       [opt(pretend),  type(boolean),   default(false),       shortflags(['p']), longflags(['pretend']),   help('Turn on pretend mode')],
       [opt(merge),    type(boolean),   default(true),        shortflags(['m']), longflags(['merge']),     help('Merge target package')],
       [opt(update),   type(boolean),   default(false),       shortflags(['u']), longflags(['update']),    help('Update target package')],
      %[opt(reinstall),type(boolean),   default(false),       shortflags(['r']), longflags(['reinstall']), help('Reinstall target package')],
       [opt(deep),     type(boolean),   default(false),       shortflags(['d']), longflags(['deep']),      help('Also consider dependencies')],
       [opt(emptytree),type(boolean),   default(false),       shortflags(['e']), longflags(['emptytree']), help('Pretend no other packages are installed')],
       [opt(buildpkg), type(boolean),   default(false),       shortflags(['b']), longflags(['buildpkg']),  help('Build packages')],
       [opt(resume),   type(boolean),   default(false),       shortflags(['r']), longflags(['resume']),    help('Resume previous command')],
       [opt(newuse),   type(boolean),   default(false),       shortflags(['N']), longflags(['newuse']),    help('Take into account new use flags')],
       [opt(oneshot),  type(boolean),   default(false),       shortflags(['1']), longflags(['oneshot']),   help('Do not add package to world')],
       [opt(prefix),   type(atom),      default('/'),                            longflags(['prefix']),    help('Set the prefix directory')],
       [opt(sync),     type(boolean),   default(false),                          longflags(['sync']),      help('Sync repository')],
       [opt(clear),    type(boolean),   default(false),                          longflags(['clear']),     help('Clear knowledge base')],
       [opt(graph),    type(boolean),   default(false),                          longflags(['graph']),     help('Create graph')],
       [opt(depclean), type(boolean),   default(false),       shortflags(['c']), longflags(['depclean']),  help('Clean dependencies')],
       [opt(info),     type(boolean),   default(false),                          longflags(['info']),      help('Show package version')],
       [opt(search),   type(boolean),   default(false),       shortflags(['s']), longflags(['search']),    help('Search for a target')],
       [opt(unmerge),  type(boolean),   default(false),       shortflags(['C']), longflags(['unmerge']),   help('Unmerge target')],
       [opt(usepkg),   type(boolean),   default(false),       shortflags(['k']), longflags(['usepkg']),    help('Use prebuilt packages')],
       [opt(quiet),    type(boolean),   default(false),       shortflags(['q']), longflags(['quiet']),     help('Reduced output')],
       [opt(server),   type(atom),      default(localhost),                      longflags(['server']),    help('Set Server hostname')],
       [opt(port),     type(integer),   default(4000),                           longflags(['port']),      help('Set Server port')],
       [opt(shell),    type(boolean),   default(false),                          longflags(['shell']),     help('Go to shell')],
       [opt(version),  type(boolean),   default(false),       shortflags(['V']), longflags(['version']),   help('Show version')]
      ].


%! interface:argv(-Options,-Args)
%
% Retrieve the arguments passed on the command line.

interface:argv(Options,Args) :-
  interface:spec(S),
  catch(opt_arguments(S,Options,Args),_,true).


%! interface:get_env(+Name,-Value)
%
% Retrieve content of environment variable

interface:getenv(Name,Value) :-
  system:getenv(Name,Value).


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
  interface:argv(Options,_),
  (lists:memberchk(mode(server),Options) ->
    Continue = true;
    (lists:memberchk(shell(true),Options) ->
     Continue = prolog;
     Continue = halt)).


%! interface:process_server(Host,Port)
%
% Retrieve the host and port from the command line

interface:process_server(Host,Port) :-
  interface:argv(Options,_),
  (lists:memberchk(host(Host),  Options) ; config:server_host(Host)),
  (lists:memberchk(port(Port),  Options) ; config:server_port(Port)),
  !.


%! interface:process_metadata(List)
%
% Retrieve the list of metadata to show from the command line

% interface:process_metadata(List) :-
%  interface:argv(Options,_),
%  (lists:memberchk(metadata(List),  Options) ; config:printable_metadata(List)),
%  !.


%! interface:process_requests(+Mode)
%
% Processes the options passed on the command line.
% Maps the options declared in interface:specs(S) onto actions defined as
% a set of predicates to be called.

interface:process_requests(_Mode) :-
  interface:version(Version),
  interface:status(Status),
  interface:process_continue(Continue),
  interface:argv(Options,Args),

  ( memberchk(verbose(true),Options) ->
      ( message:notice(['Args:    ',Args]),
  	message:notice(['Options: ',Options]) );
      true ) ,

  ( memberchk(version(true),Options)  -> (message:inform(['portage-ng ',Status,' version - ',Version]), Continue) ;
    memberchk(info(true),Options)     -> (interface:process_action(info,Args,Options),                  Continue) ;
    memberchk(clear(true),Options)    -> (kb:clear, 							Continue) ;
    memberchk(graph(true),Options)    -> (grapher:test(portage),nl, 				  	Continue) ;
    memberchk(unmerge(true),Options)  -> (message:warning('unmerge action to be implemented'), 		Continue) ;
    memberchk(depclean(true),Options) -> (message:warning('depclean action to be implemented'), 	Continue) ;
    memberchk(search(true),Options)   -> (interface:process_action(search,Args,Options),                Continue) ;
    memberchk(sync(true),Options)     -> (kb:sync, kb:save,!, 						Continue) ;
   %memberchk(reinstall(true),Options)-> (interface:process_action(reinstall,Args,Options),             Continue) ;
    memberchk(merge(true),Options)    -> (interface:process_action(merge,Args,Options),                 Continue) ;
    memberchk(shell(true),Options)    -> (message:inform(['portage-ng shell - ',Version]),		prolog)),

  Continue.


%! interface:process_action(+Action,+Args,+Options)
%
% Processes a specific action.

% ----
% INFO
% ----

interface:process_action(info,[],_) :-
  !,
  % todo: display general information
  message:inform('General information placeholder').

interface:process_action(info,Args,_Options) :-
  forall(member(Arg,Args),(atom_codes(Arg,Codes),
                           phrase(eapi:qualified_target(Q),Codes),
			   once(kb:query(Q,R://E)),
                           printer:print_entry(R://E))).


% ------
% SEARCH
% ------

interface:process_action(search,[],_) :-
  !,
  message:inform('Need more arguments').

interface:process_action(search,Args,Options) :-
  phrase(eapi:query(Q),Args),
  (memberchk(verbose(true),Options) -> ( message:notice(['Query:   ',Q]) ); true),
  forall(kb:query(Q,R://E), writeln(R://E)).

% todo: do the 'all' on the server side
% process results.
% give some explanation on expected input


% -----
% MERGE
% -----

%interface:process_action(merge,[],_) :- !.
%interface:process_action(merge,ArgsSets,Options) :-
%  !,
%  config:proving_target(T),
%  interface:process_action_mr(T,ArgsSets,Options).

%interface:process_action(reinstall,[],_) :- !.
%interface:process_action(reinstall,ArgsSets,Options) :-
%  !,
%  interface:process_action_mr(reinstall,ArgsSets,Options).


interface:process_action(merge,ArgsSets,Options) :-
  config:proving_target(T),
  eapi:substitute_sets(ArgsSets,Args),
  (memberchk(verbose(true),Options)   -> ( message:notice(['Full args:',Args]) ); true),
  findall(R://E:T, (member(Arg,Args),
                    atom_codes(Arg,Codes),
                    phrase(eapi:qualified_target(Q),Codes),
                    once(kb:query(Q,R://E))),
          Proposal),!,
  (memberchk(verbose(true),Options)   -> ( message:notice(['Proposal: ',Proposal]) ); true),
  (memberchk(emptytree(true),Options) -> ( assert(prover:flag(emptytree)) );  true),

  memberchk(mode(Mode),Options),
  interface:process_server(Host,Port),
  (Mode == 'client' ->
    (client:rpc_execute(Host,Port,
     (oracle:with_q(prover:prove(Proposal,[],Proof,[],Model,[],_)),
      oracle:with_q(planner:plan(Proof,[],[],Plan)),
      printer:print(Proposal,Model,Proof,Plan)),
     Output),
     writeln(Output));
    ( prover:prove(Proposal,[],Proof,[],Model,[],_),
      planner:plan(Proof,[],[],Plan),
      printer:print(Proposal,Model,Proof,Plan))).

% todo: rpc_wrapper
% process results
% give some explaantion on expected input
% pass emptytree to rpc server
% pass world and set to rpc server

