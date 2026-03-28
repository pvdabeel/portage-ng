# test48 — Slot conflict (same slot, different versions)

**Category:** Conflict

This test case checks the prover's ability to detect a slotting conflict. The two main dependencies, 'libgraphics' and 'libphysics', require different versions of 'libmatrix' to be installed into the same slot ('1'). A package slot can only be occupied by one version at a time.

**Expected:** The prover should identify that the dependencies for 'app-1.0' lead to a request to install two different packages ('libmatrix-1.0' and 'libmatrix-1.1') into the same slot. This is an impossible condition, so the prover must fail to find a valid proof.

![test48](test48.svg)

**Output:** [emerge -vp](test48-emerge.log) | [portage-ng](test48-portage-ng.log)