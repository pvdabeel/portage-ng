# test65 — build_with_use reinstall semantics

**Category:** Installed

This test case is a regression test for rules:installed_entry_satisfies_build_with_use/2.
It ensures that an installed VDB entry cannot be treated as satisfying a dependency
if incoming build_with_use requires a flag that the installed package was not built
with. The test uses an always-false flag requirement (__portage_ng_test_flag__)
against an arbitrary installed package.

**Expected:** The test validation checks that the rule correctly identifies unsatisfied
build_with_use requirements on installed packages. The prover should find that no
installed entry satisfies the synthetic flag requirement, and the rule should
produce non-empty conditions.

![test65](test65.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  
!!! 'test65/app' has a category that is not listed in /etc/portage/categories
... done!
Dependency resolution took 0.46 s (backtrack: 0/20).


emerge: there are no ebuilds to satisfy "test65/app".

emerge: searching for similar names...
emerge: Maybe you meant any of these: test60/app, test59/app, test58/app?
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test65/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test65/app-1.0

 └─step  2─┤ install   overlay://test65/app-1.0

 └─step  3─┤ run     overlay://test65/app-1.0

Total: 3 actions (1 download, 1 install, 1 run), grouped into 3 steps.
       0.00 Kb to be downloaded.
```

</details>