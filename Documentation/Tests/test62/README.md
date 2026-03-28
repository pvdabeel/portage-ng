# test62 — Simple mutual cycle (termination)

**Category:** Cycle

This test case is a prover termination regression test for simple mutual dependency
cycles without blockers, slots, or USE flags. It checks whether per-goal context
growth (e.g. accumulating self() markers or slot information) can defeat cycle
detection and cause backtracking until timeout.

**Expected:** The prover should terminate quickly with a finite model/plan, or fail fast. It must
not spin or backtrack indefinitely. A cycle-break assumption is expected.

![test62](test62.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.75 s (backtrack: 0/20).

[ebuild  N     ] test62/a-1.0::overlay  0 KiB
[ebuild  N     ] test62/b-1.0::overlay  0 KiB
[ebuild  N     ] test62/web-1.0::overlay  0 KiB

Total: 3 packages (3 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test62/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test62/web-1.0
             │ download  overlay://test62/b-1.0
             │ download  overlay://test62/a-1.0

 └─step  2─┤ install   overlay://test62/b-1.0

 └─step  3─┤ run       overlay://test62/b-1.0

 └─step  4─┤ install   overlay://test62/a-1.0

 └─step  5─┤ run       overlay://test62/a-1.0

 └─step  6─┤ install   overlay://test62/web-1.0

 └─step  7─┤ run     overlay://test62/web-1.0

Total: 9 actions (3 downloads, 3 installs, 3 runs), grouped into 7 steps.
       0.00 Kb to be downloaded.
```

</details>