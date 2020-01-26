/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2020, Pieter Van den Abeele

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
  V = '2020.01.26'.


%! interface:status(?Status)
%
% Retrieve the current status (alpha,beta,testing,development,release)

interface:status(S) :-
  S = 'development'.

%! interface:spec(?Specification)
%
% Retrieve the interface specification

interface:spec(S) :-
  S = [
       [opt(verbose), type(boolean), default(false), shortflags(['v']), longflags(['verbose']),  help('Turn on verbose mode')],                       % OPTION
       [opt(pretend), type(boolean), default(false), shortflags(['p']), longflags(['pretend']),  help('Turn on pretend mode')],                       % OPTION
       [opt(merge),   type(boolean), default(true),  shortflags(['m']), longflags(['merge']),    help('Merge target package')],                       % OPTION
       [opt(update),  type(boolean), default(false), shortflags(['u']), longflags(['update']),   help('Update target package')],                      % OPTION
       [opt(deep),    type(boolean), default(false), shortflags(['d']), longflags(['deep']),     help('Also consider dependencies')],                 % OPTION
       [opt(resume),  type(boolean), default(false), shortflags(['r']), longflags(['resume']),   help('Resume previous command')],                    % OPTION
       [opt(newuse),  type(boolean), default(false), shortflags(['n']), longflags(['newuse']),   help('Take into account new use flags')],            % OPTION
       [opt(sync),    type(boolean), default(false),                    longflags(['sync']),     help('Sync repository')],                            % ACTION
       [opt(clear),   type(boolean), default(false),                    longflags(['clear']),    help('Clear knowledge base')],                       % ACTION
       [opt(graph),   type(boolean), default(false),                    longflags(['graph']),    help('Create graph')],                               % ACTION
       [opt(depclean),type(boolean), default(false), shortflags(['c']), longflags(['depclean']), help('Clean dependencies')],                         % ACTION
       [opt(info),    type(boolean), default(false),                    longflags(['info']),     help('Show package version')],                       % ACTION
       [opt(search),  type(boolean), default(false), shortflags(['s']), longflags(['search']),   help('Search for a target')],                        % ACTION
       [opt(unmerge), type(boolean), default(false), shortflags(['C']), longflags(['unmerge']),  help('Unmerge target')],                             % ACTION
       [opt(shell),   type(boolean), default(false),                    longflags(['shell']),    help('Go to shell')],                                % ACTION
       [opt(version), type(boolean), default(false), shortflags(['V']), longflags(['version']),  help('Show version')]                                % ACTION
      ].


%! interface:argv(-Options,-Args)
%
% Retrieve the arguments passed on the command line.

interface:argv(Options,Args) :-
  interface:spec(S),
  opt_arguments(S,Options,Args).


%! interface:process_requests
%
% Processes the arguments passed on the command line.
% Maps the options declared in interface:specs(S) onto actions defined as
% a set of predicates to be called.

interface:process_requests :-
  interface:version(Version),
  interface:status(Status),
  catch(interface:argv(Options,Args),_,true),
  ( member(version(true),Options)  -> (message:inform(['portage-ng ',Status,' version - ',Version]),   halt) ;
    member(info(true),Options)     -> (message:inform(['portage-ng ',Status,' version - ',Version]),   halt) ;
    member(clear(true),Options)    -> (kb:clear,                                                       halt) ;
    member(sync(true),Options)     -> (kb:sync, kb:save,                                               halt) ;
    member(graph(true),Options)    -> (grapher:test(portage),                                          halt) ;
    member(unmerge(true),Options)  -> (message:warning('unmerge action to be implemented'),            halt) ;
    member(depclean(true),Options) -> (message:warning('depclean action to be implemented'),           halt) ;
    member(search(true),Options)   -> ((Args == []) -> true ;
                                       (phrase(eapi:query(Q),Args),
                                        forall(knowledgebase:query(Q,R://E),writeln(R://E))),
                                        halt) ;
    member(sync(true),Options)     -> (kb:sync, kb:save,                                               halt) ;
    member(shell(true),Options)    -> (message:inform(['portage-ng shell - ',Version]),                prolog);
    member(merge(true),Options)    -> ((Args == []) -> true ;
                                       (forall(member(Arg,Args),
                                        (atom_codes(Arg,Codes),
                                         phrase(eapi:qualifiedtarget(Q),Codes),
                                         knowledgebase:query(Q,R://E),
                                         config:proving_target(T),
                                         prover:prove(R://E:T,[],Proof,[],Model,[],_Constraints),
                                         planner:plan(Proof,[],[],Plan),
                                         printer:print(R://E:T,Model,Proof,Plan)
                                         ))),
                                        halt)
  );true.
