/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> ORDERING
Order rule set (pass 2): planning laws + Gentoo bindings.

The rule set the orderer stage hands the generic prover
(`orderer:prove_scheduled/2`).  Two layers in one module:

The *planning laws* (rule/2) are domain-generic: a step can be placed
once everything it requires is available; a requirement is available
when an earlier plan step provides it, when the installed world already
provides it, or — failing both — by recording an unreachable assumption.

The *bindings* answer the domain questions those laws ask, by reading
the pass-1 proof and the VDB (installed packages):

  - step/1     : is this literal a pass-1 plan step?
  - requires/2 : what does a step require before it can be placed
                 (build-time deps, including a planned same-CN merge
                 when the grouped :install is keep-installed, and the
                 runtime providers of a virtual being merged)?
  - prefers/2  : what would a step like placed earlier without insisting
                 (runtime dep groups, PDEPEND ordering hints)? Under the
                 default `--optimize parallelism` strategy a preference
                 whose provider depends back on its consumer is void
                 (same_component/2); `--optimize soft-requirements`
                 hands every preference to the projection.
  - world/2    : does the installed system, as it stands, already provide
                 this requirement for this consumer?

No graph algorithms live here: requires/prefers are a reading of the
pass-1 proof bodies (dependency provenance), world is a reading of the
VDB, and the mutual-reachability classes behind same_component/2 come
from the generic components:classes_succ/3 (Source/Logic/components.pl). See
Documentation/Handbook/13-doc-planning.md (the planning laws, the Gentoo
bindings and the two ordering strategies).
*/

:- module(ordering, []).

:- use_module(library(assoc)).
:- use_module(library(ordsets)).

% =============================================================================
%  ORDERING declarations
% =============================================================================

% -----------------------------------------------------------------------------
% Rule set: the planning laws
% -----------------------------------------------------------------------------
%
% The laws own no Gentoo terms: what a step is, what it requires, and
% what the world already provides are answered by the bindings below.
%
% The availability tie-break "prefer an earlier plan step over the
% installed world" is an if-then-else, NOT alternative clauses: pass-2
% derivations must succeed without choicepoints so the prover's
% cycle-stack pops (prover:prove_on_cycle_stack/2 around each rule body)
% fire eagerly. A nondet rule would defer the pops, leave completed
% literals on the stack, and make the guard below see stale "ancestors".
% (Pass 1 tolerates nondet rules because completed literals short-circuit
% through the model before the cycle stack is ever consulted; this guard
% consults the stack directly, so it needs the stack accurate.)
%
% The `\+ prover:currently_proving/1` guard itself is load-bearing: the
% prover core never fails a cyclic goal (it succeeds benignly or as a
% cycle-break assumption), so without the guard the world case would be
% unreachable and every pass-2 cycle would silently become a cycle-break
% marker — the mechanism this engine retires.

%! ordering:rule(+Literal, -Body)
%
% The pass-2 rule set. One clause per literal functor, each
% deterministic (see above). The first clause strips the optional
% ?{Ctx} proof-context wrapper the prover's literal canonicalization
% may re-attach.

rule(Literal?{_}, Body) :-
  !,
  ordering:rule(Literal, Body).

% A step can be placed once everything it requires is available:
rule(scheduled(H), Conds) :-
  ordering:step(H),
  findall(available(H, D), ordering:requires(H, D), Conds).

% A requirement is available when an earlier plan step provides it, or —
% failing that — when the world as it stands already provides it, or —
% failing that too — by recording the bootstrap failure as a negative
% domain assumption instead of failing the pass:
rule(available(H, D), Body) :-
  (   ordering:step(D),
      \+ prover:currently_proving(scheduled(D))
  ->  Body = [scheduled(D)]
  ;   ordering:world(H, D)
  ->  Body = []
  ;   Body = [assumed(unreachable(H, D))]
  ).

rule(assumed(unreachable(_, _)), []).


% -----------------------------------------------------------------------------
% Pass-1 proof access
% -----------------------------------------------------------------------------

%! ordering:proof(-ProofAVL)
%
% The pass-1 proof published by orderer:with_ordering_pass/2.

proof(ProofAVL) :-
  nb_current(portage_ordering_proof, ProofAVL),
  !,
  ProofAVL \== t.


%! ordering:step(+H)
%
% H is a pass-1 plan step: it has a proof entry, either a regular rule
% or a cycle-break assumption (whose stored body still carries the
% dependency edges).

step(H) :-
  ordering:proof(Proof),
  ( get_assoc(rule(H), Proof, _) -> true
  ; get_assoc(assumed(rule(H)), Proof, _)
  ).


%! ordering:step_body(+H, -Body)
%
% The proof body of step H. Prefers the complete rule(H) entry over the
% assumed(rule(H)) cycle-break entry (whose body may be partial).

step_body(H, Body) :-
  ordering:proof(Proof),
  ( get_assoc(rule(H), Proof, dep(_, Body)?_ ) -> true
  ; get_assoc(assumed(rule(H)), Proof, dep(_, Body)?_ )
  ).


%! ordering:step_cores(+H, -Cores)
%
% The canonical literals of step H's proof body (prover:canon_literal/3
% on every body literal, proof contexts dropped), in body order. The
% readings below work on this list rather than on the raw body.

step_cores(H, Cores) :-
  ordering:step_body(H, Body),
  ordering:canon_cores(Body, Cores).

canon_cores([], []).
canon_cores([Literal|Literals], [Core|Cores]) :-
  prover:canon_literal(Literal, Core, _),
  ordering:canon_cores(Literals, Cores).


% -----------------------------------------------------------------------------
% Requirements and preferences: a reading of the proof bodies
% -----------------------------------------------------------------------------

