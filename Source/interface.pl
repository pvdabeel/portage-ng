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
  V = '2024.08.16'.


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
  lists:member(mode(Mode),Options).

%! interface:process_requests(Options,Args,Mode)
%
% Processes the arguments passed on the command line.
% Maps the options declared in interface:specs(S) onto actions defined as
% a set of predicates to be called.

interface:process_requests(_Mode) :-
  interface:version(Version),
  interface:status(Status),
  interface:argv(Options,Args),
  ( member(version(true),Options)    -> (message:inform(['portage-ng ',Status,' version - ',Version]),   halt) ;
    member(info(true),Options)       -> (message:inform(['portage-ng ',Status,' version - ',Version]),   halt) ;
    member(clear(true),Options)      -> (kb:clear,                                                       halt) ;
    member(sync(true),Options)       -> (kb:sync, kb:save,                                               halt) ;
    member(graph(true),Options)      -> (grapher:test(portage),                                          halt) ;
    member(unmerge(true),Options)    -> (message:warning('unmerge action to be implemented'),            halt) ;
    member(depclean(true),Options)   -> (message:warning('depclean action to be implemented'),           halt) ;
%    member(search(true),Options)     -> ((Args == []) -> true ;
%                                         (phrase(eapi:query(Q),Args),
%                                          forall(knowledgebase:query(Q,R://E),writeln(R://E))),          halt) ;
    member(sync(true),Options)       -> (kb:sync, kb:save,                                               halt) ;
    member(shell(true),Options)      -> (message:inform(['portage-ng shell - ',Version]),                prolog);
    member(merge(true),Options)      -> ((Args == []) -> true ;
                                         (%os:sync,
   					  write('Args:    '), writeln(Args),
  					  write('Options: '), writeln(Options),
                                          forall(member(Arg,Args),
                                                 (atom_codes(Arg,Codes),
                                                  phrase(eapi:qualifiedtarget(Q),Codes),
  						  writeln(Q)
                                                  %knowledgebase:query(Q,R://E),
                                                  %config:proving_target(T),
                                                  %prover:prove(R://E:T,[],Proof,[],Model,[],_Constraints),
                                                  %planner:plan(Proof,[],[],Plan),
                                                  %builder:build(R://E:T,Model,Proof,Plan)
                                          ))),
                                         prolog)
  );true.
