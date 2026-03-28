# test45 — Irreconcilable USE conflict via ^^

**Category:** Conflict

This test case checks the prover's ability to detect a direct and irreconcilable USE flag conflict. The 'os' package has a REQUIRED_USE constraint of "^^ ( linux darwin )", meaning exactly one of those USE flags must be enabled. However, the dependency graph requires both to be enabled simultaneously to satisfy liba and libb.

**Expected:** The prover should correctly identify the conflict and fail to produce a valid installation proof. There is no possible configuration of USE flags that can satisfy these dependencies.

![test45](test45.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.68 s (backtrack: 0/20).


The following USE changes are necessary to proceed:
 (see "package.use" in the portage(5) man page for more details)
# required by test45/liba-1.0::overlay
# required by test45/app-1.0::overlay
# required by test45/app (argument)
>=test45/os-1.0 darwin linux

!!! The ebuild selected to satisfy "test45/os[linux]" has unmet requirements.
- test45/os-1.0::overlay USE="-darwin -linux"

  The following REQUIRED_USE flag constraints are unsatisfied:
    exactly-one-of ( linux darwin )

(dependency required by "test45/liba-1.0::overlay" [ebuild])
(dependency required by "test45/app-1.0::overlay" [ebuild])
(dependency required by "test45/app" [argument])
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test45/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ useflag overlay://test45/os-1.0 (darwin)

 └─step  2─┤ download  overlay://test45/os-1.0
             │ download  overlay://test45/libb-1.0
             │ download  overlay://test45/liba-1.0
             │ download  overlay://test45/app-1.0

 └─step  3─┤ install   overlay://test45/liba-1.0
             │ install   overlay://test45/libb-1.0
             │ install   overlay://test45/os-1.0 (USE modified)
             │           └─ conf ─┤ USE = "darwin -linux"

 └─step  4─┤ run       overlay://test45/libb-1.0
             │ run       overlay://test45/liba-1.0

 └─step  5─┤ install   overlay://test45/app-1.0

 └─step  6─┤ run     overlay://test45/app-1.0

Total: 12 actions (1 useflag, 4 downloads, 4 installs, 3 runs), grouped into 6 steps.
       0.00 Kb to be downloaded.


>>> Assumptions taken during proving & planning:

  USE flag change (1 package):
  Add to /etc/portage/package.use:
    test45/os darwin

```

</details>