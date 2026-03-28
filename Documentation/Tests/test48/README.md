# test48 — Slot conflict (same slot, different versions)

**Category:** Conflict

This test case checks the prover's ability to detect a slotting conflict. The two main dependencies, 'libgraphics' and 'libphysics', require different versions of 'libmatrix' to be installed into the same slot ('1'). A package slot can only be occupied by one version at a time.

**Expected:** The prover should identify that the dependencies for 'app-1.0' lead to a request to install two different packages ('libmatrix-1.0' and 'libmatrix-1.1') into the same slot. This is an impossible condition, so the prover must fail to find a valid proof.

![test48](test48.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  .... done!
Dependency resolution took 4.52 s (backtrack: 6/20).

[ebuild  N     ] test48/libmatrix-1.1:1/B::overlay  0 KiB
[ebuild  N     ] test48/libmatrix-1.0:1/A::overlay  0 KiB
[ebuild  N     ] test48/libgraphics-1.0::overlay  0 KiB
[ebuild  N     ] test48/libphysics-1.0::overlay  0 KiB
[ebuild  N     ] test48/app-1.0::overlay  0 KiB

Total: 5 packages (5 new), Size of downloads: 0 KiB

!!! Multiple package instances within a single package slot have been pulled
!!! into the dependency graph, resulting in a slot conflict:

test48/libmatrix:1

  (test48/libmatrix-1.1:1/B::overlay, ebuild scheduled for merge) USE="" pulled in by
    =test48/libmatrix-1.1:1/B required by (test48/libphysics-1.0:0/0::overlay, ebuild scheduled for merge) USE=""
    ^                 ^^^^^^^                                                                                     

  (test48/libmatrix-1.0:1/A::overlay, ebuild scheduled for merge) USE="" pulled in by
    =test48/libmatrix-1.0:1/A required by (test48/libgraphics-1.0:0/0::overlay, ebuild scheduled for merge) USE=""
    ^                 ^^^^^^^                                                                                      


It may be possible to solve this problem by using package.mask to
prevent one of those packages from being selected. However, it is also
possible that conflicting dependencies exist such that they are
impossible to satisfy simultaneously.  If such a conflict exists in
the dependencies of two different packages, then those packages can
not be installed simultaneously. You may want to try a larger value of
the --backtrack option, such as --backtrack=30, in order to see if
that will solve this conflict automatically.

For more information, see MASKED PACKAGES section in the emerge man
page or refer to the Gentoo Handbook.
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test48/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ verify  test48/libphysics (unsatisfied constraints, assumed running)
             │ download  overlay://test48/libmatrix-1.0
             │ download  overlay://test48/libgraphics-1.0
             │ download  overlay://test48/app-1.0

 └─step  2─┤ install   overlay://test48/libmatrix-1.0
             │           └─ conf ─┤ SLOT = "1/A"

 └─step  3─┤ run       overlay://test48/libmatrix-1.0

 └─step  4─┤ install   overlay://test48/libgraphics-1.0

 └─step  5─┤ run       overlay://test48/libgraphics-1.0

 └─step  6─┤ install   overlay://test48/app-1.0

 └─step  7─┤ run     overlay://test48/app-1.0

Total: 9 actions (3 downloads, 3 installs, 3 runs), grouped into 7 steps.
       0.00 Kb to be downloaded.



Error The proof for your build plan contains domain assumptions. Please verify:


>>> Domain assumptions

- Unsatisfied constraints for run dependency: 
  test48/libphysics

  required by: overlay://test48/app-1.0


>>> Bug report drafts (Gentoo Bugzilla)

---
Summary: overlay://test48/app-1.0: unsatisfied_constraints dependency on test48/libphysics

Affected package: overlay://test48/app-1.0
Dependency: test48/libphysics
Phases: [run]

Unsatisfiable constraint(s):
  test48/libphysics-

Observed:
  portage-ng reports no available candidate satisfies the above constraint(s).
  Available versions in repo set (sample, first 1 of 1): [1.0]

Potential fix (suggestion):
  Review dependency metadata in overlay://test48/app-1.0; constraint set: [constraint(none,,[])].
```

</details>