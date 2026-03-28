# Portage-ng Test Overlay

A synthetic Portage overlay containing 80 test cases for the **portage-ng** package resolver. Each test category (`test01`–`test80`) contains a small set of ebuilds arranged to exercise a specific aspect of dependency resolution, from basic ordering through cycles, USE flags, slots, blockers, version constraints, and VDB-aware operations.

Every test includes:

- **`description.txt`** — detailed explanation of the scenario, dependency graph, and expected outcome.
- **`emerge-testNN.log`** — output of Gentoo `emerge -vp` on the same overlay.
- **`portage-ng-testNN.log`** — output of `portage-ng --pretend` on the same overlay.
- **SVG dependency graphs** — full, DEPEND, and RDEPEND visualisations in `Documentation/Tests/testNN/`.

Tests marked **XFAIL** are expected to fail and track known limitations or unimplemented features.

## Test Matrix

| # | Category | Purpose |
|--:|----------|---------|
| 01 | Basic | Simple dependency ordering |
| 02 | Basic | Version selection (2.0 over 1.0) |
| 03 | Cycle | Self-dependency (compile) |
| 04 | Cycle | Self-dependency (runtime) |
| 05 | Cycle | Self-dependency (compile + runtime) |
| 06 | Cycle | Indirect cycle (compile) |
| 07 | Cycle | Indirect cycle (runtime) |
| 08 | Cycle | Indirect cycle (compile + runtime) |
| 09 | Missing | Non-existent dep (compile) |
| 10 | Missing | Non-existent dep (runtime) |
| 11 | Missing | Non-existent dep (compile + runtime) |
| 12 | Keywords | Stable vs unstable keyword acceptance |
| 13 | Version | Pinpointed version `=pkg-ver` |
| 14 | USE cond | Positive USE conditional `lib? ( )` |
| 15 | USE cond | Negative USE conditional `!nolib? ( )` |
| 16 | Parser | Explicit all-of group `( )` syntax |
| 17 | Choice | Exactly-one-of `^^` (compile) |
| 18 | Choice | Exactly-one-of `^^` (runtime) |
| 19 | Choice | Exactly-one-of `^^` (compile + runtime) |
| 20 | Choice | Any-of `\|\|` (compile) |
| 21 | Choice | Any-of `\|\|` (runtime) |
| 22 | Choice | Any-of `\|\|` (compile + runtime) |
| 23 | Choice | At-most-one-of `??` (compile) |
| 24 | Choice | At-most-one-of `??` (runtime) |
| 25 | Choice | At-most-one-of `??` (compile + runtime) |
| 26 | Blocker | Strong blocker `!!` (runtime) + any-of |
| 27 | Blocker | Weak blocker `!` (runtime) + any-of |
| 28 | Blocker | Strong blocker `!!` (compile) + any-of |
| 29 | Blocker | Strong blocker `!!` (compile+runtime) + any-of |
| 30 | Blocker | Weak blocker `!` (compile) + any-of |
| 31 | Blocker | Weak blocker `!` (compile+runtime) + any-of |
| 32 | REQUIRED_USE | `^^` with conditional DEPEND |
| 33 | USE dep | Positive `[linux]` |
| 34 | USE dep | Negative `[-linux]` |
| 35 | USE dep | Equality `[linux=]` |
| 36 | USE dep | Chained equality `[linux=]` through lib |
| 37 | USE dep | Inverse equality `[!linux=]` |
| 38 | USE dep | Weak conditional `[linux?]` |
| 39 | USE dep | Negative weak `[-linux?]` |
| 40 | REQUIRED_USE | `\|\|` on standalone package |
| 41 | Slot | Explicit slot `:1` |
| 42 | Slot | Wildcard slot `:*` |
| 43 | Slot | Slot equality `:=` |
| 44 | Slot | Sub-slot `:1/A` |
| 45 | Conflict | Irreconcilable USE conflict via `^^` |
| 46 | Conflict | Deep diamond USE conflict |
| 47 | Cycle | Three-way dependency cycle |
| 48 | Conflict | Slot conflict (same slot, different versions) |
| 49 | Conflict | USE default `(+)` vs REQUIRED_USE |
| 50 | Transitive | Compile dep's RDEPEND must appear |
| 51 | Conflict | USE dep vs REQUIRED_USE contradiction |
| 52 | USE merge | Multiple USE flags on shared dep |
| 53 | USE merge | USE merge + conditional extra dep |
| 54 | Printer | Expanding USE flags output |
| 55 | Version | Constraint intersection (direct `>3` + `<6`) |
| 56 | Version | Constraint intersection via dep chains |
| 57 | Virtual | Virtual-style ebuild (explicit dep) |
| 58 | Virtual | PROVIDE-based virtual **(XFAIL)** |
| 59 | Regression | Any-of `\|\|` selection regression **(XFAIL)** |
| 60 | Blocker | Versioned soft blocker `!<pkg-ver` **(XFAIL)** |
| 61 | Cycle | Mutual recursion with bracketed USE |
| 62 | Cycle | Simple mutual cycle (termination) |
| 63 | Cycle | REQUIRED_USE loop reproducer (openmpi-style) |
| 64 | Cycle | USE-conditional churn reproducer (openmp-style) |
| 65 | Installed | `build_with_use` reinstall semantics |
| 66 | PDEPEND | Post-merge dependency resolution |
| 67 | BDEPEND | Build-only dependency (separate from DEPEND) |
| 68 | Multi-slot | Co-installation of same CN in different slots |
| 69 | Version | Operator `>=` (greater-or-equal) |
| 70 | Version | Operator `~` (revision match) |
| 71 | Fetchonly | Download-only action |
| 72 | IDEPEND | Install-time dependency |
| 73 | Update | Installed old version, newer available (VDB) |
| 74 | Downgrade | Installed newer, constraint forces older (VDB) |
| 75 | Reinstall | Installed same version, emptytree (VDB) |
| 76 | Newuse | Installed with wrong USE, rebuild needed (VDB) |
| 77 | Depclean | Unused package removal (VDB) |
| 78 | Onlydeps | Skip target, install deps only |
| 79 | PDEPEND | PDEPEND cycle (A needs B, B PDEPEND A) |
| 80 | Version | Operator `<=` (less-or-equal) |

