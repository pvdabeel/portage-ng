# Prover, Assumptions & Reprove Mechanism

## Overview

The portage-ng prover builds a formal proof that a set of target packages
can be installed.  The proof is an AVL tree mapping literals to their
justifications.  When part of the dependency graph cannot be satisfied,
the prover records *assumptions* — lightweight markers that let the proof
complete while flagging the unresolved fragment for the user.

Two fundamentally different kinds of assumptions exist, and a bounded
reprove mechanism allows the prover to retry the proof with accumulated
knowledge before resorting to assumptions.

```
                        ┌─────────────────┐
                        │   prove/9       │
                        │ (top-level)     │
                        └────────┬────────┘
                                 │
                     ┌───────────▼───────────┐
                     │  with_reprove_state   │
                     │  (save/restore        │
                     │   learned store)      │
                     └───────────┬───────────┘
                                 │
               ┌─────────────────▼─────────────────┐
               │   prove_with_retries              │
               │   catch(prove_once, prover_reprove│
               │         handle_reprove)           │
               └─────────┬──────────┬──────────────┘
                         │          │ prover_reprove(Info)
                  success│          │
                         │    ┌─────▼─────────────────┐
                         │    │ handle_reprove         │
                         │    │ Attempt < MaxRetries?  │
                         │    │   yes: learn + retry   │
                         │    │   no:  reprove_exhausted
                         │    │        prove_once      │
                         │    │        (disabled)      │
                         │    └───────────────────────┘
                         │
               ┌─────────▼────────┐
               │   prove_once     │
               │  with_cycle_stack│
               │  prove_recursive │
               └──────────────────┘
```

## Data Structures

The prover maintains four AVL trees during proof construction:

| AVL       | Key → Value                        | Purpose                           |
|-----------|------------------------------------|-----------------------------------|
| Proof     | `rule(Lit)` → `dep(N, Body)?Ctx`   | Which rule justified Lit          |
| Model     | `Lit` → `Ctx`                      | Every proven literal + context    |
| Constraints | constraint key → value           | Accumulated constraint terms      |
| Triggers  | `BodyLit` → `[HeadLit, …]`        | Reverse-dependency index          |

## Assumption Taxonomy

The two kinds of assumptions are stored differently in the Proof and
Model trees.  Confusing them leads to wrong statistics, wrong plan
output, or missed warnings.

### 1. Domain Assumptions (`rule(assumed(X))`)

Introduced by the **rules layer** when a dependency cannot be satisfied
— for example, a package that does not exist in the tree, or a
REQUIRED_USE violation that makes every candidate invalid.

**How they are created:**

The `grouped_package_dependency` rule exhausts all candidates (via
Prolog backtracking), then the fallback chain (parent narrowing →
reprove → assumption), and finally emits:

```prolog
Conditions = [assumed(grouped_package_dependency(C,N,Deps):Action?{Ctx})]
```

The `assumed(X)` literal in the body is proved by the catch-all rule:

```prolog
rule(assumed(_), []) :- !.
```

This stores `rule(assumed(X))` in the Proof tree.

**Where they appear:**
- Proof: `rule(assumed(X))` → `dep(0, [])?Ctx`
- Model: the enclosing literal's entry (normal)
- Plan: rendered as "verify" steps + "Domain assumptions" warning block

### 2. Prover Cycle-Break Assumptions (`assumed(rule(X))`)

Introduced by the **prover** when it detects a cycle during proof
search.  If a literal is already on the cycle stack (currently being
proved), the prover cannot recurse further without diverging.  Instead,
it records a cycle-break:

```prolog
put_assoc(assumed(rule(Lit)), Proof, dep(-1, OldBody)?Ctx, Proof1),
put_assoc(assumed(Lit), Model, Ctx, NewModel)
```

**Where they appear:**
- Proof: `assumed(rule(Lit))` → `dep(-1, Body)?Ctx`
- Model: `assumed(Lit)` → `Ctx`
- Plan: SCC / merge-set scheduling; cycle explanation via `cycle:*`

### Summary Table

| Property               | Domain Assumption          | Prover Cycle-Break         |
|------------------------|----------------------------|----------------------------|
| Proof key              | `rule(assumed(X))`         | `assumed(rule(X))`         |
| Model key              | (normal literal)           | `assumed(Lit)`             |
| dep count              | 0                          | -1                         |
| Introduced by          | rules layer                | prover layer               |
| Represents             | unsatisfiable dependency   | cyclic dependency          |
| Printed as             | "Domain assumptions"       | cycle break (SCC)          |
| Exit code contribution | 2                          | 1                          |

## Reprove Mechanism

When a conflict is detected during proof search, the domain layer does
not simply fail — it records what went wrong and requests a retry with
refined knowledge.

### Triggering Reprove

Several predicates can throw `prover_reprove(Info)`:

