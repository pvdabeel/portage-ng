/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> EXPLAIN
LLM-powered interactive explanation of build plans. Serializes proof
artifacts into a compact summary, sends the user's question alongside
the summary to the configured LLM service, and streams the answer.

Supports single-shot mode (question on the command line) and
conversational mode (interactive prompt for follow-up questions).

This module is loaded only when LLM support is available
(via load_modules/1 when the mode table says llm).
*/

:- module(explain, []).

% =============================================================================
%  EXPLAIN declarations
% =============================================================================


% -----------------------------------------------------------------------------
%  Single-shot explain
% -----------------------------------------------------------------------------

%! explain:explain_plan(+Question, +Proposal, +ProofAVL, +ModelAVL, +Plan, +TriggersAVL) is det.
%
% Sends a single question about the build plan to the configured LLM,
% with the full plan summary as context. Streams the answer to stdout.

explain:explain_plan(Question, Proposal, ProofAVL, ModelAVL, Plan, TriggersAVL) :-
  explain:build_context(Proposal, ProofAVL, ModelAVL, Plan, TriggersAVL, Context),
  atomic_list_concat([Context, '\n\nUser question: ', Question], Prompt),
  config:llm_default(Service),
  nl,
  explainer:call_llm(Service, Prompt, _Response),
  nl.


% -----------------------------------------------------------------------------
%  Conversational explain
% -----------------------------------------------------------------------------

%! explain:explain_plan_interactive(+Proposal, +ProofAVL, +ModelAVL, +Plan, +TriggersAVL) is det.
%
% Enters a conversational loop where the user can ask multiple
% questions about the build plan. Each question is sent with the
% full plan context. Type quit, exit, or Ctrl-D to leave.

explain:explain_plan_interactive(Proposal, ProofAVL, ModelAVL, Plan, TriggersAVL) :-
  explain:build_context(Proposal, ProofAVL, ModelAVL, Plan, TriggersAVL, Context),
  config:llm_default(Service),
  nl,
  message:color(cyan),
  format('Plan explainer ready. Ask questions about the build plan.~n'),
  format('Type "quit" or "exit" to leave.~n'),
  message:color(normal),
  nl,
  explain:conversation_loop(Service, Context).


%! explain:conversation_loop(+Service, +Context) is det.

explain:conversation_loop(Service, Context) :-
  message:color(green),
  format('explain> '),
  message:color(normal),
  flush_output,
  catch(
    read_line_to_string(user_input, Line),
    _,
    Line = end_of_file
  ),
  ( Line == end_of_file
  -> nl
  ; string_lower(Line, Lower),
    ( member(Lower, ["quit", "exit", "q"])
    -> true
    ; Line == ""
    -> explain:conversation_loop(Service, Context)
    ; atomic_list_concat([Context, '\n\nUser question: ', Line], Prompt),
      nl,
      explainer:call_llm(Service, Prompt, _Response),
      nl, nl,
      explain:conversation_loop(Service, Context)
    )
  ).


% -----------------------------------------------------------------------------
%  Plan context assembly
% -----------------------------------------------------------------------------

%! explain:build_context(+Proposal, +ProofAVL, +ModelAVL, +Plan, +TriggersAVL, -Context) is det.
%
% Assembles a compact text summary of the entire build plan, suitable
% as LLM context. Includes targets, plan entries with actions and USE
% flags, dependency chains, and assumptions.

explain:build_context(Proposal, ProofAVL, ModelAVL, Plan, TriggersAVL, Context) :-
  explain:format_header(Header),
  explain:format_targets(Proposal, TargetsText),
  explain:format_plan_entries(Plan, ProofAVL, TriggersAVL, Proposal, EntriesText),
  explain:format_assumptions(ProofAVL, ModelAVL, AssumptionsText),
  atomic_list_concat([Header, '\n\n', TargetsText, '\n\n', EntriesText, '\n\n', AssumptionsText], Context).


%! explain:format_header(-Header) is det.

