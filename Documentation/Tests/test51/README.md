# test51 — USE dep vs REQUIRED_USE contradiction

**Category:** Conflict

This test case presents a direct and unsolvable conflict between a dependency's USE requirement and the target package's REQUIRED_USE. 'app-1.0' needs 'os-1.0' with the 'linux' flag, but 'os-1.0' explicitly forbids that flag from being enabled.

**Expected:** The prover should immediately detect the contradiction between the USE dependency and the REQUIRED_USE constraint and fail to produce a valid proof.

![test51](test51.svg)

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