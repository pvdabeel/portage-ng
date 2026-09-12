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
assignee, dates, keywords) plus the packages it names. Rendered as
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
% Row is bug(Id, Summary, State, ThisVersion, Detail): State is `open` or
% `resolved`, ThisVersion is true when the bug names Cat/Name at exactly
% Version, Detail is the bugs:bug_detail/2 key list.

bug_row(Cat, Name, Version, Id, bug(Id, Summary, State, ThisVersion, Detail)) :-
    bugs:bug_detail(Id, Detail),
    memberchk(summary(Summary), Detail),
    memberchk(status(Status), Detail),
    (   bugs:open_status(Status)
    ->  State = open
    ;   State = resolved
    ),
    (   Version \== version_none,
        bugsdata:bug_atom(Id, Cat, Name, Version)
    ->  ThisVersion = true
    ;   ThisVersion = false
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
    aggregate_all(count, member(bug(_, _, _, true, _), Rows), Count).


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
% Summary line plus the filter (all / open / this version) and
% expand / collapse controls. Controls are omitted when no bug names
% the package.

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
        )
    ),
    write('</span>'), nl,
    (   Total > 0
    ->  write('  <span class="glsa-btns">'), nl,
        write('    <button class="filter-btn active" onclick="bugsFilter(\'all\', this)">All</button>'), nl,
        write('    <button class="filter-btn" onclick="bugsFilter(\'open\', this)">Open</button>'), nl,
        write('    <button class="filter-btn" onclick="bugsFilter(\'this\', this)">This version</button>'), nl,
        write('    <span class="sep"></span>'), nl,
        write('    <button class="action-btn" onclick="bugsSetAll(true)">Expand all</button>'), nl,
        write('    <button class="action-btn" onclick="bugsSetAll(false)">Collapse all</button>'), nl,
        write('  </span>'), nl
    ;   true
    ),
    write('</div>'), nl.


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
% open to the stored bug columns.

emit_bug(Repository, bug(Id, Summary, State, ThisVersion, Detail)) :-
    navtheme:html_escape(Summary, SummaryE),
    (   ThisVersion == true -> VerAttr = 'this' ; VerAttr = 'other' ),
    format('<details class="glsa-item bug-item" id="bug-~w" data-status="~w" data-version="~w">~n',
           [Id, State, VerAttr]),
    write('  <summary class="glsa-summary">'), nl,
    write('    <span class="glsa-chevron">&#9656;</span>'), nl,
    format('    <span class="glsa-id">#~w</span>~n', [Id]),
    format('    <span class="glsa-title">~w</span>~n', [SummaryE]),
    write('    <span class="glsa-badges">'), nl,
    emit_state_badge(State, Detail),
    (   ThisVersion == true
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
% Expand / collapse all, the open / this-version filters, and opening
% the bug addressed by the URL fragment (`#bug-<id>`).

emit_script :-
    write('<script>'), nl,
    write('function bugsSetAll(open) {'), nl,
    write('  document.querySelectorAll("details.bug-item").forEach(d => { d.open = open; });'), nl,
    write('}'), nl,
    write('function bugsFilter(mode, btn) {'), nl,
    write('  document.querySelectorAll("details.bug-item").forEach(d => {'), nl,
    write('    const hide = (mode === "open" && d.dataset.status !== "open") ||'), nl,
    write('                 (mode === "this" && d.dataset.version !== "this");'), nl,
    write('    d.classList.toggle("hidden", hide);'), nl,
    write('  });'), nl,
    write('  document.querySelectorAll(".glsa-toolbar .filter-btn").forEach(b => b.classList.toggle("active", b === btn));'), nl,
    write('}'), nl,
    write('(function () {'), nl,
    write('  if (!location.hash) return;'), nl,
    write('  const el = document.getElementById(location.hash.slice(1));'), nl,
    write('  if (el && el.tagName === "DETAILS") { el.open = true; el.scrollIntoView(); }'), nl,
    write('})();'), nl,
    write('</script>'), nl.
