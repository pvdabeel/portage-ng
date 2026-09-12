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
sandbox:safe_primitive(config:graph_directory(_)).
sandbox:safe_primitive(config:graph_modified_only(_)).
sandbox:safe_primitive(config:graph_include_emerge(_)).
sandbox:safe_primitive(config:emerge_vp_path(_)).
sandbox:safe_primitive(config:emerge_vp_timeout(_)).
sandbox:safe_primitive(config:emerge_vp_concurrency(_)).
sandbox:safe_primitive(config:force_emerge_regen(_)).
sandbox:safe_primitive(config:print_prover_cycles(_)).
sandbox:safe_primitive(config:print_prover_cycles_max_total(_)).
sandbox:safe_primitive(config:print_prover_cycles_max_depth(_)).
sandbox:safe_primitive(config:print_prover_cycles_max_inferences(_)).
sandbox:safe_primitive(config:print_blockers(_)).
sandbox:safe_primitive(config:bugreport_drafts_enabled(_)).
sandbox:safe_primitive(config:bugreport_drafts_max_assumptions(_)).
sandbox:safe_primitive(config:llm_default(_)).
sandbox:safe_primitive(config:llm_support(_)).
sandbox:safe_primitive(config:load_llm_modules(_)).
sandbox:safe_primitive(config:llm_metacircular(_)).
sandbox:safe_primitive(config:llm_metacircular_log_tail(_)).
sandbox:safe_primitive(config:llm_metacircular_max_actions(_)).
sandbox:safe_primitive(config:llm_server_calls(_)).
sandbox:safe_primitive(config:hostname(_)).
sandbox:safe_primitive(config:installation_dir(_)).
sandbox:safe_primitive(config:name(_)).
sandbox:safe_primitive(config:number_of_cpus(_)).
sandbox:safe_primitive(config:pkg_directory(_)).
sandbox:safe_primitive(config:printing_style(_)).
sandbox:safe_primitive(config:printing_tty_size(_,_)).
sandbox:safe_primitive(config:powerline_bubbles).
sandbox:safe_primitive(config:proving_target(_)).
sandbox:safe_primitive(config:reprove_max_retries(_)).
sandbox:safe_primitive(config:server_port(_)).
sandbox:safe_primitive(config:server_bind(_)).
sandbox:safe_primitive(config:shared_dep_use_forcing(_)).
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
%  Knowledgebase (VDB repository selection)
% -----------------------------------------------------------------------------

% vdb_repository/1 only reads/writes a per-thread global variable
% (kb_vdb_repository) memoizing the active VDB repository resolution, and
% consults the client-shipped vdb_repository/vdb_import_stamp facts in the
% Pengines sandbox module.
sandbox:safe_primitive(knowledgebase:vdb_repository(_)).
sandbox:safe_primitive(knowledgebase:is_vdb_repository(_)).

% -----------------------------------------------------------------------------
%  Query
% -----------------------------------------------------------------------------

sandbox:safe_primitive(query:search(_,_)).
sandbox:safe_primitive(query:repo_not_vdb(_)).
sandbox:safe_primitive(query:apply_filters(_,_)).
sandbox:safe_primitive(query:apply_filter(_,_)).
sandbox:safe_primitive(query:with_required_use_validate(_,_,_)).
sandbox:safe_primitive(query:strip_validate_annotation(_,_)).

% -----------------------------------------------------------------------------
%  Explainer & Explanation
% -----------------------------------------------------------------------------

sandbox:safe_primitive(explanation:assumption_reason_for_grouped_dep(_,_,_,_,_,_)).

sandbox:safe_primitive(explainer:explain(_,_)).
sandbox:safe_primitive(explainer:explain(_,_,_)).
% explainer:call_llm/3 is opt-in via config:llm_server_calls(true).
% Default false keeps server API keys / prompts off the Pengines path;
% LLM then runs host-locally (standalone / client). Enable only on a
% trusted cluster that intentionally shares the server's api_key.pl.
sandbox:safe_primitive(explainer:call_llm(_,_,_)) :-
  config:llm_server_calls(true).
sandbox:safe_primitive(explainer:why_in_proof(_,_,_)).

sandbox:safe_primitive(explainer:why_in_proof(_,_,_,_)).
sandbox:safe_primitive(explainer:why_in_plan(_,_,_,_,_)).
sandbox:safe_primitive(explainer:why_in_plan(_,_,_,_,_,_)).
sandbox:safe_primitive(explainer:why_assumption(_,_,_,_)).
sandbox:safe_primitive(explainer:why_assumption(_,_,_,_,_)).
sandbox:safe_primitive(explainer:term_ctx(_,_)).

% -----------------------------------------------------------------------------
%  Feedback / missing-provider introspection (read-only; no record_*)
% -----------------------------------------------------------------------------

sandbox:safe_primitive(feedback:discovered_dep(_,_,_,_)).
sandbox:safe_primitive(feedback:discovered_usedep(_,_,_,_)).
sandbox:safe_primitive(feedback:excluded_version(_,_,_,_)).
sandbox:safe_primitive(feedback:unresolved_diagnostic(_,_)).
sandbox:safe_primitive(feedback:required_kernel_config(_,_,_)).
sandbox:safe_primitive(feedback:learned_count(_)).
sandbox:safe_primitive(feedback:discovery_count(_)).
sandbox:safe_primitive(feedback:version_excluded(_,_,_)).
sandbox:safe_primitive(feedback:discovered_bdepend_dep(_,_,_)).

sandbox:safe_primitive(missing_provider:package_in_tree(_)).
sandbox:safe_primitive(missing_provider:provider_of(_,_,_,_)).

