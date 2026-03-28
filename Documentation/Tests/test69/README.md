# test69 — Operator >= (greater-or-equal)

**Category:** Version

This test case checks the prover's handling of the >= (greater-or-equal) version
operator. The 'app-1.0' package requires lib version 3.0 or higher. Versions 1.0
and 2.0 should be excluded; versions 3.0, 4.0, and 5.0 are valid candidates.

**Expected:** The prover should select the latest valid version, lib-5.0, to satisfy the
dependency. Versions 1.0 and 2.0 should not appear in the proof.

![test69](test69.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  
!!! 'test69/app' has a category that is not listed in /etc/portage/categories
... done!
Dependency resolution took 0.49 s (backtrack: 0/20).


emerge: there are no ebuilds to satisfy "test69/app".

emerge: searching for similar names...
emerge: Maybe you meant any of these: test60/app, test59/app, test56/app?
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```ansi
[33m[00m[43mwarning[00m[33m[00m Package not found: test69/app[00m
[37m[03m--- claude-sonnet-4-5 ------------------------------------------------------------------------------------------------------------------------------------------
The package atom `test69/app` is **not a valid Gentoo package**. 

This appears to be:
1. A **test/dummy package name** (the "test69" category doesn't exist in Gentoo)
2. Possibly used for testing portage-ng's error handling
3. Or a typo/placeholder that needs to be replaced with an actual package atom

**What's wrong:** The category `test69` doesn't exist in the Gentoo Portage tree. Valid categories include things like `app-editors`, `sys-apps`, `dev-lang`, etc.

**To fix:** Replace with an actual package atom like:
- `app-editors/vim`
- `sys-apps/portage`
- Or whatever package you actually need

If you're testing portage-ng itself, this failure is expected behavior for a non-existent package.
----------------------------------------------------------------------------------------------------------------------------------------------------------------
[00m[00m
```

</details>