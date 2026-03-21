/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> INDEX
HTML index page rendering for repository, category, and package listings.
Self-contained pages with inline CSS, day/night theme toggle, and card layout.
*/

:- module(index, []).

% =============================================================================
%  INDEX declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Entry points
% -----------------------------------------------------------------------------

%! index:print_repository_index(+Repository)
%
% Print the repository index listing all categories.

index:print_repository_index(Repository) :-
    findall(Cat, cache:category(Repository, Cat), Cats),
    length(Cats, Count),
    emit_page_open(Repository, '', Count, 'categories'),
    emit_breadcrumb_repo(Repository),
    emit_grid_open,
    forall(member(Cat, Cats),
           emit_card_category(Cat)),
    emit_grid_close,
    emit_page_close.


%! index:print_category_index(+Repository, +Category)
%
% Print the category index listing all packages.

index:print_category_index(Repository, Category) :-
    findall(Name, cache:package(Repository, Category, Name), Names),
    length(Names, Count),
    atomic_list_concat([Repository, '://', Category], Title),
    emit_page_open(Title, '../', Count, 'packages'),
    emit_breadcrumb_category(Repository, Category),
    emit_grid_open,
    forall(member(Name, Names),
           emit_card_package(Name)),
    emit_grid_close,
    emit_page_close.


%! index:print_package_index(+Repository, +Category, +Name)
%
% Print the package index listing all versions with links to graph types.

index:print_package_index(Repository, Category, Name) :-
    findall(Entry-Version,
            ( cache:ordered_entry(Repository, Entry, Category, Name, Ver),
              eapi:version_full(Ver, Version)
            ),
            Pairs),
    length(Pairs, Count),
    atomic_list_concat([Repository, '://', Category, '/', Name], Title),
    emit_page_open(Title, '../', Count, 'versions'),
    emit_breadcrumb_package(Repository, Category, Name),
    emit_grid_open_vertical,
    forall(member(Entry-Version, Pairs),
           emit_card_version(Name, Entry, Version)),
    emit_grid_close,
    emit_page_close.


% -----------------------------------------------------------------------------
%  Page structure
% -----------------------------------------------------------------------------

emit_page_open(Title, _CssPrefix, Count, Unit) :-
    write('<!DOCTYPE html>'), nl,
    write('<html lang="en" data-theme="dark">'), nl,
    write('<head>'), nl,
    write('<meta charset="UTF-8">'), nl,
    write('<meta name="viewport" content="width=device-width, initial-scale=1.0">'), nl,
    format('<title>~w</title>~n', [Title]),
    emit_css,
    write('</head>'), nl,
    write('<body>'), nl,
    write('<div class="header">'), nl,
    write('<div class="title-row">'), nl,
    format('<h1>~w <span class="count">(~w ~w)</span></h1>~n', [Title, Count, Unit]),
    write('<button class="theme-btn" id="theme-btn" onclick="toggleTheme()">&#9790;</button>'), nl,
    write('</div>'), nl.

emit_page_close :-
    emit_theme_script,
    write('</body>'), nl,
    write('</html>'), nl.


% -----------------------------------------------------------------------------
%  Breadcrumb navigation
% -----------------------------------------------------------------------------

emit_breadcrumb_repo(_Repository) :-
    write('<div class="breadcrumb"></div>'), nl,
    write('</div>'), nl.

emit_breadcrumb_category(Repository, _Category) :-
    write('<div class="breadcrumb">'), nl,
    format('  <a href="../index.html">~w</a>~n', [Repository]),
    write('</div>'), nl,
    write('</div>'), nl.

emit_breadcrumb_package(Repository, Category, _Name) :-
    write('<div class="breadcrumb">'), nl,
    format('  <a href="../index.html">~w</a> <span class="sep">/</span>~n', [Repository]),
    format('  <a href="./index.html">~w</a>~n', [Category]),
    write('</div>'), nl,
    write('</div>'), nl.


% -----------------------------------------------------------------------------
%  Grid and card elements
% -----------------------------------------------------------------------------

