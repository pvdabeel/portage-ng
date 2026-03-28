# test22 — Any-of || (compile + runtime)

**Category:** Choice

This test case combines test20 and test21. The 'os-1.0' package has the same 'any-of' choice group in both its compile-time and runtime dependencies.

**Expected:** The prover can choose any of the OS packages to satisfy the compile-time dependency and any of the OS packages to satisfy the runtime dependency. They do not have to be the same. The proof should be valid.

![test22](test22.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.05 s (backtrack: 0/20).

[ebuild  N     ] test22/linux-1.0::overlay  0 KiB
[ebuild  N     ] test22/os-1.0::overlay  0 KiB
[ebuild  N     ] test22/db-1.0::overlay  0 KiB
[ebuild  N     ] test22/app-1.0::overlay  0 KiB
[ebuild  N     ] test22/web-1.0::overlay  0 KiB

Total: 5 packages (5 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```ansi
[93m>>> Emerging : overlay://test22/web-1.0:run?{[]}
[00m
[32mThese are the packages that would be merged, in order:

[00mCalculating dependencies... done!

 └─[90m[00m[100mstep  1[00m[90m[00m─┤ [36mdownload[32m  overlay://test22/web-1.0[00m
             │ [36mdownload[32m  overlay://test22/os-1.0[00m
             │ [36mdownload[32m  overlay://test22/linux-1.0[00m
             │ [36mdownload[32m  overlay://test22/db-1.0[00m
             │ [36mdownload[32m  overlay://test22/app-1.0[00m

 └─[90m[00m[100mstep  2[00m[90m[00m─┤ [36minstall[32m   overlay://test22/linux-1.0[00m

 └─[90m[00m[100mstep  3[00m[90m[00m─┤ [36mrun[32m       overlay://test22/linux-1.0[00m

 └─[90m[00m[100mstep  4[00m[90m[00m─┤ [36minstall[32m   overlay://test22/os-1.0[00m

 └─[90m[00m[100mstep  5[00m[90m[00m─┤ [36mrun[32m       overlay://test22/os-1.0[00m

 └─[90m[00m[100mstep  6[00m[90m[00m─┤ [36minstall[32m   overlay://test22/db-1.0[00m

 └─[90m[00m[100mstep  7[00m[90m[00m─┤ [36mrun[32m       overlay://test22/db-1.0[00m

 └─[90m[00m[100mstep  8[00m[90m[00m─┤ [36minstall[32m   overlay://test22/app-1.0[00m

 └─[90m[00m[100mstep  9[00m[90m[00m─┤ [36mrun[32m       overlay://test22/app-1.0[00m

 └─[90m[00m[100mstep 10[00m[90m[00m─┤ [36minstall[32m   overlay://test22/web-1.0[00m

 └─[90m[00m[100mstep 11[00m[90m[00m─┤ [32m[00m[42mrun[00m[32m[00m[01m[32m     overlay://test22/web-1.0[00m[00m

Total: 15 actions (5 downloads, 5 installs, 5 runs), grouped into 11 steps.
       0.00 Kb to be downloaded.
```

</details>