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

% -------------------------------------------------------------------------------
% CASE 1: A request for iuse. We strip use_expand contained in the IUSE parameter
% -------------------------------------------------------------------------------

ebuild:get(iuse_filtered,Repository://Entry,Content) :-
  cache:entry(Repository,Entry,_,_,_,_,Metadata),
  eapi:elem(iuse,Metadata,IUse),!,
  eapi:filter_use_defaults(IUse,IUseFiltered),
  eapi:filter_use_expand(IUseFiltered,Content).


% ---------------------------------------------
% CASE 2: A request for iuse. Iuse not declared
% ---------------------------------------------

ebuild:get(iuse_filtered,Repository://Entry,[]) :-
  cache:entry(Repository,Entry,_,_,_,_,Metadata),
  not(eapi:elem(iuse,Metadata,_)),!.


% ----------------------------------------------------------------------------
% CASE 3: A request for use_expand information contained in the IUSE parameter
% ----------------------------------------------------------------------------

ebuild:get(Key,Repository://Entry,Content) :-
  eapi:use_expand(Key),
  cache:entry(Repository,Entry,_,_,_,_,Metadata),
  eapi:elem(iuse,Metadata,IUse),
  eapi:filter_usedefaults(IUse,IUseFiltered),
  eapi:get_use_expand(Key,IUseFiltered,Content),!.


% ---------------------------------------------------------------
% CASE 4: A request for use_expand information. Iuse not declared
% ---------------------------------------------------------------

ebuild:get(Key,Repository://Entry,[]) :-
  eapi:use_expand(Key),
  cache:entry(Repository,Entry,_,_,_,_,Metadata),
  not(eapi:elem(Key,Metadata,_)),!.


% ----------------------------------------------------------------------
% Case 5: Other metadata. Ebuild declares metadata for the requested key
% ----------------------------------------------------------------------

ebuild:get(Key,Repository://Entry,Content) :-
  cache:entry(Repository,Entry,_,_,_,_,Metadata),
  eapi:elem(Key,Metadata,Content),!.


% -----------------------------------------------------------------------------
% Case 6: Other metadata; Ebuild does not declare metadata for the requested key
% ------------------------------------------------------------------------------

ebuild:get(Key,Repository://Entry,[]) :-
  cache:entry(Repository,Entry,_,_,_,_,Metadata),
  not(eapi:elem(Key,Metadata,_)),!.
