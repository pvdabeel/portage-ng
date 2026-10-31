/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> GLSATEST
Unit tests for GLSA parsing, version ranges and filtering (Source/Domain/Gentoo/glsa.pl).
*/

:- module(glsatest, []).

:- use_module(library(plunit)).
:- use_module(library(lists)).

% =============================================================================
%  GLSATEST declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  GLSA parse / range / filter tests
% -----------------------------------------------------------------------------

:- begin_tests(glsa).

glsa_fixture_xml(Xml) :-
  atomic_list_concat([
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<!DOCTYPE glsa SYSTEM "http://www.gentoo.org/dtd/glsa.dtd">',
    '<glsa id="202501-03">',
    '    <title>pip: arbitrary configuration injection</title>',
    '    <synopsis>test</synopsis>',
    '    <product type="ebuild">pip</product>',
    '    <announced>2025-01-17</announced>',
    '    <revised count="1">2025-01-17</revised>',
    '    <affected>',
    '        <package name="dev-python/pip" auto="yes" arch="*">',
    '            <unaffected range="ge">23.3</unaffected>',
    '            <vulnerable range="lt">23.3</vulnerable>',
    '        </package>',
    '    </affected>',
    '</glsa>'
  ], '\n', Xml).

test(parse_fixture, [true(Title == 'pip: arbitrary configuration injection')]) :-
  tmp_file_stream(text, File, Out),
  glsa_fixture_xml(Xml),
  write(Out, Xml),
  close(Out),
  glsa:parse_file(File, '202501-03', advisory('202501-03', Title), Packages, Ranges),
  Packages = [package('202501-03', 'dev-python', pip, '*')],
  memberchk(range('202501-03', 'dev-python', pip, vulnerable, lt, _, '*'), Ranges),
  memberchk(range('202501-03', 'dev-python', pip, unaffected, ge, _, '*'), Ranges),
  delete_file(File).

test(version_lt_matches) :-
  atom_codes('23.2', C1), once(phrase(eapi:version(V1), C1, [])),
  atom_codes('23.3', C2), once(phrase(eapi:version(V2), C2, [])),
  glsa:version_matches(lt, V2, V1),
  \+ glsa:version_matches(lt, V2, V2),
  glsa:version_matches(ge, V2, V2).

test(revision_range) :-
  atom_codes('1.0-r1', C1), once(phrase(eapi:version(V1), C1, [])),
  atom_codes('1.0-r2', C2), once(phrase(eapi:version(V2), C2, [])),
  glsa:version_matches(rlt, V2, V1),
  glsa:version_matches(rge, V1, V1),
  \+ glsa:version_matches(rgt, V1, V1).

test(filter_new_affected_skips_applied,
     [setup(glsa_filter_setup),
      cleanup(glsa_filter_cleanup)]) :-
  glsa:applied('209901-01'),
  \+ glsa:applied('209901-02'),
  \+ glsa:filter_allows(new_affected, '209901-01'),
  glsa:filter_allows(new_glsa, '209901-02'),
  \+ glsa:filter_allows(new_glsa, '209901-01'),
  glsa:filter_allows(security, '209901-01').

glsa_filter_setup :-
  glsa:clear_facts,
  assertz(glsa:advisory('209901-01', 'applied one')),
  assertz(glsa:advisory('209901-02', 'fresh one')),
  assertz(glsa:loaded),
  assertz(glsa:cache_source(test)),
  tmp_file('glsa_injected', File),
  setup_call_cleanup(
    open(File, write, Out, [encoding(utf8)]),
    format(Out, '209901-01~n', []),
    close(Out)
  ),
  retractall(glsa:injected_file_override(_)),
  assertz(glsa:injected_file_override(File)).

glsa_filter_cleanup :-
  ( retract(glsa:injected_file_override(File)) ->
      ( exists_file(File) -> delete_file(File) ; true )
  ; true
  ),
  glsa:clear_facts.


% -----------------------------------------------------------------------------
%  Advisory detail (full text) tests
% -----------------------------------------------------------------------------

