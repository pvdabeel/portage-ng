# test14 — Positive USE conditional lib? ( )

**Category:** USE cond

This test case evaluates the handling of USE conditional dependencies. The dependency on 'lib-1.0' is only active if the 'lib' USE flag is enabled for the 'app-1.0' package.

**Expected:** - If the user proves 'app-1.0' without enabling the 'lib' flag, the proof should succeed, and 'lib-1.0' should not be included in the dependency graph.
- If the user proves 'app-1.0' and enables the 'lib' flag (e.g., via configuration), the proof should succeed, and 'lib-1.0' should be correctly included and installed.

![test14](test14.svg)

**Output:** [emerge -vp](test14-emerge.log) | [portage-ng](test14-portage-ng.log)