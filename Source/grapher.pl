/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> GRAPHER
Generates interactive self-contained HTML visualizations for Gentoo ebuilds.

Given an ebuild (identified by its cache entry), the grapher produces HTML
graphs.  For a given ebuild, the following output is produced:

 - detail:     Interactive tree/graph showing the ebuild dependency expressions
               with candidate resolution.  Delegates to the detail submodule.

 - deptree:    Interactive dependency graph covering all six dependency types
               (bdepend, cdepend, depend, idepend, rdepend, pdepend) with
               collapsible nodes and pan/zoom.  Delegates to the deptree
               submodule.

 - gantt:      Interactive Gantt chart showing the execution plan with step-based
               timeline, per-package detail rows (USE flags, downloads),
               dependency arrows, and phase filters.  Delegates to the gantt
               submodule.

 - merge:      Styled HTML page showing captured merge plan CLI output.  Delegates
               to the terminal submodule.

 - fetchonly:  Styled HTML page showing captured fetchonly plan CLI output.  Delegates
               to the terminal submodule.

 - info:       Styled HTML page showing captured package info CLI output.  Delegates
               to the terminal submodule.

 - emerge:     Styled HTML page embedding the traditional emerge output file.
               Delegates to the terminal submodule.

Legacy DOT graph generation is available via dot:graph/2 in Source/Grapher/dot.pl
and can be invoked manually through grapher:graph_dot/2.
*/

:- module(grapher, []).

% =============================================================================
%  GRAPHER declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Graph types (HTML dispatch)
% -----------------------------------------------------------------------------

%! grapher:graph(+Type,+Repository://Id)
%
% For a given ebuild, identified by an Id, create an HTML graph.

grapher:graph(detail,Repository://Id) :-
  !,
  detail:graph(Repository://Id).

grapher:graph(merge,Repository://Id) :-
  !,
  terminal:graph(merge,Repository://Id).

grapher:graph(fetchonly,Repository://Id) :-
  !,
  terminal:graph(fetchonly,Repository://Id).

grapher:graph(info,Repository://Id) :-
  !,
  terminal:graph(info,Repository://Id).

grapher:graph(emerge,Repository://Id) :-
  !,
  terminal:graph(emerge,Repository://Id).

grapher:graph(gantt,Repository://Id) :-
  !,
  gantt:graph(Repository://Id).

grapher:graph(deptree,Repository://Id) :-
  !,
  deptree:graph(Repository://Id).


% -----------------------------------------------------------------------------
%  Legacy DOT pass-through
% -----------------------------------------------------------------------------

%! grapher:graph_dot(+Type, +Repository://Id)
%
% Pass-through to the legacy DOT graph generator (dot:graph/2).
% Available for manual use; not part of the default --graph pipeline.

grapher:graph_dot(Type, Repository://Id) :-
  dot:graph(Type, Repository://Id).


% -----------------------------------------------------------------------------
%  Graph file output
% -----------------------------------------------------------------------------

%! grapher:write_graph_file(+Directory,+Repository://Entry)
%
% Create HTML graph file(s) for an entry in a repository.
% Assumes directory exists. (See repository:prepare_directory)

grapher:write_graph_file(D,Repository://Entry) :-
  config:graph_html_type(Types),
  (forall(member(Type,Types),
      (  atomic_list_concat([D,'/',Entry,'-',Type,'.html'],F),
       tell(F),
       (grapher:graph(Type,Repository://Entry)
        -> told
        ;  (told,message:warning([Repository://Entry,' ',Type])))))).


%! grapher:write_graph_files(+Directory,+Repository)
%
% Create HTML graph file(s) for all entries in a repository.
% Assumes directory exists. (See repository:prepare_directory)

grapher:write_graph_files(Directory,Repository) :-
  tester:test(parallel_verbose,
              'Writing HTML graphs',
              Repository://PackageAtom,
              (Repository:package(Category,Name),
               atomic_list_concat([Category,'/',Name],PackageAtom),
               (config:graph_modified_only(true)
                -> once((Repository:ebuild(Entry,Category,Name,_),
                         Repository:entry(Entry,Time),
                         Repository:get_ebuild_file(Entry,Ebuild),
                         system:exists_file(Ebuild),
                         system:time_file(Ebuild,Modified),
                         Modified > Time))
                ;  true)),
              (forall(Repository:ebuild(Entry,Category,Name,_),
                      grapher:write_graph_file(Directory,Repository://Entry)))).


% -----------------------------------------------------------------------------
%  Testers
% -----------------------------------------------------------------------------

%! grapher:test(+Repository)
%
% Outputs HTML for every entry in a given repository, reports using the
% default reporting style.

grapher:test(Repository) :-
  config:test_style(Style),
  grapher:test(Repository,Style).


%! grapher:test(+Repository,+Style)
%
% Outputs HTML for every entry in a given repository, reports using a
% given reporting style.

grapher:test(Repository,Style) :-
  config:graph_html_type(Types),
  tester:test(Style,
              'Graphing',
              Repository://Entry,
              Repository:entry(Entry),
              forall(member(I,Types),
               with_output_to(string(_),grapher:graph(I,Repository://Entry)))).


%! grapher:test_latest(+Repository)
%
% Same as grapher:test(+Repository), but only tests highest version of every
% package.

grapher:test_latest(Repository) :-
  !,
  grapher:test_latest(Repository,parallel_verbose).

grapher:test_latest(Repository,Style) :-
  config:graph_html_type(Types),
  tester:test(Style,
              'Graphing',
              Repository://Entry,
              (Repository:package(C,N),once(Repository:ebuild(Entry,C,N,_))),
              forall(member(I,Types),
               with_output_to(string(_),grapher:graph(I,Repository://Entry)))).
