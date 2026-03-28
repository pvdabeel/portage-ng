# test41 — Explicit slot :1

**Category:** Slot

This test case checks the prover's ability to resolve dependencies based on slotting. 'app-1.0' requires a version of 'lib' that is in slot "1". Even though 'lib-2.0' is a higher version, it is in a different slot and therefore not a candidate.

**Expected:** The prover should correctly select 'lib-1.0' to satisfy the slot dependency, ignoring the newer 'lib-2.0'. The proof should be valid.

![test41](test41.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  .... done!
Dependency resolution took 0.89 s (backtrack: 0/20).

[ebuild  N     ] test41/lib-1.0:1::overlay  0 KiB
[ebuild  N     ] test41/app-1.0::overlay  0 KiB

Total: 2 packages (2 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test41/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test41/lib-1.0
             │ download  overlay://test41/app-1.0

 └─step  2─┤ install   overlay://test41/lib-1.0

 └─step  3─┤ run       overlay://test41/lib-1.0

 └─step  4─┤ install   overlay://test41/app-1.0

 └─step  5─┤ run     overlay://test41/app-1.0

Total: 6 actions (2 downloads, 2 installs, 2 runs), grouped into 5 steps.
       0.00 Kb to be downloaded.
```

</details>