explain:format_header(Header) :-
  Header = 'You are analyzing a build plan from portage-ng, a Prolog-based dependency resolver for Gentoo Linux. \c
Below is a structured summary of the build plan including all packages, their actions, USE flags, \c
dependency relationships, and any assumptions made during resolution. \c
Answer the user\'s question concisely using this data. Use plain language. \c
When referring to packages, use the Category/Name format (e.g. dev-libs/openssl). \c
When explaining dependencies, describe the chain from the requested target to the package in question.\n\n\c
USE flag annotation guide:\n\c
  flag* = set by user in make.conf (global preference)\n\c
  flag% = forced or masked by the Gentoo profile\n\c
  flag%* = both profile-forced and user-set\n\c
  -flag = disabled\n\c
  (flag) = forced by profile package.use.force\n\c
  (-flag) = masked by profile package.use.mask\n\c
  USE changes in parentheses indicate flags assumed or changed by the resolver during dependency resolution.'.


%! explain:format_targets(+Proposal, -Text) is det.

explain:format_targets(Proposal, Text) :-
  findall(TargetStr,
    ( member(Goal, Proposal),
      explain:goal_to_target_str(Goal, TargetStr)
    ),
    TargetStrs),
  ( TargetStrs == []
  -> Text = 'Requested targets: (none)'
  ;  atomic_list_concat(TargetStrs, ', ', Joined),
     atomic_list_concat(['Requested targets: ', Joined], Text)
  ).


%! explain:goal_to_target_str(+Goal, -Str) is det.

explain:goal_to_target_str(target(_Q, Arg):_Action?{_Ctx}, Str) :-
  !,
  format(atom(Str), '~w', [Arg]).
explain:goal_to_target_str(Goal, Str) :-
  format(atom(Str), '~w', [Goal]).


% -----------------------------------------------------------------------------
%  Plan entry formatting
% -----------------------------------------------------------------------------

%! explain:format_plan_entries(+Plan, +ProofAVL, +TriggersAVL, +Proposal, -Text) is det.

explain:format_plan_entries(Plan, ProofAVL, TriggersAVL, Proposal, Text) :-
  explain:collect_plan_rules(Plan, 1, Rules),
  maplist(explain:format_one_entry(ProofAVL, TriggersAVL, Proposal), Rules, EntryTexts),
  ( EntryTexts == []
  -> Text = 'Build plan: (empty)'
  ;  atomic_list_concat(['Build plan:\n' | EntryTexts], Text)
  ).


%! explain:collect_plan_rules(+Plan, +StepN, -Rules) is det.
%
% Flattens the wave-structured plan into a list of step(N, Rule) terms.

explain:collect_plan_rules([], _, []).

explain:collect_plan_rules([Wave|Rest], N, Rules) :-
  ( is_list(Wave)
  -> findall(step(N, R), member(R, Wave), WaveRules)
  ;  WaveRules = [step(N, Wave)]
  ),
  N1 is N + 1,
  explain:collect_plan_rules(Rest, N1, RestRules),
  append(WaveRules, RestRules, Rules).


%! explain:format_one_entry(+ProofAVL, +TriggersAVL, +Proposal, +StepRule, -Text) is det.

explain:format_one_entry(ProofAVL, TriggersAVL, Proposal, step(Step, Rule), Text) :-
  ( explain:extract_rule_info(Rule, Repo, Entry, Action, Ctx)
  -> ( cache:ordered_entry(Repo, Entry, C, N, Ver)
     -> version_domain:display_atom(Ver, VerStr),
        explain:format_use_flags(Repo, Entry, UseStr),
        explain:format_use_expand(Repo, Entry, UseExpandStr),
        explain:format_ctx_use_info(Ctx, CtxUseStr),
        explain:format_slot(Repo, Entry, SlotStr),
        explain:format_deps(ProofAVL, Repo, Entry, Action, DepsStr),
        explain:format_dep_path(TriggersAVL, Proposal, Repo, Entry, Action, PathStr),
        explain:format_ctx_info(Ctx, CtxStr),
        atomic_list_concat([
          '  [Step ', Step, '] ', C, '/', N, '-', VerStr,
          ' [', Action, ']',
          SlotStr, UseStr, UseExpandStr, CtxUseStr, '\n',
          DepsStr, PathStr, CtxStr
        ], Text)
     ;  format(atom(Text), '  [Step ~w] ~w://~w [~w]~n', [Step, Repo, Entry, Action])
     )
  ;  Rule = rule(world(Atom):Action?{_}, _)
  -> format(atom(Text), '  [Step ~w] @world: ~w ~w~n', [Step, Action, Atom])
  ;  Text = ''
  ).