| Source                          | When                                        |
|---------------------------------|---------------------------------------------|
| `maybe_request_grouped_dep_reprove` | Effective domain conflicts with selected CN; domain inconsistent; version/slot constraints present |
| `maybe_learn_parent_narrowing`  | Parent introduced a dep that made (C,N) unsatisfiable; learns to exclude parent version |
| `selected_cn_unique_or_reprove` | CN-domain constraint conflicts with already-selected candidate (constraint guard) |
| `selected_cn_not_blocked_or_reprove` | Blocker detected via blocked source snapshot |

Each throws `prover_reprove(cn_domain(C, N, RejectDomain, Candidates, Reasons))`.

### Handling Reprove

```
prover_reprove(Info) caught by prove_with_retries
        │
        ▼
heuristic:handle_reprove(Info, Added)
  ├── candidate:add_cn_domain_rejects(C, N, Domain, Candidates)
  │     → assertz(memo:cn_domain_reject_(Key, Rejected))
  ├── origin rejects from introduced_by reasons
  └── Added = true if new information learned
        │
        ├── Added = true, Attempt < MaxRetries
        │     → prove_with_retries(…, Attempt+1, MaxRetries)
        │       (restarts prove_once from scratch)
        │
        └── Added = false  OR  Attempt >= MaxRetries
              → heuristic:reprove_exhausted/0
                (clears cn_domain_reject_ so final attempt is unbiased)
              → with_reprove_disabled(prove_once(…))
                (final attempt; no new prover_reprove can be thrown)
```

### Learned Constraint Store

The `prover:learn/3` and `prover:learned/2` predicates maintain a
key-value store that **persists across reprove retries** within the same
top-level `prove/9` invocation.  This is distinct from the reject set
(which accumulates and is cleared on exhaustion).

The domain uses learned constraints for:
1. **Candidate narrowing**: `grouped_dep_effective_domain` intersects
   the local+context domain with any learned domain.
2. **Conflict learning**: constraint guards learn the domain when a
   conflict is detected.
3. **Parent narrowing**: `maybe_learn_parent_narrowing` learns to
   exclude the parent version when a child dep cannot be satisfied.

### Retry Budget

`reprove_max_retries` defaults to 3 (configurable via
`config:reprove_max_retries/1`).  The final attempt runs with reprove
disabled so the proof can complete with assumptions if necessary.

## REQUIRED_USE Violation Flow

When a parent package forces USE flags on a dependency via bracketed USE
deps (e.g. `cat/pkg[feature]`), and the dependency's `REQUIRED_USE`
forbids that flag combination, the REQUIRED_USE violation mechanism
ensures the prover explores alternatives before assuming.

### Step-by-Step Flow

```
1. Parent "app" depends on "lib[feature_z]"
   → build_with_use propagates feature_z to lib's context

2. lib's :install/:run entry rule fires
   → use:build_with_use_resolve_required_use computes BWU state
   → use:verify_required_use_with_bwu checks REQUIRED_USE

3. Verification FAILS (lib has REQUIRED_USE=!feature_z)
   → use:describe_required_use_violation caches structured info
   → assertz(memo:requse_violation_(C, N, ViolDesc))
   → entry rule FAILS (not assumes!)

4. Prover backtracks to grouped_package_dependency
   → tries next candidate version of lib (if any)
   → all candidates exhausted

5. Fallback chain in grouped_package_dependency:
   a. maybe_learn_parent_narrowing
      → learns to exclude app-1.0, throws prover_reprove
   b. maybe_request_grouped_dep_reprove
      → may throw if domain/constraint conflicts exist
   c. Assumption path (after retries exhausted):
      → explanation:assumption_reason_for_grouped_dep classifies
      → checks memo:requse_violation_(C, N, ViolDesc)
      → enriches assumption context with required_use_violation(…)
      → Conditions = [assumed(grouped_package_dependency(…)?{Ctx})]

6. Warning printer:
   → "REQUIRED_USE violation:"
   → "  cat/lib"
   → "  USE deps force:   [feature_z]"
   → "  violates: !feature_z"
   → "  required by: overlay://cat/app-1.0"
```

### Why Fail Instead of Assume?

If the entry rule produced an assumption directly (as was done
initially), the `grouped_package_dependency` rule would see a
successful proof — the assumption silently absorbs the failure.
The entire reprove mechanism (alternative candidates, parent narrowing,
learned constraint retries) would be **bypassed**.

By failing, the entry rule lets Prolog's backtracking explore:
- Other candidate versions (which may have different REQUIRED_USE)
- Parent narrowing (which may find a parent version without the
  conflicting USE dep)
- Reprove retries with learned constraints

Only after **all** alternatives are exhausted does the domain assumption
appear, carrying the REQUIRED_USE violation detail for the user.

### Memo Cache

The violation info is cached via `memo:requse_violation_/3` (thread-local,
survives backtracking since `assertz` is side-effecting).  It is:
- **Asserted** in the entry rule before failing
- **Consumed** in the `grouped_package_dependency` assumption path
  (retracted after enriching the context)
