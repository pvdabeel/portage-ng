/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2025, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> BONJOUR
Advertise and discover services on the network using multi-cast DNS (Apple Bonjour)
*/

:- module(bonjour, []).

% ********************
% BONJOUR declarations
% ********************

% ---------
% Advertise
% ---------

%! advertise
%
% Advertises a service on mDNS

advertise :-
  interface:process_server(_,Port),
  config:hostname(Service),
  advertise(Service,Port).


%! advertise(+Service,+Port)
%
% Advertise a service on mDNS

advertise(Service, Port) :-
  format(string(Cmd),'dns-sd -R ~w _prolog._tcp local ~w',[Service,Port]),
  Thread = process_create(path(bash),['-c',Cmd],[stdout(null),stderr(null)]),
  thread_create(Thread,_,[detached(true)]).


% --------
% Discover
% --------

%! discover(-Services)
%
% Discover services. Services is a prolog lists containing
% list of Host and Port.

discover(Services) :-
  browse_hosts(Hosts),
  setof([H,Port],
        (member(H,Hosts),resolve_host(H,Port)),
        Services),
  !.
discover([]).


% -------
% Helpers
% -------

%! browse_hosts(-Hosts)
%
% Called by discover, returns a set of hosts providing service.

browse_hosts(Hosts) :-
  bash_dns_sd(['-t','1','-B', '_prolog._tcp'],Lines),
  findall(Host,(member(Line, Lines), browse_line_host(Line, Host)),Raw),
  list_to_set(Raw, Hosts).


%! browse_line_host(+Line,-Host)
%
% Given a line of output from dns-sd, parses host information.

browse_line_host(Line,Host) :-
  sub_string(Line,_,_,_,'_prolog._tcp.'),
  split_string(Line," \t"," \t",Parts),
  last(Parts,Host).


%! resolve_host(+Host,-Port)
%
% Given a host, retrieves port number on which the service is running..

resolve_host(Host,Port) :-
  format(string(Cmd),'dns-sd -t 1 -L ~w _prolog._tcp.',[Host]),
  bash_lines(Cmd,Lines),
  member(Line,Lines),
  resolve_line_port(Line,Port),!.


%! resolve_line_port(+Line,-Port)
%
% Given a line of outpt from dns-sd, parses port information

resolve_line_port(Line,Port) :-
  re_matchsub('reached at ([0-9A-Za-z-.]+):([0-9]+)',Line,M,[capture_type(string)]),
  number_string(Port,M.2).


% -------------
% bash wrappers
% -------------

%! bash_dns_sd(+ArgList,-Lines)
%
% Calls dns-sd command in bash with given ArgList
% Returns lines of strings (output of the command)

bash_dns_sd(ArgList,Lines) :-
  atomic_list_concat(['dns-sd'|ArgList],' ',Cmd),
  bash_lines(Cmd,Lines).


%! bash_lines(+Cmd,-Lines)
%
% Runs a given command in bash
% Returns lines of strings (output of the command)

bash_lines(Cmd,Lines) :-
  process_create(path(bash),['-c',Cmd],[stdout(pipe(Out)),process(Pid)]),
  call_cleanup(reader:read_lines_to_strings(Out,Lines),(close(Out),process_wait(Pid,_))).
