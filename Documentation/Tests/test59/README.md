# test59 — Any-of || selection regression (XFAIL)

**Category:** Regression

> **XFAIL** — expected to fail.

This is an XFAIL regression test for a known bug where the any-of group (||) does
not force the solver to select at least one alternative. Structurally similar to
test21 (any-of in RDEPEND), but this test uses different package names and exists
specifically to track the regression where any-of members can all be dropped from
the model.

**Expected:** Currently expected to fail (XFAIL): the solver does not force selecting one
alternative from the any-of group. When the bug is fixed, the model should contain
either data_fast-1.0 or data_best-1.0.

![test59](test59.svg)

**Output:** [emerge -vp](test59-emerge.log) | [portage-ng](test59-portage-ng.log)