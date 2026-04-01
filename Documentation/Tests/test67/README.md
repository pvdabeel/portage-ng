# test67 — Build-only dependency (separate from DEPEND)

**Category:** BDEPEND

This test case checks the prover's handling of BDEPEND (build dependencies). The
'app-1.0' package requires 'toolchain-1.0' only for building (BDEPEND), separate
from its runtime dependency on 'lib-1.0'. BDEPEND is resolved alongside DEPEND
for the install phase.

**Expected:** All three packages should appear in the proof. The toolchain-1.0 should be
resolved as a build dependency of app-1.0, while lib-1.0 is resolved as a runtime
dependency.

![test67](test67.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.74 s (backtrack: 0/20).

[ebuild  N     ] test67/lib-1.0::overlay  0 KiB
[ebuild  N     ] test67/toolchain-1.0::overlay  0 KiB
[ebuild  N     ] test67/app-1.0::overlay  0 KiB

Total: 3 packages (3 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```

>>> Emerging : overlay://test67/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test67/toolchain-1.0
             │ download  overlay://test67/lib-1.0
             │ download  overlay://test67/app-1.0

 └─step  2─┤ install   overlay://test67/lib-1.0
             │ install   overlay://test67/toolchain-1.0

 └─step  3─┤ run       overlay://test67/lib-1.0

 └─step  4─┤ install   overlay://test67/app-1.0

 └─step  5─┤ run     overlay://test67/app-1.0

Total: 8 actions (3 downloads, 3 installs, 2 runs), grouped into 5 steps.
       0.00 Kb to be downloaded.


```

</details>