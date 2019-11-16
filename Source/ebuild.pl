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


% Case 1: The ebuild has Metadata for the requested key

ebuild:get(Key,Context://Entry,Content) :-
  cache:entry(Context,Entry,_,_,_,_,Metadata),
  eapi:elem(Key,Metadata,Content).


% Case 2: The ebuild does not have Metadata for the requested key

ebuild:get(Key,Context://Entry,[]) :-
  cache:entry(Context,Entry,_,_,_,_,Metadata),
  not(eapi:elem(Key,Metadata,_)).
