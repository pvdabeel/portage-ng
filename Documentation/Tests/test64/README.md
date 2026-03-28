# test64 — USE-conditional churn reproducer (openmp-style)

**Category:** Cycle

This test case reproduces the small backtracking/churn pattern observed for
llvm-runtimes/openmp in a tiny overlay-only setup. The real openmp metadata
includes IUSE flags, USE-gated dependencies, and REQUIRED_USE groups that can
cause excessive proof retries.

**Expected:** The prover should complete without timing out. A valid plan should be produced that
respects all REQUIRED_USE constraints and USE-conditional dependencies.

![test64](test64.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  
!!! 'test64/app' has a category that is not listed in /etc/portage/categories
... done!
Dependency resolution took 0.47 s (backtrack: 0/20).


emerge: there are no ebuilds to satisfy "test64/app".

emerge: searching for similar names...
emerge: Maybe you meant any of these: test60/app, test56/app, test54/app?
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```ansi
[93m>>> Emerging : overlay://test64/app-1.0:run?{[]}
[00m
[32mThese are the packages that would be merged, in order:

[00mCalculating dependencies... done!

 └─[90m[00m[100mstep  1[00m[90m[00m─┤ [36mdownload[32m  overlay://test64/perl-1.0[00m
             │ [36mdownload[32m  overlay://test64/openmp-1.0[00m
             │ [36mdownload[32m  overlay://test64/ninja-1.0[00m
             │ [36mdownload[32m  overlay://test64/cmake-1.0[00m
             │ [36mdownload[32m  overlay://test64/app-1.0[00m

 └─[90m[00m[100mstep  2[00m[90m[00m─┤ [36minstall[32m   overlay://test64/cmake-1.0[00m
             │ [36minstall[32m   overlay://test64/ninja-1.0[00m
             │ [36minstall[32m   overlay://test64/perl-1.0[00m

 └─[90m[00m[100mstep  3[00m[90m[00m─┤ [36minstall[32m   overlay://test64/openmp-1.0[00m
             │           [90m└─ conf ─┤ [00m[90m[00m[100mUSE[00m[90m[00m = "[90m[03m-gdb-plugin[00m [90m[03m-hwloc[00m [90m[03m-test[00m [90m[03m-verify-sig[00m"
             │          [90m          │ [00m[90m[00m[100mPYTHON_SINGLE_TARGET[00m[90m[00m = "[31m[01mpython3_13[00m [90m[03m-python3_12[00m"

 └─[90m[00m[100mstep  4[00m[90m[00m─┤ [36mrun[32m       overlay://test64/openmp-1.0[00m

 └─[90m[00m[100mstep  5[00m[90m[00m─┤ [36minstall[32m   overlay://test64/app-1.0[00m

 └─[90m[00m[100mstep  6[00m[90m[00m─┤ [32m[00m[42mrun[00m[32m[00m[01m[32m     overlay://test64/app-1.0[00m[00m

Total: 12 actions (5 downloads, 5 installs, 2 runs), grouped into 6 steps.
       0.00 Kb to be downloaded.
```

</details>