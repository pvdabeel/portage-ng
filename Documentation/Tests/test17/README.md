# test17 — Exactly-one-of ^^ (compile)

**Category:** Choice

This test case evaluates the prover's handling of an 'exactly-one-of' dependency group (^^). The 'os-1.0' package requires that exactly one of the three OS packages be installed.

**Expected:** The prover should recognize the choice and select one of the available options (e.g., linux-1.0) to satisfy the dependency. Since there are no other constraints, any of the three choices should lead to a valid proof. The final plan will include app-1.0, os-1.0, and one of the three OS packages.

![test17](test17.svg)

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

 └─step  1─┤ verify  test17/os (unsatisfied constraints, assumed running)
             │ verify  test17/os (unsatisfied constraints, assumed installed)
             │ verify  test17/db (unsatisfied constraints, assumed running)
             │ verify  test17/app (unsatisfied constraints, assumed running)
             │ download  overlay://test17/web-1.0

 └─step  2─┤ install   overlay://test17/web-1.0

 └─step  3─┤ run     overlay://test17/web-1.0

Total: 3 actions (1 download, 1 install, 1 run), grouped into 3 steps.
       0.00 Kb to be downloaded.



Error The proof for your build plan contains domain assumptions. Please verify:


>>> Domain assumptions

- Unsatisfied constraints for run dependency: 
  test17/app

  required by: overlay://test17/web-1.0

- Unsatisfied constraints for run dependency: 
  test17/db

  required by: overlay://test17/web-1.0

- Unsatisfied constraints for install dependency: 
  test17/os

  required by: overlay://test17/web-1.0

- Unsatisfied constraints for run dependency: 
  test17/os

  required by: overlay://test17/web-1.0


>>> Bug report drafts (Gentoo Bugzilla)

---
Summary: overlay://test17/web-1.0: unsatisfied_constraints dependency on test17/app

Affected package: overlay://test17/web-1.0
Dependency: test17/app
Phases: [run]

Unsatisfiable constraint(s):
  test17/app-

Observed:
  portage-ng reports no available candidate satisfies the above constraint(s).
  Available versions in repo set (sample, first 1 of 1): [1.0]

Potential fix (suggestion):
  Review dependency metadata in overlay://test17/web-1.0; constraint set: [constraint(none,,[])].

---
Summary: overlay://test17/web-1.0: unsatisfied_constraints dependency on test17/db

Affected package: overlay://test17/web-1.0
Dependency: test17/db
Phases: [run]

Unsatisfiable constraint(s):
  test17/db-

Observed:
  portage-ng reports no available candidate satisfies the above constraint(s).
  Available versions in repo set (sample, first 1 of 1): [1.0]

Potential fix (suggestion):
  Review dependency metadata in overlay://test17/web-1.0; constraint set: [constraint(none,,[])].

---
Summary: overlay://test17/web-1.0: unsatisfied_constraints dependency on test17/os

Affected package: overlay://test17/web-1.0
Dependency: test17/os
Phases: [install,run]

Unsatisfiable constraint(s):
  test17/os-

Observed:
  portage-ng reports no available candidate satisfies the above constraint(s).
  Available versions in repo set (sample, first 1 of 1): [1.0]

Potential fix (suggestion):
  Review dependency metadata in overlay://test17/web-1.0; constraint set: [constraint(none,,[])].
```

</details>