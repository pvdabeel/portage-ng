/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> NAVTHEME
Handbook-style chrome for all graph HTML pages: brand + crumb top bar,
png-theme persistence, and in-page type/version tab bars.
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
%  HTML: document scaffolding
% -----------------------------------------------------------------------------

%! navtheme:emit_doctype is det.
%
% Emit the HTML5 doctype declaration.

navtheme:emit_doctype :-
    write('<!DOCTYPE html>'), nl.


%! navtheme:emit_head_open(+Title, +Prefix) is det.
%
% Emit the opening <html>/<head> elements: light-theme default, FOUC +
% embed script, title, and the shared CSS link at Prefix.

navtheme:emit_head_open(Title, Prefix) :-
    write('<html lang="en" data-theme="light">'), nl,
    write('<head>'), nl,
    write('<meta charset="UTF-8">'), nl,
    write('<meta name="viewport" content="width=device-width, initial-scale=1.0">'), nl,
    write('<script>try{if(window.parent!==window)document.documentElement.classList.add("embedded");if(localStorage.getItem("png-theme")==="dark")document.documentElement.removeAttribute("data-theme")}catch(e){}</script>'), nl,
    format('<title>~w</title>~n', [Title]),
    navtheme:emit_css_link(Prefix).


%! navtheme:emit_head_close is det.
%
% Emit the closing </head> tag.

navtheme:emit_head_close :-
    write('</head>'), nl.


%! navtheme:emit_body_open(+PageClass) is det.
%
% Emit the opening <body> tag carrying the given page class.

navtheme:emit_body_open(PageClass) :-
    format('<body class="~w">~n', [PageClass]).


%! navtheme:emit_body_close is det.
%
% Emit the closing </body>/</html> tags.

navtheme:emit_body_close :-
    write('</body>'), nl,
    write('</html>'), nl.


%! navtheme:emit_main_open is det.
%
% Emit the opening wrapper for in-page content below the top bar.

navtheme:emit_main_open :-
    write('<div class="graph-main">'), nl.


%! navtheme:emit_main_close is det.
%
% Emit the closing wrapper for in-page content.

navtheme:emit_main_close :-
    write('</div>'), nl.


% -----------------------------------------------------------------------------
%  HTML: handbook top bar
% -----------------------------------------------------------------------------

%! navtheme:emit_top_bar(+Prefix, +Repo, +Cat, +Name) is det.
%
% Emit the fixed brand + crumb + theme-toggle bar. The clocking mark
% links to https://portage-ng.ai. Cat and Name may be '' on repository
% and category index pages. Prefix is the relative path to the repository
% index ('' at repo root, '../' in a category directory).

navtheme:emit_top_bar(Prefix, Repo, Cat, Name) :-
    navtheme:emit_top_bar(Prefix, Repo, Cat, Name, '').


%! navtheme:emit_top_bar(+Prefix, +Repo, +Cat, +Name, +Ver) is det.
%
% As emit_top_bar/4, with Ver the ebuild version shown as the last crumb
% ('' omits it — index pages).

navtheme:emit_top_bar(Prefix, Repo, Cat, Name, Ver) :-
    navtheme:html_escape(Repo, RepoE),
    write('<header class="docs-top">'), nl,
    write('  <a class="brand" href="https://portage-ng.ai">'),
    emit_brand_svg,
    write(' portage-ng</a>'), nl,
    write('  <span class="crumb">'), nl,
    emit_crumb(Prefix, RepoE, Cat, Name, Ver),
    write('  </span>'), nl,
    write('  <div class="top-right">'), nl,
    emit_theme_toggle,
    write('  </div>'), nl,
    write('</header>'), nl.


%! navtheme:emit_crumb(+Prefix, +RepoEscaped, +Cat, +Name, +Ver) is det.
%
% Emit the mono crumb trail. Earlier segments are links; the last is
% the current page. Ver, when non-empty, is the current segment so the
% package name stays a link to the package index.

navtheme:emit_crumb(_Prefix, RepoE, '', '', _) :-
    !,
    write('    <span class="crumb-sep">/</span>'), nl,
    format('    <span class="crumb-current">~w</span>~n', [RepoE]).
navtheme:emit_crumb(Prefix, RepoE, Cat, '', _) :-
    !,
    navtheme:html_escape(Cat, CatE),
    write('    <span class="crumb-sep">/</span>'), nl,
    format('    <a href="~windex.html">~w</a>~n', [Prefix, RepoE]),
    write('    <span class="crumb-sep">/</span>'), nl,
    format('    <span class="crumb-current">~w</span>~n', [CatE]).
