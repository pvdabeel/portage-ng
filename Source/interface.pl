/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2024, Pieter Van den Abeele

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
  V = '2024.09.03'.


%! interface:status(?Status)
%
% Retrieve the current status (alpha,beta,testing,development,release)

interface:status(S) :-
  S = 'development'.

%! interface:spec(?Specification)
%
% Retrieve the interface specification

interface:spec(S) :-
  S = [[opt(mode),     type(atom),    default('server'),                    longflags(['mode'] ),
        help([ '  server:     start as server'
             , '  standalone: start standalone client, not requireing running server'
             , '  client:     start lightweight client, requiring running server'])],
       [opt(verbose),  type(boolean),   default(false),    shortflags(['v']), longflags(['verbose']),   help('Turn on verbose mode')],
       [opt(pretend),  type(boolean),   default(false),    shortflags(['p']), longflags(['pretend']),   help('Turn on pretend mode')],
       [opt(merge),    type(boolean),   default(true),     shortflags(['m']), longflags(['merge']),     help('Merge target package')],
       [opt(update),   type(boolean),   default(false),    shortflags(['u']), longflags(['update']),    help('Update target package')],
       [opt(deep),     type(boolean),   default(false),    shortflags(['d']), longflags(['deep']),      help('Also consider dependencies')],
       [opt(emptytree),type(boolean),   default(false),    shortflags(['e']), longflags(['emptytree']), help('Pretend no other packages are installed')],
       [opt(buildpkg), type(boolean),   default(false),    shortflags(['b']), longflags(['buildpkg']),  help('Build packages')],
       [opt(resume),   type(boolean),   default(false),    shortflags(['r']), longflags(['resume']),    help('Resume previous command')],
       [opt(newuse),   type(boolean),   default(false),    shortflags(['N']), longflags(['newuse']),    help('Take into account new use flags')],
       [opt(oneshot),  type(boolean),   default(false),    shortflags(['1']), longflags(['oneshot']),   help('Do not add package to world')],
       [opt(prefix),   type(atom),      default('/'),                         longflags(['prefix']),    help('Set the prefix directory')],
       [opt(sync),     type(boolean),   default(false),                       longflags(['sync']),      help('Sync repository')],
       [opt(clear),    type(boolean),   default(false),                       longflags(['clear']),     help('Clear knowledge base')],
       [opt(graph),    type(boolean),   default(false),                       longflags(['graph']),     help('Create graph')],
       [opt(depclean), type(boolean),   default(false),    shortflags(['c']), longflags(['depclean']),  help('Clean dependencies')],
       [opt(info),     type(boolean),   default(false),                       longflags(['info']),      help('Show package version')],
       [opt(search),   type(boolean),   default(false),    shortflags(['s']), longflags(['search']),    help('Search for a target')],
       [opt(unmerge),  type(boolean),   default(false),    shortflags(['C']), longflags(['unmerge']),   help('Unmerge target')],
       [opt(usepkg),   type(boolean),   default(false),    shortflags(['k']), longflags(['usepkg']),    help('Use prebuilt packages')],
       [opt(quiet),    type(boolean),   default(false),    shortflags(['q']), longflags(['quiet']),     help('Reduced output')],
       [opt(server),   type(atom),      default(localhost),                   longflags(['server']),    help('Set Server hostname')],
       [opt(port),     type(integer),   default(4000),                        longflags(['port']),      help('Set Server port')],
       [opt(shell),    type(boolean),   default(false),                       longflags(['shell']),     help('Go to shell')],
       [opt(version),  type(boolean),   default(false),    shortflags(['V']), longflags(['version']),   help('Show version')]
      ].


%! interface:argv(-Options,-Args)
%
% Retrieve the arguments passed on the command line.

interface:argv(Options,Args) :-
  interface:spec(S),
  catch(opt_arguments(S,Options,Args),_,true).


%! interface:process_mode(Options,_Args,Mode)
%
% Retrieve the mode to be used to start portage-ng

