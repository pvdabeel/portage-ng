# test62 — Simple mutual cycle (termination)

**Category:** Cycle

This test case is a prover termination regression test for simple mutual dependency
cycles without blockers, slots, or USE flags. It checks whether per-goal context
growth (e.g. accumulating self() markers or slot information) can defeat cycle
detection and cause backtracking until timeout.

**Expected:** The prover should terminate quickly with a finite model/plan, or fail fast. It must
not spin or backtrack indefinitely. A cycle-break assumption is expected.

![test62](test62.svg)

**Output:** [emerge -vp](emerge-test62.log) | [portage-ng](portage-ng-test62.log)