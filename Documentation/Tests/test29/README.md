# test29 — Strong blocker !! (compile+runtime) + any-of

**Category:** Blocker

This test case combines test26 and test28. The 'app-1.0' package has a strong
blocker (!!) against 'windows-1.0' in both the compile-time (DEPEND) and runtime
(RDEPEND) scopes. The any-of group on 'os-1.0' still includes 'windows-1.0'.

**Expected:** The prover should produce a valid plan that avoids 'windows-1.0'. It should select
either 'linux-1.0' or 'bsd-1.0' for the any-of group, since 'windows-1.0' is
strongly blocked in both scopes.

![test29](test29.svg)

**Output:** [emerge -vp](emerge-test29.log) | [portage-ng](portage-ng-test29.log)