navtheme:emit_crumb(Prefix, RepoE, Cat, Name, '') :-
    !,
    navtheme:html_escape(Cat, CatE),
    navtheme:html_escape(Name, NameE),
    write('    <span class="crumb-sep">/</span>'), nl,
    format('    <a href="~windex.html">~w</a>~n', [Prefix, RepoE]),
    write('    <span class="crumb-sep">/</span>'), nl,
    format('    <a href="./index.html">~w</a>~n', [CatE]),
    write('    <span class="crumb-sep">/</span>'), nl,
    format('    <span class="crumb-current">~w</span>~n', [NameE]).
navtheme:emit_crumb(Prefix, RepoE, Cat, Name, Ver) :-
    navtheme:html_escape(Cat, CatE),
    navtheme:html_escape(Name, NameE),
    navtheme:html_escape(Ver, VerE),
    write('    <span class="crumb-sep">/</span>'), nl,
    format('    <a href="~windex.html">~w</a>~n', [Prefix, RepoE]),
    write('    <span class="crumb-sep">/</span>'), nl,
    format('    <a href="./index.html">~w</a>~n', [CatE]),
    write('    <span class="crumb-sep">/</span>'), nl,
    format('    <a href="./~w.html">~w</a>~n', [NameE, NameE]),
    write('    <span class="crumb-sep">/</span>'), nl,
    format('    <span class="crumb-current">~w</span>~n', [VerE]).


%! navtheme:emit_brand_svg is det.
%
% Emit the four-dot portage-ng brand mark.

navtheme:emit_brand_svg :-
    write('<svg viewBox="0 0 64 64" aria-hidden="true"><rect width="64" height="64" rx="14" fill="#161a26"/><circle cx="17" cy="23.5" r="5" fill="#a78bfa"/><circle cx="17" cy="40.5" r="5" fill="#a78bfa"/><circle cx="31.5" cy="23.5" r="5" fill="#a78bfa"/><circle cx="31.5" cy="40.5" r="5" fill="#a78bfa"/><rect x="41" y="28.75" width="14.5" height="6.5" rx="3.25" fill="#4ade80"/></svg>').


%! navtheme:emit_theme_toggle is det.
%
% Emit the handbook sun/moon theme button.

navtheme:emit_theme_toggle :-
    write('    <button class="theme-toggle" id="themeToggle" aria-label="Switch between dark and light theme" title="Toggle theme" onclick="toggleTheme()">'), nl,
    write('      <svg class="icon-sun" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41"/></svg>'), nl,
    write('      <svg class="icon-moon" viewBox="0 0 24 24" aria-hidden="true"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>'), nl,
    write('    </button>'), nl.


% -----------------------------------------------------------------------------
%  HTML: in-page type / version tabs
% -----------------------------------------------------------------------------

%! navtheme:emit_page_head_open is det.
%
% Open the page-head band that holds the subtitle and in-page tabs on one row.

navtheme:emit_page_head_open :-
    write('<div class="page-head">'), nl.


%! navtheme:emit_page_head_close is det.
%
% Close the page-head band.

navtheme:emit_page_head_close :-
    write('</div>'), nl.


% -----------------------------------------------------------------------------
%  HTML: handbook hero window
% -----------------------------------------------------------------------------

%! navtheme:emit_term_open(+Title) is det.
%
% Open the handbook hero window: traffic-light bar titled Title, then
% a term-body wrapper for the page content.

navtheme:emit_term_open(Title) :-
    write('<div class="term">'), nl,
    write('  <div class="term-bar">'), nl,
    write('    <span class="term-dot r"></span>'),
    write('<span class="term-dot y"></span>'),
    write('<span class="term-dot g"></span>'), nl,
    format('    <span class="term-title">~w</span>~n', [Title]),
    write('  </div>'), nl,
    write('  <div class="term-body">'), nl.


%! navtheme:emit_term_close is det.
%
% Close the handbook hero window.

navtheme:emit_term_close :-
    write('  </div>'), nl,
    write('</div>'), nl.


%! navtheme:emit_nav_bar(+Repo, +Entry, +Cat, +Name, +ActiveType, +Newer, +Newest, +Older, +Oldest)
%
% Emit the in-page tab bar: version, graph types, CLI, security, and
% legacy in one wrapping row. Repo/Cat/Name live in the top-bar crumb.

navtheme:emit_nav_bar(Repo, Entry, Cat, Name, ActiveType, Newer, Newest, Older, Oldest) :-
    navtheme:emit_nav_bar(Repo, Entry, Cat, Name, ActiveType, Newer, Newest, Older, Oldest, '').


