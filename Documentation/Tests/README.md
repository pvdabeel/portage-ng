# Test Documentation

Documentation for the 80 overlay test cases exercising the portage-ng resolver.
Each test has a dependency graph, description, and captured output from both
`emerge -vp` and `portage-ng --pretend`.

The overlay repository itself is at [`Repository/Overlay/`](../../Repository/Overlay/).

## Test Matrix

| # | Category | Purpose |
|--:|----------|---------|
| [01](#test01) | Basic | Simple dependency ordering |
| [02](#test02) | Basic | Version selection (2.0 over 1.0) |
| [03](#test03) | Cycle | Self-dependency (compile) |
| [04](#test04) | Cycle | Self-dependency (runtime) |
| [05](#test05) | Cycle | Self-dependency (compile + runtime) |
| [06](#test06) | Cycle | Indirect cycle (compile) |
| [07](#test07) | Cycle | Indirect cycle (runtime) |
| [08](#test08) | Cycle | Indirect cycle (compile + runtime) |
| [09](#test09) | Missing | Non-existent dep (compile) |
| [10](#test10) | Missing | Non-existent dep (runtime) |
| [11](#test11) | Missing | Non-existent dep (compile + runtime) |
| [12](#test12) | Keywords | Stable vs unstable keyword acceptance |
| [13](#test13) | Version | Pinpointed version =pkg-ver |
| [14](#test14) | USE cond | Positive USE conditional lib? ( ) |
| [15](#test15) | USE cond | Negative USE conditional !nolib? ( ) |
| [16](#test16) | Parser | Explicit all-of group ( ) syntax |
| [17](#test17) | Choice | Exactly-one-of ^^ (compile) |
| [18](#test18) | Choice | Exactly-one-of ^^ (runtime) |
| [19](#test19) | Choice | Exactly-one-of ^^ (compile + runtime) |
| [20](#test20) | Choice | Any-of || (compile) |
| [21](#test21) | Choice | Any-of || (runtime) |
| [22](#test22) | Choice | Any-of || (compile + runtime) |
| [23](#test23) | Choice | At-most-one-of ?? (compile) |
| [24](#test24) | Choice | At-most-one-of ?? (runtime) |
| [25](#test25) | Choice | At-most-one-of ?? (compile + runtime) |
| [26](#test26) | Blocker | Strong blocker !! (runtime) + any-of |
| [27](#test27) | Blocker | Weak blocker ! (runtime) + any-of |
| [28](#test28) | Blocker | Strong blocker !! (compile) + any-of |
| [29](#test29) | Blocker | Strong blocker !! (compile+runtime) + any-of |
| [30](#test30) | Blocker | Weak blocker ! (compile) + any-of |
| [31](#test31) | Blocker | Weak blocker ! (compile+runtime) + any-of |
| [32](#test32) | REQUIRED_USE | ^^ with conditional DEPEND |
| [33](#test33) | USE dep | Positive [linux] |
| [34](#test34) | USE dep | Negative [-linux] |
| [35](#test35) | USE dep | Equality [linux=] |
| [36](#test36) | USE dep | Chained equality [linux=] through lib |
| [37](#test37) | USE dep | Inverse equality [!linux=] |
| [38](#test38) | USE dep | Weak conditional [linux?] |
| [39](#test39) | USE dep | Negative weak [-linux?] |
| [40](#test40) | REQUIRED_USE | \|\| on standalone package |
| [41](#test41) | Slot | Explicit slot :1 |
| [42](#test42) | Slot | Wildcard slot :* |
| [43](#test43) | Slot | Slot equality := |
| [44](#test44) | Slot | Sub-slot `:1/A` |
| [45](#test45) | Conflict | Irreconcilable USE conflict via ^^ |
| [46](#test46) | Conflict | Deep diamond USE conflict |
| [47](#test47) | Cycle | Three-way dependency cycle |
| [48](#test48) | Conflict | Slot conflict (same slot, different versions) |
| [49](#test49) | Conflict | USE default (+) vs REQUIRED_USE |
| [50](#test50) | Transitive | Compile dep's RDEPEND must appear |
| [51](#test51) | Conflict | USE dep vs REQUIRED_USE contradiction |
| [52](#test52) | USE merge | Multiple USE flags on shared dep |
| [53](#test53) | USE merge | USE merge + conditional extra dep |
| [54](#test54) | Printer | Expanding USE flags output |
| [55](#test55) | Version | Constraint intersection (direct >3 + <6) |
| [56](#test56) | Version | Constraint intersection via dep chains |
| [57](#test57) | Virtual | Virtual-style ebuild (explicit dep) |
| [58](#test58) | Virtual | PROVIDE-based virtual (XFAIL) **(XFAIL)** |
| [59](#test59) | Regression | Any-of || selection regression (XFAIL) **(XFAIL)** |
| [60](#test60) | Blocker | Versioned soft blocker !<pkg-ver (XFAIL) **(XFAIL)** |
| [61](#test61) | Cycle | Mutual recursion with bracketed USE |
| [62](#test62) | Cycle | Simple mutual cycle (termination) |
| [63](#test63) | Cycle | REQUIRED_USE loop reproducer (openmpi-style) |
| [64](#test64) | Cycle | USE-conditional churn reproducer (openmp-style) |
| [65](#test65) | Installed | build_with_use reinstall semantics |
| [66](#test66) | PDEPEND | Post-merge dependency resolution |
| [67](#test67) | BDEPEND | Build-only dependency (separate from DEPEND) |
| [68](#test68) | Multi-slot | Co-installation of same CN in different slots |
| [69](#test69) | Version | Operator >= (greater-or-equal) |
| [70](#test70) | Version | Operator ~ (revision match) |
| [71](#test71) | Fetchonly | Download-only action |
| [72](#test72) | IDEPEND | Install-time dependency |
| [73](#test73) | Update | Installed old version, newer available (VDB) |
| [74](#test74) | Downgrade | Installed newer, constraint forces older (VDB) |
| [75](#test75) | Reinstall | Installed same version, emptytree (VDB) |
| [76](#test76) | Newuse | Installed with wrong USE, rebuild needed (VDB) |
| [77](#test77) | Depclean | Unused package removal (VDB) |
| [78](#test78) | Onlydeps | Skip target, install deps only |
| [79](#test79) | PDEPEND | PDEPEND cycle (A needs B, B PDEPEND A) |
| [80](#test80) | Version | Operator <= (less-or-equal) |

---

## test01
**Basic** — Simple dependency ordering

This test case checks basic dependency resolution with both compile-time and
runtime dependencies. The prover must correctly order all four packages and
identify opportunities for parallel execution.

**Expected:** The prover should produce a valid plan installing all four packages. Packages with
no unsatisfied dependencies (os-1.0) should come first. Packages that share the
same set of resolved dependencies (app-1.0, db-1.0) can be grouped into a parallel
step. The final step installs web-1.0.

![test01](test01/test01.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.75 s (backtrack: 0/20).

[ebuild  N     ] test01/os-1.0::overlay  0 KiB
[ebuild  N     ] test01/db-1.0::overlay  0 KiB
[ebuild  N     ] test01/app-1.0::overlay  0 KiB
[ebuild  N     ] test01/web-1.0::overlay  0 KiB

Total: 4 packages (4 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test01/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test01/web-1.0
             │ download  overlay://test01/os-1.0
             │ download  overlay://test01/db-1.0
             │ download  overlay://test01/app-1.0

 └─step  2─┤ install   overlay://test01/os-1.0

 └─step  3─┤ run       overlay://test01/os-1.0

 └─step  4─┤ install   overlay://test01/db-1.0

 └─step  5─┤ run       overlay://test01/db-1.0

 └─step  6─┤ install   overlay://test01/app-1.0

 └─step  7─┤ run       overlay://test01/app-1.0

 └─step  8─┤ install   overlay://test01/web-1.0

 └─step  9─┤ run     overlay://test01/web-1.0

Total: 12 actions (4 downloads, 4 installs, 4 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test02
**Basic** — Version selection (2.0 over 1.0)

This test case checks that the prover selects the latest available version when
multiple versions exist and no version constraints are specified. All dependencies
are unversioned, so the prover should prefer version 2.0 over 1.0 for every
package.

**Expected:** The plan should contain only version 2.0 packages (os-2.0, db-2.0, app-2.0,
web-2.0). No version 1.0 packages should appear. If the proposed plan is not
accepted, the prover should backtrack over available versions, proposing
alternative plans.

![test02](test02/test02.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.74 s (backtrack: 0/20).

[ebuild  N     ] test02/os-2.0::overlay  0 KiB
[ebuild  N     ] test02/db-2.0::overlay  0 KiB
[ebuild  N     ] test02/app-2.0::overlay  0 KiB
[ebuild  N     ] test02/web-2.0::overlay  0 KiB

Total: 4 packages (4 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test02/web-2.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test02/web-2.0
             │ download  overlay://test02/os-2.0
             │ download  overlay://test02/db-2.0
             │ download  overlay://test02/app-2.0

 └─step  2─┤ install   overlay://test02/os-2.0

 └─step  3─┤ run       overlay://test02/os-2.0

 └─step  4─┤ install   overlay://test02/db-2.0

 └─step  5─┤ run       overlay://test02/db-2.0

 └─step  6─┤ install   overlay://test02/app-2.0

 └─step  7─┤ run       overlay://test02/app-2.0

 └─step  8─┤ install   overlay://test02/web-2.0

 └─step  9─┤ run     overlay://test02/web-2.0

Total: 12 actions (4 downloads, 4 installs, 4 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test03
**Cycle** — Self-dependency (compile)

This test case checks the prover's handling of a direct self-dependency in the
compile-time scope. The 'os-1.0' package lists itself as a compile-time dependency,
creating an immediate cycle. The prover must detect this cycle and take an
assumption to break it.

**Expected:** The prover should take a cycle-break assumption for os-1.0's compile dependency on
itself, yielding a verify step in the proposed plan. The plan should still include
all four packages.

![test03](test03/test03.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.22 s (backtrack: 1/20).



[ebuild  N     ] test03/web-1.0::overlay  0 KiB
[ebuild  N     ]  test03/app-1.0::overlay  0 KiB
[ebuild  N     ]   test03/db-1.0::overlay  0 KiB
[ebuild  N     ]    test03/os-1.0::overlay  0 KiB

Total: 4 packages (4 new), Size of downloads: 0 KiB

 * Error: circular dependencies:

(test03/os-1.0:0/0::overlay, ebuild scheduled for merge) depends on
 (test03/os-1.0:0/0::overlay, ebuild scheduled for merge) (buildtime)

 * Note that circular dependencies can often be avoided by temporarily
 * disabling USE flags that trigger optional dependencies.
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test03/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ verify  test03/os (assumed installed) 
             │ download  overlay://test03/web-1.0
             │ download  overlay://test03/os-1.0
             │ download  overlay://test03/db-1.0
             │ download  overlay://test03/app-1.0

 └─step  2─┤ install   overlay://test03/os-1.0

 └─step  3─┤ run       overlay://test03/os-1.0

 └─step  4─┤ install   overlay://test03/db-1.0

 └─step  5─┤ run       overlay://test03/db-1.0

 └─step  6─┤ install   overlay://test03/app-1.0

 └─step  7─┤ run       overlay://test03/app-1.0

 └─step  8─┤ install   overlay://test03/web-1.0

 └─step  9─┤ run     overlay://test03/web-1.0

Total: 12 actions (4 downloads, 4 installs, 4 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.


>>> Cycle breaks (prover)

  grouped_package_dependency(no,test03,os,[package_dependency(install,no,test03,os,none,version_none,[],[])]):install
```

</details>

---

## test04
**Cycle** — Self-dependency (runtime)

This test case is a variation of test03 where the self-dependency is in the runtime
scope (RDEPEND) instead of compile-time. The 'os-1.0' package lists itself as a
runtime dependency.

**Expected:** The prover should take a cycle-break assumption for os-1.0's runtime dependency on
itself, yielding a verify step in the proposed plan. Note that Gentoo emerge is
less strict about runtime self-dependencies and may not report circular
dependencies in this case.

![test04](test04/test04.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.78 s (backtrack: 0/20).

[ebuild  N     ] test04/os-1.0::overlay  0 KiB
[ebuild  N     ] test04/db-1.0::overlay  0 KiB
[ebuild  N     ] test04/app-1.0::overlay  0 KiB
[ebuild  N     ] test04/web-1.0::overlay  0 KiB

Total: 4 packages (4 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test04/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test04/web-1.0
             │ download  overlay://test04/os-1.0
             │ download  overlay://test04/db-1.0
             │ download  overlay://test04/app-1.0

 └─step  2─┤ install   overlay://test04/os-1.0

 └─step  3─┤ install   overlay://test04/db-1.0

 └─step  4─┤ run       overlay://test04/db-1.0

 └─step  5─┤ install   overlay://test04/app-1.0

 └─step  6─┤ run       overlay://test04/app-1.0

 └─step  7─┤ install   overlay://test04/web-1.0

 └─step  8─┤ run     overlay://test04/web-1.0

Total: 11 actions (4 downloads, 4 installs, 3 runs), grouped into 8 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test05
**Cycle** — Self-dependency (compile + runtime)

This test case combines test03 and test04. The 'os-1.0' package lists itself as
both a compile-time and runtime dependency, creating two self-referential cycles.

**Expected:** The prover should take two cycle-break assumptions: one for the compile-time
self-dependency and one for the runtime self-dependency. Both should yield verify
steps in the proposed plan.

![test05](test05/test05.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.21 s (backtrack: 1/20).



[ebuild  N     ] test05/web-1.0::overlay  0 KiB
[ebuild  N     ]  test05/app-1.0::overlay  0 KiB
[ebuild  N     ]   test05/db-1.0::overlay  0 KiB
[ebuild  N     ]    test05/os-1.0::overlay  0 KiB

Total: 4 packages (4 new), Size of downloads: 0 KiB

 * Error: circular dependencies:

(test05/os-1.0:0/0::overlay, ebuild scheduled for merge) depends on
 (test05/os-1.0:0/0::overlay, ebuild scheduled for merge) (buildtime)

 * Note that circular dependencies can often be avoided by temporarily
 * disabling USE flags that trigger optional dependencies.
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test05/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ verify  test05/os (assumed installed) 
             │ download  overlay://test05/web-1.0
             │ download  overlay://test05/os-1.0
             │ download  overlay://test05/db-1.0
             │ download  overlay://test05/app-1.0

 └─step  2─┤ install   overlay://test05/os-1.0

 └─step  3─┤ install   overlay://test05/db-1.0

 └─step  4─┤ run       overlay://test05/db-1.0

 └─step  5─┤ install   overlay://test05/app-1.0

 └─step  6─┤ run       overlay://test05/app-1.0

 └─step  7─┤ install   overlay://test05/web-1.0

 └─step  8─┤ run     overlay://test05/web-1.0

Total: 11 actions (4 downloads, 4 installs, 3 runs), grouped into 8 steps.
       0.00 Kb to be downloaded.


>>> Cycle breaks (prover)

  grouped_package_dependency(no,test05,os,[package_dependency(install,no,test05,os,none,version_none,[],[])]):install
```

</details>

---

## test06
**Cycle** — Indirect cycle (compile)

This test case checks the prover's handling of an indirect circular dependency in
the compile-time scope. The 'os-1.0' package lists 'web-1.0' as a compile-time
dependency, while 'web-1.0' in turn depends on 'os-1.0', creating a two-node
cycle.

**Expected:** The prover should detect the cycle and take an assumption to break it, yielding a
verify step in the proposed plan. All four packages should still appear in the
final plan.

![test06](test06/test06.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.19 s (backtrack: 1/20).



[ebuild  N     ] test06/web-1.0::overlay  0 KiB
[ebuild  N     ]  test06/app-1.0::overlay  0 KiB
[ebuild  N     ]   test06/db-1.0::overlay  0 KiB
[ebuild  N     ]    test06/os-1.0::overlay  0 KiB

Total: 4 packages (4 new), Size of downloads: 0 KiB

 * Error: circular dependencies:

(test06/os-1.0:0/0::overlay, ebuild scheduled for merge) depends on
 (test06/web-1.0:0/0::overlay, ebuild scheduled for merge) (buildtime)
  (test06/os-1.0:0/0::overlay, ebuild scheduled for merge) (buildtime)

 * Note that circular dependencies can often be avoided by temporarily
 * disabling USE flags that trigger optional dependencies.
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test06/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ verify  overlay://test06/web-1.0 (assumed installed)
             │ download  overlay://test06/web-1.0
             │ download  overlay://test06/os-1.0
             │ download  overlay://test06/db-1.0
             │ download  overlay://test06/app-1.0

 └─step  2─┤ install   overlay://test06/os-1.0

 └─step  3─┤ run       overlay://test06/os-1.0

 └─step  4─┤ install   overlay://test06/db-1.0

 └─step  5─┤ run       overlay://test06/db-1.0

 └─step  6─┤ install   overlay://test06/app-1.0

 └─step  7─┤ run       overlay://test06/app-1.0

 └─step  8─┤ install   overlay://test06/web-1.0

 └─step  9─┤ run     overlay://test06/web-1.0

Total: 12 actions (4 downloads, 4 installs, 4 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.


>>> Cycle breaks (prover)

  overlay://test06/web-1.0:install
```

</details>

---

## test07
**Cycle** — Indirect cycle (runtime)

This test case is a variation of test06 where the indirect circular dependency is
in the runtime scope (RDEPEND). The 'os-1.0' package lists 'web-1.0' as a runtime
dependency, creating a two-node runtime cycle.

**Expected:** The prover should detect the cycle and take an assumption to break it, yielding a
verify step in the proposed plan.

![test07](test07/test07.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.19 s (backtrack: 1/20).



[ebuild  N     ] test07/web-1.0::overlay  0 KiB
[ebuild  N     ]  test07/app-1.0::overlay  0 KiB
[ebuild  N     ]   test07/db-1.0::overlay  0 KiB
[ebuild  N     ]    test07/os-1.0::overlay  0 KiB

Total: 4 packages (4 new), Size of downloads: 0 KiB

 * Error: circular dependencies:

(test07/os-1.0:0/0::overlay, ebuild scheduled for merge) depends on
 (test07/web-1.0:0/0::overlay, ebuild scheduled for merge) (runtime)
  (test07/os-1.0:0/0::overlay, ebuild scheduled for merge) (buildtime)

 * Note that circular dependencies can often be avoided by temporarily
 * disabling USE flags that trigger optional dependencies.
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test07/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ verify  overlay://test07/web-1.0 (assumed running) 
             │ download  overlay://test07/web-1.0
             │ download  overlay://test07/os-1.0
             │ download  overlay://test07/db-1.0
             │ download  overlay://test07/app-1.0

 └─step  2─┤ install   overlay://test07/os-1.0

 └─step  3─┤ install   overlay://test07/web-1.0
             │ install   overlay://test07/app-1.0
             │ install   overlay://test07/db-1.0

 └─step  4─┤ run     overlay://test07/web-1.0
             │ run       overlay://test07/app-1.0
             │ run       overlay://test07/db-1.0

 └─step  5─┤ run       overlay://test07/os-1.0

Total: 12 actions (4 downloads, 4 installs, 4 runs), grouped into 5 steps.
       0.00 Kb to be downloaded.


>>> Cycle breaks (prover)

  overlay://test07/web-1.0:run
```

</details>

---

## test08
**Cycle** — Indirect cycle (compile + runtime)

This test case combines test06 and test07. The 'os-1.0' package lists 'web-1.0' as
both a compile-time and runtime dependency, creating two indirect cycles through
the dependency graph.

**Expected:** The prover should detect both cycles and take assumptions to break them, yielding
two verify steps in the proposed plan.

![test08](test08/test08.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.19 s (backtrack: 1/20).



[ebuild  N     ] test08/web-1.0::overlay  0 KiB
[ebuild  N     ]  test08/app-1.0::overlay  0 KiB
[ebuild  N     ]   test08/db-1.0::overlay  0 KiB
[ebuild  N     ]    test08/os-1.0::overlay  0 KiB

Total: 4 packages (4 new), Size of downloads: 0 KiB

 * Error: circular dependencies:

(test08/os-1.0:0/0::overlay, ebuild scheduled for merge) depends on
 (test08/web-1.0:0/0::overlay, ebuild scheduled for merge) (buildtime)
  (test08/os-1.0:0/0::overlay, ebuild scheduled for merge) (buildtime)

 * Note that circular dependencies can often be avoided by temporarily
 * disabling USE flags that trigger optional dependencies.
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test08/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ verify  overlay://test08/web-1.0 (assumed installed)
             │ verify  overlay://test08/web-1.0 (assumed running) 
             │ download  overlay://test08/web-1.0
             │ download  overlay://test08/os-1.0
             │ download  overlay://test08/db-1.0
             │ download  overlay://test08/app-1.0

 └─step  2─┤ install   overlay://test08/web-1.0
             │ install   overlay://test08/app-1.0
             │ install   overlay://test08/db-1.0

 └─step  3─┤ run     overlay://test08/web-1.0
             │ run       overlay://test08/app-1.0
             │ run       overlay://test08/db-1.0

 └─step  4─┤ install   overlay://test08/os-1.0

 └─step  5─┤ run       overlay://test08/os-1.0

Total: 12 actions (4 downloads, 4 installs, 4 runs), grouped into 5 steps.
       0.00 Kb to be downloaded.


>>> Cycle breaks (prover)

  overlay://test08/web-1.0:install
  overlay://test08/web-1.0:run
```

</details>

---

## test09
**Missing** — Non-existent dep (compile)

This test case checks the prover's ability to handle a missing dependency. The 'os-1.0' package depends on 'test09/notexists', which is not a real package available in the repository.

**Expected:** The prover should fail to find a candidate for the 'notexists' package and report that the dependency cannot be satisfied. This should result in a failed proof.

![test09](test09/test09.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.21 s (backtrack: 1/20).


emerge: there are no ebuilds to satisfy "test09/notexists".
(dependency required by "test09/os-1.0::overlay" [ebuild])
(dependency required by "test09/os" [argument])
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test09/os-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ verify  test09/notexists (non-existent, assumed installed)
             │ download  overlay://test09/os-1.0

 └─step  2─┤ install   overlay://test09/os-1.0

 └─step  3─┤ run     overlay://test09/os-1.0

Total: 3 actions (1 download, 1 install, 1 run), grouped into 3 steps.
       0.00 Kb to be downloaded.



Error The proof for your build plan contains domain assumptions. Please verify:


>>> Domain assumptions

- Missing install dependency: 
  test09/notexists

  required by: overlay://test09/os-1.0


>>> Bug report drafts (Gentoo Bugzilla)

---
Summary: overlay://test09/os-1.0: missing dependency on test09/notexists

Affected package: overlay://test09/os-1.0
Dependency: test09/notexists
Phases: [install]

Unsatisfiable constraint(s):
  test09/notexists-

Observed:
  portage-ng reports no available candidate satisfies the above constraint(s).

Potential fix (suggestion):
  Review dependency metadata in overlay://test09/os-1.0; constraint set: [constraint(none,,[])].
```

</details>

---

## test10
**Missing** — Non-existent dep (runtime)

This is a variation of test09. It checks for a missing dependency, but this time in the runtime (RDEPEND) scope. The 'os-1.0' package requires 'test10/notexists' to run.

**Expected:** The prover should fail to find the 'notexists' package and report the missing runtime dependency, leading to a failed proof.

![test10](test10/test10.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.22 s (backtrack: 1/20).


emerge: there are no ebuilds to satisfy "test10/notexists".
(dependency required by "test10/os-1.0::overlay" [ebuild])
(dependency required by "test10/os" [argument])
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test10/os-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ verify  test10/notexists (non-existent, assumed running)
             │ download  overlay://test10/os-1.0

 └─step  2─┤ install   overlay://test10/os-1.0

 └─step  3─┤ run     overlay://test10/os-1.0

Total: 3 actions (1 download, 1 install, 1 run), grouped into 3 steps.
       0.00 Kb to be downloaded.



Error The proof for your build plan contains domain assumptions. Please verify:


>>> Domain assumptions

- Missing run dependency: 
  test10/notexists

  required by: overlay://test10/os-1.0


>>> Bug report drafts (Gentoo Bugzilla)

---
Summary: overlay://test10/os-1.0: missing dependency on test10/notexists

Affected package: overlay://test10/os-1.0
Dependency: test10/notexists
Phases: [run]

Unsatisfiable constraint(s):
  test10/notexists-

Observed:
  portage-ng reports no available candidate satisfies the above constraint(s).

Potential fix (suggestion):
  Review dependency metadata in overlay://test10/os-1.0; constraint set: [constraint(none,,[])].
```

</details>

---

## test11
**Missing** — Non-existent dep (compile + runtime)

This test case combines test09 and test10. The 'os-1.0' package has both a compile-time and a runtime dependency on the non-existent 'test11/notexists' package.

**Expected:** The prover should fail because it cannot find the 'notexists' package. It should correctly identify the missing dependency in both scopes.

![test11](test11/test11.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.23 s (backtrack: 1/20).


emerge: there are no ebuilds to satisfy "test11/notexists".
(dependency required by "test11/os-1.0::overlay" [ebuild])
(dependency required by "test11/os" [argument])
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test11/os-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ verify  test11/notexists (non-existent, assumed running)
             │ verify  test11/notexists (non-existent, assumed installed)
             │ download  overlay://test11/os-1.0

 └─step  2─┤ install   overlay://test11/os-1.0

 └─step  3─┤ run     overlay://test11/os-1.0

Total: 3 actions (1 download, 1 install, 1 run), grouped into 3 steps.
       0.00 Kb to be downloaded.



Error The proof for your build plan contains domain assumptions. Please verify:


>>> Domain assumptions

- Missing install dependency: 
  test11/notexists

  required by: overlay://test11/os-1.0

- Missing run dependency: 
  test11/notexists

  required by: overlay://test11/os-1.0


>>> Bug report drafts (Gentoo Bugzilla)

---
Summary: overlay://test11/os-1.0: missing dependency on test11/notexists

Affected package: overlay://test11/os-1.0
Dependency: test11/notexists
Phases: [install,run]

Unsatisfiable constraint(s):
  test11/notexists-

Observed:
  portage-ng reports no available candidate satisfies the above constraint(s).

Potential fix (suggestion):
  Review dependency metadata in overlay://test11/os-1.0; constraint set: [constraint(none,,[])].
```

</details>

---

## test12
**Keywords** — Stable vs unstable keyword acceptance

This test case examines the prover's handling of package keywords and stability. The latest (2.0) versions of the packages are marked as unstable. Without a specific configuration to accept these unstable keywords, the package manager should not select them.

**Expected:** Assuming a default configuration that only allows stable packages, the prover should reject the 2.0 versions and instead resolve the dependencies using the stable 1.0 versions. The final proof should be for app-1.0, db-1.0, and os-1.0.

![test12](test12/test12.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.75 s (backtrack: 0/20).

[ebuild  N     ] test12/os-2.0::overlay  0 KiB
[ebuild  N     ] test12/db-2.0::overlay  0 KiB
[ebuild  N     ] test12/app-2.0::overlay  0 KiB
[ebuild  N     ] test12/web-2.0::overlay  0 KiB

Total: 4 packages (4 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test12/web-2.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test12/web-2.0
             │ download  overlay://test12/os-2.0
             │ download  overlay://test12/db-2.0
             │ download  overlay://test12/app-2.0

 └─step  2─┤ install   overlay://test12/os-2.0

 └─step  3─┤ run       overlay://test12/os-2.0

 └─step  4─┤ install   overlay://test12/db-2.0

 └─step  5─┤ run       overlay://test12/db-2.0

 └─step  6─┤ install   overlay://test12/app-2.0

 └─step  7─┤ run       overlay://test12/app-2.0

 └─step  8─┤ install   overlay://test12/web-2.0

 └─step  9─┤ run     overlay://test12/web-2.0

Total: 12 actions (4 downloads, 4 installs, 4 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test13
**Version** — Pinpointed version =pkg-ver

This test case introduces a specific version constraint. The 'app-2.0' package explicitly requires 'db-2.0' (using the '=' operator), even though a 'db-1.0' is also available.

**Expected:** The prover must respect the version constraint. It should select 'db-2.0' and then proceed to resolve the rest of the dependencies, selecting the latest available versions for other packages like 'os-2.0'. The final proof should be for app-2.0, db-2.0, and os-2.0.

![test13](test13/test13.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.74 s (backtrack: 0/20).

[ebuild  N     ] test13/os-2.0::overlay  0 KiB
[ebuild  N     ] test13/db-2.0::overlay  0 KiB
[ebuild  N     ] test13/app-2.0::overlay  0 KiB
[ebuild  N     ] test13/web-2.0::overlay  0 KiB

Total: 4 packages (4 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test13/web-2.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test13/web-2.0
             │ download  overlay://test13/os-2.0
             │ download  overlay://test13/db-2.0
             │ download  overlay://test13/app-2.0

 └─step  2─┤ install   overlay://test13/os-2.0

 └─step  3─┤ run       overlay://test13/os-2.0

 └─step  4─┤ install   overlay://test13/db-2.0

 └─step  5─┤ run       overlay://test13/db-2.0

 └─step  6─┤ install   overlay://test13/app-2.0

 └─step  7─┤ run       overlay://test13/app-2.0

 └─step  8─┤ install   overlay://test13/web-2.0

 └─step  9─┤ run     overlay://test13/web-2.0

Total: 12 actions (4 downloads, 4 installs, 4 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test14
**USE cond** — Positive USE conditional lib? ( )

This test case evaluates the handling of USE conditional dependencies. The dependency on 'lib-1.0' is only active if the 'lib' USE flag is enabled for the 'app-1.0' package.

**Expected:** - If the user proves 'app-1.0' without enabling the 'lib' flag, the proof should succeed, and 'lib-1.0' should not be included in the dependency graph.
- If the user proves 'app-1.0' and enables the 'lib' flag (e.g., via configuration), the proof should succeed, and 'lib-1.0' should be correctly included and installed.

![test14](test14/test14.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.75 s (backtrack: 0/20).

[ebuild  N     ] test14/os-1.0::overlay  0 KiB
[ebuild  N     ] test14/db-1.0::overlay  0 KiB
[ebuild  N     ] test14/app-1.0::overlay  USE="-lib" 0 KiB
[ebuild  N     ] test14/web-1.0::overlay  0 KiB

Total: 4 packages (4 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test14/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test14/web-1.0
             │ download  overlay://test14/os-1.0
             │ download  overlay://test14/db-1.0
             │ download  overlay://test14/app-1.0

 └─step  2─┤ install   overlay://test14/os-1.0

 └─step  3─┤ run       overlay://test14/os-1.0

 └─step  4─┤ install   overlay://test14/db-1.0

 └─step  5─┤ run       overlay://test14/db-1.0

 └─step  6─┤ install   overlay://test14/app-1.0
             │           └─ conf ─┤ USE = "-lib"

 └─step  7─┤ run       overlay://test14/app-1.0

 └─step  8─┤ install   overlay://test14/web-1.0

 └─step  9─┤ run     overlay://test14/web-1.0

Total: 12 actions (4 downloads, 4 installs, 4 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test15
**USE cond** — Negative USE conditional !nolib? ( )

This test case is similar to test14 but uses a negative USE conditional. The dependency is triggered by the absence of a USE flag.

**Expected:** - If the 'nolib' flag is enabled for app-1.0, the proof should succeed without pulling in 'lib-1.0'.
- If the 'nolib' flag is not set (i.e., disabled by default), the proof should succeed and correctly include 'lib-1.0' as a dependency.

![test15](test15/test15.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.75 s (backtrack: 0/20).

[ebuild  N     ] test15/os-1.0::overlay  0 KiB
[ebuild  N     ] test15/db-1.0::overlay  0 KiB
[ebuild  N     ] test15/lib-1.0::overlay  0 KiB
[ebuild  N     ] test15/app-1.0::overlay  USE="-nolib" 0 KiB
[ebuild  N     ] test15/web-1.0::overlay  0 KiB

Total: 5 packages (5 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test15/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test15/web-1.0
             │ download  overlay://test15/os-1.0
             │ download  overlay://test15/lib-1.0
             │ download  overlay://test15/db-1.0
             │ download  overlay://test15/app-1.0

 └─step  2─┤ install   overlay://test15/os-1.0

 └─step  3─┤ run       overlay://test15/os-1.0

 └─step  4─┤ install   overlay://test15/db-1.0
             │ install   overlay://test15/lib-1.0

 └─step  5─┤ run       overlay://test15/db-1.0

 └─step  6─┤ install   overlay://test15/app-1.0
             │           └─ conf ─┤ USE = "-nolib"

 └─step  7─┤ run       overlay://test15/app-1.0

 └─step  8─┤ install   overlay://test15/web-1.0

 └─step  9─┤ run     overlay://test15/web-1.0

Total: 14 actions (5 downloads, 5 installs, 4 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test16
**Parser** — Explicit all-of group ( ) syntax

This test case checks the parser's handling of explicit all-of group
parenthesization in dependency specifications. The 'web-1.0' package wraps two of
its runtime dependencies in an explicit all-of group: ( db-1.0 os-1.0 ). In PMS,
this is semantically equivalent to listing them flat (as in test01), but the parser
must correctly handle the parenthesized form without treating it as a choice group.

**Expected:** The prover should successfully resolve the dependencies and generate the same valid
proof as test01. The all-of group should be transparent to the resolver: app-1.0,
db-1.0, and os-1.0 should all appear in the plan in the correct order.

![test16](test16/test16.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.74 s (backtrack: 0/20).

[ebuild  N     ] test16/os-1.0::overlay  0 KiB
[ebuild  N     ] test16/db-1.0::overlay  0 KiB
[ebuild  N     ] test16/app-1.0::overlay  0 KiB
[ebuild  N     ] test16/web-1.0::overlay  0 KiB

Total: 4 packages (4 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test16/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test16/web-1.0
             │ download  overlay://test16/os-1.0
             │ download  overlay://test16/db-1.0
             │ download  overlay://test16/app-1.0

 └─step  2─┤ install   overlay://test16/os-1.0

 └─step  3─┤ run       overlay://test16/os-1.0

 └─step  4─┤ install   overlay://test16/db-1.0

 └─step  5─┤ run       overlay://test16/db-1.0

 └─step  6─┤ install   overlay://test16/app-1.0

 └─step  7─┤ run       overlay://test16/app-1.0

 └─step  8─┤ install   overlay://test16/web-1.0

 └─step  9─┤ run     overlay://test16/web-1.0

Total: 12 actions (4 downloads, 4 installs, 4 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test17
**Choice** — Exactly-one-of ^^ (compile)

This test case evaluates the prover's handling of an 'exactly-one-of' dependency group (^^). The 'os-1.0' package requires that exactly one of the three OS packages be installed.

**Expected:** The prover should recognize the choice and select one of the available options (e.g., linux-1.0) to satisfy the dependency. Since there are no other constraints, any of the three choices should lead to a valid proof. The final plan will include app-1.0, os-1.0, and one of the three OS packages.

![test17](test17/test17.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.25 s (backtrack: 1/20).


!!! All ebuilds that could satisfy "test17/os" have been masked.
!!! One of the following masked packages is required to complete your request:
- test17/os-1.0::overlay (masked by: invalid: DEPEND: Invalid atom (^^), token 1)

(dependency required by "test17/web-1.0::overlay" [ebuild])
(dependency required by "test17/web" [argument])
For more information, see the MASKED PACKAGES section in the emerge
man page or refer to the Gentoo Handbook.
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test17/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test17/web-1.0
             │ download  overlay://test17/os-1.0
             │ download  overlay://test17/linux-1.0
             │ download  overlay://test17/db-1.0
             │ download  overlay://test17/app-1.0

 └─step  2─┤ install   overlay://test17/os-1.0
             │ install   overlay://test17/linux-1.0

 └─step  3─┤ run       overlay://test17/os-1.0

 └─step  4─┤ install   overlay://test17/db-1.0

 └─step  5─┤ run       overlay://test17/db-1.0

 └─step  6─┤ install   overlay://test17/app-1.0

 └─step  7─┤ run       overlay://test17/app-1.0

 └─step  8─┤ install   overlay://test17/web-1.0

 └─step  9─┤ run     overlay://test17/web-1.0

Total: 14 actions (5 downloads, 5 installs, 4 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test18
**Choice** — Exactly-one-of ^^ (runtime)

This test case is a variation of test17, but the 'exactly-one-of' dependency is in the runtime scope (RDEPEND).

**Expected:** The prover should handle the runtime choice group correctly, select one of the OS options, and generate a valid proof.

![test18](test18/test18.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  .... done!
Dependency resolution took 1.22 s (backtrack: 1/20).


!!! All ebuilds that could satisfy "test18/os" have been masked.
!!! One of the following masked packages is required to complete your request:
- test18/os-1.0::overlay (masked by: invalid: RDEPEND: Invalid atom (^^), token 1)

(dependency required by "test18/web-1.0::overlay" [ebuild])
(dependency required by "test18/web" [argument])
For more information, see the MASKED PACKAGES section in the emerge
man page or refer to the Gentoo Handbook.
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test18/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test18/web-1.0
             │ download  overlay://test18/os-1.0
             │ download  overlay://test18/linux-1.0
             │ download  overlay://test18/db-1.0
             │ download  overlay://test18/app-1.0

 └─step  2─┤ install   overlay://test18/os-1.0
             │ install   overlay://test18/linux-1.0

 └─step  3─┤ run       overlay://test18/linux-1.0

 └─step  4─┤ run       overlay://test18/os-1.0

 └─step  5─┤ install   overlay://test18/db-1.0

 └─step  6─┤ run       overlay://test18/db-1.0

 └─step  7─┤ install   overlay://test18/app-1.0

 └─step  8─┤ run       overlay://test18/app-1.0

 └─step  9─┤ install   overlay://test18/web-1.0

 └─step 10─┤ run     overlay://test18/web-1.0

Total: 15 actions (5 downloads, 5 installs, 5 runs), grouped into 10 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test19
**Choice** — Exactly-one-of ^^ (compile + runtime)

This test case combines test17 and test18. The 'os-1.0' package has the same 'exactly-one-of' choice group in both its compile-time and runtime dependencies.

**Expected:** The prover should select a single OS package that satisfies both the compile-time and runtime requirements. For example, if it chooses 'linux-1.0' for the compile dependency, it must also use 'linux-1.0' for the runtime dependency. The proof should be valid.

![test19](test19/test19.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.23 s (backtrack: 1/20).


!!! All ebuilds that could satisfy "test19/os" have been masked.
!!! One of the following masked packages is required to complete your request:
- test19/os-1.0::overlay (masked by: invalid: DEPEND: Invalid atom (^^), token 1, invalid: RDEPEND: Invalid atom (^^), token 1)

(dependency required by "test19/web-1.0::overlay" [ebuild])
(dependency required by "test19/web" [argument])
For more information, see the MASKED PACKAGES section in the emerge
man page or refer to the Gentoo Handbook.
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test19/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test19/web-1.0
             │ download  overlay://test19/os-1.0
             │ download  overlay://test19/linux-1.0
             │ download  overlay://test19/db-1.0
             │ download  overlay://test19/app-1.0

 └─step  2─┤ install   overlay://test19/linux-1.0

 └─step  3─┤ run       overlay://test19/linux-1.0

 └─step  4─┤ install   overlay://test19/os-1.0

 └─step  5─┤ run       overlay://test19/os-1.0

 └─step  6─┤ install   overlay://test19/db-1.0

 └─step  7─┤ run       overlay://test19/db-1.0

 └─step  8─┤ install   overlay://test19/app-1.0

 └─step  9─┤ run       overlay://test19/app-1.0

 └─step 10─┤ install   overlay://test19/web-1.0

 └─step 11─┤ run     overlay://test19/web-1.0

Total: 15 actions (5 downloads, 5 installs, 5 runs), grouped into 11 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test20
**Choice** — Any-of || (compile)

This test case evaluates the prover's handling of an 'any-of' dependency group (||). The 'os-1.0' package requires that at least one of the three OS packages be installed.

**Expected:** The prover should recognize the choice and select one of the available options to satisfy the dependency. Since there are no other constraints, any of the three choices should lead to a valid proof.

![test20](test20/test20.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.74 s (backtrack: 0/20).

[ebuild  N     ] test20/linux-1.0::overlay  0 KiB
[ebuild  N     ] test20/os-1.0::overlay  0 KiB
[ebuild  N     ] test20/db-1.0::overlay  0 KiB
[ebuild  N     ] test20/app-1.0::overlay  0 KiB
[ebuild  N     ] test20/web-1.0::overlay  0 KiB

Total: 5 packages (5 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test20/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test20/web-1.0
             │ download  overlay://test20/os-1.0
             │ download  overlay://test20/linux-1.0
             │ download  overlay://test20/db-1.0
             │ download  overlay://test20/app-1.0

 └─step  2─┤ install   overlay://test20/os-1.0
             │ install   overlay://test20/linux-1.0

 └─step  3─┤ run       overlay://test20/os-1.0

 └─step  4─┤ install   overlay://test20/db-1.0

 └─step  5─┤ run       overlay://test20/db-1.0

 └─step  6─┤ install   overlay://test20/app-1.0

 └─step  7─┤ run       overlay://test20/app-1.0

 └─step  8─┤ install   overlay://test20/web-1.0

 └─step  9─┤ run     overlay://test20/web-1.0

Total: 14 actions (5 downloads, 5 installs, 4 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test21
**Choice** — Any-of || (runtime)

This is a variation of test20, with the 'any-of' dependency group in the runtime scope (RDEPEND).

**Expected:** The prover should handle the runtime choice group correctly, select one of the OS options, and generate a valid proof.

![test21](test21/test21.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.75 s (backtrack: 0/20).

[ebuild  N     ] test21/linux-1.0::overlay  0 KiB
[ebuild  N     ] test21/os-1.0::overlay  0 KiB
[ebuild  N     ] test21/db-1.0::overlay  0 KiB
[ebuild  N     ] test21/app-1.0::overlay  0 KiB
[ebuild  N     ] test21/web-1.0::overlay  0 KiB

Total: 5 packages (5 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test21/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test21/web-1.0
             │ download  overlay://test21/os-1.0
             │ download  overlay://test21/linux-1.0
             │ download  overlay://test21/db-1.0
             │ download  overlay://test21/app-1.0

 └─step  2─┤ install   overlay://test21/os-1.0
             │ install   overlay://test21/linux-1.0

 └─step  3─┤ run       overlay://test21/linux-1.0

 └─step  4─┤ run       overlay://test21/os-1.0

 └─step  5─┤ install   overlay://test21/db-1.0

 └─step  6─┤ run       overlay://test21/db-1.0

 └─step  7─┤ install   overlay://test21/app-1.0

 └─step  8─┤ run       overlay://test21/app-1.0

 └─step  9─┤ install   overlay://test21/web-1.0

 └─step 10─┤ run     overlay://test21/web-1.0

Total: 15 actions (5 downloads, 5 installs, 5 runs), grouped into 10 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test22
**Choice** — Any-of || (compile + runtime)

This test case combines test20 and test21. The 'os-1.0' package has the same 'any-of' choice group in both its compile-time and runtime dependencies.

**Expected:** The prover can choose any of the OS packages to satisfy the compile-time dependency and any of the OS packages to satisfy the runtime dependency. They do not have to be the same. The proof should be valid.

![test22](test22/test22.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.74 s (backtrack: 0/20).

[ebuild  N     ] test22/linux-1.0::overlay  0 KiB
[ebuild  N     ] test22/os-1.0::overlay  0 KiB
[ebuild  N     ] test22/db-1.0::overlay  0 KiB
[ebuild  N     ] test22/app-1.0::overlay  0 KiB
[ebuild  N     ] test22/web-1.0::overlay  0 KiB

Total: 5 packages (5 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test22/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test22/web-1.0
             │ download  overlay://test22/os-1.0
             │ download  overlay://test22/linux-1.0
             │ download  overlay://test22/db-1.0
             │ download  overlay://test22/app-1.0

 └─step  2─┤ install   overlay://test22/linux-1.0

 └─step  3─┤ run       overlay://test22/linux-1.0

 └─step  4─┤ install   overlay://test22/os-1.0

 └─step  5─┤ run       overlay://test22/os-1.0

 └─step  6─┤ install   overlay://test22/db-1.0

 └─step  7─┤ run       overlay://test22/db-1.0

 └─step  8─┤ install   overlay://test22/app-1.0

 └─step  9─┤ run       overlay://test22/app-1.0

 └─step 10─┤ install   overlay://test22/web-1.0

 └─step 11─┤ run     overlay://test22/web-1.0

Total: 15 actions (5 downloads, 5 installs, 5 runs), grouped into 11 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test23
**Choice** — At-most-one-of ?? (compile)

This test case evaluates the prover's handling of an 'at-most-one-of' dependency group (??). The 'os-1.0' package requires that at most one of the three OS packages be installed. This also means that installing *none* of them is a valid resolution.

**Expected:** The prover should satisfy the dependency by choosing to install nothing from the group, as this is the simplest path. A valid proof should be generated for app-1.0 and os-1.0, without any of the optional OS packages.

![test23](test23/test23.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.21 s (backtrack: 1/20).


!!! All ebuilds that could satisfy "test23/os" have been masked.
!!! One of the following masked packages is required to complete your request:
- test23/os-1.0::overlay (masked by: invalid: DEPEND: USE flag '?' referenced in conditional '??' is not in IUSE)

(dependency required by "test23/web-1.0::overlay" [ebuild])
(dependency required by "test23/web" [argument])
For more information, see the MASKED PACKAGES section in the emerge
man page or refer to the Gentoo Handbook.
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test23/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test23/web-1.0
             │ download  overlay://test23/os-1.0
             │ download  overlay://test23/linux-1.0
             │ download  overlay://test23/db-1.0
             │ download  overlay://test23/app-1.0

 └─step  2─┤ install   overlay://test23/os-1.0
             │ install   overlay://test23/linux-1.0

 └─step  3─┤ run       overlay://test23/os-1.0

 └─step  4─┤ install   overlay://test23/db-1.0

 └─step  5─┤ run       overlay://test23/db-1.0

 └─step  6─┤ install   overlay://test23/app-1.0

 └─step  7─┤ run       overlay://test23/app-1.0

 └─step  8─┤ install   overlay://test23/web-1.0

 └─step  9─┤ run     overlay://test23/web-1.0

Total: 14 actions (5 downloads, 5 installs, 4 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test24
**Choice** — At-most-one-of ?? (runtime)

This is a variation of test23, with the 'at-most-one-of' dependency group in the runtime scope (RDEPEND).

**Expected:** The prover should satisfy the runtime dependency by choosing to install none of the optional OS packages. The proof should be valid.

![test24](test24/test24.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.21 s (backtrack: 1/20).


!!! All ebuilds that could satisfy "test24/os" have been masked.
!!! One of the following masked packages is required to complete your request:
- test24/os-1.0::overlay (masked by: invalid: RDEPEND: USE flag '?' referenced in conditional '??' is not in IUSE)

(dependency required by "test24/web-1.0::overlay" [ebuild])
(dependency required by "test24/web" [argument])
For more information, see the MASKED PACKAGES section in the emerge
man page or refer to the Gentoo Handbook.
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test24/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test24/web-1.0
             │ download  overlay://test24/os-1.0
             │ download  overlay://test24/linux-1.0
             │ download  overlay://test24/db-1.0
             │ download  overlay://test24/app-1.0

 └─step  2─┤ install   overlay://test24/os-1.0
             │ install   overlay://test24/linux-1.0

 └─step  3─┤ run       overlay://test24/linux-1.0

 └─step  4─┤ run       overlay://test24/os-1.0

 └─step  5─┤ install   overlay://test24/db-1.0

 └─step  6─┤ run       overlay://test24/db-1.0

 └─step  7─┤ install   overlay://test24/app-1.0

 └─step  8─┤ run       overlay://test24/app-1.0

 └─step  9─┤ install   overlay://test24/web-1.0

 └─step 10─┤ run     overlay://test24/web-1.0

Total: 15 actions (5 downloads, 5 installs, 5 runs), grouped into 10 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test25
**Choice** — At-most-one-of ?? (compile + runtime)

This test case combines test23 and test24. The 'os-1.0' package has the same 'at-most-one-of' choice group in both its compile-time and runtime dependencies.

**Expected:** The prover should resolve both dependencies by choosing to install none of the optional packages, as this is the simplest valid solution. The proof should be valid.

![test25](test25/test25.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  .... done!
Dependency resolution took 1.22 s (backtrack: 1/20).


!!! All ebuilds that could satisfy "test25/os" have been masked.
!!! One of the following masked packages is required to complete your request:
- test25/os-1.0::overlay (masked by: invalid: DEPEND: USE flag '?' referenced in conditional '??' is not in IUSE, invalid: RDEPEND: USE flag '?' referenced in conditional '??' is not in IUSE)

(dependency required by "test25/web-1.0::overlay" [ebuild])
(dependency required by "test25/web" [argument])
For more information, see the MASKED PACKAGES section in the emerge
man page or refer to the Gentoo Handbook.
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test25/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test25/web-1.0
             │ download  overlay://test25/os-1.0
             │ download  overlay://test25/linux-1.0
             │ download  overlay://test25/db-1.0
             │ download  overlay://test25/app-1.0

 └─step  2─┤ install   overlay://test25/linux-1.0

 └─step  3─┤ run       overlay://test25/linux-1.0

 └─step  4─┤ install   overlay://test25/os-1.0

 └─step  5─┤ run       overlay://test25/os-1.0

 └─step  6─┤ install   overlay://test25/db-1.0

 └─step  7─┤ run       overlay://test25/db-1.0

 └─step  8─┤ install   overlay://test25/app-1.0

 └─step  9─┤ run       overlay://test25/app-1.0

 └─step 10─┤ install   overlay://test25/web-1.0

 └─step 11─┤ run     overlay://test25/web-1.0

Total: 15 actions (5 downloads, 5 installs, 5 runs), grouped into 11 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test26
**Blocker** — Strong blocker !! (runtime) + any-of

This test case checks the prover's handling of a strong blocker (!!). The 'app-1.0'
package has a strong runtime blocker against 'windows-1.0'. At the same time,
'os-1.0' has an any-of compile dependency that includes 'windows-1.0' as a choice.
The prover must recognize that selecting 'windows-1.0' for the any-of group would
conflict with the strong blocker on 'app-1.0', and should steer the selection
toward 'linux-1.0' or 'bsd-1.0' instead.

**Expected:** The prover should produce a valid plan that avoids 'windows-1.0'. It should select
either 'linux-1.0' or 'bsd-1.0' to satisfy the any-of group on 'os-1.0', since
'windows-1.0' is strongly blocked by 'app-1.0' in the runtime scope.

![test26](test26/test26.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.75 s (backtrack: 0/20).

[ebuild  N     ] test26/linux-1.0::overlay  0 KiB
[ebuild  N     ] test26/os-1.0::overlay  0 KiB
[ebuild  N     ] test26/db-1.0::overlay  0 KiB
[ebuild  N     ] test26/app-1.0::overlay  0 KiB
[ebuild  N     ] test26/web-1.0::overlay  0 KiB

Total: 5 packages (5 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test26/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test26/web-1.0
             │ download  overlay://test26/os-1.0
             │ download  overlay://test26/linux-1.0
             │ download  overlay://test26/db-1.0
             │ download  overlay://test26/app-1.0

 └─step  2─┤ install   overlay://test26/os-1.0
             │ install   overlay://test26/linux-1.0

 └─step  3─┤ run       overlay://test26/os-1.0

 └─step  4─┤ install   overlay://test26/db-1.0

 └─step  5─┤ run       overlay://test26/db-1.0

 └─step  6─┤ install   overlay://test26/app-1.0

 └─step  7─┤ run       overlay://test26/app-1.0

 └─step  8─┤ install   overlay://test26/web-1.0

 └─step  9─┤ run     overlay://test26/web-1.0

Total: 14 actions (5 downloads, 5 installs, 4 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test27
**Blocker** — Weak blocker ! (runtime) + any-of

This test case checks the prover's handling of a weak blocker (!). The 'app-1.0'
package has a weak runtime blocker against 'windows-1.0'. Unlike the strong blocker
in test26, a weak blocker is advisory: it signals that 'windows-1.0' should be
uninstalled if already present, but does not absolutely forbid its co-existence.
The any-of group on 'os-1.0' still includes 'windows-1.0' as a candidate.

**Expected:** The prover should produce a valid plan. The weak blocker is recorded as a domain
assumption. The any-of group resolution may or may not select 'windows-1.0',
depending on blocker handling strategy.

![test27](test27/test27.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.75 s (backtrack: 0/20).

[ebuild  N     ] test27/linux-1.0::overlay  0 KiB
[ebuild  N     ] test27/os-1.0::overlay  0 KiB
[ebuild  N     ] test27/db-1.0::overlay  0 KiB
[ebuild  N     ] test27/app-1.0::overlay  0 KiB
[ebuild  N     ] test27/web-1.0::overlay  0 KiB

Total: 5 packages (5 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test27/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test27/web-1.0
             │ download  overlay://test27/os-1.0
             │ download  overlay://test27/linux-1.0
             │ download  overlay://test27/db-1.0
             │ download  overlay://test27/app-1.0

 └─step  2─┤ install   overlay://test27/os-1.0
             │ install   overlay://test27/linux-1.0

 └─step  3─┤ run       overlay://test27/os-1.0

 └─step  4─┤ install   overlay://test27/db-1.0

 └─step  5─┤ run       overlay://test27/db-1.0

 └─step  6─┤ install   overlay://test27/app-1.0

 └─step  7─┤ run       overlay://test27/app-1.0

 └─step  8─┤ install   overlay://test27/web-1.0

 └─step  9─┤ run     overlay://test27/web-1.0

Total: 14 actions (5 downloads, 5 installs, 4 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.



>>> Blockers added during proving & planning:

  [blocks B] !test27/windows (soft blocker, phase: run, required by: overlay://test27/app-1.0)
```

</details>

---

## test28
**Blocker** — Strong blocker !! (compile) + any-of

This test case is a variation of test26 where the strong blocker (!!) is in the
compile-time scope (DEPEND) rather than the runtime scope (RDEPEND). The 'app-1.0'
package strongly blocks 'windows-1.0' at compile time, while 'os-1.0' has an
any-of compile dependency that includes 'windows-1.0'.

**Expected:** The prover should produce a valid plan that avoids 'windows-1.0'. It should select
either 'linux-1.0' or 'bsd-1.0' to satisfy the any-of group on 'os-1.0', since
'windows-1.0' is strongly blocked by 'app-1.0' in the compile scope.

![test28](test28/test28.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.75 s (backtrack: 0/20).

[ebuild  N     ] test28/linux-1.0::overlay  0 KiB
[ebuild  N     ] test28/os-1.0::overlay  0 KiB
[ebuild  N     ] test28/db-1.0::overlay  0 KiB
[ebuild  N     ] test28/app-1.0::overlay  0 KiB
[ebuild  N     ] test28/web-1.0::overlay  0 KiB

Total: 5 packages (5 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test28/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test28/web-1.0
             │ download  overlay://test28/os-1.0
             │ download  overlay://test28/linux-1.0
             │ download  overlay://test28/db-1.0
             │ download  overlay://test28/app-1.0

 └─step  2─┤ install   overlay://test28/os-1.0
             │ install   overlay://test28/linux-1.0

 └─step  3─┤ run       overlay://test28/os-1.0

 └─step  4─┤ install   overlay://test28/db-1.0

 └─step  5─┤ run       overlay://test28/db-1.0

 └─step  6─┤ install   overlay://test28/app-1.0

 └─step  7─┤ run       overlay://test28/app-1.0

 └─step  8─┤ install   overlay://test28/web-1.0

 └─step  9─┤ run     overlay://test28/web-1.0

Total: 14 actions (5 downloads, 5 installs, 4 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test29
**Blocker** — Strong blocker !! (compile+runtime) + any-of

This test case combines test26 and test28. The 'app-1.0' package has a strong
blocker (!!) against 'windows-1.0' in both the compile-time (DEPEND) and runtime
(RDEPEND) scopes. The any-of group on 'os-1.0' still includes 'windows-1.0'.

**Expected:** The prover should produce a valid plan that avoids 'windows-1.0'. It should select
either 'linux-1.0' or 'bsd-1.0' for the any-of group, since 'windows-1.0' is
strongly blocked in both scopes.

![test29](test29/test29.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  .... done!
Dependency resolution took 0.76 s (backtrack: 0/20).

[ebuild  N     ] test29/linux-1.0::overlay  0 KiB
[ebuild  N     ] test29/os-1.0::overlay  0 KiB
[ebuild  N     ] test29/db-1.0::overlay  0 KiB
[ebuild  N     ] test29/app-1.0::overlay  0 KiB
[ebuild  N     ] test29/web-1.0::overlay  0 KiB

Total: 5 packages (5 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test29/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test29/web-1.0
             │ download  overlay://test29/os-1.0
             │ download  overlay://test29/linux-1.0
             │ download  overlay://test29/db-1.0
             │ download  overlay://test29/app-1.0

 └─step  2─┤ install   overlay://test29/os-1.0
             │ install   overlay://test29/linux-1.0

 └─step  3─┤ run       overlay://test29/os-1.0

 └─step  4─┤ install   overlay://test29/db-1.0

 └─step  5─┤ run       overlay://test29/db-1.0

 └─step  6─┤ install   overlay://test29/app-1.0

 └─step  7─┤ run       overlay://test29/app-1.0

 └─step  8─┤ install   overlay://test29/web-1.0

 └─step  9─┤ run     overlay://test29/web-1.0

Total: 14 actions (5 downloads, 5 installs, 4 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test30
**Blocker** — Weak blocker ! (compile) + any-of

This test case is a variation of test27 where the weak blocker (!) is in the
compile-time scope (DEPEND) rather than the runtime scope (RDEPEND). The 'app-1.0'
package weakly blocks 'windows-1.0' at compile time, while 'os-1.0' has an any-of
compile dependency that includes 'windows-1.0'.

**Expected:** The prover should produce a valid plan. The weak blocker is recorded as a domain
assumption. The any-of group resolution may or may not select 'windows-1.0',
depending on blocker handling strategy.

![test30](test30/test30.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.75 s (backtrack: 0/20).

[ebuild  N     ] test30/linux-1.0::overlay  0 KiB
[ebuild  N     ] test30/os-1.0::overlay  0 KiB
[ebuild  N     ] test30/db-1.0::overlay  0 KiB
[ebuild  N     ] test30/app-1.0::overlay  0 KiB
[ebuild  N     ] test30/web-1.0::overlay  0 KiB

Total: 5 packages (5 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test30/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test30/web-1.0
             │ download  overlay://test30/os-1.0
             │ download  overlay://test30/linux-1.0
             │ download  overlay://test30/db-1.0
             │ download  overlay://test30/app-1.0

 └─step  2─┤ install   overlay://test30/os-1.0
             │ install   overlay://test30/linux-1.0

 └─step  3─┤ run       overlay://test30/os-1.0

 └─step  4─┤ install   overlay://test30/db-1.0

 └─step  5─┤ run       overlay://test30/db-1.0

 └─step  6─┤ install   overlay://test30/app-1.0

 └─step  7─┤ run       overlay://test30/app-1.0

 └─step  8─┤ install   overlay://test30/web-1.0

 └─step  9─┤ run     overlay://test30/web-1.0

Total: 14 actions (5 downloads, 5 installs, 4 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.



>>> Blockers added during proving & planning:

  [blocks B] !test30/windows (soft blocker, phase: install, required by: overlay://test30/app-1.0)
```

</details>

---

## test31
**Blocker** — Weak blocker ! (compile+runtime) + any-of

This test case combines test27 and test30. The 'app-1.0' package has a weak
blocker (!) against 'windows-1.0' in both the compile-time (DEPEND) and runtime
(RDEPEND) scopes. The any-of group on 'os-1.0' still includes 'windows-1.0'.

**Expected:** The prover should produce a valid plan. The weak blockers are recorded as domain
assumptions. The any-of group resolution may or may not select 'windows-1.0',
depending on blocker handling strategy.

![test31](test31/test31.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.74 s (backtrack: 0/20).

[ebuild  N     ] test31/linux-1.0::overlay  0 KiB
[ebuild  N     ] test31/os-1.0::overlay  0 KiB
[ebuild  N     ] test31/db-1.0::overlay  0 KiB
[ebuild  N     ] test31/app-1.0::overlay  0 KiB
[ebuild  N     ] test31/web-1.0::overlay  0 KiB

Total: 5 packages (5 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test31/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test31/web-1.0
             │ download  overlay://test31/os-1.0
             │ download  overlay://test31/linux-1.0
             │ download  overlay://test31/db-1.0
             │ download  overlay://test31/app-1.0

 └─step  2─┤ install   overlay://test31/os-1.0
             │ install   overlay://test31/linux-1.0

 └─step  3─┤ run       overlay://test31/os-1.0

 └─step  4─┤ install   overlay://test31/db-1.0

 └─step  5─┤ run       overlay://test31/db-1.0

 └─step  6─┤ install   overlay://test31/app-1.0

 └─step  7─┤ run       overlay://test31/app-1.0

 └─step  8─┤ install   overlay://test31/web-1.0

 └─step  9─┤ run     overlay://test31/web-1.0

Total: 14 actions (5 downloads, 5 installs, 4 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.



>>> Blockers added during proving & planning:

  [blocks B] !test31/windows (soft blocker, phase: install, required by: overlay://test31/app-1.0)
  [blocks B] !test31/windows (soft blocker, phase: run, required by: overlay://test31/app-1.0)
```

</details>

---

## test32
**REQUIRED_USE** — ^^ with conditional DEPEND

This test case examines the interplay between REQUIRED_USE and conditional dependencies. The 'os-1.0' package must have exactly one of 'linux' or 'darwin' enabled. The choice of which flag is enabled will then trigger the corresponding dependency.

**Expected:** The prover should satisfy the REQUIRED_USE by making a choice. For example, it might enable the 'linux' flag. This action should then trigger the conditional dependency, pulling 'linux-1.0' into the installation plan. A valid proof will include os-1.0 and either linux-1.0 or darwin-1.0.

![test32](test32/test32.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  

!!! Problem resolving dependencies for test32/os
... done!
Dependency resolution took 0.48 s (backtrack: 0/20).


!!! The ebuild selected to satisfy "test32/os" has unmet requirements.
- test32/os-1.0::overlay USE="-darwin -linux"

  The following REQUIRED_USE flag constraints are unsatisfied:
    exactly-one-of ( linux darwin )
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test32/os-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ useflag overlay://test32/os-1.0 (darwin)

 └─step  2─┤ download  overlay://test32/os-1.0

 └─step  3─┤ install   overlay://test32/os-1.0 (USE modified)
             │           └─ conf ─┤ USE = "darwin -linux"

 └─step  4─┤ run     overlay://test32/os-1.0

Total: 4 actions (1 useflag, 1 download, 1 install, 1 run), grouped into 4 steps.
       0.00 Kb to be downloaded.


>>> Assumptions taken during proving & planning:

  USE flag change (1 package):
  Add to /etc/portage/package.use:
    test32/os darwin
```

</details>

---

## test33
**USE dep** — Positive [linux]

This test case examines a direct USE dependency. The 'app-1.0' package requires that 'os-1.0' be built with the 'linux' USE flag enabled.

**Expected:** The prover should identify the USE requirement and enable the 'linux' flag for 'os-1.0' when resolving its dependencies. The final proof should be valid and show that 'os-1.0' is built with USE="linux".

![test33](test33/test33.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.84 s (backtrack: 0/20).

[ebuild  N     ] test33/os-1.0::overlay  USE="linux -darwin" 0 KiB
[ebuild  N     ] test33/app-1.0::overlay  0 KiB

Total: 2 packages (2 new), Size of downloads: 0 KiB

The following USE changes are necessary to proceed:
 (see "package.use" in the portage(5) man page for more details)
# required by test33/app-1.0::overlay
# required by test33/app (argument)
>=test33/os-1.0 linux
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test33/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ useflag overlay://test33/os-1.0 (linux)

 └─step  2─┤ download  overlay://test33/os-1.0
             │ download  overlay://test33/app-1.0

 └─step  3─┤ install   overlay://test33/os-1.0 (USE modified)
             │           └─ conf ─┤ USE = "-darwin linux"

 └─step  4─┤ install   overlay://test33/app-1.0

 └─step  5─┤ run     overlay://test33/app-1.0

Total: 6 actions (1 useflag, 2 downloads, 2 installs, 1 run), grouped into 5 steps.
       0.00 Kb to be downloaded.


>>> Assumptions taken during proving & planning:

  USE flag change (1 package):
  Add to /etc/portage/package.use:
    test33/os linux
```

</details>

---

## test34
**USE dep** — Negative [-linux]

This test case is the inverse of test33. It checks the handling of a negative USE dependency. The 'app-1.0' package requires that 'os-1.0' be built with the 'linux' USE flag disabled.

**Expected:** The prover must ensure the 'linux' flag is disabled for 'os-1.0'. The proof should be valid, showing that 'os-1.0' is built with USE="-linux".

![test34](test34/test34.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.76 s (backtrack: 0/20).

[ebuild  N     ] test34/os-1.0::overlay  USE="-darwin -linux" 0 KiB
[ebuild  N     ] test34/app-1.0::overlay  USE="-linux" 0 KiB

Total: 2 packages (2 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test34/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test34/os-1.0
             │ download  overlay://test34/app-1.0

 └─step  2─┤ install   overlay://test34/os-1.0
             │           └─ conf ─┤ USE = "-darwin -linux"

 └─step  3─┤ install   overlay://test34/app-1.0
             │           └─ conf ─┤ USE = "-linux"

 └─step  4─┤ run     overlay://test34/app-1.0

Total: 5 actions (2 downloads, 2 installs, 1 run), grouped into 4 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test35
**USE dep** — Equality [linux=]

This test case checks the handling of conditional USE propagation. The dependency `os[linux=]` means that if 'app-1.0' is built with USE="linux", then 'os-1.0' must also be built with USE="linux". If 'app-1.0' is built with USE="-linux", then 'os-1.0' must be built with USE="-linux".

**Expected:** - If 'app-1.0' is proven with USE="linux", the prover should enforce USE="linux" on 'os-1.0'.
- If 'app-1.0' is proven with USE="-linux" (or it's disabled by default), the prover should enforce USE="-linux" on 'os-1.0'.
In both cases, the proof should be valid.

![test35](test35/test35.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.74 s (backtrack: 0/20).

[ebuild  N     ] test35/os-1.0::overlay  USE="-darwin -linux" 0 KiB
[ebuild  N     ] test35/app-1.0::overlay  USE="-linux" 0 KiB

Total: 2 packages (2 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test35/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test35/os-1.0
             │ download  overlay://test35/app-1.0

 └─step  2─┤ install   overlay://test35/os-1.0
             │           └─ conf ─┤ USE = "-darwin -linux"

 └─step  3─┤ install   overlay://test35/app-1.0
             │           └─ conf ─┤ USE = "-linux"

 └─step  4─┤ run     overlay://test35/app-1.0

Total: 5 actions (2 downloads, 2 installs, 1 run), grouped into 4 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test36
**USE dep** — Chained equality [linux=] through lib

This test case examines the prover's ability to propagate a conditional USE flag requirement down a dependency chain. The USE="linux" setting on 'app-1.0' should flow down to 'lib-1.0', which in turn should flow down to 'os-1.0'.

**Expected:** If 'app-1.0' is proven with USE="linux", the prover should enforce USE="linux" on both 'lib-1.0' and 'os-1.0'. Conversely, if 'app-1.0' has USE="-linux", that requirement should also propagate down the chain. The proof should be valid in both scenarios.

![test36](test36/test36.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.74 s (backtrack: 0/20).

[ebuild  N     ] test36/os-1.0::overlay  USE="-darwin -linux" 0 KiB
[ebuild  N     ] test36/lib-1.0::overlay  USE="-linux" 0 KiB
[ebuild  N     ] test36/app-1.0::overlay  USE="-linux" 0 KiB

Total: 3 packages (3 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test36/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test36/os-1.0
             │ download  overlay://test36/lib-1.0
             │ download  overlay://test36/app-1.0

 └─step  2─┤ install   overlay://test36/os-1.0
             │           └─ conf ─┤ USE = "-darwin -linux"

 └─step  3─┤ install   overlay://test36/lib-1.0
             │           └─ conf ─┤ USE = "-linux"

 └─step  4─┤ install   overlay://test36/app-1.0
             │           └─ conf ─┤ USE = "-linux"

 └─step  5─┤ run     overlay://test36/app-1.0

Total: 7 actions (3 downloads, 3 installs, 1 run), grouped into 5 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test37
**USE dep** — Inverse equality [!linux=]

This test case checks the handling of an inverse conditional USE dependency. The dependency `os[!linux=]` means that the 'linux' flag on 'os-1.0' must be the inverse of the setting on 'app-1.0'.

**Expected:** - If 'app-1.0' is proven with USE="linux", the prover must enforce USE="-linux" on 'os-1.0'.
- If 'app-1.0' is proven with USE="-linux", the prover must enforce USE="linux" on 'os-1.0'.
The proof should be valid in both scenarios.

![test37](test37/test37.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.74 s (backtrack: 0/20).

[ebuild  N     ] test37/os-1.0::overlay  USE="linux -darwin" 0 KiB
[ebuild  N     ] test37/app-1.0::overlay  USE="-linux" 0 KiB

Total: 2 packages (2 new), Size of downloads: 0 KiB

The following USE changes are necessary to proceed:
 (see "package.use" in the portage(5) man page for more details)
# required by test37/app-1.0::overlay
# required by test37/app (argument)
>=test37/os-1.0 linux
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test37/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ useflag overlay://test37/os-1.0 (linux)

 └─step  2─┤ download  overlay://test37/os-1.0
             │ download  overlay://test37/app-1.0

 └─step  3─┤ install   overlay://test37/os-1.0 (USE modified)
             │           └─ conf ─┤ USE = "-darwin linux"

 └─step  4─┤ install   overlay://test37/app-1.0
             │           └─ conf ─┤ USE = "-linux"

 └─step  5─┤ run     overlay://test37/app-1.0

Total: 6 actions (1 useflag, 2 downloads, 2 installs, 1 run), grouped into 5 steps.
       0.00 Kb to be downloaded.


>>> Assumptions taken during proving & planning:

  USE flag change (1 package):
  Add to /etc/portage/package.use:
    test37/os linux
```

</details>

---

## test38
**USE dep** — Weak conditional [linux?]

This test case checks the handling of a weak USE dependency. The dependency `os[linux?]` means that 'os-1.0' will have the 'linux' flag enabled *only if* 'app-1.0' also has the 'linux' flag enabled. It does not force the flag to be enabled on 'app-1.0'.

**Expected:** - If 'app-1.0' is proven with USE="linux", the prover should enforce USE="linux" on 'os-1.0'.
- If 'app-1.0' is proven with USE="-linux", the 'linux' flag on 'os-1.0' is not constrained by this dependency and can be either on or off (defaulting to off).
The proof should be valid in both scenarios.

![test38](test38/test38.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.76 s (backtrack: 0/20).

[ebuild  N     ] test38/os-1.0::overlay  USE="-darwin -linux" 0 KiB
[ebuild  N     ] test38/app-1.0::overlay  USE="-linux" 0 KiB

Total: 2 packages (2 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test38/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test38/os-1.0
             │ download  overlay://test38/app-1.0

 └─step  2─┤ install   overlay://test38/os-1.0
             │           └─ conf ─┤ USE = "-darwin -linux"

 └─step  3─┤ install   overlay://test38/app-1.0
             │           └─ conf ─┤ USE = "-linux"

 └─step  4─┤ run     overlay://test38/app-1.0

Total: 5 actions (2 downloads, 2 installs, 1 run), grouped into 4 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test39
**USE dep** — Negative weak [-linux?]

This test case checks the handling of a negative weak USE dependency. The dependency `os[-linux?]` means that 'os-1.0' will have the 'linux' flag disabled *only if* 'app-1.0' also has the 'linux' flag disabled.

**Expected:** - If 'app-1.0' is proven with USE="-linux", the prover should enforce USE="-linux" on 'os-1.0'.
- If 'app-1.0' is proven with USE="linux", the 'linux' flag on 'os-1.0' is not constrained by this dependency.
The proof should be valid in both scenarios.

![test39](test39/test39.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.73 s (backtrack: 0/20).

[ebuild  N     ] test39/os-1.0::overlay  USE="-darwin -linux" 0 KiB
[ebuild  N     ] test39/app-1.0::overlay  USE="-linux" 0 KiB

Total: 2 packages (2 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test39/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test39/os-1.0
             │ download  overlay://test39/app-1.0

 └─step  2─┤ install   overlay://test39/os-1.0
             │           └─ conf ─┤ USE = "-darwin -linux"

 └─step  3─┤ install   overlay://test39/app-1.0
             │           └─ conf ─┤ USE = "-linux"

 └─step  4─┤ run     overlay://test39/app-1.0

Total: 5 actions (2 downloads, 2 installs, 1 run), grouped into 4 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test40
**REQUIRED_USE** — || on standalone package

This test case checks the prover's ability to handle a REQUIRED_USE 'any-of' (||) constraint on a standalone package. To install 'os-1.0', the user or the configuration must ensure that at least one of the 'linux' or 'darwin' USE flags is enabled.

**Expected:** - If the prover is run for 'os-1.0' and the configuration provides either USE="linux" or USE="darwin", the proof should be valid.
- If no configuration is provided, the prover should make a choice and enable one of the flags to satisfy the constraint, resulting in a valid proof.
- If the configuration explicitly disables both (e.g., USE="-linux -darwin"), the proof should fail.

![test40](test40/test40.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  

!!! Problem resolving dependencies for test40/os
... done!
Dependency resolution took 0.47 s (backtrack: 0/20).


!!! The ebuild selected to satisfy "test40/os" has unmet requirements.
- test40/os-1.0::overlay USE="-darwin -linux"

  The following REQUIRED_USE flag constraints are unsatisfied:
    any-of ( linux darwin )
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test40/os-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ useflag overlay://test40/os-1.0 (darwin)

 └─step  2─┤ download  overlay://test40/os-1.0

 └─step  3─┤ install   overlay://test40/os-1.0 (USE modified)
             │           └─ conf ─┤ USE = "darwin -linux"

 └─step  4─┤ run     overlay://test40/os-1.0

Total: 4 actions (1 useflag, 1 download, 1 install, 1 run), grouped into 4 steps.
       0.00 Kb to be downloaded.


>>> Assumptions taken during proving & planning:

  USE flag change (1 package):
  Add to /etc/portage/package.use:
    test40/os darwin
```

</details>

---

## test41
**Slot** — Explicit slot :1

This test case checks the prover's ability to resolve dependencies based on slotting. 'app-1.0' requires a version of 'lib' that is in slot "1". Even though 'lib-2.0' is a higher version, it is in a different slot and therefore not a candidate.

**Expected:** The prover should correctly select 'lib-1.0' to satisfy the slot dependency, ignoring the newer 'lib-2.0'. The proof should be valid.

![test41](test41/test41.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.75 s (backtrack: 0/20).

[ebuild  N     ] test41/lib-1.0:1::overlay  0 KiB
[ebuild  N     ] test41/app-1.0::overlay  0 KiB

Total: 2 packages (2 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test41/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test41/lib-1.0
             │ download  overlay://test41/app-1.0

 └─step  2─┤ install   overlay://test41/lib-1.0
             │           └─ conf ─┤ SLOT = "1"

 └─step  3─┤ run       overlay://test41/lib-1.0

 └─step  4─┤ install   overlay://test41/app-1.0

 └─step  5─┤ run     overlay://test41/app-1.0

Total: 6 actions (2 downloads, 2 installs, 2 runs), grouped into 5 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test42
**Slot** — Wildcard slot :*

This test case checks the prover's behavior with a wildcard slot dependency. 'app-1.0' requires 'lib', but it doesn't care which slot is used.

**Expected:** Given the choice between two valid slots, the prover should follow the default behavior of picking the latest version, which is 'lib-2.0' in slot "2". The proof should be valid.

![test42](test42/test42.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.73 s (backtrack: 0/20).

[ebuild  N     ] test42/lib-2.0:2::overlay  0 KiB
[ebuild  N     ] test42/app-1.0::overlay  0 KiB

Total: 2 packages (2 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test42/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test42/lib-2.0
             │ download  overlay://test42/app-1.0

 └─step  2─┤ install   overlay://test42/lib-2.0
             │           └─ conf ─┤ SLOT = "2"

 └─step  3─┤ run       overlay://test42/lib-2.0

 └─step  4─┤ install   overlay://test42/app-1.0

 └─step  5─┤ run     overlay://test42/app-1.0

Total: 6 actions (2 downloads, 2 installs, 2 runs), grouped into 5 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test43
**Slot** — Slot equality :=

This test case examines the slot equality operator (:=). 'app-1.0' depends on 'lib' at compile time. The prover will choose the latest version, 'lib-2.0'. The runtime dependency then requires that the same slot ('2') be used.

**Expected:** The prover should first resolve the compile dependency to 'lib-2.0'. Then, when resolving the runtime dependency, it must choose a package from the same slot, which is 'lib-2.0'. The proof should be valid.

![test43](test43/test43.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.75 s (backtrack: 0/20).

[ebuild  N     ] test43/lib-2.0:2::overlay  0 KiB
[ebuild  N     ] test43/app-1.0::overlay  0 KiB

Total: 2 packages (2 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test43/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test43/lib-2.0
             │ download  overlay://test43/app-1.0

 └─step  2─┤ install   overlay://test43/lib-2.0
             │           └─ conf ─┤ SLOT = "2"

 └─step  3─┤ run       overlay://test43/lib-2.0

 └─step  4─┤ install   overlay://test43/app-1.0

 └─step  5─┤ run     overlay://test43/app-1.0

Total: 6 actions (2 downloads, 2 installs, 2 runs), grouped into 5 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test44
**Slot** — Sub-slot :1/A

This test case checks the prover's ability to resolve dependencies based on sub-slots. 'app-1.0' requires a version of 'lib' in slot "1" and sub-slot "A".

**Expected:** The prover should correctly select 'lib-1.0' to satisfy the sub-slot dependency. It should ignore 'lib-1.1' (wrong sub-slot) and 'lib-2.0' (wrong slot). The proof should be valid.

![test44](test44/test44.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.75 s (backtrack: 0/20).

[ebuild  N     ] test44/lib-1.0:1/A::overlay  0 KiB
[ebuild  N     ] test44/app-1.0::overlay  0 KiB

Total: 2 packages (2 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test44/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test44/lib-1.0
             │ download  overlay://test44/app-1.0

 └─step  2─┤ install   overlay://test44/lib-1.0
             │           └─ conf ─┤ SLOT = "1/A"

 └─step  3─┤ run       overlay://test44/lib-1.0

 └─step  4─┤ install   overlay://test44/app-1.0

 └─step  5─┤ run     overlay://test44/app-1.0

Total: 6 actions (2 downloads, 2 installs, 2 runs), grouped into 5 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test45
**Conflict** — Irreconcilable USE conflict via ^^

This test case checks the prover's ability to detect a direct and irreconcilable USE flag conflict. The 'os' package has a REQUIRED_USE constraint of "^^ ( linux darwin )", meaning exactly one of those USE flags must be enabled. However, the dependency graph requires both to be enabled simultaneously to satisfy liba and libb.

**Expected:** The prover should correctly identify the conflict and fail to produce a valid installation proof. There is no possible configuration of USE flags that can satisfy these dependencies.

![test45](test45/test45.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.49 s (backtrack: 0/20).


The following USE changes are necessary to proceed:
 (see "package.use" in the portage(5) man page for more details)
# required by test45/liba-1.0::overlay
# required by test45/app-1.0::overlay
# required by test45/app (argument)
>=test45/os-1.0 darwin linux

!!! The ebuild selected to satisfy "test45/os[linux]" has unmet requirements.
- test45/os-1.0::overlay USE="-darwin -linux"

  The following REQUIRED_USE flag constraints are unsatisfied:
    exactly-one-of ( linux darwin )

(dependency required by "test45/liba-1.0::overlay" [ebuild])
(dependency required by "test45/app-1.0::overlay" [ebuild])
(dependency required by "test45/app" [argument])
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test45/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ useflag overlay://test45/os-1.0 (darwin)

 └─step  2─┤ download  overlay://test45/os-1.0
             │ download  overlay://test45/libb-1.0
             │ download  overlay://test45/liba-1.0
             │ download  overlay://test45/app-1.0

 └─step  3─┤ install   overlay://test45/liba-1.0
             │ install   overlay://test45/libb-1.0
             │ install   overlay://test45/os-1.0 (USE modified)
             │           └─ conf ─┤ USE = "darwin -linux"

 └─step  4─┤ run       overlay://test45/libb-1.0
             │ run       overlay://test45/liba-1.0

 └─step  5─┤ install   overlay://test45/app-1.0

 └─step  6─┤ run     overlay://test45/app-1.0

Total: 12 actions (1 useflag, 4 downloads, 4 installs, 3 runs), grouped into 6 steps.
       0.00 Kb to be downloaded.


>>> Assumptions taken during proving & planning:

  USE flag change (1 package):
  Add to /etc/portage/package.use:
    test45/os darwin
```

</details>

---

## test46
**Conflict** — Deep diamond USE conflict

This test case is designed to assess the prover's ability to detect a USE flag conflict that is hidden several layers deep in the dependency graph. The two main dependency branches ('liba' and 'libb') converge on 'core-utils' with contradictory requirements for the 'feature_x' USE flag.

**Expected:** The prover must trace the entire dependency tree and identify that 'core-utils' is required with both 'feature_x' enabled and disabled simultaneously. As this is a logical contradiction, the prover should fail to produce a valid installation proof.

![test46](test46/test46.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.52 s (backtrack: 0/20).


!!! The ebuild selected to satisfy "test46/core-utils[-feature_x]" has unmet requirements.
- test46/core-utils-1.0::overlay USE="-feature_x -feature_y"

  The following REQUIRED_USE flag constraints are unsatisfied:
    exactly-one-of ( feature_x feature_y )

(dependency required by "test46/libd-1.0::overlay" [ebuild])
(dependency required by "test46/libb-1.0::overlay" [ebuild])
(dependency required by "test46/app-1.0::overlay" [ebuild])
(dependency required by "test46/app" [argument])
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test46/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ useflag overlay://test46/core-utils-1.0 (feature_x)
             │ useflag overlay://test46/core-utils-1.0 (feature_x feature_y)

 └─step  2─┤ verify  overlay://test46/core-utils-1.0 (assumed running) 
             │ download  overlay://test46/libd-1.0
             │ download  overlay://test46/libc-1.0
             │ download  overlay://test46/libb-1.0
             │ download  overlay://test46/liba-1.0
             │ download  overlay://test46/core-utils-1.0
             │ download  overlay://test46/app-1.0

 └─step  3─┤ install   overlay://test46/core-utils-1.0 (USE modified)
             │           └─ conf ─┤ USE = "feature_x feature_y"

 └─step  4─┤ run       overlay://test46/core-utils-1.0 (USE modified)

 └─step  5─┤ install   overlay://test46/libd-1.0
             │ install   overlay://test46/libc-1.0

 └─step  6─┤ run       overlay://test46/libd-1.0
             │ run       overlay://test46/libc-1.0

 └─step  7─┤ install   overlay://test46/libb-1.0
             │ install   overlay://test46/liba-1.0

 └─step  8─┤ run       overlay://test46/libb-1.0
             │ run       overlay://test46/liba-1.0

 └─step  9─┤ install   overlay://test46/app-1.0

 └─step 10─┤ run     overlay://test46/app-1.0

Total: 20 actions (2 useflags, 6 downloads, 6 installs, 6 runs), grouped into 10 steps.
       0.00 Kb to be downloaded.



>>> Assumptions taken during proving & planning:

  USE flag change (2 packages):
  Add to /etc/portage/package.use:
    test46/core-utils feature_x
    test46/core-utils feature_x feature_y

>>> Cycle breaks (prover)

  overlay://test46/core-utils-1.0:run
```

</details>

---

## test47
**Cycle** — Three-way dependency cycle

This test case presents a more complex, three-way circular dependency. The client needs the docs to build, the docs need the server to run, and the server needs the client to run. This creates a loop that cannot be resolved.

**Expected:** The prover should be able to trace the dependency chain through all three packages and identify the circular dependency, causing the proof to fail.

![test47](test47/test47.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.20 s (backtrack: 1/20).



[nomerge       ] test47/api-docs-1.0::overlay 
[ebuild  N     ]  test47/app-server-1.0::overlay  0 KiB
[ebuild  N     ]   test47/app-client-1.0::overlay  0 KiB
[ebuild  N     ]    test47/api-docs-1.0::overlay  0 KiB

Total: 3 packages (3 new), Size of downloads: 0 KiB

 * Error: circular dependencies:

(test47/app-server-1.0:0/0::overlay, ebuild scheduled for merge) depends on
 (test47/app-client-1.0:0/0::overlay, ebuild scheduled for merge) (runtime)
  (test47/api-docs-1.0:0/0::overlay, ebuild scheduled for merge) (buildtime)
   (test47/app-server-1.0:0/0::overlay, ebuild scheduled for merge) (runtime)

 * Note that circular dependencies can often be avoided by temporarily
 * disabling USE flags that trigger optional dependencies.
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test47/api-docs-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ verify  overlay://test47/api-docs-1.0 (assumed installed)
             │ download  overlay://test47/app-server-1.0
             │ download  overlay://test47/app-client-1.0
             │ download  overlay://test47/api-docs-1.0

 └─step  2─┤ install   overlay://test47/app-server-1.0

 └─step  3─┤ run       overlay://test47/app-server-1.0

 └─step  4─┤ install   overlay://test47/api-docs-1.0

 └─step  5─┤ install   overlay://test47/app-client-1.0

 └─step  6─┤ run       overlay://test47/app-client-1.0

 └─step  7─┤ run     overlay://test47/api-docs-1.0

Total: 9 actions (3 downloads, 3 installs, 3 runs), grouped into 7 steps.
       0.00 Kb to be downloaded.


>>> Cycle breaks (prover)

  overlay://test47/api-docs-1.0:install
```

</details>

---

## test48
**Conflict** — Slot conflict (same slot, different versions)

This test case checks the prover's ability to detect a slotting conflict. The two main dependencies, 'libgraphics' and 'libphysics', require different versions of 'libmatrix' to be installed into the same slot ('1'). A package slot can only be occupied by one version at a time.

**Expected:** The prover should identify that the dependencies for 'app-1.0' lead to a request to install two different packages ('libmatrix-1.0' and 'libmatrix-1.1') into the same slot. This is an impossible condition, so the prover must fail to find a valid proof.

![test48](test48/test48.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  .... done!
Dependency resolution took 4.52 s (backtrack: 6/20).

[ebuild  N     ] test48/libmatrix-1.1:1/B::overlay  0 KiB
[ebuild  N     ] test48/libmatrix-1.0:1/A::overlay  0 KiB
[ebuild  N     ] test48/libgraphics-1.0::overlay  0 KiB
[ebuild  N     ] test48/libphysics-1.0::overlay  0 KiB
[ebuild  N     ] test48/app-1.0::overlay  0 KiB

Total: 5 packages (5 new), Size of downloads: 0 KiB

!!! Multiple package instances within a single package slot have been pulled
!!! into the dependency graph, resulting in a slot conflict:

test48/libmatrix:1

  (test48/libmatrix-1.1:1/B::overlay, ebuild scheduled for merge) USE="" pulled in by
    =test48/libmatrix-1.1:1/B required by (test48/libphysics-1.0:0/0::overlay, ebuild scheduled for merge) USE=""
    ^                 ^^^^^^^                                                                                     

  (test48/libmatrix-1.0:1/A::overlay, ebuild scheduled for merge) USE="" pulled in by
    =test48/libmatrix-1.0:1/A required by (test48/libgraphics-1.0:0/0::overlay, ebuild scheduled for merge) USE=""
    ^                 ^^^^^^^                                                                                      


It may be possible to solve this problem by using package.mask to
prevent one of those packages from being selected. However, it is also
possible that conflicting dependencies exist such that they are
impossible to satisfy simultaneously.  If such a conflict exists in
the dependencies of two different packages, then those packages can
not be installed simultaneously. You may want to try a larger value of
the --backtrack option, such as --backtrack=30, in order to see if
that will solve this conflict automatically.

For more information, see MASKED PACKAGES section in the emerge man
page or refer to the Gentoo Handbook.
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test48/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ verify  test48/libphysics (unsatisfied constraints, assumed running)
             │ download  overlay://test48/libmatrix-1.0
             │ download  overlay://test48/libgraphics-1.0
             │ download  overlay://test48/app-1.0

 └─step  2─┤ install   overlay://test48/libmatrix-1.0
             │           └─ conf ─┤ SLOT = "1/A"

 └─step  3─┤ run       overlay://test48/libmatrix-1.0

 └─step  4─┤ install   overlay://test48/libgraphics-1.0

 └─step  5─┤ run       overlay://test48/libgraphics-1.0

 └─step  6─┤ install   overlay://test48/app-1.0

 └─step  7─┤ run     overlay://test48/app-1.0

Total: 9 actions (3 downloads, 3 installs, 3 runs), grouped into 7 steps.
       0.00 Kb to be downloaded.



Error The proof for your build plan contains domain assumptions. Please verify:


>>> Domain assumptions

- Unsatisfied constraints for run dependency: 
  test48/libphysics

  required by: overlay://test48/app-1.0


>>> Bug report drafts (Gentoo Bugzilla)

---
Summary: overlay://test48/app-1.0: unsatisfied_constraints dependency on test48/libphysics

Affected package: overlay://test48/app-1.0
Dependency: test48/libphysics
Phases: [run]

Unsatisfiable constraint(s):
  test48/libphysics-

Observed:
  portage-ng reports no available candidate satisfies the above constraint(s).
  Available versions in repo set (sample, first 1 of 1): [1.0]

Potential fix (suggestion):
  Review dependency metadata in overlay://test48/app-1.0; constraint set: [constraint(none,,[])].
```

</details>

---

## test49
**Conflict** — USE default (+) vs REQUIRED_USE

This test case checks the prover's ability to handle a conflict between a "soft" USE flag suggestion from a dependency and a "hard" REQUIRED_USE constraint in the target package. The `(+)` syntax is a default and should be overridden by the stricter `REQUIRED_USE`.

**Expected:** The prover should recognize that the dependency from 'app-1.0' attempts to enable a USE flag that is explicitly forbidden by 'libhelper-1.0'. The hard constraint of REQUIRED_USE must take precedence, leading to an unresolvable conflict. The prover should fail to find a valid proof.

![test49](test49/test49.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.48 s (backtrack: 0/20).


The following USE changes are necessary to proceed:
 (see "package.use" in the portage(5) man page for more details)
# required by test49/app-1.0::overlay
# required by test49/app (argument)
>=test49/libhelper-1.0 feature_z

!!! The ebuild selected to satisfy "test49/libhelper[feature_z(+)]" has unmet requirements.
- test49/libhelper-1.0::overlay USE="-feature_z"

  The following REQUIRED_USE flag constraints are unsatisfied:
    !feature_z

(dependency required by "test49/app-1.0::overlay" [ebuild])
(dependency required by "test49/app" [argument])
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test49/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ verify  test49/libhelper (unsatisfied constraints, assumed running)
             │ download  overlay://test49/app-1.0

 └─step  2─┤ install   overlay://test49/app-1.0
             │           └─ conf ─┤ USE = "-feature_z"

 └─step  3─┤ run     overlay://test49/app-1.0

Total: 3 actions (1 download, 1 install, 1 run), grouped into 3 steps.
       0.00 Kb to be downloaded.



Error The proof for your build plan contains domain assumptions. Please verify:


>>> Domain assumptions

- REQUIRED_USE violation: 
  test49/libhelper
  USE deps force:   [feature_z]
  violates: !feature_z
  required by: overlay://test49/app-1.0


>>> Bug report drafts (Gentoo Bugzilla)

---
Summary: overlay://test49/app-1.0: unsatisfied_constraints dependency on test49/libhelper

Affected package: overlay://test49/app-1.0
Dependency: test49/libhelper
Phases: [run]

Unsatisfiable constraint(s):
  test49/libhelper-

Observed:
  portage-ng reports no available candidate satisfies the above constraint(s).
  Available versions in repo set (sample, first 1 of 1): [1.0]

Potential fix (suggestion):
  Review dependency metadata in overlay://test49/app-1.0; constraint set: [constraint(none,,[])].
```

</details>

---

## test50
**Transitive** — Compile dep's RDEPEND must appear

This test case examines the prover's handling of transitive dependencies, specifically how a runtime dependency of a compile-time dependency is treated. 'app-1.0' needs 'foo-1.0' to build. 'foo-1.0' itself needs 'bar-1.0' to run.

**Expected:** When proving for 'app-1.0', the prover should correctly identify that both 'foo-1.0' and 'bar-1.0' need to be installed. The proof should be valid, and the installation plan should include all three packages in the correct order (bar, foo, app).

![test50](test50/test50.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.74 s (backtrack: 0/20).

[ebuild  N     ] test50/bar-1.0::overlay  0 KiB
[ebuild  N     ] test50/foo-1.0::overlay  0 KiB
[ebuild  N     ] test50/app-1.0::overlay  0 KiB

Total: 3 packages (3 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test50/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test50/foo-1.0
             │ download  overlay://test50/bar-1.0
             │ download  overlay://test50/app-1.0

 └─step  2─┤ install   overlay://test50/bar-1.0

 └─step  3─┤ run       overlay://test50/bar-1.0

 └─step  4─┤ install   overlay://test50/foo-1.0

 └─step  5─┤ install   overlay://test50/app-1.0

 └─step  6─┤ run     overlay://test50/app-1.0

Total: 8 actions (3 downloads, 3 installs, 2 runs), grouped into 6 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test51
**Conflict** — USE dep vs REQUIRED_USE contradiction

This test case presents a direct and unsolvable conflict between a dependency's USE requirement and the target package's REQUIRED_USE. 'app-1.0' needs 'os-1.0' with the 'linux' flag, but 'os-1.0' explicitly forbids that flag from being enabled.

**Expected:** The prover should immediately detect the contradiction between the USE dependency and the REQUIRED_USE constraint and fail to produce a valid proof.

![test51](test51/test51.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.48 s (backtrack: 0/20).


The following USE changes are necessary to proceed:
 (see "package.use" in the portage(5) man page for more details)
# required by test51/app-1.0::overlay
# required by test51/app (argument)
>=test51/os-1.0 linux

!!! The ebuild selected to satisfy "test51/os[linux]" has unmet requirements.
- test51/os-1.0::overlay USE="-linux"

  The following REQUIRED_USE flag constraints are unsatisfied:
    !linux

(dependency required by "test51/app-1.0::overlay" [ebuild])
(dependency required by "test51/app" [argument])
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test51/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ verify  test51/os (unsatisfied constraints, assumed installed)
             │ download  overlay://test51/app-1.0

 └─step  2─┤ install   overlay://test51/app-1.0

 └─step  3─┤ run     overlay://test51/app-1.0

Total: 3 actions (1 download, 1 install, 1 run), grouped into 3 steps.
       0.00 Kb to be downloaded.



Error The proof for your build plan contains domain assumptions. Please verify:


>>> Domain assumptions

- REQUIRED_USE violation: 
  test51/os
  USE deps force:   [linux]
  violates: !linux
  required by: overlay://test51/app-1.0


>>> Bug report drafts (Gentoo Bugzilla)

---
Summary: overlay://test51/app-1.0: unsatisfied_constraints dependency on test51/os

Affected package: overlay://test51/app-1.0
Dependency: test51/os
Phases: [install]

Unsatisfiable constraint(s):
  test51/os-

Observed:
  portage-ng reports no available candidate satisfies the above constraint(s).
  Available versions in repo set (sample, first 1 of 1): [1.0]

Potential fix (suggestion):
  Review dependency metadata in overlay://test51/app-1.0; constraint set: [constraint(none,,[])].
```

</details>

---

## test52
**USE merge** — Multiple USE flags on shared dep

The prover will first prove os-1.0 through the liba path. This means os-1.0 will have 'threads' enabled. Later prover needs to enable 'hardened' through the libb path. The prover should be able to produce a proof with just one os install, for both 'threads' and 'hardeded'. This should also be reflected in the download for os-1.0

**Expected:** The prover should correctly identify the need for building os-1.0 only once with the two use flags.

![test52](test52/test52.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.76 s (backtrack: 0/20).

[ebuild  N     ] test52/os-1.0::overlay  USE="hardened threads" 0 KiB
[ebuild  N     ] test52/liba-1.0::overlay  0 KiB
[ebuild  N     ] test52/libb-1.0::overlay  0 KiB
[ebuild  N     ] test52/app-1.0::overlay  0 KiB

Total: 4 packages (4 new), Size of downloads: 0 KiB

The following USE changes are necessary to proceed:
 (see "package.use" in the portage(5) man page for more details)
# required by test52/libb-1.0::overlay
# required by test52/app-1.0::overlay
# required by test52/app (argument)
>=test52/os-1.0 hardened
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test52/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ useflag overlay://test52/os-1.0 (hardened)

 └─step  2─┤ download  overlay://test52/os-1.0
             │ download  overlay://test52/libb-1.0
             │ download  overlay://test52/liba-1.0
             │ download  overlay://test52/app-1.0

 └─step  3─┤ install   overlay://test52/liba-1.0
             │ install   overlay://test52/libb-1.0
             │ install   overlay://test52/os-1.0 (USE modified)
             │           └─ conf ─┤ USE = "threads* hardened"

 └─step  4─┤ run       overlay://test52/libb-1.0
             │ run       overlay://test52/liba-1.0

 └─step  5─┤ install   overlay://test52/app-1.0

 └─step  6─┤ run     overlay://test52/app-1.0

Total: 12 actions (1 useflag, 4 downloads, 4 installs, 3 runs), grouped into 6 steps.
       0.00 Kb to be downloaded.


>>> Assumptions taken during proving & planning:

  USE flag change (1 package):
  Add to /etc/portage/package.use:
    test52/os hardened
```

</details>

---

## test53
**USE merge** — USE merge + conditional extra dep

The prover will first prove os-1.0 through the liba path. This means os-1.0 will have 'threads' enabled. Later prover needs to enable 'hardened' through the libb path. The prover should be able to produce a proof with just one os install, for both 'threads' and 'hardeded'. This should also be reflected in the download for os-1.0. Introducing 'hardened' on the already proven os-1.0 should pull in a new dependency on libhardened-1.0

**Expected:** The prover should correctly identify the need for building os-1.0 only once with the two use flags, and the libhardened-1.0 dependency

![test53](test53/test53.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.74 s (backtrack: 0/20).

[ebuild  N     ] test53/libhardened-1.0::overlay  0 KiB
[ebuild  N     ] test53/os-1.0::overlay  USE="hardened threads" 0 KiB
[ebuild  N     ] test53/liba-1.0::overlay  0 KiB
[ebuild  N     ] test53/libb-1.0::overlay  0 KiB
[ebuild  N     ] test53/app-1.0::overlay  0 KiB

Total: 5 packages (5 new), Size of downloads: 0 KiB

The following USE changes are necessary to proceed:
 (see "package.use" in the portage(5) man page for more details)
# required by test53/libb-1.0::overlay
# required by test53/app-1.0::overlay
# required by test53/app (argument)
>=test53/os-1.0 hardened
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test53/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ useflag overlay://test53/os-1.0 (hardened)

 └─step  2─┤ download  overlay://test53/os-1.0
             │ download  overlay://test53/libhardened-1.0
             │ download  overlay://test53/libb-1.0
             │ download  overlay://test53/liba-1.0
             │ download  overlay://test53/app-1.0

 └─step  3─┤ install   overlay://test53/liba-1.0
             │ install   overlay://test53/libb-1.0
             │ install   overlay://test53/libhardened-1.0

 └─step  4─┤ run       overlay://test53/libhardened-1.0
             │ run       overlay://test53/libb-1.0
             │ run       overlay://test53/liba-1.0

 └─step  5─┤ install   overlay://test53/os-1.0 (USE modified)
             │           └─ conf ─┤ USE = "threads* hardened"

 └─step  6─┤ install   overlay://test53/app-1.0

 └─step  7─┤ run     overlay://test53/app-1.0

Total: 15 actions (1 useflag, 5 downloads, 5 installs, 4 runs), grouped into 7 steps.
       0.00 Kb to be downloaded.


>>> Assumptions taken during proving & planning:

  USE flag change (1 package):
  Add to /etc/portage/package.use:
    test53/os hardened
```

</details>

---

## test54
**Printer** — Expanding USE flags output

Expanding use flags output

**Expected:** The printer should succesfully split up the different expanding use

![test54](test54/test54.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.73 s (backtrack: 0/20).

[ebuild  N     ] test54/app-1.0::overlay  USE="xattr -apidoc -bar1 -bar2 -bar3 -bar4 -bar5 -bar6 -bar7 -bar8 -bar9 -bar10 -bar11 -bar12 -bar13 -build -doc -foo1 -foo2 -foo3 -foo4 -foo5 -foo6 -foo7 -foo8 -foo9 -foo10 -foo11 -gentoo-dev -ipc -my_expanding_use_bar -my_expanding_use_cow -my_expanding_use_foo -native-extensions -rsync-verify (-selinux) -test" ALSA_CARDS="-bar -echo3g -emu10k1 -foo" VIDEO_CARDS="vmware -nouveau (-v3d) -zink" 0 KiB

Total: 1 package (1 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test54/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test54/app-1.0

 └─step  2─┤ install   overlay://test54/app-1.0
             │           └─ conf ─┤ USE = "xattr* -selinux% -apidoc -bar1 -bar10 -bar11 -bar12 -bar13 -bar2 -bar3 -bar4 -bar5 -bar6 -bar7 -bar8 -bar9 -build
             │                    │          -doc -foo1 -foo10 -foo11 -foo2 -foo3 -foo4 -foo5 -foo6 -foo7 -foo8 -foo9 -gentoo-dev -ipc -native-extensions
             │                    │          -rsync-verify -test"
             │                    │ ALSA_CARDS = "-bar -echo3g -emu10k1 -foo"
             │                    │ MY_EXPANDING_USE = "-bar -cow -foo"
             │                    │ VIDEO_CARDS = "vmware -nouveau -v3d -zink"

 └─step  3─┤ run     overlay://test54/app-1.0

Total: 3 actions (1 download, 1 install, 1 run), grouped into 3 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test55
**Version** — Constraint intersection (direct >3 + <6)

Multiple requirements should be combined. Only one version should be selected

**Expected:** The constraints on the lib versions should be combined. Only one version should be selected.

![test55](test55/test55.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.72 s (backtrack: 0/20).

[ebuild  N     ] test55/lib-6.0::overlay  0 KiB
[ebuild  N     ] test55/app-1.0::overlay  0 KiB

Total: 2 packages (2 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test55/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test55/lib-6.0
             │ download  overlay://test55/app-1.0

 └─step  2─┤ install   overlay://test55/lib-6.0

 └─step  3─┤ run       overlay://test55/lib-6.0

 └─step  4─┤ install   overlay://test55/app-1.0

 └─step  5─┤ run     overlay://test55/app-1.0

Total: 6 actions (2 downloads, 2 installs, 2 runs), grouped into 5 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test56
**Version** — Constraint intersection via dep chains

Multiple requirements should be combined. Only one version should be selected

**Expected:** The constraints on the lib versions should be combined. Only one version should be selected, since there is only one slot to fill.

![test56](test56/test56.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.73 s (backtrack: 0/20).

[ebuild  N     ] test56/lib-6.0::overlay  0 KiB
[ebuild  N     ] test56/modulea-1.0::overlay  0 KiB
[ebuild  N     ] test56/moduleb-1.0::overlay  0 KiB
[ebuild  N     ] test56/app-1.0::overlay  0 KiB

Total: 4 packages (4 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test56/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test56/moduleb-1.0
             │ download  overlay://test56/modulea-1.0
             │ download  overlay://test56/lib-6.0
             │ download  overlay://test56/app-1.0

 └─step  2─┤ install   overlay://test56/lib-6.0

 └─step  3─┤ run       overlay://test56/lib-6.0

 └─step  4─┤ install   overlay://test56/moduleb-1.0
             │ install   overlay://test56/modulea-1.0

 └─step  5─┤ run       overlay://test56/modulea-1.0
             │ run       overlay://test56/moduleb-1.0

 └─step  6─┤ install   overlay://test56/app-1.0

 └─step  7─┤ run     overlay://test56/app-1.0

Total: 12 actions (4 downloads, 4 installs, 4 runs), grouped into 7 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test57
**Virtual** — Virtual-style ebuild (explicit dep)

This test case validates that dependencies of a virtual-style ebuild are traversed
and that its provider package is included in the proof/model. The 'virtualsdk-1.0'
ebuild acts as a virtual by depending on 'linux-1.0' as its concrete provider.

**Expected:** When proving web-1.0, the plan/model should include linux-1.0 (via
virtualsdk-1.0). The full chain os -> virtualsdk -> linux should be resolved.

![test57](test57/test57.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.80 s (backtrack: 0/20).

[ebuild  N     ] test57/linux-1.0::overlay  0 KiB
[ebuild  N     ] test57/virtualsdk-1.0::overlay  0 KiB
[ebuild  N     ] test57/os-1.0::overlay  0 KiB
[ebuild  N     ] test57/db-1.0::overlay  0 KiB
[ebuild  N     ] test57/app-1.0::overlay  0 KiB
[ebuild  N     ] test57/web-1.0::overlay  0 KiB

Total: 6 packages (6 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test57/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test57/web-1.0
             │ download  overlay://test57/virtualsdk-1.0
             │ download  overlay://test57/os-1.0
             │ download  overlay://test57/linux-1.0
             │ download  overlay://test57/db-1.0
             │ download  overlay://test57/app-1.0

 └─step  2─┤ install   overlay://test57/virtualsdk-1.0
             │ install   overlay://test57/linux-1.0

 └─step  3─┤ run       overlay://test57/linux-1.0

 └─step  4─┤ install   overlay://test57/os-1.0

 └─step  5─┤ run       overlay://test57/virtualsdk-1.0

 └─step  6─┤ run       overlay://test57/os-1.0

 └─step  7─┤ install   overlay://test57/db-1.0

 └─step  8─┤ run       overlay://test57/db-1.0

 └─step  9─┤ install   overlay://test57/app-1.0

 └─step 10─┤ run       overlay://test57/app-1.0

 └─step 11─┤ install   overlay://test57/web-1.0

 └─step 12─┤ run     overlay://test57/web-1.0

Total: 18 actions (6 downloads, 6 installs, 6 runs), grouped into 12 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test58
**Virtual** — PROVIDE-based virtual (XFAIL)

> **XFAIL** — expected to fail.


This test case checks PROVIDE-based virtual satisfaction. The 'linux-1.0' package
claims to provide 'virtualsdk', which is not available as a standalone ebuild. The
resolver must recognize that 'linux-1.0' satisfies the virtual dependency through
its PROVIDE declaration. This is a deprecated PMS mechanism but still appears in
the wild.

**Expected:** Currently expected to fail (XFAIL) until PROVIDE/provider resolution is
implemented. Eventually, proving web-1.0 should pull in linux-1.0 to satisfy the
test58/virtualsdk dependency.

![test58](test58/test58.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.52 s (backtrack: 2/20).


emerge: there are no ebuilds to satisfy "test58/virtualsdk".
(dependency required by "test58/os-1.0::overlay" [ebuild])
(dependency required by "test58/web-1.0::overlay" [ebuild])
(dependency required by "test58/web" [argument])
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test58/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ verify  test58/os (unsatisfied constraints, assumed running)
             │ verify  test58/os (unsatisfied constraints, assumed installed)
             │ verify  test58/db (unsatisfied constraints, assumed running)
             │ verify  test58/app (unsatisfied constraints, assumed running)
             │ download  overlay://test58/web-1.0

 └─step  2─┤ install   overlay://test58/web-1.0

 └─step  3─┤ run     overlay://test58/web-1.0

Total: 3 actions (1 download, 1 install, 1 run), grouped into 3 steps.
       0.00 Kb to be downloaded.



Error The proof for your build plan contains domain assumptions. Please verify:


>>> Domain assumptions

- Unsatisfied constraints for run dependency: 
  test58/app

  required by: overlay://test58/web-1.0

- Unsatisfied constraints for run dependency: 
  test58/db

  required by: overlay://test58/web-1.0

- Unsatisfied constraints for install dependency: 
  test58/os

  required by: overlay://test58/web-1.0

- Unsatisfied constraints for run dependency: 
  test58/os

  required by: overlay://test58/web-1.0


>>> Bug report drafts (Gentoo Bugzilla)

---
Summary: overlay://test58/web-1.0: unsatisfied_constraints dependency on test58/app

Affected package: overlay://test58/web-1.0
Dependency: test58/app
Phases: [run]

Unsatisfiable constraint(s):
  test58/app-

Observed:
  portage-ng reports no available candidate satisfies the above constraint(s).
  Available versions in repo set (sample, first 1 of 1): [1.0]

Potential fix (suggestion):
  Review dependency metadata in overlay://test58/web-1.0; constraint set: [constraint(none,,[])].

---
Summary: overlay://test58/web-1.0: unsatisfied_constraints dependency on test58/db

Affected package: overlay://test58/web-1.0
Dependency: test58/db
Phases: [run]

Unsatisfiable constraint(s):
  test58/db-

Observed:
  portage-ng reports no available candidate satisfies the above constraint(s).
  Available versions in repo set (sample, first 1 of 1): [1.0]

Potential fix (suggestion):
  Review dependency metadata in overlay://test58/web-1.0; constraint set: [constraint(none,,[])].

---
Summary: overlay://test58/web-1.0: unsatisfied_constraints dependency on test58/os

Affected package: overlay://test58/web-1.0
Dependency: test58/os
Phases: [install,run]

Unsatisfiable constraint(s):
  test58/os-

Observed:
  portage-ng reports no available candidate satisfies the above constraint(s).
  Available versions in repo set (sample, first 1 of 1): [1.0]

Potential fix (suggestion):
  Review dependency metadata in overlay://test58/web-1.0; constraint set: [constraint(none,,[])].
```

</details>

---

## test59
**Regression** — Any-of || selection regression (XFAIL)

> **XFAIL** — expected to fail.


This is an XFAIL regression test for a known bug where the any-of group (||) does
not force the solver to select at least one alternative. Structurally similar to
test21 (any-of in RDEPEND), but this test uses different package names and exists
specifically to track the regression where any-of members can all be dropped from
the model.

**Expected:** Currently expected to fail (XFAIL): the solver does not force selecting one
alternative from the any-of group. When the bug is fixed, the model should contain
either data_fast-1.0 or data_best-1.0.

![test59](test59/test59.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.74 s (backtrack: 0/20).

[ebuild  N     ] test59/data_fast-1.0::overlay  0 KiB
[ebuild  N     ] test59/os-1.0::overlay  0 KiB
[ebuild  N     ] test59/db-1.0::overlay  0 KiB
[ebuild  N     ] test59/app-1.0::overlay  0 KiB
[ebuild  N     ] test59/web-1.0::overlay  0 KiB

Total: 5 packages (5 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test59/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test59/web-1.0
             │ download  overlay://test59/os-1.0
             │ download  overlay://test59/db-1.0
             │ download  overlay://test59/data_fast-1.0
             │ download  overlay://test59/app-1.0

 └─step  2─┤ install   overlay://test59/os-1.0
             │ install   overlay://test59/data_fast-1.0

 └─step  3─┤ run       overlay://test59/data_fast-1.0

 └─step  4─┤ run       overlay://test59/os-1.0

 └─step  5─┤ install   overlay://test59/db-1.0

 └─step  6─┤ run       overlay://test59/db-1.0

 └─step  7─┤ install   overlay://test59/app-1.0

 └─step  8─┤ run       overlay://test59/app-1.0

 └─step  9─┤ install   overlay://test59/web-1.0

 └─step 10─┤ run     overlay://test59/web-1.0

Total: 15 actions (5 downloads, 5 installs, 5 runs), grouped into 10 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test60
**Blocker** — Versioned soft blocker !<pkg-ver (XFAIL)

> **XFAIL** — expected to fail.


This test case checks the handling of versioned soft blockers (!<pkg-version). The
'app-1.0' package blocks any version of 'windows' less than 2.0. The any-of group
on 'os-1.0' offers both windows-1.0 and windows-2.0 as choices. The solver should
avoid windows-1.0 because it falls within the blocker's version range.

**Expected:** Currently expected to fail (XFAIL): the versioned blocker is handled via
assumptions rather than by steering the version choice. When fixed, the solver
should select windows-2.0 and avoid windows-1.0.

![test60](test60/test60.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.75 s (backtrack: 0/20).

[ebuild  N     ] test60/windows-2.0::overlay  0 KiB
[ebuild  N     ] test60/os-1.0::overlay  0 KiB
[ebuild  N     ] test60/app-1.0::overlay  0 KiB
[ebuild  N     ] test60/db-1.0::overlay  0 KiB
[ebuild  N     ] test60/web-1.0::overlay  0 KiB

Total: 5 packages (5 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test60/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test60/windows-1.0
             │ download  overlay://test60/web-1.0
             │ download  overlay://test60/os-1.0
             │ download  overlay://test60/db-1.0
             │ download  overlay://test60/app-1.0

 └─step  2─┤ install   overlay://test60/windows-1.0

 └─step  3─┤ run       overlay://test60/windows-1.0 (blocked: soft by test60/app)

 └─step  4─┤ install   overlay://test60/os-1.0

 └─step  5─┤ run       overlay://test60/os-1.0

 └─step  6─┤ install   overlay://test60/app-1.0
             │ install   overlay://test60/db-1.0

 └─step  7─┤ run       overlay://test60/db-1.0
             │ run       overlay://test60/app-1.0

 └─step  8─┤ install   overlay://test60/web-1.0

 └─step  9─┤ run     overlay://test60/web-1.0

Total: 15 actions (5 downloads, 5 installs, 5 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.



>>> Blockers added during proving & planning:

  [blocks B] !<test60/windows-2.0 (soft blocker, phase: run, required by: overlay://test60/app-1.0)
```

</details>

---

## test61
**Cycle** — Mutual recursion with bracketed USE

This test case checks termination and cycle handling when bracketed USE
dependencies ([foo]) are present in a mutual recursion. The 'a' and 'b' packages
each require the other with a specific USE flag. The prover must ensure that the
build_with_use context does not grow unbounded as it traverses the cycle.

**Expected:** The solver should terminate quickly, either by cycle breaking or by producing a
finite plan. It must not spin or backtrack indefinitely due to accumulating USE
context.

![test61](test61/test61.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  .... done!
Dependency resolution took 0.76 s (backtrack: 0/20).



[ebuild  N     ] test61/app-1.0::overlay  0 KiB
[nomerge       ]  test61/a-1.0::overlay  USE="foo" 
[ebuild  N     ]   test61/b-1.0::overlay  USE="foo" 0 KiB
[ebuild  N     ]    test61/a-1.0::overlay  USE="foo" 0 KiB

Total: 3 packages (3 new), Size of downloads: 0 KiB

 * Error: circular dependencies:

(test61/b-1.0:0/0::overlay, ebuild scheduled for merge) depends on
 (test61/a-1.0:0/0::overlay, ebuild scheduled for merge) (buildtime)
  (test61/b-1.0:0/0::overlay, ebuild scheduled for merge) (buildtime)

 * Note that circular dependencies can often be avoided by temporarily
 * disabling USE flags that trigger optional dependencies.

The following USE changes are necessary to proceed:
 (see "package.use" in the portage(5) man page for more details)
# required by test61/a-1.0::overlay
# required by test61/app-1.0::overlay
# required by test61/app (argument)
>=test61/b-1.0 foo
# required by test61/b-1.0::overlay
>=test61/a-1.0 foo

 * In order to avoid wasting time, backtracking has terminated early
 * due to the above autounmask change(s). The --autounmask-backtrack=y
 * option can be used to force further backtracking, but there is no
 * guarantee that it will produce a solution.
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test61/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ useflag overlay://test61/a-1.0 (foo)
             │ useflag overlay://test61/b-1.0 (foo)

 └─step  2─┤ verify  overlay://test61/a-1.0 (assumed installed)
             │ verify  overlay://test61/a-1.0 (assumed running) 
             │ verify  overlay://test61/b-1.0 (assumed installed)
             │ verify  test61/a (assumed running) 
             │ verify  test61/b (assumed running) 
             │ download  overlay://test61/b-1.0
             │ download  overlay://test61/app-1.0
             │ download  overlay://test61/a-1.0

 └─step  3─┤ install   overlay://test61/b-1.0 (USE modified)
             │           └─ conf ─┤ USE = "foo"

 └─step  4─┤ run       overlay://test61/b-1.0 (USE modified)

 └─step  5─┤ install   overlay://test61/a-1.0
             │           └─ conf ─┤ USE = "-foo"

 └─step  6─┤ run       overlay://test61/a-1.0 (USE modified)

 └─step  7─┤ install   overlay://test61/app-1.0

 └─step  8─┤ run     overlay://test61/app-1.0

Total: 11 actions (2 useflags, 3 downloads, 3 installs, 3 runs), grouped into 8 steps.
       0.00 Kb to be downloaded.



>>> Assumptions taken during proving & planning:

  USE flag change (2 packages):
  Add to /etc/portage/package.use:
    test61/a foo
    test61/b foo

>>> Cycle breaks (prover)

  grouped_package_dependency(no,test61,a,[package_dependency(run,no,test61,a,none,version_none,[],[use(enable(foo),none)])]):run
  grouped_package_dependency(no,test61,b,[package_dependency(run,no,test61,b,none,version_none,[],[use(enable(foo),none)])]):run
  overlay://test61/a-1.0:install
  overlay://test61/a-1.0:run
  overlay://test61/b-1.0:install
```

</details>

---

## test62
**Cycle** — Simple mutual cycle (termination)

This test case is a prover termination regression test for simple mutual dependency
cycles without blockers, slots, or USE flags. It checks whether per-goal context
growth (e.g. accumulating self() markers or slot information) can defeat cycle
detection and cause backtracking until timeout.

**Expected:** The prover should terminate quickly with a finite model/plan, or fail fast. It must
not spin or backtrack indefinitely. A cycle-break assumption is expected.

![test62](test62/test62.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.75 s (backtrack: 0/20).

[ebuild  N     ] test62/a-1.0::overlay  0 KiB
[ebuild  N     ] test62/b-1.0::overlay  0 KiB
[ebuild  N     ] test62/web-1.0::overlay  0 KiB

Total: 3 packages (3 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test62/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ verify  test62/a (assumed running) 
             │ download  overlay://test62/web-1.0
             │ download  overlay://test62/b-1.0
             │ download  overlay://test62/a-1.0

 └─step  2─┤ install   overlay://test62/b-1.0

 └─step  3─┤ run       overlay://test62/b-1.0

 └─step  4─┤ install   overlay://test62/a-1.0

 └─step  5─┤ run       overlay://test62/a-1.0

 └─step  6─┤ install   overlay://test62/web-1.0

 └─step  7─┤ run     overlay://test62/web-1.0

Total: 9 actions (3 downloads, 3 installs, 3 runs), grouped into 7 steps.
       0.00 Kb to be downloaded.


>>> Cycle breaks (prover)

  grouped_package_dependency(no,test62,a,[package_dependency(run,no,test62,a,none,version_none,[],[])]):run
```

</details>

---

## test63
**Cycle** — REQUIRED_USE loop reproducer (openmpi-style)

This test case reproduces the prover timeout trace seen in portage for packages
that pull sys-cluster/openmpi, where proving hits a sequence of
use_conditional_group/4 items for mutually exclusive flags. It is a tiny
overlay-only reproducer intended to isolate backtracking/timeout behaviour without
involving the full portage tree.

**Expected:** The prover should complete without timing out. The plan should include app-1.0 and
openmpi-4.1.6-r1 with a valid REQUIRED_USE configuration.

![test63](test63/test63.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.48 s (backtrack: 0/20).


!!! The ebuild selected to satisfy "test63/openmpi" has unmet requirements.
- test63/openmpi-4.1.6-r1::overlay USE="" OPENMPI_FABRICS="-ofed" OPENMPI_OFED_FEATURES="-control-hdr-padding -dynamic-sl -rdmacm -udcm" OPENMPI_RM="pbs slurm"

  The following REQUIRED_USE flag constraints are unsatisfied:
    openmpi_rm_slurm? ( !openmpi_rm_pbs ) openmpi_rm_pbs? ( !openmpi_rm_slurm )

  The above constraints are a subset of the following complete expression:
    openmpi_rm_slurm? ( !openmpi_rm_pbs ) openmpi_rm_pbs? ( !openmpi_rm_slurm ) openmpi_ofed_features_control-hdr-padding? ( openmpi_fabrics_ofed ) openmpi_ofed_features_udcm? ( openmpi_fabrics_ofed ) openmpi_ofed_features_rdmacm? ( openmpi_fabrics_ofed ) openmpi_ofed_features_dynamic-sl? ( openmpi_fabrics_ofed )

(dependency required by "test63/mpibash-1.3-r1::overlay" [ebuild])
(dependency required by "test63/app-1.0::overlay" [ebuild])
(dependency required by "test63/app" [argument])
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test63/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ useflag overlay://test63/openmpi-4.1.6-r1 (-openmpi_rm_pbs -openmpi_rm_slurm)

 └─step  2─┤ download  overlay://test63/openmpi-4.1.6-r1
             │ download  overlay://test63/mpibash-1.3-r1
             │ download  overlay://test63/app-1.0

 └─step  3─┤ install   overlay://test63/openmpi-4.1.6-r1 (USE modified)
             │           └─ conf ─┤ USE = ""
             │                    │ OPENMPI_FABRICS = "-ofed"
             │                    │ OPENMPI_OFED_FEATURES = "-control-hdr-padding -dynamic-sl -rdmacm -udcm"
             │                    │ OPENMPI_RM = "-pbs -slurm"

 └─step  4─┤ run       overlay://test63/openmpi-4.1.6-r1

 └─step  5─┤ install   overlay://test63/mpibash-1.3-r1

 └─step  6─┤ run       overlay://test63/mpibash-1.3-r1

 └─step  7─┤ install   overlay://test63/app-1.0

 └─step  8─┤ run     overlay://test63/app-1.0

Total: 10 actions (1 useflag, 3 downloads, 3 installs, 3 runs), grouped into 8 steps.
       0.00 Kb to be downloaded.


>>> Assumptions taken during proving & planning:

  USE flag change (1 package):
  Add to /etc/portage/package.use:
    test63/openmpi -openmpi_rm_pbs -openmpi_rm_slurm
```

</details>

---

## test64
**Cycle** — USE-conditional churn reproducer (openmp-style)

This test case reproduces the small backtracking/churn pattern observed for
llvm-runtimes/openmp in a tiny overlay-only setup. The real openmp metadata
includes IUSE flags, USE-gated dependencies, and REQUIRED_USE groups that can
cause excessive proof retries.

**Expected:** The prover should complete without timing out. A valid plan should be produced that
respects all REQUIRED_USE constraints and USE-conditional dependencies.

![test64](test64/test64.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.76 s (backtrack: 0/20).

[ebuild  N     ] test64/perl-1.0::overlay  0 KiB
[ebuild  N     ] test64/ninja-1.0::overlay  0 KiB
[ebuild  N     ] test64/cmake-1.0::overlay  0 KiB
[ebuild  N     ] test64/openmp-1.0::overlay  USE="-gdb-plugin -hwloc -test -verify-sig" PYTHON_SINGLE_TARGET="python3_13 -python3_12" 0 KiB
[ebuild  N     ] test64/app-1.0::overlay  0 KiB

Total: 5 packages (5 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test64/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test64/perl-1.0
             │ download  overlay://test64/openmp-1.0
             │ download  overlay://test64/ninja-1.0
             │ download  overlay://test64/cmake-1.0
             │ download  overlay://test64/app-1.0

 └─step  2─┤ install   overlay://test64/cmake-1.0
             │ install   overlay://test64/ninja-1.0
             │ install   overlay://test64/perl-1.0

 └─step  3─┤ install   overlay://test64/openmp-1.0
             │           └─ conf ─┤ USE = "-gdb-plugin -hwloc -test -verify-sig"
             │                    │ PYTHON_SINGLE_TARGET = "python3_13 -python3_12"

 └─step  4─┤ run       overlay://test64/openmp-1.0

 └─step  5─┤ install   overlay://test64/app-1.0

 └─step  6─┤ run     overlay://test64/app-1.0

Total: 12 actions (5 downloads, 5 installs, 2 runs), grouped into 6 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test65
**Installed** — build_with_use reinstall semantics

This test case is a regression test for rules:installed_entry_satisfies_build_with_use/2.
It ensures that an installed VDB entry cannot be treated as satisfying a dependency
if incoming build_with_use requires a flag that the installed package was not built
with. The test uses an always-false flag requirement (__portage_ng_test_flag__)
against an arbitrary installed package.

**Expected:** The test validation checks that the rule correctly identifies unsatisfied
build_with_use requirements on installed packages. The prover should find that no
installed entry satisfies the synthetic flag requirement, and the rule should
produce non-empty conditions.

![test65](test65/test65.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.76 s (backtrack: 0/20).

[ebuild  N     ] test65/app-1.0::overlay  0 KiB

Total: 1 package (1 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test65/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test65/app-1.0

 └─step  2─┤ install   overlay://test65/app-1.0

 └─step  3─┤ run     overlay://test65/app-1.0

Total: 3 actions (1 download, 1 install, 1 run), grouped into 3 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test66
**PDEPEND** — Post-merge dependency resolution

This test case checks the prover's handling of PDEPEND (post-merge dependencies).
The 'lib-1.0' package declares 'plugin-1.0' as a PDEPEND, meaning plugin-1.0
should be resolved after lib-1.0's installation, not as a prerequisite.

**Expected:** All three packages should appear in the proof/plan. The plugin-1.0 package should
be ordered after lib-1.0's install step via the PDEPEND proof obligation mechanism.

![test66](test66/test66.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.74 s (backtrack: 0/20).

[ebuild  N     ] test66/plugin-1.0::overlay  0 KiB
[ebuild  N     ] test66/lib-1.0::overlay  0 KiB
[ebuild  N     ] test66/app-1.0::overlay  0 KiB

Total: 3 packages (3 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test66/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test66/plugin-1.0
             │ download  overlay://test66/lib-1.0
             │ download  overlay://test66/app-1.0

 └─step  2─┤ install   overlay://test66/lib-1.0
             │ install   overlay://test66/plugin-1.0

 └─step  3─┤ run       overlay://test66/lib-1.0

 └─step  4─┤ install   overlay://test66/app-1.0

 └─step  5─┤ run     overlay://test66/app-1.0

 └─step  6─┤ run       overlay://test66/plugin-1.0

Total: 9 actions (3 downloads, 3 installs, 3 runs), grouped into 6 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test67
**BDEPEND** — Build-only dependency (separate from DEPEND)

This test case checks the prover's handling of BDEPEND (build dependencies). The
'app-1.0' package requires 'toolchain-1.0' only for building (BDEPEND), separate
from its runtime dependency on 'lib-1.0'. BDEPEND is resolved alongside DEPEND
for the install phase.

**Expected:** All three packages should appear in the proof. The toolchain-1.0 should be
resolved as a build dependency of app-1.0, while lib-1.0 is resolved as a runtime
dependency.

![test67](test67/test67.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.74 s (backtrack: 0/20).

[ebuild  N     ] test67/lib-1.0::overlay  0 KiB
[ebuild  N     ] test67/toolchain-1.0::overlay  0 KiB
[ebuild  N     ] test67/app-1.0::overlay  0 KiB

Total: 3 packages (3 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test67/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test67/toolchain-1.0
             │ download  overlay://test67/lib-1.0
             │ download  overlay://test67/app-1.0

 └─step  2─┤ install   overlay://test67/lib-1.0
             │ install   overlay://test67/toolchain-1.0

 └─step  3─┤ run       overlay://test67/lib-1.0

 └─step  4─┤ install   overlay://test67/app-1.0

 └─step  5─┤ run     overlay://test67/app-1.0

Total: 8 actions (3 downloads, 3 installs, 2 runs), grouped into 5 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test68
**Multi-slot** — Co-installation of same CN in different slots

This test case checks the prover's ability to resolve dependencies on multiple
slots of the same package simultaneously. The 'app-1.0' package requires both
slot 1 and slot 2 of 'lib', which correspond to different versions. Both must
appear in the plan since different slots can coexist.

**Expected:** Both lib-1.0 (slot 1) and lib-2.0 (slot 2) should appear in the proof. The prover
should recognize that different slots are independent installation targets and
include both in the plan.

![test68](test68/test68.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.74 s (backtrack: 0/20).

[ebuild  N     ] test68/lib-1.0:1::overlay  0 KiB
[ebuild  N     ] test68/lib-2.0:2::overlay  0 KiB
[ebuild  N     ] test68/app-1.0::overlay  0 KiB

Total: 3 packages (3 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test68/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test68/lib-2.0
             │ download  overlay://test68/lib-1.0
             │ download  overlay://test68/app-1.0

 └─step  2─┤ install   overlay://test68/lib-1.0
             │           └─ conf ─┤ SLOT = "1"
             │ install   overlay://test68/lib-2.0
             │           └─ conf ─┤ SLOT = "2"

 └─step  3─┤ install   overlay://test68/app-1.0

 └─step  4─┤ run     overlay://test68/app-1.0

Total: 7 actions (3 downloads, 3 installs, 1 run), grouped into 4 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test69
**Version** — Operator >= (greater-or-equal)

This test case checks the prover's handling of the >= (greater-or-equal) version
operator. The 'app-1.0' package requires lib version 3.0 or higher. Versions 1.0
and 2.0 should be excluded; versions 3.0, 4.0, and 5.0 are valid candidates.

**Expected:** The prover should select the latest valid version, lib-5.0, to satisfy the
dependency. Versions 1.0 and 2.0 should not appear in the proof.

![test69](test69/test69.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.74 s (backtrack: 0/20).

[ebuild  N     ] test69/lib-5.0::overlay  0 KiB
[ebuild  N     ] test69/app-1.0::overlay  0 KiB

Total: 2 packages (2 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test69/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test69/lib-5.0
             │ download  overlay://test69/app-1.0

 └─step  2─┤ install   overlay://test69/lib-5.0

 └─step  3─┤ install   overlay://test69/app-1.0

 └─step  4─┤ run     overlay://test69/app-1.0

Total: 5 actions (2 downloads, 2 installs, 1 run), grouped into 4 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test70
**Version** — Operator ~ (revision match)

This test case checks the prover's handling of the ~ (revision match) version
operator. The dependency ~lib-2.0 should match lib-2.0 and lib-2.0-r1 (any
revision of the 2.0 base version) but NOT lib-3.0 (different base version).

**Expected:** The prover should select lib-2.0-r1 (the latest matching revision of 2.0). 
lib-3.0 should not be considered a valid candidate for this dependency.

![test70](test70/test70.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.73 s (backtrack: 0/20).

[ebuild  N     ] test70/lib-2.0-r1::overlay  0 KiB
[ebuild  N     ] test70/app-1.0::overlay  0 KiB

Total: 2 packages (2 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test70/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test70/lib-2.0-r1
             │ download  overlay://test70/app-1.0

 └─step  2─┤ install   overlay://test70/lib-2.0-r1

 └─step  3─┤ install   overlay://test70/app-1.0

 └─step  4─┤ run     overlay://test70/app-1.0

Total: 5 actions (2 downloads, 2 installs, 1 run), grouped into 4 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test71
**Fetchonly** — Download-only action

This test case checks the prover's handling of the fetchonly action. The dependency
structure is identical to test01, but the entry point uses :fetchonly instead of
:run. In fetchonly mode, only download actions should be produced, with no
install/run steps.

**Expected:** All four packages should appear in the proof with download/fetchonly actions. No
install or run steps should be produced in the plan.

![test71](test71/test71.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be fetched, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.75 s (backtrack: 0/20).
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test71/web-1.0:fetchonly?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test71/web-1.0
             │ download  overlay://test71/os-1.0
             │ download  overlay://test71/db-1.0
             │ download  overlay://test71/app-1.0

Total: 4 actions (4 downloads), grouped into 1 step.
       0.00 Kb to be downloaded.
```

</details>

---

## test72
**IDEPEND** — Install-time dependency

This test case checks the prover's handling of IDEPEND (install-time dependencies).
IDEPEND is an EAPI 8 feature that specifies packages needed at install time on the
target system (as opposed to BDEPEND which is for the build system). The 'app-1.0'
package requires 'installer-1.0' at install time.

**Expected:** Both packages should appear in the proof. The installer-1.0 should be resolved as
an install-time dependency and be available before app-1.0's install phase.

![test72](test72/test72.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.75 s (backtrack: 0/20).

[ebuild  N     ] test72/installer-1.0::overlay  0 KiB
[ebuild  N     ] test72/app-1.0::overlay  0 KiB

Total: 2 packages (2 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test72/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test72/installer-1.0
             │ download  overlay://test72/app-1.0

 └─step  2─┤ install   overlay://test72/installer-1.0

 └─step  3─┤ install   overlay://test72/app-1.0

 └─step  4─┤ run     overlay://test72/app-1.0

Total: 5 actions (2 downloads, 2 installs, 1 run), grouped into 4 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test73
**Update** — Installed old version, newer available (VDB)

This test case checks the prover's update path. When lib-1.0 is already installed
and lib-2.0 is available, the prover should detect that an update is possible and
trigger the :update action instead of :install. This requires VDB simulation to
mark lib-1.0 as installed.

**Expected:** The prover should select lib-2.0 as an update replacing the installed lib-1.0. The
plan should show an update action for lib, not a fresh install.

![test73](test73/test73.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.78 s (backtrack: 0/20).

[ebuild  N     ] test73/lib-2.0::overlay  0 KiB
[ebuild  N     ] test73/app-1.0::overlay  0 KiB

Total: 2 packages (2 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test73/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test73/lib-2.0
             │ download  overlay://test73/app-1.0

 └─step  2─┤ install   overlay://test73/lib-2.0

 └─step  3─┤ install   overlay://test73/app-1.0

 └─step  4─┤ run     overlay://test73/app-1.0

Total: 5 actions (2 downloads, 2 installs, 1 run), grouped into 4 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test74
**Downgrade** — Installed newer, constraint forces older (VDB)

This test case checks the prover's downgrade path. When lib-2.0 is installed but
app-1.0 requires exactly lib-1.0 (via the = operator), the prover should detect
that a downgrade is needed. The same-slot installed version is newer than the
required version.

**Expected:** The prover should select lib-1.0 as a downgrade replacing the installed lib-2.0.
The plan should show a downgrade action for lib.

![test74](test74/test74.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.77 s (backtrack: 0/20).

[ebuild  N     ] test74/lib-1.0::overlay  0 KiB
[ebuild  N     ] test74/app-1.0::overlay  0 KiB

Total: 2 packages (2 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test74/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test74/lib-1.0
             │ download  overlay://test74/app-1.0

 └─step  2─┤ install   overlay://test74/lib-1.0

 └─step  3─┤ install   overlay://test74/app-1.0

 └─step  4─┤ run     overlay://test74/app-1.0

Total: 5 actions (2 downloads, 2 installs, 1 run), grouped into 4 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test75
**Reinstall** — Installed same version, emptytree (VDB)

This test case checks the prover's behavior when the --emptytree flag is active.
Even though os-1.0 is already installed, the emptytree flag should force the
prover to re-prove it rather than skipping it as satisfied. This exercises the
reinstall path.

**Expected:** With emptytree behavior, os-1.0 should appear in the proof despite being installed.
The plan should include a reinstall or fresh install action for os-1.0.

![test75](test75/test75.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.74 s (backtrack: 0/20).

[ebuild  N     ] test75/os-1.0::overlay  0 KiB
[ebuild  N     ] test75/app-1.0::overlay  0 KiB

Total: 2 packages (2 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test75/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test75/os-1.0
             │ download  overlay://test75/app-1.0

 └─step  2─┤ install   overlay://test75/os-1.0

 └─step  3─┤ run       overlay://test75/os-1.0

 └─step  4─┤ install   overlay://test75/app-1.0

 └─step  5─┤ run     overlay://test75/app-1.0

Total: 6 actions (2 downloads, 2 installs, 2 runs), grouped into 5 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test76
**Newuse** — Installed with wrong USE, rebuild needed (VDB)

This test case checks the prover's newuse rebuild behavior. The installed os-1.0
was built without the 'linux' USE flag, but app-1.0 requires os[linux]. The prover
should detect that the installed version does not satisfy the incoming
build_with_use requirement and trigger a rebuild.

**Expected:** The prover should detect that os-1.0 needs to be rebuilt with USE="linux" enabled.
The plan should include a rebuild action for os-1.0.

![test76](test76/test76.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.73 s (backtrack: 0/20).

[ebuild  N     ] test76/os-1.0::overlay  USE="linux -darwin" 0 KiB
[ebuild  N     ] test76/app-1.0::overlay  0 KiB

Total: 2 packages (2 new), Size of downloads: 0 KiB

The following USE changes are necessary to proceed:
 (see "package.use" in the portage(5) man page for more details)
# required by test76/app-1.0::overlay
# required by test76/app (argument)
>=test76/os-1.0 linux
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test76/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ useflag overlay://test76/os-1.0 (linux)

 └─step  2─┤ download  overlay://test76/os-1.0
             │ download  overlay://test76/app-1.0

 └─step  3─┤ install   overlay://test76/os-1.0 (USE modified)
             │           └─ conf ─┤ USE = "-darwin linux"

 └─step  4─┤ install   overlay://test76/app-1.0

 └─step  5─┤ run     overlay://test76/app-1.0

Total: 6 actions (1 useflag, 2 downloads, 2 installs, 1 run), grouped into 5 steps.
       0.00 Kb to be downloaded.


>>> Assumptions taken during proving & planning:

  USE flag change (1 package):
  Add to /etc/portage/package.use:
    test76/os linux
```

</details>

---

## test77
**Depclean** — Unused package removal (VDB)

This test case checks the depclean action. When run with :depclean, the prover
should traverse the installed dependency graph starting from world targets and
identify packages that are not reachable. The 'orphan-1.0' package is installed
but nothing depends on it, making it a candidate for removal.

**Expected:** The depclean analysis should identify orphan-1.0 as removable since it has no
reverse dependencies in the installed package graph. app-1.0 and os-1.0 should
be retained.

![test77](test77/test77.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.73 s (backtrack: 0/20).

[ebuild  N     ] test77/os-1.0::overlay  0 KiB
[ebuild  N     ] test77/app-1.0::overlay  0 KiB

Total: 2 packages (2 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test77/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test77/os-1.0
             │ download  overlay://test77/app-1.0

 └─step  2─┤ install   overlay://test77/os-1.0

 └─step  3─┤ run       overlay://test77/os-1.0

 └─step  4─┤ install   overlay://test77/app-1.0

 └─step  5─┤ run     overlay://test77/app-1.0

Total: 6 actions (2 downloads, 2 installs, 2 runs), grouped into 5 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test78
**Onlydeps** — Skip target, install deps only

This test case checks the --onlydeps behavior. When the entry point target
(web-1.0) is proven with the onlydeps_target context flag, the target package
itself should not appear in the install plan, but all of its dependencies should
still be resolved and included.

**Expected:** The dependencies (app-1.0, db-1.0, os-1.0) should appear in the proof and plan.
The target package web-1.0 should be excluded from the install actions, though it
may still appear in the proof for dependency traversal purposes.

![test78](test78/test78.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

[ebuild  N     ] test78/web-1.0::overlay  0 KiB

Total: 1 package (1 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test78/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test78/web-1.0
             │ download  overlay://test78/os-1.0
             │ download  overlay://test78/db-1.0
             │ download  overlay://test78/app-1.0

 └─step  2─┤ install   overlay://test78/os-1.0

 └─step  3─┤ run       overlay://test78/os-1.0

 └─step  4─┤ install   overlay://test78/db-1.0

 └─step  5─┤ run       overlay://test78/db-1.0

 └─step  6─┤ install   overlay://test78/app-1.0

 └─step  7─┤ run       overlay://test78/app-1.0

 └─step  8─┤ install   overlay://test78/web-1.0

 └─step  9─┤ run     overlay://test78/web-1.0

Total: 12 actions (4 downloads, 4 installs, 4 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.
```

</details>

---

## test79
**PDEPEND** — PDEPEND cycle (A needs B, B PDEPEND A)

This test case checks the handling of cycles involving PDEPEND. The server needs
the client at runtime, and the client has a PDEPEND back on the server. Since
PDEPEND is resolved post-install (via proof obligations), this cycle should be
naturally broken by the ordering: server installs first, then client, then the
PDEPEND obligation for server is already satisfied.

**Expected:** Both packages should appear in the proof without infinite loops. The PDEPEND cycle
should be handled gracefully by the proof obligation mechanism, not treated as a
hard circular dependency requiring assumptions.

![test79](test79/test79.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.73 s (backtrack: 0/20).

[ebuild  N     ] test79/client-1.0::overlay  0 KiB
[ebuild  N     ] test79/server-1.0::overlay  0 KiB

Total: 2 packages (2 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test79/server-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ verify  overlay://test79/server-1.0 (assumed running) 
             │ download  overlay://test79/server-1.0
             │ download  overlay://test79/client-1.0

 └─step  2─┤ install   overlay://test79/client-1.0

 └─step  3─┤ run       overlay://test79/client-1.0

 └─step  4─┤ install   overlay://test79/server-1.0

 └─step  5─┤ run     overlay://test79/server-1.0

Total: 6 actions (2 downloads, 2 installs, 2 runs), grouped into 5 steps.
       0.00 Kb to be downloaded.


>>> Cycle breaks (prover)

  overlay://test79/server-1.0:run
```

</details>

---

## test80
**Version** — Operator <= (less-or-equal)

This test case checks the prover's handling of the <= (less-or-equal) version
operator. The 'app-1.0' package requires lib version 3.0 or lower. Versions 4.0
and 5.0 should be excluded; versions 1.0, 2.0, and 3.0 are valid candidates.

**Expected:** The prover should select the latest valid version, lib-3.0, to satisfy the
dependency. Versions 4.0 and 5.0 should not be considered valid candidates.

![test80](test80/test80.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.74 s (backtrack: 0/20).

[ebuild  N     ] test80/lib-3.0::overlay  0 KiB
[ebuild  N     ] test80/app-1.0::overlay  0 KiB

Total: 2 packages (2 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test80/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test80/lib-3.0
             │ download  overlay://test80/app-1.0

 └─step  2─┤ install   overlay://test80/lib-3.0

 └─step  3─┤ install   overlay://test80/app-1.0

 └─step  4─┤ run     overlay://test80/app-1.0

Total: 5 actions (2 downloads, 2 installs, 1 run), grouped into 4 steps.
       0.00 Kb to be downloaded.
```

</details>

---
