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
(`prover:prove_once(ordering, ...)`).  Two layers in one module:

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
from the generic components:classes/3 (Source/Logic/components.pl). See
Documentation/Handbook/13-doc-planning.md (the planning laws, the Gentoo
bindings and the two ordering strategies).
*/

:- module(ordering, []).

:- use_module(library(assoc)).

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
% cycle-stack pops (setup_call_cleanup cleanups around each rule body)
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
%   - grouped BDEPEND/DEPEND alias: a concrete grouped :install is often
%     *not* the plan step (keep-installed groups have an empty body, so
%     they are a wave-1 leaf). When a merge-family action for the same
%     CN *is* planned, the consumer must wait for that rebuild — otherwise
%     it co-waves with the provider and configures against the stale
%     install (perl 5.42→5.44 / Syntax-Keyword-Try before
%     XS-Parse-Keyword). Assumed grouped deps stay a preference
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

requires(H, D) :-
  ordering:step_body(H, Body),
  member(Literal, Body),
  prover:canon_literal(Literal, Core, _),
  \+ constraint:is_constraint(Core),
  Core \== H,
  \+ ordering:runtime_dep(Core),
  ordering:step(Core),
  D = Core.

requires(H, D) :-
  ordering:step_body(H, Body),
  member(Literal, Body),
  prover:canon_literal(Literal, Core, _),
  ordering:grouped_install_planned(Core, D),
  D \== H.

requires(H, D) :-
  ordering:virtual_merge_step(H),
  ordering:step_body(H, Body),
  member(Literal, Body),
  prover:canon_literal(Literal, Core, _),
  Core = grouped_package_dependency(no, _, _, _):run,
  ordering:step(Core),
  D = Core.


%! ordering:prefers(+H, -D)
%
% Preference: H would like D placed earlier, without insisting. The raw
% preferences come from ordering:prefers0/2; which of them are handed to
% the projection depends on the ordering strategy (`--optimize`):
%
%   - parallelism (default): a preference whose provider depends back on
%     its consumer — H and D lie in the same mutual-reachability class
%     over requires ∪ prefers0 — is void. Inside a cycle the runtime
%     order is free (Portage treats runtime cycles as freely orderable),
%     so the cycle's members merge side by side instead of one per step;
%     preferences between classes are always kept. The accepted edge set
%     is acyclic by construction (an edge on a cycle is, by definition,
%     inside a class), so the projection never has to arbitrate;
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
% waits for, whether it insists (requires/2) or merely wishes (prefers0/2).

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
%     when another proof path planned that package for the same phase.

prefers0(H, D) :-
  ordering:step_body(H, Body),
  member(Literal, Body),
  prover:canon_literal(Literal, Core, _),
  ( Core = constraint(order_after(Anchor0):_) ->
      prover:canon_literal(Anchor0, D, _)
  ; Core = constraint(schedule_after(Anchor0):_) ->
      prover:canon_literal(Anchor0, D, _)
  ; \+ constraint:is_constraint(Core),
    ordering:runtime_dep(Core),
    D = Core
  ),
  D \== H,
  ordering:step(D).

