# test27 — Weak blocker ! (runtime) + any-of

**Category:** Blocker

This test case checks the prover's handling of a weak blocker (!). The 'app-1.0'
package has a weak runtime blocker against 'windows-1.0'. Unlike the strong blocker
in test26, a weak blocker is advisory: it signals that 'windows-1.0' should be
uninstalled if already present, but does not absolutely forbid its co-existence.
The any-of group on 'os-1.0' still includes 'windows-1.0' as a candidate.

**Expected:** The prover should produce a valid plan. The weak blocker is recorded as a domain
assumption. The any-of group resolution may or may not select 'windows-1.0',
depending on blocker handling strategy.

![test27](test27.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.75 s (backtrack: 0/20).

[ebuild  N     ] test27/linux-1.0::overlay  0 KiB
[ebuild  N     ] test27/os-1.0::overlay  0 KiB
[ebuild  N     ] test27/db-1.0::overlay  0 KiB
[ebuild  N     ] test27/app-1.0::overlay  0 KiB
[ebuild  N     ] test27/web-1.0::overlay  0 KiB

Total: 5 packages (5 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test27/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test27/web-1.0
             │ download  overlay://test27/os-1.0
             │ download  overlay://test27/linux-1.0
             │ download  overlay://test27/db-1.0
             │ download  overlay://test27/app-1.0

 └─step  2─┤ install   overlay://test27/os-1.0
             │ install   overlay://test27/linux-1.0

 └─step  3─┤ run       overlay://test27/os-1.0

 └─step  4─┤ install   overlay://test27/db-1.0

 └─step  5─┤ run       overlay://test27/db-1.0

 └─step  6─┤ install   overlay://test27/app-1.0

 └─step  7─┤ run       overlay://test27/app-1.0

 └─step  8─┤ install   overlay://test27/web-1.0

 └─step  9─┤ run     overlay://test27/web-1.0

Total: 14 actions (5 downloads, 5 installs, 4 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.



>>> Blockers added during proving & planning:

  [blocks B] !test27/windows (soft blocker, phase: run, required by: overlay://test27/app-1.0)
```

</details>