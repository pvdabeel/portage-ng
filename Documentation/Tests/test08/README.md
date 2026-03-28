# test08 — Indirect cycle (compile + runtime)

**Category:** Cycle

This test case combines test06 and test07. The 'os-1.0' package lists 'web-1.0' as
both a compile-time and runtime dependency, creating two indirect cycles through
the dependency graph.

**Expected:** The prover should detect both cycles and take assumptions to break them, yielding
two verify steps in the proposed plan.

![test08](test08.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.37 s (backtrack: 1/20).



[ebuild  N     ] test08/web-1.0::overlay  0 KiB
[ebuild  N     ]  test08/app-1.0::overlay  0 KiB
[ebuild  N     ]   test08/db-1.0::overlay  0 KiB
[ebuild  N     ]    test08/os-1.0::overlay  0 KiB

Total: 4 packages (4 new), Size of downloads: 0 KiB

 * Error: circular dependencies:

(test08/os-1.0:0/0::overlay, ebuild scheduled for merge) depends on
 (test08/web-1.0:0/0::overlay, ebuild scheduled for merge) (buildtime)
  (test08/os-1.0:0/0::overlay, ebuild scheduled for merge) (buildtime)

 * Note that circular dependencies can often be avoided by temporarily
 * disabling USE flags that trigger optional dependencies.
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```ansi
[93m>>> Emerging : overlay://test08/web-1.0:run?{[]}
[00m
[32mThese are the packages that would be merged, in order:

[00mCalculating dependencies... done!

 └─[90m[00m[100mstep  1[00m[90m[00m─┤ [36mdownload[32m  overlay://test08/web-1.0[00m
             │ [36mdownload[32m  overlay://test08/os-1.0[00m
             │ [36mdownload[32m  overlay://test08/db-1.0[00m
             │ [36mdownload[32m  overlay://test08/app-1.0[00m

 └─[90m[00m[100mstep  2[00m[90m[00m─┤ [36minstall[32m   overlay://test08/web-1.0[00m
             │ [36minstall[32m   overlay://test08/os-1.0[00m
             │ [36minstall[32m   overlay://test08/app-1.0[00m
             │ [36minstall[32m   overlay://test08/db-1.0[00m
             │ [32m[00m[42mrun[00m[32m[00m[01m[32m     overlay://test08/web-1.0[00m[00m
             │ [36mrun[32m       overlay://test08/app-1.0[00m
             │ [36mrun[32m       overlay://test08/db-1.0[00m
             │ [36mrun[32m       overlay://test08/os-1.0[00m

Total: 12 actions (4 downloads, 4 installs, 4 runs), grouped into 2 steps.
       0.00 Kb to be downloaded.



[00m
```

</details>