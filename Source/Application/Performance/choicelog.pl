/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> CHOICELOG
Structured resolver choice-event log.

Records sparse trying/succeeded/failed events for `||` arms and
multi-candidate version binds, plus reject/learn/reprove/assumption
events. Armed at runtime via `--choice-log` (or `choicelog:arm/0`).

Compile-time gating: unless started with `-Dchoice_log=true` (the
`portage-ng-dev` wrapper sets this when `--choice-log` is passed), all
hot-path `clog_emit` / `clog_wrap` / `wrap_any_of` / `maybe_dump` call
sites and `candidate:choicelog_version_wrap/4` are compiled out by
`goal_expansion` (to `true` or `call(Goal)`), leaving effectively zero
overhead — same pattern as `--profile` / `instrumentation`.

Event term:

  event(Seq, Kind, Outcome, Data)

  Kind    = any_of | version | reject | learn | reprove | assumption
  Outcome = trying | succeeded | failed | recorded
*/

:- module(choicelog, []).

% =============================================================================
%  CHOICELOG declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Compile-time gating (zero cost when disabled)
% -----------------------------------------------------------------------------

:- multifile user:goal_expansion/2.

% SWI strips the module from Module:Pred before matching user:goal_expansion/2,
% then re-qualifies the result as Module:Expanded. Expand wrap forms to
% call(Goal) so the result is Module:call(Goal) (safe for qualified Goals).
% Same flag pattern as sampler's instrumentation expansions.

user:goal_expansion(clog_emit(_, _, _), true) :-
  \+ current_prolog_flag(choice_log, true).

user:goal_expansion(clog_wrap(_, _, Goal), call(Goal)) :-
  \+ current_prolog_flag(choice_log, true).

user:goal_expansion(wrap_any_of(_, _, _, Goal), call(Goal)) :-
  \+ current_prolog_flag(choice_log, true).

user:goal_expansion(maybe_dump, true) :-
  \+ current_prolog_flag(choice_log, true).

user:goal_expansion(choicelog_version_wrap(_, _, _, Goal), call(Goal)) :-
  \+ current_prolog_flag(choice_log, true).


% -----------------------------------------------------------------------------
%  Configuration
% -----------------------------------------------------------------------------

%! choicelog:maxlen(-Max) is det.
%
% Maximum events retained in the ring buffer.

choicelog:maxlen(2000).


% -----------------------------------------------------------------------------
%  Arm / disarm / reset
% -----------------------------------------------------------------------------

%! choicelog:arm is det.
%
% Enable logging for the current thread (nb state).

choicelog:arm :-
  nb_setval(choicelog_armed, true).


%! choicelog:disarm is det.
%
% Disable logging for the current thread.

choicelog:disarm :-
  nb_setval(choicelog_armed, false).


%! choicelog:armed is semidet.
%
% Succeeds when the choice log is armed.

choicelog:armed :-
  nb_current(choicelog_armed, true).


%! choicelog:reset is det.
%
% Clear the ring buffer and sequence counter.

choicelog:reset :-
  nb_setval(choicelog_buf, []),
  nb_setval(choicelog_len, 0),
  nb_setval(choicelog_seq, 0),
  nb_setval(choicelog_dropped, 0).


%! choicelog:with_logging(:Goal) is nondet.
%
% Arm and reset, run Goal, dump on exit, then disarm.

choicelog:with_logging(Goal) :-
  setup_call_cleanup(
    ( choicelog:arm, choicelog:reset ),
    Goal,
    ( choicelog:maybe_dump, choicelog:disarm )
  ).


% -----------------------------------------------------------------------------
%  Emit / wrap
% -----------------------------------------------------------------------------

%! choicelog:clog_emit(+Kind, +Outcome, +Data) is det.
%
% Hot-path emit entry (unique name for goal_expansion). Appends an event
% when armed. Never fails or throws into the proof. Compiled to `true`
% when `choice_log` is off at load time.

choicelog:clog_emit(Kind, Outcome, Data) :-
  ( nb_current(choicelog_armed, true) ->
      catch(choicelog:do_emit(Kind, Outcome, Data), _, true)
  ; true
  ),
  !.


%! choicelog:emit(+Kind, +Outcome, +Data) is det.
%
% Alias for clog_emit/3 (shell / documentation convenience).

choicelog:emit(Kind, Outcome, Data) :-
  G = clog_emit(Kind, Outcome, Data),
  choicelog:G.


%! choicelog:do_emit(+Kind, +Outcome, +Data) is det.
%
% Internal emit: assign sequence, push to ring buffer, drop oldest if full.

