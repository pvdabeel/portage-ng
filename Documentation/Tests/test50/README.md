# test50 — Compile dep's RDEPEND must appear

**Category:** Transitive

This test case examines the prover's handling of transitive dependencies, specifically how a runtime dependency of a compile-time dependency is treated. 'app-1.0' needs 'foo-1.0' to build. 'foo-1.0' itself needs 'bar-1.0' to run.

**Expected:** When proving for 'app-1.0', the prover should correctly identify that both 'foo-1.0' and 'bar-1.0' need to be installed. The proof should be valid, and the installation plan should include all three packages in the correct order (bar, foo, app).

![test50](test50.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.90 s (backtrack: 0/20).

[ebuild  N     ] test50/bar-1.0::overlay  0 KiB
[ebuild  N     ] test50/foo-1.0::overlay  0 KiB
[ebuild  N     ] test50/app-1.0::overlay  0 KiB

Total: 3 packages (3 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```ansi
[93m>>> Emerging : overlay://test50/app-1.0:run?{[]}
[00m
[32mThese are the packages that would be merged, in order:

[00mCalculating dependencies... done!

 └─[90m[00m[100mstep  1[00m[90m[00m─┤ [36mdownload[32m  overlay://test50/foo-1.0[00m
             │ [36mdownload[32m  overlay://test50/bar-1.0[00m
             │ [36mdownload[32m  overlay://test50/app-1.0[00m

 └─[90m[00m[100mstep  2[00m[90m[00m─┤ [36minstall[32m   overlay://test50/bar-1.0[00m

 └─[90m[00m[100mstep  3[00m[90m[00m─┤ [36mrun[32m       overlay://test50/bar-1.0[00m

 └─[90m[00m[100mstep  4[00m[90m[00m─┤ [36minstall[32m   overlay://test50/foo-1.0[00m

 └─[90m[00m[100mstep  5[00m[90m[00m─┤ [36minstall[32m   overlay://test50/app-1.0[00m

 └─[90m[00m[100mstep  6[00m[90m[00m─┤ [32m[00m[42mrun[00m[32m[00m[01m[32m     overlay://test50/app-1.0[00m[00m

Total: 8 actions (3 downloads, 3 installs, 2 runs), grouped into 6 steps.
       0.00 Kb to be downloaded.
```

</details>