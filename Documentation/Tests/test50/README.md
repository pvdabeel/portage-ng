# test50 — Compile dep's RDEPEND must appear

**Category:** Transitive

This test case examines the prover's handling of transitive dependencies, specifically how a runtime dependency of a compile-time dependency is treated. 'app-1.0' needs 'foo-1.0' to build. 'foo-1.0' itself needs 'bar-1.0' to run.

**Expected:** When proving for 'app-1.0', the prover should correctly identify that both 'foo-1.0' and 'bar-1.0' need to be installed. The proof should be valid, and the installation plan should include all three packages in the correct order (bar, foo, app).

![test50](test50.svg)

**Output:** [emerge -vp](test50-emerge.log) | [portage-ng](test50-portage-ng.log)