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
<summary><b>emerge</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  ... done!
Dependency resolution took 0.48 s (backtrack: 0/20).


!!! The ebuild selected to satisfy "test63/openmpi" has unmet requirements.
- test63/openmpi-4.1.6-r1::overlay USE="" OPENMPI_FABRICS="-ofed" OPENMPI_OFED_FEATURES="-control-hdr-padding -dynamic-sl -rdmacm -udcm" OPENMPI_RM="pbs slurm"

  The following REQUIRED_USE flag constraints are unsatisfied:
    openmpi_rm_slurm? ( !openmpi_rm_pbs ) openmpi_rm_pbs? ( !openmpi_rm_slurm )

  The above constraints are a subset of the following complete expression:
    openmpi_rm_slurm? ( !openmpi_rm_pbs ) openmpi_rm_pbs? ( !openmpi_rm_slurm ) openmpi_ofed_features_control-hdr-padding? ( openmpi_fabrics_ofed ) openmpi_ofed_features_udcm? ( openmpi_fabrics_ofed ) openmpi_ofed_features_rdmacm? ( openmpi_fabrics_ofed ) openmpi_ofed_features_dynamic-sl? ( openmpi_fabrics_ofed )

(dependency required by "test63/mpibash-1.3-r1::overlay" [ebuild])
(dependency required by "test63/app-1.0::overlay" [ebuild])
(dependency required by "test63/app" [argument])
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```

>>> Emerging : overlay://test63/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ useflag overlay://test63/openmpi-4.1.6-r1 (-openmpi_rm_pbs -openmpi_rm_slurm)

 └─step  2─┤ download  overlay://test63/openmpi-4.1.6-r1
             │ download  overlay://test63/mpibash-1.3-r1
             │ download  overlay://test63/app-1.0

 └─step  3─┤ install   overlay://test63/openmpi-4.1.6-r1 (USE modified)
             │           └─ conf ─┤ USE = ""
             │                    │ OPENMPI_FABRICS = "-ofed"
             │                    │ OPENMPI_OFED_FEATURES = "-control-hdr-padding -dynamic-sl -rdmacm -udcm"
             │                    │ OPENMPI_RM = "-pbs -slurm"

 └─step  4─┤ run       overlay://test63/openmpi-4.1.6-r1

 └─step  5─┤ install   overlay://test63/mpibash-1.3-r1

 └─step  6─┤ run       overlay://test63/mpibash-1.3-r1

 └─step  7─┤ install   overlay://test63/app-1.0

 └─step  8─┤ run     overlay://test63/app-1.0

Total: 10 actions (1 useflag, 3 downloads, 3 installs, 3 runs), grouped into 8 steps.
       0.00 Kb to be downloaded.


>>> Assumptions taken during proving & planning:

  USE flag change (1 package):
  Add to /etc/portage/package.use:
    test63/openmpi -openmpi_rm_pbs -openmpi_rm_slurm
```

</details>