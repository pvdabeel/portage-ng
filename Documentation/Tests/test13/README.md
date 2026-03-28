# test13 — Pinpointed version =pkg-ver

**Category:** Version

This test case introduces a specific version constraint. The 'app-2.0' package explicitly requires 'db-2.0' (using the '=' operator), even though a 'db-1.0' is also available.

**Expected:** The prover must respect the version constraint. It should select 'db-2.0' and then proceed to resolve the rest of the dependencies, selecting the latest available versions for other packages like 'os-2.0'. The final proof should be for app-2.0, db-2.0, and os-2.0.

![test13](test13.svg)

**Output:** [emerge -vp](test13-emerge.log) | [portage-ng](test13-portage-ng.log)