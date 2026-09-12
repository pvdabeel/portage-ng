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

:- end_tests(glsa).
