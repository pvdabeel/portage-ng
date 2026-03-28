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

```ansi
[93m>>> Emerging : overlay://test62/web-1.0:run?{[]}
[00m
[32mThese are the packages that would be merged, in order:

[00mCalculating dependencies... done!

 └─[90m[00m[100mstep  1[00m[90m[00m─┤ [36mdownload[32m  overlay://test62/web-1.0[00m
             │ [36mdownload[32m  overlay://test62/b-1.0[00m
             │ [36mdownload[32m  overlay://test62/a-1.0[00m

 └─[90m[00m[100mstep  2[00m[90m[00m─┤ [36minstall[32m   overlay://test62/b-1.0[00m
             │ [36minstall[32m   overlay://test62/a-1.0[00m
             │ [36mrun[32m       overlay://test62/b-1.0[00m
             │ [36mrun[32m       overlay://test62/a-1.0[00m

 └─[90m[00m[100mstep  3[00m[90m[00m─┤ [36minstall[32m   overlay://test62/web-1.0[00m

 └─[90m[00m[100mstep  4[00m[90m[00m─┤ [32m[00m[42mrun[00m[32m[00m[01m[32m     overlay://test62/web-1.0[00m[00m

Total: 9 actions (3 downloads, 3 installs, 3 runs), grouped into 4 steps.
       0.00 Kb to be downloaded.



[00m
```

</details>