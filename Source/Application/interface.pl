/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> INTERFACE
The interface interprets command line arguments passed to portage-ng and
dispatches them to the appropriate actions (merge, sync, graph, search, etc.).
It maps CLI flags declared in interface:spec/1 onto predicates that implement
each action.

The implementation is split across the Interface/ subdirectory and assembled
here via include/1; every fragment contributes clauses to this module:

  - Interface/target.pl    : target validation and resolution
  - Interface/version.pl   : version strings and system information
  - Interface/spec.pl      : the list of command-line flags
  - Interface/argv.pl      : argv parsing, parse errors, flag suggestions
  - Interface/flags.pl     : flag processing, derived accessors, tty and cwd init
  - Interface/verify.pl    : mode flag verification and early-exit handlers
  - Interface/requests.pl  : main request dispatch
  - Interface/exitcodes.pl : exit-code lookup table and CI exit-code logic
*/

:- module(interface, []).

% =============================================================================
%  INTERFACE declarations
% =============================================================================

:- include('Interface/target.pl').
:- include('Interface/version.pl').
:- include('Interface/spec.pl').
:- include('Interface/argv.pl').
:- include('Interface/flags.pl').
:- include('Interface/verify.pl').
:- include('Interface/requests.pl').
:- include('Interface/exitcodes.pl').
