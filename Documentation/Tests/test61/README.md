# test61 — Mutual recursion with bracketed USE

**Category:** Cycle

This test case checks termination and cycle handling when bracketed USE
dependencies ([foo]) are present in a mutual recursion. The 'a' and 'b' packages
each require the other with a specific USE flag. The prover must ensure that the
build_with_use context does not grow unbounded as it traverses the cycle.

**Expected:** The solver should terminate quickly, either by cycle breaking or by producing a
finite plan. It must not spin or backtrack indefinitely due to accumulating USE
context.

![test61](test61.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  
!!! 'test61/app' has a category that is not listed in /etc/portage/categories
... done!
Dependency resolution took 0.46 s (backtrack: 0/20).


emerge: there are no ebuilds to satisfy "test61/app".

emerge: searching for similar names...
emerge: Maybe you meant any of these: test60/app, test56/app, test51/app?
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```ansi
[93m>>> Emerging : overlay://test61/app-1.0:run?{[]}
[00m
[32mThese are the packages that would be merged, in order:

[00mCalculating dependencies... done!

 └─[90m[00m[100mstep  1[00m[90m[00m─┤ [33m[00m[43museflag[00m[33m[00m[32m overlay://test61/a-1.0[90m (foo)[00m
             │ [33m[00m[43museflag[00m[33m[00m[32m overlay://test61/b-1.0[90m (foo)[00m

 └─[90m[00m[100mstep  2[00m[90m[00m─┤ [36mdownload[32m  overlay://test61/b-1.0[00m
             │ [36mdownload[32m  overlay://test61/app-1.0[00m
             │ [36mdownload[32m  overlay://test61/a-1.0[00m

 └─[90m[00m[100mstep  3[00m[90m[00m─┤ [36minstall[32m   overlay://test61/a-1.0[00m
             │           [90m└─ conf ─┤ [00m[90m[00m[100mUSE[00m[90m[00m = "[90m[03m-foo[00m"
             │ [36minstall[32m   overlay://test61/b-1.0[90m (USE modified)[00m
             │           [90m└─ conf ─┤ [00m[90m[00m[100mUSE[00m[90m[00m = "[33mfoo[00m"
             │ [36mrun[32m       overlay://test61/a-1.0[90m (USE modified)[00m
             │ [36mrun[32m       overlay://test61/b-1.0[90m (USE modified)[00m

 └─[90m[00m[100mstep  4[00m[90m[00m─┤ [36minstall[32m   overlay://test61/app-1.0[00m

 └─[90m[00m[100mstep  5[00m[90m[00m─┤ [32m[00m[42mrun[00m[32m[00m[01m[32m     overlay://test61/app-1.0[00m[00m

Total: 11 actions (2 useflags, 3 downloads, 3 installs, 3 runs), grouped into 5 steps.
       0.00 Kb to be downloaded.



[93m>>> Assumptions taken during proving & planning:[00m

  USE flag change (2 packages):
[00m[90m  Add to /etc/portage/package.use:
    test61/a foo
    test61/b foo
[00m

[00m
```

</details>