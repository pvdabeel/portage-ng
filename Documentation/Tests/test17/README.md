# test17 — Exactly-one-of ^^ (compile)

**Category:** Choice

This test case evaluates the prover's handling of an 'exactly-one-of' dependency group (^^). The 'os-1.0' package requires that exactly one of the three OS packages be installed.

**Expected:** The prover should recognize the choice and select one of the available options (e.g., linux-1.0) to satisfy the dependency. Since there are no other constraints, any of the three choices should lead to a valid proof. The final plan will include app-1.0, os-1.0, and one of the three OS packages.

![test17](test17.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.25 s (backtrack: 1/20).


!!! All ebuilds that could satisfy "test17/os" have been masked.
!!! One of the following masked packages is required to complete your request:
- test17/os-1.0::overlay (masked by: invalid: DEPEND: Invalid atom (^^), token 1)

(dependency required by "test17/web-1.0::overlay" [ebuild])
(dependency required by "test17/web" [argument])
For more information, see the MASKED PACKAGES section in the emerge
man page or refer to the Gentoo Handbook.
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test17/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test17/web-1.0
             │ download  overlay://test17/os-1.0
             │ download  overlay://test17/linux-1.0
             │ download  overlay://test17/db-1.0
             │ download  overlay://test17/app-1.0

 └─step  2─┤ install   overlay://test17/os-1.0
             │ install   overlay://test17/linux-1.0

 └─step  3─┤ run       overlay://test17/os-1.0

 └─step  4─┤ install   overlay://test17/db-1.0

 └─step  5─┤ run       overlay://test17/db-1.0

 └─step  6─┤ install   overlay://test17/app-1.0

 └─step  7─┤ run       overlay://test17/app-1.0

 └─step  8─┤ install   overlay://test17/web-1.0

 └─step  9─┤ run     overlay://test17/web-1.0

Total: 14 actions (5 downloads, 5 installs, 4 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.
```

</details>