%! explain:extract_rule_info(+Rule, -Repo, -Entry, -Action, -Ctx) is semidet.

explain:extract_rule_info(rule(Repo://Entry:Action?{Ctx}, _Body), Repo, Entry, Action, Ctx).
explain:extract_rule_info(assumed(rule(Repo://Entry:Action?{Ctx}, _Body)), Repo, Entry, Action, Ctx).
explain:extract_rule_info(rule(assumed(Repo://Entry:Action?{Ctx}), _Body), Repo, Entry, Action, Ctx).


%! explain:format_use_flags(+Repo, +Entry, -Str) is det.
%
% Formats USE flags with annotations matching the plan printer:
% * = set by user in make.conf, % = profile forced/masked

explain:format_use_flags(Repo, Entry, Str) :-
  findall(Token,
    ( query:search(iuse_filtered(Flag, State:Reason), Repo://Entry),
      explain:format_one_flag(Flag, State, Reason, Token)
    ),
    Tokens),
  ( Tokens == []
  -> Str = ''
  ;  atomic_list_concat(Tokens, ' ', FlagList),
     atomic_list_concat([' USE="', FlagList, '"'], Str)
  ).


%! explain:format_one_flag(+Flag, +State, +Reason, -Token) is det.
%
% Renders a single USE flag with annotations.

explain:format_one_flag(Flag, positive, preference, Token) :-
  preference:global_use(Flag, env), !,
  ( preference:profile_forced_use_flag(Flag)
  -> format(atom(Token), '~w%*', [Flag])
  ;  format(atom(Token), '~w*', [Flag])
  ).

explain:format_one_flag(Flag, positive, profile_package_use_force, Token) :-
  !, format(atom(Token), '(~w)', [Flag]).

explain:format_one_flag(Flag, positive, preference, Token) :-
  !,
  ( preference:profile_forced_use_flag(Flag)
  -> format(atom(Token), '~w%', [Flag])
  ;  atom_string(Flag, Token)
  ).

explain:format_one_flag(Flag, positive, package_use, Token) :-
  !, atom_string(Flag, Token).

explain:format_one_flag(Flag, positive, ebuild, Token) :-
  !, atom_string(Flag, Token).

explain:format_one_flag(Flag, negative, preference, Token) :-
  preference:global_use(minus(Flag), env), !,
  ( preference:profile_masked_use_flag(Flag)
  -> format(atom(Token), '-~w%*', [Flag])
  ;  format(atom(Token), '-~w*', [Flag])
  ).

explain:format_one_flag(Flag, negative, profile_package_use_mask, Token) :-
  !, format(atom(Token), '(-~w)', [Flag]).

explain:format_one_flag(Flag, negative, preference, Token) :-
  !,
  ( preference:profile_masked_use_flag(Flag)
  -> format(atom(Token), '-~w%', [Flag])
  ;  format(atom(Token), '-~w', [Flag])
  ).

explain:format_one_flag(Flag, negative, _, Token) :-
  format(atom(Token), '-~w', [Flag]).

explain:format_one_flag(Flag, positive, _, Token) :-
  atom_string(Flag, Token).


%! explain:format_use_expand(+Repo, +Entry, -Str) is det.
%
% Formats USE_EXPAND flags (e.g. PYTHON_TARGETS, PERL_FEATURES).

explain:format_use_expand(Repo, Entry, Str) :-
  findall(Key-Tokens,
    ( eapi:use_expand(Key),
      findall(Token,
        ( cache:entry_metadata(Repo, Entry, iuse, Arg),
          eapi:use_flag_name(Arg, ArgB),
          eapi:check_prefix_atom(Key, ArgB),
          eapi:strip_prefix_atom(Key, ArgB, Value),
          eapi:categorize_use_for_entry(Arg, Repo://Entry, State, _Reason),
          ( State == positive -> atom_string(Value, Token)
          ; format(atom(Token), '-~w', [Value])
          )
        ),
        Tokens),
      Tokens \== []
    ),
    Groups),
  ( Groups == []
  -> Str = ''
  ;  findall(GroupStr,
       ( member(Key-Tokens, Groups),
         atomic_list_concat(Tokens, ' ', FlagStr),
         format(atom(GroupStr), ' ~w="~w"', [Key, FlagStr])
       ),
       GroupStrs),
     atomic_list_concat(GroupStrs, Str)
  ).


%! explain:format_ctx_use_info(+Ctx, -Str) is det.
%
% Extracts USE flag changes from the proof context (build_with_use,
% required_use assumptions, and use_change suggestions).

explain:format_ctx_use_info(Ctx, Str) :-
  ( is_list(Ctx)
  -> findall(Token,
       ( member(Term, Ctx),
         ( Term = build_with_use(Uses) ; Term = required_use(Uses) ),
         member(assumed(Flag), Uses),
         atom(Flag),
         atom_string(Flag, Token)
       ),
       AssumedPos),
     findall(Token,
       ( member(Term, Ctx),
         ( Term = build_with_use(Uses) ; Term = required_use(Uses) ),
         member(assumed(minus(Flag)), Uses),
         format(atom(Token), '-~w', [Flag])
       ),
       AssumedNeg),
     ( memberchk(suggestion(use_change, _, Changes), Ctx)
     -> findall(Token,
          ( member(use_change(F, Dir), Changes),
            ( Dir == enable -> atom_string(F, Token)
            ; format(atom(Token), '-~w', [F])
            )
          ),
          ChangeTokens)
     ;  ChangeTokens = []
     ),
     append([AssumedPos, AssumedNeg, ChangeTokens], AllTokens),
     ( AllTokens == []
     -> Str = ''
     ;  atomic_list_concat(AllTokens, ' ', FlagStr),
        atomic_list_concat([' (USE changes: ', FlagStr, ')'], Str)
     )
  ;  Str = ''
  ).


%! explain:format_slot(+Repo, +Entry, -Str) is det.

explain:format_slot(Repo, Entry, Str) :-
  ( query:search(slot(Slot), Repo://Entry)
  -> ( Slot == '0'
     -> Str = ''
     ;  atomic_list_concat([' SLOT=', Slot], Str)
     )
  ;  Str = ''
  ).


%! explain:format_deps(+ProofAVL, +Repo, +Entry, +Action, -Str) is det.
%
% Formats the direct dependencies from the proof body.

explain:format_deps(ProofAVL, Repo, Entry, Action, Str) :-
  Lit = Repo://Entry:Action,
  ( explainer:proof_lookup(ProofAVL, Lit, _Key, dep(_Count, Body), _Ctx)
  -> explain:body_to_dep_strs(Body, DepStrs),
     ( DepStrs == []
     -> Str = ''
     ;  atomic_list_concat(DepStrs, ', ', DepList),
        atomic_list_concat(['    Depends on: ', DepList, '\n'], Str)
     )
  ;  Str = ''
  ).


%! explain:body_to_dep_strs(+Body, -Strs) is det.

explain:body_to_dep_strs(Body, Strs) :-
  ( is_list(Body)
  -> findall(S,
       ( member(Dep, Body),
         explain:dep_to_str(Dep, S)
       ),
       Strs)
  ;  Strs = []
  ).


%! explain:dep_to_str(+Dep, -Str) is semidet.

explain:dep_to_str(Dep, Str) :-
  prover:canon_literal(Dep, Core, _),
  Core = Repo://Entry:Action,
  cache:ordered_entry(Repo, Entry, C, N, Ver),
  version_domain:display_atom(Ver, VerStr),
  format(atom(Str), '~w/~w-~w[:~w]', [C, N, VerStr, Action]).

explain:dep_to_str(Dep, Str) :-
  prover:canon_literal(Dep, Core, _),
  Core = Repo://Entry,
  cache:ordered_entry(Repo, Entry, C, N, Ver),
  version_domain:display_atom(Ver, VerStr),
  format(atom(Str), '~w/~w-~w', [C, N, VerStr]).


%! explain:format_dep_path(+TriggersAVL, +Proposal, +Repo, +Entry, +Action, -Str) is det.
%
% Formats the reverse dependency path from the entry back to a root target.

explain:format_dep_path(TriggersAVL, Proposal, Repo, Entry, Action, Str) :-
  Lit = Repo://Entry:Action,
  maplist(explainer:canon_only, Proposal, ProposalKeys0),
  sort(ProposalKeys0, ProposalKeys),
  ( memberchk(Lit, ProposalKeys)
  -> Str = '    Reason: directly requested by user\n'
  ; explainer:path_to_any_root(Lit, ProposalKeys, TriggersAVL, Path)
  -> explain:path_to_str(Path, PathStr),
     atomic_list_concat(['    Required by: ', PathStr, '\n'], Str)
  ; explainer:any_dependent(Lit, TriggersAVL, Dep0)
  -> prover:canon_literal(Dep0, DepCore, _),
     ( DepCore = DR://DE:DA,
       cache:ordered_entry(DR, DE, DC, DN, _)
     -> format(atom(DepStr), '~w/~w[:~w]', [DC, DN, DA])
     ;  format(atom(DepStr), '~w', [DepCore])
     ),
     atomic_list_concat(['    Needed by: ', DepStr, '\n'], Str)
  ;  Str = ''
  ).


%! explain:path_to_str(+Path, -Str) is det.

explain:path_to_str(Path, Str) :-
  maplist(explain:lit_to_cn, Path, CNs),
  atomic_list_concat(CNs, ' -> ', Str).


%! explain:lit_to_cn(+Lit, -CN) is det.

explain:lit_to_cn(Lit, CN) :-
  ( Lit = Repo://Entry:_Action,
    cache:ordered_entry(Repo, Entry, C, N, _)
  -> format(atom(CN), '~w/~w', [C, N])
  ;  Lit = Repo://Entry,
    cache:ordered_entry(Repo, Entry, C, N, _)
  -> format(atom(CN), '~w/~w', [C, N])
  ;  format(atom(CN), '~w', [Lit])
  ).


%! explain:format_ctx_info(+Ctx, -Str) is det.
%
% Extracts relevant context info (replaces, suggestions) for display.

explain:format_ctx_info(Ctx, Str) :-
  ( is_list(Ctx)
  -> ( memberchk(replaces(OldRepo://OldEntry), Ctx),
       cache:ordered_entry(OldRepo, OldEntry, OC, ON, OVer),
       version_domain:display_atom(OVer, OVerStr)
     -> format(atom(Str), '    Replaces: ~w/~w-~w~n', [OC, ON, OVerStr])
     ;  Str = ''
     )
  ;  Str = ''
  ).


% -----------------------------------------------------------------------------
%  Assumption formatting
% -----------------------------------------------------------------------------

%! explain:format_assumptions(+ProofAVL, +ModelAVL, -Text) is det.

explain:format_assumptions(ProofAVL, ModelAVL, Text) :-
  findall(assumption(Key, Type, Reason),
    ( assoc_to_keys(ProofAVL, ProofKeys),
      member(Key, ProofKeys),
      explainer:assumption_content_from_proof_key(Key, Wrapped),
      explainer:assumption_normalize(Wrapped, Normalized),
      ( Normalized = domain(Content) -> Type = domain
      ; Normalized = cycle_break(Content) -> Type = cycle_break
      ; Content = Normalized, Type = other
      ),
      ( explainer:why_assumption(ModelAVL, ProofAVL, Key, _AssType, why_assumption(_, _, _, reason(R)))
      -> Reason = R
      ;  Reason = none
      )
    ),
    Assumptions),
  ( Assumptions == []
  -> Text = 'Assumptions: none (clean resolution)'
  ;  maplist(explain:format_one_assumption, Assumptions, ATexts),
     atomic_list_concat(['Assumptions:\n' | ATexts], Text)
  ).


%! explain:format_one_assumption(+Assumption, -Text) is det.

explain:format_one_assumption(assumption(Key, Type, Reason), Text) :-
  ( Type == domain -> TypeStr = 'domain assumption'
  ; Type == cycle_break -> TypeStr = 'cycle-break'
  ; TypeStr = 'other'
  ),
  format(atom(Text), '  [~w] ~w (reason: ~w)~n', [TypeStr, Key, Reason]).


% -----------------------------------------------------------------------------
%  Metacircular context helpers (shared with metacircular.pl)
% -----------------------------------------------------------------------------

%! explain:format_assumptions_with_polarity(+ProofAVL, +ModelAVL, -Text) is det.
%
% Like format_assumptions/3 but tags each domain assumption as positive
% (actionable config change) or negative (blocking).

explain:format_assumptions_with_polarity(ProofAVL, ModelAVL, Text) :-
  findall(assumption(Key, Type, Reason, Polarity),
    ( assoc_to_keys(ProofAVL, ProofKeys),
      member(Key, ProofKeys),
      explainer:assumption_content_from_proof_key(Key, Wrapped),
      explainer:assumption_normalize(Wrapped, Normalized),
      ( Normalized = domain(Content) -> Type = domain
      ; Normalized = cycle_break(Content) -> Type = cycle_break
      ; Content = Normalized, Type = other
      ),
      ( explainer:why_assumption(ModelAVL, ProofAVL, Key, _AssType, why_assumption(_, _, _, reason(R)))
      -> Reason = R
      ;  Reason = none
      ),
      explain:assumption_polarity(Type, Content, Reason, Polarity)
    ),
    Assumptions),
  ( Assumptions == []
  -> Text = 'Assumptions (polarity): none (clean resolution)'
  ;  maplist(explain:format_one_polarity_assumption, Assumptions, ATexts),
     atomic_list_concat(['Assumptions (polarity):\n' | ATexts], Text)
  ).


%! explain:assumption_polarity(+Type, +Content, +Reason, -Polarity) is det.

explain:assumption_polarity(cycle_break, _, _, cycle) :- !.
explain:assumption_polarity(_, Content, Reason, Polarity) :-
  ( catch(assumption:assumption_type(Content, AType), _, fail)
  -> true
  ;  ( Reason == none -> AType = other ; assumption:assumption_reason_type(Reason, AType) -> true ; AType = other )
  ),
  explain:polarity_of_type(AType, Polarity).


%! explain:polarity_of_type(+AssumptionType, -Polarity) is det.

explain:polarity_of_type(masked, positive) :- !.
explain:polarity_of_type(masked_dependency, positive) :- !.
explain:polarity_of_type(keyword_filtered, positive) :- !.
explain:polarity_of_type(keyword_filtered_dependency, positive) :- !.
explain:polarity_of_type(blocker_assumption, positive) :- !.
explain:polarity_of_type(license, positive) :- !.
explain:polarity_of_type(non_existent_dependency, negative) :- !.
explain:polarity_of_type(missing_dependency, negative) :- !.
explain:polarity_of_type(required_use_violation, negative) :- !.
explain:polarity_of_type(slot_conflict, negative) :- !.
explain:polarity_of_type(version_no_candidate, negative) :- !.
explain:polarity_of_type(version_no_candidate_dependency, negative) :- !.
explain:polarity_of_type(version_conflict, negative) :- !.
explain:polarity_of_type(version_conflict_dependency, negative) :- !.
explain:polarity_of_type(unsatisfied_constraints, negative) :- !.
explain:polarity_of_type(issue_with_model, negative) :- !.
explain:polarity_of_type(_, other).


%! explain:format_one_polarity_assumption(+Assumption, -Text) is det.

explain:format_one_polarity_assumption(assumption(Key, Type, Reason, Polarity), Text) :-
  format(atom(Text), '  [~w/~w] ~w (reason: ~w)~n', [Type, Polarity, Key, Reason]).


%! explain:format_fallback(+FallbackUsed, -Text) is det.

explain:format_fallback(FallbackUsed, Text) :-
  ( var(FallbackUsed) ; FallbackUsed == unknown
  -> Text = 'Fallback tier: (unknown)'
  ;  format(atom(Text), 'Fallback tier: ~w', [FallbackUsed])
  ).


%! explain:format_feedback_backlog(-Text) is det.

explain:format_feedback_backlog(Text) :-
  findall(Line,
    ( feedback:unresolved_diagnostic(Symbol, Evidence),
      format(atom(Line), '  unresolved ~w :: ~w~n', [Symbol, Evidence])
    ),
    Unresolved),
  findall(Line,
    ( feedback:discovered_dep(T, P, K, _),
      format(atom(Line), '  discovered_dep ~w -> ~w (~w)~n', [T, P, K])
    ),
    Deps),
  findall(Line,
    ( feedback:discovered_usedep(T, P, U, _),
      format(atom(Line), '  discovered_usedep ~w -> ~w ~w~n', [T, P, U])
    ),
    UseDeps),
  append([Unresolved, Deps, UseDeps], All),
  ( All == []
  -> Text = 'Feedback store: (empty)'
  ;  atomic_list_concat(['Feedback store:\n' | All], Text)
  ).


%! explain:format_learned_domains_for_target(+Target, -Text) is det.
%
% Compact prover:learned / cn_domain summary for the failing package CN.

explain:format_learned_domains_for_target(Repo://Entry, Text) :-
  !,
  ( cache:ordered_entry(Repo, Entry, C, N, _)
  -> ( cache:entry_metadata(Repo, Entry, slot, slot(Slot0))
     -> Slot = Slot0
     ;  Slot = '0'
     ),
     Lit = cn_domain(C, N, Slot),
     ( catch(prover:learned(Lit, Constraint), _, fail)
     -> format(atom(Text), 'Learned cn_domain for ~w/~w:~w = ~w', [C, N, Slot, Constraint])
     ;  format(atom(Text), 'Learned cn_domain for ~w/~w:~w: (none)', [C, N, Slot])
     )
  ;  Text = 'Learned cn_domain: (target not in cache)'
  ).
explain:format_learned_domains_for_target(_, 'Learned cn_domain: (n/a)').


%! explain:format_failure_focus(+Target, +Phase, +LogPath, +Reason, -Text) is det.

explain:format_failure_focus(Target, Phase, LogPath, Reason, Text) :-
  format(atom(Text),
         'Failure focus:\n  target: ~w\n  phase: ~w\n  reason: ~w\n  log: ~w',
         [Target, Phase, Reason, LogPath]).


%! explain:format_log_tail(+LogPath, -Text) is det.
%
% Bounded tail of the build log for LLM context.

explain:format_log_tail(LogPath, Text) :-
  ( catch(config:llm_metacircular_log_tail(Max), _, fail), integer(Max)
  -> true
  ;  Max = 12000
  ),
  ( exists_file(LogPath)
  -> catch(
       ( size_file(LogPath, Size),
         ( Size =< Max
         -> Offset = 0
         ;  Offset is Size - Max
         ),
         setup_call_cleanup(
           open(LogPath, read, S),
           ( ( Offset > 0 -> seek(S, Offset, bof, _) ; true ),
             read_string(S, _, Tail)
           ),
           close(S)),
         atomic_list_concat(['Build log tail:\n', Tail], Text)
       ),
       _,
       Text = 'Build log tail: (unreadable)')
  ;  Text = 'Build log tail: (file missing)'
  ).