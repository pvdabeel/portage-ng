# test45 — Irreconcilable USE conflict via ^^

**Category:** Conflict

This test case checks the prover's ability to detect a direct and irreconcilable USE flag conflict. The 'os' package has a REQUIRED_USE constraint of "^^ ( linux darwin )", meaning exactly one of those USE flags must be enabled. However, the dependency graph requires both to be enabled simultaneously to satisfy liba and libb.

**Expected:** The prover should correctly identify the conflict and fail to produce a valid installation proof. There is no possible configuration of USE flags that can satisfy these dependencies.

![test45](test45.svg)

**Output:** [emerge -vp](test45-emerge.log) | [portage-ng](test45-portage-ng.log)