glsa_detail_fixture_xml(Xml) :-
  atomic_list_concat([
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<!DOCTYPE glsa SYSTEM "http://www.gentoo.org/dtd/glsa.dtd">',
    '<glsa id="209902-01">',
    '  <title>libfoo: Multiple vulnerabilities</title>',
    '  <synopsis>',
    '    Multiple vulnerabilities in libfoo &lt;= 1.2 might allow',
    '    code execution.',
    '  </synopsis>',
    '  <product type="ebuild">libfoo</product>',
    '  <announced>2099-02-01</announced>',
    '  <revised count="3">2099-02-05</revised>',
    '  <bug>123456</bug>',
    '  <bug>123457</bug>',
    '  <access>local, remote</access>',
    '  <affected>',
    '    <package name="dev-libs/libfoo" auto="yes" arch="*">',
    '      <unaffected range="ge">1.3</unaffected>',
    '      <vulnerable range="lt">1.3</vulnerable>',
    '    </package>',
    '  </affected>',
    '  <background>',
    '    <p>libfoo is a <i>library</i>.</p>',
    '  </background>',
    '  <description>',
    '    <p>Multiple issues were found:</p>',
    '    <ul>',
    '      <li>A buffer overflow (CVE-2099-0001)</li>',
    '      <li>An <b>integer</b> overflow (CVE-2099-0002)</li>',
    '    </ul>',
    '  </description>',
    '  <impact type="high">',
    '    <p>An attacker could execute code.</p>',
    '  </impact>',
    '  <workaround>',
    '    <p>There is no known workaround at this time.</p>',
    '  </workaround>',
    '  <resolution>',
    '    <p>All libfoo users should upgrade:</p>',
    '    <code>',
    '      # emerge --sync',
    '      # emerge --ask --oneshot --verbose "&gt;=dev-libs/libfoo-1.3"',
    '    </code>',
    '  </resolution>',
    '  <references>',
    '    <uri link="https://nvd.nist.gov/vuln/detail/CVE-2099-0001">CVE-2099-0001</uri>',
    '    <uri>https://example.org/advisory</uri>',
    '  </references>',
    '</glsa>'
  ], '\n', Xml).

glsa_detail_fixture_file(File) :-
  tmp_file_stream(text, File, Out),
  glsa_detail_fixture_xml(Xml),
  write(Out, Xml),
  close(Out).

test(detail_scalar_fields, [setup(glsa_detail_fixture_file(File)),
                            cleanup(delete_file(File))]) :-
  glsa:detail_from_file(File, Detail),
  memberchk(synopsis(Syn), Detail),
  Syn == "Multiple vulnerabilities in libfoo <= 1.2 might allow code execution.",
  memberchk(announced('2099-02-01'), Detail),
  memberchk(revised('2099-02-05', 3), Detail),
  memberchk(access("local, remote"), Detail),
  memberchk(severity(high), Detail),
  memberchk(bugs(['123456', '123457']), Detail).

test(detail_prose_blocks, [setup(glsa_detail_fixture_file(File)),
                           cleanup(delete_file(File))]) :-
  glsa:detail_from_file(File, Detail),
  memberchk(background([p("libfoo is a library.")]), Detail),
  memberchk(description([p("Multiple issues were found:"), list(Items)]), Detail),
  Items == ["A buffer overflow (CVE-2099-0001)",
            "An integer overflow (CVE-2099-0002)"],
  memberchk(impact([p("An attacker could execute code.")]), Detail),
  memberchk(resolution([p("All libfoo users should upgrade:"), code(Code)]), Detail),
  Code == "# emerge --sync\n# emerge --ask --oneshot --verbose \">=dev-libs/libfoo-1.3\"".

test(detail_references, [setup(glsa_detail_fixture_file(File)),
                         cleanup(delete_file(File))]) :-
  glsa:detail_from_file(File, Detail),
  memberchk(references(Refs), Detail),
  Refs == [ref('CVE-2099-0001', 'https://nvd.nist.gov/vuln/detail/CVE-2099-0001'),
           ref('https://example.org/advisory', 'https://example.org/advisory')].

test(xml_unescape, [true(Out == "a <= b && \"q\" 'AB' &unknown; x&")]) :-
  glsa:xml_unescape("a &lt;= b &amp;&amp; &quot;q&quot; &apos;&#65;&#x42;&apos; &unknown; x&", Out).

test(xml_element_word_boundary, [true(Inner == "text")]) :-
  once(glsa:xml_element("<product>x</product><p class=\"a\">text</p>", "p", _, Inner, _)).

