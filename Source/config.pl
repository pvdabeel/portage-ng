/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2019, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> CONFIG
The config context contains general facts and rules related to the prolog
configuration. The parameters described typically do not change at runtime.
*/

:- module(config, []).

% *******************
% CONFIG declarations
% *******************

%! config:dry_run_build
%
% Declare config:dry_run_build to avoid actually building software.

config:dry_run_build(true).


%! config:installation_dir(?FullPath)
%
% Declaration of the installation directory of the application source code.
% Needs to be a full path. We serialise some Prolog code to this directory.
% May change in a a later release.

config:installation_dir('/Users/pvdabeel/Desktop/Prolog').


%! config:graph_directory(?FullPath)
%
% This application is capable of writing Graphviz dot files and will turn
% them into interactive scalable vector graphics (svg) to enable you to
% browse through a dependency graph.
%
% We store the generated dot and svg files in the following directory.

config:graph_directory('/Users/pvdabeel/Graph/').


%! config:number_of_cpus(?Count)
%
% This application parallellizes parsing, proving, planning and building.
% SWI prolog is automatically able to determine the maximum cpu count, but
% sometimes we may want to change this to a value of our choice.

config:number_of_cpus(C) :- current_prolog_flag(cpu_count,C).


%! config:number_of_cpus(?Count)
%
% Different verbosity levels may be configured for printing runtime information

config:verbosity(debug).


%! config:time_limit(?Limit)
%
% When proving use the specified time limit to automatically stop proofs when
% they take too long. In seconds.

config:time_limit(10).


%! config:graph_modified_only
%
% Set when you want Graphviz dot file to be created for new ebuilds only

config:graph_modified_only(true).


%! config:proving_target
%
% Fact which controls the test target for prover, planner, printer and builder
% Set to either:
%
%  - 'install' : Proof using compile-time dependencies only
%  - 'run': Proof using compile- and run-time dependencies

config:proving_target(run).
