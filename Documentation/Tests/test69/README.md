# test69 — Operator >= (greater-or-equal)

**Category:** Version

This test case checks the prover's handling of the >= (greater-or-equal) version
operator. The 'app-1.0' package requires lib version 3.0 or higher. Versions 1.0
and 2.0 should be excluded; versions 3.0, 4.0, and 5.0 are valid candidates.

**Expected:** The prover should select the latest valid version, lib-5.0, to satisfy the
dependency. Versions 1.0 and 2.0 should not appear in the proof.

![test69](test69.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.74 s (backtrack: 0/20).

[ebuild  N     ] test69/lib-5.0::overlay  0 KiB
[ebuild  N     ] test69/app-1.0::overlay  0 KiB

Total: 2 packages (2 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test69/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test69/lib-5.0
             │ download  overlay://test69/app-1.0

 └─step  2─┤ install   overlay://test69/lib-5.0

 └─step  3─┤ install   overlay://test69/app-1.0

 └─step  4─┤ run     overlay://test69/app-1.0

Total: 5 actions (2 downloads, 2 installs, 1 run), grouped into 4 steps.
       0.00 Kb to be downloaded.
```

</details>