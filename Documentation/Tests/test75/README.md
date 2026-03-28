# test75 — Installed same version, emptytree (VDB)

**Category:** Reinstall

This test case checks the prover's behavior when the --emptytree flag is active.
Even though os-1.0 is already installed, the emptytree flag should force the
prover to re-prove it rather than skipping it as satisfied. This exercises the
reinstall path.

**Expected:** With emptytree behavior, os-1.0 should appear in the proof despite being installed.
The plan should include a reinstall or fresh install action for os-1.0.

![test75](test75.svg)

**Output:** [emerge -vp](emerge-test75.log) | [portage-ng](portage-ng-test75.log)