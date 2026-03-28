# test71 — Download-only action

**Category:** Fetchonly

This test case checks the prover's handling of the fetchonly action. The dependency
structure is identical to test01, but the entry point uses :fetchonly instead of
:run. In fetchonly mode, only download actions should be produced, with no
install/run steps.

**Expected:** All four packages should appear in the proof with download/fetchonly actions. No
install or run steps should be produced in the plan.

![test71](test71.svg)

**Output:** [emerge -vp](test71-emerge.log) | [portage-ng](test71-portage-ng.log)