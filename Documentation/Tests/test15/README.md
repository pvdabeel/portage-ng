# test15 — Negative USE conditional !nolib? ( )

**Category:** USE cond

This test case is similar to test14 but uses a negative USE conditional. The dependency is triggered by the absence of a USE flag.

**Expected:** - If the 'nolib' flag is enabled for app-1.0, the proof should succeed without pulling in 'lib-1.0'.
- If the 'nolib' flag is not set (i.e., disabled by default), the proof should succeed and correctly include 'lib-1.0' as a dependency.

![test15](test15.svg)

**Output:** [emerge -vp](emerge-test15.log) | [portage-ng](portage-ng-test15.log)