# test45 — Irreconcilable USE conflict via ^^

**Category:** Conflict

This test case checks the prover's ability to detect a direct and irreconcilable USE flag conflict. The 'os' package has a REQUIRED_USE constraint of "^^ ( linux darwin )", meaning exactly one of those USE flags must be enabled. However, the dependency graph requires both to be enabled simultaneously to satisfy liba and libb.

**Expected:** The prover should detect the REQUIRED_USE violation on `os` (both `linux` and `darwin` required, but `^^ ( linux darwin )` allows exactly one) and produce a domain assumption with a detailed REQUIRED_USE violation descriptor. Exit code 2.

![test45](test45.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.49 s (backtrack: 0/20).


The following USE changes are necessary to proceed:
 (see "package.use" in the portage(5) man page for more details)
# required by test45/liba-1.0::overlay
# required by test45/app-1.0::overlay
# required by test45/app (argument)
>=test45/os-1.0 darwin linux

!!! The ebuild selected to satisfy "test45/os[linux]" has unmet requirements.
- test45/os-1.0::overlay USE="-darwin -linux"

  The following REQUIRED_USE flag constraints are unsatisfied:
    exactly-one-of ( linux darwin )

(dependency required by "test45/liba-1.0::overlay" [ebuild])
(dependency required by "test45/app-1.0::overlay" [ebuild])
(dependency required by "test45/app" [argument])
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```

>>> Emerging : overlay://test45/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ useflag overlay://test45/os-1.0 (linux)

 └─step  2─┤ verify  test45/os (unsatisfied constraints, assumed installed)
             │ download  overlay://test45/os-1.0
             │ download  overlay://test45/libb-1.0
             │ download  overlay://test45/liba-1.0
             │ download  overlay://test45/app-1.0

 └─step  3─┤ install   overlay://test45/liba-1.0
             │ install   overlay://test45/libb-1.0
             │ install   overlay://test45/os-1.0 (USE modified)
             │           └─ conf ─┤ USE = "-darwin linux"

 └─step  4─┤ run       overlay://test45/libb-1.0
             │ run       overlay://test45/liba-1.0

 └─step  5─┤ install   overlay://test45/app-1.0

 └─step  6─┤ run     overlay://test45/app-1.0

Total: 12 actions (1 useflag, 4 downloads, 4 installs, 3 runs), grouped into 6 steps.
       0.00 Kb to be downloaded.



>>> Assumptions taken during proving & planning:

  USE flag change (1 package):
  Add to /etc/portage/package.use:
    test45/os linux


Error The proof for your build plan contains domain assumptions. Please verify:


>>> Domain assumptions

- REQUIRED_USE violation: 
  test45/os
  USE deps force:   [darwin,linux]
  violates: ^^ ( linux darwin )
  required by: overlay://test45/libb-1.0


>>> Bug report drafts (Gentoo Bugzilla)

---
Summary: overlay://test45/libb-1.0: unsatisfied_constraints dependency on test45/os

Affected package: overlay://test45/libb-1.0
Dependency: test45/os
Phases: [install]

Unsatisfiable constraint(s):
  test45/os-

Observed:
  portage-ng reports no available candidate satisfies the above constraint(s).
  Available versions in repo set (sample, first 1 of 1): [1.0]

Potential fix (suggestion):
  Review dependency metadata in overlay://test45/libb-1.0; constraint set: [constraint(none,,[])].



```

</details>