test(package_advisories_newest_first,
     [setup(glsa_pkg_setup), cleanup(glsa:clear_facts),
      true(Ids == ['209901-03', '209901-02', '209812-01'])]) :-
  glsa:package_advisories('dev-libs', libfoo, Ids).

glsa_pkg_setup :-
  glsa:clear_facts,
  assertz(glsa:advisory('209812-01', 'old')),
  assertz(glsa:advisory('209901-02', 'mid')),
  assertz(glsa:advisory('209901-03', 'new')),
  assertz(glsa:advisory('209901-04', 'other package')),
  assertz(glsa:package('209901-02', 'dev-libs', libfoo, '*')),
  assertz(glsa:package('209812-01', 'dev-libs', libfoo, '*')),
  assertz(glsa:package('209901-03', 'dev-libs', libfoo, 'amd64 x86')),
  assertz(glsa:package('209901-03', 'dev-libs', libfoo, '*')),
  assertz(glsa:package('209901-04', 'dev-libs', libbar, '*')),
  assertz(glsa:loaded),
  assertz(glsa:cache_source(test)).

test(glob_range_parsed) :-
  Block = "<vulnerable range=\"eq\" slot=\"0/esr78\">1.5*</vulnerable>",
  once(glsa:range_element(Block, vulnerable, glob, '1.5*', '0/esr78')).

test(non_eq_glob_dropped, [fail]) :-
  Block = "<vulnerable range=\"ge\">1.5*</vulnerable>",
  glsa:range_element(Block, _, _, _, _).

test(glob_range_component) :-
  atom_codes('1.5.1', C1), once(phrase(eapi:version(V1), C1, [])),
  atom_codes('1.50', C2), once(phrase(eapi:version(V2), C2, [])),
  glsa:version_matches(glob, '1.5*', V1),
  \+ glsa:version_matches(glob, '1.5*', V2).

test(slot_and_subslot) :-
  glsa:slot_matches('0/esr78', '0', esr78),
  \+ glsa:slot_matches('0/esr78', '0', none),
  glsa:slot_matches('0', '0', none),
  glsa:slot_matches('*', '4', other).

test(unaffected_glob_clears,
     [setup(glsa_glob_setup), cleanup(glsa_glob_cleanup)]) :-
  atom_codes('1.5.1', C), once(phrase(eapi:version(V), C, [])),
  glsa:range_matches('glob-1', c, n, vulnerable, V, '0', esr78),
  glsa:range_matches('glob-1', c, n, unaffected, V, '0', esr78),
  \+ glsa:range_matches('glob-1', c, n, vulnerable, V, '0', none).

glsa_glob_setup :-
  atom_codes('1.5.1', C), once(phrase(eapi:version(V), C, [])),
  assertz(glsa:range('glob-1', c, n, vulnerable, glob, '1.5*', '0/esr78')),
  assertz(glsa:range('glob-1', c, n, unaffected, eq, V, '0/esr78')).

glsa_glob_cleanup :-
  retractall(glsa:range('glob-1', _, _, _, _, _, _)).

:- end_tests(glsa).


% -----------------------------------------------------------------------------
%  Full coverage for Domain/Gentoo/glsa.pl
% -----------------------------------------------------------------------------

glsatest_mktemp(Prefix, Dir) :-
  tmp_file_stream(text, Base, Stream),
  close(Stream),
  delete_file(Base),
  atomic_list_concat([Base, '_', Prefix], Dir),
  make_directory(Dir).

glsatest_rm_rf(Path) :-
  exists_directory(Path), !,
  directory_files(Path, Entries),
  forall((member(E, Entries), E \== '.', E \== '..'),
         ( os:compose_path(Path, E, Child),
           glsatest_rm_rf(Child) )),
  catch(delete_directory(Path), _, true).
glsatest_rm_rf(Path) :-
  exists_file(Path), !,
  catch(delete_file(Path), _, true).
glsatest_rm_rf(_).

:- dynamic portage:get_location/1.

:- begin_tests(glsa_full_coverage).

