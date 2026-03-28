# test13 — Pinpointed version =pkg-ver

**Category:** Version

This test case introduces a specific version constraint. The 'app-2.0' package explicitly requires 'db-2.0' (using the '=' operator), even though a 'db-1.0' is also available.

**Expected:** The prover must respect the version constraint. It should select 'db-2.0' and then proceed to resolve the rest of the dependencies, selecting the latest available versions for other packages like 'os-2.0'. The final proof should be for app-2.0, db-2.0, and os-2.0.

![test13](test13.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
zsh:1: test13/web-2.0 not found
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test13/web-2.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test13/web-2.0
             │ download  overlay://test13/os-2.0
             │ download  overlay://test13/db-2.0
             │ download  overlay://test13/app-2.0

 └─step  2─┤ install   overlay://test13/os-2.0

 └─step  3─┤ run       overlay://test13/os-2.0

 └─step  4─┤ install   overlay://test13/db-2.0

 └─step  5─┤ run       overlay://test13/db-2.0

 └─step  6─┤ install   overlay://test13/app-2.0

 └─step  7─┤ run       overlay://test13/app-2.0

 └─step  8─┤ install   overlay://test13/web-2.0

 └─step  9─┤ run     overlay://test13/web-2.0

Total: 12 actions (4 downloads, 4 installs, 4 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.
```

</details>