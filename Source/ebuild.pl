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

%! ebuild:get(+Key, +Repository://+Entry, -Content)
%
% Retrieves metadata from ebuild

% -------------------------------------------------------------------------------
% CASE 1: A request for iuse. We strip use_expand contained in the IUSE parameter
% -------------------------------------------------------------------------------

%ebuild:get(iuse_filtered,Repository://Entry,Content) :-
%  findall(Use,cache:entry_metadata(Repository,Entry,iuse,Use),IUse),
%  eapi:filter_use_defaults(IUse,IUseFiltered),
%  eapi:filter_use_expand(IUseFiltered,Content).


% ---------------------------------------------
% CASE 2: A request for iuse. Iuse not declared
% ---------------------------------------------

%ebuild:get(iuse_filtered,Repository://Entry,[]) :-
%  not(cache:entry_metadata(Repository,Entry,iuse,_)),!.


% ----------------------------------------------------------------------------
% CASE 3: A request for use_expand information contained in the IUSE parameter
% ----------------------------------------------------------------------------

%ebuild:get(Key,Repository://Entry,Content) :-
%  eapi:use_expand(Key),
%  findall(Use,cache:entry_metadata(Repository,Entry,iuse,Use),IUse),
%  eapi:filter_usedefaults(IUse,IUseFiltered),
%  eapi:get_use_expand(Key,IUseFiltered,Content),!.


% ---------------------------------------------------------------
% CASE 4: A request for use_expand information. Iuse not declared
% ---------------------------------------------------------------

%ebuild:get(Key,Repository://Entry,[]) :-
%  eapi:use_expand(Key),
%  not(cache:entry_metadata(Repository,Entry,Key,_)),!.


% ----------------------------------------------------------------------
% Case 5: Other metadata. Ebuild declares metadata for the requested key
% ----------------------------------------------------------------------

ebuild:get(Key,Repository://Entry,Content) :-
  findall(Value,cache:entry_metadata(Repository,Entry,Key,Value),Content).


% -----------------------------------------------------------------------------
% Case 6: Other metadata; Ebuild does not declare metadata for the requested key
% ------------------------------------------------------------------------------

%ebuild:get(Key,Repository://Entry,[]) :-
%  not(cache:entry_metadata(Repository,Entry,Key,_)),!.


%! ebuild:download(+Repository://+Entry,-B,-S)
%
% Retrieves download filename and corresponding filesize for a given Entry

ebuild:download(Repository://Entry,B,S) :-
  ebuild:get(src_uri,Repository://Entry,U),
  Repository:ebuild(Entry,Category,Name,_),
  Repository:manifest(_,Category,Name,Manifest),
  member(manifest(dist,B,Ss,_),Manifest),
  member(uri(Bs),U),
  atom_string(B,Bs),
  number_string(S,Ss).

ebuild:download(Repository://Entry,B,S) :-
  ebuild:get(src_uri,Repository://Entry,U),
  Repository:ebuild(Entry,Category,Name,_),
  Repository:manifest(_,Category,Name,Manifest),
  member(manifest(dist,B,Ss,_),Manifest),
  member(uri(_,_,Bs),U),
  atom_string(B,Bs),
  number_string(S,Ss).

ebuild:download(Repository://Entry,B,S) :-
  ebuild:get(src_uri,Repository://Entry,U),
  Repository:ebuild(Entry,Category,Name,_),
  Repository:manifest(_,Category,Name,Manifest),
  member(manifest(dist,B,Ss,_),Manifest),
  member(uri(_,P,_),U),
  file_base_name(P,Bs),
  atom_string(Bs,B),
  number_string(S,Ss).


%! ebuild:download_size(+Repository://+Entry,-T)
%
% Retrieve total download size for all files corresponding to a given Entry

ebuild:download_size(Repository://Entry,T) :-
  aggregate_all(sum(S),ebuild:download(Repository://Entry,_,S),T),!.

ebuild:download_size(_://_,0) :- !.


ebuild:iuse(Repository://Entry,Use) :-
  cache:entry_metadata(Repository,Entry,iuse,Use).

ebuild:iuse_filtered(Repository://Entry,Use) :-
  ebuild:get(iuse_filtered,Repository://Entry,Iuse),
  member(Use,Iuse).


ebuild:categorize_use(plus(Use),'pos:ebuild') :-
  !,
  not(preference:positive_use(Use)),
  not(preference:negative_use(Use)).

ebuild:categorize_use(minus(Use),'neg:ebuild') :-
  !,
  not(preference:positive_use(Use)),
  not(preference:negative_use(Use)).

ebuild:categorize_use(Use,'pos:preference') :-
  preference:positive_use(Use),!.

ebuild:categorize_use(Use,'neg:preference') :-
  preference:negative_use(Use),!.

ebuild:categorize_use(_,'neg:default') :-
  %not(preference:positive_use(Use)),
  %not(preference:negative_use(Use)),
  %not(printer:unify(plus(_),Use)),
  %not(printer:unify(minus(_),Use)).
  !.


%! ebuild:is_virtual(+Repository://+Entry)
%
% True if an entry is a virtual

ebuild:is_virtual(Repository://Entry) :-
  cache:entry(Repository,Entry,_,'virtual',_,_),!.


%! ebuild:is_live(+Repository://+Entry)
%
% True if an entry is live

ebuild:is_live(Repository://Entry) :-
  cache:entry(Repository,Entry,_,_,_,'9999'),!.

ebuild:is_live(Repository://Entry) :-
  cache:entry_metadata(Repository,Entry,'properties','live'),!.


%! ebuild:is_interactive(+Repository://+Entry)
%
% True if an entry is interactive

ebuild:is_interactive(Repository://Entry) :-
  cache:entry_metadata(Repository,Entry,'properties','interactive'),!.
