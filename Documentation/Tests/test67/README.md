# test67 — Build-only dependency (separate from DEPEND)

**Category:** BDEPEND

This test case checks the prover's handling of BDEPEND (build dependencies). The
'app-1.0' package requires 'toolchain-1.0' only for building (BDEPEND), separate
from its runtime dependency on 'lib-1.0'. BDEPEND is resolved alongside DEPEND
for the install phase.

**Expected:** All three packages should appear in the proof. The toolchain-1.0 should be
resolved as a build dependency of app-1.0, while lib-1.0 is resolved as a runtime
dependency.

![test67](test67.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  
!!! 'test67/app' has a category that is not listed in /etc/portage/categories
... done!
Dependency resolution took 0.45 s (backtrack: 0/20).


emerge: there are no ebuilds to satisfy "test67/app".

emerge: searching for similar names...
emerge: Maybe you meant any of these: test60/app, test57/app, test56/app?
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
warning Package not found: test67/app
--- claude-sonnet-4-5 ------------------------------------------------------------------------------------------------------------------------------------------
The package atom **`test67/app`** is invalid because:

1. **`test67` is not a valid Gentoo category** - Gentoo uses predefined categories like `app-misc`, `dev-libs`, `sys-apps`, etc. Custom categories like `test67` don't exist in the standard Portage tree.

2. **This looks like a test/dummy package name** - The "test67" prefix suggests this is either:
   - A placeholder used in testing
   - A package from a custom/local overlay that isn't in the main tree
   - A typo or incorrect package reference

**To fix this:**
- If you're testing portage-ng, verify you're using a valid package atom from the actual Portage tree (e.g., `app-editors/vim`)
- If this is from an overlay, ensure the overlay is properly configured
- Check if you meant a different package entirely

**Valid package atom format:** `category/package-name` where category must be one of Gentoo's official categories.
----------------------------------------------------------------------------------------------------------------------------------------------------------------

```

</details>