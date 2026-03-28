# test21 — Any-of || (runtime)

**Category:** Choice

This is a variation of test20, with the 'any-of' dependency group in the runtime scope (RDEPEND).

**Expected:** The prover should handle the runtime choice group correctly, select one of the OS options, and generate a valid proof.

![test21](test21.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.04 s (backtrack: 0/20).

[ebuild  N     ] test21/linux-1.0::overlay  0 KiB
[ebuild  N     ] test21/os-1.0::overlay  0 KiB
[ebuild  N     ] test21/db-1.0::overlay  0 KiB
[ebuild  N     ] test21/app-1.0::overlay  0 KiB
[ebuild  N     ] test21/web-1.0::overlay  0 KiB

Total: 5 packages (5 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```ansi
[93m>>> Emerging : overlay://test21/web-1.0:run?{[]}
[00m
[32mThese are the packages that would be merged, in order:

[00mCalculating dependencies... done!

 └─[90m[00m[100mstep  1[00m[90m[00m─┤ [36mdownload[32m  overlay://test21/web-1.0[00m
             │ [36mdownload[32m  overlay://test21/os-1.0[00m
             │ [36mdownload[32m  overlay://test21/linux-1.0[00m
             │ [36mdownload[32m  overlay://test21/db-1.0[00m
             │ [36mdownload[32m  overlay://test21/app-1.0[00m

 └─[90m[00m[100mstep  2[00m[90m[00m─┤ [36minstall[32m   overlay://test21/os-1.0[00m
             │ [36minstall[32m   overlay://test21/linux-1.0[00m

 └─[90m[00m[100mstep  3[00m[90m[00m─┤ [36mrun[32m       overlay://test21/linux-1.0[00m

 └─[90m[00m[100mstep  4[00m[90m[00m─┤ [36mrun[32m       overlay://test21/os-1.0[00m

 └─[90m[00m[100mstep  5[00m[90m[00m─┤ [36minstall[32m   overlay://test21/db-1.0[00m

 └─[90m[00m[100mstep  6[00m[90m[00m─┤ [36mrun[32m       overlay://test21/db-1.0[00m

 └─[90m[00m[100mstep  7[00m[90m[00m─┤ [36minstall[32m   overlay://test21/app-1.0[00m

 └─[90m[00m[100mstep  8[00m[90m[00m─┤ [36mrun[32m       overlay://test21/app-1.0[00m

 └─[90m[00m[100mstep  9[00m[90m[00m─┤ [36minstall[32m   overlay://test21/web-1.0[00m

 └─[90m[00m[100mstep 10[00m[90m[00m─┤ [32m[00m[42mrun[00m[32m[00m[01m[32m     overlay://test21/web-1.0[00m[00m

Total: 15 actions (5 downloads, 5 installs, 5 runs), grouped into 10 steps.
       0.00 Kb to be downloaded.
```

</details>