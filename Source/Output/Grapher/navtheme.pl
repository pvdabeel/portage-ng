/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> NAVTHEME
Shared navigation bar and day/night theme infrastructure for all graph HTML
pages. Provides a uniform two-row navigation bar, base CSS custom properties,
theme toggle button, and theme persistence JavaScript.
*/

:- module(navtheme, []).

% =============================================================================
%  NAVTHEME declarations
% =============================================================================


% -----------------------------------------------------------------------------
%  External CSS link
% -----------------------------------------------------------------------------

%! navtheme:emit_css_link(+Prefix)
%
% Emit a link element referencing the shared portage-ng.css stylesheet.
% Prefix is the relative path prefix to the graph root directory
% (e.g. '../' for category-level files, '' for root-level files).

navtheme:emit_css_link(Prefix) :-
    format('<link rel="stylesheet" href="~w.portage-ng.css">~n', [Prefix]).


% -----------------------------------------------------------------------------
%  HTML: navigation bar
% -----------------------------------------------------------------------------

%! navtheme:emit_nav_bar(+Repo, +Entry, +Cat, +Name, +ActiveType, +Newer, +Newest, +Older, +Oldest)
%
% Emit the full two-row navigation bar. Row 1 has navigation and version
% groups, row 2 has graphs, CLI, and legacy groups. ActiveType determines
% which link is highlighted and where version links point.

navtheme:emit_nav_bar(Repo, Entry, Cat, Name, ActiveType, Newer, Newest, Older, Oldest) :-
    write('<div class="nav-rows">'), nl,
    write('<div class="nav-bar">'), nl,
    emit_nav_group(Repo, Cat, Name),
    emit_version_group(Entry, ActiveType, Newer, Newest, Older, Oldest),
    write('</div>'), nl,
    write('<div class="nav-bar">'), nl,
    emit_graphs_group(Entry, ActiveType),
    emit_cli_group(Entry, ActiveType),
    emit_legacy_group(Entry, ActiveType),
    write('</div>'), nl,
    write('</div>'), nl.


emit_nav_group(Repo, Cat, Name) :-
    write('  <div class="nav-group">'), nl,
    write('    <span class="nav-group-label">nav</span>'), nl,
    format('    <a class="nav-link" href="../index.html">~w</a>~n', [Repo]),
    format('    <a class="nav-link" href="./index.html">~w</a>~n', [Cat]),
    format('    <a class="nav-link" href="./~w.html">~w</a>~n', [Name, Name]),
    write('  </div>'), nl.


emit_version_group(_Entry, ActiveType, Newer, Newest, Older, Oldest) :-
    write('  <div class="nav-group">'), nl,
    write('    <span class="nav-group-label">version</span>'), nl,
    emit_version_link(Newest, '&laquo;', ActiveType),
    emit_version_link(Newer,  '&lsaquo;', ActiveType),
    emit_version_link(Older,  '&rsaquo;', ActiveType),
    emit_version_link(Oldest, '&raquo;', ActiveType),
    write('  </div>'), nl.


emit_graphs_group(Entry, ActiveType) :-
    write('  <div class="nav-group">'), nl,
    write('    <span class="nav-group-label">graphs</span>'), nl,
    emit_type_link(Entry, detail,  detail,  ActiveType),
    emit_type_link(Entry, deptree, deptree, ActiveType),
    emit_type_link(Entry, gantt,   gantt,   ActiveType),
    write('  </div>'), nl.


emit_cli_group(Entry, ActiveType) :-
    write('  <div class="nav-group">'), nl,
    write('    <span class="nav-group-label">cli</span>'), nl,
    emit_type_link(Entry, merge,    '--merge',    ActiveType),
    emit_type_link(Entry, fetchonly, '--fetchonly', ActiveType),
    emit_type_link(Entry, info,     '--info',     ActiveType),
    write('  </div>'), nl.


emit_legacy_group(Entry, ActiveType) :-
    write('  <div class="nav-group">'), nl,
    write('    <span class="nav-group-label">legacy</span>'), nl,
    emit_type_link(Entry, emerge, emerge, ActiveType),
    write('  </div>'), nl.


%! navtheme:emit_type_link(+Entry, +Type, +Label, +ActiveType)
%
% Emit a navigation link. Active when Type == ActiveType.

emit_type_link(_Entry, Type, Label, Type) :-
    !,
    format('    <a class="nav-link active">~w</a>~n', [Label]).

emit_type_link(Entry, Type, Label, _) :-
    format('    <a class="nav-link" href="../~w-~w.html">~w</a>~n',
           [Entry, Type, Label]).


%! navtheme:emit_version_link(+Entry, +Label, +Type)
%
% Emit a version navigation link. Disabled when Entry is empty.

emit_version_link('', Label, _) :-
    !,
    format('    <a class="nav-link disabled">~w</a>~n', [Label]).

emit_version_link(Entry, Label, Type) :-
    format('    <a class="nav-link" href="../~w-~w.html" title="~w">~w</a>~n',
           [Entry, Type, Entry, Label]).


% -----------------------------------------------------------------------------
%  HTML: theme toggle button
% -----------------------------------------------------------------------------

%! navtheme:emit_theme_btn
%
% Emit the day/night theme toggle button.

navtheme:emit_theme_btn :-
    write('<button class="theme-btn" id="theme-btn" onclick="toggleTheme()">&#9790;</button>'), nl.


% -----------------------------------------------------------------------------
%  JavaScript: theme toggle and persistence
% -----------------------------------------------------------------------------

%! navtheme:emit_theme_script(+StorageKey)
%
% Emit the theme toggle JavaScript with localStorage persistence under the
% given key.

navtheme:emit_theme_script(StorageKey) :-
    write('<script>'), nl,
    write('function toggleTheme() {'), nl,
    write('  const html = document.documentElement;'), nl,
    write('  const cur = html.getAttribute("data-theme") || "dark";'), nl,
    write('  const next = cur === "dark" ? "light" : "dark";'), nl,
    write('  html.setAttribute("data-theme", next);'), nl,
    write('  document.getElementById("theme-btn").innerHTML = next === "light" ? "&#9788;" : "&#9790;";'), nl,
    format('  localStorage.setItem("~w", next);~n', [StorageKey]),
    write('}'), nl,
    write('(function() {'), nl,
    format('  const saved = localStorage.getItem("~w");~n', [StorageKey]),
    write('  if (saved) {'), nl,
    write('    document.documentElement.setAttribute("data-theme", saved);'), nl,
    write('    document.getElementById("theme-btn").innerHTML = saved === "light" ? "&#9788;" : "&#9790;";'), nl,
    write('  }'), nl,
    write('})();'), nl,
    write('</script>'), nl.
