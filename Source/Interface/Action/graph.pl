% -----------------------------------------------------------------------------
%  Action: GRAPH (optional mode argument)
% -----------------------------------------------------------------------------

%! action:process_graph(+Args) is det.
%
% Dispatches --graph with optional positional arguments:
%   --graph                 uses config:graph_modified_only/1
%   --graph modified        overrides to modified-only for this run
%   --graph full            overrides to graph everything for this run
%   --graph build           graph + builder test (download + safe phases)
%   --graph build modified  graph modified + builder test
%   --graph build full      graph full + builder test

process_graph([]) :-
  kb:graph,
  !.
process_graph([modified]) :-
  setup_call_cleanup(
    asserta(config:interface_graph_modified_only(true)),
    kb:graph,
    retractall(config:interface_graph_modified_only(_))
  ),
  !.
process_graph([full]) :-
  setup_call_cleanup(
    asserta(config:interface_graph_modified_only(false)),
    kb:graph,
    retractall(config:interface_graph_modified_only(_))
  ),
  !.
process_graph([build]) :-
  kb:graph,
  builder:test_stats(portage),
  !.
process_graph([build, modified]) :-
  setup_call_cleanup(
    asserta(config:interface_graph_modified_only(true)),
    kb:graph,
    retractall(config:interface_graph_modified_only(_))
  ),
  builder:test_stats(portage),
  !.
process_graph([build, full]) :-
  setup_call_cleanup(
    asserta(config:interface_graph_modified_only(false)),
    kb:graph,
    retractall(config:interface_graph_modified_only(_))
  ),
  builder:test_stats(portage),
  !.
process_graph(Args) :-
  message:warning(['--graph: ignoring unexpected args: ', Args]),
  kb:graph.