- **Cleared** by `memo:clear_caches/0` at the start of each proof run

## Entry Rule Structure

Both `:install` and `:run` entry rules follow the same pattern:

```
rule(Repo://Ebuild:Action?{Context}, Conditions) :-
  !,
  ( masked, \+ assuming(unmask) -> fail
  ; no accepted keyword, \+ assuming(keyword_acceptance) -> fail
  ; installed, \+ emptytree -> Conditions = []
  ; ctx_take_after…,
    ( % Normal proof
      query metadata,
      compute required_use + build_with_use,

      % REQUIRED_USE guard: fail to allow reprove
      ( \+ verify_required_use_with_bwu(…) ->
          cache violation, fail
      ; true
      ),

      % Build dependency model
      ( memoized_search(dependency model),
        order deps,
        Conditions = [selected_cn, constraints, download, deps…]
      ; % Model-computation fallback
        Conditions = [assumed(…:Action?{issue_with_model})]
      )
    )
  ).
```

The key design decisions:
- **Cut (`!`)** after the head: only one `:install` / `:run` rule clause
  exists per literal form; alternatives come from different candidates
  in `grouped_package_dependency`.
- **REQUIRED_USE violation → fail**: propagates to candidate selection
  for reprove.
- **Model-computation fallback → assume**: when the dependency model
  itself cannot be built (e.g. all `any_of_group` branches filtered),
  the entry rule assumes rather than failing, because this is a
  property of the ebuild metadata, not a candidate selection issue.

## Constraint Guards and Reprove Integration

The prover calls `rules:constraint_guard(Key, Constraints)` after
unifying each constraint term.  The guard may:
- Succeed silently (no conflict)
- Fail (causes backtracking within the current proof attempt)
- Throw `prover_reprove(…)` (triggers a retry with learned knowledge)

Key guard predicates in `candidate.pl`:
- `selected_cn_unique_or_reprove`: enforces CN-domain consistency
- `selected_cn_not_blocked_or_reprove`: enforces blocker constraints
- `maybe_request_cn_domain_reprove`: handles domain inconsistencies

## Assumption Printing Pipeline

```
Proof AVL
  │
  ├── rule(assumed(X))           → handle_assumption("domain")
  │     └── print_assumption_detail(rule(…))
  │           ├── required_use_violation in Ctx → REQUIRED_USE block
  │           ├── grouped_package_dependency    → reason label + detail
  │           ├── R://E:Action + issue_with_model → "Model unavailable"
  │           └── other                         → generic
  │
  └── assumed(rule(X))           → handle_assumption("cycle-break")
        └── cycle:print_cycle_explanation
```

### Assumption Type Classification (`assumption.pl`)

```prolog
required_use_violation(Ctx)    →  required_use_violation
grouped_dep:Action             →  non_existent_dependency
grouped_dep:Action?{Ctx}       →  (from assumption_reason in Ctx)
R://E:install                  →  assumed_installed
R://E:run                      →  assumed_running
blocker(…)                     →  blocker_assumption
issue_with_model in Ctx        →  issue_with_model
```

## Testing Learned Constraints

When testing changes to the reprove/assumption mechanism, always verify:

1. **Exit code**: 0 = no assumptions, 1 = cycle breaks only, 2 = domain
   assumptions
2. **"Total: N actions"** line present (proof completed)
3. **Count of "non-existent"** lines (domain assumptions)
4. **No "Unknown message"** or escaping exceptions
5. **Runtime** < 10 seconds for single targets (reprove retries can add
   latency; excessive retries suggest a learning bug)
6. **Overlay test suite**: `prover:test_stats(overlay)` should process
   all 364 ebuilds / 316 packages at 100%

## Source File Map

| File | Role |
|------|------|
| `Source/Pipeline/prover.pl` | Core proof engine, reprove retry loop, cycle detection, learned store |
| `Source/Domain/Gentoo/rules.pl` | Domain rules: entry rules, grouped deps, `rule(assumed(_),[])` |
| `Source/Domain/Gentoo/Rules/candidate.pl` | Candidate selection, reprove triggers, parent narrowing |
| `Source/Domain/Gentoo/Rules/heuristic.pl` | Reprove state management, reject accumulation |
| `Source/Domain/Gentoo/Rules/memo.pl` | Thread-local caches including `requse_violation_/3` |
| `Source/Domain/Gentoo/Rules/use.pl` | `verify_required_use_with_bwu`, `describe_required_use_violation` |
| `Source/Pipeline/Prover/explanation.pl` | `assumption_reason_for_grouped_dep` diagnosis |
| `Source/Pipeline/Prover/explainer.pl` | `term_ctx/2`, "why" queries |
| `Source/Pipeline/Printer/Plan/assumption.pl` | Assumption type classification |
| `Source/Pipeline/Printer/Plan/warning.pl` | Assumption detail rendering |
