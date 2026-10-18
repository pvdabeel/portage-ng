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
% Collect dependency expression trees by phase. Install and Run are the
% full trees for that phase. Both is the intersection: expressions
% declared in install *and* run (phase slot ignored so DEPEND and
% RDEPEND copies of the same atom match).

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
    maplist(phase_neutral, OC, NeutralC0),
    maplist(phase_neutral, OR, NeutralR0),
    list_to_ord_set(NeutralC0, NeutralC),
    list_to_ord_set(NeutralR0, NeutralR),
    ord_intersection(NeutralC, NeutralR, Both),
    maplist(build_tree(Repository), OC, InstallTree),
    maplist(build_tree(Repository), OR, RunTree),
    maplist(build_tree(Repository), Both, BothTree).


%! detail:phase_neutral(+Dep, -Neutral) is det.
%
% Drop the parse-phase argument of package_dependency/8 (install vs run)
% and the parent ebuild slot of use_conditional_group/4 so the same
% declared atom compares equal across phases.

phase_neutral(package_dependency(_, B, C, P, Op, V, S, U),
              package_dependency(any, B, C, P, Op, V, S, U)) :- !.
phase_neutral(use_conditional_group(Pol, Use, _, Deps),
              use_conditional_group(Pol, Use, any, Neutral)) :-
  !,
  maplist(phase_neutral, Deps, Neutral).
phase_neutral(Term, Neutral) :-
  Term =.. [Functor, Deps],
  memberchk(Functor, [any_of_group, all_of_group,
                      exactly_one_of_group, at_most_one_of_group]),
  !,
  maplist(phase_neutral, Deps, NeutralDeps),
  Neutral =.. [Functor, NeutralDeps].
phase_neutral(Term, Term).


%! detail:build_tree(+Repo, +DepExpr, -Tree)
%
% Convert a raw dependency expression into a nested tree term.

