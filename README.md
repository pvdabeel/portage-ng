Automate building and maintaining custom operating systems using declarative reasoning.

# portage-ng

A declarative reasoning engine for software configuration, applied to Gentoo Linux.

## What is portage-ng?

portage-ng uses **inductive proof search** to reason about package dependencies.
Every build plan it produces is a formal proof -- not a heuristic guess. It fully
implements **PMS 9 / EAPI 9** (USE-conditional dependencies, slot operators,
sub-slots, blockers, PDEPEND) and is written in SWI-Prolog. It reads the same
Portage tree, VDB, profiles, and `/etc/portage` configuration as traditional
Portage.

## The reasoning approach

**Inductive proof search.** Given a target package, the prover constructs a
proof and a model that together guarantee every dependency is satisfied. Unlike
Portage, portage-ng always produces a plan -- even for targets where Portage
gives up. When strict proving fails, it makes explicit assumptions (USE flag
changes, keyword acceptance, unmasking) and produces a proven plan under
assumptions, with actionable suggestions for the user to approve, already
applied within the build plan.

**Prescient proving.** When a literal is re-encountered with a changed context
(e.g. new USE requirements from a different dependency path), the prover merges
contexts via feature-unification and re-expands only the difference. This
shortens proofs because knowledge about requirements imposed later is
incorporated into earlier decisions -- the prover is prescient about constraints
that would otherwise require backtracking.

**Multiple stable models.** Building upon the backtracking functionality built
in to Prolog, the prover can produce different solutions (stable models) of the
USE flag configuration space, taking into account constraints such as
`build_with_use` and `required_use` as defined in PMS. Different valid
configurations of the same target can be explored and compared.

