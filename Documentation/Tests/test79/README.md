# test79 — PDEPEND cycle (A needs B, B PDEPEND A)

**Category:** PDEPEND

This test case checks the handling of cycles involving PDEPEND. The server needs
the client at runtime, and the client has a PDEPEND back on the server. Since
PDEPEND is resolved post-install (via proof obligations), this cycle should be
naturally broken by the ordering: server installs first, then client, then the
PDEPEND obligation for server is already satisfied.

**Expected:** Both packages should appear in the proof without infinite loops. The PDEPEND cycle
should be handled gracefully by the proof obligation mechanism, not treated as a
hard circular dependency requiring assumptions.

![test79](test79.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  
!!! 'test79/server' has a category that is not listed in /etc/portage/categories
... done!
Dependency resolution took 0.46 s (backtrack: 0/20).


emerge: there are no ebuilds to satisfy "test79/server".

emerge: searching for similar names...
emerge: Maybe you meant any of these: test47/app-server, test59/os, test57/os?
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
warning Package not found: test79/server
--- claude-sonnet-4-5 ------------------------------------------------------------------------------------------------------------------------------------------
The package atom **`test79/server`** is not a valid Gentoo package. 

**`test79`** is not a recognized category in the Gentoo Portage tree. This appears to be either:

1. **A typo or test input** - The "test79" prefix suggests this might be placeholder/test data
2. **A custom overlay package** that doesn't exist in the standard Portage tree
3. **Completely fictional** package name

**If you're looking for a server package**, you might want:
- `www-servers/*` (web servers like nginx, apache)
- `net-misc/*` (network services)
- `mail-mta/*` (mail servers)

**To fix**: Specify a valid package atom from the official Gentoo repository or ensure your custom overlay is properly configured if this is supposed to be a local package.
----------------------------------------------------------------------------------------------------------------------------------------------------------------

```

</details>