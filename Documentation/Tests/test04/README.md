# test04 — Self-dependency (runtime)

**Category:** Cycle

This test case is a variation of test03 where the self-dependency is in the runtime
scope (RDEPEND) instead of compile-time. The 'os-1.0' package lists itself as a
runtime dependency. Runtime self-dependencies are trivially satisfied (a package
provides itself once built) and are silently resolved by both Portage and
portage-ng.

**Expected:** The prover should produce a clean plan with all four packages and no cycle-break
assumptions or verify steps. Gentoo emerge also handles runtime self-dependencies
silently.

![test04](test04.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.78 s (backtrack: 0/20).

[ebuild  N     ] test04/os-1.0::overlay  0 KiB
[ebuild  N     ] test04/db-1.0::overlay  0 KiB
[ebuild  N     ] test04/app-1.0::overlay  0 KiB
[ebuild  N     ] test04/web-1.0::overlay  0 KiB

Total: 4 packages (4 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```

>>> Emerging : overlay://test04/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test04/web-1.0
             │ download  overlay://test04/os-1.0
             │ download  overlay://test04/db-1.0
             │ download  overlay://test04/app-1.0

 └─step  2─┤ install   overlay://test04/os-1.0

 └─step  3─┤ install   overlay://test04/db-1.0

 └─step  4─┤ run       overlay://test04/db-1.0

 └─step  5─┤ install   overlay://test04/app-1.0

 └─step  6─┤ run       overlay://test04/app-1.0

 └─step  7─┤ install   overlay://test04/web-1.0

 └─step  8─┤ run     overlay://test04/web-1.0

Total: 11 actions (4 downloads, 4 installs, 3 runs), grouped into 8 steps.
       0.00 Kb to be downloaded.


```

</details>