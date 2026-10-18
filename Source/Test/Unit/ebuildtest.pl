/*
 Author: Pieter Van den Abeele
 E-mail: pvdabeel@mac.com
 Copyright (c) 2005-2026, Pieter Van den Abeele

 Distributed under the terms of the LICENSE file in the root directory of this
 project.
*/

/** <module> EBUILDTEST
Security tests for the NUL-framed ebuild-depend.sh request protocol.
*/

:- module(ebuildtest, []).

:- use_module(library(plunit)).

% =============================================================================
% EBUILDTEST declarations
% =============================================================================

% -----------------------------------------------------------------------------
% Fixtures
% -----------------------------------------------------------------------------

ebuildtest:script(Script) :-
  absolute_file_name(
    portage('Source/Domain/Gentoo/Ebuild/ebuild-depend.sh'),
    Script, [access(read)]).


ebuildtest:with_repo(Goal) :-
  tmp_file(ebuildtest, Tmp),
  ( exists_file(Tmp) -> delete_file(Tmp) ; true ),
  make_directory(Tmp),
  setup_call_cleanup(true, call(Goal, Tmp),
                     catch(delete_directory_and_contents(Tmp), _, true)).


ebuildtest:write_ebuild(Repo, Rel, File, Path) :-
  os:compose_path(Repo, Rel, Dir),
  make_directory_path(Dir),
  os:compose_path(Dir, File, Path),
  setup_call_cleanup(
    open(Path, write, Out),
    format(Out,
      'EAPI=8~nDESCRIPTION="protocol fixture"~nSLOT="0"~nKEYWORDS="*"~nLICENSE="GPL-2"~n',
      []),
    close(Out)).


ebuildtest:fields(Repo, Canary, Ebuild, Fields) :-
  ebuildtest:write_ebuild(Repo, 'spaced cat/hello world',
                          'hello world-1.0.ebuild', Ebuild),
  format(atom(Category), '$(touch ~w); touch ~w', [Canary, Canary]),
  Fields = [Category, 'hello world', '1.0', '', '1.0',
            'hello world-1.0', 'hello world-1.0', Ebuild].


ebuildtest:run_mode(Mode, Repo, Writer, Output, Status) :-
  ebuildtest:script(Script),
  process_create(Script, [Mode, Repo],
                 [stdin(pipe(In)), stdout(pipe(Out)),
                  stderr(pipe(Err)), process(Pid)]),
  set_stream(In, encoding(utf8)),
  set_stream(Out, encoding(utf8)),
  set_stream(Err, encoding(utf8)),
  setup_call_cleanup(
    true,
    ( call(Writer, In),
      close(In),
      read_string(Out, _, Output),
      read_string(Err, _, _)
    ),
    ( catch(close(In, [force(true)]), _, true),
      catch(close(Out), _, true),
      catch(close(Err), _, true)
    )),
  process_wait(Pid, Waited, [timeout(10)]),
  ( Waited = exit(Status) -> true ; Status = Waited ).


ebuildtest:batch_outcome(Result) :-
  ebuildtest:with_repo(ebuildtest:batch_outcome_(Result)).

ebuildtest:batch_outcome_(Status-Marker-CanaryExists, Repo) :-
  os:compose_path(Repo, canary, Canary),
  ebuildtest:fields(Repo, Canary, _Ebuild, Fields),
  ebuildtest:run_mode('--batch', Repo,
    [In]>>(ebuild:write_entry_frame(In, Fields), flush_output(In)),
    Output, Status),
  ( sub_string(Output, _, _, _, "DESCRIPTION=protocol fixture"),
    sub_string(Output, _, _, _, "---END---")
  -> Marker = true
  ;  Marker = false
  ),
  ( exists_file(Canary) -> CanaryExists = true ; CanaryExists = false ).


ebuildtest:legacy_outcome(Result) :-
  ebuildtest:with_repo(ebuildtest:legacy_outcome_(Result)).

ebuildtest:legacy_outcome_(Status-CanaryExists, Repo) :-
  os:compose_path(Repo, canary, Canary),
  ebuildtest:write_ebuild(Repo, 'app/hello', 'hello-1.0.ebuild', Ebuild),
  format(atom(Line),
    'CATEGORY=foo; touch ~w PN=hello PV=1.0 PR=r0 PVR=1.0 PF=hello-1.0 P=hello-1.0 EBUILD=~w~n',
    [Canary, Ebuild]),
  ebuildtest:run_mode('--batch', Repo,
    [In]>>format(In, '~w', [Line]),
    Output, Status),
  once(sub_string(Output, _, _, _, "---ERROR--- truncated request")),
  \+ sub_string(Output, _, _, _, "DESCRIPTION=protocol fixture"),
  ( exists_file(Canary) -> CanaryExists = true ; CanaryExists = false ).


ebuildtest:truncated_status(Status) :-
  ebuildtest:with_repo(ebuildtest:truncated_status_(Status)).

ebuildtest:truncated_status_(Status, Repo) :-
  ebuildtest:run_mode('--batch', Repo,
    [In]>>(
      format(In, 'entry', []),
      put_code(In, 0),
      format(In, 'only', []),
      put_code(In, 0)
    ),
    Output, Status),
  once(sub_string(Output, _, _, _, "---ERROR--- truncated request")).


ebuildtest:server_status(Status) :-
  ebuildtest:with_repo(ebuildtest:server_status_(Status)).

ebuildtest:server_status_(Status, Repo) :-
  os:compose_path(Repo, canary, Canary),
  ebuildtest:fields(Repo, Canary, _Ebuild, Fields),
  ebuildtest:run_mode('--server', Repo,
    [In]>>(
      ebuild:write_entry_frame(In, Fields),
      flush_output(In),
      ebuild:write_quit_frame(In),
      flush_output(In)
    ),
    Output, Status),
  once(sub_string(Output, _, _, _, "DESCRIPTION=protocol fixture")),
  \+ exists_file(Canary).


% -----------------------------------------------------------------------------
% Protocol
% -----------------------------------------------------------------------------

:- begin_tests(ebuild_protocol).

test(nul_field_writes_nothing) :-
  atom_codes(Bad, [0'a, 0, 0'b]),
  new_memory_file(Mem),
  setup_call_cleanup(
    open_memory_file(Mem, write, Out, [encoding(utf8)]),
    ( ebuild:write_entry_frame(Out, [Bad, pn, pv, pr, pvr, pf, p, ebuild])
    -> fail
    ;  true
    ),
    close(Out)),
  memory_file_to_string(Mem, Text),
  Text == "".

test(batch_keeps_metacharacters_as_data,
     [true(Got == 0-true-false)]) :-
  ebuildtest:batch_outcome(Got).

test(legacy_eval_line_is_not_executed,
     [true(Got == 1-false)]) :-
  ebuildtest:legacy_outcome(Got).

test(truncated_frame_fails_closed, [true(Status == 1)]) :-
  ebuildtest:truncated_status(Status).

test(server_frame_then_quit, [true(Status == 0)]) :-
  ebuildtest:server_status(Status).

:- end_tests(ebuild_protocol).
