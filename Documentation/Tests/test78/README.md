# test78 — Skip target, install deps only

**Category:** Onlydeps

This test case checks the --onlydeps behavior. When the entry point target
(web-1.0) is proven with the onlydeps_target context flag, the target package
itself should not appear in the install plan, but all of its dependencies should
still be resolved and included.

**Expected:** The dependencies (app-1.0, db-1.0, os-1.0) should appear in the proof and plan.
The target package web-1.0 should be excluded from the install actions, though it
may still appear in the proof for dependency traversal purposes.

![test78](test78.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  
!!! 'test78/web' has a category that is not listed in /etc/portage/categories
... done!
Dependency resolution took 0.47 s (backtrack: 0/20).


emerge: there are no ebuilds to satisfy "test78/web".

emerge: searching for similar names...
emerge: Maybe you meant any of these: test58/web, test57/web, test28/web?
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```ansi
[33m[00m[43mwarning[00m[33m[00m Package not found: test78/web[00m
[37m[03m--- claude-sonnet-4-5 ------------------------------------------------------------------------------------------------------------------------------------------
The package atom `test78/web` appears to be invalid. Here's what's wrong:

**Issue**: `test78` is not a valid Gentoo package category in the standard Portage tree.

**Possible causes**:
1. **Typo in category name** - There is no `test78` category in Gentoo
2. **Local overlay package** - This might be from a custom/local overlay that portage-ng cannot see
3. **Test/dummy package** - The name suggests this might be a test package that doesn't actually exist

**Suggestions**:
- If you're looking for a web-related package, check valid categories like:
  - `www-apps/` (web applications)
  - `www-servers/` (web servers)
  - `www-client/` (web browsers/clients)
- Verify the package exists: `eix web` or check `/usr/portage/test78/`
- If this is from a custom overlay, ensure portage-ng is configured to read that overlay's metadata

The atom format is correct (`category/package`), but the category doesn't exist in standard Gentoo.
----------------------------------------------------------------------------------------------------------------------------------------------------------------
[00m[00m
```

</details>