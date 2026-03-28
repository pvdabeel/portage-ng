# test73 — Installed old version, newer available (VDB)

**Category:** Update

This test case checks the prover's update path. When lib-1.0 is already installed
and lib-2.0 is available, the prover should detect that an update is possible and
trigger the :update action instead of :install. This requires VDB simulation to
mark lib-1.0 as installed.

**Expected:** The prover should select lib-2.0 as an update replacing the installed lib-1.0. The
plan should show an update action for lib, not a fresh install.

![test73](test73.svg)

**Output:** [emerge -vp](test73-emerge.log) | [portage-ng](test73-portage-ng.log)