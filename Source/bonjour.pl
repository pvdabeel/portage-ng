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

%! advertise
%
% Advertises a service on mDNS,

advertise :-
  interface:process_server(_,Port),
  config:hostname(Service),
  advertise(Service,Port).


%! advertise(Service,Port)
%
% Advertise a service on mDNS

advertise(Service,Port) :-
    format(string(Command), 'dns-sd -R ~w _prolog._tcp local ~w', [Service,Port]),
    Thread = process_create(path(bash), ['-c', Command], [stdout(null),stderr(null)]),
    thread_create(Thread,_,[detached(true)]).


%! discover(Services)
%
% Discover services

discover(Services) :-
  format(string(CommandA), 'dns-sd -t 1 -B _prolog._tcp | grep _prolog._tcp. | sed -e \'s/.*tcp.        //\'', []),
  process_create(path(bash), ['-c', CommandA], [stdout(pipe(StreamA))]),
  reader:read_lines_to_string(StreamA,Hosts),
  findall(Service,
   (member(Host,Hosts),
    format(string(CommandB), 'dns-sd -t 1 -L ~w _prolog._tcp . | grep \'reached at\' | sed -e \'s/.*reached at //\' | sed -e \'s/ (interface.*//\' | sed -e \'s/.:/:/\'', [Host]),
    process_create(path(bash), ['-c', CommandB], [stdout(pipe(StreamB))]),
    reader:read_lines_to_string(StreamB,Service)),
   UnsortedServices),
  flatten(UnsortedServices,FlatServices),
  sort(FlatServices,Services).

