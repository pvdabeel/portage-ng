# test56 — Constraint intersection via dep chains

**Category:** Version

Multiple requirements should be combined. Only one version should be selected

**Expected:** The constraints on the lib versions should be combined. Only one version should be selected, since there is only one slot to fill.

![test56](test56.svg)

**Output:** [emerge -vp](test56-emerge.log) | [portage-ng](test56-portage-ng.log)