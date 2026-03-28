# test71 — Download-only action

**Category:** Fetchonly

This test case checks the prover's handling of the fetchonly action. The dependency
structure is identical to test01, but the entry point uses :fetchonly instead of
:run. In fetchonly mode, only download actions should be produced, with no
install/run steps.

**Expected:** All four packages should appear in the proof with download/fetchonly actions. No
install or run steps should be produced in the plan.

![test71](test71.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  
!!! 'test71/web' has a category that is not listed in /etc/portage/categories
... done!
Dependency resolution took 0.47 s (backtrack: 0/20).


emerge: there are no ebuilds to satisfy "test71/web".

emerge: searching for similar names...
emerge: Maybe you meant any of these: test57/web, test31/web, test27/web?
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```ansi
[33m[00m[43mwarning[00m[33m[00m Package not found: test71/web[00m
[37m[03m--- claude-sonnet-4-5 ------------------------------------------------------------------------------------------------------------------------------------------
The package `test71/web` appears to be a **non-existent or test package**. 

The category `test71` is not a standard Gentoo Portage category. This looks like:

1. **A test/dummy package** used for debugging portage-ng itself
2. **A typo** - you may have meant a real package like:
   - `www-client/` or `www-servers/` category packages
   - `net-libs/webkit-gtk` or similar web-related packages

**To fix:**
- If testing portage-ng, ensure test packages are in your local overlay
- If looking for a real package, check standard categories like `www-*`, `net-*`, or `dev-*`
- Verify the package exists: `eix web` or `emerge --search web`

The "test71" category strongly suggests this is an intentional test case rather than a real package request.
----------------------------------------------------------------------------------------------------------------------------------------------------------------
[00m[00m
```

</details>