# test22 — Any-of || (compile + runtime)

**Category:** Choice

This test case combines test20 and test21. The 'os-1.0' package has the same 'any-of' choice group in both its compile-time and runtime dependencies.

**Expected:** The prover can choose any of the OS packages to satisfy the compile-time dependency and any of the OS packages to satisfy the runtime dependency. They do not have to be the same. The proof should be valid.

![test22](test22.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.05 s (backtrack: 0/20).

[ebuild  N     ] test22/linux-1.0::overlay  0 KiB
[ebuild  N     ] test22/os-1.0::overlay  0 KiB
[ebuild  N     ] test22/db-1.0::overlay  0 KiB
[ebuild  N     ] test22/app-1.0::overlay  0 KiB
[ebuild  N     ] test22/web-1.0::overlay  0 KiB

Total: 5 packages (5 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test22/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test22/web-1.0
             │ download  overlay://test22/os-1.0
             │ download  overlay://test22/linux-1.0
             │ download  overlay://test22/db-1.0
             │ download  overlay://test22/app-1.0

 └─step  2─┤ install   overlay://test22/linux-1.0

 └─step  3─┤ run       overlay://test22/linux-1.0

 └─step  4─┤ install   overlay://test22/os-1.0

 └─step  5─┤ run       overlay://test22/os-1.0

 └─step  6─┤ install   overlay://test22/db-1.0

 └─step  7─┤ run       overlay://test22/db-1.0

 └─step  8─┤ install   overlay://test22/app-1.0

 └─step  9─┤ run       overlay://test22/app-1.0

 └─step 10─┤ install   overlay://test22/web-1.0

 └─step 11─┤ run     overlay://test22/web-1.0

Total: 15 actions (5 downloads, 5 installs, 5 runs), grouped into 11 steps.
       0.00 Kb to be downloaded.
```

</details>