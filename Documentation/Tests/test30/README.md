# test30 — Weak blocker ! (compile) + any-of

**Category:** Blocker

This test case is a variation of test27 where the weak blocker (!) is in the
compile-time scope (DEPEND) rather than the runtime scope (RDEPEND). The 'app-1.0'
package weakly blocks 'windows-1.0' at compile time, while 'os-1.0' has an any-of
compile dependency that includes 'windows-1.0'.

**Expected:** The prover should produce a valid plan. The weak blocker is recorded as a domain
assumption. The any-of group resolution may or may not select 'windows-1.0',
depending on blocker handling strategy.

![test30](test30.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 1.09 s (backtrack: 0/20).

[ebuild  N     ] test30/linux-1.0::overlay  0 KiB
[ebuild  N     ] test30/os-1.0::overlay  0 KiB
[ebuild  N     ] test30/db-1.0::overlay  0 KiB
[ebuild  N     ] test30/app-1.0::overlay  0 KiB
[ebuild  N     ] test30/web-1.0::overlay  0 KiB

Total: 5 packages (5 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```ansi
[93m>>> Emerging : overlay://test30/web-1.0:run?{[]}
[00m
[32mThese are the packages that would be merged, in order:

[00mCalculating dependencies... done!

 └─[90m[00m[100mstep  1[00m[90m[00m─┤ [36mdownload[32m  overlay://test30/web-1.0[00m
             │ [36mdownload[32m  overlay://test30/os-1.0[00m
             │ [36mdownload[32m  overlay://test30/linux-1.0[00m
             │ [36mdownload[32m  overlay://test30/db-1.0[00m
             │ [36mdownload[32m  overlay://test30/app-1.0[00m

 └─[90m[00m[100mstep  2[00m[90m[00m─┤ [36minstall[32m   overlay://test30/os-1.0[00m
             │ [36minstall[32m   overlay://test30/linux-1.0[00m

 └─[90m[00m[100mstep  3[00m[90m[00m─┤ [36mrun[32m       overlay://test30/os-1.0[00m

 └─[90m[00m[100mstep  4[00m[90m[00m─┤ [36minstall[32m   overlay://test30/db-1.0[00m

 └─[90m[00m[100mstep  5[00m[90m[00m─┤ [36mrun[32m       overlay://test30/db-1.0[00m

 └─[90m[00m[100mstep  6[00m[90m[00m─┤ [36minstall[32m   overlay://test30/app-1.0[00m

 └─[90m[00m[100mstep  7[00m[90m[00m─┤ [36mrun[32m       overlay://test30/app-1.0[00m

 └─[90m[00m[100mstep  8[00m[90m[00m─┤ [36minstall[32m   overlay://test30/web-1.0[00m

 └─[90m[00m[100mstep  9[00m[90m[00m─┤ [32m[00m[42mrun[00m[32m[00m[01m[32m     overlay://test30/web-1.0[00m[00m

Total: 14 actions (5 downloads, 5 installs, 4 runs), grouped into 9 steps.
       0.00 Kb to be downloaded.



[93m>>> Blockers added during proving & planning:[00m

[90m  [blocks B] !test30/windows (soft blocker, phase: install, required by: overlay://test30/app-1.0)
[00m

[00m
```

</details>