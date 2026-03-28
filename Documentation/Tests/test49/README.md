# test49 — USE default (+) vs REQUIRED_USE

**Category:** Conflict

This test case checks the prover's ability to handle a conflict between a "soft" USE flag suggestion from a dependency and a "hard" REQUIRED_USE constraint in the target package. The `(+)` syntax is a default and should be overridden by the stricter `REQUIRED_USE`.

**Expected:** The prover should recognize that the dependency from 'app-1.0' attempts to enable a USE flag that is explicitly forbidden by 'libhelper-1.0'. The hard constraint of REQUIRED_USE must take precedence, leading to an unresolvable conflict. The prover should fail to find a valid proof.

![test49](test49.svg)

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