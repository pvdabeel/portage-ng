# test74 — Installed newer, constraint forces older (VDB)

**Category:** Downgrade

This test case checks the prover's downgrade path. When lib-2.0 is installed but
app-1.0 requires exactly lib-1.0 (via the = operator), the prover should detect
that a downgrade is needed. The same-slot installed version is newer than the
required version.

**Expected:** The prover should select lib-1.0 as a downgrade replacing the installed lib-2.0.
The plan should show a downgrade action for lib.

![test74](test74.svg)

**Output:** [emerge -vp](test74-emerge.log) | [portage-ng](test74-portage-ng.log)