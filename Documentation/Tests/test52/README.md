# test52 — Multiple USE flags on shared dep

**Category:** USE merge

The prover will first prove os-1.0 through the liba path. This means os-1.0 will have 'threads' enabled. Later prover needs to enable 'hardened' through the libb path. The prover should be able to produce a proof with just one os install, for both 'threads' and 'hardeded'. This should also be reflected in the download for os-1.0

**Expected:** The prover should correctly identify the need for building os-1.0 only once with the two use flags.

![test52](test52.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.92 s (backtrack: 0/20).

[ebuild  N     ] test52/os-1.0::overlay  USE="hardened threads" 0 KiB
[ebuild  N     ] test52/liba-1.0::overlay  0 KiB
[ebuild  N     ] test52/libb-1.0::overlay  0 KiB
[ebuild  N     ] test52/app-1.0::overlay  0 KiB

Total: 4 packages (4 new), Size of downloads: 0 KiB

The following USE changes are necessary to proceed:
 (see "package.use" in the portage(5) man page for more details)
# required by test52/libb-1.0::overlay
# required by test52/app-1.0::overlay
# required by test52/app (argument)
>=test52/os-1.0 hardened
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```ansi
[93m>>> Emerging : overlay://test52/app-1.0:run?{[]}
[00m
[32mThese are the packages that would be merged, in order:

[00mCalculating dependencies... done!

 └─[90m[00m[100mstep  1[00m[90m[00m─┤ [33m[00m[43museflag[00m[33m[00m[32m overlay://test52/os-1.0[90m (hardened)[00m

 └─[90m[00m[100mstep  2[00m[90m[00m─┤ [36mdownload[32m  overlay://test52/os-1.0[00m
             │ [36mdownload[32m  overlay://test52/libb-1.0[00m
             │ [36mdownload[32m  overlay://test52/liba-1.0[00m
             │ [36mdownload[32m  overlay://test52/app-1.0[00m

 └─[90m[00m[100mstep  3[00m[90m[00m─┤ [36minstall[32m   overlay://test52/liba-1.0[00m
             │ [36minstall[32m   overlay://test52/libb-1.0[00m
             │ [36minstall[32m   overlay://test52/os-1.0[90m (USE modified)[00m
             │           [90m└─ conf ─┤ [00m[90m[00m[100mUSE[00m[90m[00m = "[32m[01mthreads[00m* [33mhardened[00m"

 └─[90m[00m[100mstep  4[00m[90m[00m─┤ [36mrun[32m       overlay://test52/libb-1.0[00m
             │ [36mrun[32m       overlay://test52/liba-1.0[00m

 └─[90m[00m[100mstep  5[00m[90m[00m─┤ [36minstall[32m   overlay://test52/app-1.0[00m

 └─[90m[00m[100mstep  6[00m[90m[00m─┤ [32m[00m[42mrun[00m[32m[00m[01m[32m     overlay://test52/app-1.0[00m[00m

Total: 12 actions (1 useflag, 4 downloads, 4 installs, 3 runs), grouped into 6 steps.
       0.00 Kb to be downloaded.


[93m>>> Assumptions taken during proving & planning:[00m

  USE flag change (1 package):
[00m[90m  Add to /etc/portage/package.use:
    test52/os hardened
[00m
```

</details>