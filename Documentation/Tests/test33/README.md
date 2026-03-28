# test33 — Positive [linux]

**Category:** USE dep

This test case examines a direct USE dependency. The 'app-1.0' package requires that 'os-1.0' be built with the 'linux' USE flag enabled.

**Expected:** The prover should identify the USE requirement and enable the 'linux' flag for 'os-1.0' when resolving its dependencies. The final proof should be valid and show that 'os-1.0' is built with USE="linux".

![test33](test33.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.87 s (backtrack: 0/20).

[ebuild  N     ] test33/os-1.0::overlay  USE="linux -darwin" 0 KiB
[ebuild  N     ] test33/app-1.0::overlay  0 KiB

Total: 2 packages (2 new), Size of downloads: 0 KiB

The following USE changes are necessary to proceed:
 (see "package.use" in the portage(5) man page for more details)
# required by test33/app-1.0::overlay
# required by test33/app (argument)
>=test33/os-1.0 linux
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```ansi
[93m>>> Emerging : overlay://test33/app-1.0:run?{[]}
[00m
[32mThese are the packages that would be merged, in order:

[00mCalculating dependencies... done!

 └─[90m[00m[100mstep  1[00m[90m[00m─┤ [33m[00m[43museflag[00m[33m[00m[32m overlay://test33/os-1.0[90m (linux)[00m

 └─[90m[00m[100mstep  2[00m[90m[00m─┤ [36mdownload[32m  overlay://test33/os-1.0[00m
             │ [36mdownload[32m  overlay://test33/app-1.0[00m

 └─[90m[00m[100mstep  3[00m[90m[00m─┤ [36minstall[32m   overlay://test33/os-1.0[90m (USE modified)[00m
             │           [90m└─ conf ─┤ [00m[90m[00m[100mUSE[00m[90m[00m = "[90m[03m-darwin[00m [33mlinux[00m"

 └─[90m[00m[100mstep  4[00m[90m[00m─┤ [36minstall[32m   overlay://test33/app-1.0[00m

 └─[90m[00m[100mstep  5[00m[90m[00m─┤ [32m[00m[42mrun[00m[32m[00m[01m[32m     overlay://test33/app-1.0[00m[00m

Total: 6 actions (1 useflag, 2 downloads, 2 installs, 1 run), grouped into 5 steps.
       0.00 Kb to be downloaded.


[93m>>> Assumptions taken during proving & planning:[00m

  USE flag change (1 package):
[00m[90m  Add to /etc/portage/package.use:
    test33/os linux
[00m
```

</details>