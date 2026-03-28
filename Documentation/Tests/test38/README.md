# test38 — Weak conditional [linux?]

**Category:** USE dep

This test case checks the handling of a weak USE dependency. The dependency `os[linux?]` means that 'os-1.0' will have the 'linux' flag enabled *only if* 'app-1.0' also has the 'linux' flag enabled. It does not force the flag to be enabled on 'app-1.0'.

**Expected:** - If 'app-1.0' is proven with USE="linux", the prover should enforce USE="linux" on 'os-1.0'.
- If 'app-1.0' is proven with USE="-linux", the 'linux' flag on 'os-1.0' is not constrained by this dependency and can be either on or off (defaulting to off).
The proof should be valid in both scenarios.

![test38](test38.svg)

<details>
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.82 s (backtrack: 0/20).

[ebuild  N     ] test38/os-1.0::overlay  USE="-darwin -linux" 0 KiB
[ebuild  N     ] test38/app-1.0::overlay  USE="-linux" 0 KiB

Total: 2 packages (2 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test38/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test38/os-1.0
             │ download  overlay://test38/app-1.0

 └─step  2─┤ install   overlay://test38/os-1.0
             │           └─ conf ─┤ USE = "-darwin -linux"

 └─step  3─┤ install   overlay://test38/app-1.0
             │           └─ conf ─┤ USE = "-linux"

 └─step  4─┤ run     overlay://test38/app-1.0

Total: 5 actions (2 downloads, 2 installs, 1 run), grouped into 4 steps.
       0.00 Kb to be downloaded.
```

</details>