choicelog:do_emit(Kind, Outcome, Data) :-
  ( nb_current(choicelog_seq, Seq0) -> true ; Seq0 = 0 ),
  Seq is Seq0 + 1,
  nb_setval(choicelog_seq, Seq),
  Event = event(Seq, Kind, Outcome, Data),
  ( nb_current(choicelog_buf, Buf0) -> true ; Buf0 = [] ),
  ( nb_current(choicelog_len, Len0) -> true ; Len0 = 0 ),
  choicelog:maxlen(Max),
  Buf1 = [Event|Buf0],
  Len1 is Len0 + 1,
  ( Len1 > Max ->
      append(Keep, [_Oldest], Buf1),
      ( nb_current(choicelog_dropped, Drop0) -> true ; Drop0 = 0 ),
      Drop1 is Drop0 + 1,
      nb_setval(choicelog_dropped, Drop1),
      nb_setval(choicelog_buf, Keep),
      nb_setval(choicelog_len, Max)
  ; nb_setval(choicelog_buf, Buf1),
    nb_setval(choicelog_len, Len1)
  ).


%! choicelog:do_wrap(+Kind, +Data, :Goal) is nondet.
%
% Internal wrap implementation (not goal_expansion'd). Emit trying, run
% Goal, emit succeeded or failed. On success, also emit failed if Goal
% is later undone by backtracking.

choicelog:do_wrap(Kind, Data, Goal) :-
  ( nb_current(choicelog_armed, true) ->
      catch(choicelog:do_emit(Kind, trying, Data), _, true),
      ( call(Goal)
      -> catch(choicelog:do_emit(Kind, succeeded, Data), _, true),
         ( true
         ; catch(choicelog:do_emit(Kind, failed, Data), _, true),
           fail
         )
      ; catch(choicelog:do_emit(Kind, failed, Data), _, true),
        fail
      )
  ; call(Goal)
  ).


%! choicelog:clog_wrap(+Kind, +Data, :Goal) is nondet.
%
% Hot-path wrap entry. Compiled to call(Goal) when `choice_log` is off.

choicelog:clog_wrap(Kind, Data, Goal) :-
  choicelog:do_wrap(Kind, Data, Goal).


%! choicelog:wrap(+Kind, +Data, :Goal) is nondet.
%
% Alias for clog_wrap/3.

choicelog:wrap(Kind, Data, Goal) :-
  choicelog:do_wrap(Kind, Data, Goal).


%! choicelog:wrap_any_of(+Context, +SortedDeps, +D0, :Goal) is nondet.
%
% Prepare any_of event data for arm D0 and wrap Goal. Compiled to
% call(Goal) when `choice_log` is off at load time (prep work included).

choicelog:wrap_any_of(Context, SortedDeps, D0, Goal) :-
  ( nb_current(choicelog_armed, true) ->
      length(SortedDeps, ArmCount),
      choicelog:parent_summary(Context, Parent),
      choicelog:nth_member(SortedDeps, D0, ArmIndex),
      choicelog:summarize_arm(D0, ArmSummary),
      Data = any_of(Parent, ArmIndex, ArmCount, ArmSummary),
      choicelog:do_wrap(any_of, Data, Goal)
  ; call(Goal)
  ).


% -----------------------------------------------------------------------------
%  Read / dump
% -----------------------------------------------------------------------------

%! choicelog:events(-Events) is det.
%
% Chronological list of buffered events (oldest first).

choicelog:events(Events) :-
  ( nb_current(choicelog_buf, Buf) ->
      reverse(Buf, Events)
  ; Events = []
  ).


%! choicelog:maybe_dump is det.
%
% Dump to user_error when armed; no-op otherwise.

choicelog:maybe_dump :-
  ( nb_current(choicelog_armed, true) ->
      choicelog:dump
  ; true
  ),
  !.


%! choicelog:dump is det.
%
% Print a human-readable summary of the choice log to user_error.

choicelog:dump :-
  catch(choicelog:do_dump, _, true),
  !.


%! choicelog:do_dump is det.
%
% Internal dump implementation.

choicelog:do_dump :-
  choicelog:events(Events),
  length(Events, N),
  ( nb_current(choicelog_dropped, Dropped) -> true ; Dropped = 0 ),
  choicelog:maxlen(Max),
  format(user_error,
         '~n=== choice log: ~d events (~d dropped), maxlen ~d ===~n',
         [N, Dropped, Max]),
  forall(member(E, Events), choicelog:dump_event(E)),
  format(user_error, '=== end choice log ===~n', []).


%! choicelog:dump_event(+Event) is det.
%
% Print one event line.

choicelog:dump_event(event(Seq, Kind, Outcome, Data)) :-
  choicelog:format_data(Data, DataText),
  format(user_error, '~t~d~4+ ~w~t~12+ ~w~t~12+ ~w~n',
         [Seq, Outcome, Kind, DataText]).


%! choicelog:format_data(+Data, -Text) is det.
%
% Compact one-line rendering of event Data.

choicelog:format_data(any_of(Parent, Index, Count, Arm), Text) :-
  !,
  format(atom(Text), 'parent=~w index=~d/~d arm=~w',
         [Parent, Index, Count, Arm]).
choicelog:format_data(any_of(Parent, Index, Count, Arm, Reason), Text) :-
  !,
  format(atom(Text), 'parent=~w index=~d/~d arm=~w reason=~w',
         [Parent, Index, Count, Arm, Reason]).
choicelog:format_data(version(Parent, C, N, Ver, Slot, Index, Count), Text) :-
  !,
  choicelog:format_version(Ver, VerText),
  format(atom(Text), 'parent=~w dep=~w/~w-~w slot=~w index=~d/~d',
         [Parent, C, N, VerText, Slot, Index, Count]).
choicelog:format_data(reject(C, N, Domain, Candidates, Reasons), Text) :-
  !,
  length(Candidates, NC),
  format(atom(Text), 'cn=~w/~w domain=~w candidates=~d reasons=~w',
         [C, N, Domain, NC, Reasons]).
choicelog:format_data(learn(Literal, Constraint, Added), Text) :-
  !,
  format(atom(Text), 'lit=~w constraint=~w added=~w',
         [Literal, Constraint, Added]).
choicelog:format_data(reprove(Info), Text) :-
  !,
  format(atom(Text), 'info=~w', [Info]).
choicelog:format_data(assumption(Type, Lit), Text) :-
  !,
  format(atom(Text), 'type=~w lit=~w', [Type, Lit]).
choicelog:format_data(Data, Text) :-
  format(atom(Text), '~w', [Data]).


%! choicelog:format_version(+Ver, -Text) is det.
%
% Prefer the Full component of version/7 when present.

choicelog:format_version(version(_N, _A, _SR, _SN, _ST, _R, Full), Full) :-
  Full \== [],
  Full \== '',
  !.
choicelog:format_version(Ver, Text) :-
  format(atom(Text), '~w', [Ver]).


% -----------------------------------------------------------------------------
%  Context / arm helpers (used by emit sites)
% -----------------------------------------------------------------------------

%! choicelog:parent_summary(+Context, -Parent) is det.
%
% Parent package entry atom from self/1 in the proof context, or unknown.

choicelog:parent_summary(Context, Parent) :-
  ( is_list(Context),
    memberchk(self(_://Entry), Context)
  -> Parent = Entry
  ; Parent = unknown
  ).


%! choicelog:summarize_arm(+Dep, -Summary) is det.
%
% Compact atom describing a choice-group arm.

choicelog:summarize_arm(grouped_package_dependency(_Strength, C, N, Deps), Summary) :-
  !,
  choicelog:summarize_pkg_deps(C, N, Deps, Summary).
choicelog:summarize_arm(package_dependency(_P, _S, C, N, O, V, Slot, Use), Summary) :-
  !,
  choicelog:summarize_one_dep(C, N, O, V, Slot, Use, Summary).
choicelog:summarize_arm(all_of_group(Deps), Summary) :-
  !,
  length(Deps, N),
  format(atom(Summary), 'all_of(~d)', [N]).
choicelog:summarize_arm(any_of_group(Deps), Summary) :-
  !,
  length(Deps, N),
  format(atom(Summary), 'any_of(~d)', [N]).
choicelog:summarize_arm(use_conditional_group(Pol, Use, _, _), Summary) :-
  !,
  format(atom(Summary), '~w[~w]', [Pol, Use]).
choicelog:summarize_arm(Dep, Summary) :-
  format(atom(Summary), '~w', [Dep]).


%! choicelog:summarize_pkg_deps(+C, +N, +Deps, -Summary) is det.
%
% Summarize the first package_dependency in a grouped arm.

choicelog:summarize_pkg_deps(C, N, Deps, Summary) :-
  ( member(package_dependency(_P, _S, C, N, O, V, Slot, Use), Deps)
  -> choicelog:summarize_one_dep(C, N, O, V, Slot, Use, Summary)
  ; format(atom(Summary), '~w/~w', [C, N])
  ).


%! choicelog:summarize_one_dep(+C, +N, +O, +V, +Slot, +Use, -Summary) is det.
%
% One-line CN + operator/version + slot + use summary.

choicelog:summarize_one_dep(C, N, O, V, Slot, Use, Summary) :-
  choicelog:format_version(V, VerText),
  ( Slot == [] -> SlotText = ''
  ; format(atom(SlotText), ':~w', [Slot])
  ),
  ( Use == [] -> UseText = ''
  ; format(atom(UseText), '[~w]', [Use])
  ),
  format(atom(Summary), '~w~w/~w-~w~w~w', [O, C, N, VerText, SlotText, UseText]).


%! choicelog:nth_member(+List, +Elem, -Index) is semidet.
%
% 1-based index of Elem in List (first match).

choicelog:nth_member(List, Elem, Index) :-
  nth1(Index, List, Elem).
