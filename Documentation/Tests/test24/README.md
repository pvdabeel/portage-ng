# test24 — At-most-one-of ?? (runtime)

**Category:** Choice

This is a variation of test23, with the 'at-most-one-of' dependency group in the runtime scope (RDEPEND).

**Expected:** The prover should satisfy the runtime dependency by choosing to install none of the optional OS packages. The proof should be valid.

![test24](test24.svg)

**Output:** [emerge -vp](emerge-test24.log) | [portage-ng](portage-ng-test24.log)