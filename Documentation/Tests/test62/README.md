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
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  
!!! 'test62/web' has a category that is not listed in /etc/portage/categories
... done!
Dependency resolution took 0.47 s (backtrack: 0/20).


emerge: there are no ebuilds to satisfy "test62/web".

emerge: searching for similar names...
emerge: Maybe you meant any of these: test60/web, test29/web, test28/web?
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
             │ install   overlay://test62/a-1.0
             │ run       overlay://test62/b-1.0
             │ run       overlay://test62/a-1.0

 └─step  3─┤ install   overlay://test62/web-1.0

 └─step  4─┤ run     overlay://test62/web-1.0

Total: 9 actions (3 downloads, 3 installs, 3 runs), grouped into 4 steps.
       0.00 Kb to be downloaded.




```

</details>