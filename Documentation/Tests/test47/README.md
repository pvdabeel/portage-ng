# test47 — Three-way dependency cycle

**Category:** Cycle

This test case presents a more complex, three-way circular dependency. The client needs the docs to build, the docs need the server to run, and the server needs the client to run. This creates a loop that cannot be resolved.

**Expected:** The prover should be able to trace the dependency chain through all three packages and identify the circular dependency, causing the proof to fail.

![test47](test47.svg)

**Output:** [emerge -vp](test47-emerge.log) | [portage-ng](test47-portage-ng.log)