# test26 — Strong blocker !! (runtime) + any-of

**Category:** Blocker

This test case checks the prover's handling of a strong blocker (!!). The 'app-1.0'
package has a strong runtime blocker against 'windows-1.0'. At the same time,
'os-1.0' has an any-of compile dependency that includes 'windows-1.0' as a choice.
The prover must recognize that selecting 'windows-1.0' for the any-of group would
conflict with the strong blocker on 'app-1.0', and should steer the selection
toward 'linux-1.0' or 'bsd-1.0' instead.

**Expected:** The prover should produce a valid plan that avoids 'windows-1.0'. It should select
either 'linux-1.0' or 'bsd-1.0' to satisfy the any-of group on 'os-1.0', since
'windows-1.0' is strongly blocked by 'app-1.0' in the runtime scope.

![test26](test26.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  .... done!
Dependency resolution took 1.08 s (backtrack: 0/20).

[ebuild  N     ] test26/linux-1.0::overlay  0 KiB
[ebuild  N     ] test26/os-1.0::overlay  0 KiB
[ebuild  N     ] test26/db-1.0::overlay  0 KiB
[ebuild  N     ] test26/app-1.0::overlay  0 KiB
[ebuild  N     ] test26/web-1.0::overlay  0 KiB

Total: 5 packages (5 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test26/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test26/web-1.0
             │ download  overlay://test26/os-1.0
             │ download  overlay://test26/linux-1.0
             │ download  overlay://test26/db-1.0
             │ download  overlay://test26/app-1.0

 └─step  2─┤ install   overlay://test26/os-1.0
             │ install   overlay://test26/linux-1.0

 └─step  3─┤ run       overlay://test26/os-1.0

 └─step  4─┤ install   overlay://test26/db-1.0

 └─step  5─┤ run       overlay://test26/db-1.0

 └─step  6─┤ install   overlay://test26/app-1.0

 └─step  7─┤ run       overlay://test26/app-1.0

 └─step  8─┤ install   overlay://test26/web-1.0

 └─step  9─┤ run     overlay://test26/web-1.0

Total: 14 actions (5 downloads, 5 installs, 4 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.
```

</details>