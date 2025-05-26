/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2025, Pieter Van den Abeele

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
  os:compose_path([Dir,'Source/Config','default'],Default),
  os:compose_path([Dir,'Source/Config',Hostname],Configuration),
  system:file_name_extension(Configuration,'pl',ConfigFile),
  ( system:exists_file(ConfigFile)
    -> Filename = ConfigFile
    ;  Filename = Default ).


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



%! config:certificate_password(?Key,?Pass)
%
% Declares the password for the SSL client/server certificates

config:certificate_password(server,'demoServer').
config:certificate_password(client,'demoClient').


%! config:digest_passwordfile(?File)
%
% Declares the password file for http(s) digest user authentication

config:digest_passwordfile(Filename) :-
  config:installation_dir(Dir),
  os:compose_path([Dir,'Source/Certificates/passwordfile'],Filename).


%! config:digestpassword(?User,?Pass)
%
% Declares the password for digest user authentication

config:digest_password('portage-ng','portage-ng').


%! config:realm(?Pass)
%
% Declares the realm for digest user authentication

config:digest_realm('portage-ng').


%! config:graph_directory(?Hostname,?FullPath)
%
% This application is capable of writing Graphviz dot files and will turn
% them into interactive scalable vector graphics (svg) to enable you to
% browse through a dependency graph.
%
% We store the generated dot and svg files in the following directory.

config:graph_directory('imac-pro.local',    '/Volumes/Disk 1/Graph/') :- !.
config:graph_directory('mac-pro.local',     '/Volumes/Storage/Graph/') :- !.
config:graph_directory('macbook-pro.local', '/Users/pvdabeel/Graph/') :- !.
config:graph_directory('vm-linux.local',    '/root/Graph/')           :- !.


%! config:pkg_directory(?Hostname,?FullPath)
%
% Declaration of the pkg db directory on a system. This holds metadata
% for all packages installed on a system

config:pkg_directory('imac-pro.local',      '/Volumes/Disk 1/Repository/pkg/') :- !.
config:pkg_directory('mac-pro.local',       '/Volumes/Storage/Repository/pkg/') :- !.
config:pkg_directory('macbook-pro.local',   '/Users/pvdabeel/Repository/pkg/') :- !.
config:pkg_directory('vm-linux.local',      '/var/db/pkg/') :- !.


%! config:workd_file(Path)
%
% Declaration of the world file path

config:world_file(Filename) :-
  config:installation_dir(Dir),
  config:hostname(Hostname),
  os:compose_path([Dir,'Source/Sets/world',Hostname],Filename).


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
% Retrieves the printing style ('short', 'column' or 'fancy')
%
% 1. Running as a server, use client style

config:printing_style(Style) :-
  pengine_self(M),
  !,
  M:printing_style(Style).


% 2. Not running as a server, use interface style when specified, otherwise default

config:printing_style(Style) :-
  %\+pengine_self(M),
  config:interface_printing_style(Style),!.

config:printing_style(Style) :-
  %\+pengine_self(M),
  \+(config:interface_printing_style(_)),
  config:default_printing_style(Style).


% Interface can dynamically set the printing style

:- dynamic config:interface_printing_style/1.

% The default printing style

config:default_printing_style('fancy').


%! config:print_expand_use(?Bool)
%
% Defines whether we print information that is normally not printed

config:print_expand_use(false).


%! config:printable_metadata(?List)
%
% Defines which elements in which order to print out when printing ebuild information
% Use 'blank' to put blank lines in output. Use 'hl' to output a horizontal line.

config:printable_metadata([blank,hl,description,homepage,license,eapi,slot,hl,blank,iuse,required_use,keywords,properties,eclasses,defined_phases,installed,hl,blank,src_uri,hl,bdepend,blank,depend,blank,idepend,blank,rdepend,blank,pdepend,blank]).


%! config:graph_modified_only(?Bool)
%
% Set when you want Graphviz dot file to be created for new ebuilds only

config:graph_modified_only(true).


%! config:graph_dependency_type(?Bool)
%
% Defines the dependency types for which you want a full graph

config:graph_dependency_type([detail,bdepend,cdepend,depend,idepend,rdepend,pdepend]).


%! config:proving_target(?Target)
%
% Fact which controls the test target for prover, planner, printer and builder
% Set to either:
%
%  - 'install' : Proof using compile-time dependencies only
%  - 'run': Proof using compile- and run-time dependencies

config:proving_target(run).


%! config:avoid_reinstall(?Bool)
%
% If a package is already installed, when this config item is set to true,
% we will verify installation, rather than reinstall the package.

config:avoid_reinstall(true).



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


%! config:chunck(?Chunksize)
%
% When set to false, when working in client-server mode, one
% RPC call is performed per solution. When generating large
% number of solutions, such as backtracking over a goal, it
% is best to transfer multiple solutions in one chunck over one
% rpc call. Setting this to a higher value speeds up searching
% in client-server mode. Shouldn't be higher than the total number
% of entries in your repositories.

config:chunk(50000).

%! config:server_host(?Url)
%
% Declares the server url, including protocol (https) and port
% the client needs to connect on.

config:server_host('mac-pro.local').


%! config:trust_metadata(?Bool)
%
% When set to false, we regenerate locally the cache entries
% after syncing with the remote repository. This is expensive,
% so by default we trust and regenerate only for locally changed
% ebuilds or ebuilds with missing cache.

config:trust_metadata(true).


%! config:write_metadata(?Bool)
%
% When ebuilds are changed locally or new ebuilds are created locally
% this will be detected during syncing, and portage will parse the
% ebuild metadata after running it through ebuild.sh.
%
% Prolog facts are updated with the updated metadata.
% If this variable is set to true, we will also create an on-disk
% cache entry for these ebuilds. This cache entry may be overwritten
% by a sync later on by remotely generated cache.

config:write_metadata(false).
