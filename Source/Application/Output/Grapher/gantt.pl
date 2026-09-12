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
    gantt:collect_grid(Plan, Grid0, _NumSteps0),
    gantt:collect_pre_actions(ProofAVL, Grid0, Grid, HasPre),
    max_used_step(Grid, NumSteps),
    gantt:collect_deps(ProofAVL, Grid, Deps),
    gantt:emit_html(Repository://Entry, Grid, Deps, NumSteps, HasPre).


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

%! gantt:max_used_step(+Grid, -Max) is det.
%
% Find the highest step number used in the grid.

gantt:max_used_step(Grid, Max) :-
    findall(S, (member(pkg(_,_,_,_,_,_,Acts), Grid), member(S-_, Acts)), Steps),
    (   Steps == []
    ->  Max = 0
    ;   max_list(Steps, Max)
    ).

%! gantt:collect_grid_steps(+Steps, +N, +Acc, -Out) is det.
%
% Walk plan steps, accumulating package actions with step numbers.

gantt:collect_grid_steps([], _, Acc, Acc).
gantt:collect_grid_steps([Step|Steps], N, Acc, Out) :-
    collect_step_rules(Step, N, Acc, Acc1),
    (   Acc1 \== Acc
    ->  N1 is N + 1
    ;   N1 = N
    ),
    collect_grid_steps(Steps, N1, Acc1, Out).

%! gantt:collect_step_rules(+Rules, +N, +Acc, -Out) is det.
%
% Process rules within a single plan step.

gantt:collect_step_rules([], _, Acc, Acc).
gantt:collect_step_rules([Rule|Rules], N, Acc, Out) :-
    (   rule_pkg_action(Rule, Repo, Entry, Action),
        visible_action(Action)
    ->  add_action(Repo, Entry, N, Action, Acc, Acc1)
    ;   Acc1 = Acc
    ),
    collect_step_rules(Rules, N, Acc1, Out).

%! gantt:rule_pkg_action(+Rule, -Repo, -Entry, -Action) is semidet.
%
% Extract repository, entry, and action from a proof rule term.

gantt:rule_pkg_action(rule(Head, _), Repo, Entry, Action) :-
    prover:canon_literal(Head, Repo://Entry:Action, _).
gantt:rule_pkg_action(assumed(rule(Head, _)), Repo, Entry, Action) :-
    prover:canon_literal(Head, Repo://Entry:Action, _).

%! gantt:visible_action(+Action) is semidet.
%
% Actions that appear as cells in the Gantt chart.

gantt:visible_action(download).
gantt:visible_action(install).
gantt:visible_action(run).
gantt:visible_action(update).
gantt:visible_action(downgrade).
gantt:visible_action(reinstall).
gantt:visible_action(fetchonly).
gantt:visible_action(unmask).
gantt:visible_action(license).
gantt:visible_action(keyword).
gantt:visible_action(useflag).

%! gantt:add_action(+Repo, +Entry, +StepN, +Action, +Acc, -Acc1) is det.
%
% Add an action to the accumulator, creating or updating the package entry.

gantt:add_action(Repo, Entry, StepN, Action, Acc, Acc1) :-
    (   select(Entry-pacc(Id, Repo, Cat, Name, Ver, Acts), Acc, Rest)
    ->  Acc1 = [Entry-pacc(Id, Repo, Cat, Name, Ver, [StepN-Action|Acts])|Rest]
    ;   (   cache:ordered_entry(Repo, Entry, Cat, Name, Version)
        ->  version_domain:display_atom(Version, Ver),
            gantt:make_id(Name, Id),
            Acc1 = [Entry-pacc(Id, Repo, Cat, Name, Ver, [StepN-Action])|Acc]
        ;   Acc1 = Acc
        )
    ).

%! gantt:build_grid(+Pairs, -Grid) is det.
%
% Convert accumulated entry-pacc pairs into a sorted grid of pkg/7 terms.

gantt:build_grid(Pairs, Grid) :-
    reverse(Pairs, Ordered),
    maplist(pair_to_pkg, Ordered, Grid0),
    disambiguate_ids(Grid0, Grid).

%! gantt:pair_to_pkg(+Pair, -Pkg) is det.
%
% Convert an Entry-pacc pair into a pkg/7 term with sorted actions.

gantt:pair_to_pkg(Entry-pacc(Id, Repo, Cat, Name, Ver, Acts0),
            pkg(Id, Repo, Entry, Cat, Name, Ver, Acts)) :-
    msort(Acts0, Acts).

%! gantt:disambiguate_ids(+Grid0, -Grid) is det.
%
% Prefix duplicate HTML ids with the category to make them unique.

gantt:disambiguate_ids(Grid0, Grid) :-
    maplist(pkg_id, Grid0, Ids),
    msort(Ids, Sorted),
    find_dups(Sorted, Dups),
    (   Dups == []
    ->  Grid = Grid0
    ;   maplist(fix_dup_id(Dups), Grid0, Grid)
    ).

%! gantt:pkg_id(+Pkg, -Id) is det.
%
% Extract the HTML id from a pkg/7 term.

gantt:pkg_id(pkg(Id, _, _, _, _, _, _), Id).

%! gantt:find_dups(+Sorted, -Dups) is det.
%
% Find duplicate elements in a sorted list.

gantt:find_dups([], []).
gantt:find_dups([X, X|T], [X|Ds]) :- !, skip_same(X, T, Rest), find_dups(Rest, Ds).
gantt:find_dups([_|T], Ds) :- find_dups(T, Ds).

%! gantt:skip_same(+X, +List, -Rest) is det.
%
% Skip consecutive occurrences of X at the head of List.

gantt:skip_same(X, [X|T], Rest) :- !, skip_same(X, T, Rest).
gantt:skip_same(_, L, L).

%! gantt:fix_dup_id(+Dups, +PkgIn, -PkgOut) is det.
%
% Prepend category to the id of packages whose name appears in Dups.

gantt:fix_dup_id(Dups, pkg(Id, Repo, Entry, Cat, Name, Ver, Acts),
                 pkg(NewId, Repo, Entry, Cat, Name, Ver, Acts)) :-
    (   memberchk(Id, Dups)
    ->  gantt:make_id(Cat, CatId),
        atomic_list_concat([CatId, '-', Id], NewId)
    ;   NewId = Id
    ).


% -----------------------------------------------------------------------------
%  Pre-action collection (unmask / keyword / useflag)
% -----------------------------------------------------------------------------

%! gantt:collect_pre_actions(+ProofAVL, +Grid0, -Grid, -NumSteps)
%
% Scan the proof for suggestion(unmask, ...), suggestion(accept_keyword, ...),
% and suggestion(use_change, ...) annotations. Inject them as step 0 actions
% into the grid, shifting existing steps by 1 when pre-actions are found.

gantt:collect_pre_actions(ProofAVL, Grid0, Grid, HasPre) :-
    assoc_to_list(ProofAVL, Pairs),
    findall(Entry-unmask,
            ( member(rule(R://Entry:_A)-(_?Ctx), Pairs),
              is_list(Ctx),
              memberchk(suggestion(unmask, _), Ctx),
              \+ memberchk(suggestion(accept_license, _), Ctx),
              entry_in_grid(Entry, Grid0, R)
            ), Unmasks0),
    sort(Unmasks0, Unmasks),
    findall(Entry-license,
            ( member(rule(R://Entry:_A1)-(_?Ctx1), Pairs),
              is_list(Ctx1),
              memberchk(suggestion(accept_license, _), Ctx1),
              entry_in_grid(Entry, Grid0, R)
            ), Licenses0),
    sort(Licenses0, Licenses),
    findall(Entry-keyword,
            ( member(rule(R://Entry:_A2)-(_?Ctx2), Pairs),
              is_list(Ctx2),
              memberchk(suggestion(accept_keyword, _), Ctx2),
              entry_in_grid(Entry, Grid0, R)
            ), Keywords0),
    sort(Keywords0, Keywords),
    findall(Entry-useflag,
            ( member(rule(R://Entry:_A3)-(_?Ctx3), Pairs),
              is_list(Ctx3),
              memberchk(suggestion(use_change, _, _), Ctx3),
              entry_in_grid(Entry, Grid0, R)
            ), UseChanges0),
    sort(UseChanges0, UseChanges),
    append([Unmasks, Licenses, Keywords, UseChanges], AllPre),
    (   AllPre == []
    ->  Grid = Grid0,
        HasPre = false
    ;   inject_pre_actions(AllPre, Grid0, Grid),
        HasPre = true
    ).

%! gantt:entry_in_grid(+Entry, +Grid, -Repo) is semidet.
%
% Check whether Entry appears in the grid and unify its repository.

gantt:entry_in_grid(Entry, Grid, Repo) :-
    member(pkg(_, Repo, Entry, _, _, _, _), Grid).

%! gantt:inject_pre_actions(+PreActions, +Grid0, -Grid) is det.
%
% Inject step-0 pre-actions into existing grid entries.

gantt:inject_pre_actions([], Grid, Grid).
gantt:inject_pre_actions([Entry-Action|Rest], Grid0, Grid) :-
    (   select(pkg(Id, Repo, Entry, Cat, Name, Ver, Acts0), Grid0, GridRest)
    ->  Grid1 = [pkg(Id, Repo, Entry, Cat, Name, Ver, [0-Action|Acts0])|GridRest]
    ;   Grid1 = Grid0
    ),
    inject_pre_actions(Rest, Grid1, Grid).


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
    collect_pdepend_deps(Pairs, Grid, EntryMap, PdependDeps),
    append(Deps0, PdependDeps, Deps1),
    sort(Deps1, Deps).

%! gantt:entry_id_pair(+Pkg, -EntryIdPair) is det.
%
% Extract an Entry-Id pair from a pkg/7 term for dependency lookup.

gantt:entry_id_pair(pkg(Id, _, Entry, _, _, _, _), Entry-Id).


%! gantt:build_pd_resolutions(+ProofAVL, -PDRes)
%
% Pre-compute resolutions for package_dependency intermediate nodes.

gantt:build_pd_resolutions(ProofAVL, PDRes) :-
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

%! gantt:pd_phase(+PDCore, -Phase) is semidet.
%
% Extract the dependency phase from a package_dependency proof key.

gantt:pd_phase(package_dependency(Phase, _, _, _, _, _, _, _):_, Phase).
gantt:pd_phase(grouped_package_dependency(_, _, _, PackageDeps):_, Phase) :-
    member(package_dependency(Phase, _, _, _, _, _, _, _), PackageDeps).

%! gantt:resolve_body(+BodyCore, +PDRes, +EntryMap, -DepId, -DepAct, -DepType) is semidet.
%
% Resolve a proof body literal to a grid dependency edge.

gantt:resolve_body(_R://DepEntry:DepAct, _, EntryMap, DepId, DepAct, depend) :-
    memberchk(DepEntry-DepId, EntryMap), !.
gantt:resolve_body(BodyCore, PDRes, EntryMap, DepId, DepAct, DepType) :-
    member(pd(BodyCore, Phase, DepEntry, DepAct), PDRes),
    memberchk(DepEntry-DepId, EntryMap),
    phase_deptype(Phase, DepType), !.

%! gantt:phase_deptype(+Phase, -DepType) is det.
%
% Map a dependency phase atom to a dependency type label.

gantt:phase_deptype(install, depend).
gantt:phase_deptype(run, rdepend).
gantt:phase_deptype(pdepend, pdepend).
gantt:phase_deptype(compile, depend).
gantt:phase_deptype(_, depend).


%! gantt:collect_pdepend_deps(+ProofPairs, +Grid, +EntryMap, -Deps)
%
% Reconstruct PDEPEND edges from obligation_done markers in the proof.
% The prover appends PDEPEND goals to the queue (not to the rule body),
% so collect_deps cannot see them. This predicate finds packages whose
% install action triggered a PDEPEND obligation, queries the cache for
% their PDEPEND metadata, and matches targets in the grid.

gantt:collect_pdepend_deps(Pairs, Grid, EntryMap, Deps) :-
    findall(dep(SrcId, SrcAct, DepId, install, pdepend),
        (   member(KV, Pairs),
            KV = obligation_done(pdepend(SrcCore, _))-true,
            SrcCore = Repo://SrcEntry:SrcAct,
            memberchk(SrcEntry-SrcId, EntryMap),
            cache:entry_metadata(Repo, SrcEntry, pdepend, DepTerm),
            pdepend_dep_cn(DepTerm, DepC, DepN),
            member(pkg(DepId, _, _, DepC, DepN, _, _), Grid),
            SrcId \= DepId
        ),
        Deps0),
    sort(Deps0, Deps).


%! gantt:pdepend_dep_cn(+DepTerm, -Category, -Name)
%
% Extract category/name from a PDEPEND dependency term, recursing into
% USE-conditional and any-of groups.

gantt:pdepend_dep_cn(package_dependency(_, _, C, N, _, _, _, _), C, N).
gantt:pdepend_dep_cn(use_conditional_group(_, _, _, Deps), C, N) :-
    member(D, Deps), pdepend_dep_cn(D, C, N).
gantt:pdepend_dep_cn(any_of_group(Deps), C, N) :-
    member(D, Deps), pdepend_dep_cn(D, C, N).


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

%! gantt:resolve_url(+Proto, +Base, +Local, -Url) is det.
%
% Construct a full download URL from protocol, base, and local filename.

gantt:resolve_url(Proto, Base, Local, Url) :-
    (   var(Proto) ; var(Base) ; Proto == '' ),
    !,
    atom_concat('https://distfiles.gentoo.org/distfiles/', Local, Url).
gantt:resolve_url(mirror, Base, _Local, Url) :-
    !,
    (   catch(download:resolve_mirror_uri(Base, _, Url0), _, fail)
    ->  Url = Url0
    ;   atomic_list_concat(['mirror://', Base], Url)
    ).
gantt:resolve_url(Proto, Base, _Local, Url) :-
    atomic_list_concat([Proto, '://', Base], Url).

%! gantt:manifest_size(+Repo, +Entry, +Filename, -Size) is det.
%
% Look up the manifest size for a distfile, defaulting to 0.

gantt:manifest_size(Repo, Entry, Filename, Size) :-
    (   kb:query(manifest(all, dist, Filename, S), Repo://Entry)
    ->  Size = S
    ;   Size = 0
    ).


% -----------------------------------------------------------------------------
%  HTML emission - main
% -----------------------------------------------------------------------------

%! gantt:emit_html(+Target, +Grid, +Deps, +NumSteps, +HasPre)
%
% Emit a complete self-contained HTML document to the current output stream.
% HasPre is true when pre-actions (unmask/keyword/useflag) exist at step 0.

gantt:emit_html(Target, Grid, Deps, NumSteps, HasPre) :-
    Target = Repo://Entry,
    cache:ordered_entry(Repo, Entry, Cat, Name, Version),
    version_domain:display_atom(Version, Ver),
    (HasPre == true -> MinStep = 0 ; MinStep = 1),
    format(atom(Title), '~w/~w-~w &mdash; Execution Plan', [Cat, Name, Ver]),
    navtheme:emit_doctype,
    navtheme:emit_head_open(Title, '../'),
    navtheme:emit_head_close,
    navtheme:emit_body_open('page-gantt'),
    navtheme:emit_top_bar('../', Repo, Cat, Name, Ver),
    navtheme:emit_main_open,
    navtheme:emit_page_head_open,
    deptree:version_neighbours(Repo, Entry, Newer, Newest, Older, Oldest),
    navtheme:emit_nav_bar(Repo, Entry, Cat, Name, gantt, Newer, Newest, Older, Oldest, Ver),
    navtheme:emit_page_head_close,
    navtheme:emit_term_open('portage-ng gantt'),
    emit_filters,
    gantt:pkg_use_flags(Repo, Entry, TargetFlags),
    emit_global_use(TargetFlags),
    emit_table_open,
    emit_thead(MinStep, NumSteps),
    emit_tbody(Grid, MinStep, NumSteps, Repo),
    emit_table_close,
    emit_legend,
    navtheme:emit_term_close,
    emit_script(Grid, Deps),
    navtheme:emit_main_close,
    navtheme:emit_theme_script,
    navtheme:emit_body_close.


% -----------------------------------------------------------------------------
%  HTML emission - document structure
% -----------------------------------------------------------------------------

%! gantt:emit_global_use(+Flags) is det.
%
% Emit the collapsible global USE flags section for the target package.

gantt:emit_global_use([]) :- !.
gantt:emit_global_use(Flags) :-
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

%! gantt:emit_filters is det.
%
% Emit the phase, action, and dependency type filter buttons.

gantt:emit_filters :-
    write('<div class="filters">'), nl,
    write('  <div class="filter-row">'), nl,
    write('    <button class="filter-btn active" data-action="download" onclick="toggleFilter(this)">download</button>'), nl,
    write('    <button class="filter-btn active" data-action="fetchonly" onclick="toggleFilter(this)">fetchonly</button>'), nl,
    write('    <button class="filter-btn active" data-action="install" onclick="toggleFilter(this)">install</button>'), nl,
    write('    <button class="filter-btn active" data-action="update" onclick="toggleFilter(this)">:update</button>'), nl,
    write('    <button class="filter-btn active" data-action="reinstall" onclick="toggleFilter(this)">:reinstall</button>'), nl,
    write('    <button class="filter-btn active" data-action="downgrade" onclick="toggleFilter(this)">:downgrade</button>'), nl,
    write('    <button class="filter-btn active" data-action="run" onclick="toggleFilter(this)">run</button>'), nl,
    write('    <span class="sep" aria-hidden="true"></span>'), nl,
    write('    <button class="filter-btn active" data-action="unmask" onclick="toggleFilter(this)">unmask</button>'), nl,
    write('    <button class="filter-btn active" data-action="keyword" onclick="toggleFilter(this)">keyword</button>'), nl,
    write('    <button class="filter-btn active" data-action="useflag" onclick="toggleFilter(this)">useflag</button>'), nl,
    write('    <button class="filter-btn active" data-action="license" onclick="toggleFilter(this)">license</button>'), nl,
    write('    <span class="sep" aria-hidden="true"></span>'), nl,
    write('    <button class="filter-btn active" data-action="bdepend" onclick="toggleFilter(this)">BDEPEND</button>'), nl,
    write('    <button class="filter-btn active" data-action="depend" onclick="toggleFilter(this)">DEPEND</button>'), nl,
    write('    <button class="filter-btn active" data-action="rdepend" onclick="toggleFilter(this)">RDEPEND</button>'), nl,
    write('    <button class="filter-btn active" data-action="pdepend" onclick="toggleFilter(this)">PDEPEND</button>'), nl,
    write('    <button class="filter-btn active" data-action="idepend" onclick="toggleFilter(this)">IDEPEND</button>'), nl,
    write('  </div>'), nl,
    write('  <div class="filter-toolbar">'), nl,
    write('    <button class="action-btn" onclick="expandAll()">Expand All</button>'), nl,
    write('    <button class="action-btn" onclick="collapseAll()">Collapse All</button>'), nl,
    write('    <button class="action-btn" id="hover-mode-btn" onclick="toggleHoverMode(this)" aria-pressed="false" title="Hide dependency edges; show only those of the hovered package">Hover</button>'), nl,
    write('  </div>'), nl,
    write('</div>'), nl.


% -----------------------------------------------------------------------------
%  HTML emission - table
% -----------------------------------------------------------------------------

%! gantt:emit_table_open is det.
%
% Emit the Gantt table wrapper and opening table tag.

gantt:emit_table_open :-
    write('<div class="gantt-wrapper" id="gantt-wrapper">'), nl,
    write('<table class="gantt" id="gantt">'), nl.

%! gantt:emit_table_close is det.
%
% Emit the closing table tag, dependency SVG overlay, and wrapper close.

gantt:emit_table_close :-
    write('</table>'), nl,
    write('<svg class="deps" id="dep-svg"></svg>'), nl,
    write('</div>'), nl.

%! gantt:emit_thead(+MinStep, +NumSteps) is det.
%
% Emit the table header row with step column headings.

gantt:emit_thead(MinStep, NumSteps) :-
    write('  <thead><tr>'), nl,
    write('    <th>Package</th>'), nl,
    (   MinStep =:= 0
    ->  write('    <th>Pre</th>'), nl
    ;   true
    ),
    forall(between(1, NumSteps, N),
        format('    <th>Step ~w</th>~n', [N])),
    write('  </tr></thead>'), nl.

%! gantt:emit_tbody(+Grid, +MinStep, +NumSteps, +Repo) is det.
%
% Emit the table body with one row per package.

gantt:emit_tbody(Grid, MinStep, NumSteps, Repo) :-
    write('  <tbody>'), nl,
    maplist(emit_pkg_rows(MinStep, NumSteps, Repo), Grid),
    write('  </tbody>'), nl.


%! gantt:emit_pkg_rows(+NumSteps, +Repo, +Pkg)
%
% Emit the main row and detail row for a single package.

gantt:emit_pkg_rows(MinStep, NumSteps, Repo, pkg(Id, Repo, Entry, Cat, Name, Ver, Actions)) :-
    action_types_atom(Actions, TypesAtom),
    format('    <tr data-pkg="~w" data-actions="~w">~n', [Id, TypesAtom]),
    format('      <td class="pkg"><span class="toggle" onclick="toggleDetail(this)">&#9654;</span>~w/~w-~w</td>~n',
           [Cat, Name, Ver]),
    emit_step_cells(Id, Actions, MinStep, NumSteps),
    write('    </tr>'), nl,
    TotalCols is NumSteps - MinStep + 1,
    emit_detail_row(Id, Repo, Entry, TotalCols).

%! gantt:action_types_atom(+Actions, -Atom) is det.
%
% Collect distinct action types from a step-action list into a space-separated atom.

gantt:action_types_atom(Actions, Atom) :-
    findall(A, member(_-A, Actions), As0),
    sort(As0, As),
    atomic_list_concat(As, ' ', Atom).

%! gantt:emit_step_cells(+Id, +Actions, +N, +NumSteps) is det.
%
% Emit table cells for steps N through NumSteps, showing action badges.

gantt:emit_step_cells(_, _, N, NumSteps) :-
    N > NumSteps, !.
gantt:emit_step_cells(Id, Actions, N, NumSteps) :-
    findall(Action, member(N-Action, Actions), StepActions),
    (   StepActions == []
    ->  write('      <td class="empty"></td>'), nl
    ;   StepActions = [Single]
    ->  action_css(Single, Css),
        action_label(Single, Label),
        action_id_suffix(Single, Suf),
        format('      <td><span class="cell ~w" data-type="~w" id="~w-~w">~w</span></td>~n',
               [Css, Single, Id, Suf, Label])
    ;   write('      <td class="stacked">'), nl,
        forall(member(A, StepActions),
               ( action_css(A, Cs), action_label(A, Lb), action_id_suffix(A, Sf),
                 format('        <span class="cell ~w" data-type="~w" id="~w-~w">~w</span>~n',
                        [Cs, A, Id, Sf, Lb])
               )),
        write('      </td>'), nl
    ),
    N1 is N + 1,
    emit_step_cells(Id, Actions, N1, NumSteps).

%! gantt:action_css(+Action, -CssClass) is det.
%
% Map an action type to its CSS class name.

gantt:action_css(download, dl).
gantt:action_css(install, inst).
gantt:action_css(run, run).
gantt:action_css(update, inst).
gantt:action_css(downgrade, inst).
gantt:action_css(reinstall, inst).
gantt:action_css(fetchonly, dl).
gantt:action_css(unmask, unmask).
gantt:action_css(license, license).
gantt:action_css(keyword, keyword).
gantt:action_css(useflag, useflag).

%! gantt:action_label(+Action, -Label) is det.
%
% Map an action type to its display label.

gantt:action_label(download, download).
gantt:action_label(install, install).
gantt:action_label(run, run).
gantt:action_label(update, update).
gantt:action_label(downgrade, downgrade).
gantt:action_label(reinstall, reinstall).
gantt:action_label(fetchonly, fetchonly).
gantt:action_label(unmask, unmask).
gantt:action_label(license, license).
gantt:action_label(keyword, keyword).
gantt:action_label(useflag, useflag).

%! gantt:action_id_suffix(+Action, -Suffix) is det.
%
% Map an action type to its HTML id suffix for dependency arrow targeting.

gantt:action_id_suffix(download, dl).
gantt:action_id_suffix(install, inst).
gantt:action_id_suffix(run, run).
gantt:action_id_suffix(update, inst).
gantt:action_id_suffix(downgrade, inst).
gantt:action_id_suffix(reinstall, inst).
gantt:action_id_suffix(fetchonly, dl).
gantt:action_id_suffix(unmask, umsk).
gantt:action_id_suffix(license, lic).
gantt:action_id_suffix(keyword, kw).
gantt:action_id_suffix(useflag, uf).


% -----------------------------------------------------------------------------
%  HTML emission - detail rows
% -----------------------------------------------------------------------------

%! gantt:emit_detail_row(+Id, +Repo, +Entry, +TotalCols) is det.
%
% Emit the collapsible detail row showing USE flags and source URIs.

gantt:emit_detail_row(Id, Repo, Entry, TotalCols) :-
    format('    <tr class="detail-row" data-parent="~w">~n', [Id]),
    write('      <td class="detail-pkg">'), nl,
    gantt:pkg_use_flags(Repo, Entry, Flags),
    emit_use_section(Flags),
    write('      </td>'), nl,
    write('      <td class="detail-dl">'), nl,
    gantt:pkg_src_uris(Repo, Entry, Uris),
    emit_src_table(Uris),
    write('      </td>'), nl,
    EmptyCount is TotalCols - 1,
    forall(between(1, EmptyCount, _),
        (write('      <td class="detail-empty"></td>'), nl)),
    write('    </tr>'), nl.

%! gantt:emit_use_section(+Flags) is det.
%
% Emit the USE flags subsection within a detail row.

gantt:emit_use_section([]) :- !.
gantt:emit_use_section(Flags) :-
    write('        <div class="detail-label">USE</div>'), nl,
    write('        <div class="use-flags">'), nl,
    maplist(emit_use_flag_span, Flags),
    write('        </div>'), nl.

%! gantt:emit_use_flag_span(+Flag) is det.
%
% Emit a single USE flag span element with on/off styling.

gantt:emit_use_flag_span(flag(Name, on)) :-
    format('          <span class="use-flag on">+~w</span>~n', [Name]).
gantt:emit_use_flag_span(flag(Name, off)) :-
    format('          <span class="use-flag off">-~w</span>~n', [Name]).

%! gantt:emit_src_table(+Uris) is det.
%
% Emit the source URI table within a detail row.

gantt:emit_src_table([]) :- !.
gantt:emit_src_table(Uris) :-
    write('        <table class="src-table">'), nl,
    maplist(emit_src_row, Uris),
    write('        </table>'), nl.

%! gantt:emit_src_row(+Src) is det.
%
% Emit a single source URI table row with filename, size, and cache status.

gantt:emit_src_row(src(Url, Filename, SizeBytes, Status)) :-
    format_size(SizeBytes, SizeStr),
    status_label(Status, CssClass, Label),
    format('          <tr><td><a href="~w" target="_blank">~w</a></td><td class="sz">~w</td><td><span class="src-status ~w">~w</span></td></tr>~n',
           [Url, Filename, SizeStr, CssClass, Label]).

%! gantt:status_label(+Status, -CssClass, -Label) is det.
%
% Map a distfile cache status to CSS class and display label.

gantt:status_label(cached, cached, cached).
gantt:status_label(pending, pending, fetch).

%! gantt:format_size(+Bytes, -Str) is det.
%
% Format a byte count as a human-readable size string (B, KB, or MB).

gantt:format_size(0, '-') :- !.
gantt:format_size(B, Str) :-
    B >= 1048576, !,
    V is B / 1048576,
    format(atom(Str), '~1f MB', [V]).
gantt:format_size(B, Str) :-
    B >= 1024, !,
    V is B / 1024,
    format(atom(Str), '~0f KB', [V]).
gantt:format_size(B, Str) :-
    format(atom(Str), '~w B', [B]).


% -----------------------------------------------------------------------------
%  HTML emission - legend
% -----------------------------------------------------------------------------

%! gantt:emit_legend is det.
%
% Emit the color legend showing action types and dependency arrow styles.

gantt:emit_legend :-
    write('<div class="legend">'), nl,
    write('  <div class="legend-item"><div class="legend-swatch" style="background:var(--dl);border-color:var(--dl-b)"></div>download</div>'), nl,
    write('  <div class="legend-item"><div class="legend-swatch" style="background:var(--inst);border-color:var(--inst-b)"></div>install / :update / :reinstall / :downgrade</div>'), nl,
    write('  <div class="legend-item"><div class="legend-swatch" style="background:var(--run);border-color:var(--run-b)"></div>run</div>'), nl,
    write('  <div class="legend-item"><div class="legend-swatch" style="background:var(--unmask);border-color:var(--unmask-b)"></div>unmask</div>'), nl,
    write('  <div class="legend-item"><div class="legend-swatch" style="background:var(--keyword);border-color:var(--keyword-b)"></div>keyword</div>'), nl,
    write('  <div class="legend-item"><div class="legend-swatch" style="background:var(--useflag);border-color:var(--useflag-b)"></div>useflag</div>'), nl,
    write('  <div class="legend-item"><svg width="24" height="12"><line x1="0" y1="6" x2="18" y2="6" stroke="var(--bdepend)" stroke-width="1.5"/><polygon points="18,3.5 24,6 18,8.5" fill="var(--bdepend)"/></svg>BDEPEND</div>'), nl,
    write('  <div class="legend-item"><svg width="24" height="12"><line x1="0" y1="6" x2="18" y2="6" stroke="var(--depend)" stroke-width="1.5"/><polygon points="18,3.5 24,6 18,8.5" fill="var(--depend)"/></svg>DEPEND</div>'), nl,
    write('  <div class="legend-item"><svg width="24" height="12"><line x1="0" y1="6" x2="18" y2="6" stroke="var(--rdepend)" stroke-width="1.5"/><polygon points="18,3.5 24,6 18,8.5" fill="var(--rdepend)"/></svg>RDEPEND</div>'), nl,
    write('  <div class="legend-item"><svg width="24" height="12"><line x1="0" y1="6" x2="18" y2="6" stroke="var(--pdepend)" stroke-width="1.5" stroke-dasharray="4,2"/><polygon points="18,3.5 24,6 18,8.5" fill="var(--pdepend)"/></svg>PDEPEND</div>'), nl,
    write('  <div class="legend-item"><svg width="24" height="12"><line x1="0" y1="6" x2="18" y2="6" stroke="var(--idepend)" stroke-width="1.5" stroke-dasharray="2,2"/><polygon points="18,3.5 24,6 18,8.5" fill="var(--idepend)"/></svg>IDEPEND</div>'), nl,
    write('  <div class="legend-item"><svg width="24" height="12"><line x1="0" y1="6" x2="24" y2="6" stroke="var(--bar)" stroke-width="2" stroke-dasharray="4,3"/></svg>same pkg</div>'), nl,
    write('</div>'), nl.


% -----------------------------------------------------------------------------
%  HTML emission - JavaScript
% -----------------------------------------------------------------------------

%! gantt:emit_script(+Grid, +Deps) is det.
%
% Emit the JavaScript block with state, dependency data, and UI functions.

gantt:emit_script(Grid, Deps) :-
    write('<script>'), nl,
    emit_js_state,
    emit_js_dep_array(Deps, Grid),
    emit_js_functions,
    write('</script>'), nl.

%! gantt:emit_js_state is det.
%
% Emit JavaScript filter state and dependency color/dash definitions.

gantt:emit_js_state :-
    write('const filters = {'), nl,
    write('  download:true, fetchonly:true, install:true, update:true, reinstall:true, downgrade:true, run:true,'), nl,
    write('  unmask:true, keyword:true, useflag:true, license:true,'), nl,
    write('  bdepend:true, depend:true, rdepend:true, pdepend:true, idepend:true'), nl,
    write('};'), nl,
    write('const depColors = {bdepend:"#ef6c00",depend:"#e53935",rdepend:"#7e57c2",pdepend:"#00897b",idepend:"#6d4c41"};'), nl,
    write('const depDash = {bdepend:"",depend:"",rdepend:"",pdepend:"6,3",idepend:"3,3"};'), nl,
    write('let hoverMode=false, hoverPkg=null;'), nl.

%! gantt:emit_js_dep_array(+Deps, +Grid) is det.
%
% Emit the JavaScript dependency edge array.

gantt:emit_js_dep_array(Deps, _Grid) :-
    write('const deps = ['), nl,
    emit_dep_entries(Deps),
    write('];'), nl.

%! gantt:emit_dep_entries(+Deps) is det.
%
% Emit individual dependency array entries as JavaScript literals.

gantt:emit_dep_entries([]).
gantt:emit_dep_entries([dep(DepId, DepAct, PkgId, PkgAct, DepType)|Rest]) :-
    action_id_suffix(DepAct, DepSuf),
    action_id_suffix(PkgAct, PkgSuf),
    format('  ["~w-~w","~w-~w","~w"]', [DepId, DepSuf, PkgId, PkgSuf, DepType]),
    (Rest == [] -> nl ; (write(','), nl)),
    emit_dep_entries(Rest).

%! gantt:emit_js_functions is det.
%
% Emit all JavaScript UI functions for filtering, toggling, and drawing.

gantt:emit_js_functions :-
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
    write('  document.querySelectorAll(".cell[data-type]").forEach(c=>c.classList.toggle("hidden",filters[c.dataset.type]===false));'), nl,
    write('  document.querySelectorAll("#gantt tbody tr[data-pkg]").forEach(r=>{'), nl,
    write('    const a=(r.dataset.actions||"").split(" ").filter(Boolean), v=a.some(x=>filters[x]!==false);'), nl,
    write('    r.classList.toggle("row-hidden",!v);'), nl,
    write('    if(!v){const p=r.dataset.pkg;'), nl,
    write('      document.querySelectorAll(`tr.detail-row[data-parent="${p}"]`).forEach(d=>d.classList.remove("visible"));'), nl,
    write('      const t=r.querySelector(".toggle");if(t)t.classList.remove("open");}'), nl,
    write('  });'), nl,
    write('  drawOverlays();'), nl,
    write('}'), nl,
    write('function drawOverlays(){'), nl,
    write('  const svg=document.getElementById("dep-svg"),wr=document.getElementById("gantt-wrapper"),'), nl,
    write('        wR=wr.getBoundingClientRect(),ns="http://www.w3.org/2000/svg",'), nl,
    write('        barColor=getComputedStyle(document.documentElement).getPropertyValue("--bar").trim();'), nl,
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
    write('      l.setAttribute("stroke",barColor);l.setAttribute("stroke-width","2");'), nl,
    write('      l.setAttribute("stroke-dasharray","5,4");l.setAttribute("class","bar-edge");'), nl,
    write('      l.dataset.pkg=row.dataset.pkg;svg.appendChild(l);}'), nl,
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
    write('    p.setAttribute("class","dep-edge");p.dataset.fromPkg=fr.dataset.pkg;p.dataset.toPkg=tr2.dataset.pkg;'), nl,
    write('    svg.appendChild(p);'), nl,
    write('  });'), nl,
    write('  if(hoverMode&&hoverPkg)litEdges(hoverPkg);'), nl,
    write('}'), nl,
    write('function toggleHoverMode(btn){'), nl,
    write('  hoverMode=!hoverMode;'), nl,
    write('  btn.classList.toggle("active",hoverMode);btn.setAttribute("aria-pressed",hoverMode);'), nl,
    write('  document.getElementById("dep-svg").classList.toggle("hover-mode",hoverMode);'), nl,
    write('  document.getElementById("gantt").classList.toggle("hover-mode",hoverMode);'), nl,
    write('  if(!hoverMode)litEdges(null);'), nl,
    write('}'), nl,
    write('function litEdges(p){'), nl,
    write('  hoverPkg=p;'), nl,
    write('  document.querySelectorAll("#dep-svg .lit").forEach(e=>e.classList.remove("lit"));'), nl,
    write('  document.querySelectorAll("#gantt tr.hover-lit").forEach(r=>r.classList.remove("hover-lit"));'), nl,
    write('  if(!p)return;'), nl,
    write('  document.querySelectorAll(`#dep-svg [data-pkg="${p}"],#dep-svg [data-from-pkg="${p}"],#dep-svg [data-to-pkg="${p}"]`)'), nl,
    write('    .forEach(e=>e.classList.add("lit"));'), nl,
    write('  const r=document.querySelector(`#gantt tr[data-pkg="${p}"]`);if(r)r.classList.add("hover-lit");'), nl,
    write('}'), nl,
    write('(function(){'), nl,
    write('  const tb=document.querySelector("#gantt tbody");if(!tb)return;'), nl,
    write('  tb.addEventListener("mouseover",e=>{'), nl,
    write('    if(!hoverMode)return;'), nl,
    write('    const r=e.target.closest("tr[data-pkg],tr.detail-row"),p=r?(r.dataset.pkg||r.dataset.parent):null;'), nl,
    write('    if(p!==hoverPkg)litEdges(p);'), nl,
    write('  });'), nl,
    write('  tb.addEventListener("mouseleave",()=>{if(hoverMode)litEdges(null);});'), nl,
    write('})();'), nl,
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

%! gantt:make_id(+Name, -Id)
%
% Create an HTML-safe identifier from a package name atom.

gantt:make_id(Name, Id) :-
    atom_chars(Name, Chars),
    maplist(safe_id_char, Chars, SafeChars),
    atom_chars(Id, SafeChars).

%! gantt:safe_id_char(+Char, -SafeChar) is det.
%
% Map a character to an HTML-id-safe character, replacing non-alnum with underscore.

gantt:safe_id_char(C, C) :- char_type(C, alnum), !.
gantt:safe_id_char(-, -) :- !.
gantt:safe_id_char(_, '_').
