# test74 — Installed newer, constraint forces older (VDB)

**Category:** Downgrade

This test case checks the prover's downgrade path. When lib-2.0 is installed but
app-1.0 requires exactly lib-1.0 (via the = operator), the prover should detect
that a downgrade is needed. The same-slot installed version is newer than the
required version.

**Expected:** The prover should select lib-1.0 as a downgrade replacing the installed lib-2.0.
The plan should show a downgrade action for lib.

![test74](test74.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  
!!! 'test74/app' has a category that is not listed in /etc/portage/categories
... done!
Dependency resolution took 0.48 s (backtrack: 0/20).


emerge: there are no ebuilds to satisfy "test74/app".

emerge: searching for similar names...
emerge: Maybe you meant any of these: test57/app, test54/app, test49/app?
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
warning Package not found: test74/app
--- claude-sonnet-4-5 ------------------------------------------------------------------------------------------------------------------------------------------
The package `test74/app` appears to be a **non-existent test package**. 

This looks like:
1. A **test case** for portage-ng itself (the "test74" suggests automated testing)
2. A **typo or placeholder** that was never meant to be resolved
3. A **custom/local package** that doesn't exist in the standard Portage tree

**What's wrong:** No package with category `test74` exists in Gentoo's official Portage tree. Categories like `test74` are not standard Gentoo categories.

**To verify:** Run `eix -C test74` or check if this is part of portage-ng's test suite rather than an actual package request.

If you're testing portage-ng functionality, this failure is expected for non-existent packages.
----------------------------------------------------------------------------------------------------------------------------------------------------------------

```

</details>