/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> SANDBOX
This module contains the predicates used for sandboxing the client - server
architecture
*/

% =============================================================================
%  SANDBOX declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Config
% -----------------------------------------------------------------------------

sandbox:safe_primitive(config:certificate(_,_)).
sandbox:safe_primitive(config:certificate(_,_,_)).
sandbox:safe_primitive(config:build_live_phases(_)).
sandbox:safe_primitive(config:dry_run_build(_)).
sandbox:safe_primitive(config:failsilenton(_)).
sandbox:safe_primitive(config:graph_directory(_,_)).
sandbox:safe_primitive(config:graph_modified_only(_)).
sandbox:safe_primitive(config:print_prover_cycles(_)).
sandbox:safe_primitive(config:print_prover_cycles_max_total(_)).
sandbox:safe_primitive(config:print_prover_cycles_max_depth(_)).
sandbox:safe_primitive(config:print_scc(_)).
sandbox:safe_primitive(config:print_scc_max_members(_)).
sandbox:safe_primitive(config:print_blockers(_)).
sandbox:safe_primitive(config:bugreport_drafts_enabled(_)).
sandbox:safe_primitive(config:bugreport_drafts_max_assumptions(_)).
sandbox:safe_primitive(config:llm_default(_)).
sandbox:safe_primitive(config:llm_support(_)).
sandbox:safe_primitive(config:hostname(_)).
sandbox:safe_primitive(config:installation_dir(_)).
sandbox:safe_primitive(config:name(_)).
sandbox:safe_primitive(config:number_of_cpus(_)).
sandbox:safe_primitive(config:pkg_directory(_,_)).
sandbox:safe_primitive(config:printing_style(_)).
sandbox:safe_primitive(config:printing_tty_size(_,_)).
sandbox:safe_primitive(config:proving_target(_)).
sandbox:safe_primitive(config:reprove_max_retries(_)).
sandbox:safe_primitive(config:server_port(_)).
sandbox:safe_primitive(config:server_host(_)).
sandbox:safe_primitive(config:systemconfig(_)).
sandbox:safe_primitive(config:test_style(_)).
sandbox:safe_primitive(config:time_limit(_)).
sandbox:safe_primitive(config:time_limit_build(_)).
sandbox:safe_primitive(config:verbosity(_)).
sandbox:safe_primitive(config:working_dir(_)).
sandbox:safe_primitive(config:daemon_socket_path(_)).
sandbox:safe_primitive(config:daemon_pid_path(_)).
sandbox:safe_primitive(config:daemon_inactivity_timeout(_)).
sandbox:safe_primitive(config:daemon_autostart(_)).

% -----------------------------------------------------------------------------
%  Cache
% -----------------------------------------------------------------------------

sandbox:safe_primitive(cache:repository(_)).
sandbox:safe_primitive(cache:category(_,_)).
sandbox:safe_primitive(cache:entry(_,_,_,_,_)).
sandbox:safe_primitive(cache:package(_,_,_)).
sandbox:safe_primitive(cache:ordered_entry(_,_,_,_,_)).
sandbox:safe_primitive(cache:entry_metadata(_,_,_,_)).
sandbox:safe_primitive(cache:manifest(_,_,_,_,_)).
sandbox:safe_primitive(cache:manifest_metadata(_,_,_,_,_,_)).

% -----------------------------------------------------------------------------
%  Query
% -----------------------------------------------------------------------------

sandbox:safe_primitive(query:search(_,_)).
sandbox:safe_primitive(query:apply_filters(_,_)).
sandbox:safe_primitive(query:apply_filter(_,_)).
sandbox:safe_primitive(query:pdepend_dep_as_pdepend(_,_)).
sandbox:safe_primitive(query:with_required_use_validate(_,_,_)).
sandbox:safe_primitive(query:strip_validate_annotation(_,_)).

% -----------------------------------------------------------------------------
%  Explainer & Explanation
% -----------------------------------------------------------------------------

sandbox:safe_primitive(explanation:assumption_reason_for_grouped_dep(_,_,_,_,_,_)).

