# test03 — Self-dependency (compile)

**Category:** Cycle

This test case checks the prover's handling of a direct self-dependency in the
compile-time scope. The 'os-1.0' package lists itself as a compile-time dependency,
creating an immediate cycle. The prover must detect this cycle and take an
assumption to break it.

**Expected:** The prover should take a cycle-break assumption for os-1.0's compile dependency on
itself, yielding a verify step in the proposed plan. The plan should still include
all four packages.

![test03](test03.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.30 s (backtrack: 1/20).



[ebuild  N     ] test03/web-1.0::overlay  0 KiB
[ebuild  N     ]  test03/app-1.0::overlay  0 KiB
[ebuild  N     ]   test03/db-1.0::overlay  0 KiB
[ebuild  N     ]    test03/os-1.0::overlay  0 KiB

Total: 4 packages (4 new), Size of downloads: 0 KiB

 * Error: circular dependencies:

(test03/os-1.0:0/0::overlay, ebuild scheduled for merge) depends on
 (test03/os-1.0:0/0::overlay, ebuild scheduled for merge) (buildtime)

 * Note that circular dependencies can often be avoided by temporarily
 * disabling USE flags that trigger optional dependencies.
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```ansi
[93m>>> Emerging : overlay://test03/web-1.0:run?{[]}
[00m
[32mThese are the packages that would be merged, in order:

[00mCalculating dependencies... done!

 └─[90m[00m[100mstep  1[00m[90m[00m─┤ [36mdownload[32m  overlay://test03/web-1.0[00m
             │ [36mdownload[32m  overlay://test03/os-1.0[00m
             │ [36mdownload[32m  overlay://test03/db-1.0[00m
             │ [36mdownload[32m  overlay://test03/app-1.0[00m

 └─[90m[00m[100mstep  2[00m[90m[00m─┤ [36minstall[32m   overlay://test03/os-1.0[00m

 └─[90m[00m[100mstep  3[00m[90m[00m─┤ [36mrun[32m       overlay://test03/os-1.0[00m

 └─[90m[00m[100mstep  4[00m[90m[00m─┤ [36minstall[32m   overlay://test03/db-1.0[00m

 └─[90m[00m[100mstep  5[00m[90m[00m─┤ [36mrun[32m       overlay://test03/db-1.0[00m

 └─[90m[00m[100mstep  6[00m[90m[00m─┤ [36minstall[32m   overlay://test03/app-1.0[00m

 └─[90m[00m[100mstep  7[00m[90m[00m─┤ [36mrun[32m       overlay://test03/app-1.0[00m

 └─[90m[00m[100mstep  8[00m[90m[00m─┤ [36minstall[32m   overlay://test03/web-1.0[00m

 └─[90m[00m[100mstep  9[00m[90m[00m─┤ [32m[00m[42mrun[00m[32m[00m[01m[32m     overlay://test03/web-1.0[00m[00m

Total: 12 actions (4 downloads, 4 installs, 4 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.



[00m
```

</details>