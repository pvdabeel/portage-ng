# test04 — Self-dependency (runtime)

**Category:** Cycle

This test case is a variation of test03 where the self-dependency is in the runtime
scope (RDEPEND) instead of compile-time. The 'os-1.0' package lists itself as a
runtime dependency.

**Expected:** The prover should take a cycle-break assumption for os-1.0's runtime dependency on
itself, yielding a verify step in the proposed plan. Note that Gentoo emerge is
less strict about runtime self-dependencies and may not report circular
dependencies in this case.

![test04](test04.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.91 s (backtrack: 0/20).

[ebuild  N     ] test04/os-1.0::overlay  0 KiB
[ebuild  N     ] test04/db-1.0::overlay  0 KiB
[ebuild  N     ] test04/app-1.0::overlay  0 KiB
[ebuild  N     ] test04/web-1.0::overlay  0 KiB

Total: 4 packages (4 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```ansi
[93m>>> Emerging : overlay://test04/web-1.0:run?{[]}
[00m
[32mThese are the packages that would be merged, in order:

[00mCalculating dependencies... done!

 └─[90m[00m[100mstep  1[00m[90m[00m─┤ [36mdownload[32m  overlay://test04/web-1.0[00m
             │ [36mdownload[32m  overlay://test04/os-1.0[00m
             │ [36mdownload[32m  overlay://test04/db-1.0[00m
             │ [36mdownload[32m  overlay://test04/app-1.0[00m

 └─[90m[00m[100mstep  2[00m[90m[00m─┤ [36minstall[32m   overlay://test04/os-1.0[00m

 └─[90m[00m[100mstep  3[00m[90m[00m─┤ [36minstall[32m   overlay://test04/db-1.0[00m

 └─[90m[00m[100mstep  4[00m[90m[00m─┤ [36mrun[32m       overlay://test04/db-1.0[00m

 └─[90m[00m[100mstep  5[00m[90m[00m─┤ [36minstall[32m   overlay://test04/app-1.0[00m

 └─[90m[00m[100mstep  6[00m[90m[00m─┤ [36mrun[32m       overlay://test04/app-1.0[00m

 └─[90m[00m[100mstep  7[00m[90m[00m─┤ [36minstall[32m   overlay://test04/web-1.0[00m

 └─[90m[00m[100mstep  8[00m[90m[00m─┤ [32m[00m[42mrun[00m[32m[00m[01m[32m     overlay://test04/web-1.0[00m[00m

Total: 11 actions (4 downloads, 4 installs, 3 runs), grouped into 8 steps.
       0.00 Kb to be downloaded.
```

</details>