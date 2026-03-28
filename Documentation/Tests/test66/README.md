# test66 — Post-merge dependency resolution

**Category:** PDEPEND

This test case checks the prover's handling of PDEPEND (post-merge dependencies).
The 'lib-1.0' package declares 'plugin-1.0' as a PDEPEND, meaning plugin-1.0
should be resolved after lib-1.0's installation, not as a prerequisite.

**Expected:** All three packages should appear in the proof/plan. The plugin-1.0 package should
be ordered after lib-1.0's install step via the PDEPEND proof obligation mechanism.

![test66](test66.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  
!!! 'test66/app' has a category that is not listed in /etc/portage/categories
... done!
Dependency resolution took 0.46 s (backtrack: 0/20).


emerge: there are no ebuilds to satisfy "test66/app".

emerge: searching for similar names...
emerge: Maybe you meant any of these: test60/app, test56/app, test46/app?
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
warning Package not found: test66/app
--- claude-sonnet-4-5 ------------------------------------------------------------------------------------------------------------------------------------------
The package atom **`test66/app`** is not a valid Gentoo package. 

**What's wrong:**
- `test66` is not a recognized category in the Gentoo Portage tree
- This appears to be a test/dummy package name that doesn't exist

**Possible issues:**
1. **Typo in category name** - Check if you meant a real category like `app-*`, `dev-*`, `sys-*`, etc.
2. **Missing overlay** - This might be a package from a custom/third-party overlay that isn't configured
3. **Test data** - The name suggests this is test input rather than a real package request

**To fix:**
- Verify the correct package atom (format: `category/package-name`)
- If from an overlay, ensure it's added via `eselect repository` or layman
- Check `eix test66/app` or search on packages.gentoo.org for the actual package name
----------------------------------------------------------------------------------------------------------------------------------------------------------------

```

</details>