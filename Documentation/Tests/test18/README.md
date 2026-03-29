# test18 — Exactly-one-of ^^ (runtime)

**Category:** Choice

This test case is a variation of test17, but the 'exactly-one-of' dependency is in the runtime scope (RDEPEND).

**Expected:** The prover should handle the runtime choice group correctly, select one of the OS options, and generate a valid proof.

![test18](test18.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  .... done!
Dependency resolution took 1.22 s (backtrack: 1/20).


!!! All ebuilds that could satisfy "test18/os" have been masked.
!!! One of the following masked packages is required to complete your request:
- test18/os-1.0::overlay (masked by: invalid: RDEPEND: Invalid atom (^^), token 1)

(dependency required by "test18/web-1.0::overlay" [ebuild])
(dependency required by "test18/web" [argument])
For more information, see the MASKED PACKAGES section in the emerge
man page or refer to the Gentoo Handbook.
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```

>>> Emerging : overlay://test18/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test18/web-1.0
             │ download  overlay://test18/os-1.0
             │ download  overlay://test18/linux-1.0
             │ download  overlay://test18/db-1.0
             │ download  overlay://test18/app-1.0

 └─step  2─┤ install   overlay://test18/os-1.0
             │ install   overlay://test18/linux-1.0

 └─step  3─┤ run       overlay://test18/linux-1.0

 └─step  4─┤ run       overlay://test18/os-1.0

 └─step  5─┤ install   overlay://test18/db-1.0

 └─step  6─┤ run       overlay://test18/db-1.0

 └─step  7─┤ install   overlay://test18/app-1.0

 └─step  8─┤ run       overlay://test18/app-1.0

 └─step  9─┤ install   overlay://test18/web-1.0

 └─step 10─┤ run     overlay://test18/web-1.0

Total: 15 actions (5 downloads, 5 installs, 5 runs), grouped into 10 steps.
       0.00 Kb to be downloaded.
```

</details>