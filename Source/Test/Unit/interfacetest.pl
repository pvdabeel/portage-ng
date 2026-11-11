/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> INTERFACETEST
Unit tests for CLI request dispatch (Source/Application/Interface/requests.pl).
*/

:- module(interfacetest, []).

:- use_module(library(plunit)).
:- use_module(library(lists)).
:- use_module(library(prolog_wrap)).

% =============================================================================
%  INTERFACETEST declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Interface request dispatch tests
% -----------------------------------------------------------------------------

:- begin_tests(interface_request_dispatch).

% Every handler flag maps to an option declared in interface:spec/1.
% 'shellrun' is the only pseudo-flag (--shell with target arguments).
test(handler_flags_declared_in_spec, [true(Unknown == [shellrun])]) :-
  interface:spec(Spec),
  findall(Opt, (member(Line, Spec), member(opt(Opt), Line)), Opts),
  findall(Flag,
          ( interface:request_handler(Flag, _, _, _, _),
            \+ memberchk(Flag, Opts) ),
          Unknown).

% One handler per flag.
test(handler_flags_unique) :-
  findall(Flag, interface:request_handler(Flag, _, _, _, _), Flags),
  msort(Flags, Sorted),
  sort(Flags, Set),
  Sorted == Set.

% Order is load-bearing: --shell must be dispatched before --merge, because
% merge(true) is the default in the flag list (spec.pl) and matches any command
% line.
test(shell_precedes_merge_catchall) :-
  findall(Flag, interface:request_handler(Flag, _, _, _, _), Flags),
  once(nth0(ShellRun, Flags, shellrun)),
  once(nth0(Shell, Flags, shell)),
  once(nth0(Merge, Flags, merge)),
  ShellRun < Shell,
  Shell < Merge,
  last(Flags, merge).

% Per-flag goal lookup: the table binds Mode/Args/Options into the goal.
test(info_handler_goal) :-
  once(interface:request_handler(info, mode, args, opts, Goal)),
  Goal == action:process_action(info, args, opts).

test(sync_handler_goal_uses_mode) :-
  once(interface:request_handler(sync, standalone, args, opts, Goal)),
  Goal == action:process_sync(standalone, args).

% Default guard: boolean flag set to true in Options.
test(matches_boolean_flag) :-
  interface:request_matches(search, [], [search(true)]).

test(matches_boolean_flag_false, [fail]) :-
  interface:request_matches(search, [], [search(false)]).

% Specialised guards.
test(matches_rollback_value) :-
  interface:request_matches(rollback, [], [rollback(snap1)]).

test(matches_rollback_none_fails, [fail]) :-
  interface:request_matches(rollback, [], [rollback(none)]).

test(matches_llm_service) :-
  interface:request_matches(llm, [], [llm(ollama)]).

test(matches_llm_none_fails, [fail]) :-
  interface:request_matches(llm, [], [llm(none)]).

test(matches_shellrun_needs_args) :-
  interface:request_matches(shellrun, ['app-misc/foo'], [shell(true)]).

test(matches_shellrun_no_args_fails, [fail]) :-
  interface:request_matches(shellrun, [], [shell(true)]).

% Selection: first triggered handler in table order wins.
test(select_shellrun_over_merge) :-
  Opts = [shell(true), merge(true)],
  interface:request_select(standalone, ['app-misc/foo'], Opts, Flag, Goal),
  Flag == shellrun,
  Goal == action:process_action(run, ['app-misc/foo'], Opts).

test(select_bare_shell_is_noop) :-
  interface:request_select(standalone, [], [shell(true), merge(true)], Flag, Goal),
  Flag == shell,
  Goal == true.

test(select_merge_catchall) :-
  Opts = [merge(true)],
  interface:request_select(standalone, ['app-misc/foo'], Opts, Flag, Goal),
  Flag == merge,
  Goal == action:process_default(standalone, ['app-misc/foo'], Opts).

test(select_client_merge_stays_print) :-
  Opts = [merge(true)],
  interface:request_select(client, ['app-misc/foo'], Opts, Flag, Goal),
  Flag == merge,
  Goal == action:process_default(client, ['app-misc/foo'], Opts).

% `--fetchonly` / `-F` prove the same :run plan as --merge.
test(fetchonly_handler_proves_run) :-
  once(interface:request_handler(fetchonly, mode, args, opts, Goal)),
  Goal == action:process_action(run, args, opts).

test(fetchall_handler_proves_run) :-
  once(interface:request_handler(fetchall, mode, args, opts, Goal)),
  Goal == action:process_action(run, args, opts).

% `--build --fetchonly` must execute (filtered) rather than only print.
test(build_precedes_fetchonly) :-
  findall(Flag, interface:request_handler(Flag, _, _, _, _), Flags),
  once(nth0(Build, Flags, build)),
  once(nth0(Fetch, Flags, fetchonly)),
  Build < Fetch.

test(select_build_over_fetchonly) :-
  Opts = [build(true), fetchonly(true), merge(true)],
  interface:request_select(standalone, ['app-misc/foo'], Opts, Flag, Goal),
  Flag == build,
  Goal == action:process_build(['app-misc/foo'], Opts).

% `--build --pretend` prints the plan and does not execute.
test(select_build_pretend_does_not_build) :-
  Opts = [build(true), pretend(true), merge(true)],
  interface:request_select(standalone, ['app-misc/foo'], Opts, Flag, Goal),
  Flag == merge,
  Goal == action:process_default(standalone, ['app-misc/foo'], Opts).

test(select_build_fetchonly_pretend_does_not_build) :-
  Opts = [build(true), fetchonly(true), pretend(true), merge(true)],
  interface:request_select(standalone, ['app-misc/foo'], Opts, Flag, Goal),
  Flag == fetchonly,
  Goal == action:process_action(run, ['app-misc/foo'], Opts).

test(process_default_standalone_builds) :-
  setup_call_cleanup(
    wrap_predicate(action:process_build(Args, Opts), test_pd, _,
                   ( Args == ['app-misc/foo'],
                     Opts == [merge(true)]
                   )),
    action:process_default(standalone, ['app-misc/foo'], [merge(true)]),
    unwrap_predicate(action:process_build/2, test_pd)).

test(process_default_client_does_not_build) :-
  setup_call_cleanup(
    ( wrap_predicate(action:process_action(Action, Args, _), test_pa, _,
                     ( Action == run,
                       Args == ['app-misc/foo']
                     )),
      wrap_predicate(builder:build(_), test_bb2, _, throw(built))
    ),
    action:process_default(client, ['app-misc/foo'], [merge(true)]),
    ( unwrap_predicate(action:process_action/3, test_pa),
      unwrap_predicate(builder:build/1, test_bb2)
    )).

test(select_unmerge_executes) :-
  Opts = [unmerge(true), merge(true)],
  interface:request_select(standalone, ['app-editors/neovim'], Opts, Flag, Goal),
  Flag == unmerge,
  Goal == action:process_unmerge(['app-editors/neovim'], Opts).

test(process_unmerge_pretend_does_not_execute) :-
  setup_call_cleanup(
    ( wrap_predicate(action:process_action(Action, Args, Opts), test_up, _,
                     ( Action == uninstall,
                       Args == ['app-editors/neovim'],
                       memberchk(pretend(true), Opts)
                     )),
      wrap_predicate(builder:build(_), test_ub, _, throw(built))
    ),
    action:process_unmerge(['app-editors/neovim'], [pretend(true)]),
    ( unwrap_predicate(action:process_action/3, test_up),
      unwrap_predicate(builder:build/1, test_ub)
    )).

test(process_unmerge_executes_the_plan) :-
  Goal = target(none, 'app-editors/neovim'):uninstall?{[]},
  setup_call_cleanup(
    ( wrap_predicate(interface:report_unresolvable_targets(_, _), test_ur, _, true),
      wrap_predicate(action:build_proposal(Action, _, Proposal), test_um, _,
                     ( Action == uninstall,
                       Proposal = [Goal]
                     )),
      wrap_predicate(builder:build(Goals), test_ub2, _,
                     Goals == [Goal]),
      wrap_predicate(action:process_action(_, _, _), test_ua, _, throw(printed))
    ),
    action:process_unmerge(['app-editors/neovim'], [unmerge(true)]),
    ( unwrap_predicate(interface:report_unresolvable_targets/2, test_ur),
      unwrap_predicate(action:build_proposal/3, test_um),
      unwrap_predicate(builder:build/1, test_ub2),
      unwrap_predicate(action:process_action/3, test_ua)
    )).

