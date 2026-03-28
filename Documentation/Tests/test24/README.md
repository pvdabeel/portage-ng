# test24 — At-most-one-of ?? (runtime)

**Category:** Choice

This is a variation of test23, with the 'at-most-one-of' dependency group in the runtime scope (RDEPEND).

**Expected:** The prover should satisfy the runtime dependency by choosing to install none of the optional OS packages. The proof should be valid.

![test24](test24.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.21 s (backtrack: 1/20).


!!! All ebuilds that could satisfy "test24/os" have been masked.
!!! One of the following masked packages is required to complete your request:
- test24/os-1.0::overlay (masked by: invalid: RDEPEND: USE flag '?' referenced in conditional '??' is not in IUSE)

(dependency required by "test24/web-1.0::overlay" [ebuild])
(dependency required by "test24/web" [argument])
For more information, see the MASKED PACKAGES section in the emerge
man page or refer to the Gentoo Handbook.
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test24/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test24/web-1.0
             │ download  overlay://test24/os-1.0
             │ download  overlay://test24/linux-1.0
             │ download  overlay://test24/db-1.0
             │ download  overlay://test24/app-1.0

 └─step  2─┤ install   overlay://test24/os-1.0
             │ install   overlay://test24/linux-1.0

 └─step  3─┤ run       overlay://test24/linux-1.0

 └─step  4─┤ run       overlay://test24/os-1.0

 └─step  5─┤ install   overlay://test24/db-1.0

 └─step  6─┤ run       overlay://test24/db-1.0

 └─step  7─┤ install   overlay://test24/app-1.0

 └─step  8─┤ run       overlay://test24/app-1.0

 └─step  9─┤ install   overlay://test24/web-1.0

 └─step 10─┤ run     overlay://test24/web-1.0

Total: 15 actions (5 downloads, 5 installs, 5 runs), grouped into 10 steps.
       0.00 Kb to be downloaded.
```

</details>