# test02 — Version selection (2.0 over 1.0)

**Category:** Basic

This test case checks that the prover selects the latest available version when
multiple versions exist and no version constraints are specified. All dependencies
are unversioned, so the prover should prefer version 2.0 over 1.0 for every
package.

**Expected:** The plan should contain only version 2.0 packages (os-2.0, db-2.0, app-2.0,
web-2.0). No version 1.0 packages should appear. If the proposed plan is not
accepted, the prover should backtrack over available versions, proposing
alternative plans.

![test02](test02.svg)

**Output:** [emerge -vp](test02-emerge.log) | [portage-ng](test02-portage-ng.log)