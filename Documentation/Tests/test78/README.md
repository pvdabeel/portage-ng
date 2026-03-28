# test78 — Skip target, install deps only

**Category:** Onlydeps

This test case checks the --onlydeps behavior. When the entry point target
(web-1.0) is proven with the onlydeps_target context flag, the target package
itself should not appear in the install plan, but all of its dependencies should
still be resolved and included.

**Expected:** The dependencies (app-1.0, db-1.0, os-1.0) should appear in the proof and plan.
The target package web-1.0 should be excluded from the install actions, though it
may still appear in the proof for dependency traversal purposes.

![test78](test78.svg)

**Output:** [emerge -vp](test78-emerge.log) | [portage-ng](test78-portage-ng.log)