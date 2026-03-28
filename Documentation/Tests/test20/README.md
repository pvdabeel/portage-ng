# test20 — Any-of || (compile)

**Category:** Choice

This test case evaluates the prover's handling of an 'any-of' dependency group (||). The 'os-1.0' package requires that at least one of the three OS packages be installed.

**Expected:** The prover should recognize the choice and select one of the available options to satisfy the dependency. Since there are no other constraints, any of the three choices should lead to a valid proof.

![test20](test20.svg)

**Output:** [emerge -vp](emerge-test20.log) | [portage-ng](portage-ng-test20.log)