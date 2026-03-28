# test17 — Exactly-one-of ^^ (compile)

**Category:** Choice

This test case evaluates the prover's handling of an 'exactly-one-of' dependency group (^^). The 'os-1.0' package requires that exactly one of the three OS packages be installed.

**Expected:** The prover should recognize the choice and select one of the available options (e.g., linux-1.0) to satisfy the dependency. Since there are no other constraints, any of the three choices should lead to a valid proof. The final plan will include app-1.0, os-1.0, and one of the three OS packages.

![test17](test17.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.37 s (backtrack: 1/20).


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

```ansi
[93m>>> Emerging : overlay://test17/web-1.0:run?{[]}
[00m
[32mThese are the packages that would be merged, in order:

[00mCalculating dependencies... done!

 └─[90m[00m[100mstep  1[00m[90m[00m─┤ [00mverify[00m[00m  test17/os[90m (unsatisfied constraints, assumed running)[00m
             │ [00mverify[00m[00m  test17/os[90m (unsatisfied constraints, assumed installed)[00m
             │ [00mverify[00m[00m  test17/db[90m (unsatisfied constraints, assumed running)[00m
             │ [00mverify[00m[00m  test17/app[90m (unsatisfied constraints, assumed running)[00m
             │ [36mdownload[32m  overlay://test17/web-1.0[00m

 └─[90m[00m[100mstep  2[00m[90m[00m─┤ [36minstall[32m   overlay://test17/web-1.0[00m

 └─[90m[00m[100mstep  3[00m[90m[00m─┤ [32m[00m[42mrun[00m[32m[00m[01m[32m     overlay://test17/web-1.0[00m[00m

Total: 3 actions (1 download, 1 install, 1 run), grouped into 3 steps.
       0.00 Kb to be downloaded.



[31m[00m[41mError[00m[31m[00m[31m The proof for your build plan contains domain assumptions. Please verify:

[00m
[93m>>> Domain assumptions[00m

[91m[01m- Unsatisfied constraints for run dependency: [00m
[00m  test17/app

[90m  required by: overlay://test17/web-1.0
[00m
[91m[01m- Unsatisfied constraints for run dependency: [00m
[00m  test17/db

[90m  required by: overlay://test17/web-1.0
[00m
[91m[01m- Unsatisfied constraints for install dependency: [00m
[00m  test17/os

[90m  required by: overlay://test17/web-1.0
[00m
[91m[01m- Unsatisfied constraints for run dependency: [00m
[00m  test17/os

[90m  required by: overlay://test17/web-1.0
[00m

[93m>>> Bug report drafts (Gentoo Bugzilla)[00m

[90m---
[00m[01mSummary: [00moverlay://test17/web-1.0: unsatisfied_constraints dependency on test17/app

[01mAffected package: [00m[90moverlay://test17/web-1.0[00m
[01mDependency: [00m[90mtest17/app[00m
[01mPhases: [00m[90m[run][00m

[01mUnsatisfiable constraint(s):[00m
[90m  test17/app-[00m

[01mObserved:[00m
[90m  portage-ng reports no available candidate satisfies the above constraint(s).
  Available versions in repo set (sample, first 1 of 1): [1.0]
[00m
[01mPotential fix (suggestion):[00m
[90m  Review dependency metadata in overlay://test17/web-1.0; constraint set: [constraint(none,,[])].
[00m
[90m---
[00m[01mSummary: [00moverlay://test17/web-1.0: unsatisfied_constraints dependency on test17/db

[01mAffected package: [00m[90moverlay://test17/web-1.0[00m
[01mDependency: [00m[90mtest17/db[00m
[01mPhases: [00m[90m[run][00m

[01mUnsatisfiable constraint(s):[00m
[90m  test17/db-[00m

[01mObserved:[00m
[90m  portage-ng reports no available candidate satisfies the above constraint(s).
  Available versions in repo set (sample, first 1 of 1): [1.0]
[00m
[01mPotential fix (suggestion):[00m
[90m  Review dependency metadata in overlay://test17/web-1.0; constraint set: [constraint(none,,[])].
[00m
[90m---
[00m[01mSummary: [00moverlay://test17/web-1.0: unsatisfied_constraints dependency on test17/os

[01mAffected package: [00m[90moverlay://test17/web-1.0[00m
[01mDependency: [00m[90mtest17/os[00m
[01mPhases: [00m[90m[install,run][00m

[01mUnsatisfiable constraint(s):[00m
[90m  test17/os-[00m

[01mObserved:[00m
[90m  portage-ng reports no available candidate satisfies the above constraint(s).
  Available versions in repo set (sample, first 1 of 1): [1.0]
[00m
[01mPotential fix (suggestion):[00m
[90m  Review dependency metadata in overlay://test17/web-1.0; constraint set: [constraint(none,,[])].
[00m

[00m
```

</details>