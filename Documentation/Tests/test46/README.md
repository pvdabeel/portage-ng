# test46 — Deep diamond USE conflict

**Category:** Conflict

This test case is designed to assess the prover's ability to detect a USE flag conflict that is hidden several layers deep in the dependency graph. The two main dependency branches ('liba' and 'libb') converge on 'core-utils' with contradictory requirements for the 'feature_x' USE flag.

**Expected:** The prover must trace the entire dependency tree and identify that 'core-utils' is required with both 'feature_x' enabled and disabled simultaneously. As this is a logical contradiction, the prover should fail to produce a valid installation proof.

![test46](test46.svg)

<details>
<summary><b>emerge -vp</b></summary>

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

```ansi
[93m>>> Emerging : overlay://test46/app-1.0:run?{[]}
[00m
[32mThese are the packages that would be merged, in order:

[00mCalculating dependencies... done!

 └─[90m[00m[100mstep  1[00m[90m[00m─┤ [33m[00m[43museflag[00m[33m[00m[32m overlay://test46/core-utils-1.0[90m (feature_x)[00m
             │ [33m[00m[43museflag[00m[33m[00m[32m overlay://test46/core-utils-1.0[90m (feature_x feature_y)[00m

 └─[90m[00m[100mstep  2[00m[90m[00m─┤ [36mdownload[32m  overlay://test46/libd-1.0[00m
             │ [36mdownload[32m  overlay://test46/libc-1.0[00m
             │ [36mdownload[32m  overlay://test46/libb-1.0[00m
             │ [36mdownload[32m  overlay://test46/liba-1.0[00m
             │ [36mdownload[32m  overlay://test46/core-utils-1.0[00m
             │ [36mdownload[32m  overlay://test46/app-1.0[00m

 └─[90m[00m[100mstep  3[00m[90m[00m─┤ [36minstall[32m   overlay://test46/core-utils-1.0[90m (USE modified)[00m
             │           [90m└─ conf ─┤ [00m[90m[00m[100mUSE[00m[90m[00m = "[33mfeature_x[00m [33mfeature_y[00m"

 └─[90m[00m[100mstep  4[00m[90m[00m─┤ [36mrun[32m       overlay://test46/core-utils-1.0[90m (USE modified)[00m

 └─[90m[00m[100mstep  5[00m[90m[00m─┤ [36minstall[32m   overlay://test46/libd-1.0[00m
             │ [36minstall[32m   overlay://test46/libc-1.0[00m

 └─[90m[00m[100mstep  6[00m[90m[00m─┤ [36mrun[32m       overlay://test46/libd-1.0[00m
             │ [36mrun[32m       overlay://test46/libc-1.0[00m

 └─[90m[00m[100mstep  7[00m[90m[00m─┤ [36minstall[32m   overlay://test46/libb-1.0[00m
             │ [36minstall[32m   overlay://test46/liba-1.0[00m

 └─[90m[00m[100mstep  8[00m[90m[00m─┤ [36mrun[32m       overlay://test46/libb-1.0[00m
             │ [36mrun[32m       overlay://test46/liba-1.0[00m

 └─[90m[00m[100mstep  9[00m[90m[00m─┤ [36minstall[32m   overlay://test46/app-1.0[00m

 └─[90m[00m[100mstep 10[00m[90m[00m─┤ [32m[00m[42mrun[00m[32m[00m[01m[32m     overlay://test46/app-1.0[00m[00m

Total: 20 actions (2 useflags, 6 downloads, 6 installs, 6 runs), grouped into 10 steps.
       0.00 Kb to be downloaded.



[93m>>> Assumptions taken during proving & planning:[00m

  USE flag change (2 packages):
[00m[90m  Add to /etc/portage/package.use:
    test46/core-utils feature_x
    test46/core-utils feature_x feature_y
[00m

[00m
```

</details>