sandbox:safe_primitive(explainer:explain(_,_)).
sandbox:safe_primitive(explainer:explain(_,_,_)).
sandbox:safe_primitive(explainer:call_llm(_,_,_)).
sandbox:safe_primitive(explainer:why_in_proof(_,_,_)).
sandbox:safe_primitive(explainer:why_in_proof(_,_,_,_)).
sandbox:safe_primitive(explainer:why_in_plan(_,_,_,_,_)).
sandbox:safe_primitive(explainer:why_in_plan(_,_,_,_,_,_)).
sandbox:safe_primitive(explainer:why_assumption(_,_,_,_)).
sandbox:safe_primitive(explainer:why_assumption(_,_,_,_,_)).
sandbox:safe_primitive(explainer:term_ctx(_,_)).

% -----------------------------------------------------------------------------
%  Prover
% -----------------------------------------------------------------------------

sandbox:safe_primitive(prover:prove(_,_,_,_,_,_,_,_,_)).
sandbox:safe_primitive(prover:prove_model(_,_,_,_,_)).
sandbox:safe_primitive(prover:proven(_,_,_)).
sandbox:safe_primitive(prover:assumed_proven(_,_)).
sandbox:safe_primitive(prover:proving(_,_)).
sandbox:safe_primitive(prover:assumed_proving(_,_)).
sandbox:safe_primitive(prover:conflicts(_,_)).
sandbox:safe_primitive(prover:conflictrule(_,_)).
sandbox:safe_primitive(prover:assuming(_)).
sandbox:safe_primitive(prover:assuming(_,_)).
sandbox:safe_primitive(prover:learned(_,_)).
sandbox:safe_primitive(prover:learn(_,_,_)).
sandbox:safe_primitive(prover:test(_)).
sandbox:safe_primitive(prover:test(_,_)).
sandbox:safe_primitive(prover:test_latest(_)).
sandbox:safe_primitive(prover:test_latest(_,_)).
sandbox:safe_primitive(prover:test_stats(_)).
sandbox:safe_primitive(prover:test_stats(_,_)).
sandbox:safe_primitive(prover:test_stats(_,_,_)).
sandbox:safe_primitive(prover:test_stats_pkgs(_,_)).
sandbox:safe_primitive(prover:test_stats_pkgs(_,_,_,_)).

sandbox:safe_primitive(builder:test_stats(_)).
sandbox:safe_primitive(builder:test_stats(_,_)).
sandbox:safe_primitive(builder:test_stats(_,_,_)).
sandbox:safe_primitive(builder:test_stats_pkgs(_,_)).
sandbox:safe_primitive(builder:test_stats_pkgs(_,_,_,_)).
sandbox:safe_primitive(builder:test_single(_,_)).

sandbox:safe_primitive(constraint:is_constraint(_)).
sandbox:safe_primitive(constraint:unify_constraints(_,_,_)).

% -----------------------------------------------------------------------------
%  Sampler
% -----------------------------------------------------------------------------

sandbox:safe_primitive(sampler:fact(_)).
sandbox:safe_primitive(sampler:value(_,_)).
sandbox:safe_primitive(sampler:percent(_,_,_)).
sandbox:safe_primitive(sampler:stage_at_least(_)).
sandbox:safe_primitive(sampler:pkg_count(_,_)).
sandbox:safe_primitive(sampler:counters(_)).
sandbox:safe_primitive(sampler:ctx_counters(_,_,_,_)).
sandbox:safe_primitive(sampler:ctx_distribution(_,_,_,_)).
sandbox:safe_primitive(sampler:report_callsites(_)).
sandbox:safe_primitive(sampler:report_callsites_sig(_)).

% -----------------------------------------------------------------------------
%  Rules
% -----------------------------------------------------------------------------

sandbox:safe_primitive(rules:rule(_,_)).

% -----------------------------------------------------------------------------
%  Planner & Scheduler
% -----------------------------------------------------------------------------

sandbox:safe_primitive(planner:plan(_,_,_,_)).
sandbox:safe_primitive(planner:plan(_,_,_,_,_)).
sandbox:safe_primitive(planner:test(_)).
sandbox:safe_primitive(planner:test(_,_)).
sandbox:safe_primitive(planner:test_latest(_)).
sandbox:safe_primitive(planner:test_latest(_,_)).
sandbox:safe_primitive(planner:test_stats(_)).
sandbox:safe_primitive(planner:test_stats(_,_)).

