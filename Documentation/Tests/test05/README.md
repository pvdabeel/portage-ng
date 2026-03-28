# test05 — Self-dependency (compile + runtime)

**Category:** Cycle

This test case combines test03 and test04. The 'os-1.0' package lists itself as
both a compile-time and runtime dependency, creating two self-referential cycles.

**Expected:** The prover should take two cycle-break assumptions: one for the compile-time
self-dependency and one for the runtime self-dependency. Both should yield verify
steps in the proposed plan.

![test05](test05.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.32 s (backtrack: 1/20).



[ebuild  N     ] test05/web-1.0::overlay  0 KiB
[ebuild  N     ]  test05/app-1.0::overlay  0 KiB
[ebuild  N     ]   test05/db-1.0::overlay  0 KiB
[ebuild  N     ]    test05/os-1.0::overlay  0 KiB

Total: 4 packages (4 new), Size of downloads: 0 KiB

 * Error: circular dependencies:

(test05/os-1.0:0/0::overlay, ebuild scheduled for merge) depends on
 (test05/os-1.0:0/0::overlay, ebuild scheduled for merge) (buildtime)

 * Note that circular dependencies can often be avoided by temporarily
 * disabling USE flags that trigger optional dependencies.
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```ansi
[93m>>> Emerging : overlay://test05/web-1.0:run?{[]}
[00m
[32mThese are the packages that would be merged, in order:

[00mCalculating dependencies... done!

 └─[90m[00m[100mstep  1[00m[90m[00m─┤ [36mdownload[32m  overlay://test05/web-1.0[00m
             │ [36mdownload[32m  overlay://test05/os-1.0[00m
             │ [36mdownload[32m  overlay://test05/db-1.0[00m
             │ [36mdownload[32m  overlay://test05/app-1.0[00m

 └─[90m[00m[100mstep  2[00m[90m[00m─┤ [36minstall[32m   overlay://test05/os-1.0[00m

 └─[90m[00m[100mstep  3[00m[90m[00m─┤ [36minstall[32m   overlay://test05/db-1.0[00m

 └─[90m[00m[100mstep  4[00m[90m[00m─┤ [36mrun[32m       overlay://test05/db-1.0[00m

 └─[90m[00m[100mstep  5[00m[90m[00m─┤ [36minstall[32m   overlay://test05/app-1.0[00m

 └─[90m[00m[100mstep  6[00m[90m[00m─┤ [36mrun[32m       overlay://test05/app-1.0[00m

 └─[90m[00m[100mstep  7[00m[90m[00m─┤ [36minstall[32m   overlay://test05/web-1.0[00m

 └─[90m[00m[100mstep  8[00m[90m[00m─┤ [32m[00m[42mrun[00m[32m[00m[01m[32m     overlay://test05/web-1.0[00m[00m

Total: 11 actions (4 downloads, 4 installs, 3 runs), grouped into 8 steps.
       0.00 Kb to be downloaded.



[00m
```

</details>