build_tree(_Repo, package_dependency(_, Strength, Cat, Name, Cmpr, Ver, _, _),
           tree(pkg_dep(Strength, Cat, Name, Constraint), Candidates)) :-
    !,
    constraint_str(Cmpr, Ver, Constraint),
    findall(CandVer-candidate(Ch, Inst),
            (   query:search([name(Name), category(Cat), select(version, Cmpr, Ver)],
                             _://Ch),
                cache:ordered_entry(_, Ch, _, _, CandVer),
                (   cache:ordered_entry(pkg, Ch, _, _, _)
                ->  Inst = true
                ;   Inst = false
                )
            ),
            Pairs0),
    sort(1, @>=, Pairs0, PairsSorted),
    dedupe_candidate_pairs_by_entry(PairsSorted, Pairs),
    pairs_values(Pairs, Candidates).

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


%! detail:dedupe_candidate_pairs_by_entry(+PairsSorted, -UniquePairs)
%
% Pairs are CandVer-candidate(Entry, Inst), sorted with newest version first.
% query:search/2 may yield the same Entry multiple times; keep the first
% occurrence per Entry so the detail tree lists each candidate once.

dedupe_candidate_pairs_by_entry(Pairs, Unique) :-
    dedupe_candidate_pairs_by_entry(Pairs, [], Unique).

dedupe_candidate_pairs_by_entry([], _, []).
dedupe_candidate_pairs_by_entry([Pair|Rest], Seen, Out) :-
    Pair = _-candidate(Ch, _),
    (   memberchk(Ch, Seen)
    ->  dedupe_candidate_pairs_by_entry(Rest, Seen, Out)
    ;   Out = [Pair|Out0],
        dedupe_candidate_pairs_by_entry(Rest, [Ch|Seen], Out0)
    ).


% -----------------------------------------------------------------------------
%  Constraint formatting
% -----------------------------------------------------------------------------

%! detail:constraint_str(+Cmpr, +Ver, -Str)
%
% Format a comparator + version pair into a human-readable constraint string.

constraint_str(none, version_none, '*') :- !.
constraint_str(Cmpr, Ver, Str) :-
    eapi:comparator_symbol(Cmpr, Sym),
    version_domain:display_atom(Ver, VerStr),
    atomic_list_concat([Sym, VerStr], Str).


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
    navtheme:js_escape_atom(Flag, EFlag),
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
    navtheme:js_escape_atom(Cat, ECat),
    navtheme:js_escape_atom(Name, EName),
    navtheme:js_escape_atom(Constraint, ECon),
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
    navtheme:js_escape_atom(Entry, EEntry),
    (Installed == true -> I = "true" ; I = "false"),
    format('{id:"~w",inst:~w}', [EEntry, I]).
emit_candidates_json([candidate(Entry, Installed)|Rest]) :-
    navtheme:js_escape_atom(Entry, EEntry),
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
    version_domain:display_atom(Version, Ver),
    format(atom(Title), '~w/~w-~w — Detail Graph', [Cat, Name, Ver]),
    navtheme:emit_doctype,
    navtheme:emit_head_open(Title, '../'),
    navtheme:emit_head_close,
    navtheme:emit_body_open('page-detail'),
    navtheme:emit_top_bar('../', Repo, Cat, Name, Ver),
    navtheme:emit_main_open,
    navtheme:emit_page_head_open,
    emit_subtitle,
    deptree:version_neighbours(Repo, Entry, Newer, Newest, Older, Oldest),
    navtheme:emit_nav_bar(Repo, Entry, Cat, Name, detail, Newer, Newest, Older, Oldest, Ver),
    navtheme:emit_page_head_close,
    navtheme:emit_term_open('portage-ng detail'),
    emit_controls_row,
    emit_tree_toolbar,
    emit_tree_container,
    emit_graph_container,
    emit_legend,
    navtheme:emit_term_close,
    emit_script(Repo, Entry, Cat, Name, Ver, InstallTree, RunTree, BothTree),
    navtheme:emit_main_close,
    navtheme:emit_theme_script,
    navtheme:emit_body_close.


% -----------------------------------------------------------------------------
%  HTML emission - body elements
% -----------------------------------------------------------------------------

emit_subtitle :-
    write('<p class="subtitle" id="subtitle"></p>'), nl.


emit_controls_row :-
    write('<div class="controls-row">'), nl,
    write('  <div class="phase-tabs">'), nl,
    write('    <button class="phase-tab active" data-phase="install" onclick="switchPhase(\'install\',this)" title="DEPEND, BDEPEND, CDEPEND">Install<span class="badge" id="badge-install">0</span></button>'), nl,
    write('    <button class="phase-tab" data-phase="run" onclick="switchPhase(\'run\',this)" title="RDEPEND, IDEPEND">Run<span class="badge" id="badge-run">0</span></button>'), nl,
    write('    <button class="phase-tab" data-phase="both" onclick="switchPhase(\'both\',this)" title="Declared in both install and run">Both<span class="badge" id="badge-both">0</span></button>'), nl,
    write('  </div>'), nl,
    write('  <div class="view-toggle">'), nl,
    write('    <button class="view-btn" onclick="switchView(\'tree\',this)">&#9776; Metadata</button>'), nl,
    write('    <button class="view-btn active" onclick="switchView(\'graph\',this)">&#9675; Graph</button>'), nl,
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
    write('  <span class="legend-item"><span class="legend-swatch" style="background:var(--surface2);border:1px solid var(--border2)"></span> candidate</span>'), nl,
    write('  <span class="legend-item"><span class="legend-swatch" style="background:var(--green-bg);border:1px solid var(--green-border)"></span> installed</span>'), nl,
    write('</div>'), nl.


% -----------------------------------------------------------------------------
%  Script emission
% -----------------------------------------------------------------------------

%! detail:emit_script(+Repo, +Entry, +Cat, +Name, +Ver, +Install, +Run, +Both)
%
% Emit the page data (root labels and dependency trees, escaped) in an
% inline block, then the external script element for the verbatim
% detail.js asset (state, renderers, layout, controls, init).

emit_script(_Repo, _Entry, Cat, Name, Ver, InstallTree, RunTree, BothTree) :-
    format(atom(RootLabel), '~w/~w-~w', [Cat, Name, Ver]),
    navtheme:js_escape_atom(RootLabel, RootLabelE),
    write('<script>'), nl,
    format('const rootLabel = "~w";~n', [RootLabelE]),
    emit_dep_data(InstallTree, RunTree, BothTree),
    write('</script>'), nl,
    navtheme:emit_script_src('../', detail).
