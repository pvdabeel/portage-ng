/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> SECURITY
Security advisory (GLSA) HTML page for portage-ng ebuilds. Lists every
advisory whose affected-package list names the ebuild's package, newest
first, marks how the page's version relates to each one (in a vulnerable
range, in an unaffected range, or not mentioned) and folds each advisory
open to its full text: synopsis, metadata, affected ranges, background,
description, impact, workaround, resolution and references. Advisory
facts come from the GLSA knowledge store (`glsa:package/4`,
`glsa:range/7`); the prose is read on demand via `glsa:detail/2`.
*/

:- module(security, []).

% =============================================================================
%  SECURITY declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Entry point
% -----------------------------------------------------------------------------

%! security:graph(+Target)
%
% Generate the security advisory HTML document for Target to the current
% output stream.

security:graph(Repository://Entry) :-
    cache:ordered_entry(Repository, Entry, Cat, Name, _),
    glsa:package_advisories(Cat, Name, Ids),
    findall(Row,
            ( member(Id, Ids),
              advisory_row(Repository://Entry, Cat, Name, Id, Row)
            ),
            Rows),
    emit_html(Repository://Entry, Rows).


% -----------------------------------------------------------------------------
%  Data collection
% -----------------------------------------------------------------------------

%! security:advisory_row(+Target, +Cat, +Name, +Id, -Row)
%
% Row is adv(Id, Title, Status, InstalledVulnerable, Detail): Status is
% the glsa:entry_status/3 verdict for Target, InstalledVulnerable is
% true when an installed copy of Cat/Name sits in a vulnerable range of
% Id, Detail is glsa:detail/2 output ([] when the XML is unavailable).

advisory_row(Repository://Entry, Cat, Name, Id, adv(Id, Title, Status, InstVuln, Detail)) :-
    (   glsa:advisory(Id, Title0)
    ->  Title = Title0
    ;   Title = ''
    ),
    glsa:entry_status(Id, Repository://Entry, Status),
    (   catch(once(glsa:vulnerable_installed(Id, Cat, Name, _, _)), _, fail)
    ->  InstVuln = true
    ;   InstVuln = false
    ),
    (   catch(glsa:detail(Id, Detail0), _, fail)
    ->  Detail = Detail0
    ;   Detail = []
    ).


%! security:count_status(+Rows, +Status, -Count)
%
% Number of rows whose entry status equals Status.

count_status(Rows, Status, Count) :-
    aggregate_all(count, member(adv(_, _, Status, _, _), Rows), Count).


% -----------------------------------------------------------------------------
%  HTML emission - main
% -----------------------------------------------------------------------------

%! security:emit_html(+Target, +Rows)
%
% Emit a complete HTML document to the current output stream.

emit_html(Repository://Entry, Rows) :-
    cache:ordered_entry(Repository, Entry, Cat, Name, Version),
    version_domain:display_atom(Version, Ver),
    format(atom(Title), '~w/~w-~w &mdash; Security Advisories', [Cat, Name, Ver]),
    navtheme:emit_doctype,
    navtheme:emit_head_open(Title, '../'),
    navtheme:emit_head_close,
    navtheme:emit_body_open('page-glsa'),
    navtheme:emit_top_bar('../', Repository, Cat, Name, Ver),
    navtheme:emit_main_open,
    navtheme:emit_page_head_open,
    deptree:version_neighbours(Repository, Entry, Newer, Newest, Older, Oldest),
    navtheme:emit_nav_bar(Repository, Entry, Cat, Name, glsa, Newer, Newest, Older, Oldest, Ver),
    navtheme:emit_page_head_close,
    navtheme:emit_term_open('portage-ng glsa'),
    emit_toolbar(Cat, Name, Ver, Rows),
    emit_advisories(Repository, Cat, Name, Rows),
    navtheme:emit_term_close,
    emit_script,
    navtheme:emit_main_close,
    navtheme:emit_theme_script,
    navtheme:emit_body_close.


% -----------------------------------------------------------------------------
%  HTML emission - toolbar
% -----------------------------------------------------------------------------

%! security:emit_toolbar(+Cat, +Name, +Ver, +Rows)
%
% Summary line plus the filter (all / affecting this version) and
% expand / collapse controls. Controls are omitted when no advisory
% references the package.

emit_toolbar(Cat, Name, Ver, Rows) :-
    navtheme:html_escape(Cat, CatE),
    navtheme:html_escape(Name, NameE),
    navtheme:html_escape(Ver, VerE),
    length(Rows, Total),
    count_status(Rows, vulnerable, Affecting),
    write('<div class="glsa-toolbar">'), nl,
    write('  <span class="glsa-summary-text">'),
    (   Total =:= 0
    ->  format('No security advisories reference <b>~w/~w</b>.', [CatE, NameE])
    ;   plural(Total, 'advisory', 'advisories', AdvWord),
        format('<b>~w</b> ~w reference <b>~w/~w</b> &middot; ', [Total, AdvWord, CatE, NameE]),
        (   Affecting =:= 0
        ->  format('none place version <b>~w</b> in a vulnerable range', [VerE])
        ;   plural(Affecting, 'places', 'place', PlaceWord),
            format('<b class="glsa-affecting">~w</b> ~w version <b>~w</b> in a vulnerable range',
                   [Affecting, PlaceWord, VerE])
        )
    ),
    write('</span>'), nl,
    (   Total > 0
    ->  write('  <span class="glsa-btns">'), nl,
        write('    <button class="filter-btn active" onclick="glsaFilter(\'all\', this)">All</button>'), nl,
        write('    <button class="filter-btn" onclick="glsaFilter(\'affecting\', this)">Affecting this version</button>'), nl,
        write('    <span class="sep"></span>'), nl,
        write('    <button class="action-btn" onclick="glsaSetAll(true)">Expand all</button>'), nl,
        write('    <button class="action-btn" onclick="glsaSetAll(false)">Collapse all</button>'), nl,
        write('  </span>'), nl
    ;   true
    ),
    write('</div>'), nl.


%! security:plural(+N, +Singular, +Plural, -Word)
%
% Word is Singular when N is 1, else Plural.

plural(1, Singular, _, Singular) :- !.
plural(_, _, Plural, Plural).


% -----------------------------------------------------------------------------
%  HTML emission - advisory list
% -----------------------------------------------------------------------------

%! security:emit_advisories(+Repo, +Cat, +Name, +Rows)
%
% Emit the fold-open advisory list, or the empty-state note.

emit_advisories(_, _, _, []) :-
    !,
    write('<div class="glsa-empty">Nothing to report: the GLSA index has no advisory for this package.</div>'), nl.
emit_advisories(Repository, Cat, Name, Rows) :-
    write('<div class="glsa-list">'), nl,
    forall(member(Row, Rows), emit_advisory(Repository, Cat, Name, Row)),
    write('</div>'), nl.


%! security:emit_advisory(+Repo, +Cat, +Name, +Row)
%
% One `<details>` item: a summary row (id, title, badges) that folds
% open to the advisory body.

emit_advisory(Repository, Cat, Name, adv(Id, Title, Status, InstVuln, Detail)) :-
    navtheme:html_escape(Id, IdE),
    navtheme:html_escape(Title, TitleE),
    format('<details class="glsa-item" id="glsa-~w" data-status="~w">~n', [IdE, Status]),
    write('  <summary class="glsa-summary">'), nl,
    write('    <span class="glsa-chevron">&#9656;</span>'), nl,
    format('    <span class="glsa-id">GLSA ~w</span>~n', [IdE]),
    format('    <span class="glsa-title">~w</span>~n', [TitleE]),
    write('    <span class="glsa-badges">'), nl,
    emit_status_badge(Status),
    (   InstVuln == true
    ->  write('      <span class="glsa-badge installed">installed copy vulnerable</span>'), nl
    ;   true
    ),
    (   memberchk(severity(Sev), Detail)
    ->  severity_class(Sev, SevCls),
        navtheme:html_escape(Sev, SevE),
        format('      <span class="glsa-badge severity ~w">~w</span>~n', [SevCls, SevE])
    ;   true
    ),
    (   memberchk(access(Acc), Detail)
    ->  navtheme:html_escape(Acc, AccE),
        format('      <span class="glsa-badge access">~w</span>~n', [AccE])
    ;   true
    ),
    (   memberchk(announced(Date), Detail)
    ->  navtheme:html_escape(Date, DateE),
        format('      <span class="glsa-date">~w</span>~n', [DateE])
    ;   true
    ),
    write('    </span>'), nl,
    write('  </summary>'), nl,
    write('  <div class="glsa-body">'), nl,
    emit_body(Repository, Cat, Name, Id, Detail),
    write('  </div>'), nl,
    write('</details>'), nl.


%! security:emit_status_badge(+Status)
%
% Badge describing how the page's version relates to the advisory.

emit_status_badge(vulnerable) :-
    write('      <span class="glsa-badge status vulnerable">affects this version</span>'), nl.
emit_status_badge(unaffected) :-
    write('      <span class="glsa-badge status unaffected">this version unaffected</span>'), nl.
emit_status_badge(unlisted) :-
    write('      <span class="glsa-badge status unlisted">version not in range</span>'), nl.


%! security:severity_class(+Level, -Class)
%
% Maps the GLSA impact type onto the three badge colours.

severity_class(high, high) :- !.
severity_class(medium, normal) :- !.
severity_class(normal, normal) :- !.
severity_class(low, low) :- !.
severity_class(minimal, low) :- !.
severity_class(_, normal).


% -----------------------------------------------------------------------------
%  HTML emission - advisory body
% -----------------------------------------------------------------------------

%! security:emit_body(+Repo, +Cat, +Name, +Id, +Detail)
%
% Synopsis, metadata list, affected-range table, prose sections and
% references. The range table always renders (it comes from the fact
% store); the prose only when glsa:detail/2 found the XML file.

emit_body(Repository, Cat, Name, Id, Detail) :-
    (   memberchk(synopsis(Syn), Detail)
    ->  navtheme:html_escape(Syn, SynE),
        format('    <p class="glsa-synopsis">~w</p>~n', [SynE])
    ;   true
    ),
    emit_meta(Id, Detail),
    emit_ranges(Repository, Cat, Name, Id),
    emit_section('Background', background, Detail),
    emit_section('Description', description, Detail),
    emit_section('Impact', impact, Detail),
    emit_section('Workaround', workaround, Detail),
    emit_section('Resolution', resolution, Detail),
    emit_references(Detail),
    (   Detail == []
    ->  write('    <div class="glsa-note">The full advisory text is not available on this host (no <code>metadata/glsa</code> XML next to the GLSA cache); the ranges above come from the cached index. Follow the advisory link for the complete text.</div>'), nl
    ;   true
    ).


%! security:emit_meta(+Id, +Detail)
%
% Announced / revised / access / bugs / advisory-link definition list.

emit_meta(Id, Detail) :-
    write('    <dl class="glsa-meta">'), nl,
    (   memberchk(announced(Ann), Detail)
    ->  navtheme:html_escape(Ann, AnnE),
        emit_meta_row('Announced', AnnE)
    ;   true
    ),
    (   memberchk(revised(Rev, Count), Detail)
    ->  navtheme:html_escape(Rev, RevE),
        (   Count > 1
        ->  format(atom(RevText), '~w <span class="glsa-muted">(revision ~w)</span>', [RevE, Count])
        ;   RevText = RevE
        ),
        emit_meta_row('Revised', RevText)
    ;   true
    ),
    (   memberchk(access(Acc), Detail)
    ->  navtheme:html_escape(Acc, AccE),
        emit_meta_row('Access', AccE)
    ;   true
    ),
    (   memberchk(bugs(Bugs), Detail)
    ->  findall(Link, ( member(Bug, Bugs), bug_link(Bug, Link) ), Links),
        atomic_list_concat(Links, ' ', BugsText),
        emit_meta_row('Bugs', BugsText)
    ;   true
    ),
    glsa:advisory_url(Id, Url),
    navtheme:html_escape(Url, UrlE),
    format(atom(AdvText), '<a href="~w" rel="noopener">~w</a>', [UrlE, UrlE]),
    emit_meta_row('Advisory', AdvText),
    write('    </dl>'), nl.


%! security:emit_meta_row(+Label, +Html)
%
% One dt/dd pair; Html is already escaped.

emit_meta_row(Label, Html) :-
    format('      <dt>~w</dt><dd>~w</dd>~n', [Label, Html]).


%! security:bug_link(+Bug, -Html)
%
% Anchor to the Gentoo bug.

bug_link(Bug, Html) :-
    glsa:bug_url(Bug, Url),
    navtheme:html_escape(Bug, BugE),
    navtheme:html_escape(Url, UrlE),
    format(atom(Html), '<a href="~w" rel="noopener">#~w</a>', [UrlE, BugE]).


%! security:emit_ranges(+Repo, +Cat, +Name, +Id)
%
% Table of every package named by the advisory with its vulnerable and
% unaffected ranges. The page's own package is highlighted; packages
% present in the repository link to their index page.

emit_ranges(Repository, Cat, Name, Id) :-
    findall(C-N-Arch, glsa:package(Id, C, N, Arch), Pkgs0),
    sort(Pkgs0, Pkgs),
    (   Pkgs == []
    ->  true
    ;   write('    <h4>Affected packages</h4>'), nl,
        write('    <table class="glsa-ranges">'), nl,
        write('      <thead><tr><th>Package</th><th>Arch</th><th>Vulnerable</th><th>Unaffected</th></tr></thead>'), nl,
        write('      <tbody>'), nl,
        forall(member(C-N-Arch, Pkgs),
               emit_range_row(Repository, Cat, Name, Id, C, N, Arch)),
        write('      </tbody>'), nl,
        write('    </table>'), nl
    ).


%! security:emit_range_row(+Repo, +Cat, +Name, +Id, +C, +N, +Arch)
%
% One package row of the affected-range table.

emit_range_row(Repository, Cat, Name, Id, C, N, Arch) :-
    navtheme:html_escape(C, CE),
    navtheme:html_escape(N, NE),
    navtheme:html_escape(Arch, ArchE),
    (   C == Cat, N == Name
    ->  RowCls = ' class="current"'
    ;   RowCls = ''
    ),
    (   cache:package(Repository, C, N)
    ->  format(atom(PkgHtml), '<a href="../~w/~w.html">~w/~w</a>', [CE, NE, CE, NE])
    ;   format(atom(PkgHtml), '~w/~w', [CE, NE])
    ),
    ranges_text(Id, C, N, vulnerable, VulnText),
    ranges_text(Id, C, N, unaffected, UnaffText),
    format('        <tr~w><td>~w</td><td class="arch">~w</td><td class="range vulnerable">~w</td><td class="range unaffected">~w</td></tr>~n',
           [RowCls, PkgHtml, ArchE, VulnText, UnaffText]).


%! security:ranges_text(+Id, +C, +N, +Kind, -Html)
%
% Comma-joined, escaped range list of one kind ('&mdash;' when empty).

ranges_text(Id, C, N, Kind, Html) :-
    findall(Text,
            ( glsa:range(Id, C, N, Kind, Op, Ver, Slot),
              range_text(Op, Ver, Slot, Text)
            ),
            Texts),
    (   Texts == []
    ->  Html = '&mdash;'
    ;   maplist(navtheme:html_escape, Texts, Escaped),
        atomic_list_concat(Escaped, ', ', Html)
    ).


%! security:range_text(+Op, +Ver, +Slot, -Text)
%
% Human form of one GLSA range: comparator, version, optional `:slot`,
% and a revision marker for the revision-only operators.

range_text(Op, Ver, Slot, Text) :-
    op_symbol(Op, Sym, Suffix),
    version_domain:display_atom(Ver, V),
    (   Slot == '*'
    ->  SlotText = ''
    ;   format(atom(SlotText), ':~w', [Slot])
    ),
    format(atom(Text), '~w ~w~w~w', [Sym, V, SlotText, Suffix]).


%! security:op_symbol(+Op, -Symbol, -Suffix)
%
% Comparator symbol and display suffix for a GLSA range token.

op_symbol(lt,  '<',  '').
op_symbol(le,  '<=', '').
op_symbol(eq,  '=',  '').
op_symbol(gt,  '>',  '').
op_symbol(ge,  '>=', '').
op_symbol(rlt, '<',  ' (revision)').
op_symbol(rle, '<=', ' (revision)').
op_symbol(rgt, '>',  ' (revision)').
op_symbol(rge, '>=', ' (revision)').


%! security:emit_section(+Label, +Key, +Detail)
%
% Heading plus the block list of one prose section, when present.

emit_section(Label, Key, Detail) :-
    Field =.. [Key, Blocks],
    (   memberchk(Field, Detail),
        Blocks \== []
    ->  format('    <h4>~w</h4>~n', [Label]),
        forall(member(Block, Blocks), emit_block(Block))
    ;   true
    ).


%! security:emit_block(+Block)
%
% One p/1, code/1 or list/1 block.

emit_block(p(Text)) :-
    navtheme:html_escape(Text, TextE),
    format('    <p>~w</p>~n', [TextE]).
emit_block(code(Text)) :-
    navtheme:html_escape(Text, TextE),
    format('    <pre class="glsa-code">~w</pre>~n', [TextE]).
emit_block(list(Items)) :-
    write('    <ul>'), nl,
    forall(member(Item, Items),
           ( navtheme:html_escape(Item, ItemE),
             format('      <li>~w</li>~n', [ItemE])
           )),
    write('    </ul>'), nl.


%! security:emit_references(+Detail)
%
% Reference link list (CVE identifiers and other URIs).

emit_references(Detail) :-
    (   memberchk(references(Refs), Detail),
        Refs \== []
    ->  write('    <h4>References</h4>'), nl,
        write('    <ul class="glsa-refs">'), nl,
        forall(member(ref(Label, Url), Refs),
               ( navtheme:html_escape(Label, LabelE),
                 navtheme:html_escape(Url, UrlE),
                 format('      <li><a href="~w" rel="noopener">~w</a></li>~n', [UrlE, LabelE])
               )),
        write('    </ul>'), nl
    ;   true
    ).


% -----------------------------------------------------------------------------
%  Script emission
% -----------------------------------------------------------------------------

%! security:emit_script
%
% Expand / collapse all, the affecting-only filter, and opening the
% advisory addressed by the URL fragment (`#glsa-<id>`).

emit_script :-
    write('<script>'), nl,
    write('function glsaSetAll(open) {'), nl,
    write('  document.querySelectorAll("details.glsa-item").forEach(d => { d.open = open; });'), nl,
    write('}'), nl,
    write('function glsaFilter(mode, btn) {'), nl,
    write('  document.querySelectorAll("details.glsa-item").forEach(d => {'), nl,
    write('    d.classList.toggle("hidden", mode === "affecting" && d.dataset.status !== "vulnerable");'), nl,
    write('  });'), nl,
    write('  document.querySelectorAll(".glsa-toolbar .filter-btn").forEach(b => b.classList.toggle("active", b === btn));'), nl,
    write('}'), nl,
    write('(function () {'), nl,
    write('  if (!location.hash) return;'), nl,
    write('  const el = document.getElementById(location.hash.slice(1));'), nl,
    write('  if (el && el.tagName === "DETAILS") { el.open = true; el.scrollIntoView(); }'), nl,
    write('})();'), nl,
    write('</script>'), nl.
