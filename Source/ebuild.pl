/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> EBUILD
This file currently contains some syntactic sugar for common knowledgebase
queries.
*/

:- module(ebuild, []).

% =============================================================================
%  EBUILD declarations
% =============================================================================

%! ebuild:invoke(cache,+Location,+Entry,-Stream)
%
% Sources the ebuild, its eclasses in a bash session and exports the
% variables relevant to create a repository cache entry

ebuild:invoke(cache,Location,Entry,Stream) :-
  split_string(Entry,"/","/",[Category,Package]),
  eapi:packageversion(Package,Name,version(_,_,_,_,_,Rev,Version)),
  ( Rev =:= 0 -> Revision = '' ; format(atom(Revision), '-r~d', [Rev]) ),
  string_concat(UpstreamVersion,Revision,Version),
  string_concat(UpstreamPackage,Revision,Package),
  atomic_list_concat([Location,'/',Category,"/",Name,"/",Package,'.ebuild'],Ebuild),
  script:exec(cache,[eapi,depend,Ebuild,Location],
    [environment([ 'P'=UpstreamPackage,
                   'PV'=UpstreamVersion,
                   'PN'=Name,
                   'PR'=Revision,
                   'PVR'=Version,
                   'PF'=Package,
                   'CATEGORY'=Category ])],Stream),!.


%! ebuild:download_size(+Repository://+Entry,-T)
%
% Retrieve total download size for all files corresponding to a given Entry

ebuild:download_size(Scope,Repository://Entry,T) :-
  aggregate_all(sum(S),F,kb:query(manifest(Scope,_,F,S),Repository://Entry),T),!.

ebuild:download_size(_,_://_,0) :- !.


%! ebuild:is_virtual(+Repository://+Entry)
%
% True if an entry is a virtual

ebuild:is_virtual(Repository://Entry) :-
  kb:query(category('virtual'),Repository://Entry).


%! ebuild:is_live(+Repository://+Entry)
%
% True if an entry is live

ebuild:is_live(Repository://Entry) :-
  kb:query(properties(live),Repository://Entry).


%! ebuild:is_interactive(+Repository://+Entry)
%
% True if an entry is interactive

ebuild:is_interactive(Repository://Entry) :-
  kb:query(properties(interactive),Repository://Entry).
