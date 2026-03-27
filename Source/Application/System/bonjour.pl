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
  config:hostname(Host),
  interface:get_port(Port),
  config:bonjour_service(Name),
  bonjour:advertise(Name,Host,Port).


%! bonjour:advertise(+Host,+Port)
%
% Advertise a Host and Port using mDNS

bonjour:advertise(Host, Port) :-
  config:bonjour_service(Name),
  bonjour:advertise(Name,Host,Port).


%! bonjour:advertise(+Service,+Host,+Port)
%
% Advertise a Service on Host and Port using mDNS

bonjour:advertise(Service, Host, Port) :-
  subprocess:dns_sd(advertise, Host, Service, Port).


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

%! bonjour:browse_hostnames(+Service, -Hostnames)
%
% Called by discover, returns a set of hostnames providing service.

bonjour:browse_hostnames(Service, Hostnames) :-
  subprocess:dns_sd(browse, Service, Hostnames).


%! bonjour:resolve_hostname(+Service, +Hostname, -Port)
%
% Given a hostname, retrieves port number on which the service is running.

bonjour:resolve_hostname(Service, Hostname, Port) :-
  subprocess:dns_sd(resolve, Service, Hostname, Port).