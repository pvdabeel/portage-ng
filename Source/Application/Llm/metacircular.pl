/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> METACIRCULAR
LLM metacircular self-repair: diagnose unresolved build failures, propose
feedback:* learning (or draft fixup sketches), and apply only after human
confirmation so the existing builder replan loop can re-derive the plan.
*/

:- module(metacircular, []).

% =============================================================================
%  METACIRCULAR declarations
% =============================================================================

:- multifile fixup:mechanism/1.
:- multifile fixup:mechanism_note/3.

fixup:mechanism(metacircular).

fixup:mechanism_note(metacircular, Count, [Line]) :-
  format(atom(Line),
         'Metacircular LLM feedback applied (~d); plan re-derived after confirm',
         [Count]).


% -----------------------------------------------------------------------------
%  Interactive availability
% -----------------------------------------------------------------------------

%! metacircular:interactive_available is semidet.
%
% True when metacircular diagnose may prompt the user: kill-switch on,
% not `--ci`, and stdin is a TTY.

metacircular:interactive_available :-
  catch(config:llm_metacircular(true), _, fail),
  \+ catch(config:cli_ci(true), _, fail),
  stream_property(user_input, tty(true)).


%! metacircular:llm_backend_available is semidet.
%
% True when a configured LLM backend predicate is loaded (LLM modules
% were loaded and the default service implements Service/2).

metacircular:llm_backend_available :-
  catch(config:load_llm_modules(true), _, fail),
  config:llm_default(Service),
  atom(Service),
  current_predicate(Service:Service/2).


% -----------------------------------------------------------------------------
%  Builder entry: diagnose after a failed pass with no new discoveries
% -----------------------------------------------------------------------------

%! metacircular:diagnose_after_build(+Goals, +ProofAVL, +ModelAVL, +Plan, +TriggersAVL, +FallbackUsed, -AppliedCount) is det.
%
% For each recorded failed entry, ask the LLM for a repair_proposal/1,
% confirm actions with the user, and apply accepted feedback records.
% AppliedCount is the number of feedback-mutating actions accepted
% (draft_fixup sketches do not count toward replan). When LLM modules
% are not loaded or the session is non-interactive, AppliedCount is 0.

metacircular:diagnose_after_build(Goals, ProofAVL, ModelAVL, Plan, TriggersAVL, FallbackUsed, AppliedCount) :-
  ( metacircular:interactive_available,
    metacircular:llm_backend_available
  -> findall(failinfo(Target, Reason, LogPath),
             builder:last_failed(Target, Reason, LogPath),
             Fails0),
     sort(Fails0, Fails),
     ( Fails == []
     -> AppliedCount = 0
     ;  Ctx = ctx(Goals, ProofAVL, ModelAVL, Plan, TriggersAVL, FallbackUsed),
        metacircular:diagnose_failures(Fails, Ctx, 0, AppliedCount)
     )
  ;  AppliedCount = 0
  ).


%! metacircular:diagnose_failures(+Fails, +Ctx, +Acc, -Applied) is det.

metacircular:diagnose_failures([], _, Acc, Acc).
metacircular:diagnose_failures([failinfo(Target, Reason, LogPath)|Rest], Ctx, Acc0, Applied) :-
  metacircular:diagnose_failure(Target, unknown, LogPath, Reason, Ctx, N),
  Acc1 is Acc0 + N,
  metacircular:diagnose_failures(Rest, Ctx, Acc1, Applied).


%! metacircular:diagnose_failure(+Target, +Phase, +LogPath, +Reason, +Ctx, -Applied) is det.
%
% Assembles context, calls the LLM, parses/validates a repair_proposal/1,
% and confirms/applies actions. Applied is the count of feedback writes.

