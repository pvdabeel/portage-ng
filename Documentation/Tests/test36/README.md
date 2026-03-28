# test36 — Chained equality [linux=] through lib

**Category:** USE dep

This test case examines the prover's ability to propagate a conditional USE flag requirement down a dependency chain. The USE="linux" setting on 'app-1.0' should flow down to 'lib-1.0', which in turn should flow down to 'os-1.0'.

**Expected:** If 'app-1.0' is proven with USE="linux", the prover should enforce USE="linux" on both 'lib-1.0' and 'os-1.0'. Conversely, if 'app-1.0' has USE="-linux", that requirement should also propagate down the chain. The proof should be valid in both scenarios.

![test36](test36.svg)

**Output:** [emerge -vp](test36-emerge.log) | [portage-ng](test36-portage-ng.log)