test(process_build_pretend_does_not_execute) :-
  setup_call_cleanup(
    ( wrap_predicate(action:process_action(Action, Args, Opts), test_bp, _,
                     ( Action == run,
                       Args == ['app-misc/foo'],
                       memberchk(pretend(true), Opts)
                     )),
      wrap_predicate(builder:build(_), test_bb, _, throw(built))
    ),
    action:process_build(['app-misc/foo'], [pretend(true)]),
    ( unwrap_predicate(action:process_action/3, test_bp),
      unwrap_predicate(builder:build/1, test_bb)
    )).

% No handler triggered -> selection fails (process_requests then reports
% the unrecognised options and falls through to its catch-all halt(1)).
test(select_fails_on_unrecognised_options, [fail]) :-
  interface:request_select(standalone, [], [merge(false)], _, _).

% --help is rendered from the option spec, before any request dispatch.
% Descriptions share one column, including the preformatted --mode lines.
test(print_help_lists_declared_flags) :-
  with_output_to(string(Text), interface:print_help),
  once(sub_string(Text, _, _, _, 'Usage:')),
  once(sub_string(Text, _, _, _, '-h, --help')),
  once(sub_string(Text, _, _, _, '--merge')),
  once(sub_string(Text, _, _, _, '--mode')),
  \+ sub_string(Text, _, _, _, 'boolean=false'),
  help_column(Text, 'Show this help and exit', ShowCol),
  help_column(Text, 'Ask for confirmation', AskCol),
  help_column(Text, 'standalone:', ModeCol),
  help_column(Text, 'ipc:', IpcCol),
  ShowCol =:= AskCol,
  ModeCol =:= IpcCol,
  ModeCol =:= ShowCol.

help_column(Text, Needle, Col) :-
  split_string(Text, "\n", "", Lines),
  member(Line, Lines),
  sub_string(Line, Before, _, _, Needle),
  !,
  Col = Before.

:- end_tests(interface_request_dispatch).


% -----------------------------------------------------------------------------
%  State a command line leaves behind
% -----------------------------------------------------------------------------

:- begin_tests(interface_flag_state).

% The daemon handles one command line after another. What one of them
% switched on or off must be gone before the next one is processed.
test(restore_undoes_what_a_command_line_changed,
     [ setup(interface:save_flag_state),
       cleanup(interface:restore_flag_state) ]) :-
  findall(Head-Facts,
          ( interface:flag_state(Head),
            interface:flag_state_facts(Head, Facts) ),
          Before),
  asserta(config:verbose(true)),
  retractall(config:color_output),
  asserta(config:excluded_atom('cat/pkg')),
  asserta(config:skip_atom('cat/other')),
  asserta(config:interface_printing_style(column)),
  asserta(config:cli_jobs(7)),
  asserta(config:cli_ci(true)),
  findall(Head-Facts,
          ( interface:flag_state(Head),
            interface:flag_state_facts(Head, Facts) ),
          Changed),
  interface:restore_flag_state,
  findall(Head-Facts,
          ( interface:flag_state(Head),
            interface:flag_state_facts(Head, Facts) ),
          After),
  Changed \=@= Before,
  After =@= Before.

% The order of the facts is part of the state: readers take the first one.
test(restore_keeps_fact_order) :-
  setup_call_cleanup(
    ( findall(S, retract(config:interface_printing_style(S)), Original),
      assertz(config:interface_printing_style(short)),
      assertz(config:interface_printing_style(fancy)),
      interface:save_flag_state
    ),
    ( asserta(config:interface_printing_style(column)),
      interface:restore_flag_state,
      findall(S, config:interface_printing_style(S), Styles),
      Styles == [short, fancy]
    ),
    ( retractall(config:interface_printing_style(_)),
      forall(member(S, Original), assertz(config:interface_printing_style(S))),
      interface:save_flag_state
    )).

% Every fact that flag processing writes, apart from the per-request
% preference flags, has to be in interface:flag_state/1. Otherwise it stays
% behind in the daemon.
test(every_fact_written_by_flag_processing_is_listed) :-
  findall(Fact,
          ( member(Head, [ process_flags,
                           process_repeated_flags,
                           process_snapshot_flag,
                           assert_valid_style(_),
                           assert_valid_optimize(_) ]),
            clause(interface:Head, Body),
            sub_term(Goal, Body),
            nonvar(Goal),
            interfacetest:written_fact(Goal, Fact)
          ),
          Facts),
  Facts \== [],
  forall(member(Fact, Facts),
         ( Fact = preference:local_flag(_)
         -> true
         ;  \+ \+ interface:flag_state(Fact)
         )).

:- end_tests(interface_flag_state).


% -----------------------------------------------------------------------------
%  Ending a request
% -----------------------------------------------------------------------------

:- begin_tests(interface_request_exit).

% Inside the daemon a request ends by an exception that carries the exit
% status. A halt would end the daemon.
test(exit_inside_daemon_throws_the_status,
     [ setup(assertz(daemon:running)),
       cleanup(retractall(daemon:running)) ]) :-
  catch(( interface:exit(7), Ended = no ),
        request_exit(Status),
        Ended = yes(Status)),
  Ended == yes(7).

% The actions run inside the daemon as well, so none of them may call
% halt/1 itself. They end a request through interface:exit/1.
test(actions_do_not_halt) :-
  findall(Name/Arity,
          ( predicate_property(action:Head, defined),
            \+ predicate_property(action:Head, imported_from(_)),
            \+ predicate_property(action:Head, foreign),
            catch(clause(action:Head, Body), _, fail),
            interfacetest:called_goal(Body, Goal),
            ( Goal == halt ; Goal = halt(_) ),
            functor(Head, Name, Arity)
          ),
          Halting),
  Halting == [].

:- end_tests(interface_request_exit).


%! interfacetest:called_goal(+Body, -Goal)
%
% Goal is a goal that the clause body Body calls: Body itself, or a goal
% in an argument that a control construct or meta-predicate (`,`, `;`,
% `->`, `\+`, catch/3, forall/2, findall/3, ...) calls. A term that is
% only compared with, such as the halt(_) in `Err = halt(_)`, is not a
% goal.

interfacetest:called_goal(Goal, _) :-
  var(Goal), !,
  fail.
interfacetest:called_goal(_:Goal, Called) :-
  !,
  interfacetest:called_goal(Goal, Called).
interfacetest:called_goal(_^Goal, Called) :-
  !,
  interfacetest:called_goal(Goal, Called).
interfacetest:called_goal(Goal, Called) :-
  callable(Goal),
  predicate_property(action:Goal, meta_predicate(Spec)),
  !,
  Goal =.. [_|Args],
  Spec =.. [_|ArgSpecs],
  ( Called = Goal
  ; nth1(Index, ArgSpecs, ArgSpec),
    ( integer(ArgSpec) ; ArgSpec == (^) ),
    nth1(Index, Args, Arg),
    interfacetest:called_goal(Arg, Called)
  ).
interfacetest:called_goal(Goal, Goal).


%! interfacetest:written_fact(+Goal, -Fact)
%
% Goal adds or removes Fact in the database.

interfacetest:written_fact(asserta(Fact), Fact).
interfacetest:written_fact(assertz(Fact), Fact).
interfacetest:written_fact(assert(Fact), Fact).
interfacetest:written_fact(retract(Fact), Fact).
interfacetest:written_fact(retractall(Fact), Fact).


