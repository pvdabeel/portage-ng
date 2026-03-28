# test56 — Constraint intersection via dep chains

**Category:** Version

Multiple requirements should be combined. Only one version should be selected

**Expected:** The constraints on the lib versions should be combined. Only one version should be selected, since there is only one slot to fill.

![test56](test56.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.98 s (backtrack: 0/20).

[ebuild  N     ] test56/lib-6.0::overlay  0 KiB
[ebuild  N     ] test56/modulea-1.0::overlay  0 KiB
[ebuild  N     ] test56/moduleb-1.0::overlay  0 KiB
[ebuild  N     ] test56/app-1.0::overlay  0 KiB

Total: 4 packages (4 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```ansi
[93m>>> Emerging : overlay://test56/app-1.0:run?{[]}
[00m
[32mThese are the packages that would be merged, in order:

[00mCalculating dependencies... done!

 └─[90m[00m[100mstep  1[00m[90m[00m─┤ [36mdownload[32m  overlay://test56/moduleb-1.0[00m
             │ [36mdownload[32m  overlay://test56/modulea-1.0[00m
             │ [36mdownload[32m  overlay://test56/lib-6.0[00m
             │ [36mdownload[32m  overlay://test56/app-1.0[00m

 └─[90m[00m[100mstep  2[00m[90m[00m─┤ [36minstall[32m   overlay://test56/lib-6.0[00m

 └─[90m[00m[100mstep  3[00m[90m[00m─┤ [36mrun[32m       overlay://test56/lib-6.0[00m

 └─[90m[00m[100mstep  4[00m[90m[00m─┤ [36minstall[32m   overlay://test56/moduleb-1.0[00m
             │ [36minstall[32m   overlay://test56/modulea-1.0[00m

 └─[90m[00m[100mstep  5[00m[90m[00m─┤ [36mrun[32m       overlay://test56/modulea-1.0[00m
             │ [36mrun[32m       overlay://test56/moduleb-1.0[00m

 └─[90m[00m[100mstep  6[00m[90m[00m─┤ [36minstall[32m   overlay://test56/app-1.0[00m

 └─[90m[00m[100mstep  7[00m[90m[00m─┤ [32m[00m[42mrun[00m[32m[00m[01m[32m     overlay://test56/app-1.0[00m[00m

Total: 12 actions (4 downloads, 4 installs, 4 runs), grouped into 7 steps.
       0.00 Kb to be downloaded.
```

</details>