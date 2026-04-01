# test72 — Install-time dependency

**Category:** IDEPEND

This test case checks the prover's handling of IDEPEND (install-time dependencies).
IDEPEND is an EAPI 8 feature that specifies packages needed at install time on the
target system (as opposed to BDEPEND which is for the build system). The 'app-1.0'
package requires 'installer-1.0' at install time.

**Expected:** Both packages should appear in the proof. The installer-1.0 should be resolved as
an install-time dependency and be available before app-1.0's install phase.

![test72](test72.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.75 s (backtrack: 0/20).

[ebuild  N     ] test72/installer-1.0::overlay  0 KiB
[ebuild  N     ] test72/app-1.0::overlay  0 KiB

Total: 2 packages (2 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```

>>> Emerging : overlay://test72/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test72/installer-1.0
             │ download  overlay://test72/app-1.0

 └─step  2─┤ install   overlay://test72/installer-1.0

 └─step  3─┤ install   overlay://test72/app-1.0

 └─step  4─┤ run     overlay://test72/app-1.0

Total: 5 actions (2 downloads, 2 installs, 1 run), grouped into 4 steps.
       0.00 Kb to be downloaded.


```

</details>