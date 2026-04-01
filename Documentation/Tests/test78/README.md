# test78 — Skip target, install deps only

**Category:** Onlydeps

This test case checks the --onlydeps behavior. When the entry point target
(web-1.0) is proven with the onlydeps_target context flag, the target package
itself should not appear in the install plan, but all of its dependencies should
still be resolved and included.

**Expected:** The dependencies (app-1.0, db-1.0, os-1.0) should appear in the proof and plan.
The target package web-1.0 should be excluded from the install actions, though it
may still appear in the proof for dependency traversal purposes.

![test78](test78.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

[ebuild  N     ] test78/web-1.0::overlay  0 KiB

Total: 1 package (1 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```

>>> Emerging : overlay://test78/web-1.0:run?{[onlydeps_target]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test78/web-1.0
             │ download  overlay://test78/os-1.0
             │ download  overlay://test78/db-1.0
             │ download  overlay://test78/app-1.0

 └─step  2─┤ install   overlay://test78/os-1.0

 └─step  3─┤ run       overlay://test78/os-1.0

 └─step  4─┤ install   overlay://test78/db-1.0

 └─step  5─┤ run       overlay://test78/db-1.0

 └─step  6─┤ install   overlay://test78/app-1.0

 └─step  7─┤ run       overlay://test78/app-1.0

 └─step  8─┤ install   overlay://test78/web-1.0

 └─step  9─┤ run     overlay://test78/web-1.0

Total: 12 actions (4 downloads, 4 installs, 4 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.


```

</details>