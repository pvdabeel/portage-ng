/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> COVERAGE
Clause-level coverage harness built on SWI-Prolog's library(prolog_coverage).

Runs the PLUnit suite (Source/Test/unittest.pl), the synthetic overlay
regression suite (Source/Test/test.pl), or both under coverage/2, and
produces a complete per-file clause coverage report across Source/.

Addresses two limitations in upstream prolog_coverage:show_coverage/1:
  1. Upstream report_file/5 omits loaded files with 0% coverage
     (\+ (Sets.failed == [], Sets.succeeded == [])). This module includes
     all loaded production files under Source/ by default.
  2. Upstream uncovered_clause_line/3 has an unbound-variable bug that
     prevents non-annotated per-clause reporting. This module inspects
     prolog_coverage:cov_clause_sets/4 directly to emit exact uncovered
     predicate indicators and line numbers per file.
  3. SWI-Prolog's VM coverage collector skips dynamic predicates and
     compile-time expansion hooks (goal_expansion/2, term_expansion/2),
     yet upstream clean_set/2 leaves them in the denominator. This module
     filters out dynamic and compile-time expansion clauses so 100%
     reflects all instrumentable runtime clauses.

Usage via make:

  make coverage

Or interactively / filtered to a specific module or directory:

  swipl --stack-limit=4G -f portage-ng.pl -p portage=. -Dverbose_autoload=false \
    -g "load_modules(common), load_modules(standalone),
        load_files(portage('Source/Test/coverage'), [if(true)]),
        coverage_run([filter('Pipeline/prover.pl'), uncovered(true)]),
        halt(0)"
*/

:- module(test_coverage, [coverage_run/0,
                          coverage_run/1,
                          coverage_report/0,
                          coverage_report/1]).

:- use_module(library(prolog_coverage)).
:- use_module(library(lists)).
:- use_module(library(option)).
:- use_module(library(pairs)).


% =============================================================================
%  COVERAGE declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Environment preparation
% -----------------------------------------------------------------------------

%! test_coverage:ensure_environment is det.
%
% Ensures all production module groups, unit tests, and the overlay
% regression harness are loaded, and initializes in-memory knowledgebase
% and preference state without loading the full on-disk kb.qlf.

test_coverage:ensure_environment :-
  load_files(portage('Source/Test/unittest'), [if(true)]),
  loader:load_test_modules,
  ( catch(stats:declared(type(instance(stat))), _, fail)
  -> true
  ;  stats:newinstance(stat)
  ),
  ( catch(kb:declared(type(instance(knowledgebase))), _, fail)
  -> true
  ;  kb:newinstance(knowledgebase),
     preference:init
  ).


% -----------------------------------------------------------------------------
%  Public entry points
% -----------------------------------------------------------------------------

%! coverage_run is semidet.
%! coverage_run(+Options) is semidet.
%
% Run the configured test suite(s) under library(prolog_coverage) and
% print the resulting coverage report.
%
% Options:
%   * suite(Suite)        -- `all` (default: plunit + overlay),
%                            `plunit`, `plunit(Units)`, or `overlay`
%   * filter(Substr)      -- only report files under Source/ whose relative
%                            path contains Substr (default '')
%   * include_zero(Bool)  -- include 0%-covered loaded files (default true)
%   * uncovered(Bool)     -- list uncovered clauses + line numbers per file
%                            (default: true when filter/1 is non-empty,
%                             false otherwise)
%   * dir(Dir)            -- also emit annotated .cov files into Dir

coverage_run :-
  coverage_run([]).

coverage_run(Options) :-
  test_coverage:ensure_environment,
  option(suite(Suite), Options, all),
  test_coverage:suite_goal(Suite, Goal),
  cov_reset,
  coverage(Goal, [show(false)]),
  ( option(dir(Dir), Options)
  -> show_coverage([roots([portage('Source')]), dir(Dir)])
  ;  true
  ),
  coverage_report(Options).


%! test_coverage:suite_goal(+Suite, -Goal) is det.
%
% Map a suite specification to the callable test goal.

test_coverage:suite_goal(all, (plunit:run_tests, test:run(cases, batch))) :- !.
test_coverage:suite_goal(plunit, plunit:run_tests) :- !.
test_coverage:suite_goal(plunit(Units), plunit:run_tests(Units)) :- !.
test_coverage:suite_goal(overlay, test:run(cases, batch)) :- !.
test_coverage:suite_goal(Goal, Goal).


% -----------------------------------------------------------------------------
%  Reporting
% -----------------------------------------------------------------------------

%! coverage_report is det.
%! coverage_report(+Options) is det.
%
% Inspect currently collected prolog_coverage data and print the summary
% table and (optionally) uncovered clause line numbers.

coverage_report :-
  coverage_report([]).

