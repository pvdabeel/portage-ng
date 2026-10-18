/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> RESUME
Build resume-state persistence.

Owns the on-disk resume state (Knowledge/resume.pl) and the in-memory
done marks recorded while a build runs. A --build run saves its goals
and plan up front; after every plan step the builder flushes completed
entries here for crash safety. A later --resume loads the saved plan,
filters out everything already done (or explicitly skipped via
config:skip_atom/1), and re-executes the remainder.
*/

:- module(resume, []).

% =============================================================================
%  RESUME declarations
% =============================================================================

:- dynamic resume:done/2.

% -----------------------------------------------------------------------------
%  In-memory done marks
% -----------------------------------------------------------------------------

%! resume:mark_done(+Entry, +Action) is det.
%
% Record that Entry completed Action successfully in the current run.
% Marks are flushed to disk after each plan step (flush_done_to_disk/0)
% and consulted by the builder's VDB reconciliation backstop.

resume:mark_done(Entry, Action) :-
  assertz(resume:done(Entry, Action)).


%! resume:clear_done_marks is det.
%
% Drop all in-memory done marks. Called at the start of every build run
% so marks from a previous run in the same session cannot leak in.

resume:clear_done_marks :-
  retractall(resume:done(_, _)).


% -----------------------------------------------------------------------------
%  Resume state file
% -----------------------------------------------------------------------------

%! resume:state_file(-Path) is det.
%
% Returns the path to the resume state file (Knowledge/resume.pl).

resume:state_file(Path) :-
  config:state_dir(Dir),
  os:compose_path([Dir, 'Knowledge', 'resume.pl'], Path).


%! resume:save_state(+Goals, +Plan) is det.
%
% Saves the build goals and plan to Knowledge/resume.pl. This is
% called at the start of a --build run so the plan can be loaded
% later by --resume.

resume:save_state(Goals, Plan) :-
  resume:state_file(Path),
  catch(
    ( setup_call_cleanup(
        open(Path, write, S),
        ( write_term(S, resume_goals(Goals), [quoted(true)]),
          format(S, '.~n', []),
          write_term(S, resume_plan(Plan), [quoted(true)]),
          format(S, '.~n', [])
        ),
        close(S)),
      sanitize:write_sha256_sidecar(Path)
    ),
    _, true).


%! resume:flush_done_to_disk is det.
%
% Appends any in-memory done/2 marks to the resume state file,
% then retracts them. Called after each plan step for crash safety.

resume:flush_done_to_disk :-
  resume:state_file(Path),
  ( exists_file(Path)
  -> findall(E-A, resume:done(E, A), Entries),
     ( Entries \= []
     -> catch(
          ( setup_call_cleanup(
              open(Path, append, S),
              forall(
                member(E-A, Entries),
                ( write_term(S, resume_done(E, A), [quoted(true)]),
                  format(S, '.~n', [])
                )
              ),
              close(S)),
            sanitize:write_sha256_sidecar(Path)
          ),
          _, true),
        resume:clear_done_marks
     ;  true
     )
  ;  true
  ).


%! resume:load_state(-Goals, -Plan, -DoneList) is semidet.
%
% Loads the resume state from Knowledge/resume.pl. Returns the
% original goals, plan, and a list of done(Entry, Action) terms
% for entries that already completed. Fails if no resume file exists.

resume:load_state(Goals, Plan, DoneList) :-
  resume:state_file(Path),
  exists_file(Path),
  sanitize:ensure_file_integrity(Path),
  catch(
    setup_call_cleanup(
      open(Path, read, S),
      resume:read_all_terms(S, Terms),
      close(S)),
    _, fail),
  ( memberchk(resume_goals(Goals), Terms) -> true ; Goals = [] ),
  ( memberchk(resume_plan(Plan), Terms) -> true ; Plan = [] ),
  findall(done(E, A), member(resume_done(E, A), Terms), DoneList).


%! resume:read_all_terms(+Stream, -Terms) is det.
%
% Reads all Prolog terms from a stream until end_of_file. Only
% resume_goals/1, resume_plan/1, and resume_done/2 terms are kept;
% everything else is dropped so a poisoned file cannot inject goals.

resume:read_all_terms(S, Terms) :-
  read_term(S, T, [syntax_errors(error)]),
  ( T == end_of_file
  -> Terms = []
  ;  ( resume:safe_state_term(T)
     -> Terms = [T|Rest]
     ;  Terms = Rest
     ),
     resume:read_all_terms(S, Rest)
  ).


%! resume:safe_state_term(+Term) is semidet.
%
% True when Term is a ground resume-state fact of an allowed shape.

resume:safe_state_term(resume_goals(Goals)) :-
  ground(Goals), is_list(Goals).
resume:safe_state_term(resume_plan(Plan)) :-
  ground(Plan), is_list(Plan).
resume:safe_state_term(resume_done(E, A)) :-
  ground(E), ground(A).


%! resume:clear_state is det.
%
% Deletes the resume state file after a successful build.

resume:clear_state :-
  resume:state_file(Path),
  ( exists_file(Path) -> delete_file(Path) ; true ).


% -----------------------------------------------------------------------------
%  Plan filtering
% -----------------------------------------------------------------------------

%! resume:filter_completed_plan(+Plan, +DoneList, -FilteredPlan) is det.
%
% Removes completed rules from each step in the plan. A rule is
% considered completed if its Entry and Action appear in DoneList.

resume:filter_completed_plan([], _, []).

resume:filter_completed_plan([Step|Rest], DoneList, [Filtered|FilteredRest]) :-
  exclude(resume:rule_is_done(DoneList), Step, Filtered),
  resume:filter_completed_plan(Rest, DoneList, FilteredRest).


%! resume:rule_is_done(+DoneList, +Rule) is semidet.
%
% True if the rule's package and action appear in the done list.

resume:rule_is_done(DoneList, rule(Repo://Entry:Action?{_Ctx}, _Body)) :-
  memberchk(done(Repo://Entry, Action), DoneList).


%! resume:collect_skip_entries(+Plan, -SkipDone) is det.
%
% Collects done/2 entries for rules whose Entry matches any
% config:skip_atom/1 fact. Matches by sub_atom so the user can
% specify a qualified name like dev-lang/python-3.12.0 and it
% will match the full Entry atom in the plan.

resume:collect_skip_entries(Plan, SkipDone) :-
  findall(done(Repo://Entry, Action),
    ( member(Step, Plan),
      member(rule(Repo://Entry:Action?{_Ctx}, _Body), Step),
      config:skip_atom(Skip),
      sub_atom(Entry, _, _, _, Skip)
    ),
    SkipDone).
