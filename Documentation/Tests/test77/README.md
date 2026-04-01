# test77 — Unused package removal (VDB)

**Category:** Depclean

This test case checks the depclean action. When run with :depclean, the prover
should traverse the installed dependency graph starting from world targets and
identify packages that are not reachable. The 'orphan-1.0' package is installed
but nothing depends on it, making it a candidate for removal.

**Expected:** The depclean analysis should identify orphan-1.0 as removable since it has no
reverse dependencies in the installed package graph. app-1.0 and os-1.0 should
be retained.

![test77](test77.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.73 s (backtrack: 0/20).

[ebuild  N     ] test77/os-1.0::overlay  0 KiB
[ebuild  N     ] test77/app-1.0::overlay  0 KiB

Total: 2 packages (2 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```

>>> Emerging : overlay://test77/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test77/os-1.0
             │ download  overlay://test77/app-1.0

 └─step  2─┤ install   overlay://test77/os-1.0

 └─step  3─┤ run       overlay://test77/os-1.0

 └─step  4─┤ install   overlay://test77/app-1.0

 └─step  5─┤ run     overlay://test77/app-1.0

Total: 6 actions (2 downloads, 2 installs, 2 runs), grouped into 5 steps.
       0.00 Kb to be downloaded.


```

</details>