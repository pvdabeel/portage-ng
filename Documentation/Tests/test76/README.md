# test76 — Installed with wrong USE, rebuild needed (VDB)

**Category:** Newuse

This test case checks the prover's newuse rebuild behavior. The installed os-1.0
was built without the 'linux' USE flag, but app-1.0 requires os[linux]. The prover
should detect that the installed version does not satisfy the incoming
build_with_use requirement and trigger a rebuild.

**Expected:** The prover should detect that os-1.0 needs to be rebuilt with USE="linux" enabled.
The plan should include a rebuild action for os-1.0.

![test76](test76.svg)

**Output:** [emerge -vp](emerge-test76.log) | [portage-ng](portage-ng-test76.log)