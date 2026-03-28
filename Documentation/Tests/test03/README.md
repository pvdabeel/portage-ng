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
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.22 s (backtrack: 1/20).



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

```
>>> Emerging : overlay://test03/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ verify  test03/os (assumed installed) 
             │ download  overlay://test03/web-1.0
             │ download  overlay://test03/os-1.0
             │ download  overlay://test03/db-1.0
             │ download  overlay://test03/app-1.0

 └─step  2─┤ install   overlay://test03/os-1.0

 └─step  3─┤ run       overlay://test03/os-1.0

 └─step  4─┤ install   overlay://test03/db-1.0

 └─step  5─┤ run       overlay://test03/db-1.0

 └─step  6─┤ install   overlay://test03/app-1.0

 └─step  7─┤ run       overlay://test03/app-1.0

 └─step  8─┤ install   overlay://test03/web-1.0

 └─step  9─┤ run     overlay://test03/web-1.0

Total: 12 actions (4 downloads, 4 installs, 4 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.


>>> Cycle breaks (prover)

  grouped_package_dependency(no,test03,os,[package_dependency(install,no,test03,os,none,version_none,[],[])]):install
```

</details>