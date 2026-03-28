# test51 — USE dep vs REQUIRED_USE contradiction

**Category:** Conflict

This test case presents a direct and unsolvable conflict between a dependency's USE requirement and the target package's REQUIRED_USE. 'app-1.0' needs 'os-1.0' with the 'linux' flag, but 'os-1.0' explicitly forbids that flag from being enabled.

**Expected:** The prover should immediately detect the contradiction between the USE dependency and the REQUIRED_USE constraint and fail to produce a valid proof.

![test51](test51.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.60 s (backtrack: 0/20).


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

```ansi
[93m>>> Emerging : overlay://test51/app-1.0:run?{[]}
[00m
[32mThese are the packages that would be merged, in order:

[00mCalculating dependencies... done!

 └─[90m[00m[100mstep  1[00m[90m[00m─┤ [33m[00m[43museflag[00m[33m[00m[32m overlay://test51/os-1.0[90m (linux)[00m

 └─[90m[00m[100mstep  2[00m[90m[00m─┤ [36mdownload[32m  overlay://test51/os-1.0[00m
             │ [36mdownload[32m  overlay://test51/app-1.0[00m

 └─[90m[00m[100mstep  3[00m[90m[00m─┤ [36minstall[32m   overlay://test51/os-1.0[90m (USE modified)[00m
             │           [90m└─ conf ─┤ [00m[90m[00m[100mUSE[00m[90m[00m = "[33mlinux[00m"

 └─[90m[00m[100mstep  4[00m[90m[00m─┤ [36minstall[32m   overlay://test51/app-1.0[00m

 └─[90m[00m[100mstep  5[00m[90m[00m─┤ [32m[00m[42mrun[00m[32m[00m[01m[32m     overlay://test51/app-1.0[00m[00m

Total: 6 actions (1 useflag, 2 downloads, 2 installs, 1 run), grouped into 5 steps.
       0.00 Kb to be downloaded.


[93m>>> Assumptions taken during proving & planning:[00m

  USE flag change (1 package):
[00m[90m  Add to /etc/portage/package.use:
    test51/os linux
[00m
```

</details>