# test77 — Unused package removal (VDB)

**Category:** Depclean

This test case checks the depclean action. When run with :depclean, the prover
should traverse the installed dependency graph starting from world targets and
identify packages that are not reachable. The 'orphan-1.0' package is installed
but nothing depends on it, making it a candidate for removal.

**Expected:** The depclean analysis should identify orphan-1.0 as removable since it has no
reverse dependencies in the installed package graph. app-1.0 and os-1.0 should
be retained.

![test77](test77.svg)

**Output:** [emerge -vp](emerge-test77.log) | [portage-ng](portage-ng-test77.log)