# test53 — USE merge + conditional extra dep

**Category:** USE merge

The prover will first prove os-1.0 through the liba path. This means os-1.0 will have 'threads' enabled. Later prover needs to enable 'hardened' through the libb path. The prover should be able to produce a proof with just one os install, for both 'threads' and 'hardeded'. This should also be reflected in the download for os-1.0. Introducing 'hardened' on the already proven os-1.0 should pull in a new dependency on libhardened-1.0

**Expected:** The prover should correctly identify the need for building os-1.0 only once with the two use flags, and the libhardened-1.0 dependency

![test53](test53.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.97 s (backtrack: 0/20).

[ebuild  N     ] test53/libhardened-1.0::overlay  0 KiB
[ebuild  N     ] test53/os-1.0::overlay  USE="hardened threads" 0 KiB
[ebuild  N     ] test53/liba-1.0::overlay  0 KiB
[ebuild  N     ] test53/libb-1.0::overlay  0 KiB
[ebuild  N     ] test53/app-1.0::overlay  0 KiB

Total: 5 packages (5 new), Size of downloads: 0 KiB

The following USE changes are necessary to proceed:
 (see "package.use" in the portage(5) man page for more details)
# required by test53/libb-1.0::overlay
# required by test53/app-1.0::overlay
# required by test53/app (argument)
>=test53/os-1.0 hardened
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test53/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ useflag overlay://test53/os-1.0 (hardened)

 └─step  2─┤ download  overlay://test53/os-1.0
             │ download  overlay://test53/libhardened-1.0
             │ download  overlay://test53/libb-1.0
             │ download  overlay://test53/liba-1.0
             │ download  overlay://test53/app-1.0

 └─step  3─┤ install   overlay://test53/liba-1.0
             │ install   overlay://test53/libb-1.0
             │ install   overlay://test53/libhardened-1.0

 └─step  4─┤ run       overlay://test53/libhardened-1.0
             │ run       overlay://test53/libb-1.0
             │ run       overlay://test53/liba-1.0

 └─step  5─┤ install   overlay://test53/os-1.0 (USE modified)
             │           └─ conf ─┤ USE = "threads* hardened"

 └─step  6─┤ install   overlay://test53/app-1.0

 └─step  7─┤ run     overlay://test53/app-1.0

Total: 15 actions (1 useflag, 5 downloads, 5 installs, 4 runs), grouped into 7 steps.
       0.00 Kb to be downloaded.


>>> Assumptions taken during proving & planning:

  USE flag change (1 package):
  Add to /etc/portage/package.use:
    test53/os hardened

```

</details>