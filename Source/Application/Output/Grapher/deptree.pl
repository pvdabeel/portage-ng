/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> DEPTREE
Interactive HTML dependency graph visualisation for portage-ng packages.
Generates a self-contained HTML file with a layered tree graph showing
transitive dependencies per dep type (BDEPEND, DEPEND, RDEPEND, PDEPEND, etc.),
node cards with installed status, hover tooltips with metadata, collapsible
subtrees, pan/zoom, and dep-type tab switching.
*/

:- module(deptree, []).

% =============================================================================
%  DEPTREE declarations
% =============================================================================


% -----------------------------------------------------------------------------
%  Entry point
% -----------------------------------------------------------------------------

%! deptree:graph(+Target)
%
% Generate a dependency graph HTML document for Target to current output stream.
% Collects trees for all dep types, then emits HTML.

deptree:graph(Repository://Entry) :-
    DepTypes = [bdepend, cdepend, depend, idepend, rdepend, pdepend],
    collect_all_types(DepTypes, Repository, Entry, TypeTrees),
    deptree:emit_html(Repository://Entry, TypeTrees).


% -----------------------------------------------------------------------------
%  Data collection - tree traversal
% -----------------------------------------------------------------------------

:- thread_local dep_visited/1.

%! deptree:collect_all_types(+Types, +Repo, +Entry, -TypeTrees)
%
% Collect dependency trees for each dep type. TypeTrees is a list of
% deptree(Type, Nodes, Edges) terms. Empty trees are included with [] nodes.

collect_all_types([], _, _, []).
collect_all_types([Type|Types], Repo, Entry, [deptree(Type, Nodes, Edges)|Rest]) :-
    catch(
        collect_tree(Type, Repo, Entry, Nodes, Edges),
        _,
        (Nodes = [], Edges = [])
    ),
    collect_all_types(Types, Repo, Entry, Rest).


%! deptree:collect_tree(+Type, +Repo, +Entry, -Nodes, -Edges)
%
% BFS traversal of the dependency tree for a given dep type. Tracks visited
% nodes to handle DAGs. Produces flat lists of node/6 and edge/3 terms.

collect_tree(Type, Repo, Entry, Nodes, Edges) :-
    retractall(dep_visited(_)),
    collect_tree_bfs([Repo://Entry], Type, Repo, [], [], NodesRev, EdgesRev),
    retractall(dep_visited(_)),
    reverse(NodesRev, Nodes),
    reverse(EdgesRev, Edges0),
    sort(Edges0, Edges).

collect_tree_bfs([], _, _, Nodes, Edges, Nodes, Edges).
collect_tree_bfs([Repo://Id|Queue], Type, RootRepo, NodesAcc, EdgesAcc, NodesOut, EdgesOut) :-
    (   dep_visited(Repo://Id)
    ->  collect_tree_bfs(Queue, Type, RootRepo, NodesAcc, EdgesAcc, NodesOut, EdgesOut)
    ;   assertz(dep_visited(Repo://Id)),
        make_node(Repo, Id, Node),
        Statement =.. [Type, DS],
        (   query:search(all(Statement), Repo://Id)
        ->  true
        ;   DS = []
        ),
        findall(edge(Id, ChildId, Strength),
            (   member(D, DS),
                dep_choice(D, Repo, ChildId, Strength)
            ),
            NewEdges),
        findall(Repo://ChildId, member(edge(_, ChildId, _), NewEdges), Children),
        append(Queue, Children, Queue1),
        append(NodesAcc, [Node], NodesAcc1),
        append(EdgesAcc, NewEdges, EdgesAcc1),
        collect_tree_bfs(Queue1, Type, RootRepo, NodesAcc1, EdgesAcc1, NodesOut, EdgesOut)
    ).


%! deptree:dep_choice(+DepTerm, +Repo, -ChildEntry, -Strength)
%
% Extract a concrete package choice from a dependency term, matching the
% grapher handle logic for full tree graphs (groups are skipped).

dep_choice(package_dependency(_, Strength, Cat, Name, Cmpr, Ver, _, _),
           _Repo, Choice, Strength) :-
    query:search([name(Name), category(Cat), select(version, Cmpr, Ver)],
                 _://Choice), !.

dep_choice(Group, _, _, _) :-
    functor(Group, F, _),
    member(F, [use_conditional_group, any_of_group, all_of_group,
               exactly_one_of_group, at_most_one_of_group]),
    !, fail.


%! deptree:make_node(+Repo, +Entry, -Node)
%
% Build a node/6 term with category, name, version, slot, and installed status.

make_node(Repo, Entry, node(Entry, Cat, Name, Ver, Slot, Installed)) :-
    (   cache:ordered_entry(Repo, Entry, Cat, Name, Version)
    ->  version_domain:display_atom(Version, Ver)
    ;   Cat = '', Name = Entry, Ver = ''
    ),
    (   cache:entry_metadata(Repo, Entry, slot, slot(S))
    ->  atom_string(S, Slot)
    ;   Slot = "0"
    ),
    (   cache:ordered_entry(pkg, Entry, _, _, _)
    ->  Installed = true
    ;   Installed = false
    ).


% -----------------------------------------------------------------------------
%  Per-node metadata collection
% -----------------------------------------------------------------------------

%! deptree:node_meta(+Repo, +Entry, -Desc, -Homepage, -UseFlags)
%
% Retrieve description, homepage, and USE flags for a node.

node_meta(Repo, Entry, Desc, Homepage, UseFlags) :-
    (   cache:entry_metadata(Repo, Entry, description, D)
    ->  Desc = D
    ;   Desc = ''
    ),
    (   cache:entry_metadata(Repo, Entry, homepage, H)
    ->  Homepage = H
    ;   Homepage = ''
    ),
    (   gantt:pkg_use_flags(Repo, Entry, Flags)
    ->  UseFlags = Flags
    ;   UseFlags = []
    ).


% -----------------------------------------------------------------------------
%  Version navigation helpers
% -----------------------------------------------------------------------------

%! deptree:version_neighbours(+Repo, +Entry, -Newer, -Newest, -Older, -Oldest)
%
% Find adjacent versions for navigation links.

version_neighbours(Repo, Entry, Newer, Newest, Older, Oldest) :-
    query:search([category(C), name(N), version(V)], Repo://Entry),
    findall(E, query:search([name(N), category(C), select(version, greater, V)], Repo://E), EgList),
    findall(E, query:search([name(N), category(C), select(version, smaller, V)], Repo://E), EsList),
    (last(EgList, Newer0)       -> Newer = Newer0   ; Newer = ''),
    (EgList = [Newest0|_]       -> Newest = Newest0  ; Newest = ''),
    (EsList = [Older0|_]        -> Older = Older0    ; Older = ''),
    (last(EsList, Oldest0)      -> Oldest = Oldest0  ; Oldest = ''),
    !.
version_neighbours(_, _, '', '', '', '').


% -----------------------------------------------------------------------------
%  HTML emission - main
% -----------------------------------------------------------------------------

%! deptree:emit_html(+Target, +TypeTrees)
%
% Emit a complete self-contained HTML document to the current output stream.

deptree:emit_html(Target, TypeTrees) :-
    Target = Repo://Entry,
    cache:ordered_entry(Repo, Entry, Cat, Name, Version),
    version_domain:display_atom(Version, Ver),
    format(atom(Title), '~w/~w-~w — Dependency Graph', [Cat, Name, Ver]),
    navtheme:emit_doctype,
    navtheme:emit_head_open(Title, '../'),
    navtheme:emit_head_close,
    navtheme:emit_body_open('page-deptree'),
    navtheme:emit_top_bar('../', Repo, Cat, Name, Ver),
    navtheme:emit_main_open,
    navtheme:emit_page_head_open,
    version_neighbours(Repo, Entry, Newer, Newest, Older, Oldest),
    navtheme:emit_nav_bar(Repo, Entry, Cat, Name, deptree, Newer, Newest, Older, Oldest, Ver),
    navtheme:emit_page_head_close,
    navtheme:emit_term_open('portage-ng deptree'),
    emit_dep_tabs,
    emit_graph_container,
    emit_legend,
    navtheme:emit_term_close,
    emit_tooltip_container,
    emit_script(Repo, Entry, TypeTrees),
    navtheme:emit_main_close,
    navtheme:emit_theme_script,
    navtheme:emit_body_close.


% -----------------------------------------------------------------------------
%  HTML emission - dep type tabs
% -----------------------------------------------------------------------------

emit_dep_tabs :-
    write('<div class="dep-tabs">'), nl,
    write('  <div class="filter-row">'), nl,
    write('    <button class="dep-tab off" data-type="bdepend" onclick="switchDepType(\'bdepend\')">BDEPEND</button>'), nl,
    write('    <button class="dep-tab off" data-type="cdepend" onclick="switchDepType(\'cdepend\')">CDEPEND</button>'), nl,
    write('    <button class="dep-tab off" data-type="depend" onclick="switchDepType(\'depend\')">DEPEND</button>'), nl,
    write('    <button class="dep-tab off" data-type="idepend" onclick="switchDepType(\'idepend\')">IDEPEND</button>'), nl,
    write('    <button class="dep-tab active" data-type="rdepend" onclick="switchDepType(\'rdepend\')">RDEPEND</button>'), nl,
    write('    <button class="dep-tab off" data-type="pdepend" onclick="switchDepType(\'pdepend\')">PDEPEND</button>'), nl,
    write('  </div>'), nl,
    write('  <div class="filter-toolbar">'), nl,
    write('    <button class="action-btn" onclick="expandAll()">Expand All</button>'), nl,
    write('    <button class="action-btn" onclick="collapseAll()">Collapse All</button>'), nl,
    write('    <button class="action-btn" onclick="resetView()">Reset</button>'), nl,
    write('  </div>'), nl,
    write('</div>'), nl.


% -----------------------------------------------------------------------------
%  HTML emission - graph and tooltip containers
% -----------------------------------------------------------------------------

emit_graph_container :-
    write('<div class="graph-container" id="graph-container">'), nl,
    write('  <svg id="graph-svg" xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMidYMid meet"></svg>'), nl,
    write('  <div class="zoom-controls">'), nl,
    write('    <button class="zoom-btn" onclick="zoomIn()">+</button>'), nl,
    write('    <span class="zoom-level" id="zoom-level">100%</span>'), nl,
    write('    <button class="zoom-btn" onclick="zoomOut()">&minus;</button>'), nl,
    write('    <button class="zoom-btn" onclick="resetView()" title="Fit to view">&#8634;</button>'), nl,
    write('  </div>'), nl,
    write('</div>'), nl.

emit_tooltip_container :-
    write('<div class="tooltip" id="tooltip"></div>'), nl.


% -----------------------------------------------------------------------------
%  HTML emission - legend
% -----------------------------------------------------------------------------

emit_legend :-
    write('<div class="legend">'), nl,
    write('  <div class="legend-item"><div class="legend-swatch" style="background:#fff;border-color:var(--node-root-border);border-width:2px"></div>root package</div>'), nl,
    write('  <div class="legend-item"><div class="legend-swatch" style="background:#fff;border-color:#ccc;border-left:3px solid var(--node-installed)"></div>installed</div>'), nl,
    write('  <div class="legend-item"><div class="legend-swatch" style="background:#fff;border-color:#ccc"></div>not installed</div>'), nl,
    write('  <div class="legend-item"><svg width="30" height="12"><line x1="0" y1="6" x2="24" y2="6" stroke="var(--edge-normal)" stroke-width="1.5"/><polygon points="24,3 30,6 24,9" fill="var(--edge-normal)"/></svg>dependency</div>'), nl,
    write('  <div class="legend-item"><svg width="30" height="12"><line x1="0" y1="6" x2="24" y2="6" stroke="var(--edge-weak)" stroke-width="1.5" stroke-dasharray="4,2"/><polygon points="24,3 30,6 24,9" fill="var(--edge-weak)"/></svg>weak blocker</div>'), nl,
    write('  <div class="legend-item"><svg width="30" height="12"><line x1="0" y1="6" x2="24" y2="6" stroke="var(--edge-strong)" stroke-width="1.5" stroke-dasharray="2,2"/><polygon points="24,3 30,6 24,9" fill="var(--edge-strong)"/></svg>strong blocker</div>'), nl,
    write('</div>'), nl.


% -----------------------------------------------------------------------------
%  HTML emission - JavaScript
% -----------------------------------------------------------------------------

emit_script(Repo, RootEntry, TypeTrees) :-
    write('<script>'), nl,
    emit_js_tree_data(Repo, RootEntry, TypeTrees),
    write('</script>'), nl,
    navtheme:emit_script_src('../', deptree).


%! deptree:emit_js_tree_data(+Repo, +RootEntry, +TypeTrees)
%
% Emit the treeData JavaScript object containing nodes, edges, and metadata
% for each dep type.

emit_js_tree_data(Repo, RootEntry, TypeTrees) :-
    write('const treeData = {'), nl,
    emit_js_type_entries(Repo, RootEntry, TypeTrees),
    write('};'), nl.

emit_js_type_entries(_, _, []).
emit_js_type_entries(Repo, RootEntry, [deptree(Type, Nodes, Edges)|Rest]) :-
    navtheme:js_escape_atom(RootEntry, ERootEntry),
    format('  ~w: {~n', [Type]),
    write('    nodes: ['), nl,
    emit_js_nodes(Repo, Nodes),
    write('    ],'), nl,
    write('    edges: ['), nl,
    emit_js_edges(Edges),
    write('    ],'), nl,
    format('    root: "~w"~n', [ERootEntry]),
    (   Rest == []
    ->  write('  }'), nl
    ;   write('  },'), nl
    ),
    emit_js_type_entries(Repo, RootEntry, Rest).


%! deptree:emit_js_nodes(+Repo, +Nodes)
%
% Emit JavaScript node objects with embedded metadata.

emit_js_nodes(_, []).
emit_js_nodes(Repo, [node(Entry, Cat, Name, Ver, Slot, Installed)|Rest]) :-
    node_meta(Repo, Entry, Desc, Homepage, UseFlags),
    navtheme:js_escape_atom(Entry, EEntry),
    navtheme:js_escape_atom(Cat, ECat),
    navtheme:js_escape_atom(Name, EName),
    navtheme:js_escape_atom(Ver, EVer),
    navtheme:js_escape_atom(Slot, ESlot),
    navtheme:js_escape_atom(Desc, EDesc),
    navtheme:js_escape_atom(Homepage, EHomepage),
    (Installed == true -> InsStr = "true" ; InsStr = "false"),
    format('      {id:"~w",cat:"~w",name:"~w",ver:"~w",slot:"~w",installed:~w,desc:"~w",homepage:"~w",use:[',
           [EEntry, ECat, EName, EVer, ESlot, InsStr, EDesc, EHomepage]),
    emit_js_use_flags(UseFlags),
    (   Rest == []
    ->  write(']}'), nl
    ;   write(']},'), nl
    ),
    emit_js_nodes(Repo, Rest).

emit_js_use_flags([]).
emit_js_use_flags([flag(Name, OnOff)|Rest]) :-
    (OnOff == on -> Prefix = "+" ; Prefix = "-"),
    navtheme:js_escape_atom(Name, EName),
    format('"~w~w"', [Prefix, EName]),
    (Rest \== [] -> write(',') ; true),
    emit_js_use_flags(Rest).


%! deptree:emit_js_edges(+Edges)
%
% Emit JavaScript edge objects.

emit_js_edges([]).
emit_js_edges([edge(From, To, Strength)|Rest]) :-
    navtheme:js_escape_atom(From, EFrom),
    navtheme:js_escape_atom(To, ETo),
    format('      {from:"~w",to:"~w",type:"~w"}', [EFrom, ETo, Strength]),
    (   Rest == []
    ->  nl
    ;   write(','), nl
    ),
    emit_js_edges(Rest).