emit_grid_open :-
    write('<div class="grid">'), nl.

emit_grid_open_vertical :-
    write('<div class="grid vertical">'), nl.

emit_grid_close :-
    write('</div>'), nl.

emit_card_category(Cat) :-
    format('<a class="card" href="./~w/index.html">~w</a>~n', [Cat, Cat]).

emit_card_package(Name) :-
    format('<a class="card" href="./~w.html">~w</a>~n', [Name, Name]).

emit_card_version(Name, Entry, Version) :-
    file_base_name(Entry, Base),
    write('<div class="card version-card">'), nl,
    format('  <a class="ver-label" href="./~w-detail.html">~w-~w</a>~n', [Base, Name, Version]),
    write('  <div class="ver-links">'), nl,
    format('    <a href="./~w-detail.html" title="detail">detail</a>~n', [Base]),
    format('    <a href="./~w-deptree.html" title="deptree">deptree</a>~n', [Base]),
    format('    <a href="./~w-gantt.html" title="gantt">gantt</a>~n', [Base]),
    format('    <a href="./~w-merge.html" title="merge">merge</a>~n', [Base]),
    format('    <a href="./~w-info.html" title="info">info</a>~n', [Base]),
    write('  </div>'), nl,
    write('</div>'), nl.


% -----------------------------------------------------------------------------
%  Inline CSS
% -----------------------------------------------------------------------------

emit_css :-
    write('<style>'), nl,
    write('  :root {'), nl,
    write('    --bg: #1e1e2e; --surface: #282840; --surface2: #313150;'), nl,
    write('    --border: #444466; --text: #e0e0f0; --text2: #a0a0c0; --text3: #777799;'), nl,
    write('    --accent: #7aa2f7; --link: #7aa2f7;'), nl,
    write('  }'), nl,
    write('  [data-theme="light"] {'), nl,
    write('    --bg: #f4f4f9; --surface: #fff; --surface2: #fafbfc;'), nl,
    write('    --border: #e0e0e0; --text: #333; --text2: #888; --text3: #bbb;'), nl,
    write('    --accent: #1565c0; --link: #1565c0;'), nl,
    write('  }'), nl,
    write('  * { box-sizing: border-box; margin: 0; padding: 0; }'), nl,
    write('  body { font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;'), nl,
    write('         background: var(--bg); color: var(--text); padding: 24px 32px; }'), nl,
    write('  .header { padding-bottom: 12px; border-bottom: 1px solid var(--border); margin-bottom: 16px; }'), nl,
    write('  .title-row { display: flex; align-items: center; justify-content: space-between; }'), nl,
    write('  h1 { font-size: 18px; font-weight: 600; }'), nl,
    write('  .count { font-weight: 400; color: var(--text2); font-size: 14px; }'), nl,
    write('  .theme-btn { background: var(--surface); border: 1px solid var(--border);'), nl,
    write('               border-radius: 6px; padding: 4px 10px; cursor: pointer;'), nl,
    write('               font-size: 14px; color: var(--text2); }'), nl,
    write('  .theme-btn:hover { background: var(--surface2); color: var(--text); }'), nl,
    write('  .breadcrumb { margin-top: 8px; font-size: 12px; color: var(--text2); }'), nl,
    write('  .breadcrumb a { color: var(--link); text-decoration: none; }'), nl,
    write('  .breadcrumb a:hover { text-decoration: underline; }'), nl,
    write('  .breadcrumb .sep { color: var(--text3); margin: 0 2px; }'), nl,
    write('  .grid { display: flex; flex-wrap: wrap; gap: 8px; }'), nl,
    write('  .grid.vertical { flex-direction: column; }'), nl,
    write('  .card { display: inline-block; padding: 8px 14px; background: var(--surface);'), nl,
    write('          border: 1px solid var(--border); border-radius: 6px;'), nl,
    write('          color: var(--text); text-decoration: none; font-size: 12px;'), nl,
    write('          transition: background 0.15s, border-color 0.15s; cursor: pointer; }'), nl,
    write('  .card:hover { background: var(--surface2); border-color: var(--accent); color: var(--accent); }'), nl,
    write('  .version-card { display: flex; align-items: center; gap: 12px; cursor: default; }'), nl,
    write('  .ver-label { font-weight: 600; min-width: 180px; font-size: 12px;'), nl,
    write('               color: var(--text); text-decoration: none; }'), nl,
    write('  .ver-label:hover { color: var(--accent); }'), nl,
    write('  .ver-links { display: flex; gap: 0; border: 1px solid var(--border);'), nl,
    write('               border-radius: 4px; overflow: hidden; }'), nl,
    write('  .ver-links a { padding: 3px 8px; color: var(--link); text-decoration: none;'), nl,
    write('                  font-size: 10px; border-right: 1px solid var(--border); }'), nl,
    write('  .ver-links a:last-child { border-right: none; }'), nl,
    write('  .ver-links a:hover { background: var(--surface2); }'), nl,
    write('</style>'), nl.