sandbox:safe_primitive(metacircular:provider_in_tree(_)).
sandbox:safe_primitive(metacircular:parse_proposal(_,_)).
sandbox:safe_primitive(metacircular:valid_action(_)).

% -----------------------------------------------------------------------------
%  LLM knowledge pack (read-only Handbook / Source excerpts)
% -----------------------------------------------------------------------------

sandbox:safe_primitive(llmknowledge:topics(_)).
sandbox:safe_primitive(llmknowledge:topic(_,_)).
sandbox:safe_primitive(llmknowledge:print_topic(_)).
sandbox:safe_primitive(llmknowledge:list_topics).
sandbox:safe_primitive(llmknowledge:handbook(_,_)).
sandbox:safe_primitive(llmknowledge:print_handbook(_)).
sandbox:safe_primitive(llmknowledge:handbook_catalogue(_)).
sandbox:safe_primitive(llmknowledge:source(_,_,_,_)).
sandbox:safe_primitive(llmknowledge:print_source(_,_,_)).
sandbox:safe_primitive(config:llm_knowledge_max_bytes(_)).
sandbox:safe_primitive(config:llm_knowledge_max_source_lines(_)).

% -----------------------------------------------------------------------------
%  Prover (generic engine) + Resolver (pass-1 stage)
% -----------------------------------------------------------------------------

sandbox:safe_primitive(prover:prove(_,_,_,_,_,_,_,_,_,_)).
sandbox:safe_primitive(prover:prove_once(_,_,_,_,_,_,_,_,_,_)).
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
% prover:learn/3 is intentionally NOT safelisted: Pengines clients must
% not poison the server's learned-constraint store. Learning still runs
% inside server-side prove (safe_primitive prove body is not re-sandboxed).
sandbox:safe_primitive(resolver:resolve(_,_,_,_,_,_,_,_,_)).
sandbox:safe_primitive(resolver:test(_)).
sandbox:safe_primitive(resolver:test(_,_)).
sandbox:safe_primitive(resolver:test_latest(_)).
sandbox:safe_primitive(resolver:test_latest(_,_)).
sandbox:safe_primitive(resolver:test_stats(_)).
sandbox:safe_primitive(resolver:test_stats(_,_)).
sandbox:safe_primitive(resolver:test_stats(_,_,_)).
sandbox:safe_primitive(resolver:test_stats_pkgs(_,_)).
sandbox:safe_primitive(resolver:test_stats_pkgs(_,_,_,_)).

sandbox:safe_primitive(plancompare:run(_,_)).
sandbox:safe_primitive(plancompare:diff(_,_)).

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

sandbox:safe_primitive(choicelog:arm).
sandbox:safe_primitive(choicelog:disarm).
sandbox:safe_primitive(choicelog:armed).
sandbox:safe_primitive(choicelog:reset).
sandbox:safe_primitive(choicelog:emit(_,_,_)).
sandbox:safe_primitive(choicelog:clog_emit(_,_,_)).
sandbox:safe_primitive(choicelog:events(_)).
sandbox:safe_primitive(choicelog:dump).
sandbox:safe_primitive(choicelog:maybe_dump).
sandbox:safe_primitive(choicelog:with_logging(_)).

% -----------------------------------------------------------------------------
%  Rule sets
% -----------------------------------------------------------------------------

sandbox:safe_primitive(resolving:rule(_,_)).
sandbox:safe_primitive(ordering:rule(_,_)).
sandbox:safe_primitive(unmerging:rule(_,_)).

% -----------------------------------------------------------------------------
%  Orderer
% -----------------------------------------------------------------------------

sandbox:safe_primitive(orderer:order(_,_,_,_)).
sandbox:safe_primitive(orderer:test(_)).
sandbox:safe_primitive(orderer:test(_,_)).
sandbox:safe_primitive(orderer:test_latest(_)).
sandbox:safe_primitive(orderer:test_latest(_,_)).
sandbox:safe_primitive(orderer:test_stats(_)).
sandbox:safe_primitive(orderer:test_stats(_,_)).

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

% pengine_module/1 only reads/writes a per-thread global variable
% (pref_pengine_module) memoizing the pengine_self/1 dispatch result.
sandbox:safe_primitive(preference:pengine_module(_)).
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
%  GLSA knowledge store
% -----------------------------------------------------------------------------

sandbox:safe_primitive(glsa:cache_available).
sandbox:safe_primitive(glsa:search(_,_)).
sandbox:safe_primitive(glsa:advisory(_,_)).
sandbox:safe_primitive(glsa:is_vulnerable(_)).
sandbox:safe_primitive(glsa:security_atoms(_,_)).
sandbox:safe_primitive(glsa:entry_covered(_,_)).
sandbox:safe_primitive(glsa:entry_status(_,_,_)).
sandbox:safe_primitive(glsa:package_advisories(_,_,_)).
sandbox:safe_primitive(glsa:ensure_loaded).
sandbox:safe_primitive(sets:expand(_,_)).
sandbox:safe_primitive(sets:is_computed_set(_)).
sandbox:safe_primitive(sets:entry_deps_outdated(_)).
sandbox:safe_primitive(config:preserved_libs_registry(_)).

% -----------------------------------------------------------------------------
%  Server job queue (worker RPC protocol)
% -----------------------------------------------------------------------------

sandbox:safe_primitive(server:get_job(_,_,_)).
sandbox:safe_primitive(server:post_result(_,_)).
sandbox:safe_primitive(server:register_worker(_,_,_)).
sandbox:safe_primitive(server:snapshot(_,_)).

% -----------------------------------------------------------------------------
%  Streams
% -----------------------------------------------------------------------------

sandbox:safe_meta(streams:with_output_to(_,_,_),_).