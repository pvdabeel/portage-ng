# test25 — At-most-one-of ?? (compile + runtime)

**Category:** Choice

This test case combines test23 and test24. The 'os-1.0' package has the same 'at-most-one-of' choice group in both its compile-time and runtime dependencies.

**Expected:** The prover should resolve both dependencies by choosing to install none of the optional packages, as this is the simplest valid solution. The proof should be valid.

![test25](test25.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  .... done!
Dependency resolution took 1.22 s (backtrack: 1/20).


!!! All ebuilds that could satisfy "test25/os" have been masked.
!!! One of the following masked packages is required to complete your request:
- test25/os-1.0::overlay (masked by: invalid: DEPEND: USE flag '?' referenced in conditional '??' is not in IUSE, invalid: RDEPEND: USE flag '?' referenced in conditional '??' is not in IUSE)

(dependency required by "test25/web-1.0::overlay" [ebuild])
(dependency required by "test25/web" [argument])
For more information, see the MASKED PACKAGES section in the emerge
man page or refer to the Gentoo Handbook.
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```

>>> Emerging : overlay://test25/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test25/web-1.0
             │ download  overlay://test25/os-1.0
             │ download  overlay://test25/linux-1.0
             │ download  overlay://test25/db-1.0
             │ download  overlay://test25/app-1.0

 └─step  2─┤ install   overlay://test25/linux-1.0

 └─step  3─┤ run       overlay://test25/linux-1.0

 └─step  4─┤ install   overlay://test25/os-1.0

 └─step  5─┤ run       overlay://test25/os-1.0

 └─step  6─┤ install   overlay://test25/db-1.0

 └─step  7─┤ run       overlay://test25/db-1.0

 └─step  8─┤ install   overlay://test25/app-1.0

 └─step  9─┤ run       overlay://test25/app-1.0

 └─step 10─┤ install   overlay://test25/web-1.0

 └─step 11─┤ run     overlay://test25/web-1.0

Total: 15 actions (5 downloads, 5 installs, 5 runs), grouped into 11 steps.
       0.00 Kb to be downloaded.


```

</details>