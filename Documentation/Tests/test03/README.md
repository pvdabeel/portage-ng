# test03 — Self-dependency (compile)

**Category:** Cycle

This test case checks the prover's handling of a direct self-dependency in the
compile-time scope. The 'os-1.0' package lists itself as a compile-time dependency,
creating an immediate cycle. The prover must detect this cycle and take an
assumption to break it.

**Expected:** The prover should take a cycle-break assumption for os-1.0's compile dependency on
itself, yielding a verify step in the proposed plan. The plan should still include
all four packages.

![test03](test03.svg)

**Output:** [emerge -vp](test03-emerge.log) | [portage-ng](test03-portage-ng.log)