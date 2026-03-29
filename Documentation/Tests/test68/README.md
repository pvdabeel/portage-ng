# test68 — Co-installation of same CN in different slots

**Category:** Multi-slot

This test case checks the prover's ability to resolve dependencies on multiple
slots of the same package simultaneously. The 'app-1.0' package requires both
slot 1 and slot 2 of 'lib', which correspond to different versions. Both must
appear in the plan since different slots can coexist.

**Expected:** Both lib-1.0 (slot 1) and lib-2.0 (slot 2) should appear in the proof. The prover
should recognize that different slots are independent installation targets and
include both in the plan.

![test68](test68.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.74 s (backtrack: 0/20).

[ebuild  N     ] test68/lib-1.0:1::overlay  0 KiB
[ebuild  N     ] test68/lib-2.0:2::overlay  0 KiB
[ebuild  N     ] test68/app-1.0::overlay  0 KiB

Total: 3 packages (3 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```

>>> Emerging : overlay://test68/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test68/lib-2.0
             │ download  overlay://test68/lib-1.0
             │ download  overlay://test68/app-1.0

 └─step  2─┤ install   overlay://test68/lib-1.0
             │           └─ conf ─┤ SLOT = "1"
             │ install   overlay://test68/lib-2.0
             │           └─ conf ─┤ SLOT = "2"

 └─step  3─┤ install   overlay://test68/app-1.0

 └─step  4─┤ run     overlay://test68/app-1.0

Total: 7 actions (3 downloads, 3 installs, 1 run), grouped into 4 steps.
       0.00 Kb to be downloaded.
```

</details>