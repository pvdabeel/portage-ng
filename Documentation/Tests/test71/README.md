# test71 — Download-only action

**Category:** Fetchonly

This test case checks the prover's handling of the fetchonly action. The dependency
structure is identical to test01, but the entry point uses :fetchonly instead of
:run. In fetchonly mode, only download actions should be produced, with no
install/run steps.

**Expected:** All four packages should appear in the proof with download/fetchonly actions. No
install or run steps should be produced in the plan.

![test71](test71.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be fetched, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.75 s (backtrack: 0/20).
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```

>>> Emerging : overlay://test71/web-1.0:fetchonly?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test71/web-1.0
             │ download  overlay://test71/os-1.0
             │ download  overlay://test71/db-1.0
             │ download  overlay://test71/app-1.0

Total: 4 actions (4 downloads), grouped into 1 step.
       0.00 Kb to be downloaded.


```

</details>