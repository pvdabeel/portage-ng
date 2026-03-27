# Context Terms in portage-ng

How contexts are created, propagated, and merged across the dependency graph.

## Overview

Every literal in the prover carries a **context** — a list of tagged terms
that records provenance, ordering, constraints, and USE requirements as the
proof expands through dependencies.  The literal format is:

```
Literal:Action?{Context}
```

Contexts are not opaque blobs; they are structured as **feature-term lists**
and are merged using a Zeller-inspired feature-unification algorithm.  This
gives them lattice semantics: merging two contexts produces a well-defined
meet that preserves all non-contradictory information from both sides.


## Anatomy of a context

A context is a Prolog list.  Each element is either a plain term or a
`Feature:Value` pair.  The distinction matters for merging:

| Form | Example | Merge behaviour |
|------|---------|-----------------|
| Plain term | `self(portage://sys-apps/portage-3.0.77-r3)` | Identity match; duplicates dropped |
| Feature:Value | `build_with_use:use_state([foo],[bar])` | Value-merged by `val_hook/3` |
| Feature:Compound | `slot(sys-apps,portage,0/0):{…}` | Compound feature key |


### Common context tags

| Tag | Set by | Purpose |
|-----|--------|---------|
| `self(Repo://Entry)` | `dependency:add_self_to_dep_contexts` | Identifies the parent ebuild that introduced this dependency edge |
| `build_with_use:use_state(En,Dis)` | `dependency:process_build_with_use` | Bracketed USE constraints from the dep atom (e.g. `dev-libs/foo[bar,-baz]`) |
| `slot(C,N,Ss):{Candidate}` | `dependency:process_slot` | Slot lock from `:=` (subslot rebuild) semantics |
| `after(Literal)` | `rules:ctx_add_after` | Ordering constraint: this dep must come after `Literal` in the plan; propagates to children |
| `after_only(Literal)` | `rules:add_after_only_to_dep_contexts` | Ordering constraint that does **not** propagate to children |
| `replaces(pkg://Entry)` | Install/update rules | Records which installed package this action replaces |
| `assumption_reason(Reason)` | Domain assumption fallback | Records why a domain assumption was made (e.g. `missing`, `masked`, `keyword_filtered`) |
| `suggestion(Type,Detail)` | Relaxation fallback | Records an actionable suggestion (e.g. `accept_keyword`, `unmask`, `use_change`) |
| `domain_reason(cn_domain(C,N,Tags))` | `candidate:add_domain_reason_context` | Diagnostic tags for version domain narrowing |
| `constraint(cn_domain(C,N):{Domain})` | Constraint system | Carries an inline constraint for domain scoping |


## Context lifecycle

### 1. Creation (root)

At the top level, the prover starts with an empty context (`{}` or `[]`).
The first rule expansion — typically `target/2` → `install` — begins
populating it.

### 2. Extension (downward propagation)

As rules expand dependencies, contexts grow:

```
target(sys-apps/portage)?{}
  └─ install(portage://sys-apps/portage-3.0.77-r3):install?{...}
       ├─ dep(dev-lang/python):install?{self(portage://sys-apps/portage-3.0.77-r3),
       │                                 build_with_use:use_state([ssl,threads],[]),
       │                                 after(install(portage://...))}
       │    └─ dep(dev-libs/openssl):install?{self(portage://dev-lang/python-3.13),
       │                                       build_with_use:use_state([],[]),
       │                                       after(install(portage://dev-lang/python-3.13))}
       └─ dep(app-arch/tar):install?{self(portage://sys-apps/portage-3.0.77-r3),
                                      after(install(portage://...))}
```

Key propagation rules:

- **`self/1`** is set to the current ebuild at each dependency edge.
  It does **not** accumulate — each edge replaces the previous `self`.
- **`build_with_use`** is per-edge: the child gets a fresh `build_with_use`
  from its dep atom, not the parent's `build_with_use`.
- **`after/1`** propagates transitively (children inherit it).
- **`after_only/1`** does **not** propagate (ordering is local to this edge).
- **`assumption_reason`** and **`build_with_use`** are dropped on PDEPEND
  edges (via `ctx_drop_build_with_use_and_assumption_reason`).


### 3. Merging (join points)

When the prover encounters a literal that was already proven with a
different context, it merges the old and new contexts via `ctx_union`:

```prolog
sampler:ctx_union(OldCtx, NewCtx, MergedCtx)
```

The merge algorithm:

1. **Strip `self/1`** from the old context entirely.
2. **Extract one `self/1`** from the new context (keep it aside).
3. **Unify** the remaining lists via `feature_unification:unify/3`.
4. **Prepend** the extracted `self/1` back onto the result.

This guarantees:
- At most one `self/1` in the merged result (from the new/incoming side).
- Feature:Value pairs with the same key are merged by `val_hook/3`.
- Plain terms present in either side appear in the result (union semantics).


### 4. Stripping for memoisation

Before checking whether a literal has already been proven, planning markers
are stripped so they don't pollute the memoisation key:

```prolog
rules:ctx_strip_planning(Context0, Context)
```