---

## Test Cases

### Basic Dependency Resolution

#### test01 — Simple dependency ordering

**Category:** Basic

Four packages (`web`, `app`, `db`, `os`) with straightforward compile-time and runtime dependencies. The prover must order all packages correctly, placing `os-1.0` first (no unsatisfied deps), grouping `app-1.0` and `db-1.0` as parallelisable, and scheduling `web-1.0` last.

**Dependency graph:** [View](../../Documentation/Tests/test01/test01.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test01/emerge-test01.log) | [portage-ng](../../Documentation/Tests/test01/portage-ng-test01.log)

---

#### test02 — Version selection (2.0 over 1.0)

**Category:** Basic

Two versions of each package (1.0 and 2.0) with unversioned dependencies. The prover should prefer the latest available version when no constraints restrict the choice. The plan must contain only 2.0 packages.

**Dependency graph:** [View](../../Documentation/Tests/test02/test02.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test02/emerge-test02.log) | [portage-ng](../../Documentation/Tests/test02/portage-ng-test02.log)

---

#### test16 — Explicit all-of group `( )` syntax

**Category:** Parser

The `web-1.0` package wraps two runtime dependencies in an explicit all-of group: `( db-1.0 os-1.0 )`. In PMS this is semantically equivalent to a flat listing. The parser must handle the parenthesised form without treating it as a choice group. The result should match test01.

**Dependency graph:** [View](../../Documentation/Tests/test16/test16.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test16/emerge-test16.log) | [portage-ng](../../Documentation/Tests/test16/portage-ng-test16.log)

---

### Circular Dependencies

#### test03 — Self-dependency (compile)

**Category:** Cycle

The `os-1.0` package lists itself as a compile-time dependency, creating an immediate cycle. The prover must detect this and take a cycle-break assumption, yielding a verify step in the plan while still including all four packages.

**Dependency graph:** [View](../../Documentation/Tests/test03/test03.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test03/emerge-test03.log) | [portage-ng](../../Documentation/Tests/test03/portage-ng-test03.log)

---

#### test04 — Self-dependency (runtime)

**Category:** Cycle

Variation of test03 where the self-dependency is in RDEPEND. The `os-1.0` package lists itself as a runtime dependency. The prover takes a cycle-break assumption. Note that Gentoo emerge is less strict about runtime self-dependencies and may not report a circular dependency here.

**Dependency graph:** [View](../../Documentation/Tests/test04/test04.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test04/emerge-test04.log) | [portage-ng](../../Documentation/Tests/test04/portage-ng-test04.log)

---

#### test05 — Self-dependency (compile + runtime)

**Category:** Cycle

Combines test03 and test04. The `os-1.0` package lists itself in both DEPEND and RDEPEND, creating two self-referential cycles. The prover should take two cycle-break assumptions and produce verify steps for both.

**Dependency graph:** [View](../../Documentation/Tests/test05/test05.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test05/emerge-test05.log) | [portage-ng](../../Documentation/Tests/test05/portage-ng-test05.log)

---

#### test06 — Indirect cycle (compile)

**Category:** Cycle

The `os-1.0` package lists `web-1.0` as a compile-time dependency, while `web-1.0` depends on `os-1.0`, creating a two-node indirect cycle. The prover must detect the cycle, take an assumption to break it, and still produce a valid plan for all four packages.

**Dependency graph:** [View](../../Documentation/Tests/test06/test06.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test06/emerge-test06.log) | [portage-ng](../../Documentation/Tests/test06/portage-ng-test06.log)

---

#### test07 — Indirect cycle (runtime)

**Category:** Cycle

Variation of test06 where the indirect circular dependency is in RDEPEND. The `os-1.0` package lists `web-1.0` as a runtime dependency, creating a two-node runtime cycle.

**Dependency graph:** [View](../../Documentation/Tests/test07/test07.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test07/emerge-test07.log) | [portage-ng](../../Documentation/Tests/test07/portage-ng-test07.log)

---

#### test08 — Indirect cycle (compile + runtime)

**Category:** Cycle

Combines test06 and test07. The `os-1.0` package lists `web-1.0` as both a compile-time and runtime dependency, creating two indirect cycles. The prover should detect both and take two assumptions.

**Dependency graph:** [View](../../Documentation/Tests/test08/test08.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test08/emerge-test08.log) | [portage-ng](../../Documentation/Tests/test08/portage-ng-test08.log)

---

#### test47 — Three-way dependency cycle

**Category:** Cycle

A three-node cycle: `app-client` needs `api-docs` to compile, `api-docs` needs `app-server` at runtime, and `app-server` needs `app-client` at runtime. The prover must trace the full chain and take an assumption to break the loop.

**Dependency graph:** [View](../../Documentation/Tests/test47/test47.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test47/emerge-test47.log) | [portage-ng](../../Documentation/Tests/test47/portage-ng-test47.log)

---

#### test61 — Mutual recursion with bracketed USE

**Category:** Cycle

Packages `a` and `b` each depend on the other with a bracketed USE dependency (`[foo]`). The prover must terminate without unbounded `build_with_use` context growth, either by cycle-breaking or producing a finite plan.

