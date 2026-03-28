# test01 — Simple dependency ordering

**Category:** Basic

This test case checks basic dependency resolution with both compile-time and
runtime dependencies. The prover must correctly order all four packages and
identify opportunities for parallel execution.

**Expected:** The prover should produce a valid plan installing all four packages. Packages with
no unsatisfied dependencies (os-1.0) should come first. Packages that share the
same set of resolved dependencies (app-1.0, db-1.0) can be grouped into a parallel
step. The final step installs web-1.0.

![test01](test01.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.69 s (backtrack: 0/20).

[ebuild  N     ] test01/os-1.0::overlay  0 KiB
[ebuild  N     ] test01/db-1.0::overlay  0 KiB
[ebuild  N     ] test01/app-1.0::overlay  0 KiB
[ebuild  N     ] test01/web-1.0::overlay  0 KiB

Total: 4 packages (4 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test01/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test01/web-1.0
             │ download  overlay://test01/os-1.0
             │ download  overlay://test01/db-1.0
             │ download  overlay://test01/app-1.0

 └─step  2─┤ install   overlay://test01/os-1.0

 └─step  3─┤ run       overlay://test01/os-1.0

 └─step  4─┤ install   overlay://test01/db-1.0

 └─step  5─┤ run       overlay://test01/db-1.0

 └─step  6─┤ install   overlay://test01/app-1.0

 └─step  7─┤ run       overlay://test01/app-1.0

 └─step  8─┤ install   overlay://test01/web-1.0

 └─step  9─┤ run     overlay://test01/web-1.0

Total: 12 actions (4 downloads, 4 installs, 4 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.
```

</details>