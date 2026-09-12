/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> SYNTHETICTEST
Unit tests for the prover core over synthetic rule sets (issue #73).

The resolving module's synthetic rule store (resolving:enable_test_rules/0)
drives resolver:resolve/9, orderer:order/4, depclean:uninstall_order/3
and the prove_with_fallback tier chain over hand-built rules: proof /
model / cycle-break shape, wave projection and preferences, unmerge
order over synthetic claims, and tier selection.
*/

:- module(synthetictest, []).

:- use_module(library(plunit)).
:- use_module(library(assoc)).
:- use_module(library(lists)).

% =============================================================================
%  SYNTHETICTEST declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Synthetic-rule resolver core tests (issue #73)
% -----------------------------------------------------------------------------
%
% KB-independent unit tests for the resolver core. The resolving module
% exposes a synthetic rule store (resolving:enable_test_rules/0,
% resolving:test_rule/2): while active, resolving:rule/2 resolves
% EXCLUSIVELY against hand-built test_rule/2 clauses, so
% resolver:resolve/9, orderer:order/4 and the prove_with_fallback tier
% chain can be exercised over tiny rule sets without a knowledge base.
%
% Goals are passed as BARE literals (no ?{[]} proof-context wrapper):
% prover:canon_literal/3 canonicalizes the R://- and :Action-shaped literal
% forms used by the production rules, but a bare atom wrapped in ?{Ctx} is
% itself its canonical form, which would make proof/model keys diverge from
% the body literals. Bare goals keep all keys canonical.

% Replace the synthetic rule store contents with Head-Body pairs.
issue73_rules(Pairs) :-
  resolving:enable_test_rules,
  retractall(resolving:test_rule(_, _)),
  forall(member(H-B, Pairs), assertz(resolving:test_rule(H, B))).

% Wave index of the rule whose canonical head is Lit (fails when unplanned).
issue73_wave(Plan, Lit, W) :-
  nth1(W, Plan, Wave),
  member(R, Wave),
  prover:rule_head(R, Lit),
  !.


% -----------------------------------------------------------------------------
%  Prover core: proof / model / cycle-break shape (issue #73)
% -----------------------------------------------------------------------------

:- begin_tests(prover_core_synthetic, [cleanup(resolving:disable_test_rules)]).

% A linear chain proves every literal exactly once: the model holds each
% literal, the proof holds one rule(L) key per literal with the synthetic
% body and dep count, and the triggers AVL is the reverse dependency index.
test(chain_proof_model_triggers_shape) :-
  issue73_rules([a-[b], b-[c], c-[]]),
  resolver:resolve([a], t, Proof, t, Model, t, _Cons, t, Triggers),
  get_assoc(a, Model, _),
  get_assoc(b, Model, _),
  get_assoc(c, Model, _),
  get_assoc(rule(a), Proof, dep(1, [b])?_),
  get_assoc(rule(b), Proof, dep(1, [c])?_),
  get_assoc(rule(c), Proof, dep(0, [])?_),
  \+ gen_assoc(assumed(_), Model, _),
  forall(gen_assoc(K, Proof, _), K \= assumed(rule(_))),
  get_assoc(b, Triggers, [a]),
  get_assoc(c, Triggers, [b]).

% A shared dependency (diamond) is proven once and triggers both parents.
test(diamond_shared_dep_proved_once) :-
  issue73_rules([a-[b, c], b-[d], c-[d], d-[]]),
  resolver:resolve([a], t, Proof, t, Model, t, _Cons, t, Triggers),
  get_assoc(rule(d), Proof, dep(0, [])?_),
  get_assoc(d, Model, _),
  get_assoc(d, Triggers, Dependents),
  msort(Dependents, [b, c]).

% A structural cycle yields a prover cycle-break: proof key
% assumed(rule(Lit)) (dep count -1, body preserved for the orderer), a
% cycle_path witness, and assumed(Lit) in the model — while the regular
% rule(Lit) entry remains. This is the `assumed(rule(X))` axis of the
% assumption taxonomy, distinct from domain assumptions.
test(structural_cycle_break_shape) :-
  issue73_rules([a-[b], b-[a]]),
  resolver:resolve([a], t, Proof, t, Model, t, _Cons, t, _Triggers),
  get_assoc(assumed(rule(a)), Proof, dep(-1, [b])?_),
  get_assoc(cycle_path(a), Proof, CyclePath),
  CyclePath == [a, b, a],
  get_assoc(assumed(a), Model, _),
  get_assoc(rule(a), Proof, dep(1, [b])?_),
  get_assoc(rule(b), Proof, dep(1, [a])?_),
  get_assoc(b, Model, _).

% An RDEPEND-mediated cycle (a :run step on the cycle path) is classified
% benign by heuristic:cycle_benign/2: no cycle-break assumption of any kind
% is recorded.
test(benign_run_cycle_no_assumption) :-
  issue73_rules([(p:run)-[q:run], (q:run)-[p:run]]),
  resolver:resolve([p:run], t, Proof, t, Model, t, _Cons, t, _Triggers),
  get_assoc(p:run, Model, _),
  get_assoc(q:run, Model, _),
  \+ gen_assoc(assumed(_), Model, _),
  forall(gen_assoc(K, Proof, _), K \= assumed(rule(_))).

% A fetchonly cycle is likewise benign: distfiles are independent, so
% "fetch A requires fetch B requires fetch A" is not a bootstrap failure
% and must not surface as assumed(rule(...:fetchonly)) ("assumed fetched").
test(benign_fetchonly_cycle_no_assumption) :-
  issue73_rules([(p:fetchonly)-[q:fetchonly], (q:fetchonly)-[p:fetchonly]]),
  resolver:resolve([p:fetchonly], t, Proof, t, Model, t, _Cons, t, _Triggers),
  get_assoc(p:fetchonly, Model, _),
  get_assoc(q:fetchonly, Model, _),
  \+ gen_assoc(assumed(_), Model, _),
  forall(gen_assoc(K, Proof, _), K \= assumed(rule(_))).

% A domain assumption (assumed/1 emitted by a rule body) is stored under the
% proof key rule(assumed(X)) — the OTHER axis of the assumption taxonomy —
% and never as a prover cycle-break key.
test(domain_assumption_shape) :-
  issue73_rules([p-[assumed(q)], assumed(_)-[]]),
  resolver:resolve([p], t, Proof, t, Model, t, _Cons, t, _Triggers),
  get_assoc(rule(p), Proof, dep(1, [assumed(q)])?_),
  get_assoc(rule(assumed(q)), Proof, dep(0, [])?_),
  get_assoc(assumed(q), Model, _),
  \+ get_assoc(assumed(rule(q)), Proof, _),
  \+ get_assoc(cycle_path(q), Proof, _).

% naf/1 conflict detection: a body requiring both naf(q) and q has no model.
test(naf_conflict_fails, [fail]) :-
  issue73_rules([p-[naf(q), q], naf(_)-[], q-[]]),
  resolver:resolve([p], t, _Proof, t, _Model, t, _Cons, t, _Triggers).

% constraint/1 body literals are routed to the constraint store: they never
% appear in the model or the triggers, but the head's dep body retains them
% and the value lands in the constraint AVL.
test(constraint_routed_to_store) :-
  issue73_rules([p-[constraint(k:{hello})]]),
  resolver:resolve([p], t, Proof, t, Model, t, Cons, t, Triggers),
  get_assoc(rule(p), Proof, dep(1, [constraint(k:{hello})])?_),
  get_assoc(k, Cons, hello),
  \+ gen_assoc(constraint(_), Model, _),
  \+ gen_assoc(constraint(_), Triggers, _).

:- end_tests(prover_core_synthetic).


% -----------------------------------------------------------------------------
%  Ordering engine: rule-based pass-2 over synthetic proofs
% -----------------------------------------------------------------------------
%
% The rule-based ordering engine (Source/Pipeline/orderer.pl +
% Source/Domain/Gentoo/Rules/ordering.pl) re-runs the prover core over generic
% planning laws to order the pass-1 proof. These tests drive it over
% tiny synthetic rule sets: waves come out of availability proofs,
% cycles fall through the currently_proving guard into the world clause
% (ordering:world_override/1 stands in for the VDB), the genuine
% bootstrap case surfaces as an unreachable/2 domain assumption, and
% preferences (runtime dep groups, order_after anchors) are honored by
% the projection exactly when they close no cycle.

% Helper: prove Goals over the active synthetic rule set (pass 1) and
% order the proof with the rule-based engine (pass 2).
ordering_engine_plan(Goals, ProofOut, Plan) :-
  resolver:resolve(Goals, t, Proof, t, _Model, t, _Cons, t, Triggers),
  orderer:order(Proof, Triggers, ProofOut, Plan).

% Unreachable assumptions merged into the output proof, as full keys.
ordering_engine_unreachables(ProofOut, Unreachables) :-
  findall(unreachable(H, D),
          gen_assoc(rule(assumed(unreachable(H, D))), ProofOut, _),
          Unreachables).

:- begin_tests(ordering_engine_synthetic,
               [cleanup(( resolving:disable_test_rules,
                          retractall(ordering:world_override(_)) ))]).

% A linear chain orders leaf-first, one step per wave, no assumptions.
test(chain_waves_dependency_order) :-
  issue73_rules([a-[b], b-[c], c-[]]),
  ordering_engine_plan([a], ProofOut, Plan),
  ordering_engine_unreachables(ProofOut, []),
  issue73_wave(Plan, c, W1),
  issue73_wave(Plan, b, W2),
  issue73_wave(Plan, a, W3),
  W1 < W2, W2 < W3.

% Diamond: independent siblings share a wave; every hard body dep sits in
% a strictly earlier wave (the wave invariant, now a proof property).
test(diamond_siblings_share_wave_and_invariant_holds) :-
  issue73_rules([a-[b, c], b-[d], c-[d], d-[]]),
  ordering_engine_plan([a], _ProofOut, Plan),
  issue73_wave(Plan, d, WD),
  issue73_wave(Plan, b, WB),
  issue73_wave(Plan, c, WC),
  issue73_wave(Plan, a, WA),
  WB =:= WC,
  WD < WB, WB < WA.

% Membership invariant: every pass-1 proof step is planned exactly once —
% cycles included.
test(cycle_members_are_planned_with_bootstrap_assumption) :-
  issue73_rules([top-[a, x], a-[b], b-[a], x-[]]),
  ordering_engine_plan([top], ProofOut, Plan),
  issue73_wave(Plan, x, _),
  issue73_wave(Plan, a, WA),
  issue73_wave(Plan, b, WB),
  issue73_wave(Plan, top, WTop),
  % The a->b requirement was provable (b scheduled first in derivation
  % order); the b->a back-edge is the genuine bootstrap boundary and is
  % reported as a negative unreachable assumption, not silently cut.
  WB < WA, WA < WTop,
  ordering_engine_unreachables(ProofOut, [unreachable(b, a)]),
  assumption:assumption_type(unreachable(b, a), unreachable).

% The same cycle on a system where the world already provides `a`: the
% world clause bridges the loop with a citation instead of an assumption
% (the LFS argument), and no unreachable is recorded.
test(cycle_bridged_by_world) :-
  issue73_rules([top-[a, x], a-[b], b-[a], x-[]]),
  assertz(ordering:world_override(a)),
  ordering_engine_plan([top], ProofOut, Plan),
  retractall(ordering:world_override(_)),
  ordering_engine_unreachables(ProofOut, []),
  issue73_wave(Plan, b, WB),
  issue73_wave(Plan, a, WA),
  issue73_wave(Plan, top, WTop),
  WB < WA, WA < WTop.

% Runtime dependency groups (grouped :run heads) are preferences: the
% provider chain is placed first when nothing hard conflicts.
test(runtime_preference_orders_provider_first) :-
  G = grouped_package_dependency(no, cat, lib, []):run,
  issue73_rules([prog-[G], G-[lib], lib-[]]),
  ordering_engine_plan([prog], ProofOut, Plan),
  ordering_engine_unreachables(ProofOut, []),
  issue73_wave(Plan, lib, WLib),
  issue73_wave(Plan, G, WG),
  issue73_wave(Plan, prog, WProg),
  WLib < WG, WG < WProg.

% A preference that closes a cycle against the hard structure is simply
% not honored — no unreachable assumption, no arbitrary cut: the hard
% chain wins and the runtime edge is dropped (Portage's :run relaxation
% as a projection property).
test(cyclic_preference_dropped_silently) :-
  G = grouped_package_dependency(no, cat, liba, []):run,
  issue73_rules([prog-[G], G-[lib], lib-[prog]]),
  ordering_engine_plan([prog], ProofOut, Plan),
  ordering_engine_unreachables(ProofOut, []),
  issue73_wave(Plan, prog, WProg),
  issue73_wave(Plan, lib, WLib),
  issue73_wave(Plan, G, WG),
  WProg < WLib, WLib < WG.

% Ordering strategies (--optimize). A pure runtime cycle — the
% nautilus/sushi shape, each side's grouped :run wanting the other placed
% first — has no order that honors both preferences.
%
% parallelism (default): both preferences lie inside one mutual-
% reachability class (ordering:same_component/2) and are void; the two
% packages share a wave and their groups share the next one.
test(runtime_cycle_parallelism_shares_waves, [nondet]) :-
  GS = grouped_package_dependency(no, cat, sushi, []):run,
  GN = grouped_package_dependency(no, cat, nautilus, []):run,
  issue73_rules([nautilus-[GS], GS-[sushi], sushi-[GN], GN-[nautilus]]),
  ordering_engine_plan([nautilus], ProofOut, Plan),
  ordering_engine_unreachables(ProofOut, []),
  issue73_wave(Plan, nautilus, WN),
  issue73_wave(Plan, sushi, WS),
  issue73_wave(Plan, GS, WGS),
  issue73_wave(Plan, GN, WGN),
  WN =:= WS, WGS =:= WGN, WN < WGS,
  length(Plan, 2).

% soft-requirements: every preference reaches the projection, which
% honors the first one and drops the second (it would close the cycle):
% the same four steps become a staircase, one per wave.
test(runtime_cycle_soft_requirements_serialises,
     [setup(asserta(preference:local_flag(optimize_soft_requirements))),
      cleanup(retractall(preference:local_flag(optimize_soft_requirements))),
      nondet]) :-
  GS = grouped_package_dependency(no, cat, sushi, []):run,
  GN = grouped_package_dependency(no, cat, nautilus, []):run,
  issue73_rules([nautilus-[GS], GS-[sushi], sushi-[GN], GN-[nautilus]]),
  ordering_engine_plan([nautilus], ProofOut, Plan),
  ordering_engine_unreachables(ProofOut, []),
  length(Plan, 4),
  forall(member(Wave, Plan), length(Wave, 1)),
  % The hard structure is honored under both strategies.
  issue73_wave(Plan, nautilus, WN),
  issue73_wave(Plan, sushi, WS),
  issue73_wave(Plan, GS, WGS),
  issue73_wave(Plan, GN, WGN),
  WS < WGS, WN < WGN.

% A preference between two classes (the audacious/audacious-plugins
% shape: the plugins want the player first, the player only prefers
% its library) is kept under parallelism: only preferences on a cycle
% are void.
test(acyclic_preference_kept_under_parallelism, [nondet]) :-
  GA = grouped_package_dependency(no, cat, audacious, []):run,
  GL = grouped_package_dependency(no, cat, lib, []):run,
  issue73_rules([plugins-[GA], GA-[audacious], audacious-[GL], GL-[lib], lib-[]]),
  ordering_engine_plan([plugins], ProofOut, Plan),
  ordering_engine_unreachables(ProofOut, []),
  issue73_wave(Plan, lib, WLib),
  issue73_wave(Plan, audacious, WA),
  issue73_wave(Plan, plugins, WP),
  WLib < WA, WA < WP.

% Fetchonly inter-package edges are preferences, not hard requirements.
% A parent<->child fetchonly cycle (the calligra / qtbase shape) must
% not produce unreachable/2 domain assumptions: distfiles can be
% retrieved in any order.
test(fetchonly_cycle_no_unreachable) :-
  G = grouped_package_dependency(no, cat, lib, []):fetchonly,
  issue73_rules([(prog:fetchonly)-[G], G-[lib:fetchonly], (lib:fetchonly)-[prog:fetchonly]]),
  ordering_engine_plan([prog:fetchonly], ProofOut, Plan),
  ordering_engine_unreachables(ProofOut, []),
  issue73_wave(Plan, prog:fetchonly, _),
  issue73_wave(Plan, lib:fetchonly, _),
  issue73_wave(Plan, G, _).

% order_after pseudo-constraints (the PDEPEND ordering channel) are
% preferences on their anchor: the carrier lands after the anchor.
test(order_after_anchor_honored) :-
  issue73_rules([p-[constraint(order_after(q):{[]})], q-[]]),
  ordering_engine_plan([p, q], _ProofOut, Plan),
  issue73_wave(Plan, q, WQ),
  issue73_wave(Plan, p, WP),
  WQ < WP.

% schedule_after pseudo-constraints (plain anchoring, portage-ng#89 ABI
% rebuilds) are the same carrier-after-anchor preference...
test(schedule_after_anchor_honored) :-
  issue73_rules([p-[constraint(schedule_after(q):{[]})], q-[]]),
  ordering_engine_plan([p, q], _ProofOut, Plan),
  issue73_wave(Plan, q, WQ),
  issue73_wave(Plan, p, WP),
  WQ < WP.

% ...but unlike order_after they are NOT a PDEPEND completion group: two
% rebuilds anchored on the same provider share a wave (no one-per-wave
% serialization), and an unrelated consumer of the provider does not wait
% for them.
test(schedule_after_carriers_not_serialized) :-
  issue73_rules([c-[p], p-[],
                 r1-[constraint(schedule_after(p):{[]})],
                 r2-[constraint(schedule_after(p):{[]})]]),
  ordering_engine_plan([c, r1, r2], ProofOut, Plan),
  ordering_engine_unreachables(ProofOut, []),
  issue73_wave(Plan, p, WP),
  issue73_wave(Plan, r1, WR1),
  issue73_wave(Plan, r2, WR2),
  issue73_wave(Plan, c, WC),
  WP < WR1, WR1 == WR2,
  WC =< WR1.

% Domain assumptions from pass 1 are steps like any other: wave-1 leaves.
test(domain_assumption_planned_before_consumer) :-
  issue73_rules([p-[assumed(q)], assumed(_)-[]]),
  ordering_engine_plan([p], _ProofOut, Plan),
  issue73_wave(Plan, assumed(q), W1),
  issue73_wave(Plan, p, W2),
  W1 < W2.

% Constraint body literals are not ordering edges.
test(constraint_deps_do_not_block_readiness) :-
  issue73_rules([p-[constraint(k:{v})]]),
  ordering_engine_plan([p], _ProofOut, Plan),
  issue73_wave(Plan, p, 1).

% PDEPEND completion (portage-ng#18): a consumer of provider p waits for
% p's post-install group t (the step carrying order_after(p)) — p alone
% is not functionally complete.
test(pdepend_completion_delays_consumer_after_target) :-
  issue73_rules([c-[p], p-[], t-[constraint(order_after(p):{[]})]]),
  ordering_engine_plan([c, t], ProofOut, Plan),
  ordering_engine_unreachables(ProofOut, []),
  issue73_wave(Plan, p, WP),
  issue73_wave(Plan, t, WT),
  issue73_wave(Plan, c, WC),
  WP < WT, WT < WC.

% PDEPEND completion cycle guard (portage-ng#19): when the target itself
% hard-requires the consumer (clang-runtime RDEPENDs compiler-rt), the
% completion preference would close a cycle and is skipped — the hard
% edge wins, silently.
test(pdepend_completion_cyclic_consumer_not_bumped) :-
  issue73_rules([c-[p], p-[], t-[constraint(order_after(p):{[]}), c]]),
  ordering_engine_plan([c, t], ProofOut, Plan),
  ordering_engine_unreachables(ProofOut, []),
  issue73_wave(Plan, c, WC),
  issue73_wave(Plan, t, WT),
  WC < WT.

% Configure closure (portage-ng#21): the :install action of a package
% prefers the runtime providers of its :run sibling earlier — sg's
% configure phase already exercises the bifunctors library, so
% sg:install must not co-wave with (or precede) the provider chain.
test(configure_closure_delays_install_after_run_providers, [nondet]) :-
  G = grouped_package_dependency(no, 'dev-x', bif, []):run,
  issue73_rules([ (portage://'fake/sg-1':install)-[],
                  (portage://'fake/sg-1':run)-[portage://'fake/sg-1':install, G],
                  G-[portage://'fake/bif-1':run],
                  (portage://'fake/bif-1':run)-[portage://'fake/bif-1':install],
                  (portage://'fake/bif-1':install)-[] ]),
  ordering_engine_plan([portage://'fake/sg-1':run], ProofOut, Plan),
  ordering_engine_unreachables(ProofOut, []),
  issue73_wave(Plan, G, WG),
  issue73_wave(Plan, portage://'fake/sg-1':install, WSgI),
  issue73_wave(Plan, portage://'fake/sg-1':run, WSgR),
  WG < WSgI, WSgI < WSgR.

% Grouped BDEPEND keep-installed alias: the group is a wave-1 leaf
% (empty body — old XS-Parse-Keyword still "satisfies" the version
% constraint) while a same-CN :update is planned after a perl subslot
% bump. Without the alias, Try only waits for the group and co-waves
% with the rebuild; configure then dies looking for Builder.pm under
% the new perl. The alias is a hard requires/2, not a preference.
% Versions are deliberately non-existent so the synthetic rules cannot
% collide with real KB entries (pass-1 heuristics on real atoms).
test(grouped_bdepend_waits_for_provider_rebuild) :-
  G = grouped_package_dependency(no, 'dev-perl', 'XS-Parse-Keyword', []):install,
  Try = portage://'dev-perl/Syntax-Keyword-Try-0':install,
  XSPK = portage://'dev-perl/XS-Parse-Keyword-0':update,
  Perl = portage://'dev-lang/perl-0':update,
  issue73_rules([Try-[G], G-[], XSPK-[Perl], Perl-[]]),
  ordering_engine_plan([Try, XSPK], ProofOut, Plan),
  ordering_engine_unreachables(ProofOut, []),
  issue73_wave(Plan, Perl, WPerl),
  issue73_wave(Plan, XSPK, WXSPK),
  issue73_wave(Plan, Try, WTry),
  WPerl < WXSPK, WXSPK < WTry.

% Virtual collapse (portage-ng#119): typeprof DEPENDs on the empty
% virtual/rubygems whose RDEPEND is dev-ruby/rubygems. The virtual's
% :install body names that provider as a grouped :run head. As a mere
% preference it loses to a competing preference processed earlier in
% sort order — here rubygems' own wish to land after the virtual (in the
% tree: the PDEPEND completion pull of ruby's post-install group, which
% contains virtual/rubygems) — and the consumer co-waves with the empty
% virtual while rubygems lands sixty steps later. For a virtual being
% merged the provider is a hard requirement, so the consumer lands
% strictly after the real provider's :run. (Version 0 keeps the entries
% out of the real KB so no pass-1 hook fires on them.)
test(virtual_install_waits_for_its_runtime_providers) :-
  GV   = grouped_package_dependency(no, virtual, rubygems, []):install,
  V    = portage://'virtual/rubygems-0':install,
  GR   = grouped_package_dependency(no, 'dev-ruby', rubygems, []):run,
  RRun = portage://'dev-ruby/rubygems-0':run,
  RIns = portage://'dev-ruby/rubygems-0':install,
  Tp   = portage://'dev-ruby/typeprof-0':install,
  issue73_rules([Tp-[GV], GV-[V], V-[GR], GR-[RRun], RRun-[RIns],
                 RIns-[constraint(order_after(V):{[]})]]),
  ordering_engine_plan([Tp], ProofOut, Plan),
  ordering_engine_unreachables(ProofOut, []),
  issue73_wave(Plan, RIns, WRIns),
  issue73_wave(Plan, RRun, WRRun),
  issue73_wave(Plan, V, WV),
  issue73_wave(Plan, Tp, WTp),
  WRIns < WRRun, WRRun < WV, WV < WTp.

% ...whereas a regular (non-virtual) package's grouped :run body heads
% stay preferences: its consumer does not hard-wait on them, so a
% runtime cycle is still relaxed silently instead of surfacing as an
% unreachable assumption.
test(non_virtual_install_runtime_groups_stay_preferences) :-
  G   = grouped_package_dependency(no, cat, lib, []):run,
  App = portage://'cat/app-1':install,
  Lib = portage://'cat/lib-1':run,
  issue73_rules([App-[G], G-[Lib], Lib-[App]]),
  ordering_engine_plan([App], ProofOut, Plan),
  ordering_engine_unreachables(ProofOut, []),
  issue73_wave(Plan, App, WApp),
  issue73_wave(Plan, Lib, WLib),
  WApp < WLib.

% Blocker groups never alias onto a planned merge (portage-ng#119):
% ocaml's BDEPEND `!dev-ml/findlib:0/0` is a weak blocker group whose CN
% has a planned :install. Aliasing it would make ocaml hard-require
% findlib, close a cycle with findlib's DEPEND on ocaml, and leave
% findlib configuring before ocaml is on PATH (two unreachable
% assumptions). The blocker carries no ordering; the DEPEND wins.
test(blocker_group_does_not_alias_onto_planned_merge) :-
  GO  = grouped_package_dependency(no, 'dev-lang', ocaml, []):install,
  BF  = grouped_package_dependency(weak, 'dev-ml', findlib, []):install,
  Oc  = portage://'dev-lang/ocaml-0':install,
  Fl  = portage://'dev-ml/findlib-0':install,
  issue73_rules([Fl-[GO], GO-[Oc], Oc-[BF], BF-[]]),
  ordering_engine_plan([Fl, Oc], ProofOut, Plan),
  ordering_engine_unreachables(ProofOut, []),
  issue73_wave(Plan, Oc, WOc),
  issue73_wave(Plan, Fl, WFl),
  WOc < WFl.

:- end_tests(ordering_engine_synthetic).


% -----------------------------------------------------------------------------
%  Unmerging engine: rule-based uninstall ordering over synthetic claims
% -----------------------------------------------------------------------------
%
% The depclean uninstall order (Source/Domain/Gentoo/depclean.pl +
% Source/Domain/Gentoo/Rules/unmerging.pl) runs the same planning laws as
% the ordering engine with the bindings flipped: a step is the unmerge of
% a removable package, and a step's requirement is the release of every
% claim on it (each removable consumer unmerges first). These tests drive
% depclean:uninstall_order/3 over synthetic claim graphs:
% unmerging:consumes_override/2 stands in for the VDB dependency models,
% unmerging:world_override/1 for a world release. Cyclic claim chains
% surface as retained/2 claims, never as silent cuts.

unmerging_claims(Pairs) :-
  retractall(unmerging:consumes_override(_, _)),
  forall(member(C-R, Pairs),
         assertz(unmerging:consumes_override(C, R))).

:- begin_tests(unmerging_engine_synthetic,
               [cleanup(( retractall(unmerging:consumes_override(_, _)),
                          retractall(unmerging:world_override(_)) ))]).

% A consumer unmerges before its dependency; nothing is retained.
test(unmerge_consumer_before_dependency, [true(Order-Retained == [a,b]-[])]) :-
  unmerging_claims([a-b]),
  depclean:uninstall_order([a, b], Order, Retained).

% A chain unmerges leaf-consumer-first.
test(unmerge_chain_order, [true(Order-Retained == [a,b,c]-[])]) :-
  unmerging_claims([a-b, b-c]),
  depclean:uninstall_order([c, a, b], Order, Retained).

% Independent consumers of a shared dependency share a wave (wave-major
% flatten: both precede the dependency).
test(unmerge_shared_dependency_last, [true(Order-Retained == [a,b,c]-[])]) :-
  unmerging_claims([a-c, b-c]),
  depclean:uninstall_order([a, b, c], Order, Retained).

% Packages without claims on each other are unordered (single wave).
test(unmerge_independent_nodes, [true(Order-Retained == [a,b,c]-[])]) :-
  unmerging_claims([]),
  depclean:uninstall_order([b, c, a], Order, Retained).

% Membership invariant: cyclic claims still unmerge every member exactly
% once, and the claim that could not be honored is reported as retained —
% b unmerges while claimant a is still installed.
test(unmerge_cycle_retained_claim,
     [true(Order-Retained == [b,a]-[retained(a, b)])]) :-
  unmerging_claims([a-b, b-a]),
  depclean:uninstall_order([a, b], Order, Retained).

% The same cycle with a world release for a's unmerge: the world clause
% bridges the loop with a citation instead of a retained claim.
test(unmerge_cycle_bridged_by_world, [true(Order-Retained == [b,a]-[])]) :-
  unmerging_claims([a-b, b-a]),
  assertz(unmerging:world_override(a:unmerge)),
  depclean:uninstall_order([a, b], Order, Retained),
  retractall(unmerging:world_override(_)).

:- end_tests(unmerging_engine_synthetic).


% -----------------------------------------------------------------------------
%  Pipeline: prove_with_fallback tier selection (issue #73)
% -----------------------------------------------------------------------------
%
% The 5-tier committed-choice relaxation chain (strict, keyword_acceptance,
% blockers, unmask, keyword_unmask) is exercised with stubbed failures:
% guarded test_rule/2 clauses succeed only under specific prover:assuming/1
% flags, and a marker literal in the body records which tier produced the
% accepted model.

:- begin_tests(pipeline_fallback_tiers, [cleanup(resolving:disable_test_rules)]).

test(strict_tier_succeeds_without_flags) :-
  issue73_rules([s-[]]),
  pipeline:prove_with_fallback([s], _Proof, Model, _Triggers),
  get_assoc(s, Model, _).

% Tier order: keyword_acceptance is tried before blockers, so a goal
% provable under either resolves under keyword_acceptance.
test(keyword_acceptance_preferred_over_blockers) :-
  issue73_rules([marker(_)-[]]),
  assertz((resolving:test_rule(k1, [marker(keyword)]) :-
             prover:assuming(keyword_acceptance))),
  assertz((resolving:test_rule(k1, [marker(blockers)]) :-
             prover:assuming(blockers))),
  pipeline:prove_with_fallback([k1], _Proof, Model, _Triggers),
  get_assoc(marker(keyword), Model, _),
  \+ get_assoc(marker(blockers), Model, _).

test(blockers_tier_reached_when_keyword_insufficient) :-
  issue73_rules([marker(_)-[]]),
  assertz((resolving:test_rule(k2, [marker(blockers)]) :-
             prover:assuming(blockers))),
  pipeline:prove_with_fallback([k2], _Proof, Model, _Triggers),
  get_assoc(marker(blockers), Model, _).

% The unmask tier sets ONLY unmask (no keyword_acceptance); the guard
% rejects the final keyword_unmask tier, so success proves tier 4 ran.
test(unmask_tier_sets_only_unmask) :-
  issue73_rules([marker(_)-[]]),
  assertz((resolving:test_rule(k3, [marker(unmask)]) :-
             prover:assuming(unmask),
             \+ prover:assuming(keyword_acceptance))),
  pipeline:prove_with_fallback([k3], _Proof, Model, _Triggers),
  get_assoc(marker(unmask), Model, _).

% The final tier sets keyword_acceptance AND unmask together.
test(keyword_unmask_tier_sets_both_flags) :-
  issue73_rules([marker(_)-[]]),
  assertz((resolving:test_rule(k4, [marker(both)]) :-
             prover:assuming(keyword_acceptance),
             prover:assuming(unmask))),
  pipeline:prove_with_fallback([k4], _Proof, Model, _Triggers),
  get_assoc(marker(both), Model, _).

% When no tier can prove the goal, the chain fails deterministically.
test(all_tiers_exhausted_fails, [fail]) :-
  issue73_rules([]),
  pipeline:prove_with_fallback([nope], _Proof, _Model, _Triggers).

% prove_plan_with_fallback/6 reports the tier that succeeded and still
% produces a wave-ordered plan (marker leaf before its consumer).
test(prove_plan_with_fallback_reports_tier, [true(Used == keyword_acceptance)]) :-
  issue73_rules([marker(_)-[]]),
  assertz((resolving:test_rule(k5, [marker(keyword)]) :-
             prover:assuming(keyword_acceptance))),
  pipeline:prove_plan_with_fallback([k5], _Proof, _Model, Plan, _Triggers, Used),
  issue73_wave(Plan, marker(keyword), W1),
  issue73_wave(Plan, k5, W2),
  W1 < W2.

test(prove_plan_with_fallback_strict_reports_false, [true(Used == false)]) :-
  issue73_rules([s2-[]]),
  pipeline:prove_plan_with_fallback([s2], _Proof, _Model, _Plan, _Triggers, Used).

% The assuming/1 flags are scoped to the fallback attempt: none survive.
test(assuming_flags_restored_after_fallback) :-
  issue73_rules([marker(_)-[]]),
  assertz((resolving:test_rule(k6, [marker(both)]) :-
             prover:assuming(keyword_acceptance),
             prover:assuming(unmask))),
  pipeline:prove_with_fallback([k6], _Proof, _Model, _Triggers),
  \+ prover:assuming(keyword_acceptance),
  \+ prover:assuming(blockers),
  \+ prover:assuming(unmask).

:- end_tests(pipeline_fallback_tiers).
