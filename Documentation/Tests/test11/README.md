# test11 — Non-existent dep (compile + runtime)

**Category:** Missing

This test case combines test09 and test10. The 'os-1.0' package has both a compile-time and a runtime dependency on the non-existent 'test11/notexists' package.

**Expected:** The prover should fail because it cannot find the 'notexists' package. It should correctly identify the missing dependency in both scopes.

![test11](test11.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.21 s (backtrack: 1/20).


emerge: there are no ebuilds to satisfy "test11/notexists".
(dependency required by "test11/os-1.0::overlay" [ebuild])
(dependency required by "test11/os" [argument])
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test11/os-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ verify  test11/notexists (non-existent, assumed running)
             │ verify  test11/notexists (non-existent, assumed installed)
             │ download  overlay://test11/os-1.0

 └─step  2─┤ install   overlay://test11/os-1.0

 └─step  3─┤ run     overlay://test11/os-1.0

Total: 3 actions (1 download, 1 install, 1 run), grouped into 3 steps.
       0.00 Kb to be downloaded.



Error The proof for your build plan contains domain assumptions. Please verify:


>>> Domain assumptions

- Missing install dependency: 
  test11/notexists

  required by: overlay://test11/os-1.0

- Missing run dependency: 
  test11/notexists

  required by: overlay://test11/os-1.0


>>> Bug report drafts (Gentoo Bugzilla)

---
Summary: overlay://test11/os-1.0: missing dependency on test11/notexists

Affected package: overlay://test11/os-1.0
Dependency: test11/notexists
Phases: [install,run]

Unsatisfiable constraint(s):
  test11/notexists-

Observed:
  portage-ng reports no available candidate satisfies the above constraint(s).

Potential fix (suggestion):
  Review dependency metadata in overlay://test11/os-1.0; constraint set: [constraint(none,,[])].



```

</details>