% PDEPEND completion (portage-ng#18/#19).
prefers0(H, T) :-
  ordering:step_body(H, Body),
  member(Literal, Body),
  prover:canon_literal(Literal, Core, _),
  ordering:dep_anchor_key(Core, Key),
  ordering:pdepend_anchor_index(Idx),
  get_assoc(Key, Idx, Targets),
  member(T, Targets),
  T \== H.

% Configure closure (portage-ng#21).
prefers0(Repository://Entry:install, D) :-
  ordering:step(Repository://Entry:run),
  ordering:step_body(Repository://Entry:run, RunBody),
  member(Literal, RunBody),
  prover:canon_literal(Literal, Core, _),
  ordering:runtime_dep(Core),
  ordering:step(Core),
  D = Core.

% Assumed-dep alias (portage-ng#95).
prefers0(H, D) :-
  ordering:step_body(H, Body),
  member(Literal, Body),
  prover:canon_literal(Literal, assumed(Inner), _),
  prover:canon_literal(Inner, G:Action, _),
  ordering:grouped_cn(G, C, N),
  ordering:cn_action_index(Idx),
  ordering:phase_action(Action, A),
  get_assoc(cn(C-N)-A, Idx, Steps),
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
%     class over ordering:edge/2, so prefers/2 can tell a preference on a
%     cycle from one between cycles (same_component/2). The classes are
%     computed by the generic components:classes/3 (Source/Logic); this
%     module only names the nodes and the edges;
%   - the PDEPEND anchor index maps a provider identity to the steps that
%     carry a `constraint(order_after(Provider))` marker — i.e. the
%     provider's PDEPEND group. Consumers of the provider look themselves
%     up here (via dep_anchor_key/2) to prefer the post-install group
%     earlier (portage-ng#18/#19);
%   - the concrete-action index maps cn(Category-Name)-Action to the
%     concrete plan steps for that package, so grouped :install deps
%     (hard requires) and assumed grouped deps (portage-ng#95 preference)
%     can alias to the planned provider.

%! ordering:prepare_pass
%
% Reset the per-pass caches. Called by orderer:with_ordering_pass/2.

prepare_pass :-
  nb_setval(portage_ordering_component_idx, none),
  nb_setval(portage_ordering_pdepend_idx, none),
  nb_setval(portage_ordering_cnaction_idx, none).


%! ordering:component_index(-Idx)
%
% The component index for the current pass, built on first use: plan
% step -> class identifier (components:classes/3 over all pass-1 proof
% heads and ordering:edge/2).

component_index(Idx) :-
  ( nb_current(portage_ordering_component_idx, Idx0), Idx0 \== none ->
      Idx = Idx0
  ; ordering:build_component_index(Idx),
    nb_setval(portage_ordering_component_idx, Idx)
  ).

build_component_index(Idx) :-
  ordering:proof(Proof),
  findall(H,
          ( assoc:gen_assoc(Key, Proof, _),
            ( Key = rule(H) -> true ; Key = assumed(rule(H)) )
          ),
          Heads0),
  sort(Heads0, Heads),
  components:classes(Heads, ordering:edge, Idx).


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
  findall(Key-T,
          ( assoc:gen_assoc(ProofKey, Proof, dep(_, Body)?_),
            ( ProofKey = rule(T) -> true ; ProofKey = assumed(rule(T)) ),
            member(Literal, Body),
            prover:canon_literal(Literal, constraint(order_after(Anchor0):_), _),
            prover:canon_literal(Anchor0, ACore, _),
            ordering:anchor_key(ACore, Key)
          ),
          Pairs0),
  sort(Pairs0, Pairs),
  empty_assoc(I0),
  foldl(ordering:anchor_index_put, Pairs, I0, Idx).

anchor_index_put(Key-T, In, Out) :-
  ( get_assoc(Key, In, Ts) -> true ; Ts = [] ),
  put_assoc(Key, In, [T|Ts], Out).


%! ordering:dep_anchor_key(+Core, -Key)
%
% The provider-identity key a dependency literal resolves to: concrete
% actions key on their entry, dependency groups on category-name.
% Blocker groups carry no provider identity.

dep_anchor_key(Repository://Entry:_, entry(Repository://Entry)) :- !.
dep_anchor_key(grouped_package_dependency(no, C, N, _):_, cn(C-N)) :- !.
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
% cn(Category-Name)-Action -> concrete plan steps of that package.

cn_action_index(Idx) :-
  ( nb_current(portage_ordering_cnaction_idx, Idx0), Idx0 \== none ->
      Idx = Idx0
  ; ordering:build_cn_action_index(Idx),
    nb_setval(portage_ordering_cnaction_idx, Idx)
  ).

build_cn_action_index(Idx) :-
  ordering:proof(Proof),
  findall((cn(C-N)-Action)-Head,
          ( assoc:gen_assoc(ProofKey, Proof, _),
            ( ProofKey = rule(Head) -> true ; ProofKey = assumed(rule(Head)) ),
            Head = Repository://Entry:Action,
            ordering:entry_cn(Repository, Entry, C, N)
          ),
          Pairs0),
  sort(Pairs0, Pairs),
  empty_assoc(I0),
  foldl(ordering:anchor_index_put, Pairs, I0, Idx).


%! ordering:entry_cn(+Repository, +Entry, -C, -N)
%
% Category and name of a repository entry. Prefers the KB query; falls
% back to parsing `Category/PF` so the concrete-action index works in
% KB-free synthetic tests (`portage://'fake/sg-1'`).

entry_cn(Repository, Entry, C, N) :-
  catch(query:search([category(C), name(N)], Repository://Entry), _, fail),
  !.
entry_cn(_Repository, Entry, C, N) :-
  atomic(Entry),
  atomic_list_concat([C, PF], '/', Entry),
  eapi:packageversion(PF, N, _).


%! ordering:grouped_install_planned(+Core, -D)
%
% The planned merge-family action that satisfies a concrete grouped
% :install BDEPEND/DEPEND. Fails for assumed wrappers (those stay a
% preference, portage-ng#95), for :run/:fetchonly, and when no merge
% of that CN is in the pass-1 proof.

grouped_install_planned(Core, D) :-
  Core = G:install,
  ordering:grouped_cn(G, C, N),
  ordering:cn_action_index(Idx),
  ordering:phase_action(install, A),
  get_assoc(cn(C-N)-A, Idx, Steps),
  member(D, Steps),
  ordering:step(D).


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
  catch(ordering:installed_satisfies(C, N, Deps), _, fail).

world(_H, grouped_package_dependency(no, C, N, Deps):_) :-
  !,
  catch(ordering:installed_satisfies(C, N, Deps), _, fail).

world(_H, Repository://Entry:Action) :-
  memberchk(Action, [install, run]),
  !,
  catch(ordering:installed_same_version(Repository, Entry), _, fail).

% A planned :update/:downgrade/:reinstall is a step, so the availability
% law waits for it whenever that is acyclic. This clause is only reached
% when citing the rebuild would close a loop (python/tk/fontconfig): an
% already-installed CN of the same package still bridges the cycle.
world(_H, Repository://Entry:Action) :-
  ordering:merge_action(Action),
  Action \== install,
  !,
  catch(ordering:installed_same_cn(Repository, Entry), _, fail).


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
