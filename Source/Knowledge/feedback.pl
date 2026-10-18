/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> FEEDBACK
Builder-to-prover learned-knowledge channel (portage-ng#102/#105/#110).

When a build phase fails because a required provider (a command or file
some package would supply) is missing, the diagnosis is not repaired in
place: it is recorded here as a durable discovered dependency edge and
fed back into the resolver. On the next proof pass rules unions the
discovered provider into BDEPEND, so the provider is proved and ordered
before the target (plans are derived, never patched).

Records persisted (plain-text term files under Knowledge/, gitignored
like resume.pl / phase_stats.pl):

  - discovered_dep(Target, Provider, Kind, Evidence): a concrete provider
    that a build proved was needed but the metadata never declared. The
    structured Evidence doubles as an upstream ebuild bug report.
  - discovered_usedep(Target, Provider, UseDeps, Evidence): Target needs
    Provider with HARD bracketed USE deps (portage-ng#110). Unlike a bare
    discovered_dep, re-adding an already-installed provider without USE
    is a no-op; the usedeps force a rebuild with the missing flags.
  - excluded_version(C, N, Ver, Evidence): a Category/Name/Version that
    failed at configure against the live GHC boot library set
    (portage-ng#108). Selection excludes this exact version on the next
    prove so an alternate (e.g. text-2.1.1 over text-1.2.5.0) can win.
  - unresolved_diagnostic(Symbol, Evidence): a missing-provider signature
    that fired but could not be mapped to a concrete package. Kept as a
    maintainer backlog (extend the seed table / index); never guessed.
  - required_kernel_config(Target, Options, Evidence): a set of kernel
    CONFIG_* options a build's setup-phase CONFIG_CHECK required (learned
    by the kernelconfig exception mechanism, portage-ng#105). Surfaced as a
    plan pre-action ordered before the target and applied to the kernel
    source .config, so the CONFIG_CHECK passes on the re-derived plan.
*/

:- module(feedback, []).

% =============================================================================
%  FEEDBACK declarations
% =============================================================================

:- dynamic feedback:discovered_dep/4.
:- dynamic feedback:discovered_usedep/4.
:- dynamic feedback:excluded_version/4.
:- dynamic feedback:unresolved_diagnostic/2.
:- dynamic feedback:required_kernel_config/3.
:- dynamic feedback:session_discovery/4.
:- dynamic feedback:session_usedep/4.
:- dynamic feedback:session_excluded_version/4.
:- dynamic feedback:session_kernel_config/3.
:- dynamic feedback:loaded_/0.

% -----------------------------------------------------------------------------
%  State files
% -----------------------------------------------------------------------------

%! feedback:discovered_file(-Path) is det.
%
% Path to the persisted discovered-dependency file (Knowledge/feedback.pl).

feedback:discovered_file(Path) :-
  config:state_dir(Dir),
  os:compose_path([Dir, 'Knowledge', 'feedback.pl'], Path).


%! feedback:unresolved_file(-Path) is det.
%
% Path to the persisted unresolved-diagnostic backlog
% (Knowledge/feedback.unresolved.pl).

feedback:unresolved_file(Path) :-
  config:state_dir(Dir),
  os:compose_path([Dir, 'Knowledge', 'feedback.unresolved.pl'], Path).


% -----------------------------------------------------------------------------
%  Startup load
% -----------------------------------------------------------------------------

%! feedback:load is det.
%
% Consults the persisted discovery/backlog files into the dynamic store,
% at most once per session. Called from init_knowledgebase/0 after the
% host config is loaded so config:installation_dir/1 is available. Missing
% files are not an error (a fresh baseline has made no discoveries yet).

feedback:load :-
  ( feedback:loaded_
  -> true
  ;  assertz(feedback:loaded_),
     feedback:discovered_file(DPath),
     feedback:consult_terms(DPath),
     feedback:unresolved_file(UPath),
     feedback:consult_terms(UPath)
  ).


%! feedback:consult_terms(+Path) is det.
%
% Reads every term from Path and asserts it, skipping if the file does not
% exist. Errors are contained so a corrupt file can never abort startup.

feedback:consult_terms(Path) :-
  ( exists_file(Path)
  -> ( sanitize:ensure_file_integrity(Path)
     -> catch(
          setup_call_cleanup(
            open(Path, read, S),
            feedback:read_assert_terms(S),
            close(S)),
          _, true)
     ;  message:warning(['Skipping feedback file after integrity failure: ', Path])
     )
  ;  true
  ).


%! feedback:read_assert_terms(+Stream) is det.
%
% Reads terms until end_of_file, asserting only ground feedback facts of
% known functors (other terms are ignored defensively).

feedback:read_assert_terms(S) :-
  read_term(S, T, [syntax_errors(error)]),
  ( T == end_of_file
  -> true
  ;  ( feedback:safe_feedback_term(T) -> assertz(feedback:T) ; true ),
     feedback:read_assert_terms(S)
  ).


%! feedback:safe_feedback_term(+Term) is semidet.
%
% True when Term is a ground fact of an allowed feedback functor.

feedback:safe_feedback_term(discovered_dep(A, B, C, D)) :-
  ground(A), ground(B), ground(C), ground(D).

feedback:safe_feedback_term(discovered_usedep(A, B, C, D)) :-
  ground(A), ground(B), ground(C), ground(D).

feedback:safe_feedback_term(excluded_version(A, B, C, D)) :-
  ground(A), ground(B), ground(C), ground(D).

feedback:safe_feedback_term(unresolved_diagnostic(A, B)) :-
  ground(A), ground(B).

feedback:safe_feedback_term(required_kernel_config(A, B, C)) :-
  ground(A), ground(B), ground(C).


% -----------------------------------------------------------------------------
%  Recording discoveries
% -----------------------------------------------------------------------------

%! feedback:record_discovery(+Target, +Provider, +Kind, +Evidence) is det.
%
% Records a concrete discovered dependency: Target (Repo://Entry) needs
% Provider (a Category/Name atom) at Kind (bdepend), justified by the
% structured Evidence term. Deduplicated on (Target, Provider, Kind): a
% one-time runtime discovery becomes durable knowledge, appended to the
% persisted file so future runs plan it proactively.

feedback:record_discovery(Target, Provider, Kind, Evidence) :-
  ( feedback:discovered_dep(Target, Provider, Kind, _)
  -> true
  ;  assertz(feedback:discovered_dep(Target, Provider, Kind, Evidence)),
     feedback:discovered_file(Path),
     feedback:append_term(Path, discovered_dep(Target, Provider, Kind, Evidence))
  ),
  ( feedback:session_discovery(Target, Provider, Kind, _)
  -> true
  ;  assertz(feedback:session_discovery(Target, Provider, Kind, Evidence))
  ).


%! feedback:record_unresolved(+Symbol, +Evidence) is det.
%
% Records that a missing-provider signature (Symbol = symbol(Kind, Name))
% fired but could not be mapped to a concrete package. Deduplicated on
% Symbol. This is a maintainer backlog for extending the resolver seed
% table / index; it never affects proving (no discovery is minted).

feedback:record_unresolved(Symbol, Evidence) :-
  ( feedback:unresolved_diagnostic(Symbol, _)
  -> true
  ;  assertz(feedback:unresolved_diagnostic(Symbol, Evidence)),
     feedback:unresolved_file(Path),
     feedback:append_term(Path, unresolved_diagnostic(Symbol, Evidence))
  ).


%! feedback:record_excluded_version(+C, +N, +Ver, +Evidence) is det.
%
% Records that Category/Name at Ver failed against the live GHC boot
% library set (portage-ng#108) and must not be re-selected. Deduplicated
% on (C, N, Ver). Persisted so the next prove (and future runs) skip it.

feedback:record_excluded_version(C, N, Ver, Evidence) :-
  ( feedback:excluded_version(C, N, Ver, _)
  -> true
  ;  assertz(feedback:excluded_version(C, N, Ver, Evidence)),
     feedback:discovered_file(Path),
     feedback:append_term(Path, excluded_version(C, N, Ver, Evidence))
  ),
  ( feedback:session_excluded_version(C, N, Ver, _)
  -> true
  ;  assertz(feedback:session_excluded_version(C, N, Ver, Evidence))
  ).


%! feedback:version_excluded(+C, +N, +RepoEntry) is semidet.
%
% True when RepoEntry is an excluded version of (C, N).

feedback:version_excluded(C, N, Repo://Entry) :-
  cache:ordered_entry(Repo, Entry, C, N, Ver),
  feedback:excluded_version(C, N, Ver, _),
  !.


%! feedback:record_usedep(+Target, +Provider, +UseDeps, +Evidence) is det.
%
% Records that Target needs Provider with HARD UseDeps (a list of
% use(enable(Flag), none) terms). Deduplicated on (Target, Provider,
% UseDeps). Persisted alongside discovered_dep so future runs force the
% provider USE proactively (portage-ng#110).

feedback:record_usedep(Target, Provider, UseDeps, Evidence) :-
  ( feedback:discovered_usedep(Target, Provider, UseDeps, _)
  -> true
  ;  assertz(feedback:discovered_usedep(Target, Provider, UseDeps, Evidence)),
     feedback:discovered_file(Path),
     feedback:append_term(Path, discovered_usedep(Target, Provider, UseDeps, Evidence))
  ),
  ( feedback:session_usedep(Target, Provider, UseDeps, _)
  -> true
  ;  assertz(feedback:session_usedep(Target, Provider, UseDeps, Evidence))
  ).


%! feedback:record_kernel_config(+Target, +Options, +Evidence) is det.
%
% Records that Target (Repo://Entry) requires the kernel CONFIG_* Options
% (a list of config(Name, State) with State in {y, n}), as learned from a
% setup-phase CONFIG_CHECK failure (portage-ng#105). Deduplicated on
% Target: the first learned option set for a target is kept and appended to
% the persisted file so future runs plan the kernel-config change
% proactively. Also marked in the session store for this build's summary.

feedback:record_kernel_config(Target, Options, Evidence) :-
  ( feedback:required_kernel_config(Target, _, _)
  -> true
  ;  assertz(feedback:required_kernel_config(Target, Options, Evidence)),
     feedback:discovered_file(Path),
     feedback:append_term(Path, required_kernel_config(Target, Options, Evidence))
  ),
  ( feedback:session_kernel_config(Target, _, _)
  -> true
  ;  assertz(feedback:session_kernel_config(Target, Options, Evidence))
  ).


%! feedback:append_term(+Path, +Term) is det.
%
% Appends a single quoted, period-terminated term to Path. Errors are
% contained so a persistence failure never breaks the build.

feedback:append_term(Path, Term) :-
  catch(
    ( setup_call_cleanup(
        open(Path, append, S),
        ( write_term(S, Term, [quoted(true)]),
          format(S, '.~n', []) ),
        close(S)),
      sanitize:write_sha256_sidecar(Path)
    ),
    _, true).


% -----------------------------------------------------------------------------
%  Queries
% -----------------------------------------------------------------------------

%! feedback:discovery_count(-Count) is det.
%
% Number of distinct discovered dependencies currently known. Used by the
% builder's replan loop to detect whether a build pass grew the store.

feedback:discovery_count(Count) :-
  aggregate_all(count, feedback:discovered_dep(_, _, _, _), Count).


%! feedback:usedep_count(-Count) is det.
%
% Number of distinct discovered USE-dep edges (portage-ng#110).

feedback:usedep_count(Count) :-
  aggregate_all(count, feedback:discovered_usedep(_, _, _, _), Count).


%! feedback:excluded_version_count(-Count) is det.
%
% Number of distinct GHC-incompatible versions excluded (portage-ng#108).

feedback:excluded_version_count(Count) :-
  aggregate_all(count, feedback:excluded_version(_, _, _, _), Count).


%! feedback:kernel_config_count(-Count) is det.
%
% Number of distinct targets with a learned kernel-config requirement.

feedback:kernel_config_count(Count) :-
  aggregate_all(count, feedback:required_kernel_config(_, _, _), Count).


%! feedback:learned_count(-Count) is det.
%
% Total learned-knowledge count (discovered deps + usedeps + excluded
% versions + kernel-config requirements). The builder's replan loop uses
% this to detect whether a build pass grew any learned store, and
% re-derive the plan if so.

feedback:learned_count(Count) :-
  feedback:discovery_count(D),
  feedback:usedep_count(U),
  feedback:excluded_version_count(E),
  feedback:kernel_config_count(K),
  Count is D + U + E + K.


%! feedback:session_discoveries(-List) is det.
%
% Discoveries recorded in the current session, as
% discovery(Target, Provider, Kind, Evidence) terms. Used by the printer
% to draft bug reports only for dependencies worked around this run (not
% the entire persisted history).

feedback:session_discoveries(List) :-
  findall(discovery(T, P, K, E), feedback:session_discovery(T, P, K, E), List).


%! feedback:clear_session is det.
%
% Drops the current session's discovery marks. Called at the start of a
% build invocation so bug-report drafts are scoped to that build (and do
% not bleed across requests in a long-running daemon/server session). The
% durable discovered_dep/4 store is untouched.

feedback:clear_session :-
  retractall(feedback:session_discovery(_, _, _, _)),
  retractall(feedback:session_usedep(_, _, _, _)),
  retractall(feedback:session_excluded_version(_, _, _, _)),
  retractall(feedback:session_kernel_config(_, _, _)).


%! feedback:session_kernel_configs(-List) is det.
%
% Kernel-config requirements learned in the current session, as
% kernel_config(Target, Options, Evidence) terms. Used by the printer to
% report only the requirements worked around this run.

feedback:session_kernel_configs(List) :-
  findall(kernel_config(T, O, E), feedback:session_kernel_config(T, O, E), List).


%! feedback:plan_kernel_config_pre_actions(+Entries, -PreActions) is det.
%
% Given the tree entries in a derived plan (a list of Repo://Entry terms),
% yields one kernel_config(Options, Evidence) pre-action per learned
% kernel-config requirement whose target is in the plan. These are
% prepended to the plan's pre-actions so the kernel-config change is
% applied (and displayed) before the packages build.

feedback:plan_kernel_config_pre_actions(Entries, PreActions) :-
  findall(kernel_config(Options, Evidence),
          ( member(Target, Entries),
            feedback:required_kernel_config(Target, Options, Evidence) ),
          PreActions0),
  sort(PreActions0, PreActions).


%! feedback:discovered_bdepend_dep(+Repo, +Id, -Dep) is nondet.
%
% Yields, for the tree entry Repo://Id, each discovered build-dependency
% as a parsed package_dependency/8 term shaped exactly like an md5-cache
% BDEPEND atom, so query.pl can union it into the install dependency
% model. Surfaces bare discovered_dep (#102) and discovered_usedep (#110)
% edges (the latter with non-empty UseDeps so BWU forcing rebuilds the
% provider with the missing flags).

feedback:discovered_bdepend_dep(Repo, Id, Dep) :-
  feedback:discovered_dep(Repo://Id, Provider, bdepend, _Evidence),
  feedback:provider_dep(Provider, Dep).
feedback:discovered_bdepend_dep(Repo, Id, Dep) :-
  feedback:discovered_usedep(Repo://Id, Provider, UseDeps, _Evidence),
  feedback:provider_dep(Provider, UseDeps, Dep).


%! feedback:provider_dep(+Provider, -Dep) is semidet.
%
% Converts a Category/Name provider atom into an unversioned
% package_dependency/8 term matching the eapi grammar's parse of a bare
% `cat/name` BDEPEND atom (phase install, no blocker/operator/version/
% slot/use).

feedback:provider_dep(Provider, Dep) :-
  feedback:provider_dep(Provider, [], Dep).


%! feedback:provider_dep(+Provider, +UseDeps, -Dep) is semidet.
%
% Like provider_dep/2 but fills the USE-dep slot (portage-ng#110).

feedback:provider_dep(Provider, UseDeps, package_dependency(install, no, C, N, none, version_none, [], UseDeps)) :-
  atom(Provider),
  atomic_list_concat([C, N], '/', Provider),
  C \== '',
  N \== ''.
