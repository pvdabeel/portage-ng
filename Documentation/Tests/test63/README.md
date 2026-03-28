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

**Output:** [emerge -vp](emerge-test63.log) | [portage-ng](portage-ng-test63.log)