coverage_report(Options) :-
  option(filter(Filter), Options, ''),
  option(include_zero(IncludeZero), Options, true),
  ( option(uncovered(ShowUncov), Options)
  -> true
  ;  ( Filter \== '', Filter \== [] -> ShowUncov = true ; ShowUncov = false )
  ),
  prolog_coverage:covered(Succeeded, Failed),
  absolute_file_name(portage('Source'), Root, [file_type(directory)]),
  atom_concat(Root, '/', RootSlash),
  findall(File,
          ( source_file(File)
          ; prolog_coverage:source_includes(_, File)
          ),
          Files0),
  sort(Files0, Files),
  findall(row(Rel, Total, Cov, Uncov, Fail, UncovClauses),
          ( member(File, Files),
            atom_concat(RootSlash, Rel, File),
            \+ sub_atom(Rel, 0, _, _, 'Test/'),
            \+ sub_atom(Rel, 0, _, _, 'Config/'),
            test_coverage:matches_filter(Rel, Filter),
            prolog_coverage:cov_clause_sets(File, Succeeded, Failed, Sets0),
            prolog_coverage:deduplicate_clauses(File, Sets0, Sets),
            get_dict(clauses, Sets, AllClauses0),
            get_dict(uncovered, Sets, UncovClauses0),
            get_dict(failed, Sets, FailClauses0),
            exclude(test_coverage:non_instrumentable_clause, AllClauses0, AllClauses),
            exclude(test_coverage:non_instrumentable_clause, UncovClauses0, UncovClauses),
            exclude(test_coverage:non_instrumentable_clause, FailClauses0, FailClauses),
            length(AllClauses, Total),
            Total > 0,
            length(UncovClauses, Uncov),
            length(FailClauses, Fail),
            Cov is Total - Uncov,
            ( IncludeZero == true -> true ; Cov > 0 )
          ),
          Rows),
  test_coverage:print_summary_table(Rows),
  ( ShowUncov == true
  -> test_coverage:print_uncovered_details(Rows)
  ;  true
  ).


%! test_coverage:non_instrumentable_clause(+ClauseOrSet) is semidet.
%
% True when Clause belongs to a dynamic predicate (which SWI-Prolog's VM
% coverage engine does not instrument) or a compile-time expansion hook
% (goal_expansion/2, term_expansion/2).

test_coverage:non_instrumentable_clause(ClOrSet) :-
  ( ClOrSet = [Cl|_] -> true ; Cl = ClOrSet ),
  clause(Module:Head, _, Cl),
  ( predicate_property(Module:Head, dynamic)
  ; functor(Head, goal_expansion, 2)
  ; functor(Head, term_expansion, 2)
  ),
  !.


%! test_coverage:matches_filter(+RelPath, +Filter) is semidet.
%
% True when Filter is empty ('' or []), or RelPath contains Filter (atom),
% or RelPath contains at least one element of Filter (list).

test_coverage:matches_filter(_Rel, '') :- !.
test_coverage:matches_filter(_Rel, []) :- !.
test_coverage:matches_filter(Rel, Filters) :-
  is_list(Filters),
  !,
  member(F, Filters),
  sub_atom(Rel, _, _, _, F),
  !.
test_coverage:matches_filter(Rel, Filter) :-
  sub_atom(Rel, _, _, _, Filter).


%! test_coverage:print_summary_table(+Rows) is det.
%
% Print a formatted per-file coverage table and aggregate footer.

test_coverage:print_summary_table(Rows) :-
  nl,
  format('~`=t~96|~n', []),
  format('~w~t~w~62|~t~w~70|~t~w~78|~t~w~87|~t~w~96|~n',
         ['File (under Source/)', 'Clauses', 'Cov', 'Uncov', '%Cov', '%Fail']),
  format('~`-t~96|~n', []),
  forall(member(row(Rel, Total, Cov, Uncov, Fail, _), Rows),
         ( PctCov is 100.0 * Cov / Total,
           PctFail is 100.0 * Fail / Total,
           format('~w ~`.t ~d~62| ~t~d~70| ~t~d~78| ~t~1f%~87| ~t~1f%~96|~n',
                  [Rel, Total, Cov, Uncov, PctCov, PctFail])
         )),
  format('~`-t~96|~n', []),
  length(Rows, NFiles),
  findall(T, member(row(_, T, _, _, _, _), Rows), Ts), sum_list(Ts, TotalAll),
  findall(C, member(row(_, _, C, _, _, _), Rows), Cs), sum_list(Cs, CovAll),
  findall(U, member(row(_, _, _, U, _, _), Rows), Us), sum_list(Us, UncovAll),
  findall(F, member(row(_, _, _, _, F, _), Rows), Fs), sum_list(Fs, FailAll),
  ( TotalAll > 0
  -> PctAll is 100.0 * CovAll / TotalAll,
     PctFailAll is 100.0 * FailAll / TotalAll
  ;  PctAll = 0.0,
     PctFailAll = 0.0
  ),
  format('TOTAL (~d files) ~`.t ~d~62| ~t~d~70| ~t~d~78| ~t~1f%~87| ~t~1f%~96|~n',
         [NFiles, TotalAll, CovAll, UncovAll, PctAll, PctFailAll]),
  format('~`=t~96|~n', []).


%! test_coverage:print_uncovered_details(+Rows) is det.
%
% For each row with uncovered clauses, print the predicate indicator and
% source line numbers of every uncovered clause.

test_coverage:print_uncovered_details(Rows) :-
  forall(( member(row(Rel, Total, _Cov, Uncov, _Fail, UncovClauses), Rows),
           Uncov > 0
         ),
         ( nl,
           format('Uncovered clauses in ~w (~d/~d):~n', [Rel, Uncov, Total]),
           findall(PI-Line,
                   ( member(ClOrSet, UncovClauses),
                     ( ClOrSet = [Cl|_] -> true ; Cl = ClOrSet ),
                     prolog_coverage:clause_pi(Cl, PI),
                     clause_property(Cl, line_count(Line))
                   ),
                   Pairs0),
           sort(Pairs0, Pairs),
           group_pairs_by_key(Pairs, Grouped),
           forall(member(PI-Lines, Grouped),
                  format('  ~q ~`.t ~56| lines ~w~n', [PI, Lines]))
         )).
