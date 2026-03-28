# test51 — USE dep vs REQUIRED_USE contradiction

**Category:** Conflict

This test case presents a direct and unsolvable conflict between a dependency's USE requirement and the target package's REQUIRED_USE. 'app-1.0' needs 'os-1.0' with the 'linux' flag, but 'os-1.0' explicitly forbids that flag from being enabled.

**Expected:** The prover should immediately detect the contradiction between the USE dependency and the REQUIRED_USE constraint and fail to produce a valid proof.

![test51](test51.svg)

**Output:** [emerge -vp](test51-emerge.log) | [portage-ng](test51-portage-ng.log)