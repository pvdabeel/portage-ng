# test18 — Exactly-one-of ^^ (runtime)

**Category:** Choice

This test case is a variation of test17, but the 'exactly-one-of' dependency is in the runtime scope (RDEPEND).

**Expected:** The prover should handle the runtime choice group correctly, select one of the OS options, and generate a valid proof.

![test18](test18.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.35 s (backtrack: 1/20).


!!! All ebuilds that could satisfy "test18/os" have been masked.
!!! One of the following masked packages is required to complete your request:
- test18/os-1.0::overlay (masked by: invalid: RDEPEND: Invalid atom (^^), token 1)

(dependency required by "test18/web-1.0::overlay" [ebuild])
(dependency required by "test18/web" [argument])
For more information, see the MASKED PACKAGES section in the emerge
man page or refer to the Gentoo Handbook.
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```ansi
[93m>>> Emerging : overlay://test18/web-1.0:run?{[]}
[00m
[32mThese are the packages that would be merged, in order:

[00mCalculating dependencies... done!

 └─[90m[00m[100mstep  1[00m[90m[00m─┤ [00mverify[00m[00m  test18/os[90m (unsatisfied constraints, assumed running)[00m
             │ [00mverify[00m[00m  test18/os[90m (unsatisfied constraints, assumed installed)[00m
             │ [00mverify[00m[00m  test18/db[90m (unsatisfied constraints, assumed running)[00m
             │ [00mverify[00m[00m  test18/app[90m (unsatisfied constraints, assumed running)[00m
             │ [36mdownload[32m  overlay://test18/web-1.0[00m

 └─[90m[00m[100mstep  2[00m[90m[00m─┤ [36minstall[32m   overlay://test18/web-1.0[00m

 └─[90m[00m[100mstep  3[00m[90m[00m─┤ [32m[00m[42mrun[00m[32m[00m[01m[32m     overlay://test18/web-1.0[00m[00m

Total: 3 actions (1 download, 1 install, 1 run), grouped into 3 steps.
       0.00 Kb to be downloaded.



[31m[00m[41mError[00m[31m[00m[31m The proof for your build plan contains domain assumptions. Please verify:

[00m
[93m>>> Domain assumptions[00m

[91m[01m- Unsatisfied constraints for run dependency: [00m
[00m  test18/app

[90m  required by: overlay://test18/web-1.0
[00m
[91m[01m- Unsatisfied constraints for run dependency: [00m
[00m  test18/db

[90m  required by: overlay://test18/web-1.0
[00m
[91m[01m- Unsatisfied constraints for install dependency: [00m
[00m  test18/os

[90m  required by: overlay://test18/web-1.0
[00m
[91m[01m- Unsatisfied constraints for run dependency: [00m
[00m  test18/os

[90m  required by: overlay://test18/web-1.0
[00m

[93m>>> Bug report drafts (Gentoo Bugzilla)[00m

[90m---
[00m[01mSummary: [00moverlay://test18/web-1.0: unsatisfied_constraints dependency on test18/app

[01mAffected package: [00m[90moverlay://test18/web-1.0[00m
[01mDependency: [00m[90mtest18/app[00m
[01mPhases: [00m[90m[run][00m

[01mUnsatisfiable constraint(s):[00m
[90m  test18/app-[00m

[01mObserved:[00m
[90m  portage-ng reports no available candidate satisfies the above constraint(s).
  Available versions in repo set (sample, first 1 of 1): [1.0]
[00m
[01mPotential fix (suggestion):[00m
[90m  Review dependency metadata in overlay://test18/web-1.0; constraint set: [constraint(none,,[])].
[00m
[90m---
[00m[01mSummary: [00moverlay://test18/web-1.0: unsatisfied_constraints dependency on test18/db

[01mAffected package: [00m[90moverlay://test18/web-1.0[00m
[01mDependency: [00m[90mtest18/db[00m
[01mPhases: [00m[90m[run][00m

[01mUnsatisfiable constraint(s):[00m
[90m  test18/db-[00m

[01mObserved:[00m
[90m  portage-ng reports no available candidate satisfies the above constraint(s).
  Available versions in repo set (sample, first 1 of 1): [1.0]
[00m
[01mPotential fix (suggestion):[00m
[90m  Review dependency metadata in overlay://test18/web-1.0; constraint set: [constraint(none,,[])].
[00m
[90m---
[00m[01mSummary: [00moverlay://test18/web-1.0: unsatisfied_constraints dependency on test18/os

[01mAffected package: [00m[90moverlay://test18/web-1.0[00m
[01mDependency: [00m[90mtest18/os[00m
[01mPhases: [00m[90m[install,run][00m

[01mUnsatisfiable constraint(s):[00m
[90m  test18/os-[00m

[01mObserved:[00m
[90m  portage-ng reports no available candidate satisfies the above constraint(s).
  Available versions in repo set (sample, first 1 of 1): [1.0]
[00m
[01mPotential fix (suggestion):[00m
[90m  Review dependency metadata in overlay://test18/web-1.0; constraint set: [constraint(none,,[])].
[00m

[00m
```

</details>