# test27 — Weak blocker ! (runtime) + any-of

**Category:** Blocker

This test case checks the prover's handling of a weak blocker (!). The 'app-1.0'
package has a weak runtime blocker against 'windows-1.0'. Unlike the strong blocker
in test26, a weak blocker is advisory: it signals that 'windows-1.0' should be
uninstalled if already present, but does not absolutely forbid its co-existence.
The any-of group on 'os-1.0' still includes 'windows-1.0' as a candidate.

**Expected:** The prover should produce a valid plan. The weak blocker is recorded as a domain
assumption. The any-of group resolution may or may not select 'windows-1.0',
depending on blocker handling strategy.

![test27](test27.svg)

**Output:** [emerge -vp](emerge-test27.log) | [portage-ng](portage-ng-test27.log)