metacircular:diagnose_failure(Target, Phase, LogPath, Reason, Ctx, Applied) :-
  nl,
  message:color(cyan),
  format('>>> Metacircular diagnose: ~w (log ~w)~n', [Target, LogPath]),
  message:color(normal),
  ( metacircular:assemble_context(Target, Phase, LogPath, Reason, Ctx, Prompt)
  -> config:llm_default(Service),
     catch(explainer:call_llm(Service, Prompt, Response), _, Response = ''),
     ( Response == ''
     -> message:warning('Metacircular diagnose: empty LLM response.'),
        Applied = 0
     ;  ( metacircular:parse_proposal(Response, Actions0)
        -> metacircular:validate_actions(Actions0, Actions),
           ( Actions == []
           -> message:inform('Metacircular diagnose: no valid actions in proposal.'),
              Applied = 0
           ;  metacircular:confirm_and_apply(Actions, Applied)
           )
        ;  message:warning('Metacircular diagnose: could not parse repair_proposal/1 from LLM response.'),
           Applied = 0
        )
     )
  ;  Applied = 0
  ).


% -----------------------------------------------------------------------------
%  Context assembly
% -----------------------------------------------------------------------------

%! metacircular:assemble_context(+Target, +Phase, +LogPath, +Reason, +Ctx, -Prompt) is det.

metacircular:assemble_context(Target, Phase, LogPath, Reason,
                              ctx(Goals, ProofAVL, ModelAVL, Plan, TriggersAVL, FallbackUsed),
                              Prompt) :-
  ( config:llm_capability(metacircular, MetaCap) -> true ; MetaCap = '' ),
  explain:build_context(Goals, ProofAVL, ModelAVL, Plan, TriggersAVL, PlanCtx),
  explain:format_fallback(FallbackUsed, FallbackText),
  explain:format_assumptions_with_polarity(ProofAVL, ModelAVL, AssumpText),
  explain:format_feedback_backlog(FeedbackText),
  explain:format_learned_domains_for_target(Target, LearnedText),
  explain:format_failure_focus(Target, Phase, LogPath, Reason, FailText),
  explain:format_log_tail(LogPath, LogText),
  ( llmknowledge:topic(learning, LearningText) -> true ; LearningText = '' ),
  ( llmknowledge:topic(code_map, CodeMapText) -> true ; CodeMapText = '' ),
  atomic_list_concat([
    MetaCap, '\n\n',
    LearningText, '\n\n',
    CodeMapText, '\n\n',
    FailText, '\n',
    FallbackText, '\n',
    AssumpText, '\n',
    FeedbackText, '\n',
    LearnedText, '\n\n',
    PlanCtx, '\n\n',
    LogText, '\n\n',
    'Respond with exactly one repair_proposal([...]) term (at most 3 actions). ',
    'If unsure about mechanisms, prefer feedback:record_discovery for missing ',
    'in-tree providers; use draft_fixup only for recurring log signatures.'
  ], Prompt).


% -----------------------------------------------------------------------------
%  Parse / validate proposal
% -----------------------------------------------------------------------------

%! metacircular:parse_proposal(+Response, -Actions) is semidet.
%
% Extracts repair_proposal(Actions) from Response text.

metacircular:parse_proposal(Response, Actions) :-
  atom_string(RespAtom, Response),
  ( metacircular:extract_fenced_prolog(RespAtom, Code)
  -> true
  ;  Code = RespAtom
  ),
  metacircular:read_repair_proposal(Code, Actions).


%! metacircular:extract_fenced_prolog(+Text, -Code) is semidet.

metacircular:extract_fenced_prolog(Text, Code) :-
  sub_atom(Text, Start, _, _, '```'),
  !,
  sub_atom(Text, Start, _, 0, FromFence),
  ( sub_atom(FromFence, 0, _, _, '```prolog')
  -> sub_atom(FromFence, 9, _, 0, AfterLang)
  ;  sub_atom(FromFence, 3, _, 0, AfterLang)
  ),
  ( sub_atom(AfterLang, 0, 1, _, '\n')
  -> sub_atom(AfterLang, 1, _, 0, Body0)
  ;  Body0 = AfterLang
  ),
  sub_atom(Body0, End, _, _, '```'),
  !,
  sub_atom(Body0, 0, End, _, Code).


