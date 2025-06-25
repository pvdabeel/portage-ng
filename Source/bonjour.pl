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
% Advertises a service using mDNS

advertise :-
  interface:process_server(Host,Port),
  config:bonjour_service(Service),
  advertise(Service,Host,Port).


%! advertise(+Host,+Port)
%
% Advertise a Host and Port using mDNS

advertise(Host, Port) :-
  config:bonjour_service(Service),
  advertise(Service,Host,Port).


%! advertise(+Service,+Host,+Port)
%
% Advertise a Service on Host and Port using mDNS

advertise(Service, Host, Port) :-
  format(string(Cmd),'dns-sd -R ~w ~w local ~w',[Host,Service,Port]),
  Thread = process_create(path(bash),['-c',Cmd],[stdout(null),stderr(null)]),
  thread_create(Thread,_,[detached(true)]).


% --------
% Discover
% --------

%! discover(-Hosts)
%
% Discover Hosts announced using mDNS.
% Hosts is a prolog list containing list pairs of Host and Port.

discover(Hosts) :-
  config:bonjour_service(Service),
  discover(Service,Hosts).


%! discover(+Service,-Hosts)
%
% Discover Hosts providing Service, announced using mDNS.
% Hosts is a prolog list containing list pairs of Host and Port.

discover(Service,Hosts) :-
  browse_hostnames(Service,Hostnames),
  setof([Host,Port],
        (member(Host,Hostnames),resolve_hostname(Service,Host,Port)),
        Hosts),
  !.
discover(_Service,[]).


% -------
% Helpers
% -------

%! browse_hostnames(-Hostnames)
%
% Called by discover, returns a set of hostnames providing service.

browse_hostnames(Service,Hostnames) :-
  bash_dns_sd(['-t','1','-B', Service],Lines),
  findall(Hostname,(member(Line, Lines), browse_line_hostname(Service,Line, Hostname)),Raw),
  list_to_set(Raw, Hostnames).


%! browse_line_hostname(+Line,-Hostname)
%
% Given a line of output from dns-sd, parses hostname information.

browse_line_hostname(Service,Line,Host) :-
  sub_string(Line,_,_,_,Service),
  split_string(Line," \t"," \t",Parts),
  last(Parts,Host).


%! resolve_hostname(+Hostname,-Port)
%
% Given a hostname, retrieves port number on which the service is running.

resolve_hostname(Service,Hostname,Port) :-
  format(string(Cmd),'dns-sd -t 1 -L ~w ~w',[Hostname,Service]),
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
