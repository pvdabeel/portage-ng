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
(the sampler), **bulk testing**, and a **pm-bench performance comparison**
across emerge, pkgcore, Paludis, and portage-ng IPC.


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

**Companion caches.**  `Knowledge/profile.qlf` (profile tree data, built by
`--sync`) and `Knowledge/preference.qlf` (materialized preference state after
`preference:init/0`, built on first startup and invalidated by `--sync` or input
changes) further reduce startup work.  After `kb.qlf` loads, `knowledgebase:load/0`
also primes the JIT index on `cache:entry_metadata/4` for slotted profile-mask
lookups so the first `preference:init/0` does not pay a multi-second penalty on
atoms such as `dev-qt/qtimageformats:5`.


## Pillar 2: Goal expansion macros

High-level queries in the knowledge layer are written for clarity; at
**compile time** they are rewritten into **direct cache access**, so the
runtime path never pays for meta-interpretation over generic search.

A module-local `query:goal_expansion/2` hook in
`Source/Knowledge/query.pl` performs this rewrite (deliberately *not*
`user:goal_expansion/2`, so only code compiled inside the `query` module
is affected — portage-ng#59).  It expands `search(Query, Repo://Id)`
goals at compile time: `compile_query_list/3` / `compile_query_compound/3`
translate each query term into direct indexed cache lookups such as
`cache:ordered_entry/5` conjunctions.

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
sampler:phase_walltime(-T)
```

Captures a wall-clock snapshot.  The pipeline takes three snapshots —
before resolving, between resolving and ordering, and after ordering.

```prolog
sampler:phase_record(T0, T1, T2)
```

Computes and records the per-phase deltas (resolve ms, order ms) from
the three snapshots for later retrieval.

### Test statistics

```prolog
resolver:test_stats(Repository)
resolver:test_stats_pkgs(Repository, PackageList)
```

Run the resolver across all packages (or a specific list) in a repository
and collect aggregate statistics:

- Totals: entries processed, proved, failed
- Share of entries with domain assumptions and with cycle breaks
  (as percentages)
- Failure and assumption-type breakdowns
- Slowest entries and packages

### Feature term unification sampling

The sampler tracks feature term unification operations to identify hot paths in
context merging. Excessive merges can indicate redundant re-proving.


## Bulk testing workflow

The standard performance testing workflow uses the `--shell` here-doc
pattern:

```bash
./Source/Application/Wrapper/portage-ng-dev --mode standalone --shell --timeout 60 <<'PL'
resolver:test_stats(portage).
halt.
PL
```

For specific packages:

```bash
./Source/Application/Wrapper/portage-ng-dev --mode standalone --shell <<'PL'
resolver:test_stats_pkgs(portage, ['kde-apps'-'kde-apps-meta']).
halt.
PL
```


## Performance comparison: package managers (pm-bench)

The numbers below are **process wall-clock** times for a cold
`--pretend` / resolve-only invocation of each tool — how long it takes
to produce a merge plan, not how long builds take.  They were measured
on `vm-linux.local` with `Source/Application/Wrapper/pm-bench` against
an identical Portage tree, VDB, and `/etc/portage` for every engine.

| **Tool** | **Invocation** |
| :--- | :--- |
| emerge | `emerge -vp <pkg>` |
| pmerge | `pmerge -vp <pkg>` (pkgcore) |
| cave | `cave resolve --lazy <pkg>` (Paludis) |
| ng-ipc | `portage-ng-dev --mode ipc --pretend <pkg>` (ultralight SWI `ipclient.pl`) |
| ng-ipc-cpp | `ipcclient --mode ipc --pretend <pkg>` (native C++ client) |

portage-ng IPC uses a **warm daemon** (knowledge base already loaded);
the timed sample is client connect + prove + print.  Standalone
portage-ng (full process boot + `kb.qlf` load each time) is much slower
and is not included in this table.


### Packages where emerge produced a plan

**16,313** packages where `emerge -vp` exited 0 (an actual plan).
Median speedup is `emerge_median / tool_median`.  Total is the sum of
per-package wall times (serial equivalent).

| **Tool** | **Median** | **Average** | **Total** | **Median speedup** | **Total speedup** |
| :--- | ---: | ---: | ---: | ---: | ---: |
| emerge | 1,234 ms | 1,345 ms | 6.09 hours | 1.0× | 1.0× |
| cave | 520 ms | 1,372 ms | 6.22 hours | 2.4× | 1.0× |
| pmerge | 245 ms | 282 ms | 1.28 hours | 5.0× | 4.8× |
| ng-ipc | 82 ms | 119 ms | 32.4 minutes | **15.1×** | **11.3×** |
| ng-ipc-cpp | 55 ms | 92 ms | 25.0 minutes | **22.4×** | **14.6×** |

The C++ IPC client is about **27 ms** faster than the SWI `ipclient` at
the median (same daemon; the gap is client process boot).  Both IPC
tools finished every package in this set with exit code 0.  Cave’s
average/total are inflated by hard timeouts (120 s cap in this run).


### All packages in the manifest

Across all **19,430** packages in the pm-bench manifest (including
those where emerge exited non-zero):

| **Tool** | **Median** | **Average** | **Total** | **Median speedup** |
| :--- | ---: | ---: | ---: | ---: |
| emerge | 1,240 ms | 1,437 ms | 7.76 hours | 1.0× |
| cave | 544 ms | 1,891 ms | 10.21 hours | 2.3× |
| pmerge | 247 ms | 286 ms | 1.55 hours | 5.0× |
| ng-ipc | 85 ms | 161 ms | 52.0 minutes | **14.6×** |
| ng-ipc-cpp | 58 ms | 133 ms | 43.2 minutes | **21.4×** |


### Why portage-ng IPC is faster

The gap is not primarily “Prolog vs Python.”  It comes from
architectural differences that compound across thousands of packages:

| **Factor** | **Traditional PMs** | **portage-ng (daemon + IPC)** |
| :--- | :--- | :--- |
| Startup cost | Interpreter + imports + metadata load each invoke | KB loaded once in the daemon; thin client (~3–30 ms) |
| Graph construction | Build full graph, then check for conflicts | Single-pass proof — no separate graph phase |
| Conflict recovery | Discard / restart large parts of the search | Retry the affected subtree with learned constraints |
| Repeated queries | Each pretend starts cold | In-memory facts persist across IPC requests |
| Parallelism | Sequential graph walk | Ordering pass identifies parallel waves |

The largest single factor for interactive use is the **resident
daemon** plus **qcompiled cache** (Pillar 1): once loaded, ebuilds are
indexed Prolog facts and queries hit first-argument indexing directly.
The second factor is **single-pass proving** (Pillar 4): for over 99%
of packages, portage-ng needs no backtracking at all.
