# test30 — Weak blocker ! (compile) + any-of

**Category:** Blocker

This test case is a variation of test27 where the weak blocker (!) is in the
compile-time scope (DEPEND) rather than the runtime scope (RDEPEND). The 'app-1.0'
package weakly blocks 'windows-1.0' at compile time, while 'os-1.0' has an any-of
compile dependency that includes 'windows-1.0'.

**Expected:** The prover should produce a valid plan. The weak blocker is recorded as a domain
assumption. The any-of group resolution may or may not select 'windows-1.0',
depending on blocker handling strategy.

![test30](test30.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.09 s (backtrack: 0/20).

[ebuild  N     ] test30/linux-1.0::overlay  0 KiB
[ebuild  N     ] test30/os-1.0::overlay  0 KiB
[ebuild  N     ] test30/db-1.0::overlay  0 KiB
[ebuild  N     ] test30/app-1.0::overlay  0 KiB
[ebuild  N     ] test30/web-1.0::overlay  0 KiB

Total: 5 packages (5 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test30/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test30/web-1.0
             │ download  overlay://test30/os-1.0
             │ download  overlay://test30/linux-1.0
             │ download  overlay://test30/db-1.0
             │ download  overlay://test30/app-1.0

 └─step  2─┤ install   overlay://test30/os-1.0
             │ install   overlay://test30/linux-1.0

 └─step  3─┤ run       overlay://test30/os-1.0

 └─step  4─┤ install   overlay://test30/db-1.0

 └─step  5─┤ run       overlay://test30/db-1.0

 └─step  6─┤ install   overlay://test30/app-1.0

 └─step  7─┤ run       overlay://test30/app-1.0

 └─step  8─┤ install   overlay://test30/web-1.0

 └─step  9─┤ run     overlay://test30/web-1.0

Total: 14 actions (5 downloads, 5 installs, 4 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.



>>> Blockers added during proving & planning:

  [blocks B] !test30/windows (soft blocker, phase: install, required by: overlay://test30/app-1.0)



```

</details>