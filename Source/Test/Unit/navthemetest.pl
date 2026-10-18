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
           \+ sub_string(Content, _, _, _, "</script")
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
