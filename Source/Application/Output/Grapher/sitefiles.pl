/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> SITEFILES
404, robots.txt and sitemap.xml for the ebuild graph site.

Written into the repository graph directory by `--graph` (via
`repository:prepare_directory/1` → `sitefiles:write_site_files/2`) so
the public origin (`config:graph_site_url/1`, default
https://ebuild.portage-ng.ai) can serve them as static files.
*/

:- module(sitefiles, []).

% =============================================================================
%  SITEFILES declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Public entry
% -----------------------------------------------------------------------------

%! sitefiles:write_site_files(+Directory, +Repository) is det.
%
% Write 404.html, robots.txt and the sitemap set into Directory.

sitefiles:write_site_files(Directory, Repository) :-
    catch(sitefiles:do_write(Directory, Repository), E,
          ( term_to_atom(E, EA),
            message:warning(['Failed to write graph site files (', EA, ')'])
          )).


%! sitefiles:do_write(+Directory, +Repository) is det.
%
% Uncaught write of the site files.

sitefiles:do_write(Directory, Repository) :-
    sitefiles:site_url(Url),
    sitefiles:write_file(Directory, '404.html', sitefiles:emit_404),
    sitefiles:write_file(Directory, 'robots.txt', sitefiles:emit_robots(Url)),
    sitefiles:write_sitemaps(Directory, Repository, Url).


%! sitefiles:site_url(-Url) is det.
%
% Public graph origin with no trailing slash.

sitefiles:site_url(Url) :-
    (   current_predicate(config:graph_site_url/1),
        config:graph_site_url(Raw)
    ->  sitefiles:strip_slash(Raw, Url)
    ;   Url = 'https://ebuild.portage-ng.ai'
    ).


%! sitefiles:strip_slash(+Raw, -Url) is det.
%
% Drop a single trailing slash from Raw.

sitefiles:strip_slash(Raw, Url) :-
    atom_concat(Prefix, '/', Raw),
    Prefix \== '',
    !,
    Url = Prefix.
sitefiles:strip_slash(Url, Url).


% -----------------------------------------------------------------------------
%  File helper
% -----------------------------------------------------------------------------

%! sitefiles:write_file(+Directory, +Name, :Goal) is det.
%
% Open Directory/Name for write and call Goal with output directed there.

sitefiles:write_file(Directory, Name, Goal) :-
    os:compose_path(Directory, Name, Path),
    setup_call_cleanup(
        open(Path, write, S),
        with_output_to(S, Goal),
        close(S)).


% -----------------------------------------------------------------------------
%  404 page
% -----------------------------------------------------------------------------

%! sitefiles:emit_404 is det.
%
% Emit the handbook-style 404 page (prove/assumption snippet).
% <base href="/"> keeps CSS and homepage links valid when the server
% serves this file for a missing URL at any depth.

sitefiles:emit_404 :-
    write('<!DOCTYPE html>'), nl,
    write('<html lang="en" data-theme="light">'), nl,
    write('<head>'), nl,
    write('<meta charset="UTF-8">'), nl,
    write('<meta name="viewport" content="width=device-width, initial-scale=1.0">'), nl,
    write('<meta name="robots" content="noindex">'), nl,
    write('<script>try{if(localStorage.getItem("png-theme")==="dark")document.documentElement.removeAttribute("data-theme")}catch(e){}</script>'), nl,
    write('<base href="/">'), nl,
    write('<title>404 — portage-ng</title>'), nl,
    write('<link rel="icon" type="image/svg+xml" href="favicon.svg">'), nl,
    write('<link rel="stylesheet" href=".portage-ng.css">'), nl,
    write('</head>'), nl,
    write('<body class="page-404">'), nl,
    write('<div class="nf">'), nl,
    write('  <pre class="nf-code"><span class="p">?-</span> prove(page).'), nl,
    write('<span class="e">false.</span>'), nl,
    nl,
    write('<span class="p">?-</span> assumption(page_not_found(404)).'), nl,
    write('true.</pre>'), nl,
    write('  <h1><span class="glyph">::-</span> no proof found.</h1>'), nl,
    write('  <p>The page you requested could not be derived from the knowledge base.</p>'), nl,
    write('  <div class="cta-row">'), nl,
    write('    <a class="btn btn-primary" href="./">Back to the homepage</a>'), nl,
    write('    <a class="btn btn-ghost" href="https://portage-ng.ai/docs/">Browse the handbook</a>'), nl,
    write('  </div>'), nl,
    write('</div>'), nl,
    write('</body>'), nl,
    write('</html>'), nl.


% -----------------------------------------------------------------------------
%  robots.txt
% -----------------------------------------------------------------------------

%! sitefiles:emit_robots(+Url) is det.
%
% Emit robots.txt allowing the tree and pointing at the sitemap index.

sitefiles:emit_robots(Url) :-
    write('User-agent: *'), nl,
    write('Allow: /'), nl,
    nl,
    format('Sitemap: ~w/sitemap.xml~n', [Url]).


% -----------------------------------------------------------------------------
%  Sitemaps
% -----------------------------------------------------------------------------

%! sitefiles:write_sitemaps(+Directory, +Repository, +Url) is det.
%
% Write sitemap.xml (index) plus one urlset per index layer and graph type.
% A single urlset would exceed the 50 000 URL sitemap limit.

sitefiles:write_sitemaps(Directory, Repository, Url) :-
    findall(Cat, cache:category(Repository, Cat), Cats),
    findall(Cat-Name, cache:package(Repository, Cat, Name), Pkgs),
    findall(Entry, cache:ordered_entry(Repository, Entry, _, _, _), Entries),
    config:graph_html_type(Types),
    sitefiles:write_file(Directory, 'sitemap.xml',
                         sitefiles:emit_sitemap_index(Url, Types)),
    sitefiles:write_file(Directory, 'sitemap-indexes.xml',
                         sitefiles:emit_indexes_urlset(Url, Cats, Pkgs)),
    forall(member(Type, Types),
           (   format(atom(File), 'sitemap-~w.xml', [Type]),
               sitefiles:write_file(Directory, File,
                                    sitefiles:emit_type_urlset(Url, Type, Entries))
           )).


%! sitefiles:emit_sitemap_index(+Url, +Types) is det.
%
% Emit the sitemap index listing the indexes shard and one shard per type.

sitefiles:emit_sitemap_index(Url, Types) :-
    write('<?xml version="1.0" encoding="UTF-8"?>'), nl,
    write('<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'), nl,
    sitefiles:emit_sitemap_loc(Url, 'sitemap-indexes.xml'),
    forall(member(Type, Types),
           (   format(atom(File), 'sitemap-~w.xml', [Type]),
               sitefiles:emit_sitemap_loc(Url, File)
           )),
    write('</sitemapindex>'), nl.


%! sitefiles:emit_sitemap_loc(+Url, +File) is det.
%
% One <sitemap><loc>…</loc></sitemap> row.

sitefiles:emit_sitemap_loc(Url, File) :-
    navtheme:html_escape(File, FileE),
    format('  <sitemap><loc>~w/~w</loc></sitemap>~n', [Url, FileE]).


%! sitefiles:emit_indexes_urlset(+Url, +Cats, +Pkgs) is det.
%
% Urlset for the repository, category and package index pages.

sitefiles:emit_indexes_urlset(Url, Cats, Pkgs) :-
    sitefiles:emit_urlset_open,
    format('  <url><loc>~w/</loc></url>~n', [Url]),
    forall(member(Cat, Cats),
           (   atomic_list_concat([Cat, '/index.html'], Path),
               sitefiles:emit_url(Url, Path)
           )),
    forall(member(Cat-Name, Pkgs),
           (   atomic_list_concat([Cat, '/', Name, '.html'], Path),
               sitefiles:emit_url(Url, Path)
           )),
    sitefiles:emit_urlset_close.


%! sitefiles:emit_type_urlset(+Url, +Type, +Entries) is det.
%
% Urlset for every ebuild page of one graph type.

sitefiles:emit_type_urlset(Url, Type, Entries) :-
    sitefiles:emit_urlset_open,
    forall(member(Entry, Entries),
           (   atomic_list_concat([Entry, '-', Type, '.html'], Path),
               sitefiles:emit_url(Url, Path)
           )),
    sitefiles:emit_urlset_close.


%! sitefiles:emit_urlset_open is det.
%
% XML declaration and opening urlset tag.

sitefiles:emit_urlset_open :-
    write('<?xml version="1.0" encoding="UTF-8"?>'), nl,
    write('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'), nl.


%! sitefiles:emit_urlset_close is det.
%
% Closing urlset tag.

sitefiles:emit_urlset_close :-
    write('</urlset>'), nl.


%! sitefiles:emit_url(+Url, +Path) is det.
%
% One <url><loc>…</loc></url> row for Url/Path.

sitefiles:emit_url(Url, Path) :-
    navtheme:html_escape(Path, PathE),
    format('  <url><loc>~w/~w</loc></url>~n', [Url, PathE]).
