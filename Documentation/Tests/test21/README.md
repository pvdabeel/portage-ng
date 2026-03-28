# test21 — Any-of || (runtime)

**Category:** Choice

This is a variation of test20, with the 'any-of' dependency group in the runtime scope (RDEPEND).

**Expected:** The prover should handle the runtime choice group correctly, select one of the OS options, and generate a valid proof.

![test21](test21.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.75 s (backtrack: 0/20).

[ebuild  N     ] test21/linux-1.0::overlay  0 KiB
[ebuild  N     ] test21/os-1.0::overlay  0 KiB
[ebuild  N     ] test21/db-1.0::overlay  0 KiB
[ebuild  N     ] test21/app-1.0::overlay  0 KiB
[ebuild  N     ] test21/web-1.0::overlay  0 KiB

Total: 5 packages (5 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test21/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test21/web-1.0
             │ download  overlay://test21/os-1.0
             │ download  overlay://test21/linux-1.0
             │ download  overlay://test21/db-1.0
             │ download  overlay://test21/app-1.0

 └─step  2─┤ install   overlay://test21/os-1.0
             │ install   overlay://test21/linux-1.0

 └─step  3─┤ run       overlay://test21/linux-1.0

 └─step  4─┤ run       overlay://test21/os-1.0

 └─step  5─┤ install   overlay://test21/db-1.0

 └─step  6─┤ run       overlay://test21/db-1.0

 └─step  7─┤ install   overlay://test21/app-1.0

 └─step  8─┤ run       overlay://test21/app-1.0

 └─step  9─┤ install   overlay://test21/web-1.0

 └─step 10─┤ run     overlay://test21/web-1.0

Total: 15 actions (5 downloads, 5 installs, 5 runs), grouped into 10 steps.
       0.00 Kb to be downloaded.
```

</details>