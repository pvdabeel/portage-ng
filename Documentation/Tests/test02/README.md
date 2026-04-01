# test02 — Version selection (2.0 over 1.0)

**Category:** Basic

This test case checks that the prover selects the latest available version when
multiple versions exist and no version constraints are specified. All dependencies
are unversioned, so the prover should prefer version 2.0 over 1.0 for every
package.

**Expected:** The plan should contain only version 2.0 packages (os-2.0, db-2.0, app-2.0,
web-2.0). No version 1.0 packages should appear. If the proposed plan is not
accepted, the prover should backtrack over available versions, proposing
alternative plans.

![test02](test02.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.74 s (backtrack: 0/20).

[ebuild  N     ] test02/os-2.0::overlay  0 KiB
[ebuild  N     ] test02/db-2.0::overlay  0 KiB
[ebuild  N     ] test02/app-2.0::overlay  0 KiB
[ebuild  N     ] test02/web-2.0::overlay  0 KiB

Total: 4 packages (4 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```

>>> Emerging : overlay://test02/web-2.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test02/web-2.0
             │ download  overlay://test02/os-2.0
             │ download  overlay://test02/db-2.0
             │ download  overlay://test02/app-2.0

 └─step  2─┤ install   overlay://test02/os-2.0

 └─step  3─┤ run       overlay://test02/os-2.0

 └─step  4─┤ install   overlay://test02/db-2.0

 └─step  5─┤ run       overlay://test02/db-2.0

 └─step  6─┤ install   overlay://test02/app-2.0

 └─step  7─┤ run       overlay://test02/app-2.0

 └─step  8─┤ install   overlay://test02/web-2.0

 └─step  9─┤ run     overlay://test02/web-2.0

Total: 12 actions (4 downloads, 4 installs, 4 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.


```

</details>