**Dependency graph:** [View](../../Documentation/Tests/test61/test61.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test61/emerge-test61.log) | [portage-ng](../../Documentation/Tests/test61/portage-ng-test61.log)

---

#### test62 — Simple mutual cycle (termination)

**Category:** Cycle

A minimal mutual dependency cycle (`a -> b`, `b -> a`) without blockers, slots, or USE flags. This is a termination regression test ensuring that per-goal context growth (e.g. accumulating `self()` markers) does not defeat cycle detection and cause backtracking until timeout.

**Dependency graph:** [View](../../Documentation/Tests/test62/test62.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test62/emerge-test62.log) | [portage-ng](../../Documentation/Tests/test62/portage-ng-test62.log)

---

### Missing Dependencies

#### test09 — Non-existent dep (compile)

**Category:** Missing

The `os-1.0` package depends on a non-existent package in the compile scope. The prover should fail to find a candidate and take a domain assumption about the missing dependency. A plan is still produced based on the assumption.

**Dependency graph:** [View](../../Documentation/Tests/test09/test09.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test09/emerge-test09.log) | [portage-ng](../../Documentation/Tests/test09/portage-ng-test09.log)

---

#### test10 — Non-existent dep (runtime)

**Category:** Missing

Variation of test09 where the missing dependency (`notexists`) is in the RDEPEND scope. The prover should report the unsatisfiable runtime dependency and take a domain assumption.

**Dependency graph:** [View](../../Documentation/Tests/test10/test10.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test10/emerge-test10.log) | [portage-ng](../../Documentation/Tests/test10/portage-ng-test10.log)

---

#### test11 — Non-existent dep (compile + runtime)

**Category:** Missing

Combines test09 and test10. The `os-1.0` package has both a compile-time and runtime dependency on the non-existent package. The prover should correctly identify the missing dependency in both scopes.

**Dependency graph:** [View](../../Documentation/Tests/test11/test11.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test11/emerge-test11.log) | [portage-ng](../../Documentation/Tests/test11/portage-ng-test11.log)

---

### Keywords

#### test12 — Stable vs unstable keyword acceptance

**Category:** Keywords

Two versions of each package: 1.0 (stable `amd64`) and 2.0 (unstable `~amd64`). Without configuration to accept unstable keywords, the prover should reject the 2.0 versions and resolve using only stable 1.0 packages.

**Dependency graph:** [View](../../Documentation/Tests/test12/test12.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test12/emerge-test12.log) | [portage-ng](../../Documentation/Tests/test12/portage-ng-test12.log)

---

### Version Selection

#### test13 — Pinpointed version `=pkg-ver`

**Category:** Version

The `app-2.0` package explicitly requires `=db-2.0` using the `=` operator. Even though `db-1.0` is also available, the version constraint must be respected. The plan should include `app-2.0`, `db-2.0`, and `os-2.0`.

**Dependency graph:** [View](../../Documentation/Tests/test13/test13.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test13/emerge-test13.log) | [portage-ng](../../Documentation/Tests/test13/portage-ng-test13.log)

---

#### test55 — Constraint intersection (direct `>3` + `<6`)

**Category:** Version

The `app` package has two direct dependencies on `lib`: one requiring `>3.0` and another requiring `<6.0`. The prover must combine both constraints to select a version in the range (3.0, 6.0). With versions 1.0–8.0 available, `lib-5.0` should be selected as the latest valid candidate.

**Dependency graph:** [View](../../Documentation/Tests/test55/test55.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test55/emerge-test55.log) | [portage-ng](../../Documentation/Tests/test55/portage-ng-test55.log)

---

#### test56 — Constraint intersection via dep chains

**Category:** Version

Similar to test55, but the version constraints arrive through different dependency paths: `modulea` requires `lib >3.0` and `moduleb` requires `lib <6.0`. The prover must intersect constraints originating from separate branches of the dependency tree.

**Dependency graph:** [View](../../Documentation/Tests/test56/test56.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test56/emerge-test56.log) | [portage-ng](../../Documentation/Tests/test56/portage-ng-test56.log)

---

#### test69 — Operator `>=` (greater-or-equal)

**Category:** Version

The `app-1.0` package requires `>=lib-3.0`. With five library versions (1.0–5.0), versions 1.0 and 2.0 must be excluded. The prover should select `lib-5.0` as the latest valid candidate.

**Dependency graph:** [View](../../Documentation/Tests/test69/test69.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test69/emerge-test69.log) | [portage-ng](../../Documentation/Tests/test69/portage-ng-test69.log)

---

#### test70 — Operator `~` (revision match)

**Category:** Version

The `app-1.0` package depends on `~lib-2.0`, which should match `lib-2.0` and `lib-2.0-r1` (any revision of base version 2.0) but not `lib-3.0`. The prover should select `lib-2.0-r1` as the latest matching revision.

**Dependency graph:** [View](../../Documentation/Tests/test70/test70.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test70/emerge-test70.log) | [portage-ng](../../Documentation/Tests/test70/portage-ng-test70.log)

---

#### test80 — Operator `<=` (less-or-equal)

**Category:** Version

The `app-1.0` package requires `<=lib-3.0`. With five library versions (1.0–5.0), versions 4.0 and 5.0 must be excluded. The prover should select `lib-3.0` as the latest valid candidate.

**Dependency graph:** [View](../../Documentation/Tests/test80/test80.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test80/emerge-test80.log) | [portage-ng](../../Documentation/Tests/test80/portage-ng-test80.log)

---

### USE Conditional Dependencies

#### test14 — Positive USE conditional `lib? ( )`

**Category:** USE cond

