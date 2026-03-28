# test09 — Non-existent dep (compile)

**Category:** Missing

This test case checks the prover's ability to handle a missing dependency. The 'os-1.0' package depends on 'test09/notexists', which is not a real package available in the repository.

**Expected:** The prover should fail to find a candidate for the 'notexists' package and report that the dependency cannot be satisfied. This should result in a failed proof.

![test09](test09.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.22 s (backtrack: 1/20).


emerge: there are no ebuilds to satisfy "test09/notexists".
(dependency required by "test09/os-1.0::overlay" [ebuild])
(dependency required by "test09/os" [argument])
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```ansi
[93m>>> Emerging : overlay://test09/os-1.0:run?{[]}
[00m
[32mThese are the packages that would be merged, in order:

[00mCalculating dependencies... done!

 └─[90m[00m[100mstep  1[00m[90m[00m─┤ [31m[00m[41mverify[00m[31m[00m[31m  test09/notexists (non-existent, assumed installed)[00m
             │ [36mdownload[32m  overlay://test09/os-1.0[00m

 └─[90m[00m[100mstep  2[00m[90m[00m─┤ [36minstall[32m   overlay://test09/os-1.0[00m

 └─[90m[00m[100mstep  3[00m[90m[00m─┤ [32m[00m[42mrun[00m[32m[00m[01m[32m     overlay://test09/os-1.0[00m[00m

Total: 3 actions (1 download, 1 install, 1 run), grouped into 3 steps.
       0.00 Kb to be downloaded.



[31m[00m[41mError[00m[31m[00m[31m The proof for your build plan contains domain assumptions. Please verify:

[00m
[93m>>> Domain assumptions[00m

[91m[01m- Missing install dependency: [00m
[00m  test09/notexists

[90m  required by: overlay://test09/os-1.0
[00m

[93m>>> Bug report drafts (Gentoo Bugzilla)[00m

[90m---
[00m[01mSummary: [00moverlay://test09/os-1.0: missing dependency on test09/notexists

[01mAffected package: [00m[90moverlay://test09/os-1.0[00m
[01mDependency: [00m[90mtest09/notexists[00m
[01mPhases: [00m[90m[install][00m

[01mUnsatisfiable constraint(s):[00m
[90m  test09/notexists-[00m

[01mObserved:[00m
[90m  portage-ng reports no available candidate satisfies the above constraint(s).
[00m
[01mPotential fix (suggestion):[00m
[90m  Review dependency metadata in overlay://test09/os-1.0; constraint set: [constraint(none,,[])].
[00m

[00m
```

</details>