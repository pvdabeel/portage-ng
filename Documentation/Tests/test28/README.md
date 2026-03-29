# test28 — Strong blocker !! (compile) + any-of

**Category:** Blocker

This test case is a variation of test26 where the strong blocker (!!) is in the
compile-time scope (DEPEND) rather than the runtime scope (RDEPEND). The 'app-1.0'
package strongly blocks 'windows-1.0' at compile time, while 'os-1.0' has an
any-of compile dependency that includes 'windows-1.0'.

**Expected:** The prover should produce a valid plan that avoids 'windows-1.0'. It should select
either 'linux-1.0' or 'bsd-1.0' to satisfy the any-of group on 'os-1.0', since
'windows-1.0' is strongly blocked by 'app-1.0' in the compile scope.

![test28](test28.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.75 s (backtrack: 0/20).

[ebuild  N     ] test28/linux-1.0::overlay  0 KiB
[ebuild  N     ] test28/os-1.0::overlay  0 KiB
[ebuild  N     ] test28/db-1.0::overlay  0 KiB
[ebuild  N     ] test28/app-1.0::overlay  0 KiB
[ebuild  N     ] test28/web-1.0::overlay  0 KiB

Total: 5 packages (5 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```

>>> Emerging : overlay://test28/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test28/web-1.0
             │ download  overlay://test28/os-1.0
             │ download  overlay://test28/linux-1.0
             │ download  overlay://test28/db-1.0
             │ download  overlay://test28/app-1.0

 └─step  2─┤ install   overlay://test28/os-1.0
             │ install   overlay://test28/linux-1.0

 └─step  3─┤ run       overlay://test28/os-1.0

 └─step  4─┤ install   overlay://test28/db-1.0

 └─step  5─┤ run       overlay://test28/db-1.0

 └─step  6─┤ install   overlay://test28/app-1.0

 └─step  7─┤ run       overlay://test28/app-1.0

 └─step  8─┤ install   overlay://test28/web-1.0

 └─step  9─┤ run     overlay://test28/web-1.0

Total: 14 actions (5 downloads, 5 installs, 4 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.
```

</details>