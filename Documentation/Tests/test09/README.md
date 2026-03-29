# test09 — Non-existent dep (compile)

**Category:** Missing

This test case checks the prover's ability to handle a missing dependency. The 'os-1.0' package depends on 'test09/notexists', which is not a real package available in the repository.

**Expected:** The prover should fail to find a candidate for the 'notexists' package and report that the dependency cannot be satisfied. This should result in a failed proof.

![test09](test09.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.21 s (backtrack: 1/20).


emerge: there are no ebuilds to satisfy "test09/notexists".
(dependency required by "test09/os-1.0::overlay" [ebuild])
(dependency required by "test09/os" [argument])
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```

>>> Emerging : overlay://test09/os-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ verify  test09/notexists (non-existent, assumed installed)
             │ download  overlay://test09/os-1.0

 └─step  2─┤ install   overlay://test09/os-1.0

 └─step  3─┤ run     overlay://test09/os-1.0

Total: 3 actions (1 download, 1 install, 1 run), grouped into 3 steps.
       0.00 Kb to be downloaded.



Error The proof for your build plan contains domain assumptions. Please verify:


>>> Domain assumptions

- Missing install dependency: 
  test09/notexists

  required by: overlay://test09/os-1.0


>>> Bug report drafts (Gentoo Bugzilla)

---
Summary: overlay://test09/os-1.0: missing dependency on test09/notexists

Affected package: overlay://test09/os-1.0
Dependency: test09/notexists
Phases: [install]

Unsatisfiable constraint(s):
  test09/notexists-

Observed:
  portage-ng reports no available candidate satisfies the above constraint(s).

Potential fix (suggestion):
  Review dependency metadata in overlay://test09/os-1.0; constraint set: [constraint(none,,[])].
```

</details>