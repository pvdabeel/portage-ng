# Performance and Profiling

portage-ng loads on the order of **32,000 ebuilds** into memory and reasons
about their dependencies with **formal proof search**. That combination is
easy to make slow: naive parsing, interpreted queries, imperative
undo stacks, exponential backtracking, and repeated failed branches can each
dominate runtime on their own. The design question is not “which single trick
wins?” but **how we stack complementary strategies** so the whole pipeline
stays responsive.

The answer is **the five pillars of portage-ng performance**: compiled
knowledge (qcompiled cache), compile-time query expansion, persistent AVL
structures for proof state, prescient proving that avoids redundant work, and
incremental learning that narrows the search after failures. Together they
explain why the tree can load with sub-second queries and why a full prove
across all packages can finish in under a minute on a strong multi-core
machine—while leaving room for profiling and targeted optimization.

This chapter walks those pillars in order, then covers **instrumentation**
(the sampler), **bulk testing**, and a **performance comparison** between
portage-ng and Portage.


## Pillar 1: Compiled knowledge (qcompiled `.qlf` files)

The Portage tree is **not** parsed from scratch on every startup. During
`--sync`, metadata is read and the knowledge base is written in a form that
SWI-Prolog can **qcompile** into a binary load unit—`Knowledge/kb.qlf` (source
facts live in `Knowledge/kb.raw`). The next time the application starts, it
loads that **binary** representation instead of re-parsing large textual
artifacts.

That is the **largest single speedup** in the system: startup drops from
**tens of seconds** of parsing and assertion to **under a second** for the
compiled cache, after which reasoning works directly over in-memory facts.
Everything else in this chapter assumes that this first pillar is in place;
without it, no amount of clever proving would feel fast enough.


## Pillar 2: Goal expansion macros

High-level queries in the knowledge layer are written for clarity; at
**compile time** they are rewritten into **direct cache access**, so the
runtime path never pays for meta-interpretation over generic search.

`goal_expansion/2` in `Source/Knowledge/query.pl` performs this rewrite. For
example, a search by repository, category, and package name expands straight
to an ordered cache entry lookup:

```prolog
user:goal_expansion(query:search(R, C, N), cache:ordered_entry(R, _, C, N, _)).
```

The expanded code calls the indexed predicate **directly**. SWI-Prolog’s
**first-argument indexing** on `cache:entry/5` (and related entry predicates)
makes those lookups **O(1) amortized** in typical use: the prover’s inner loop
sees plain deterministic cache reads, not a slow interpretive layer.

For how the knowledge base and query surface fit together, see
[Chapter 6: Knowledge Base and Cache](06-doc-knowledgebase.md).


## Pillar 3: Persistent AVL trees

Proof search maintains large associative structures—proof literals, models,
constraints, triggers—using **`library(assoc)` AVL trees**. Lookups and
updates are **O(log n)**; for about **32,000** entries that is on the order
of **fifteen comparisons** per operation, which is cheap enough to live in
the inner loop of dependency proving.

The deeper win is **persistence**: AVL trees in Prolog are **immutable
structures** threaded through the search. **Backtracking** automatically
restores the previous tree without hand-written save/restore stacks or
explicit undo logs—the kind of machinery imperative resolvers often maintain
by hand. That keeps the prover’s control flow simple while remaining safe
under deep choicepoints.

**Practical caveat:** Proof and Model AVLs still **grow with proof size**.
Algorithms should avoid **full traversals** when a more local structure
suffices; the Triggers AVL (see the next pillar) exists partly so reverse
lookups do not devolve into scanning the entire proof tree. That trade-off
shows up again in practice when proof trees grow large.


## Pillar 4: Prescient proving (avoiding backtracking)

Naive proof search can exhibit **O(2ⁿ)** behaviour in the worst case: each
wrong choice is explored and then undone by backtracking. portage-ng pushes
hard in the other direction by **merging proof context** when the same
literal is encountered again with **refined constraints**—via mechanisms such
as **feature term unification**—so the system does not blindly re-prove from scratch
every time the dependency graph revisits a head under slightly different
assumptions.

In practice, for most real packages, that style of **prescient** handling
yields **O(n) amortized** proof steps rather than exponential churn. The
**Triggers AVL** complements this: it supports **efficient identification of
affected heads** when something downstream changes, instead of linear scans
over the whole proof.

The sampler’s **`ctx_union` sampling** (documented later in this chapter)
exists precisely to spot **hot merge paths**—a sign that context merging is
working harder than it should and that some literals may still be reproved
more often than necessary.


## Pillar 5: Incremental learning (avoiding repeated failures)

When a proof attempt fails, portage-ng does not always forget what went
wrong. **Learned constraints** from failed branches can **persist across
reprove retries**, **narrowing domains** so the same conflict is not hit twice
the same way. Together with a **reject set** that records candidates already
ruled out, the prover avoids thrashing on the same dead ends.

