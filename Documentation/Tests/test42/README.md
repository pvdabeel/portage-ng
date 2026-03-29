# test42 — Wildcard slot :*

**Category:** Slot

This test case checks the prover's behavior with a wildcard slot dependency. 'app-1.0' requires 'lib', but it doesn't care which slot is used.

**Expected:** Given the choice between two valid slots, the prover should follow the default behavior of picking the latest version, which is 'lib-2.0' in slot "2". The proof should be valid.

![test42](test42.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.73 s (backtrack: 0/20).

[ebuild  N     ] test42/lib-2.0:2::overlay  0 KiB
[ebuild  N     ] test42/app-1.0::overlay  0 KiB

Total: 2 packages (2 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```

>>> Emerging : overlay://test42/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test42/lib-2.0
             │ download  overlay://test42/app-1.0

 └─step  2─┤ install   overlay://test42/lib-2.0
             │           └─ conf ─┤ SLOT = "2"

 └─step  3─┤ run       overlay://test42/lib-2.0

 └─step  4─┤ install   overlay://test42/app-1.0

 └─step  5─┤ run     overlay://test42/app-1.0

Total: 6 actions (2 downloads, 2 installs, 2 runs), grouped into 5 steps.
       0.00 Kb to be downloaded.
```

</details>