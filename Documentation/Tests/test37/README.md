# test37 — Inverse equality [!linux=]

**Category:** USE dep

This test case checks the handling of an inverse conditional USE dependency. The dependency `os[!linux=]` means that the 'linux' flag on 'os-1.0' must be the inverse of the setting on 'app-1.0'.

**Expected:** - If 'app-1.0' is proven with USE="linux", the prover must enforce USE="-linux" on 'os-1.0'.
- If 'app-1.0' is proven with USE="-linux", the prover must enforce USE="linux" on 'os-1.0'.
The proof should be valid in both scenarios.

![test37](test37.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.82 s (backtrack: 0/20).

[ebuild  N     ] test37/os-1.0::overlay  USE="linux -darwin" 0 KiB
[ebuild  N     ] test37/app-1.0::overlay  USE="-linux" 0 KiB

Total: 2 packages (2 new), Size of downloads: 0 KiB

The following USE changes are necessary to proceed:
 (see "package.use" in the portage(5) man page for more details)
# required by test37/app-1.0::overlay
# required by test37/app (argument)
>=test37/os-1.0 linux
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test37/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ useflag overlay://test37/os-1.0 (linux)

 └─step  2─┤ download  overlay://test37/os-1.0
             │ download  overlay://test37/app-1.0

 └─step  3─┤ install   overlay://test37/os-1.0 (USE modified)
             │           └─ conf ─┤ USE = "-darwin linux"

 └─step  4─┤ install   overlay://test37/app-1.0
             │           └─ conf ─┤ USE = "-linux"

 └─step  5─┤ run     overlay://test37/app-1.0

Total: 6 actions (1 useflag, 2 downloads, 2 installs, 1 run), grouped into 5 steps.
       0.00 Kb to be downloaded.


>>> Assumptions taken during proving & planning:

  USE flag change (1 package):
  Add to /etc/portage/package.use:
    test37/os linux

```

</details>