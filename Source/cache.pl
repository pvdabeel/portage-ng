/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2021, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> CACHE
Cache is an unguarded, dynamic Prolog context that will hold our database
structure. Repository and Knowledgebase are both interfaces to the high
performance cache context.
*/


% ******************
% CACHE declarations
% ******************

:- dynamic cache:entry/6.
:- dynamic cache:entry_metadata/4.
:- dynamic cache:manifest/6.