%! metacircular:read_repair_proposal(+Text, -Actions) is semidet.

metacircular:read_repair_proposal(Text, Actions) :-
  atom_string(TextAtom, Text),
  ( sub_atom(TextAtom, Start, _, _, 'repair_proposal(')
  -> sub_atom(TextAtom, Start, _, 0, From),
     metacircular:balanced_term_atom(From, TermAtom),
     catch(term_string(Term, TermAtom, []), _, fail),
     Term = repair_proposal(Actions),
     is_list(Actions)
  ;  fail
  ).


%! metacircular:balanced_term_atom(+From, -TermAtom) is semidet.
%
% Takes a string starting at a term and returns the atom of the first
% top-level term (balanced parentheses, ignoring quoted content).

metacircular:balanced_term_atom(From, TermAtom) :-
  atom_codes(From, Codes),
  metacircular:take_balanced(Codes, 0, in_plain, [], AccRev),
  reverse(AccRev, Acc),
  atom_codes(TermAtom, Acc).


%! metacircular:take_balanced(+Codes, +Depth, +State, +Acc, -AccOut) is semidet.

metacircular:take_balanced([], Depth, _, Acc, Acc) :-
  Depth =:= 0,
  Acc \== [].

metacircular:take_balanced([0''|Rest], Depth, in_plain, Acc, AccOut) :-
  !,
  metacircular:take_balanced(Rest, Depth, in_atom_quote, [0''|Acc], AccOut).

metacircular:take_balanced([0''|Rest], Depth, in_atom_quote, Acc, AccOut) :-
  !,
  metacircular:take_balanced(Rest, Depth, in_plain, [0''|Acc], AccOut).

