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
  G = ((Masked -> (prover:assuming(unmask) -> true ; memo:visibility_override_(_, _)) ; true), _),
  query:compile_query_compound(masked(true), qtest://'dev-test/foo-1.0', MaskedExpected),
  Masked == MaskedExpected.

:- end_tests(query_dedup).
