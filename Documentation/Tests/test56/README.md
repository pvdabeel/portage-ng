# test56 — Constraint intersection via dep chains

**Category:** Version

Multiple requirements should be combined. Only one version should be selected

**Expected:** The constraints on the lib versions should be combined. Only one version should be selected, since there is only one slot to fill.

![test56](test56.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.73 s (backtrack: 0/20).

[ebuild  N     ] test56/lib-6.0::overlay  0 KiB
[ebuild  N     ] test56/modulea-1.0::overlay  0 KiB
[ebuild  N     ] test56/moduleb-1.0::overlay  0 KiB
[ebuild  N     ] test56/app-1.0::overlay  0 KiB

Total: 4 packages (4 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```

>>> Emerging : overlay://test56/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test56/moduleb-1.0
             │ download  overlay://test56/modulea-1.0
             │ download  overlay://test56/lib-6.0
             │ download  overlay://test56/app-1.0

 └─step  2─┤ install   overlay://test56/lib-6.0

 └─step  3─┤ run       overlay://test56/lib-6.0

 └─step  4─┤ install   overlay://test56/moduleb-1.0
             │ install   overlay://test56/modulea-1.0

 └─step  5─┤ run       overlay://test56/modulea-1.0
             │ run       overlay://test56/moduleb-1.0

 └─step  6─┤ install   overlay://test56/app-1.0

 └─step  7─┤ run     overlay://test56/app-1.0

Total: 12 actions (4 downloads, 4 installs, 4 runs), grouped into 7 steps.
       0.00 Kb to be downloaded.
```

</details>