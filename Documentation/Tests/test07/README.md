# test07 — Indirect cycle (runtime)

**Category:** Cycle

This test case is a variation of test06 where the indirect circular dependency is
in the runtime scope (RDEPEND). The 'os-1.0' package lists 'web-1.0' as a runtime
dependency, creating a two-node runtime cycle.

**Expected:** The prover should detect the cycle and take an assumption to break it, yielding a
verify step in the proposed plan.

![test07](test07.svg)

**Output:** [emerge -vp](emerge-test07.log) | [portage-ng](portage-ng-test07.log)