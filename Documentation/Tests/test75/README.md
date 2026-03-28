# test75 — Installed same version, emptytree (VDB)

**Category:** Reinstall

This test case checks the prover's behavior when the --emptytree flag is active.
Even though os-1.0 is already installed, the emptytree flag should force the
prover to re-prove it rather than skipping it as satisfied. This exercises the
reinstall path.

**Expected:** With emptytree behavior, os-1.0 should appear in the proof despite being installed.
The plan should include a reinstall or fresh install action for os-1.0.

![test75](test75.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.74 s (backtrack: 0/20).

[ebuild  N     ] test75/os-1.0::overlay  0 KiB
[ebuild  N     ] test75/app-1.0::overlay  0 KiB

Total: 2 packages (2 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test75/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test75/os-1.0
             │ download  overlay://test75/app-1.0

 └─step  2─┤ install   overlay://test75/os-1.0

 └─step  3─┤ run       overlay://test75/os-1.0

 └─step  4─┤ install   overlay://test75/app-1.0

 └─step  5─┤ run     overlay://test75/app-1.0

Total: 6 actions (2 downloads, 2 installs, 2 runs), grouped into 5 steps.
       0.00 Kb to be downloaded.
```

</details>