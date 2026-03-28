# test33 — Positive [linux]

**Category:** USE dep

This test case examines a direct USE dependency. The 'app-1.0' package requires that 'os-1.0' be built with the 'linux' USE flag enabled.

**Expected:** The prover should identify the USE requirement and enable the 'linux' flag for 'os-1.0' when resolving its dependencies. The final proof should be valid and show that 'os-1.0' is built with USE="linux".

![test33](test33.svg)

**Output:** [emerge -vp](test33-emerge.log) | [portage-ng](test33-portage-ng.log)