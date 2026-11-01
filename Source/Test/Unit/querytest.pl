/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> QUERYTEST
Unit tests for the query layer (Source/Knowledge/query.pl).

The hazard-encoded dependency-model cache key, the compile_query_compound
macro table (portage-ng#32) and macro-vs-runtime equivalence
(portage-ng#59). Synthetic cache facts under a private qtest
repository; no knowledge base is needed.
*/

:- module(querytest, []).

:- use_module(library(plunit)).
:- use_module(library(lists)).
:- use_module(library(prolog_wrap)).
:- use_module(portage('Source/Test/Unit/fixture')).

% =============================================================================
%  QUERYTEST declarations
% =============================================================================

:- begin_tests(dep_model_cache).

% Hazard-encoded cache key for model(dependency) queries (see the
% "Dependency-model cache key" section in Source/Knowledge/query.pl).

test(choice_cn_extraction_only_inside_choice_groups) :-
  T1 = any_of_group([package_dependency(install,no,'dev-lang','python',none,version_none,[],[]),
                     all_of_group([package_dependency(install,no,'dev-lang','pypy',none,version_none,[],[])])]),
  findall(CN, query:dep_model_choice_cn(T1, CN), CNs1),
  msort(CNs1, ['dev-lang'-'pypy', 'dev-lang'-'python']),
  % package deps NOT under a choice group are not choice CNs
  T2 = all_of_group([package_dependency(install,no,'sys-libs','zlib',none,version_none,[],[])]),
  findall(CN2, query:dep_model_choice_cn(T2, CN2), []),
  % choice group nested under a conditional is still found
  T3 = use_conditional_group(positive, foo, r://e,
         [exactly_one_of_group([package_dependency(install,no,'app-misc','a',none,version_none,[],[])])]),
  findall(CN3, query:dep_model_choice_cn(T3, CN3), ['app-misc'-'a']).

test(choice_sig_reflects_snapshot_presence,
     [setup(( stash_selected_cn_snap(Saved),
              retractall(memo:dep_model_choice_cns_(_, _, _)),
              assertz(memo:dep_model_choice_cns_(testrepo, 'x/y-1', ['dev-lang'-'python'])) )),
      cleanup(( restore_selected_cn_snap(Saved),
                retractall(memo:dep_model_choice_cns_(_, _, _)) ))]) :-
  query:dep_model_selected_choice_cns(testrepo, 'x/y-1', []),
  cnselect:record_selected_cn_snapshot('dev-lang', 'python', [selected(portage,'dev-lang/python-3.13',run,v,'3.13')]),
  query:dep_model_selected_choice_cns(testrepo, 'x/y-1',
    ['dev-lang'-'python'-[portage://'dev-lang/python-3.13']]),
  cnselect:record_selected_cn_snapshot('dev-lang', 'python', [selected(portage,'dev-lang/python-3.12',run,v,'3.12')]),
  query:dep_model_selected_choice_cns(testrepo, 'x/y-1', Sig312),
  Sig312 \== ['dev-lang'-'python'-[portage://'dev-lang/python-3.13']].

test(choice_sig_zero_without_choice_groups,
     [setup(( retractall(memo:dep_model_choice_cns_(_, _, _)),
              assertz(memo:dep_model_choice_cns_(testrepo, 'x/z-1', [])) )),
      cleanup(retractall(memo:dep_model_choice_cns_(_, _, _)))]) :-
  query:dep_model_selected_choice_cns(testrepo, 'x/z-1', []).

test(assuming_bits_reflect_prover_scopes) :-
  query:dep_model_assuming([]),
  prover:assuming(conflicts, query:dep_model_assuming([conflicts])),
  prover:assuming(keyword_acceptance,
    prover:assuming(blockers, query:dep_model_assuming([keyword_acceptance, blockers]))),
  query:dep_model_assuming([]).

test(key_none_for_nonground_context) :-
  query:dep_model_key(testrepo, 'x/y-1', [build_with_use:use_state([_Var], [])], none).

test(key_none_while_variant_active,
     [setup(assertz(variant:branch_prefer(package_dependency(install,no,'a','b',none,version_none,[],[])))),
      cleanup(retractall(variant:branch_prefer(_)))]) :-
  query:dep_model_key(testrepo, 'x/y-1', [build_with_use:use_state([], [])], none).

test(key_encodes_context_bits_and_sig,
     [setup(( stash_selected_cn_snap(Saved),
              retractall(memo:dep_model_choice_cns_(_, _, _)),
              assertz(memo:dep_model_choice_cns_(testrepo, 'x/y-1', ['dev-lang'-'python'])) )),
      cleanup(( restore_selected_cn_snap(Saved),
                retractall(memo:dep_model_choice_cns_(_, _, _)) ))]) :-
  Ctx = [build_with_use:use_state([icu], [])],
  query:dep_model_learned(Learned),
  query:dep_model_key(testrepo, 'x/y-1', Ctx, key(Ctx, [], [], Learned)),
    prover:assuming(unmask,
    query:dep_model_key(testrepo, 'x/y-1', Ctx, key(Ctx, [unmask], [], Learned))).

% Hazard 5: config-time arm rejection reads the learned store, so a
% learned domain must change the key (portage-ng#123).
test(key_encodes_learned_store,
     [setup(( stash_selected_cn_snap(Saved),
              ( nb_current(prover_learned_constraints, OldL) -> nb_setval(qt_saved_learned, OldL)
              ; nb_setval(qt_saved_learned, none) ) )),
      cleanup(( restore_selected_cn_snap(Saved),
                ( nb_current(qt_saved_learned, S), S \== none ->
                    nb_setval(prover_learned_constraints, S)
                ; nb_delete(prover_learned_constraints) ) ))]) :-
  Ctx = [build_with_use:use_state([], [])],
  query:dep_model_key(testrepo, 'x/y-1', Ctx, key(_, _, _, Before)),
  prover:learn(cn_domain('dev-lang', ghc, any),
               version_domain(any, [bound(smaller, version([9,5],'',4,0,[],0,'9.5'))]), _),
  query:dep_model_key(testrepo, 'x/y-1', Ctx, key(_, _, _, After)),
  Before \== After.

:- end_tests(dep_model_cache).


% -----------------------------------------------------------------------------
%  Query macro layer (portage-ng#32)
% -----------------------------------------------------------------------------
% Regression tests for the compile_query_compound macro table: tilde targets,
% select(keyword/keywords) metadata key, maintainer clause arity, and slot
% filters on operator-less (none) targets. Each query form is exercised
% through both paths:
%   - expanded:  the query is a literal in the test source, so
%                user:goal_expansion/2 inlines the cache goals at compile time
%   - runtime:   the query is constructed at runtime (parsed or =..-built),
%                so query:search/2 compiles it via the same macro table at
%                call time
% Uses synthetic cache facts under a private 'qtest' repository; no KB needed.

query_macros_setup :-
  query_macros_cleanup,
  assertz(cache:ordered_entry(qtest, 'dev-test/foo-2.0', 'dev-test', foo,
                              version([2,0],'',4,0,[],0,'2.0'))),
  assertz(cache:ordered_entry(qtest, 'dev-test/foo-1.0-r1', 'dev-test', foo,
                              version([1,0],'',4,0,[],1,'1.0-r1'))),
  assertz(cache:ordered_entry(qtest, 'dev-test/foo-1.0', 'dev-test', foo,
                              version([1,0],'',4,0,[],0,'1.0'))),
  assertz(cache:entry_metadata(qtest, 'dev-test/foo-1.0',    slot, slot('1'))),
  assertz(cache:entry_metadata(qtest, 'dev-test/foo-1.0-r1', slot, slot('1'))),
  assertz(cache:entry_metadata(qtest, 'dev-test/foo-2.0',    slot, slot('2'))),
  assertz(cache:entry_metadata(qtest, 'dev-test/foo-1.0', keywords, stable(amd64))),
  assertz(cache:entry_metadata(qtest, 'dev-test/foo-2.0', keywords, unstable(amd64))),
  assertz(cache:entry_metadata(qtest, 'dev-test/foo-1.0', maintainer,
                               ['dev@example.org','other@example.org'])).

query_macros_cleanup :-
  retractall(cache:ordered_entry(qtest,_,_,_,_)),
  retractall(cache:entry_metadata(qtest,_,_,_)).

:- begin_tests(query_macros, [setup(query_macros_setup),
                              cleanup(query_macros_cleanup)]).

% The arity-typo class (body goals written as extra head arguments) must not
% silently define compile_query_compound/4 or /5; query.pl also fails loudly
% at load time via a directive when this happens.
test(no_wrong_arity_macro_clauses) :-
  \+ current_predicate(query:compile_query_compound/4),
  \+ current_predicate(query:compile_query_compound/5).

% Tilde targets must match any revision of the given version (runtime path,
% parsed exactly like a CLI target).
test(tilde_target_runtime, [true(Ids == ['dev-test/foo-1.0','dev-test/foo-1.0-r1']), nondet]) :-
  atom_codes('~dev-test/foo-1.0', Codes),
  phrase(eapi:qualified_target(Q), Codes),
  findall(I, query:search(Q, qtest://I), Ids0),
  msort(Ids0, Ids).

% Same query as a source literal (goal-expanded path).
test(tilde_target_expanded, [true(Ids == ['dev-test/foo-1.0','dev-test/foo-1.0-r1'])]) :-
  findall(I,
          query:search(qualified_target(tilde, qtest, 'dev-test', foo,
                                        version([1,0],'',4,0,[],0,'1.0'),
                                        [[],[]]),
                       qtest://I),
          Ids0),
  msort(Ids0, Ids).

% Slot restrictions on operator-less targets must filter candidates
% (previously dropped at query level).
test(cn_target_slot_filter_runtime, [true(Ids == ['dev-test/foo-2.0'])]) :-
  atom_codes('dev-test/foo:2', Codes),
  phrase(eapi:qualified_target(Q), Codes),
  findall(I, query:search(Q, qtest://I), Ids0),
  msort(Ids0, Ids).

% Operator-less target without restrictions still returns all versions
% (goal-expanded path, empty filters).
test(cn_target_expanded_all, [true(N == 3)]) :-
  findall(I,
          query:search(qualified_target(none, qtest, 'dev-test', foo,
                                        version_none, [[],[]]),
                       qtest://I),
          Ids),
  length(Ids, N).

% select(keyword/keywords) must query the 'keywords' metadata key.
test(select_keyword_expanded, [true(Ids == ['dev-test/foo-1.0'])]) :-
  findall(I, query:search(select(keyword,equal,stable(amd64)), qtest://I), Ids0),
  msort(Ids0, Ids).

test(select_keywords_runtime, [true(Ids == ['dev-test/foo-1.0'])]) :-
  Q =.. [select, keywords, equal, stable(amd64)],
  findall(I, query:search(Q, qtest://I), Ids0),
  msort(Ids0, Ids).

% maintainer(M) enumerates list members (previously a wrong-arity clause, so
% the inlining never happened).
test(maintainer_expanded, [true(Ms == ['dev@example.org','other@example.org'])]) :-
  findall(M, query:search(maintainer(M), qtest://'dev-test/foo-1.0'), Ms0),
  msort(Ms0, Ms).

test(select_maintainer_runtime, [true(Ids == ['dev-test/foo-1.0'])]) :-
  Q =.. [select, maintainer, equal, 'dev@example.org'],
  findall(I, query:search(Q, qtest://I), Ids0),
  msort(Ids0, Ids).

% is_cn_target/1 only recognises the version_none form (the stale
% pre-version/7 list form is gone).
test(is_cn_target_version_none) :-
  target:is_cn_target(qualified_target(none, _, 'dev-test', foo, version_none, [[],[]])).

test(is_cn_target_rejects_versioned, [fail]) :-
  target:is_cn_target(qualified_target(none, _, 'dev-test', foo,
                                       version([1,0],'',4,0,[],0,'1.0'), [[],[]])).

:- end_tests(query_macros).


% -----------------------------------------------------------------------------
%  Query macro vs runtime dedup (portage-ng#59)
% -----------------------------------------------------------------------------
% compile_query_compound/3 is the single source of truth for every query form
% it covers: the runtime query:search/2 entry clause compiles the query at
% call time and executes the same cache-level goal the compile-time expansion
% would inline (the former duplicate runtime clauses for version comparisons,
% slot constraints, iuse and maintainer were deleted). These tests pin:
%   (a) macro coverage  — forms that must compile to cache-level goals
%                         rather than the runtime fallback,
%   (b) equivalence     — the runtime (=..-built) path returns the same
%                         results as directly executing the compiled goal,
%   (c) hook guards     — the module-local expansion hooks neither fire for
%                         foreign modules nor bind call-site variables.

query_dedup_setup :-
  query_macros_setup,
  assertz(cache:entry_metadata(qtest, 'dev-test/foo-1.0', iuse, plus(minimal))),
  assertz(cache:entry_metadata(qtest, 'dev-test/foo-1.0', iuse, doc)).

query_dedup_cleanup :-
  query_macros_cleanup.

% Runtime path (query:search/2 on a runtime-constructed query) and expanded
% path (executing the compile_query_compound/3 goal directly) must agree.
issue59_runtime_vs_expanded(Q) :-
  copy_term(Q, Qr),
  findall(I1, query:search(Qr, qtest://I1), Rs0),
  msort(Rs0, Rs),
  copy_term(Q, Qe),
  query:compile_query_compound(Qe, qtest://I2, G),
  findall(I2, call(G), Es0),
  msort(Es0, Es),
  Rs == Es.

:- begin_tests(query_dedup, [setup(query_dedup_setup),
                             cleanup(query_dedup_cleanup)]).

% (a) Macro coverage: these forms must compile to cache-level goals, not to
% the search/2 runtime fallback (guards against macro rot reintroducing a
% second, runtime-only implementation).
test(issue59_macro_coverage) :-
  V = version([1,0],'',4,0,[],0,'1.0'),
  forall(member(Q, [ name(_), category(_), version(_), slot(_), keyword(_),
                     iuse(_), masked(true), masked(false),
                     installed(true), installed(false),
                     dependency(_,run), dependency(_,install),
                     dependency(_,fetchonly),
                     select(version,equal,V), select(version,greaterequal,V),
                     select(version,tilde,V), select(name,wildcard,_),
                     select(slot,equal,_), select(slot,constraint([]),_),
                     select(slot,constraint([slot(_)]),_),
                     select(slot,constraint([any_same_slot]),_),
                     select(masked,equal,true), select(installed,equal,true),
                     select(maintainer,equal,_),
                     all(depend(_)), all(dependency(_,run)) ]),
         ( query:compile_query_compound(Q, _R://_I, G),
           G \= search(_,_) )).

% A slot constraint whose list skeleton is still unbound is deferred to the
% runtime fallback (and re-compiled at call time once it is bound).
test(issue59_unbound_slot_constraint_defers) :-
  query:compile_query_compound(select(slot,constraint(C),Sn), R://I, G),
  var(C),
  G == search(select(slot,constraint(C),Sn), R://I).

% (b) Equivalence per query form whose runtime duplicate was deleted.
test(issue59_runtime_matches_expanded) :-
  V10 = version([1,0],'',4,0,[],0,'1.0'),
  forall(member(Q, [ select(version,equal,V10),
                     select(version,greater,V10),
                     select(version,greaterequal,V10),
                     select(version,smaller,V10),
                     select(version,smallerequal,V10),
                     select(version,notequal,V10),
                     select(version,tilde,V10),
                     select(version,wildcard,version(_,_,_,_,_,_,'1.0*')),
                     select(slot,constraint([]),_),
                     select(slot,constraint([slot('1')]),_),
                     select(slot,constraint([slot(_)]),_),
                     select(slot,constraint([any_same_slot]),_),
                     select(slot,constraint([any_different_slot]),_),
                     select(maintainer,equal,'dev@example.org'),
                     iuse(_),
                     installed(false) ]),
         issue59_runtime_vs_expanded(Q)).

% A runtime slot-constraint query with an unbound inner slot argument
% (formerly served by the deleted runtime clauses) binds it from the cache.
test(issue59_slot_constraint_runtime_var_inner,
     [true(S-Sn == '1'-[slot('1')])]) :-
  Q =.. [select, slot, constraint([slot(S)]), Sn],
  once(query:search(Q, qtest://'dev-test/foo-1.0')).

% A runtime slot-constraint query whose entire skeleton is still a variable
% is served by the runtime-only generator clause: it commits to the first
% matching skeleton pattern ([], all slot metadata) exactly like the
% head-unification + cut of the former runtime clauses.
test(issue59_slot_constraint_runtime_var_skeleton,
     [true(C-Sn == []-[slot('1')])]) :-
  Q =.. [select, slot, constraint(C), Sn],
  once(query:search(Q, qtest://'dev-test/foo-1.0')).

test(issue59_slot_constraint_runtime_var_skeleton_enumerates,
     [true(N == 3)]) :-
  Q =.. [select, slot, constraint(_), _],
  aggregate_all(count, query:search(Q, qtest://_), N).

% A variable operator at call time behaves like the 'none' operator
% (mirrors the former runtime clause, which unified it with 'none').
test(issue59_version_var_op_behaves_as_none, [true(N == 3)]) :-
  Q =.. [select, version, _Op, _V],
  aggregate_all(count, query:search(Q, qtest://_), N).

% List queries constructed at runtime go through the same compile-then-call
% path as compile-time literals.
test(issue59_list_query_runtime, [true(Ids == ['dev-test/foo-2.0'])]) :-
  QL = [category('dev-test'), name(foo), select(slot,constraint([slot('2')]),_)],
  findall(I, query:search(QL, qtest://I), Ids0),
  sort(Ids0, Ids).

% iuse/1 returns the RAW metadata value (e.g. plus(flag)); the deleted
% runtime clause silently stripped defaults, diverging from the macro.
test(issue59_iuse_returns_raw_metadata, [true(Vs == [doc, plus(minimal)])]) :-
  Q =.. [iuse, V],
  findall(V, query:search(Q, qtest://'dev-test/foo-1.0'), Vs0),
  msort(Vs0, Vs).

% CLI iuse searches are served by select/4 (sign-aware), the single
% remaining runtime implementation.
test(issue59_select_iuse_equal_runtime, [true(Ids == ['dev-test/foo-1.0'])]) :-
  Q =.. [select, iuse, equal, minimal],
  findall(I, query:search(Q, qtest://I), Ids0),
  sort(Ids0, Ids).

test(issue59_select_iuse_wildcard_runtime, [true(Ids == ['dev-test/foo-1.0'])]) :-
  Q =.. [select, iuse, wildcard, 'mini*'],
  findall(I, query:search(Q, qtest://I), Ids0),
  sort(Ids0, Ids).

% (c) The search/2 expansion hook is module-local to query: qualified
% callers are inlined, while a bare search/2 goal in another module is
% never rewritten (modules may define their own search/2).
test(issue59_search_hook_is_module_local) :-
  query:goal_expansion(search(category(_), qtest://_), G),
  G \= search(_,_),
  \+ user:goal_expansion(search(category(_), qtest://_), _).

% Download-specialized candidate hooks fire only for a bound 'download'
% action; a variable action is left for runtime resolution instead of
% being bound at expansion time.
test(issue59_eligible_download_inlined,
     [true(G =@= cache:ordered_entry(qtest, 'dev-test/foo-1.0', _, _, _))]) :-
  candidate:goal_expansion(eligible(qtest://'dev-test/foo-1.0':download?{[]}), G),
  !.

test(issue59_eligible_var_action_not_expanded) :-
  \+ candidate:goal_expansion(eligible(qtest://'dev-test/foo-1.0':_A?{[]}), _).

test(issue59_resolve_download_expanded,
     [true(G == featureterm:get(after, ctx, Conds))]) :-
  candidate:goal_expansion(resolve(qtest://x:download?{ctx}, Conds), G),
  !.

test(issue59_resolve_var_action_not_expanded) :-
  \+ candidate:goal_expansion(resolve(qtest://x:_A?{ctx}, _C), _).

% candidate:installed/1 inlines through the same compile_query_compound
% table its definition compiles through (single source of truth).
test(issue59_installed_macro_single_source) :-
  candidate:goal_expansion(installed(R://I), G1),
  !,
  query:compile_query_compound(installed(true), R://I, G2),
  G1 =@= G2.

% The version_domain:normalize_version_term/2 hook (formerly a dead
% user:goal_expansion clause in query.pl) is module-local to version_domain
% and rewrites the goal to a cache-free conditional.
test(issue59_version_domain_hook_fires) :-
  version_domain:goal_expansion(normalize_version_term(_, _), G),
  G \= normalize_version_term(_, _).

% The expansion and the predicate agree on every input class: unbound input
% (identity — the dead macro got this wrong), version/7 passthrough,
% wildcard atom, parseable atom, version(...)=Ver strip, arbitrary compound
% passthrough, numeric input. The predicate is meta-called so this compares
% expansion vs predicate, not expansion vs expansion.
test(issue59_version_domain_hook_matches_predicate) :-
  forall(member(V, [_, version([1,0],'',4,0,[],0,'1.0'), '1.0.*', '2.3',
                    version(a,b,c,d,e,f,g)=myver, foo(bar), 42]),
         ( version_domain:goal_expansion(normalize_version_term(V, R1), G),
           call(G),
           P =.. [normalize_version_term, V, R2],
           version_domain:P,
           R1 =@= R2 )).

% The non-download eligible expansion derives its mask check from the
% masked(true) macro.
test(issue59_eligible_install_uses_masked_macro) :-
  candidate:goal_expansion(eligible(qtest://'dev-test/foo-1.0':install?{[]}), G),
  !,
  G = ( candidate:abi_repair_eligible(qtest, 'dev-test/foo-1.0', []) -> true
      ; (Masked -> (prover:assuming(unmask) -> true ; memo:visibility_override_(_, _)) ; true),
        _ ),
  query:compile_query_compound(masked(true), qtest://'dev-test/foo-1.0', MaskedExpected),
  Masked == MaskedExpected.

:- end_tests(query_dedup).


% -----------------------------------------------------------------------------
%  Full coverage for Knowledge/* (feedback, knowledgebase, repository, query)
% -----------------------------------------------------------------------------

qt_mktemp(Prefix, Dir) :-
  tmp_file_stream(text, Base, Stream),
  close(Stream),
  delete_file(Base),
  atomic_list_concat([Base, '_', Prefix], Dir),
  make_directory(Dir).

qt_rm_rf(Path) :-
  exists_directory(Path), !,
  directory_files(Path, Entries),
  forall((member(E, Entries), E \== '.', E \== '..'),
         ( os:compose_path(Path, E, Child),
           qt_rm_rf(Child) )),
  catch(delete_directory(Path), _, true).
qt_rm_rf(Path) :-
  exists_file(Path), !,
  catch(delete_file(Path), _, true).
qt_rm_rf(_).

:- dynamic pengines:pengine_user/1.
:- dynamic client:execute_remotely/3.

:- begin_tests(knowledge_layer_full_coverage).

test(feedback_module_full_coverage, [nondet]) :-
  qt_mktemp(fb_cov, TmpDir),
  os:compose_path(TmpDir, 'Knowledge', KDir),
  make_directory(KDir),
  V1 = version([1,0], '', 4, 0, [], 0, '1.0'),
  setup_call_cleanup(
    ( setenv('PORTAGE_NG_STATE', TmpDir),
      retractall(feedback:loaded_),
      retractall(feedback:discovered_dep(_, _, _, _)),
      retractall(feedback:discovered_usedep(_, _, _, _)),
      retractall(feedback:excluded_version(_, _, _, _)),
      retractall(feedback:unresolved_diagnostic(_, _)),
      retractall(feedback:required_kernel_config(_, _, _)),
      feedback:clear_session,
      assertz(cache:ordered_entry(qtest, 'fcat/fpkg-1.0', fcat, fpkg, V1))
    ),
    ( feedback:record_discovery(qtest://'fcat/fpkg-1.0', 'dev-util/pkgconf', bdepend, ev1),
      feedback:record_discovery(qtest://'fcat/fpkg-1.0', 'dev-util/pkgconf', bdepend, ev1),
      feedback:record_usedep(qtest://'fcat/fpkg-1.0', 'dev-libs/foo',
                             [use(enable(bar), none)], ev2),
      feedback:record_usedep(qtest://'fcat/fpkg-1.0', 'dev-libs/foo',
                             [use(enable(bar), none)], ev2),
      feedback:record_excluded_version(fcat, fpkg, V1, ev3),
      feedback:record_excluded_version(fcat, fpkg, V1, ev3),
      feedback:version_excluded(fcat, fpkg, qtest://'fcat/fpkg-1.0'),
      feedback:record_unresolved(symbol(cmd, 'missing-bin'), ev4),
      feedback:record_unresolved(symbol(cmd, 'missing-bin'), ev4),
      feedback:record_kernel_config(qtest://'fcat/fpkg-1.0', [config('NET', y)], ev5),
      feedback:record_kernel_config(qtest://'fcat/fpkg-1.0', [config('NET', y)], ev5),
      feedback:discovery_count(1),
      feedback:usedep_count(1),
      feedback:excluded_version_count(1),
      feedback:kernel_config_count(1),
      feedback:learned_count(4),
      feedback:session_discoveries([_]),
      feedback:session_kernel_configs([_]),
      feedback:plan_kernel_config_pre_actions([qtest://'fcat/fpkg-1.0'], [_]),
      findall(D, feedback:discovered_bdepend_dep(qtest, 'fcat/fpkg-1.0', D), [_, _]),
      feedback:clear_session,
      feedback:session_discoveries([]),
      retractall(feedback:discovered_dep(_, _, _, _)),
      retractall(feedback:discovered_usedep(_, _, _, _)),
      retractall(feedback:excluded_version(_, _, _, _)),
      retractall(feedback:unresolved_diagnostic(_, _)),
      retractall(feedback:required_kernel_config(_, _, _)),
      retractall(feedback:loaded_),
      feedback:load,
      feedback:load,
      feedback:learned_count(4)
    ),
    ( unsetenv('PORTAGE_NG_STATE'),
      retractall(feedback:loaded_),
      retractall(feedback:discovered_dep(_, _, _, _)),
      retractall(feedback:discovered_usedep(_, _, _, _)),
      retractall(feedback:excluded_version(_, _, _, _)),
      retractall(feedback:unresolved_diagnostic(_, _)),
      retractall(feedback:required_kernel_config(_, _, _)),
      feedback:clear_session,
      retractall(cache:ordered_entry(qtest, 'fcat/fpkg-1.0', _, _, _)),
      qt_rm_rf(TmpDir)
    )).

test(knowledgebase_and_repository_full_coverage, [nondet]) :-
  qt_mktemp(kb_repo_cov, TmpDir),
  os:compose_path(TmpDir, 'Knowledge', KDir),
  make_directory(KDir),
  os:compose_path(TmpDir, 'Manifest', PlainManifest),
  setup_call_cleanup(open(PlainManifest, write, SM1), writeln(SM1, 'DIST a 1'), close(SM1)),
  os:compose_path(TmpDir, 'gzpkg', GzDir),
  make_directory(GzDir),
  os:compose_path(GzDir, 'Manifest.gz', GzManifest),
  setup_call_cleanup(open(GzManifest, write, SM2), writeln(SM2, 'DIST b 2'), close(SM2)),
  V1 = version([1,0], '', 4, 0, [], 0, '1.0'),
  setup_call_cleanup(
    ( setenv('PORTAGE_NG_STATE', TmpDir),
      load_files(portage('Source/Application/Mode/routes'), [if(not_loaded)]),
      wrap_predicate(client:execute_remotely(_, _, _), test_cov, _, true),
      assertz(cache:ordered_entry(qtest, 'kcat/kpkg-1.0', kcat, kpkg, V1)),
      assertz(cache:entry_metadata(qtest, 'kcat/kpkg-1.0', slot, slot('0')))
    ),
    with_output_to(string(_),
      ( % Class template coverage for OO classes knowledgebase and repository
        forall(knowledgebase:(_ ::- _), true),
        forall(repository:(_ ::- _), true),
        % Warmer lifecycle
        knowledgebase:kb_warm_metadata_index,
        knowledgebase:start_metadata_warmer,
        knowledgebase:join_metadata_warmer,
        thread_create(sleep(0.05), Tid, []),
        knowledgebase:join_thread_timeout(Tid, 2),
        % VDB repository & client VDB helpers
        knowledgebase:is_vdb_repository(pkg),
        knowledgebase:is_vdb_repository('pkg@client.local'),
        \+ knowledgebase:is_vdb_repository(portage),
        Principal = tenant(u, 'client.local'),
        knowledgebase:principal_vdb_repository(Principal, 'pkg@client.local'),
        assertz(cache:repository('pkg@client.local')),
        knowledgebase:register_client_vdb(Principal, 'pkg@client.local', stamp1, 10, 1, 1),
        knowledgebase:client_vdb_stamp('pkg@client.local', stamp1),
        assertz(mock_pengine_mod:vdb_repository('pkg@client.local')),
        assertz(mock_pengine_mod:vdb_import_stamp(stamp1)),
        knowledgebase:client_vdb_valid(Principal, mock_pengine_mod, 'pkg@client.local'),
        knowledgebase:touch_client_vdb(Principal, 'pkg@client.local'),
        asserta(pengines:pengine_user(Principal)),
        knowledgebase:pengine_vdb_repository(mock_pengine_mod, 'pkg@client.local'),
        retractall(pengines:pengine_user(_)),
        catch(knowledgebase:pengine_vdb_repository(mock_pengine_mod, _), _, true),
        knowledgebase:remove_client_vdb(Principal, 'pkg@client.local'),
        retractall(cache:repository('pkg@client.local')),
        retractall(mock_pengine_mod:vdb_repository(_)),
        retractall(mock_pengine_mod:vdb_import_stamp(_)),
        % Proxy knowledgebase remote calls
        kb_proxy_test:newinstance(knowledgebase),
        kb_proxy_test:knowledgebase('localhost', 4000),
        kb_proxy_test:sync,
        kb_proxy_test:sync(portage),
        % Repository plain helpers (manifest_file + sync cap)
        repository:manifest_file(TmpDir, PlainManifest),
        repository:manifest_file(GzDir, GzManifest),
        repository:network_sync_allowed(r_unlim),
        repository:record_network_sync(r_unlim),
        assertz(config:repository_sync_limit(r_capped, 1)),
        repository:sync_limit(r_capped, 1),
        repository:network_sync_allowed(r_capped),
        repository:record_network_sync(r_capped),
        \+ repository:network_sync_allowed(r_capped),
        repository:sync_limit_notice(r_capped),
        retractall(config:repository_sync_limit(r_capped, _))
      )),
    ( unsetenv('PORTAGE_NG_STATE'),
      unwrap_predicate(client:execute_remotely/3, test_cov),
      retractall(cache:ordered_entry(qtest, 'kcat/kpkg-1.0', _, _, _)),
      retractall(cache:entry_metadata(qtest, 'kcat/kpkg-1.0', _, _)),
      qt_rm_rf(TmpDir)
    )).

test(query_module_full_coverage, [nondet]) :-
  V1 = version([1,0], '', 4, 0, [], 0, '1.0'),
  V2 = version([2,0], '', 4, 0, [], 0, '2.0'),
  knowledgebase:vdb_repository(Vdb),
  setup_call_cleanup(
    ( assertz(cache:package(qtest, 'qcat', qpkg)),
      assertz(cache:ordered_entry(qtest, 'qcat/qpkg-1.0', 'qcat', qpkg, V1)),
      assertz(cache:ordered_entry(qtest, 'qcat/qpkg-2.0', 'qcat', qpkg, V2)),
      assertz(cache:ordered_entry(Vdb,   'qcat/qpkg-1.0', 'qcat', qpkg, V1)),
      assertz(cache:entry_metadata(qtest, 'qcat/qpkg-1.0', slot, slot('0'))),
      assertz(cache:entry_metadata(qtest, 'qcat/qpkg-1.0', slot, subslot('0'))),
      assertz(cache:entry_metadata(qtest, 'qcat/qpkg-2.0', slot, slot('1'))),
      assertz(cache:entry_metadata(qtest, 'qcat/qpkg-1.0', keywords, stable(amd64))),
      assertz(cache:entry_metadata(qtest, 'qcat/qpkg-1.0', use, flag_u)),
      assertz(cache:entry_metadata(qtest, 'qcat/qpkg-1.0', needed_elf2, 'liba.so')),
      assertz(cache:entry_metadata(qtest, 'qcat/qpkg-1.0', provides_elf2, 'libb.so')),
      assertz(cache:entry_metadata(qtest, 'qcat/qpkg-1.0', required_use, required(flag_u))),
      assertz(cache:entry_metadata(qtest, 'qcat/qpkg-1.0', src_uri, uri('https', 'ex.org', 'f.tar.gz'))),
      assertz(cache:entry_metadata(qtest, 'qcat/qpkg-1.0', bdepend,
        package_dependency(install, no, qcat, qdep, none, version_none, [slot('0')], []))),
      assertz(cache:entry_metadata(qtest, 'qcat/qpkg-1.0', cdepend,
        package_dependency(install, no, qcat, qdep, none, version_none, [slot('1')], []))),
      assertz(cache:entry_metadata(qtest, 'qcat/qpkg-1.0', depend,
        package_dependency(install, no, qcat, qdep, none, version_none, [], []))),
      assertz(cache:entry_metadata(qtest, 'qcat/qpkg-1.0', idepend,
        package_dependency(run, no, qcat, qdep, none, version_none, [], []))),
      assertz(cache:entry_metadata(qtest, 'qcat/qpkg-1.0', rdepend,
        package_dependency(run, no, qcat, qdep, none, version_none, [], []))),
      assertz(cache:entry_metadata(qtest, 'qcat/qpkg-1.0', pdepend,
        package_dependency(run, no, qcat, qdep, none, version_none, [], []))),
      assertz(cache:entry_metadata(qtest, 'qcat/qpkg-1.0', defined_phases, compile)),
      assertz(cache:entry_metadata(qtest, 'qcat/qpkg-1.0', description, 'desc')),
      assertz(cache:entry_metadata(qtest, 'qcat/qpkg-1.0', eapi, V1)),
      assertz(cache:entry_metadata(qtest, 'qcat/qpkg-1.0', homepage, 'https://ex.org')),
      assertz(cache:entry_metadata(qtest, 'qcat/qpkg-1.0', license, 'MIT')),
      assertz(cache:entry_metadata(qtest, 'qcat/qpkg-1.0', maintainer, ['dev@ex.org'])),
      assertz(cache:entry_metadata(qtest, 'qcat/qpkg-1.0', eclasses, [eclass(cmake), '123'])),
      assertz(cache:entry_metadata(qtest, 'qcat/qpkg-1.0', properties, live)),
      assertz(cache:entry_metadata(qtest, 'qcat/qpkg-1.0', restrict, strip)),
      assertz(cache:entry_metadata(qtest, 'qcat/qpkg-1.0', timestamp, 100)),
      assertz(cache:entry_metadata(qtest, 'qcat/qpkg-1.0', build_time, 10)),
      assertz(cache:entry_metadata(qtest, 'qcat/qpkg-1.0', md5, 'abc')),
      assertz(cache:entry_metadata(qtest, 'qcat/qpkg-1.0', local, true)),
      assertz(cache:entry_metadata(qtest, 'qcat/qpkg-1.0', iuse, plus(flag_u))),
      assertz(cache:entry_metadata(qtest, 'qcat/qpkg-1.0', iuse, minus(flag_m))),
      assertz(cache:entry_metadata(qtest, 'qcat/qpkg-1.0', iuse, 'python_targets_python3_12')),
      assertz(cache:manifest(qtest, '/m/Manifest', 100, 'qcat', qpkg)),
      assertz(cache:manifest_metadata(qtest, '/m/Manifest', 'DIST', 'f.tar.gz', 42, [])),
      assertz(preference:local_set(qset, ['qcat/qpkg']))
    ),
    ( % 1. Compile all macro compound forms in compile_query_compound/3
      MacroForms = [
        repository(qtest), entry('qcat/qpkg-1.0'), ebuild('qcat/qpkg-1.0'),
        package('qcat', qpkg), name(qpkg), category('qcat'), version(V1),
        slot('0'), subslot('0'), keyword(stable(amd64)), keywords(stable(amd64)),
        installed(true), installed(false),
        use(flag_u), needed_elf2(_), provides_elf2(_), required_use(_),
        src_uri(_), download('f.tar.gz'), bdepend(_), cdepend(_), depend(_),
        idepend(_), pdepend(_), rdepend(_), defined_phases(_), description(_),
        eapi(V1), homepage(_), license(_), maintainer(_), eclass(cmake),
        eclasses(cmake), properties(_), restrict(_), timestamp(_), build_time(_),
        md5(_), local(_), iuse(_),
        masked(true), masked(false),
        vulnerable(true), vulnerable(false), glsa('202601-01'),
        dependency(_, run), dependency(_, install), dependency(_, fetchonly),
        select(slot, constraint([]), _),
        select(slot, constraint([slot('0')]), _),
        select(slot, constraint([slot('0'), subslot('0')]), _),
        select(slot, constraint([slot('0'), equal]), _),
        select(slot, constraint([slot('0'), subslot('0'), equal]), _),
        select(slot, constraint([any_same_slot]), _),
        select(slot, constraint([any_different_slot]), _),
        select(repository, notequal, pkg),
        select(repository, notequal, other),
        select(repository, equal, qtest),
        select(repository, tilde, qtest),
        select(repository, wildcard, 'q*'),
        select(name, equal, qpkg), select(name, notequal, other),
        select(name, tilde, qpkg), select(name, wildcard, 'qp?g'),
        select(category, equal, 'qcat'), select(category, notequal, other),
        select(category, tilde, 'qcat'), select(category, wildcard, 'qc*'),
        select(version, none, _), select(version, equal, version_none),
        select(version, equal, V1), select(version, smaller, V2),
        select(version, greater, V1), select(version, smallerequal, V1),
        select(version, greaterequal, V1), select(version, notequal, V2),
        select(version, wildcard, version(_,_,_,_,_,_,'1*')),
        select(version, tilde, V1),
        select(eapi, notequal, V2), select(eapi, equal, V1),
        select(eapi, wildcard, V1), select(eapi, smaller, V2),
        select(eapi, greater, V1), select(eapi, smallerequal, V1),
        select(eapi, greaterequal, V1),
        select(eclass, notequal, other), select(eclass, equal, cmake),
        select(eclass, tilde, cmake), select(eclass, wildcard, 'cm*'),
        select(eclasses, notequal, other), select(eclasses, equal, cmake),
        select(eclasses, tilde, cmake), select(eclasses, wildcard, 'cm*'),
        select(download, notequal, other), select(download, equal, 'f.tar.gz'),
        select(download, tilde, 'f.tar.gz'), select(download, wildcard, 'f*'),
        select(slot, notequal, '9'), select(slot, equal, '0'),
        select(slot, tilde, '0'), select(slot, wildcard, '0*'),
        select(subslot, notequal, '9'), select(subslot, equal, '0'),
        select(subslot, tilde, '0'), select(subslot, wildcard, '0*'),
        select(keyword, equal, stable(amd64)),
        select(keywords, equal, stable(amd64)),
        select(maintainer, equal, 'dev@ex.org'),
        select(maintainer, wildcard, 'dev*'),
        select(maintainer, tilde, 'dev@ex.org'),
        select(masked, equal, true), select(masked, equal, false),
        select(masked, notequal, false), select(masked, notequal, true),
        select(installed, equal, true), select(installed, equal, false),
        select(installed, notequal, true), select(installed, notequal, false),
        all(_VarS), all(_VarS2):install?{[]},
        all(src_uri(_)), all(required_use(_)), all(bdepend(_)),
        all(depend(_)), all(cdepend(_)), all(idepend(_)),
        all(rdepend(_)), all(pdepend(_)),
        all(dependency(_, run)), all(dependency(_, install)), all(dependency(_, fetchonly)),
        all(dependency(_, run)):run?{[]},
        all(dependency(_, install)):install?{[]},
        all(dependency(_, fetchonly)):fetchonly?{[]},
        model(_, required_use(_), build_with_use(_)),
        model(required_use(_)),
        model(dependency(_, run)):config?{[]},
        model(dependency(_, install)):config?{[]},
        model(dependency(_, pdepend)):config?{[]},
        model(dependency(_, fetchonly)):config?{[]},
        qualified_target(none, qtest, 'qcat', qpkg, version_none, []),
        qualified_target(none, qtest, 'qcat', qpkg, V1, []),
        qualified_target(greater, qtest, 'qcat', qpkg, V1, []),
        qualified_target(greaterequal, qtest, 'qcat', qpkg, V1, []),
        qualified_target(smaller, qtest, 'qcat', qpkg, V2, []),
        qualified_target(smallerequal, qtest, 'qcat', qpkg, V1, []),
        qualified_target(equal, qtest, 'qcat', qpkg, V1, []),
        qualified_target(notequal, qtest, 'qcat', qpkg, V2, []),
        qualified_target(tilde, qtest, 'qcat', qpkg, V1, []),
        unknown_compound_query(1)
      ],
      forall(member(MF, MacroForms),
             ( copy_term(MF, MF1),
               query:compile_query_compound(MF1, qtest://'qcat/qpkg-1.0', Goal),
               ignore(catch(query:Goal, _, true)) )),
      query:repo_not_vdb(_UnboundRepo),
      query:repo_not_vdb(qtest),
      % 2. Choice CN under nested groups
      NestedChoice = at_most_one_of_group([
        any_of_group([package_dependency(install, no, c1, n1, none, version_none, [], [])]),
        exactly_one_of_group([package_dependency(install, no, c2, n2, none, version_none, [], [])]),
        at_most_one_of_group([package_dependency(install, no, c3, n3, none, version_none, [], [])]),
        use_conditional_group(positive, u, qtest://'qcat/qpkg-1.0',
          [package_dependency(install, no, c4, n4, none, version_none, [], [])])
      ]),
      findall(CN, query:dep_model_choice_cn(NestedChoice, CN), [_, _, _, _]),
      % 3. Runtime search/2 meta-predicates & specialized clauses
      S1 =.. [description, _],
      ignore(query:search(all(S1):run?{[]}, qtest://'qcat/qpkg-1.0')),
      ignore(query:search(all(S1), qtest://'qcat/qpkg-1.0')),
      S2 =.. [iuse, _, _],
      ignore(query:search(all(S2):run?{[]}, qtest://'qcat/qpkg-1.0')),
      ignore(query:search(all(S2), qtest://'qcat/qpkg-1.0')),
      M1 =.. [description, _],
      ignore(catch(query:search(model(M1):validate?{[]}, qtest://'qcat/qpkg-1.0'), _, true)),
      ignore(catch(query:search(model(M1), qtest://'qcat/qpkg-1.0'), _, true)),
      M2 =.. [iuse, _, _],
      ignore(catch(query:search(model(M2):config?{[]}, qtest://'qcat/qpkg-1.0'), _, true)),
      ignore(catch(query:search(model(M2), qtest://'qcat/qpkg-1.0'), _, true)),
      ignore(query:search(latest(name(qpkg)), qtest://'qcat/qpkg-1.0')),
      ignore(query:search(manifest(all, 'DIST', 'f.tar.gz', 42), qtest://'qcat/qpkg-1.0')),
      ignore(query:search(manifest(preference, 'DIST', 'f.tar.gz', 42), qtest://'qcat/qpkg-1.0')),
      CondModel = [use_conditional_group(positive, flag_u, qtest://'qcat/qpkg-1.0', [item_in_cond]),
                   use_conditional_group(negative, flag_m, qtest://'qcat/qpkg-1.0', [item_in_neg])],
      ignore(query:deep_member(all, item_in_cond, CondModel)),
      assertz(preference:local_use(flag_u)),
      assertz(preference:local_use(minus(flag_m))),
      ignore(query:deep_member(preference, item_in_cond, CondModel)),
      ignore(query:deep_member(preference, item_in_neg, CondModel)),
      retractall(preference:local_use(flag_u)),
      retractall(preference:local_use(minus(flag_m))),
      findall(U-SR, query:search(iuse(U, SR), qtest://'qcat/qpkg-1.0'), _),
      findall(UF, query:search(iuse_filtered(UF), qtest://'qcat/qpkg-1.0'), _),
      findall(UF2-SR2, query:search(iuse_filtered(UF2, SR2), qtest://'qcat/qpkg-1.0'), _),
      ignore(query:search(python_targets('python3_12'), qtest://'qcat/qpkg-1.0')),
      ignore(query:search(python_targets('python3_12', _), qtest://'qcat/qpkg-1.0')),
      QCustom = custom_meta_key(val),
      ignore(query:search(QCustom, qtest://'qcat/qpkg-1.0')),
      % 4. Runtime select/4 clauses
      findall(E, query:select(set, equal, qset, qtest://E), _),
      findall(E, query:select(set, tilde, qset, qtest://E), _),
      findall(E, query:select(set, wildcard, 'qs*', qtest://E), _),
      ignore(query:select(set, notequal, qset, qtest://'qcat/qpkg-1.0')),
      ignore(query:select(description, notequal, 'other', qtest://'qcat/qpkg-1.0')),
      ignore(query:select(description, equal, 'desc', qtest://'qcat/qpkg-1.0')),
      ignore(query:select(description, tilde, 'desc', qtest://'qcat/qpkg-1.0')),
      ignore(query:select(description, wildcard, 'd?sc', qtest://'qcat/qpkg-1.0')),
      ignore(query:select(iuse, tilde, '+flag_u', qtest://'qcat/qpkg-1.0')),
      ignore(query:select(iuse, tilde, '-flag_m', qtest://'qcat/qpkg-1.0')),
      % 5. Group dependencies splitting multi-slot regular groups
      DSlot0 = package_dependency(install, no, qcat, qpkg, equal, V1, [], []):install?{[]},
      DSlot1 = package_dependency(install, no, qcat, qpkg, equal, V2, [], []):install?{[]},
      query:group_dependencies([DSlot0, DSlot1], _),
      % 6. Apply filters (use filters)
      ignore(query:apply_filters(qtest://'qcat/qpkg-1.0',
        [[slot('0')],
         [use(optenable(flag_u), none),
          use(optdisable(flag_m), none),
          use(enable(flag_u), none),
          use(enable(absent_flag), positive)]]))
    ),
    ( retractall(cache:package(qtest, 'qcat', qpkg)),
      retractall(cache:ordered_entry(qtest, 'qcat/qpkg-1.0', _, _, _)),
      retractall(cache:ordered_entry(qtest, 'qcat/qpkg-2.0', _, _, _)),
      retractall(cache:ordered_entry(Vdb,   'qcat/qpkg-1.0', _, _, _)),
      retractall(cache:entry_metadata(qtest, 'qcat/qpkg-1.0', _, _)),
      retractall(cache:entry_metadata(qtest, 'qcat/qpkg-2.0', _, _)),
      retractall(cache:manifest(qtest, '/m/Manifest', _, _, _)),
      retractall(cache:manifest_metadata(qtest, '/m/Manifest', _, _, _, _)),
      retractall(preference:local_set(qset, _))
    )).

:- end_tests(knowledge_layer_full_coverage).