metacircular:take_balanced([0'\\, C|Rest], Depth, in_atom_quote, Acc, AccOut) :-
  !,
  metacircular:take_balanced(Rest, Depth, in_atom_quote, [C,0'\\|Acc], AccOut).

metacircular:take_balanced([C|Rest], Depth, in_atom_quote, Acc, AccOut) :-
  !,
  metacircular:take_balanced(Rest, Depth, in_atom_quote, [C|Acc], AccOut).

metacircular:take_balanced([0'( |Rest], Depth, in_plain, Acc, AccOut) :-
  !,
  Depth1 is Depth + 1,
  metacircular:take_balanced(Rest, Depth1, in_plain, [0'(|Acc], AccOut).

metacircular:take_balanced([0')|Rest], Depth, in_plain, Acc, AccOut) :-
  !,
  Depth1 is Depth - 1,
  ( Depth1 =:= 0
  -> AccOut = [0')|Acc]
  ;  Depth1 > 0,
     metacircular:take_balanced(Rest, Depth1, in_plain, [0')|Acc], AccOut)
  ).

metacircular:take_balanced([C|Rest], 0, in_plain, Acc, AccOut) :-
  !,
  metacircular:take_balanced(Rest, 0, in_plain, [C|Acc], AccOut).

metacircular:take_balanced([C|Rest], Depth, in_plain, Acc, AccOut) :-
  Depth > 0,
  metacircular:take_balanced(Rest, Depth, in_plain, [C|Acc], AccOut).


%! metacircular:validate_actions(+Raw, -Valid) is det.
%
% Drops unknown/malformed actions and phantom providers; caps length.

metacircular:validate_actions(Raw, Valid) :-
  ( catch(config:llm_metacircular_max_actions(Max), _, fail), integer(Max)
  -> true
  ;  Max = 3
  ),
  metacircular:validate_actions_(Raw, Max, [], Rev),
  reverse(Rev, Valid).


%! metacircular:validate_actions_(+Raw, +Left, +Acc, -Out) is det.

metacircular:validate_actions_([], _, Acc, Acc).

metacircular:validate_actions_(_, 0, Acc, Acc) :- !.

metacircular:validate_actions_([A|Rest], Left, Acc, Out) :-
  ( metacircular:valid_action(A)
  -> Left1 is Left - 1,
     metacircular:validate_actions_(Rest, Left1, [A|Acc], Out)
  ;  format(atom(Msg), 'Metacircular: rejecting invalid action ~w', [A]),
     message:warning(Msg),
     metacircular:validate_actions_(Rest, Left, Acc, Out)
  ).


%! metacircular:valid_action(+Action) is semidet.

metacircular:valid_action(action(record_discovery, Target, Provider, Kind, Evidence)) :-
  Target = _://_,
  atom(Provider),
  Kind == bdepend,
  nonvar(Evidence),
  metacircular:provider_in_tree(Provider).

metacircular:valid_action(action(record_usedep, Target, Provider, UseDeps, Evidence)) :-
  Target = _://_,
  atom(Provider),
  is_list(UseDeps),
  UseDeps \== [],
  forall(member(U, UseDeps), metacircular:valid_usedep(U)),
  nonvar(Evidence),
  metacircular:provider_in_tree(Provider).

metacircular:valid_action(action(record_excluded_version, C, N, Ver, Evidence)) :-
  atom(C), atom(N), nonvar(Ver), nonvar(Evidence).

metacircular:valid_action(action(record_kernel_config, Target, Options, Evidence)) :-
  Target = _://_,
  is_list(Options),
  Options \== [],
  nonvar(Evidence).

metacircular:valid_action(action(draft_fixup, Mechanism, Synopsis, SketchBody)) :-
  % Mechanism becomes the draft filename (see write_draft_fixup/3), so
  % it must be a single safe path component: `/` or `..` in LLM output
  % would otherwise write the draft outside Knowledge/drafts/.
  sanitize:safe_filename(Mechanism),
  ( atom(Synopsis) -> true ; string(Synopsis) ),
  ( atom(SketchBody) -> true ; string(SketchBody) ).


%! metacircular:valid_usedep(+Term) is semidet.

metacircular:valid_usedep(use(enable(Flag), none)) :-
  atom(Flag).

metacircular:valid_usedep(use(disable(Flag), none)) :-
  atom(Flag).


%! metacircular:provider_in_tree(+Package) is semidet.

metacircular:provider_in_tree(Package) :-
  ( current_predicate(missing_provider:package_in_tree/1)
  -> missing_provider:package_in_tree(Package)
  ;  atom(Package),
     atomic_list_concat([C, N], '/', Package),
     cache:ordered_entry(Repo, _Id, C, N, _),
     Repo \== pkg
  ).


% -----------------------------------------------------------------------------
%  Confirm and apply
% -----------------------------------------------------------------------------

%! metacircular:confirm_and_apply(+Actions, -AppliedCount) is det.

metacircular:confirm_and_apply(Actions, AppliedCount) :-
  metacircular:confirm_and_apply_(Actions, 0, AppliedCount).


%! metacircular:confirm_and_apply_(+Actions, +Acc, -Applied) is det.

metacircular:confirm_and_apply_([], Acc, Acc).

metacircular:confirm_and_apply_([Action|Rest], Acc0, Applied) :-
  metacircular:describe_action(Action, Desc),
  nl,
  message:color(yellow),
  format('Proposed: ~w~n', [Desc]),
  message:color(normal),
  message:print('Apply this action? [Yes/No] '),
  flush_output,
  read_line_to_string(user_input, Answer),
  ( member(Answer, ["Yes", "yes", "Y", "y", ""])
  -> ( metacircular:apply_action(Action, Kind)
     -> ( Kind == feedback
        -> Acc1 is Acc0 + 1
        ;  Acc1 = Acc0
        ),
        message:inform('Applied.')
     ;  message:warning('Failed to apply action.'),
        Acc1 = Acc0
     )
  ;  message:inform('Skipped.'),
     Acc1 = Acc0
  ),
  metacircular:confirm_and_apply_(Rest, Acc1, Applied).


%! metacircular:describe_action(+Action, -Desc) is det.

metacircular:describe_action(action(record_discovery, Target, Provider, Kind, _), Desc) :-
  !,
  format(atom(Desc), 'record_discovery ~w needs ~w (~w)', [Target, Provider, Kind]).

metacircular:describe_action(action(record_usedep, Target, Provider, UseDeps, _), Desc) :-
  !,
  format(atom(Desc), 'record_usedep ~w needs ~w ~w', [Target, Provider, UseDeps]).

metacircular:describe_action(action(record_excluded_version, C, N, Ver, _), Desc) :-
  !,
  format(atom(Desc), 'record_excluded_version ~w/~w-~w', [C, N, Ver]).

metacircular:describe_action(action(record_kernel_config, Target, Options, _), Desc) :-
  !,
  format(atom(Desc), 'record_kernel_config ~w ~w', [Target, Options]).

metacircular:describe_action(action(draft_fixup, Mechanism, Synopsis, _), Desc) :-
  !,
  format(atom(Desc), 'draft_fixup ~w (~w) -> Knowledge/drafts/~w-<unixtime>.pl',
         [Mechanism, Synopsis, Mechanism]).

metacircular:describe_action(Action, Desc) :-
  format(atom(Desc), '~w', [Action]).


%! metacircular:apply_action(+Action, -Kind) is semidet.
%
% Kind is `feedback` when learned_count may grow, or `draft` for sketches.

metacircular:apply_action(action(record_discovery, Target, Provider, Kind, Evidence), feedback) :-
  !,
  feedback:record_discovery(Target, Provider, Kind, Evidence),
  ( Target = _://Entry
  -> fixup:record(metacircular, Entry, discovered(Provider))
  ;  true
  ).

metacircular:apply_action(action(record_usedep, Target, Provider, UseDeps, Evidence), feedback) :-
  !,
  feedback:record_usedep(Target, Provider, UseDeps, Evidence),
  ( Target = _://Entry
  -> fixup:record(metacircular, Entry, usedep(Provider, UseDeps))
  ;  true
  ).

metacircular:apply_action(action(record_excluded_version, C, N, Ver, Evidence), feedback) :-
  !,
  feedback:record_excluded_version(C, N, Ver, Evidence).

metacircular:apply_action(action(record_kernel_config, Target, Options0, Evidence), feedback) :-
  !,
  metacircular:normalize_kernel_options(Options0, Options),
  feedback:record_kernel_config(Target, Options, Evidence),
  ( Target = _://Entry
  -> fixup:record(metacircular, Entry, kernel_config(Options))
  ;  true
  ).

metacircular:apply_action(action(draft_fixup, Mechanism, Synopsis, SketchBody), draft) :-
  !,
  metacircular:write_draft_fixup(Mechanism, Synopsis, SketchBody).


%! metacircular:normalize_kernel_options(+In, -Out) is det.

metacircular:normalize_kernel_options(In, Out) :-
  maplist(metacircular:normalize_kernel_option, In, Out).


%! metacircular:normalize_kernel_option(+In, -Out) is det.

metacircular:normalize_kernel_option(config(Name, State), config(Name, State)) :- !.

metacircular:normalize_kernel_option(Name, config(Name, y)) :-
  atom(Name).


%! metacircular:write_draft_fixup(+Mechanism, +Synopsis, +SketchBody) is det.
%
% Write the draft sketch to Knowledge/drafts/<Mechanism>-<unixtime>.pl.
% Fails (with a warning) when Mechanism is not a safe filename — a
% defence-in-depth recheck of valid_action/1, since the filename is
% built from LLM-proposed text.

metacircular:write_draft_fixup(Mechanism, Synopsis, SketchBody) :-
  ( sanitize:safe_filename(Mechanism)
  -> true
  ;  message:warning(['Metacircular: refusing draft fixup with unsafe mechanism name: ',
                      Mechanism]),
     fail
  ),
  config:installation_dir(Dir),
  os:compose_path([Dir, 'Knowledge', 'drafts'], DraftDir),
  os:make_directory_path(DraftDir),
  get_time(StampF),
  Stamp is integer(StampF),
  format(atom(File), '~w-~w.pl', [Mechanism, Stamp]),
  os:compose_path([DraftDir, File], Path),
  atom_string(SynopsisAtom, Synopsis),
  atom_string(BodyAtom, SketchBody),
  catch(
    setup_call_cleanup(
      open(Path, write, S),
      ( format(S, '/* Metacircular draft fixup: ~w~n', [Mechanism]),
        format(S, '   Synopsis: ~w~n', [SynopsisAtom]),
        format(S, '   Review, then move under Source/Domain/Gentoo/Exceptions/ and register via fixup:mechanism/1.~n', []),
        format(S, '*/~n~n', []),
        write(S, BodyAtom),
        ( sub_atom(BodyAtom, _, 1, 0, '\n') -> true ; nl(S) )
      ),
      close(S)),
    Error,
    ( format(atom(Msg), 'Failed to write draft fixup: ~w', [Error]),
      message:warning(Msg),
      fail
    )
  ),
  message:inform(['Draft fixup written to ', Path]).


% -----------------------------------------------------------------------------
%  CLI: --diagnose
% -----------------------------------------------------------------------------

%! metacircular:diagnose_cli(+Args, +Options) is det.
%
% Offline diagnose for a package atom (and optional --log path).

metacircular:diagnose_cli(Args, Options) :-
  ( metacircular:llm_backend_available
  -> true
  ;  message:warning('--diagnose requires LLM support. LLM modules are not loaded.'),
     !, fail
  ),
  ( metacircular:interactive_available
  -> true
  ;  message:warning('--diagnose requires an interactive TTY (disabled under --ci or llm_metacircular(false)).'),
     !, fail
  ),
  ( Args = [Atom|_]
  -> true
  ;  message:failure('Usage: portage-ng --diagnose category/name [--log path]'),
     !, fail
  ),
  ( memberchk(diagnoselog(LogOpt), Options), LogOpt \== none
  -> LogPath = LogOpt
  ;  metacircular:default_log_for_atom(Atom, LogPath)
  ),
  ( exists_file(LogPath)
  -> true
  ;  message:warning(['Build log not found: ', LogPath]),
     !, fail
  ),
  ( metacircular:resolve_target_atom(Atom, Target)
  -> true
  ;  Target = unknown://Atom
  ),
  Goals = [target(_, Atom):run?{[]}],
  empty_assoc(Empty),
  Ctx = ctx(Goals, Empty, Empty, [], Empty, unknown),
  metacircular:diagnose_failure(Target, unknown, LogPath, diagnose_cli, Ctx, Applied),
  ( Applied > 0
  -> message:inform(['Applied ', Applied, ' feedback action(s). Re-run --build to re-derive the plan.'])
  ;  true
  ).


%! metacircular:default_log_for_atom(+Atom, -LogPath) is det.

metacircular:default_log_for_atom(Atom, LogPath) :-
  ( metacircular:resolve_target_atom(Atom, _Repo://Entry)
  -> ebuild_exec:build_log_path(Entry, LogPath)
  ;  ebuild_exec:build_log_path(Atom, LogPath)
  ).


%! metacircular:resolve_target_atom(+Atom, -Repo://Entry) is semidet.

metacircular:resolve_target_atom(Atom, Repo://Entry) :-
  atom_codes(Atom, Codes),
  phrase(eapi:qualified_target(Q), Codes),
  once(kb:query(Q, Repo://Entry)),
  Repo \== pkg.