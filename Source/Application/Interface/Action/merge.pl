/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

% -----------------------------------------------------------------------------
%  Action: MERGE
% -----------------------------------------------------------------------------

%! action:process_action(+Action, +Args, +Options) is det.
%
% Catch-all action dispatcher for merge/unmerge. `--fetchonly` / `-F`
% prove :run (same proposal) and set preference:local_flag(fetchonly).
% These clauses MUST appear after the specific info/search/depclean
% clauses (ensured by include order in action.pl).

action:process_action(_Action,[],Options) :-
  !,
  ignore(message:failure('No targets specified.')),
  action:exit_on_invalid_targets(Options).

action:process_action(Action,ArgsSets,Options) :-
  interface:get_mode(Mode),
  interface:process_server(Host,Port),
  ( memberchk(pretend(true), Options) -> PretendMode = true ; PretendMode = false ),
  eapi:substitute_sets(ArgsSets,Args),
  interface:report_unresolvable_targets(Action, Args),
  action:build_proposal(Action, Args, Proposal),
  !,
  message:log(['Proposal:  ',Proposal]),
  ( Proposal == []
  -> action:handle_empty_proposal(ArgsSets, Args, Options)
  ;  true
  ),
  action:dispatch_proposal(Mode, Host, Port, Proposal, Options, PretendMode).


% -----------------------------------------------------------------------------
%  Proposal construction
% -----------------------------------------------------------------------------

%! action:build_proposal(+Action, +Args, -Proposal) is det.
%
% Parses CLI atoms into prove targets. Instantiates each target's
% repository to the preferred visible candidate (overlay before tree)
% so prove does not bind the first cache hit (`portage`) and then
% keyword-relax it. Uninstall uses installed VDB candidates.

action:build_proposal(Action, Args, Proposal) :-
  findall(target(Q,Arg):Action?{[]},
          ( member(Arg,Args),
            atom_codes(Arg,Codes),
            phrase(eapi:qualified_target(Q),Codes),
            action:bind_proposal_target(Action, Q)
          ),
          Proposal).


%! action:bind_proposal_target(+Action, ?Q) is semidet.
%
% Resolves Q against the installed VDB for uninstall, otherwise
% against visible tree/overlay candidates.

action:bind_proposal_target(uninstall, Q) :-
  !,
  interface:target_query_installed(Q),
  once(target:resolve_installed_candidate(Q, _)).
action:bind_proposal_target(_Action, Q) :-
  interface:target_query_exists(Q),
  once(target:resolve_candidate(Q, _)).


%! action:handle_empty_proposal(+ArgsSets, +Args, +Options) is det.
%
% Empty computed sets are success (nothing to do), not a bad atom.
% Any other empty proposal is an invalid-target failure.

action:handle_empty_proposal(ArgsSets, Args, Options) :-
  ( action:empty_computed_set_message(ArgsSets, EmptyMsg) ->
      ignore(message:inform(EmptyMsg)),
      ( memberchk(ci(true), Options) -> interface:exit(0) ; true )
  ; ignore(( config:llm_support(Prompt),
             atomic_list_concat([Prompt|Args], Message),
             config:llm_default(Service),
             current_predicate(Service:Service/2),
             explainer:call_llm(Service, Message, _) )),
    ignore(message:failure('No valid targets found.')),
    action:exit_on_invalid_targets(Options)
  ).


% -----------------------------------------------------------------------------
%  Prove, print, and post-plan actions
% -----------------------------------------------------------------------------

%! action:dispatch_proposal(+Mode, +Host, +Port, +Proposal, +Options, +PretendMode) is det.
%
% Client mode RPCs prove+print to the server. Other modes prove locally.

action:dispatch_proposal(client, Host, Port, Proposal, _Options, _PretendMode) :-
  !,
  client:rpc_execute(Host, Port,
    ( pipeline:prove_plan_with_fallback(Proposal, ProofAVL, ModelAVL, Plan, Triggers, _FallbackUsed),
      printer:print(Proposal, ModelAVL, ProofAVL, Plan, Triggers)
    ),
    Output),
  writeln(Output).