% -----------------------------------------------------------------------------
%  Comprehensive coverage tests for Interface/* andInterface/Action/*
% -----------------------------------------------------------------------------

:- begin_tests(interface_and_actions_full_coverage).

% True when no repository has been loaded into the cache, which is the case
% when the tests run without a knowledge base.
no_repository_loaded :-
  \+ cache:repository(_).

% True when parsing Argv throws an error that matches Expected. Fails when
% the command line is accepted, so a mistake that goes unnoticed is caught.
argv_error(Argv, Expected) :-
  catch(( interface:parse_argv(Argv, _, _), Thrown = none ),
        Error,
        Thrown = thrown(Error)),
  Thrown = thrown(Expected).

test(argv_version_exitcodes_target_flags_verify_requests) :-
  redefine_system_predicate(interface:halt(_)),
  redefine_system_predicate(interface:prolog),
  findall(O-A, interface:argv_(O, A), SavedArgv),
  working_directory(OrigCwd, OrigCwd),
  setup_call_cleanup(
    ( asserta((interface:halt(Code) :- throw(test_halt(Code)))),
      asserta((interface:prolog :- true))
    ),
    with_output_to(string(_),
      ( % argv.pl
        retractall(interface:argv_(_, _)),
        retractall(interface:opt_index_ready_),
        retractall(interface:opt_flag_(_, _, _)),
        retractall(interface:opt_neg_flag_(_, _)),
        retractall(interface:opt_defaults_(_)),
        interface:argv(_Opts0, _Args0),
        interface:argv(_Opts1, _Args1),
        interface:parse_argv(
          [ '--no-merge', '--pretend', 'false', '--verbose=true',
            '--quiet=false', '--mode=ipc', '-j4', '--jobs', '2',
            '--load-average', '1.5', '--', '=cat/pkg-1.0'
          ],
          ParsedOpts, ParsedPos),
        memberchk(merge(false), ParsedOpts),
        memberchk(pretend(false), ParsedOpts),
        memberchk(verbose(true), ParsedOpts),
        memberchk(mode(ipc), ParsedOpts),
        memberchk(jobs(2), ParsedOpts),
        memberchk(loadavg(1.5), ParsedOpts),
        ParsedPos == ['--', '=cat/pkg-1.0'],
        catch(interface:parse_argv(['--unknown=val'], _, _),
              error(existence_error(commandline_option, '--unknown'), _), true),
        catch(interface:parse_argv(['--unknown'], _, _),
              error(existence_error(commandline_option, '--unknown'), _), true),
        % Where the parser differs from library(optparse) on purpose.
        interface:parse_argv(['-1', 'cat/pkg'], OneshotOpts, ['cat/pkg']),
        memberchk(oneshot(true), OneshotOpts),
        interface:parse_argv(['--load-average', '2'], WholeOpts, []),
        memberchk(loadavg(2.0), WholeOpts),
        interface:parse_argv(['--jobs', '2', '--jobs=8'], LastOpts, []),
        memberchk(jobs(8), LastOpts),
        \+ memberchk(jobs(2), LastOpts),
        interface:parse_argv(['-', 'a', '--pretend', 'b'], _, ['-', 'a', 'b']),
        % Every mistake is an error that names the option and the value.
        argv_error(['--unknown=val'],
          error(existence_error(commandline_option, '--unknown'), _)),
        argv_error(['--unknown'],
          error(existence_error(commandline_option, '--unknown'), _)),
        argv_error(['--p'],
          error(existence_error(commandline_option, '--p'), _)),
        argv_error(['-j=4'],
          error(syntax_error(commandline_option_value), commandline_option('-j=4'))),
        argv_error(['--jobs'],
          error(existence_error(commandline_option_value, '--jobs'), _)),
        argv_error(['--color'],
          error(existence_error(commandline_option_value, '--color'), _)),
        argv_error(['--jobs', 'notanint'],
          error(type_error(integer, notanint), commandline_option('--jobs'))),
        argv_error(['-jx'],
          error(type_error(integer, x), commandline_option('-j'))),
        argv_error(['--load-average', 'notafloat'],
          error(type_error(float, notafloat), commandline_option('--load-average'))),
        argv_error(['--pretend=maybe'],
          error(type_error(boolean, maybe), commandline_option('--pretend'))),
        interface:drop_end_of_options(['--', 'a'], ['a']),
        interface:drop_end_of_options(['a'], ['a']),
        % The explanation and exit status for each kind of mistake.
        interface:argv_error_text(
          error(existence_error(commandline_option, '--merg'), _), 1,
          ['Error: Unknown option --merg.', _DidYouMean,
           'Use --help for available options.']),
        interface:argv_error_text(
          error(existence_error(commandline_option, '--zzzzzz'), _), 1,
          ['Error: Unknown option --zzzzzz.',
           'Use --help for available options.']),
        interface:argv_error_text(
          error(existence_error(commandline_option_value, '--color'),
                commandline_option('--color')), 2,
          ['Error: Option --color needs a value.'|_]),
        interface:argv_error_text(
          error(type_error(integer, x), commandline_option('--jobs')), 2,
          ['Error: Option --jobs expects a whole number, got \'x\'.'|_]),
        interface:argv_error_text(
          error(type_error(float, x), commandline_option('--load-average')), 2,
          ['Error: Option --load-average expects a number, got \'x\'.'|_]),
        interface:argv_error_text(
          error(type_error(boolean, maybe), commandline_option('--pretend')), 2,
          ['Error: Option --pretend expects true or false, got \'maybe\'.'|_]),
        interface:argv_error_text(
          error(type_error(term, x), commandline_option('--odd')), 2, _),
        interface:argv_error_text(
          error(syntax_error(commandline_option_value),
                commandline_option('-j=4')), 2,
          ['Error: Cannot read option -j=4.'|_]),
        \+ interface:argv_error_text(error(other_err, _), _, _),
        catch(interface:argv_handle_parse_error(
                error(existence_error(commandline_option, '--merg'), _)),
              test_halt(1), true),
        catch(interface:argv_handle_parse_error(
                error(type_error(integer, x), commandline_option('--jobs'))),
              test_halt(2), true),
        catch(interface:argv_handle_parse_error(error(other_err, _)),
              error(other_err, _), true),
        interface:flag_similarity("", "", 0.0),
        ignore(interface:getenv('PATH', _)),
        assertz(daemon:client_env('TEST_COV_ENV', 'val')),
        interface:getenv('TEST_COV_ENV', 'val'),
        retractall(daemon:client_env('TEST_COV_ENV', _)),
        % version.pl
        interface:version(_),
        interface:repo_git_version(OrigCwd, _),
        interface:repo_git_version('/nonexistent_git_dir_12345', unknown),
        interface:status('development'),
        % exitcodes.pl
        forall(interface:exit_code(_, _, _), true),
        empty_assoc(EmptyAVL),
        interface:ci_exit_code(EmptyAVL, EmptyAVL, 0),
        put_assoc(assumed(foo), EmptyAVL, true, ModelAssumed),
        put_assoc(assumed(rule(r)), EmptyAVL, dep(1, [])?[], ProofCycle),
        interface:ci_exit_code(ModelAssumed, ProofCycle, 1),
        interface:ci_exit_code(ModelAssumed, EmptyAVL, 0),
        put_assoc(rule(assumed(r://e:run)), EmptyAVL, dep(1, [])?[], ProofDom),
        interface:ci_exit_code(ModelAssumed, ProofDom, 2),
        % target.pl
        V1 = version([1,0], '', 4, 0, '', 0, '1.0'),
        assertz(cache:ordered_entry(test_if_repo, 'cat/pkg-1.0', 'cat', 'pkg', V1)),
        assertz(cache:ordered_entry(pkg, 'cat/pkg-1.0', 'cat', 'pkg', V1)),
        assertz(cache:package(test_if_repo, 'cat', 'pkg')),
        assertz(cache:package(test_if_repo, 'cat2', 'pkg')),
        interface:report_unresolvable_targets(run, ['--', '!!!bad target!!!', 'cat/pkg', 'cat/missing']),
        interface:report_unresolvable_targets(uninstall, ['cat/pkg', 'cat/missing']),
        interface:resolve_pkg_arg('cat/pkg', 'cat', 'pkg'),
        interface:resolve_pkg_arg('pkg', 'cat', 'pkg'),
        retractall(cache:package(test_if_repo, 'cat2', 'pkg')),
        interface:resolve_pkg_arg('pkg', 'cat', 'pkg'),
        retractall(cache:ordered_entry(test_if_repo, _, _, _, _)),
        retractall(cache:ordered_entry(pkg, 'cat/pkg-1.0', _, _, _)),
        retractall(cache:package(test_if_repo, _, _)),
        % flags.pl
        retractall(interface:argv_(_, _)),
        assertz(interface:argv_([
          deep(true), emptytree(true), depclean(true), newuse(true),
          changeduse(true), changeddeps(true), changedslot(true),
          selective(true), noreplace(true), nodeps(true), onlydeps(true),
          dynamicdeps(false), rebuildnewrev(true), rebuildnewver(true),
          rebuildnewslot(true), rebuildunbuilt(true), updateifinstalled(true),
          readnews(true), withbdeps(n), withtestdeps(y), pretend(true),
          oneshot(true), select(false), buildpkg(true), buildpkgonly(true),
          usepkg(true), usepkgonly(true), getbinpkg(true), getbinpkgonly(true),
          fetchonly(true), fetchall(true), failclean(true),
          usepkgexcludelive(true), binpkgchangeddeps(true), binpkgrespectuse(true),
          binpkgrespectuserpatches(n), rebuiltbinaries(true),
          ask(true), alert(true), quiet(true), verbose(true), choicelog(true),
          logs(true), ci(true), style(fancy), optimize('soft-requirements'),
          jobs(4), loadavg(2.0), permitdowngrade(true), prefix('/tmp/pfx'),
          showdescriptions(all), continuefailure(always),
          lazy(true), complete(true), everything(true),
          snapshot(true), mode(standalone), port(4000), host(localhost)
        ], [])),
        interface:process_flags,
        choicelog:disarm,
        retractall(config:choice_log(_)),
        retractall(config:verbose(_)),
        retractall(config:show_build_logs(_)),
        retractall(config:cli_ci(_)),
        retractall(config:interface_printing_style(_)),
        retractall(config:cli_jobs(_)),
        retractall(config:cli_load_average(_)),
        retractall(config:cli_prefix(_)),
        retractall(config:show_use_descriptions(_)),
        retractall(config:continue_on_failure(_)),
        retractall(snapshot:active_id(_)),
        retractall(preference:local_flag(_)),
        interface:collect_flag_values(['--skip', 'a', 'other', '--skip', 'b'], '--skip', ['a', 'b']),
        interface:assert_valid_style('unknown_style'),
        retractall(config:interface_printing_style(_)),
        interface:assert_valid_optimize(parallelism),
        interface:assert_valid_optimize('unknown_opt'),
        retractall(interface:argv_(_, _)),
        assertz(interface:argv_([snapshot('custom_snap'), mode(server)], [])),
        interface:process_snapshot_flag,
        retractall(snapshot:active_id(_)),
        retractall(interface:argv_(_, _)),
        assertz(interface:argv_([snapshot(none), mode(server)], [])),
        assertz(config:snapshot_enabled),
        interface:process_snapshot_flag,
        retractall(config:snapshot_enabled),
        retractall(snapshot:active_id(_)),
        interface:get_mode(server),
        interface:process_continue(_),
        retractall(interface:argv_(_, _)),
        assertz(interface:argv_([mode(standalone), shell(true)], [])),
        interface:process_continue(_),
        retractall(interface:argv_(_, _)),
        assertz(interface:argv_([mode(standalone)], [])),
        catch(interface:process_continue(_), _, true),
        assertz(daemon:running),
        interface:process_continue(true),
        retractall(daemon:running),
        interface:get_port(_),
        interface:process_server(_, _),
        \+ interface:server_reachable(localhost, 1),
        tmp_file(tls_cov, TlsTmp),
        setup_call_cleanup(open(TlsTmp, write, S), write(S, 'x'), close(S)),
        interface:require_tls_files(client, localhost, TlsTmp, TlsTmp, TlsTmp),
        ignore(interface:require_tls_files(client, localhost, '/no_tls_1', '/no_tls_2', '/no_tls_3')),
        catch(delete_file(TlsTmp), _, true),
        ignore(interface:require_digest_password),
        interface:init_tty,
        interface:init_line_editor,
        interface:init_working_dir,
        working_directory(_, OrigCwd),
        % verify.pl
        retractall(interface:argv_(_, _)),
        assertz(interface:argv_([], [])),
        interface:verify_mode(standalone),
        catch(interface:early_exit(standalone, [help(true)]), test_halt(0), true),
        catch(interface:early_exit(ipc, [shell(true)]), test_halt(1), true),
        catch(interface:early_exit(ipc, [status(true)]), test_halt(_), true),
        catch(interface:early_exit(ipc, [cmd(unknown_cmd)]), test_halt(0), true),
        catch(interface:early_exit(client, [status(true)]), test_halt(_), true),
        catch(interface:early_exit(client, [cmd(halt)]), test_halt(1), true),
        wrap_predicate(ipc:fork_background(_Mode), test_cov, _W1, true),
        catch(interface:early_exit(daemon, [background(true)]), test_halt(0), true),
        catch(interface:early_exit(server, [background(true)]), test_halt(0), true),
        unwrap_predicate(ipc:fork_background/1, test_cov),
        % requests.pl
        forall(member(ReqF-ReqOpts, [
          shell-[],
          build-[],
          graph-[],
          llm-[],
          merge-[explain(true)],
          info-[]
        ]), interface:ensure_for_request(ReqF, ReqOpts)),
        ignore(interface:dispatch_request(standalone, [], [merge(false)])),
        interface:process_requests(ipc),
        interface:process_requests(server),
        interface:process_requests(daemon),
        interface:process_requests(worker),
        retractall(interface:argv_(_, _)),
        assertz(interface:argv_([shell(true), mode(standalone)], [])),
        interface:process_requests(standalone),
        retractall(interface:argv_(_, _)),
        assertz(interface:argv_([merge(false), mode(standalone)], [])),
        catch(interface:process_requests(standalone), test_halt(1), true),
        % The same request inside the daemon ends with the same status,
        % without a halt.
        assertz(daemon:running),
        catch(( interface:process_requests(standalone), Ended = no ),
              request_exit(Status),
              Ended = yes(Status)),
        retractall(daemon:running),
        Ended == yes(1)
      )),
    ( retractall(interface:halt(_)),
      retractall(interface:prolog),
      asserta((interface:halt(C) :- system:halt(C))),
      asserta((interface:prolog :- system:prolog)),
      retractall(interface:argv_(_, _)),
      forall(member(O-A, SavedArgv), assertz(interface:argv_(O, A))),
      working_directory(_, OrigCwd)
    )).

% Calls every action once, among them the ones behind --sync, --regen,
% --graph and the VDB import, which work on every repository that is
% loaded. The test therefore only runs when no repository is loaded and
% the only one it meets is its own stub (`make coverage`, the PLUnit job
% on GitHub). With the Portage tree loaded (`make test` on a development
% machine) it would sync and graph the real tree, so it is skipped there.
test(actions_full_coverage, [condition(no_repository_loaded)]) :-
  user:ensure_loaded(portage('Source/Application/Mode/client.pl')),
  redefine_system_predicate(interface:halt(_)),
  findall(O-A, interface:argv_(O, A), SavedArgv),
  V1 = version([1,0], '', 4, 0, '', 0, '1.0'),
  tmp_file(act_dir, TmpDir),
  ( exists_file(TmpDir) -> delete_file(TmpDir) ; true ),
  make_directory(TmpDir),
  os:compose_path(TmpDir, 'Knowledge', KnowDir),
  make_directory(KnowDir),
  os:compose_path(TmpDir, 'world', WorldFile),
  setup_call_cleanup(
    ( asserta((interface:halt(Code) :- throw(act_halt(Code)))),
      retractall(interface:argv_(_, _)),
      assertz(interface:argv_([mode(standalone), host(localhost), port(4000)], [])),
      setenv('PORTAGE_NG_STATE', TmpDir),
      assertz(portage:graph),
      assertz(portage:graph_emerge),
      assertz(portage:graph_pmerge),
      assertz(test_act_repo:sync),
      assertz(test_act_repo:sync(metadata)),
      kb:register(test_act_repo),
      ( catch(world:declared(type(instance(set))), _, fail)
      -> world:init(WorldFile)
      ;  world:newinstance(set(WorldFile))
      ),
      assertz(cache:ordered_entry(test_act_repo, 'cat/pkg-1.0', 'cat', 'pkg', V1)),
      assertz(cache:ordered_entry(pkg, 'cat/pkg-1.0', 'cat', 'pkg', V1)),
      assertz(cache:package(test_act_repo, 'cat', 'pkg')),
      assertz(cache:entry_metadata(test_act_repo, 'cat/pkg-1.0', iuse, 'foo')),
      assertz(cache:entry_metadata(test_act_repo, 'cat/pkg-1.0', keywords, stable(amd64))),
      unittest:accept_stable_amd64,
      asserta(config:pkg_directory(TmpDir)),
      wrap_predicate(explainer:call_llm(_, _, LlmResp), test_cov, _, LlmResp = "ok")
    ),
    with_output_to(string(_),
      ( % bugs.pl
        action:process_bugs([], []),
        action:process_bugs(['cat/nonexistent'], []),
        action:process_bugs(['cat/pkg'], []),
        catch(action:process_bugs(['cat/pkg'], [ci(true)]), act_halt(0), true),
        action:process_search_bugs([], []),
        % build.pl
        action:assert_resume_skip_args(['cat/pkg']),
        retractall(config:skip_atom('cat/pkg')),
        ignore(action:process_build([], [])),
        catch(action:process_build([], [ci(true)]), act_halt(3), true),
        ignore(action:process_build(['cat/nonexistent'], [])),
        wrap_predicate(action:process_action(_, _, _), test_cov_pretend, _, true),
        action:process_build(['cat/pkg'], [pretend(true)]),
        unwrap_predicate(action:process_action/3, test_cov_pretend),
        wrap_predicate(builder:build(_), test_cov, _, true),
        action:process_build(['cat/pkg'], []),
        unwrap_predicate(builder:build/1, test_cov),
        catch(action:handle_build_exception(halt(2), []), halt(2), true),
        catch(action:handle_build_exception(request_exit(2), [ci(true)]),
              request_exit(2), true),
        catch(action:handle_build_exception(boom, [ci(true)]), act_halt(3), true),
        catch(action:handle_build_exception(boom, []), boom, true),
        asserta(builder:last_build_status(0, 1, 0)),
        catch(action:maybe_ci_exit_on_build_failure([ci(true)]), act_halt(3), true),
        action:maybe_ci_exit_on_build_failure([]),
        retractall(builder:last_build_status(_, _, _)),
        % deselect.pl
        ignore(action:process_deselect([])),
        action:process_deselect(['cat/pkg']),
        % estimate.pl
        ignore(action:process_estimate([])),
        action:process_estimate(['cat/pkg', 'cat/nonexistent']),
        wrap_predicate(config:buildtime_enabled(_), test_cov, _, fail),
        action:process_estimate(['cat/pkg']),
        unwrap_predicate(config:buildtime_enabled/1, test_cov),
        % explain.pl
        empty_assoc(EmptyAVL),
        wrap_predicate(explain:explain_plan_interactive(_, _, _, _, _), test_cov, _, true),
        wrap_predicate(explain:explain_plan(_, _, _, _, _, _), test_cov, _, true),
        action:run_explain(true, [], EmptyAVL, EmptyAVL, [], EmptyAVL),
        action:run_explain('why?', [], EmptyAVL, EmptyAVL, [], EmptyAVL),
        unwrap_predicate(explain:explain_plan_interactive/5, test_cov),
        unwrap_predicate(explain:explain_plan/6, test_cov),
        action:extract_llm_opt([llm('')], true),
        action:extract_llm_opt([llm(grok)], grok),
        action:process_llm_chat(unknown_service_xyz),
        open_string("quit\n", InStream),
        stream_property(OldIn, alias(user_input)),
        set_stream(InStream, alias(user_input)),
        call_cleanup(
          action:process_llm_chat(true),
          ( set_stream(OldIn, alias(user_input)),
            close(InStream) )
        ),
        wrap_predicate(metacircular:diagnose_cli(_, _), test_cov, _, true),
        action:process_diagnose([], []),
        unwrap_predicate(metacircular:diagnose_cli/2, test_cov),
        % graph.pl
        forall(member(GArgs, [[], [modified], [full],
                              [emerge], [emerge, modified], [emerge, full],
                              [pmerge], [pmerge, modified], [pmerge, full],
                              [legacy], [legacy, modified], [legacy, full],
                              [unexpected_arg]]),
               action:process_graph(GArgs)),
        % importvdb.pl
        ignore(action:process_import_vdb(standalone)),
        wrap_predicate(client:import_vdb(_, _), test_cov, _, true),
        action:process_import_vdb(client),
        unwrap_predicate(client:import_vdb/2, test_cov),
        % info.pl
        action:process_action(info, [], []),
        action:process_action(info, ['cat/pkg', 'cat/nonexistent'], []),
        % installed.pl
        ignore(action:process_vdb_query(contents, [])),
        action:process_vdb_query(owner, ['/usr/bin/foo']),
        forall(member(VQ, [contents, size, verify, executables]),
               action:process_vdb_query(VQ, ['cat/pkg-1.0', 'cat/nonexistent-1.0'])),
        wrap_predicate(linkage:check(Res), test_cov, _, Res = ['cat/pkg-1.0'-['libfoo.so']]),
        action:process_fix_linkage([], []),
        unwrap_predicate(linkage:check/1, test_cov),
        wrap_predicate(linkage:check(Res2), test_cov, _, Res2 = []),
        action:process_fix_linkage([], []),
        unwrap_predicate(linkage:check/1, test_cov),
        action:process_report([]),
        ignore(action:process_rdeps([])),
        action:process_rdeps(['cat/pkg', 'cat/nonexistent']),
        wrap_predicate(distfiles:get_location(DLoc), test_cov, _, DLoc = TmpDir),
        wrap_predicate(distfiles:orphans(_, Orph1), test_cov, _, Orph1 = ['a.tar.gz']),
        action:process_unused_distfiles([]),
        unwrap_predicate(distfiles:orphans/2, test_cov),
        wrap_predicate(distfiles:orphans(_, Orph2), test_cov, _, Orph2 = []),
        action:process_unused_distfiles([]),
        unwrap_predicate(distfiles:orphans/2, test_cov),
        unwrap_predicate(distfiles:get_location/1, test_cov),
        ignore(action:process_import([], [])),
        action:process_import(['cat/pkg-1.0', 'invalid_spec'], [pretend(true)]),
        wrap_predicate(vdb:import_package(_, _, _), test_cov, _, true),
        action:process_import(['cat/pkg-1.0'], []),
        unwrap_predicate(vdb:import_package/3, test_cov),
        action:process_unmanaged_files([TmpDir, '/nonexistent_dir_xyz']),
        % merge.pl
        ignore(action:process_action(run, [], [])),
        action:process_action(run, ['cat/pkg'], [pretend(true)]),
        action:process_action(uninstall, ['cat/pkg'], [pretend(true)]),
        ignore(action:process_action(run, ['cat/nonexistent'], [pretend(true)])),
        catch(action:process_action(run, ['@security'], [ci(true), pretend(true)]), act_halt(0), true),
        wrap_predicate(client:rpc_execute(_, _, _, OutRpc), test_cov, _, OutRpc = "ok"),
        action:dispatch_proposal(client, localhost, 4000, [], [], true),
        unwrap_predicate(client:rpc_execute/4, test_cov),
        action:run_local_proposal([test_act_repo://'cat/pkg-1.0':run?{[]}], [timeout(5), pretend(true)], true),
        catch(action:halt_with_error('test error'), act_halt(1), true),
        catch(action:maybe_ci_halt([ci(true)], EmptyAVL, EmptyAVL), act_halt(0), true),
        action:maybe_execute_world(false, false,
                                   [[rule(world('cat/pkg'):register?{[]}, []),
                                     rule(world('cat/pkg'):unregister?{[]}, []),
                                     rule(world('cat/pkg'):other?{[]}, []),
                                     rule(other_head, [])]]),
        action:empty_computed_set_text(['preserved-rebuild'], _),
        action:empty_computed_set_text(['changed-deps'], _),
        action:empty_computed_set_text(['installed'], _),
        action:empty_computed_set_text(['security', 'affected'], _),
        action:empty_security_set(['@security']),
        % search.pl
        ignore(action:process_action(search, [], [])),
        action:process_action(search, ['name=pkg'], []),
        action:process_action(search, ['name=nonexistent_pkg_xyz'], []),
        action:process_action(search, ['natural', 'language', 'query'], []),
        action:process_semantic_search('editor'),
        wrap_predicate(semantic:search(_, _, SemRes), test_cov, _, SemRes = []),
        action:process_semantic_search('editor'),
        unwrap_predicate(semantic:search/3, test_cov),
        wrap_predicate(semantic:build_index, test_cov, _, true),
        action:process_train_model,
        unwrap_predicate(semantic:build_index/0, test_cov),
        ignore(action:process_similar([])),
        action:process_similar(['cat/pkg', 'cat/nonexistent']),
        wrap_predicate(semantic:similar(_, _, _, SimRes), test_cov, _, SimRes = []),
        action:process_similar(['cat/pkg']),
        unwrap_predicate(semantic:similar/4, test_cov),
        wrap_predicate(config:semantic_search_enabled(_), test_cov, _, fail),
        action:process_semantic_search('editor'),
        action:process_train_model,
        action:process_similar(['cat/pkg']),
        unwrap_predicate(config:semantic_search_enabled/1, test_cov),
        % snapshot.pl
        wrap_predicate(snapshot:diff(_), test_cov, _, true),
        wrap_predicate(snapshot:rollback(_), test_cov, _, true),
        action:process_rollback(snap1, [pretend(true)]),
        action:process_rollback(snap1, []),
        unwrap_predicate(snapshot:diff/1, test_cov),
        unwrap_predicate(snapshot:rollback/1, test_cov),
        % sync.pl
        action:process_list_sets,
        wrap_predicate(profile:cache_save, test_cov, _, true),
        wrap_predicate(glsa:cache_save, test_cov, _, true),
        action:process_sync(standalone, []),
        action:process_sync(client, [test_act_repo]),
        unwrap_predicate(profile:cache_save/0, test_cov),
        unwrap_predicate(glsa:cache_save/0, test_cov),
        action:process_regen(standalone, []),
        action:process_regen(standalone, [test_act_repo]),
        ignore(action:process_regen(standalone, [unknown_repo_xyz])),
        % upgrade.pl
        wrap_predicate(depclean:run(_), test_cov, _, true),
        action:process_action(depclean, ['cat/pkg'], [pretend(true)]),
        action:process_upgrade(['cat/pkg'], [pretend(true)]),
        unwrap_predicate(depclean:run/1, test_cov),
        % upstream.pl
        wrap_predicate(upstream:check(_), test_cov, _, true),
        action:process_upstream([], []),
        action:process_upstream(['cat/pkg'], []),
        unwrap_predicate(upstream:check/1, test_cov),
        % variants.pl
        action:run_variants(auto, [], EmptyAVL, [], EmptyAVL),
        action:run_variants(all, [], EmptyAVL, [], EmptyAVL),
        put_assoc(rule(test_act_repo://'cat/pkg-1.0':install), EmptyAVL, dep(1, [])?[], ProofVar),
        action:run_variants('foo', [test_act_repo://'cat/pkg-1.0':run?{[]}], ProofVar, [], EmptyAVL)
      )),
    ( unwrap_predicate(explainer:call_llm/3, test_cov),
      unittest:restore_stable_amd64,
      retractall(interface:halt(_)),
      asserta((interface:halt(C) :- system:halt(C))),
      ignore(kb:deregister(test_act_repo)),
      retractall(portage:graph),
      retractall(portage:graph_emerge),
      retractall(portage:graph_pmerge),
      retractall(test_act_repo:sync),
      retractall(test_act_repo:sync(_)),
      unsetenv('PORTAGE_NG_STATE'),
      retractall(config:pkg_directory(TmpDir)),
      retractall(cache:ordered_entry(test_act_repo, _, _, _, _)),
      retractall(cache:ordered_entry(pkg, 'cat/pkg-1.0', _, _, _)),
      retractall(cache:package(test_act_repo, _, _)),
      retractall(cache:entry_metadata(test_act_repo, _, _, _)),
      retractall(interface:argv_(_, _)),
      forall(member(O-A, SavedArgv), assertz(interface:argv_(O, A))),
      catch(process_create(path(rm), ['-rf', TmpDir], [process(Pid)]), _, true),
      ( var(Pid) -> true ; process_wait(Pid, _) )
    )).

test(llm_modules_full_coverage) :-
  V1 = version([1,0], '', 4, 0, '', 0, '1.0'),
  tmp_file(llm_cov, TmpDir),
  ( exists_file(TmpDir) -> delete_file(TmpDir) ; true ),
  make_directory(TmpDir),
  os:compose_path(TmpDir, 'Knowledge', KnowDir),
  make_directory(KnowDir),
  os:compose_path(TmpDir, 'build.log', LogPath),
  setup_call_cleanup(
    open(LogPath, write, LS),
    write(LS, 'error: build failed\n'),
    close(LS)),
  setup_call_cleanup(
    ( setenv('PORTAGE_NG_STATE', TmpDir),
      assertz(cache:ordered_entry(test_llm_repo, 'cat/pkg-1.0', 'cat', 'pkg', V1)),
      assertz(cache:package(test_llm_repo, 'cat', 'pkg')),
      assertz(cache:entry_metadata(test_llm_repo, 'cat/pkg-1.0', description, 'test pkg')),
      assertz(cache:entry_metadata(test_llm_repo, 'cat/pkg-1.0', iuse, 'foo')),
      assertz(cache:entry_metadata(test_llm_repo, 'cat/pkg-1.0', iuse, 'python_targets_python3_12')),
      assertz(cache:entry_metadata(test_llm_repo, 'cat/pkg-1.0', slot, slot('1'))),
      assertz(cache:entry_metadata(test_llm_repo, 'cat/pkg-1.0', keywords, stable(amd64))),
      unittest:accept_stable_amd64
    ),
    with_output_to(string(_),
      ( % llm.pl + chatgpt/claude/gemini/grok/ollama
        llm:check_api_key(ollama, ''),
        llm:check_api_key(grok, 'key123'),
        llm:check_api_key(grok, "key123"),
        \+ llm:check_api_key(grok, ''),
        \+ llm:check_api_key(grok, 123),
        wrap_predicate(prolog_edit:edit(EditFile), test_cov, _,
                       setup_call_cleanup(open(EditFile, write, ES), write(ES, 'hello'), close(ES))),
        wrap_predicate(http_open:http_open(Url, Stream, _Opts), test_cov, _,
          ( sub_atom(Url, _, _, _, 'embed')
          -> open_string("{\"embeddings\": [[1.0, 0.0]]}", Stream)
          ;  sub_atom(Url, _, _, _, 'anthropic')
          -> open_string("event: message_start\ndata: {\"type\":\"content_block_delta\",\"delta\":{\"text\":\"hi\"}}\ndata: {\"type\":\"message_delta\",\"delta\":{\"text\":\"!\"}}\ndata: {\"type\":\"other\"}\ndata: not_json\ndata: [DONE]\n", Stream)
          ;  open_string("\ndata: {\"choices\":[{\"delta\":{\"content\":\"hi\"}}]}\ndata: {\"choices\":[]}\nother line\ndata: [DONE]\n", Stream)
          )),
        wrap_predicate(config:llm_api_key(_Svc, Key), test_cov, _, Key = 'dummy_key'),
        chatgpt:chatgpt,
        claude:claude,
        gemini:gemini,
        grok:grok,
        ollama:ollama,
        claude:claude_llm_stream('dummy_key', 'claude-sonnet-4-5', [], 'hi', _),
        open_string("event: ping\ndata: {\"type\":\"content_block_delta\",\"delta\":{\"text\":\"ok\"}}\n", SCl),
        claude:process_stream_claude(SCl, _),
        close(SCl),
        % Tool call and error branches in llm.pl
        llm:prepare_history(['hi'], [_{role: user, content: 'q'}, _{role: assistant, content: 'old'}], _),
        llm:execute_and_get_output("ollama"-"hi", _),
        llm:execute_and_get_output("swi_prolog"-":- writeln(1).", _),
        llm:make_function_message(gemini, "out", _),
        llm:make_function_message(claude, "out", _),
        llm:make_function_message(grok, "out", _),
        llm:handle_response(
          [_, _, _, _, R]>>(R = _{contents: ["done"], history: []}),
          'k', 'm', 'u', grok:update_history,
          "<call:swi_prolog>:- true.</call:swi_prolog>", []),
        llm:handle_response(
          [_, _, _, _, R]>>(R = _{error: boom, history: []}),
          'k', 'm', 'u', grok:update_history,
          "<call:swi_prolog>:- true.</call:swi_prolog>", []),
        unwrap_predicate(http_open:http_open/3, test_cov),
        wrap_predicate(http_open:http_open(_, _, _), test_cov, _, throw(http_err)),
        llm:stream('http://localhost', 'k', 'm', [], _),
        claude:llm_stream_claude('http://localhost', 'k', 'm', [], _),
        grok:grok('hi', ''),
        \+ llm:embed('http://localhost', 'm', ["a"], _),
        unwrap_predicate(http_open:http_open/3, test_cov),
        unwrap_predicate(config:llm_api_key/2, test_cov),
        wrap_predicate(config:llm_api_key(_, _), test_cov, _, fail),
        grok:grok('hi', ''),
        unwrap_predicate(config:llm_api_key/2, test_cov),
        unwrap_predicate(prolog_edit:edit/1, test_cov),
        llm:extract_embeddings(_{embedding: [0.5, 0.5]}, [[0.5, 0.5]]),
        % knowledge.pl (llmknowledge)
        llmknowledge:list_topics,
        forall(llmknowledge:topic_text(Topic, _), llmknowledge:print_topic(Topic)),
        llmknowledge:print_topic(unknown_topic_xyz),
        llmknowledge:print_handbook(architecture),
        llmknowledge:print_handbook('04-doc-architecture'),
        llmknowledge:print_handbook(nonexistent_chapter_xyz),
        wrap_predicate(config:llm_knowledge_max_bytes(MaxB), test_cov, _, MaxB = 50),
        llmknowledge:print_handbook(architecture),
        unwrap_predicate(config:llm_knowledge_max_bytes/1, test_cov),
        llmknowledge:print_source('Source/Pipeline/prover.pl', 1, 5),
        llmknowledge:print_source('Source/Pipeline/prover.pl', 5, 5),
        llmknowledge:print_source('portage-ng.pl', 1, 500),
        llmknowledge:print_source('/etc/passwd', 1, 5),
        forall(member(Pfx, [
          'Source/Pipeline/a', 'Source/Domain/Gentoo/a', 'Source/Knowledge/a',
          'Source/Application/Llm/a', 'Source/Application/Interface/a',
          'Source/Logic/a', 'Documentation/Handbook/a', '.cursorrules', 'portage-ng.pl'
        ]), llmknowledge:allowed_prefix(Pfx)),
        % explain.pl
        empty_assoc(E0),
        put_assoc(rule(test_llm_repo://'cat/pkg-1.0':install), E0,
                  dep(1, [test_llm_repo://'cat/pkg-1.0':download?{[]},
                          test_llm_repo://'cat/pkg-1.0'])?[], E1),
        put_assoc(rule(assumed(test_llm_repo://'cat/pkg-1.0':run)), E1,
                  dep(0, [])?[], E2),
        put_assoc(assumed(rule(test_llm_repo://'cat/pkg-1.0':install)), E2,
                  dep(0, [])?[], ProofAVL),
        put_assoc(test_llm_repo://'cat/pkg-1.0':download, E0,
                  [test_llm_repo://'cat/pkg-1.0':install], TrigAVL),
        Plan = [
          [rule(test_llm_repo://'cat/pkg-1.0':install?{[
             build_with_use([assumed(foo), assumed(minus(bar))]),
             suggestion(use_change, 'cat/pkg-1.0', [use_change(foo, enable), use_change(bar, disable)]),
             replaces(test_llm_repo://'cat/pkg-1.0')
           ]}, []),
           rule(test_llm_repo://'cat/pkg-1.0':download?{[]}, []),
           rule(test_llm_repo://'missing/pkg-1.0':run?{[]}, []),
           rule(assumed(test_llm_repo://'cat/pkg-1.0':install?{[]}), []),
           rule(world('cat/pkg'):register?{[]}, []),
           other_rule],
          assumed(rule(test_llm_repo://'cat/pkg-1.0':install?{[]}, []))
        ],
        wrap_predicate(explainer:call_llm(_, _, ExpResp), test_cov, _, ExpResp = "ok"),
        explain:explain_plan('why?', [target(q, 'cat/pkg'):run?{[]}, test_llm_repo://'cat/pkg-1.0':install?{[]}],
                             ProofAVL, E0, Plan, TrigAVL),
        explain:explain_plan('why?', [], E0, E0, [], E0),
        open_string("\nwhy?\nquit\n", InExp),
        stream_property(OldInE, alias(user_input)),
        set_stream(InExp, alias(user_input)),
        call_cleanup(
          explain:explain_plan_interactive([], E0, E0, [], E0),
          ( set_stream(OldInE, alias(user_input)), close(InExp) )
        ),
        open_string("", InExpEof),
        set_stream(InExpEof, alias(user_input)),
        call_cleanup(
          explain:explain_plan_interactive([], E0, E0, [], E0),
          ( set_stream(OldInE, alias(user_input)), close(InExpEof) )
        ),
        unwrap_predicate(explainer:call_llm/3, test_cov),
        forall(member(Rsn, [preference, profile_package_use_force, package_use, ebuild,
                            profile_package_use_mask, other]),
               ( explain:format_one_flag(f, positive, Rsn, _),
                 explain:format_one_flag(f, negative, Rsn, _) )),
        assertz(preference:local_env_use(f)),
        assertz(preference:local_env_use(minus(f))),
        assertz(preference:local_profile_forced_use_flag(f)),
        assertz(preference:local_profile_masked_use_flag(f)),
        explain:format_one_flag(f, positive, preference, _),
        explain:format_one_flag(f, negative, preference, _),
        retractall(preference:local_env_use(f)),
        retractall(preference:local_env_use(minus(f))),
        explain:format_one_flag(f, positive, preference, _),
        explain:format_one_flag(f, negative, preference, _),
        retractall(preference:local_profile_forced_use_flag(f)),
        retractall(preference:local_profile_masked_use_flag(f)),
        explain:format_ctx_use_info(not_a_list, ''),
        explain:format_ctx_info(not_a_list, ''),
        explain:body_to_dep_strs(not_a_list, []),
        explain:lit_to_cn(test_llm_repo://'cat/pkg-1.0', 'cat/pkg'),
        explain:lit_to_cn(other_lit, 'other_lit'),
        explain:format_one_assumption(assumption(k, other, none), _),
        explain:format_assumptions_with_polarity(E0, E0, _),
        explain:format_assumptions_with_polarity(ProofAVL, E0, _),
        forall(member(AT, [masked, masked_dependency, keyword_filtered, keyword_filtered_dependency,
                           blocker_assumption, license, non_existent_dependency, missing_dependency,
                           required_use_violation, slot_conflict, version_no_candidate,
                           version_no_candidate_dependency, version_conflict,
                           version_conflict_dependency, unsatisfied_constraints,
                           issue_with_model, unknown_type]),
               explain:polarity_of_type(AT, _)),
        explain:format_fallback(unknown, _),
        explain:format_fallback(strict, _),
        assertz(feedback:unresolved_diagnostic(sym, ev)),
        assertz(feedback:discovered_dep(t, p, k, ev)),
        assertz(feedback:discovered_usedep(t, p, u, ev)),
        explain:format_feedback_backlog(_),
        retractall(feedback:unresolved_diagnostic(sym, ev)),
        retractall(feedback:discovered_dep(t, p, k, ev)),
        retractall(feedback:discovered_usedep(t, p, u, ev)),
        explain:format_feedback_backlog(_),
        explain:format_learned_domains_for_target(test_llm_repo://'cat/pkg-1.0', _),
        explain:format_learned_domains_for_target(test_llm_repo://'missing/pkg-1.0', _),
        explain:format_learned_domains_for_target(other_target, _),
        explain:format_log_tail(LogPath, _),
        explain:format_log_tail('/nonexistent_log_xyz', _),
        wrap_predicate(config:llm_metacircular_log_tail(MaxLT), test_cov, _, MaxLT = 5),
        explain:format_log_tail(LogPath, _),
        unwrap_predicate(config:llm_metacircular_log_tail/1, test_cov),
        % metacircular.pl
        fixup:mechanism(metacircular),
        fixup:mechanism_note(metacircular, 2, _),
        metacircular:diagnose_after_build([], E0, E0, [], E0, strict, 0),
        wrap_predicate(metacircular:interactive_available, test_cov, _, true),
        metacircular:diagnose_after_build([], E0, E0, [], E0, strict, 0),
        assertz(builder:last_failed(test_llm_repo://'cat/pkg-1.0', phase_fail, LogPath)),
        wrap_predicate(explainer:call_llm(_, _, MResp1), test_cov, _, MResp1 = ''),
        metacircular:diagnose_after_build([], E0, E0, [], E0, strict, 0),
        unwrap_predicate(explainer:call_llm/3, test_cov),
        wrap_predicate(explainer:call_llm(_, _, MResp2), test_cov, _, MResp2 = 'no proposal here'),
        metacircular:diagnose_failure(test_llm_repo://'cat/pkg-1.0', compile, LogPath, fail,
                                      ctx([], E0, E0, [], E0, strict), 0),
        unwrap_predicate(explainer:call_llm/3, test_cov),
        wrap_predicate(explainer:call_llm(_, _, MResp3), test_cov, _,
                       MResp3 = '```prolog\nrepair_proposal([invalid_act]).\n```'),
        metacircular:diagnose_failure(test_llm_repo://'cat/pkg-1.0', compile, LogPath, fail,
                                      ctx([], E0, E0, [], E0, strict), 0),
        unwrap_predicate(explainer:call_llm/3, test_cov),
        ProposalFence = "```\nrepair_proposal([\n  action(record_discovery, test_llm_repo://'cat/pkg-1.0', 'cat/pkg', bdepend, 'ev\\'1'),\n  action(record_usedep, test_llm_repo://'cat/pkg-1.0', 'cat/pkg', [use(enable(foo), none), use(disable(bar), none)], ev),\n  action(record_excluded_version, cat, pkg, '1.0', ev),\n  action(record_kernel_config, test_llm_repo://'cat/pkg-1.0', [config('CONFIG_FOO', y), 'CONFIG_BAR'], ev),\n  action(draft_fixup, test_draft_mech, 'syn', 'body')\n]).\n```",
        metacircular:parse_proposal(ProposalFence, ParsedActs),
        wrap_predicate(config:llm_metacircular_max_actions(MaxAct), test_cov, _, MaxAct = 10),
        metacircular:validate_actions(ParsedActs, ValidActs),
        unwrap_predicate(config:llm_metacircular_max_actions/1, test_cov),
        wrap_predicate(config:llm_metacircular_max_actions(MaxAct1), test_cov, _, MaxAct1 = 1),
        metacircular:validate_actions(ParsedActs, _),
        unwrap_predicate(config:llm_metacircular_max_actions/1, test_cov),
        metacircular:take_balanced([], 0, in_plain, [97], [97]),
        metacircular:validate_actions([a, b, c, d], _),
        metacircular:describe_action(other_act, _),
        \+ metacircular:write_draft_fixup('../unsafe', 's', 'b'),
        open_string("yes\nyes\nyes\nyes\nyes\nno\n", InMeta),
        stream_property(OldInM, alias(user_input)),
        set_stream(InMeta, alias(user_input)),
        call_cleanup(
          ( append(ValidActs, [action(record_excluded_version, c, p, v, e)], SixActs),
            metacircular:confirm_and_apply(SixActs, _)
          ),
          ( set_stream(OldInM, alias(user_input)), close(InMeta) )
        ),
        wrap_predicate(explainer:call_llm(_, _, MResp4), test_cov, _,
                       MResp4 = "repair_proposal([action(record_excluded_version, cat, pkg, '1.0', ev)])"),
        open_string("yes\nyes\n", InCli),
        set_stream(InCli, alias(user_input)),
        call_cleanup(
          ( metacircular:diagnose_cli(['cat/pkg'], [diagnoselog(LogPath)]),
            metacircular:diagnose_cli(['cat/nonexistent_atom'], [diagnoselog(LogPath)])
          ),
          ( set_stream(OldInM, alias(user_input)), close(InCli) )
        ),
        unwrap_predicate(explainer:call_llm/3, test_cov),
        \+ metacircular:diagnose_cli([], []),
        \+ metacircular:diagnose_cli(['cat/pkg'], [diagnoselog('/no_such_log_xyz')]),
        metacircular:default_log_for_atom('cat/pkg', _),
        metacircular:default_log_for_atom('cat/nonexistent_xyz', _),
        unwrap_predicate(metacircular:interactive_available/0, test_cov),
        wrap_predicate(metacircular:interactive_available, test_cov, _, fail),
        \+ metacircular:diagnose_cli(['cat/pkg'], []),
        unwrap_predicate(metacircular:interactive_available/0, test_cov),
        wrap_predicate(metacircular:llm_backend_available, test_cov, _, fail),
        \+ metacircular:diagnose_cli(['cat/pkg'], []),
        unwrap_predicate(metacircular:llm_backend_available/0, test_cov),
        retractall(builder:last_failed(_, _, _)),
        retractall(feedback:discovered_dep(_, _, _, _)),
        retractall(feedback:discovered_usedep(_, _, _, _)),
        retractall(feedback:excluded_version(_, _, _, _)),
        retractall(feedback:required_kernel_config(_, _, _)),
        % semantic.pl
        retractall(semantic:index_loaded),
        retractall(semantic:embedding(_, _, _)),
        wrap_predicate(http_open:http_open(_, _, _), test_cov, _, throw(ollama_down)),
        semantic:build_index,
        semantic:search("editor", 5, []),
        semantic:similar('cat', 'pkg', 5, []),
        unwrap_predicate(http_open:http_open/3, test_cov),
        wrap_predicate(llm:embed(_, _, Texts, Embs), test_cov, _,
          ( Texts = [_, _|_] -> fail
          ; maplist([_, [3.0, 4.0]]>>true, Texts, Embs)
          )),
        assertz(cache:package(test_llm_repo, 'cat2', 'pkg2')),
        assertz(cache:ordered_entry(test_llm_repo, 'cat2/pkg2-1.0', 'cat2', 'pkg2', V1)),
        semantic:build_index,
        unwrap_predicate(llm:embed/4, test_cov),
        wrap_predicate(llm:embed(_, _, Texts2, Embs2), test_cov, _,
                       maplist([_, [3.0, 4.0]]>>true, Texts2, Embs2)),
        semantic:build_index,
        retractall(semantic:index_loaded),
        semantic:search("editor", 1, _),
        unwrap_predicate(llm:embed/4, test_cov),
        wrap_predicate(llm:embed(_, _, _, _), test_cov, _, fail),
        semantic:search("editor", 5, []),
        unwrap_predicate(llm:embed/4, test_cov),
        semantic:similar('cat', 'pkg', 5, SimResults),
        semantic:similar('cat', 'missing_pkg', 5, []),
        semantic:print_results([]),
        semantic:print_results(SimResults),
        semantic:chunk_list([], 2, []),
        semantic:chunk_list([a, b, c], 2, [[a, b], [c]]),
        semantic:normalize_vector([0.0, 0.0], [0.0, 0.0]),
        open_string("other_term.\nsemantic:embedding(c, p, [1.0]).\n", SRead),
        semantic:read_terms(SRead),
        close(SRead),
        retractall(semantic:index_loaded),
        retractall(semantic:embedding(_, _, _))
      )),
    ( unittest:restore_stable_amd64,
      unsetenv('PORTAGE_NG_STATE'),
      retractall(cache:ordered_entry(test_llm_repo, _, _, _, _)),
      retractall(cache:package(test_llm_repo, _, _)),
      retractall(cache:entry_metadata(test_llm_repo, _, _, _)),
      catch(process_create(path(rm), ['-rf', TmpDir], [process(Pid)]), _, true),
      ( var(Pid) -> true ; process_wait(Pid, _) )
    )).

:- end_tests(interface_and_actions_full_coverage).