The `app-1.0` package has `IUSE="lib"` and `DEPEND="lib? ( test14/lib )"`. The dependency on `lib-1.0` is only active when the `lib` USE flag is enabled. Without the flag, the dependency is skipped entirely.

**Dependency graph:** [View](../../Documentation/Tests/test14/test14.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test14/emerge-test14.log) | [portage-ng](../../Documentation/Tests/test14/portage-ng-test14.log)

---

#### test15 — Negative USE conditional `!nolib? ( )`

**Category:** USE cond

The `app-1.0` package has `IUSE="nolib"` and `DEPEND="!nolib? ( test15/lib )"`. The dependency on `lib-1.0` is active when the `nolib` flag is *disabled* (the default). Enabling `nolib` suppresses the dependency.

**Dependency graph:** [View](../../Documentation/Tests/test15/test15.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test15/emerge-test15.log) | [portage-ng](../../Documentation/Tests/test15/portage-ng-test15.log)

---

### Choice Groups

#### test17 — Exactly-one-of `^^` (compile)

**Category:** Choice

The `os-1.0` package has `DEPEND="^^ ( linux bsd windows )"`. The prover must select exactly one of the three alternatives. Any single choice yields a valid plan.

**Dependency graph:** [View](../../Documentation/Tests/test17/test17.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test17/emerge-test17.log) | [portage-ng](../../Documentation/Tests/test17/portage-ng-test17.log)

---

#### test18 — Exactly-one-of `^^` (runtime)

**Category:** Choice

Variation of test17 with the `^^` group in RDEPEND. The prover must select exactly one runtime alternative.

**Dependency graph:** [View](../../Documentation/Tests/test18/test18.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test18/emerge-test18.log) | [portage-ng](../../Documentation/Tests/test18/portage-ng-test18.log)

---

#### test19 — Exactly-one-of `^^` (compile + runtime)

**Category:** Choice

Combines test17 and test18: the `^^` group appears in both DEPEND and RDEPEND. The prover should select a single OS package that satisfies both scopes consistently.

**Dependency graph:** [View](../../Documentation/Tests/test19/test19.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test19/emerge-test19.log) | [portage-ng](../../Documentation/Tests/test19/portage-ng-test19.log)

---

#### test20 — Any-of `||` (compile)

**Category:** Choice

The `os-1.0` package has `DEPEND="|| ( linux bsd windows )"`. The prover must select at least one alternative. Backtracking over different realisations is possible.

**Dependency graph:** [View](../../Documentation/Tests/test20/test20.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test20/emerge-test20.log) | [portage-ng](../../Documentation/Tests/test20/portage-ng-test20.log)

---

#### test21 — Any-of `||` (runtime)

**Category:** Choice

Variation of test20 with the `||` group in RDEPEND. The prover must select at least one runtime alternative.

**Dependency graph:** [View](../../Documentation/Tests/test21/test21.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test21/emerge-test21.log) | [portage-ng](../../Documentation/Tests/test21/portage-ng-test21.log)

---

#### test22 — Any-of `||` (compile + runtime)

**Category:** Choice

Combines test20 and test21: the `||` group appears in both DEPEND and RDEPEND. The choices for compile and runtime do not have to be the same.

**Dependency graph:** [View](../../Documentation/Tests/test22/test22.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test22/emerge-test22.log) | [portage-ng](../../Documentation/Tests/test22/portage-ng-test22.log)

---

#### test23 — At-most-one-of `??` (compile)

**Category:** Choice

The `os-1.0` package has `DEPEND="?? ( linux bsd windows )"`. At most one of the three may be installed; installing none is also valid. The simplest resolution is to install none of the optional packages.

**Dependency graph:** [View](../../Documentation/Tests/test23/test23.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test23/emerge-test23.log) | [portage-ng](../../Documentation/Tests/test23/portage-ng-test23.log)

---

#### test24 — At-most-one-of `??` (runtime)

**Category:** Choice

Variation of test23 with the `??` group in RDEPEND. Installing none of the optional packages is valid.

**Dependency graph:** [View](../../Documentation/Tests/test24/test24.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test24/emerge-test24.log) | [portage-ng](../../Documentation/Tests/test24/portage-ng-test24.log)

---

#### test25 — At-most-one-of `??` (compile + runtime)

**Category:** Choice

Combines test23 and test24: the `??` group appears in both DEPEND and RDEPEND. The simplest valid resolution is installing none of the optional packages in both scopes.

**Dependency graph:** [View](../../Documentation/Tests/test25/test25.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test25/emerge-test25.log) | [portage-ng](../../Documentation/Tests/test25/portage-ng-test25.log)

---

### Blockers

#### test26 — Strong blocker `!!` (runtime) + any-of

**Category:** Blocker

The `app-1.0` package strongly blocks `!!windows-1.0` in RDEPEND. The `os-1.0` package has `DEPEND="|| ( linux bsd windows )"`. The prover must recognise that selecting `windows-1.0` would conflict with the strong blocker and steer the choice toward `linux-1.0` or `bsd-1.0`.

**Dependency graph:** [View](../../Documentation/Tests/test26/test26.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test26/emerge-test26.log) | [portage-ng](../../Documentation/Tests/test26/portage-ng-test26.log)

---

#### test27 — Weak blocker `!` (runtime) + any-of

**Category:** Blocker

The `app-1.0` package weakly blocks `!windows-1.0` in RDEPEND. Unlike the strong blocker in test26, a weak blocker is advisory: it signals that `windows-1.0` should be uninstalled if already present. The blocker is recorded as a domain assumption.

**Dependency graph:** [View](../../Documentation/Tests/test27/test27.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test27/emerge-test27.log) | [portage-ng](../../Documentation/Tests/test27/portage-ng-test27.log)

---

