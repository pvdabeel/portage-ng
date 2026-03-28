# test42 — Wildcard slot :*

**Category:** Slot

This test case checks the prover's behavior with a wildcard slot dependency. 'app-1.0' requires 'lib', but it doesn't care which slot is used.

**Expected:** Given the choice between two valid slots, the prover should follow the default behavior of picking the latest version, which is 'lib-2.0' in slot "2". The proof should be valid.

![test42](test42.svg)

**Output:** [emerge -vp](test42-emerge.log) | [portage-ng](test42-portage-ng.log)