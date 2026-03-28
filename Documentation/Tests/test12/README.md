# test12 — Stable vs unstable keyword acceptance

**Category:** Keywords

This test case examines the prover's handling of package keywords and stability. The latest (2.0) versions of the packages are marked as unstable. Without a specific configuration to accept these unstable keywords, the package manager should not select them.

**Expected:** Assuming a default configuration that only allows stable packages, the prover should reject the 2.0 versions and instead resolve the dependencies using the stable 1.0 versions. The final proof should be for app-1.0, db-1.0, and os-1.0.

![test12](test12.svg)

**Output:** [emerge -vp](test12-emerge.log) | [portage-ng](test12-portage-ng.log)