%! navtheme:emit_nav_bar(+Repo, +Entry, +Cat, +Name, +ActiveType, +Newer, +Newest, +Older, +Oldest, +Ver)
%
% As emit_nav_bar/9, with Ver shown between the version arrows.

navtheme:emit_nav_bar(Repo, Entry, Cat, Name, ActiveType, Newer, Newest, Older, Oldest, Ver) :-
    write('<div class="nav-rows">'), nl,
    write('<div class="nav-bar">'), nl,
    emit_version_group(Entry, ActiveType, Newer, Newest, Older, Oldest, Ver),
    emit_graphs_group(Entry, ActiveType),
    emit_cli_group(Entry, ActiveType),
    emit_security_group(Repo, Entry, Cat, Name, ActiveType),
    emit_legacy_group(Entry, ActiveType),
    write('</div>'), nl,
    write('</div>'), nl.


%! navtheme:emit_version_group(+Entry, +ActiveType, +Newer, +Newest, +Older, +Oldest, +Ver) is det.
%
% Emit the version navigation group: newest/newer, the current version,
% older/oldest.

navtheme:emit_version_group(_Entry, ActiveType, Newer, Newest, Older, Oldest, Ver) :-
    write('  <div class="nav-group">'), nl,
    write('    <span class="nav-group-label">version</span>'), nl,
    emit_version_link(Newest, '&laquo;', ActiveType),
    emit_version_link(Newer,  '&lsaquo;', ActiveType),
    emit_version_current(Ver),
    emit_version_link(Older,  '&rsaquo;', ActiveType),
    emit_version_link(Oldest, '&raquo;', ActiveType),
    write('  </div>'), nl.


%! navtheme:emit_version_current(+Ver) is det.
%
% Emit the current ebuild version in the version tab group.

navtheme:emit_version_current('') :- !.
navtheme:emit_version_current(Ver) :-
    navtheme:html_escape(Ver, VerE),
    format('    <span class="nav-link active">~w</span>~n', [VerE]).


%! navtheme:emit_graphs_group(+Entry, +ActiveType) is det.
%
% Emit the graphs navigation group with detail, deptree, and gantt links.

navtheme:emit_graphs_group(Entry, ActiveType) :-
    write('  <div class="nav-group">'), nl,
    write('    <span class="nav-group-label">graphs</span>'), nl,
    emit_type_link(Entry, detail,  detail,  ActiveType),
    emit_type_link(Entry, deptree, deptree, ActiveType),
    emit_type_link(Entry, gantt,   gantt,   ActiveType),
    write('  </div>'), nl.


%! navtheme:emit_cli_group(+Entry, +ActiveType) is det.
%
% Emit the CLI navigation group with merge, fetchonly, and info links.

navtheme:emit_cli_group(Entry, ActiveType) :-
    write('  <div class="nav-group">'), nl,
    write('    <span class="nav-group-label">cli</span>'), nl,
    emit_type_link(Entry, merge,    '--merge',    ActiveType),
    emit_type_link(Entry, fetchonly, '--fetchonly', ActiveType),
    emit_type_link(Entry, info,     '--info',     ActiveType),
    write('  </div>'), nl.


%! navtheme:emit_security_group(+Repo, +Entry, +Cat, +Name, +ActiveType) is det.
%
% Emit the security navigation group with the glsa link. The link
% carries a count pill when advisories reference Cat/Name; the pill is
% marked `affected` when one of them places this Entry in a vulnerable
% range.

navtheme:emit_security_group(Repo, Entry, Cat, Name, ActiveType) :-
    write('  <div class="nav-group">'), nl,
    write('    <span class="nav-group-label">security</span>'), nl,
    navtheme:glsa_badge(Repo, Entry, Cat, Name, Badge),
    atom_concat(glsa, Badge, Label),
    emit_type_link(Entry, glsa, Label, ActiveType),
    write('  </div>'), nl.


%! navtheme:glsa_badge(+Repo, +Entry, +Cat, +Name, -Badge) is det.
%
% Badge is '' when no advisory references Cat/Name, else a leading
% space plus the count pill markup. Any failure in the GLSA store
% (no cache, no tree) degrades to no badge.

