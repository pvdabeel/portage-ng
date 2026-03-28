# test72 — Install-time dependency

**Category:** IDEPEND

This test case checks the prover's handling of IDEPEND (install-time dependencies).
IDEPEND is an EAPI 8 feature that specifies packages needed at install time on the
target system (as opposed to BDEPEND which is for the build system). The 'app-1.0'
package requires 'installer-1.0' at install time.

**Expected:** Both packages should appear in the proof. The installer-1.0 should be resolved as
an install-time dependency and be available before app-1.0's install phase.

![test72](test72.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  
!!! 'test72/app' has a category that is not listed in /etc/portage/categories
... done!
Dependency resolution took 0.48 s (backtrack: 0/20).


emerge: there are no ebuilds to satisfy "test72/app".

emerge: searching for similar names...
emerge: Maybe you meant any of these: test57/app, test52/app, test42/app?
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
warning Package not found: test72/app
--- claude-sonnet-4-5 ------------------------------------------------------------------------------------------------------------------------------------------
The package `test72/app` appears to be a **non-existent test package** that doesn't exist in the Gentoo Portage tree.

This looks like:
1. A **test/dummy package name** used for debugging or testing portage-ng itself
2. The category `test72` is not a valid Gentoo category
3. No legitimate Gentoo package would be named this way

**What's likely wrong:**
- You're testing portage-ng with a fictional package
- There's a typo or placeholder that wasn't replaced with a real package atom
- This is from a test suite or example configuration

**To fix:** Replace with an actual Gentoo package atom like `app-editors/vim` or `sys-apps/portage`.

If you intended to test with a real package, please provide the actual package name you're looking for.
----------------------------------------------------------------------------------------------------------------------------------------------------------------

```

</details>