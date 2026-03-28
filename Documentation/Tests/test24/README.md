# test24 — At-most-one-of ?? (runtime)

**Category:** Choice

This is a variation of test23, with the 'at-most-one-of' dependency group in the runtime scope (RDEPEND).

**Expected:** The prover should satisfy the runtime dependency by choosing to install none of the optional OS packages. The proof should be valid.

![test24](test24.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.32 s (backtrack: 1/20).


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

 └─step  1─┤ verify  test24/os (unsatisfied constraints, assumed running)
             │ verify  test24/os (unsatisfied constraints, assumed installed)
             │ verify  test24/db (unsatisfied constraints, assumed running)
             │ verify  test24/app (unsatisfied constraints, assumed running)
             │ download  overlay://test24/web-1.0

 └─step  2─┤ install   overlay://test24/web-1.0

 └─step  3─┤ run     overlay://test24/web-1.0

Total: 3 actions (1 download, 1 install, 1 run), grouped into 3 steps.
       0.00 Kb to be downloaded.



Error The proof for your build plan contains domain assumptions. Please verify:


>>> Domain assumptions

- Unsatisfied constraints for run dependency: 
  test24/app

  required by: overlay://test24/web-1.0

- Unsatisfied constraints for run dependency: 
  test24/db

  required by: overlay://test24/web-1.0

- Unsatisfied constraints for install dependency: 
  test24/os

  required by: overlay://test24/web-1.0

- Unsatisfied constraints for run dependency: 
  test24/os

  required by: overlay://test24/web-1.0


>>> Bug report drafts (Gentoo Bugzilla)

---
Summary: overlay://test24/web-1.0: unsatisfied_constraints dependency on test24/app

Affected package: overlay://test24/web-1.0
Dependency: test24/app
Phases: [run]

Unsatisfiable constraint(s):
  test24/app-

Observed:
  portage-ng reports no available candidate satisfies the above constraint(s).
  Available versions in repo set (sample, first 1 of 1): [1.0]

Potential fix (suggestion):
  Review dependency metadata in overlay://test24/web-1.0; constraint set: [constraint(none,,[])].

---
Summary: overlay://test24/web-1.0: unsatisfied_constraints dependency on test24/db

Affected package: overlay://test24/web-1.0
Dependency: test24/db
Phases: [run]

Unsatisfiable constraint(s):
  test24/db-

Observed:
  portage-ng reports no available candidate satisfies the above constraint(s).
  Available versions in repo set (sample, first 1 of 1): [1.0]

Potential fix (suggestion):
  Review dependency metadata in overlay://test24/web-1.0; constraint set: [constraint(none,,[])].

---
Summary: overlay://test24/web-1.0: unsatisfied_constraints dependency on test24/os

Affected package: overlay://test24/web-1.0
Dependency: test24/os
Phases: [install,run]

Unsatisfiable constraint(s):
  test24/os-

Observed:
  portage-ng reports no available candidate satisfies the above constraint(s).
  Available versions in repo set (sample, first 1 of 1): [1.0]

Potential fix (suggestion):
  Review dependency metadata in overlay://test24/web-1.0; constraint set: [constraint(none,,[])].



```

</details>