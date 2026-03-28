# test49 — USE default (+) vs REQUIRED_USE

**Category:** Conflict

This test case checks the prover's ability to handle a conflict between a "soft" USE flag suggestion from a dependency and a "hard" REQUIRED_USE constraint in the target package. The `(+)` syntax is a default and should be overridden by the stricter `REQUIRED_USE`.

**Expected:** The prover should recognize that the dependency from 'app-1.0' attempts to enable a USE flag that is explicitly forbidden by 'libhelper-1.0'. The hard constraint of REQUIRED_USE must take precedence, leading to an unresolvable conflict. The prover should fail to find a valid proof.

![test49](test49.svg)

**Output:** [emerge -vp](test49-emerge.log) | [portage-ng](test49-portage-ng.log)