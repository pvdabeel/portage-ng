# test16 — Explicit all-of group ( ) syntax

**Category:** Parser

This test case checks the parser's handling of explicit all-of group
parenthesization in dependency specifications. The 'web-1.0' package wraps two of
its runtime dependencies in an explicit all-of group: ( db-1.0 os-1.0 ). In PMS,
this is semantically equivalent to listing them flat (as in test01), but the parser
must correctly handle the parenthesized form without treating it as a choice group.

**Expected:** The prover should successfully resolve the dependencies and generate the same valid
proof as test01. The all-of group should be transparent to the resolver: app-1.0,
db-1.0, and os-1.0 should all appear in the plan in the correct order.

![test16](test16.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.74 s (backtrack: 0/20).

[ebuild  N     ] test16/os-1.0::overlay  0 KiB
[ebuild  N     ] test16/db-1.0::overlay  0 KiB
[ebuild  N     ] test16/app-1.0::overlay  0 KiB
[ebuild  N     ] test16/web-1.0::overlay  0 KiB

Total: 4 packages (4 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```

>>> Emerging : overlay://test16/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test16/web-1.0
             │ download  overlay://test16/os-1.0
             │ download  overlay://test16/db-1.0
             │ download  overlay://test16/app-1.0

 └─step  2─┤ install   overlay://test16/os-1.0

 └─step  3─┤ run       overlay://test16/os-1.0

 └─step  4─┤ install   overlay://test16/db-1.0

 └─step  5─┤ run       overlay://test16/db-1.0

 └─step  6─┤ install   overlay://test16/app-1.0

 └─step  7─┤ run       overlay://test16/app-1.0

 └─step  8─┤ install   overlay://test16/web-1.0

 └─step  9─┤ run     overlay://test16/web-1.0

Total: 12 actions (4 downloads, 4 installs, 4 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.
```

</details>