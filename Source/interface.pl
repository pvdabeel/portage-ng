% **********************
% INTERFACE declarations
% **********************


:- ensure_loaded(library('optparse')).

interface:version(V) :-
  V = '20190311'.


interface:spec(S) :- 
  S = [
        [opt(verbose), type(boolean), default(false), shortflags(['v']), longflags(['verbose'])],  % OPTION
        [opt(pretend), type(boolean), default(false), shortflags(['p']), longflags(['pretend'])],  % OPTION
        [opt(update),  type(boolean), default(false), shortflags(['u']), longflags(['update'])],   % OPTION
        [opt(deep),    type(boolean), default(false), shortflags(['d']), longflags(['deep'])],     % OPTION
        [opt(resume),  type(boolean), default(false), shortflags(['r']), longflags(['resume'])],   % OPTION
        [opt(newuse),  type(boolean), default(false), shortflags(['n']), longflags(['newuse'])],   % OPTION
        [opt(sync),    type(boolean), default(false),                    longflags(['sync'])],     % ACTION
        [opt(clear),   type(boolean), default(false),                    longflags(['clear'])],    % ACTION
        [opt(graph),   type(boolean), default(false),                    longflags(['graph'])],    % ACTION
        [opt(depclean),type(boolean), default(false), shortflags(['c']), longflags(['depclean'])], % ACTION
        [opt(info),    type(boolean), default(false),                    longflags(['info'])],     % ACTION
        [opt(search),  type(boolean), default(false), shortflags(['s']), longflags(['search'])],   % ACTION
        [opt(unmerge), type(boolean), default(false), shortflags(['C']), longflags(['unmerge'])],  % ACTION
        [opt(shell),   type(boolean), default(false),                    longflags(['shell'])],    % ACTION
        [opt(version), type(boolean), default(false), shortflags(['V']), longflags(['version'])]   % ACTION
      ].


interface:argv(Options,Args) :-
  interface:spec(S),
  opt_arguments(S,Options,Args).

interface:process_requests :-
  interface:version(Version),
  interface:argv(Options,Args),
  ( member(version(true),Options)  -> (message:inform(['portage-ng development version - ',Version]),  halt) ; 
    member(info(true),Options)     -> (message:inform(['portage-ng development version - ',Version]),  halt) ; 
    member(clear(true),Options)    -> (kb:clear,                                                       halt) ; 
    member(sync(true),Options)     -> (kb:sync, kb:save,                                               halt) ; 
    member(graph(true),Options)    -> (grapher:test(portage),                                          halt) ; 
    member(unmerge(true),Options)  -> (message:warning('unmerge action to be implemented'),            halt) ;
    member(depclean(true),Options) -> (message:warning('depclean action to be implemented'),           halt) ;
    member(search(true),Options)   -> (message:warning('search action to be implemented'),             halt) ; 
    member(sync,Args)              -> (kb:sync, kb:save,                                               halt) ;
    member(_,Args)                 -> (message:inform(['portage-ng shell - ',Version]))
  );true.
