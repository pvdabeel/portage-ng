# test69 — Operator >= (greater-or-equal)

**Category:** Version

This test case checks the prover's handling of the >= (greater-or-equal) version
operator. The 'app-1.0' package requires lib version 3.0 or higher. Versions 1.0
and 2.0 should be excluded; versions 3.0, 4.0, and 5.0 are valid candidates.

**Expected:** The prover should select the latest valid version, lib-5.0, to satisfy the
dependency. Versions 1.0 and 2.0 should not appear in the proof.

![test69](test69.svg)

**Output:** [emerge -vp](test69-emerge.log) | [portage-ng](test69-portage-ng.log)