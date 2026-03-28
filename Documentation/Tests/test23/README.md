# test23 — At-most-one-of ?? (compile)

**Category:** Choice

This test case evaluates the prover's handling of an 'at-most-one-of' dependency group (??). The 'os-1.0' package requires that at most one of the three OS packages be installed. This also means that installing *none* of them is a valid resolution.

**Expected:** The prover should satisfy the dependency by choosing to install nothing from the group, as this is the simplest path. A valid proof should be generated for app-1.0 and os-1.0, without any of the optional OS packages.

![test23](test23.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.21 s (backtrack: 1/20).


!!! All ebuilds that could satisfy "test23/os" have been masked.
!!! One of the following masked packages is required to complete your request:
- test23/os-1.0::overlay (masked by: invalid: DEPEND: USE flag '?' referenced in conditional '??' is not in IUSE)

(dependency required by "test23/web-1.0::overlay" [ebuild])
(dependency required by "test23/web" [argument])
For more information, see the MASKED PACKAGES section in the emerge
man page or refer to the Gentoo Handbook.
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test23/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test23/web-1.0
             │ download  overlay://test23/os-1.0
             │ download  overlay://test23/linux-1.0
             │ download  overlay://test23/db-1.0
             │ download  overlay://test23/app-1.0

 └─step  2─┤ install   overlay://test23/os-1.0
             │ install   overlay://test23/linux-1.0

 └─step  3─┤ run       overlay://test23/os-1.0

 └─step  4─┤ install   overlay://test23/db-1.0

 └─step  5─┤ run       overlay://test23/db-1.0

 └─step  6─┤ install   overlay://test23/app-1.0

 └─step  7─┤ run       overlay://test23/app-1.0

 └─step  8─┤ install   overlay://test23/web-1.0

 └─step  9─┤ run     overlay://test23/web-1.0

Total: 14 actions (5 downloads, 5 installs, 4 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.
```

</details>