# Dependency Resolver Comparison: Portage, Paludis, portage-ng

## Architecture Overview

### Portage (Python, `depgraph.py`)

**Model:** Greedy graph builder with retroactive backtracking.

Portage builds a dependency graph incrementally. For each dependency,
`_select_pkg_highest_available_imp` picks the best candidate (newest stable).
A `PackageTracker` detects slot conflicts when two packages compete for the
same slot.

When a conflict is detected:
1. `_process_slot_conflict` identifies the conflicting packages
2. `_slot_confict_backtrack` masks ONE package via `runtime_pkg_mask`
3. `Backtracker` creates a new `BacktrackNode` with the mask
4. The entire dependency graph is rebuilt from scratch
5. Repeat up to `--backtrack=N` times (default 20)

**Key characteristics:**
- Full graph rebuild per backtrack attempt
- Masks (negative filtering) accumulate across attempts
- No package-specific heuristics
- Each attempt adds ONE mask
- 14 backtracks needed for OCaml Jane Street async_kernel

**Source:** `lib/_emerge/depgraph.py`, `lib/_emerge/resolver/backtracking.py`

### Paludis (C++, `decider.cc`)

**Model:** Constraint accumulator with exception-driven restart.

Paludis maintains a `Resolution` per `Resolvent` (package+slot+destination).
Each Resolution accumulates `Constraints` and has a `Decision` (chosen
candidate). Dependencies are added incrementally.

When a new constraint conflicts with an existing decision:
1. `_verify_new_constraint` detects the incompatibility
2. `_made_wrong_decision` finds the CORRECT candidate via
   `_try_to_find_decision_for` (evaluates ALL accumulated constraints)
3. `_suggest_restart_with` throws `SuggestRestart` carrying:
   - The correct decision
   - A "preloading constraint" for the next resolver
4. The main loop catches `SuggestRestart`, adds the preset, creates a
   brand new `Resolver`, and retries

**Key characteristics:**
- Positive guidance (preloads correct candidate, not rejects wrong one)
- Brand new resolver each restart (fresh state)
- `_try_to_find_decision_for` evaluates ALL constraints simultaneously
- Typically fewer restarts than Portage
- Up to 9000 restarts allowed

**Source:** `paludis/resolver/decider.cc`, `src/clients/cave/resolve_common.cc`

### portage-ng (SWI-Prolog, `prover.pl` + `rules.pl`)

**Model:** Inductive proof search with constraint guards and learned
constraint refinement.

portage-ng uses a Prolog proof tree. Each `grouped_package_dependency` is a
rule that selects a candidate, adds `selected_cn` and `cn_domain` constraints,
and recursively proves the candidate's subtree. Constraint guards fire during
constraint unification and detect conflicts.

When a conflict is detected:
1. The constraint guard learns the domain constraint via `prover:learn`
2. Throws `rules_reprove_cn_domain` for the existing reprove mechanism
3. The handler adds rejects and retries with the learned constraint applied
4. On retry, `grouped_dep_effective_domain` intersects the learned domain
   with the local domain, narrowing candidates before selection
5. For inconsistent domains, the Vermeir-style clause identifies the
   "adjustable origin" and narrows it further
6. For wrong-level assumptions, `maybe_learn_parent_narrowing` learns to
   exclude the parent version that introduced the unsatisfiable constraint

**Key characteristics:**
- Single-pass proof for 99%+ of targets (fastest resolver)
- Learned constraints (positive guidance via domain narrowing)
- Existing reject mechanism for backward compatibility
- Slot-scoped domain learning (cn_domain(C,N,Slot))
- Vermeir-style priority resolution for inconsistent domains
- No package-specific code

**Source:** `Source/prover.pl`, `Source/rules.pl`

## Comparison Table

| Aspect | Portage | Paludis | portage-ng |
|---|---|---|---|
| Language | Python | C++ | SWI-Prolog |
| Conflict detection | Post-hoc (after graph built) | Incremental (on constraint add) | Incremental (constraint guard) |
| What carries across retries | Masks (negative) | Preloads (positive) | Learned domains (positive) + Rejects (negative) |
| Fresh state each retry? | Yes (new depgraph) | Yes (new Resolver) | Partial (reject set accumulates, learned store accumulates) |
| Finding the right candidate | Brute force (mask+retry) | `_try_to_find_decision_for` with ALL constraints | Domain narrowing (Zeller) + priority resolution (Vermeir) |
| Performance | Slowest (full rebuild) | Fast (targeted restarts) | Fastest (single-pass for most targets) |
| Package-specific code | None | None | None |

## Academic Foundations

### Zeller & Snelting: Feature Logic (ESEC 1995, TOSEM 1997)

"Unified Versioning Through Feature Logic" — version sets are identified by
feature terms and configured by incrementally narrowing the set until each
component resolves to a single version. portage-ng's `version_domain` with
`domain_meet` (intersection) is essentially Zeller's feature term narrowing.
The learned constraint store implements Zeller's feature implication
propagation: constraints discovered in one proof attempt propagate to narrow
version sets in the next attempt.

### Vermeir & Van Nieuwenborgh: Ordered Logic Programs (JELIA 2002)

"Preferred Answer Sets for Ordered Logic Programs" — when rules conflict,
a partial order determines which yields. portage-ng's `find_adjustable_origin`
implements this: when a domain is inconsistent (two bounds that can't be
simultaneously satisfied), the bound from the "adjustable" origin (the
package that already has a learned constraint) is dropped, and the origin
is narrowed further.

### CDCL / PubGrub / SAT-based approaches

Modern package resolvers (libsolv, Resolvo, PubGrub) encode version
constraints as boolean satisfiability problems. portage-ng's approach is
different: it uses proof search with domain narrowing rather than SAT
encoding. The learned constraint store is analogous to CDCL's learned
clauses, but expressed as version domains rather than boolean clauses.