#### test28 — Strong blocker `!!` (compile) + any-of

**Category:** Blocker

Variation of test26 where the strong blocker `!!windows-1.0` is in the compile-time scope (DEPEND). The prover must avoid selecting `windows-1.0` for the any-of group.

**Dependency graph:** [View](../../Documentation/Tests/test28/test28.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test28/emerge-test28.log) | [portage-ng](../../Documentation/Tests/test28/portage-ng-test28.log)

---

#### test29 — Strong blocker `!!` (compile+runtime) + any-of

**Category:** Blocker

Combines test26 and test28. The `app-1.0` package strongly blocks `windows-1.0` in both DEPEND and RDEPEND. The prover must avoid `windows-1.0` regardless of which scope triggers the conflict.

**Dependency graph:** [View](../../Documentation/Tests/test29/test29.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test29/emerge-test29.log) | [portage-ng](../../Documentation/Tests/test29/portage-ng-test29.log)

---

#### test30 — Weak blocker `!` (compile) + any-of

**Category:** Blocker

Variation of test27 where the weak blocker `!windows-1.0` is in the compile-time scope (DEPEND). The blocker is recorded as a domain assumption. The any-of resolution may or may not select `windows-1.0`.

**Dependency graph:** [View](../../Documentation/Tests/test30/test30.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test30/emerge-test30.log) | [portage-ng](../../Documentation/Tests/test30/portage-ng-test30.log)

---

#### test31 — Weak blocker `!` (compile+runtime) + any-of

**Category:** Blocker

Combines test27 and test30. Weak blockers against `windows-1.0` in both DEPEND and RDEPEND. Both are recorded as domain assumptions.

**Dependency graph:** [View](../../Documentation/Tests/test31/test31.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test31/emerge-test31.log) | [portage-ng](../../Documentation/Tests/test31/portage-ng-test31.log)

---

#### test60 — Versioned soft blocker `!<pkg-ver` (XFAIL)

**Category:** Blocker

> **XFAIL** — expected to fail until versioned blocker steering is implemented.

The `app-1.0` package blocks `!<windows-2.0` (any version less than 2.0). The any-of group on `os-1.0` offers both `windows-1.0` and `windows-2.0`. The solver should steer toward `windows-2.0`, but currently handles the versioned blocker via assumptions.

**Dependency graph:** [View](../../Documentation/Tests/test60/test60.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test60/emerge-test60.log) | [portage-ng](../../Documentation/Tests/test60/portage-ng-test60.log)

---

### REQUIRED_USE

#### test32 — `^^` with conditional DEPEND

**Category:** REQUIRED_USE

The `os-1.0` package has `REQUIRED_USE="^^ ( linux darwin )"` and USE-conditional dependencies for each flag. The prover must satisfy the exactly-one-of constraint and then pull in the corresponding conditional dependency (either `linux-1.0` or `darwin-1.0`).

**Dependency graph:** [View](../../Documentation/Tests/test32/test32.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test32/emerge-test32.log) | [portage-ng](../../Documentation/Tests/test32/portage-ng-test32.log)

---

#### test40 — `||` on standalone package

**Category:** REQUIRED_USE

The `os-1.0` package has `REQUIRED_USE="|| ( linux darwin )"`. At least one of the two USE flags must be enabled. The prover should make a choice if none is configured, or fail if both are explicitly disabled.

**Dependency graph:** [View](../../Documentation/Tests/test40/test40.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test40/emerge-test40.log) | [portage-ng](../../Documentation/Tests/test40/portage-ng-test40.log)

---

### USE Dependency Propagation

#### test33 — Positive `[linux]`

**Category:** USE dep

The `app-1.0` package depends on `os[linux]`, requiring that `os-1.0` be built with the `linux` USE flag enabled. The prover must enforce this requirement when resolving the dependency.

**Dependency graph:** [View](../../Documentation/Tests/test33/test33.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test33/emerge-test33.log) | [portage-ng](../../Documentation/Tests/test33/portage-ng-test33.log)

---

#### test34 — Negative `[-linux]`

**Category:** USE dep

Inverse of test33. The `app-1.0` package depends on `os[-linux]`, requiring that `os-1.0` be built with the `linux` USE flag *disabled*. The prover must ensure the flag is off.

**Dependency graph:** [View](../../Documentation/Tests/test34/test34.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test34/emerge-test34.log) | [portage-ng](../../Documentation/Tests/test34/portage-ng-test34.log)

---

#### test35 — Equality `[linux=]`

**Category:** USE dep

The `app-1.0` package depends on `os[linux=]`. If `app` has `USE="linux"`, then `os` must also have `USE="linux"`. If `app` has `USE="-linux"`, then `os` must also have `USE="-linux"`. The flag state is bidirectionally tied.

**Dependency graph:** [View](../../Documentation/Tests/test35/test35.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test35/emerge-test35.log) | [portage-ng](../../Documentation/Tests/test35/portage-ng-test35.log)

---

#### test36 — Chained equality `[linux=]` through lib

**Category:** USE dep

The `linux=` USE propagation flows through a chain: `app -> lib[linux=] -> os[linux=]`. If `app` has `USE="linux"`, both `lib` and `os` must also have the flag enabled, testing multi-hop propagation.

**Dependency graph:** [View](../../Documentation/Tests/test36/test36.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test36/emerge-test36.log) | [portage-ng](../../Documentation/Tests/test36/portage-ng-test36.log)

---

#### test37 — Inverse equality `[!linux=]`

**Category:** USE dep

The `app-1.0` package depends on `os[!linux=]`. The `linux` flag on `os` must be the *inverse* of its setting on `app`. If `app` has `USE="linux"`, then `os` must have `USE="-linux"`, and vice versa.

