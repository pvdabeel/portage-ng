# test35 — Equality [linux=]

**Category:** USE dep

This test case checks the handling of conditional USE propagation. The dependency `os[linux=]` means that if 'app-1.0' is built with USE="linux", then 'os-1.0' must also be built with USE="linux". If 'app-1.0' is built with USE="-linux", then 'os-1.0' must be built with USE="-linux".

**Expected:** - If 'app-1.0' is proven with USE="linux", the prover should enforce USE="linux" on 'os-1.0'.
- If 'app-1.0' is proven with USE="-linux" (or it's disabled by default), the prover should enforce USE="-linux" on 'os-1.0'.
In both cases, the proof should be valid.

![test35](test35.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.81 s (backtrack: 0/20).

[ebuild  N     ] test35/os-1.0::overlay  USE="-darwin -linux" 0 KiB
[ebuild  N     ] test35/app-1.0::overlay  USE="-linux" 0 KiB

Total: 2 packages (2 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```ansi
[93m>>> Emerging : overlay://test35/app-1.0:run?{[]}
[00m
[32mThese are the packages that would be merged, in order:

[00mCalculating dependencies... done!

 └─[90m[00m[100mstep  1[00m[90m[00m─┤ [36mdownload[32m  overlay://test35/os-1.0[00m
             │ [36mdownload[32m  overlay://test35/app-1.0[00m

 └─[90m[00m[100mstep  2[00m[90m[00m─┤ [36minstall[32m   overlay://test35/os-1.0[00m
             │           [90m└─ conf ─┤ [00m[90m[00m[100mUSE[00m[90m[00m = "[90m[03m-darwin[00m [90m[03m-linux[00m"

 └─[90m[00m[100mstep  3[00m[90m[00m─┤ [36minstall[32m   overlay://test35/app-1.0[00m
             │           [90m└─ conf ─┤ [00m[90m[00m[100mUSE[00m[90m[00m = "[90m[03m-linux[00m"

 └─[90m[00m[100mstep  4[00m[90m[00m─┤ [32m[00m[42mrun[00m[32m[00m[01m[32m     overlay://test35/app-1.0[00m[00m

Total: 5 actions (2 downloads, 2 installs, 1 run), grouped into 4 steps.
       0.00 Kb to be downloaded.
```

</details>