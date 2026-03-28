# test79 — PDEPEND cycle (A needs B, B PDEPEND A)

**Category:** PDEPEND

This test case checks the handling of cycles involving PDEPEND. The server needs
the client at runtime, and the client has a PDEPEND back on the server. Since
PDEPEND is resolved post-install (via proof obligations), this cycle should be
naturally broken by the ordering: server installs first, then client, then the
PDEPEND obligation for server is already satisfied.

**Expected:** Both packages should appear in the proof without infinite loops. The PDEPEND cycle
should be handled gracefully by the proof obligation mechanism, not treated as a
hard circular dependency requiring assumptions.

![test79](test79.svg)

**Output:** [emerge -vp](emerge-test79.log) | [portage-ng](portage-ng-test79.log)