**Dependency graph:** [View](../../Documentation/Tests/test37/test37.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test37/emerge-test37.log) | [portage-ng](../../Documentation/Tests/test37/portage-ng-test37.log)

---

#### test38 — Weak conditional `[linux?]`

**Category:** USE dep

The `app-1.0` package depends on `os[linux?]`. If `app` has `USE="linux"`, then `os` must also enable it. If `app` has `USE="-linux"`, the flag on `os` is unconstrained. This is a one-way implication.

**Dependency graph:** [View](../../Documentation/Tests/test38/test38.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test38/emerge-test38.log) | [portage-ng](../../Documentation/Tests/test38/portage-ng-test38.log)

---

#### test39 — Negative weak `[-linux?]`

**Category:** USE dep

The `app-1.0` package depends on `os[-linux?]`. If `app` has `USE="-linux"` (flag disabled), then `os` must also have it disabled. If `app` has `USE="linux"`, the flag on `os` is unconstrained.

**Dependency graph:** [View](../../Documentation/Tests/test39/test39.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test39/emerge-test39.log) | [portage-ng](../../Documentation/Tests/test39/portage-ng-test39.log)

---

### Slot Dependencies

#### test41 — Explicit slot `:1`

**Category:** Slot

The `app-1.0` package depends on `lib:1`. Even though `lib-2.0` (slot 2) is a higher version, only `lib-1.0` (slot 1) satisfies the slot constraint. The prover must select `lib-1.0`.

**Dependency graph:** [View](../../Documentation/Tests/test41/test41.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test41/emerge-test41.log) | [portage-ng](../../Documentation/Tests/test41/portage-ng-test41.log)

---

#### test42 — Wildcard slot `:*`

**Category:** Slot

The `app-1.0` package depends on `lib:*`, accepting any slot. The prover should follow the default behaviour and select the latest version (`lib-2.0` in slot 2).

**Dependency graph:** [View](../../Documentation/Tests/test42/test42.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test42/emerge-test42.log) | [portage-ng](../../Documentation/Tests/test42/portage-ng-test42.log)

---

#### test43 — Slot equality `:=`

**Category:** Slot

The `app-1.0` package has a compile dependency on `lib` and a runtime dependency on `lib:=`. The slot chosen at compile time (slot 2, via `lib-2.0`) must be the same slot used at runtime, ensuring ABI consistency.

**Dependency graph:** [View](../../Documentation/Tests/test43/test43.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test43/emerge-test43.log) | [portage-ng](../../Documentation/Tests/test43/portage-ng-test43.log)

---

#### test44 — Sub-slot `:1/A`

**Category:** Slot

The `app-1.0` package depends on `lib:1/A`. Three library versions exist: `lib-1.0` (slot 1/A), `lib-1.1` (slot 1/B), and `lib-2.0` (slot 2). Only `lib-1.0` matches the exact sub-slot requirement.

**Dependency graph:** [View](../../Documentation/Tests/test44/test44.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test44/emerge-test44.log) | [portage-ng](../../Documentation/Tests/test44/portage-ng-test44.log)

---

#### test68 — Co-installation of same CN in different slots

**Category:** Multi-slot

The `app-1.0` package requires both `lib:1` and `lib:2` simultaneously. Since different slots can coexist, both `lib-1.0` (slot 1) and `lib-2.0` (slot 2) must appear in the plan.

**Dependency graph:** [View](../../Documentation/Tests/test68/test68.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test68/emerge-test68.log) | [portage-ng](../../Documentation/Tests/test68/portage-ng-test68.log)

---

### Conflicts

#### test45 — Irreconcilable USE conflict via `^^`

**Category:** Conflict

The `os` package has `REQUIRED_USE="^^ ( linux darwin )"`. However, `liba` requires `os[linux]` and `libb` requires `os[darwin]`. Both cannot be enabled simultaneously due to the `^^` constraint. The prover should detect the irreconcilable conflict and fail.

**Dependency graph:** [View](../../Documentation/Tests/test45/test45.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test45/emerge-test45.log) | [portage-ng](../../Documentation/Tests/test45/portage-ng-test45.log)

---

#### test46 — Deep diamond USE conflict

**Category:** Conflict

A double-diamond dependency graph where `libc` requires `core-utils[feature_x]` and `libd` requires `core-utils[-feature_x]`. The contradictory USE requirements are hidden several layers deep. The prover must trace the full tree and identify the logical contradiction.

**Dependency graph:** [View](../../Documentation/Tests/test46/test46.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test46/emerge-test46.log) | [portage-ng](../../Documentation/Tests/test46/portage-ng-test46.log)

---

#### test48 — Slot conflict (same slot, different versions)

**Category:** Conflict

Two dependencies require different versions of `libmatrix` in the same slot: `libgraphics` needs `=libmatrix-1.0:1/A` and `libphysics` needs `=libmatrix-1.1:1/B`. Since a slot can only hold one version, this is an impossible condition and the prover must fail.

**Dependency graph:** [View](../../Documentation/Tests/test48/test48.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test48/emerge-test48.log) | [portage-ng](../../Documentation/Tests/test48/portage-ng-test48.log)

---

#### test49 — USE default `(+)` vs REQUIRED_USE

**Category:** Conflict

The `app-1.0` package depends on `libhelper[feature_z(+)]` (suggesting the flag be enabled by default), but `libhelper` has `REQUIRED_USE="!feature_z"` (explicitly forbidding the flag). The hard `REQUIRED_USE` constraint must override the soft default.

**Dependency graph:** [View](../../Documentation/Tests/test49/test49.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test49/emerge-test49.log) | [portage-ng](../../Documentation/Tests/test49/portage-ng-test49.log)

---