action:dispatch_proposal(_Mode, _Host, _Port, Proposal, Options, PretendMode) :-
  action:run_local_proposal(Proposal, Options, PretendMode).


%! action:run_local_proposal(+Proposal, +Options, +PretendMode) is det.
%
% Proves and prints locally, honoring `--timeout`, then applies CI
% exit codes and world-file side effects.

action:run_local_proposal(Proposal, Options, PretendMode) :-
  ( memberchk(timeout(TimeLimitSec), Options) -> true ; TimeLimitSec = 0 ),
  ( TimeLimitSec =< 0 ->
      action:prove_print_proposal(Proposal, Options, PretendMode,
                                  ProofAVL, ModelAVL, Plan, FallbackUsed)
  ; catch(
      call_with_time_limit(TimeLimitSec,
        action:prove_print_proposal(Proposal, Options, PretendMode,
                                    ProofAVL, ModelAVL, Plan, FallbackUsed)),
      time_limit_exceeded,
      action:halt_with_error(' Time limit exceeded while proving/planning. Try increasing --timeout or narrowing the target.')
    )
  ),
  action:maybe_ci_halt(Options, ModelAVL, ProofAVL),
  action:maybe_execute_world(FallbackUsed, PretendMode, Plan).


%! action:prove_print_proposal(+Proposal, +Options, +PretendMode, -ProofAVL, -ModelAVL, -Plan, -FallbackUsed) is det.
%
% Proves a plan, prints it, and optionally runs variants/explain on
% `--pretend`. Halts on proof failure.

action:prove_print_proposal(Proposal, Options, PretendMode,
                            ProofAVL, ModelAVL, Plan, FallbackUsed) :-
  ( pipeline:prove_plan_with_fallback(Proposal, ProofAVL, ModelAVL, Plan, Triggers, FallbackUsed) ->
      true
  ; action:halt_with_error(' Proof/planning failed. Check that the target is valid and all dependencies exist.')
  ),
  printer:print(Proposal, ModelAVL, ProofAVL, Plan, Triggers),
  action:maybe_run_variants(Options, PretendMode, Proposal, ProofAVL, Plan, Triggers),
  action:maybe_run_explain(Options, PretendMode, Proposal, ProofAVL, ModelAVL, Plan, Triggers),
  choicelog:maybe_dump.


%! action:maybe_run_variants(+Options, +PretendMode, +Proposal, +ProofAVL, +Plan, +Triggers) is det.

action:maybe_run_variants(Options, PretendMode, Proposal, ProofAVL, Plan, Triggers) :-
  ( memberchk(variants(VariantsOpt), Options),
    VariantsOpt \== none,
    PretendMode == true
  -> run_variants(VariantsOpt, Proposal, ProofAVL, Plan, Triggers)
  ;  true
  ).


%! action:maybe_run_explain(+Options, +PretendMode, +Proposal, +ProofAVL, +ModelAVL, +Plan, +Triggers) is det.

action:maybe_run_explain(Options, PretendMode, Proposal, ProofAVL, ModelAVL, Plan, Triggers) :-
  ( memberchk(explain(ExplainOpt), Options),
    ExplainOpt \== none,
    PretendMode == true
  -> run_explain(ExplainOpt, Proposal, ProofAVL, ModelAVL, Plan, Triggers)
  ;  true
  ).


%! action:maybe_ci_halt(+Options, +ModelAVL, +ProofAVL) is det.
%
% In `--ci` mode, end the request with the assumption-derived exit code.

action:maybe_ci_halt(Options, ModelAVL, ProofAVL) :-
  ( memberchk(ci(true), Options) ->
      interface:ci_exit_code(ModelAVL, ProofAVL, ExitCode),
      interface:exit(ExitCode)
  ; true
  ).


%! action:maybe_execute_world(+FallbackUsed, +PretendMode, +Plan) is det.
%
% Applies world-file side effects only on a real (non-pretend) merge
% that did not fall through a fallback tier. `--fetchonly` / `-F` prove
% the same :run plan but must not write @world.

