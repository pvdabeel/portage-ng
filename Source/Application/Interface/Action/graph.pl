/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

% -----------------------------------------------------------------------------
%  Action: GRAPH (optional mode argument)
% -----------------------------------------------------------------------------

%! action:process_graph(+Args) is det.
%
% Dispatches --graph with optional positional arguments. The repository
% graphed is always config:graph_repository/1 (via kb:graph / kb:graph_emerge):
%   --graph                 uses config:graph_modified_only/1
%   --graph modified        overrides to modified-only for this run
%   --graph full            overrides to graph everything for this run
%   --graph emerge          generates only .emerge files (calls emerge-vp)
%   --graph emerge modified .emerge files for modified ebuilds only
%   --graph emerge full     force-regenerate all .emerge files
%   --graph pmerge          generates only .pmerge files (pmerge --pretend --verbose)
%   --graph pmerge modified .pmerge files for modified ebuilds only
%   --graph pmerge full     force-regenerate all .pmerge files

action:process_graph([]) :-
  kb:graph,
  !.

action:process_graph([modified]) :-
  setup_call_cleanup(
    asserta(config:interface_graph_modified_only(true)),
    kb:graph,
    retractall(config:interface_graph_modified_only(_))
  ),
  !.

action:process_graph([full]) :-
  setup_call_cleanup(
    asserta(config:interface_graph_modified_only(false)),
    kb:graph,
    retractall(config:interface_graph_modified_only(_))
  ),
  !.

action:process_graph([emerge]) :-
  kb:graph_emerge,
  !.

action:process_graph([emerge, modified]) :-
  setup_call_cleanup(
    asserta(config:interface_graph_modified_only(true)),
    kb:graph_emerge,
    retractall(config:interface_graph_modified_only(_))
  ),
  !.

action:process_graph([emerge, full]) :-
  setup_call_cleanup(
    ( asserta(config:interface_graph_modified_only(false)),
      asserta(config:force_emerge_regen(true)) ),
    kb:graph_emerge,
    ( retractall(config:interface_graph_modified_only(_)),
      retractall(config:force_emerge_regen(_)) )
  ),
  !.

action:process_graph([pmerge]) :-
  kb:graph_pmerge,
  !.

action:process_graph([pmerge, modified]) :-
  setup_call_cleanup(
    asserta(config:interface_graph_modified_only(true)),
    kb:graph_pmerge,
    retractall(config:interface_graph_modified_only(_))
  ),
  !.

action:process_graph([pmerge, full]) :-
  setup_call_cleanup(
    ( asserta(config:interface_graph_modified_only(false)),
      asserta(config:force_pmerge_regen(true)) ),
    kb:graph_pmerge,
    ( retractall(config:interface_graph_modified_only(_)),
      retractall(config:force_pmerge_regen(_)) )
  ),
  !.

action:process_graph(Args) :-
  message:warning(['--graph: ignoring unexpected args: ', Args]),
  kb:graph.
