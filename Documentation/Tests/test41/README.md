# test41 — Explicit slot :1

**Category:** Slot

This test case checks the prover's ability to resolve dependencies based on slotting. 'app-1.0' requires a version of 'lib' that is in slot "1". Even though 'lib-2.0' is a higher version, it is in a different slot and therefore not a candidate.

**Expected:** The prover should correctly select 'lib-1.0' to satisfy the slot dependency, ignoring the newer 'lib-2.0'. The proof should be valid.

![test41](test41.svg)

**Output:** [emerge -vp](test41-emerge.log) | [portage-ng](test41-portage-ng.log)