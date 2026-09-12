/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> TRACKER
Bug tracker HTML page for portage-ng ebuilds. Lists every bug in the
synced Bugzilla store (`Source/Domain/Gentoo/bugs.pl`) whose summary or
stabilisation atoms name the ebuild's package, newest first, marks the
ones naming the page's exact version, and folds each bug open to its
stored columns (status, resolution, severity, priority, component,
assignee, dates, keywords) plus the packages it names. Facet chips
(status, resolution, version relevance, component, severity, keyword,
last-changed age) and a free-text box filter the list client-side; the
filter state lives in the URL hash so a view can be linked. Rendered as
`<entry>-bugs.html`; the layout reuses the GLSA page's fold-open list
styling (`glsa-*` classes) with bug-specific status colours.
*/

:- module(tracker, []).

% =============================================================================
%  TRACKER declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Entry point
% -----------------------------------------------------------------------------

%! tracker:graph(+Target)
%
% Generate the bug tracker HTML document for Target to the current
% output stream.

tracker:graph(Repository://Entry) :-
    cache:ordered_entry(Repository, Entry, Cat, Name, Version),
    ( catch(bugs:package_bugs(Cat, Name, Ids), _, fail) -> true ; Ids = [] ),
    findall(Row,
            ( member(Id, Ids),
              bug_row(Cat, Name, Version, Id, Row)
            ),
            Rows),
    emit_html(Repository://Entry, Rows).


% -----------------------------------------------------------------------------
%  Data collection
% -----------------------------------------------------------------------------

%! tracker:bug_row(+Cat, +Name, +Version, +Id, -Row)
%
% Row is bug(Id, Summary, State, VersionFacet, Detail): State is `open`
% or `resolved`; VersionFacet is `this` when the bug names Cat/Name at
% exactly Version, `other` when it names Cat/Name at some other version,
% `none` when it only names the bare package; Detail is the
% bugs:bug_detail/2 key list.

bug_row(Cat, Name, Version, Id, bug(Id, Summary, State, Facet, Detail)) :-
    bugs:bug_detail(Id, Detail),
    memberchk(summary(Summary), Detail),
    memberchk(status(Status), Detail),
    (   bugs:open_status(Status)
    ->  State = open
    ;   State = resolved
    ),
    version_facet(Cat, Name, Version, Id, Facet).


%! tracker:version_facet(+Cat, +Name, +Version, +Id, -Facet)
%
% Facet is `this`, `other` or `none` (see bug_row/5).

version_facet(Cat, Name, Version, Id, Facet) :-
    (   Version \== version_none,
        bugsdata:bug_atom(Id, Cat, Name, Version)
    ->  Facet = this
    ;   bugsdata:bug_atom(Id, Cat, Name, V), V \== version_none
    ->  Facet = other
    ;   Facet = none
    ).


%! tracker:count_state(+Rows, +State, -Count)
%
% Number of rows in State.

count_state(Rows, State, Count) :-
    aggregate_all(count, member(bug(_, _, State, _, _), Rows), Count).


%! tracker:count_this_version(+Rows, -Count)
%
% Number of rows naming the page's version.

count_this_version(Rows, Count) :-
    aggregate_all(count, member(bug(_, _, _, this, _), Rows), Count).


%! tracker:facet_values(+Rows, +Key, -Values)
%
% Distinct non-empty values of the Detail column Key across Rows, in
% order of first appearance (rows are newest first, so the most recently
% touched value leads).

facet_values(Rows, Key, Values) :-
    Field =.. [Key, Value],
    findall(Value,
            ( member(bug(_, _, _, _, Detail), Rows),
              memberchk(Field, Detail),
              Value \== ''
            ),
            Values0),
    list_to_set(Values0, Values).


%! tracker:facet_keywords(+Rows, -Keywords)
%
% Distinct Bugzilla keywords across Rows, most frequent first.

facet_keywords(Rows, Keywords) :-
    findall(Kw,
            ( member(bug(_, _, _, _, Detail), Rows),
              memberchk(keywords(Kws), Detail),
              member(Kw, Kws)
            ),
            All),
    msort(All, Sorted),
    clumped(Sorted, Counted),
    findall(N-Kw, member(Kw-N, Counted), ByCount0),
    sort(0, @>=, ByCount0, ByCount),
    findall(Kw, member(_-Kw, ByCount), Keywords).


%! tracker:severity_order(+Severities, -Ordered)
%
% Severities in Bugzilla's blocker-to-enhancement order; unknown ones
% follow in their original order.

severity_order(Severities, Ordered) :-
    Canon = [blocker, critical, major, normal, minor, trivial, enhancement],
    findall(S, ( member(S, Canon), memberchk(S, Severities) ), Known),
    findall(S, ( member(S, Severities), \+ memberchk(S, Canon) ), Unknown),
    append(Known, Unknown, Ordered).


%! tracker:slug(+Value, -Slug)
%
% Lower-case attribute-safe token for a facet value: runs of characters
% other than ASCII letters and digits become a single `-`.

slug(Value, Slug) :-
    downcase_atom(Value, Lower),
    atom_codes(Lower, Codes0),
    skip_nonalnum(Codes0, Codes),
    slug_codes(Codes, SlugCodes),
    atom_codes(Slug0, SlugCodes),
    (   Slug0 == '' -> Slug = other ; Slug = Slug0 ).


%! tracker:slug_codes(+Codes, -SlugCodes)
%
% slug/2 on a code list.

slug_codes([], []).
slug_codes([C|T], [C|R]) :-
    ( code_type(C, alpha) ; code_type(C, digit) ), C < 128,
    !,
    slug_codes(T, R).
slug_codes(Cs, Out) :-
    skip_nonalnum(Cs, Rest),
    (   Rest == []
    ->  Out = []
    ;   Out = [0'-|R],
        slug_codes(Rest, R)
    ).


%! tracker:skip_nonalnum(+Codes, -Rest)
%
% Drops the leading run of non-alphanumeric codes.

skip_nonalnum([C|T], Rest) :-
    \+ ( ( code_type(C, alpha) ; code_type(C, digit) ), C < 128 ),
    !,
    skip_nonalnum(T, Rest).
skip_nonalnum(Rest, Rest).


%! tracker:default_off_component(+Slug)
%
% Components hidden by default: stabilisation and keywording requests
% are workflow tickets, not defects.

default_off_component(stabilization).
default_off_component(keywording).


% -----------------------------------------------------------------------------
%  HTML emission - main
% -----------------------------------------------------------------------------

%! tracker:emit_html(+Target, +Rows)
%
% Emit a complete HTML document to the current output stream.

emit_html(Repository://Entry, Rows) :-
    cache:ordered_entry(Repository, Entry, Cat, Name, Version),
    version_domain:display_atom(Version, Ver),
    format(atom(Title), '~w/~w-~w &mdash; Bugs', [Cat, Name, Ver]),
    navtheme:emit_doctype,
    navtheme:emit_head_open(Title, '../'),
    navtheme:emit_head_close,
    navtheme:emit_body_open('page-glsa page-bugs'),
    navtheme:emit_top_bar('../', Repository, Cat, Name, Ver),
    navtheme:emit_main_open,
    navtheme:emit_page_head_open,
    deptree:version_neighbours(Repository, Entry, Newer, Newest, Older, Oldest),
    navtheme:emit_nav_bar(Repository, Entry, Cat, Name, bugs, Newer, Newest, Older, Oldest, Ver),
    navtheme:emit_page_head_close,
    navtheme:emit_term_open('portage-ng bugs'),
    emit_toolbar(Cat, Name, Ver, Rows),
    emit_filters(Ver, Rows),
    emit_bugs(Repository, Rows),
    navtheme:emit_term_close,
    emit_script,
    navtheme:emit_main_close,
    navtheme:emit_theme_script,
    navtheme:emit_body_close.


% -----------------------------------------------------------------------------
%  HTML emission - toolbar
% -----------------------------------------------------------------------------

%! tracker:emit_toolbar(+Cat, +Name, +Ver, +Rows)
%
% Summary line (totals, plus a script-maintained "showing N" count),
% the free-text filter box, and the reset / expand / collapse controls.
% Controls are omitted when no bug names the package.

emit_toolbar(Cat, Name, Ver, Rows) :-
    navtheme:html_escape(Cat, CatE),
    navtheme:html_escape(Name, NameE),
    navtheme:html_escape(Ver, VerE),
    length(Rows, Total),
    count_state(Rows, open, Open),
    count_this_version(Rows, This),
    write('<div class="glsa-toolbar">'), nl,
    write('  <span class="glsa-summary-text">'),
    (   Total =:= 0
    ->  (   bugs:cache_available
        ->  format('No bugs in the local bug store reference <b>~w/~w</b>.', [CatE, NameE])
        ;   format('No bug store has been synced on this host (register a <code>bugzilla</code> repository and run <code>--sync</code>).', [])
        )
    ;   plural(Total, 'bug', 'bugs', BugWord),
        format('<b>~w</b> ~w reference <b>~w/~w</b> &middot; ', [Total, BugWord, CatE, NameE]),
        (   Open =:= 0
        ->  format('none open', [])
        ;   format('<b class="glsa-affecting">~w</b> open', [Open])
        ),
        (   This > 0
        ->  plural(This, 'names', 'name', NameWord),
            format(' &middot; <b>~w</b> ~w version <b>~w</b>', [This, NameWord, VerE])
        ;   true
        ),
        write('<span id="bugs-shown"></span>')
    ),
    write('</span>'), nl,
    (   Total > 0
    ->  write('  <span class="glsa-btns">'), nl,
        write('    <input class="bug-search" id="bug-search" type="search" placeholder="Filter by text&hellip;" oninput="bugsApply()" aria-label="Filter bugs by text">'), nl,
        write('    <button class="action-btn bug-filters-toggle" id="bug-filters-toggle" onclick="bugsToggleFilters()" aria-expanded="false" aria-controls="bug-filters"><span class="glsa-chevron">&#9656;</span>Filters<span class="nav-badge" id="bug-filters-count"></span></button>'), nl,
        write('    <button class="action-btn" onclick="bugsReset()">Reset</button>'), nl,
        write('    <span class="sep"></span>'), nl,
        write('    <button class="action-btn" onclick="bugsSetAll(true)">Expand all</button>'), nl,
        write('    <button class="action-btn" onclick="bugsSetAll(false)">Collapse all</button>'), nl,
        write('  </span>'), nl
    ;   true
    ),
    write('</div>'), nl.


% -----------------------------------------------------------------------------
%  HTML emission - filters
% -----------------------------------------------------------------------------

%! tracker:emit_filters(+Ver, +Rows)
%
% Facet chip rows. Chips within a group are OR-ed, groups are AND-ed.
% `status`, `version`, `component`, `severity` and `resolution` are
% exclusion groups (a lit chip admits its value; a row whose value has
% no lit chip is hidden). `keyword` is a requirement group (no lit chip
% means no constraint; lit chips require one of them). `age` is
% single-select on the last-changed date. Defaults: open bugs only,
% stabilisation / keywording components off, everything else lit.
% The block starts folded (`collapsed`); the toolbar's Filters button
% unfolds it, and the script unfolds it on load when the URL hash
% carries a non-default filter state. Nothing is emitted when the page
% has no bugs.

emit_filters(_, []) :- !.
emit_filters(Ver, Rows) :-
    write('<div class="bug-filters collapsed" id="bug-filters">'), nl,
    write('  <div class="filter-row">'), nl,
    write('    <span class="nav-group-label">status</span>'), nl,
    emit_chip(status, open, 'open', active),
    emit_chip(status, resolved, 'resolved', inactive),
    facet_values(Rows, resolution, Resolutions),
    (   Resolutions == []
    ->  true
    ;   write('    <span class="sep" aria-hidden="true"></span>'), nl,
        write('    <span class="nav-group-label">resolution</span>'), nl,
        forall(member(R, Resolutions),
               ( slug(R, RS), emit_chip(resolution, RS, R, active) ))
    ),
    write('  </div>'), nl,
    write('  <div class="filter-row">'), nl,
    write('    <span class="nav-group-label">version</span>'), nl,
    format(atom(ThisLabel), 'names ~w', [Ver]),
    emit_chip(version, this, ThisLabel, active),
    emit_chip(version, other, 'names another version', active),
    emit_chip(version, none, 'no version', active),
    write('    <span class="sep" aria-hidden="true"></span>'), nl,
    write('    <span class="nav-group-label">changed</span>'), nl,
    emit_chip(age, 0, 'any time', active),
    emit_chip(age, 30, '30 days', inactive),
    emit_chip(age, 90, '90 days', inactive),
    emit_chip(age, 365, '1 year', inactive),
    write('  </div>'), nl,
    facet_values(Rows, component, Components),
    emit_facet_row(component, Components, Rows),
    facet_values(Rows, severity, Severities0),
    severity_order(Severities0, Severities),
    emit_facet_row(severity, Severities, Rows),
    facet_keywords(Rows, Keywords),
    emit_facet_row(keyword, Keywords, Rows),
    write('</div>'), nl.


%! tracker:emit_facet_row(+Group, +Values, +Rows)
%
% One chip row for a data-derived facet; omitted when Values is empty.

emit_facet_row(_, [], _) :- !.
emit_facet_row(Group, Values, _) :-
    write('  <div class="filter-row">'), nl,
    format('    <span class="nav-group-label">~w</span>~n', [Group]),
    forall(member(V, Values),
           ( slug(V, S), chip_default(Group, S, State), emit_chip(Group, S, V, State) )),
    write('  </div>'), nl.


%! tracker:chip_default(+Group, +Slug, -State)
%
% Initial chip state: keyword chips start unlit (requirement group),
% default-off components start unlit, the rest lit.

chip_default(keyword, _, inactive) :- !.
chip_default(component, Slug, inactive) :- default_off_component(Slug), !.
chip_default(_, _, active).


%! tracker:emit_chip(+Group, +Value, +Label, +State)
%
% One filter chip button.

emit_chip(Group, Value, Label, State) :-
    navtheme:html_escape(Label, LabelE),
    (   State == active -> Cls = ' active' ; Cls = '' ),
    format('    <button class="filter-btn~w" data-group="~w" data-value="~w" onclick="bugsToggle(this)">~w</button>~n',
           [Cls, Group, Value, LabelE]).


%! tracker:plural(+N, +Singular, +Plural, -Word)
%
% Word is Singular when N is 1, else Plural.

plural(1, Singular, _, Singular) :- !.
plural(_, _, Plural, Plural).


% -----------------------------------------------------------------------------
%  HTML emission - bug list
% -----------------------------------------------------------------------------

%! tracker:emit_bugs(+Repo, +Rows)
%
% Emit the fold-open bug list, or the empty-state note.

emit_bugs(_, []) :-
    !,
    write('<div class="glsa-empty">Nothing to report: the bug store has no bug naming this package.</div>'), nl.
emit_bugs(Repository, Rows) :-
    write('<div class="glsa-list">'), nl,
    forall(member(Row, Rows), emit_bug(Repository, Row)),
    write('</div>'), nl.


%! tracker:emit_bug(+Repo, +Row)
%
% One `<details>` item: a summary row (id, title, badges) that folds
% open to the stored bug columns. The facet values the filters match on
% are carried as `data-*` attributes (slugs, see slug/2); rows the
% default filters hide start with the `hidden` class so the page does
% not flash before the script runs.

emit_bug(Repository, bug(Id, Summary, State, Facet, Detail)) :-
    navtheme:html_escape(Summary, SummaryE),
    facet_attr(resolution, Detail, ResAttr),
    facet_attr(component, Detail, CompAttr),
    facet_attr(severity, Detail, SevAttr),
    keyword_attr(Detail, KwAttr),
    changed_attr(Detail, ChangedAttr),
    search_attr(Id, Summary, Detail, SearchAttr),
    (   default_hidden(State, CompAttr) -> Hidden = ' hidden' ; Hidden = '' ),
    format('<details class="glsa-item bug-item~w" id="bug-~w" data-status="~w" data-version="~w" data-resolution="~w" data-component="~w" data-severity="~w" data-keyword="~w" data-changed="~w" data-search="~w">~n',
           [Hidden, Id, State, Facet, ResAttr, CompAttr, SevAttr, KwAttr, ChangedAttr, SearchAttr]),
    write('  <summary class="glsa-summary">'), nl,
    write('    <span class="glsa-chevron">&#9656;</span>'), nl,
    format('    <span class="glsa-id">#~w</span>~n', [Id]),
    format('    <span class="glsa-title">~w</span>~n', [SummaryE]),
    write('    <span class="glsa-badges">'), nl,
    emit_state_badge(State, Detail),
    (   Facet == this
    ->  write('      <span class="glsa-badge version">names this version</span>'), nl
    ;   true
    ),
    (   memberchk(severity(Sev), Detail), Sev \== ''
    ->  severity_class(Sev, SevCls),
        navtheme:html_escape(Sev, SevE),
        format('      <span class="glsa-badge severity ~w">~w</span>~n', [SevCls, SevE])
    ;   true
    ),
    (   memberchk(changed(Changed), Detail), Changed \== ''
    ->  date_only(Changed, Date),
        navtheme:html_escape(Date, DateE),
        format('      <span class="glsa-date">~w</span>~n', [DateE])
    ;   true
    ),
    write('    </span>'), nl,
    write('  </summary>'), nl,
    write('  <div class="glsa-body">'), nl,
    emit_body(Repository, Id, Detail),
    write('  </div>'), nl,
    write('</details>'), nl.


%! tracker:emit_state_badge(+State, +Detail)
%
% Badge with the Bugzilla status (and resolution when resolved).

emit_state_badge(open, Detail) :-
    memberchk(status(Status), Detail),
    navtheme:html_escape(Status, StatusE),
    format('      <span class="glsa-badge status open">~w</span>~n', [StatusE]).
emit_state_badge(resolved, Detail) :-
    memberchk(status(Status), Detail),
    memberchk(resolution(Res), Detail),
    (   Res == ''
    ->  Text = Status
    ;   format(atom(Text), '~w ~w', [Status, Res])
    ),
    navtheme:html_escape(Text, TextE),
    format('      <span class="glsa-badge status resolved">~w</span>~n', [TextE]).


%! tracker:severity_class(+Severity, -Class)
%
% Maps Bugzilla severities onto the three badge colours.

severity_class(blocker,  high)   :- !.
severity_class(critical, high)   :- !.
severity_class(major,    high)   :- !.
severity_class(normal,   normal) :- !.
severity_class(minor,    low)    :- !.
severity_class(trivial,  low)    :- !.
severity_class(enhancement, low) :- !.
severity_class(_,        normal).


%! tracker:date_only(+Iso, -Date)
%
% `YYYY-MM-DD` part of a Bugzilla ISO timestamp.

date_only(Iso, Date) :-
    (   sub_atom(Iso, 0, 10, _, Date0), sub_atom(Iso, 10, 1, _, 'T')
    ->  Date = Date0
    ;   Date = Iso
    ).


%! tracker:facet_attr(+Key, +Detail, -Attr)
%
% Slug of the Detail column Key; `other` when the column is empty
% (matches the slug/2 fallback so an empty value still has a chip).

facet_attr(Key, Detail, Attr) :-
    Field =.. [Key, Value],
    (   memberchk(Field, Detail), Value \== ''
    ->  slug(Value, Attr)
    ;   Attr = other
    ).


%! tracker:keyword_attr(+Detail, -Attr)
%
% Space-separated keyword slugs.

keyword_attr(Detail, Attr) :-
    (   memberchk(keywords(Kws), Detail)
    ->  maplist(slug, Kws, Slugs),
        atomic_list_concat(Slugs, ' ', Attr)
    ;   Attr = ''
    ).


%! tracker:changed_attr(+Detail, -Attr)
%
% `YYYY-MM-DD` of the last change, empty when unknown.

changed_attr(Detail, Attr) :-
    (   memberchk(changed(Changed), Detail), Changed \== ''
    ->  date_only(Changed, Attr)
    ;   Attr = ''
    ).


%! tracker:search_attr(+Id, +Summary, +Detail, -Attr)
%
% Lower-cased, attribute-escaped haystack for the free-text filter:
% bug id, summary, assignee, component and keywords.

search_attr(Id, Summary, Detail, Attr) :-
    (   memberchk(assignee(As), Detail) -> true ; As = '' ),
    (   memberchk(component(Co), Detail) -> true ; Co = '' ),
    (   memberchk(keywords(Kws), Detail) -> true ; Kws = [] ),
    atomic_list_concat(Kws, ' ', KwText),
    atomic_list_concat(['#', Id, ' ', Summary, ' ', As, ' ', Co, ' ', KwText], Text),
    downcase_atom(Text, Lower),
    navtheme:html_escape(Lower, Attr).


%! tracker:default_hidden(+State, +ComponentSlug)
%
% True when the default filter state hides a row (see emit_filters/2).

default_hidden(resolved, _) :- !.
default_hidden(_, Comp) :- default_off_component(Comp).


% -----------------------------------------------------------------------------
%  HTML emission - bug body
% -----------------------------------------------------------------------------

%! tracker:emit_body(+Repo, +Id, +Detail)
%
% Metadata list, the packages the bug names, and the Bugzilla link.

emit_body(Repository, Id, Detail) :-
    write('    <dl class="glsa-meta">'), nl,
    emit_meta_field('Status',     status,     Detail),
    emit_meta_field('Resolution', resolution, Detail),
    emit_meta_field('Severity',   severity,   Detail),
    emit_meta_field('Priority',   priority,   Detail),
    emit_meta_field('Product',    product,    Detail),
    emit_meta_field('Component',  component,  Detail),
    emit_meta_field('Assignee',   assignee,   Detail),
    emit_meta_field('Created',    created,    Detail),
    emit_meta_field('Changed',    changed,    Detail),
    (   memberchk(keywords(Kws), Detail), Kws \== []
    ->  maplist(navtheme:html_escape, Kws, KwsE),
        atomic_list_concat(KwsE, ', ', KwText),
        emit_meta_row('Keywords', KwText)
    ;   true
    ),
    bugs:bug_url(Id, Url),
    navtheme:html_escape(Url, UrlE),
    format(atom(LinkText), '<a href="~w" rel="noopener">~w</a>', [UrlE, UrlE]),
    emit_meta_row('Bugzilla', LinkText),
    write('    </dl>'), nl,
    emit_atoms(Repository, Id).


%! tracker:emit_meta_field(+Label, +Key, +Detail)
%
% One dt/dd pair for a stored column, skipped when empty.

emit_meta_field(Label, Key, Detail) :-
    Field =.. [Key, Value],
    (   memberchk(Field, Detail), Value \== ''
    ->  navtheme:html_escape(Value, ValueE),
        emit_meta_row(Label, ValueE)
    ;   true
    ).


%! tracker:emit_meta_row(+Label, +Html)
%
% One dt/dd pair; Html is already escaped.

emit_meta_row(Label, Html) :-
    format('      <dt>~w</dt><dd>~w</dd>~n', [Label, Html]).


%! tracker:emit_atoms(+Repo, +Id)
%
% Packages named by the bug's atom index; packages present in the
% repository link to their index page.

emit_atoms(Repository, Id) :-
    findall(C-N-V, bugsdata:bug_atom(Id, C, N, V), Atoms0),
    sort(Atoms0, Atoms),
    (   Atoms == []
    ->  true
    ;   write('    <h4>Packages named</h4>'), nl,
        write('    <ul>'), nl,
        forall(member(C-N-V, Atoms), emit_atom(Repository, C, N, V)),
        write('    </ul>'), nl
    ).


%! tracker:emit_atom(+Repo, +C, +N, +V)
%
% One named package (with version when the bug gave one).

emit_atom(Repository, C, N, V) :-
    navtheme:html_escape(C, CE),
    navtheme:html_escape(N, NE),
    (   V == version_none
    ->  VerText = ''
    ;   version_domain:display_atom(V, Ver),
        navtheme:html_escape(Ver, VerE),
        format(atom(VerText), '-~w', [VerE])
    ),
    (   cache:package(Repository, C, N)
    ->  format('      <li><a href="../~w/~w.html">~w/~w</a>~w</li>~n', [CE, NE, CE, NE, VerText])
    ;   format('      <li>~w/~w~w</li>~n', [CE, NE, VerText])
    ).


% -----------------------------------------------------------------------------
%  Script emission
% -----------------------------------------------------------------------------

%! tracker:emit_script
%
% Expand / collapse all, the facet filters (see emit_filters/2) and the
% fold of their block (the Filters button carries a badge with the
% number of groups that differ from the defaults), the "showing N"
% count, filter state in the URL hash
% (`#status=open,resolved&severity=major&q=clang`) so a filtered view
% can be linked, and opening the bug addressed by a `#bug-<id>`
% fragment (lighting whatever chips are needed to make it visible).

emit_script :-
    write('<script>'), nl,
    write('const bugChips = () => Array.from(document.querySelectorAll("#bug-filters .filter-btn"));'), nl,
    write('const bugRows = () => Array.from(document.querySelectorAll("details.bug-item"));'), nl,
    write('const bugDefaults = {};'), nl,
    write('bugChips().forEach(b => { (bugDefaults[b.dataset.group] = bugDefaults[b.dataset.group] || []); if (b.classList.contains("active")) bugDefaults[b.dataset.group].push(b.dataset.value); });'), nl,
    write('function bugsSetAll(open) { bugRows().forEach(d => { d.open = open; }); }'), nl,
    write('function bugsLit() {'), nl,
    write('  const lit = {};'), nl,
    write('  bugChips().forEach(b => { lit[b.dataset.group] = lit[b.dataset.group] || new Set(); if (b.classList.contains("active")) lit[b.dataset.group].add(b.dataset.value); });'), nl,
    write('  return lit;'), nl,
    write('}'), nl,
    write('function bugsApply() {'), nl,
    write('  const lit = bugsLit();'), nl,
    write('  const has = (g, v) => !lit[g] || lit[g].has(v);'), nl,
    write('  const box = document.getElementById("bug-search");'), nl,
    write('  const q = box ? box.value.trim().toLowerCase() : "";'), nl,
    write('  const days = lit.age ? parseInt(Array.from(lit.age)[0] || "0", 10) : 0;'), nl,
    write('  const cutoff = days ? new Date(Date.now() - days * 86400000).toISOString().slice(0, 10) : "";'), nl,
    write('  let shown = 0, total = 0;'), nl,
    write('  bugRows().forEach(d => {'), nl,
    write('    const s = d.dataset; total++;'), nl,
    write('    let ok = has("status", s.status) && has("version", s.version) && has("component", s.component) && has("severity", s.severity);'), nl,
    write('    if (ok && s.status === "resolved") ok = has("resolution", s.resolution);'), nl,
    write('    if (ok && lit.keyword && lit.keyword.size) ok = s.keyword.split(" ").some(k => lit.keyword.has(k));'), nl,
    write('    if (ok && cutoff) ok = s.changed >= cutoff;'), nl,
    write('    if (ok && q) ok = s.search.indexOf(q) >= 0;'), nl,
    write('    d.classList.toggle("hidden", !ok); if (ok) shown++;'), nl,
    write('  });'), nl,
    write('  const el = document.getElementById("bugs-shown");'), nl,
    write('  if (el) el.textContent = shown === total ? "" : " \\u00b7 showing " + shown;'), nl,
    write('  const badge = document.getElementById("bug-filters-count");'), nl,
    write('  if (badge) { const n = bugsChanged(lit).length; badge.textContent = n ? String(n) : ""; badge.classList.toggle("affected", n > 0); }'), nl,
    write('}'), nl,
    write('function bugsChanged(lit) {'), nl,
    write('  return Object.keys(lit).filter(g => Array.from(lit[g]).sort().join(",") !== (bugDefaults[g] || []).slice().sort().join(","));'), nl,
    write('}'), nl,
    write('function bugsToggleFilters(open) {'), nl,
    write('  const box = document.getElementById("bug-filters"), btn = document.getElementById("bug-filters-toggle");'), nl,
    write('  if (!box) return;'), nl,
    write('  const show = open === undefined ? box.classList.contains("collapsed") : open;'), nl,
    write('  box.classList.toggle("collapsed", !show);'), nl,
    write('  if (btn) { btn.setAttribute("aria-expanded", show ? "true" : "false"); btn.classList.toggle("active", show); }'), nl,
    write('}'), nl,
    write('function bugsToggle(btn) {'), nl,
    write('  if (btn.dataset.group === "age") bugChips().filter(b => b.dataset.group === "age").forEach(b => b.classList.toggle("active", b === btn));'), nl,
    write('  else btn.classList.toggle("active");'), nl,
    write('  bugsApply(); bugsWriteHash();'), nl,
    write('}'), nl,
    write('function bugsReset() {'), nl,
    write('  bugChips().forEach(b => b.classList.toggle("active", bugDefaults[b.dataset.group].indexOf(b.dataset.value) >= 0));'), nl,
    write('  const box = document.getElementById("bug-search"); if (box) box.value = "";'), nl,
    write('  bugsApply(); history.replaceState(null, "", location.pathname + location.search);'), nl,
    write('}'), nl,
    write('function bugsWriteHash() {'), nl,
    write('  const lit = bugsLit(), parts = [];'), nl,
    write('  bugsChanged(lit).forEach(g => parts.push(g + "=" + Array.from(lit[g]).sort().join(",")));'), nl,
    write('  const box = document.getElementById("bug-search");'), nl,
    write('  if (box && box.value.trim()) parts.push("q=" + encodeURIComponent(box.value.trim()));'), nl,
    write('  history.replaceState(null, "", location.pathname + location.search + (parts.length ? "#" + parts.join("&") : ""));'), nl,
    write('}'), nl,
    write('(function () {'), nl,
    write('  const h = location.hash.slice(1);'), nl,
    write('  if (h.indexOf("bug-") === 0) {'), nl,
    write('    const el = document.getElementById(h);'), nl,
    write('    if (el && el.tagName === "DETAILS") {'), nl,
    write('      bugChips().forEach(b => { const v = el.dataset[b.dataset.group]; if (v !== undefined && v.split(" ").indexOf(b.dataset.value) >= 0 && b.dataset.group !== "keyword") b.classList.add("active"); });'), nl,
    write('      bugsApply(); el.open = true; el.scrollIntoView();'), nl,
    write('      return;'), nl,
    write('    }'), nl,
    write('  }'), nl,
    write('  if (h && h.indexOf("=") > 0) {'), nl,
    write('    h.split("&").forEach(p => {'), nl,
    write('      const i = p.indexOf("="), g = p.slice(0, i), vs = p.slice(i + 1);'), nl,
    write('      if (g === "q") { const box = document.getElementById("bug-search"); if (box) box.value = decodeURIComponent(vs); return; }'), nl,
    write('      const want = vs ? vs.split(",") : [];'), nl,
    write('      bugChips().filter(b => b.dataset.group === g).forEach(b => b.classList.toggle("active", want.indexOf(b.dataset.value) >= 0));'), nl,
    write('    });'), nl,
    write('    bugsToggleFilters(true);'), nl,
    write('  }'), nl,
    write('  bugsApply();'), nl,
    write('})();'), nl,
    write('</script>'), nl.
