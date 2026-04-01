# test32 — ^^ with conditional DEPEND

**Category:** REQUIRED_USE

This test case examines the interplay between REQUIRED_USE and conditional dependencies. The 'os-1.0' package must have exactly one of 'linux' or 'darwin' enabled. The choice of which flag is enabled will then trigger the corresponding dependency.

**Expected:** The prover should satisfy the REQUIRED_USE by making a choice. For example, it might enable the 'linux' flag. This action should then trigger the conditional dependency, pulling 'linux-1.0' into the installation plan. A valid proof will include os-1.0 and either linux-1.0 or darwin-1.0.

![test32](test32.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  

!!! Problem resolving dependencies for test32/os
... done!
Dependency resolution took 0.48 s (backtrack: 0/20).


!!! The ebuild selected to satisfy "test32/os" has unmet requirements.
- test32/os-1.0::overlay USE="-darwin -linux"

  The following REQUIRED_USE flag constraints are unsatisfied:
    exactly-one-of ( linux darwin )
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```

>>> Emerging : overlay://test32/os-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ useflag overlay://test32/os-1.0 (darwin)

 └─step  2─┤ download  overlay://test32/os-1.0

 └─step  3─┤ install   overlay://test32/os-1.0 (USE modified)
             │           └─ conf ─┤ USE = "darwin -linux"

 └─step  4─┤ run     overlay://test32/os-1.0

Total: 4 actions (1 useflag, 1 download, 1 install, 1 run), grouped into 4 steps.
       0.00 Kb to be downloaded.


>>> Assumptions taken during proving & planning:

  USE flag change (1 package):
  Add to /etc/portage/package.use:
    test32/os darwin


```

</details>