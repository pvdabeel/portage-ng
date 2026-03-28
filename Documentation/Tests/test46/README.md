# test46 — Deep diamond USE conflict

**Category:** Conflict

This test case is designed to assess the prover's ability to detect a USE flag conflict that is hidden several layers deep in the dependency graph. The two main dependency branches ('liba' and 'libb') converge on 'core-utils' with contradictory requirements for the 'feature_x' USE flag.

**Expected:** The prover must trace the entire dependency tree and identify that 'core-utils' is required with both 'feature_x' enabled and disabled simultaneously. As this is a logical contradiction, the prover should fail to produce a valid installation proof.

![test46](test46.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.71 s (backtrack: 0/20).


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

 └─step  2─┤ download  overlay://test46/libd-1.0
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



```

</details>