This removes `after/1` and `world_atom/1` — ordering and planning concerns
that should not affect whether a proof is reusable.


## Feature unification in detail

`feature_unification:unify/3` implements a **horizontal unification**
algorithm inspired by Zeller's feature logic:

1. Normalise both terms (`{}` → `[]`).
2. Walk both lists.  For each `Feature:Value` pair in list A, check if
   list B has the same `Feature`.
3. If both sides have `Feature`, merge values via `val/3` (or `val_hook/3`
   for domain-specific merge).
4. If only one side has `Feature`, include it in the result.
5. Plain terms are matched by identity; duplicates are dropped.

### Value merge rules

| V1 | V2 | Result | Semantics |
|----|----|--------|-----------|
| `{L1}` | `{L2}` | `{Intersection}` | Set intersection (must be non-empty) |
| `[L1]` | `[L2]` | `[Union]` | Sorted union (fails on contradictions) |
| atom `V` | `{L}` | `{V}` if `V ∈ L` | Singleton intersection |
| `V` | `V` | `V` | Identity |

### Domain-specific hooks (`val_hook/3`)

| Feature | Hook in | Merge behaviour |
|---------|---------|-----------------|
| `build_with_use` | `use.pl` | `use_state(En1,Dis1)` ⊔ `use_state(En2,Dis2)` = union of enable/disable sets; **fails** if a flag appears in both enable and disable |
| `cn_domain` | `version.pl` | `version_domain` meet (intersection of version bounds); `none` is identity |


## `self/1` — parent provenance

The `self/1` tag identifies **which ebuild introduced this dependency**.
It is critical for:

- **USE evaluation**: `use:effective_use_in_context/3` looks up the USE
  model of the ebuild in `self/1` to evaluate USE conditionals.
- **Blocker source**: `candidate:blocker_source_constraints/5` uses `self/1`
  to determine who is blocking whom.
- **Parent narrowing**: `candidate:maybe_learn_parent_narrowing/4` uses
  `self/1` to learn that the parent version should be excluded when a child
  dependency cannot be satisfied.
- **REQUIRED_USE**: `query:with_required_use_self/2` evaluates REQUIRED_USE
  against the USE model of the package in `self/1`.

### Invariant: at most one `self/1`

Without bounding, `self/1` would stack along dependency chains:

```
[self(A), self(B), self(C), ...]  ← unbounded growth
```

The system prevents this at two levels:

1. **`dependency:ctx_set_self/3`** replaces any existing `self/1` when
   setting a new parent.
2. **`ctx_union_raw/3`** strips all `self/1` from the old context and
   keeps only one from the new context.


## `build_with_use` — bracketed USE requirements

When a dependency atom carries USE requirements (e.g.
`dev-lang/python[ssl,threads]`), they are recorded as:

```prolog
build_with_use:use_state([ssl, threads], [])
```

The enable list contains flags that must be ON; the disable list contains
flags that must be OFF.

### Per-edge, not inherited

Each dependency edge computes its own `build_with_use` from the dep atom.
The parent's `build_with_use` is **removed** before computing the child's:

```prolog
dependency:process_build_with_use(MergedUse, ContextDep, NewContext, ...)
```

This prevents a grandparent's USE requirements from leaking to grandchildren.

### Merge semantics

When `ctx_union` merges two contexts with `build_with_use`, the `val_hook`
in `use.pl` takes the **union** of enable sets and the **union** of disable
sets.  If a flag appears in both enable and disable, the merge **fails**
(contradiction), forcing the prover to backtrack.

### PDEPEND edge

On PDEPEND edges, `build_with_use` is dropped because PDEPEND dependencies
are resolved at runtime, not build time, so build-time USE constraints do
not apply.


## Constraints vs contexts

Contexts and constraints serve different purposes:

| Aspect | Context | Constraint |
|--------|---------|------------|
| Scope | Per-literal (local) | Global (across proof) |
| Storage | List attached to `?{...}` | AVL in ConstraintsAVL |
| Growth | Bounded by design | Grows with proof |
| Purpose | Provenance, ordering, USE | Version selection, slot locks, blockers |

### How they interact

1. **Context → Constraint**: When a candidate is selected, constraints are
   **emitted** into the global ConstraintsAVL (e.g. `selected_cn(C,N)`,
   `cn_domain(C,N)`, `slot(C,N,S)`).

2. **Constraint → Context**: Inline constraint terms like
   `constraint(cn_domain(C,N):{Domain})` can appear in contexts, passed
   down from parent deps that want to scope the version domain for a child.

3. **Constraint guards**: After a constraint is merged into the global store,
   `rules:constraint_guard/2` fires to check consistency:
   - `cn_domain` ↔ `selected_cn` compatibility
   - `selected_cn` uniqueness (per slot)
   - `blocked_cn` ↔ `selected_cn` conflict detection

4. **Constraint learning**: When a constraint guard detects a conflict, it
   can `prover:learn/3` a narrowed domain that persists across reprove
   retries (Zeller-style incremental narrowing).


## Ordering: `after` vs `after_only`

Both create ordering edges in the plan, but they differ in propagation:

| Marker | Propagates to child deps? | Use case |
|--------|--------------------------|----------|
| `after(Lit)` | Yes | Build deps: the package and all its deps must come after `Lit` |
| `after_only(Lit)` | No | Runtime deps: only this package (not its deps) must come after `Lit` |

### Extraction

```prolog
rules:ctx_take_after_with_mode(Context, After, AfterForDeps, ContextRest)
```

- If `after(X)` → `After = X`, `AfterForDeps = X` (propagate).
- If `after_only(X)` → `After = X`, `AfterForDeps = none` (don't propagate).
- If neither → both `none`.


## Example: full context evolution

Starting from `emerge sys-apps/portage`:

```
1. target(sys-apps/portage)?{}
   │
   │  [target rule: select best visible candidate]
   │
2. install(portage://sys-apps/portage-3.0.77-r3):install?{}
   │
   │  [install rule: compute USE model, expand deps]
   │  Context gains: nothing yet (root)
   │
   ├─ DEPEND: dev-lang/python[ssl,threads]
   │  │
   │  │  [add_self_to_dep_contexts]
   │  │  [process_build_with_use]
   │  │  [ctx_add_after]
   │  │
   │  grouped_dep(dev-lang/python):install?{
   │    self(portage://sys-apps/portage-3.0.77-r3),
   │    build_with_use:use_state([ssl,threads],[]),
   │    after(install(portage://sys-apps/portage-3.0.77-r3))
   │  }
   │  │
   │  │  [candidate selected: python-3.13.2]
   │  │  [constraint emitted: selected_cn(dev-lang,python)]
   │  │  [slot constraint: slot(dev-lang,python,3.13)]
   │  │
   │  3. install(portage://dev-lang/python-3.13.2):install?{
   │       self(portage://sys-apps/portage-3.0.77-r3),
   │       build_with_use:use_state([ssl,threads],[]),
   │       after(install(portage://sys-apps/portage-3.0.77-r3))
   │     }
   │     │
   │     ├─ DEPEND: dev-libs/openssl:=
   │     │  │
   │     │  │  [self replaced: now python-3.13.2]
   │     │  │  [build_with_use replaced: openssl has no USE reqs → empty]
   │     │  │  [after propagated from parent]
   │     │  │  [slot processed: := adds slot lock]
   │     │  │
   │     │  grouped_dep(dev-libs/openssl):install?{
   │     │    self(portage://dev-lang/python-3.13.2),
   │     │    build_with_use:use_state([],[]),
   │     │    slot(dev-libs,openssl,0/3.4.1):{portage://dev-libs/openssl-3.4.1},
   │     │    after(install(portage://sys-apps/portage-3.0.77-r3))
   │     │  }
   │     │
   │     └─ RDEPEND: app-misc/mime-types
   │        │
   │        │  [RDEPEND: after_only (no propagation)]
   │        │  [build_with_use: fresh (no USE reqs)]
   │        │
   │        grouped_dep(app-misc/mime-types):install?{
   │          self(portage://dev-lang/python-3.13.2),
   │          build_with_use:use_state([],[]),
   │          after_only(install(portage://dev-lang/python-3.13.2))
   │        }
   │
   └─ RDEPEND: app-arch/tar
      │
      │  [RDEPEND: after_only]
      │
      grouped_dep(app-arch/tar):install?{
        self(portage://sys-apps/portage-3.0.77-r3),
        build_with_use:use_state([],[]),
        after_only(install(portage://sys-apps/portage-3.0.77-r3))
      }
```

Key observations:
- `self/1` always points to the **immediate** parent, never accumulates.
- `build_with_use` is replaced at each edge based on the dep atom's `[flags]`.
- `after/1` from DEPEND propagates down; `after_only/1` from RDEPEND does not.
- Slot locks (`:=`) add `slot/3` entries to the context.
- Constraint emissions (e.g. `selected_cn`) go into the global store, not the context.


## Design rationale

### Why feature unification?

Traditional dependency solvers use flat constraint lists or SAT clauses.
portage-ng uses feature-term unification because:

1. **Composability**: Contexts from different proof branches merge
   naturally at join points without ad-hoc conflict resolution.
2. **Bounded growth**: The `self/1` stripping in `ctx_union` and the
   per-edge `build_with_use` replacement prevent unbounded context growth
   along dependency chains.
3. **Domain extensibility**: New context tags can be added without changing
   the merge infrastructure — just add a `val_hook/3` clause if
   domain-specific merge is needed.
4. **Conflict detection**: The merge fails (backtracks) on contradictions
   (e.g. a flag in both enable and disable), providing natural constraint
   propagation.

### Why separate contexts and constraints?

Contexts are **local** (per-literal, scoped to a proof branch) while
constraints are **global** (shared across the entire proof).  This
separation allows:

- **Contexts** to carry provenance information that should not leak across
  unrelated proof branches.
- **Constraints** to enforce global invariants (e.g. only one version of a
  package can be selected) that must hold across the entire proof.
- **Constraint learning** to persist across reprove retries, narrowing the
  search space incrementally.
