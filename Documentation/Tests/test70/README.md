# test70 — Operator ~ (revision match)

**Category:** Version

This test case checks the prover's handling of the ~ (revision match) version
operator. The dependency ~lib-2.0 should match lib-2.0 and lib-2.0-r1 (any
revision of the 2.0 base version) but NOT lib-3.0 (different base version).

**Expected:** The prover should select lib-2.0-r1 (the latest matching revision of 2.0). 
lib-3.0 should not be considered a valid candidate for this dependency.

![test70](test70.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  .
!!! 'test70/app' has a category that is not listed in /etc/portage/categories
... done!
Dependency resolution took 0.48 s (backtrack: 0/20).


emerge: there are no ebuilds to satisfy "test70/app".

emerge: searching for similar names...
emerge: Maybe you meant any of these: test60/app, test57/app, test50/app?
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```ansi
[33m[00m[43mwarning[00m[33m[00m Package not found: test70/app[00m
[37m[03m--- claude-sonnet-4-5 ------------------------------------------------------------------------------------------------------------------------------------------
The package atom `test70/app` appears to be invalid because:

1. **`test70` is not a standard Gentoo category** - Valid categories include things like `app-admin`, `dev-lang`, `sys-apps`, etc.

2. **This looks like a test/example package** - The "test70" prefix suggests this is either:
   - A custom overlay package that isn't in the standard Portage tree
   - A fictional example used for testing portage-ng
   - A typo or placeholder

**To resolve this:**

- If testing portage-ng, use a real package like `sys-apps/portage` or `app-portage/gentoolkit`
- Check if you need to add a custom overlay that contains this package
- Verify the correct category/package name if this was meant to be something else

**Most likely:** This is a non-existent test package and you should replace it with an actual package atom from the Gentoo repository.
----------------------------------------------------------------------------------------------------------------------------------------------------------------
[00m[00m
```

</details>