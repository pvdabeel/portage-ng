/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2024, Pieter Van den Abeele

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

%! config:name(?Name)
%
% Declares the name of this program.

config:name('portage-ng-dev').


%! config:hostname(?Hostname)
%
% Declares the hostname this program is running on.

config:hostname(Hostname) :- socket:gethostname(Hostname).


%! config:dry_run_build(?Bool)
%
% Declare config:dry_run_build to avoid actually building software.

config:dry_run_build(true).


%! config:installation_dir(?FullPath)
%
% Declaration of the installation directory of the application source code.
% Needs to be a full path. We serialise some Prolog code to this directory.
% Needs to be passed to prolog as a system flag (See portage-ng.pl)

config:installation_dir(Dir) :-
  file_search_path(portage,Dir),!.


%! config:working_dir(+FullPath)
%
% Declares the current working directory

config:working_dir(Dir) :-
  config:installation_dir(Dir).


%! config:systemconfig(?Filename)
%
% Declares the systemconfig for the host this program is running on

config:systemconfig(Filename) :-
  config:installation_dir(Dir),
  config:hostname(Hostname),
  os:compose_path([Dir,'Source/Config',Hostname],Filename).


%! config:initialize_cacert
%
% Initializes the certificate authority

config:initialize_cacert :-
  config:certificate('cacert.pem',Fullpath),
  create_prolog_flag(system_cacert_filename,Fullpath,[access(read_only)]).


%! config:certificate(+Certificate,-Fullpath)
%
% Returns an absolute path for a given certificate name

config:certificate(Certificate,Fullpath) :-
  config:installation_dir(Dir),
  os:compose_path([Dir,'Source/Certificates',Certificate],Fullpath).


%! config:certificate(+Hostname,+Certificate,-Fullpath)
%
% Return an absolute path for a given hostname certificate name

config:certificate(Hostname,Certificate,FullPath) :-
  atomic_list_concat([Hostname,Certificate],'.',HostCertificate),
  config:certificate(HostCertificate,FullPath).



%! config:password(?Key,?Pass)
%
% Declares the password for the client/server certificates

config:password(server,'demoServer').
config:password(client,'demoClient').


%! config:graph_directory(?Hostname,?FullPath)
%
% This application is capable of writing Graphviz dot files and will turn
% them into interactive scalable vector graphics (svg) to enable you to
% browse through a dependency graph.
%
% We store the generated dot and svg files in the following directory.

config:graph_directory('imac-pro.local',    '/Volumes/Disk 1/Graph/') :- !.
config:graph_directory('mac-pro.local',     '/Users/pvdabeel/Graph/') :- !.
config:graph_directory('macbook-pro.local', '/Users/pvdabeel/Graph/') :- !.
config:graph_directory('vm-linux.local',    '/root/Graph/')           :- !.


%! config:pkg_directory(?Hostname,?FullPath)
%
% Declaration of the pkg db directory on a system. This holds metadata
% for all packages installed on a system

config:pkg_directory('imac-pro.local',      '/Volumes/Disk 1/Repository/pkg/') :- !.
config:pkg_directory('mac-pro.local',       '/Users/pvdabeel/Repository/pkg/') :- !.
config:pkg_directory('macbook-pro.local',   '/Users/pvdabeel/Repository/pkg/') :- !.
config:pkg_directory('vm-linux.local',      '/var/db/pkg/') :- !.


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
% When parsing, proving or planning, use the specified time limit to automatically stop
% computation if it takes too long. In seconds.

config:time_limit(6000).


%! config:time_limit(?Limit)
%
% When executing a plan (i.e. building) use the specified time limit to automatically stop
% the build process if it takes too long. Note this limit applies to an entire step in a plan.
% In seconds.

config:time_limit_build(6000).


%! confg:printing_style(?Setting)
%
% Defines the printing style ('short', 'column' or 'fancy')

config:printing_style('fancy').


%! config:graph_modified_only(?Bool)
%
% Set when you want Graphviz dot file to be created for new ebuilds only

config:graph_modified_only(false).


%! config:proving_target(?Target)
%
% Fact which controls the test target for prover, planner, printer and builder
% Set to either:
%
%  - 'install' : Proof using compile-time dependencies only
%  - 'run': Proof using compile- and run-time dependencies

config:proving_target(run).


%! config:test_style(?Style)
%
% Sets the default test style for executing tests. Can be either:
% - single_verbose
% - parallel_verbose
% - parallel_fast

config:test_style(parallel_verbose).


%! config:failsilenton(?Key)
%
% Fails silently (i.e. without messaging failure on the termimal.
% Key can be:
% - version : fails silently when trying to parse versions from git repositories

config:failsilenton(version).


%! config:server_port(?Number)
%
% Declares the port on which the server needs to be launched.
% Always launches on localhost, using https/ssl.

config:server_port(4000).


%! config:server_host(?Url)
%
% Declares the server url, including protocol (https) and port
% the client needs to connect on.

config:server_host('imac-pro.local').


%! config:server_name(Name)
%
% Declares the server knowledge base name
% the client needs to connect on.

config:server_name('kb').
