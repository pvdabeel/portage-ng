# test68 — Co-installation of same CN in different slots

**Category:** Multi-slot

This test case checks the prover's ability to resolve dependencies on multiple
slots of the same package simultaneously. The 'app-1.0' package requires both
slot 1 and slot 2 of 'lib', which correspond to different versions. Both must
appear in the plan since different slots can coexist.

**Expected:** Both lib-1.0 (slot 1) and lib-2.0 (slot 2) should appear in the proof. The prover
should recognize that different slots are independent installation targets and
include both in the plan.

![test68](test68.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  
!!! 'test68/app' has a category that is not listed in /etc/portage/categories
... done!
Dependency resolution took 0.47 s (backtrack: 0/20).


emerge: there are no ebuilds to satisfy "test68/app".

emerge: searching for similar names...
emerge: Maybe you meant any of these: test60/app, test58/app, test56/app?
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
warning Package not found: test68/app
--- claude-sonnet-4-5 ------------------------------------------------------------------------------------------------------------------------------------------
The package atom `test68/app` appears to be a **non-existent test package** rather than a real Gentoo package.

**Issues:**
1. **Invalid category**: `test68` is not a standard Gentoo category
2. **Test naming pattern**: This looks like a synthetic test case or placeholder

**Likely causes:**
- Test input for portage-ng development/debugging
- Typo or placeholder that should reference an actual package
- Missing overlay configuration if this is from a custom repository

**To resolve:**
- If this is a test: Check if portage-ng test suite requires specific test fixtures/repositories
- If seeking a real package: Provide the actual package name you intended to install
- Check if a custom overlay needs to be added to repos.conf

Without more context about what software you're actually trying to install, this appears to be an intentionally invalid package atom for testing purposes.
----------------------------------------------------------------------------------------------------------------------------------------------------------------

```

</details>