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
% Catch-all action dispatcher for merge/unmerge/fetchonly.
% These clauses MUST appear after the specific info/search/depclean
% clauses (ensured by include order in action.pl).

action:process_action(_Action,[],_) :-
  !,
  message:failure('No targets specified.').

action:process_action(Action,ArgsSets,Options) :-
  interface:process_mode(Mode),
  interface:process_server(Host,Port),
  ( memberchk(pretend(true), Options) -> PretendMode = true ; PretendMode = false ),
  eapi:substitute_sets(ArgsSets,Args),
  interface:report_unresolvable_targets(Action, Args),
  findall(target(Q,Arg):Action?{[]},
          ( member(Arg,Args),
            atom_codes(Arg,Codes),
            phrase(eapi:qualified_target(Q),Codes),
            ( Action == uninstall
              -> once((kb:query(Q, R0://E0), kb:query(installed(true), R0://E0)))
              ;  once(kb:query(Q, _R://_E))
            )
          ),
          Proposal),!,
  message:log(['Proposal:  ',Proposal]),
  (Proposal == []
   -> ( config:llm_support(Prompt),
        atomic_list_concat([Prompt|Args],Message),
        config:llm_default(Service),
        explainer:call_llm(Service, Message, _),
        fail )
   ;  true),
  (Mode == 'client' ->
    (client:rpc_execute(Host,Port,
     (pipeline:prove_plan_with_fallback(Proposal, ProofAVL, ModelAVL, Plan, Triggers),
      printer:print(Proposal,ModelAVL,ProofAVL,Plan,Triggers)),
     Output),
     writeln(Output));
    ( ( memberchk(timeout(TimeLimitSec), Options) -> true ; TimeLimitSec = 0 ),
      ( memberchk(variants(VariantsOpt), Options) -> true ; VariantsOpt = none ),
      ( memberchk(explain(ExplainOpt), Options) -> true ; ExplainOpt = none ),
      ( TimeLimitSec =< 0 ->
          ( ( pipeline:prove_plan_with_fallback(Proposal, ProofAVL, ModelAVL, Plan, Triggers, FallbackUsed) ->
                true
            ; message:bubble(red,'Error'),
              message:color(red),
              message:print(' Proof/planning failed. Check that the target is valid and all dependencies exist.'), nl,
              message:color(normal),
              flush_output,
              halt(1)
            ),
            printer:print(Proposal,ModelAVL,ProofAVL,Plan,Triggers),
            ( VariantsOpt \== none, PretendMode == true
            -> run_variants(VariantsOpt, Proposal, ProofAVL, Plan, Triggers)
            ;  true
            ),
            ( ExplainOpt \== none, PretendMode == true
            -> run_explain(ExplainOpt, Proposal, ProofAVL, ModelAVL, Plan, Triggers)
            ;  true
            )
          )
      ; catch(
          call_with_time_limit(TimeLimitSec,
            ( ( pipeline:prove_plan_with_fallback(Proposal, ProofAVL, ModelAVL, Plan, Triggers, FallbackUsed) ->
                  true
              ; message:bubble(red,'Error'),
                message:color(red),
                message:print(' Proof/planning failed. Check that the target is valid and all dependencies exist.'), nl,
                message:color(normal),
                flush_output,
                halt(1)
              ),
              printer:print(Proposal,ModelAVL,ProofAVL,Plan,Triggers),
              ( VariantsOpt \== none, PretendMode == true
              -> run_variants(VariantsOpt, Proposal, ProofAVL, Plan, Triggers)
              ;  true
              ),
              ( ExplainOpt \== none, PretendMode == true
              -> run_explain(ExplainOpt, Proposal, ProofAVL, ModelAVL, Plan, Triggers)
              ;  true
              )
            )),
          time_limit_exceeded,
          ( message:bubble(red,'Error'),
            message:color(red),
            message:print(' Time limit exceeded while proving/planning. Try increasing --timeout or narrowing the target.'), nl,
            message:color(normal),
            flush_output,
            halt(1)
          )
        )
      ),
      ( memberchk(ci(true), Options) ->
          interface:ci_exit_code(ModelAVL, ProofAVL, ExitCode),
          halt(ExitCode)
      ; true
      ),
      ( FallbackUsed == false,
        PretendMode == false ->
            execute_world_plan(Plan),
            world:save
        ; true
        )
    )).


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
    prover:canon_literal(Head, Core, _Ctx),
    Core = world(Atom):Action ->
      ( Action == register ->
          world:register(Atom)
      ; Action == unregister ->
          world:unregister(Atom)
      ; true
      )
  ; true
  ),
  execute_world_step(Rest).