That closes the loop with [Chapter 8: The Prover](08-doc-prover.md): reprove
and learning are part of the same story as performance. If retries explode
without narrowing behaviour improving, runtime suffers.


## Sampler module

The sampler (`Source/Application/Performance/sampler.pl`) is the main place
to **measure** whether the pillars above are behaving as intended in
production-like runs.

### Hook performance

```prolog
sampler:phase_walltime(Phase, Goal)
```

Wraps `Goal` and records wall-clock time for the named `Phase`. Used by the
pipeline to time each stage (prove, plan, schedule).

```prolog
sampler:phase_record(Phase, Duration)
```

Records a phase timing for later retrieval.

### Test statistics

```prolog
prover:test_stats(Repository)
prover:test_stats_pkgs(Repository, PackageList)
```

Run the prover across all packages (or a specific list) in a repository and
collect aggregate statistics:

- Total packages attempted
- Success rate (no assumptions)
- Cycle-break-only rate
- Domain assumption rate
- Average proof time

### Feature term unification sampling

The sampler tracks feature term unification operations to identify hot paths in
context merging. Excessive merges can indicate redundant re-proving.


## Bulk testing workflow

The standard performance testing workflow uses the `--shell` here-doc
pattern:

```bash
./Source/Application/Wrapper/portage-ng-dev --mode standalone --shell --timeout 60 <<'PL'
prover:test_stats(portage).
halt.
PL
```

For specific packages:

```bash
./Source/Application/Wrapper/portage-ng-dev --mode standalone --shell <<'PL'
prover:test_stats_pkgs(portage, ['kde-apps'-'kde-apps-meta']).
halt.
PL
```


## Performance comparison: portage-ng vs Portage

The numbers below put the five pillars in perspective with measured
data from a full Portage tree comparison.  Both resolvers start from
the same input: an identical Portage tree snapshot (roughly 32,000
ebuilds), the same VDB (installed package database), and the same
`/etc/portage` configuration.  The measurement is **dependency
resolution time only** — how long it takes to produce a merge plan,
not how long the actual builds take.

- **Portage** uses `emerge -vp <target>`, which runs the Python
  `depgraph.py` resolver with greedy selection and backtracking.
- **portage-ng** uses `--mode standalone --pretend <target>`, which
  runs the Prolog prover, planner, and scheduler.


### Resolution speed

The comparison covers **30,097 packages** resolved by both tools.
For the 22,971 packages where Portage itself reports a clean result
(`emerge_ok`), portage-ng is faster in **100%** of cases:

| | **Portage** | **portage-ng** | **Speedup** |
| :--- | ---: | ---: | ---: |
| Average | 1,607 ms | 34 ms | **48x** |
| Median | 1,413 ms | 7 ms | **202x** |
| 95th percentile | 2,869 ms | 154 ms | **19x** |
| Cumulative (22,971 pkgs) | 10.3 hours | 12.9 minutes | **48x** |

The median package resolves in **7 milliseconds** in portage-ng
versus **1.4 seconds** in Portage — a two-hundred-fold improvement.
Even at the 95th percentile (complex packages with deep dependency
chains), portage-ng finishes in 154 ms while Portage needs nearly
3 seconds.

Across all 30,097 packages (including those where Portage reports
errors), portage-ng is faster in **99.8%** of cases.  The few
exceptions are large meta-packages (e.g. `gnome-base/gnome`) where
portage-ng's broader dependency expansion temporarily exceeds
Portage's more selective approach.


### Why portage-ng is faster

The performance gap is not about language speed (Prolog vs Python).
It comes from architectural differences that compound across
thousands of packages:

| **Factor** | **Portage** | **portage-ng** |
| :--- | :--- | :--- |
| Startup cost | Python interpreter + module imports per invocation | Qcompiled cache loads once, shared across all queries |
| Graph construction | Build full graph, then check for conflicts | Single-pass proof — no separate graph phase |
| Conflict recovery | Discard entire graph, rebuild from scratch | Retry only the affected subtree with learned constraints |
| Repeated queries | Each `emerge -vp` starts cold | In-memory facts persist; subsequent queries are instant |
| Parallelism | Sequential graph walk | Wave planner identifies parallel steps automatically |

The largest single factor is the **qcompiled cache** (Pillar 1): once
loaded, all 32,000 ebuilds are in memory as indexed Prolog facts, and
queries hit first-argument indexing directly.  Portage re-reads and
re-parses metadata structures on each invocation.

The second factor is **single-pass proving** (Pillar 4): for over 99%
of packages, portage-ng needs no backtracking at all.  Portage's
greedy approach works well for simple cases but scales poorly when
conflicts require multiple backtracks — each of which rebuilds the
entire dependency graph.