#### test51 — USE dep vs REQUIRED_USE contradiction

**Category:** Conflict

The `app-1.0` package depends on `os[linux]`, but `os-1.0` has `REQUIRED_USE="!linux"`. This is a direct, unsolvable contradiction: the dependency requires the flag, but the target package forbids it. The prover must fail immediately.

**Dependency graph:** [View](../../Documentation/Tests/test51/test51.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test51/emerge-test51.log) | [portage-ng](../../Documentation/Tests/test51/portage-ng-test51.log)

---

### Transitive Dependencies

#### test50 — Compile dep's RDEPEND must appear

**Category:** Transitive

The `app-1.0` has a compile dependency on `foo-1.0`, and `foo-1.0` has a runtime dependency on `bar-1.0`. The prover must recognise that `bar-1.0` is transitively required and include all three packages in the correct order: `bar`, `foo`, `app`.

**Dependency graph:** [View](../../Documentation/Tests/test50/test50.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test50/emerge-test50.log) | [portage-ng](../../Documentation/Tests/test50/portage-ng-test50.log)

---

### USE Flag Merging

#### test52 — Multiple USE flags on shared dep

**Category:** USE merge

Two packages (`liba` and `libb`) both depend on `os-1.0` but require different USE flags: `liba` needs `os[threads]` and `libb` needs `os[hardened]`. The prover must merge both requirements into a single `os-1.0` install with both flags enabled.

**Dependency graph:** [View](../../Documentation/Tests/test52/test52.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test52/emerge-test52.log) | [portage-ng](../../Documentation/Tests/test52/portage-ng-test52.log)

---

#### test53 — USE merge + conditional extra dep

**Category:** USE merge

Extends test52: after merging the `hardened` USE flag onto `os-1.0`, the conditional dependency `hardened? ( libhardened-1.0 )` must also be activated and pulled into the plan. Tests that late USE flag introduction triggers new conditional dependency evaluation.

**Dependency graph:** [View](../../Documentation/Tests/test53/test53.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test53/emerge-test53.log) | [portage-ng](../../Documentation/Tests/test53/portage-ng-test53.log)

---

### Printer / Output

#### test54 — Expanding USE flags output

**Category:** Printer

A single package (`app-1.0`) with multiple USE flags but no dependencies. Tests that the printer correctly formats and splits expanding USE flag output without errors.

**Dependency graph:** [View](../../Documentation/Tests/test54/test54.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test54/emerge-test54.log) | [portage-ng](../../Documentation/Tests/test54/portage-ng-test54.log)

---

### Virtuals

#### test57 — Virtual-style ebuild (explicit dep)

**Category:** Virtual

The `virtualsdk-1.0` ebuild acts as a virtual by explicitly depending on `linux-1.0` as its concrete provider. The prover must traverse the full chain (`os -> virtualsdk -> linux`) and include `linux-1.0` in the plan.

**Dependency graph:** [View](../../Documentation/Tests/test57/test57.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test57/emerge-test57.log) | [portage-ng](../../Documentation/Tests/test57/portage-ng-test57.log)

---

#### test58 — PROVIDE-based virtual (XFAIL)

**Category:** Virtual

> **XFAIL** — expected to fail until PROVIDE/provider resolution is implemented.

The `linux-1.0` package claims to PROVIDE `virtualsdk`, which has no standalone ebuild. The resolver must recognise that `linux-1.0` satisfies the virtual dependency through its PROVIDE declaration. This is a deprecated PMS mechanism.

**Dependency graph:** [View](../../Documentation/Tests/test58/test58.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test58/emerge-test58.log) | [portage-ng](../../Documentation/Tests/test58/portage-ng-test58.log)

---

### Regressions

#### test59 — Any-of `||` selection regression (XFAIL)

**Category:** Regression

> **XFAIL** — expected to fail; tracks a bug where `||` members can all be dropped from the model.

Structurally similar to test21 but with different package names (`data_fast`, `data_best`). Exists specifically to track the regression where the any-of group does not force the solver to select at least one alternative.

**Dependency graph:** [View](../../Documentation/Tests/test59/test59.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test59/emerge-test59.log) | [portage-ng](../../Documentation/Tests/test59/portage-ng-test59.log)

---

#### test63 — REQUIRED_USE loop reproducer (openmpi-style)

**Category:** Regression

Reproduces the prover timeout seen when packages pull `sys-cluster/openmpi`, where complex `REQUIRED_USE` mutual exclusion groups cause excessive backtracking. A minimal overlay-only reproducer to isolate the behaviour without the full portage tree.

**Dependency graph:** [View](../../Documentation/Tests/test63/test63.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test63/emerge-test63.log) | [portage-ng](../../Documentation/Tests/test63/portage-ng-test63.log)

---

#### test64 — USE-conditional churn reproducer (openmp-style)

**Category:** Regression

Reproduces the small backtracking/churn pattern observed for `llvm-runtimes/openmp`. The metadata includes IUSE flags, USE-gated dependencies, and REQUIRED_USE groups that can cause excessive proof retries. The prover must complete without timing out.

**Dependency graph:** [View](../../Documentation/Tests/test64/test64.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test64/emerge-test64.log) | [portage-ng](../../Documentation/Tests/test64/portage-ng-test64.log)

---

### Installed / VDB

#### test65 — `build_with_use` reinstall semantics

**Category:** Installed

Regression test for `rules:installed_entry_satisfies_build_with_use/2`. Verifies that an installed VDB entry cannot be treated as satisfying a dependency if incoming `build_with_use` requires a flag the installed package was not built with. Uses a synthetic `__portage_ng_test_flag__` against an installed package.

