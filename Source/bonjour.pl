/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2024, Pieter Van den Abeele

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
  config:name(Service),
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
  config:name(Service),
  discover(Service,Services).


%! discover(Service,Services)
%
% Discover services of a specified type

discover(Service,Services) :-
    format(string(Command), 'dns-sd -t 1 -L ~w _prolog._tcp . | grep \'reached at\' | sed -e \'s/.*reached at //\' | sed -e \'s/ (interface.*//\' | sed -e \'s/.:/:/\'', [Service]),
    process_create(path(bash), ['-c', Command], [stdout(pipe(Stream))]),
    reader:read_lines_to_string(Stream,ServicesWithDuplicates),
    sort(ServicesWithDuplicates,Services).