% -----------------------------------------------------------------------------
%  Theme toggle script
% -----------------------------------------------------------------------------

emit_theme_script :-
    write('<script>'), nl,
    write('function toggleTheme() {'), nl,
    write('  const html = document.documentElement;'), nl,
    write('  const cur = html.getAttribute("data-theme") || "dark";'), nl,
    write('  const next = cur === "dark" ? "light" : "dark";'), nl,
    write('  html.setAttribute("data-theme", next);'), nl,
    write('  document.getElementById("theme-btn").innerHTML = next === "light" ? "&#9788;" : "&#9790;";'), nl,
    write('  localStorage.setItem("index-theme", next);'), nl,
    write('}'), nl,
    write('(function() {'), nl,
    write('  const saved = localStorage.getItem("index-theme");'), nl,
    write('  if (saved) {'), nl,
    write('    document.documentElement.setAttribute("data-theme", saved);'), nl,
    write('    document.getElementById("theme-btn").innerHTML = saved === "light" ? "&#9788;" : "&#9790;";'), nl,
    write('  }'), nl,
    write('})();'), nl,
    write('</script>'), nl.


% -----------------------------------------------------------------------------
%  Legacy entry point (backward compatibility)
% -----------------------------------------------------------------------------

%! index:print_index(+Type, +Title, +TitleHtml, +Generator, +Template, +Stylesheet)
%
% Legacy entry point kept for backward compatibility. Delegates to the new
% type-specific predicates cannot be used directly because the new predicates
% need Repository/Category/Name context. Falls back to old XHTML rendering.

index:print_index(Type, Title, TitleHtml, Generator, Template, Stylesheet) :-
    index:print_index_header_legacy(Title, TitleHtml, Stylesheet),
    forall(Generator, index:print_index_element(Type, Template)),
    index:print_index_footer_legacy.

index:print_index_header_legacy(Title, TitleHtml, Stylesheet) :-
    writeln('<!DOCTYPE html>'),
    writeln('<html lang="en">'),
    writeln('<head>'),
    writeln('<meta charset="UTF-8">'),
    write('<title>'), write(Title), write('</title>'), nl,
    write('<link rel="stylesheet" href="'), write(Stylesheet), write('"/>'),
    writeln('</head>'),
    writeln('<body>'),
    write('<h1>'), write(TitleHtml), write('</h1>'), nl,
    writeln('<ul>').

index:print_index_footer_legacy :-
    writeln('</ul>'),
    writeln('</body>'),
    writeln('</html>').

index:print_index_element(repository, E) :-
    format('<li class="element"><a href="./~w/index.html">~w</a></li>~n', [E, E]).

index:print_index_element(category, E) :-
    format('<li class="element"><a href="./~w.html">~w</a></li>~n', [E, E]).

index:print_index_element(package, [E, V]) :-
    format('<li class="element"><a href="./~w-~w-detail.html">~w</a></li>~n', [E, V, V]).
