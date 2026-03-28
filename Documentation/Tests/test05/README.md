# test05 — Self-dependency (compile + runtime)

**Category:** Cycle

This test case combines test03 and test04. The 'os-1.0' package lists itself as
both a compile-time and runtime dependency, creating two self-referential cycles.

**Expected:** The prover should take two cycle-break assumptions: one for the compile-time
self-dependency and one for the runtime self-dependency. Both should yield verify
steps in the proposed plan.

![test05](test05.svg)

**Output:** [emerge -vp](emerge-test05.log) | [portage-ng](portage-ng-test05.log)