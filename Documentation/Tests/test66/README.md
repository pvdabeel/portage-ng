# test66 — Post-merge dependency resolution

**Category:** PDEPEND

This test case checks the prover's handling of PDEPEND (post-merge dependencies).
The 'lib-1.0' package declares 'plugin-1.0' as a PDEPEND, meaning plugin-1.0
should be resolved after lib-1.0's installation, not as a prerequisite.

**Expected:** All three packages should appear in the proof/plan. The plugin-1.0 package should
be ordered after lib-1.0's install step via the PDEPEND proof obligation mechanism.

![test66](test66.svg)

**Output:** [emerge -vp](test66-emerge.log) | [portage-ng](test66-portage-ng.log)