sandbox:safe_primitive(scheduler:schedule(_,_,_,_,_,_)).
sandbox:safe_primitive(scheduler:test(_)).
sandbox:safe_primitive(scheduler:test(_,_)).
sandbox:safe_primitive(scheduler:test_latest(_)).
sandbox:safe_primitive(scheduler:test_latest(_,_)).
sandbox:safe_primitive(scheduler:test_stats(_)).
sandbox:safe_primitive(scheduler:test_stats(_,_)).

% -----------------------------------------------------------------------------
%  Pipeline
% -----------------------------------------------------------------------------

sandbox:safe_primitive(pipeline:test(_)).
sandbox:safe_primitive(pipeline:test_stats(_)).
sandbox:safe_primitive(pipeline:test_stats(_,_)).
sandbox:safe_primitive(pipeline:prove_plan(_,_,_,_,_)).
sandbox:safe_primitive(pipeline:prove_with_fallback(_,_,_,_)).
sandbox:safe_primitive(pipeline:prove_plan_with_fallback(_,_,_,_,_)).
sandbox:safe_primitive(pipeline:prove_plan_with_fallback(_,_,_,_,_,_)).

% -----------------------------------------------------------------------------
%  Message
% -----------------------------------------------------------------------------

sandbox:safe_primitive(message:title(_)).
sandbox:safe_primitive(message:title_reset).

sandbox:safe_primitive(message:color(_)).
sandbox:safe_primitive(message:bgcolor(_)).
sandbox:safe_primitive(message:el).
sandbox:safe_primitive(message:hc).
sandbox:safe_primitive(message:sc).
sandbox:safe_primitive(message:hl).
sandbox:safe_primitive(message:hl(_)).
sandbox:safe_primitive(message:style(_)).
sandbox:safe_primitive(message:eend(_)).
sandbox:safe_primitive(message:column(_,_)).
sandbox:safe_primitive(message:bubble(_,_)).
sandbox:safe_primitive(message:print(_)).
sandbox:safe_primitive(message:msg(_,_)).
sandbox:safe_primitive(message:msg(_,_,_)).
sandbox:safe_primitive(message:scroll(_)).
sandbox:safe_primitive(message:scroll_msg(_,_)).
sandbox:safe_primitive(message:notice(_)).
sandbox:safe_primitive(message:datetime(_)).
sandbox:safe_primitive(message:failure(_)).
sandbox:safe_primitive(message:warning(_)).
sandbox:safe_primitive(message:success(_)).
sandbox:safe_primitive(message:inform(_)).
sandbox:safe_primitive(message:topheader(_)).
sandbox:safe_primitive(message:header(_)).
sandbox:safe_primitive(message:convert_bytes(_,_)).
sandbox:safe_primitive(message:print_bytes(_)).

% -----------------------------------------------------------------------------
%  Preference
% -----------------------------------------------------------------------------

sandbox:safe_primitive(preference:global_use(_)).
sandbox:safe_primitive(preference:accept_keywords(_)).
sandbox:safe_primitive(preference:package_keyword_accepted(_,_,_)).
sandbox:safe_primitive(preference:masked(_)).
sandbox:safe_primitive(preference:flag(_)).
sandbox:safe_primitive(preference:set(_,_)).
sandbox:safe_primitive(preference:world_entry(_)).

% -----------------------------------------------------------------------------
%  Portage configuration
% -----------------------------------------------------------------------------

sandbox:safe_primitive(userconfig:env(_,_)).
sandbox:safe_primitive(userconfig:package_keyword(_,_)).
sandbox:safe_primitive(userconfig:package_license_entry(_,_)).

% -----------------------------------------------------------------------------
%  Profile cache
% -----------------------------------------------------------------------------

sandbox:safe_primitive(profile:cache_available).

% -----------------------------------------------------------------------------
%  Streams
% -----------------------------------------------------------------------------

sandbox:safe_meta(streams:with_output_to(_,_,_),_).