# test49 — USE default (+) vs REQUIRED_USE

**Category:** Conflict

This test case checks the prover's ability to handle a conflict between a "soft" USE flag suggestion from a dependency and a "hard" REQUIRED_USE constraint in the target package. The `(+)` syntax is a default and should be overridden by the stricter `REQUIRED_USE`.

**Expected:** The prover should recognize that the dependency from 'app-1.0' attempts to enable a USE flag that is explicitly forbidden by 'libhelper-1.0'. The hard constraint of REQUIRED_USE must take precedence, leading to an unresolvable conflict. The prover should fail to find a valid proof.

![test49](test49.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.60 s (backtrack: 0/20).


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

```ansi
[93m>>> Emerging : overlay://test49/app-1.0:run?{[]}
[00m
[32mThese are the packages that would be merged, in order:

[00mCalculating dependencies... done!

 └─[90m[00m[100mstep  1[00m[90m[00m─┤ [33m[00m[43museflag[00m[33m[00m[32m overlay://test49/libhelper-1.0[90m (feature_z -feature_z)[00m
             │ [33m[00m[43museflag[00m[33m[00m[32m overlay://test49/libhelper-1.0[90m (feature_z)[00m

 └─[90m[00m[100mstep  2[00m[90m[00m─┤ [36mdownload[32m  overlay://test49/libhelper-1.0[00m
             │ [36mdownload[32m  overlay://test49/app-1.0[00m

 └─[90m[00m[100mstep  3[00m[90m[00m─┤ [36minstall[32m   overlay://test49/libhelper-1.0[90m (USE modified)[00m
             │           [90m└─ conf ─┤ [00m[90m[00m[100mUSE[00m[90m[00m = "[33m-feature_z[00m"

 └─[90m[00m[100mstep  4[00m[90m[00m─┤ [36mrun[32m       overlay://test49/libhelper-1.0[90m (USE modified)[00m

 └─[90m[00m[100mstep  5[00m[90m[00m─┤ [36minstall[32m   overlay://test49/app-1.0[00m
             │           [90m└─ conf ─┤ [00m[90m[00m[100mUSE[00m[90m[00m = "[90m[03m-feature_z[00m"

 └─[90m[00m[100mstep  6[00m[90m[00m─┤ [32m[00m[42mrun[00m[32m[00m[01m[32m     overlay://test49/app-1.0[00m[00m

Total: 8 actions (2 useflags, 2 downloads, 2 installs, 2 runs), grouped into 6 steps.
       0.00 Kb to be downloaded.


[93m>>> Assumptions taken during proving & planning:[00m

  USE flag change (2 packages):
[00m[90m  Add to /etc/portage/package.use:
    test49/libhelper feature_z -feature_z
    test49/libhelper feature_z
[00m
```

</details>