# test70 — Operator ~ (revision match)

**Category:** Version

This test case checks the prover's handling of the ~ (revision match) version
operator. The dependency ~lib-2.0 should match lib-2.0 and lib-2.0-r1 (any
revision of the 2.0 base version) but NOT lib-3.0 (different base version).

**Expected:** The prover should select lib-2.0-r1 (the latest matching revision of 2.0). 
lib-3.0 should not be considered a valid candidate for this dependency.

![test70](test70.svg)

**Output:** [emerge -vp](test70-emerge.log) | [portage-ng](test70-portage-ng.log)