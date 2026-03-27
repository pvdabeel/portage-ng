/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> ACTION
Action handlers for CLI commands dispatched by the interface module.
Each action file is textually included into this module via :- include/1.
*/

:- module(action, []).

% =============================================================================
%  ACTION declarations
% =============================================================================

:- discontiguous process_action/3.

:- include('Action/info.pl').
:- include('Action/search.pl').
:- include('Action/upgrade.pl').
:- include('Action/merge.pl').

:- include('Action/graph.pl').
:- include('Action/sync.pl').
:- include('Action/bugs.pl').
:- include('Action/build.pl').
:- include('Action/explain.pl').
:- include('Action/variants.pl').
:- include('Action/upstream.pl').
:- include('Action/snapshot.pl').
:- include('Action/deselect.pl').
:- include('Action/installed.pl').
:- include('Action/estimate.pl').