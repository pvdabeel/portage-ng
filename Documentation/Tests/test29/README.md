# test29 — Strong blocker !! (compile+runtime) + any-of

**Category:** Blocker

This test case combines test26 and test28. The 'app-1.0' package has a strong
blocker (!!) against 'windows-1.0' in both the compile-time (DEPEND) and runtime
(RDEPEND) scopes. The any-of group on 'os-1.0' still includes 'windows-1.0'.

**Expected:** The prover should produce a valid plan that avoids 'windows-1.0'. It should select
either 'linux-1.0' or 'bsd-1.0' for the any-of group, since 'windows-1.0' is
strongly blocked in both scopes.

![test29](test29.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.09 s (backtrack: 0/20).

[ebuild  N     ] test29/linux-1.0::overlay  0 KiB
[ebuild  N     ] test29/os-1.0::overlay  0 KiB
[ebuild  N     ] test29/db-1.0::overlay  0 KiB
[ebuild  N     ] test29/app-1.0::overlay  0 KiB
[ebuild  N     ] test29/web-1.0::overlay  0 KiB

Total: 5 packages (5 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```ansi
[93m>>> Emerging : overlay://test29/web-1.0:run?{[]}
[00m
[32mThese are the packages that would be merged, in order:

[00mCalculating dependencies... done!

 └─[90m[00m[100mstep  1[00m[90m[00m─┤ [36mdownload[32m  overlay://test29/web-1.0[00m
             │ [36mdownload[32m  overlay://test29/os-1.0[00m
             │ [36mdownload[32m  overlay://test29/linux-1.0[00m
             │ [36mdownload[32m  overlay://test29/db-1.0[00m
             │ [36mdownload[32m  overlay://test29/app-1.0[00m

 └─[90m[00m[100mstep  2[00m[90m[00m─┤ [36minstall[32m   overlay://test29/os-1.0[00m
             │ [36minstall[32m   overlay://test29/linux-1.0[00m

 └─[90m[00m[100mstep  3[00m[90m[00m─┤ [36mrun[32m       overlay://test29/os-1.0[00m

 └─[90m[00m[100mstep  4[00m[90m[00m─┤ [36minstall[32m   overlay://test29/db-1.0[00m

 └─[90m[00m[100mstep  5[00m[90m[00m─┤ [36mrun[32m       overlay://test29/db-1.0[00m

 └─[90m[00m[100mstep  6[00m[90m[00m─┤ [36minstall[32m   overlay://test29/app-1.0[00m

 └─[90m[00m[100mstep  7[00m[90m[00m─┤ [36mrun[32m       overlay://test29/app-1.0[00m

 └─[90m[00m[100mstep  8[00m[90m[00m─┤ [36minstall[32m   overlay://test29/web-1.0[00m

 └─[90m[00m[100mstep  9[00m[90m[00m─┤ [32m[00m[42mrun[00m[32m[00m[01m[32m     overlay://test29/web-1.0[00m[00m

Total: 14 actions (5 downloads, 5 installs, 4 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.
```

</details>