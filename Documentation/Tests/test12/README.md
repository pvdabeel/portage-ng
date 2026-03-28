# test12 — Stable vs unstable keyword acceptance

**Category:** Keywords

This test case examines the prover's handling of package keywords and stability. The latest (2.0) versions of the packages are marked as unstable. Without a specific configuration to accept these unstable keywords, the package manager should not select them.

**Expected:** Assuming a default configuration that only allows stable packages, the prover should reject the 2.0 versions and instead resolve the dependencies using the stable 1.0 versions. The final proof should be for app-1.0, db-1.0, and os-1.0.

![test12](test12.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.91 s (backtrack: 0/20).

[ebuild  N     ] test12/os-2.0::overlay  0 KiB
[ebuild  N     ] test12/db-2.0::overlay  0 KiB
[ebuild  N     ] test12/app-2.0::overlay  0 KiB
[ebuild  N     ] test12/web-2.0::overlay  0 KiB

Total: 4 packages (4 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test12/web-2.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test12/web-2.0
             │ download  overlay://test12/os-2.0
             │ download  overlay://test12/db-2.0
             │ download  overlay://test12/app-2.0

 └─step  2─┤ install   overlay://test12/os-2.0

 └─step  3─┤ run       overlay://test12/os-2.0

 └─step  4─┤ install   overlay://test12/db-2.0

 └─step  5─┤ run       overlay://test12/db-2.0

 └─step  6─┤ install   overlay://test12/app-2.0

 └─step  7─┤ run       overlay://test12/app-2.0

 └─step  8─┤ install   overlay://test12/web-2.0

 └─step  9─┤ run     overlay://test12/web-2.0

Total: 12 actions (4 downloads, 4 installs, 4 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.
```

</details>