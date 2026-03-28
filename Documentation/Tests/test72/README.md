# test72 — Install-time dependency

**Category:** IDEPEND

This test case checks the prover's handling of IDEPEND (install-time dependencies).
IDEPEND is an EAPI 8 feature that specifies packages needed at install time on the
target system (as opposed to BDEPEND which is for the build system). The 'app-1.0'
package requires 'installer-1.0' at install time.

**Expected:** Both packages should appear in the proof. The installer-1.0 should be resolved as
an install-time dependency and be available before app-1.0's install phase.

![test72](test72.svg)

**Output:** [emerge -vp](emerge-test72.log) | [portage-ng](portage-ng-test72.log)