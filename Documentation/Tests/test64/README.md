# test64 — USE-conditional churn reproducer (openmp-style)

**Category:** Cycle

This test case reproduces the small backtracking/churn pattern observed for
llvm-runtimes/openmp in a tiny overlay-only setup. The real openmp metadata
includes IUSE flags, USE-gated dependencies, and REQUIRED_USE groups that can
cause excessive proof retries.

**Expected:** The prover should complete without timing out. A valid plan should be produced that
respects all REQUIRED_USE constraints and USE-conditional dependencies.

![test64](test64.svg)

**Output:** [emerge -vp](emerge-test64.log) | [portage-ng](portage-ng-test64.log)