action:maybe_execute_world(false, false, Plan) :-
  \+ preference:flag(fetchonly),
  !,
  execute_world_plan(Plan),
  world:save.
action:maybe_execute_world(_, _, _).


%! action:halt_with_error(+Message) is det.
%
% Prints a red error bubble, dumps the choice log, and ends the request
% with exit status 1.

action:halt_with_error(Message) :-
  message:bubble(red,'Error'),
  message:color(red),
  message:print(Message), nl,
  message:color(normal),
  flush_output,
  choicelog:maybe_dump,
  interface:exit(1).


% -----------------------------------------------------------------------------
%  Side effects: execute planned world actions
% -----------------------------------------------------------------------------

%! action:execute_world_plan(+Plan) is det.
%
% Walks the plan (list of steps, each a list of rules) and executes any
% world(Atom):Action side effects (register/unregister packages in @world).

action:execute_world_plan([]) :- !.

action:execute_world_plan([Step|Rest]) :-
  execute_world_step(Step),
  execute_world_plan(Rest).

%! action:execute_world_step(+Step) is det.
%
% Processes a single plan step (list of rules), executing world
% side effects for any rule whose head is world(Atom):Action.

action:execute_world_step([]) :- !.

action:execute_world_step([Rule|Rest]) :-
  ( Rule = rule(Head,_Body),
    prover:canon_literal(Head, Core, Ctx0),
    Core = world(Atom):Action,
    memberchk(Action, [register, unregister]) ->
      ( is_list(Ctx0) -> Ctx = Ctx0 ; Ctx = [] ),
      builder:execute_world(Action, Atom, Ctx)
  ; true
  ),
  execute_world_step(Rest).


%! action:empty_computed_set_message(+ArgsSets, -Message) is semidet.
%
% True when the original CLI targets were only computed sets that may
% legitimately expand to nothing. Binds a user-facing inform message so
% an empty proposal is reported as an empty set, not a bad atom.

action:empty_computed_set_message(ArgsSets, Message) :-
  ArgsSets \== [],
  findall(Name, (member(A, ArgsSets), action:computed_set_arg(A, Name)), Names),
  Names \== [],
  length(ArgsSets, NArgs),
  length(Names, NArgs),
  action:empty_computed_set_text(Names, Message).


%! action:computed_set_arg(+Arg, -Name) is semidet.
%
% True when Arg is a `@name` / `name` reference to a known computed set.

action:computed_set_arg(Arg, Name) :-
  ( atom_concat('@', Name, Arg) -> true ; Name = Arg ),
  current_predicate(sets:is_computed_set/1),
  sets:is_computed_set(Name).


%! action:empty_computed_set_text(+Names, -Message) is det.
%
% Informational text for an empty computed-set expansion.

action:empty_computed_set_text(Names, Message) :-
  ( Names = [Name] ->
      ( memberchk(Name, [security, affected, 'new-affected', 'new-glsa']) ->
          format(atom(Message),
                 'No vulnerable packages requiring a GLSA upgrade (@~w is empty).',
                 [Name])
      ; Name == 'preserved-rebuild' ->
          Message = 'No packages consume preserved libraries (@preserved-rebuild is empty).'
      ; Name == 'changed-deps' ->
          Message = 'No installed packages have outdated runtime dependencies (@changed-deps is empty).'
      ; format(atom(Message), 'Computed set @~w is empty.', [Name])
      )
  ; atomic_list_concat(Names, ', @', Joined),
    format(atom(Message), 'Computed sets @~w are empty.', [Joined])
  ).


%! action:empty_security_set(+ArgsSets) is semidet.
%
% Backward-compatible alias: true when every CLI target is a GLSA
% security computed set.

action:empty_security_set(ArgsSets) :-
  ArgsSets \== [],
  forall(member(A, ArgsSets),
         ( action:computed_set_arg(A, Name),
           memberchk(Name, [security, affected, 'new-affected', 'new-glsa'])
         )).