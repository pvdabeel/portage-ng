# test11 — Non-existent dep (compile + runtime)

**Category:** Missing

This test case combines test09 and test10. The 'os-1.0' package has both a compile-time and a runtime dependency on the non-existent 'test11/notexists' package.

**Expected:** The prover should fail because it cannot find the 'notexists' package. It should correctly identify the missing dependency in both scopes.

![test11](test11.svg)

**Output:** [emerge -vp](emerge-test11.log) | [portage-ng](portage-ng-test11.log)