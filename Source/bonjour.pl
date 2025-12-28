/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> BONJOUR
Advertise and discover services on the network using multi-cast DNS also known
as zeroconf or Apple Bonjour.
*/

:- module(bonjour, []).

% =============================================================================
%  BONJOUR declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Advertise a service
% -----------------------------------------------------------------------------

%! bonjour:advertise
%
% Advertises a service using mDNS

bonjour:advertise :-
  interface:process_server(Host, Port),
  config:bonjour_service(Service),
  bonjour:advertise(Service,Host,Port).


%! bonjour:advertise(+Host,+Port)
%
% Advertise a Host and Port using mDNS

bonjour:advertise(Host, Port) :-
  config:bonjour_service(Service),
  bonjour:advertise(Service,Host,Port).


%! bonjour:advertise(+Service,+Host,+Port)
%
% Advertise a Service on Host and Port using mDNS

bonjour:advertise(Service, Host, Port) :-
  format(string(Cmd),'dns-sd -R ~w ~w local ~w',[Host,Service,Port]),
  Thread = process_create(path(bash),['-c',Cmd],[stdout(null),stderr(null)]),
  thread_create(Thread,_,[detached(true)]).


% -----------------------------------------------------------------------------
%  Discover services  
% -----------------------------------------------------------------------------

%! bonjour:discover(-Hosts)
%
% Discover Hosts announced using mDNS.
% Hosts is a prolog list containing list pairs of Host and Port.

bonjour:discover(Hosts) :-
  config:bonjour_service(Service),
  bonjour:discover(Service,Hosts).


%! bonjour:discover(+Service,-Hosts)
%
% Discover Hosts providing Service, announced using mDNS.
% Hosts is a prolog list containing list pairs of Host and Port.

bonjour:discover(Service, Hosts) :-
  browse_hostnames(Service,Hostnames),
  setof([Host,Port],
        (member(Host,Hostnames),bonjour:resolve_hostname(Service,Host,Port)),
        Hosts),
  !.
bonjour:discover(_Service, []).


% -----------------------------------------------------------------------------
%  Bonjour Helpers
% -----------------------------------------------------------------------------

%! bonjour:browse_hostnames(-Hostnames)
%
% Called by discover, returns a set of hostnames providing service.

bonjour:browse_hostnames(Service, Hostnames) :-
  os:bash_dns_sd(['-t','1','-B', Service],Lines),
  findall(Hostname,(member(Line, Lines), 
          bonjour:browse_line_hostname(Service,Line, Hostname)),
          Raw),
  list_to_set(Raw, Hostnames).


%! bonjour:browse_line_hostname(+Line,-Hostname)
%
% Given a line of output from dns-sd, parses hostname information.

bonjour:browse_line_hostname(Service, Line, Host) :-
  sub_string(Line, _, _, After, Service),
  sub_string(Line, _, After, 0, RawHost),
  split_string(RawHost, "", " \t", [Host]).


%! bonjour:resolve_hostname(+Hostname,-Port)
%
% Given a hostname, retrieves port number on which the service is running.

bonjour:resolve_hostname(Service, Hostname, Port) :-
  format(string(Cmd),'dns-sd -t 1 -L "~w" ~w',[Hostname,Service]),
  os:bash_lines(Cmd,Lines),
  member(Line,Lines),
  bonjour:resolve_line_port(Line,Port),!.


%! bonjour:resolve_line_port(+Line,-Port)
%
% Given a line of outpt from dns-sd, parses port information

bonjour:resolve_line_port(Line, Port) :-
  re_matchsub('reached at ([0-9A-Za-z-.]+):([0-9]+)',Line,M,[capture_type(string)]),
  number_string(Port,M.2).