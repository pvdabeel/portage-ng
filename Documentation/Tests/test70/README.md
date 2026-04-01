# test70 — Operator ~ (revision match)

**Category:** Version

This test case checks the prover's handling of the ~ (revision match) version
operator. The dependency ~lib-2.0 should match lib-2.0 and lib-2.0-r1 (any
revision of the 2.0 base version) but NOT lib-3.0 (different base version).

**Expected:** The prover should select lib-2.0-r1 (the latest matching revision of 2.0). 
lib-3.0 should not be considered a valid candidate for this dependency.

![test70](test70.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.73 s (backtrack: 0/20).

[ebuild  N     ] test70/lib-2.0-r1::overlay  0 KiB
[ebuild  N     ] test70/app-1.0::overlay  0 KiB

Total: 2 packages (2 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```

>>> Emerging : overlay://test70/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test70/lib-2.0-r1
             │ download  overlay://test70/app-1.0

 └─step  2─┤ install   overlay://test70/lib-2.0-r1

 └─step  3─┤ install   overlay://test70/app-1.0

 └─step  4─┤ run     overlay://test70/app-1.0

Total: 5 actions (2 downloads, 2 installs, 1 run), grouped into 4 steps.
       0.00 Kb to be downloaded.


```

</details>