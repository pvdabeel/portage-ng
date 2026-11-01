/*
 Author: Pieter Van den Abeele
 E-mail: pvdabeel@mac.com
 Copyright (c) 2005-2026, Pieter Van den Abeele

 Distributed under the terms of the LICENSE file in the root directory of this
 project.
*/

/** <module> NAVTHEMETEST
Unit tests for the grapher escaping helpers
(Source/Application/Output/Grapher/navtheme.pl).

HTML/JS escaping of ebuild-controlled text (DESCRIPTION, HOMEPAGE, …)
embedded in generated graph pages.
*/

:- module(navthemetest, []).

:- use_module(library(plunit)).

% =============================================================================
%  NAVTHEMETEST declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  HTML escaping tests
% -----------------------------------------------------------------------------

:- begin_tests(navtheme_html_escape).

test(escapes_markup_chars, [true(Out == 'a&lt;b&gt;&amp;&quot;c&quot;')]) :-
  navtheme:html_escape('a<b>&"c"', Out).

test(escapes_single_quote, [true(Out == 'it&#39;s')]) :-
  navtheme:html_escape('it''s', Out).

test(passthrough_plain, [true(Out == 'sys-apps/portage-3.0')]) :-
  navtheme:html_escape('sys-apps/portage-3.0', Out).

:- end_tests(navtheme_html_escape).


% -----------------------------------------------------------------------------
%  JavaScript string escaping tests
% -----------------------------------------------------------------------------

:- begin_tests(navtheme_js_escape).

test(escapes_quote_and_backslash,
     [true(Out == 'a\\"b\\\\c')]) :-
  navtheme:js_escape_atom('a"b\\c', Out).

test(script_close_cannot_break_out) :-
  once(navtheme:js_escape_atom('</script><script>alert(1)</script>', Out)),
  \+ sub_atom(Out, _, _, _, '</script'),
  \+ sub_atom(Out, _, _, _, '<'),
  once(sub_atom(Out, _, _, _, '\\u003c')).

test(escapes_line_terminators) :-
  atom_codes(In, [97, 8232, 98, 8233, 99, 10, 100]),
  navtheme:js_escape_atom(In, Out),
  atom_codes(Out, Codes),
  Codes == [97, 0'\\, 0'u, 0'2, 0'0, 0'2, 0'8,
            98, 0'\\, 0'u, 0'2, 0'0, 0'2, 0'9,
            99, 0'\\, 0'n, 100].

test(escapes_control_chars) :-
  atom_codes(In, [97, 1, 98]),
  navtheme:js_escape_atom(In, Out),
  atom_codes(Out, Codes),
  Codes == [97, 0'\\, 0'u, 0'0, 0'0, 0'0, 0'1, 98].

test(passthrough_plain, [true(Out == 'A fast package manager')]) :-
  navtheme:js_escape_atom('A fast package manager', Out).

:- end_tests(navtheme_js_escape).


% -----------------------------------------------------------------------------
%  URL/path and HTML sink tests
% -----------------------------------------------------------------------------

:- begin_tests(navtheme_url_safety).

test(accepts_https) :-
  navtheme:safe_http_url('https://example.org/path?q=1', _).

test(rejects_javascript, [fail]) :-
  navtheme:safe_http_url('javascript:alert(1)', _).

test(rejects_protocol_relative, [fail]) :-
  navtheme:safe_http_url('//example.org/path', _).

test(encodes_entry_segments,
     [true(Path == 'cat/pkg%3Fname-1.0')]) :-
  navtheme:entry_path('cat/pkg?name-1.0', Path).

test(rejects_dot_entry, [fail]) :-
  navtheme:entry_path('../pkg-1.0', _).

test(gantt_unsafe_url_is_plain_text, [nondet]) :-
  with_output_to(string(Output),
    gantt:emit_src_row(src('javascript:alert(1)',
                           '\"><img src=x onerror=alert(1)>',
                           0, pending))),
  \+ sub_string(Output, _, _, _, '<a '),
  \+ sub_string(Output, _, _, _, '<img '),
  sub_string(Output, _, _, _, '&lt;img').

