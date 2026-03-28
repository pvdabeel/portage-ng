# test29 — Strong blocker !! (compile+runtime) + any-of

**Category:** Blocker

This test case combines test26 and test28. The 'app-1.0' package has a strong
blocker (!!) against 'windows-1.0' in both the compile-time (DEPEND) and runtime
(RDEPEND) scopes. The any-of group on 'os-1.0' still includes 'windows-1.0'.

**Expected:** The prover should produce a valid plan that avoids 'windows-1.0'. It should select
either 'linux-1.0' or 'bsd-1.0' for the any-of group, since 'windows-1.0' is
strongly blocked in both scopes.

![test29](test29.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.09 s (backtrack: 0/20).

[ebuild  N     ] test29/linux-1.0::overlay  0 KiB
[ebuild  N     ] test29/os-1.0::overlay  0 KiB
[ebuild  N     ] test29/db-1.0::overlay  0 KiB
[ebuild  N     ] test29/app-1.0::overlay  0 KiB
[ebuild  N     ] test29/web-1.0::overlay  0 KiB

Total: 5 packages (5 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test29/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test29/web-1.0
             │ download  overlay://test29/os-1.0
             │ download  overlay://test29/linux-1.0
             │ download  overlay://test29/db-1.0
             │ download  overlay://test29/app-1.0

 └─step  2─┤ install   overlay://test29/os-1.0
             │ install   overlay://test29/linux-1.0

 └─step  3─┤ run       overlay://test29/os-1.0

 └─step  4─┤ install   overlay://test29/db-1.0

 └─step  5─┤ run       overlay://test29/db-1.0

 └─step  6─┤ install   overlay://test29/app-1.0

 └─step  7─┤ run       overlay://test29/app-1.0

 └─step  8─┤ install   overlay://test29/web-1.0

 └─step  9─┤ run     overlay://test29/web-1.0

Total: 14 actions (5 downloads, 5 installs, 4 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.
```

</details>