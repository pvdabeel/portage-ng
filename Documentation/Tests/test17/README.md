# test17 — Exactly-one-of ^^ (compile)

**Category:** Choice

This test case evaluates the prover's handling of an 'exactly-one-of' dependency group (^^). The 'os-1.0' package requires that exactly one of the three OS packages be installed.

**Expected:** The prover should recognize the choice and select one of the available options (e.g., linux-1.0) to satisfy the dependency. Since there are no other constraints, any of the three choices should lead to a valid proof. The final plan will include app-1.0, os-1.0, and one of the three OS packages.

![test17](test17.svg)

**Output:** [emerge -vp](emerge-test17.log) | [portage-ng](portage-ng-test17.log)