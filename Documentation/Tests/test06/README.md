# test06 — Indirect cycle (compile)

**Category:** Cycle

This test case checks the prover's handling of an indirect circular dependency in
the compile-time scope. The 'os-1.0' package lists 'web-1.0' as a compile-time
dependency, while 'web-1.0' in turn depends on 'os-1.0', creating a two-node
cycle. Because the proof path passes through RDEPEND entries, the cycle is
classified as RDEPEND-mediated and therefore benign (matching Portage's MEDIUM
priority / Paludis's "freely orderable" semantics for runtime cycles).

**Expected:** The prover should detect the cycle but classify it as benign, producing a clean plan
with all four packages and no cycle-break assumptions or verify steps. Emerge
reports the cycle as a warning but still produces a valid merge list.

![test06](test06.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.19 s (backtrack: 1/20).



[ebuild  N     ] test06/web-1.0::overlay  0 KiB
[ebuild  N     ]  test06/app-1.0::overlay  0 KiB
[ebuild  N     ]   test06/db-1.0::overlay  0 KiB
[ebuild  N     ]    test06/os-1.0::overlay  0 KiB

Total: 4 packages (4 new), Size of downloads: 0 KiB

 * Error: circular dependencies:

(test06/os-1.0:0/0::overlay, ebuild scheduled for merge) depends on
 (test06/web-1.0:0/0::overlay, ebuild scheduled for merge) (buildtime)
  (test06/os-1.0:0/0::overlay, ebuild scheduled for merge) (buildtime)

 * Note that circular dependencies can often be avoided by temporarily
 * disabling USE flags that trigger optional dependencies.
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```

>>> Emerging : overlay://test06/web-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test06/web-1.0
             │ download  overlay://test06/os-1.0
             │ download  overlay://test06/db-1.0
             │ download  overlay://test06/app-1.0

 └─step  2─┤ install   overlay://test06/os-1.0

 └─step  3─┤ run       overlay://test06/os-1.0

 └─step  4─┤ install   overlay://test06/db-1.0

 └─step  5─┤ run       overlay://test06/db-1.0

 └─step  6─┤ install   overlay://test06/app-1.0

 └─step  7─┤ run       overlay://test06/app-1.0

 └─step  8─┤ install   overlay://test06/web-1.0

 └─step  9─┤ run     overlay://test06/web-1.0

Total: 12 actions (4 downloads, 4 installs, 4 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.


```

</details>