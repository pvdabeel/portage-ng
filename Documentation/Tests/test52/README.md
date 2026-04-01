# test52 — Multiple USE flags on shared dep

**Category:** USE merge

The prover will first prove os-1.0 through the liba path. This means os-1.0 will have 'threads' enabled. Later prover needs to enable 'hardened' through the libb path. The prover should be able to produce a proof with just one os install, for both 'threads' and 'hardeded'. This should also be reflected in the download for os-1.0

**Expected:** The prover should correctly identify the need for building os-1.0 only once with the two use flags.

![test52](test52.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.76 s (backtrack: 0/20).

[ebuild  N     ] test52/os-1.0::overlay  USE="hardened threads" 0 KiB
[ebuild  N     ] test52/liba-1.0::overlay  0 KiB
[ebuild  N     ] test52/libb-1.0::overlay  0 KiB
[ebuild  N     ] test52/app-1.0::overlay  0 KiB

Total: 4 packages (4 new), Size of downloads: 0 KiB

The following USE changes are necessary to proceed:
 (see "package.use" in the portage(5) man page for more details)
# required by test52/libb-1.0::overlay
# required by test52/app-1.0::overlay
# required by test52/app (argument)
>=test52/os-1.0 hardened
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```

>>> Emerging : overlay://test52/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ useflag overlay://test52/os-1.0 (hardened)

 └─step  2─┤ download  overlay://test52/os-1.0
             │ download  overlay://test52/libb-1.0
             │ download  overlay://test52/liba-1.0
             │ download  overlay://test52/app-1.0

 └─step  3─┤ install   overlay://test52/liba-1.0
             │ install   overlay://test52/libb-1.0
             │ install   overlay://test52/os-1.0 (USE modified)
             │           └─ conf ─┤ USE = "threads* hardened"

 └─step  4─┤ run       overlay://test52/libb-1.0
             │ run       overlay://test52/liba-1.0

 └─step  5─┤ install   overlay://test52/app-1.0

 └─step  6─┤ run     overlay://test52/app-1.0

Total: 12 actions (1 useflag, 4 downloads, 4 installs, 3 runs), grouped into 6 steps.
       0.00 Kb to be downloaded.


>>> Assumptions taken during proving & planning:

  USE flag change (1 package):
  Add to /etc/portage/package.use:
    test52/os hardened


```

</details>