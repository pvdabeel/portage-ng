# test34 — Negative [-linux]

**Category:** USE dep

This test case is the inverse of test33. It checks the handling of a negative USE dependency. The 'app-1.0' package requires that 'os-1.0' be built with the 'linux' USE flag disabled.

**Expected:** The prover must ensure the 'linux' flag is disabled for 'os-1.0'. The proof should be valid, showing that 'os-1.0' is built with USE="-linux".

![test34](test34.svg)

**Output:** [emerge -vp](test34-emerge.log) | [portage-ng](test34-portage-ng.log)