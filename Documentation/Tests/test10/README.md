# test10 — Non-existent dep (runtime)

**Category:** Missing

This is a variation of test09. It checks for a missing dependency, but this time in the runtime (RDEPEND) scope. The 'os-1.0' package requires 'test10/notexists' to run.

**Expected:** The prover should fail to find the 'notexists' package and report the missing runtime dependency, leading to a failed proof.

![test10](test10.svg)

**Output:** [emerge -vp](emerge-test10.log) | [portage-ng](portage-ng-test10.log)