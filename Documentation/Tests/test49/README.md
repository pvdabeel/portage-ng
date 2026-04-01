# test49 — USE default (+) vs REQUIRED_USE

**Category:** Conflict

This test case checks the prover's ability to handle a conflict between a "soft" USE flag suggestion from a dependency and a "hard" REQUIRED_USE constraint in the target package. The `(+)` syntax is a default and should be overridden by the stricter `REQUIRED_USE`.

**Expected:** The prover should recognize that the dependency from `app-1.0` attempts to enable `feature_z` via `[feature_z(+)]`, but `libhelper-1.0` has `REQUIRED_USE="!feature_z"` forbidding it. The hard constraint takes precedence, producing a domain assumption. Exit code 2.

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

 └─step  1─┤ useflag overlay://test49/libhelper-1.0 (feature_z)

 └─step  2─┤ download  overlay://test49/app-1.0

 └─step  3─┤ run       overlay://test49/libhelper-1.0 (USE modified)

 └─step  4─┤ install   overlay://test49/app-1.0
             │           └─ conf ─┤ USE = "-feature_z"

 └─step  5─┤ run     overlay://test49/app-1.0

Total: 5 actions (1 useflag, 1 download, 1 install, 2 runs), grouped into 5 steps.
       0.00 Kb to be downloaded.



>>> Assumptions taken during proving & planning:

  USE flag change (1 package):
  Add to /etc/portage/package.use:
    test49/libhelper feature_z


Error The proof for your build plan contains domain assumptions. Please verify:


>>> Domain assumptions

- Model unavailable: 
  test49/libhelper — dependency model could not be built
  (some dependencies may be missing from the tree or keyword-filtered)
  required by: overlay://test49/app-1.0



```

</details>