test(gantt_https_link_is_hardened, [nondet]) :-
  with_output_to(string(Output),
    gantt:emit_src_row(src('https://example.org/source.tar',
                           'source.tar', 1, cached))),
  sub_string(Output, _, _, _, 'href=\"https://example.org/source.tar\"'),
  sub_string(Output, _, _, _, 'rel=\"noopener noreferrer\"').

:- end_tests(navtheme_url_safety).


% -----------------------------------------------------------------------------
%  Verbatim JavaScript asset tests
% -----------------------------------------------------------------------------

:- begin_tests(grapher_js_assets).

test(script_src_emission,
     [true(Out == "<script src=\"../.gantt.js\"></script>\n")]) :-
  with_output_to(string(Out),
                 navtheme:emit_script_src('../', gantt)).

test(assets_exist_and_are_script_safe,
     [condition(current_predicate(config:graph_asset_source/2))]) :-
  forall(member(Key, [deptree_js, detail_js, gantt_js,
                      security_js, tracker_js]),
         ( config:graph_asset_source(Key, Source),
           exists_file(Source),
           read_file_to_string(Source, Content, []),
           string_length(Content, Len), Len > 0,
           \+ sub_string(Content, _, _, _, "</script"),
           \+ sub_string(Content, _, _, _, "innerHTML"),
           \+ sub_string(Content, _, _, _, "outerHTML"),
           \+ sub_string(Content, _, _, _, "insertAdjacentHTML")
         )).

test(copy_graph_assets_copies_js) :-
  tmp_file(navthemeassets, Tmp),
  ( exists_file(Tmp) -> delete_file(Tmp) ; true ),
  make_directory(Tmp),
  setup_call_cleanup(
    true,
    ( grapher:copy_graph_assets(Tmp),
      forall(member(Name, ['.deptree.js', '.detail.js', '.gantt.js',
                           '.security.js', '.tracker.js']),
             ( atomic_list_concat([Tmp, '/', Name], Path),
               exists_file(Path) ))
    ),
    ( catch(process_create(path(rm), ['-rf', Tmp], [process(Pid)]), _, true),
      ( var(Pid) -> true ; process_wait(Pid, _) )
    )).

:- end_tests(grapher_js_assets).


