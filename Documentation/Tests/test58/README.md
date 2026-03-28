# test58 — PROVIDE-based virtual (XFAIL)

**Category:** Virtual

> **XFAIL** — expected to fail.

This test case checks PROVIDE-based virtual satisfaction. The 'linux-1.0' package
claims to provide 'virtualsdk', which is not available as a standalone ebuild. The
resolver must recognize that 'linux-1.0' satisfies the virtual dependency through
its PROVIDE declaration. This is a deprecated PMS mechanism but still appears in
the wild.

**Expected:** Currently expected to fail (XFAIL) until PROVIDE/provider resolution is
implemented. Eventually, proving web-1.0 should pull in linux-1.0 to satisfy the
test58/virtualsdk dependency.

![test58](test58.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.69 s (backtrack: 2/20).


emerge: there are no ebuilds to satisfy "test58/virtualsdk".
(dependency required by "test58/os-1.0::overlay" [ebuild])
(dependency required by "test58/web-1.0::overlay" [ebuild])
(dependency required by "test58/web" [argument])
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```ansi
[93m>>> Emerging : overlay://test58/web-1.0:run?{[]}
[00m
[32mThese are the packages that would be merged, in order:

[00mCalculating dependencies... done!

 └─[90m[00m[100mstep  1[00m[90m[00m─┤ [00mverify[00m[00m  test58/os[90m (unsatisfied constraints, assumed running)[00m
             │ [00mverify[00m[00m  test58/os[90m (unsatisfied constraints, assumed installed)[00m
             │ [00mverify[00m[00m  test58/db[90m (unsatisfied constraints, assumed running)[00m
             │ [00mverify[00m[00m  test58/app[90m (unsatisfied constraints, assumed running)[00m
             │ [36mdownload[32m  overlay://test58/web-1.0[00m

 └─[90m[00m[100mstep  2[00m[90m[00m─┤ [36minstall[32m   overlay://test58/web-1.0[00m

 └─[90m[00m[100mstep  3[00m[90m[00m─┤ [32m[00m[42mrun[00m[32m[00m[01m[32m     overlay://test58/web-1.0[00m[00m

Total: 3 actions (1 download, 1 install, 1 run), grouped into 3 steps.
       0.00 Kb to be downloaded.



[31m[00m[41mError[00m[31m[00m[31m The proof for your build plan contains domain assumptions. Please verify:

[00m
[93m>>> Domain assumptions[00m

[91m[01m- Unsatisfied constraints for run dependency: [00m
[00m  test58/app

[90m  required by: overlay://test58/web-1.0
[00m
[91m[01m- Unsatisfied constraints for run dependency: [00m
[00m  test58/db

[90m  required by: overlay://test58/web-1.0
[00m
[91m[01m- Unsatisfied constraints for install dependency: [00m
[00m  test58/os

[90m  required by: overlay://test58/web-1.0
[00m
[91m[01m- Unsatisfied constraints for run dependency: [00m
[00m  test58/os

[90m  required by: overlay://test58/web-1.0
[00m

[93m>>> Bug report drafts (Gentoo Bugzilla)[00m

[90m---
[00m[01mSummary: [00moverlay://test58/web-1.0: unsatisfied_constraints dependency on test58/app

[01mAffected package: [00m[90moverlay://test58/web-1.0[00m
[01mDependency: [00m[90mtest58/app[00m
[01mPhases: [00m[90m[run][00m

[01mUnsatisfiable constraint(s):[00m
[90m  test58/app-[00m

[01mObserved:[00m
[90m  portage-ng reports no available candidate satisfies the above constraint(s).
  Available versions in repo set (sample, first 1 of 1): [1.0]
[00m
[01mPotential fix (suggestion):[00m
[90m  Review dependency metadata in overlay://test58/web-1.0; constraint set: [constraint(none,,[])].
[00m
[90m---
[00m[01mSummary: [00moverlay://test58/web-1.0: unsatisfied_constraints dependency on test58/db

[01mAffected package: [00m[90moverlay://test58/web-1.0[00m
[01mDependency: [00m[90mtest58/db[00m
[01mPhases: [00m[90m[run][00m

[01mUnsatisfiable constraint(s):[00m
[90m  test58/db-[00m

[01mObserved:[00m
[90m  portage-ng reports no available candidate satisfies the above constraint(s).
  Available versions in repo set (sample, first 1 of 1): [1.0]
[00m
[01mPotential fix (suggestion):[00m
[90m  Review dependency metadata in overlay://test58/web-1.0; constraint set: [constraint(none,,[])].
[00m
[90m---
[00m[01mSummary: [00moverlay://test58/web-1.0: unsatisfied_constraints dependency on test58/os

[01mAffected package: [00m[90moverlay://test58/web-1.0[00m
[01mDependency: [00m[90mtest58/os[00m
[01mPhases: [00m[90m[install,run][00m

[01mUnsatisfiable constraint(s):[00m
[90m  test58/os-[00m

[01mObserved:[00m
[90m  portage-ng reports no available candidate satisfies the above constraint(s).
  Available versions in repo set (sample, first 1 of 1): [1.0]
[00m
[01mPotential fix (suggestion):[00m
[90m  Review dependency metadata in overlay://test58/web-1.0; constraint set: [constraint(none,,[])].
[00m

[00m
```

</details>