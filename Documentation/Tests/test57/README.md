# test57 — Virtual-style ebuild (explicit dep)

**Category:** Virtual

This test case validates that dependencies of a virtual-style ebuild are traversed
and that its provider package is included in the proof/model. The 'virtualsdk-1.0'
ebuild acts as a virtual by depending on 'linux-1.0' as its concrete provider.

**Expected:** When proving web-1.0, the plan/model should include linux-1.0 (via
virtualsdk-1.0). The full chain os -> virtualsdk -> linux should be resolved.

![test57](test57.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.80 s (backtrack: 0/20).

[ebuild  N     ] test57/linux-1.0::overlay  0 KiB
[ebuild  N     ] test57/virtualsdk-1.0::overlay  0 KiB
[ebuild  N     ] test57/os-1.0::overlay  0 KiB
[ebuild  N     ] test57/db-1.0::overlay  0 KiB
[ebuild  N     ] test57/app-1.0::overlay  0 KiB
[ebuild  N     ] test57/web-1.0::overlay  0 KiB

Total: 6 packages (6 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```

>>> Emerging : overlay://test57/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test57/web-1.0
             │ download  overlay://test57/virtualsdk-1.0
             │ download  overlay://test57/os-1.0
             │ download  overlay://test57/linux-1.0
             │ download  overlay://test57/db-1.0
             │ download  overlay://test57/app-1.0

 └─step  2─┤ install   overlay://test57/virtualsdk-1.0
             │ install   overlay://test57/linux-1.0

 └─step  3─┤ run       overlay://test57/linux-1.0

 └─step  4─┤ install   overlay://test57/os-1.0

 └─step  5─┤ run       overlay://test57/virtualsdk-1.0

 └─step  6─┤ run       overlay://test57/os-1.0

 └─step  7─┤ install   overlay://test57/db-1.0

 └─step  8─┤ run       overlay://test57/db-1.0

 └─step  9─┤ install   overlay://test57/app-1.0

 └─step 10─┤ run       overlay://test57/app-1.0

 └─step 11─┤ install   overlay://test57/web-1.0

 └─step 12─┤ run     overlay://test57/web-1.0

Total: 18 actions (6 downloads, 6 installs, 6 runs), grouped into 12 steps.
       0.00 Kb to be downloaded.


```

</details>