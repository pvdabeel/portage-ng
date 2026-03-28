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
<summary><b>emerge</b></summary>

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

```
>>> Emerging : overlay://test61/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ useflag overlay://test61/a-1.0 (foo)
             │ useflag overlay://test61/b-1.0 (foo)

 └─step  2─┤ download  overlay://test61/b-1.0
             │ download  overlay://test61/app-1.0
             │ download  overlay://test61/a-1.0

 └─step  3─┤ install   overlay://test61/a-1.0
             │           └─ conf ─┤ USE = "-foo"
             │ install   overlay://test61/b-1.0 (USE modified)
             │           └─ conf ─┤ USE = "foo"
             │ run       overlay://test61/a-1.0 (USE modified)
             │ run       overlay://test61/b-1.0 (USE modified)

 └─step  4─┤ install   overlay://test61/app-1.0

 └─step  5─┤ run     overlay://test61/app-1.0

Total: 11 actions (2 useflags, 3 downloads, 3 installs, 3 runs), grouped into 5 steps.
       0.00 Kb to be downloaded.



>>> Assumptions taken during proving & planning:

  USE flag change (2 packages):
  Add to /etc/portage/package.use:
    test61/a foo
    test61/b foo



```

</details>