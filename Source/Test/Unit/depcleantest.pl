/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> DEPCLEANTEST
Unit tests for the depclean structural predicates (Source/Domain/Gentoo/depclean.pl).

Model items, dependency-term category/name extraction and PROVIDES
tokens.
*/

:- module(depcleantest, []).

:- use_module(library(plunit)).
:- use_module(library(assoc)).
:- use_module(library(lists)).

% =============================================================================
%  DEPCLEANTEST declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Depclean structural predicate tests
% -----------------------------------------------------------------------------
:- begin_tests(depclean_model_item).

test(extract_depclean_bare, [true(R == myrepo://'cat/pkg-1.0')]) :-
  depclean:model_item_repo_entry(myrepo://'cat/pkg-1.0':depclean, R).

test(extract_depclean_ctx, [true(R == myrepo://'cat/pkg-1.0')]) :-
  depclean:model_item_repo_entry(myrepo://'cat/pkg-1.0':depclean?{[]}, R).

test(reject_non_depclean, [fail]) :-
  depclean:model_item_repo_entry(myrepo://'cat/pkg-1.0':install, _).

test(reject_plain_atom, [fail]) :-
  depclean:model_item_repo_entry(something, _).

:- end_tests(depclean_model_item).


:- begin_tests(depclean_dep_term_cn).

test(with_action_ctx, [true(A-C-N == run-'sys-libs'-glibc)]) :-
  depclean:dep_term_cn_deps(
    grouped_package_dependency(strong,'sys-libs',glibc,[dep1]):run?{[some_ctx]},
    A, C, N, _).

test(with_action_bare, [true(A-C-N == install-'dev-libs'-openssl)]) :-
  depclean:dep_term_cn_deps(
    grouped_package_dependency(weak,'dev-libs',openssl,[]):install,
    A, C, N, _).

test(no_action_defaults_run, [true(A-C-N == run-'app-misc'-foo)]) :-
  depclean:dep_term_cn_deps(
    grouped_package_dependency(strong,'app-misc',foo,[d1,d2]),
    A, C, N, _).

test(extracts_packagedeps, [true(PD == [d1,d2])]) :-
  depclean:dep_term_cn_deps(
    grouped_package_dependency(strong,c,n,[d1,d2]),
    _, _, _, PD).

:- end_tests(depclean_dep_term_cn).


:- begin_tests(depclean_provides_tok).

test(new_token, [true(V == [pkg://e1])]) :-
  empty_assoc(E),
  depclean:provides_tok_put(pkg://e1, 'libfoo.so', E, Out),
  get_assoc('libfoo.so', Out, V).

test(existing_token, [true(V == [pkg://e1, pkg://e2])]) :-
  list_to_assoc(['libfoo.so'-[pkg://e1]], In),
  depclean:provides_tok_put(pkg://e2, 'libfoo.so', In, Out),
  get_assoc('libfoo.so', Out, V).

:- end_tests(depclean_provides_tok).


% -----------------------------------------------------------------------------
%  Full depclean, pkgmoves, distfiles, set, and issue coverage
% -----------------------------------------------------------------------------

depcleantest_mktemp(Prefix, Dir) :-
  tmp_file(Prefix, Tmp),
  ( exists_file(Tmp) -> delete_file(Tmp) ; true ),
  make_directory(Tmp),
  Dir = Tmp.

depcleantest_rm_rf(Dir) :-
  ( exists_directory(Dir)
  -> catch(process_create(path(rm), ['-rf', Dir], [process(Pid)]), _, true),
     ( var(Pid) -> true ; process_wait(Pid, _) )
  ;  true
  ).

% Makes Dir the only answer of distfiles:get_location/1 and returns the
% clauses that were there before in Saved. With a knowledge base loaded
% that is the clause of the real distfiles repository. Fails when Dir is
% not the only answer afterwards.
depcleantest_swap_distfiles_location(Dir, Saved) :-
  findall(distfiles:(get_location(Location) :- Body),
          catch(clause(distfiles:get_location(Location), Body), _, fail),
          Saved),
  retractall(distfiles:get_location(_)),
  assertz(distfiles:get_location(Dir)),
  findall(Answer, distfiles:get_location(Answer), Answers),
  ( Answers == [Dir]
  -> true
  ;  depcleantest_restore_distfiles_location(Saved),
     fail
  ).

% Puts back the clauses that depcleantest_swap_distfiles_location/2 took
% away. They are stored as distfiles:(Head :- Body) so that their bodies
% run in the module they came from.
depcleantest_restore_distfiles_location(Saved) :-
  retractall(distfiles:get_location(_)),
  forall(member(Clause, Saved), assertz(Clause)).

:- begin_tests(depclean_and_gentoo_domain_full).

test(issue_known_tree_issues) :-
  issue:known_tree_issue('dev-php', 'composer', _),
  issue:known_tree_issue('dev-python', 'cryptography', _).

test(set_class_operations, [nondet]) :-
  depcleantest_mktemp(set_test, TmpDir),
  setup_call_cleanup(
    true,
    ( os:compose_path([TmpDir, 'sub', 'world_test'], SetFile),
      tset1:newinstance(set),
      tset1:init(SetFile),
      tset1:load,
      tset2:newinstance(set(SetFile)),
      tset2:register(['cat/a', 'cat/b']),
      tset2:register('cat/c'),
      tset2:register('cat/c'),
      tset2:save,
      tset1:load,
      tset1::entry("cat/a"),
      tset1::file(SetFile),
      tset1:unregister(["cat/a"]),
      tset1:unregister("cat/b"),
      forall(set:(_ ::- _), true)
    ),
    depcleantest_rm_rf(TmpDir)).

% distfiles:clean/1 deletes files. The distfiles directory of this machine
% is therefore taken out of distfiles:get_location/1 for the duration of
% the test, and the test does not start unless the temporary directory is
% the only location left.
test(distfiles_operations) :-
  depcleantest_mktemp(dist_test, TmpDir),
  setup_call_cleanup(
    ( depcleantest_swap_distfiles_location(TmpDir, SavedLocation),
      os:compose_path(TmpDir, 'foo-1.0.tar.gz', F1),
      os:compose_path(TmpDir, 'orphan-1.0.tar.gz', F2),
      setup_call_cleanup(open(F1, write, S1), write(S1, '12345'), close(S1)),
      setup_call_cleanup(open(F2, write, S2), write(S2, '678'), close(S2)),
      V1 = version([1,0], '', 4, 0, [], 0, '1.0'),
      assertz(cache:ordered_entry(qtest, 'dcat/dpkg-1.0', dcat, dpkg, V1)),
      assertz(cache:entry_metadata(qtest, 'dcat/dpkg-1.0', src_uri,
                                   uri(https, 'example.com/foo-1.0.tar.gz', 'foo-1.0.tar.gz'))),
      assertz(cache:manifest(qtest, m1, 0, dcat, dpkg)),
      assertz(cache:manifest_metadata(qtest, m1, dist, 'foo-1.0.tar.gz', 5, []))
    ),
    ( distfiles:present('foo-1.0.tar.gz'),
      distfiles:path('foo-1.0.tar.gz', _),
      catch(distfiles:path('../evil', _), error(permission_error(access, distfile, _), _), true),
      distfiles:list(['foo-1.0.tar.gz', 'orphan-1.0.tar.gz']),
      distfiles:file_size('foo-1.0.tar.gz', 5),
      distfiles:total_size(8),
      distfiles:orphans(qtest, ['orphan-1.0.tar.gz']),
      distfiles:clean(qtest),
      \+ distfiles:present('orphan-1.0.tar.gz'),
      retractall(distfiles:get_location(TmpDir)),
      assertz(distfiles:get_location('/tmp/nonexistent-portage-ng-distfiles-dir')),
      distfiles:list([])
    ),
    ( depcleantest_restore_distfiles_location(SavedLocation),
      retractall(cache:ordered_entry(qtest, 'dcat/dpkg-1.0', _, _, _)),
      retractall(cache:entry_metadata(qtest, 'dcat/dpkg-1.0', _, _)),
      retractall(cache:manifest(qtest, m1, _, _, _)),
      retractall(cache:manifest_metadata(qtest, m1, _, _, _, _)),
      depcleantest_rm_rf(TmpDir)
    )).

test(pkgmoves_loading_translation_and_world_moves, [nondet]) :-
  depcleantest_mktemp(pm_test, TmpDir),
  setup_call_cleanup(
    ( os:compose_path([TmpDir, 'profiles', 'updates'], UpdDir),
      make_directory_path(UpdDir),
      os:compose_path(UpdDir, '1Q-2025', Q1),
      setup_call_cleanup(open(Q1, write, SQ1),
        ( writeln(SQ1, 'move old-cat/old-pkg mid-cat/mid-pkg'),
          writeln(SQ1, 'slotmove ~app-editors/emacs-27.0.91 0 27'),
          writeln(SQ1, 'slotmove dev-libs/foo 1 2'),
          writeln(SQ1, 'malformed line')
        ),
        close(SQ1)),
      os:compose_path(UpdDir, '2Q-2025', Q2),
      setup_call_cleanup(open(Q2, write, SQ2),
        ( writeln(SQ2, 'move mid-cat/mid-pkg new-cat/new-pkg'),
          writeln(SQ2, 'move self-cat/self-pkg self-cat/self-pkg')
        ),
        close(SQ2)),
      assertz(cache:repository(pmtest_repo)),
      assertz(pmtest_repo:get_type(eapi)),
      assertz(pmtest_repo:get_location(TmpDir)),
      assertz(cache:package(pmtest_repo, 'in-tree-cat', 'in-tree-pkg')),
      os:compose_path(TmpDir, 'world', WorldFile),
      ( catch(world:declared(type(instance(set))), _, fail)
      -> world:init(WorldFile)
      ;  world:newinstance(set(WorldFile))
      ),
      world:register('old-cat/old-pkg'),
      world:save
    ),
    ( pkgmoves:load,
      pkgmoves:load_updates_dir('/tmp/nonexistent-portage-ng-updates-dir'),
      pkgmoves:moved('old-cat', 'old-pkg', 'new-cat', 'new-pkg'),
      pkgmoves:slotmoved('app-editors', emacs, _, '0', '27'),
      pkgmoves:slotmoved('dev-libs', foo, _, '1', '2'),
      pkgmoves:cn_in_tree('in-tree-cat', 'in-tree-pkg'),
      pkgmoves:strip_version('plainname', 'plainname'),
      pkgmoves:translate_atom('=old-cat/old-pkg-1.0:0[use]', '=new-cat/new-pkg-1.0:0[use]'),
      pkgmoves:translate_atom("old-cat/old-pkg:0", 'new-cat/new-pkg:0'),
      pkgmoves:translate_atom('old-cat/old-pkg[use]', 'new-cat/new-pkg[use]'),
      pkgmoves:translate_atom('old-cat/old-pkg', 'new-cat/new-pkg'),
      with_output_to(string(_),
        ( pkgmoves:apply_world_moves,
          pkgmoves:apply_world_moves
        )),
      world::entry('new-cat/new-pkg')
    ),
    ( retractall(cache:repository(pmtest_repo)),
      retractall(pmtest_repo:get_type(_)),
      retractall(pmtest_repo:get_location(_)),
      retractall(cache:package(pmtest_repo, _, _)),
      retractall(pkgmoves:pmove_(_, _, _, _)),
      retractall(pkgmoves:pslotmove_(_, _, _, _, _)),
      retractall(pkgmoves:loaded_),
      depcleantest_rm_rf(TmpDir)
    )).

test(depclean_end_to_end_and_helpers, [nondet]) :-
  depcleantest_mktemp(dc_test, TmpDir),
  V1 = version([1,0], '', 4, 0, [], 0, '1.0'),
  knowledgebase:vdb_repository(Vdb),
  findall(K, retract(preference:local_accept_keywords(K)), SavedKws),
  setup_call_cleanup(
    ( assertz(preference:local_accept_keywords(stable(amd64))),
      asserta(config:pkg_directory(TmpDir)),
      os:compose_path([TmpDir, 'dcat/root-1.0'], RootVdbDir),
      make_directory_path(RootVdbDir),
      os:compose_path(RootVdbDir, 'RDEPEND', RdepFile),
      setup_call_cleanup(open(RdepFile, write, SR),
        writeln(SR, '|| ( dcat/dep ) !dcat/blk'),
        close(SR)),
      assertz(cache:ordered_entry(Vdb, 'dcat/root-1.0', dcat, root, V1)),
      assertz(cache:entry_metadata(Vdb, 'dcat/root-1.0', slot, slot('0'))),
      assertz(cache:entry_metadata(Vdb, 'dcat/root-1.0', needed_elf2, ['liborphan.so'])),
      assertz(cache:ordered_entry(Vdb, 'dcat/dep-1.0', dcat, dep, V1)),
      assertz(cache:entry_metadata(Vdb, 'dcat/dep-1.0', slot, slot('0'))),
      assertz(cache:ordered_entry(Vdb, 'dcat/nokw-1.0', dcat, nokw, V1)),
      assertz(cache:entry_metadata(Vdb, 'dcat/nokw-1.0', slot, slot('0'))),
      assertz(cache:ordered_entry(Vdb, 'dcat/orphan-1.0', dcat, orphan, V1)),
      assertz(cache:entry_metadata(Vdb, 'dcat/orphan-1.0', slot, slot('0'))),
      assertz(cache:entry_metadata(Vdb, 'dcat/orphan-1.0', provides_elf2, ['liborphan.so'])),
      assertz(cache:ordered_entry(qtest, 'dcat/root-1.0', dcat, root, V1)),
      assertz(cache:entry_metadata(qtest, 'dcat/root-1.0', slot, slot('0'))),
      assertz(cache:entry_metadata(qtest, 'dcat/root-1.0', keywords, stable(amd64))),
      assertz(cache:entry_metadata(qtest, 'dcat/root-1.0', rdepend,
        package_dependency(run, no, dcat, dep, none, version_none, [], []))),
      assertz(cache:ordered_entry(qtest, 'dcat/dep-1.0', dcat, dep, V1)),
      assertz(cache:entry_metadata(qtest, 'dcat/dep-1.0', slot, slot('0'))),
      assertz(cache:entry_metadata(qtest, 'dcat/dep-1.0', keywords, stable(amd64))),
      assertz(cache:ordered_entry(qtest, 'dcat/nokw-1.0', dcat, nokw, V1)),
      assertz(cache:entry_metadata(qtest, 'dcat/nokw-1.0', slot, slot('0'))),
      assertz(cache:ordered_entry(qtest, 'dcat/orphan-1.0', dcat, orphan, V1)),
      assertz(cache:entry_metadata(qtest, 'dcat/orphan-1.0', slot, slot('0'))),
      assertz(cache:entry_metadata(qtest, 'dcat/orphan-1.0', keywords, stable(amd64))),
      os:compose_path(TmpDir, 'world', WorldFile),
      ( catch(world:declared(type(instance(set))), _, fail)
      -> world:init(WorldFile)
      ;  world:newinstance(set(WorldFile))
      )
    ),
    ( depclean:uninstall_order([], [], []),
      depclean:installed_to_repo_entry(Vdb://'dcat/nokw-1.0', qtest://'dcat/nokw-1.0'),
      depclean:roots_from_args(['dcat/root', 'dcat/nonexistent'], [qtest://'dcat/root-1.0']),
      depclean:direct_deps_installed(Vdb://'dcat/root-1.0', [Vdb://'dcat/dep-1.0']),
      assertz(preference:local_flag(nodynamicdeps)),
      depclean:direct_deps_installed(Vdb://'dcat/root-1.0', [Vdb://'dcat/dep-1.0']),
      retractall(preference:local_flag(nodynamicdeps)),
      depclean:recorded_dep_leaves([non_pkg_leaf], []),
      depclean:build_provides_map([Vdb://'dcat/orphan-1.0', Vdb://'dcat/dep-1.0'], ProvMap),
      depclean:collect_broken_needed([Vdb://'dcat/root-1.0'], [Vdb://'dcat/root-1.0'],
                                     [Vdb://'dcat/orphan-1.0'], ProvMap,
                                     [broken(Vdb://'dcat/root-1.0', 'liborphan.so', [Vdb://'dcat/orphan-1.0'])]),
      with_output_to(string(_),
        ( depclean:run([]),
          depclean:run(['dcat/root'])
        ))
    ),
    ( retractall(preference:local_accept_keywords(_)),
      forall(member(K, SavedKws), assertz(preference:local_accept_keywords(K))),
      retractall(config:pkg_directory(TmpDir)),
      retractall(cache:ordered_entry(Vdb, _, dcat, _, _)),
      retractall(cache:entry_metadata(Vdb, 'dcat/root-1.0', _, _)),
      retractall(cache:entry_metadata(Vdb, 'dcat/dep-1.0', _, _)),
      retractall(cache:entry_metadata(Vdb, 'dcat/nokw-1.0', _, _)),
      retractall(cache:entry_metadata(Vdb, 'dcat/orphan-1.0', _, _)),
      retractall(cache:ordered_entry(qtest, _, dcat, _, _)),
      retractall(cache:entry_metadata(qtest, 'dcat/root-1.0', _, _)),
      retractall(cache:entry_metadata(qtest, 'dcat/dep-1.0', _, _)),
      retractall(cache:entry_metadata(qtest, 'dcat/nokw-1.0', _, _)),
      retractall(cache:entry_metadata(qtest, 'dcat/orphan-1.0', _, _)),
      memo:clear_caches,
      depcleantest_rm_rf(TmpDir)
    )).

:- end_tests(depclean_and_gentoo_domain_full).
