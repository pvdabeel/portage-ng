# test21 — Any-of || (runtime)

**Category:** Choice

This is a variation of test20, with the 'any-of' dependency group in the runtime scope (RDEPEND).

**Expected:** The prover should handle the runtime choice group correctly, select one of the OS options, and generate a valid proof.

![test21](test21.svg)

**Output:** [emerge -vp](emerge-test21.log) | [portage-ng](portage-ng-test21.log)