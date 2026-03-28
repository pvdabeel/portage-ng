# test43 — Slot equality :=

**Category:** Slot

This test case examines the slot equality operator (:=). 'app-1.0' depends on 'lib' at compile time. The prover will choose the latest version, 'lib-2.0'. The runtime dependency then requires that the same slot ('2') be used.

**Expected:** The prover should first resolve the compile dependency to 'lib-2.0'. Then, when resolving the runtime dependency, it must choose a package from the same slot, which is 'lib-2.0'. The proof should be valid.

![test43](test43.svg)

**Output:** [emerge -vp](emerge-test43.log) | [portage-ng](portage-ng-test43.log)