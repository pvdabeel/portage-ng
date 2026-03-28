# test76 — Installed with wrong USE, rebuild needed (VDB)

**Category:** Newuse

This test case checks the prover's newuse rebuild behavior. The installed os-1.0
was built without the 'linux' USE flag, but app-1.0 requires os[linux]. The prover
should detect that the installed version does not satisfy the incoming
build_with_use requirement and trigger a rebuild.

**Expected:** The prover should detect that os-1.0 needs to be rebuilt with USE="linux" enabled.
The plan should include a rebuild action for os-1.0.

![test76](test76.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.73 s (backtrack: 0/20).

[ebuild  N     ] test76/os-1.0::overlay  USE="linux -darwin" 0 KiB
[ebuild  N     ] test76/app-1.0::overlay  0 KiB

Total: 2 packages (2 new), Size of downloads: 0 KiB

The following USE changes are necessary to proceed:
 (see "package.use" in the portage(5) man page for more details)
# required by test76/app-1.0::overlay
# required by test76/app (argument)
>=test76/os-1.0 linux
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test76/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ useflag overlay://test76/os-1.0 (linux)

 └─step  2─┤ download  overlay://test76/os-1.0
             │ download  overlay://test76/app-1.0

 └─step  3─┤ install   overlay://test76/os-1.0 (USE modified)
             │           └─ conf ─┤ USE = "-darwin linux"

 └─step  4─┤ install   overlay://test76/app-1.0

 └─step  5─┤ run     overlay://test76/app-1.0

Total: 6 actions (1 useflag, 2 downloads, 2 installs, 1 run), grouped into 5 steps.
       0.00 Kb to be downloaded.


>>> Assumptions taken during proving & planning:

  USE flag change (1 package):
  Add to /etc/portage/package.use:
    test76/os linux
```

</details>