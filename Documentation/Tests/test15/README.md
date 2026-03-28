# test15 — Negative USE conditional !nolib? ( )

**Category:** USE cond

This test case is similar to test14 but uses a negative USE conditional. The dependency is triggered by the absence of a USE flag.

**Expected:** - If the 'nolib' flag is enabled for app-1.0, the proof should succeed without pulling in 'lib-1.0'.
- If the 'nolib' flag is not set (i.e., disabled by default), the proof should succeed and correctly include 'lib-1.0' as a dependency.

![test15](test15.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.95 s (backtrack: 0/20).

[ebuild  N     ] test15/os-1.0::overlay  0 KiB
[ebuild  N     ] test15/db-1.0::overlay  0 KiB
[ebuild  N     ] test15/lib-1.0::overlay  0 KiB
[ebuild  N     ] test15/app-1.0::overlay  USE="-nolib" 0 KiB
[ebuild  N     ] test15/web-1.0::overlay  0 KiB

Total: 5 packages (5 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```ansi
[93m>>> Emerging : overlay://test15/web-1.0:run?{[]}
[00m
[32mThese are the packages that would be merged, in order:

[00mCalculating dependencies... done!

 └─[90m[00m[100mstep  1[00m[90m[00m─┤ [36mdownload[32m  overlay://test15/web-1.0[00m
             │ [36mdownload[32m  overlay://test15/os-1.0[00m
             │ [36mdownload[32m  overlay://test15/lib-1.0[00m
             │ [36mdownload[32m  overlay://test15/db-1.0[00m
             │ [36mdownload[32m  overlay://test15/app-1.0[00m

 └─[90m[00m[100mstep  2[00m[90m[00m─┤ [36minstall[32m   overlay://test15/os-1.0[00m

 └─[90m[00m[100mstep  3[00m[90m[00m─┤ [36mrun[32m       overlay://test15/os-1.0[00m

 └─[90m[00m[100mstep  4[00m[90m[00m─┤ [36minstall[32m   overlay://test15/db-1.0[00m
             │ [36minstall[32m   overlay://test15/lib-1.0[00m

 └─[90m[00m[100mstep  5[00m[90m[00m─┤ [36mrun[32m       overlay://test15/db-1.0[00m

 └─[90m[00m[100mstep  6[00m[90m[00m─┤ [36minstall[32m   overlay://test15/app-1.0[00m
             │           [90m└─ conf ─┤ [00m[90m[00m[100mUSE[00m[90m[00m = "[90m[03m-nolib[00m"

 └─[90m[00m[100mstep  7[00m[90m[00m─┤ [36mrun[32m       overlay://test15/app-1.0[00m

 └─[90m[00m[100mstep  8[00m[90m[00m─┤ [36minstall[32m   overlay://test15/web-1.0[00m

 └─[90m[00m[100mstep  9[00m[90m[00m─┤ [32m[00m[42mrun[00m[32m[00m[01m[32m     overlay://test15/web-1.0[00m[00m

Total: 14 actions (5 downloads, 5 installs, 4 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.
```

</details>