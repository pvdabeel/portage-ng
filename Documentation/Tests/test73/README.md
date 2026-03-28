# test73 — Installed old version, newer available (VDB)

**Category:** Update

This test case checks the prover's update path. When lib-1.0 is already installed
and lib-2.0 is available, the prover should detect that an update is possible and
trigger the :update action instead of :install. This requires VDB simulation to
mark lib-1.0 as installed.

**Expected:** The prover should select lib-2.0 as an update replacing the installed lib-1.0. The
plan should show an update action for lib, not a fresh install.

![test73](test73.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.78 s (backtrack: 0/20).

[ebuild  N     ] test73/lib-2.0::overlay  0 KiB
[ebuild  N     ] test73/app-1.0::overlay  0 KiB

Total: 2 packages (2 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test73/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test73/lib-2.0
             │ download  overlay://test73/app-1.0

 └─step  2─┤ install   overlay://test73/lib-2.0

 └─step  3─┤ install   overlay://test73/app-1.0

 └─step  4─┤ run     overlay://test73/app-1.0

Total: 5 actions (2 downloads, 2 installs, 1 run), grouped into 4 steps.
       0.00 Kb to be downloaded.
```

</details>