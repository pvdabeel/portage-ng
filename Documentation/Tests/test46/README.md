# test46 — Deep diamond USE conflict

**Category:** Conflict

This test case is designed to assess the prover's ability to detect a USE flag conflict that is hidden several layers deep in the dependency graph. The two main dependency branches ('liba' and 'libb') converge on 'core-utils' with contradictory requirements for the 'feature_x' USE flag.

**Expected:** The prover must trace the entire dependency tree and identify that 'core-utils' is required with both 'feature_x' enabled and disabled simultaneously. As this is a logical contradiction, the prover should fail to produce a valid installation proof.

![test46](test46.svg)

**Output:** [emerge -vp](test46-emerge.log) | [portage-ng](test46-portage-ng.log)