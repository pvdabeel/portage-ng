# Resolution: Configuration as Proofs

## Configuration as a first proving pass

The prover ([Chapter 8](08-doc-prover.md)) answers a question about the
**final world**: which packages, which versions, which USE flags?  Pass 1
gives that *what* the same status that pass 2 gives the *when*
([Chapter 13](13-doc-planning.md)): **the configuration is a proof**.

`resolver:resolve/9` hands the `resolving` rule set to
`prover:prove/10`.  Every chosen candidate, every USE-conditional branch
taken or skipped, every OR-group arm, and every domain assumption is
justified by a `resolving:rule/2` expansion (or by an explicit prover
cycle break).  There is no separate "resolver algorithm" whose output
must later be trusted — the Proof / Model / Constraints / Triggers
quadruples *are* the justified configuration.

The rules contract and the multi-module picture are in
[Chapter 11](11-doc-rules.md).  This chapter is the Gentoo resolve pass
in depth: how a user target becomes an installed graph, how candidates
and USE are chosen, and what happens when the rules layer must propose
a configuration change.


## How dependency resolution works (end-to-end)

A typical run starts with a user query like `sys-apps/portage`.  The
rules layer turns this into a `target/2` literal and resolves it to
the best eligible candidate — the newest version that is not masked,
has an accepted keyword, and satisfies any slot constraints.  This
resolution produces sub-literals that drive the rest of the proof.

The resolution then branches depending on the action:

