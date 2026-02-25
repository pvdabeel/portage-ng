/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> SUBPROCESS
Predicates for spawning and interacting with external processes.
*/

:- module(subprocess, []).

% =============================================================================
%  SUBPROCESS declarations
% =============================================================================

%! subprocess:spawn(+Program, +Args)
%
% Spawn a detached external process (fire-and-forget).
% Stdout and stderr are discarded.

subprocess:spawn(Program, Args) :-
  Thread = process_create(path(Program), Args, [stdout(null), stderr(null)]),
  thread_create(Thread, _, [detached(true)]).

%! subprocess:spawn(+Program, +Args, -Lines)
%
% Run an external process, wait for it to complete, and return its
% stdout as a list of strings (one per line).

subprocess:spawn(Program, Args, Lines) :-
  process_create(path(Program), Args, [stdout(pipe(Out)), process(Pid)]),
  call_cleanup(
    reader:read_lines_to_strings(Out, Lines),
    ( close(Out), process_wait(Pid, _) )
  ).

%! subprocess:spawn(+Program, +Args, :Parser, -Results)
%
% Run an external process, parse each output line with Parser, and
% return the collected Results. Parser is called as call(Parser, Line, Result);
% lines for which Parser fails are silently skipped.

:- meta_predicate subprocess:spawn(+, +, 3, -).

subprocess:spawn(Program, Args, Parser, Results) :-
  subprocess:spawn(Program, Args, Lines),
  findall(R, (member(L, Lines), call(Parser, L, R)), Results).


% =============================================================================
%  dns-sd interface
% =============================================================================

%! subprocess:dns_sd(+browse, +Service, -Hostnames)
%
% Browse for hosts advertising Service via mDNS.

subprocess:dns_sd(browse, Service, Hostnames) :-
  subprocess:spawn('dns-sd', ['-t','1','-B', Service],
                   subprocess:dns_sd_parse_host(Service), Raw),
  list_to_set(Raw, Hostnames).

%! subprocess:dns_sd(+advertise, +Host, +Service, +Port)
%
% Advertise a Service on Host and Port via mDNS (fire-and-forget).

subprocess:dns_sd(advertise, Host, Service, Port) :-
  subprocess:spawn('dns-sd', ['-R', Host, Service, 'local', Port]).

%! subprocess:dns_sd(+resolve, +Service, +Hostname, -Port)
%
% Resolve a Hostname advertising Service to its Port via mDNS.

subprocess:dns_sd(resolve, Service, Hostname, Port) :-
  subprocess:spawn('dns-sd', ['-t','1','-L', Hostname, Service],
                   subprocess:dns_sd_parse_port, Ports),
  Ports = [Port|_],
  !.

subprocess:dns_sd_parse_host(Service, Line, Host) :-
  sub_string(Line, _, _, After, Service),
  sub_string(Line, _, After, 0, RawHost),
  split_string(RawHost, "", " \t", [Host]).

subprocess:dns_sd_parse_port(Line, Port) :-
  re_matchsub('reached at ([0-9A-Za-z-.]+):([0-9]+)', Line, M, [capture_type(string)]),
  number_string(Port, M.2).