% -----------------------------------------------------------------------------
%  Comprehensive coverage tests for Grapher/* and grapher.pl
% -----------------------------------------------------------------------------

:- begin_tests(grapher_modules_full_coverage).

test(navtheme_and_grapher_branches) :-
  with_output_to(string(_),
    ( navtheme:emit_nav_bar(test_gr_repo, 'cat/pkg-1.0', cat, pkg, detail,
                            'cat/pkg-2.0', 'cat/pkg-3.0', 'cat/pkg-0.9', 'cat/pkg-0.1'),
      navtheme:emit_version_current(''),
      navtheme:emit_version_current('1.0'),
      navtheme:emit_version_link('', '&laquo;', detail),
      navtheme:emit_version_link('cat/pkg-2.0', '&laquo;', detail)
    )),
  atom_codes(InJs, [39, 13, 9, 38, 127]),
  navtheme:js_escape_atom(InJs, _),
  with_output_to(string(_),
    ( grapher:graph(gantt, test_gr_repo://'cat/pkg-1.0', failed),
      assertz(test_gr_repo:entry(_):-fail),
      assertz(test_gr_repo:package(_, _):-fail),
      assertz(test_gr_repo:ebuild(_, _, _, _):-fail),
      grapher:test(test_gr_repo),
      grapher:test(test_gr_repo, single_verbose),
      grapher:test_latest(test_gr_repo),
      grapher:test_latest(test_gr_repo, single_verbose),
      retractall(test_gr_repo:entry(_)),
      retractall(test_gr_repo:package(_, _)),
      retractall(test_gr_repo:ebuild(_, _, _, _))
    )).

test(sitefiles_all_clauses) :-
  sitefiles:strip_slash('https://example.org/', 'https://example.org'),
  sitefiles:strip_slash('https://example.org', 'https://example.org'),
  sitefiles:site_url(_),
  assertz(cache:category(test_sf_repo, 'app-misc')),
  assertz(cache:package(test_sf_repo, 'app-misc', 'foo')),
  assertz(cache:ordered_entry(test_sf_repo, 'app-misc/foo-1.0', 'app-misc', 'foo',
                              version([1,0], '', 4, 0, '', 0, '1.0'))),
  tmp_file(sitefiles_cov, TmpDir),
  ( exists_file(TmpDir) -> delete_file(TmpDir) ; true ),
  make_directory(TmpDir),
  setup_call_cleanup(
    true,
    with_output_to(string(_),
      ( sitefiles:write_site_files(TmpDir, test_sf_repo),
        sitefiles:write_site_files('/nonexistent_dir_12345/sub', test_sf_repo)
      )),
    ( retractall(cache:category(test_sf_repo, _)),
      retractall(cache:package(test_sf_repo, _, _)),
      retractall(cache:ordered_entry(test_sf_repo, _, _, _, _)),
      catch(process_create(path(rm), ['-rf', TmpDir], [process(Pid)]), _, true),
      ( var(Pid) -> true ; process_wait(Pid, _) )
    )).

test(deptree_and_detail_all_clauses) :-
  V1 = version([1,0], '', 4, 0, '', 0, '1.0'),
  V2 = version([2,0], '', 4, 0, '', 0, '2.0'),
  setup_call_cleanup(
    ( assertz(cache:ordered_entry(test_dt_repo, 'cat/pkg-1.0', 'cat', 'pkg', V1)),
      assertz(cache:ordered_entry(test_dt_repo, 'cat/pkg-2.0', 'cat', 'pkg', V2)),
      assertz(cache:ordered_entry(pkg, 'cat/pkg-1.0', 'cat', 'pkg', V1)),
      assertz(cache:entry_metadata(test_dt_repo, 'cat/pkg-1.0', slot, slot('0'))),
      assertz(cache:entry_metadata(test_dt_repo, 'cat/pkg-1.0', description, 'desc')),
      assertz(cache:entry_metadata(test_dt_repo, 'cat/pkg-1.0', homepage, 'https://example.org')),
      assertz(cache:entry_metadata(test_dt_repo, 'cat/pkg-1.0', iuse, 'foo')),
      assertz(cache:entry_metadata(test_dt_repo, 'cat/pkg-1.0', rdepend,
              package_dependency(run, no, 'cat', 'pkg', equal, V2, _, []))),
      assertz(cache:entry_metadata(test_dt_repo, 'cat/pkg-1.0', depend,
              use_conditional_group(positive, foo, 'cat/pkg-1.0',
                [any_of_group([package_dependency(install, weak, 'cat', 'pkg', none, version_none, _, [])]),
                 all_of_group([package_dependency(install, strong, 'cat', 'pkg', greater, V1, _, [])]),
                 exactly_one_of_group([]),
                 at_most_one_of_group([])])))
    ),
    with_output_to(string(_),
      ( deptree:graph(test_dt_repo://'cat/pkg-1.0'),
        deptree:version_neighbours(test_dt_repo, 'cat/nonexistent-1.0', '', '', '', ''),
        ignore(deptree:dep_choice(any_of_group([]), test_dt_repo, _, _)),
        deptree:emit_js_use_flags([flag(foo, on), flag(bar, off)]),
        deptree:emit_js_edges([edge('a', 'b', no), edge('b', 'c', weak)]),
        detail:graph(test_dt_repo://'cat/pkg-1.0'),
        detail:phase_neutral(other_term, other_term),
        detail:build_tree(test_dt_repo, unknown_dep_term, tree(unknown, [])),
        detail:dedupe_candidate_pairs_by_entry([V2-candidate('cat/pkg-2.0', false),
                                                V1-candidate('cat/pkg-2.0', false)], [_]),
        detail:emit_trees_json([tree(unknown, []),
                                tree(use_cond(positive, foo),
                                     [tree(any_of_group, []),
                                      tree(all_of_group, [tree(pkg_dep(no, 'c', 'p', '*'),
                                                               [candidate('c/p-1', true),
                                                                candidate('c/p-2', false)])]),
                                      tree(exactly_one_of_group, [tree(pkg_dep(no, 'c', 'p', '*'),
                                                                       [candidate('c/p-1', true)])]),
                                      tree(at_most_one_of_group, [tree(pkg_dep(no, 'c', 'p', '*'), [])])])])
      )),
    ( retractall(cache:ordered_entry(test_dt_repo, _, _, _, _)),
      retractall(cache:ordered_entry(pkg, 'cat/pkg-1.0', _, _, _)),
      retractall(cache:entry_metadata(test_dt_repo, _, _, _))
    )).

test(security_and_tracker_all_clauses) :-
  V1 = version([1,0], '', 4, 0, '', 0, '1.0'),
  V2 = version([2,0], '', 4, 0, '', 0, '2.0'),
  setup_call_cleanup(
    ( ignore(glsa:ensure_loaded),
      ignore(bugs:ensure_loaded),
      assertz(cache:ordered_entry(test_sec_repo, 'cat/pkg-1.0', 'cat', 'pkg', V1)),
      assertz(cache:ordered_entry(pkg, 'cat/pkg-1.0', 'cat', 'pkg', V1)),
      assertz(cache:package(test_sec_repo, 'cat', 'pkg')),
      assertz(glsa:loaded),
      assertz(glsa:advisory('202601-01', 'Test Advisory')),
      assertz(glsa:package('202601-01', 'cat', 'pkg', '*')),
      assertz(glsa:package('202601-02', 'cat', 'pkg', '*')),
      assertz(glsa:package('202601-01', 'other', 'missing', 'amd64')),
      assertz(glsa:range('202601-01', 'cat', 'pkg', vulnerable, lt, V2, '*')),
      assertz(glsa:range('202601-01', 'cat', 'pkg', unaffected, ge, V2, '0')),
      assertz(bugsdata:bug(100, 'Gentoo Linux', 'Current packages', 'CONFIRMED', '',
                           'blocker', 'P1', 'dev@gentoo.org',
                           '2026-01-01T00:00:00Z', '2026-01-02T00:00:00Z',
                           ['amd64', 'security'], 'cat/pkg-1.0 fails')),
      assertz(bugsdata:bug(101, 'Gentoo Linux', 'Stabilization', 'RESOLVED', 'FIXED',
                           'minor', 'P2', 'dev@gentoo.org',
                           '2026-01-01', '2026-01-02',
                           [], 'cat/pkg-2.0 stabilization')),
      assertz(bugsdata:bug(102, 'Gentoo Linux', 'Keywording', 'RESOLVED', '',
                           'custom_sev', 'P3', '',
                           '', '',
                           [], 'cat/pkg general')),
      assertz(bugsdata:bug_package(100, 'cat', 'pkg')),
      assertz(bugsdata:bug_package(101, 'cat', 'pkg')),
      assertz(bugsdata:bug_package(102, 'cat', 'pkg')),
      assertz(bugsdata:bug_atom(100, 'cat', 'pkg', V1)),
      assertz(bugsdata:bug_atom(100, 'other', 'pkg', version_none)),
      assertz(bugsdata:bug_atom(101, 'cat', 'pkg', V2)),
      assertz(bugsdata:bug_atom(102, 'cat', 'pkg', version_none))
    ),
    with_output_to(string(_),
      ( security:graph(test_sec_repo://'cat/pkg-1.0'),
        security:emit_toolbar('cat', 'pkg', '1.0', []),
        security:emit_toolbar('cat', 'pkg', '1.0', [adv('1', 't', unaffected, false, [])]),
        security:emit_toolbar('cat', 'pkg', '1.0', [adv('1', 't', vulnerable, true, []),
                                                     adv('2', 't2', vulnerable, false, [])]),
        security:emit_advisories(test_sec_repo, 'cat', 'pkg', []),
        DetailFull = [synopsis('syn'), severity(high), access('remote'),
                      announced('2026-01-01'), revised('2026-01-02', 1),
                      bugs(['12345']),
                      background([p('bg'), code('cd'), list(['i1', 'i2'])]),
                      description([p('desc')]),
                      impact([p('imp')]),
                      workaround([p('wa')]),
                      resolution([p('res')]),
                      references([ref('CVE-2026-0001', 'https://example.org/cve')])],
        DetailRev2 = [revised('2026-01-03', 2), severity(low)],
        security:emit_advisory(test_sec_repo, 'cat', 'pkg',
                               adv('202601-01', 'Title', vulnerable, true, DetailFull)),
        security:emit_advisory(test_sec_repo, 'cat', 'pkg',
                               adv('202601-02', 'Title2', unaffected, false, DetailRev2)),
        security:emit_advisory(test_sec_repo, 'cat', 'pkg',
                               adv('202601-03', 'Title3', unlisted, false, [])),
        forall(member(Sev-Cls, [high-high, medium-normal, normal-normal, low-low, minimal-low, weird-normal]),
               security:severity_class(Sev, Cls)),
        forall(member(Op, [lt, le, eq, gt, ge, rlt, rle, rgt, rge]),
               security:range_text(Op, V1, '0', _)),
        tracker:graph(test_sec_repo://'cat/pkg-1.0'),
        tracker:emit_toolbar('cat', 'pkg', '1.0', []),
        tracker:emit_toolbar('cat', 'pkg', '1.0',
                             [bug(101, 's', resolved, this, [])]),
        tracker:emit_filters('1.0', []),
        tracker:emit_facet_row(keyword, [], []),
        tracker:emit_bugs(test_sec_repo, []),
        tracker:slug('---', other),
        forall(member(BSev-BCls, [blocker-high, critical-high, major-high, normal-normal,
                                  minor-low, trivial-low, enhancement-low, custom-normal]),
               tracker:severity_class(BSev, BCls)),
        tracker:facet_attr(missing_key, [], other),
        tracker:keyword_attr([], ''),
        tracker:search_attr(1, 'sum', [], _),
        retractall(bugsdata:bug(_, _, _, _, _, _, _, _, _, _, _, _)),
        tracker:emit_toolbar('cat', 'pkg', '1.0', [])
      )),
    ( retractall(cache:ordered_entry(test_sec_repo, _, _, _, _)),
      retractall(cache:ordered_entry(pkg, 'cat/pkg-1.0', _, _, _)),
      retractall(cache:package(test_sec_repo, _, _)),
      retractall(glsa:advisory('202601-01', _)),
      retractall(glsa:package('202601-01', _, _, _)),
      retractall(glsa:package('202601-02', _, _, _)),
      retractall(glsa:range('202601-01', _, _, _, _, _, _)),
      retractall(bugsdata:bug(_, _, _, _, _, _, _, _, _, _, _, _)),
      retractall(bugsdata:bug_package(_, _, _)),
      retractall(bugsdata:bug_atom(_, _, _, _))
    )).

test(dot_all_clauses) :-
  V1 = version([1,0], '', 4, 0, '', 0, '1.0'),
  V2 = version([2,0], '', 4, 0, '', 0, '2.0'),
  setup_call_cleanup(
    ( assertz(cache:ordered_entry(test_dot_repo, 'cat/pkg-1.0', 'cat', 'pkg', V1)),
      assertz(cache:ordered_entry(test_dot_repo, 'cat/pkg-2.0', 'cat', 'pkg', V2)),
      assertz(cache:entry_metadata(test_dot_repo, 'cat/pkg-1.0', depend,
              package_dependency(install, no, 'cat', 'pkg', equal, V2, _, []))),
      assertz(cache:entry_metadata(test_dot_repo, 'cat/pkg-1.0', depend,
              package_dependency(install, weak, 'cat', 'pkg', equal, V2, _, []))),
      assertz(cache:entry_metadata(test_dot_repo, 'cat/pkg-1.0', depend,
              package_dependency(install, strong, 'cat', 'pkg', equal, V2, _, []))),
      assertz(cache:entry_metadata(test_dot_repo, 'cat/pkg-1.0', depend,
              use_conditional_group(positive, foo, 'cat/pkg-1.0',
                [any_of_group([package_dependency(install, no, 'cat', 'pkg', equal, V2, _, [])]),
                 all_of_group([]),
                 exactly_one_of_group([]),
                 at_most_one_of_group([]),
                 unknown_dep_item]))),
      assertz(cache:entry_metadata(test_dot_repo, 'cat/pkg-1.0', rdepend,
              package_dependency(run, no, 'cat', 'pkg', equal, V2, _, []))),
      assertz(cache:entry_metadata(test_dot_repo, 'cat/pkg-1.0', rdepend,
              any_of_group([]))),
      assertz(cache:entry_metadata(test_dot_repo, 'cat/pkg-1.0', rdepend,
              unknown_rdep_item)),
      assertz(cache:entry_metadata(test_dot_repo, 'cat/pkg-2.0', rdepend,
              package_dependency(run, weak, 'cat', 'pkg', equal, V1, _, []))),
      assertz(cache:entry_metadata(test_dot_repo, 'cat/pkg-2.0', rdepend,
              package_dependency(run, strong, 'cat', 'pkg', equal, V1, _, [])))
    ),
    with_output_to(string(_),
      ( grapher:graph_dot(detail, test_dot_repo://'cat/pkg-1.0'),
        grapher:graph_dot(merge, test_dot_repo://'cat/pkg-1.0'),
        grapher:graph_dot(rdepend, test_dot_repo://'cat/pkg-1.0'),
        forall(member(HrefType, [repository, category, package, merge, fetchonly,
                                 info, emerge, pmerge, detail, index_repository,
                                 index_category, index_package, rdepend]),
               dot:graph_legend_href(HrefType, test_dot_repo://'cat/pkg-1.0', 'lbl')),
        dot:graph_legend_href(detail, test_dot_repo://[], 'lbl'),
        dot:tl_gensym_reset(package_dependency),
        catch(dot:produce_svg('/nonexistent_svg_dir'), _, true)
      )),
    ( retractall(cache:ordered_entry(test_dot_repo, _, _, _, _)),
      retractall(cache:entry_metadata(test_dot_repo, _, _, _))
    )).

test(terminal_all_clauses) :-
  V1 = version([1,0], '', 4, 0, '', 0, '1.0'),
  tmp_file(term_cov, TmpBase),
  ( exists_file(TmpBase) -> delete_file(TmpBase) ; true ),
  make_directory(TmpBase),
  os:compose_path(TmpBase, test_term_repo, RepoDir),
  make_directory(RepoDir),
  os:compose_path(RepoDir, 'cat', CatDir),
  make_directory(CatDir),
  setup_call_cleanup(
    assertz(cache:ordered_entry(test_term_repo, 'cat/pkg-1.0', 'cat', 'pkg', V1)),
    with_output_to(string(_),
      ( % Exercise without stored files first
        terminal:graph(merge, test_term_repo://'cat/pkg-1.0'),
        terminal:graph(fetchonly, test_term_repo://'cat/pkg-1.0'),
        terminal:graph(info, test_term_repo://'cat/pkg-1.0'),
        terminal:graph(emerge, test_term_repo://'cat/pkg-1.0'),
        terminal:graph(pmerge, test_term_repo://'cat/pkg-1.0'),
        % Timing lines with ANSI CSI/OSC prefixes
        RawTiming = "\e[32m% merge started: 100 (human)\n\e]0;title\a% merge ended: 102 (human)\n\eM% merge wall_time_ms: 2000\n",
        terminal:split_timing_body(merge, RawTiming, _, timing_display(2.0, none)),
        terminal:split_timing_body(merge, "plain line\n% merge wall_time_ms: 1500", _, timing_display(1.5, none)),
        terminal:split_timing_body(merge, "plain only", _, timing_display(none, none)),
        terminal:split_timing_body(merge, "% merge started: 100 (human)\nplain", _, timing_display(none, none)),
        terminal:timing_line_plain_for_meta('% merge wall_time_ms: 1000', _),
        terminal:format_wall_seconds(2.0, "2"),
        terminal:format_wall_seconds(1.234, "1.234"),
        % ANSI walk coverage: CSI SGR, CSI non-SGR, OSC BEL, OSC ST, ESC other, PUA char, trailing lone ESC
        atom_codes(AnsiAtom,
          [27,91,49,59,50,59,51,59,52,59,50,50,59,50,51,59,50,52,109,
           27,91,51,48,59,51,57,59,52,48,59,52,57,59,57,48,59,49,48,48,59,57,57,57,109,
           27,91,109,
           27,91,65,
           27,93,48,59,116,7,
           27,93,48,59,116,27,92,
           27,77,
           0xE000, 65, 27]),
        terminal:ansi_to_html(AnsiAtom, _),
        atom_codes(AnsiUntermOsc, [27,93,48]),
        terminal:ansi_to_html(AnsiUntermOsc, _),
        terminal:collect_csi([], [], 0, []),
        terminal:param_number([], 0),
        forall(between(30, 37, C1), terminal:fg_class(C1, _)),
        forall(between(40, 47, C2), terminal:bg_class(C2, _)),
        forall(between(90, 97, C3), terminal:bfg_class(C3, _)),
        forall(between(100, 107, C4), terminal:bbg_class(C4, _)),
        terminal:add_class(['ansi-bold'], 'ansi-bold', ['ansi-bold']),
        terminal:emit_terminal_stats(emerge, timing_display(1.5, 1.0)),
        terminal:emit_terminal_stats(merge, timing_display(1.5, none)),
        terminal:emit_terminal_stats(merge, timing_display(none, none))
      )),
    ( retractall(cache:ordered_entry(test_term_repo, _, _, _, _)),
      catch(process_create(path(rm), ['-rf', TmpBase], [process(Pid)]), _, true),
      ( var(Pid) -> true ; process_wait(Pid, _) )
    )).

test(gantt_all_clauses) :-
  V1 = version([1,0], '', 4, 0, '', 0, '1.0'),
  V2 = version([2,0], '', 4, 0, '', 0, '2.0'),
  empty_assoc(E0),
  put_assoc(rule(test_gantt_repo://'cat1/pkg-1.0':install), E0,
            dep(1, [test_gantt_repo://'cat2/pkg-2.0':run,
                    package_dependency(install, no, 'cat2', 'pkg', none, version_none, _, []):install?{[]},
                    grouped_package_dependency(no, 'cat2', 'pkg',
                      [package_dependency(run, no, 'cat2', 'pkg', none, version_none, _, [])]):run?{[]}])?[
              suggestion(unmask, 'cat1/pkg-1.0'),
              suggestion(accept_keyword, '~amd64'),
              suggestion(use_change, 'cat1/pkg-1.0', [enable(foo)])
            ], E1),
  put_assoc(rule(test_gantt_repo://'cat2/pkg-2.0':run), E1,
            dep(1, [])?[suggestion(accept_license, 'MIT')], E2),
  put_assoc(rule(package_dependency(install, no, 'cat2', 'pkg', none, version_none, _, []):install), E2,
            dep(1, [test_gantt_repo://'cat2/pkg-2.0':install?{[]}])?[], E3),
  put_assoc(rule(grouped_package_dependency(no, 'cat2', 'pkg',
              [package_dependency(run, no, 'cat2', 'pkg', none, version_none, _, [])]):run), E3,
            dep(1, [test_gantt_repo://'cat2/pkg-2.0':run?{[]}])?[], E4),
  put_assoc(obligation_done(pdepend(test_gantt_repo://'cat1/pkg-1.0':install, 'cat2/pkg')), E4,
            true?[], ProofAVL),
  Plan = [
    [rule(test_gantt_repo://'cat1/pkg-1.0':download?{[]}, []),
     rule(test_gantt_repo://'cat1/pkg-1.0':install?{[]}, []),
     rule(non_visible_head, [])],
    [assumed(rule(test_gantt_repo://'cat2/pkg-2.0':run?{[]}, [])),
     rule(test_gantt_repo://'missing/entry-1.0':install?{[]}, [])],
    [rule(non_visible_only, [])]
  ],
  tmp_file(gantt_dir, TmpDir),
  ( exists_file(TmpDir) -> delete_file(TmpDir) ; true ),
  make_directory(TmpDir),
  os:compose_path(TmpDir, 'file.bin', TmpFile),
  setup_call_cleanup(open(TmpFile, write, S), write(S, 'hello'), close(S)),
  setup_call_cleanup(
    ( assertz(cache:ordered_entry(test_gantt_repo, 'cat1/pkg-1.0', 'cat1', 'pkg', V1)),
      assertz(cache:ordered_entry(test_gantt_repo, 'cat2/pkg-2.0', 'cat2', 'pkg', V2)),
      assertz(cache:ordered_entry(test_gantt_repo, 'cat1/pkg-2.0', 'cat1', 'pkg', V2)),
      assertz(cache:entry_metadata(test_gantt_repo, 'cat1/pkg-1.0', iuse, 'foo')),
      assertz(cache:entry_metadata(test_gantt_repo, 'cat1/pkg-1.0', iuse, 'bar')),
      assertz(cache:entry_metadata(test_gantt_repo, 'cat1/pkg-1.0', pdepend,
              use_conditional_group(positive, foo, 'cat1/pkg-1.0',
                [any_of_group([package_dependency(pdepend, no, 'cat2', 'pkg', none, version_none, _, [])])]))),
      assertz(cache:entry_metadata(test_gantt_repo, 'cat1/pkg-1.0', src_uri,
              uri('', '', 'local.tar.gz'))),
      assertz(cache:entry_metadata(test_gantt_repo, 'cat1/pkg-1.0', src_uri,
              uri(mirror, 'gentoo/foo.tar.gz', 'foo.tar.gz'))),
      assertz(cache:entry_metadata(test_gantt_repo, 'cat1/pkg-1.0', src_uri,
              uri(https, 'example.org/bar.tar.gz', 'bar.tar.gz'))),
      assertz(cache:entry_metadata(test_gantt_repo, 'cat1/pkg-2.0', src_uri,
              uri(https, 'example.org/bar2.tar.gz', 'bar2.tar.gz'))),
      assertz(cache:manifest(test_gantt_repo, 'p1', 0, 'cat1', 'pkg')),
      assertz(cache:manifest_metadata(test_gantt_repo, 'p1', dist, 'bar2.tar.gz', 2048, [])),
      assertz(phasestats:phase_stats_loaded),
      assertz(phasestats:phase_seconds('cat1/pkg-2.0', compile, 5.0)),
      assertz(phasestats:phase_seconds('cat2/pkg-2.0', install, 3.0)),
      retractall(gantt:cn_index_ready)
    ),
    with_output_to(string(_),
      ( gantt:graph(test_gantt_repo://'cat1/pkg-1.0'),
        gantt:emit(test_gantt_repo://'cat1/pkg-1.0', ProofAVL, Plan),
        gantt:max_used_step([], 0),
        forall(member(Act, [download, install, run, update, downgrade, reinstall,
                            fetchonly, unmask, license, keyword, useflag]),
               ( gantt:visible_action(Act),
                 gantt:action_time_class(Act, _),
                 gantt:action_css(Act, _),
                 gantt:action_label(Act, _),
                 gantt:action_id_suffix(Act, _)
               )),
        gantt:find_dups([a, a, a, b], [a]),
        gantt:inject_pre_actions(['missing/pkg-1.0'-unmask], [], []),
        forall(member(Ph-Dt, [install-depend, run-rdepend, pdepend-pdepend, compile-depend, other-depend]),
               gantt:phase_deptype(Ph, Dt)),
        gantt:directory_bytes(TmpDir, B1),
        gantt:directory_bytes(TmpDir, B1),
        gantt:cn_phase_seconds('cat1/pkg-1.0', compile, 5.0),
        gantt:cn_merge_seconds('cat1/pkg-1.0', 5.0),
        gantt:average([10, 20], 15),
        gantt:format_size(0, '-'),
        gantt:format_size(2097152, _),
        gantt:format_size(2048, _),
        gantt:format_size(512, _),
        gantt:emit_use_flag_span(flag(foo, on)),
        gantt:make_id('pkg+name-1', 'pkg_name-1')
      )),
    ( retractall(cache:ordered_entry(test_gantt_repo, _, _, _, _)),
      retractall(cache:entry_metadata(test_gantt_repo, _, _, _)),
      retractall(cache:manifest(test_gantt_repo, _, _, _, _)),
      retractall(cache:manifest_metadata(test_gantt_repo, _, _, _, _, _)),
      retractall(phasestats:phase_seconds('cat1/pkg-2.0', _, _)),
      retractall(phasestats:phase_seconds('cat2/pkg-2.0', _, _)),
      catch(process_create(path(rm), ['-rf', TmpDir], [process(Pid)]), _, true),
      ( var(Pid) -> true ; process_wait(Pid, _) )
    )).

:- end_tests(grapher_modules_full_coverage).