**Constraint learning.** Version domains are narrowed incrementally across
reprove retries (inspired by Zeller's feature logic). Learned constraints
persist -- no full restart of the prover needed. Unlike traditional
backtracking, the reprove mechanism is iterative refinement: when a domain
conflict is detected, the prover records the conflict as a no-good, learns a
narrowed domain, and restarts the complete proof with this additional knowledge.
This is closer to CDCL-style learning than to Prolog backtracking.

**Progressive relaxation.** The pipeline tries strict mode first, then
progressively relaxes (keyword acceptance, blockers, unmask). Each tier is a
weaker proof that still carries formal guarantees. Every assumption is tracked
and reported.

**Wave planning with optimal parallelism.** The proven dependency graph is
scheduled using Kahn's algorithm (acyclic portion) with parallelism calculated
from the start -- the build plan shows which packages can be built concurrently.
Cyclic remainders are handled via Kosaraju Strongly Connected Component (SCC)
decomposition, matching PMS semantics.

## What this enables

**Always produces a plan.** portage-ng succeeds 100% of the time, including
targets where Portage fails. Assumptions are explicit and actionable.

**Measured correctness.** Correctness is measured against Portage for every
ebuild in the tree, using an identical Portage tree, VDB, and `/etc/portage`
configuration. Detailed comparison reports are available under
[`Reports/`](Reports/).

**Performance.** The entire Portage tree is loaded in-memory as Prolog facts
with sub-second queries. A full prove of all 32,000 ebuilds in the tree takes
less than a minute on a recent multi-core machine.<sup>1</sup> Parallel proving
with `--jobs` enables plan "variants" showing build plan differences when
enabling or disabling USE flags.

**Actionable plans.** portage-ng builds plans incorporating suggested actions
like `package.accept_keywords`, `package.unmask`, or `package.use` --
suggestions are already applied within the plan for the user to review.

**Automatic bug report drafts.** When the prover detects unsatisfiable
dependencies, it generates structured Gentoo Bugzilla bug report drafts with
a summary, affected package, unsatisfiable constraints, observed state, and a
suggested fix.

**Optimal parallelism.** Build plans include concurrent execution groups from
the start.

**Best-of-breed CLI.** Compatible flags from emerge, paludis, and pkgcore.

<sup>1</sup> 2019 Mac Pro, 28-core.

## Architecture

```
reader/parser ──> prover ──> planner ──> scheduler ──> printer
                  └──────── pipeline ────────┘
```

| Stage | Description |
|-------|-------------|
| **Reader / Parser** | Loads md5-cache into Prolog facts via a DCG grammar (PMS 9 / EAPI 9) |
| **Prover** | Inductive proof search producing Proof, Model, Constraints, and Triggers |
| **Planner** | Wave scheduling (Kahn) with parallelism; returns an acyclic plan and a remainder |
| **Scheduler** | Strongly Connected Component (SCC) decomposition (Kosaraju) and merge-set scheduling for cyclic remainders |
| **Printer** | Renders the plan, assumptions, suggestions, and optional LLM explanation |

See the full architecture diagram: [`Documentation/Diagrams/architecture.svg`](Documentation/Diagrams/architecture.svg).

## How it compares

| | Portage | Paludis | pkgcore | portage-ng |
|---|---------|---------|---------|------------|
| **Language** | Python | C++ | Python | SWI-Prolog |
| **Resolver model** | Greedy graph builder + backtracking | Constraint accumulator + exception-driven restart | Same imperative model as Portage | Single-pass inductive proof search |
| **Conflict handling** | Up to 20 retries; masks accumulate negatively | Up to 9,000 restarts; fresh resolver each time | Same as Portage | Iterative refinement with learned domains (positive) and rejects (negative) |
| **Completeness** | Sometimes fails to produce a plan | May exhaust restarts | Same as Portage | Always produces a plan (with explicit assumptions when needed) |
| **Formal guarantees** | None | None | None | Every plan is a proof |

For a deeper comparison of the reasoning models, see
[`Documentation/doc-resolver-comparison.md`](Documentation/doc-resolver-comparison.md).

## Unique capabilities

- **Multiple modes** -- standalone, IPC daemon (Unix socket), client/server (TLS), distributed workers
- **mDNS/Bonjour discovery** -- automatic cluster formation for distributed proving
- **LLM integration** -- `--explain` / `--llm` for AI-assisted plan explanation
- **Interactive Prolog shell** -- `--shell` for live querying of the knowledge base
- **Graph generation** -- interactive SVG dependency graphs via Graphviz
- **Contextual logic programming** -- an object-oriented paradigm for Prolog with contexts, classes, and inheritance ([documentation](Documentation/doc-contextual-logic-programming.md))

## Quick start

**Prerequisites:** SWI-Prolog >= 9.3, a Gentoo Portage tree (or md5-cache snapshot).

```bash
# Build and install
make build && make install

# Pretend (dry-run) a build plan
portage-ng --mode standalone --pretend app-editors/neovim

# Interactive Prolog shell
portage-ng --mode standalone --shell

# Sync the Portage tree
portage-ng --mode standalone --sync
```

For the full command reference, see the
[`portage-ng(1)` manpage](Documentation/Manpage/portage-ng.1).

## Screenshots

### Build plan

![Build plan for app-editors/neovim](Documentation/Images/proof.png)

### Bug search

![Searching Gentoo Bugzilla for known issues](Documentation/Images/bugs.png)

### Package search

![Querying the in-memory knowledge base](Documentation/Images/search.png)

### Upstream version check

![Checking upstream versions via Repology](Documentation/Images/upstream.png)

## Handbook

The portage-ng handbook is under construction. Topics covered:

- [Resolver comparison](Documentation/doc-resolver-comparison.md)
- [Dependency ordering](Documentation/doc-dependency-ordering.md)
- [Context terms](Documentation/doc-context-terms.md)
- [Contextual logic programming](Documentation/doc-contextual-logic-programming.md)
- [LLM explainer](Documentation/doc-explainer.md)
- [TLS certificates](Documentation/doc-tls-certificates.md)

## License

BSD 3-Clause. See [`LICENSE`](LICENSE).
