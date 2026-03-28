# test25 — At-most-one-of ?? (compile + runtime)

**Category:** Choice

This test case combines test23 and test24. The 'os-1.0' package has the same 'at-most-one-of' choice group in both its compile-time and runtime dependencies.

**Expected:** The prover should resolve both dependencies by choosing to install none of the optional packages, as this is the simplest valid solution. The proof should be valid.

![test25](test25.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.33 s (backtrack: 1/20).


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

 └─step  1─┤ verify  test25/os (unsatisfied constraints, assumed running)
             │ verify  test25/os (unsatisfied constraints, assumed installed)
             │ verify  test25/db (unsatisfied constraints, assumed running)
             │ verify  test25/app (unsatisfied constraints, assumed running)
             │ download  overlay://test25/web-1.0

 └─step  2─┤ install   overlay://test25/web-1.0

 └─step  3─┤ run     overlay://test25/web-1.0

Total: 3 actions (1 download, 1 install, 1 run), grouped into 3 steps.
       0.00 Kb to be downloaded.



Error The proof for your build plan contains domain assumptions. Please verify:


>>> Domain assumptions

- Unsatisfied constraints for run dependency: 
  test25/app

  required by: overlay://test25/web-1.0

- Unsatisfied constraints for run dependency: 
  test25/db

  required by: overlay://test25/web-1.0

- Unsatisfied constraints for install dependency: 
  test25/os

  required by: overlay://test25/web-1.0

- Unsatisfied constraints for run dependency: 
  test25/os

  required by: overlay://test25/web-1.0


>>> Bug report drafts (Gentoo Bugzilla)

---
Summary: overlay://test25/web-1.0: unsatisfied_constraints dependency on test25/app

Affected package: overlay://test25/web-1.0
Dependency: test25/app
Phases: [run]

Unsatisfiable constraint(s):
  test25/app-

Observed:
  portage-ng reports no available candidate satisfies the above constraint(s).
  Available versions in repo set (sample, first 1 of 1): [1.0]

Potential fix (suggestion):
  Review dependency metadata in overlay://test25/web-1.0; constraint set: [constraint(none,,[])].

---
Summary: overlay://test25/web-1.0: unsatisfied_constraints dependency on test25/db

Affected package: overlay://test25/web-1.0
Dependency: test25/db
Phases: [run]

Unsatisfiable constraint(s):
  test25/db-

Observed:
  portage-ng reports no available candidate satisfies the above constraint(s).
  Available versions in repo set (sample, first 1 of 1): [1.0]

Potential fix (suggestion):
  Review dependency metadata in overlay://test25/web-1.0; constraint set: [constraint(none,,[])].

---
Summary: overlay://test25/web-1.0: unsatisfied_constraints dependency on test25/os

Affected package: overlay://test25/web-1.0
Dependency: test25/os
Phases: [install,run]

Unsatisfiable constraint(s):
  test25/os-

Observed:
  portage-ng reports no available candidate satisfies the above constraint(s).
  Available versions in repo set (sample, first 1 of 1): [1.0]

Potential fix (suggestion):
  Review dependency metadata in overlay://test25/web-1.0; constraint set: [constraint(none,,[])].



```

</details>