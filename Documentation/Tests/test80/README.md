# test80 — Operator <= (less-or-equal)

**Category:** Version

This test case checks the prover's handling of the <= (less-or-equal) version
operator. The 'app-1.0' package requires lib version 3.0 or lower. Versions 4.0
and 5.0 should be excluded; versions 1.0, 2.0, and 3.0 are valid candidates.

**Expected:** The prover should select the latest valid version, lib-3.0, to satisfy the
dependency. Versions 4.0 and 5.0 should not be considered valid candidates.

![test80](test80.svg)

**Output:** [emerge -vp](emerge-test80.log) | [portage-ng](portage-ng-test80.log)