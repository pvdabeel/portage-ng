# test12 — Stable vs unstable keyword acceptance

**Category:** Keywords

This test case examines the prover's handling of package keywords and stability. The latest (2.0) versions of the packages are marked as unstable. Without a specific configuration to accept these unstable keywords, the package manager should not select them.

**Expected:** Assuming a default configuration that only allows stable packages, the prover should reject the 2.0 versions and instead resolve the dependencies using the stable 1.0 versions. The final proof should be for app-1.0, db-1.0, and os-1.0.

![test12](test12.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.91 s (backtrack: 0/20).

[ebuild  N     ] test12/os-2.0::overlay  0 KiB
[ebuild  N     ] test12/db-2.0::overlay  0 KiB
[ebuild  N     ] test12/app-2.0::overlay  0 KiB
[ebuild  N     ] test12/web-2.0::overlay  0 KiB

Total: 4 packages (4 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```ansi
[93m>>> Emerging : overlay://test12/web-2.0:run?{[]}
[00m
[32mThese are the packages that would be merged, in order:

[00mCalculating dependencies... done!

 └─[90m[00m[100mstep  1[00m[90m[00m─┤ [36mdownload[32m  overlay://test12/web-2.0[00m
             │ [36mdownload[32m  overlay://test12/os-2.0[00m
             │ [36mdownload[32m  overlay://test12/db-2.0[00m
             │ [36mdownload[32m  overlay://test12/app-2.0[00m

 └─[90m[00m[100mstep  2[00m[90m[00m─┤ [36minstall[32m   overlay://test12/os-2.0[00m

 └─[90m[00m[100mstep  3[00m[90m[00m─┤ [36mrun[32m       overlay://test12/os-2.0[00m

 └─[90m[00m[100mstep  4[00m[90m[00m─┤ [36minstall[32m   overlay://test12/db-2.0[00m

 └─[90m[00m[100mstep  5[00m[90m[00m─┤ [36mrun[32m       overlay://test12/db-2.0[00m

 └─[90m[00m[100mstep  6[00m[90m[00m─┤ [36minstall[32m   overlay://test12/app-2.0[00m

 └─[90m[00m[100mstep  7[00m[90m[00m─┤ [36mrun[32m       overlay://test12/app-2.0[00m

 └─[90m[00m[100mstep  8[00m[90m[00m─┤ [36minstall[32m   overlay://test12/web-2.0[00m

 └─[90m[00m[100mstep  9[00m[90m[00m─┤ [32m[00m[42mrun[00m[32m[00m[01m[32m     overlay://test12/web-2.0[00m[00m

Total: 12 actions (4 downloads, 4 installs, 4 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.
```

</details>