test(glsa_cache_search_upgrade_and_security_sets, [nondet]) :-
  glsatest_mktemp(glsa_cov, TmpDir),
  os:compose_path(TmpDir, 'Knowledge', KDir),
  make_directory(KDir),
  os:compose_path(TmpDir, 'metadata/glsa', GlsaDir),
  make_directory_path(GlsaDir),
  os:compose_path(GlsaDir, 'glsa-209901-01.xml', XmlDest),
  setup_call_cleanup(
    open(XmlDest, write, SX),
    format(SX, '<?xml version="1.0" encoding="UTF-8"?>~n<glsa id="209901-01">~n  <title>libfoo: test</title>~n  <synopsis>s</synopsis>~n  <product type="ebuild">libfoo</product>~n  <announced>2026-01-01</announced>~n  <revised count="1">2026-01-01</revised>~n  <affected>~n    <package name="dev-libs/libfoo" auto="yes" arch="*">~n      <unaffected range="ge">1.5</unaffected>~n      <vulnerable range="lt">1.5</vulnerable>~n    </package>~n  </affected>~n</glsa>~n', []),
    close(SX)),
  os:compose_path(TmpDir, 'injected', InjectedFile),
  V10 = version([1,0], '', 4, 0, [], 0, '1.0'),
  V15 = version([1,5], '', 4, 0, [], 0, '1.5'),
  V20 = version([2,0], '', 4, 0, [], 0, '2.0'),
  knowledgebase:vdb_repository(Vdb),
  setup_call_cleanup(
    ( working_directory(OldCwd, TmpDir),
      retractall(config:glsa_dir(_)),
      asserta(config:glsa_dir(GlsaDir)),
      retractall(glsa:injected_file_override(_)),
      asserta(config:glsa_injected_file(InjectedFile)),
      asserta(script:mock_exec(sync, _, _)),
      assertz(cache:ordered_entry(Vdb, 'dev-libs/libfoo-1.0', 'dev-libs', libfoo, V10)),
      assertz(cache:entry_metadata(Vdb, 'dev-libs/libfoo-1.0', slot, slot('0'))),
      assertz(cache:ordered_entry(qtest, 'dev-libs/libfoo-1.0', 'dev-libs', libfoo, V10)),
      assertz(cache:entry_metadata(qtest, 'dev-libs/libfoo-1.0', slot, slot('0'))),
      assertz(cache:entry_metadata(qtest, 'dev-libs/libfoo-1.0', keywords, stable(amd64))),
      assertz(cache:ordered_entry(qtest, 'dev-libs/libfoo-1.5', 'dev-libs', libfoo, V15)),
      assertz(cache:entry_metadata(qtest, 'dev-libs/libfoo-1.5', slot, slot('0'))),
      assertz(cache:entry_metadata(qtest, 'dev-libs/libfoo-1.5', keywords, stable(amd64))),
      assertz(cache:ordered_entry(qtest, 'dev-libs/libfoo-2.0', 'dev-libs', libfoo, V20)),
      assertz(cache:entry_metadata(qtest, 'dev-libs/libfoo-2.0', slot, slot('0'))),
      assertz(cache:entry_metadata(qtest, 'dev-libs/libfoo-2.0', keywords, stable(amd64))),
      unittest:accept_stable_amd64,
      glsa:clear_facts
    ),
    with_output_to(string(_),
      ( % Source dir via config:glsa_dir and via portage:get_location
        glsa:source_dir(GlsaDir),
        retractall(config:glsa_dir(_)),
        asserta(portage:get_location(TmpDir)),
        glsa:source_dir(GlsaDir),
        asserta(config:glsa_dir(GlsaDir)),
        glsa:directory(GlsaDir),
        glsa:git_dir(GlsaDir, GitDir),
        % Injected file paths and inject/applied
        glsa:injected_file(InjectedFile),
        retractall(config:glsa_injected_file(_)),
        glsa:injected_file(_DefaultInj),
        asserta(config:glsa_injected_file(InjectedFile)),
        glsa:inject('209901-99'),
        glsa:inject('209901-99'),
        glsa:applied('209901-99'),
        % ensure_directory branches (rsync tree, git tree, missing tree)
        glsa:ensure_directory(GlsaDir),
        make_directory(GitDir),
        glsa:ensure_directory(GlsaDir),
        os:compose_path(TmpDir, 'missing_glsa', MissingDir),
        retractall(config:glsa_dir(_)),
        asserta(config:glsa_dir(MissingDir)),
        \+ glsa:ensure_directory(_),
        glsa:cache_save,
        retractall(config:glsa_dir(_)),
        asserta(config:glsa_dir(GlsaDir)),
        % cache_save / cache_available / cache_load / ensure_loaded
        glsa:cache_save,
        glsa:cache_available,
        glsa:clear_facts,
        glsa:ensure_loaded,
        % Detail & URLs
        glsa:advisory_file('209901-01', XmlDest),
        glsa:advisory_url('209901-01', _),
        glsa:bug_url('12345', _),
        glsa:detail('209901-01', _),
        glsa:strip_tags("<unclosed", ""),
        % Operators & version_matches
        forall(member(Op, [le, lt, eq, gt, ge, rge, rle, rgt, rlt]),
               ( glsa:normalize_op(Op, Op),
                 ignore(glsa:version_matches(Op, V15, V10)) )),
        % host_arch fallbacks (when config:portage_confdir suppresses fallback:env)
        asserta(config:portage_confdir(TmpDir)),
        retractall(userconfig:env(_, _)),
        setenv('ARCH', 'amd64'),
        glsa:host_arch(amd64),
        unsetenv('ARCH'),
        setenv('ACCEPT_KEYWORDS', '~amd64'),
        glsa:host_arch(amd64),
        unsetenv('ACCEPT_KEYWORDS'),
        retractall(config:portage_confdir(TmpDir)),
        glsa:arch_matches('amd64 x86'),
        % range_matches/6, entry_covered/2, least_upgrade/6, merge_list/2, search/2, entry_status/3
        ignore(glsa:range_matches('209901-01', 'dev-libs', libfoo, vulnerable, V10, '0')),
        glsa:entry_covered('209901-01', qtest://'dev-libs/libfoo-1.0'),
        glsa:least_upgrade('dev-libs', libfoo, '0', V10, '209901-01', _),
        glsa:merge_list('209901-01', _),
        findall(Id, glsa:search([id('209901-01'), title(_), package('dev-libs', libfoo),
                                 applied(false), vulnerable(true)], Id), _),
        glsa:search_goal(vulnerable(false), '209901-99', _),
        findall(Id2, glsa:search([applied(true), vulnerable(false)], Id2), _),
        glsa:entry_status('209901-01', qtest://'dev-libs/libfoo-1.0', vulnerable),
        glsa:entry_status('209901-01', qtest://'dev-libs/libfoo-1.5', unaffected),
        glsa:entry_status('209901-01', qtest://'dev-libs/unknown-1.0', unlisted),
        % security_atoms / reduce_atoms / atom_cn_slot_ver / keep_highest_per_key
        forall(member(Filt, [security, affected, new_glsa, new_affected]),
               glsa:security_atoms(Filt, _)),
        glsa:reduce_atoms([], []),
        glsa:reduce_atoms(['=dev-libs/libfoo-1.5', '=dev-libs/libfoo-2.0', '=dev-libs/unlisted-1.0'], _),
        phrase(prolog:message(glsa_parse_error('209901-01', err)), _)
      )),
    ( working_directory(_, OldCwd),
      retractall(config:glsa_dir(_)),
      retractall(config:glsa_injected_file(_)),
      retractall(portage:get_location(TmpDir)),
      retractall(script:mock_exec(_, _, _)),
      retractall(cache:ordered_entry(Vdb, 'dev-libs/libfoo-1.0', _, _, _)),
      retractall(cache:entry_metadata(Vdb, 'dev-libs/libfoo-1.0', _, _)),
      retractall(cache:ordered_entry(qtest, 'dev-libs/libfoo-1.0', _, _, _)),
      retractall(cache:entry_metadata(qtest, 'dev-libs/libfoo-1.0', _, _)),
      retractall(cache:ordered_entry(qtest, 'dev-libs/libfoo-1.5', _, _, _)),
      retractall(cache:entry_metadata(qtest, 'dev-libs/libfoo-1.5', _, _)),
      retractall(cache:ordered_entry(qtest, 'dev-libs/libfoo-2.0', _, _, _)),
      retractall(cache:entry_metadata(qtest, 'dev-libs/libfoo-2.0', _, _)),
      glsa:clear_facts,
      glsatest_rm_rf(TmpDir)
    )).

:- end_tests(glsa_full_coverage).

