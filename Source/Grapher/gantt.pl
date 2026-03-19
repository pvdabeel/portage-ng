/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> GANTT
Interactive Gantt chart HTML visualisation of a portage-ng execution plan.
Generates a self-contained HTML file with step-based timeline, per-package
detail rows (USE flags, downloads), phase and dependency-type filters, and SVG
dependency arrows.
*/

:- module(gantt, []).

% =============================================================================
%  GANTT declarations
% =============================================================================


% -----------------------------------------------------------------------------
%  Entry point
% -----------------------------------------------------------------------------

%! gantt:graph(+Target)
%
% Generate a Gantt chart HTML document for Target to current output stream.
% Runs the proof pipeline, collects the grid and dependencies, then emits HTML.

gantt:graph(Repository://Entry) :-
    pipeline:prove_plan_with_fallback([Repository://Entry:run?{[]}],
                                      ProofAVL, _ModelAVL, Plan, _Triggers),
    gantt:emit(Repository://Entry, ProofAVL, Plan).


%! gantt:emit(+Target, +ProofAVL, +Plan)
%
% Emit the Gantt chart HTML for Target given a pre-computed proof and plan.

gantt:emit(Repository://Entry, ProofAVL, Plan) :-
    gantt:collect_grid(Plan, Grid, NumSteps),
    gantt:collect_deps(ProofAVL, Grid, Deps),
    gantt:emit_html(Repository://Entry, Grid, Deps, NumSteps).


% -----------------------------------------------------------------------------
%  Data collection from plan
% -----------------------------------------------------------------------------

%! gantt:collect_grid(+Plan, -Grid, -NumSteps)
%
% Walk the plan and build a grid of package actions. Grid is a list of pkg/7
% terms sorted by first appearance. NumSteps is the total step count.

gantt:collect_grid(Plan, Grid, NumSteps) :-
    collect_grid_steps(Plan, 1, [], Acc),
    build_grid(Acc, Grid),
    max_used_step(Grid, NumSteps).

max_used_step(Grid, Max) :-
    findall(S, (member(pkg(_,_,_,_,_,_,Acts), Grid), member(S-_, Acts)), Steps),
    (   Steps == []
    ->  Max = 0
    ;   max_list(Steps, Max)
    ).

collect_grid_steps([], _, Acc, Acc).
collect_grid_steps([Step|Steps], N, Acc, Out) :-
    collect_step_rules(Step, N, Acc, Acc1),
    N1 is N + 1,
    collect_grid_steps(Steps, N1, Acc1, Out).

collect_step_rules([], _, Acc, Acc).
collect_step_rules([Rule|Rules], N, Acc, Out) :-
    (   rule_pkg_action(Rule, Repo, Entry, Action),
        visible_action(Action)
    ->  add_action(Repo, Entry, N, Action, Acc, Acc1)
    ;   Acc1 = Acc
    ),
    collect_step_rules(Rules, N, Acc1, Out).

rule_pkg_action(rule(Head, _), Repo, Entry, Action) :-
    prover:canon_literal(Head, Repo://Entry:Action, _).
rule_pkg_action(assumed(rule(Head, _)), Repo, Entry, Action) :-
    prover:canon_literal(Head, Repo://Entry:Action, _).

visible_action(download).
visible_action(install).
visible_action(run).
visible_action(update).
visible_action(downgrade).
visible_action(reinstall).
visible_action(fetchonly).

add_action(Repo, Entry, StepN, Action, Acc, Acc1) :-
    (   select(Entry-pacc(Id, Repo, Cat, Name, Ver, Acts), Acc, Rest)
    ->  Acc1 = [Entry-pacc(Id, Repo, Cat, Name, Ver, [StepN-Action|Acts])|Rest]
    ;   (   cache:ordered_entry(Repo, Entry, Cat, Name, Version)
        ->  gantt:version_str(Version, Ver),
            gantt:make_id(Name, Id),
            Acc1 = [Entry-pacc(Id, Repo, Cat, Name, Ver, [StepN-Action])|Acc]
        ;   Acc1 = Acc
        )
    ).

build_grid(Pairs, Grid) :-
    reverse(Pairs, Ordered),
    maplist(pair_to_pkg, Ordered, Grid0),
    disambiguate_ids(Grid0, Grid).

pair_to_pkg(Entry-pacc(Id, Repo, Cat, Name, Ver, Acts0),
            pkg(Id, Repo, Entry, Cat, Name, Ver, Acts)) :-
    msort(Acts0, Acts).

disambiguate_ids(Grid0, Grid) :-
    maplist(pkg_id, Grid0, Ids),
    msort(Ids, Sorted),
    find_dups(Sorted, Dups),
    (   Dups == []
    ->  Grid = Grid0
    ;   maplist(fix_dup_id(Dups), Grid0, Grid)
    ).

pkg_id(pkg(Id, _, _, _, _, _, _), Id).

find_dups([], []).
find_dups([X, X|T], [X|Ds]) :- !, skip_same(X, T, Rest), find_dups(Rest, Ds).
find_dups([_|T], Ds) :- find_dups(T, Ds).

skip_same(X, [X|T], Rest) :- !, skip_same(X, T, Rest).
skip_same(_, L, L).

fix_dup_id(Dups, pkg(Id, Repo, Entry, Cat, Name, Ver, Acts),
                 pkg(NewId, Repo, Entry, Cat, Name, Ver, Acts)) :-
    (   memberchk(Id, Dups)
    ->  gantt:make_id(Cat, CatId),
        atomic_list_concat([CatId, '-', Id], NewId)
    ;   NewId = Id
    ).


% -----------------------------------------------------------------------------
%  Dependency collection from proof
% -----------------------------------------------------------------------------

%! gantt:collect_deps(+ProofAVL, +Grid, -Deps)
%
% Extract cross-package dependency edges from the proof. Returns a sorted list
% of dep(FromId, FromAct, ToId, ToAct, DepType) terms.

gantt:collect_deps(ProofAVL, Grid, Deps) :-
    maplist(entry_id_pair, Grid, EntryMap),
    build_pd_resolutions(ProofAVL, PDRes),
    assoc_to_list(ProofAVL, Pairs),
    findall(dep(DepId, DepAct, PkgId, PkgAct, DepType),
        (   member(KV, Pairs),
            KV = rule(Core)-Val,
            Val = dep(_, Body)?_,
            Core = _R://PkgEntry:PkgAct,
            memberchk(PkgEntry-PkgId, EntryMap),
            member(BodyLit, Body),
            catch(prover:canon_literal(BodyLit, BodyCore, _), _, fail),
            resolve_body(BodyCore, PDRes, EntryMap, DepId, DepAct, DepType),
            PkgId \= DepId
        ),
        Deps0),
    sort(Deps0, Deps).

entry_id_pair(pkg(Id, _, Entry, _, _, _, _), Entry-Id).


%! gantt:build_pd_resolutions(+ProofAVL, -PDRes)
%
% Pre-compute resolutions for package_dependency intermediate nodes.

build_pd_resolutions(ProofAVL, PDRes) :-
    assoc_to_list(ProofAVL, Pairs),
    findall(pd(PDCore, Phase, DepEntry, DepAct),
        (   member(KV, Pairs),
            KV = rule(PDCore)-Val,
            Val = dep(_, PDBody)?_,
            pd_phase(PDCore, Phase),
            member(Lit, PDBody),
            catch(prover:canon_literal(Lit, _R://DepEntry:DepAct, _), _, fail)
        ),
        PDRes).

pd_phase(package_dependency(Phase, _, _, _, _, _, _, _):_, Phase).
pd_phase(grouped_package_dependency(_, _, _, PackageDeps):_, Phase) :-
    member(package_dependency(Phase, _, _, _, _, _, _, _), PackageDeps).

resolve_body(_R://DepEntry:DepAct, _, EntryMap, DepId, DepAct, depend) :-
    memberchk(DepEntry-DepId, EntryMap), !.
resolve_body(BodyCore, PDRes, EntryMap, DepId, DepAct, DepType) :-
    member(pd(BodyCore, Phase, DepEntry, DepAct), PDRes),
    memberchk(DepEntry-DepId, EntryMap),
    phase_deptype(Phase, DepType), !.

phase_deptype(install, depend).
phase_deptype(run, rdepend).
phase_deptype(pdepend, pdepend).
phase_deptype(compile, depend).
phase_deptype(_, depend).


% -----------------------------------------------------------------------------
%  Per-package metadata
% -----------------------------------------------------------------------------

%! gantt:pkg_use_flags(+Repo, +Entry, -Flags)
%
% Retrieve USE flags for an entry. Flags is a list of flag(Name, on|off).

gantt:pkg_use_flags(Repo, Entry, Flags) :-
    findall(flag(Use, OnOff),
        (   query:search(iuse_filtered(Use, State:_), Repo://Entry),
            (State == positive -> OnOff = on ; OnOff = off)
        ),
        Flags0),
    sort(Flags0, Flags),
    !.
gantt:pkg_use_flags(_, _, []).


%! gantt:pkg_src_uris(+Repo, +Entry, -Uris)
%
% Retrieve source URIs for an entry. Uris is a list of
% src(Url, Filename, SizeBytes, Status) with resolved URLs, manifest sizes,
% and local cache status (cached or pending).

gantt:pkg_src_uris(Repo, Entry, Uris) :-
    findall(src(Url, Local, Size, Status),
        (   query:search(src_uri(uri(Proto, Base, Local)), Repo://Entry),
            resolve_url(Proto, Base, Local, Url),
            manifest_size(Repo, Entry, Local, Size),
            (distfiles:present(Local) -> Status = cached ; Status = pending)
        ),
        Uris0),
    sort(2, @<, Uris0, Uris),
    !.
gantt:pkg_src_uris(_, _, []).

resolve_url(Proto, Base, Local, Url) :-
    (   var(Proto) ; var(Base) ; Proto == '' ),
    !,
    atom_concat('https://distfiles.gentoo.org/distfiles/', Local, Url).
resolve_url(mirror, Base, _Local, Url) :-
    !,
    (   catch(download:resolve_mirror_uri(Base, _, Url0), _, fail)
    ->  Url = Url0
    ;   atomic_list_concat(['mirror://', Base], Url)
    ).
resolve_url(Proto, Base, _Local, Url) :-
    atomic_list_concat([Proto, '://', Base], Url).

manifest_size(Repo, Entry, Filename, Size) :-
    (   kb:query(manifest(all, dist, Filename, S), Repo://Entry)
    ->  Size = S
    ;   Size = 0
    ).


% -----------------------------------------------------------------------------
%  Download size aggregation
% -----------------------------------------------------------------------------

%! gantt:collect_download_totals(+Grid, +Repo, -TotalBytes, -CachedBytes)
%
% Sum manifest sizes across all grid packages. CachedBytes counts only files
% that are locally present in the distfiles directory.

collect_download_totals(Grid, Repo, TotalBytes, CachedBytes) :-
    findall(Size-Cached,
        (   member(pkg(_, Repo, Entry, _, _, _, _), Grid),
            query:search(src_uri(uri(_, _, Local)), Repo://Entry),
            manifest_size(Repo, Entry, Local, Size),
            (distfiles:present(Local) -> Cached = Size ; Cached = 0)
        ),
        Pairs),
    foldl(sum_pair, Pairs, 0-0, TotalBytes-CachedBytes).

sum_pair(S-C, T0-C0, T1-C1) :-
    T1 is T0 + S,
    C1 is C0 + C.


% -----------------------------------------------------------------------------
%  HTML emission - main
% -----------------------------------------------------------------------------

%! gantt:emit_html(+Target, +Grid, +Deps, +NumSteps)
%
% Emit a complete self-contained HTML document to the current output stream.

gantt:emit_html(Target, Grid, Deps, NumSteps) :-
    Target = Repo://Entry,
    cache:ordered_entry(Repo, Entry, Cat, Name, Version),
    gantt:version_str(Version, Ver),
    length(Grid, PkgCount),
    collect_download_totals(Grid, Repo, TotalBytes, CachedBytes),
    emit_doctype,
    emit_head_open,
    emit_css,
    emit_head_close,
    emit_body_open,
    emit_title(Cat, Name, Ver),
    emit_subtitle(PkgCount, NumSteps, TotalBytes, CachedBytes),
    gantt:pkg_use_flags(Repo, Entry, TargetFlags),
    emit_global_use(TargetFlags),
    emit_filters,
    emit_table_open,
    emit_thead(NumSteps),
    emit_tbody(Grid, NumSteps, Repo),
    emit_table_close,
    emit_legend,
    emit_script(Grid, Deps),
    emit_body_close.


% -----------------------------------------------------------------------------
%  HTML emission - document structure
% -----------------------------------------------------------------------------

emit_doctype :-
    write('<!DOCTYPE html>'), nl.

emit_head_open :-
    write('<html lang="en">'), nl,
    write('<head>'), nl,
    write('<meta charset="UTF-8">'), nl,
    write('<meta name="viewport" content="width=device-width, initial-scale=1.0">'), nl.

emit_head_close :-
    write('</head>'), nl.

emit_body_open :-
    write('<body>'), nl.

emit_body_close :-
    write('</body>'), nl,
    write('</html>'), nl.

emit_title(Cat, Name, Ver) :-
    format('<h1>~w/~w-~w &mdash; Execution Plan</h1>~n', [Cat, Name, Ver]).

emit_subtitle(PkgCount, NumSteps, TotalBytes, CachedBytes) :-
    format_size(TotalBytes, TotalStr),
    format_size(CachedBytes, CachedStr),
    format('<p class="subtitle">~w packages &middot; ~w steps &middot; ', [PkgCount, NumSteps]),
    format('download ~w', [TotalStr]),
    (   CachedBytes > 0
    ->  format(' (~w cached)', [CachedStr])
    ;   true
    ),
    write('</p>'), nl.

emit_global_use([]) :- !.
emit_global_use(Flags) :-
    write('<div class="global-use">'), nl,
    write('  <span class="global-use-label">USE</span>'), nl,
    write('  <span class="use-expand-btn" onclick="toggleUseExpand()">&#9654;</span>'), nl,
    write('  <span class="use-flags" id="global-use-flags">'), nl,
    maplist(emit_use_flag_span, Flags),
    write('  </span>'), nl,
    write('</div>'), nl.


% -----------------------------------------------------------------------------
%  HTML emission - filters
% -----------------------------------------------------------------------------

emit_filters :-
    write('<div class="filters">'), nl,
    write('  <span class="label">Phases:</span>'), nl,
    write('  <button class="filter-btn active" data-action="download" onclick="toggleFilter(this)">download</button>'), nl,
    write('  <button class="filter-btn active" data-action="install" onclick="toggleFilter(this)">install</button>'), nl,
    write('  <button class="filter-btn active" data-action="run" onclick="toggleFilter(this)">run</button>'), nl,
    write('  <div class="sep"></div>'), nl,
    write('  <button class="filter-btn" style="background:#fff;border-color:#aaa;color:#555" onclick="expandAll()">expand all</button>'), nl,
    write('  <button class="filter-btn" style="background:#fff;border-color:#aaa;color:#555" onclick="collapseAll()">collapse all</button>'), nl,
    write('  <div class="sep"></div>'), nl,
    write('  <span class="label">Deps:</span>'), nl,
    write('  <button class="filter-btn active" data-action="bdepend" onclick="toggleFilter(this)">BDEPEND</button>'), nl,
    write('  <button class="filter-btn active" data-action="depend" onclick="toggleFilter(this)">DEPEND</button>'), nl,
    write('  <button class="filter-btn active" data-action="rdepend" onclick="toggleFilter(this)">RDEPEND</button>'), nl,
    write('  <button class="filter-btn active" data-action="pdepend" onclick="toggleFilter(this)">PDEPEND</button>'), nl,
    write('  <button class="filter-btn active" data-action="idepend" onclick="toggleFilter(this)">IDEPEND</button>'), nl,
    write('</div>'), nl.


% -----------------------------------------------------------------------------
%  HTML emission - table
% -----------------------------------------------------------------------------

emit_table_open :-
    write('<div class="gantt-wrapper" id="gantt-wrapper">'), nl,
    write('<table class="gantt" id="gantt">'), nl.

emit_table_close :-
    write('</table>'), nl,
    write('<svg class="deps" id="dep-svg"></svg>'), nl,
    write('</div>'), nl.

emit_thead(NumSteps) :-
    write('  <thead><tr>'), nl,
    write('    <th>Package</th>'), nl,
    forall(between(1, NumSteps, N),
        format('    <th>Step ~w</th>~n', [N])),
    write('  </tr></thead>'), nl.

emit_tbody(Grid, NumSteps, Repo) :-
    write('  <tbody>'), nl,
    maplist(emit_pkg_rows(NumSteps, Repo), Grid),
    write('  </tbody>'), nl.


%! gantt:emit_pkg_rows(+NumSteps, +Repo, +Pkg)
%
% Emit the main row and detail row for a single package.

emit_pkg_rows(NumSteps, Repo, pkg(Id, Repo, Entry, Cat, Name, Ver, Actions)) :-
    action_types_atom(Actions, TypesAtom),
    format('    <tr data-pkg="~w" data-actions="~w">~n', [Id, TypesAtom]),
    format('      <td class="pkg"><span class="toggle" onclick="toggleDetail(this)">&#9654;</span>~w/~w-~w</td>~n',
           [Cat, Name, Ver]),
    emit_step_cells(Id, Actions, 1, NumSteps),
    write('    </tr>'), nl,
    emit_detail_row(Id, Repo, Entry, NumSteps).

action_types_atom(Actions, Atom) :-
    findall(A, member(_-A, Actions), As0),
    sort(As0, As),
    atomic_list_concat(As, ' ', Atom).

emit_step_cells(_, _, N, NumSteps) :-
    N > NumSteps, !.
emit_step_cells(Id, Actions, N, NumSteps) :-
    (   member(N-Action, Actions)
    ->  action_css(Action, Css),
        action_label(Action, Label),
        action_id_suffix(Action, Suf),
        format('      <td><span class="cell ~w" data-type="~w" id="~w-~w">~w</span></td>~n',
               [Css, Action, Id, Suf, Label])
    ;   write('      <td class="empty"></td>'), nl
    ),
    N1 is N + 1,
    emit_step_cells(Id, Actions, N1, NumSteps).

action_css(download, dl).
action_css(install, inst).
action_css(run, run).
action_css(update, inst).
action_css(downgrade, inst).
action_css(reinstall, inst).
action_css(fetchonly, dl).

action_label(download, download).
action_label(install, install).
action_label(run, run).
action_label(update, update).
action_label(downgrade, downgrade).
action_label(reinstall, reinstall).
action_label(fetchonly, fetchonly).

action_id_suffix(download, dl).
action_id_suffix(install, inst).
action_id_suffix(run, run).
action_id_suffix(update, inst).
action_id_suffix(downgrade, inst).
action_id_suffix(reinstall, inst).
action_id_suffix(fetchonly, dl).


% -----------------------------------------------------------------------------
%  HTML emission - detail rows
% -----------------------------------------------------------------------------

emit_detail_row(Id, Repo, Entry, NumSteps) :-
    format('    <tr class="detail-row" data-parent="~w">~n', [Id]),
    write('      <td class="detail-pkg">'), nl,
    gantt:pkg_use_flags(Repo, Entry, Flags),
    emit_use_section(Flags),
    write('      </td>'), nl,
    write('      <td class="detail-dl">'), nl,
    gantt:pkg_src_uris(Repo, Entry, Uris),
    emit_src_table(Uris),
    write('      </td>'), nl,
    EmptyCount is NumSteps - 1,
    forall(between(1, EmptyCount, _),
        (write('      <td class="detail-empty"></td>'), nl)),
    write('    </tr>'), nl.

emit_use_section([]) :- !.
emit_use_section(Flags) :-
    write('        <div class="detail-label">USE</div>'), nl,
    write('        <div class="use-flags">'), nl,
    maplist(emit_use_flag_span, Flags),
    write('        </div>'), nl.

emit_use_flag_span(flag(Name, on)) :-
    format('          <span class="use-flag on">+~w</span>~n', [Name]).
emit_use_flag_span(flag(Name, off)) :-
    format('          <span class="use-flag off">-~w</span>~n', [Name]).

emit_src_table([]) :- !.
emit_src_table(Uris) :-
    write('        <table class="src-table">'), nl,
    maplist(emit_src_row, Uris),
    write('        </table>'), nl.

emit_src_row(src(Url, Filename, SizeBytes, Status)) :-
    format_size(SizeBytes, SizeStr),
    status_label(Status, CssClass, Label),
    format('          <tr><td><a href="~w" target="_blank">~w</a></td><td class="sz">~w</td><td><span class="src-status ~w">~w</span></td></tr>~n',
           [Url, Filename, SizeStr, CssClass, Label]).

status_label(cached, cached, cached).
status_label(pending, pending, fetch).

format_size(0, '-') :- !.
format_size(B, Str) :-
    B >= 1048576, !,
    V is B / 1048576,
    format(atom(Str), '~1f MB', [V]).
format_size(B, Str) :-
    B >= 1024, !,
    V is B / 1024,
    format(atom(Str), '~0f KB', [V]).
format_size(B, Str) :-
    format(atom(Str), '~w B', [B]).


% -----------------------------------------------------------------------------
%  HTML emission - legend
% -----------------------------------------------------------------------------

emit_legend :-
    write('<div class="legend">'), nl,
    write('  <div class="legend-item"><div class="legend-swatch" style="background:var(--dl);border-color:var(--dl-b)"></div>download</div>'), nl,
    write('  <div class="legend-item"><div class="legend-swatch" style="background:var(--inst);border-color:var(--inst-b)"></div>install</div>'), nl,
    write('  <div class="legend-item"><div class="legend-swatch" style="background:var(--run);border-color:var(--run-b)"></div>run</div>'), nl,
    write('  <div class="legend-item"><svg width="24" height="12"><line x1="0" y1="6" x2="18" y2="6" stroke="var(--bdepend)" stroke-width="1.5"/><polygon points="18,3.5 24,6 18,8.5" fill="var(--bdepend)"/></svg>BDEPEND</div>'), nl,
    write('  <div class="legend-item"><svg width="24" height="12"><line x1="0" y1="6" x2="18" y2="6" stroke="var(--depend)" stroke-width="1.5"/><polygon points="18,3.5 24,6 18,8.5" fill="var(--depend)"/></svg>DEPEND</div>'), nl,
    write('  <div class="legend-item"><svg width="24" height="12"><line x1="0" y1="6" x2="18" y2="6" stroke="var(--rdepend)" stroke-width="1.5"/><polygon points="18,3.5 24,6 18,8.5" fill="var(--rdepend)"/></svg>RDEPEND</div>'), nl,
    write('  <div class="legend-item"><svg width="24" height="12"><line x1="0" y1="6" x2="18" y2="6" stroke="var(--pdepend)" stroke-width="1.5" stroke-dasharray="4,2"/><polygon points="18,3.5 24,6 18,8.5" fill="var(--pdepend)"/></svg>PDEPEND</div>'), nl,
    write('  <div class="legend-item"><svg width="24" height="12"><line x1="0" y1="6" x2="18" y2="6" stroke="var(--idepend)" stroke-width="1.5" stroke-dasharray="2,2"/><polygon points="18,3.5 24,6 18,8.5" fill="var(--idepend)"/></svg>IDEPEND</div>'), nl,
    write('  <div class="legend-item"><svg width="24" height="12"><line x1="0" y1="6" x2="24" y2="6" stroke="var(--bar)" stroke-width="2" stroke-dasharray="4,3"/></svg>same pkg</div>'), nl,
    write('</div>'), nl.


% -----------------------------------------------------------------------------
%  HTML emission - CSS
% -----------------------------------------------------------------------------

emit_css :-
    write('<style>'), nl,
    write('  :root {'), nl,
    write('    --dl:  #e1f5fe; --dl-b:  #0288d1;'), nl,
    write('    --inst:#dae8fc; --inst-b:#6c8ebf;'), nl,
    write('    --run: #d5e8d4; --run-b: #82b366;'), nl,
    write('    --bar: #bdbdbd;'), nl,
    write('    --bg:  #fdfdfd;'), nl,
    write('    --hdr: #f5f5f5;'), nl,
    write('    --bdepend: #ef6c00; --depend: #e53935; --rdepend: #7e57c2;'), nl,
    write('    --pdepend: #00897b; --idepend: #6d4c41;'), nl,
    write('    --sub-bg: #f7f8fa;'), nl,
    write('  }'), nl,
    write('  * { box-sizing: border-box; margin: 0; padding: 0; }'), nl,
    write('  body { font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;'), nl,
    write('         background: var(--bg); color: #333; padding: 32px; }'), nl,
    write('  h1 { font-size: 18px; font-weight: 600; margin-bottom: 6px; }'), nl,
    write('  .global-use { display: flex; align-items: center; gap: 5px;'), nl,
    write('                margin-bottom: 6px; flex-wrap: wrap; }'), nl,
    write('  .global-use-label { font-size: 9px; font-weight: 600; color: #999;'), nl,
    write('                      text-transform: uppercase; letter-spacing: 0.5px; }'), nl,
    write('  .use-expand-btn { cursor: pointer; user-select: none; font-size: 8px;'), nl,
    write('                    color: #999; transition: transform 0.15s;'), nl,
    write('                    display: inline-block; }'), nl,
    write('  .use-expand-btn.open { transform: rotate(90deg); color: #555; }'), nl,
    write('  .use-flags { display: flex; gap: 3px; flex-wrap: wrap; }'), nl,
    write('  .use-flags.collapsed { display: none; }'), nl,
    write('  .use-flag { font-size: 8px; padding: 1px 5px; border-radius: 3px;'), nl,
    write('              font-family: "SF Mono", Menlo, monospace; font-weight: 500; }'), nl,
    write('  .use-flag.on  { background: #e8f5e9; color: #2e7d32; border: 1px solid #a5d6a7; }'), nl,
    write('  .use-flag.off { background: #fafafa; color: #bbb;    border: 1px solid #e0e0e0;'), nl,
    write('                  text-decoration: line-through; }'), nl,
    write('  .subtitle { font-size: 12px; color: #888; margin-bottom: 16px; }'), nl,
    write('  .filters { display: flex; gap: 5px; margin-bottom: 16px; align-items: center;'), nl,
    write('             flex-wrap: wrap; }'), nl,
    write('  .filters .label { font-size: 11px; font-weight: 600; color: #666;'), nl,
    write('                    margin-right: 2px; }'), nl,
    write('  .filter-btn { display: inline-flex; align-items: center; gap: 4px;'), nl,
    write('                padding: 3px 8px; border-radius: 4px; border: 1.5px solid;'), nl,
    write('                font-size: 10px; font-weight: 500; cursor: pointer;'), nl,
    write('                transition: opacity 0.15s, box-shadow 0.15s;'), nl,
    write('                user-select: none; }'), nl,
    write('  .filter-btn.active { box-shadow: 0 0 0 2px rgba(0,0,0,0.08); }'), nl,
    write('  .filter-btn.off { opacity: 0.3; }'), nl,
    write('  .filter-btn[data-action="download"]  { background: var(--dl);  border-color: var(--dl-b);  color: #01579b; }'), nl,
    write('  .filter-btn[data-action="install"]   { background: var(--inst); border-color: var(--inst-b); color: #1a237e; }'), nl,
    write('  .filter-btn[data-action="run"]       { background: var(--run);  border-color: var(--run-b);  color: #1b5e20; }'), nl,
    write('  .filter-btn[data-action="bdepend"]   { background: #fff3e0; border-color: var(--bdepend); color: #bf360c; }'), nl,
    write('  .filter-btn[data-action="depend"]    { background: #ffebee; border-color: var(--depend);  color: #b71c1c; }'), nl,
    write('  .filter-btn[data-action="rdepend"]   { background: #ede7f6; border-color: var(--rdepend); color: #4527a0; }'), nl,
    write('  .filter-btn[data-action="pdepend"]   { background: #e0f2f1; border-color: var(--pdepend); color: #004d40; }'), nl,
    write('  .filter-btn[data-action="idepend"]   { background: #efebe9; border-color: var(--idepend); color: #3e2723; }'), nl,
    write('  .sep { width: 1px; height: 20px; background: #ddd; margin: 0 4px; }'), nl,
    write('  .gantt-wrapper { position: relative; overflow-x: auto; }'), nl,
    write('  table.gantt { border-collapse: collapse; width: 100%; min-width: 1100px; }'), nl,
    write('  table.gantt th, table.gantt td {'), nl,
    write('    padding: 4px 6px; font-size: 10px; text-align: center;'), nl,
    write('    border: 1px solid #e0e0e0; white-space: nowrap;'), nl,
    write('  }'), nl,
    write('  table.gantt th { background: var(--hdr); font-weight: 600; position: sticky; top: 0; z-index: 2; }'), nl,
    write('  table.gantt td.pkg { text-align: left; font-weight: 500; background: #fafafa;'), nl,
    write('                       min-width: 210px; position: sticky; left: 0; z-index: 1;'), nl,
    write('                       border-right: 2px solid #ccc; }'), nl,
    write('  table.gantt td.empty { background: #fff; }'), nl,
    write('  .cell { border-radius: 3px; padding: 2px 5px; font-size: 9px; font-weight: 500;'), nl,
    write('          display: inline-block; min-width: 44px; transition: opacity 0.2s; }'), nl,
    write('  .cell.dl   { background: var(--dl);  border: 1.5px solid var(--dl-b);  color: #01579b; }'), nl,
    write('  .cell.inst { background: var(--inst); border: 1.5px solid var(--inst-b); color: #1a237e; }'), nl,
    write('  .cell.run  { background: var(--run);  border: 1.5px solid var(--run-b);  color: #1b5e20; }'), nl,
    write('  .cell.hidden { opacity: 0.08; pointer-events: none; }'), nl,
    write('  tr.row-hidden { display: none; }'), nl,
    write('  .toggle { cursor: pointer; user-select: none; display: inline-block;'), nl,
    write('            width: 14px; text-align: center; font-size: 9px; color: #999;'), nl,
    write('            margin-right: 3px; transition: transform 0.15s; }'), nl,
    write('  .toggle.open { transform: rotate(90deg); color: #555; }'), nl,
    write('  tr.detail-row { display: none; }'), nl,
    write('  tr.detail-row.visible { display: table-row; }'), nl,
    write('  tr.detail-row td { background: var(--sub-bg); border-top: none; }'), nl,
    write('  tr.detail-row td.detail-pkg { text-align: left; padding: 2px 6px 2px 22px;'), nl,
    write('                                 background: var(--sub-bg); position: sticky;'), nl,
    write('                                 left: 0; z-index: 1; border-right: 2px solid #ccc;'), nl,
    write('                                 vertical-align: top; }'), nl,
    write('  tr.detail-row td.detail-dl  { text-align: left; padding: 2px 4px;'), nl,
    write('                                 background: var(--sub-bg); vertical-align: top; }'), nl,
    write('  tr.detail-row td.detail-empty { background: var(--sub-bg); }'), nl,
    write('  .detail-label { font-size: 8px; font-weight: 600; color: #999;'), nl,
    write('                  text-transform: uppercase; letter-spacing: 0.5px;'), nl,
    write('                  margin-bottom: 2px; }'), nl,
    write('  table.src-table { border-collapse: collapse; width: auto; }'), nl,
    write('  table.src-table td { padding: 0px 3px; font-size: 8px; border: none;'), nl,
    write('                       border-bottom: 1px solid #eee; vertical-align: middle;'), nl,
    write('                       white-space: nowrap; line-height: 1.4; }'), nl,
    write('  table.src-table tr:last-child td { border-bottom: none; }'), nl,
    write('  table.src-table td:nth-child(1) { text-align: left;'), nl,
    write('                       font-family: "SF Mono", Menlo, monospace; font-size: 7.5px; }'), nl,
    write('  table.src-table td:nth-child(1) a { color: #0277bd; text-decoration: none; }'), nl,
    write('  table.src-table td:nth-child(1) a:hover { text-decoration: underline; }'), nl,
    write('  table.src-table td.sz { text-align: right; color: #888; font-size: 7px;'), nl,
    write('                          padding-right: 6px; }'), nl,
    write('  table.src-table td:nth-child(3) { text-align: right; }'), nl,
    write('  .src-status { font-size: 8px; padding: 1px 5px; border-radius: 3px;'), nl,
    write('                white-space: nowrap; }'), nl,
    write('  .src-status.cached  { background: #e8f5e9; color: #2e7d32; }'), nl,
    write('  .src-status.pending { background: #fff3e0; color: #e65100; }'), nl,
    write('  svg.deps { position: absolute; top: 0; left: 0; pointer-events: none; }'), nl,
    write('  .legend { display: flex; gap: 12px; margin-top: 20px; font-size: 10px;'), nl,
    write('            align-items: center; flex-wrap: wrap; }'), nl,
    write('  .legend-item { display: flex; align-items: center; gap: 4px; }'), nl,
    write('  .legend-swatch { width: 12px; height: 12px; border-radius: 2px; border: 1.5px solid; }'), nl,
    write('</style>'), nl.


% -----------------------------------------------------------------------------
%  HTML emission - JavaScript
% -----------------------------------------------------------------------------

emit_script(Grid, Deps) :-
    write('<script>'), nl,
    emit_js_state,
    emit_js_dep_array(Deps, Grid),
    emit_js_functions,
    write('</script>'), nl.

emit_js_state :-
    write('const filters = {'), nl,
    write('  download:true, install:true, run:true,'), nl,
    write('  bdepend:true, depend:true, rdepend:true, pdepend:true, idepend:true'), nl,
    write('};'), nl,
    write('const depColors = {bdepend:"#ef6c00",depend:"#e53935",rdepend:"#7e57c2",pdepend:"#00897b",idepend:"#6d4c41"};'), nl,
    write('const depDash = {bdepend:"",depend:"",rdepend:"",pdepend:"6,3",idepend:"3,3"};'), nl.

emit_js_dep_array(Deps, _Grid) :-
    write('const deps = ['), nl,
    emit_dep_entries(Deps),
    write('];'), nl.

emit_dep_entries([]).
emit_dep_entries([dep(DepId, DepAct, PkgId, PkgAct, DepType)|Rest]) :-
    action_id_suffix(DepAct, DepSuf),
    action_id_suffix(PkgAct, PkgSuf),
    format('  ["~w-~w","~w-~w","~w"]', [DepId, DepSuf, PkgId, PkgSuf, DepType]),
    (Rest == [] -> nl ; (write(','), nl)),
    emit_dep_entries(Rest).

emit_js_functions :-
    write('function toggleFilter(btn){'), nl,
    write('  const a=btn.dataset.action; filters[a]=!filters[a];'), nl,
    write('  btn.classList.toggle("active",filters[a]); btn.classList.toggle("off",!filters[a]);'), nl,
    write('  applyFilters();'), nl,
    write('}'), nl,
    write('function toggleDetail(t){'), nl,
    write('  t.classList.toggle("open");'), nl,
    write('  const p=t.closest("tr").dataset.pkg;'), nl,
    write('  document.querySelectorAll(`tr.detail-row[data-parent="${p}"]`).forEach(d=>d.classList.toggle("visible"));'), nl,
    write('  setTimeout(drawOverlays,20);'), nl,
    write('}'), nl,
    write('function expandAll(){'), nl,
    write('  document.querySelectorAll("#gantt tbody tr[data-pkg]:not(.row-hidden)").forEach(r=>{'), nl,
    write('    const t=r.querySelector(".toggle"); if(t&&!t.classList.contains("open")) t.classList.add("open");'), nl,
    write('    const p=r.dataset.pkg;'), nl,
    write('    document.querySelectorAll(`tr.detail-row[data-parent="${p}"]`).forEach(d=>d.classList.add("visible"));'), nl,
    write('  });'), nl,
    write('  setTimeout(drawOverlays,20);'), nl,
    write('}'), nl,
    write('function collapseAll(){'), nl,
    write('  document.querySelectorAll(".toggle.open").forEach(t=>t.classList.remove("open"));'), nl,
    write('  document.querySelectorAll("tr.detail-row.visible").forEach(d=>d.classList.remove("visible"));'), nl,
    write('  setTimeout(drawOverlays,20);'), nl,
    write('}'), nl,
    write('function applyFilters(){'), nl,
    write('  document.querySelectorAll(".cell[data-type]").forEach(c=>c.classList.toggle("hidden",!filters[c.dataset.type]));'), nl,
    write('  document.querySelectorAll("#gantt tbody tr[data-pkg]").forEach(r=>{'), nl,
    write('    const a=(r.dataset.actions||"").split(" "), v=a.some(x=>filters[x]);'), nl,
    write('    r.classList.toggle("row-hidden",!v);'), nl,
    write('    if(!v){const p=r.dataset.pkg;'), nl,
    write('      document.querySelectorAll(`tr.detail-row[data-parent="${p}"]`).forEach(d=>d.classList.remove("visible"));'), nl,
    write('      const t=r.querySelector(".toggle");if(t)t.classList.remove("open");}'), nl,
    write('  });'), nl,
    write('  drawOverlays();'), nl,
    write('}'), nl,
    write('function drawOverlays(){'), nl,
    write('  const svg=document.getElementById("dep-svg"),wr=document.getElementById("gantt-wrapper"),'), nl,
    write('        wR=wr.getBoundingClientRect(),ns="http://www.w3.org/2000/svg";'), nl,
    write('  svg.setAttribute("width",wr.scrollWidth);svg.setAttribute("height",wr.scrollHeight);svg.innerHTML="";'), nl,
    write('  const defs=document.createElementNS(ns,"defs");'), nl,
    write('  for(const[t,c]of Object.entries(depColors)){'), nl,
    write('    const m=document.createElementNS(ns,"marker");m.setAttribute("id","arrow-"+t);'), nl,
    write('    m.setAttribute("markerWidth","6");m.setAttribute("markerHeight","5");'), nl,
    write('    m.setAttribute("refX","6");m.setAttribute("refY","2.5");m.setAttribute("orient","auto");'), nl,
    write('    const p=document.createElementNS(ns,"polygon");p.setAttribute("points","0 0,6 2.5,0 5");'), nl,
    write('    p.setAttribute("fill",c);m.appendChild(p);defs.appendChild(m);'), nl,
    write('  }svg.appendChild(defs);'), nl,
    write('  document.querySelectorAll("#gantt tbody tr[data-pkg]:not(.row-hidden)").forEach(row=>{'), nl,
    write('    const f=[];row.querySelectorAll("td:not(.pkg)").forEach(td=>{'), nl,
    write('      const s=td.querySelector(".cell:not(.hidden)");if(s)f.push(s);});'), nl,
    write('    for(let i=0;i<f.length-1;i++){'), nl,
    write('      const a=f[i].getBoundingClientRect(),b=f[i+1].getBoundingClientRect(),'), nl,
    write('            l=document.createElementNS(ns,"line");'), nl,
    write('      l.setAttribute("x1",a.right-wR.left+wr.scrollLeft);'), nl,
    write('      l.setAttribute("y1",a.top+a.height/2-wR.top+wr.scrollTop);'), nl,
    write('      l.setAttribute("x2",b.left-wR.left+wr.scrollLeft);'), nl,
    write('      l.setAttribute("y2",b.top+b.height/2-wR.top+wr.scrollTop);'), nl,
    write('      l.setAttribute("stroke","#bdbdbd");l.setAttribute("stroke-width","2");'), nl,
    write('      l.setAttribute("stroke-dasharray","5,4");svg.appendChild(l);}'), nl,
    write('  });'), nl,
    write('  deps.forEach(([fid,tid,dt])=>{'), nl,
    write('    if(!filters[dt])return;'), nl,
    write('    const fe=document.getElementById(fid),te=document.getElementById(tid);'), nl,
    write('    if(!fe||!te||fe.classList.contains("hidden")||te.classList.contains("hidden"))return;'), nl,
    write('    const fr=fe.closest("tr"),tr2=te.closest("tr");'), nl,
    write('    if(fr.classList.contains("row-hidden")||tr2.classList.contains("row-hidden"))return;'), nl,
    write('    const fR=fe.getBoundingClientRect(),tR=te.getBoundingClientRect(),'), nl,
    write('          x1=fR.right-wR.left+wr.scrollLeft+2,y1=fR.top+fR.height/2-wR.top+wr.scrollTop,'), nl,
    write('          x2=tR.left-wR.left+wr.scrollLeft-2,y2=tR.top+tR.height/2-wR.top+wr.scrollTop,'), nl,
    write('          mx=(x1+x2)/2,p=document.createElementNS(ns,"path");'), nl,
    write('    p.setAttribute("d",`M${x1},${y1} C${mx},${y1} ${mx},${y2} ${x2},${y2}`);'), nl,
    write('    p.setAttribute("stroke",depColors[dt]);p.setAttribute("stroke-width","1.2");'), nl,
    write('    p.setAttribute("fill","none");p.setAttribute("marker-end",`url(#arrow-${dt})`);'), nl,
    write('    p.setAttribute("opacity","0.7");if(depDash[dt])p.setAttribute("stroke-dasharray",depDash[dt]);'), nl,
    write('    svg.appendChild(p);'), nl,
    write('  });'), nl,
    write('}'), nl,
    write('function toggleUseExpand(){'), nl,
    write('  const f=document.getElementById("global-use-flags"),'), nl,
    write('        b=f.previousElementSibling;'), nl,
    write('  f.classList.toggle("collapsed");'), nl,
    write('  b.classList.toggle("open");'), nl,
    write('}'), nl,
    write('window.addEventListener("load",drawOverlays);'), nl,
    write('window.addEventListener("resize",drawOverlays);'), nl.


% -----------------------------------------------------------------------------
%  Helpers
% -----------------------------------------------------------------------------

%! gantt:version_str(+Version, -Str)
%
% Convert a version/7 term to a display string.

gantt:version_str(version(_, _, _, _, _, _, Full), Full) :- !.
gantt:version_str(version_none, '') :- !.
gantt:version_str(V, S) :- format(atom(S), '~w', [V]).


%! gantt:make_id(+Name, -Id)
%
% Create an HTML-safe identifier from a package name atom.

gantt:make_id(Name, Id) :-
    atom_chars(Name, Chars),
    maplist(safe_id_char, Chars, SafeChars),
    atom_chars(Id, SafeChars).

safe_id_char(C, C) :- char_type(C, alnum), !.
safe_id_char(-, -) :- !.
safe_id_char(_, '_').


%! gantt:html_escape(+In, -Out)
%
% Escape HTML special characters in an atom.

gantt:html_escape(In, Out) :-
    atom_codes(In, Codes),
    esc_codes(Codes, OutCodes),
    atom_codes(Out, OutCodes).

esc_codes([], []).
esc_codes([0'<|T], Out) :- !, append(`&lt;`, R, Out), esc_codes(T, R).
esc_codes([0'>|T], Out) :- !, append(`&gt;`, R, Out), esc_codes(T, R).
esc_codes([0'&|T], Out) :- !, append(`&amp;`, R, Out), esc_codes(T, R).
esc_codes([0'"|T], Out) :- !, append(`&quot;`, R, Out), esc_codes(T, R).
esc_codes([H|T], [H|R]) :- esc_codes(T, R).