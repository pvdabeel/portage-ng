# test75 — Installed same version, emptytree (VDB)

**Category:** Reinstall

This test case checks the prover's behavior when the --emptytree flag is active.
Even though os-1.0 is already installed, the emptytree flag should force the
prover to re-prove it rather than skipping it as satisfied. This exercises the
reinstall path.

**Expected:** With emptytree behavior, os-1.0 should appear in the proof despite being installed.
The plan should include a reinstall or fresh install action for os-1.0.

![test75](test75.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  
!!! 'test75/app' has a category that is not listed in /etc/portage/categories
... done!
Dependency resolution took 0.46 s (backtrack: 0/20).


emerge: there are no ebuilds to satisfy "test75/app".

emerge: searching for similar names...
emerge: Maybe you meant any of these: test59/app, test58/app, test57/app?
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```ansi
[33m[00m[43mwarning[00m[33m[00m Package not found: test75/app[00m
[37m[03m--- claude-sonnet-4-5 ------------------------------------------------------------------------------------------------------------------------------------------
The package atom `test75/app` appears to be **invalid/non-existent**. 

**Issue**: `test75` is not a standard Gentoo package category. Valid Gentoo categories include things like `app-admin`, `dev-python`, `sys-apps`, etc., but not `test75`.

**Possible causes**:
1. **Typo in category name** - You may have meant a real category
2. **Local overlay package** - This might be from a custom overlay that portage-ng cannot see
3. **Test/dummy package** - The name suggests this is a test package that doesn't exist in the main tree

**To fix**:
- Check if you meant a real package (search with `eix` or `emerge --search`)
- If it's from an overlay, ensure portage-ng can access that overlay's metadata
- Verify the package actually exists: `ls /var/db/repos/gentoo/test75/app` or `/usr/portage/test75/app`

Without more context, this looks like either a typo or a reference to a non-existent test package.
----------------------------------------------------------------------------------------------------------------------------------------------------------------
[00m[00m
```

</details>