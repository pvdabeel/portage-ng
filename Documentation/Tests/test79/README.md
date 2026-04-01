# test79 — PDEPEND cycle (A needs B, B PDEPEND A)

**Category:** PDEPEND

This test case checks the handling of cycles involving PDEPEND. The server needs
the client at runtime, and the client has a PDEPEND back on the server. Since
PDEPEND is resolved post-install (via proof obligations), this cycle should be
naturally broken by the ordering: server installs first, then client, then the
PDEPEND obligation for server is already satisfied.

**Expected:** Both packages should appear in the proof without infinite loops. The PDEPEND cycle
should be handled gracefully by the proof obligation mechanism, not treated as a
hard circular dependency requiring assumptions.

![test79](test79.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.73 s (backtrack: 0/20).

[ebuild  N     ] test79/client-1.0::overlay  0 KiB
[ebuild  N     ] test79/server-1.0::overlay  0 KiB

Total: 2 packages (2 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```

>>> Emerging : overlay://test79/server-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test79/server-1.0
             │ download  overlay://test79/client-1.0

 └─step  2─┤ install   overlay://test79/client-1.0

 └─step  3─┤ run       overlay://test79/client-1.0

 └─step  4─┤ install   overlay://test79/server-1.0

 └─step  5─┤ run     overlay://test79/server-1.0

Total: 6 actions (2 downloads, 2 installs, 2 runs), grouped into 5 steps.
       0.00 Kb to be downloaded.


```

</details>