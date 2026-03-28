# test19 — Exactly-one-of ^^ (compile + runtime)

**Category:** Choice

This test case combines test17 and test18. The 'os-1.0' package has the same 'exactly-one-of' choice group in both its compile-time and runtime dependencies.

**Expected:** The prover should select a single OS package that satisfies both the compile-time and runtime requirements. For example, if it chooses 'linux-1.0' for the compile dependency, it must also use 'linux-1.0' for the runtime dependency. The proof should be valid.

![test19](test19.svg)

**Output:** [emerge -vp](emerge-test19.log) | [portage-ng](portage-ng-test19.log)