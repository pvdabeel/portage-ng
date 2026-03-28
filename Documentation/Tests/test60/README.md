# test60 — Versioned soft blocker !<pkg-ver (XFAIL)

**Category:** Blocker

> **XFAIL** — expected to fail.

This test case checks the handling of versioned soft blockers (!<pkg-version). The
'app-1.0' package blocks any version of 'windows' less than 2.0. The any-of group
on 'os-1.0' offers both windows-1.0 and windows-2.0 as choices. The solver should
avoid windows-1.0 because it falls within the blocker's version range.

**Expected:** Currently expected to fail (XFAIL): the versioned blocker is handled via
assumptions rather than by steering the version choice. When fixed, the solver
should select windows-2.0 and avoid windows-1.0.

![test60](test60.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.04 s (backtrack: 0/20).

[ebuild  N     ] test60/windows-2.0::overlay  0 KiB
[ebuild  N     ] test60/os-1.0::overlay  0 KiB
[ebuild  N     ] test60/app-1.0::overlay  0 KiB
[ebuild  N     ] test60/db-1.0::overlay  0 KiB
[ebuild  N     ] test60/web-1.0::overlay  0 KiB

Total: 5 packages (5 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```ansi
[93m>>> Emerging : overlay://test60/web-1.0:run?{[]}
[00m
[32mThese are the packages that would be merged, in order:

[00mCalculating dependencies... done!

 └─[90m[00m[100mstep  1[00m[90m[00m─┤ [36mdownload[32m  overlay://test60/windows-1.0[00m
             │ [36mdownload[32m  overlay://test60/web-1.0[00m
             │ [36mdownload[32m  overlay://test60/os-1.0[00m
             │ [36mdownload[32m  overlay://test60/db-1.0[00m
             │ [36mdownload[32m  overlay://test60/app-1.0[00m

 └─[90m[00m[100mstep  2[00m[90m[00m─┤ [36minstall[32m   overlay://test60/windows-1.0[00m

 └─[90m[00m[100mstep  3[00m[90m[00m─┤ [36mrun[32m       overlay://test60/windows-1.0[37m ([91mblocked[37m: [91msoft[37m by [32mtest60/app[37m)[00m[00m

 └─[90m[00m[100mstep  4[00m[90m[00m─┤ [36minstall[32m   overlay://test60/os-1.0[00m

 └─[90m[00m[100mstep  5[00m[90m[00m─┤ [36mrun[32m       overlay://test60/os-1.0[00m

 └─[90m[00m[100mstep  6[00m[90m[00m─┤ [36minstall[32m   overlay://test60/app-1.0[00m
             │ [36minstall[32m   overlay://test60/db-1.0[00m

 └─[90m[00m[100mstep  7[00m[90m[00m─┤ [36mrun[32m       overlay://test60/db-1.0[00m
             │ [36mrun[32m       overlay://test60/app-1.0[00m

 └─[90m[00m[100mstep  8[00m[90m[00m─┤ [36minstall[32m   overlay://test60/web-1.0[00m

 └─[90m[00m[100mstep  9[00m[90m[00m─┤ [32m[00m[42mrun[00m[32m[00m[01m[32m     overlay://test60/web-1.0[00m[00m

Total: 15 actions (5 downloads, 5 installs, 5 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.



[93m>>> Blockers added during proving & planning:[00m

[90m  [blocks B] !<test60/windows-2.0 (soft blocker, phase: run, required by: overlay://test60/app-1.0)
[00m

[00m
```

</details>