# test36 — Chained equality [linux=] through lib

**Category:** USE dep

This test case examines the prover's ability to propagate a conditional USE flag requirement down a dependency chain. The USE="linux" setting on 'app-1.0' should flow down to 'lib-1.0', which in turn should flow down to 'os-1.0'.

**Expected:** If 'app-1.0' is proven with USE="linux", the prover should enforce USE="linux" on both 'lib-1.0' and 'os-1.0'. Conversely, if 'app-1.0' has USE="-linux", that requirement should also propagate down the chain. The proof should be valid in both scenarios.

![test36](test36.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.90 s (backtrack: 0/20).

[ebuild  N     ] test36/os-1.0::overlay  USE="-darwin -linux" 0 KiB
[ebuild  N     ] test36/lib-1.0::overlay  USE="-linux" 0 KiB
[ebuild  N     ] test36/app-1.0::overlay  USE="-linux" 0 KiB

Total: 3 packages (3 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test36/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test36/os-1.0
             │ download  overlay://test36/lib-1.0
             │ download  overlay://test36/app-1.0

 └─step  2─┤ install   overlay://test36/os-1.0
             │           └─ conf ─┤ USE = "-darwin -linux"

 └─step  3─┤ install   overlay://test36/lib-1.0
             │           └─ conf ─┤ USE = "-linux"

 └─step  4─┤ install   overlay://test36/app-1.0
             │           └─ conf ─┤ USE = "-linux"

 └─step  5─┤ run     overlay://test36/app-1.0

Total: 7 actions (3 downloads, 3 installs, 1 run), grouped into 5 steps.
       0.00 Kb to be downloaded.
```

</details>