**Dependency graph:** [View](../../Documentation/Tests/test65/test65.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test65/emerge-test65.log) | [portage-ng](../../Documentation/Tests/test65/portage-ng-test65.log)

---

#### test73 — Update: installed old version, newer available (VDB)

**Category:** Update

The `lib-1.0` is simulated as installed via VDB, but `lib-2.0` is available. The prover should detect that an update is possible and trigger an `:update` action instead of `:install`.

**Dependency graph:** [View](../../Documentation/Tests/test73/test73.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test73/emerge-test73.log) | [portage-ng](../../Documentation/Tests/test73/portage-ng-test73.log)

---

#### test74 — Downgrade: installed newer, constraint forces older (VDB)

**Category:** Downgrade

The `lib-2.0` is installed but `app-1.0` requires exactly `=lib-1.0`. The prover must detect that a downgrade is needed and produce a downgrade action replacing the newer installed version.

**Dependency graph:** [View](../../Documentation/Tests/test74/test74.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test74/emerge-test74.log) | [portage-ng](../../Documentation/Tests/test74/portage-ng-test74.log)

---

#### test75 — Reinstall: installed same version, emptytree (VDB)

**Category:** Reinstall

The `os-1.0` is already installed but the emptytree flag forces re-proving. The prover should not skip the package as satisfied but instead include a reinstall action.

**Dependency graph:** [View](../../Documentation/Tests/test75/test75.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test75/emerge-test75.log) | [portage-ng](../../Documentation/Tests/test75/portage-ng-test75.log)

---

#### test76 — Newuse: installed with wrong USE, rebuild needed (VDB)

**Category:** Newuse

The `os-1.0` was installed with `USE="-linux"` but `app-1.0` requires `os[linux]`. The prover should detect the unsatisfied `build_with_use` requirement on the installed package and trigger a rebuild with the correct USE flags.

**Dependency graph:** [View](../../Documentation/Tests/test76/test76.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test76/emerge-test76.log) | [portage-ng](../../Documentation/Tests/test76/portage-ng-test76.log)

---

### PDEPEND

#### test66 — Post-merge dependency resolution

**Category:** PDEPEND

The `lib-1.0` package declares `plugin-1.0` as a PDEPEND. The plugin should be resolved *after* `lib`'s installation via the PDEPEND proof obligation mechanism, not as a prerequisite. All three packages (`app`, `lib`, `plugin`) should appear in the plan.

**Dependency graph:** [View](../../Documentation/Tests/test66/test66.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test66/emerge-test66.log) | [portage-ng](../../Documentation/Tests/test66/portage-ng-test66.log)

---

#### test79 — PDEPEND cycle (A needs B, B PDEPEND A)

**Category:** PDEPEND

The `server-1.0` has a runtime dependency on `client-1.0`, and `client-1.0` has a PDEPEND back on `server-1.0`. Since PDEPEND is resolved post-install, the cycle is naturally broken: server installs first, then client, and the PDEPEND obligation is already satisfied.

**Dependency graph:** [View](../../Documentation/Tests/test79/test79.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test79/emerge-test79.log) | [portage-ng](../../Documentation/Tests/test79/portage-ng-test79.log)

---

### BDEPEND

#### test67 — Build-only dependency (separate from DEPEND)

**Category:** BDEPEND

The `app-1.0` package requires `toolchain-1.0` only for building (BDEPEND), separate from its runtime dependency on `lib-1.0`. BDEPEND is resolved alongside DEPEND for the install phase but is semantically distinct (for the build host in cross-compilation scenarios).

**Dependency graph:** [View](../../Documentation/Tests/test67/test67.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test67/emerge-test67.log) | [portage-ng](../../Documentation/Tests/test67/portage-ng-test67.log)

---

### IDEPEND

#### test72 — Install-time dependency

**Category:** IDEPEND

The `app-1.0` package requires `installer-1.0` at install time (IDEPEND, an EAPI 8 feature). IDEPEND specifies packages needed during the install phase on the target system, as opposed to BDEPEND which targets the build system. Both packages should appear in the proof.

**Dependency graph:** [View](../../Documentation/Tests/test72/test72.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test72/emerge-test72.log) | [portage-ng](../../Documentation/Tests/test72/portage-ng-test72.log)

---

### Fetchonly

#### test71 — Download-only action

**Category:** Fetchonly

The dependency structure is identical to test01, but the entry point uses `:fetchonly` instead of `:run`. Only download actions should be produced — no install or run steps. All four packages should appear with fetchonly actions.

**Dependency graph:** [View](../../Documentation/Tests/test71/test71.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test71/emerge-test71.log) | [portage-ng](../../Documentation/Tests/test71/portage-ng-test71.log)

---

### Depclean

#### test77 — Unused package removal (VDB)

**Category:** Depclean

Three packages are installed: `app-1.0` depends on `os-1.0`, and `orphan-1.0` has no reverse dependencies. When run with `:depclean`, the prover should traverse the installed dependency graph and identify `orphan-1.0` as removable.

**Dependency graph:** [View](../../Documentation/Tests/test77/test77.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test77/emerge-test77.log) | [portage-ng](../../Documentation/Tests/test77/portage-ng-test77.log)

---

### Onlydeps

#### test78 — Skip target, install deps only

**Category:** Onlydeps

The dependency structure is identical to test01, but the target package (`web-1.0`) is proven with the `onlydeps_target` context flag. The target itself should be excluded from the install plan, while all of its dependencies (`app-1.0`, `db-1.0`, `os-1.0`) should still be resolved and included.

**Dependency graph:** [View](../../Documentation/Tests/test78/test78.svg)

**Output:** [emerge -vp](../../Documentation/Tests/test78/emerge-test78.log) | [portage-ng](../../Documentation/Tests/test78/portage-ng-test78.log)