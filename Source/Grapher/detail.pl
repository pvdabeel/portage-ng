/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> DETAIL
Interactive HTML detail graph visualisation for portage-ng packages.
Generates a self-contained HTML file with a tree view (default) and a graph
view (toggle) showing the raw dependency expression structure: use conditionals,
grouping operators (any_of, all_of, etc.), package dependencies, and candidate
versions. Supports day/night theme toggle.
*/

:- module(detail, []).

% =============================================================================
%  DETAIL declarations
% =============================================================================


% -----------------------------------------------------------------------------
%  Entry point
% -----------------------------------------------------------------------------

%! detail:graph(+Target)
%
% Generate a detail graph HTML document for Target to current output stream.
% Collects dependency trees for install, run, and both phases, then emits HTML.

detail:graph(Repository://Entry) :-
    collect_dep_tree(Repository, Entry, InstallTree, RunTree, BothTree),
    emit_html(Repository://Entry, InstallTree, RunTree, BothTree).


% -----------------------------------------------------------------------------
%  Data collection
% -----------------------------------------------------------------------------

%! detail:collect_dep_tree(+Repo, +Entry, -InstallTree, -RunTree, -BothTree)
%
% Collect dependency expression trees split by phase. Install-only, run-only,
% and shared (both) dependency sets are each converted to nested tree terms.

collect_dep_tree(Repository, Entry, InstallTree, RunTree, BothTree) :-
    (   query:search(all(dependency(C, install)), Repository://Entry)
    ->  true
    ;   C = []
    ),
    (   query:search(all(dependency(R, run)), Repository://Entry)
    ->  true
    ;   R = []
    ),
    list_to_ord_set(C, OC),
    list_to_ord_set(R, OR),
    ord_intersection(OC, OR, Both, InstallOnly),
    ord_intersection(OR, OC, _, RunOnly),
    maplist(build_tree(Repository), InstallOnly, InstallTree),
    maplist(build_tree(Repository), RunOnly, RunTree),
    maplist(build_tree(Repository), Both, BothTree).


%! detail:build_tree(+Repo, +DepExpr, -Tree)
%
% Convert a raw dependency expression into a nested tree term.

build_tree(_Repo, package_dependency(_, Strength, Cat, Name, Cmpr, Ver, _, _),
           tree(pkg_dep(Strength, Cat, Name, Constraint), Candidates)) :-
    !,
    constraint_str(Cmpr, Ver, Constraint),
    findall(candidate(Ch, Inst),
            (   query:search([name(Name), category(Cat), select(version, Cmpr, Ver)],
                             _://Ch),
                (   cache:entry_metadata(_, Ch, installed, true)
                ->  Inst = true
                ;   Inst = false
                )
            ),
            Candidates0),
    sort(1, @<, Candidates0, Candidates).

build_tree(Repo, use_conditional_group(Type, Use, _, Deps),
           tree(use_cond(Type, Use), Children)) :-
    !,
    maplist(build_tree(Repo), Deps, Children).

build_tree(Repo, Group, tree(GroupType, Children)) :-
    Group =.. [GroupType, Deps],
    member(GroupType, [any_of_group, all_of_group,
                       exactly_one_of_group, at_most_one_of_group]),
    !,
    maplist(build_tree(Repo), Deps, Children).

build_tree(_, Term, tree(unknown, [])) :-
    message:warning(['detail: unknown dep expression: ', Term]).


% -----------------------------------------------------------------------------
%  Constraint formatting
% -----------------------------------------------------------------------------

%! detail:constraint_str(+Cmpr, +Ver, -Str)
%
% Format a comparator + version pair into a human-readable constraint string.

constraint_str(none, version_none, '*') :- !.
constraint_str(Cmpr, Ver, Str) :-
    cmpr_sym(Cmpr, Sym),
    ver_str(Ver, VerStr),
    atomic_list_concat([Sym, VerStr], Str).

cmpr_sym(none, '') :- !.
cmpr_sym(greater, '>') :- !.
cmpr_sym(greaterequal, '>=') :- !.
cmpr_sym(smaller, '<') :- !.
cmpr_sym(smallerequal, '<=') :- !.
cmpr_sym(equal, '=') :- !.
cmpr_sym(_, '').

ver_str(version_none, '') :- !.
ver_str(V, Full) :- compound(V), functor(V, version, 7), !, arg(7, V, Full).
ver_str(V, S) :- term_to_atom(V, S).


% -----------------------------------------------------------------------------
%  JSON tree emission
% -----------------------------------------------------------------------------

%! detail:emit_dep_data(+InstallTree, +RunTree, +BothTree)
%
% Emit depData JavaScript object with nested tree structures per phase.

emit_dep_data(InstallTree, RunTree, BothTree) :-
    write('const depData = {'), nl,
    write('  install: ['), nl,
    emit_trees_json(InstallTree),
    write('  ],'), nl,
    write('  run: ['), nl,
    emit_trees_json(RunTree),
    write('  ],'), nl,
    write('  both: ['), nl,
    emit_trees_json(BothTree),
    write('  ]'), nl,
    write('};'), nl.


emit_trees_json([]).
emit_trees_json([Tree]) :- !, write('    '), emit_tree_json(Tree), nl.
emit_trees_json([Tree|Rest]) :-
    write('    '), emit_tree_json(Tree), write(','), nl,
    emit_trees_json(Rest).


emit_tree_json(tree(use_cond(Cond, Flag), Children)) :-
    !,
    js_escape_atom(Flag, EFlag),
    format('{type:"use_cond",cond:"~w",flag:"~w",children:[', [Cond, EFlag]),
    emit_trees_json_inline(Children),
    write(']}').

emit_tree_json(tree(any_of_group, Children)) :-
    !,
    write('{type:"any_of",children:['),
    emit_trees_json_inline(Children),
    write(']}').

emit_tree_json(tree(all_of_group, Children)) :-
    !,
    write('{type:"all_of",children:['),
    emit_trees_json_inline(Children),
    write(']}').

emit_tree_json(tree(exactly_one_of_group, Children)) :-
    !,
    write('{type:"exactly_one_of",children:['),
    emit_trees_json_inline(Children),
    write(']}').

emit_tree_json(tree(at_most_one_of_group, Children)) :-
    !,
    write('{type:"at_most_one_of",children:['),
    emit_trees_json_inline(Children),
    write(']}').

emit_tree_json(tree(pkg_dep(Strength, Cat, Name, Constraint), Candidates)) :-
    !,
    js_escape_atom(Cat, ECat),
    js_escape_atom(Name, EName),
    js_escape_atom(Constraint, ECon),
    format('{type:"pkg_dep",strength:"~w",cat:"~w",name:"~w",constraint:"~w",candidates:[',
           [Strength, ECat, EName, ECon]),
    emit_candidates_json(Candidates),
    write(']}').

emit_tree_json(tree(_, _)) :-
    write('{type:"unknown",children:[]}').


emit_trees_json_inline([]).
emit_trees_json_inline([Tree]) :- !, emit_tree_json(Tree).
emit_trees_json_inline([Tree|Rest]) :-
    emit_tree_json(Tree), write(','),
    emit_trees_json_inline(Rest).


emit_candidates_json([]).
emit_candidates_json([candidate(Entry, Installed)]) :-
    !,
    js_escape_atom(Entry, EEntry),
    (Installed == true -> I = "true" ; I = "false"),
    format('{id:"~w",inst:~w}', [EEntry, I]).
emit_candidates_json([candidate(Entry, Installed)|Rest]) :-
    js_escape_atom(Entry, EEntry),
    (Installed == true -> I = "true" ; I = "false"),
    format('{id:"~w",inst:~w},', [EEntry, I]),
    emit_candidates_json(Rest).


% -----------------------------------------------------------------------------
%  HTML emission - main
% -----------------------------------------------------------------------------

%! detail:emit_html(+Target, +InstallTree, +RunTree, +BothTree)
%
% Emit a complete self-contained HTML document to the current output stream.

emit_html(Target, InstallTree, RunTree, BothTree) :-
    Target = Repo://Entry,
    cache:ordered_entry(Repo, Entry, Cat, Name, Version),
    gantt:version_str(Version, Ver),
    emit_doctype,
    emit_head_open(Cat, Name, Ver),
    emit_head_close,
    emit_body_open,
    emit_title_row(Cat, Name, Ver),
    emit_subtitle,
    deptree:version_neighbours(Repo, Entry, Newer, Newest, Older, Oldest),
    navtheme:emit_nav_bar(Repo, Entry, Cat, Name, detail, Newer, Newest, Older, Oldest),
    write('</div>'), nl,
    emit_controls_row,
    emit_tree_toolbar,
    emit_tree_container,
    emit_graph_container,
    emit_legend,
    emit_script(Repo, Entry, Cat, Name, Ver, InstallTree, RunTree, BothTree),
    navtheme:emit_theme_script('detail-theme'),
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
    format('<title>~w/~w-~w &mdash; Detail Graph</title>~n', [Cat, Name, Ver]).

emit_head_close :-
    write('</head>'), nl.

emit_body_open :-
    write('<body class="page-detail">'), nl.

emit_body_close :-
    write('</body>'), nl,
    write('</html>'), nl.


% -----------------------------------------------------------------------------
%  HTML emission - body elements
% -----------------------------------------------------------------------------

emit_title_row(Cat, Name, Ver) :-
    write('<div class="header">'), nl,
    write('<div class="title-row">'), nl,
    format('<h1>~w/~w-~w &mdash; Detail Graph</h1>~n', [Cat, Name, Ver]),
    navtheme:emit_theme_btn,
    write('</div>'), nl.

emit_subtitle :-
    write('<p class="subtitle" id="subtitle"></p>'), nl.


emit_controls_row :-
    write('<div class="controls-row">'), nl,
    write('  <div class="phase-tabs">'), nl,
    write('    <button class="phase-tab active" data-phase="install" onclick="switchPhase(\'install\',this)">Install<span class="badge" id="badge-install">0</span></button>'), nl,
    write('    <button class="phase-tab" data-phase="run" onclick="switchPhase(\'run\',this)">Run<span class="badge" id="badge-run">0</span></button>'), nl,
    write('    <button class="phase-tab" data-phase="both" onclick="switchPhase(\'both\',this)">Install &amp; Run<span class="badge" id="badge-both">0</span></button>'), nl,
    write('  </div>'), nl,
    write('  <div class="view-toggle">'), nl,
    write('    <button class="view-btn active" onclick="switchView(\'tree\',this)">&#9776; Tree</button>'), nl,
    write('    <button class="view-btn" onclick="switchView(\'graph\',this)">&#9675; Graph</button>'), nl,
    write('  </div>'), nl,
    write('</div>'), nl.


emit_tree_toolbar :-
    write('<div class="tree-toolbar" id="tree-toolbar">'), nl,
    write('  <button onclick="expandAll()">Expand All</button>'), nl,
    write('  <button onclick="collapseAll()">Collapse All</button>'), nl,
    write('  <button onclick="expandCandidates()">Show Candidates</button>'), nl,
    write('  <button onclick="collapseCandidates()">Hide Candidates</button>'), nl,
    write('</div>'), nl.


emit_tree_container :-
    write('<div class="tree-container" id="tree-container"></div>'), nl.


emit_graph_container :-
    write('<div class="graph-container" id="graph-container">'), nl,
    write('  <svg id="graph-svg" xmlns="http://www.w3.org/2000/svg"></svg>'), nl,
    write('  <div class="zoom-controls">'), nl,
    write('    <button class="zoom-btn" onclick="zoomIn()" title="Zoom in">+</button>'), nl,
    write('    <span class="zoom-level" id="zoom-level">100%</span>'), nl,
    write('    <button class="zoom-btn" onclick="zoomOut()" title="Zoom out">&minus;</button>'), nl,
    write('    <button class="zoom-btn" onclick="resetView()" title="Reset view">&#8634;</button>'), nl,
    write('  </div>'), nl,
    write('</div>'), nl.


emit_legend :-
    write('<div class="legend">'), nl,
    write('  <span class="legend-title">Legend:</span>'), nl,
    write('  <span class="legend-item"><span class="legend-swatch" style="background:var(--green-bg);border:1px solid var(--green-border)"></span> +flag</span>'), nl,
    write('  <span class="legend-item"><span class="legend-swatch" style="background:var(--red-bg);border:1px solid var(--red-border)"></span> -flag</span>'), nl,
    write('  <span class="legend-item"><span class="legend-swatch" style="background:var(--orange-bg);border:1px solid var(--orange-border)"></span> any_of</span>'), nl,
    write('  <span class="legend-item"><span class="legend-swatch" style="background:var(--blue-bg);border:1px solid var(--blue-border)"></span> all_of</span>'), nl,
    write('  <span class="legend-item"><span class="legend-swatch" style="background:var(--purple-bg);border:1px solid var(--purple-border)"></span> exactly_one_of</span>'), nl,
    write('  <span class="legend-item"><span class="legend-swatch" style="background:var(--gray-bg);border:1px solid var(--gray-border)"></span> at_most_one_of</span>'), nl,
    write('  <span class="legend-item"><span class="legend-swatch" style="background:var(--orange);border:1px solid var(--orange)"></span> weak blocker</span>'), nl,
    write('  <span class="legend-item"><span class="legend-swatch" style="background:var(--red);border:1px solid var(--red)"></span> strong blocker</span>'), nl,
    write('</div>'), nl.


% -----------------------------------------------------------------------------
%  Script emission
% -----------------------------------------------------------------------------

%! detail:emit_script(+Repo, +Entry, +Cat, +Name, +Ver, +Install, +Run, +Both)
%
% Emit the JavaScript block with data, tree view, graph view, and controls.

emit_script(Repo, Entry, Cat, Name, Ver, InstallTree, RunTree, BothTree) :-
    write('<script>'), nl,
    format('const rootLabel = "~w/~w-~w";~n', [Cat, Name, Ver]),
    format('const rootEntry = "~w";~n', [Entry]),
    format('const rootRepo = "~w";~n', [Repo]),
    emit_dep_data(InstallTree, RunTree, BothTree),
    emit_js_state,
    emit_js_helpers,
    emit_js_tree_renderer,
    emit_js_graph_renderer,
    emit_js_graph_layout,
    emit_js_graph_pan_zoom,
    emit_js_controls,
    emit_js_init,
    write('</script>'), nl.


emit_js_state :-
    write('let currentPhase = "install";'), nl,
    write('let currentView = "tree";'), nl,
    write('let gZoom = 1;'), nl,
    write('let isPanning = false, panStart = {x:0,y:0}, vbStart = {x:0,y:0};'), nl.


emit_js_helpers :-
    write('function escHTML(s) {'), nl,
    write('  if (typeof s !== "string") s = String(s);'), nl,
    write('  return s.replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;");'), nl,
    write('}'), nl,
    write('function countDeps(nodes) {'), nl,
    write('  let c = 0;'), nl,
    write('  (nodes||[]).forEach(n => { if (n.type==="pkg_dep") c++; if (n.children) c += countDeps(n.children); });'), nl,
    write('  return c;'), nl,
    write('}'), nl,
    write('function countConds(nodes) {'), nl,
    write('  let c = 0;'), nl,
    write('  (nodes||[]).forEach(n => { if (n.type==="use_cond") c++; if (n.children) c += countConds(n.children); });'), nl,
    write('  return c;'), nl,
    write('}'), nl,
    write('function countCandidates(nodes) {'), nl,
    write('  let c = 0;'), nl,
    write('  (nodes||[]).forEach(n => { if (n.candidates) c += n.candidates.length; if (n.children) c += countCandidates(n.children); });'), nl,
    write('  return c;'), nl,
    write('}'), nl,
    write('function countChildren(node) {'), nl,
    write('  if (node.type==="pkg_dep") return 0;'), nl,
    write('  return (node.children||[]).length;'), nl,
    write('}'), nl.


% -----------------------------------------------------------------------------
%  Script emission - tree view
% -----------------------------------------------------------------------------

emit_js_tree_renderer :-
    write('function renderTree() {'), nl,
    write('  const data = depData[currentPhase] || [];'), nl,
    write('  const el = document.getElementById("tree-container");'), nl,
    write('  if (!data.length) { el.innerHTML = "<div class=\\"tree-empty\\">No dependencies for this phase.</div>"; updateSubtitle(); return; }'), nl,
    write('  el.innerHTML = buildTreeHTML(data);'), nl,
    write('  updateSubtitle();'), nl,
    write('}'), nl,
    write('function updateSubtitle() {'), nl,
    write('  const data = depData[currentPhase] || [];'), nl,
    write('  const d = countDeps(data), c = countConds(data), k = countCandidates(data);'), nl,
    write('  document.getElementById("subtitle").textContent ='), nl,
    write('    d + " dependencies \\u00b7 " + c + " use conditionals \\u00b7 " + k + " candidates";'), nl,
    write('}'), nl,
    emit_js_build_tree_html,
    emit_js_tree_interaction.


emit_js_build_tree_html :-
    write('function buildTreeHTML(nodes) {'), nl,
    write('  let h = "";'), nl,
    write('  (nodes||[]).forEach(node => {'), nl,
    write('    h += "<div class=\\"tree-node\\">";'), nl,
    write('    if (node.type === "use_cond") {'), nl,
    write('      const cls = node.cond === "positive" ? "badge-use-pos" : "badge-use-neg";'), nl,
    write('      const sign = node.cond === "positive" ? "+" : "-";'), nl,
    write('      const n = countChildren(node);'), nl,
    write('      h += "<div class=\\"group-row\\" onclick=\\"toggleGroup(this)\\">";'), nl,
    write('      h += "<span class=\\"toggle-icon\\">&#9662;</span>";'), nl,
    write('      h += "<span class=\\"type-badge " + cls + "\\">" + sign + escHTML(node.flag) + "</span>";'), nl,
    write('      h += "<span class=\\"group-label\\">use_conditional</span>";'), nl,
    write('      h += "<span class=\\"group-count\\">" + n + " dep" + (n!==1?"s":"") + "</span>";'), nl,
    write('      h += "</div>";'), nl,
    write('      h += "<div class=\\"tree-children\\">" + buildTreeHTML(node.children) + "</div>";'), nl,
    write('    } else if (["any_of","all_of","exactly_one_of","at_most_one_of"].indexOf(node.type) >= 0) {'), nl,
    write('      const info = {any_of:["any of","badge-any-of","at least one required"],'), nl,
    write('                    all_of:["all of","badge-all-of","all required"],'), nl,
    write('                    exactly_one_of:["exactly one of","badge-exactly-one","exactly one required"],'), nl,
    write('                    at_most_one_of:["at most one of","badge-at-most-one","at most one required"]};'), nl,
    write('      const [label, cls, desc] = info[node.type];'), nl,
    write('      const n = (node.children||[]).length;'), nl,
    write('      h += "<div class=\\"group-row\\" onclick=\\"toggleGroup(this)\\">";'), nl,
    write('      h += "<span class=\\"toggle-icon\\">&#9662;</span>";'), nl,
    write('      h += "<span class=\\"type-badge " + cls + "\\">" + label + "</span>";'), nl,
    write('      h += "<span class=\\"group-label\\">" + desc + "</span>";'), nl,
    write('      h += "<span class=\\"group-count\\">" + n + " option" + (n!==1?"s":"") + "</span>";'), nl,
    write('      h += "</div>";'), nl,
    write('      h += "<div class=\\"tree-children\\">" + buildTreeHTML(node.children) + "</div>";'), nl,
    write('    } else if (node.type === "pkg_dep") {'), nl,
    write('      const nc = (node.candidates||[]).length;'), nl,
    write('      const firstId = nc > 0 ? node.candidates[0].id : "";'), nl,
    write('      h += "<div class=\\"pkg-row\\">";'), nl,
    write('      h += "<span class=\\"pkg-connector\\"></span>";'), nl,
    write('      h += "<span class=\\"pkg-cat\\">" + escHTML(node.cat) + "/</span>";'), nl,
    write('      h += "<span class=\\"pkg-name\\"><a href=\\"../" + firstId + "-detail.html\\">" + escHTML(node.name) + "</a></span>";'), nl,
    write('      h += "<span class=\\"pkg-constraint\\">" + escHTML(node.constraint) + "</span>";'), nl,
    write('      if (node.strength !== "no") {'), nl,
    write('        h += "<span class=\\"pkg-blocker " + node.strength + "\\">" + node.strength + " blocker</span>";'), nl,
    write('      }'), nl,
    write('      h += "<span class=\\"candidates-toggle\\" onclick=\\"toggleCandidates(this)\\">" + nc + " candidate" + (nc!==1?"s":"") + " <span class=\\"arrow\\">&#9656;</span></span>";'), nl,
    write('      h += "</div>";'), nl,
    write('      h += "<div class=\\"candidates-list\\">";'), nl,
    write('      (node.candidates||[]).forEach(c => {'), nl,
    write('        h += "<div class=\\"candidate-item\\">";'), nl,
    write('        h += "<a href=\\"../" + c.id + "-detail.html\\">" + escHTML(c.id) + "</a>";'), nl,
    write('        if (c.inst) h += " <span class=\\"candidate-installed\\">installed</span>";'), nl,
    write('        h += "</div>";'), nl,
    write('      });'), nl,
    write('      h += "</div>";'), nl,
    write('    }'), nl,
    write('    h += "</div>";'), nl,
    write('  });'), nl,
    write('  return h;'), nl,
    write('}'), nl.


emit_js_tree_interaction :-
    write('function toggleGroup(row) {'), nl,
    write('  const icon = row.querySelector(".toggle-icon");'), nl,
    write('  const ch = row.parentElement.querySelector(".tree-children");'), nl,
    write('  if (!ch) return;'), nl,
    write('  if (ch.style.display === "none") { ch.style.display = "block"; icon.classList.remove("collapsed"); }'), nl,
    write('  else { ch.style.display = "none"; icon.classList.add("collapsed"); }'), nl,
    write('}'), nl,
    write('function toggleCandidates(el) {'), nl,
    write('  const list = el.parentElement.nextElementSibling;'), nl,
    write('  if (!list || !list.classList.contains("candidates-list")) return;'), nl,
    write('  list.classList.toggle("open");'), nl,
    write('  const arrow = el.querySelector(".arrow");'), nl,
    write('  arrow.innerHTML = list.classList.contains("open") ? "&#9662;" : "&#9656;";'), nl,
    write('}'), nl,
    write('function expandAll() {'), nl,
    write('  document.querySelectorAll(".tree-children").forEach(c => c.style.display = "block");'), nl,
    write('  document.querySelectorAll(".toggle-icon").forEach(i => i.classList.remove("collapsed"));'), nl,
    write('}'), nl,
    write('function collapseAll() {'), nl,
    write('  document.querySelectorAll(".tree-children").forEach(c => c.style.display = "none");'), nl,
    write('  document.querySelectorAll(".toggle-icon").forEach(i => i.classList.add("collapsed"));'), nl,
    write('}'), nl,
    write('function expandCandidates() {'), nl,
    write('  document.querySelectorAll(".candidates-list").forEach(c => c.classList.add("open"));'), nl,
    write('  document.querySelectorAll(".candidates-toggle .arrow").forEach(a => a.innerHTML = "&#9662;");'), nl,
    write('}'), nl,
    write('function collapseCandidates() {'), nl,
    write('  document.querySelectorAll(".candidates-list").forEach(c => c.classList.remove("open"));'), nl,
    write('  document.querySelectorAll(".candidates-toggle .arrow").forEach(a => a.innerHTML = "&#9656;");'), nl,
    write('}'), nl.


% -----------------------------------------------------------------------------
%  Script emission - graph view
% -----------------------------------------------------------------------------

emit_js_graph_renderer :-
    write('const CARD_W = 160, CARD_H = 36, LAYER_X = 210, GAP_Y = 10;'), nl,
    write('const nodeColors = {'), nl,
    write('  ebuild:         {fill:"var(--blue-bg)",   stroke:"var(--accent)",  text:"var(--accent)"},'), nl,
    write('  use_cond_pos:   {fill:"var(--green-bg)",  stroke:"var(--green)",   text:"var(--green)"},'), nl,
    write('  use_cond_neg:   {fill:"var(--red-bg)",    stroke:"var(--red)",     text:"var(--red)"},'), nl,
    write('  any_of:         {fill:"var(--orange-bg)", stroke:"var(--orange)",  text:"var(--orange)"},'), nl,
    write('  all_of:         {fill:"var(--blue-bg)",   stroke:"var(--blue)",    text:"var(--blue)"},'), nl,
    write('  exactly_one_of: {fill:"var(--purple-bg)", stroke:"var(--purple)",  text:"var(--purple)"},'), nl,
    write('  at_most_one_of: {fill:"var(--gray-bg)",   stroke:"var(--gray-c)",  text:"var(--gray-c)"},'), nl,
    write('  pkg_dep:        {fill:"var(--node-bg)",   stroke:"var(--node-border)", text:"var(--text)"},'), nl,
    write('  blocker_weak:   {fill:"var(--orange-bg)", stroke:"var(--orange)",  text:"var(--orange)"},'), nl,
    write('  blocker_strong: {fill:"var(--red-bg)",    stroke:"var(--red)",     text:"var(--red)"}'), nl,
    write('};'), nl,
    write('function flattenTree(nodes, parentId, depth) {'), nl,
    write('  const flat = [], edges = [];'), nl,
    write('  (nodes||[]).forEach((node, i) => {'), nl,
    write('    const id = parentId + "_" + i;'), nl,
    write('    let nodeType = node.type;'), nl,
    write('    let label1 = "", label2 = "";'), nl,
    write('    let edgeStyle = "solid";'), nl,
    write('    if (node.type === "use_cond") {'), nl,
    write('      nodeType = node.cond === "positive" ? "use_cond_pos" : "use_cond_neg";'), nl,
    write('      label1 = (node.cond === "positive" ? "+" : "-") + node.flag;'), nl,
    write('      label2 = "use_conditional";'), nl,
    write('      edgeStyle = "dashed";'), nl,
    write('    } else if (node.type === "pkg_dep") {'), nl,
    write('      if (node.strength === "weak") nodeType = "blocker_weak";'), nl,
    write('      else if (node.strength === "strong") nodeType = "blocker_strong";'), nl,
    write('      label1 = node.cat + "/" + node.name;'), nl,
    write('      label2 = node.constraint;'), nl,
    write('    } else {'), nl,
    write('      label1 = node.type.replace(/_/g, " ");'), nl,
    write('      edgeStyle = node.type === "all_of" ? "solid" : "dotted";'), nl,
    write('    }'), nl,
    write('    flat.push({id, nodeType, label1, label2, depth});'), nl,
    write('    if (parentId !== "root") edges.push({from: parentId, to: id, style: edgeStyle});'), nl,
    write('    else edges.push({from: "root", to: id, style: "solid"});'), nl,
    write('    if (node.children) {'), nl,
    write('      const sub = flattenTree(node.children, id, depth + 1);'), nl,
    write('      flat.push(...sub.flat); edges.push(...sub.edges);'), nl,
    write('    }'), nl,
    write('  });'), nl,
    write('  return {flat, edges};'), nl,
    write('}'), nl,
    write('function renderGraph() {'), nl,
    write('  const data = depData[currentPhase] || [];'), nl,
    write('  const svg = document.getElementById("graph-svg");'), nl,
    write('  if (!data.length) { svg.innerHTML = ""; return; }'), nl,
    write('  const {flat, edges} = flattenTree(data, "root", 1);'), nl,
    write('  flat.unshift({id:"root", nodeType:"ebuild", label1:rootLabel, label2:"ebuild", depth:0});'), nl,
    write('  const positions = layoutGraph(flat, edges);'), nl,
    write('  let svgContent = "";'), nl,
    write('  edges.forEach(e => {'), nl,
    write('    const fp = positions[e.from], tp = positions[e.to];'), nl,
    write('    if (!fp || !tp) return;'), nl,
    write('    const x1 = fp.x + CARD_W, y1 = fp.y + CARD_H / 2;'), nl,
    write('    const x2 = tp.x, y2 = tp.y + CARD_H / 2;'), nl,
    write('    const mx = (x1 + x2) / 2;'), nl,
    write('    let dash = "";'), nl,
    write('    if (e.style === "dashed") dash = " stroke-dasharray=\\"6,3\\"";'), nl,
    write('    if (e.style === "dotted") dash = " stroke-dasharray=\\"2,4\\"";'), nl,
    write('    svgContent += "<path d=\\"M" + x1 + "," + y1 + " C" + mx + "," + y1 + " " + mx + "," + y2 + " " + x2 + "," + y2 + "\\"" +'), nl,
    write('      " fill=\\"none\\" stroke=\\"var(--edge-color)\\" stroke-width=\\"1.3\\"" + dash + " opacity=\\"0.5\\"/>";'), nl,
    write('    const aS = 4;'), nl,
    write('    svgContent += "<polygon points=\\"" + x2 + "," + y2 + " " + (x2-aS*1.5) + "," + (y2-aS) + " " + (x2-aS*1.5) + "," + (y2+aS) + "\\" fill=\\"var(--edge-color)\\" opacity=\\"0.5\\"/>";'), nl,
    write('  });'), nl,
    write('  flat.forEach(n => {'), nl,
    write('    const pos = positions[n.id];'), nl,
    write('    if (!pos) return;'), nl,
    write('    const c = nodeColors[n.nodeType] || nodeColors.pkg_dep;'), nl,
    write('    svgContent += "<g>";'), nl,
    write('    svgContent += "<rect x=\\"" + pos.x + "\\" y=\\"" + pos.y + "\\" width=\\"" + CARD_W + "\\" height=\\"" + CARD_H + "\\"" +'), nl,
    write('      " rx=\\"5\\" fill=\\"" + c.fill + "\\" stroke=\\"" + c.stroke + "\\" stroke-width=\\"1.5\\"/>";'), nl,
    write('    svgContent += "<text x=\\"" + (pos.x + CARD_W/2) + "\\" y=\\"" + (pos.y + 14) + "\\"" +'), nl,
    write('      " text-anchor=\\"middle\\" font-size=\\"11\\" font-weight=\\"600\\" fill=\\"" + c.text + "\\">" + escHTML(n.label1) + "</text>";'), nl,
    write('    if (n.label2) {'), nl,
    write('      svgContent += "<text x=\\"" + (pos.x + CARD_W/2) + "\\" y=\\"" + (pos.y + 27) + "\\"" +'), nl,
    write('        " text-anchor=\\"middle\\" font-size=\\"10\\" fill=\\"var(--text2)\\">" + escHTML(n.label2) + "</text>";'), nl,
    write('    }'), nl,
    write('    svgContent += "</g>";'), nl,
    write('  });'), nl,
    write('  let maxX = 0, maxY = 0;'), nl,
    write('  flat.forEach(n => { const p = positions[n.id]; if (p) { if (p.x+CARD_W > maxX) maxX = p.x+CARD_W; if (p.y+CARD_H > maxY) maxY = p.y+CARD_H; }});'), nl,
    write('  const pad = 40;'), nl,
    write('  svg.setAttribute("viewBox", (-pad) + " " + (-pad) + " " + (maxX+pad*2) + " " + (maxY+pad*2));'), nl,
    write('  svg.innerHTML = "<g id=\\"graph-g\\">" + svgContent + "</g>";'), nl,
    write('}'), nl.


emit_js_graph_layout :-
    write('function layoutGraph(nodes, edges) {'), nl,
    write('  const layers = {};'), nl,
    write('  nodes.forEach(n => { if (!layers[n.depth]) layers[n.depth] = []; layers[n.depth].push(n); });'), nl,
    write('  const childMap = {};'), nl,
    write('  nodes.forEach(n => childMap[n.id] = []);'), nl,
    write('  edges.forEach(e => { if (childMap[e.from]) childMap[e.from].push(e.to); });'), nl,
    write('  const positions = {};'), nl,
    write('  const maxDepth = Math.max(0, ...Object.keys(layers).map(Number));'), nl,
    write('  for (let d = 0; d <= maxDepth; d++) {'), nl,
    write('    const ids = layers[d] || [];'), nl,
    write('    ids.forEach((n, i) => {'), nl,
    write('      positions[n.id] = {x: d * LAYER_X + 20, y: i * (CARD_H + GAP_Y) + 20};'), nl,
    write('    });'), nl,
    write('  }'), nl,
    write('  for (let pass = 0; pass < 4; pass++) {'), nl,
    write('    for (let d = maxDepth; d >= 0; d--) {'), nl,
    write('      const ids = (layers[d]||[]);'), nl,
    write('      ids.forEach(n => {'), nl,
    write('        const ch = (childMap[n.id]||[]).filter(c => positions[c]);'), nl,
    write('        if (ch.length > 0) {'), nl,
    write('          positions[n.id].y = ch.reduce((s,c) => s + positions[c].y, 0) / ch.length;'), nl,
    write('        }'), nl,
    write('      });'), nl,
    write('      spreadLayerY(ids.map(n => n.id), positions);'), nl,
    write('    }'), nl,
    write('    for (let d = 0; d <= maxDepth; d++) {'), nl,
    write('      const ids = (layers[d]||[]);'), nl,
    write('      ids.forEach(n => {'), nl,
    write('        const ch = (childMap[n.id]||[]).filter(c => positions[c]);'), nl,
    write('        if (ch.length > 0) {'), nl,
    write('          positions[n.id].y = ch.reduce((s,c) => s + positions[c].y, 0) / ch.length;'), nl,
    write('        }'), nl,
    write('      });'), nl,
    write('      spreadLayerY(ids.map(n => n.id), positions);'), nl,
    write('    }'), nl,
    write('  }'), nl,
    write('  return positions;'), nl,
    write('}'), nl,
    write('function spreadLayerY(ids, positions) {'), nl,
    write('  if (!ids || ids.length <= 1) return;'), nl,
    write('  for (let i = 1; i < ids.length; i++) {'), nl,
    write('    const prev = positions[ids[i-1]], curr = positions[ids[i]];'), nl,
    write('    if (!prev || !curr) continue;'), nl,
    write('    const minY = prev.y + CARD_H + GAP_Y;'), nl,
    write('    if (curr.y < minY) curr.y = minY;'), nl,
    write('  }'), nl,
    write('}'), nl.


emit_js_graph_pan_zoom :-
    write('(function() {'), nl,
    write('  const container = document.getElementById("graph-container");'), nl,
    write('  const svg = document.getElementById("graph-svg");'), nl,
    write('  container.addEventListener("mousedown", e => {'), nl,
    write('    if (e.target.closest("g")) return;'), nl,
    write('    isPanning = true; panStart = {x: e.clientX, y: e.clientY};'), nl,
    write('    const vb = svg.getAttribute("viewBox");'), nl,
    write('    if (!vb) return;'), nl,
    write('    const parts = vb.split(" ").map(Number);'), nl,
    write('    vbStart = {x: parts[0], y: parts[1]};'), nl,
    write('    container.style.cursor = "grabbing";'), nl,
    write('  });'), nl,
    write('  container.addEventListener("mousemove", e => {'), nl,
    write('    if (!isPanning) return;'), nl,
    write('    const vb = svg.getAttribute("viewBox");'), nl,
    write('    if (!vb) return;'), nl,
    write('    const parts = vb.split(" ").map(Number);'), nl,
    write('    const scale = parts[2] / container.clientWidth;'), nl,
    write('    const dx = (e.clientX - panStart.x) * scale;'), nl,
    write('    const dy = (e.clientY - panStart.y) * scale;'), nl,
    write('    svg.setAttribute("viewBox", (vbStart.x - dx) + " " + (vbStart.y - dy) + " " + parts[2] + " " + parts[3]);'), nl,
    write('  });'), nl,
    write('  container.addEventListener("mouseup", () => { isPanning = false; container.style.cursor = ""; });'), nl,
    write('  container.addEventListener("mouseleave", () => { isPanning = false; container.style.cursor = ""; });'), nl,
    write('  container.addEventListener("wheel", e => {'), nl,
    write('    e.preventDefault();'), nl,
    write('    const factor = e.deltaY > 0 ? 0.9 : 1.1;'), nl,
    write('    gZoom *= factor; gZoom = Math.max(0.25, Math.min(4, gZoom));'), nl,
    write('    const vb = svg.getAttribute("viewBox");'), nl,
    write('    if (!vb) return;'), nl,
    write('    const parts = vb.split(" ").map(Number);'), nl,
    write('    const rect = container.getBoundingClientRect();'), nl,
    write('    const mx = (e.clientX - rect.left) / rect.width;'), nl,
    write('    const my = (e.clientY - rect.top) / rect.height;'), nl,
    write('    const nw = parts[2] / factor, nh = parts[3] / factor;'), nl,
    write('    const nx = parts[0] + (parts[2] - nw) * mx;'), nl,
    write('    const ny = parts[1] + (parts[3] - nh) * my;'), nl,
    write('    svg.setAttribute("viewBox", nx + " " + ny + " " + nw + " " + nh);'), nl,
    write('    document.getElementById("zoom-level").textContent = Math.round(gZoom * 100) + "%";'), nl,
    write('  }, {passive: false});'), nl,
    write('})();'), nl.


% -----------------------------------------------------------------------------
%  Script emission - controls
% -----------------------------------------------------------------------------

emit_js_controls :-
    write('function switchPhase(phase, btn) {'), nl,
    write('  currentPhase = phase;'), nl,
    write('  document.querySelectorAll(".phase-tab").forEach(t => t.classList.remove("active"));'), nl,
    write('  if (btn) btn.classList.add("active");'), nl,
    write('  if (currentView === "tree") renderTree(); else renderGraph();'), nl,
    write('}'), nl,
    write('function switchView(view, btn) {'), nl,
    write('  currentView = view;'), nl,
    write('  document.querySelectorAll(".view-btn").forEach(b => b.classList.remove("active"));'), nl,
    write('  if (btn) btn.classList.add("active");'), nl,
    write('  const treeEl = document.getElementById("tree-container");'), nl,
    write('  const toolbar = document.getElementById("tree-toolbar");'), nl,
    write('  const graphEl = document.getElementById("graph-container");'), nl,
    write('  if (view === "tree") {'), nl,
    write('    treeEl.style.display = "block"; toolbar.style.display = "flex"; graphEl.style.display = "none";'), nl,
    write('    renderTree();'), nl,
    write('  } else {'), nl,
    write('    treeEl.style.display = "none"; toolbar.style.display = "none"; graphEl.style.display = "block";'), nl,
    write('    renderGraph();'), nl,
    write('  }'), nl,
    write('}'), nl,
    write('function zoomIn() {'), nl,
    write('  gZoom = Math.min(gZoom * 1.25, 4);'), nl,
    write('  applyZoom();'), nl,
    write('}'), nl,
    write('function zoomOut() {'), nl,
    write('  gZoom = Math.max(gZoom / 1.25, 0.25);'), nl,
    write('  applyZoom();'), nl,
    write('}'), nl,
    write('function applyZoom() {'), nl,
    write('  const svg = document.getElementById("graph-svg");'), nl,
    write('  const vb = svg.getAttribute("viewBox");'), nl,
    write('  if (!vb) return;'), nl,
    write('  const parts = vb.split(" ").map(Number);'), nl,
    write('  const cx = parts[0] + parts[2] / 2, cy = parts[1] + parts[3] / 2;'), nl,
    write('  const nw = parts[2] / gZoom, nh = parts[3] / gZoom;'), nl,
    write('  svg.setAttribute("viewBox", (cx - nw/2) + " " + (cy - nh/2) + " " + nw + " " + nh);'), nl,
    write('  document.getElementById("zoom-level").textContent = Math.round(gZoom * 100) + "%";'), nl,
    write('}'), nl,
    write('function resetView() {'), nl,
    write('  gZoom = 1;'), nl,
    write('  document.getElementById("zoom-level").textContent = "100%";'), nl,
    write('  renderGraph();'), nl,
    write('}'), nl.


% -----------------------------------------------------------------------------
%  Script emission - initialisation
% -----------------------------------------------------------------------------

emit_js_init :-
    write('(function() {'), nl,
    write('  ["install","run","both"].forEach(p => {'), nl,
    write('    const el = document.getElementById("badge-" + p);'), nl,
    write('    if (el) el.textContent = countDeps(depData[p] || []);'), nl,
    write('  });'), nl,
    write('  renderTree();'), nl,
    write('})();'), nl.


% -----------------------------------------------------------------------------
%  Helpers
% -----------------------------------------------------------------------------

%! detail:js_escape_atom(+In, -Out)
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
