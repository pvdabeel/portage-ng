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
    ->  gantt:version_str(Version, Ver)
    ;   Cat = '', Name = Entry, Ver = ''
    ),
    (   cache:entry_metadata(Repo, Entry, slot, slot(S))
    ->  atom_string(S, Slot)
    ;   Slot = "0"
    ),
    (   cache:entry_metadata(Repo, Entry, installed, true)
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
    gantt:version_str(Version, Ver),
    emit_doctype,
    emit_head_open(Cat, Name, Ver),
    emit_head_close,
    emit_body_open,
    emit_title(Cat, Name, Ver),
    emit_subtitle_placeholder,
    version_neighbours(Repo, Entry, Newer, Newest, Older, Oldest),
    navtheme:emit_nav_bar(Repo, Entry, Cat, Name, deptree, Newer, Newest, Older, Oldest),
    write('</div>'), nl,
    emit_dep_tabs,
    emit_graph_container,
    emit_tooltip_container,
    emit_legend,
    emit_script(Repo, Entry, TypeTrees),
    navtheme:emit_theme_script('deptree-theme'),
    emit_body_close.


% -----------------------------------------------------------------------------
%  HTML emission - document structure
% -----------------------------------------------------------------------------

emit_doctype :-
    write('<!DOCTYPE html>'), nl.

emit_head_open(Cat, Name, Ver) :-
    write('<html lang="en" data-theme="dark">'), nl,
    write('<head>'), nl,
    write('<meta charset="UTF-8">'), nl,
    write('<meta name="viewport" content="width=device-width, initial-scale=1.0">'), nl,
    format('<title>~w/~w-~w &mdash; Dependency Graph</title>~n', [Cat, Name, Ver]),
    navtheme:emit_css_link('../').

emit_head_close :-
    write('</head>'), nl.

emit_body_open :-
    write('<body class="page-deptree">'), nl.

emit_body_close :-
    write('</body>'), nl,
    write('</html>'), nl.

emit_title(Cat, Name, Ver) :-
    write('<div class="header">'), nl,
    write('<div class="title-row">'), nl,
    format('<h1>~w/~w-~w &mdash; Dependency Graph</h1>~n', [Cat, Name, Ver]),
    navtheme:emit_theme_btn,
    write('</div>'), nl.

emit_subtitle_placeholder :-
    write('<p class="subtitle" id="subtitle"></p>'), nl.


% -----------------------------------------------------------------------------
%  HTML emission - dep type tabs
% -----------------------------------------------------------------------------

emit_dep_tabs :-
    write('<div class="dep-tabs">'), nl,
    write('  <span class="label">Dep type:</span>'), nl,
    write('  <button class="dep-tab off" data-type="bdepend" onclick="switchDepType(\'bdepend\')">BDEPEND</button>'), nl,
    write('  <button class="dep-tab off" data-type="cdepend" onclick="switchDepType(\'cdepend\')">CDEPEND</button>'), nl,
    write('  <button class="dep-tab off" data-type="depend" onclick="switchDepType(\'depend\')">DEPEND</button>'), nl,
    write('  <button class="dep-tab off" data-type="idepend" onclick="switchDepType(\'idepend\')">IDEPEND</button>'), nl,
    write('  <button class="dep-tab active" data-type="rdepend" onclick="switchDepType(\'rdepend\')">RDEPEND</button>'), nl,
    write('  <button class="dep-tab off" data-type="pdepend" onclick="switchDepType(\'pdepend\')">PDEPEND</button>'), nl,
    write('  <div class="sep"></div>'), nl,
    write('  <button class="action-btn" onclick="expandAll()">expand all</button>'), nl,
    write('  <button class="action-btn" onclick="collapseAll()">collapse all</button>'), nl,
    write('  <button class="action-btn" onclick="resetView()">reset view</button>'), nl,
    write('</div>'), nl.


% -----------------------------------------------------------------------------
%  HTML emission - graph and tooltip containers
% -----------------------------------------------------------------------------

emit_graph_container :-
    write('<div class="graph-container" id="graph-container">'), nl,
    write('  <svg id="graph-svg" xmlns="http://www.w3.org/2000/svg"></svg>'), nl,
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
    emit_js_engine(RootEntry),
    write('</script>'), nl.


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
    format('  ~w: {~n', [Type]),
    write('    nodes: ['), nl,
    emit_js_nodes(Repo, Nodes),
    write('    ],'), nl,
    write('    edges: ['), nl,
    emit_js_edges(Edges),
    write('    ],'), nl,
    format('    root: "~w"~n', [RootEntry]),
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
    js_escape_atom(Entry, EEntry),
    js_escape_atom(Cat, ECat),
    js_escape_atom(Name, EName),
    js_escape_atom(Ver, EVer),
    js_escape_atom(Slot, ESlot),
    js_escape_atom(Desc, EDesc),
    js_escape_atom(Homepage, EHomepage),
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
    js_escape_atom(Name, EName),
    format('"~w~w"', [Prefix, EName]),
    (Rest \== [] -> write(',') ; true),
    emit_js_use_flags(Rest).


%! deptree:emit_js_edges(+Edges)
%
% Emit JavaScript edge objects.

emit_js_edges([]).
emit_js_edges([edge(From, To, Strength)|Rest]) :-
    js_escape_atom(From, EFrom),
    js_escape_atom(To, ETo),
    format('      {from:"~w",to:"~w",type:"~w"}', [EFrom, ETo, Strength]),
    (   Rest == []
    ->  nl
    ;   write(','), nl
    ),
    emit_js_edges(Rest).


%! deptree:emit_js_engine(+RootEntry)
%
% Emit the JavaScript layout engine, rendering, and interaction code.

emit_js_engine(_RootEntry) :-
    write('let currentType = "rdepend";'), nl,
    write('let collapsed = new Set();'), nl,
    write('let viewBox = {x:0, y:0, w:0, h:0};'), nl,
    write('let zoom = 1;'), nl,
    write('let isPanning = false, panStart = {x:0,y:0}, vbStart = {x:0,y:0};'), nl,
    write('const CARD_W = 130, CARD_H = 44, LAYER_H = 90, MIN_GAP = 16;'), nl,
    write('const svg = document.getElementById("graph-svg");'), nl,
    write('const container = document.getElementById("graph-container");'), nl,
    write('const tooltip = document.getElementById("tooltip");'), nl,
    write('const ns = "http://www.w3.org/2000/svg";'), nl,
    write('function getTree() { return treeData[currentType]; }'), nl,
    emit_js_build_layout,
    emit_js_resolve_overlaps,
    emit_js_render,
    emit_js_count_descendants,
    emit_js_tooltip,
    emit_js_controls,
    emit_js_pan_zoom,
    write('render();'), nl.

emit_js_build_layout :-
    write('function buildLayout() {'), nl,
    write('  const tree = getTree();'), nl,
    write('  if (!tree || !tree.nodes.length) return {positions:{},maxX:0,maxY:0,hiddenSet:new Set(),childMap:{},nodeMap:{}};'), nl,
    write('  const childMap = {}, nodeMap = {};'), nl,
    write('  tree.nodes.forEach(n => { nodeMap[n.id] = n; childMap[n.id] = []; });'), nl,
    write('  tree.edges.forEach(e => { if (childMap[e.from]) childMap[e.from].push(e.to); });'), nl,
    write('  const hiddenSet = new Set();'), nl,
    write('  function markHidden(id) { (childMap[id]||[]).forEach(c => { hiddenSet.add(c); markHidden(c); }); }'), nl,
    write('  collapsed.forEach(id => markHidden(id));'), nl,
    write('  const layers = {};'), nl,
    write('  const visited = new Set();'), nl,
    write('  function bfs(startId) {'), nl,
    write('    const queue = [{id: startId, depth: 0}];'), nl,
    write('    visited.add(startId);'), nl,
    write('    while (queue.length) {'), nl,
    write('      const {id, depth} = queue.shift();'), nl,
    write('      if (!layers[depth]) layers[depth] = [];'), nl,
    write('      layers[depth].push(id);'), nl,
    write('      (childMap[id]||[]).forEach(c => {'), nl,
    write('        if (!visited.has(c) && !hiddenSet.has(c)) { visited.add(c); queue.push({id:c, depth:depth+1}); }'), nl,
    write('      });'), nl,
    write('    }'), nl,
    write('  }'), nl,
    write('  bfs(tree.root);'), nl,
    write('  const positions = {};'), nl,
    write('  const maxDepth = Math.max(0, ...Object.keys(layers).map(Number));'), nl,
    write('  const layerWidths = {};'), nl,
    write('  for (let d = maxDepth; d >= 0; d--) {'), nl,
    write('    const ids = layers[d] || [];'), nl,
    write('    layerWidths[d] = ids.length * CARD_W + (ids.length - 1) * MIN_GAP;'), nl,
    write('  }'), nl,
    write('  const maxW = Math.max(...Object.values(layerWidths), 400);'), nl,
    write('  for (let d = maxDepth; d >= 0; d--) {'), nl,
    write('    const ids = layers[d] || [];'), nl,
    write('    if (ids.length === 0) continue;'), nl,
    write('    const totalW = ids.length * CARD_W + (ids.length - 1) * MIN_GAP;'), nl,
    write('    const startX = (maxW - totalW) / 2;'), nl,
    write('    ids.forEach((id, i) => {'), nl,
    write('      positions[id] = {x: startX + i * (CARD_W + MIN_GAP) + CARD_W / 2, y: d * LAYER_H + 30};'), nl,
    write('    });'), nl,
    write('  }'), nl,
    write('  for (let pass = 0; pass < 4; pass++) {'), nl,
    write('    for (let d = maxDepth; d >= 0; d--) {'), nl,
    write('      const ids = layers[d] || [];'), nl,
    write('      ids.forEach(id => {'), nl,
    write('        const children = (childMap[id]||[]).filter(c => !hiddenSet.has(c) && positions[c]);'), nl,
    write('        if (children.length > 0) {'), nl,
    write('          positions[id].x = children.reduce((s, c) => s + positions[c].x, 0) / children.length;'), nl,
    write('        }'), nl,
    write('      });'), nl,
    write('      spreadLayer(ids, positions);'), nl,
    write('    }'), nl,
    write('    for (let d = 0; d <= maxDepth; d++) {'), nl,
    write('      const ids = layers[d] || [];'), nl,
    write('      ids.forEach(id => {'), nl,
    write('        const children = (childMap[id]||[]).filter(c => !hiddenSet.has(c) && positions[c]);'), nl,
    write('        if (children.length > 0) {'), nl,
    write('          positions[id].x = children.reduce((s, c) => s + positions[c].x, 0) / children.length;'), nl,
    write('        }'), nl,
    write('      });'), nl,
    write('      spreadLayer(ids, positions);'), nl,
    write('    }'), nl,
    write('  }'), nl,
    write('  let actualMaxX = 0;'), nl,
    write('  Object.values(positions).forEach(p => { if (p.x + CARD_W/2 > actualMaxX) actualMaxX = p.x + CARD_W/2; });'), nl,
    write('  return {positions, maxX: Math.max(actualMaxX + MIN_GAP, 400), maxY: (maxDepth + 1) * LAYER_H + 40, hiddenSet, childMap, nodeMap};'), nl,
    write('}'), nl.

emit_js_resolve_overlaps :-
    write('function spreadLayer(ids, positions) {'), nl,
    write('  if (!ids || ids.length <= 1) return;'), nl,
    write('  for (let i = 1; i < ids.length; i++) {'), nl,
    write('    const prev = positions[ids[i-1]], curr = positions[ids[i]];'), nl,
    write('    const minX = prev.x + CARD_W + MIN_GAP;'), nl,
    write('    if (curr.x < minX) curr.x = minX;'), nl,
    write('  }'), nl,
    write('}'), nl.

emit_js_render :-
    write('function render() {'), nl,
    write('  const tree = getTree();'), nl,
    write('  if (!tree || !tree.nodes.length) { svg.innerHTML = ""; document.getElementById("subtitle").textContent = "No dependencies"; return; }'), nl,
    write('  const {positions, maxX, maxY, hiddenSet, childMap, nodeMap} = buildLayout();'), nl,
    write('  const pad = 40;'), nl,
    write('  viewBox = {x: -pad, y: -pad, w: maxX + pad * 2, h: maxY + pad * 2};'), nl,
    write('  svg.setAttribute("viewBox", `${viewBox.x} ${viewBox.y} ${viewBox.w} ${viewBox.h}`);'), nl,
    write('  svg.innerHTML = "";'), nl,
    write('  const defs = document.createElementNS(ns, "defs");'), nl,
    write('  ["normal","weak","strong"].forEach(t => {'), nl,
    write('    const col = t === "weak" ? "var(--edge-weak)" : t === "strong" ? "var(--edge-strong)" : "var(--edge-normal)";'), nl,
    write('    const m = document.createElementNS(ns, "marker");'), nl,
    write('    m.setAttribute("id", "arrow-" + t); m.setAttribute("markerWidth", "7");'), nl,
    write('    m.setAttribute("markerHeight", "5"); m.setAttribute("refX", "7");'), nl,
    write('    m.setAttribute("refY", "2.5"); m.setAttribute("orient", "auto");'), nl,
    write('    const p = document.createElementNS(ns, "polygon");'), nl,
    write('    p.setAttribute("points", "0 0,7 2.5,0 5"); p.setAttribute("fill", col);'), nl,
    write('    m.appendChild(p); defs.appendChild(m);'), nl,
    write('  }); svg.appendChild(defs);'), nl,
    write('  const edgeG = document.createElementNS(ns, "g");'), nl,
    write('  tree.edges.forEach(e => {'), nl,
    write('    if (hiddenSet.has(e.to) || !positions[e.from] || !positions[e.to]) return;'), nl,
    write('    const fp = positions[e.from], tp = positions[e.to];'), nl,
    write('    const x1 = fp.x, y1 = fp.y + CARD_H / 2, x2 = tp.x, y2 = tp.y - CARD_H / 2;'), nl,
    write('    const my = (y1 + y2) / 2;'), nl,
    write('    const path = document.createElementNS(ns, "path");'), nl,
    write('    path.setAttribute("d", `M${x1},${y1} C${x1},${my} ${x2},${my} ${x2},${y2}`);'), nl,
    write('    const col = e.type === "weak" ? "var(--edge-weak)" : e.type === "strong" ? "var(--edge-strong)" : "var(--edge-normal)";'), nl,
    write('    const markerT = e.type === "no" ? "normal" : e.type;'), nl,
    write('    path.setAttribute("stroke", col); path.setAttribute("stroke-width", "1.3");'), nl,
    write('    path.setAttribute("fill", "none"); path.setAttribute("marker-end", `url(#arrow-${markerT})`);'), nl,
    write('    path.setAttribute("opacity", "0.6");'), nl,
    write('    if (e.type === "weak") path.setAttribute("stroke-dasharray", "5,3");'), nl,
    write('    if (e.type === "strong") path.setAttribute("stroke-dasharray", "3,2");'), nl,
    write('    edgeG.appendChild(path);'), nl,
    write('  }); svg.appendChild(edgeG);'), nl,
    write('  const nodeG = document.createElementNS(ns, "g");'), nl,
    write('  tree.nodes.forEach(n => {'), nl,
    write('    if (hiddenSet.has(n.id) || !positions[n.id]) return;'), nl,
    write('    const pos = positions[n.id], isRoot = n.id === tree.root;'), nl,
    write('    const isCollapsed = collapsed.has(n.id);'), nl,
    write('    const childCount = (childMap[n.id]||[]).length;'), nl,
    write('    const descendantCount = countDescendants(n.id, childMap);'), nl,
    write('    const g = document.createElementNS(ns, "g");'), nl,
    write('    g.setAttribute("class", "node-g");'), nl,
    write('    g.setAttribute("data-id", n.id);'), nl,
    write('    g.style.cursor = childCount > 0 ? "pointer" : "default";'), nl,
    write('    const x = pos.x - CARD_W / 2, y = pos.y - CARD_H / 2;'), nl,
    write('    if (n.installed) {'), nl,
    write('      const ib = document.createElementNS(ns, "rect");'), nl,
    write('      ib.setAttribute("x", x); ib.setAttribute("y", y);'), nl,
    write('      ib.setAttribute("width", 3); ib.setAttribute("height", CARD_H);'), nl,
    write('      ib.setAttribute("fill", "var(--node-installed)"); ib.setAttribute("rx", "2");'), nl,
    write('      g.appendChild(ib);'), nl,
    write('    }'), nl,
    write('    const rect = document.createElementNS(ns, "rect");'), nl,
    write('    const rx = n.installed ? x + 3 : x, rw = n.installed ? CARD_W - 3 : CARD_W;'), nl,
    write('    rect.setAttribute("x", rx); rect.setAttribute("y", y);'), nl,
    write('    rect.setAttribute("width", rw); rect.setAttribute("height", CARD_H);'), nl,
    write('    rect.setAttribute("rx", "5"); rect.setAttribute("ry", "5");'), nl,
    write('    rect.setAttribute("fill", "var(--node-bg)");'), nl,
    write('    rect.setAttribute("stroke", isRoot ? "var(--node-root-border)" : "var(--node-border)");'), nl,
    write('    rect.setAttribute("stroke-width", isRoot ? "2" : "1.5");'), nl,
    write('    if (isCollapsed) rect.setAttribute("opacity", "0.7");'), nl,
    write('    g.appendChild(rect);'), nl,
    write('    const nameT = document.createElementNS(ns, "text");'), nl,
    write('    nameT.setAttribute("x", pos.x); nameT.setAttribute("y", pos.y - 4);'), nl,
    write('    nameT.setAttribute("text-anchor", "middle");'), nl,
    write('    nameT.setAttribute("font-size", "11"); nameT.setAttribute("font-weight", "600");'), nl,
    write('    nameT.setAttribute("fill", "var(--text)"); nameT.setAttribute("font-family", "Helvetica Neue, Helvetica, sans-serif");'), nl,
    write('    nameT.textContent = n.name;'), nl,
    write('    g.appendChild(nameT);'), nl,
    write('    const verT = document.createElementNS(ns, "text");'), nl,
    write('    verT.setAttribute("x", pos.x); verT.setAttribute("y", pos.y + 10);'), nl,
    write('    verT.setAttribute("text-anchor", "middle");'), nl,
    write('    verT.setAttribute("font-size", "10"); verT.setAttribute("fill", "var(--text2)");'), nl,
    write('    verT.setAttribute("font-family", "Helvetica Neue, Helvetica, sans-serif");'), nl,
    write('    verT.textContent = n.ver + (n.slot !== "0" ? "  :" + n.slot : "");'), nl,
    write('    g.appendChild(verT);'), nl,
    write('    if (childCount > 0) {'), nl,
    write('      const indT = document.createElementNS(ns, "text");'), nl,
    write('      indT.setAttribute("x", pos.x + CARD_W / 2 - 6);'), nl,
    write('      indT.setAttribute("y", pos.y + CARD_H / 2 - 3);'), nl,
    write('      indT.setAttribute("text-anchor", "end"); indT.setAttribute("font-size", "9");'), nl,
    write('      indT.setAttribute("fill", isCollapsed ? "var(--rdepend)" : "var(--text2)");'), nl,
    write('      indT.setAttribute("font-weight", isCollapsed ? "600" : "normal");'), nl,
    write('      indT.setAttribute("font-family", "Helvetica Neue, Helvetica, sans-serif");'), nl,
    write('      indT.textContent = isCollapsed ? "+" + descendantCount : "\\u25BE";'), nl,
    write('      g.appendChild(indT);'), nl,
    write('    }'), nl,
    write('    g.addEventListener("click", () => {'), nl,
    write('      if (childCount === 0) return;'), nl,
    write('      if (collapsed.has(n.id)) collapsed.delete(n.id); else collapsed.add(n.id);'), nl,
    write('      render();'), nl,
    write('    });'), nl,
    write('    g.addEventListener("mouseenter", ev => showTooltip(ev, n));'), nl,
    write('    g.addEventListener("mousemove", ev => moveTooltip(ev));'), nl,
    write('    g.addEventListener("mouseleave", hideTooltip);'), nl,
    write('    nodeG.appendChild(g);'), nl,
    write('  }); svg.appendChild(nodeG);'), nl,
    write('  const visibleNodes = tree.nodes.filter(n => !hiddenSet.has(n.id) && positions[n.id]).length;'), nl,
    write('  const visibleEdges = tree.edges.filter(e => !hiddenSet.has(e.to) && positions[e.from] && positions[e.to]).length;'), nl,
    write('  const depths = Object.values(positions).map(p => p.y);'), nl,
    write('  const levels = depths.length ? Math.round((Math.max(...depths) - Math.min(...depths)) / LAYER_H) + 1 : 0;'), nl,
    write('  document.getElementById("subtitle").textContent ='), nl,
    write('    `${visibleNodes} nodes \\u00b7 ${visibleEdges} edges \\u00b7 ${levels} levels`;'), nl,
    write('}'), nl.

emit_js_count_descendants :-
    write('function countDescendants(id, childMap) {'), nl,
    write('  let count = 0; const stack = [...(childMap[id]||[])]; const seen = new Set();'), nl,
    write('  while (stack.length) {'), nl,
    write('    const c = stack.pop();'), nl,
    write('    if (seen.has(c)) continue; seen.add(c); count++;'), nl,
    write('    (childMap[c]||[]).forEach(cc => stack.push(cc));'), nl,
    write('  }'), nl,
    write('  return count;'), nl,
    write('}'), nl.

emit_js_tooltip :-
    write('function showTooltip(ev, n) {'), nl,
    write('  const useHtml = (n.use||[]).map(u => {'), nl,
    write('    const on = u.startsWith("+");'), nl,
    write('    return `<span class="use-flag ${on?"on":"off"}">${u}</span>`;'), nl,
    write('  }).join("");'), nl,
    write('  tooltip.innerHTML = `'), nl,
    write('    <div class="tt-title">${n.cat}/${n.name}-${n.ver}</div>'), nl,
    write('    ${n.desc ? `<div class="tt-desc">${n.desc}</div>` : ""}'), nl,
    write('    <div class="tt-row"><span class="tt-label">Slot</span><span class="tt-value">${n.slot}</span></div>'), nl,
    write('    <div class="tt-row"><span class="tt-label">Status</span><span class="${n.installed?"tt-installed":"tt-not-installed"}">${n.installed?"Installed":"Not installed"}</span></div>'), nl,
    write('    ${n.homepage ? `<div class="tt-row"><span class="tt-label">Home</span><a class="tt-link" href="${n.homepage}" target="_blank">${n.homepage.replace(/https?:\\/\\//,"").substring(0,40)}...</a></div>` : ""}'), nl,
    write('    ${useHtml ? `<div style="margin-top:4px"><span class="tt-label">USE</span><div class="use-flags">${useHtml}</div></div>` : ""}'), nl,
    write('  `; tooltip.style.display = "block"; moveTooltip(ev);'), nl,
    write('}'), nl,
    write('function moveTooltip(ev) {'), nl,
    write('  const pad = 12; let x = ev.clientX + pad, y = ev.clientY + pad;'), nl,
    write('  const tw = tooltip.offsetWidth, th = tooltip.offsetHeight;'), nl,
    write('  if (x + tw > window.innerWidth - pad) x = ev.clientX - tw - pad;'), nl,
    write('  if (y + th > window.innerHeight - pad) y = ev.clientY - th - pad;'), nl,
    write('  tooltip.style.left = x + "px"; tooltip.style.top = y + "px";'), nl,
    write('}'), nl,
    write('function hideTooltip() { tooltip.style.display = "none"; }'), nl.

emit_js_controls :-
    write('function switchDepType(type) {'), nl,
    write('  if (!treeData[type]) return;'), nl,
    write('  currentType = type; collapsed.clear();'), nl,
    write('  document.querySelectorAll(".dep-tab").forEach(b => {'), nl,
    write('    b.classList.toggle("active", b.dataset.type === type);'), nl,
    write('    b.classList.toggle("off", b.dataset.type !== type);'), nl,
    write('  }); render();'), nl,
    write('}'), nl,
    write('function expandAll() { collapsed.clear(); render(); }'), nl,
    write('function collapseAll() {'), nl,
    write('  const tree = getTree(); if (!tree) return;'), nl,
    write('  const childMap = {};'), nl,
    write('  tree.nodes.forEach(n => childMap[n.id] = []);'), nl,
    write('  tree.edges.forEach(e => { if (childMap[e.from]) childMap[e.from].push(e.to); });'), nl,
    write('  tree.nodes.forEach(n => { if ((childMap[n.id]||[]).length > 0 && n.id !== tree.root) collapsed.add(n.id); });'), nl,
    write('  render();'), nl,
    write('}'), nl,
    write('function resetView() { zoom = 1; document.getElementById("zoom-level").textContent = "100%"; render(); }'), nl,
    write('function zoomIn() { zoom = Math.min(zoom * 1.25, 4); applyZoom(); }'), nl,
    write('function zoomOut() { zoom = Math.max(zoom / 1.25, 0.25); applyZoom(); }'), nl,
    write('function applyZoom() {'), nl,
    write('  const cx = viewBox.x + viewBox.w / 2, cy = viewBox.y + viewBox.h / 2;'), nl,
    write('  const nw = viewBox.w / zoom, nh = viewBox.h / zoom;'), nl,
    write('  svg.setAttribute("viewBox", `${cx - nw/2} ${cy - nh/2} ${nw} ${nh}`);'), nl,
    write('  document.getElementById("zoom-level").textContent = Math.round(zoom * 100) + "%";'), nl,
    write('}'), nl.

emit_js_pan_zoom :-
    write('container.addEventListener("mousedown", e => {'), nl,
    write('  if (e.target.closest(".node-g")) return;'), nl,
    write('  isPanning = true; panStart = {x: e.clientX, y: e.clientY};'), nl,
    write('  const vb = svg.getAttribute("viewBox").split(" ").map(Number);'), nl,
    write('  vbStart = {x: vb[0], y: vb[1]}; container.style.cursor = "grabbing";'), nl,
    write('});'), nl,
    write('container.addEventListener("mousemove", e => {'), nl,
    write('  if (!isPanning) return;'), nl,
    write('  const vb = svg.getAttribute("viewBox").split(" ").map(Number);'), nl,
    write('  const scale = vb[2] / container.clientWidth;'), nl,
    write('  const dx = (e.clientX - panStart.x) * scale, dy = (e.clientY - panStart.y) * scale;'), nl,
    write('  svg.setAttribute("viewBox", `${vbStart.x - dx} ${vbStart.y - dy} ${vb[2]} ${vb[3]}`);'), nl,
    write('});'), nl,
    write('container.addEventListener("mouseup", () => { isPanning = false; container.style.cursor = ""; });'), nl,
    write('container.addEventListener("mouseleave", () => { isPanning = false; container.style.cursor = ""; });'), nl,
    write('container.addEventListener("wheel", e => {'), nl,
    write('  e.preventDefault();'), nl,
    write('  const factor = e.deltaY > 0 ? 0.9 : 1.1;'), nl,
    write('  zoom *= factor; zoom = Math.max(0.25, Math.min(4, zoom));'), nl,
    write('  const vb = svg.getAttribute("viewBox").split(" ").map(Number);'), nl,
    write('  const rect = container.getBoundingClientRect();'), nl,
    write('  const mx = (e.clientX - rect.left) / rect.width, my = (e.clientY - rect.top) / rect.height;'), nl,
    write('  const nw = vb[2] / factor, nh = vb[3] / factor;'), nl,
    write('  const nx = vb[0] + (vb[2] - nw) * mx, ny = vb[1] + (vb[3] - nh) * my;'), nl,
    write('  svg.setAttribute("viewBox", `${nx} ${ny} ${nw} ${nh}`);'), nl,
    write('  document.getElementById("zoom-level").textContent = Math.round(zoom * 100) + "%";'), nl,
    write('}, {passive: false});'), nl.


% -----------------------------------------------------------------------------
%  Helpers
% -----------------------------------------------------------------------------

%! deptree:js_escape_atom(+In, -Out)
%
% Escape an atom for safe embedding in a JavaScript string literal.

js_escape_atom(In, Out) :-
    atom_codes(In, Codes),
    js_esc_codes(Codes, OutCodes),
    atom_codes(Out, OutCodes).

js_esc_codes([], []).
js_esc_codes([0'\\|T], [0'\\, 0'\\ |R]) :- !, js_esc_codes(T, R).
js_esc_codes([0'"|T],  [0'\\, 0'" |R])  :- !, js_esc_codes(T, R).
js_esc_codes([0'\n|T], [0'\\, 0'n |R])  :- !, js_esc_codes(T, R).
js_esc_codes([0'\r|T], [0'\\, 0'r |R])  :- !, js_esc_codes(T, R).
js_esc_codes([H|T], [H|R]) :- js_esc_codes(T, R).