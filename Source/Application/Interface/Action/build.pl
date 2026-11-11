/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

% -----------------------------------------------------------------------------
%  Action: RESUME (skip args helper)
% -----------------------------------------------------------------------------

%! action:assert_resume_skip_args(+Args) is det.
%
% Asserts each positional argument as a config:skip_atom/1 fact.
% When --resume is active, positional args name packages to skip.

action:assert_resume_skip_args([]).

action:assert_resume_skip_args([A|Rest]) :-
  asserta(config:skip_atom(A)),
  assert_resume_skip_args(Rest).


% -----------------------------------------------------------------------------
%  Action: BUILD
% -----------------------------------------------------------------------------

%! action:process_default(+Mode, +Args, +Options) is det.
%
% The merge catch-all. Standalone builds the target, as emerge does
% with a bare package name. `--pretend` is handled by process_build/2
% and only prints. Other modes keep the prove-and-print merge path,
% including the client RPC.

action:process_default(standalone, Args, Options) :-
  !,
  action:process_build(Args, Options).
action:process_default(_Mode, Args, Options) :-
  action:process_action(run, Args, Options).



%! action:process_build(+Args, +Options) is det.
%
% Handles the --build CLI flag. Resolves targets, proves a plan, then
% builds with live progress output. `--pretend` prints that plan and
% does not execute it.

action:process_build([], Options) :-
  !,
  ignore(message:failure('No targets specified for --build.')),
  action:exit_on_invalid_targets(Options).

action:process_build(ArgsSets, Options) :-
  memberchk(pretend(true), Options),
  !,
  action:process_action(run, ArgsSets, Options).

action:process_build(ArgsSets, Options) :-
  eapi:substitute_sets(ArgsSets, Args),
  interface:report_unresolvable_targets(run, Args),
  findall(target(Q,Arg):run?{[]},
          ( member(Arg, Args),
            atom_codes(Arg, Codes),
            phrase(eapi:qualified_target(Q), Codes),
            interface:target_query_exists(Q),
            once(target:resolve_candidate(Q, _))
          ),
          Proposal),
  !,
  ( Proposal == []
  -> ignore(message:failure('No valid targets found.')),
     action:exit_on_invalid_targets(Options)
  ;  action:run_build_with_ci_guard(Proposal, Options),
     action:maybe_ci_exit_on_build_failure(Options)
  ).


%! action:process_unmerge(+Args, +Options) is det.
%
% `--unmerge` / `-C`. `--pretend` prints the uninstall plan. A
% standalone run without `--pretend` executes it, including the
% world-file unregister the plan carries. Other modes keep the
% prove-and-print path.

action:process_unmerge(Args, Options) :-
  ( memberchk(pretend(true), Options)
  ; interface:get_mode(Mode),
    Mode \== standalone
  ),
  !,
  action:process_action(uninstall, Args, Options).
action:process_unmerge([], Options) :-
  !,
  ignore(message:failure('No targets specified for --unmerge.')),
  action:exit_on_invalid_targets(Options).
action:process_unmerge(ArgsSets, Options) :-
  eapi:substitute_sets(ArgsSets, Args),
  interface:report_unresolvable_targets(uninstall, Args),
  action:build_proposal(uninstall, Args, Proposal),
  !,
  ( Proposal == []
  -> action:handle_empty_proposal(ArgsSets, Args, Options)
  ;  action:run_build_with_ci_guard(Proposal, Options),
     action:maybe_ci_exit_on_build_failure(Options)
  ).


%! action:run_build_with_ci_guard(+Proposal, +Options) is det.
%
% Runs `builder:build/1` with an exception guard. In `--ci` mode any
% uncaught exception is converted to exit status 3 so the silent-failure
% class of bug -- "pipeline exited 0 but the build clearly didn't
% finish" -- cannot escape via the uncaught-exception path either.
% Outside `--ci` the exception is re-raised so interactive users still
% see the full stack trace.

action:run_build_with_ci_guard(Proposal, Options) :-
  catch(builder:build(Proposal), Err, action:handle_build_exception(Err, Options)).


%! action:handle_build_exception(+Err, +Options) is det.
%
% In `--ci` mode: log the exception to stderr and end the request with
% exit status 3 so the pipeline exit code matches the "execution failed"
% semantics documented on `maybe_ci_exit_on_build_failure/1`. Outside
% `--ci`: rethrow so the interactive caller's debugger / top-level handler
% sees it unchanged. `halt/1` exceptions (`unwind(halt(_))`) and the
% request_exit(_) of interface:exit/1 are always rethrown so that an
% explicit exit inside builder:build/1 keeps its exit code.

action:handle_build_exception(Err, _Options) :-
  ( Err = unwind(halt(_)) ; Err = halt(_) ; Err = request_exit(_) ),
  !,
  throw(Err).

action:handle_build_exception(Err, Options) :-
  format(user_error, '[builder] exception during build: ~q~n', [Err]),
  ( memberchk(ci(true), Options)
  -> interface:exit(3)
  ;  throw(Err)
  ).


%! action:maybe_ci_exit_on_build_failure(+Options) is det.
%
% In `--ci` mode, propagate any sub-step build failure to the process
% exit code. Without this, a failed install/merge of a sub-dep is only
% reflected in the printed summary (`Failed: N`); the pipeline still
% exits 0 and downstream tooling cannot detect the problem.
%
% Exit codes:
%   - 0 : all actions completed successfully
%   - 3 : one or more actions failed (build/install/merge step failed
%         and execute_plan skipped the remainder).
%
% We deliberately use exit code 3 (not 1 or 2) to disambiguate from
% the prover-side codes that `--merge --ci` already produces:
%   - 0 : clean
%   - 1 : prover cycle-break assumptions
%   - 2 : domain assumptions
%   - 3 : at least one action failed during execution
%
% Only ends the request when both `--ci` is set AND `Failed > 0`.

action:maybe_ci_exit_on_build_failure(Options) :-
  ( memberchk(ci(true), Options),
    builder:last_build_status(_Completed, Failed, _Stubs),
    Failed > 0
  -> interface:exit(3)
  ;  true
  ).


%! action:exit_on_invalid_targets(+Options) is det.
%
% Surface "no valid targets resolved" as a hard failure exit code in CI
% mode. Without this, an unresolvable target falls back through predicate
% failure to the catch-all exit status 1 in interface:process_requests/1, which
% downstream comparison tooling that triages by exit code misinterprets
% as "OK(cycles)" (exit 1 normally means "build succeeded with prover
% cycle-break assumptions"). Outside --ci the predicate fails so the
% caller preserves its existing behaviour.

action:exit_on_invalid_targets(Options) :-
  ( memberchk(ci(true), Options)
  -> interface:exit(3)
  ;  fail
  ).
