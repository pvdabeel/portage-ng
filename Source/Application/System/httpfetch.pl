/*
 Author: Pieter Van den Abeele
 E-mail: pvdabeel@mac.com
 Copyright (c) 2005-2026, Pieter Van den Abeele

 Distributed under the terms of the LICENSE file in the root directory of this
 project.
*/

/** <module> HTTPFETCH
Shared JSON-over-HTTP transport for API clients (Bugzilla, Repology).

Curl piped straight into the JSON reader is the primary transport —
the same choice as download.pl: curl is what every other network
fetch in portage-ng already relies on, and SWI's http_open/3 was
observed to block indefinitely in the TLS handshake on one macOS
host while curl on the same host answered in under a second.
http_open/3 remains as the fallback when no curl binary is installed.

Callers keep their own failure policy (log-and-fail vs error term);
this module only standardizes the wire mechanics: User-Agent and
Accept headers, protocol allowlist, timeout, optional extra curl
arguments, and curl exit-code rendering.
*/

:- module(httpfetch, []).

:- use_module(library(http/json)).
:- use_module(library(http/http_open)).
:- use_module(library(process)).
:- use_module(library(option)).

% =============================================================================
%  HTTPFETCH declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Curl transport
% -----------------------------------------------------------------------------

%! httpfetch:fetch_json_curl(+URL, +UA, +Options, -Dict, -Status) is det.
%
% GET URL as JSON via curl. Status is `ok` (Dict bound), `no_curl`
% (curl binary missing) or `error(Why)` (curl exit / unparsable body,
% Why rendered by httpfetch:curl_exit_text/2). Options:
%   * timeout(Seconds)      — curl --max-time (default 60)
%   * proto(Proto)          — curl --proto allowlist (default '=https')
%   * extra_curl_args(List) — extra arguments before the URL (default [])

httpfetch:fetch_json_curl(URL, UA, Options, Dict, Status) :-
  option(timeout(Timeout), Options, 60),
  option(proto(Proto), Options, '=https'),
  option(extra_curl_args(ExtraArgs), Options, []),
  format(atom(UAHeader), 'User-Agent: ~w', [UA]),
  format(atom(TimeoutArg), '~w', [Timeout]),
  append([['-s', '-f', '-L', '--proto', Proto,
           '--max-time', TimeoutArg,
           '-H', UAHeader, '-H', 'Accept: application/json'],
          ExtraArgs,
          [URL]],
         Args),
  catch(process_create(path(curl),
                       Args,
                       [stdout(pipe(Out)), stderr(null), process(Pid)]),
        error(existence_error(_, _), _),
        Status = no_curl),
  ( Status == no_curl
  -> true
  ;  set_stream(Out, encoding(utf8)),
     catch(call_cleanup(json_read_dict(Out, Dict0, [default_tag(json)]),
                        close(Out)),
           _, Dict0 = none),
     process_wait(Pid, exit(Code)),
     ( Code =:= 0, Dict0 \== none
     -> Dict = Dict0, Status = ok
     ;  httpfetch:curl_exit_text(Code, Why),
        Status = error(Why)
     )
  ).


%! httpfetch:curl_exit_text(+Code, -Text) is det.
%
% Human-readable reason for a curl exit code.

httpfetch:curl_exit_text(0,  'unparsable JSON') :- !.
httpfetch:curl_exit_text(22, 'HTTP error reply') :- !.
httpfetch:curl_exit_text(28, 'timeout') :- !.
httpfetch:curl_exit_text(6,  'could not resolve host') :- !.
httpfetch:curl_exit_text(7,  'connection refused') :- !.
httpfetch:curl_exit_text(Code, Text) :-
  format(atom(Text), 'curl exit ~w', [Code]).


% -----------------------------------------------------------------------------
%  http_open fallback transport
% -----------------------------------------------------------------------------

%! httpfetch:fetch_json_http_open(+URL, +UA, +Options, -Dict) is semidet.
%
% GET URL as JSON via SWI's HTTP client. Options: timeout(Seconds)
% (default 60). Fails on a non-200 reply by throwing
% error(http_status(URL, Code), _); transport and parse exceptions
% propagate to the caller, which owns the failure policy.

httpfetch:fetch_json_http_open(URL, UA, Options, Dict) :-
  option(timeout(Timeout), Options, 60),
  setup_call_cleanup(
    http_open(URL, In, [
      request_header('User-Agent' = UA),
      request_header('Accept' = 'application/json'),
      status_code(Code),
      timeout(Timeout)
    ]),
    ( Code == 200
    -> set_stream(In, encoding(utf8)),
       json_read_dict(In, Dict, [default_tag(json)])
    ;  throw(error(http_status(URL, Code),
                   httpfetch:fetch_json_http_open/4))
    ),
    close(In)
  ).


% -----------------------------------------------------------------------------
%  Error rendering
% -----------------------------------------------------------------------------

%! httpfetch:error_text(+Error, -Text) is det.
%
% Render an exception term as a single atom.

httpfetch:error_text(E, Text) :-
  format(atom(Text), '~w', [E]).
