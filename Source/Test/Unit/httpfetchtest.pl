/*
 Author: Pieter Van den Abeele
 E-mail: pvdabeel@mac.com
 Copyright (c) 2005-2026, Pieter Van den Abeele

 Distributed under the terms of the LICENSE file in the root directory of this
 project.
*/

/** <module> HTTPFETCHTEST
Unit tests for the shared JSON-over-HTTP transport
(Source/Application/System/httpfetch.pl).

The curl path is exercised offline against a file:// JSON fixture.
*/

:- module(httpfetchtest, []).

:- use_module(library(plunit)).

% =============================================================================
%  HTTPFETCHTEST declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Transport helper tests
% -----------------------------------------------------------------------------

:- begin_tests(httpfetch).

test(curl_exit_text_known,
     [true(A-B-C == 'HTTP error reply'-timeout-'curl exit 99')]) :-
  httpfetch:curl_exit_text(22, A),
  httpfetch:curl_exit_text(28, B),
  httpfetch:curl_exit_text(99, C).

test(error_text, [true(Text == 'error(foo,bar)')]) :-
  httpfetch:error_text(error(foo, bar), Text).

test(fetch_json_curl_file_fixture,
     [true(Dict == json{hello: "world"})]) :-
  tmp_file(httpfetchtest, Path),
  setup_call_cleanup(
    setup_call_cleanup(
      open(Path, write, S),
      format(S, '{"hello":"world"}', []),
      close(S)),
    ( format(atom(URL), 'file://~w', [Path]),
      httpfetch:fetch_json_curl(URL, 'httpfetch-test/1.0',
                                [proto('=file')], Dict, Status),
      Status == ok
    ),
    delete_file(Path)).

:- end_tests(httpfetch).
