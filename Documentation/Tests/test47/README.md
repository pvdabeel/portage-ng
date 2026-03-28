# test47 — Three-way dependency cycle

**Category:** Cycle

This test case presents a more complex, three-way circular dependency. The client needs the docs to build, the docs need the server to run, and the server needs the client to run. This creates a loop that cannot be resolved.

**Expected:** The prover should be able to trace the dependency chain through all three packages and identify the circular dependency, causing the proof to fail.

![test47](test47.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  . ... done!
Dependency resolution took 1.32 s (backtrack: 1/20).



[nomerge       ] test47/api-docs-1.0::overlay 
[ebuild  N     ]  test47/app-server-1.0::overlay  0 KiB
[ebuild  N     ]   test47/app-client-1.0::overlay  0 KiB
[ebuild  N     ]    test47/api-docs-1.0::overlay  0 KiB

Total: 3 packages (3 new), Size of downloads: 0 KiB

 * Error: circular dependencies:

(test47/app-server-1.0:0/0::overlay, ebuild scheduled for merge) depends on
 (test47/app-client-1.0:0/0::overlay, ebuild scheduled for merge) (runtime)
  (test47/api-docs-1.0:0/0::overlay, ebuild scheduled for merge) (buildtime)
   (test47/app-server-1.0:0/0::overlay, ebuild scheduled for merge) (runtime)

 * Note that circular dependencies can often be avoided by temporarily
 * disabling USE flags that trigger optional dependencies.
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```ansi
[93m>>> Emerging : overlay://test47/api-docs-1.0:run?{[]}
[00m
[32mThese are the packages that would be merged, in order:

[00mCalculating dependencies... done!

 └─[90m[00m[100mstep  1[00m[90m[00m─┤ [36mdownload[32m  overlay://test47/app-server-1.0[00m
             │ [36mdownload[32m  overlay://test47/app-client-1.0[00m
             │ [36mdownload[32m  overlay://test47/api-docs-1.0[00m

 └─[90m[00m[100mstep  2[00m[90m[00m─┤ [36minstall[32m   overlay://test47/api-docs-1.0[00m
             │ [36minstall[32m   overlay://test47/app-server-1.0[00m
             │ [36minstall[32m   overlay://test47/app-client-1.0[00m
             │ [36mrun[32m       overlay://test47/app-server-1.0[00m
             │ [36mrun[32m       overlay://test47/app-client-1.0[00m

 └─[90m[00m[100mstep  3[00m[90m[00m─┤ [32m[00m[42mrun[00m[32m[00m[01m[32m     overlay://test47/api-docs-1.0[00m[00m

Total: 9 actions (3 downloads, 3 installs, 3 runs), grouped into 3 steps.
       0.00 Kb to be downloaded.



[00m
```

</details>