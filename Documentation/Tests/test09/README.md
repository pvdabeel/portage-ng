# test09 — Non-existent dep (compile)

**Category:** Missing

This test case checks the prover's ability to handle a missing dependency. The 'os-1.0' package depends on 'test09/notexists', which is not a real package available in the repository.

**Expected:** The prover should fail to find a candidate for the 'notexists' package and report that the dependency cannot be satisfied. This should result in a failed proof.

![test09](test09.svg)

**Output:** [emerge -vp](emerge-test09.log) | [portage-ng](portage-ng-test09.log)