interface:process_mode(Mode) :-
  interface:argv(Options,_),
  lists:memberchk(mode(Mode),Options).


%! interface:process_mode(Options,_Args,Mode)
%
% Retrieve the mode to be used to start portage-ng

interface:process_continue(Continue) :-
  interface:argv(Options,_),
  lists:memberchk(shell(true),Options) ->
    Continue = prolog;
    Continue = halt.


%! interface:process_requests(Options,Args,Mode)
%
% Processes the arguments passed on the command line.
% Maps the options declared in interface:specs(S) onto actions defined as
% a set of predicates to be called.

interface:process_requests(Mode) :-
  interface:version(Version),
  interface:status(Status),
  interface:process_continue(Continue),
  interface:argv(Options,Args),


  ( memberchk(verbose(true),Options) ->
      ( message:inform(['Args:    ',Args]),
  	message:inform(['Options: ',Options]) );
      true ) ,

  ( memberchk(version(true),Options)  -> (message:inform(['portage-ng ',Status,' version - ',Version]), Continue) ;
    memberchk(info(true),Options)     -> (message:inform(['portage-ng ',Status,' version - ',Version]), Continue) ;
    memberchk(clear(true),Options)    -> (kb:clear, 							Continue) ;
    memberchk(sync(true),Options)     -> (kb:sync, kb:save, 						Continue) ;
    memberchk(graph(true),Options)    -> (grapher:test(portage), 				  	Continue) ;
    memberchk(unmerge(true),Options)  -> (message:warning('unmerge action to be implemented'), 		Continue) ;
    memberchk(depclean(true),Options) -> (message:warning('depclean action to be implemented'), 	Continue) ;
    member(search(true),Options)      -> ((Args == []) -> true ;
                                          (
    					    (Mode == 'client' ->
                                            client:rpc_execute('imac-pro.local',4000,phrase(eapi:query(Q),Args));
					    phrase(eapi:query(Q),Args)),
		                           (memberchk(verbose(true),Options) ->
   						( message:inform(['Query:   ',Q]));
 					        true),
					   (Mode == 'client' ->
                                            forall(client:rpc_execute('imac-pro.local',4000,query:search(Q,R://E)),
 						   writeln(R://E));
                                            forall(query:search(Q,R://E),
                                                  writeln(R://E)))
                                          ),								Continue) ;
    memberchk(sync(true),Options)     -> (kb:sync, kb:save, 						Continue) ;
    memberchk(merge(true),Options)    -> ((Args == []) -> true ;
                                          (
                                          forall(member(Arg,Args),
                                                 (atom_codes(Arg,Codes),
                                                  (
 					           (Mode == 'client' ->
                                                    client:rpc_execute('imac-pro.local',4000,phrase(eapi:qualified_target(Q),Codes));
						    phrase(eapi:qualified_target(Q),Codes)),
						   (memberchk(verbose(true),Options) ->
   						    (write('Query:   '),write(Q),nl);
 					            true),
  						   (memberchk(emptytree(true),Options) ->
 						    assert(prover:flag(emptytree));
						    true),
  						   (Mode == 'client' ->
						    (client:rpc_execute('imac-pro.local',4000,query:search(Q,R://E)),
  						     client:rpc_execute('imac-pro.local',4000,prover:prove(R://E:run,[],Proof,[],Model,[],_)),
                                                     client:rpc_execute('imac-pro.local',4000,planner:plan(Proof,[],[],Plan)));
                                                    (query:search(Q,R://E),
  						     prover:prove(R://E:run,[],Proof,[],Model,[],_),
                                                     planner:plan(Proof,[],[],Plan))),
                                                   printer:print(R://E:run,Model,Proof,Plan))))),      Continue) ;
                                                  %builder:build(R://E:T,Model,Proof,Plan)
    memberchk(shell(true),Options)    -> (message:inform(['portage-ng shell - ',Version]),		prolog)).
