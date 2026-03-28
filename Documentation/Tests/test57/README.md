# test57 — Virtual-style ebuild (explicit dep)

**Category:** Virtual

This test case validates that dependencies of a virtual-style ebuild are traversed
and that its provider package is included in the proof/model. The 'virtualsdk-1.0'
ebuild acts as a virtual by depending on 'linux-1.0' as its concrete provider.

**Expected:** When proving web-1.0, the plan/model should include linux-1.0 (via
virtualsdk-1.0). The full chain os -> virtualsdk -> linux should be resolved.

![test57](test57.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.02 s (backtrack: 0/20).

[ebuild  N     ] test57/linux-1.0::overlay  0 KiB
[ebuild  N     ] test57/virtualsdk-1.0::overlay  0 KiB
[ebuild  N     ] test57/os-1.0::overlay  0 KiB
[ebuild  N     ] test57/db-1.0::overlay  0 KiB
[ebuild  N     ] test57/app-1.0::overlay  0 KiB
[ebuild  N     ] test57/web-1.0::overlay  0 KiB

Total: 6 packages (6 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```ansi
[93m>>> Emerging : overlay://test57/web-1.0:run?{[]}
[00m
[32mThese are the packages that would be merged, in order:

[00mCalculating dependencies... done!

 └─[90m[00m[100mstep  1[00m[90m[00m─┤ [36mdownload[32m  overlay://test57/web-1.0[00m
             │ [36mdownload[32m  overlay://test57/virtualsdk-1.0[00m
             │ [36mdownload[32m  overlay://test57/os-1.0[00m
             │ [36mdownload[32m  overlay://test57/linux-1.0[00m
             │ [36mdownload[32m  overlay://test57/db-1.0[00m
             │ [36mdownload[32m  overlay://test57/app-1.0[00m

 └─[90m[00m[100mstep  2[00m[90m[00m─┤ [36minstall[32m   overlay://test57/virtualsdk-1.0[00m
             │ [36minstall[32m   overlay://test57/linux-1.0[00m

 └─[90m[00m[100mstep  3[00m[90m[00m─┤ [36mrun[32m       overlay://test57/linux-1.0[00m

 └─[90m[00m[100mstep  4[00m[90m[00m─┤ [36minstall[32m   overlay://test57/os-1.0[00m

 └─[90m[00m[100mstep  5[00m[90m[00m─┤ [36mrun[32m       overlay://test57/virtualsdk-1.0[00m

 └─[90m[00m[100mstep  6[00m[90m[00m─┤ [36mrun[32m       overlay://test57/os-1.0[00m

 └─[90m[00m[100mstep  7[00m[90m[00m─┤ [36minstall[32m   overlay://test57/db-1.0[00m

 └─[90m[00m[100mstep  8[00m[90m[00m─┤ [36mrun[32m       overlay://test57/db-1.0[00m

 └─[90m[00m[100mstep  9[00m[90m[00m─┤ [36minstall[32m   overlay://test57/app-1.0[00m

 └─[90m[00m[100mstep 10[00m[90m[00m─┤ [36mrun[32m       overlay://test57/app-1.0[00m

 └─[90m[00m[100mstep 11[00m[90m[00m─┤ [36minstall[32m   overlay://test57/web-1.0[00m

 └─[90m[00m[100mstep 12[00m[90m[00m─┤ [32m[00m[42mrun[00m[32m[00m[01m[32m     overlay://test57/web-1.0[00m[00m

Total: 18 actions (6 downloads, 6 installs, 6 runs), grouped into 12 steps.
       0.00 Kb to be downloaded.
```

</details>