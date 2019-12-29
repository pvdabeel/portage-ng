/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2020, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> INSTANCES
This file declares a predicate to list all instances for a given class.
*/

:- module(instances, ['instances'/2]).

% **********************
% INSTANCES declarations
% **********************


%! instances(+Class,?Instance)
%
% For a given class, retrieves its instances

instances(Class,Instance) :-
  current_module(Instance),
  clause(Instance:'$__meta'(type(instance(Class))),true).
