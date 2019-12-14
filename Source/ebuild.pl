/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2019, Pieter Van den Abeele

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

% -------------------------------------------------------------------------------------
% CASE 1: A request for iuse. We strip meta information contained in the IUSE parameter
% -------------------------------------------------------------------------------------

ebuild:get(iuse_filtered,Repository://Entry,Content) :-
  cache:entry(Repository,Entry,_,_,_,_,Metadata),
  eapi:elem(iuse,Metadata,IUse),!,
  eapi:filter_meta_use(IUse,Content).


% ---------------------------------------------
% CASE 2: A request for iuse. Iuse not declared
% ---------------------------------------------

ebuild:get(iuse_filtered,Repository://Entry,[]) :-
  cache:entry(Repository,Entry,_,_,_,_,Metadata),
  not(eapi:elem(iuse,Metadata,_)),!.


% ----------------------------------------------------------------------
% CASE 3: A request for meta information contained in the IUSE parameter
% ----------------------------------------------------------------------

ebuild:get(Key,Repository://Entry,Content) :-
  eapi:meta_use(Key),
  cache:entry(Repository,Entry,_,_,_,_,Metadata),
  eapi:elem(iuse,Metadata,IUse),
  eapi:get_meta_use(Key,IUse,Content),!.


% ---------------------------------------------------------
% CASE 4: A request for meta information. Iuse not declared
% ---------------------------------------------------------

ebuild:get(Key,Repository://Entry,[]) :-
  eapi:meta_use(Key),
  cache:entry(Repository,Entry,_,_,_,_,Metadata),
  not(eapi:elem(Key,Metadata,_)),!.


% ----------------------------------------------------------------------
% Case 5: Other metadata. Ebuild declares metadata for the requested key
% ----------------------------------------------------------------------

ebuild:get(Key,Repository://Entry,Content) :-
  cache:entry(Repository,Entry,_,_,_,_,Metadata),
  eapi:elem(Key,Metadata,Content),!.


% -----------------------------------------------------------------------------
% Case 6: Other metadata; Ebuild deos not declare metadata for the requested key
% ------------------------------------------------------------------------------

ebuild:get(Key,Repository://Entry,[]) :-
  cache:entry(Repository,Entry,_,_,_,_,Metadata),
  not(eapi:elem(Key,Metadata,_)),!.
