/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2025, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


% ********************
% SANDBOX declarations
% ********************

sandbox:safe_primitive(config:certificate(_,_)).
sandbox:safe_primitive(config:certificate(_,_,_)).
sandbox:safe_primitive(config:dry_run_build(_)).
sandbox:safe_primitive(config:failsilenton(_)).
sandbox:safe_primitive(config:graph_directory(_,_)).
sandbox:safe_primitive(config:graph_modified_only(_)).
sandbox:safe_primitive(config:hostname(_)).
sandbox:safe_primitive(config:installation_dir(_)).
sandbox:safe_primitive(config:name(_)).
sandbox:safe_primitive(config:number_of_cpus(_)).
sandbox:safe_primitive(config:pkg_directory(_,_)).
sandbox:safe_primitive(config:proving_target(_)).
sandbox:safe_primitive(config:server_port(_)).
sandbox:safe_primitive(config:server_host(_)).
sandbox:safe_primitive(config:systemconfig(_)).
sandbox:safe_primitive(config:test_style(_)).
sandbox:safe_primitive(config:time_limit(_)).
sandbox:safe_primitive(config:time_limit_build(_)).
sandbox:safe_primitive(config:verbosity(_)).
sandbox:safe_primitive(config:working_dir(_)).

sandbox:safe_primitive(cache:repository(_)).
sandbox:safe_primitive(cache:category(_,_)).
sandbox:safe_primitive(cache:entry(_,_,_,_,_)).
sandbox:safe_primitive(cache:package(_,_,_)).
sandbox:safe_primitive(cache:ordered_entry(_,_,_,_,_)).
sandbox:safe_primitive(cache:entry_metadata(_,_,_,_)).
sandbox:safe_primitive(cache:entry_metadata(_,_,_,_)).
sandbox:safe_primitive(cache:manifest(_,_,_,_,_)).
sandbox:safe_primitive(cache:manifest_metadata(_,_,_,_,_,_)).

sandbox:safe_primitive(query:search(_,_)).
sandbox:safe_primitive(query:apply_version_filter(_,_,_)).
sandbox:safe_primitive(query:apply_filters(_,_)).
sandbox:safe_primitive(query:apply_filter(_,_)).

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

sandbox:safe_primitive(message:title(_)).
sandbox:safe_primitive(message:title_reset).

sandbox:safe_primitive(message:color(_)).
sandbox:safe_primitive(message:el).
sandbox:safe_primitive(message:hc).
sandbox:safe_primitive(message:sc).
sandbox:safe_primitive(message:style(_)).
sandbox:safe_primitive(message:eend(_)).
sandbox:safe_primitive(message:column(_,_)).
sandbox:safe_primitive(message:print(_)).
sandbox:safe_primitive(message:failure(_)).
sandbox:safe_primitive(message:warning(_)).
sandbox:safe_primitive(message:success(_)).
sandbox:safe_primitive(message:inform(_)).
sandbox:safe_primitive(message:scroll(_)).
sandbox:safe_primitive(message:topheader(_)).
sandbox:safe_primitive(message:header(_)).
sandbox:safe_primitive(message:convert_bytes(_,_)).
sandbox:safe_primitive(message:print_bytes(_)).
sandbox:safe_primitive(message:prefix(_)).
sandbox:safe_primitive(message:wrap(_)).

sandbox:safe_primitive(preference:use(_)).
sandbox:safe_primitive(preference:accept_keywords(_)).

sandbox:safe_meta(streams:with_output_to(_,_,_),_).