navtheme:glsa_badge(Repo, Entry, Cat, Name, Badge) :-
    (   catch(glsa:package_advisories(Cat, Name, Ids), _, fail),
        Ids \== []
    ->  length(Ids, N),
        (   member(Id, Ids),
            catch(glsa:entry_covered(Id, Repo://Entry), _, fail)
        ->  Cls = 'nav-badge affected'
        ;   Cls = 'nav-badge'
        ),
        format(atom(Badge), ' <span class="~w">~w</span>', [Cls, N])
    ;   Badge = ''
    ).


%! navtheme:emit_legacy_group(+Entry, +ActiveType) is det.
%
% Emit the legacy navigation group with emerge link.

navtheme:emit_legacy_group(Entry, ActiveType) :-
    write('  <div class="nav-group">'), nl,
    write('    <span class="nav-group-label">legacy</span>'), nl,
    emit_type_link(Entry, emerge, emerge, ActiveType),
    write('  </div>'), nl.


%! navtheme:emit_type_link(+Entry, +Type, +Label, +ActiveType)
%
% Emit a navigation link. Active when Type == ActiveType.

navtheme:emit_type_link(_Entry, Type, Label, Type) :-
    !,
    format('    <a class="nav-link active">~w</a>~n', [Label]).
navtheme:emit_type_link(Entry, Type, Label, _) :-
    format('    <a class="nav-link" href="../~w-~w.html">~w</a>~n',
           [Entry, Type, Label]).


%! navtheme:emit_version_link(+Entry, +Label, +Type)
%
% Emit a version navigation link. Disabled when Entry is empty.

navtheme:emit_version_link('', Label, _) :-
    !,
    format('    <a class="nav-link disabled">~w</a>~n', [Label]).
navtheme:emit_version_link(Entry, Label, Type) :-
    format('    <a class="nav-link" href="../~w-~w.html" title="~w">~w</a>~n',
           [Entry, Type, Entry, Label]).


% -----------------------------------------------------------------------------
%  JavaScript: theme toggle and persistence
% -----------------------------------------------------------------------------

%! navtheme:emit_theme_script is det.
%
% Emit the png-theme toggle. Light sets data-theme="light"; dark removes
% the attribute, matching the handbook contract.

navtheme:emit_theme_script :-
    write('<script>'), nl,
    write('function toggleTheme() {'), nl,
    write('  const html = document.documentElement;'), nl,
    write('  const light = html.getAttribute("data-theme") === "light";'), nl,
    write('  if (light) html.removeAttribute("data-theme");'), nl,
    write('  else html.setAttribute("data-theme", "light");'), nl,
    write('  try { localStorage.setItem("png-theme", light ? "dark" : "light"); } catch (e) {}'), nl,
    write('}'), nl,
    write('</script>'), nl.


% -----------------------------------------------------------------------------
%  Escaping helpers
% -----------------------------------------------------------------------------
%
% Shared by every grapher that embeds package data in generated HTML or
% inline JavaScript.

%! navtheme:html_escape(+In, -Out) is det.
%
% Escape the HTML special characters (< > & ") of an atom.

navtheme:html_escape(In, Out) :-
    atom_codes(In, Codes),
    navtheme:html_escape_codes(Codes, OutCodes),
    atom_codes(Out, OutCodes).


%! navtheme:html_escape_codes(+Codes, -Escaped) is det.
%
% html_escape/2 on a code list.

navtheme:html_escape_codes([], []).
navtheme:html_escape_codes([C|T], Out) :-
    navtheme:html_escape_code(C, Esc),
    append(Esc, R, Out),
    navtheme:html_escape_codes(T, R).


%! navtheme:html_escape_code(+Code, -Codes) is det.
%
% The HTML entity (as a code list) for one character code; the character
% itself when it needs no escaping.

navtheme:html_escape_code(0'<, `&lt;`)   :- !.
navtheme:html_escape_code(0'>, `&gt;`)   :- !.
navtheme:html_escape_code(0'&, `&amp;`)  :- !.
navtheme:html_escape_code(0'", `&quot;`) :- !.
navtheme:html_escape_code(C, [C]).


%! navtheme:js_escape_atom(+In, -Out) is det.
%
% Escape an atom for safe embedding in a double-quoted JavaScript string
% literal.

navtheme:js_escape_atom(In, Out) :-
    atom_codes(In, Codes),
    navtheme:js_escape_codes(Codes, OutCodes),
    atom_codes(Out, OutCodes).


navtheme:js_escape_codes([], []).
navtheme:js_escape_codes([0'\\|T], [0'\\, 0'\\ |R]) :- !, navtheme:js_escape_codes(T, R).
navtheme:js_escape_codes([0'"|T],  [0'\\, 0'" |R])  :- !, navtheme:js_escape_codes(T, R).
navtheme:js_escape_codes([0'\n|T], [0'\\, 0'n |R])  :- !, navtheme:js_escape_codes(T, R).
navtheme:js_escape_codes([0'\r|T], [0'\\, 0'r |R])  :- !, navtheme:js_escape_codes(T, R).
navtheme:js_escape_codes([H|T], [H|R]) :- navtheme:js_escape_codes(T, R).
