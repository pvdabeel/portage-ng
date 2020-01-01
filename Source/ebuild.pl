/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2020, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> EBUILD
The contents of this file needs some rework. Probably to be moved into repository.
*/

:- module(ebuild, []).

% *******************
% EBUILD declarations
% *******************

%! ebuild:download_size(+Repository://+Entry,-T)
%
% Retrieve total download size for all files corresponding to a given Entry

ebuild:download_size(Repository://Entry,T) :-
  aggregate_all(sum(S),knowledgebase:query([manifest(_,_,S)],Repository://Entry),T),!.

ebuild:download_size(_://_,0) :- !.


%! ebuild:categorize_use(Use,Type)
%
% Retrieve use flags from ebuild


ebuild:categorize_use(plus(Use),'pos:preference') :-
  preference:positive_use(Use),!.

ebuild:categorize_use(plus(Use),'neg:preference') :-
  preference:negative_use(Use),!.

ebuild:categorize_use(plus(Use),'pos:ebuild') :-
  not(preference:positive_use(Use)),
  not(preference:negative_use(Use)),
  !.

ebuild:categorize_use(minus(Use),'pos:preference') :-
  preference:positive_use(Use),!.

ebuild:categorize_use(minus(Use),'neg:preference') :-
  preference:negative_use(Use),!.

ebuild:categorize_use(minus(Use),'neg:ebuild') :-
  not(preference:positive_use(Use)),
  not(preference:negative_use(Use)),
  !.

ebuild:categorize_use(Use,'pos:preference') :-
  preference:positive_use(Use),!.

ebuild:categorize_use(Use,'neg:preference') :-
  preference:negative_use(Use),!.

ebuild:categorize_use(Use,'neg:default') :-
  not(preference:positive_use(Use)),
  not(preference:negative_use(Use)),
  not(printer:unify(plus(_),Use)),
  not(printer:unify(minus(_),Use)),!.


%! ebuild:is_virtual(+Repository://+Entry)
%
% True if an entry is a virtual

ebuild:is_virtual(Repository://Entry) :-
  knowledgebase:query([category('virtual')],Repository://Entry).


%! ebuild:is_live(+Repository://+Entry)
%
% True if an entry is live

ebuild:is_live(Repository://Entry) :-
  knowledgebase:query([properties('live')],Repository://Entry).


%! ebuild:is_interactive(+Repository://+Entry)
%
% True if an entry is interactive

ebuild:is_interactive(Repository://Entry) :-
  knowledgebase:query([properties('interactive')],Repository://Entry).
