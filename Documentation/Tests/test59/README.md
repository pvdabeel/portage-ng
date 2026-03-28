# test59 — Any-of || selection regression (XFAIL)

**Category:** Regression

> **XFAIL** — expected to fail.

This is an XFAIL regression test for a known bug where the any-of group (||) does
not force the solver to select at least one alternative. Structurally similar to
test21 (any-of in RDEPEND), but this test uses different package names and exists
specifically to track the regression where any-of members can all be dropped from
the model.

**Expected:** Currently expected to fail (XFAIL): the solver does not force selecting one
alternative from the any-of group. When the bug is fixed, the model should contain
either data_fast-1.0 or data_best-1.0.

![test59](test59.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.02 s (backtrack: 0/20).

[ebuild  N     ] test59/data_fast-1.0::overlay  0 KiB
[ebuild  N     ] test59/os-1.0::overlay  0 KiB
[ebuild  N     ] test59/db-1.0::overlay  0 KiB
[ebuild  N     ] test59/app-1.0::overlay  0 KiB
[ebuild  N     ] test59/web-1.0::overlay  0 KiB

Total: 5 packages (5 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```ansi
[93m>>> Emerging : overlay://test59/web-1.0:run?{[]}
[00m
[32mThese are the packages that would be merged, in order:

[00mCalculating dependencies... done!

 └─[90m[00m[100mstep  1[00m[90m[00m─┤ [36mdownload[32m  overlay://test59/web-1.0[00m
             │ [36mdownload[32m  overlay://test59/os-1.0[00m
             │ [36mdownload[32m  overlay://test59/db-1.0[00m
             │ [36mdownload[32m  overlay://test59/data_fast-1.0[00m
             │ [36mdownload[32m  overlay://test59/app-1.0[00m

 └─[90m[00m[100mstep  2[00m[90m[00m─┤ [36minstall[32m   overlay://test59/os-1.0[00m
             │ [36minstall[32m   overlay://test59/data_fast-1.0[00m

 └─[90m[00m[100mstep  3[00m[90m[00m─┤ [36mrun[32m       overlay://test59/data_fast-1.0[00m

 └─[90m[00m[100mstep  4[00m[90m[00m─┤ [36mrun[32m       overlay://test59/os-1.0[00m

 └─[90m[00m[100mstep  5[00m[90m[00m─┤ [36minstall[32m   overlay://test59/db-1.0[00m

 └─[90m[00m[100mstep  6[00m[90m[00m─┤ [36mrun[32m       overlay://test59/db-1.0[00m

 └─[90m[00m[100mstep  7[00m[90m[00m─┤ [36minstall[32m   overlay://test59/app-1.0[00m

 └─[90m[00m[100mstep  8[00m[90m[00m─┤ [36mrun[32m       overlay://test59/app-1.0[00m

 └─[90m[00m[100mstep  9[00m[90m[00m─┤ [36minstall[32m   overlay://test59/web-1.0[00m

 └─[90m[00m[100mstep 10[00m[90m[00m─┤ [32m[00m[42mrun[00m[32m[00m[01m[32m     overlay://test59/web-1.0[00m[00m

Total: 15 actions (5 downloads, 5 installs, 5 runs), grouped into 10 steps.
       0.00 Kb to be downloaded.
```

</details>