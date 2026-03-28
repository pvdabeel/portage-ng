# test22 — Any-of || (compile + runtime)

**Category:** Choice

This test case combines test20 and test21. The 'os-1.0' package has the same 'any-of' choice group in both its compile-time and runtime dependencies.

**Expected:** The prover can choose any of the OS packages to satisfy the compile-time dependency and any of the OS packages to satisfy the runtime dependency. They do not have to be the same. The proof should be valid.

![test22](test22.svg)

**Output:** [emerge -vp](test22-emerge.log) | [portage-ng](test22-portage-ng.log)