/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2024, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


% ********************
% SANDBOX declarations
% ********************

sandbox:safe_primitive(cache:repository(_)).
sandbox:safe_primitive(cache:category(_,_)).
sandbox:safe_primitive(cache:entry(_,_,_,_,_)).
sandbox:safe_primitive(cache:package(_,_,_)).
sandbox:safe_primitive(cache:ordered_entry(_,_,_,_,_)).
sandbox:safe_primitive(cache:entry_metadata(_,_,_,_)).
sandbox:safe_primitive(cache:entry_metadata(_,_,_,_)).
sandbox:safe_primitive(cache:manifest(_,_,_,_,_)).
sandbox:safe_primitive(cache:manifest_metadata(_,_,_,_,_,_)).

sandbox:safe_primitive(query:execute(_)).

sandbox:safe_primitive(prover:prove_targets(_,_,_,_,_,_,_)).
sandbox:safe_primitive(prover:prove(_,_,_,_,_,_,_)).
sandbox:safe_primitive(prover:fact(_)).
sandbox:safe_primitive(prover:proven(_,_)).
sandbox:safe_primitive(prover:assumed_proven(_,_)).
sandbox:safe_primitive(prover:proving(_,_)).
sandbox:safe_primitive(prover:assumed_proving(_,_)).
sandbox:safe_primitive(prover:conflicts(_,_)).
sandbox:safe_primitive(prover:conflictrule(_,_)).
sandbox:safe_primitive(prover:is_constraint(_)).
sandbox:safe_primitive(prover:unify_constraints(_,_,_)).
sandbox:safe_primitive(prover:model(_,_)).

sandbox:safe_primitive(rules:rule(_,_)).

sandbox:safe_primitive(planner:zerorules(_,_,_,_,_)).
sandbox:safe_primitive(planner:is_zero(_,_)).
sandbox:safe_primitive(planner:plan(_,_,_,_)).

