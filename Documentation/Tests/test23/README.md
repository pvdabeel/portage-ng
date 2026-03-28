# test23 — At-most-one-of ?? (compile)

**Category:** Choice

This test case evaluates the prover's handling of an 'at-most-one-of' dependency group (??). The 'os-1.0' package requires that at most one of the three OS packages be installed. This also means that installing *none* of them is a valid resolution.

**Expected:** The prover should satisfy the dependency by choosing to install nothing from the group, as this is the simplest path. A valid proof should be generated for app-1.0 and os-1.0, without any of the optional OS packages.

![test23](test23.svg)

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

 └─step  1─┤ verify  test23/os (unsatisfied constraints, assumed running)
             │ verify  test23/os (unsatisfied constraints, assumed installed)
             │ verify  test23/db (unsatisfied constraints, assumed running)
             │ verify  test23/app (unsatisfied constraints, assumed running)
             │ download  overlay://test23/web-1.0

 └─step  2─┤ install   overlay://test23/web-1.0

 └─step  3─┤ run     overlay://test23/web-1.0

Total: 3 actions (1 download, 1 install, 1 run), grouped into 3 steps.
       0.00 Kb to be downloaded.



Error The proof for your build plan contains domain assumptions. Please verify:


>>> Domain assumptions

- Unsatisfied constraints for run dependency: 
  test23/app

  required by: overlay://test23/web-1.0

- Unsatisfied constraints for run dependency: 
  test23/db

  required by: overlay://test23/web-1.0

- Unsatisfied constraints for install dependency: 
  test23/os

  required by: overlay://test23/web-1.0

- Unsatisfied constraints for run dependency: 
  test23/os

  required by: overlay://test23/web-1.0


>>> Bug report drafts (Gentoo Bugzilla)

---
Summary: overlay://test23/web-1.0: unsatisfied_constraints dependency on test23/app

Affected package: overlay://test23/web-1.0
Dependency: test23/app
Phases: [run]

Unsatisfiable constraint(s):
  test23/app-

Observed:
  portage-ng reports no available candidate satisfies the above constraint(s).
  Available versions in repo set (sample, first 1 of 1): [1.0]

Potential fix (suggestion):
  Review dependency metadata in overlay://test23/web-1.0; constraint set: [constraint(none,,[])].

---
Summary: overlay://test23/web-1.0: unsatisfied_constraints dependency on test23/db

Affected package: overlay://test23/web-1.0
Dependency: test23/db
Phases: [run]

Unsatisfiable constraint(s):
  test23/db-

Observed:
  portage-ng reports no available candidate satisfies the above constraint(s).
  Available versions in repo set (sample, first 1 of 1): [1.0]

Potential fix (suggestion):
  Review dependency metadata in overlay://test23/web-1.0; constraint set: [constraint(none,,[])].

---
Summary: overlay://test23/web-1.0: unsatisfied_constraints dependency on test23/os

Affected package: overlay://test23/web-1.0
Dependency: test23/os
Phases: [install,run]

Unsatisfiable constraint(s):
  test23/os-

Observed:
  portage-ng reports no available candidate satisfies the above constraint(s).
  Available versions in repo set (sample, first 1 of 1): [1.0]

Potential fix (suggestion):
  Review dependency metadata in overlay://test23/web-1.0; constraint set: [constraint(none,,[])].



```

</details>