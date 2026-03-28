# test18 — Exactly-one-of ^^ (runtime)

**Category:** Choice

This test case is a variation of test17, but the 'exactly-one-of' dependency is in the runtime scope (RDEPEND).

**Expected:** The prover should handle the runtime choice group correctly, select one of the OS options, and generate a valid proof.

![test18](test18.svg)

**Output:** [emerge -vp](test18-emerge.log) | [portage-ng](test18-portage-ng.log)