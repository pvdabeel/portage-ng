# test63 — REQUIRED_USE loop reproducer (openmpi-style)

**Category:** Cycle

This test case reproduces the prover timeout trace seen in portage for packages
that pull sys-cluster/openmpi, where proving hits a sequence of
use_conditional_group/4 items for mutually exclusive flags. It is a tiny
overlay-only reproducer intended to isolate backtracking/timeout behaviour without
involving the full portage tree.

**Expected:** The prover should complete without timing out. The plan should include app-1.0 and
openmpi-4.1.6-r1 with a valid REQUIRED_USE configuration.

![test63](test63.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  
!!! 'test63/app' has a category that is not listed in /etc/portage/categories
... done!
Dependency resolution took 0.45 s (backtrack: 0/20).


emerge: there are no ebuilds to satisfy "test63/app".

emerge: searching for similar names...
emerge: Maybe you meant any of these: test60/app, test56/app, test53/app?
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```ansi
[93m>>> Emerging : overlay://test63/app-1.0:run?{[]}
[00m
[32mThese are the packages that would be merged, in order:

[00mCalculating dependencies... done!

 └─[90m[00m[100mstep  1[00m[90m[00m─┤ [33m[00m[43museflag[00m[33m[00m[32m overlay://test63/openmpi-4.1.6-r1[90m (-openmpi_rm_pbs -openmpi_rm_slurm)[00m

 └─[90m[00m[100mstep  2[00m[90m[00m─┤ [36mdownload[32m  overlay://test63/openmpi-4.1.6-r1[00m
             │ [36mdownload[32m  overlay://test63/mpibash-1.3-r1[00m
             │ [36mdownload[32m  overlay://test63/app-1.0[00m

 └─[90m[00m[100mstep  3[00m[90m[00m─┤ [36minstall[32m   overlay://test63/openmpi-4.1.6-r1[90m (USE modified)[00m
             │           [90m└─ conf ─┤ [00m[90m[00m[100mUSE[00m[90m[00m = ""
             │          [90m          │ [00m[90m[00m[100mOPENMPI_FABRICS[00m[90m[00m = "[90m[03m-ofed[00m"
             │          [90m          │ [00m[90m[00m[100mOPENMPI_OFED_FEATURES[00m[90m[00m = "[90m[03m-control-hdr-padding[00m [90m[03m-dynamic-sl[00m [90m[03m-rdmacm[00m [90m[03m-udcm[00m"
             │          [90m          │ [00m[90m[00m[100mOPENMPI_RM[00m[90m[00m = "[33m-pbs[00m [33m-slurm[00m"

 └─[90m[00m[100mstep  4[00m[90m[00m─┤ [36mrun[32m       overlay://test63/openmpi-4.1.6-r1[00m

 └─[90m[00m[100mstep  5[00m[90m[00m─┤ [36minstall[32m   overlay://test63/mpibash-1.3-r1[00m

 └─[90m[00m[100mstep  6[00m[90m[00m─┤ [36mrun[32m       overlay://test63/mpibash-1.3-r1[00m

 └─[90m[00m[100mstep  7[00m[90m[00m─┤ [36minstall[32m   overlay://test63/app-1.0[00m

 └─[90m[00m[100mstep  8[00m[90m[00m─┤ [32m[00m[42mrun[00m[32m[00m[01m[32m     overlay://test63/app-1.0[00m[00m

Total: 10 actions (1 useflag, 3 downloads, 3 installs, 3 runs), grouped into 8 steps.
       0.00 Kb to be downloaded.


[93m>>> Assumptions taken during proving & planning:[00m

  USE flag change (1 package):
[00m[90m  Add to /etc/portage/package.use:
    test63/openmpi -openmpi_rm_pbs -openmpi_rm_slurm
[00m
```

</details>