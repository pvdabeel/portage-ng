# test31 — Weak blocker ! (compile+runtime) + any-of

**Category:** Blocker

This test case combines test27 and test30. The 'app-1.0' package has a weak
blocker (!) against 'windows-1.0' in both the compile-time (DEPEND) and runtime
(RDEPEND) scopes. The any-of group on 'os-1.0' still includes 'windows-1.0'.

**Expected:** The prover should produce a valid plan. The weak blockers are recorded as domain
assumptions. The any-of group resolution may or may not select 'windows-1.0',
depending on blocker handling strategy.

![test31](test31.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.07 s (backtrack: 0/20).

[ebuild  N     ] test31/linux-1.0::overlay  0 KiB
[ebuild  N     ] test31/os-1.0::overlay  0 KiB
[ebuild  N     ] test31/db-1.0::overlay  0 KiB
[ebuild  N     ] test31/app-1.0::overlay  0 KiB
[ebuild  N     ] test31/web-1.0::overlay  0 KiB

Total: 5 packages (5 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```ansi
[93m>>> Emerging : overlay://test31/web-1.0:run?{[]}
[00m
[32mThese are the packages that would be merged, in order:

[00mCalculating dependencies... done!

 └─[90m[00m[100mstep  1[00m[90m[00m─┤ [36mdownload[32m  overlay://test31/web-1.0[00m
             │ [36mdownload[32m  overlay://test31/os-1.0[00m
             │ [36mdownload[32m  overlay://test31/linux-1.0[00m
             │ [36mdownload[32m  overlay://test31/db-1.0[00m
             │ [36mdownload[32m  overlay://test31/app-1.0[00m

 └─[90m[00m[100mstep  2[00m[90m[00m─┤ [36minstall[32m   overlay://test31/os-1.0[00m
             │ [36minstall[32m   overlay://test31/linux-1.0[00m

 └─[90m[00m[100mstep  3[00m[90m[00m─┤ [36mrun[32m       overlay://test31/os-1.0[00m

 └─[90m[00m[100mstep  4[00m[90m[00m─┤ [36minstall[32m   overlay://test31/db-1.0[00m

 └─[90m[00m[100mstep  5[00m[90m[00m─┤ [36mrun[32m       overlay://test31/db-1.0[00m

 └─[90m[00m[100mstep  6[00m[90m[00m─┤ [36minstall[32m   overlay://test31/app-1.0[00m

 └─[90m[00m[100mstep  7[00m[90m[00m─┤ [36mrun[32m       overlay://test31/app-1.0[00m

 └─[90m[00m[100mstep  8[00m[90m[00m─┤ [36minstall[32m   overlay://test31/web-1.0[00m

 └─[90m[00m[100mstep  9[00m[90m[00m─┤ [32m[00m[42mrun[00m[32m[00m[01m[32m     overlay://test31/web-1.0[00m[00m

Total: 14 actions (5 downloads, 5 installs, 4 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.



[93m>>> Blockers added during proving & planning:[00m

[90m  [blocks B] !test31/windows (soft blocker, phase: install, required by: overlay://test31/app-1.0)
[00m[90m  [blocks B] !test31/windows (soft blocker, phase: run, required by: overlay://test31/app-1.0)
[00m

[00m
```

</details>