- **`:run`** resolves runtime dependencies (RDEPEND).  PDEPEND is
  handled in the same pass through the prover's proof-obligation hook
  (see [Hooks](#hooks)).
- **`:install`** resolves build-time dependencies (DEPEND and BDEPEND)
  and attaches ordering markers (`after/1`) that express which
  packages must be installed before others.

Each dependency atom from the metadata becomes a
`grouped_package_dependency` literal.  The candidate selection
machinery then applies version ranges, slot operators, keyword and
mask policy, and any learned constraints from prior reprove attempts
(see [Chapter 9](09-doc-prover-assumptions.md) and
[Chapter 10](10-doc-version-domains.md)).

USE-conditional dependencies are included only when the condition
holds in the effective USE set for that ebuild and path.  For example,
`ssl? ( dev-libs/openssl )` adds `dev-libs/openssl` to the body only
if `ssl` is enabled; otherwise the branch is skipped entirely.  When a
parent requires particular flags on a child, those requirements
propagate via `build_with_use` in the proof-term context (see
[USE flags in depth](#use-flags-in-depth)).

The prover walks this structure depth-first: each successful rule
expansion adds literals to the proof and updates the model.  When a
rule fails, Prolog backtracks to try an alternative candidate or,
ultimately, records an assumption.


## The `resolving:rule/2` head patterns

The resolve pass uses the shared `rule/2` contract
([Chapter 11](11-doc-rules.md)) with Gentoo heads:

```prolog
resolving:rule(+Head, -Body)
```

Target rules translate a user query into a concrete ebuild.  Action
rules (`:install`, `:run`, `:download`) expand an ebuild into its
dependency obligations.  Dependency rules resolve individual atoms to
candidates.  Validation rules enforce REQUIRED_USE constraints.  The
catch-all `assumed(X)` clause handles domain assumptions when no real
rule applies.

| **Head pattern** | **Purpose** |
| :--- | :--- |
| `target(Q, Arg):run` | Resolve a user target to a candidate ebuild (`--merge`, `--fetchonly`) |
| `target(Q, Arg):fetchonly` | Legacy fetch-only target (CLI `--fetchonly` proves `:run` instead) |
| `target(Q, Arg):uninstall` | Uninstall target resolution |
| `Repo://Ebuild:install` | Build and install an ebuild (DEPEND + BDEPEND) |
| `Repo://Ebuild:run` | Runtime availability (RDEPEND) |
| `Repo://Ebuild:download` | Fetch source archives |
| `Repo://Ebuild:fetchonly` | Legacy fetch-only ebuild action |
| `Repo://Ebuild:depclean` | Remove unneeded package |
| `grouped_package_dependency(...):Action` | Resolve a grouped dependency |
| `package_dependency(...):config` | Configure a single dependency |
| `exactly_one_of_group(...):validate` | Validate REQUIRED_USE `^^` |
| `any_of_group(...):validate` | Validate REQUIRED_USE any-of |
| `at_most_one_of_group(...):validate` | Validate REQUIRED_USE `??` |
| `assumed(X)` | Catch-all for domain assumptions |


## Candidate resolution

When the rules layer encounters a dependency, it must choose a
concrete version of the target package.  This process has three
stages: eligibility filtering, version-ordered selection, and a
fallback chain for when no candidate works.

### Eligibility filtering

Before a candidate version is considered, `candidate:eligible/1`
checks two things:

- **Masking** — is the ebuild masked by the profile or user
  configuration?
- **Keyword acceptance** — does the ebuild have an accepted keyword
  for the current architecture?

(Installed status is a separate check, `candidate:installed/1`, used
by the entry rules' already-installed short-circuit.)

If a candidate fails these checks and no relaxation tier is active
(see [Chapter 9, Progressive Relaxation](09-doc-prover-assumptions.md#progressive-relaxation)),
the entry rule fails and Prolog backtracks to try the next candidate.

### Version-ordered selection

`target:resolve_candidate/2` resolves a query to a specific
`Repository://Ebuild` pair.  Candidates are tried newest-first via
`cache:ordered_entry/5`, so the prover naturally prefers the latest
eligible version.

### Dependency ordering within a group

Before proving the dependencies of a package, `ranking:dep_priority/2`
sorts them so that tightly constrained siblings are proved first.  This
reduces greedy conflicts where an unconstrained sibling selects a version
that later clashes with a tighter constraint:

| **BaseK** | **Constraint type** | **Example** |
| :--- | :--- | :--- |
| 1 | Tight upper bound (range) | `>=1.0 <2.0` |
| 4 | Tilde constraint | `~dev-ruby/railties-8.1.1` |
| 8 | Wildcard constraint | `=dev-python/gast-0.6*` |
| 999 | Unconstrained | `dev-libs/openssl` |

Lower keys are proved first.  Slot specificity is folded into the base
key via `min` — a fully slot-qualified dependency (slot + subslot) gets
key 0 and outranks every tier above.  The effect is that slotted, tilde
and wildcard dependencies lock their `selected_cn` before unconstrained
siblings pick a potentially conflicting version.

### Self-dependencies and cross-slot handling

When a package lists itself as a build dependency (e.g. `antlr-tool:4`
needing `antlr-tool:3.5` to bootstrap), the rules layer distinguishes
**same-slot self-deps** from **cross-slot self-deps**.

Same-slot self-deps (same category, name, and slot as the parent) are
treated as bootstrap dependencies: if the package is already installed,
the dependency is satisfied; otherwise the rule fails so that
backtracking can reach a bootstrap alternative.

Cross-slot self-deps (same category and name but a *different* slot)
are treated as **regular dependencies** and resolved normally.  This
prevents model build failures when the cross-slot version is not yet
installed.

### Fallback chain

When every candidate for a grouped dependency has been tried and none
succeeded, the rules layer activates a fallback chain before giving
up:

- **Wildcard domain learning** — `maybe_learn_wildcard_domain` fires
  when a wildcard dependency (e.g. `=dev-python/gast-0.6*`) fails
  resolution and the parent has already been narrowed by a prior
  parent-narrowing attempt, or the parent is a single-version package
  (where parent narrowing would be futile).  It derives an upper-bound
  `cn_domain` from the wildcard constraint (e.g. `< 0.7`) and learns
  it via `prover:learn/3`, then throws `prover_reprove`.
- **Parent narrowing** — `maybe_learn_parent_narrowing` records that
  the current parent version led to a dead end and throws
  `prover_reprove`, so the prover can retry with a different parent.
- **Domain reprove** — `maybe_request_grouped_dep_reprove` checks
  whether domain or constraint conflicts exist and, if so, triggers a
  reprove with learned constraints.
- **Domain assumption** — as a last resort, the rules layer emits
  `assumed(grouped_package_dependency(...))`.  This records the
  failure as a domain assumption so the proof can still complete.


## Cycles and how portage-ng handles them

Circular dependencies are a fact of life in the Portage tree.  A
language runtime may be packaged with tooling that itself depends on
that runtime, creating a loop.  The prover detects these cycles during
its depth-first proof search: it keeps track of which literals are
currently being proved, and if the same literal appears again while it
is still on the stack, a cycle has been found.

Before breaking a cycle with an assumption, the prover asks the domain
whether the cycle is **benign**.  The hook `heuristic:cycle_benign/2`
inspects the repeating literal and the cycle path.  If the hook
succeeds, the literal is treated as already justified and added to the
model without a cycle-break assumption.  If the hook fails, the prover
records a cycle-break assumption (`assumed(rule(Lit))` in the proof,
`assumed(Lit)` in the model).  This is separate from domain
assumptions introduced by `rule(assumed(X), [])`.

The benign classification is conservative and pattern-based.  For
example, cycles that pass through `:run` (RDEPEND paths) are often
treated as ordering-style cycles rather than hard failures — mirroring
how traditional resolvers tolerate certain cyclic patterns.

After the proof is complete, the ordering pass
([Chapter 13](13-doc-planning.md)) resolves cyclic portions of the
graph by citing the installed world (VDB) where possible, so that the
merge ordering respects the cycle structure.  For more on proof search
and assumptions, see [Chapter 8](08-doc-prover.md) and
[Chapter 9](09-doc-prover-assumptions.md).


## USE flags in depth

USE flags play a central role in dependency resolution.  They determine
which dependency branches exist, which packages are eligible, and
whether REQUIRED_USE constraints are satisfied.

### Effective USE and conditionals

For each ebuild the rules layer computes an **effective USE set** — the
final set of flags that are active for this particular proof path.
USE-conditional dependencies like `ssl? ( dev-libs/openssl )` are
evaluated against this set: if the flag is active, the dependency is
included; otherwise it is skipped.

The key predicate is `use:effective_use_for_entry/3` (with the context
wrapper `use:effective_use_in_context/3`), which computes the full
effective USE set for an ebuild.  Whether a USE-conditional group is
active is decided by the `candidate:eligible(use_conditional(...))`
clauses together with the `use_conditional_group` rules in
`resolving.pl`.

### `build_with_use`

When a parent dependency requires specific USE flags on a child (e.g.
`dev-libs/openssl[threads]`), those requirements travel through the
proof as `build_with_use` context annotations.  They influence how the
child's effective USE set is computed, ensuring that parent
requirements are not silently ignored.

### `REQUIRED_USE`

Gentoo's REQUIRED_USE expressions (e.g. `^^ ( gtk qt5 )` meaning
"exactly one of gtk or qt5") are enforced through dedicated validation
literals.  If the active USE set violates a REQUIRED_USE expression,
the rule fails and the prover backtracks to try another candidate or
records an assumption (see
[Chapter 9, section 9.8](09-doc-prover-assumptions.md#use-model-violation-flow)).

### Priority order

USE flags are resolved in priority order, highest priority first:

1. **`build_with_use`** from the parent's dependency context
2. **User configuration** (`/etc/portage/package.use`)
3. **Profile defaults**
4. **Ebuild IUSE defaults**

The most important consequence is that context wins over profile
defaults: a `build_with_use` requirement from the parent can force or
forbid a flag regardless of what the profile would normally choose.
This is why two proofs for the same package can produce different USE
sets — they arrive through different dependency paths with different
context annotations.

### Conflicts and backtracking

When USE-derived constraints conflict — for example, REQUIRED_USE
fails, a conditional branch does not apply as expected, or an
eligibility check fails — the relevant rule fails.  The prover then
backtracks: it tries another candidate version, another slot, or
another branch of the search tree.  If no alternative succeeds, the
candidate layer records a domain assumption, often tagged with a
suggestion for which `package.use` change would resolve the conflict
(see [Assumptions as proposals](#assumptions-as-proposals)).

## Choice groups

Gentoo's PMS defines three choice-group operators that constrain how
many members of a set may be active at the same time.  The rules layer
maps each operator to a dedicated validation literal that the prover
must satisfy as part of the proof:

| **Operator** | **Rule clause** | **Semantics** |
| :--- | :--- | :--- |
| any-of ( a b c ) | `any_of_group(Deps):validate` | At least one must be satisfied |
| `^^ ( a b c )` | `exactly_one_of_group(Deps):validate` | Exactly one must be satisfied |
| `?? ( a b c )` | `at_most_one_of_group(Deps):validate` | At most one may be satisfied |

If the validation literal fails (e.g. two members of an
`exactly_one_of` group are both active), the prover backtracks to try
a different USE configuration or candidate version.

When a disjunctive dependency group (`||`, `^^`, `exactly_one_of`) must
*select* an alternative, the candidate layer ranks the members with
`ranking:prioritize_deps_keep_all/3` and commits to the first arm that
passes config checks (see [Any-of (`||`) arm selection](#any-of-arm-selection)
below).  Profile-forced and installed preferences still dominate via
`is_preferred_dep/2`, the leading signal of the `preference` criterion;
USE_EXPAND target digits (`ranking:use_expand_target_key/2`) are its
last signal and also feed `use_expand` — `llvm_slot_20` → `[20]`,
`python_single_target_python3_13` → `[3,13]`, and so on.


## Any-of (`||`) arm selection {#any-of-arm-selection}

Gentoo ebuilds often write `|| ( arm1 arm2 … )`.  The PMS only requires
that *at least one* arm is satisfiable; it does not say which arm to
pick.  Wrong order locks the prover onto a suboptimal (or incompatible)
branch — for example cabal’s
`|| ( ( >=text-1.2.3 <text-1.3 ) ( >=text-2 <text-2.2 ) )` must prefer
the text-2.x arm when that is the newest tree candidate
(portage-ng#112).

### Portage vs portage-ng entry points

| | **Portage** | **portage-ng** |
| :--- | :--- | :--- |
| Mechanism | `dep_zapdeps` ordered `choice_bins` + intra-bin upgrade promotion (`lib/portage/dep/dep_check.py`) | `candidate:resolve(choice_group…)` → `ranking:prioritize_deps_keep_all/3` then first `any_of_config_dep_ok` |
| Structure | Nine preference bins (lists) | One declared criterion list (`ranking:choice_criteria/1`), compared lexicographically by standard order of terms, original index last |
| Graph reuse | Digraph `all_in_graph` | `selected_cn` snapshot (`snap_all`) |

Ranking *is* the preference policy: after the cut commits, later arms
are not tried unless the proof backtracks for another reason.

### Preference criteria (most significant first)

Declared as `ranking:choice_criteria/1`; each criterion's value comes
from `ranking:criterion_value/5` and `prioritize_deps_keep_all/3`
compares arms criterion by criterion (`ranking:compare_preference/3`)
using the standard order of terms — a *larger* value is preferred, and
the original ebuild index breaks remaining ties (left-to-right).  There
is no weighted sum and no integer packing: booleans are `no @< yes`,
counts are integers, versions are `version/7` terms (which compare as
PMS versions), slots and USE_EXPAND targets are digit-group lists
(`'3.10'` → `[3,10]` `@>` `[3,3]`), and `none` sorts below everything
else.  Adding a preference means adding a criterion to the list, not
choosing a magnitude.

| **Criterion** | **Value** | **Intent** | **Emerge analogue** |
| :--- | :--- | :--- | :--- |
| `license_ok` | `yes`/`no` | Prefer license-acceptable arms | Availability / license gate |
| `use_sat` | `yes`/`no` | Prefer arms needing no USE flip on the arm’s best candidate | `preferred_*` vs `unsat_use_*` |
| `use_unmasked` | `yes`/`no` | Among USE-unsat arms, prefer flips that do not fight use.mask / use.force | `all_use_unmasked` (masked → `other`) |
| `preference` | `pref/6` | Installed / profile-preferred, `--favour` / `--avoid`, not self-CN, no forced upgrade, `-bootstrap`, USE_EXPAND target — in that order, as the six arguments of one compound | `preferred_installed` + favour |
| `snap_all` | `yes`/`no` | Prefer arms whose non-`virtual/` CNs are already in the proof snapshot | `all_in_graph` |
| `slot` | digit list / `none` | Prefer higher explicit package slot (`pkg:N`) — only active when *all* arms target the same (C,N) | `want_update` / higher-slot promotion |
| `no_downgrade` | `yes`/`no` | Demote arms whose newest admitted version is below installed or snap-selected | `downgrade_probe` → `other` |
| `installed` | count | Prefer arms that reuse more installed CNs | `other_installed` / `_some` / `_any_slot` |
| `overlap` | count | Prefer arms that appear in several sibling `\|\|` groups | Soft stand-in for minimize-slots pressure |
| `version` | `version/7` / `version_none` | Prefer the arm that admits the newest tree version — only active when *all* arms target the same (C,N) | Intra-bin `has_upgrade and not has_downgrade` |
| `use_expand` | integer | Prefer USE_EXPAND profile alignment (+1 per matching target, −1 per mismatch) | Profile target preference |
| ebuild index | integer, ascending | Stable left-to-right when all else equal | Ebuild order fallback |

Worked examples:

- `|| ( foo[a] foo[b] )` with `a` already effective → `use_sat` picks `foo[a]`.
- Cabal text ranges (above) → `version` picks the text-2.x arm.
- `|| ( sys-devel/llvm:18 sys-devel/llvm:20 )` → `slot` prefers `:20`.
- An arm whose packages are already in `selected_cn` beats a fresh CN → `snap_all`.

The same pattern orders the *proof* of a package's dependencies:
`ranking:dep_priority/2` sorts sibling deps by their position in the
declared `ranking:tightness_classes/1` list (sub-slot pin, tight upper
bound, tilde, slot pin, wildcard, any-same-slot, any-different-slot,
unconstrained, …), taking the first class that applies, so the tightest
constraint locks `selected_cn` before a looser sibling can pick a
conflicting version.

`version` and `slot` are gated to same-CN groups because
comparing newest tree versions — or highest slots — of *different*
packages is meaningless and overrides ebuild order: `virtual/mta`
would pick `notqmail` (a `-9999` live ebuild inflates its score) over
the intended `nullmailer`, and `virtual/jdk` would pick source
`dev-java/openjdk` over `openjdk-bin` (portage-ng#115,
portage-ng#116).  Ungated slot-ranking likewise flipped ruby-single
choices: `( ruby:3.3 rubygems[ruby33] )` — the profile default, listed
first — lost to `( ruby:4.0 rubygems[ruby40] )` because 4.0 > 3.3,
scheduling the `~arch` ruby:4.0 slot plus a `ruby_targets_ruby40` USE
toggle that emerge never takes (webkit-gtk build cluster, Aug-2026
tinderbox run).  Emerge never version- or slot-ranks across CPs inside
a choice; it falls back to ebuild order there.

`virtual/` atoms are skipped for `snap_all`, `installed`, and
`no_downgrade` (Portage’s zero-cost treatment of virtuals in those
checks).  Scores are computed once per arm per
`prioritize_deps_keep_all/3` call, with a short-lived per-call cache for
installed / reference-version lookups.  Ranking must not walk the
ProofAVL; it only sees the proof-context list and memo snapshots
(see also [Chapter 26](26-doc-performance.md)).

### What we deliberately do not implement

These Portage mechanisms are **design omissions**, not open bugs.  The
inductive prover and ordering pass already provide the effects they target.

**Overlapping-`||` DNF (`_overlap_dnf`) and `minimize_slots` /
`new_slot_count`.**
Portage merges overlapping `||` groups that share a CP into DNF, then
sorts bins by ascending new-slot count.  portage-ng does not rewrite
the dep tree into DNF: expansion is exponential in overlapping width and
does not belong on the per-`choice_group` hot path.  The prover already
commits `selected_cn` / learned `cn_domain` across the proof; later `||`
sites reuse those choices via `snap_all` and constraint guards — the same
“prefer packages already chosen” effect without a cross-product.
`overlap`, `installed`, and `snap_all` cover the common “don’t pull a
second redundant package” pressure.  Remaining edge cases (two
overlapping `||`s neither yet selected) are rare relative to cost; if
tinderbox surfaces one, prefer a targeted heuristic over full DNF.

**Virtual expand (`_expand_new_virtuals`).**
Portage expands new-style virtuals into a newest-first `||` of providers
before zapdeps.  portage-ng already resolves virtuals through the
virtual-provider path and `candidates_prefer_proven_providers/5`, and
skips `virtual/` in the scores above.  A second expand-into-`||` pass
would duplicate that work and fight proven-provider reuse.

**Circular-dep demotion inside `||`.**
Portage demotes arms that close a known cycle with the parent (or
`--onlydeps` parent CP) into `other`.  portage-ng handles cycles in the
prover and the ordering pass (cycle-break assumptions, world citations,
`unreachable` assumptions) — see [Chapter 8](08-doc-prover.md),
[Chapter 9](09-doc-prover-assumptions.md), and
[Chapter 13](13-doc-planning.md).  Demoting at ranking time would
second-guess cycle-break polarity and needs a parent circular map that
the proof-context list does not carry.

**Intra-choice `cp_map` slot consistency (Portage bug 600346).**
Portage keeps a per-choice CP→slot map so several atoms in one choice
stay slot-consistent.  portage-ng arms are usually a single atom or a
same-CN `all_of_group` of version bounds; cross-CP multi-atom arms that
need `cp_map` are uncommon.  Slot consistency is enforced later by
`selected_cn`, slot constraints, and constraint guards.

### Validation

- PLUnit: `ranking_any_of_version_branch`, `ranking_any_of_preference_keys`
  in `Source/Test/Unit/rankingtest.pl`.
- Overlay suite (`||` / USE / slot cases) and tinderbox-ng compare on
  USE-dep `||` and llvm/gcc/python slot packages.


## Slot operators

Dependency atoms can carry a slot operator that tells the rules layer
how to handle multi-slot packages.  A package like `dev-lang/python`
may offer several slots (e.g. `3.11`, `3.12`), and the slot operator
determines which slots are acceptable and whether a sub-slot change
should trigger a rebuild of the dependent package.

| **Operator** | **Meaning** | **Context effect** |
| :--- | :--- | :--- |
| `:SLOT` | Depend on a specific slot | Filters candidates to that slot |
| `:*` | Any slot is acceptable | No slot constraint applied |
| `:=` | Sub-slot rebuild trigger | Records the selected sub-slot; a change triggers rebuild |
| `:SLOT=` | Specific slot + rebuild | Combines slot filter with rebuild tracking |


## Blockers

A blocker dependency says that two packages cannot coexist.  Gentoo
distinguishes two strengths:

| **Type** | **Syntax** | **Behaviour** |
| :--- | :--- | :--- |
| Soft blocker (PMS: *weak*) | `!cat/pkg` | The blocked package should not be present; never fails the proof — walked past, recorded, and reported as an actionable assumption when effective |
| Hard blocker (PMS: *strong*) | `!!cat/pkg` | The blocked package must not be present; the constraint guard fires immediately |

Plan output says *soft* / *hard*; the rules name the atoms `weak` /
`strong` after the PMS syntax.  A soft blocker is the negative
counterpart of an ordering preference — see the terminology box in
Chapter 13 ("Dependency types and ordering strength").

Internally, blockers produce `blocked_cn` constraint terms.  These are
checked against `selected_cn` constraints by
`selected_cn_not_blocked_or_reprove`: if the blocked package has
already been selected elsewhere in the proof, the guard triggers a
reprove so the prover can learn to avoid the conflicting combination
(see [Chapter 9, section 9.10](09-doc-prover-assumptions.md#constraint-guards-and-reprove-integration)).


## Hooks

PDEPEND (post-dependencies) represent packages that should be present
at runtime but are not required at build time.  Unlike DEPEND and
RDEPEND, they do not block the build — they are installed afterwards.

In portage-ng, PDEPEND is handled in a single pass inside the prover
via the `heuristic:proof_obligation/4` hook.  Whenever a literal is
successfully proved, the hook checks whether the corresponding ebuild
has PDEPEND entries.  If it does, those entries are injected as
additional proof obligations on the spot.  This avoids a separate
PDEPEND resolution pass and ensures that post-dependencies are part of
the same proof and plan.


## Assumptions as proposals

When strict resolution cannot satisfy every dependency, the rules
layer records a **domain assumption** rather than giving up.  From a
user perspective, an assumption is not a dead end — it is a
**proposal** for a configuration change.

The literal's proof-term context is annotated with **suggestion** tags
that spell out exactly what to change.  Common suggestions include:

- `suggestion(unmask, ...)` — unmask a package
- `suggestion(accept_keyword, ...)` — accept an unstable keyword
- `suggestion(use_change, ..., Changes)` — adjust USE flags

The printer collects these tags and shows them next to the assumption,
so you can see which `/etc/portage` file to edit and what to put in
it.  The plan is still constructed as if the change had already been
applied: the merge list is coherent under the stated proposal, and the
output tells you which configuration changes would make it real.

For the full story on assumptions and constraint learning, see
[Chapter 9](09-doc-prover-assumptions.md).


## Rules submodules

The `resolving` entry point is not a single monolithic file.  It is
split across focused submodules under
`Source/Domain/Gentoo/Rules/Resolving/`, each handling a distinct
concern:

| **Module** | **File** | **Purpose** |
| :--- | :--- | :--- |
| `acceptance` | `acceptance.pl` | Keyword, mask, and license acceptance; keyword-aware candidate enumeration |
| `candidate` | `candidate.pl` | Grouped-dep resolution pipeline, blocker matching, eligibility protocol |
| `cnselect` | `cnselect.pl` | CN-consistency: selected_cn reuse, CN-domain reject map, learned-domain narrowing |
| `dependency` | `dependency.pl` | Self-entry injection, USE-requirement collection, slot/BWU proof-context propagation |
| `featureterm` | `featureterm.pl` | Proof-context list helpers (`after/1`, strip `build_with_use`, etc.) |
| `heuristic` | `heuristic.pl` | Prover hooks: constraint guard, cycle classification, PDEPEND obligations, reprove state |
| `memo` | `memo.pl` | Thread-local caching declarations, `clear_caches/0` |
| `ranking` | `ranking.pl` | Dependency ordering (`dep_priority/2`), choice-group ranking, BWU memo seeding |
| `slotmeta` | `slotmeta.pl` | Slot canonicalization, restriction merging, constraint queries |
| `target` | `target.pl` | Target resolution, update/downgrade transactions, depclean, `--exclude` helpers |
| `use` | `use.pl` | USE evaluation, conditionals, `build_with_use`, newuse, REQUIRED_USE, BWU conflicts |


## Policy cards (declarative view)

This chapter walks **how** resolution proceeds. For a newbie-oriented
view of **what** Gentoo policy requires — PMS meaning, literals,
owning modules, and short invariants — start here:

- [Policy cards hub](Policy/README.md)
- [Policy by example](Policy/examples.md) — curated overlay curriculum
- [One-page map](Policy/map.md) — `rule/2` head → schema → test → card

Prefer those cards when onboarding or reviewing a rules change; keep
this chapter for the end-to-end narrative and `||` ranking detail.


## Further reading

- [Chapter 11: Rules and Domain Logic](11-doc-rules.md) — the `rule/2`
  contract and how rule modules plug into the prover
- [Chapter 8: The Prover](08-doc-prover.md) — how the prover calls
  `rule/2` and builds the proof
- [Chapter 9: Assumptions](09-doc-prover-assumptions.md) — the
  fallback chain, reprove mechanism, and progressive relaxation
- [Chapter 10: Version Domains](10-doc-version-domains.md) — how
  version constraints feed into candidate selection
- [Chapter 13: Ordering — Plans as Proofs](13-doc-planning.md) — pass 2
- [Policy cards](Policy/README.md) — declarative Gentoo policy surface
