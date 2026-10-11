/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> BUILDER
Build execution orchestrator.

Takes the same pipeline output as printer (Plan, Proof, Model, Triggers)
and executes each step in parallel via the jobserver. Downloads use
parallel curl with per-file progress; other build phases dispatch to
ebuild_exec (Portage's ebuild CLI) when config:build_live_phases is
non-empty, or return stub when fully stubbed.

The full plan is printed first (normal colors, via printer:print/5), then
a progress area below shows slot-based live updates as workers execute
jobs. Within each plan step, all executable rules run in parallel; steps
are sequential (the next step starts only after the previous completes).

Both entry points (build/1 for a fresh build, build_resume/0 for
continuing an interrupted one) share the run_plan/6 lifecycle. The
supporting concerns are split into sibling modules:

  - Builder/display.pl : slot layout math + slot-info registry
  - Builder/fetch.pl   : download orchestration (curl/git/RESTRICT=fetch)
  - Builder/resume.pl  : resume-state persistence + done marks
*/

:- module(builder, []).

% =============================================================================
%  BUILDER declarations
% =============================================================================

:- dynamic builder:slot_outcome/2.
:- dynamic builder:exec_phase_state/3.
:- dynamic builder:last_build_status/3.
:- dynamic builder:last_failed/3.

% -----------------------------------------------------------------------------
%  Entry points
% -----------------------------------------------------------------------------

%! builder:build(+Goals) is det.
%
% Top-level entry point. Delegates to the bounded replan loop
% (build_loop/2): each pass proves goals, prints the plan, and runs it;
% if the pass fails AND recorded new missing-provider discoveries
% (portage-ng#102), the plan is re-derived with the discovered providers
% unioned into BDEPEND and re-run, so the provider is proved and ordered
% before the target. Plans are derived, never patched.

builder:build(Goals) :-
  feedback:clear_session,
  builder:build_loop(Goals, 0).


%! builder:build_loop(+Goals, +Attempt) is det.
%
% One prove/print/confirm/run pass. Confirmation is asked only on the
% first attempt; a replan re-runs non-interactively. On a failed pass
% that grew the discovery store (builder:should_replan/4), re-enters with
% Attempt+1, bounded by config:missing_provider_max_replan/1. When the
% pass failed without new deterministic discoveries, optionally invokes
% metacircular LLM diagnose (human-confirmed feedback) and replans if
% the learned store grew.

builder:build_loop(Goals, Attempt) :-
  pipeline:prove_plan_with_fallback(Goals, ProofAVL, ModelAVL, Plan, TriggersAVL, FallbackUsed),
  printer:print(Goals, ModelAVL, ProofAVL, Plan, TriggersAVL),
  nl,
  ( Attempt =:= 0
  -> ( builder:ask_confirmation
     -> true
     ;  message:inform('Aborted.'),
        !,
        fail
     )
  ;  true
  ),
  builder:maybe_create_snapshot(Plan),
  resume:save_state(Goals, Plan),
  annotation:collect(ProofAVL, Annotations),
  annotation:pre_actions(Annotations, AnnPreActions),
  builder:plan_entries(Plan, PlanEntries),
  feedback:plan_kernel_config_pre_actions(PlanEntries, KcPreActions),
  append(KcPreActions, AnnPreActions, PreActions),
  length(PreActions, PreCount),
  ( PreCount > 0 -> PreSteps = 1 ; PreSteps = 0 ),
  StartStep is PreSteps + 1,
  feedback:learned_count(Before),
  builder:run_plan(Plan, StartStep, [pre_actions(PreActions)],
                   _Completed, Failed, _Stubs),
  feedback:learned_count(After),
  ( builder:should_replan(Attempt, Failed, Before, After)
  -> Next is Attempt + 1,
     builder:announce_replan(Next),
     builder:build_loop(Goals, Next)
  ;  builder:maybe_metacircular_replan(Goals, ProofAVL, ModelAVL, Plan, TriggersAVL,
                                       FallbackUsed, Attempt, Failed, Before)
  -> Next is Attempt + 1,
     builder:announce_replan(Next),
     builder:build_loop(Goals, Next)
  ;  true
  ).


%! builder:maybe_metacircular_replan(+Goals, +ProofAVL, +ModelAVL, +Plan, +TriggersAVL, +FallbackUsed, +Attempt, +Failed, +Before) is semidet.
%
% Succeeds when a failed pass had no deterministic discovery growth, the
% metacircular module is available and interactive, the user confirmed
% at least one feedback action, and the replan budget is not exhausted.

builder:maybe_metacircular_replan(Goals, ProofAVL, ModelAVL, Plan, TriggersAVL,
                                  FallbackUsed, Attempt, Failed, Before) :-
  Failed > 0,
  catch(config:load_llm_modules(true), _, fail),
  catch(config:llm_metacircular(true), _, fail),
  config:llm_default(Service),
  current_predicate(Service:Service/2),
  predicate_property(metacircular:diagnose_after_build(_,_,_,_,_,_,_), defined),
  ( catch(config:missing_provider_max_replan(Max), _, fail), integer(Max)
  -> true
  ;  Max = 3
  ),
  Attempt < Max,
  catch(metacircular:diagnose_after_build(Goals, ProofAVL, ModelAVL, Plan, TriggersAVL,
                                          FallbackUsed, Applied),
        _, Applied = 0),
  Applied > 0,
  feedback:learned_count(After),
  After > Before.


%! builder:should_replan(+Attempt, +Failed, +Before, +After) is semidet.
%
% True when the just-finished pass failed, grew the learned-knowledge
% store (a new missing-provider discovery, portage-ng#102, or a new
% kernel-config requirement, portage-ng#105), and the replan budget is not
% exhausted. Both stores deduplicate on record, so After only grows on
% genuinely new knowledge and the loop terminates.

builder:should_replan(Attempt, Failed, Before, After) :-
  Failed > 0,
  After > Before,
  ( catch(config:missing_provider_max_replan(Max), _, fail), integer(Max)
  -> true
  ;  Max = 3
  ),
  Attempt < Max.


%! builder:announce_replan(+Attempt) is det.
%
% Prints a banner before re-deriving the plan on a new discovery.

builder:announce_replan(Attempt) :-
  nl,
  message:color(green),
  format('>>> Re-deriving plan after build-time discovery (replan attempt ~d, portage-ng#102/#105/#110)~n', [Attempt]),
  message:color(normal),
  nl.


%! builder:build_resume is det.
%
% Resumes a previously interrupted build. Loads the saved plan from
% Knowledge/resume.pl, filters out completed packages, and re-executes
% the remainder via the shared run_plan/6 lifecycle. Skips the clean
% phase so ebuild can pick up from the preserved work directory.

builder:build_resume :-
  ( resume:load_state(_Goals, Plan, DoneList)
  -> true
  ;  message:failure('No saved build state found. Run --build first.'),
     !,
     fail
  ),
  resume:collect_skip_entries(Plan, SkipDone),
  append(DoneList, SkipDone, AllDone),
  resume:filter_completed_plan(Plan, AllDone, FilteredPlan),
  builder:count_actions(FilteredPlan, 0, RemainingActions),
  ( RemainingActions =:= 0
  -> message:inform('Nothing to resume — all packages completed successfully.'),
     resume:clear_state
  ;  length(DoneList, CompletedCount),
     format(atom(ResumeMsg), '>>> Resuming: ~d completed, ~d remaining', [CompletedCount, RemainingActions]),
     message:color(green),
     message:print(ResumeMsg),
     message:reset,
     nl, nl,
     setup_call_cleanup(
       assertz(ebuild_exec:resuming),
       builder:run_plan(FilteredPlan, 1, [], _Completed, _Failed, _Stubs),
       retractall(ebuild_exec:resuming))
  ).


% -----------------------------------------------------------------------------
%  Shared plan lifecycle
% -----------------------------------------------------------------------------

%! builder:run_plan(+Plan, +StartStep, +Opts, -Completed, -Failed, -Stubs) is det.
%
% Shared build lifecycle used by both build/1 and build_resume/0:
% binpkg index refresh, header, jobserver init, step-at-a-time plan
% execution, jobserver shutdown, snapshot finalization, VDB
% reconciliation backstop, resume-state cleanup on success, summary,
% last_build_status/3 bookkeeping, and the optional terminal alert.
% Any fix to this sequence (e.g. the planned build exit codes 10-16)
% lands here exactly once.
%
% Opts is a list of options:
%   pre_actions(PreActions) : annotation pre-actions (keyword
%     acceptance, unmask, use changes) rendered as a completed step 1
%     before the plan steps. Defaults to [].
%
% StartStep is the 1-based number of the first plan step in the build
% display (2 when a pre-action step is shown, 1 otherwise).
%
% snapshot:finalize only clears snapshot:active_id/1 and is a no-op
% when --snapshot is not active (always the case on the resume path).
%
% Exception safety: the worker pool and the snapshot marker are torn
% down in the cleanup of a setup_call_cleanup/3 around execute_plan/9,
% so an exception escaping a step (a display or resume-state error, a
% user abort, ...) can never leave `build_worker_N` threads alive
% (which would make the next jobserver:init/2 in the replan loop or a
% later --resume fail on the thread alias) or a stale
% snapshot:active_id/1 behind. The exception itself still propagates
% to the caller; on that path the resume state is deliberately kept so
% the user can --resume, and last_build_status/3 is left untouched.

builder:run_plan(Plan, StartStep, Opts, Completed, Failed, Stubs) :-
  ( memberchk(pre_actions(PreActions), Opts) -> true ; PreActions = [] ),
  length(PreActions, PreCount),
  ( PreCount > 0 -> PreSteps = 1 ; PreSteps = 0 ),
  retractall(builder:last_failed(_, _, _)),
  resume:clear_done_marks,
  builder:prepare_binpkg_index,
  builder:count_actions(Plan, 0, PlanActions),
  TotalActions is PlanActions + PreCount,
  builder:count_nonempty_steps(Plan, 0, PlanSteps),
  NumSteps is PlanSteps + PreSteps,
  build:header(NumSteps, TotalActions),
  display:print_pre_action_step(PreActions, PreSteps),
  builder:apply_kernel_config_pre_actions(PreActions),
  builder:num_workers(NumWorkers),
  setup_call_cleanup(
    jobserver:init(NumWorkers, builder:execute_build_job),
    once(builder:execute_plan(Plan, StartStep, NumSteps, 0, 0, 0, Completed, Failed0, Stubs)),
    ( jobserver:shutdown(NumWorkers),
      snapshot:finalize
    )),
  builder:apply_vdb_reconciliation(Plan, Failed0, Failed, _Missing),
  ( Failed =:= 0
  -> resume:clear_state
  ;  true
  ),
  build:summary(Completed, Failed, Stubs),
  retractall(builder:last_build_status(_, _, _)),
  assertz(builder:last_build_status(Completed, Failed, Stubs)),
  builder:alert.


%! builder:apply_kernel_config_pre_actions(+PreActions) is det.
%
% Applies any kernel_config(Options, Evidence) pre-actions (learned via the
% kernelconfig exception mechanism, portage-ng#105) to the kernel source
% .config before the plan steps run, so a package's setup-phase
% CONFIG_CHECK passes. Dispatched to the domain kernelconfig module, which
% is only loaded in standalone mode; the builder stays generic and this is
% a no-op when the mechanism is absent or no such pre-action was surfaced.

builder:apply_kernel_config_pre_actions(PreActions) :-
  ( current_predicate(kernelconfig:apply_planned/1)
  -> catch(kernelconfig:apply_planned(PreActions), _, true)
  ;  true
  ).


%! builder:alert is det.
%
% When --alert is active, rings the terminal bell to attract attention.

builder:alert :-
  ( preference:flag(alert)
  -> message:bell
  ;  true
  ).


%! builder:prepare_binpkg_index is det.
%
% Ensure the in-memory binpkg cache reflects the on-disk `Packages`
% index before a build starts (portage-ng#12, portage-ng#24).
%
% `kb:register(binpkg)` only records the repository fact; it does NOT
% parse `Packages`. The in-memory binpkg cache at build start is either
% empty (cold process, portage-ng#12) or -- worse -- a stale snapshot
% qcompiled into `Knowledge/kb.qlf` at the last `--sync`. With a stale
% snapshot, `binpkg_exec:available_for/4` selects outdated BUILD_IDs:
% in issue #24 a kb.qlf snapshot predating fresh sci-ml/onnx gpkgs made
% the builder qmerge an onnx variant whose gencode was produced by
% dev-libs/protobuf-33.1 into a system where the same plan had just
% merged protobuf-34.2, and sci-ml/caffe2 then failed its compile phase
% on the protobuf gencode/runtime cross-version #error.
%
% Delegates to `binpkg_exec:ensure_index_fresh/0`, which is mtime-gated:
% it always syncs on the first observation in a process (fixing the cold
% / stale-snapshot cases above) but skips the full ~27 MB re-parse on a
% back-to-back build whose `Packages` mtime is unchanged (portage-ng#80,
% item A). The (re)load is atomic and never leaves the index empty.

builder:prepare_binpkg_index :-
  ( current_predicate(binpkg_exec:ensure_index_fresh/0)
  -> catch(binpkg_exec:ensure_index_fresh, _, true)
  ;  true
  ).


%! builder:ask_confirmation is semidet.
%
% When --ask is active, prompts the user to confirm before proceeding.
% Succeeds immediately if --ask is not set. Fails if the user declines.

builder:ask_confirmation :-
  ( preference:flag(ask)
  -> ( preference:flag(readnews)
     -> catch(news:check, _, true), nl
     ;  true
     ),
     builder:alert,
     nl,
     message:print('Would you like to merge these packages? [Yes/No] '),
     flush_output,
     read_line_to_string(current_input, Answer),
     ( member(Answer, ["Yes", "yes", "Y", "y", ""])
     -> true
     ;  false
     )
  ;  true
  ).


%! builder:num_workers(-N) is det.
%
% Compute the number of worker threads: min(cpu_count, available_display_lines).
% When --jobs N is specified and N > 0, uses that value instead.

builder:num_workers(N) :-
  ( config:cli_jobs(J)
  -> N = J
  ;  config:number_of_cpus(Cpus),
     console:printing_tty_size(H, _W),
     ReservedLines = 6,
     MaxDisplay is max(1, H - ReservedLines),
     N is min(Cpus, MaxDisplay)
  ).


% -----------------------------------------------------------------------------
%  Step counting
% -----------------------------------------------------------------------------

%! builder:count_actions(+Plan, +Acc, -Total) is det.

builder:count_actions([], Total, Total).

builder:count_actions([Step|Rest], Acc, Total) :-
  builder:count_executable_in_step(Step, N),
  Acc1 is Acc + N,
  builder:count_actions(Rest, Acc1, Total).

builder:count_executable_in_step(Rules, N) :-
  include(builder:is_executable_rule, Rules, Executable),
  length(Executable, N).


%! builder:count_nonempty_steps(+Plan, +Acc, -Total) is det.

builder:count_nonempty_steps([], Total, Total).

builder:count_nonempty_steps([Step|Rest], Acc, Total) :-
  builder:count_executable_in_step(Step, N),
  ( N > 0 -> Acc1 is Acc + 1 ; Acc1 = Acc ),
  builder:count_nonempty_steps(Rest, Acc1, Total).


%! builder:is_executable_rule(+Rule) is semidet.

builder:is_executable_rule(rule(_Repository://_Entry:annotate?{_Context}, _Body)) :- !, fail.
builder:is_executable_rule(rule(_Repository://_Entry:Action?{_Context}, _Body)) :-
  preference:fetchonly_skips_action(Action),
  !,
  fail.
builder:is_executable_rule(rule(world(_Atom):_Action?{_Ctx}, _Body)) :-
  preference:flag(fetchonly),
  !,
  fail.
builder:is_executable_rule(rule(_Repository://_Entry:_Action?{_Context}, _Body)) :- !.
builder:is_executable_rule(rule(world(_Atom):_Action?{_Ctx}, _Body)) :- !.
builder:is_executable_rule(_) :- fail.


%! builder:plan_entries(+Plan, -Entries) is det.
%
% The sorted set of tree package entries (Repo://Entry) appearing in the
% derived plan. Used to scope learned kernel-config requirements
% (feedback:plan_kernel_config_pre_actions/2) to targets actually in this
% plan, so an option learned for one package is only re-applied when that
% package is (re)built.

builder:plan_entries(Plan, Entries) :-
  findall(Repo://Entry,
          ( member(Step, Plan),
            member(Rule, Step),
            builder:is_executable_rule(Rule),
            Rule = rule(Repo://Entry:_Action?{_Ctx}, _Body) ),
          Entries0),
  sort(Entries0, Entries).


% -----------------------------------------------------------------------------
%  VDB reconciliation (defensive backstop)
% -----------------------------------------------------------------------------
%
% Even with correct per-step failure counting, the engine has historically
% leaked silent-success regressions: a sub-dependency's install fails,
% but the aggregate `Failed` counter ends up at 0 and `--ci --build`
% exits 0. The downstream comparison harness (tinderbox-ng's
% render-compare-matrix.py:real_pn_built/parse_vdb_delta) catches this
% post-hoc by parsing the VDB delta, but by then the engine has already
% lied about its own success.
%
% This block pulls that ground-truth check up into the engine itself.
% After execute_plan returns, we walk the plan and verify that every
% rule whose action would install a package (install / update /
% downgrade / reinstall) has produced an on-disk VDB entry. Any
% missing entries are counted as failures regardless of what the
% step-by-step tally said, so `builder:last_build_status/3` -- and
% therefore `action:maybe_ci_exit_on_build_failure/1` -- reflects
% reality.
%
% The check is intentionally cheap (one directory-stat per install
% action) and is gated so it only runs when a real merge could have
% happened: `merge` must be in `config:build_live_phases/1` and the
% `pkg` repository (VDB) must be registered with a stat'able location.
% Stubbed runs (build_live_phases empty, --pretend-style) are skipped
% silently.

%! builder:apply_vdb_reconciliation(+Plan, +F0, -F, -Missing) is det.
%
% Wrapper that combines `reconcile_install_actions/3` with the
% Failed-counter adjustment + warning print. F = F0 + len(Missing) when
% the check fired; F = F0 otherwise. Missing is the list of plan rules
% (Repo://Entry:Action terms) whose VDB entry is missing on disk.

builder:apply_vdb_reconciliation(Plan, F0, F, Missing) :-
  builder:reconcile_install_actions(Plan, Missing, Active),
  ( Active == true, Missing \= []
  -> length(Missing, N),
     F is F0 + N,
     builder:print_reconciliation_warning(Missing, N)
  ;  F = F0
  ).


%! builder:reconcile_install_actions(+Plan, -Missing, -Active) is det.
%
% Walk Plan and collect install-shaped rules that completed with
% outcome `done` (see `resume:done/2`) but whose target has no
% corresponding directory under the VDB root. Failed or skipped installs
% are excluded so reconciliation does not inflate the failure tally
% (portage-ng#11). Active is `true` when the check actually ran,
% `false` when it was skipped (no merge in live phases, or no pkg
% repository). When Active is `false`, callers MUST ignore Missing.

builder:reconcile_install_actions(Plan, Missing, Active) :-
  ( builder:reconciliation_should_run(VdbRoot)
  -> Active = true,
     findall(Repo://Entry:Action,
             ( member(Step, Plan),
               member(Rule, Step),
               builder:is_install_rule(Rule, Repo, Entry, Action),
               resume:done(Entry, Action),
               \+ builder:vdb_entry_present(VdbRoot, Entry)
             ),
             Missing)
  ;  Active = false,
     Missing = []
  ).


%! builder:reconciliation_should_run(-VdbRoot) is semidet.
%
% Succeeds (binding VdbRoot to the on-disk VDB location) iff a real
% merge could have happened during this run AND the VDB is stat'able.
% Fails silently for stubbed builds, fully-dry runs, or hosts without
% a registered `pkg` repository.

builder:reconciliation_should_run(VdbRoot) :-
  config:build_live_phases(LP),
  memberchk(merge, LP),
  current_predicate(pkg:get_location/1),
  catch(pkg:get_location(VdbRoot), _, fail),
  exists_directory(VdbRoot).


%! builder:is_install_rule(+Rule, -Repo, -Entry, -Action) is semidet.
%
% True when Rule is an `install` / `update` / `downgrade` / `reinstall`
% action on an eapi-typed source repository -- i.e. an action expected
% to land a directory under `<vdb_root>/<cat>/<pf>/` when it succeeds.
% Other actions (download, fetchonly, register, uninstall, world ops,
% non-eapi script execs) don't write to the VDB and are excluded from
% reconciliation.

builder:is_install_rule(rule(Repo://Entry:Action?{_Ctx}, _Body), Repo, Entry, Action) :-
  memberchk(Action, [install, update, downgrade, reinstall]),
  catch(Repo:get_type(eapi), _, fail).


%! builder:vdb_entry_present(+VdbRoot, +Entry) is semidet.
%
% True iff `<VdbRoot>/<Entry>/` exists as a directory. Entry is the
% canonical `<cat>/<pf>` form used throughout cache:ordered_entry/5,
% which matches the on-disk VDB layout (cf. repository:find_vdb_entry/4).

builder:vdb_entry_present(VdbRoot, Entry) :-
  os:compose_path(VdbRoot, Entry, Path),
  exists_directory(Path).


%! builder:print_reconciliation_warning(+Missing, +N) is det.
%
% Print a clearly-flagged warning enumerating the missing installs.
% Format mirrors the existing builder warnings (message:warning) so the
% line shows up in build logs with the standard "!!!" prefix and
% orange/red coloring, making this easy to grep for in CI reports.

builder:print_reconciliation_warning(Missing, N) :-
  ( N =:= 1 -> Suffix = '' ; Suffix = 's' ),
  format(atom(Header),
         'VDB reconciliation: ~w install action~w missing from /var/db/pkg after build',
         [N, Suffix]),
  message:warning([Header]),
  forall(member(Repo://Entry:Action, Missing),
         ( format(atom(Line), '  ~w  ~w://~w', [Action, Repo, Entry]),
           message:warning([Line])
         )),
  message:warning(['Counting these as failures even though the per-step tally missed them.']),
  message:warning(['See builder:apply_vdb_reconciliation/4 for the backstop logic.']).


% -----------------------------------------------------------------------------
%  Plan execution (step-at-a-time via jobserver)
% -----------------------------------------------------------------------------

%! builder:execute_plan(+Plan, +PlanStep, +NumSteps, +C0, +F0, +S0, -C, -F, -S) is det.

builder:execute_plan([], _PlanStep, _NumSteps, C, F, S, C, F, S).

builder:execute_plan([Step|Rest], PlanStep, NumSteps, C0, F0, S0, C, F, S) :-
  builder:execute_step(Step, PlanStep, NumSteps, C0, F0, S0, C1, F1, S1, HasJobs),
  ( HasJobs == true -> PlanStep1 is PlanStep + 1 ; PlanStep1 = PlanStep ),
  resume:flush_done_to_disk,
  ( F1 > F0
  -> ( builder:should_continue_on_failure ->
       builder:execute_plan(Rest, PlanStep1, NumSteps, C1, F1, S1, C, F, S)
     ; builder:skip_remaining(Rest, PlanStep1, NumSteps, C1, F1, S1, C, F, S)
     )
  ;  builder:execute_plan(Rest, PlanStep1, NumSteps, C1, F1, S1, C, F, S)
  ).


%! builder:should_continue_on_failure is semidet.
%
% Succeeds when --continue-on-failure is set to a value other
% than 'never'.

builder:should_continue_on_failure :-
  config:continue_on_failure(Mode),
  Mode \== never.


%! builder:skip_remaining(+Plan, +PlanStep, +NumSteps, +C0, +F0, +S0, -C, -F, -S) is det.
%
% When a step has failures, skip all remaining steps. Each remaining
% executable action is counted as failed since its dependencies weren't met.

builder:skip_remaining([], _PlanStep, _NumSteps, C, F, S, C, F, S).

builder:skip_remaining([Step|Rest], PlanStep, NumSteps, C0, F0, S0, C, F, S) :-
  include(builder:is_executable_rule, Step, Executable),
  length(Executable, NumJobs),
  ( NumJobs > 0
  -> display:assign_slots(Executable, PlanStep, NumSteps, SlottedJobs, TotalLines),
     build:print_skipped_slots(SlottedJobs, NumSteps),
     display:mark_skipped(SlottedJobs, TotalLines),
     nl,
     F1 is F0 + NumJobs,
     PlanStep1 is PlanStep + 1
  ;  F1 = F0,
     PlanStep1 = PlanStep
  ),
  builder:skip_remaining(Rest, PlanStep1, NumSteps, C0, F1, S0, C, F, S).


%! builder:execute_step(+Step, +PlanStep, +NumSteps, +C0, +F0, +S0, -C, -F, -S, -HasJobs) is det.
%
% Execute all jobs in a step in parallel:
%   1. Extract executable rules and pre-allocate display layout
%   2. Register slot info for result handler lookups
%   3. Print all slots (with file sub-lines for downloads)
%   4. Submit all jobs to the jobserver
%   5. Collect results, updating slots in-place
%   6. Tally outcomes, clean up
%
% Steps 2-6 run under setup_call_cleanup/3 so clear_step_state/0 also
% runs when a result handler or the tally throws: the slot registry,
% recorded slot outcomes, speed snapshots and exec phase states are
% per-step and must never leak into the next step or the next run.
% Stale jobs/results left in the jobserver queues by such an exception
% are drained by jobserver:shutdown/1 in run_plan/6's cleanup.

builder:execute_step(Step, PlanStep, NumSteps, C0, F0, S0, C, F, S, HasJobs) :-
  plan:sort_by_display_order(Step, Sorted),
  include(builder:is_executable_rule, Sorted, Executable),
  length(Executable, NumJobs),
  ( NumJobs > 0
  -> HasJobs = true,
     display:assign_slots(Executable, PlanStep, NumSteps, SlottedJobs, TotalLines),
     setup_call_cleanup(
       display:register_slot_info(SlottedJobs),
       once(( build:print_job_slots(SlottedJobs, NumSteps),
              jobserver:submit(SlottedJobs),
              jobserver:collect(NumJobs, builder:handle_result(TotalLines)),
              nl,
              builder:tally_outcomes(C0, F0, S0, C, F, S)
            )),
       builder:clear_step_state)
  ;  HasJobs = false,
     C = C0, F = F0, S = S0
  ).


%! builder:clear_step_state is det.
%
% Tear down all per-step dynamic state: the display slot registry,
% recorded slot outcomes, per-file download speed snapshots, and any
% leftover exec phase states.

builder:clear_step_state :-
  display:clear_slot_info,
  retractall(builder:slot_outcome(_, _)),
  fetch:clear_speed_tracking,
  retractall(builder:exec_phase_state(_, _, _)).


% -----------------------------------------------------------------------------
%  Job execution (called by worker threads)
% -----------------------------------------------------------------------------

%! builder:execute_build_job(+SlottedJob, +WorkerSlot, -Result) is det.
%
% Execute a single build job. Called by jobserver worker threads.
% Updates the display slot to "active" on entry, then performs the work.
% For download/fetchonly actions, the worker manages file sub-slot display
% itself and returns display_handled(Outcome) to skip redundant updates.

builder:execute_build_job(
    slotted(LineOff, TotalLines, PlanStep, NumSteps, ActionIdx, rule(Repo://Entry:Action?{Ctx}, _Body), FileInfo),
    _WorkerSlot, result(LineOff, ResultOutcome)) :-
  !,
  with_mutex(build_display,
    build:update_slot(LineOff, TotalLines, active, PlanStep, NumSteps, ActionIdx, Action, Repo://Entry)),
  builder:maybe_quickpkg_old(Action, Ctx),
  ( FileInfo = live_source(LiveStartLine)
  -> fetch:run_git_download(Repo, Entry, LiveStartLine, TotalLines,
                            LineOff, PlanStep, NumSteps, ActionIdx, Action, Outcome),
     ResultOutcome = display_handled(Outcome)
  ;  FileInfo = files(FileStartLine, _NumFiles, DistFiles, Distdir)
  -> fetch:run_download_parallel(Repo, Entry, Ctx, LineOff, TotalLines, PlanStep, NumSteps, ActionIdx, Action,
                                 FileStartLine, DistFiles, Distdir, Outcome),
     ResultOutcome = display_handled(Outcome)
  ;  memberchk(Action, [download, fetchonly])
  -> with_mutex(build_display,
       build:update_slot(LineOff, TotalLines, done, PlanStep, NumSteps, ActionIdx, Action, Repo://Entry)),
     ResultOutcome = display_handled(done)
  ;  FileInfo = phases(ExecLine, ExecLineCount, LogsLine, PhaseList, LogPath)
  -> builder:run_action_with_phases(Action, Repo, Entry, Ctx,
                                     TotalLines, ExecLine, ExecLineCount, LogsLine, PhaseList, LogPath,
                                     LineOff, PlanStep, NumSteps, ActionIdx, Outcome),
     ResultOutcome = display_handled(Outcome)
  ;  builder:run_action(Action, Repo, Entry, Ctx, Outcome),
     ResultOutcome = Outcome
  ),
  builder:dispatch_suggestions(Repo, Entry, Ctx).

builder:execute_build_job(
    slotted(LineOff, TotalLines, PlanStep, NumSteps, ActionIdx, rule(world(Atom):Action?{_Ctx}, _Body), _FileInfo),
    _WorkerSlot, result(LineOff, display_handled(done))) :-
  !,
  builder:execute_world(Action, Atom),
  with_mutex(build_display,
    build:update_slot(LineOff, TotalLines, done, PlanStep, NumSteps, ActionIdx, Action, Atom)).

% Catch-all: a job whose rule shape doesn't match either of the two
% recognized executable patterns above. Historically this silently
% returned `stub`, which tally_outcomes counted as a (harmless) stub
% rather than a failure -- so any future malformed rule would slip
% through `--ci --build` as exit 0. Treat it as a failure with a
% descriptive reason so the bug surfaces immediately.
builder:execute_build_job(Job, _WorkerSlot, result(unknown, failed(unrecognised_job_shape(Job)))) :-
  format(user_error,
         '[builder] unrecognised job shape, treating as failure: ~q~n',
         [Job]).


%! builder:run_action(+Action, +Repo, +Entry, +Ctx, -Outcome) is det.
%
% Execute a non-download action. Downloads are handled by
% fetch:run_download_parallel via execute_build_job.
%
% Dispatches to ebuild_exec for real builds when config:build_live_phases
% is non-empty. Falls back to stub when fully stubbed or ebuild_exec
% is unavailable.

builder:run_action(Action, Repo, Entry, Ctx, Outcome) :-
  Repo:get_type(eapi),
  config:build_live_phases(LP), LP \= [],
  predicate_property(ebuild_exec:execute(_,_,_,_,_), defined),
  !,
  ebuild_exec:execute(Action, Repo, Entry, Ctx, Outcome).

builder:run_action(Action, Repo, Entry, Ctx, Outcome) :-
  Repo == binpkg,
  config:build_live_phases(LP), LP \= [],
  predicate_property(binpkg_exec:execute(_,_,_,_,_,_), defined),
  !,
  builder:run_binpkg_action(Action, Entry, Ctx, Outcome).

builder:run_action(_Action, Repo, _Entry, _Ctx, Outcome) :-
  Repo:get_type(Type),
  Type \= eapi,
  !,
  Repo:get_location(Location),
  builder:run_script_action(Type, Location, Outcome).

builder:run_action(_Action, _Repo, _Entry, _Ctx, stub).


%! builder:run_script_action(+Type, +Location, -Outcome) is det.
%
% Run the `build` script for a non-eapi repository. Success is reported
% as `done` — the same outcome vocabulary ebuild_exec, binpkg_exec and
% fetch use — so outcome_to_status/2 and tally_outcomes/6 count it as a
% completed step rather than an unknown failure.

builder:run_script_action(Type, Location, Outcome) :-
  ( script:exec(build, [Type, Location])
  -> Outcome = done
  ;  Outcome = failed
  ).


%! builder:run_binpkg_action(+Action, +BinpkgEntry, +Ctx, -Outcome) is det.
%
% Execute a plan step whose repository is `binpkg` (a direct
% binpkg://… literal, not the ebuild_exec fast-path substitution).
% Resolves the matching portage source ebuild for qmerge and delegates
% to `binpkg_exec:execute/6`. Maps `run` to `install` (qmerge).

builder:run_binpkg_action(Action, BinpkgEntry, Ctx, Outcome) :-
  ( cache:ordered_entry(binpkg, BinpkgEntry, Cat, Name, Version),
    cache:repository(portage),
    cache:ordered_entry(portage, SrcEntry, Cat, Name, Version),
    builder:binpkg_merge_action(Action, MergeAction)
  -> binpkg_exec:execute(MergeAction, portage, SrcEntry, BinpkgEntry, Ctx, Outcome)
  ;  Outcome = failed(no_source_ebuild)
  ).


%! builder:binpkg_merge_action(+Action, -MergeAction) is det.
%
% Only install-shaped actions drive qmerge; `run` on a binpkg entry is
% treated as a binary merge (mirrors emerge's USEPKG install).

builder:binpkg_merge_action(run, install) :- !.
builder:binpkg_merge_action(Action, Action) :-
  memberchk(Action, [install, reinstall, update, downgrade]).


%! builder:run_action_with_phases(+Action, +Repo, +Entry, +Ctx, +TotalLines, +ExecLine, +ExecLineCount, +LogsLine, +PhaseList, +LogPath, +LineOff, +PlanStep, +NumSteps, +ActionIdx, -Outcome) is det.
%
% Execute a build action with inline phase progress tracking.
% Uses exec lines with arrow-separated phases and a logs line below.

builder:run_action_with_phases(Action, Repo, Entry, Ctx,
                                TotalLines, _ExecLine, _ExecLineCount, _LogsLine, _PhaseList, _LogPath,
                                LineOff, PlanStep, NumSteps, ActionIdx, Outcome) :-
  Repo == binpkg,
  config:build_live_phases(LP), LP \= [],
  predicate_property(binpkg_exec:execute(_,_,_,_,_,_), defined),
  !,
  builder:run_binpkg_action(Action, Entry, Ctx, Outcome),
  builder:outcome_to_status(Outcome, FinalStatus),
  with_mutex(build_display,
    build:update_slot(LineOff, TotalLines, FinalStatus, PlanStep, NumSteps, ActionIdx, Action, Repo://Entry)).

builder:run_action_with_phases(Action, Repo, Entry, _Ctx,
                                TotalLines, _ExecLine, _ExecLineCount, _LogsLine, _PhaseList, _LogPath,
                                LineOff, PlanStep, NumSteps, ActionIdx, Outcome) :-
  Repo:get_type(Type),
  Type \= eapi,
  !,
  Repo:get_location(Location),
  builder:run_script_action(Type, Location, Outcome),
  builder:outcome_to_status(Outcome, FinalStatus),
  with_mutex(build_display,
    build:update_slot(LineOff, TotalLines, FinalStatus, PlanStep, NumSteps, ActionIdx, Action, Repo://Entry)).

builder:run_action_with_phases(Action, Repo, Entry, Ctx,
                                TotalLines, ExecLine, _ExecLineCount, LogsLine, PhaseList, LogPath,
                                LineOff, PlanStep, NumSteps, ActionIdx, Outcome) :-
  Repo:get_type(eapi),
  config:build_live_phases(LP), LP \= [],
  predicate_property(ebuild_exec:execute_with_progress(_,_,_,_,_,_), defined),
  !,
  builder:init_exec_phase_state(ExecLine, PhaseList),
  Callback = builder:phase_callback(TotalLines, ExecLine, LogsLine, Action, PhaseList, LogPath),
  ebuild_exec:execute_with_progress(Action, Repo, Entry, Ctx, Callback, Outcome),
  builder:outcome_to_status(Outcome, FinalStatus),
  builder:clear_exec_phase_state(ExecLine),
  ( LogsLine >= 0
  -> with_mutex(build_display,
       build:update_logs_line(LogsLine, TotalLines, LogPath, FinalStatus))
  ;  true
  ),
  with_mutex(build_display,
    build:update_slot(LineOff, TotalLines, FinalStatus, PlanStep, NumSteps, ActionIdx, Action, Repo://Entry)).

builder:run_action_with_phases(Action, Repo, Entry, _Ctx,
                                TotalLines, ExecLine, _ExecLineCount, LogsLine, PhaseList, LogPath,
                                LineOff, PlanStep, NumSteps, ActionIdx, stub) :-
  builder:stub_all_phases(Action, PhaseList, TotalLines, ExecLine, LogsLine, LogPath),
  with_mutex(build_display,
    build:update_slot(LineOff, TotalLines, stub, PlanStep, NumSteps, ActionIdx, Action, Repo://Entry)).


%! builder:phase_callback(+TotalLines, +ExecLine, +LogsLine, +Action, +PhaseList, +LogPath, +Phase, +Status) is det.
%
% Display callback invoked by ebuild_exec for each phase transition.
% Updates the exec_phase_state facts and re-renders the inline exec line.

builder:phase_callback(TotalLines, ExecLine, LogsLine, Action, PhaseList, LogPath, Phase, Status) :-
  memberchk(Phase, PhaseList),
  !,
  ( retract(builder:exec_phase_state(ExecLine, Phase, _)) -> true ; true ),
  assertz(builder:exec_phase_state(ExecLine, Phase, Status)),
  builder:collect_phase_states(ExecLine, PhaseList, PhaseStates),
  with_mutex(build_display,
    build:update_exec_line(ExecLine, TotalLines, Action, PhaseStates)),
  ( build:is_failed_status(Status), LogsLine >= 0
  -> with_mutex(build_display,
       build:update_logs_line(LogsLine, TotalLines, LogPath, failed))
  ;  true
  ).

builder:phase_callback(_, _, _, _, _, _, _, _).


%! builder:collect_phase_states(+ExecLine, +PhaseList, -PhaseStates) is det.
%
% Build a list of Phase-Status pairs from the dynamic exec_phase_state facts.

builder:collect_phase_states(_, [], []).

builder:collect_phase_states(ExecLine, [Phase|Rest], [Phase-Status|States]) :-
  ( builder:exec_phase_state(ExecLine, Phase, Status)
  -> true
  ;  Status = pending
  ),
  builder:collect_phase_states(ExecLine, Rest, States).


%! builder:init_exec_phase_state(+ExecLine, +PhaseList) is det.
%
% Initialize all phases as pending for a given exec line.

builder:init_exec_phase_state(_, []).

builder:init_exec_phase_state(ExecLine, [Phase|Rest]) :-
  assertz(builder:exec_phase_state(ExecLine, Phase, pending)),
  builder:init_exec_phase_state(ExecLine, Rest).


%! builder:clear_exec_phase_state(+ExecLine) is det.
%
% Remove all phase state facts for a given exec line.

builder:clear_exec_phase_state(ExecLine) :-
  retractall(builder:exec_phase_state(ExecLine, _, _)).


%! builder:stub_all_phases(+Action, +PhaseList, +TotalLines, +ExecLine, +LogsLine, +LogPath) is det.
%
% Mark all phases as stub and render the inline display accordingly.

builder:stub_all_phases(Action, PhaseList, TotalLines, ExecLine, LogsLine, LogPath) :-
  maplist([P, P-stub]>>true, PhaseList, PhaseStates),
  with_mutex(build_display,
    build:update_exec_line(ExecLine, TotalLines, Action, PhaseStates)),
  ( LogsLine >= 0
  -> with_mutex(build_display,
       build:update_logs_line(LogsLine, TotalLines, LogPath, stub))
  ;  true
  ).


% -----------------------------------------------------------------------------
%  Result handling (main thread, display callback)
% -----------------------------------------------------------------------------

%! builder:handle_result(+TotalLines, +LineOff, +Outcome) is det.
%
% Called by jobserver:collect for each completed job. Updates the
% display slot and records the outcome for tallying.
% display_handled(Outcome) means the worker already updated the display.

builder:handle_result(_TotalLines, LineOff, display_handled(Outcome)) :-
  !,
  assertz(builder:slot_outcome(LineOff, Outcome)),
  builder:maybe_record_resume_done(LineOff, Outcome),
  builder:maybe_record_failed(LineOff, Outcome).

builder:handle_result(TotalLines, LineOff, Outcome) :-
  assertz(builder:slot_outcome(LineOff, Outcome)),
  display:get_slot_info(LineOff, PlanStep, NumSteps, ActionIdx, Action, Entry),
  builder:outcome_to_status(Outcome, Status),
  with_mutex(build_display,
    build:update_slot(LineOff, TotalLines, Status, PlanStep, NumSteps, ActionIdx, Action, Entry)),
  builder:maybe_record_resume_done(LineOff, Outcome),
  builder:maybe_record_failed(LineOff, Outcome).


%! builder:maybe_record_resume_done(+LineOff, +Outcome) is det.
%
% Records a completed entry for resume tracking. Only records
% repository entries (Repo://Entry pattern) with done outcome.

builder:maybe_record_resume_done(LineOff, Outcome) :-
  ( Outcome == done,
    display:slot_info(LineOff, _, _, _, Action, Entry),
    Entry = _://_
  -> resume:mark_done(Entry, Action)
  ;  true
  ).


%! builder:maybe_record_failed(+LineOff, +Outcome) is det.
%
% Persists failed Repo://Entry outcomes (with log path) across
% clear_step_state/0 so metacircular diagnose can inspect them after
% run_plan/6 returns.

builder:maybe_record_failed(LineOff, Outcome) :-
  ( builder:outcome_to_status(Outcome, failed(Reason)),
    display:slot_info(LineOff, _, _, _, _Action, Repo://Entry)
  -> ( current_predicate(ebuild_exec:build_log_path/2)
     -> ebuild_exec:build_log_path(Entry, LogPath)
     ;  LogPath = ''
     ),
     assertz(builder:last_failed(Repo://Entry, Reason, LogPath))
  ;  true
  ).


%! builder:outcome_to_status(+Outcome, -Status) is det.

builder:outcome_to_status(done, done) :- !.
builder:outcome_to_status(stub, stub) :- !.
builder:outcome_to_status(failed(Reason), failed(Reason)) :- !.
builder:outcome_to_status(failed, failed('error')) :- !.
builder:outcome_to_status(error(E), failed(E)) :- !.
builder:outcome_to_status(_, failed('unknown')).


% -----------------------------------------------------------------------------
%  Tally
% -----------------------------------------------------------------------------

%! builder:tally_outcomes(+C0, +F0, +S0, -C, -F, -S) is det.
%
% Count recorded outcomes from the last step.

builder:tally_outcomes(C0, F0, S0, C, F, S) :-
  aggregate_all(count, builder:slot_outcome(_, done), DC),
  aggregate_all(count, builder:slot_outcome(_, stub), SC),
  aggregate_all(count, (builder:slot_outcome(_, O),
                         O \= done, O \= stub), FC),
  C is C0 + DC,
  F is F0 + FC,
  S is S0 + SC.


% -----------------------------------------------------------------------------
%  Snapshot integration
% -----------------------------------------------------------------------------

%! builder:maybe_create_snapshot(+Plan) is det.
%
% If --snapshot is active (snapshot:active_id/1 has been asserted by
% interface dispatch), creates a snapshot before the build begins.

builder:maybe_create_snapshot(Plan) :-
  ( snapshot:active_id(Id)
  -> snapshot:create(Id, Plan)
  ;  true
  ).


%! builder:maybe_quickpkg_old(+Action, +Ctx) is det.
%
% When a snapshot is active and the action replaces an installed
% package, quickpkg the old version before the merge phase overwrites it.

builder:maybe_quickpkg_old(Action, Ctx) :-
  snapshot:active_id(_),
  memberchk(Action, [install, update, downgrade, reinstall]),
  memberchk(replaces(OldRepo://OldEntry), Ctx),
  !,
  snapshot:quickpkg_old(OldRepo, OldEntry).

builder:maybe_quickpkg_old(_, _).


% -----------------------------------------------------------------------------
%  World action execution (stubs)
% -----------------------------------------------------------------------------

%! builder:execute_world(+Op, +Arg) is det.
%
% Stub for world set modifications. Currently a no-op; future
% implementation will call world:register/1 or world:unregister/1.

builder:execute_world(register, _Arg).
builder:execute_world(unregister, _Arg).


% -----------------------------------------------------------------------------
%  Suggestion dispatch (auto-config writers)
% -----------------------------------------------------------------------------
%
% The prover tags fully-resolved literals with three flavors of suggestion:
%
%   suggestion(unmask, Repo://Entry)
%   suggestion(accept_keyword, Kw)
%   suggestion(use_change, Repo://Entry, Changes)
%
% These describe the /etc/portage overrides the prover had to assume in
% order to build a working plan (e.g. picking apache2_mpms_event to
% satisfy a `|| (...)` REQUIRED_USE group, or accepting ~amd64 for a
% candidate ebuild). For the current build the overrides are already
% applied via the proof context (ebuild_exec:apply_ctx_use_overrides), so
% this layer's job is purely persistence: write them into
%
%   $portage_confdir/package.{unmask,accept_keywords,use}/00portage-ng-auto
%
% so that subsequent builds (in this session OR later sessions) start
% from the same configured state. The file format is the standard
% Portage one; lines are line-deduped so retries never accumulate
% duplicates. After every successful write, userconfig:load is invoked
% so the next ebuild in the same build sees the freshly persisted
% override without restarting.
%
% No-op when config:portage_confdir/1 is unset (e.g. dev-Mac setup that
% relies on Source/Domain/Gentoo/Preference/fallback.pl).
%
% Thread-safe: a global mutex (build_auto_config) serializes the
% read-modify-write cycle across parallel build workers.

:- mutex_create(build_auto_config).


%! builder:dispatch_suggestions(+Repo, +Entry, +Ctx) is det.
%
% Persists suggestions tagged on the (Repo, Entry, Ctx) literal. Repo
% and Entry are the outer literal's identifier; the proof-context
% suggestion(unmask, ...) and suggestion(use_change, ..., ...) terms
% may carry their own Repo://Entry, but that's typically a candidate
% the prover is *introducing*, distinct from the outer literal.

builder:dispatch_suggestions(Repo, Entry, Ctx) :-
  is_list(Ctx), !,
  ( memberchk(suggestion(unmask, UR://UE), Ctx)
  -> builder:execute_suggestion(unmask, UR, UE)
  ;  true
  ),
  ( memberchk(suggestion(accept_keyword, Kw), Ctx)
  -> ( memberchk(suggestion(unmask, KR://KE), Ctx)
     -> builder:execute_suggestion(accept_keyword, KR, KE, Kw)
     ;  builder:execute_suggestion(accept_keyword, Repo, Entry, Kw)
     )
  ;  true
  ),
  ( memberchk(suggestion(use_change, UCR://UCE, Changes), Ctx)
  -> builder:execute_suggestion(use_change, UCR, UCE, Changes)
  ;  true
  ).

builder:dispatch_suggestions(_, _, _).


%! builder:execute_suggestion(+Type, +Repo, +Entry) is det.
%! builder:execute_suggestion(+Type, +Repo, +Entry, +Arg) is det.
%
% Persist a single prover suggestion to the corresponding /etc/portage
% package.* file. Each handler is defensive: invalid arguments, missing
% portage_confdir, or unwritable confdir all silently no-op rather than
% break the build.

builder:execute_suggestion(unmask, Repo, Entry) :-
  ( builder:auto_confdir(ConfDir),
    builder:atom_for_entry(Repo, Entry, Atom)
  -> builder:write_auto_config(ConfDir, 'package.unmask', Atom)
  ;  true
  ).


builder:execute_suggestion(accept_keyword, Repo, Entry, Kw) :-
  ( builder:auto_confdir(ConfDir),
    builder:atom_for_entry(Repo, Entry, Atom),
    builder:keyword_token(Kw, KwTok)
  -> atomic_list_concat([Atom, ' ', KwTok], Line),
     builder:write_auto_config(ConfDir, 'package.accept_keywords', Line)
  ;  true
  ).


builder:execute_suggestion(use_change, Repo, Entry, Changes) :-
  ( builder:auto_confdir(ConfDir),
    builder:atom_for_entry(Repo, Entry, Atom),
    builder:format_use_changes(Changes, FlagsAtom),
    FlagsAtom \== ''
  -> atomic_list_concat([Atom, ' ', FlagsAtom], Line),
     builder:write_auto_config(ConfDir, 'package.use', Line)
  ;  true
  ).


% -----------------------------------------------------------------------------
%  Auto-config helpers
% -----------------------------------------------------------------------------

%! builder:auto_confdir(-Dir) is semidet.
%
% Succeed with the configured /etc/portage directory; fail if no
% portage_confdir is configured (e.g. development setups that rely on
% Source/Domain/Gentoo/Preference/fallback.pl).

builder:auto_confdir(Dir) :-
  current_predicate(config:portage_confdir/1),
  config:portage_confdir(Dir).


%! builder:atom_for_entry(+Repo, +Entry, -Atom) is semidet.
%
% Build an exact-version Portage atom (=cat/name-version) from a
% repo entry. Fails when the entry can't be resolved.
%
% Version comes back from cache:ordered_entry/5 as a `version/7`
% compound term whose 7th argument is the canonical version string;
% see Source/Domain/Gentoo/version.pl. We extract that here.

builder:atom_for_entry(Repo, Entry, Atom) :-
  cache:ordered_entry(Repo, Entry, Cat, Name, Version),
  atom(Cat), atom(Name),
  version_domain:display_atom(Version, VAtom),
  VAtom \== '',
  atomic_list_concat(['=', Cat, '/', Name, '-', VAtom], Atom).


%! builder:format_use_changes(+Changes, -Atom) is det.
%
% Convert a list of use_change(Flag, enable/disable) terms into a
% portage-style flag list ("flag1 -flag2 flag3"). Empty atom if no
% supported changes are present.

builder:format_use_changes(Changes, Atom) :-
  findall(Tok,
    ( member(use_change(F, Dir), Changes),
      atom(F),
      ( Dir == enable  -> Tok = F
      ; Dir == disable -> atom_concat('-', F, Tok)
      )
    ),
    Toks),
  ( Toks == []
  -> Atom = ''
  ;  atomic_list_concat(Toks, ' ', Atom)
  ).


%! builder:keyword_token(+Kw, -Atom) is semidet.
%
% Normalize a keyword argument from the prover (atom, string, or term
% like keyword(Arch)) to a single atom suitable for the second column
% of a package.accept_keywords line.

builder:keyword_token(Kw, Atom) :- atom(Kw), !, Atom = Kw.
builder:keyword_token(Kw, Atom) :- string(Kw), !, atom_string(Atom, Kw).
builder:keyword_token(keyword(K), Atom) :- !, builder:keyword_token(K, Atom).
builder:keyword_token(Kw, Atom) :- format(atom(Atom), '~w', [Kw]).


%! builder:write_auto_config(+ConfDir, +SubDir, +Line) is det.
%
% Idempotently append `Line` to ConfDir/SubDir/00portage-ng-auto. On
% first use, creates the SubDir (if missing) and writes a clarifying
% header. Skips when the line is already present (whitespace- and
% trailing-comment-tolerant compare). After writing, reload userconfig
% so the next ebuild in this build picks up the override.
%
% Safe to call from parallel workers; serialized via build_auto_config.

builder:write_auto_config(ConfDir, SubDir, Line) :-
  catch(
    with_mutex(build_auto_config,
      builder:write_auto_config_locked(ConfDir, SubDir, Line)),
    Err,
    ( print_message(warning,
        format('portage-ng: failed to persist ~w override "~w": ~w', [SubDir, Line, Err])),
      true
    )).

builder:write_auto_config_locked(ConfDir, SubDir, Line) :-
  os:compose_path(ConfDir, SubDir, DirPath),
  ( exists_directory(DirPath) -> true ; make_directory_path(DirPath) ),
  atomic_list_concat([DirPath, '/00portage-ng-auto'], Path),
  ( builder:line_already_present(Path, Line)
  -> true
  ;  builder:append_with_header(Path, SubDir, Line),
     catch(userconfig:load, _, true)
  ).


%! builder:line_already_present(+Path, +Line) is semidet.
%
% True if Path exists and contains Line, comparing configuration lines
% (comments dropped, whitespace normalized) on both sides.

builder:line_already_present(Path, Line) :-
  reader:config_lines(Path, Lines),
  normalize_space(string(LineStr), Line),
  memberchk(LineStr, Lines).


%! builder:append_with_header(+Path, +SubDir, +Line) is det.
%
% Append Line to Path, creating Path with a clear "auto-managed" header
% on first use. Header explains the file's purpose and gives the user
% an out (delete or edit). SubDir is included so the header is unique
% per file (helps when grepping /etc/portage).

builder:append_with_header(Path, SubDir, Line) :-
  ( exists_file(Path) -> true
  ;  setup_call_cleanup(
       open(Path, write, S),
       format(S,
         '# Auto-managed by portage-ng (~w/00portage-ng-auto).~n~c Lines below are persisted prover suggestions: REQUIRED_USE picks,~n~c keyword acceptance, mask overrides, etc. Safe to edit or delete;~n~c missing entries will be re-derived on the next --build invocation.~n',
         [SubDir, 0'#, 0'#, 0'#]),
       close(S))
  ),
  setup_call_cleanup(
    open(Path, append, S2),
    format(S2, '~w~n', [Line]),
    close(S2)).


% -----------------------------------------------------------------------------
%  Builder test stats (whole-repo and targeted)
% -----------------------------------------------------------------------------

%! builder:test_stats(+Repository) is det.
%
% Run a builder test across the entire repository: for each entry,
% prove a plan, download distfiles, and run safe build phases.
% Uses tester:test for parallel iteration with progress.

builder:test_stats(Repository) :-
  config:test_style(Style),
  builder:test_stats(Repository, Style).


%! builder:test_stats(+Repository, +StyleOrTopN) is det.

builder:test_stats(Repository, TopN) :-
  integer(TopN), !,
  config:test_style(Style),
  builder:test_stats(Repository, Style, TopN).

builder:test_stats(Repository, Style) :-
  ( config:test_stats_top_n(TopN) -> true ; TopN = 25 ),
  builder:test_stats(Repository, Style, TopN).


%! builder:test_stats(+Repository, +Style, +TopN) is det.
%
% Core test loop: for each entry, prove plan, download distfiles,
% run safe phases. Failure at any stage is recorded via the sampler.

builder:test_stats(Repository, Style, TopN) :-
  aggregate_all(count, (Repository:entry(_E)), ExpectedTotal),
  sampler:reset('Building', ExpectedTotal),
  aggregate_all(count, (Repository:package(_C,_N)), ExpectedPkgs),
  sampler:set_expected_pkgs(ExpectedPkgs),
  tester:test(Style,
              'Building',
              Repository://Entry,
              Repository:entry(Entry),
              builder:test_single(Repository, Entry)),
  stats:test_stats_print(TopN).


%! builder:test_stats_pkgs(+Repository, +Pkgs) is det.
%
% Run builder test for a specific list of packages (C-N pairs).

builder:test_stats_pkgs(Repository, Pkgs) :-
  config:test_style(Style),
  ( config:test_stats_top_n(TopN) -> true ; TopN = 25 ),
  builder:test_stats_pkgs(Repository, Style, TopN, Pkgs).


%! builder:test_stats_pkgs(+Repository, +Style, +TopN, +Pkgs) is det.

builder:test_stats_pkgs(Repository, Style, TopN, Pkgs) :-
  is_list(Pkgs),
  length(Pkgs, ExpectedTotal),
  sampler:reset('Building', ExpectedTotal),
  sampler:set_expected_pkgs(ExpectedTotal),
  tester:test(Style,
              'Building',
              Repository://Entry,
              ( member(C-N, Pkgs),
                once(Repository:ebuild(Entry, C, N, _))
              ),
              builder:test_single(Repository, Entry)),
  stats:test_stats_print(TopN).


% -----------------------------------------------------------------------------
%  Per-entry test (prove + download + safe phases)
% -----------------------------------------------------------------------------

%! builder:test_single(+Repository, +Entry) is det.
%
% Test a single entry end-to-end without display:
%   1. Prove plan via prove_plan_with_fallback (canonical 5-tier fallback)
%   2. Download distfiles (skips already-present, verifies hashes)
%   3. Run safe build phases via ebuild_exec
%
% Succeeds if all steps complete, otherwise records failure via sampler
% and succeeds (tester:test handles outer error classification).

builder:test_single(Repository, Entry) :-
  sampler:reset_counters,
  statistics(inferences, I0),
  statistics(walltime, [T0, _]),
  Goals = [Repository://Entry:run?{[]}],
  ( pipeline:prove_plan_with_fallback(Goals, _Proof, _Model, Plan, _Triggers)
  -> catch(builder:test_plan_downloads(Plan), DlErr,
       with_mutex(mutex,
         (term_to_atom(DlErr, DA), message:warning([Entry, ' download error: ', DA])))),
     catch(builder:test_plan_phases(Plan), PhErr,
       with_mutex(mutex,
         (term_to_atom(PhErr, PA), message:warning([Entry, ' build error: ', PA])))),
     statistics(walltime, [T1, _]),
     statistics(inferences, I1),
     TimeMs is T1 - T0,
     Inferences is I1 - I0,
     sampler:counters(rule_calls(RuleCalls)),
     sampler:record(costs(Repository://Entry, TimeMs, Inferences, RuleCalls))
  ;  ( current_predicate(sampler:record/1)
     -> sampler:record(failed(other))
     ;  true
     )
  ).


%! builder:test_plan_downloads(+Plan) is det.
%
% Walk the plan and download distfiles for all download/fetchonly rules.
% Uses download:fetch_distfiles/4 which handles mirror URLs, fallback,
% hash verification, and skipping already-present files.

builder:test_plan_downloads([]).

builder:test_plan_downloads([Step|Rest]) :-
  builder:test_step_downloads(Step),
  builder:test_plan_downloads(Rest).


%! builder:test_step_downloads(+Step) is det.

builder:test_step_downloads([]).

builder:test_step_downloads([Rule|Rest]) :-
  ( Rule = rule(Head, _Body),
    prover:canon_literal(Head, Core, Ctx),
    Core = Repo://Entry:Action,
    memberchk(Action, [download, fetchonly]),
    \+ download:is_fetch_restricted(Repo, Entry),
    ( predicate_property(ebuild:is_live(_), defined) -> \+ ebuild:is_live(Repo://Entry) ; true )
  -> ( download:fetch_distfiles(Repo, Entry, Ctx, Failures),
       ( Failures == [] -> true
       ; term_to_atom(Failures, FA),
         with_mutex(mutex, message:warning([Entry, ' download failures: ', FA]))
       )
     ; true
     )
  ;  true
  ),
  builder:test_step_downloads(Rest).


%! builder:test_plan_phases(+Plan) is det.
%
% Walk the plan and execute safe build phases for all non-download rules.
% Uses ebuild_exec:execute/5 when config:build_live_phases is non-empty.

builder:test_plan_phases([]).

builder:test_plan_phases([Step|Rest]) :-
  builder:test_step_phases(Step),
  builder:test_plan_phases(Rest).


%! builder:test_step_phases(+Step) is det.

builder:test_step_phases([]).

builder:test_step_phases([Rule|Rest]) :-
  ( Rule = rule(Head, _Body),
    prover:canon_literal(Head, Core, Ctx),
    Core = Repo://Entry:Action,
    \+ memberchk(Action, [download, fetchonly])
  -> ( config:build_live_phases(LP), LP \= [],
       predicate_property(ebuild_exec:execute(_,_,_,_,_), defined)
     -> ( ebuild_exec:execute(Action, Repo, Entry, Ctx, Outcome),
          ( Outcome == done -> true
          ; term_to_atom(Outcome, OA),
            with_mutex(mutex, message:warning([Entry, ' build phase outcome: ', OA]))
          )
        ; true
        )
     ;  true
     )
  ;  true
  ),
  builder:test_step_phases(Rest).
