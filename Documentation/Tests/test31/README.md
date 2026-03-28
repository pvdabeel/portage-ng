# test31 — Weak blocker ! (compile+runtime) + any-of

**Category:** Blocker

This test case combines test27 and test30. The 'app-1.0' package has a weak
blocker (!) against 'windows-1.0' in both the compile-time (DEPEND) and runtime
(RDEPEND) scopes. The any-of group on 'os-1.0' still includes 'windows-1.0'.

**Expected:** The prover should produce a valid plan. The weak blockers are recorded as domain
assumptions. The any-of group resolution may or may not select 'windows-1.0',
depending on blocker handling strategy.

![test31](test31.svg)

**Output:** [emerge -vp](emerge-test31.log) | [portage-ng](portage-ng-test31.log)