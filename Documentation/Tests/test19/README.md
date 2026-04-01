# test19 — Exactly-one-of ^^ (compile + runtime)

**Category:** Choice

This test case combines test17 and test18. The 'os-1.0' package has the same 'exactly-one-of' choice group in both its compile-time and runtime dependencies.

**Expected:** The prover should select a single OS package that satisfies both the compile-time and runtime requirements. For example, if it chooses 'linux-1.0' for the compile dependency, it must also use 'linux-1.0' for the runtime dependency. The proof should be valid.

![test19](test19.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.23 s (backtrack: 1/20).


!!! All ebuilds that could satisfy "test19/os" have been masked.
!!! One of the following masked packages is required to complete your request:
- test19/os-1.0::overlay (masked by: invalid: DEPEND: Invalid atom (^^), token 1, invalid: RDEPEND: Invalid atom (^^), token 1)

(dependency required by "test19/web-1.0::overlay" [ebuild])
(dependency required by "test19/web" [argument])
For more information, see the MASKED PACKAGES section in the emerge
man page or refer to the Gentoo Handbook.
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```

>>> Emerging : overlay://test19/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test19/web-1.0
             │ download  overlay://test19/os-1.0
             │ download  overlay://test19/linux-1.0
             │ download  overlay://test19/db-1.0
             │ download  overlay://test19/app-1.0

 └─step  2─┤ install   overlay://test19/linux-1.0

 └─step  3─┤ run       overlay://test19/linux-1.0

 └─step  4─┤ install   overlay://test19/os-1.0

 └─step  5─┤ run       overlay://test19/os-1.0

 └─step  6─┤ install   overlay://test19/db-1.0

 └─step  7─┤ run       overlay://test19/db-1.0

 └─step  8─┤ install   overlay://test19/app-1.0

 └─step  9─┤ run       overlay://test19/app-1.0

 └─step 10─┤ install   overlay://test19/web-1.0

 └─step 11─┤ run     overlay://test19/web-1.0

Total: 15 actions (5 downloads, 5 installs, 5 runs), grouped into 11 steps.
       0.00 Kb to be downloaded.


```

</details>