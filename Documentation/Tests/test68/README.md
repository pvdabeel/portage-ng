# test68 — Co-installation of same CN in different slots

**Category:** Multi-slot

This test case checks the prover's ability to resolve dependencies on multiple
slots of the same package simultaneously. The 'app-1.0' package requires both
slot 1 and slot 2 of 'lib', which correspond to different versions. Both must
appear in the plan since different slots can coexist.

**Expected:** Both lib-1.0 (slot 1) and lib-2.0 (slot 2) should appear in the proof. The prover
should recognize that different slots are independent installation targets and
include both in the plan.

![test68](test68.svg)

**Output:** [emerge -vp](emerge-test68.log) | [portage-ng](portage-ng-test68.log)