%! ordering:requires(+H, -D)
%
% Hard requirement: D must be available before step H can be placed.
% Three sources, all read from H's pass-1 proof body:
%
%   - every body literal that is itself a step, except preference-only
%     deps (`runtime_dep/1`: grouped :run heads, and :fetchonly heads).
%     A runtime dep does not gate the build; fetching another package's
%     sources does not gate fetching this one;
%   - satisfied grouped :install steps are not hard either
%     (satisfied_group_step/1): when the installed system already
%     satisfies the group as stated and no member dep is sub-slot
%     pinned, the installed provider can serve the build — the
%     keep-installed situation — so a provider update the group
%     happens to select must not gate the consumer. The selected
%     provider stays a preference (see prefers0/2), so it still
%     lands first whenever that closes no cycle. Without this, the
%     BDEPEND chain of a glib update (docutils/pillow/harfbuzz
%     updates selected for new Python targets) closed a hard cycle
%     back through gobject-introspection to glib itself, although
%     traditional emerge builds glib against the installed
%     intermediates and floats those updates later;
%   - grouped BDEPEND/DEPEND alias: a concrete grouped :install is often
%     *not* the plan step (keep-installed groups have an empty body, so
%     they are a wave-1 leaf). When a merge-family action for the same
%     CN *is* planned, the consumer must wait for that rebuild — otherwise
%     it co-waves with the provider and configures against the stale
%     install (perl 5.42→5.44 / Syntax-Keyword-Try before
%     XS-Parse-Keyword). The alias only fires onto a merge of the
%     slot the group states, and only when the installed provider
%     cannot serve as-is (see grouped_install_planned/2). Assumed
%     grouped deps stay a preference
%     (portage-ng#95); this clause is the hard edge for the
%     keep-installed path. Blocker groups never alias: a blocker names
%     a package that must be *absent*, so `!dev-ml/findlib` in ocaml's
%     BDEPEND must not make ocaml wait for the planned findlib merge
%     (that closed a hard cycle and pushed findlib before ocaml,
%     portage-ng#119);
%   - virtual collapse (portage-ng#119): a `virtual/*` package has no
%     build and installs no files — a DEPEND/BDEPEND on it means the
%     consumer needs the virtual's RDEPEND providers at build time
%     (Portage collapses the virtual's runtime deps onto the consumer
%     with the consumer's dep priority). The pass-1 :install body of
%     the virtual already names those providers as grouped :run heads;
%     for a virtual being merged they are hard requirements, not
%     preferences, so `dev-ruby/typeprof` cannot co-wave with an empty
%     `virtual/rubygems` while `dev-ruby/rubygems` lands sixty steps
%     later. Consumers of a keep-installed virtual are covered by the
%     same-CN alias whenever the virtual itself is re-merged.
%
% Constraints and body literals without a proof entry and without a
% planned same-CN merge carry no ordering information.
%
% The reading itself is read_requires/3, over the canonical body
% literals of H (step_cores/2); requires/2 serves it from the per-pass
% relation index (step_relation/3), because every step's requirements
% are asked for twice per pass — by the scheduled/1 law and by the
% component index (edge/2) — and the published proof does not change
% between the two.

requires(H, D) :-
  ordering:step_relation(requires, H, Ds),
  member(D, Ds).

read_requires(H, Cores, D) :-
  member(Core, Cores),
  \+ constraint:is_constraint(Core),
  Core \== H,
  \+ ordering:runtime_dep(Core),
  \+ ordering:satisfied_group_step(Core),
  ordering:step(Core),
  D = Core.

read_requires(H, Cores, D) :-
  member(Core, Cores),
  ordering:grouped_install_planned(Core, D),
  D \== H.

read_requires(H, Cores, D) :-
  ordering:virtual_merge_step(H),
  member(Core, Cores),
  Core = grouped_package_dependency(no, _, _, _):run,
  ordering:step(Core),
  D = Core.


%! ordering:satisfied_group_step(+Core)
%
% Core is a grouped :install step the installed system already
% satisfies as stated, with no sub-slot (`:=`, req `equal`) pin
% among its member deps and at least one stated dep: the
% keep-installed situation, in which the consumer can build
% against the installed provider (see requires/2). Groups with
% empty Deps state nothing to satisfy, and sub-slot-pinned groups
% need the planned rebuild's ABI, so neither is satisfied here.
% Mirrors the satisfaction guard in grouped_install_planned/2
% (which uses group_installed_satisfied/3 directly).

ordering:satisfied_group_step(grouped_package_dependency(no, C, N, Deps):install) :-
  Deps \== [],
  \+ ( member(package_dependency(_, _, _, _, _, _, SlotReqs, _), Deps),
       memberchk(equal, SlotReqs) ),
  ordering:group_installed_satisfied(C, N, Deps).


%! ordering:prefers(+H, -D)
%
% Preference: H would like D placed earlier, without insisting. The raw
% preferences come from ordering:prefers0/2; which of them are handed to
% the projection depends on the ordering strategy (`--optimize`):
%
%   - parallelism (default): a preference whose provider depends back on
%     its consumer — H and D lie in the same mutual-reachability class
%     over requires ∪ prefers0 — is void, except for explicit PDEPEND
%     `order_after` anchors (`ordering:order_after_step/2`), which stay
%     active so a post-dependency is placed after its parent even when
%     it RDEPENDs back on that parent (portage-ng#124). Inside a pure
%     runtime cycle the order is free (Portage treats runtime cycles as
%     freely orderable), so the cycle's members merge side by side
%     instead of one per step; preferences between classes are always
%     kept;
%   - soft-requirements: every raw preference is handed to the projection,
%     which honors as many as it can in processing order and drops only
%     the ones that would close a cycle (orderer:honor_preferences/4).
%     Serialises a cycle's members one step per package; the choice of
%     which member goes first is processing-order dependent.
%
% Hard requirements (requires/2) are unaffected by the strategy.

prefers(H, D) :-
  ordering:prefers0(H, D),
  ( preference:local_flag(optimize_soft_requirements) -> true
  ; ordering:order_after_step(H, D) -> true
  ; \+ ordering:same_component(H, D)
  ).


%! ordering:same_component(+H, +D)
%
% H and D are mutually reachable over ordering:edge/2 (requires ∪
% prefers0): each depends, directly or transitively, on the other. Read
% from the per-pass component index.

same_component(H, D) :-
  ordering:component_index(Idx),
  get_assoc(H, Idx, C),
  get_assoc(D, Idx, C).


%! ordering:edge(+H, -D)
%
% The edge relation the component index is built over: everything H
% waits for, whether it insists (requires/2) or merely prefers (prefers0/2).

edge(H, D) :- ordering:requires(H, D).
edge(H, D) :- ordering:prefers0(H, D).


%! ordering:prefers0(+H, -D)
%
% Raw preference: H would like D placed earlier, without insisting. Five
% sources, all read from the pass-1 proof:
%
%   - preference-only deps (`runtime_dep/1`: grouped :run heads, and
%     :fetchonly heads) in H's body — RDEPEND wants its providers early
%     but cannot force them; fetching another package's sources likewise
%     cannot gate this fetch (Portage relaxes exactly these edges
%     inside cycles);
%   - `constraint(order_after(Anchor))` pseudo-constraints (the PDEPEND
%     ordering channel, Handbook chapter 12) — post-merge by nature,
%     best-effort by Portage semantics;
%   - `constraint(schedule_after(Anchor))` pseudo-constraints (plain
%     anchoring, portage-ng#89): the carrier alone goes after Anchor —
%     unlike order_after, NOT indexed as a PDEPEND completion group, so
%     the anchor's other consumers do not wait for the carrier (sub-slot
%     ABI rebuilds would otherwise serialize into one-per-wave chains);
%   - PDEPEND completion (portage-ng#18/#19): a step depending on a
%     provider P prefers P's PDEPEND targets placed earlier too — P is
%     only functionally complete once its post-install group is merged
%     (ruby gems wait for rubygems). Cycle safety (the clang/compiler-rt
%     case) is inherited from the projection's preference honoring: a
%     preference that would close a cycle is skipped;
%   - configure closure (portage-ng#21): the :install action of a package
%     prefers the runtime providers of its :run sibling placed earlier —
%     the package's configure phase already exercises them;
%   - assumed-dep alias (portage-ng#95): a dep that degraded to a domain
%     assumption (e.g. a REQUIRED_USE conflict on the provider) still
%     prefers the concretely planned action of the same package earlier,
%     when another proof path planned that package for the same phase;
%   - satisfied groups (satisfied_group_step/1): a grouped :install the
%     installed system already satisfies is not hard (requires/2), but
%     its consumer still prefers the group's selected provider steps
%     earlier, exactly like a runtime group — new files first when
%     possible, installed files when the update must float later.
%
% Like requires/2, prefers0/2 serves the reading (read_prefers0/3, over
% the canonical body literals of H) from the per-pass relation index:
% prefers/2 and the component index (edge/2) both enumerate it for
% every step.

prefers0(H, D) :-
  ordering:step_relation(prefers0, H, Ds),
  member(D, Ds).

read_prefers0(H, Cores, D) :-
  ordering:read_order_after_step(H, Cores, D).
read_prefers0(H, Cores, D) :-
  ordering:read_prefers0_other(H, Cores, D).


%! ordering:read_prefers0_other(+H, +Cores, -D)
%
% Raw preferences of H other than the `order_after` channel, which
% `read_relations/2` already collected. Same sources as prefers0/2
% minus that first clause.

read_prefers0_other(H, Cores, D) :-
  member(Core, Cores),
  ( Core = constraint(schedule_after(Anchor0):_) ->
      prover:canon_literal(Anchor0, D, _)
  ; \+ constraint:is_constraint(Core),
    ordering:runtime_dep(Core),
    D = Core
  ),
  D \== H,
  ordering:step(D).

% Satisfied groups: the selected provider steps of a group the
% installed system already satisfies (not hard, see requires/2).
read_prefers0_other(H, Cores, D) :-
  member(Core, Cores),
  ordering:satisfied_group_step(Core),
  ordering:step_cores(Core, GroupCores),
  member(D, GroupCores),
  \+ constraint:is_constraint(D),
  D \== H,
  ordering:step(D).

% PDEPEND completion (portage-ng#18/#19/#124).
% Only genuine external consumers H of the anchor package qualify:
% grouped_package_dependency wrappers, the anchor package itself, and
% the PDEPEND target package itself are excluded so completion never
% hoists a post-dependency ahead of its parent.
read_prefers0_other(H, Cores, T) :-
  ordering:pdepend_anchor_index(Idx),
  Idx \== t,
  \+ ordering:is_grouped_dep_step(H),
  member(Core, Cores),
  ordering:dep_anchor_key(Core, Key),
  get_assoc(Key, Idx, Pairs),
  member(ACore-T, Pairs),
  T \== H,
  \+ ordering:same_package_entry(H, ACore),
  \+ ordering:same_package_entry(H, T).

% Configure closure (portage-ng#21).
read_prefers0_other(Repository://Entry:install, _Cores, D) :-
  ordering:step_cores(Repository://Entry:run, RunCores),
  member(Core, RunCores),
  ordering:runtime_dep(Core),
  ordering:step(Core),
  D = Core.

% Assumed-dep alias (portage-ng#95).
read_prefers0_other(H, Cores, D) :-
  member(assumed(Inner), Cores),
  prover:canon_literal(Inner, G:Action, _),
  ordering:grouped_cn(G, C, N),
  ordering:dep_action_phase(Action, Phase),
  ordering:cn_action_index(Idx),
  get_assoc(cn(C, N, Phase), Idx, Steps),
  member(D, Steps),
  D \== H.


%! ordering:runtime_dep(+Core)
%
% True for preference-only body literals: ordered early when possible,
% never required. Two families:
%
%   - grouped :run heads (RDEPEND provenance) — a runtime dep does not
%     gate the build;
%   - :fetchonly heads (grouped or concrete) — fetching another
%     package's sources does not gate fetching this one. Distfiles are
%     independent; a fetchonly cycle is not a bootstrap failure.

runtime_dep(grouped_package_dependency(_, _, _, _):run).
runtime_dep(grouped_package_dependency(_, _, _, _):fetchonly).
runtime_dep(grouped_package_dependency(_, _, _):fetchonly).
runtime_dep(_://_:fetchonly).


% -----------------------------------------------------------------------------
% Per-pass indexes (components, PDEPEND anchors, concrete actions by package)
% -----------------------------------------------------------------------------
%
% Three lazily-built views over the published pass-1 proof, reset at the
% start of every ordering pass (orderer:with_ordering_pass calls
% ordering:prepare_pass/0); thread-local like the published proof itself.
%
%   - the component index maps every plan step to its mutual-reachability
%     class over requires ∪ prefers0, so prefers/2 can tell a preference
%     on a cycle from one between cycles (same_component/2). The classes
%     are computed by the generic components:classes_succ/3
%     (Source/Logic) from the per-step successor lists in the relation
%     index; this module only names the nodes and the edges;
%   - the PDEPEND anchor index maps a provider identity to the steps that
%     carry a `constraint(order_after(Provider))` marker — i.e. the
%     provider's PDEPEND group. Consumers of the provider look themselves
%     up here (via dep_anchor_key/2) to prefer the post-install group
%     earlier (portage-ng#18/#19);
%   - the concrete-action index maps cn(Category-Name)-Action to the
%     concrete plan steps for that package, so grouped :install deps
%     (hard requires) and assumed grouped deps (portage-ng#95 preference)
%     can alias to the planned provider.
%
% Next to those, the per-pass relation index (step_relation/3) holds
% the answers of requires/2, prefers0/2 and order_after_step/2 for every
% step: each is asked for the same step more than once per pass (by the
% scheduled/1 law, the component index, prefers/2 and the orderer's
% preference partition) and reads only the immutable published proof,
% the indexes above and the VDB. The index is built once per pass, on
% the first question, by reading all three relations for every proof
% head over its canonical body literals (step_cores/2, canonicalised
% once per head); being an AVL keyed by the step it answers with one
% get_assoc/3. The VDB readings behind world/2 are memoised per pass as
% well, in the `portage_ordering_memo` nbstore (world_fact/2), because
% their key set is not known in advance.
%
% All of this is reset by prepare_pass/0 and released by release_pass/0,
% so outside a pass nothing is memoised and every question is answered
% from scratch, as before.

%! ordering:prepare_pass
%
% Reset the per-pass caches. Called by orderer:with_ordering_pass/2.

prepare_pass :-
  nb_setval(portage_ordering_component_idx, none),
  nb_setval(portage_ordering_pdepend_idx, none),
  nb_setval(portage_ordering_order_after_idx, none),
  nb_setval(portage_ordering_cnaction_idx, none),
  nb_setval(portage_ordering_heads, none),
  nb_setval(portage_ordering_relation_idx, none),
  nbstore:reset(portage_ordering_memo),
  nb_setval(portage_ordering_memo_active, true).


%! ordering:release_pass
%
% Drop the per-pass memo once the pass is over. Called by
% orderer:with_ordering_pass/2 on the way out.

release_pass :-
  nb_setval(portage_ordering_memo_active, false),
  nb_setval(portage_ordering_heads, none),
  nb_setval(portage_ordering_relation_idx, none),
  nbstore:reset(portage_ordering_memo).


%! ordering:memo_active
%
% An ordering pass is running: answers may be recorded in the per-pass
% memo.

memo_active :-
  nb_current(portage_ordering_memo_active, true).


%! ordering:proof_heads(-Heads)
%
% The sorted, duplicate-free heads of every pass-1 proof rule (keys
% rule(H) and assumed(rule(H))), kept for the pass.

proof_heads(Heads) :-
  ( nb_current(portage_ordering_heads, Heads0), Heads0 \== none ->
      Heads = Heads0
  ; ordering:proof(Proof),
    findall(H,
            ( assoc:gen_assoc(Key, Proof, _),
              ( Key = rule(H) -> true ; Key = assumed(rule(H)) )
            ),
            Heads0),
    sort(Heads0, Heads),
    nb_setval(portage_ordering_heads, Heads)
  ).


%! ordering:step_relation(+Relation, +H, -Ds)
%
% Ds is the list of every D with ordering:read_<Relation>(H, Cores, D)
% over H's canonical body literals, in derivation order with
% duplicates kept, so `member(D, Ds)` yields exactly the solutions the
% reading yields. Inside a pass the answer comes from the relation
% index (built on first use for every proof head); a literal outside
% the index — or any question outside a pass — is read directly.

step_relation(Relation, H, Ds) :-
  ( ordering:memo_active,
    ordering:relation_index(Idx),
    get_assoc(H, Idx, Relations) ->
      ordering:relation_of(Relation, Relations, Ds)
  ; ordering:read_relations(H, Relations),
    ordering:relation_of(Relation, Relations, Ds)
  ).

relation_of(requires,         relations(Ds, _, _), Ds).
relation_of(prefers0,         relations(_, Ds, _), Ds).
relation_of(order_after_step, relations(_, _, Ds), Ds).


%! ordering:read_relations(+H, -Relations)
%
% Relations = relations(Requires, Prefers0, OrderAfter): Requires in
% derivation order (duplicates kept); OrderAfter and Prefers0 sorted
% unique, with OrderAfter collected once and reused inside Prefers0.
% A literal without a proof body (not a step) has no canonical
% literals, so the readings over the body are empty for it, exactly as
% they were when the body lookup failed.

read_relations(H, relations(Requires, Prefers0, OrderAfter)) :-
  ( ordering:step_cores(H, Cores) -> true ; Cores = [] ),
  findall(D, ordering:read_order_after_step(H, Cores, D), OrderAfter0),
  sort(OrderAfter0, OrderAfter),
  findall(D, ordering:read_prefers0_other(H, Cores, D), PrefersOther0),
  sort(PrefersOther0, PrefersOther),
  ord_union(OrderAfter, PrefersOther, Prefers0),
  findall(D, ordering:read_requires(H, Cores, D), Requires).


%! ordering:relation_index(-Idx)
%
% The per-pass relation index: step -> relations/3, built on first use
% by reading every proof head.

relation_index(Idx) :-
  ( nb_current(portage_ordering_relation_idx, Idx0), Idx0 \== none ->
      Idx = Idx0
  ; ordering:build_relation_index(Idx),
    nb_setval(portage_ordering_relation_idx, Idx)
  ).

build_relation_index(Idx) :-
  ordering:proof_heads(Heads),
  findall(H-Relations,
          ( member(H, Heads),
            ordering:read_relations(H, Relations)
          ),
          Pairs),
  ord_list_to_assoc(Pairs, Idx).


%! ordering:world_fact(+Key, :Goal)
%
% Semidet memo of a VDB reading: succeeds iff Goal succeeds, with the
% outcome recorded per pass under Key. Exceptions raised by Goal count
% as failure, as the world/2 clauses treated them before the memo.

world_fact(Key, Goal) :-
  ( nbstore:get(portage_ordering_memo, Key, Known) ->
      Known == true
  ; ( catch(Goal, _, fail) -> Known = true ; Known = false ),
    ( ordering:memo_active ->
        nbstore:put(portage_ordering_memo, Key, Known)
    ; true
    ),
    Known == true
  ).


%! ordering:component_index(-Idx)
%
% The component index for the current pass, built on first use: plan
% step -> class identifier (components:classes_succ/3 over all pass-1
% proof heads and the requires ∪ prefers0 successor lists).

component_index(Idx) :-
  ( nb_current(portage_ordering_component_idx, Idx0), Idx0 \== none ->
      Idx = Idx0
  ; ordering:build_component_index(Idx),
    nb_setval(portage_ordering_component_idx, Idx)
  ).

build_component_index(Idx) :-
  ordering:proof_heads(Heads),
  ordering:relation_index(RelIdx),
  ordering:successor_pairs(Heads, RelIdx, Pairs),
  list_to_assoc(Pairs, SuccAVL),
  components:classes_succ(Heads, SuccAVL, Idx).


successor_pairs([], _, []).
successor_pairs([H|Hs], RelIdx, [H-Ws|Pairs]) :-
  ( get_assoc(H, RelIdx, relations(Req, Pref, _)) ->
      append(Req, Pref, Ws0),
      sort(Ws0, Ws)
  ; Ws = []
  ),
  ordering:successor_pairs(Hs, RelIdx, Pairs).


%! ordering:pdepend_anchor_index(-Idx)
%
% The anchor index for the current pass, built on first use.

pdepend_anchor_index(Idx) :-
  ( nb_current(portage_ordering_pdepend_idx, Idx0), Idx0 \== none ->
      Idx = Idx0
  ; ordering:build_pdepend_anchor_index(Idx),
    nb_setval(portage_ordering_pdepend_idx, Idx)
  ).

build_pdepend_anchor_index(Idx) :-
  ordering:proof(Proof),
  findall(Key-(ACore-T),
          ( assoc:gen_assoc(ProofKey, Proof, dep(_, Body)?_),
            ( ProofKey = rule(T) -> true ; ProofKey = assumed(rule(T)) ),
            member(Literal, Body),
            prover:canon_literal(Literal, constraint(order_after(Anchor0):_), _),
            prover:canon_literal(Anchor0, ACore, _),
            ordering:anchor_key(ACore, Key)
          ),
          Pairs0),
  sort(Pairs0, Pairs),
  ordering:group_pairs_rev(Pairs, Grouped),
  ord_list_to_assoc(Grouped, Idx).


%! ordering:order_after_step(+H, -D)
%
% Step H is ordered after step D via the PDEPEND order_after / after_only
% channel (portage-ng#124). Covers both direct `constraint(order_after(D))`
% literals in H's body and merge-family actions (`:install`/`:update`/...)
% of an entry whose `:run` step carries the PDEPEND anchor (including when
% `:run` was already proven before the PDEPEND obligation fired, leaving
% `after_only(D)` on the grouped PDEPEND body literal).
%
% Served from the per-pass relation index (read_order_after_step/3,
% over the canonical body literals of H, is the reading): asked once
% per step by prefers0/2 and again for every raw preference by
% prefers/2 and the orderer's preference partition.

order_after_step(H, D) :-
  ordering:step_relation(order_after_step, H, Ds),
  member(D, Ds).

read_order_after_step(H, Cores, D) :-
  member(constraint(order_after(Anchor0):_), Cores),
  prover:canon_literal(Anchor0, D, _),
  D \== H,
  ordering:step(D).

read_order_after_step(Repository://Entry:Action, _Cores, D) :-
  ( Action == run ; ordering:merge_action(Action) ),
  ordering:entry_order_after_anchor(Repository, Entry, D),
  D \== Repository://Entry:Action,
  ordering:step(Repository://Entry:Action),
  ordering:step(D).


%! ordering:entry_order_after_anchor(+Repository, +Entry, -Anchor)
%
% Entry's `:run` step carries a PDEPEND anchor (either in its own body or
% via an incoming `after_only/1` context from a PDEPEND group). Read from
% the per-pass order_after entry index.

entry_order_after_anchor(Repository, Entry, D) :-
  ordering:order_after_entry_index(Idx),
  get_assoc(Repository://Entry, Idx, Anchors),
  member(D, Anchors).


%! ordering:order_after_entry_index(-Idx)
%
% Per-pass index mapping `Repository://Entry` to the list of canonical
% anchor steps `D` that its `:run` action is ordered after (either via a
% `constraint(order_after(D))` body literal or an incoming `after_only(D)`
% context on a grouped `:run` body literal). Built once per pass on first
% use and reset by `ordering:prepare_pass/0`.

order_after_entry_index(Idx) :-
  ( nb_current(portage_ordering_order_after_idx, Idx0), Idx0 \== none ->
      Idx = Idx0
  ; ordering:build_order_after_entry_index(Idx),
    nb_setval(portage_ordering_order_after_idx, Idx)
  ).

build_order_after_entry_index(Idx) :-
  ordering:proof(Proof),
  findall((Repository://Entry)-D,
          ( assoc:gen_assoc(ProofKey, Proof, dep(_, Body)?_),
            ( ( ProofKey = rule(Repository://Entry:run)
              ; ProofKey = assumed(rule(Repository://Entry:run))
              ),
              member(Literal, Body),
              prover:canon_literal(Literal, constraint(order_after(Anchor0):_), _),
              prover:canon_literal(Anchor0, D, _)
            ; ( ProofKey = rule(grouped_package_dependency(no, _, _, _):run)
              ; ProofKey = assumed(rule(grouped_package_dependency(no, _, _, _):run))
              ),
              member(Literal, Body),
              prover:canon_literal(Literal, Repository://Entry:_, Ctx0),
              ordering:ctx_list(Ctx0, Ctx),
              memberchk(after_only(Anchor0), Ctx),
              prover:canon_literal(Anchor0, D, _)
            )
          ),
          Pairs0),
  sort(Pairs0, Pairs),
  ordering:group_pairs_rev(Pairs, Grouped),
  ord_list_to_assoc(Grouped, Idx).


%! ordering:ctx_list(+Ctx0, -Ctx)
%
% Unwraps a proof-context term into a plain list.

ctx_list(Ctx, Ctx) :- is_list(Ctx), !.
ctx_list({Ctx}, Ctx) :- is_list(Ctx), !.
ctx_list(_, []).


%! ordering:is_grouped_dep_step(+Step)
%
% True when Step is a grouped_package_dependency head rather than a
% concrete package action.

is_grouped_dep_step(grouped_package_dependency(_, _, _, _):_).
is_grouped_dep_step(grouped_package_dependency(_, _, _):_).


%! ordering:same_package_entry(+StepA, +StepB)
%
% True when StepA and StepB are actions of the same repository entry
% (or identical bare atoms in synthetic tests).

same_package_entry(Repository://Entry:_, Repository://Entry:_) :- !.
same_package_entry(Step, Step).


%! ordering:dep_anchor_key(+Core, -Key)
%
% The provider-identity key a dependency literal resolves to: concrete
% actions key on their entry, dependency groups on category-name.
% Blocker groups and download/fetchonly actions carry no provider identity.

dep_anchor_key(Repository://Entry:Action, entry(Repository://Entry)) :-
  Action \== download,
  Action \== fetchonly,
  !.
dep_anchor_key(grouped_package_dependency(no, C, N, _):Action, cn(C-N)) :-
  Action \== download,
  Action \== fetchonly,
  !.
dep_anchor_key(Core, entry(Core)) :-
  atom(Core).


%! ordering:anchor_key(+ACore, -Key)
%
% The keys an order_after anchor is indexed under: its entry, plus its
% category-name when the KB resolves it (so grouped consumer deps match).

anchor_key(Repository://Entry:_, Key) :-
  !,
  ( Key = entry(Repository://Entry)
  ; catch(query:search([category(C), name(N)], Repository://Entry), _, fail),
    Key = cn(C-N)
  ).
anchor_key(ACore, entry(ACore)) :-
  atom(ACore).


%! ordering:cn_action_index(-Idx)
%
% The concrete-action index for the current pass, built on first use:
% cn(Category, Name, Phase) -> concrete plan steps of that package
% for the given dependency phase (`install` or `run`), ordered by
% action rank so a single lookup replaces four merge-family keys.

cn_action_index(Idx) :-
  ( nb_current(portage_ordering_cnaction_idx, Idx0), Idx0 \== none ->
      Idx = Idx0
  ; ordering:build_cn_action_index(Idx),
    nb_setval(portage_ordering_cnaction_idx, Idx)
  ).

build_cn_action_index(Idx) :-
  ordering:proof(Proof),
  findall(cn(C, N, Phase)-(Rank-Head),
          ( assoc:gen_assoc(ProofKey, Proof, _),
            ( ProofKey = rule(Head) -> true ; ProofKey = assumed(rule(Head)) ),
            Head = Repository://Entry:Action,
            ordering:action_phase_rank(Action, Phase, Rank),
            ordering:entry_cn(Repository, Entry, C, N)
          ),
          Pairs0),
  sort(Pairs0, Pairs),
  ordering:group_cn_phase_pairs(Pairs, Grouped),
  ord_list_to_assoc(Grouped, Idx).


%! ordering:action_phase_rank(+Action, -Phase, -Rank) is semidet
%
% Maps a plan action onto the dependency phase it satisfies and a
% rank used to keep merge-family steps in install/update/downgrade/
% reinstall order inside a phase bucket.

action_phase_rank(install,   install, 1).
action_phase_rank(update,    install, 2).
action_phase_rank(downgrade, install, 3).
action_phase_rank(reinstall, install, 4).
action_phase_rank(run,       run,     1).


%! ordering:dep_action_phase(+Action, -Phase) is semidet
%
% Dependency-literal action to the cn_action_index phase key.

dep_action_phase(install, install).
dep_action_phase(run,     run).


%! ordering:group_pairs_rev(+SortedPairs, -Grouped)
%
% Group consecutive Key-Val pairs into Key-Vals, prepending so the
% last sorted value comes first — the same bucket order
% foldl(anchor_index_put) produced.

group_pairs_rev([], []).
group_pairs_rev([K-V|Rest], [K-Vs|Groups]) :-
  ordering:group_pairs_same_rev(Rest, K, [V], Vs, Tail),
  ordering:group_pairs_rev(Tail, Groups).

group_pairs_same_rev([K-V|Rest], K, Acc, Vs, Tail) :-
  !,
  ordering:group_pairs_same_rev(Rest, K, [V|Acc], Vs, Tail).
group_pairs_same_rev(Rest, _, Vs, Vs, Rest).


%! ordering:group_cn_phase_pairs(+SortedPairs, -Grouped)
%
% Group cn(C,N,Phase)-(Rank-Head) pairs. Same rank prepends (reverse
% sorted heads); a rank change appends the next rank's heads so
% member/2 walks install, then update, then downgrade, then reinstall.

group_cn_phase_pairs([], []).
group_cn_phase_pairs([Key-(Rank-Head)|Rest], [Key-Heads|Groups]) :-
  ordering:group_cn_same_key(Rest, Key, Rank, [Head], Heads, Tail),
  ordering:group_cn_phase_pairs(Tail, Groups).

group_cn_same_key([Key-(Rank-Head)|Rest], Key, Rank, Acc, Heads, Tail) :-
  !,
  ordering:group_cn_same_key(Rest, Key, Rank, [Head|Acc], Heads, Tail).
group_cn_same_key([Key-(Rank2-Head)|Rest], Key, _Rank1, Acc, Heads, Tail) :-
  !,
  ordering:group_cn_same_key(Rest, Key, Rank2, [Head], MoreHeads, Tail),
  append(Acc, MoreHeads, Heads).
group_cn_same_key(Rest, _Key, _Rank, Acc, Acc, Rest).


%! ordering:entry_cn(+Repository, +Entry, -C, -N)
%
% Category and name of a repository entry. Prefers the ordered-entry
% cache, then the KB query; falls back to parsing `Category/PF` so the
% concrete-action index works in KB-free synthetic tests
% (`portage://'fake/sg-1'`).

entry_cn(Repository, Entry, C, N) :-
  ( cache:ordered_entry(Repository, Entry, C, N, _) ->
      true
  ; catch(query:search([category(C), name(N)], Repository://Entry), _, fail) ->
      true
  ; atomic(Entry),
    atomic_list_concat([C, PF], '/', Entry),
    eapi:packageversion(PF, N, _)
  ),
  !.


%! ordering:grouped_install_planned(+Core, -D)
%
% The planned merge-family action that satisfies a concrete grouped
% :install BDEPEND/DEPEND. Fails for assumed wrappers (those stay a
% preference, portage-ng#95), for :run/:fetchonly, and when no merge
% of that CN is in the pass-1 proof.
%
% The alias is deliberately narrow, in two ways (whole-tree
% unreachable scan, 602 affected entries):
%
%   - slot-aware: the concrete action must carry one of the slots
%     the group states (`slot(S)` requirements). The index is keyed
%     by category-name, so without this check a `junit:0` group
%     aliased onto a planned junit-4 merge (and a `virtual/libusb:0`
%     group onto the planned `virtual/libusb:1` merge), inventing
%     hard cycles that no ebuild declares — 101 entries;
%   - satisfaction-aware: when the installed system already
%     satisfies the group as stated and no member dep carries a
%     sub-slot (`:=`, req `equal`) pin, the consumer can build
%     against the installed provider (the keep-installed case), so
%     the planned update must not gate it. Traditional emerge
%     orders the glib/gobject-introspection cycle exactly this
%     way. Sub-slot-pinned groups keep the hard alias (the perl
%     case, portage-ng#119), as do groups whose `Deps` are empty
%     (nothing stated to satisfy — the synthetic #119 shape).

grouped_install_planned(Core, D) :-
  Core = G:install,
  ordering:grouped_cn(G, C, N),
  ordering:cn_action_index(Idx),
  get_assoc(cn(C, N, install), Idx, Steps),
  member(D, Steps),
  ordering:grouped_slot_admits(G, D),
  ordering:grouped_alias_needed(G, C, N).


%! ordering:grouped_deps(+G, -Deps)
%
% The package_dependency list carried by a grouped dependency
% literal (empty for the strength-stripped 3-argument shape when it
% carries no list).

ordering:grouped_deps(grouped_package_dependency(no, _, _, Deps), Deps) :- !.
ordering:grouped_deps(grouped_package_dependency(_, _, Deps), Deps) :- !.
ordering:grouped_deps(_, []).


%! ordering:grouped_slot_admits(+G, +D)
%
% D's slot is one of the `slot(S)` requirements stated in G's deps.
% Admits unconditionally when the group states no slot, or when
% D's slot cannot be determined (KB-free synthetic entries).

ordering:grouped_slot_admits(G, D) :-
  ordering:grouped_deps(G, Deps),
  ordering:deps_slots(Deps, Slots),
  ( Slots == []
  -> true
  ;  ordering:entry_slot(D, DSlot)
  -> memberchk(DSlot, Slots)
  ;  true
  ).


%! ordering:deps_slots(+Deps, -Slots)
%
% Slot atoms stated in the group's package_dependency list, in
% declaration order.

deps_slots([], []).
deps_slots([package_dependency(_, _, _, _, _, _, SlotReqs, _)|Deps], Slots) :-
  !,
  ordering:slot_reqs_slots(SlotReqs, Slots, Tail),
  ordering:deps_slots(Deps, Tail).
deps_slots([_|Deps], Slots) :-
  ordering:deps_slots(Deps, Slots).

slot_reqs_slots([], Tail, Tail).
slot_reqs_slots([Req|Reqs], Slots, Tail) :-
  ( Req = slot(S) -> Slots = [S|Rest] ; Slots = Rest ),
  ordering:slot_reqs_slots(Reqs, Rest, Tail).


%! ordering:entry_slot(+Step, -Slot)
%
% Slot of a concrete plan step. Prefers the KB query; falls back
% to the slot_override/2 test hook (KB-free synthetic tests,
% mirroring world_override/1).

:- dynamic slot_override/2.

ordering:entry_slot(Repository://Entry:_Action, Slot) :-
  ( ordering:slot_override(Entry, Slot)
  -> true
  ;  catch(query:search(slot(Slot), Repository://Entry), _, fail)
  ).


%! ordering:group_satisfied_override(+C, +N)
%
% Test hook: synthetic tests assert this to state that the
% installed system satisfies the group for C/N without a VDB
% (mirrors world_override/1).

:- dynamic group_satisfied_override/2.


%! ordering:group_installed_satisfied(+C, +N, +Deps)
%
% The installed system satisfies the group for C/N as stated in
% Deps (or a test override says so).

ordering:group_installed_satisfied(C, N, Deps) :-
  ( ordering:group_satisfied_override(C, N)
  -> true
  ;  ordering:world_fact(satisfies(C, N, Deps),
                         ordering:installed_satisfies(C, N, Deps))
  ).


%! ordering:grouped_alias_needed(+G, +C, +N)
%
% The hard alias onto a planned merge is only needed when the
% installed provider cannot serve the consumer as-is: the group
% states nothing (empty Deps), a member dep is sub-slot pinned
% (`:=`), or the installed system does not satisfy the group.

ordering:grouped_alias_needed(G, C, N) :-
  ordering:grouped_deps(G, Deps),
  ( Deps == []
  -> true
  ;  ( member(package_dependency(_, _, _, _, _, _, SlotReqs, _), Deps),
       memberchk(equal, SlotReqs)
     )
  -> true
  ;  \+ ordering:group_installed_satisfied(C, N, Deps)
  ).


%! ordering:grouped_cn(+G, -C, -N)
%
% Category and name of a regular (non-blocker) grouped dependency
% literal. Assumed grouped deps occur both with the 4-argument
% (strength-carrying) and the 3-argument (strength-stripped, phantom
% path) shape. Weak/strong blocker groups deliberately fail: they name
% a package to be absent, so they must never alias onto that package's
% planned merge (portage-ng#119).

grouped_cn(grouped_package_dependency(no, C, N, _), C, N).
grouped_cn(grouped_package_dependency(C, N, _), C, N).


%! ordering:virtual_merge_step(+H)
%
% H is a merge-family plan step of a `virtual/*` package: the step
% whose grouped :run body literals are hard requirements (virtual
% collapse, see requires/2).

virtual_merge_step(Repository://Entry:Action) :-
  ordering:merge_action(Action),
  ordering:entry_cn(Repository, Entry, C, _),
  C == virtual.


%! ordering:merge_action(?Action)
%
% The merge-family plan actions: those that (re)install an ebuild, as
% opposed to the :run head its consumers depend on.

merge_action(install).
merge_action(update).
merge_action(downgrade).
merge_action(reinstall).


%! ordering:phase_action(+DepAction, -PlanAction)
%
% A concrete plan action that satisfies a dependency phase: an :install
% dep is satisfied by any merge-family action, a :run dep by the :run
% head.

phase_action(install, Action) :-
  ordering:merge_action(Action).
phase_action(run, run).


%! ordering:reference_heads(+H, -Heads)
%
% The proof heads whose dependents count as references to plan step H
% (orderer:merge_order_bias/4): H itself and, for a merge-family step,
% its :run head, because consumers depend on a package's :run action
% rather than on the merge that provides it.

reference_heads(H, [H, Repository://Entry:run]) :-
  H = Repository://Entry:Action,
  ordering:merge_action(Action),
  !.
reference_heads(H, [H]).


% -----------------------------------------------------------------------------
% World: a reading of the VDB
% -----------------------------------------------------------------------------

%! ordering:world_override(+D)
%
% Test hook: unit tests assert world facts here to exercise the laws
% without a knowledge base or VDB (see Source/Test/Unit/synthetictest.pl).

:- dynamic world_override/1.


%! ordering:world(+H, +D)
%
% The installed system, as it stands, already provides requirement D of
% consumer H — the LFS argument: a fact about the present system, cited
% from the VDB. Four shapes:
%
%   - D is a :fetchonly or :download action (grouped or concrete):
%     distfiles are not temporally gated, so a fetch-only requirement
%     is always world-available. Must precede the VDB clauses: those
%     cut on any grouped dep / concrete action and would otherwise
%     demand an installed package for a mere fetch;
%   - H is a dependency group and D its chosen provider (the cycle-bridge
%     case): the group's version and USE constraints — not the provider's
%     identity — are what H actually requires, so the world provides D
%     when an installed package satisfies the group;
%   - D is a dependency group: same test on D's own constraints;
%   - D is a concrete ebuild action: exactly that version is installed.
%
% Blocker groups (strength weak/strong) are never world-provided: their
% satisfaction is an absence, not a presence.

world(_H, D) :-
  ordering:world_override(D),
  !.

world(_H, _Repository://_Entry:fetchonly) :- !.
world(_H, _Repository://_Entry:download) :- !.
world(_H, grouped_package_dependency(_, _, _, _):fetchonly) :- !.
world(_H, grouped_package_dependency(_, _, _):fetchonly) :- !.

world(grouped_package_dependency(no, C, N, Deps):_, _Repository://_Entry:_Action) :-
  !,
  ordering:world_fact(satisfies(C, N, Deps),
                      ordering:installed_satisfies(C, N, Deps)).

world(_H, grouped_package_dependency(no, C, N, Deps):_) :-
  !,
  ordering:world_fact(satisfies(C, N, Deps),
                      ordering:installed_satisfies(C, N, Deps)).

world(_H, Repository://Entry:Action) :-
  memberchk(Action, [install, run]),
  !,
  ordering:world_fact(same_version(Repository, Entry),
                      ordering:installed_same_version(Repository, Entry)).

% A planned :update/:downgrade/:reinstall is a step, so the availability
% law waits for it whenever that is acyclic. This clause is only reached
% when citing the rebuild would close a loop (python/tk/fontconfig): an
% already-installed CN of the same package still bridges the cycle.
world(_H, Repository://Entry:Action) :-
  ordering:merge_action(Action),
  Action \== install,
  !,
  ordering:world_fact(same_cn(Repository, Entry),
                      ordering:installed_same_cn(Repository, Entry)).


%! ordering:installed_satisfies(+C, +N, +Deps)
%
% An installed package satisfies every package_dependency in Deps
% (version operators and USE requirements; delegates to the same
% predicate pass-1 candidate ranking trusts).

installed_satisfies(C, N, []) :-
  !,
  ordering:installed_cn(C, N).
installed_satisfies(_C, _N, Deps) :-
  forall(member(Dep, Deps),
         ( Dep = package_dependency(_, no, _, _, _, _, _, _),
           ranking:installed_pkg_satisfies_dep([], Dep)
         )).


%! ordering:installed_same_version(+Repository, +Entry)
%
% The exact version of Repository://Entry is already installed.

installed_same_version(Repository, Entry) :-
  cache:ordered_entry(Repository, Entry, C, N, Version),
  knowledgebase:vdb_repository(VdbRepo),
  query:search([name(N), category(C), installed(true)], VdbRepo://Installed),
  cache:ordered_entry(VdbRepo, Installed, _, _, Version),
  !.


%! ordering:installed_same_cn(+Repository, +Entry)
%
% Some version of Repository://Entry's category-name is already
% installed. Used only as a cycle bridge for a planned rebuild (the
% acyclic path waits for the rebuild itself).

installed_same_cn(Repository, Entry) :-
  cache:ordered_entry(Repository, Entry, C, N, _),
  ordering:installed_cn(C, N),
  !.


%! ordering:installed_cn(+C, +N)
%
% Some version of category C, name N is installed. Read from the VDB
% directly: the pass-1 ranking memo (ranking:cn_is_installed/2) lives
% only inside ranking:prioritize_deps_keep_all/3 and must not be
% populated from pass 2.

installed_cn(C, N) :-
  knowledgebase:vdb_repository(VdbRepo),
  query:search([name(N), category(C), installed(true)], VdbRepo://_),
  !.
