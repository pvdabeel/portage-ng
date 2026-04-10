# Rules and Domain Logic

## How we resolve dependencies

The prover works with abstract literals and rules.  It does not know
what "install" means for Gentoo — it only knows how to find a matching
rule and prove its body.  The **rules layer** is the bridge between
that abstract proof search and the concrete world of ebuilds, USE
flags, and version constraints.

When the prover encounters a literal like
`portage://'sys-apps/portage-3.0.77-r3':install`, it is the rules
layer that answers questions such as:

- What are this ebuild's dependency lists (DEPEND, BDEPEND, RDEPEND)?
- Which USE flags are active for this particular path through the
  dependency graph?
- Which repository entries are valid candidates, given version, slot,
  and keyword constraints?
- Should a USE-conditional dependency like `ssl? ( dev-libs/openssl )`
  be included or skipped?
- Are there blockers, REQUIRED_USE constraints, or ordering
  requirements?

All of these decisions are encoded as rule bodies and proof-term
context annotations (`?{...}` lists).  The sections below follow one
resolution from user target to installed graph, then cover cycles, USE
semantics, and what happens when the rules layer must record an
assumption.


## How dependency resolution works (end-to-end)

A typical run starts with a user query like `sys-apps/portage`.  The
rules layer turns this into a `target/2` literal and resolves it to
the best eligible candidate — the newest version that is not masked,
has an accepted keyword, and satisfies any slot constraints.  This
resolution produces sub-literals that drive the rest of the proof.

The resolution then branches depending on the action:

- **`:run`** resolves runtime dependencies (RDEPEND).  PDEPEND is
  handled in the same pass through the prover's literal hook (see
  [Hooks](#hooks)).
- **`:install`** resolves build-time dependencies (DEPEND and BDEPEND)
  and attaches ordering constraints (`after/1`) that express which
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


## The `rule/2` interface

The single entry point between the prover and the domain logic is:

```prolog
rules:rule(+Head, -Body)
```

The prover passes a literal as `Head`, and the rules layer returns a
list of sub-literals `Body` that must be proved in order to justify
it.  The prover never interprets what the literals mean — all
Gentoo-specific knowledge is encapsulated inside the rule clauses.

The table below lists the main head patterns.  Target rules translate
a user query into a concrete ebuild.  Action rules (`:install`,
`:run`, `:download`) expand an ebuild into its dependency obligations.
Dependency rules resolve individual atoms to candidates.  Validation
rules enforce REQUIRED_USE constraints.  The catch-all `assumed(X)`
clause handles domain assumptions when no real rule applies.

| **Head pattern** | **Purpose** |
| :--- | :--- |
| `target(Q, Arg):run` | Resolve a user target to a candidate ebuild |
| `target(Q, Arg):fetchonly` | Fetch-only target resolution |
| `target(Q, Arg):uninstall` | Uninstall target resolution |
| `Repo://Ebuild:install` | Build and install an ebuild (DEPEND + BDEPEND) |
| `Repo://Ebuild:run` | Runtime availability (RDEPEND) |
| `Repo://Ebuild:download` | Fetch source archives |
| `Repo://Ebuild:fetchonly` | Fetch only |
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
checks three things:

- **Masking** — is the ebuild masked by the profile or user
  configuration?
- **Keyword acceptance** — does the ebuild have an accepted keyword
  for the current architecture?
- **Installed status** — is the package already installed (checked
  against the VDB)?

If a candidate fails these checks and no relaxation tier is active
(see [Chapter 9, Progressive Relaxation](09-doc-prover-assumptions.md#progressive-relaxation)),
the entry rule fails and Prolog backtracks to try the next candidate.

### Version-ordered selection

`candidate:resolve/2` resolves a query to a specific
`Repository://Ebuild` pair.  Candidates are tried newest-first via
`cache:ordered_entry/5`, so the prover naturally prefers the latest
eligible version.

### Fallback chain

When every candidate for a grouped dependency has been tried and none
succeeded, the rules layer activates a fallback chain before giving
up:

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

After the proof is complete, cyclic portions of the `:run` side of the
graph are grouped into **strongly connected components (SCCs)** by the
scheduler, so that the merge ordering respects the cycle structure.
For more on proof search and assumptions, see
[Chapter 8](08-doc-prover.md) and
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

The key predicates are `use:effective_use/3` (computes the full
effective USE set for an ebuild) and `use:evaluate_conditional/3`
(evaluates a single flag condition).

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
| Weak blocker | `!cat/pkg` | The blocked package should not be present; resolved at plan time |
| Strong blocker | `!!cat/pkg` | The blocked package must not be present; the constraint guard fires immediately |

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
via the `rules:literal_hook/4` hook.  Whenever a literal is
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

The rules layer is not a single monolithic file.  It is split across
several focused submodules under `Source/Domain/Gentoo/Rules/`, each
handling a distinct concern:

| **Module** | **File** | **Purpose** |
| :--- | :--- | :--- |
| `memo` | `memo.pl` | Thread-local caches for selected candidates and violations |
| `use` | `use.pl` | USE flag evaluation and REQUIRED_USE checking |
| `candidate` | `candidate.pl` | Candidate selection, eligibility, and reprove triggers |
| `heuristic` | `heuristic.pl` | Reprove state, retry budgets, and cycle benignity checks |
| `dependency` | `dependency.pl` | Dependency model construction and context threading |
| `target` | `target.pl` | Target resolution (translating a query to a candidate) |
| `featureterm` | `featureterm.pl` | Context stripping for memoisation keys |


## Further reading

- [Chapter 8: The Prover](08-doc-prover.md) — how the prover calls
  `rule/2` and builds the proof
- [Chapter 9: Assumptions](09-doc-prover-assumptions.md) — the
  fallback chain, reprove mechanism, and progressive relaxation
- [Chapter 10: Version Domains](10-doc-version-domains.md) — how
  version constraints feed into candidate selection
