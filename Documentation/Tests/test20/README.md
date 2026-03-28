# test20 — Any-of || (compile)

**Category:** Choice

This test case evaluates the prover's handling of an 'any-of' dependency group (||). The 'os-1.0' package requires that at least one of the three OS packages be installed.

**Expected:** The prover should recognize the choice and select one of the available options to satisfy the dependency. Since there are no other constraints, any of the three choices should lead to a valid proof.

![test20](test20.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.09 s (backtrack: 0/20).

[ebuild  N     ] test20/linux-1.0::overlay  0 KiB
[ebuild  N     ] test20/os-1.0::overlay  0 KiB
[ebuild  N     ] test20/db-1.0::overlay  0 KiB
[ebuild  N     ] test20/app-1.0::overlay  0 KiB
[ebuild  N     ] test20/web-1.0::overlay  0 KiB

Total: 5 packages (5 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```ansi
[93m>>> Emerging : overlay://test20/web-1.0:run?{[]}
[00m
[32mThese are the packages that would be merged, in order:

[00mCalculating dependencies... done!

 └─[90m[00m[100mstep  1[00m[90m[00m─┤ [36mdownload[32m  overlay://test20/web-1.0[00m
             │ [36mdownload[32m  overlay://test20/os-1.0[00m
             │ [36mdownload[32m  overlay://test20/linux-1.0[00m
             │ [36mdownload[32m  overlay://test20/db-1.0[00m
             │ [36mdownload[32m  overlay://test20/app-1.0[00m

 └─[90m[00m[100mstep  2[00m[90m[00m─┤ [36minstall[32m   overlay://test20/os-1.0[00m
             │ [36minstall[32m   overlay://test20/linux-1.0[00m

 └─[90m[00m[100mstep  3[00m[90m[00m─┤ [36mrun[32m       overlay://test20/os-1.0[00m

 └─[90m[00m[100mstep  4[00m[90m[00m─┤ [36minstall[32m   overlay://test20/db-1.0[00m

 └─[90m[00m[100mstep  5[00m[90m[00m─┤ [36mrun[32m       overlay://test20/db-1.0[00m

 └─[90m[00m[100mstep  6[00m[90m[00m─┤ [36minstall[32m   overlay://test20/app-1.0[00m

 └─[90m[00m[100mstep  7[00m[90m[00m─┤ [36mrun[32m       overlay://test20/app-1.0[00m

 └─[90m[00m[100mstep  8[00m[90m[00m─┤ [36minstall[32m   overlay://test20/web-1.0[00m

 └─[90m[00m[100mstep  9[00m[90m[00m─┤ [32m[00m[42mrun[00m[32m[00m[01m[32m     overlay://test20/web-1.0[00m[00m

Total: 14 actions (5 downloads, 5 installs, 4 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.
```

</details>