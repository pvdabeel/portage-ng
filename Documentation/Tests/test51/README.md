# test51 — USE dep vs REQUIRED_USE contradiction

**Category:** Conflict

This test case presents a direct and unsolvable conflict between a dependency's USE requirement and the target package's REQUIRED_USE. 'app-1.0' needs 'os-1.0' with the 'linux' flag, but 'os-1.0' explicitly forbids that flag from being enabled.

**Expected:** The prover should immediately detect the contradiction between the USE dependency and the REQUIRED_USE constraint and fail to produce a valid proof.

![test51](test51.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.60 s (backtrack: 0/20).


The following USE changes are necessary to proceed:
 (see "package.use" in the portage(5) man page for more details)
# required by test51/app-1.0::overlay
# required by test51/app (argument)
>=test51/os-1.0 linux

!!! The ebuild selected to satisfy "test51/os[linux]" has unmet requirements.
- test51/os-1.0::overlay USE="-linux"

  The following REQUIRED_USE flag constraints are unsatisfied:
    !linux

(dependency required by "test51/app-1.0::overlay" [ebuild])
(dependency required by "test51/app" [argument])
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test51/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ useflag overlay://test51/os-1.0 (linux)

 └─step  2─┤ download  overlay://test51/os-1.0
             │ download  overlay://test51/app-1.0

 └─step  3─┤ install   overlay://test51/os-1.0 (USE modified)
             │           └─ conf ─┤ USE = "linux"

 └─step  4─┤ install   overlay://test51/app-1.0

 └─step  5─┤ run     overlay://test51/app-1.0

Total: 6 actions (1 useflag, 2 downloads, 2 installs, 1 run), grouped into 5 steps.
       0.00 Kb to be downloaded.


>>> Assumptions taken during proving & planning:

  USE flag change (1 package):
  Add to /etc/portage/package.use:
    test51/os linux

```

</details>