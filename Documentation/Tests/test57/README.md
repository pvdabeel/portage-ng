# test57 — Virtual-style ebuild (explicit dep)

**Category:** Virtual

This test case validates that dependencies of a virtual-style ebuild are traversed
and that its provider package is included in the proof/model. The 'virtualsdk-1.0'
ebuild acts as a virtual by depending on 'linux-1.0' as its concrete provider.

**Expected:** When proving web-1.0, the plan/model should include linux-1.0 (via
virtualsdk-1.0). The full chain os -> virtualsdk -> linux should be resolved.

![test57](test57.svg)

**Output:** [emerge -vp](emerge-test57.log) | [portage-ng](portage-ng-test57.log)